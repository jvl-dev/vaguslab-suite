"""
Session Manager for Report Check Multi-Turn Conversations

Manages ephemeral conversation sessions stored as JSON files.
Each session tracks message history and provider-specific metadata.
Sessions are auto-cleaned after 24 hours.
"""
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import json
import logging
import uuid
from datetime import datetime, timedelta
from pathlib import Path

logger = logging.getLogger("report-check")

SESSIONS_DIR = os.path.join(os.environ.get("TEMP", "/tmp"), "ReportCheck", "sessions")


def _ensure_dir():
    os.makedirs(SESSIONS_DIR, exist_ok=True)


def _session_path(session_id):
    return os.path.join(SESSIONS_DIR, f"{session_id}.json")


def create_session(system_prompt, provider, model, mode, original_report):
    """Create a new conversation session.

    Returns the session_id string.
    """
    _ensure_dir()
    session_id = uuid.uuid4().hex[:16]

    session = {
        "id": session_id,
        "provider": provider,
        "model": model,
        "mode": mode,
        "system_prompt": system_prompt,
        "original_report": original_report,
        "messages": [],
        "created_at": datetime.now().isoformat(),
    }

    path = _session_path(session_id)
    Path(path).write_text(json.dumps(session, ensure_ascii=False), encoding="utf-8")
    logger.info("Session created", extra={"session_id": session_id})
    return session_id


def load(session_id):
    """Load a session by ID. Returns the session dict or None."""
    path = _session_path(session_id)
    if not os.path.exists(path):
        logger.warning("Session not found", extra={"session_id": session_id})
        return None
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        logger.error("Failed to load session", extra={"session_id": session_id, "error": str(e)})
        return None


def save(session):
    """Save a session dict back to disk."""
    _ensure_dir()
    path = _session_path(session["id"])
    Path(path).write_text(json.dumps(session, ensure_ascii=False), encoding="utf-8")


def add_turn(session_id, role, content):
    """Append a message turn to the session and save."""
    session = load(session_id)
    if not session:
        return False
    session["messages"].append({"role": role, "content": content})
    save(session)
    return True


def build_messages_for_provider(session):
    """Translate session messages to the provider's expected format.

    Returns:
        For Claude: list of {role, content} dicts (system prompt handled separately)
        For OpenAI: list of {role, content} dicts (system message prepended by caller)
        For Gemini: list of {role, content} dicts (translated by streaming/API layer)

    All providers use the same internal format; the API layer handles
    provider-specific translation (system message placement, role names, etc.)
    """
    return list(session["messages"])


def cleanup_old_sessions(max_age_hours=24):
    """Delete session files older than max_age_hours."""
    _ensure_dir()
    cutoff = datetime.now() - timedelta(hours=max_age_hours)
    cleaned = 0

    try:
        for f in Path(SESSIONS_DIR).glob("*.json"):
            try:
                mtime = datetime.fromtimestamp(f.stat().st_mtime)
                if mtime < cutoff:
                    f.unlink()
                    cleaned += 1
            except OSError:
                pass
    except Exception:
        pass

    if cleaned:
        logger.info("Cleaned old sessions", extra={"count": cleaned})
    return cleaned
