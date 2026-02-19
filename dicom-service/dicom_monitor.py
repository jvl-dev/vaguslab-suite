"""
DICOM Monitor — core monitoring logic.

Ported from DicomMonitor.ahk (661 lines).  Uses *pydicom* for parsing and
*watchdog* to detect PSOnePerf.log modifications instantly (replaces 2 s
polling).  The main loop still calls :meth:`continue_search` every 2 s to
handle cases where the DICOM file hasn't appeared yet.
"""

import json
import logging
import os
import re
import tempfile
import time
from collections import OrderedDict

from watchdog.events import FileSystemEventHandler

try:
    import pydicom
except ImportError:
    pydicom = None

log = logging.getLogger(__name__)

# Modalities we consider clinically useful (others like REG, SR, PR are
# valid DICOM but not helpful for demographic display).
_CLINICAL_MODALITIES = {"CT", "MR", "US", "DX", "CR", "MG", "PT", "NM", "XA"}
_CLINICAL_RE = re.compile(r"^(" + "|".join(_CLINICAL_MODALITIES) + r")$")
_ACC_MOD_RE = re.compile(r"-(" + "|".join(_CLINICAL_MODALITIES) + r")(?:[_-]|$)")


# ======================================================================
# watchdog handler — triggers on PSOnePerf.log modification
# ======================================================================

class PSOnePerfHandler(FileSystemEventHandler):
    """watchdog handler that fires when PSOnePerf.log is modified."""

    def __init__(self, monitor):
        super().__init__()
        self.monitor = monitor

    def on_modified(self, event):
        if event.is_directory:
            return
        # watchdog may fire for any file in the watched directory
        if os.path.basename(event.src_path) != "PSOnePerf.log":
            return
        log.debug("PSOnePerf.log modified (watchdog)")
        self.monitor.on_psone_log_changed()


# ======================================================================
# DicomMonitor
# ======================================================================

