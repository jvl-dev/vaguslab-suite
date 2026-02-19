"""
Config Reader for Report Check Python Backend

Reads config.json (owned by AHK), handles API key deobfuscation,
loads system prompts, and reads DICOM demographics from current_study.json.

IMPORTANT: Python never writes to config.json — AHK owns config writes.
"""
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
prompts_dir = os.path.join(script_dir, "prompts")
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import json
import logging
import re
from datetime import datetime
from pathlib import Path

logger = logging.getLogger("report-check")


def read_config(config_path):
    """Read and parse the config.json file."""
    with open(config_path, encoding="utf-8-sig") as f:
        return json.load(f)


def get_provider(config):
    """Get the active API provider."""
    return config.get("api", {}).get("provider", "claude")


def get_api_key(config, provider):
    """Get the API key for the given provider, handling deobfuscation."""
    key_field = f"{provider}_api_key"
    raw_key = config.get("api", {}).get(key_field, "")
    if not raw_key:
        return ""
    if _is_plaintext_key(raw_key):
        return raw_key
    return _deobfuscate_key(raw_key)


def get_model(config, provider, mode_override=""):
    """Get the model for the given provider and mode.

    No hardcoded defaults — AHK writes all model fields to config.json
    via Constants.GetDefaultModel().  If a field is missing, something
    went wrong on the AHK side; log a warning and return empty string.
    """
    prompt_type = (
        mode_override
        if mode_override in ("comprehensive", "proofreading")
        else config.get("settings", {}).get("prompt_type", "comprehensive")
    )
    model_field = f"{prompt_type}_{provider}_model"
    model = config.get("settings", {}).get(model_field, "")
    if not model:
        logger.warning("Model field '%s' missing from config — AHK should have written it", model_field)
    return model


def get_mode(config, mode_override=""):
    """Determine actual mode (comprehensive or proofreading)."""
    if mode_override in ("comprehensive", "proofreading"):
        return mode_override
    return config.get("settings", {}).get("prompt_type", "comprehensive")


_FALLBACK_PROMPT = (
    "You are a radiology report checking assistant. Review the provided "
    "radiology report and provide constructive, professional feedback."
)


def get_prompt(config_dir, mode_override="", config=None):
    """Load the system prompt for the given mode, with date injection."""
    prompt_type = get_mode(config or {}, mode_override)

    prompt_path = os.path.join(prompts_dir, f"system_prompt_{prompt_type}.txt")
    if os.path.exists(prompt_path):
        with open(prompt_path, encoding="utf-8") as f:
            content = f.read()
        if content.startswith("\ufeff"):
            content = content[1:]
        return _inject_dates(content)

    logger.warning("Prompt file not found: %s — using fallback", prompt_path)
    return _FALLBACK_PROMPT


def get_targeted_prompt(config_dir):
    """Load the targeted review system prompt."""
    path = os.path.join(prompts_dir, "system_prompt_targeted_review.txt")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            content = f.read()
        if content.startswith("\ufeff"):
            content = content[1:]
        return content
    logger.warning("Targeted prompt not found: %s", path)
    return ""


def is_targeted_review_enabled(config):
    """Check if targeted review is enabled (requires both flags)."""
    demo_enabled = config.get("beta", {}).get("demographic_extraction_enabled", False)
    targeted_enabled = config.get("settings", {}).get("targeted_review_enabled", False)
    return demo_enabled and targeted_enabled


def is_demographic_extraction_enabled(config):
    """Check if demographic extraction is enabled."""
    return config.get("beta", {}).get("demographic_extraction_enabled", False)


def _find_state_file(config_dir):
    """Locate current_study.json: shared dicom-service first, then legacy."""
    # Shared dicom-service (dev sibling layout)
    dev_path = os.path.normpath(
        os.path.join(script_dir, "..", "dicom-service", "data", "current_study.json")
    )
    if os.path.isfile(dev_path):
        return dev_path

    # Shared dicom-service (production LOCALAPPDATA)
    local_app = os.environ.get("LOCALAPPDATA", "")
    if local_app:
        prod_path = os.path.join(
            local_app, "vaguslab", "dicom-service", "data", "current_study.json"
        )
        if os.path.isfile(prod_path):
            return prod_path

    # Legacy fallback: config_dir/current_study.json
    legacy_path = os.path.join(config_dir, "current_study.json")
    if os.path.isfile(legacy_path):
        return legacy_path

    return ""


