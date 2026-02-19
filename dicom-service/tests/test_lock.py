"""Tests for PID lock file management."""

import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import dicom_service


class TestPIDLock(unittest.TestCase):
    """Test PID lock acquire / stale detection / release."""

    def setUp(self):
        self._orig_data_dir = dicom_service.DATA_DIR
        self._orig_lock_file = dicom_service.LOCK_FILE
        self._tmp = tempfile.mkdtemp()
        dicom_service.DATA_DIR = self._tmp
        dicom_service.LOCK_FILE = os.path.join(self._tmp, "service.lock")

    def tearDown(self):
        dicom_service.DATA_DIR = self._orig_data_dir
        dicom_service.LOCK_FILE = self._orig_lock_file
        import shutil
        shutil.rmtree(self._tmp, ignore_errors=True)

    def test_acquire_creates_lock(self):
        dicom_service._acquire_lock()
        self.assertTrue(os.path.isfile(dicom_service.LOCK_FILE))
        with open(dicom_service.LOCK_FILE) as fh:
            self.assertEqual(fh.read().strip(), str(os.getpid()))

    def test_release_removes_lock(self):
        dicom_service._acquire_lock()
        dicom_service._release_lock()
        self.assertFalse(os.path.isfile(dicom_service.LOCK_FILE))

    def test_stale_lock_overwritten(self):
        # Write a PID that doesn't exist (99999999 is almost certainly unused)
        with open(dicom_service.LOCK_FILE, "w") as fh:
            fh.write("99999999")
        # Should succeed — stale lock detected
        dicom_service._acquire_lock()
        with open(dicom_service.LOCK_FILE) as fh:
            self.assertEqual(fh.read().strip(), str(os.getpid()))

    def test_running_instance_exits(self):
        # Write our own PID — simulates another instance running
        with open(dicom_service.LOCK_FILE, "w") as fh:
            fh.write(str(os.getpid()))
        with self.assertRaises(SystemExit):
            dicom_service._acquire_lock()

    def test_release_no_file_no_error(self):
        # Releasing when no lock file exists should not raise
        dicom_service._release_lock()

    def test_invalid_pid_in_lock(self):
        with open(dicom_service.LOCK_FILE, "w") as fh:
            fh.write("not_a_number")
        # Should succeed — invalid PID treated as stale
        dicom_service._acquire_lock()
        with open(dicom_service.LOCK_FILE) as fh:
            self.assertEqual(fh.read().strip(), str(os.getpid()))


if __name__ == "__main__":
    unittest.main()
