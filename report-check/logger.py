"""
Logging setup for Report Check Python Backend

Configures Python logging to write to <script_dir>/logs/ alongside AHK logs.
"""
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path


def setup_logging(debug=False):
    """Configure logging for the Python backend."""
    log_dir = Path(script_dir) / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)

    log_file = log_dir / "report-check-python.log"

    logger = logging.getLogger("report-check")
    logger.setLevel(logging.DEBUG if debug else logging.INFO)

    # Avoid duplicate handlers on repeated calls
    if logger.handlers:
        return logger

    # File handler with rotation
    file_handler = RotatingFileHandler(
        log_file, maxBytes=10 * 1024 * 1024, backupCount=5, encoding="utf-8"
    )
    file_handler.setLevel(logging.DEBUG if debug else logging.INFO)

    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger
