"""
Report Check Python Backend — Entry Point

Called by AHK via subprocess:
    python.exe backend.py <request_json_path>

Reads request, performs API call + targeted review + HTML generation,
writes response JSON to the same directory.
"""
import sys
import os

# Add app root to sys.path so sibling modules resolve (required for shared Python install)
script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import json
import traceback
from pathlib import Path

# Import project modules (after sys.path setup)
from logger import setup_logging
import config_reader
import api_handler
import html_generator
import targeted_review
import session_manager
import utils

VERSION = "0.30.2"


def main():
    request_path = Path(sys.argv[1])
    request = json.loads(request_path.read_text(encoding="utf-8"))
    response_path = request_path.with_name("response.json")

    # Setup logging early
    config_path = request.get("config_path", "")
    debug = False
    try:
        if config_path and os.path.exists(config_path):
            cfg = config_reader.read_config(config_path)
            debug = cfg.get("settings", {}).get("debug_logging", False)
    except Exception:
        pass
    logger = setup_logging(debug=debug)
    logger.info("Backend invoked", extra={"command": request.get("command")})

    try:
        command = request.get("command", "")
        if command == "review":
            result = handle_review(request)
        elif command == "test_api_key":
            result = handle_test_api_key(request)
        elif command == "follow_up":
            result = handle_follow_up(request)
        elif command == "stream_follow_up":
            result = handle_stream_follow_up(request)
        elif command == "stream_review":
            result = handle_stream_review(request)
        else:
            result = {"success": False, "error": f"Unknown command: {command}"}

        response_path.write_text(
            json.dumps(result, ensure_ascii=False), encoding="utf-8"
        )

    except Exception as e:
        logger.error(f"Unhandled exception: {e}\n{traceback.format_exc()}")
        error_response = {"success": False, "error": str(e)}
        response_path.write_text(json.dumps(error_response), encoding="utf-8")


def handle_review(request):
    """Handle the 'review' command — main review flow."""
    logger = setup_logging()

    # Read config
    config_path = request.get("config_path", "")
    if not config_path or not os.path.exists(config_path):
        return {"success": False, "error": "Config file not found"}
    config = config_reader.read_config(config_path)
    config_dir = os.path.dirname(config_path)

    # Read report text (from file to avoid JSON escaping issues)
    report_text_file = request.get("report_text_file", "")
    if report_text_file and os.path.exists(report_text_file):
        with open(report_text_file, encoding="utf-8") as f:
            original_report = f.read()
    else:
        # Fallback: report text directly in JSON
        original_report = request.get("report_text", "")

    if not original_report.strip():
        return {"success": False, "error": "No report text provided"}

    mode_override = request.get("mode_override", "")
    mode = config_reader.get_mode(config, mode_override)
    provider = config_reader.get_provider(config)
    api_key = config_reader.get_api_key(config, provider)

    if not api_key:
        return {
            "success": False,
            "error": f"{provider.title()} API key not configured. Open Settings to configure it.",
        }

    model = config_reader.get_model(config, provider, mode_override)
    system_prompt = config_reader.get_prompt(config_dir, mode_override, config)

    logger.info("Starting review", extra={
        "provider": provider, "model": model, "mode": mode,
        "report_length": len(original_report),
    })

    # --- Prepare report text with demographics and date verification ---
    analysis_demographics_label = ""
    report_with_context = original_report

    if config_reader.is_demographic_extraction_enabled(config):
        try:
            demographics = config_reader.read_demographics(config_dir)
            if demographics.get("success"):
                demo_str = config_reader.format_demographics_string(demographics)
                if demo_str:
                    report_with_context = demo_str + "\n\n" + report_with_context
                    logger.info("Demographics prepended to report", extra={"demographics": demo_str})
                analysis_demographics_label = config_reader.build_demographics_label(demographics)
        except Exception:
            pass  # Non-fatal

    # Pre-verify dates
    date_verification = utils.pre_verify_dates(original_report)
    if date_verification:
        report_with_context = date_verification + "\n\n" + report_with_context
        logger.info("Date verification prepended to report")

    # --- Build user message ---
    if mode == "proofreading":
        user_message = "Check this radiology report for errors according to your instructions:\n\n" + report_with_context
    else:
        user_message = "Please review this radiology report:\n\n" + report_with_context

    # --- Main API call (with per-mode parameters) ---
    profile = api_handler.REVIEW_PROFILES.get(mode, {})
    api_result = api_handler.send_to_api(
        provider, api_key, model, system_prompt, user_message,
        max_tokens=profile.get("max_tokens", api_handler.DEFAULT_MAX_TOKENS),
        temperature=profile.get("temperature", api_handler.DEFAULT_TEMPERATURE),
    )

    if not api_result.get("success"):
        return {
            "success": False,
            "error": api_result.get("error", "API call failed"),
            "provider": api_result.get("provider", provider),
            "model": api_result.get("model", model),
        }

    # --- Targeted review (if enabled and comprehensive mode) ---
    targeted_areas = []
    targeted_user_message = ""
    targeted_demographics_label = ""

    if config_reader.is_targeted_review_enabled(config) and mode == "comprehensive":
        logger.info("Getting targeted review...")
        try:
            tr_result = targeted_review.get_targeted_review(
                original_report, config, config_dir
            )
            if tr_result.get("success") and tr_result.get("areas"):
                targeted_areas = tr_result["areas"]
                targeted_demographics_label = tr_result.get("demographics_label", "")
                logger.info("Targeted review obtained", extra={"count": len(targeted_areas)})
            else:
                targeted_user_message = tr_result.get("user_message", "")
                targeted_demographics_label = tr_result.get("demographics_label", "")
        except Exception as e:
            logger.warning(f"Targeted review failed: {e}")

    # --- Create conversation session ---
    session_id = ""
    try:
        session_id = session_manager.create_session(
            system_prompt=system_prompt,
            provider=provider,
            model=model,
            mode=mode,
            original_report=original_report,
        )
        # Add initial conversation turns
        session_manager.add_turn(session_id, "user", user_message)
        session_manager.add_turn(session_id, "assistant", api_result["response"])
        logger.info("Session created for review", extra={"session_id": session_id})
    except Exception as e:
        logger.warning(f"Session creation failed (non-fatal): {e}")
        session_id = ""

    # Clean up old sessions (non-blocking, best effort)
    try:
        session_manager.cleanup_old_sessions()
    except Exception:
        pass

    # --- Generate HTML ---
    try:
        html_file = html_generator.generate_html_file(
            original_report=original_report,
            ai_response=api_result["response"],
            mode=mode,
            model=api_result.get("model", model),
            stop_reason=api_result.get("stop_reason", ""),
            targeted_areas=targeted_areas,
            targeted_user_message=targeted_user_message,
            targeted_demographics_label=targeted_demographics_label,
            analysis_demographics_label=analysis_demographics_label,
            version=request.get("version", VERSION),
            session_id=session_id,
        )
    except Exception as e:
        logger.error(f"HTML generation failed: {e}")
        return {
            "success": True,
            "response": api_result["response"],
            "provider": api_result.get("provider", ""),
            "model": api_result.get("model", model),
            "stop_reason": api_result.get("stop_reason", ""),
            "html_file": "",
            "error": f"HTML generation failed: {e}",
        }

    # --- Build response ---
    return {
        "success": True,
        "response": api_result["response"],
        "provider": api_result.get("provider", ""),
        "model": api_result.get("model", model),
        "stop_reason": api_result.get("stop_reason", ""),
        "targeted_areas": targeted_areas,
        "targeted_user_message": targeted_user_message,
        "targeted_demographics_label": targeted_demographics_label,
        "analysis_demographics_label": analysis_demographics_label,
        "html_file": html_file,
        "session_id": session_id,
        "error": None,
    }


def handle_test_api_key(request):
    """Handle the 'test_api_key' command — verify API key works."""
    logger = setup_logging()

    config_path = request.get("config_path", "")
    if not config_path or not os.path.exists(config_path):
        return {"success": False, "error": "Config file not found"}

    config = config_reader.read_config(config_path)
    provider = request.get("provider", config_reader.get_provider(config))
    api_key = request.get("api_key", "") or config_reader.get_api_key(config, provider)

    if not api_key:
        return {"success": False, "error": "No API key provided"}

    # Cheapest model per provider for API key validation.
    # Python-only; NOT in Constants.ahk. Only update when a cheaper model
    # becomes available or one is deprecated.
    test_models = {
        "claude": "claude-haiku-4-5-20251001",
        "gemini": "gemini-2.5-flash",
        "openai": "gpt-4o-mini",
    }
    model = test_models.get(provider, "")

    result = api_handler.send_to_api(
        provider, api_key, model,
        system_prompt="You are a test assistant.",
        user_message="Reply with exactly: API key verified.",
        max_tokens=20,
        temperature=0.0,
    )

    if result.get("success"):
        return {"success": True, "provider": provider, "model": model}
    else:
        return {"success": False, "error": result.get("error", "Unknown error")}


def handle_stream_review(request):
    """Handle the 'stream_review' command — streaming initial review.

    Streams the AI response to stream_file, then does targeted review,
    session creation, and HTML generation. Writes final status to status_file
    with html_file and session_id.
    """
    logger = setup_logging()

    stream_file = request.get("stream_file", "")
    status_file = request.get("status_file", "")

    def _write_error(msg):
        """Helper to write error to status file and return error dict."""
        if status_file:
            Path(status_file).write_text(
                json.dumps({"done": True, "error": msg, "html_file": "", "session_id": ""}),
                encoding="utf-8",
            )
        return {"success": False, "error": msg}

    if not stream_file or not status_file:
        return _write_error("Missing stream_file or status_file parameters")

    # --- Same setup as handle_review ---
    config_path = request.get("config_path", "")
    if not config_path or not os.path.exists(config_path):
        return _write_error("Config file not found")
    config = config_reader.read_config(config_path)
    config_dir = os.path.dirname(config_path)

    report_text_file = request.get("report_text_file", "")
    if report_text_file and os.path.exists(report_text_file):
        with open(report_text_file, encoding="utf-8") as f:
            original_report = f.read()
    else:
        original_report = request.get("report_text", "")

    if not original_report.strip():
        return _write_error("No report text provided")

    mode_override = request.get("mode_override", "")
    mode = config_reader.get_mode(config, mode_override)
    provider = config_reader.get_provider(config)
    api_key = config_reader.get_api_key(config, provider)

    if not api_key:
        return _write_error(
            f"{provider.title()} API key not configured. Open Settings to configure it."
        )

    model = config_reader.get_model(config, provider, mode_override)
    system_prompt = config_reader.get_prompt(config_dir, mode_override, config)

    logger.info("Starting streaming review", extra={
        "provider": provider, "model": model, "mode": mode,
        "report_length": len(original_report),
    })

    # --- Prepare report text (demographics + date verification) ---
    analysis_demographics_label = ""
    report_with_context = original_report

    if config_reader.is_demographic_extraction_enabled(config):
        try:
            demographics = config_reader.read_demographics(config_dir)
            if demographics.get("success"):
                demo_str = config_reader.format_demographics_string(demographics)
                if demo_str:
                    report_with_context = demo_str + "\n\n" + report_with_context
                analysis_demographics_label = config_reader.build_demographics_label(demographics)
        except Exception:
            pass

    date_verification = utils.pre_verify_dates(original_report)
    if date_verification:
        report_with_context = date_verification + "\n\n" + report_with_context

    # --- Build user message ---
    if mode == "proofreading":
        user_message = "Check this radiology report for errors according to your instructions:\n\n" + report_with_context
    else:
        user_message = "Please review this radiology report:\n\n" + report_with_context

    # --- Stream the API response ---
    profile = api_handler.REVIEW_PROFILES.get(mode, {})
    api_status_file = stream_file + ".api_done"

    api_handler.stream_to_api(
        provider, api_key, model, system_prompt,
        [{"role": "user", "content": user_message}],
        stream_file, api_status_file,
        max_tokens=profile.get("max_tokens", api_handler.DEFAULT_MAX_TOKENS),
        temperature=profile.get("temperature", api_handler.DEFAULT_TEMPERATURE),
    )

    # Check if API streaming succeeded
    try:
        api_status = json.loads(Path(api_status_file).read_text(encoding="utf-8"))
    except Exception as e:
        return _write_error(f"Failed to read API status: {e}")
    finally:
        try:
            Path(api_status_file).unlink()
        except OSError:
            pass

    if api_status.get("error"):
        return _write_error(api_status["error"])

    # Read the full streamed response
    try:
        ai_response = Path(stream_file).read_text(encoding="utf-8")
    except Exception as e:
        return _write_error(f"Failed to read streamed response: {e}")

    if not ai_response.strip():
        return _write_error("Empty response from API")

    logger.info("Streaming API call completed", extra={
        "provider": provider, "model": model,
        "response_length": len(ai_response),
    })

    # --- Targeted review (if enabled and comprehensive mode) ---
    targeted_areas = []
    targeted_user_message = ""
    targeted_demographics_label = ""

    if config_reader.is_targeted_review_enabled(config) and mode == "comprehensive":
        logger.info("Getting targeted review...")
        try:
            tr_result = targeted_review.get_targeted_review(
                original_report, config, config_dir
            )
            if tr_result.get("success") and tr_result.get("areas"):
                targeted_areas = tr_result["areas"]
                targeted_demographics_label = tr_result.get("demographics_label", "")
            else:
                targeted_user_message = tr_result.get("user_message", "")
                targeted_demographics_label = tr_result.get("demographics_label", "")
        except Exception as e:
            logger.warning(f"Targeted review failed: {e}")

    # --- Create conversation session ---
    session_id = ""
    try:
        session_id = session_manager.create_session(
            system_prompt=system_prompt,
            provider=provider,
            model=model,
            mode=mode,
            original_report=original_report,
        )
        session_manager.add_turn(session_id, "user", user_message)
        session_manager.add_turn(session_id, "assistant", ai_response)
    except Exception as e:
        logger.warning(f"Session creation failed (non-fatal): {e}")
        session_id = ""

    try:
        session_manager.cleanup_old_sessions()
    except Exception:
        pass

    # --- Generate HTML ---
    try:
        html_file = html_generator.generate_html_file(
            original_report=original_report,
            ai_response=ai_response,
            mode=mode,
            model=model,
            stop_reason="",
            targeted_areas=targeted_areas,
            targeted_user_message=targeted_user_message,
            targeted_demographics_label=targeted_demographics_label,
            analysis_demographics_label=analysis_demographics_label,
            version=request.get("version", VERSION),
            session_id=session_id,
        )
    except Exception as e:
        logger.error(f"HTML generation failed: {e}")
        html_file = ""

    # --- Write final status file ---
    Path(status_file).write_text(
        json.dumps({
            "done": True,
            "error": None,
            "html_file": html_file,
            "session_id": session_id,
        }),
        encoding="utf-8",
    )

    logger.info("Streaming review complete", extra={
        "session_id": session_id, "html_file": html_file,
    })

    return {
        "success": True,
        "html_file": html_file,
        "session_id": session_id,
    }


