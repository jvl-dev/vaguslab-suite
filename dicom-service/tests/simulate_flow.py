"""
DICOM Service Flow Simulator

Simulates the full detection flow without needing PowerScribe or InteleViewer:

  1. Opens a fake "InteleViewer" window (tkinter) so the window monitor is satisfied
  2. Writes a PSOnePerf.log entry with a chosen accession number
  3. Watches current_study.json for the detection result

Usage (from project root):

    python-embedded\python.exe dicom-service\tests\simulate_flow.py

Commands while running:
    study <accession>   — Write accession to PSOnePerf.log (e.g. "study RH-28122146-CT")
    close               — Close the fake patient window (triggers state clear)
    open <NAME^PARTS>   — Re-open window with a patient name
    status              — Print current_study.json contents
    quit                — Exit

The simulator auto-detects available DICOM files in the cache and shows their
accession numbers so you know what to type.
"""

import json
import os
import sys
import threading
import time
import tkinter as tk

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SERVICE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(SERVICE_DIR, "data")
STATE_FILE = os.path.join(DATA_DIR, "current_study.json")

PSONE_LOG_DIR = os.path.join(
    os.environ.get("USERPROFILE", ""),
    "AppData", "Local", "Nuance", "PowerScribeOne", "Logs", "Perf",
)
PSONE_LOG_FILE = os.path.join(PSONE_LOG_DIR, "PSOnePerf.log")

# Add project root so we can import pydicom from embedded Python's packages
sys.path.insert(0, SERVICE_DIR)


def _scan_cache_accessions(cache_dir, max_folders=10):
    """Scan the DICOM cache and return a list of (accession, patient_name, folder) tuples."""
    try:
        import pydicom
    except ImportError:
        return []

    results = []
    if not os.path.isdir(cache_dir):
        return results

    # Walk up to max_folders top-level directories
    folders = []
    for name in os.listdir(cache_dir):
        full = os.path.join(cache_dir, name)
        if os.path.isdir(full):
            folders.append(full)

    for folder in folders[:max_folders]:
        for root, _dirs, files in os.walk(folder):
            for fname in files:
                if not fname.endswith(".dcm"):
                    continue
                path = os.path.join(root, fname)
                try:
                    if os.path.getsize(path) < 1024:
                        continue
                    ds = pydicom.dcmread(path, stop_before_pixels=True, force=True)
                    acc = str(getattr(ds, "AccessionNumber", "")).strip()
                    name = str(getattr(ds, "PatientName", "")).strip()
                    mod = str(getattr(ds, "Modality", "")).strip()
                    if acc and acc != "N/A":
                        results.append((acc, name, mod))
                        break  # one per top-level folder
                except Exception:
                    continue
            if results and results[-1][2]:  # found one in this folder
                break

    # Deduplicate by accession
    seen = set()
    unique = []
    for acc, name, mod in results:
        if acc not in seen:
            seen.add(acc)
            unique.append((acc, name, mod))
    return unique


def _read_config_cache_dir():
    """Read the DICOM cache directory from config.ini."""
    import configparser
    config_file = os.path.join(SERVICE_DIR, "config.ini")
    cp = configparser.ConfigParser()
    cp.read(config_file, encoding="utf-8")
    return cp.get("service", "dicom_cache_directory",
                   fallback=r"C:\Intelerad\InteleViewerDicom")


# ---------------------------------------------------------------------------
# Fake InteleViewer window (tkinter)
# ---------------------------------------------------------------------------

class FakePatientWindow:
    """A minimal tkinter window whose title matches InteleViewer's pattern."""

    def __init__(self):
        self._root = None
        self._thread = None
        self._title = ""
        self._running = False

    def open(self, patient_name="TEST^PATIENT"):
        if self._running:
            self.close()
        self._title = f"{patient_name} - Simulated Study - Fake InteleViewer"
        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        time.sleep(0.5)  # let window appear

    def close(self):
        if self._root and self._running:
            self._root.after(0, self._root.destroy)
            self._running = False
            if self._thread:
                self._thread.join(timeout=2)
            self._root = None

    def _run(self):
        self._root = tk.Tk()
        self._root.title(self._title)
        self._root.geometry("400x80")
        label = tk.Label(self._root, text=f"Simulating: {self._title}",
                         wraplength=380)
        label.pack(expand=True, padx=10, pady=10)
        self._root.protocol("WM_DELETE_CLOSE", lambda: None)  # ignore X button
        try:
            self._root.mainloop()
        except Exception:
            pass
        self._running = False


# ---------------------------------------------------------------------------
# PSOnePerf.log writer
# ---------------------------------------------------------------------------