class DicomMonitor:
    """Core DICOM monitoring logic."""

    def __init__(self, *, cache_dir, data_dir, search_timeout=120,
                 cache_size=5, max_scan_folders=50):
        self.cache_dir = cache_dir
        self.data_dir = data_dir
        self.state_file = os.path.join(data_dir, "current_study.json")
        self.search_timeout = search_timeout
        self.cache_size = cache_size
        self.max_scan_folders = max_scan_folders

        # Search state
        self.search_active = False
        self.search_start = 0.0
        self.search_target_acc = ""
        self.current_locked_acc = ""

        # PSOne log state
        self._last_psone_mtime = 0.0

        # LRU cache: accession -> parsed dict
        self._cache = OrderedDict()

        # Reference to the window monitor (set by main loop)
        self.window_monitor = None

    # ------------------------------------------------------------------
    # PSOne log change (called by watchdog handler AND by fallback poll)
    # ------------------------------------------------------------------

    def on_psone_log_changed(self):
        """Parse PSOnePerf.log and start a search if a new accession is found."""
        # Only trigger if a patient window is open
        if self.window_monitor and not self.window_monitor.last_patient_title:
            return

        log_path = _psone_log_path()
        if not log_path or not os.path.isfile(log_path):
            return

        try:
            mtime = os.path.getmtime(log_path)
        except OSError:
            return

        if mtime == self._last_psone_mtime:
            return
        self._last_psone_mtime = mtime

        acc = self._parse_psone_log(log_path)
        if acc and acc != self.search_target_acc and acc != self.current_locked_acc:
            self._start_search(acc)

    # ------------------------------------------------------------------
    # Search lifecycle
    # ------------------------------------------------------------------

    def _start_search(self, accession):
        log.info("Starting DICOM search for %s", accession)
        self.search_active = True
        self.search_start = time.monotonic()
        self.search_target_acc = accession
        self.current_locked_acc = ""
        self._write_state({})

    def continue_search(self):
        """Called from the main loop every timer tick while a search is active."""
        if not self.search_active:
            return

        elapsed = time.monotonic() - self.search_start
        if elapsed > self.search_timeout:
            log.warning("Search timed out for %s (%.1f s)",
                        self.search_target_acc, elapsed)
            self._stop_search()
            return

        result = self._try_match(self.search_target_acc)
        if result is not None:
            log.info("DICOM lock for %s (%.1f s, source=%s)",
                     self.search_target_acc, elapsed, result.get("_source", "?"))
            self.current_locked_acc = self.search_target_acc
            self._write_state(result)
            self._stop_search()

    def _stop_search(self):
        self.search_active = False
        self.search_start = 0.0

    def reset_state(self, reason):
        """Clear all search/lock state and empty the state file."""
        was_active = self.search_active or self.current_locked_acc
        self.search_active = False
        self.search_start = 0.0
        self.search_target_acc = ""
        self.current_locked_acc = ""
        self._last_psone_mtime = 0.0
        self._write_state({})
        if was_active:
            log.info("State reset (%s)", reason)

    # ------------------------------------------------------------------
    # DICOM matching
    # ------------------------------------------------------------------

    def _try_match(self, target_acc):
        """Try to find a DICOM study matching *target_acc*.

        Returns a demographics dict on success, or *None*.
        """
        window_patient = ""
        if self.window_monitor:
            window_patient = self.window_monitor.last_patient_title
        window_last = _extract_last_name(window_patient)

        # 1) Check LRU cache
        if target_acc in self._cache:
            data = self._cache[target_acc]
            dicom_last = _extract_last_name(data.get("_Name", ""))
            if not window_last or window_last.upper() in (data.get("_Name", "")).upper():
                # Move to end (most recently used)
                self._cache.move_to_end(target_acc)
                log.debug("Cache hit for %s", target_acc)
                data["_source"] = "cache"
                return data
            else:
                log.warning("Cache hit but name mismatch: dicom=%s window=%s",
                            data.get("_Name", ""), window_patient)
                return None

        # 2) Scan recent folders
        data = self._find_in_recent_folders(target_acc)
        if data is None:
            return None

        dicom_last = _extract_last_name(data.get("_Name", ""))
        self._add_to_cache(target_acc, data)

        if not window_last or window_last.upper() in (data.get("_Name", "")).upper():
            data["_source"] = "recent_folders"
            return data

        log.warning("Accession match but name mismatch: dicom=%s window=%s",
                    data.get("_Name", ""), window_patient)
        return None

    def _find_in_recent_folders(self, target_acc):
        """Scan the top N most-recently-modified study folders in the DICOM cache.

        InteleViewer stores studies as UID-named folders directly under the
        cache directory::

            <cache_dir>/
              <study_uid>/                 ← one per study, sorted by mtime
                <series_uid>/*.dcm

        Only UID-named folders (starting with a digit) are considered.
        Named directories like ``InteleViewerDicomSpool`` are skipped.
        One DICOM file per folder is enough since all files in a study
        share the same accession.
        """
        if not os.path.isdir(self.cache_dir):
            return None

        entries = []  # (mtime, path)
        try:
            for child in os.listdir(self.cache_dir):
                if not _looks_like_uid(child):
                    continue
                child_path = os.path.join(self.cache_dir, child)
                if not os.path.isdir(child_path):
                    continue
                try:
                    entries.append((os.path.getmtime(child_path), child_path))
                except OSError:
                    pass
        except OSError:
            return None

        entries.sort(reverse=True)
        entries = entries[:self.max_scan_folders]

        for _, folder in entries:
            data = self._parse_first_dicom_in_folder(folder)
            if data and data.get("_Name", "") != "Unknown":
                dicom_acc = _extract_core_acc(data.get("Acc", ""))
                if dicom_acc == target_acc:
                    return data

        return None

    def _parse_first_dicom_in_folder(self, folder):
        """Find and parse the first valid DICOM file in *folder* using pydicom."""
        if pydicom is None:
            log.error("pydicom not installed")
            return None

        for root, _dirs, files in os.walk(folder):
            for fname in files:
                path = os.path.join(root, fname)
                try:
                    if os.path.getsize(path) < 1024:
                        continue
                except OSError:
                    continue
                try:
                    ds = pydicom.dcmread(path, stop_before_pixels=True, force=True)
                except Exception:
                    continue
                return _extract_fields(ds)

        return None

    # ------------------------------------------------------------------
    # LRU cache
    # ------------------------------------------------------------------

    def _add_to_cache(self, accession, data):
        if accession in self._cache:
            self._cache.move_to_end(accession)
        self._cache[accession] = data
        while len(self._cache) > self.cache_size:
            evicted_acc, _ = self._cache.popitem(last=False)
            log.debug("Evicted %s from cache", evicted_acc)
        log.debug("Cached %s (size=%d)", accession, len(self._cache))

    # ------------------------------------------------------------------
    # PSOne log parsing
    # ------------------------------------------------------------------

    @staticmethod
    def _parse_psone_log(log_path):
        """Read PSOnePerf.log and return the most recent core accession."""
        try:
            with open(log_path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            return ""

        for line in reversed(lines):
            fields = line.split()

            # Try SingleAccession token first
            for i, tok in enumerate(fields[:-1]):
                if tok == "SingleAccession":
                    raw = fields[i + 1]
                    if raw and raw != "-":
                        acc = _extract_core_acc(raw)
                        log.info("PSOne accession: %s (raw=%s, type=SingleAccession)",
                                 acc, raw)
                        return acc
                    break

            # Try accession pattern in any field
            for tok in fields:
                if re.match(r"^[A-Z]{2,3}-\d+-[A-Z]{2}$", tok):
                    acc = _extract_core_acc(tok)
                    log.info("PSOne accession: %s (type=pattern_match)", acc)
                    return acc

        return ""

    # ------------------------------------------------------------------
    # State file I/O
    # ------------------------------------------------------------------

    def _write_state(self, data):
        """Write demographics to current_study.json atomically.

        PRIVACY: patient name is never written.
        """
        os.makedirs(self.data_dir, exist_ok=True)

        # Filter to only the allowed fields
        out = {}
        for key in ("Acc", "Sex", "Age", "Mod", "StudyDesc"):
            val = data.get(key, "")
            if val:
                # Strip control characters
                out[key] = re.sub(r"[\x00-\x1f]", "", str(val))

        tmp_fd, tmp_path = tempfile.mkstemp(dir=self.data_dir, suffix=".tmp")
        try:
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
                json.dump(out, fh)
            os.replace(tmp_path, self.state_file)
        except OSError:
            log.warning("Failed to write state file", exc_info=True)
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


# ======================================================================
# Helpers (module-level)
# ======================================================================

def _looks_like_uid(name):
    """Check if a folder name looks like a DICOM UID (e.g. ``1.2.840.xxx``).

    Study and series folders created by InteleViewer are named with their
    DICOM UIDs.  Named containers like ``InteleViewerDicom`` will NOT match.
    """
    return bool(name) and name[0].isdigit() and "." in name


def _psone_log_path():
    """Derive the PSOnePerf.log path from %USERPROFILE%."""
    profile = os.environ.get("USERPROFILE", "")
    if not profile:
        return ""
    return os.path.join(
        profile,
        "AppData", "Local", "Nuance", "PowerScribeOne",
        "Logs", "Perf", "PSOnePerf.log",
    )


def _extract_core_acc(acc):
    """Normalise an accession by stripping split suffixes.

    Keeps up to and including the modality code (e.g. ``RAD-12345-CT``).
    Falls back to stripping trailing ``_N`` digits.
    """
    if not acc or acc == "N/A":
        return ""
    m = re.match(r"^(.+-(?:CT|MR|US|DX|CR|MG|PT|NM|XA))", acc)
    if m:
        return m.group(0)
    return re.sub(r"_\d+$", "", acc)


def _extract_last_name(full_name):
    if not full_name:
        return ""
    return full_name.split("^")[0]


def _extract_fields(ds):
    """Pull demographics from a pydicom Dataset.

    Returns a dict with the standard keys plus ``_Name`` (internal, never
    written to the state file).
    """
    name_raw = str(getattr(ds, "PatientName", "Unknown")).strip()
    acc_raw = str(getattr(ds, "AccessionNumber", "N/A")).strip()
    sex_raw = str(getattr(ds, "PatientSex", "?")).strip()
    age_raw = str(getattr(ds, "PatientAge", "?")).strip()
    mod_raw = str(getattr(ds, "Modality", "--")).strip()
    desc_raw = str(getattr(ds, "StudyDescription", "N/A")).strip()

    # Modality fallback chain
    mod = _resolve_modality(mod_raw, acc_raw, desc_raw)

    return {
        "_Name": name_raw,
        "Acc": acc_raw,
        "Sex": sex_raw,
        "Age": age_raw,
        "Mod": mod,
        "StudyDesc": desc_raw,
    }


def _resolve_modality(mod_tag, accession, study_desc):
    """Apply the modality fallback chain: DICOM tag -> accession -> description."""
    # 1) Use DICOM tag if it's a clinical modality
    if _CLINICAL_RE.match(mod_tag):
        return mod_tag

    # 2) Try to extract from accession
    m = _ACC_MOD_RE.search(accession)
    if m:
        return m.group(1)

    # 3) Infer from study description keywords
    if study_desc and study_desc != "N/A":
        desc = study_desc.upper()
        if "PET" in desc or "FDG" in desc:
            return "PT"
        if re.search(r"\bCT\b", desc):
            return "CT"
        if "MRI" in desc or re.search(r"\bMR\b", desc):
            return "MR"
        if "ULTRASOUND" in desc or re.search(r"\bUS\b", desc):
            return "US"
        if "X-RAY" in desc or "XRAY" in desc or "RADIOGRAPH" in desc:
            return "DX"
        if "MAMMO" in desc:
            return "MG"
        if "NUCLEAR" in desc or "SPECT" in desc:
            return "NM"
        if "FLUORO" in desc or "ANGIO" in desc:
            return "XA"

    return mod_tag  # keep whatever the tag had
