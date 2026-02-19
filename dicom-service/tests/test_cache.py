"""Tests for LRU cache and state file writing."""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from dicom_monitor import DicomMonitor


class TestLRUCache(unittest.TestCase):
    """Test the DicomMonitor LRU cache (OrderedDict, default 5 entries)."""

    def _make_monitor(self, cache_size=5):
        data_dir = tempfile.mkdtemp()
        self.addCleanup(lambda: _rmtree(data_dir))
        return DicomMonitor(
            cache_dir=tempfile.mkdtemp(),
            data_dir=data_dir,
            cache_size=cache_size,
        )

    def test_add_and_retrieve(self):
        m = self._make_monitor()
        data = {"Acc": "RAD-1-CT", "_Name": "DOE^JOHN"}
        m._add_to_cache("RAD-1-CT", data)
        self.assertIn("RAD-1-CT", m._cache)
        self.assertEqual(m._cache["RAD-1-CT"]["Acc"], "RAD-1-CT")

    def test_eviction_at_limit(self):
        m = self._make_monitor(cache_size=3)
        for i in range(4):
            m._add_to_cache(f"ACC-{i}", {"Acc": f"ACC-{i}", "_Name": "X"})
        # First entry should have been evicted
        self.assertNotIn("ACC-0", m._cache)
        self.assertIn("ACC-1", m._cache)
        self.assertIn("ACC-2", m._cache)
        self.assertIn("ACC-3", m._cache)
        self.assertEqual(len(m._cache), 3)

    def test_reinsert_moves_to_end(self):
        m = self._make_monitor(cache_size=3)
        m._add_to_cache("A", {"Acc": "A", "_Name": "X"})
        m._add_to_cache("B", {"Acc": "B", "_Name": "X"})
        m._add_to_cache("C", {"Acc": "C", "_Name": "X"})
        # Re-add A (should move to end, making B the oldest)
        m._add_to_cache("A", {"Acc": "A", "_Name": "X"})
        # Now add D — B should be evicted (oldest)
        m._add_to_cache("D", {"Acc": "D", "_Name": "X"})
        self.assertNotIn("B", m._cache)
        self.assertIn("A", m._cache)
        self.assertIn("C", m._cache)
        self.assertIn("D", m._cache)

    def test_cache_size_one(self):
        m = self._make_monitor(cache_size=1)
        m._add_to_cache("A", {"Acc": "A", "_Name": "X"})
        m._add_to_cache("B", {"Acc": "B", "_Name": "X"})
        self.assertEqual(len(m._cache), 1)
        self.assertNotIn("A", m._cache)
        self.assertIn("B", m._cache)


class TestStateFileWrite(unittest.TestCase):
    """Test _write_state() privacy filtering and atomic writes."""

    def _make_monitor(self):
        data_dir = tempfile.mkdtemp()
        self.addCleanup(lambda: _rmtree(data_dir))
        return DicomMonitor(
            cache_dir=tempfile.mkdtemp(),
            data_dir=data_dir,
        )

    def test_write_demographics(self):
        m = self._make_monitor()
        m._write_state({
            "Acc": "RAD-123-CT",
            "Sex": "M",
            "Age": "045Y",
            "Mod": "CT",
            "StudyDesc": "CT CHEST",
        })
        with open(m.state_file, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data["Acc"], "RAD-123-CT")
        self.assertEqual(data["Sex"], "M")
        self.assertEqual(data["Age"], "045Y")
        self.assertEqual(data["Mod"], "CT")
        self.assertEqual(data["StudyDesc"], "CT CHEST")

    def test_patient_name_never_written(self):
        m = self._make_monitor()
        m._write_state({
            "_Name": "DOE^JOHN",
            "Acc": "RAD-123-CT",
            "Sex": "F",
            "Age": "30Y",
            "Mod": "MR",
            "StudyDesc": "MR BRAIN",
        })
        with open(m.state_file, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertNotIn("_Name", data)
        self.assertNotIn("Name", data)
        # Verify the content doesn't contain patient name
        with open(m.state_file, encoding="utf-8") as fh:
            raw = fh.read()
        self.assertNotIn("DOE", raw)
        self.assertNotIn("JOHN", raw)

    def test_write_empty_state(self):
        m = self._make_monitor()
        m._write_state({})
        with open(m.state_file, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data, {})

    def test_control_chars_stripped(self):
        m = self._make_monitor()
        m._write_state({"Acc": "RAD\x00-123\x0a-CT"})
        with open(m.state_file, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data["Acc"], "RAD-123-CT")

    def test_only_allowed_keys(self):
        m = self._make_monitor()
        m._write_state({
            "Acc": "A",
            "Sex": "M",
            "Age": "50Y",
            "Mod": "CT",
            "StudyDesc": "Test",
            "_Name": "SECRET",
            "_source": "cache",
            "RandomKey": "should_not_appear",
        })
        with open(m.state_file, encoding="utf-8") as fh:
            data = json.load(fh)
        allowed = {"Acc", "Sex", "Age", "Mod", "StudyDesc"}
        self.assertTrue(set(data.keys()).issubset(allowed))

    def test_creates_data_dir(self):
        data_dir = os.path.join(tempfile.mkdtemp(), "nested", "data")
        self.addCleanup(lambda: _rmtree(os.path.dirname(os.path.dirname(data_dir))))
        m = DicomMonitor(cache_dir=tempfile.mkdtemp(), data_dir=data_dir)
        m._write_state({"Acc": "X"})
        self.assertTrue(os.path.isfile(m.state_file))


class TestResetState(unittest.TestCase):
    """Test DicomMonitor.reset_state()."""

    def test_reset_clears_search(self):
        data_dir = tempfile.mkdtemp()
        m = DicomMonitor(cache_dir=tempfile.mkdtemp(), data_dir=data_dir)
        m.search_active = True
        m.search_target_acc = "RAD-1-CT"
        m.current_locked_acc = "RAD-1-CT"

        m.reset_state("test")

        self.assertFalse(m.search_active)
        self.assertEqual(m.search_target_acc, "")
        self.assertEqual(m.current_locked_acc, "")

    def test_reset_writes_empty_state(self):
        data_dir = tempfile.mkdtemp()
        m = DicomMonitor(cache_dir=tempfile.mkdtemp(), data_dir=data_dir)
        # Write some state first
        m._write_state({"Acc": "RAD-1-CT", "Mod": "CT"})
        m.reset_state("test")
        with open(m.state_file, encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertEqual(data, {})


def _rmtree(path):
    """Best-effort recursive delete."""
    import shutil
    try:
        shutil.rmtree(path)
    except OSError:
        pass


if __name__ == "__main__":
    unittest.main()
