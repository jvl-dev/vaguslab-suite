"""Tests for window monitor helper functions and safety logic."""

import os
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from window_monitor import WindowMonitor, _extract_last_name


class TestExtractLastName(unittest.TestCase):
    """Test _extract_last_name() helper."""

    def test_standard_dicom_name(self):
        self.assertEqual(_extract_last_name("DOE^JOHN"), "DOE")

    def test_last_name_only(self):
        self.assertEqual(_extract_last_name("DOE"), "DOE")

    def test_multiple_components(self):
        self.assertEqual(_extract_last_name("DOE^JOHN^M^DR"), "DOE")

    def test_empty_string(self):
        self.assertEqual(_extract_last_name(""), "")

    def test_none(self):
        self.assertEqual(_extract_last_name(None), "")


class TestPatientSafety(unittest.TestCase):
    """Test WindowMonitor.check_patient_safety() state transitions."""

    def _make_monitor_pair(self):
        """Create a WindowMonitor and a mock DicomMonitor."""
        wm = WindowMonitor()
        dm = MagicMock()
        dm.reset_state = MagicMock()
        return wm, dm

    def test_window_closed_clears_state(self):
        wm, dm = self._make_monitor_pair()
        wm.last_patient_title = "DOE^JOHN - Study"
        # Simulate window closing (get_patient_title returns "")
        with patch.object(wm, "get_patient_title", return_value=""):
            wm.check_patient_safety(dm)
        dm.reset_state.assert_called_once_with("window_closed")
        self.assertEqual(wm.last_patient_title, "")

    def test_patient_changed_clears_state(self):
        wm, dm = self._make_monitor_pair()
        wm.last_patient_title = "DOE^JOHN"
        with patch.object(wm, "get_patient_title", return_value="SMITH^JANE"):
            wm.check_patient_safety(dm)
        dm.reset_state.assert_called_once_with("patient_changed")
        self.assertEqual(wm.last_patient_title, "SMITH^JANE")

    def test_same_patient_no_reset(self):
        wm, dm = self._make_monitor_pair()
        wm.last_patient_title = "DOE^JOHN"
        with patch.object(wm, "get_patient_title", return_value="DOE^JOHN"):
            wm.check_patient_safety(dm)
        dm.reset_state.assert_not_called()

    def test_no_window_no_previous_no_reset(self):
        wm, dm = self._make_monitor_pair()
        wm.last_patient_title = ""
        with patch.object(wm, "get_patient_title", return_value=""):
            wm.check_patient_safety(dm)
        dm.reset_state.assert_not_called()

    def test_window_appears_no_reset(self):
        wm, dm = self._make_monitor_pair()
        wm.last_patient_title = ""
        with patch.object(wm, "get_patient_title", return_value="DOE^JOHN"):
            wm.check_patient_safety(dm)
        dm.reset_state.assert_not_called()
        self.assertEqual(wm.last_patient_title, "DOE^JOHN")


if __name__ == "__main__":
    unittest.main()