def read_demographics(config_dir):
    """Read current_study.json and return non-identifiable demographics.

    PRIVACY: Only returns Age, Sex, Modality, StudyDesc.
    Patient name is NEVER extracted.

    Search order: shared dicom-service/data/ (dev sibling -> LOCALAPPDATA)
    then legacy config_dir/current_study.json fallback.
    """
    state_file = _find_state_file(config_dir)
    result = {"Age": "", "Sex": "", "Modality": "", "StudyDesc": "", "success": False}

    if not state_file:
        return result

    try:
        with open(state_file, encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return result

    if not data or not isinstance(data, dict):
        return result

    # PRIVACY: Extract ONLY non-identifiable fields
    age = data.get("Age", "")
    if age and age not in ("?", "--"):
        result["Age"] = re.sub(r"^0+", "", age)  # Strip leading zeros

    sex = data.get("Sex", "")
    if sex and sex not in ("?", "--"):
        sex_map = {"M": "Male", "F": "Female", "O": "Other"}
        result["Sex"] = sex_map.get(sex, sex)

    mod = data.get("Mod", "")
    if mod and mod != "--":
        result["Modality"] = mod

    study_desc = data.get("StudyDesc", "")
    if study_desc and study_desc not in ("N/A", "--"):
        result["StudyDesc"] = study_desc

    if any(result[k] for k in ("Age", "Sex", "Modality", "StudyDesc")):
        result["success"] = True

    return result


def format_demographics_string(demographics):
    """Format demographics as a string for prepending to report.
    e.g. 'Patient demographics: 69Y, Male, CT, CT CHEST'
    """
    if not demographics.get("success"):
        return ""
    parts = []
    for field in ("Age", "Sex", "Modality", "StudyDesc"):
        if demographics.get(field):
            parts.append(demographics[field])
    if not parts:
        return ""
    return "Patient demographics: " + ", ".join(parts)


def build_demographics_label(demographics):
    """Build demographics label for display (e.g. '69Y/M/CT/CT Chest').
    Only uses non-identifiable fields.
    """
    if not demographics.get("success"):
        return ""
    parts = []
    if demographics.get("Age"):
        parts.append(demographics["Age"])
    if demographics.get("Sex"):
        sex = demographics["Sex"]
        if sex == "Male":
            parts.append("M")
        elif sex == "Female":
            parts.append("F")
        else:
            parts.append(sex[:1])
    if demographics.get("Modality"):
        parts.append(demographics["Modality"])
    if demographics.get("StudyDesc"):
        desc = demographics["StudyDesc"]
        if len(desc) > 30:
            desc = desc[:27] + "..."
        parts.append(desc)
    return "/".join(parts) if parts else ""


# --- Internal helpers ---


def _is_plaintext_key(key):
    """Check if a key is plaintext (not obfuscated)."""
    if key.startswith("sk-ant-"):
        return True
    if key.startswith("AI"):
        return True
    if key.startswith("sk-") and not key.startswith("sk-ant-"):
        return True
    return False


def _get_machine_key():
    """Generate the same machine key as AHK's ObfuscateAPIKey.
    Format: ComputerName|UserName|VolumeSerialNumber
    """
    import platform

    computer_name = platform.node()
    user_name = os.environ.get("USERNAME", os.environ.get("USER", ""))
    volume_serial = _get_volume_serial()
    return f"{computer_name}|{user_name}|{volume_serial}"


def _get_volume_serial():
    """Get C: drive volume serial number (matching AHK's WMI query)."""
    try:
        import win32com.client

        wmi = win32com.client.GetObject("winmgmts:")
        results = wmi.ExecQuery(
            "SELECT VolumeSerialNumber FROM Win32_LogicalDisk WHERE DeviceID='C:'"
        )
        for item in results:
            return item.VolumeSerialNumber
    except Exception:
        pass
    # Fallback matching AHK: StrReplace(A_ScriptDir, "\", "_")
    return script_dir.replace("\\", "_")


def _deobfuscate_key(hex_encrypted):
    """XOR decrypt a hex-encoded obfuscated key (matching AHK's _XORDecrypt)."""
    machine_key = _get_machine_key()
    try:
        chars = []
        for i in range(0, len(hex_encrypted), 2):
            chars.append(int(hex_encrypted[i : i + 2], 16))
        result = []
        key_len = len(machine_key)
        for i, c in enumerate(chars):
            key_char = ord(machine_key[i % key_len])
            result.append(chr(c ^ key_char))
        return "".join(result)
    except Exception:
        return ""


_MONTHS = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]


def _inject_dates(prompt):
    """Replace date placeholders with current date values."""
    now = datetime.now()
    current_date = f"{now.day}/{now.month}/{now.year}"
    current_date_long = f"{now.day} {_MONTHS[now.month - 1]} {now.year}"
    current_year = str(now.year)
    previous_year = str(now.year - 1)

    prompt = prompt.replace(
        "{{CURRENT_DATE}}", f"{current_date} ({current_date_long})"
    )
    prompt = prompt.replace("{{CURRENT_YEAR}}", current_year)
    prompt = prompt.replace("{{PREVIOUS_YEAR}}", previous_year)
    return prompt
