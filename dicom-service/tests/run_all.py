"""Run all dicom-service tests.

Usage:
    python tests/run_all.py          # from dicom-service/
    python dicom-service/tests/run_all.py  # from vaguslab/
"""

import os
import sys
import unittest

# Ensure dicom-service/ is on the path
tests_dir = os.path.dirname(os.path.abspath(__file__))
service_dir = os.path.dirname(tests_dir)
sys.path.insert(0, service_dir)

if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = loader.discover(tests_dir, pattern="test_*.py")
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
