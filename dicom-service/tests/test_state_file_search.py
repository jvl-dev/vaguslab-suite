"""Tests for config_reader._find_state_file() search order."""

import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

# We need to import from the report-check directory
report_check_dir = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "report-check")
)
sys.path.insert(0, report_check_dir)

import config_reader


class TestFindStateFile(unittest.TestCase):
    """Test _find_state_file() search order:
    dev sibling -> LOCALAPPDATA -> legacy config_dir fallback.
    """

    def _write_json(self, path, data=None):
        """Create a JSON file at path with optional data."""
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data or {"Acc": "test"}, fh)
        return path

    def test_dev_sibling_preferred(self):
        """Dev layout: script_dir/../dicom-service/data/current_study.json"""
        with tempfile.TemporaryDirectory() as root:
            # Simulate the dev layout
            fake_script_dir = os.path.join(root, "report-check")
            os.makedirs(fake_script_dir)
            dev_state = os.path.join(root, "dicom-service", "data", "current_study.json")
            self._write_json(dev_state)

            legacy_dir = os.path.join(root, "legacy-config")
            os.makedirs(legacy_dir)

            with patch.object(config_reader, "script_dir", fake_script_dir):
                result = config_reader._find_state_file(legacy_dir)
            self.assertEqual(os.path.normpath(result), os.path.normpath(dev_state))

    def test_localappdata_fallback(self):
        """Production layout: %LOCALAPPDATA%/vaguslab/dicom-service/data/"""
        with tempfile.TemporaryDirectory() as root:
            fake_script_dir = os.path.join(root, "no-sibling-here")
            os.makedirs(fake_script_dir)

            fake_localapp = os.path.join(root, "LocalAppData")
            prod_state = os.path.join(
                fake_localapp, "vaguslab", "dicom-service", "data", "current_study.json"
            )
            self._write_json(prod_state)

            with patch.object(config_reader, "script_dir", fake_script_dir), \
                 patch.dict(os.environ, {"LOCALAPPDATA": fake_localapp}):
                result = config_reader._find_state_file("/nonexistent/config")
            self.assertEqual(os.path.normpath(result), os.path.normpath(prod_state))

    def test_legacy_fallback(self):
        """Legacy: config_dir/current_study.json when no dicom-service exists."""
        with tempfile.TemporaryDirectory() as root:
            fake_script_dir = os.path.join(root, "no-sibling")
            os.makedirs(fake_script_dir)

            config_dir = os.path.join(root, "config")
            legacy_state = os.path.join(config_dir, "current_study.json")
            self._write_json(legacy_state)

            with patch.object(config_reader, "script_dir", fake_script_dir), \
                 patch.dict(os.environ, {"LOCALAPPDATA": os.path.join(root, "empty")}):
                result = config_reader._find_state_file(config_dir)
            self.assertEqual(os.path.normpath(result), os.path.normpath(legacy_state))

    def test_nothing_found(self):
        with tempfile.TemporaryDirectory() as root:
            fake_script_dir = os.path.join(root, "nope")
            os.makedirs(fake_script_dir)
            with patch.object(config_reader, "script_dir", fake_script_dir), \
                 patch.dict(os.environ, {"LOCALAPPDATA": os.path.join(root, "empty")}):
                result = config_reader._find_state_file("/nonexistent")
            self.assertEqual(result, "")


class TestReadDemographicsIntegration(unittest.TestCase):
    """Test that read_demographics uses _find_state_file correctly."""

    def test_reads_from_dicom_service(self):
        with tempfile.TemporaryDirectory() as root:
            fake_script_dir = os.path.join(root, "report-check")
            os.makedirs(fake_script_dir)
            state_dir = os.path.join(root, "dicom-service", "data")
            os.makedirs(state_dir)
            state_file = os.path.join(state_dir, "current_study.json")
            with open(state_file, "w", encoding="utf-8") as fh:
                json.dump({"Age": "065Y", "Sex": "F", "Mod": "CT",
                           "StudyDesc": "CT CHEST"}, fh)

            with patch.object(config_reader, "script_dir", fake_script_dir):
                result = config_reader.read_demographics("/dummy/config")

            self.assertTrue(result["success"])
            self.assertEqual(result["Age"], "65Y")  # Leading zero stripped
            self.assertEqual(result["Sex"], "Female")
            self.assertEqual(result["Modality"], "CT")
            self.assertEqual(result["StudyDesc"], "CT CHEST")


if __name__ == "__main__":
    unittest.main()
