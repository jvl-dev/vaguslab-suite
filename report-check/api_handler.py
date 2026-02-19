"""
API Handler for Report Check Python Backend

Wraps anthropic, openai, and google-genai SDKs for all three providers.
Replaces APIManager.ahk (777 lines) with ~150 lines.
"""
import sys
import os
import re

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import logging

logger = logging.getLogger("report-check")

# API constants
DEFAULT_MAX_TOKENS = 4000
DEFAULT_TEMPERATURE = 0.2
TARGETED_MAX_TOKENS = 1000
TARGETED_TEMPERATURE = 0.3

# Per-mode parameter profiles
REVIEW_PROFILES = {
    "comprehensive": {"max_tokens": 8000, "temperature": 0.2},
    "proofreading":  {"max_tokens": 4000, "temperature": 0.1},
}

# Targeted review models — cheapest/fastest per provider for demographic extraction.
# Python-only; NOT shown in GUI, NOT in Constants.ahk. Only update when a
# cheaper model becomes available or one is deprecated.
TARGETED_MODELS = {
    "claude": "claude-sonnet-4-20250514",
    "gemini": "gemini-2.5-flash",
    "openai": "gpt-4o",
}


def send_to_api(provider, api_key, model, system_prompt, user_message,
                max_tokens=DEFAULT_MAX_TOKENS, temperature=DEFAULT_TEMPERATURE):
    """Send a request to the specified provider and return the result.

    Returns dict with keys: success, response, provider, model, stop_reason, error
    """
    if provider == "claude":
        return _send_claude(api_key, model, system_prompt, user_message, max_tokens, temperature)
    elif provider == "gemini":
        return _send_gemini(api_key, model, system_prompt, user_message, max_tokens, temperature)
    elif provider == "openai":
        return _send_openai(api_key, model, system_prompt, user_message, max_tokens, temperature)
    else:
        return {"success": False, "error": f"Unknown provider: {provider}"}


def _send_claude(api_key, model, system_prompt, user_message, max_tokens, temperature):
    """Send request to Claude API using the anthropic SDK."""
    try:
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            temperature=temperature,
            system=system_prompt,
            messages=[{"role": "user", "content": user_message}],
        )
        response_text = message.content[0].text
        stop_reason = message.stop_reason  # "end_turn", "max_tokens", etc.

        logger.info("Claude API call successful", extra={
            "model": model, "response_length": len(response_text), "stop_reason": stop_reason
        })

        if stop_reason != "end_turn" and stop_reason:
            logger.warning("Claude response truncated", extra={"stop_reason": stop_reason})

        return {
            "success": True,
            "response": response_text,
            "provider": "Claude",
            "model": model,
            "stop_reason": stop_reason or "",
        }

    except Exception as e:
        error_msg = _translate_claude_error(e)
        logger.error("Claude API call failed", extra={"error": str(e)})
        return {"success": False, "error": error_msg, "provider": "Claude", "model": model}


def _send_gemini(api_key, model, system_prompt, user_message, max_tokens, temperature):
    """Send request to Gemini API using the google-genai SDK."""
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)

        response = client.models.generate_content(
            model=model,
            contents=user_message,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                max_output_tokens=max_tokens,
                temperature=temperature,
                top_p=0.9,
                top_k=40,
                safety_settings=[
                    types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="OFF"),
                    types.SafetySetting(category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="OFF"),
                    types.SafetySetting(category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="OFF"),
                    types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="OFF"),
                ],
            ),
        )

        response_text = response.text
        # Extract finish reason from candidates
        stop_reason = ""
        if response.candidates:
            finish_reason = response.candidates[0].finish_reason
            stop_reason = finish_reason.name if hasattr(finish_reason, "name") else str(finish_reason)

        logger.info("Gemini API call successful", extra={
            "model": model, "response_length": len(response_text), "finish_reason": stop_reason
        })

        if stop_reason not in ("STOP", ""):
            logger.warning("Gemini response truncated", extra={"finish_reason": stop_reason})

        return {
            "success": True,
            "response": response_text,
            "provider": "Gemini",
            "model": model,
            "stop_reason": stop_reason,
        }

    except Exception as e:
        error_msg = _translate_gemini_error(e, model)
        logger.error("Gemini API call failed", extra={"error": str(e)})
        return {"success": False, "error": error_msg, "provider": "Gemini", "model": model}