def handle_follow_up(request):
    """Handle the 'follow_up' command — blocking multi-turn follow-up."""
    logger = setup_logging()

    session_id = request.get("session_id", "")
    user_message = request.get("user_message", "")
    config_path = request.get("config_path", "")

    if not session_id:
        return {"success": False, "error": "No session ID provided"}
    if not user_message.strip():
        return {"success": False, "error": "Empty follow-up message"}

    session = session_manager.load(session_id)
    if not session:
        return {"success": False, "error": "Session not found or expired"}

    # Read config for API key
    if not config_path or not os.path.exists(config_path):
        return {"success": False, "error": "Config file not found"}
    config = config_reader.read_config(config_path)

    provider = session["provider"]
    api_key = config_reader.get_api_key(config, provider)
    if not api_key:
        return {"success": False, "error": f"API key not configured for {provider}"}

    # Add user turn
    session_manager.add_turn(session_id, "user", user_message)

    # Reload session to get updated messages
    session = session_manager.load(session_id)
    messages = session_manager.build_messages_for_provider(session)

    logger.info("Follow-up request", extra={
        "session_id": session_id, "provider": provider,
        "turn_count": len(messages),
    })

    # Call API with full conversation history
    api_result = api_handler.send_to_api_multiturn(
        provider, api_key, session["model"],
        session["system_prompt"], messages,
    )

    if not api_result.get("success"):
        return {
            "success": False,
            "error": api_result.get("error", "API call failed"),
            "session_id": session_id,
        }

    # Add assistant turn
    session_manager.add_turn(session_id, "assistant", api_result["response"])

    # Convert markdown to HTML for display
    response_html = html_generator.convert_markdown_to_html(api_result["response"])

    return {
        "success": True,
        "response": api_result["response"],
        "response_html": response_html,
        "session_id": session_id,
        "provider": api_result.get("provider", provider),
        "model": api_result.get("model", session["model"]),
    }


