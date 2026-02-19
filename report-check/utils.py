"""
Utility functions for Report Check Python Backend

Date verification, HTML escaping, and misc helpers.
Replaces relevant parts of SharedUtils.ahk.
"""
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import re
from datetime import datetime

_MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


def pre_verify_dates(report_text):
    """Pre-verify all DD/MM/YYYY dates in report text against today's date.

    Returns a verification summary block to prepend to the report,
    or empty string if no dates found. Each date is tagged PAST, TODAY, or FUTURE.

    Matches SharedUtils.PreVerifyDates() in AHK.
    """
    now = datetime.now()
    today_str = now.strftime("%Y%m%d")
    today_display = f"{now.day}/{now.month}/{now.year}"

    results = []
    seen = set()

    for m in re.finditer(r"(\d{1,2})/(\d{1,2})/(\d{4})", report_text):
        date_str = m.group(0)
        if date_str in seen:
            continue
        seen.add(date_str)

        day, month, year = int(m.group(1)), int(m.group(2)), int(m.group(3))
        comp_date = f"{year:04d}{month:02d}{day:02d}"

        if comp_date > today_str:
            status = "FUTURE"
        elif comp_date == today_str:
            status = "TODAY"
        else:
            status = "PAST"

        # Build long-form date
        try:
            long_date = f"{day} {_MONTHS[month - 1]} {year}"
        except (IndexError, ValueError):
            long_date = date_str

        results.append((date_str, long_date, status))

    if not results:
        return ""

    lines = ["[DATE VERIFICATION \u2014 computed by system, not the AI model]"]
    lines.append(f"Today's date: {today_display}")
    for date_str, long_date, status in results:
        lines.append(f"\u2022 {date_str} ({long_date}) \u2192 {status}")
    lines.append("[END DATE VERIFICATION]")

    return "\n".join(lines)


def escape_html(text):
    """Escape HTML special characters (matching SharedUtils.EscapeHTML).

    Handles ASCII special chars while preserving Unicode (em dashes, smart quotes, etc.)
    """
    if not text:
        return ""
    # & must be first to avoid double-escaping
    text = text.replace("&", "&amp;")
    text = text.replace("<", "&lt;")
    text = text.replace(">", "&gt;")
    text = text.replace('"', "&quot;")
    return text