def _send_openai(api_key, model, system_prompt, user_message, max_tokens, temperature):
    """Send request to OpenAI API using the openai SDK."""
    try:
        import openai

        client = openai.OpenAI(api_key=api_key)
        response = client.chat.completions.create(
            model=model,
            temperature=temperature,
            max_completion_tokens=max_tokens,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_message},
            ],
        )

        response_text = response.choices[0].message.content
        stop_reason = response.choices[0].finish_reason or ""  # "stop", "length", etc.

        logger.info("OpenAI API call successful", extra={
            "model": model, "response_length": len(response_text), "finish_reason": stop_reason
        })

        return {
            "success": True,
            "response": response_text,
            "provider": "OpenAI",
            "model": model,
            "stop_reason": stop_reason,
        }

    except Exception as e:
        error_msg = _translate_openai_error(e)
        logger.error("OpenAI API call failed", extra={"error": str(e)})
        return {"success": False, "error": error_msg, "provider": "OpenAI", "model": model}


# --- Error translation ---

def _translate_error(provider, e, model=""):
    """Route to the appropriate provider-specific error translator."""
    if provider == "claude":
        return _translate_claude_error(e)
    elif provider == "gemini":
        return _translate_gemini_error(e, model)
    elif provider == "openai":
        return _translate_openai_error(e)
    return f"API error: {e}"


def _translate_claude_error(e):
    """Translate anthropic SDK exceptions to user-friendly messages."""
    try:
        import anthropic
        if isinstance(e, anthropic.AuthenticationError):
            return "Authentication failed - check your Claude API key in Settings."
        if isinstance(e, anthropic.RateLimitError):
            # Check for retry-after header hint in the message
            retry_hint = ""
            err_str = str(e)
            retry_match = re.search(r"retry.* (\d+)\s*s", err_str, re.IGNORECASE)
            if retry_match:
                retry_hint = f" Try again in ~{retry_match.group(1)} seconds."
            return f"Rate limit exceeded.{retry_hint} Please wait and try again."
        if isinstance(e, anthropic.APIConnectionError):
            return "Could not connect to Claude API servers."
        if isinstance(e, anthropic.APIStatusError):
            return f"Claude API error (status {e.status_code}): {e.message}"
    except ImportError:
        pass
    return f"Error connecting to Claude API: {e}"


def _translate_gemini_error(e, model=""):
    """Translate google-genai exceptions to user-friendly messages."""
    err_str = str(e)
    err_lower = err_str.lower()
    if "403" in err_lower or "permission" in err_lower:
        return "Authentication failed - check your Gemini API key in Settings."
    if "429" in err_lower or "resource exhausted" in err_lower:
        if "gemini-2.5-pro" in model:
            return (
                "Gemini Pro requires a paid API tier. Options: "
                "(1) Switch to Claude in Settings, "
                "(2) Upgrade your Gemini API plan, or "
                "(3) Use Proofreading mode (uses Gemini Flash)"
            )
        # Extract retry delay if present (e.g. "Please retry in 17.818436202s")
        retry_hint = ""
        retry_match = re.search(r"retry in ([\d.]+)s", err_str, re.IGNORECASE)
        if retry_match:
            retry_secs = int(float(retry_match.group(1)) + 0.5)
            retry_hint = f" Try again in ~{retry_secs} seconds."
        # Detect free tier quota
        if "free_tier" in err_lower:
            return f"Gemini free tier rate limit reached.{retry_hint} To avoid this, upgrade your Gemini API plan or switch to Claude in Settings."
        return f"Rate limit exceeded.{retry_hint} Please wait and try again."
    if "400" in err_lower:
        return "Bad request - check your Gemini API configuration."
    if "500" in err_lower or "503" in err_lower:
        return "Gemini API server error - please try again later."
    return f"Error connecting to Gemini API: {e}"


