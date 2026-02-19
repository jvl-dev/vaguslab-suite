"""Tests for accession normalization and PSOne log parsing."""

import os
import sys
import tempfile
import unittest

# Ensure the parent package is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from dicom_monitor import DicomMonitor, _extract_core_acc


class TestExtractCoreAcc(unittest.TestCase):
    """Test _extract_core_acc() accession normalization."""

    def test_standard_accession(self):
        self.assertEqual(_extract_core_acc("RAD-12345-CT"), "RAD-12345-CT")

    def test_strip_split_suffix(self):
        self.assertEqual(_extract_core_acc("RAD-12345-CT_1"), "RAD-12345-CT")
        self.assertEqual(_extract_core_acc("RAD-12345-CT_2"), "RAD-12345-CT")

    def test_all_clinical_modalities(self):
        for mod in ("CT", "MR", "US", "DX", "CR", "MG", "PT", "NM", "XA"):
            acc = f"HOS-99999-{mod}"
            self.assertEqual(_extract_core_acc(acc), acc)
            # With suffix
            self.assertEqual(_extract_core_acc(f"{acc}_3"), acc)

    def test_three_letter_site(self):
        self.assertEqual(_extract_core_acc("ABC-12345-MR"), "ABC-12345-MR")

    def test_no_modality_code_strips_trailing_digits(self):
        self.assertEqual(_extract_core_acc("SOMETHING_1"), "SOMETHING")
        self.assertEqual(_extract_core_acc("SOMETHING_99"), "SOMETHING")

    def test_no_modality_no_suffix_passthrough(self):
        self.assertEqual(_extract_core_acc("SOMETHING"), "SOMETHING")

    def test_empty_and_na(self):
        self.assertEqual(_extract_core_acc(""), "")
        self.assertEqual(_extract_core_acc("N/A"), "")

    def test_none_like(self):
        self.assertEqual(_extract_core_acc(None), "")


class TestParsePSOneLog(unittest.TestCase):
    """Test DicomMonitor._parse_psone_log() static method."""

    def _write_log(self, lines):
        """Write lines to a temp file and return the path."""
        fd, path = tempfile.mkstemp(suffix=".log")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))
        self.addCleanup(os.unlink, path)
        return path

    def test_single_accession_token(self):
        path = self._write_log([
            "2025-01-15 10:00:00 QuickSearchByAccession SingleAccession RAD-12345-CT",
        ])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "RAD-12345-CT")

    def test_single_accession_with_suffix(self):
        path = self._write_log([
            "2025-01-15 10:00:00 SignReport SingleAccession RAD-12345-CT_1",
        ])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "RAD-12345-CT")

    def test_pattern_match_fallback(self):
        path = self._write_log([
            "2025-01-15 10:00:00 OpenReport RAD-67890-MR",
        ])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "RAD-67890-MR")

    def test_last_line_wins(self):
        path = self._write_log([
            "2025-01-15 10:00:00 OpenReport SingleAccession RAD-11111-CT",
            "2025-01-15 10:01:00 OpenReport SingleAccession RAD-22222-MR",
        ])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "RAD-22222-MR")

    def test_skips_dash_value(self):
        path = self._write_log([
            "2025-01-15 10:00:00 Action SingleAccession -",
            "2025-01-15 10:01:00 OpenReport RAD-33333-US",
        ])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "RAD-33333-US")

    def test_empty_log(self):
        path = self._write_log([""])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "")

    def test_no_accession_lines(self):
        path = self._write_log([
            "2025-01-15 10:00:00 SomeOtherAction foo bar",
            "2025-01-15 10:01:00 AnotherAction baz",
        ])
        self.assertEqual(DicomMonitor._parse_psone_log(path), "")

    def test_missing_file(self):
        self.assertEqual(DicomMonitor._parse_psone_log("/nonexistent/path.log"), "")


if __name__ == "__main__":
    unittest.main()
