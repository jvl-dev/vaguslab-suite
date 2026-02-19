"""Tests for modality resolution fallback chain."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from dicom_monitor import _resolve_modality


class TestResolveModality(unittest.TestCase):
    """Test _resolve_modality() fallback chain: tag -> accession -> description."""

    # --- Priority 1: DICOM tag (if clinical) ---

    def test_tag_clinical_ct(self):
        self.assertEqual(_resolve_modality("CT", "", ""), "CT")

    def test_tag_clinical_mr(self):
        self.assertEqual(_resolve_modality("MR", "", ""), "MR")

    def test_tag_all_clinical(self):
        for mod in ("CT", "MR", "US", "DX", "CR", "MG", "PT", "NM", "XA"):
            self.assertEqual(_resolve_modality(mod, "", ""), mod)

    def test_tag_non_clinical_falls_through(self):
        # REG, SR, PR are valid DICOM modalities but not clinically useful
        result = _resolve_modality("REG", "RAD-123-CT", "")
        self.assertEqual(result, "CT")

    def test_tag_sr_falls_to_accession(self):
        result = _resolve_modality("SR", "RAD-123-MR", "")
        self.assertEqual(result, "MR")

    # --- Priority 2: Extract from accession ---

    def test_accession_modality(self):
        self.assertEqual(_resolve_modality("--", "RAD-12345-CT", ""), "CT")
        self.assertEqual(_resolve_modality("--", "HOS-99999-MR", ""), "MR")
        self.assertEqual(_resolve_modality("--", "ABC-11111-US", ""), "US")

    def test_accession_with_suffix(self):
        self.assertEqual(_resolve_modality("--", "RAD-12345-CT_1", ""), "CT")

    def test_accession_no_modality(self):
        # Falls through to description
        result = _resolve_modality("--", "RAD-12345", "CT CHEST")
        self.assertEqual(result, "CT")

    # --- Priority 3: Infer from study description ---

    def test_desc_pet(self):
        self.assertEqual(_resolve_modality("--", "", "PET CT WHOLE BODY"), "PT")

    def test_desc_fdg(self):
        self.assertEqual(_resolve_modality("--", "", "FDG PET/CT"), "PT")

    def test_desc_ct(self):
        self.assertEqual(_resolve_modality("--", "", "CT CHEST WITH CONTRAST"), "CT")

    def test_desc_ct_at_start(self):
        self.assertEqual(_resolve_modality("--", "", "CT ABDOMEN"), "CT")

    def test_desc_ct_at_end(self):
        self.assertEqual(_resolve_modality("--", "", "CHEST CT"), "CT")

    def test_desc_mri(self):
        self.assertEqual(_resolve_modality("--", "", "MRI BRAIN"), "MR")

    def test_desc_mr_word(self):
        self.assertEqual(_resolve_modality("--", "", "MR ABDOMEN"), "MR")

    def test_desc_ultrasound(self):
        self.assertEqual(_resolve_modality("--", "", "ULTRASOUND THYROID"), "US")

    def test_desc_us_word(self):
        self.assertEqual(_resolve_modality("--", "", "US ABDOMEN COMPLETE"), "US")

    def test_desc_xray(self):
        self.assertEqual(_resolve_modality("--", "", "X-RAY CHEST 2V"), "DX")

    def test_desc_radiograph(self):
        self.assertEqual(_resolve_modality("--", "", "RADIOGRAPH KNEE"), "DX")

    def test_desc_mammography(self):
        self.assertEqual(_resolve_modality("--", "", "MAMMOGRAPHY SCREENING"), "MG")

    def test_desc_nuclear(self):
        self.assertEqual(_resolve_modality("--", "", "NUCLEAR BONE SCAN"), "NM")

    def test_desc_spect(self):
        self.assertEqual(_resolve_modality("--", "", "SPECT MYOCARDIAL PERFUSION"), "NM")

    def test_desc_fluoro(self):
        self.assertEqual(_resolve_modality("--", "", "FLUOROSCOPY SWALLOW"), "XA")

    def test_desc_angio(self):
        self.assertEqual(_resolve_modality("--", "", "ANGIOGRAPHY CEREBRAL"), "XA")

    # --- Fallback: keep original tag ---

    def test_no_match_keeps_tag(self):
        self.assertEqual(_resolve_modality("OT", "", "SOMETHING UNKNOWN"), "OT")

    def test_empty_everything(self):
        self.assertEqual(_resolve_modality("--", "", ""), "--")

    def test_na_description_skipped(self):
        self.assertEqual(_resolve_modality("--", "", "N/A"), "--")


if __name__ == "__main__":
    unittest.main()
