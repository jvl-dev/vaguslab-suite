"""
Targeted Review for Report Check Python Backend

Generates anatomical review guidance based on clinical context.
Replaces TargetedReviewManager.ahk (730 lines) with ~120 lines.

The targeted review makes a separate API call (to a fast model) that
analyses the patient demographics and clinical history to suggest
specific anatomical areas the radiologist should scrutinise.
"""
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import re
import logging

import config_reader
import api_handler

logger = logging.getLogger("report-check")

# Supported modalities for targeted review (CT, MR, PET only)
_DICOM_MODALITY_MAP = {
    "CT": "CT",
    "MR": "MRI",
    "MRI": "MRI",
    "PT": "PET",
    "PET": "PET",
}


def get_targeted_review(report_text, config, config_dir):
    """Get targeted review areas for the given report.

    Returns dict with: success, areas, user_message, demographics_label, error
    """
    if not config_reader.is_targeted_review_enabled(config):
        return {
            "success": False, "areas": [], "user_message": "",
            "demographics_label": "", "error": "Targeted review disabled",
        }

    # Get DICOM demographics (required - no fallback to report parsing)
    demographics = config_reader.read_demographics(config_dir)
    if not demographics.get("success"):
        logger.warning("DICOM demographics unavailable - targeted review requires demographic data")
        return {
            "success": False, "areas": [], "user_message": "",
            "demographics_label": "", "error": "Demographics unavailable",
        }

    demographics_label = config_reader.build_demographics_label(demographics)

    # Check modality support
    modality_check = _check_modality(demographics, report_text)
    if not modality_check["supported"]:
        logger.info("Targeted review skipped - unsupported modality",
                     extra={"modality": modality_check.get("modality", "")})
        return {
            "success": False, "areas": [], "user_message": "",
            "demographics_label": demographics_label,
            "error": "Unsupported modality",
        }

    # Load system prompt
    system_prompt = config_reader.get_targeted_prompt(config_dir)
    if not system_prompt:
        return {
            "success": False, "areas": [], "user_message": "",
            "demographics_label": demographics_label,
            "error": "Targeted review prompt not loaded",
        }

    # Build user prompt
    user_prompt = _build_user_prompt(report_text, demographics)

    # Make API call
    provider = config_reader.get_provider(config)
    api_key = config_reader.get_api_key(config, provider)
    if not api_key:
        return {
            "success": False, "areas": [], "user_message": "",
            "demographics_label": demographics_label,
            "error": "API key not configured",
        }

    model = api_handler.TARGETED_MODELS.get(provider, "")
    logger.info("Requesting targeted review", extra={"provider": provider, "model": model})

    result = api_handler.send_to_api(
        provider, api_key, model, system_prompt, user_prompt,
        max_tokens=api_handler.TARGETED_MAX_TOKENS,
        temperature=api_handler.TARGETED_TEMPERATURE,
    )

    if not result.get("success"):
        return {
            "success": False, "areas": [], "user_message": "",
            "demographics_label": demographics_label,
            "error": result.get("error", "API call failed"),
        }

    # Parse the response
    areas = _parse_targeted_areas(result["response"])

    if areas:
        logger.info("Targeted review parsed successfully", extra={"count": len(areas)})
        return {
            "success": True, "areas": areas, "user_message": "",
            "demographics_label": demographics_label,
        }
    else:
        user_message = "Insufficient clinical information for targeted review advice."
        content = result["response"]
        if any(kw in content.lower() for kw in ("apologize", "need more", "provide more", "incomplete")):
            user_message = "Insufficient clinical information for targeted review advice."
        logger.warning("No targeted areas found in response",
                       extra={"content_length": len(content)})
        return {
            "success": False, "areas": [], "user_message": user_message,
            "demographics_label": demographics_label,
            "error": "Could not parse targeted areas",
        }