def handle_stream_follow_up(request):
    """Handle the 'stream_follow_up' command — streaming multi-turn follow-up.

    Writes tokens to stream_file as they arrive.
    Writes status to status_file on completion/error.
    """
    logger = setup_logging()

    session_id = request.get("session_id", "")
    user_message = request.get("user_message", "")
    stream_file = request.get("stream_file", "")
    status_file = request.get("status_file", "")
    config_path = request.get("config_path", "")

    if not session_id or not stream_file or not status_file:
        error_msg = "Missing required parameters for stream_follow_up"
        if status_file:
            Path(status_file).write_text(
                json.dumps({"done": True, "error": error_msg}), encoding="utf-8"
            )
        return {"success": False, "error": error_msg}

    if not user_message.strip():
        Path(status_file).write_text(
            json.dumps({"done": True, "error": "Empty follow-up message"}),
            encoding="utf-8",
        )
        return {"success": False, "error": "Empty follow-up message"}

    session = session_manager.load(session_id)
    if not session:
        Path(status_file).write_text(
            json.dumps({"done": True, "error": "Session not found or expired"}),
            encoding="utf-8",
        )
        return {"success": False, "error": "Session not found or expired"}

    # Read config for API key
    if not config_path or not os.path.exists(config_path):
        Path(status_file).write_text(
            json.dumps({"done": True, "error": "Config file not found"}),
            encoding="utf-8",
        )
        return {"success": False, "error": "Config file not found"}

    config = config_reader.read_config(config_path)
    provider = session["provider"]
    api_key = config_reader.get_api_key(config, provider)

    if not api_key:
        error_msg = f"API key not configured for {provider}"
        Path(status_file).write_text(
            json.dumps({"done": True, "error": error_msg}), encoding="utf-8"
        )
        return {"success": False, "error": error_msg}

    # Add user turn
    session_manager.add_turn(session_id, "user", user_message)

    # Reload session to get updated messages
    session = session_manager.load(session_id)
    messages = session_manager.build_messages_for_provider(session)

    logger.info("Streaming follow-up", extra={
        "session_id": session_id, "provider": provider,
        "turn_count": len(messages),
    })

    # Stream the response (blocks until complete, writes to files)
    api_handler.stream_to_api(
        provider, api_key, session["model"],
        session["system_prompt"], messages,
        stream_file, status_file,
    )

    # After streaming completes, save the full response to the session
    try:
        full_response = Path(stream_file).read_text(encoding="utf-8")
        if full_response:
            session_manager.add_turn(session_id, "assistant", full_response)
            logger.info("Streaming follow-up saved to session", extra={
                "session_id": session_id,
                "response_length": len(full_response),
            })
    except Exception as e:
        logger.warning(f"Failed to save streamed response to session: {e}")

    return {"success": True, "session_id": session_id}


if __name__ == "__main__":
    main()