def _translate_openai_error(e):
    """Translate openai SDK exceptions to user-friendly messages."""
    try:
        import openai
        if isinstance(e, openai.AuthenticationError):
            return "Authentication failed - check your OpenAI API key in Settings."
        if isinstance(e, openai.RateLimitError):
            err_str = str(e).lower()
            if "insufficient_quota" in err_str or "exceeded your current quota" in err_str:
                return "OpenAI quota exceeded. Check your billing details at platform.openai.com."
            return "Rate limit exceeded. Please wait and try again."
        if isinstance(e, openai.APIConnectionError):
            return "Could not connect to OpenAI API servers."
        if isinstance(e, openai.BadRequestError):
            return f"Bad request: {e.message}"
        if isinstance(e, openai.APIStatusError):
            return f"OpenAI API error (status {e.status_code}): {e.message}"
    except ImportError:
        pass
    return f"Error connecting to OpenAI API: {e}"


# --- Multi-turn conversation support ---


def send_to_api_multiturn(provider, api_key, model, system_prompt, messages,
                          max_tokens=DEFAULT_MAX_TOKENS, temperature=DEFAULT_TEMPERATURE):
    """Send a multi-turn conversation request.

    Args:
        messages: list of {role, content} dicts (full conversation history)

    Returns dict with keys: success, response, provider, model, stop_reason, error
    """
    if provider == "claude":
        return _send_claude_multiturn(api_key, model, system_prompt, messages, max_tokens, temperature)
    elif provider == "gemini":
        return _send_gemini_multiturn(api_key, model, system_prompt, messages, max_tokens, temperature)
    elif provider == "openai":
        return _send_openai_multiturn(api_key, model, system_prompt, messages, max_tokens, temperature)
    else:
        return {"success": False, "error": f"Unknown provider: {provider}"}


def _send_claude_multiturn(api_key, model, system_prompt, messages, max_tokens, temperature):
    try:
        import anthropic
        client = anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            temperature=temperature,
            system=system_prompt,
            messages=messages,
        )
        response_text = message.content[0].text
        stop_reason = message.stop_reason
        return {
            "success": True, "response": response_text,
            "provider": "Claude", "model": model, "stop_reason": stop_reason or "",
        }
    except Exception as e:
        return {"success": False, "error": _translate_claude_error(e), "provider": "Claude", "model": model}


def _send_gemini_multiturn(api_key, model, system_prompt, messages, max_tokens, temperature):
    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)
        contents = _build_gemini_contents(messages)

        response = client.models.generate_content(
            model=model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                max_output_tokens=max_tokens,
                temperature=temperature,
                top_p=0.9,
                top_k=40,
                safety_settings=[
                    types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="OFF"),
                    types.SafetySetting(category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="OFF"),
                    types.SafetySetting(category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="OFF"),
                    types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="OFF"),
                ],
            ),
        )
        response_text = response.text
        stop_reason = ""
        if response.candidates:
            finish_reason = response.candidates[0].finish_reason
            stop_reason = finish_reason.name if hasattr(finish_reason, "name") else str(finish_reason)
        return {
            "success": True, "response": response_text,
            "provider": "Gemini", "model": model, "stop_reason": stop_reason,
        }
    except Exception as e:
        return {"success": False, "error": _translate_gemini_error(e, model), "provider": "Gemini", "model": model}


def _send_openai_multiturn(api_key, model, system_prompt, messages, max_tokens, temperature):
    try:
        import openai
        client = openai.OpenAI(api_key=api_key)
        full_messages = [{"role": "system", "content": system_prompt}] + messages
        response = client.chat.completions.create(
            model=model,
            temperature=temperature,
            max_completion_tokens=max_tokens,
            messages=full_messages,
        )
        response_text = response.choices[0].message.content
        stop_reason = response.choices[0].finish_reason or ""
        return {
            "success": True, "response": response_text,
            "provider": "OpenAI", "model": model, "stop_reason": stop_reason,
        }
    except Exception as e:
        return {"success": False, "error": _translate_openai_error(e), "provider": "OpenAI", "model": model}


