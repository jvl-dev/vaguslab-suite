"""
Window Monitor — InteleViewer patient window safety checks.

Polls InteleViewer windows every timer tick. Clears DICOM state when the
patient viewer closes or the displayed patient changes (last-name comparison).
"""

import logging

try:
    import win32gui
except ImportError:
    win32gui = None

log = logging.getLogger(__name__)


class WindowMonitor:
    """Track InteleViewer patient window state."""

    def __init__(self):
        self.last_patient_title = ""

    # ------------------------------------------------------------------
    # Public
    # ------------------------------------------------------------------

    def get_patient_title(self):
        """Return the patient name string from the active InteleViewer viewer.

        Patient windows contain ``^`` (name separator) and `` - `` (field
        separator) but are *not* the Search Tool.  Returns the portion
        before the first `` - `` or empty string if no patient window found.
        """
        if win32gui is None:
            return ""

        result = []

        def _enum_cb(hwnd, _):
            if not win32gui.IsWindowVisible(hwnd):
                return True
            try:
                title = win32gui.GetWindowText(hwnd)
            except Exception:
                return True
            if not title:
                return True
            # InteleViewer patient windows: have "^" and " - ", not Search Tool
            if "^" in title and " - " in title and "Search Tool" not in title:
                # Verify it belongs to InteleViewer
                try:
                    _, pid = win32gui.GetWindowThreadProcessId(hwnd)  # noqa: F841
                    # We can't cheaply check exe name without psutil, so rely
                    # on the title heuristic which is unique to InteleViewer.
                except Exception:
                    pass
                patient_part = title.split(" - ")[0].strip()
                result.append(patient_part)
                return False  # stop enumeration
            return True

        try:
            win32gui.EnumWindows(_enum_cb, None)
        except Exception:
            pass

        return result[0] if result else ""

    def check_patient_safety(self, monitor):
        """Clear monitor state when the patient viewer closes or changes.

        Called every timer tick from the main loop.

        *monitor* is the :class:`DicomMonitor` instance whose state should
        be reset when the window disappears or a different patient is loaded.
        """
        current_title = self.get_patient_title()

        # Window closed while we had state
        if not current_title and self.last_patient_title:
            log.info("Patient window closed — clearing state")
            self.last_patient_title = ""
            monitor.reset_state("window_closed")
            return

        # Patient changed (different last name)
        if current_title and self.last_patient_title:
            new_last = _extract_last_name(current_title)
            old_last = _extract_last_name(self.last_patient_title)
            if new_last != old_last:
                log.info("Patient changed: %s -> %s", old_last, new_last)
                monitor.reset_state("patient_changed")

        self.last_patient_title = current_title


def _extract_last_name(full_name):
    """Return the portion before the first ``^`` (DICOM PN component)."""
    if not full_name:
        return ""
    return full_name.split("^")[0]
