"""
DICOM Service — shared background process for DICOM monitoring.

Runs as a standalone process that survives app restarts.  Writes
``data/current_study.json`` for consumers (report-check, etc.).

Usage::

    python dicom_service.py [--cache-dir <path>]

"""

import argparse
import atexit
import configparser
import logging
import os
import signal
import sys
import time
from logging.handlers import RotatingFileHandler

# Embedded Python's ._pth file suppresses the normal addition of the script
# directory to sys.path.  Ensure our own directory is importable so that
# sibling modules (dicom_monitor, window_monitor) can be found.
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
if _THIS_DIR not in sys.path:
    sys.path.insert(0, _THIS_DIR)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SERVICE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SERVICE_DIR, "data")
LOGS_DIR = os.path.join(SERVICE_DIR, "logs")
LOCK_FILE = os.path.join(DATA_DIR, "service.lock")
CONFIG_FILE = os.path.join(SERVICE_DIR, "config.ini")

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

def _setup_logging():
    os.makedirs(LOGS_DIR, exist_ok=True)
    handler = RotatingFileHandler(
        os.path.join(LOGS_DIR, "dicom-service.log"),
        maxBytes=2 * 1024 * 1024,
        backupCount=3,
        encoding="utf-8",
    )
    handler.setFormatter(logging.Formatter(
        "%(asctime)s  %(levelname)-7s  %(name)s  %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    ))
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    root.addHandler(handler)

# ---------------------------------------------------------------------------
# PID lock
# ---------------------------------------------------------------------------

def _pid_exists(pid):
    """Check whether *pid* is alive.  Works correctly on Windows."""
    if sys.platform == "win32":
        import ctypes
        kernel32 = ctypes.windll.kernel32
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if handle:
            kernel32.CloseHandle(handle)
            return True
        return False
    else:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False


def _acquire_lock():
    """Write our PID to the lock file.  Exit if another instance is running."""
    os.makedirs(DATA_DIR, exist_ok=True)

    if os.path.isfile(LOCK_FILE):
        try:
            with open(LOCK_FILE) as fh:
                old_pid = int(fh.read().strip())
            if _pid_exists(old_pid):
                # Process exists — another instance is running
                print(f"Service already running (PID {old_pid}). Exiting.",
                      file=sys.stderr)
                sys.exit(0)
            else:
                logging.getLogger(__name__).info(
                    "Stale lock detected (PID %d gone, cleaning up)", old_pid)
        except (ValueError, OSError):
            # Corrupt lock file
            logging.getLogger(__name__).info(
                "Stale lock detected (cleaning up)")

    with open(LOCK_FILE, "w") as fh:
        fh.write(str(os.getpid()))


def _release_lock():
    try:
        os.unlink(LOCK_FILE)
    except OSError:
        pass

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def _read_config(cache_dir_override=None):
    """Return a dict of service settings from config.ini + CLI overrides."""
    cp = configparser.ConfigParser()
    cp.read(CONFIG_FILE, encoding="utf-8")

    cfg = {
        "timer_interval": cp.getfloat("service", "timer_interval", fallback=2.0),
        "dicom_cache_directory": cp.get(
            "service", "dicom_cache_directory",
            fallback=r"C:\Intelerad\InteleViewerDicom"),
        "search_timeout": cp.getint("service", "search_timeout", fallback=120),
        "cache_size": cp.getint("service", "cache_size", fallback=5),
        "max_scan_folders": cp.getint("service", "max_scan_folders", fallback=50),
        "perf_log_path": cp.get("service", "perf_log_path", fallback=""),
    }

    if cache_dir_override:
        cfg["dicom_cache_directory"] = cache_dir_override

    return cfg

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="DICOM monitoring service")
    parser.add_argument("--cache-dir", default=None,
                        help="Override DICOM cache directory")
    args = parser.parse_args()

    _setup_logging()
    log = logging.getLogger("dicom_service")

    _acquire_lock()
    atexit.register(_release_lock)

    cfg = _read_config(cache_dir_override=args.cache_dir)
    log.info("Service starting (PID %d)", os.getpid())
    log.info("Config: %s", cfg)

    # Late imports so logging is ready
    from dicom_monitor import DicomMonitor, PSOnePerfHandler
    from window_monitor import WindowMonitor

    monitor = DicomMonitor(
        cache_dir=cfg["dicom_cache_directory"],
        data_dir=DATA_DIR,
        search_timeout=cfg["search_timeout"],
        cache_size=cfg["cache_size"],
        max_scan_folders=cfg["max_scan_folders"],
        perf_log_path=cfg.get("perf_log_path", ""),
    )

    win_mon = WindowMonitor()
    monitor.window_monitor = win_mon

    # watchdog: watch the PSOnePerf.log directory
    observer = None
    psone_log_dir = _psone_log_dir(cfg.get("perf_log_path", ""))
    if psone_log_dir and os.path.isdir(psone_log_dir):
        from watchdog.observers import Observer
        observer = Observer()
        observer.schedule(PSOnePerfHandler(monitor), psone_log_dir, recursive=False)
        observer.daemon = True
        observer.start()
        log.info("Watching %s for PSOnePerf.log changes", psone_log_dir)
    else:
        log.warning("PSOnePerf.log directory not found: %s — falling back to polling",
                    psone_log_dir)

    # Graceful shutdown
    running = True

    def _shutdown(signum=None, frame=None):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    # Heartbeat: report-check writes a timestamp to data/heartbeat every
    # 10 s.  If the file goes stale (>30 s), the host app is gone and we
    # should exit so file locks on the embedded Python runtime are released.
    HEARTBEAT_FILE = os.path.join(DATA_DIR, "heartbeat")
    HEARTBEAT_STALE_SECS = 30
    heartbeat_missing_since = None

    def _check_heartbeat():
        nonlocal running, heartbeat_missing_since
        try:
            mtime = os.path.getmtime(HEARTBEAT_FILE)
            age = time.time() - mtime
            if age > HEARTBEAT_STALE_SECS:
                if heartbeat_missing_since is None:
                    heartbeat_missing_since = time.monotonic()
                elif time.monotonic() - heartbeat_missing_since > HEARTBEAT_STALE_SECS:
                    log.info("Heartbeat stale (%.0f s) — host app gone, shutting down", age)
                    running = False
            else:
                heartbeat_missing_since = None
        except FileNotFoundError:
            # No heartbeat file yet — give the host app time to create it.
            # Only shut down if we've been waiting a long time (2 minutes).
            if heartbeat_missing_since is None:
                heartbeat_missing_since = time.monotonic()
            elif time.monotonic() - heartbeat_missing_since > 120:
                log.info("No heartbeat file after 120 s — shutting down")
                running = False
        except OSError:
            pass

    log.info("Entering main loop (interval=%.1f s)", cfg["timer_interval"])

    try:
        while running:
            try:
                # Window safety (polling — no filesystem event to hook)
                win_mon.check_patient_safety(monitor)

                # Fallback PSOne check (in case watchdog missed an event)
                monitor.on_psone_log_changed()

                # Continue any active DICOM search
                monitor.continue_search()

                # Shut down if the host app (report-check) is gone
                _check_heartbeat()
            except Exception:
                log.exception("Error in main loop tick")

            time.sleep(cfg["timer_interval"])
    finally:
        if observer is not None:
            observer.stop()
            observer.join(timeout=2)
        monitor.reset_state("shutdown")
        log.info("Service stopped")


def _psone_log_dir(perf_log_path=""):
    """Return the directory containing PSOnePerf.log.

    If *perf_log_path* is set (from config.ini), derive the directory from
    that explicit path.  Otherwise fall back to the default %USERPROFILE%
    derivation.
    """
    if perf_log_path:
        return os.path.dirname(perf_log_path)
    profile = os.environ.get("USERPROFILE", "")
    if not profile:
        return ""
    return os.path.join(
        profile, "AppData", "Local", "Nuance", "PowerScribeOne",
        "Logs", "Perf",
    )


if __name__ == "__main__":
    main()