def _build_gemini_contents(messages):
    """Build Gemini contents list from standard {role, content} messages."""
    from google.genai import types

    contents = []
    for msg in messages:
        role = "model" if msg["role"] == "assistant" else "user"
        contents.append(types.Content(
            role=role,
            parts=[types.Part(text=msg["content"])],
        ))
    return contents


# --- Streaming support ---


def stream_to_api(provider, api_key, model, system_prompt, messages,
                  output_file, status_file,
                  max_tokens=DEFAULT_MAX_TOKENS, temperature=DEFAULT_TEMPERATURE):
    """Stream a multi-turn response, writing tokens to output_file.

    Writes each chunk to output_file with flush().
    On completion, writes {"done": true, "error": null} to status_file.
    On error, writes {"done": true, "error": "..."} to status_file.
    """
    from pathlib import Path
    import json

    try:
        if provider == "claude":
            _stream_claude(api_key, model, system_prompt, messages, output_file, max_tokens, temperature)
        elif provider == "openai":
            _stream_openai(api_key, model, system_prompt, messages, output_file, max_tokens, temperature)
        elif provider == "gemini":
            _stream_gemini(api_key, model, system_prompt, messages, output_file, max_tokens, temperature)
        else:
            raise ValueError(f"Unknown provider: {provider}")

        Path(status_file).write_text(
            json.dumps({"done": True, "error": None}), encoding="utf-8"
        )
        logger.info("Streaming completed successfully", extra={"provider": provider})

    except Exception as e:
        error_msg = _translate_error(provider, e, model)
        logger.error("Streaming failed", extra={"provider": provider, "error": str(e)})
        Path(status_file).write_text(
            json.dumps({"done": True, "error": error_msg}), encoding="utf-8"
        )


def _stream_claude(api_key, model, system_prompt, messages, output_file, max_tokens, temperature):
    import anthropic
    client = anthropic.Anthropic(api_key=api_key)

    with client.messages.stream(
        model=model,
        max_tokens=max_tokens,
        temperature=temperature,
        system=system_prompt,
        messages=messages,
    ) as stream:
        with open(output_file, "w", encoding="utf-8") as f:
            for text in stream.text_stream:
                f.write(text)
                f.flush()


def _stream_openai(api_key, model, system_prompt, messages, output_file, max_tokens, temperature):
    import openai
    client = openai.OpenAI(api_key=api_key)

    full_messages = [{"role": "system", "content": system_prompt}] + messages
    stream = client.chat.completions.create(
        model=model,
        temperature=temperature,
        max_completion_tokens=max_tokens,
        messages=full_messages,
        stream=True,
    )

    with open(output_file, "w", encoding="utf-8") as f:
        for chunk in stream:
            if chunk.choices and chunk.choices[0].delta.content:
                f.write(chunk.choices[0].delta.content)
                f.flush()


def _stream_gemini(api_key, model, system_prompt, messages, output_file, max_tokens, temperature):
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=api_key)
    contents = _build_gemini_contents(messages)

    response = client.models.generate_content_stream(
        model=model,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=system_prompt,
            max_output_tokens=max_tokens,
            temperature=temperature,
            top_p=0.9,
            top_k=40,
            safety_settings=[
                types.SafetySetting(category="HARM_CATEGORY_HATE_SPEECH", threshold="OFF"),
                types.SafetySetting(category="HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold="OFF"),
                types.SafetySetting(category="HARM_CATEGORY_DANGEROUS_CONTENT", threshold="OFF"),
                types.SafetySetting(category="HARM_CATEGORY_HARASSMENT", threshold="OFF"),
            ],
        ),
    )

    with open(output_file, "w", encoding="utf-8") as f:
        for chunk in response:
            if chunk.text:
                f.write(chunk.text)
                f.flush()