def write_psone_entry(accession):
    """Append a SingleAccession entry to PSOnePerf.log."""
    os.makedirs(PSONE_LOG_DIR, exist_ok=True)
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{timestamp} QuickSearchByAccession SingleAccession {accession}\n"
    with open(PSONE_LOG_FILE, "a", encoding="utf-8") as fh:
        fh.write(line)
    print(f"  -> Wrote to PSOnePerf.log: SingleAccession {accession}")


# ---------------------------------------------------------------------------
# State file watcher
# ---------------------------------------------------------------------------

def read_state():
    """Read and return current_study.json contents."""
    if not os.path.isfile(STATE_FILE):
        return {}
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    except (json.JSONDecodeError, OSError):
        return {}


def watch_state(stop_event, interval=0.5):
    """Background thread that prints when current_study.json changes."""
    last = None
    while not stop_event.is_set():
        current = read_state()
        if current != last:
            if current:
                print(f"\n  ** DETECTION: current_study.json updated:")
                for k, v in current.items():
                    print(f"     {k}: {v}")
            else:
                print(f"\n  ** State cleared (current_study.json is empty)")
            last = current
            print("\n> ", end="", flush=True)
        stop_event.wait(interval)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("  DICOM Service Flow Simulator")
    print("=" * 60)
    print()

    # Check if service is running
    lock_file = os.path.join(DATA_DIR, "service.lock")
    if os.path.isfile(lock_file):
        try:
            with open(lock_file) as fh:
                pid = int(fh.read().strip())
            print(f"  Service lock file found (PID {pid})")
        except (ValueError, OSError):
            print("  WARNING: Lock file exists but is unreadable")
    else:
        print("  WARNING: No service.lock found — is the service running?")
        print("  Start it with: python-embedded\\python.exe dicom-service\\dicom_service.py")
        print()

    # Show available DICOM accessions
    cache_dir = _read_config_cache_dir()
    print(f"  DICOM cache: {cache_dir}")
    print(f"  Scanning for available studies...")
    studies = _scan_cache_accessions(cache_dir)
    if studies:
        print(f"  Found {len(studies)} study/studies in cache:")
        for acc, name, mod in studies:
            print(f"    {acc}  ({name}, {mod})")
    else:
        print("  No DICOM files found in cache.")
    print()

    # PSOnePerf.log status
    print(f"  PSOnePerf.log dir: {PSONE_LOG_DIR}")
    if os.path.isdir(PSONE_LOG_DIR):
        print(f"  PSOnePerf.log exists: {os.path.isfile(PSONE_LOG_FILE)}")
    else:
        print(f"  Directory will be created on first 'study' command")
    print()

    # Current state
    state = read_state()
    if state:
        print(f"  Current state: {json.dumps(state)}")
    else:
        print(f"  Current state: (empty)")
    print()

    print("Commands:")
    print("  study <accession>   — Write accession to PSOnePerf.log")
    print("  open <NAME^PARTS>   — Open fake InteleViewer window")
    print("  close               — Close fake window (triggers state clear)")
    print("  status              — Show current_study.json")
    print("  quit                — Exit")
    print()

    # Start state watcher
    stop_event = threading.Event()
    watcher = threading.Thread(target=watch_state, args=(stop_event,), daemon=True)
    watcher.start()

    # Fake window
    window = FakePatientWindow()

    # If we found a study, suggest a default patient name
    default_name = studies[0][1] if studies else "TEST^PATIENT"

    try:
        while True:
            try:
                cmd = input("> ").strip()
            except EOFError:
                break

            if not cmd:
                continue

            parts = cmd.split(None, 1)
            verb = parts[0].lower()
            arg = parts[1] if len(parts) > 1 else ""

            if verb == "quit" or verb == "exit":
                break

            elif verb == "study":
                if not arg:
                    if studies:
                        arg = studies[0][0]
                        print(f"  Using default: {arg}")
                    else:
                        print("  Usage: study <accession>")
                        continue
                if not window._running:
                    print("  WARNING: No patient window open — service will ignore this.")
                    print("  Run 'open' first.")
                write_psone_entry(arg)

            elif verb == "open":
                name = arg if arg else default_name
                window.open(name)
                print(f"  Opened fake window: {name}")

            elif verb == "close":
                window.close()
                print("  Closed fake window")

            elif verb == "status":
                state = read_state()
                if state:
                    print(f"  {json.dumps(state, indent=2)}")
                else:
                    print("  (empty)")

            elif verb == "help":
                print("  study <acc>  — Write to PSOnePerf.log")
                print("  open [name]  — Open fake window")
                print("  close        — Close fake window")
                print("  status       — Show current_study.json")
                print("  quit         — Exit")

            else:
                print(f"  Unknown command: {verb} (try 'help')")

    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
        window.close()
        print("\nSimulator exited.")


if __name__ == "__main__":
    main()