def _check_modality(demographics, report_text):
    """Check if modality is supported for targeted review."""
    dicom_mod = demographics.get("Modality", "").upper().strip()
    if dicom_mod and dicom_mod in _DICOM_MODALITY_MAP:
        return {"supported": True, "modality": _DICOM_MODALITY_MAP[dicom_mod]}

    # Fallback: check report text
    if re.search(r"\b(CT|CAT\s*scan|computed\s*tomography)\b", report_text, re.I):
        return {"supported": True, "modality": "CT"}
    if re.search(r"\b(MRI|MR[A-Z]|MR\s|magnetic\s*resonance)\b", report_text, re.I):
        return {"supported": True, "modality": "MRI"}
    if re.search(r"\b(PET|PET[-/]CT|positron)\b", report_text, re.I):
        return {"supported": True, "modality": "PET"}

    return {"supported": False, "modality": dicom_mod or ""}


def _build_user_prompt(report_text, demographics):
    """Build the user prompt for the targeted review API call."""
    # Extract clinical history from report
    raw_history = ""
    m = re.search(
        r"(?i)(Clinical\s*(?:history|details|information)?|History|Indication|"
        r"Reason\s*for\s*(?:exam|study|scan))[\s:]+([^\r\n]+(?:\r?\n(?![A-Z]{2,})[^\r\n]+)*)",
        report_text,
    )
    if m:
        raw_history = m.group(2).strip()
    else:
        raw_history = report_text[:500]

    # Extract body region from report
    body_region = ""
    region_m = re.search(
        r"\b(abdomen|pelvis|abdo|abd|chest|thorax|head|brain|spine|neck|"
        r"extremity|limb|musculoskeletal|MSK)\b",
        report_text, re.I,
    )
    if region_m:
        body_region = region_m.group(1)

    # Build prompt
    prompt = "Generate targeted review areas for this clinical presentation:\n\n"

    age = demographics.get("Age", "")
    sex = demographics.get("Sex", "")
    if age or sex:
        prompt += "Patient: "
        if age:
            prompt += f"{age} "
        if sex:
            prompt += sex
        prompt += "\n"

    modality = demographics.get("Modality", "")
    study_desc = demographics.get("StudyDesc", "")
    if modality or study_desc or body_region:
        prompt += "Study: "
        if modality:
            prompt += f"{modality} "
        if study_desc:
            prompt += study_desc
        elif body_region:
            prompt += body_region
        prompt = prompt.rstrip() + "\n"

    prompt += f"\nClinical History:\n{raw_history}"

    return prompt


def _parse_targeted_areas(content):
    """Parse numbered list of targeted areas from API response.

    Handles multiple formatting styles from different AI models.
    Matches TargetedReviewManager._ParseTargetedAreas() in AHK.
    """
    patterns = [
        # Bold with colon inside: 1. **Area:** Rationale
        r"(\d+)\.\s*\*{2}([^*:]+):\*{2}\s+([^\r\n]+)",
        # Bold with dash/colon after: 1. **Area** - Rationale
        r"(\d+)\.\s*\*{2}([^*]+)\*{2}\s*[-\u2013\u2014:]\s*(.+?)(?=\n\d+\.|\n*$)",
        # Bold with dash (single line)
        r"(\d+)\.\s*\*{2}([^*]+)\*{2}\s*[-\u2013\u2014]\s*([^\r\n]+)",
        # Bold with colon after
        r"(\d+)\.\s*\*{2}([^*]+)\*{2}:\s*([^\r\n]+)",
        # Plain with dash
        r"(\d+)\.\s+(.+?)\s+[-\u2013\u2014]\s+([^\r\n]+)",
        # Plain with colon
        r"(\d+)\.\s+([^:\r\n]+):\s+([^\r\n]+)",
    ]

    for pattern in patterns:
        areas = []
        for m in re.finditer(pattern, content, re.DOTALL):
            num = m.group(1)
            area = m.group(2).strip().strip("*")
            rationale = m.group(3).strip().strip("*")

            if area and rationale and len(area) > 3:
                areas.append({
                    "number": num,
                    "area": area,
                    "rationale": rationale,
                })

        if len(areas) >= 3:
            return areas

    return []
