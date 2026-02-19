"""
PSOnePerf.log Simulator — writes accession entries to trigger the DICOM service.

Use this on machines without PowerScribe to test the detection flow.
Open a study in InteleViewer first, then type the accession here.

Usage:
    python test_simulator.py [accession]

Interactive mode (no args):  prompts for accessions
One-shot mode (with arg):    writes one entry and exits
"""

import os
import sys
import json
import time

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))


def get_psone_log_dir():
    profile = os.environ.get("USERPROFILE", "")
    if not profile:
        print("ERROR: USERPROFILE not set")
        sys.exit(1)
    return os.path.join(
        profile, "AppData", "Local", "Nuance", "PowerScribeOne",
        "Logs", "Perf",
    )


def write_psone_entry(log_dir, accession):
    """Append a SingleAccession entry to PSOnePerf.log."""
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "PSOnePerf.log")
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{timestamp} QuickSearchByAccession SingleAccession {accession}\n"
    with open(log_path, "a", encoding="utf-8") as fh:
        fh.write(line)
    print(f"  Wrote: {line.strip()}")
    return log_path


def show_state():
    state_file = os.path.join(_THIS_DIR, "data", "current_study.json")
    if os.path.isfile(state_file):
        with open(state_file, encoding="utf-8") as f:
            content = f.read().strip()
        if content:
            data = json.loads(content)
            if data:
                for k, v in data.items():
                    print(f"    {k}: {v}")
            else:
                print("    (empty — no study locked)")
        else:
            print("    (file empty)")
    else:
        print("    (file does not exist yet)")


def show_log(n=15):
    log_path = os.path.join(_THIS_DIR, "logs", "dicom-service.log")
    if os.path.isfile(log_path):
        with open(log_path, encoding="utf-8") as f:
            lines = f.readlines()
        # Filter out the noisy pydicom optional-codec probes
        filtered = [l for l in lines if "pydicom.pixels" not in l
                    and "No module named" not in l
                    and "_passes_version_check" not in l
                    and "_find_and_load" not in l
                    and "_gcd_import" not in l
                    and "import_module" not in l
                    and "ModuleNotFoundError" not in l
                    and "Traceback" not in l]
        for line in filtered[-n:]:
            print(f"  {line.rstrip()}")
    else:
        print("  (no log file)")


def main():
    psone_log_dir = get_psone_log_dir()
    psone_log_path = os.path.join(psone_log_dir, "PSOnePerf.log")

    # One-shot mode
    if len(sys.argv) > 1:
        acc = sys.argv[1]
        write_psone_entry(psone_log_dir, acc)
        return

    # Interactive mode
    print("=" * 55)
    print("  PSOnePerf.log Simulator")
    print("=" * 55)
    print()
    print(f"  Log path: {psone_log_path}")
    print()
    print("  1. Open a study in InteleViewer")
    print("  2. Type the accession number here")
    print("  3. Watch current_study.json populate")
    print()
    print("Commands:")
    print("  <accession>  Write accession to PSOnePerf.log")
    print("  state        Show current_study.json")
    print("  log          Show recent service log (filtered)")
    print("  wait         Write accession then poll state for 10s")
    print("  q            Quit")
    print("-" * 55)

    try:
        while True:
            cmd = input("\n> ").strip()
            if not cmd:
                continue

            if cmd.lower() in ("q", "quit", "exit"):
                break
            elif cmd.lower() == "state":
                show_state()
            elif cmd.lower() == "log":
                show_log()
            elif cmd.lower().startswith("wait "):
                acc = cmd.split(None, 1)[1]
                write_psone_entry(psone_log_dir, acc)
                print("  Polling state for up to 10s...")
                for i in range(20):
                    time.sleep(0.5)
                    state_file = os.path.join(_THIS_DIR, "data", "current_study.json")
                    if os.path.isfile(state_file):
                        with open(state_file, encoding="utf-8") as f:
                            data = json.loads(f.read().strip() or "{}")
                        if data.get("Acc"):
                            print(f"  LOCKED after {(i+1)*0.5:.1f}s:")
                            show_state()
                            break
                else:
                    print("  No lock after 10s. Check 'log' for details.")
            else:
                # Treat as accession
                write_psone_entry(psone_log_dir, cmd)
                print("  (run 'state' in a few seconds to check)")

    except (KeyboardInterrupt, EOFError):
        pass

    print("\nDone.")


if __name__ == "__main__":
    main()
