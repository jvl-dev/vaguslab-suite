"""
HTML Generator for Report Check Python Backend

Converts markdown AI response to HTML, renders the report template,
and writes the final HTML file. Replaces ~300 lines of AHK HTML
generation code and TemplateManager.ahk (133 lines).
"""
import sys
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

import re
import logging
from datetime import datetime
from pathlib import Path

from utils import escape_html

logger = logging.getLogger("report-check")

# Version injected by backend.py at call time
_VERSION = "0.21.7"


def generate_html_file(
    original_report,
    ai_response,
    mode,
    model,
    stop_reason="",
    targeted_areas=None,
    targeted_user_message="",
    targeted_demographics_label="",
    analysis_demographics_label="",
    version="0.21.7",
    output_dir=None,
    session_id="",
):
    """Generate the complete HTML review file and return its path.

    This is the main entry point. It:
    1. Cleans/formats the AI response
    2. Converts markdown to HTML
    3. Formats the original report
    4. Builds metadata
    5. Generates targeted review section
    6. Renders the template
    7. Writes the HTML file
    """
    global _VERSION
    _VERSION = version

    if output_dir is None:
        output_dir = os.path.join(os.environ.get("TEMP", "/tmp"), "RadReviewResults")
    os.makedirs(output_dir, exist_ok=True)

    # Clean and format AI response
    cleaned_response, prompt_status = _clean_ai_response(ai_response)
    ai_html = convert_markdown_to_html(cleaned_response)

    # Format original report
    formatted_original = _format_original_report(original_report)
    escaped_original = escape_html(formatted_original)

    # Build metadata
    metadata_html = _build_metadata_html(
        mode, model, len(original_report), stop_reason, prompt_status
    )

    # Build targeted review section
    targeted_html = _build_targeted_review_html(
        targeted_areas or [], targeted_user_message, targeted_demographics_label
    )

    # Build analysis demographics
    analysis_demo_html = ""
    if analysis_demographics_label:
        analysis_demo_html = (
            f'<span class="demographics-label">'
            f"{escape_html(analysis_demographics_label)}</span>"
        )

    # Build follow-up section
    follow_up_html = _build_follow_up_section(session_id)

    # Render template
    html_content = _render_template(
        metadata_html, ai_html, escaped_original,
        targeted_html, analysis_demo_html, version,
        follow_up_html,
    )

    # Write file
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    html_file = os.path.join(output_dir, f"review_simple_{timestamp}.html")
    with open(html_file, "w", encoding="utf-8") as f:
        f.write(html_content)

    # Cleanup old files
    _cleanup_old_reviews(output_dir)

    logger.info("HTML file generated", extra={"path": html_file})
    return html_file


def convert_markdown_to_html(text):
    """Convert markdown text to HTML (matching AHK ConvertMarkdownToHTML).

    Handles headers, bold, italic, code, bullet/numbered lists, and paragraphs.
    """
    html = text

    # Normalize line endings
    html = html.replace("\r\n", "\n")

    # Remove duplicate top-level headers from AI output
    html = re.sub(
        r"(?m)^#{1,3}\s*(Radiology Report Review|AI Report Check)\s*$", "", html
    )

    # Handle headers (process ### before ## before #)
    html = re.sub(
        r"(?m)^#{3}\s*(.+?)$", r'<h3 class="section-header">\1</h3>', html
    )
    html = re.sub(
        r"(?m)^#{2}\s*(.+?)$", r'<h2 class="section-header">\2</h2>' if False else r'<h2 class="section-header">\1</h2>', html
    )
    html = re.sub(
        r"(?m)^#{1}\s*(.+?)$", r'<h1 class="section-header">\1</h1>', html
    )

    # Handle bold, italic, code
    html = re.sub(r"\*\*([^*]+)\*\*", r'<strong class="highlight">\1</strong>', html)
    html = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", html)
    html = re.sub(r"`([^`]+)`", r"<code>\1</code>", html)

    # Process lines for list handling
    lines = html.split("\n")
    result = []
    in_list = False

    for line in lines:
        stripped = line.strip()

        # Markdown horizontal rules (---, ***, ___) — strip them;
        # section headers already provide visual separation
        if re.match(r"^[-*_]{3,}$", stripped):
            continue

        # Already a header tag
        if re.match(r"^<h[1-6]", stripped):
            if in_list:
                result.append("</ul>")
                in_list = False
            result.append(stripped)

        # Bullet points (-, *, +)
        elif m := re.match(r"^[-*+]\s+(.+)$", stripped):
            if not in_list:
                result.append('<ul class="review-list">')
                in_list = True
            result.append(f"<li>{m.group(1)}</li>")

        # Numbered lists
        elif m := re.match(r"^\d+\.\s+(.+)$", stripped):
            if not in_list:
                result.append('<ul class="review-list">')
                in_list = True
            result.append(f"<li>{m.group(1)}</li>")

        # Regular content
        elif stripped and stripped != ".":
            if not re.match(r"^\s", stripped) and len(stripped) > 10:
                if in_list:
                    result.append("</ul>")
                    in_list = False
            result.append(f"<p>{stripped}</p>")

        else:
            # Empty line - preserve spacing
            result.append("")

    if in_list:
        result.append("</ul>")

    output = "\n".join(result)

    # Post-processing: remove highlight class from list item labels ending with colon
    output = re.sub(
        r'(<li><strong) class="highlight"([^>]*>[^<]*?:)',
        r"\1\2",
        output,
    )

    return output


# --- Internal helpers ---


def _clean_ai_response(response):
    """Clean and format AI response for HTML display.

    Returns (cleaned_html, prompt_status_string).
    Matches CleanAndFormatAIResponse() in AHK.
    """
    # Check prompt receipt
    prompt_status = (
        " | \u2705 Prompt OK"
        if "Full prompt received" in response
        else " | \u26a0\ufe0f Prompt Issue"
    )

    # Remove "Full prompt received"
    cleaned = response.replace("Full prompt received", "")
    cleaned = re.sub(r"^\s*\n*", "", cleaned)

    # Unescape API entities (SDKs return clean text, but some models may include these)
    cleaned = cleaned.replace('\\"', '"')
    cleaned = cleaned.replace("&quot;", '"')
    cleaned = cleaned.replace("&amp;", "&")
    cleaned = cleaned.replace("&lt;", "<")
    cleaned = cleaned.replace("&gt;", ">")

    return cleaned, prompt_status


def _format_original_report(text):
    """Format original report text for HTML display.

    Matches FormatOriginalReportForHTML() in AHK.
    """
    # Normalize line endings
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    lines = text.split("\n")
    result_lines = []
    for line in lines:
        line = line.strip()
        if line == "":
            result_lines.append("")
            result_lines.append("")
        else:
            result_lines.append(line)

    result = "\n".join(result_lines)

    # Clean up excessive blank lines
    for _ in range(100):
        new_result = result.replace("\n\n\n\n", "\n\n\n")
        if new_result == result:
            break
        result = new_result

    return result.strip()


def _build_metadata_html(mode, model, char_count, stop_reason, prompt_status):
    """Build the metadata bar HTML (matching BuildMetadataHTML in AHK)."""
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    mode_display = "Comprehensive" if mode == "comprehensive" else "Proofreading"

    html = (
        f'<span class="metadata-item">'
        f'<span class="metadata-label">Generated:</span> '
        f'<span class="metadata-value">{current_time}</span></span>'
    )
    html += (
        f'<span class="metadata-item">'
        f'<span class="metadata-label">Mode:</span> '
        f'<span class="metadata-value">{mode_display}</span></span>'
    )
    html += (
        f'<span class="metadata-item">'
        f'<span class="metadata-label">Model:</span> '
        f'<span class="metadata-value">{model}</span></span>'
    )
    html += (
        f'<span class="metadata-item">'
        f'<span class="metadata-label">Characters:</span> '
        f'<span class="metadata-value">{char_count}</span></span>'
    )

    if stop_reason and stop_reason not in ("end_turn", "STOP", "stop"):
        html += (
            f'<span class="metadata-item">'
            f'<span class="metadata-value">\u26a0\ufe0f Truncated: {stop_reason}</span></span>'
        )

    html += f'<span class="metadata-item"><span class="metadata-value">{prompt_status}</span></span>'

    return html


def _build_targeted_review_html(areas, user_message="", demographics_label=""):
    """Build the targeted review panel HTML.

    Matches TargetedReviewManager.GenerateHTML() in AHK.
    """
    if not areas and not user_message:
        return ""

    # Message-only panel
    if not areas and user_message:
        safe_msg = escape_html(user_message)
        return (
            '<div class="report-section targeted-review-section">\n'
            '    <div class="collapsible-header" onclick="toggleCollapse(this)">\n'
            '        <h2 class="targeted-review-header">Targeted Review Suggestions</h2>\n'
            '        <span class="collapse-icon">\u25b6</span>\n'
            "    </div>\n"
            '    <div class="collapsible-content collapsed">\n'
            '        <div class="targeted-review-content">\n'
            f'            <p class="targeted-review-empty">{safe_msg}</p>\n'
            "        </div>\n"
            "    </div>\n"
            "</div>"
        )

    # Full panel with areas
    demo_span = ""
    if demographics_label:
        demo_span = (
            f'<span class="demographics-label">'
            f"{escape_html(demographics_label)}</span>"
        )

    lines = [
        '<div class="report-section targeted-review-section">',
        '    <div class="collapsible-header" onclick="toggleCollapse(this)">',
        '        <h2 class="targeted-review-header">Targeted Review Suggestions</h2>',
        f"        {demo_span}",
        '        <span class="collapse-icon">\u25b6</span>',
        "    </div>",
        '    <div class="collapsible-content collapsed">',
        '        <div class="targeted-review-content">',
        '            <ol class="targeted-review-list">',
    ]

    for item in areas:
        safe_area = escape_html(item.get("area", ""))
        safe_rationale = escape_html(item.get("rationale", ""))
        num = item.get("number", "")
        lines.append("                <li>")
        lines.append(
            f'                    <span class="targeted-review-number">{num}.</span>'
        )
        lines.append(
            f'                    <span class="targeted-review-item">'
            f"<strong>{safe_area}</strong> "
            f'<span class="rationale">- {safe_rationale}</span></span>'
        )
        lines.append("                </li>")

    lines.extend([
        "            </ol>",
        "        </div>",
        "    </div>",
        "</div>",
    ])

    return "\n".join(lines)


def _build_follow_up_section(session_id):
    """Build the follow-up conversation section HTML.

    Returns empty string if no session_id (follow-up not available).
    """
    if not session_id:
        return ""

    return (
        f'<div id="followUpSection" class="report-section follow-up-section"'
        f' data-session-id="{escape_html(session_id)}">\n'
        '    <h2 class="original-report-header">Follow-up</h2>\n'
        '    <div id="conversationThread" class="conversation-thread"></div>\n'
        '    <div id="typingIndicator" class="typing-indicator" style="display:none;">\n'
        '        <span class="typing-dot"></span>\n'
        '        <span class="typing-dot"></span>\n'
        '        <span class="typing-dot"></span>\n'
        '        <span class="typing-label">AI is responding...</span>\n'
        '    </div>\n'
        '    <div class="follow-up-input-area">\n'
        '        <textarea id="followUpInput" class="follow-up-textarea"'
        ' placeholder="Ask a follow-up question about this review..."'
        ' rows="2"></textarea>\n'
        '        <button id="followUpSend" class="follow-up-send-btn"'
        ' onclick="sendFollowUp()">Send</button>\n'
        '    </div>\n'
        '</div>'
    )


def _render_template(metadata_html, ai_html, original_html,
                     targeted_html, analysis_demo_html, version,
                     follow_up_html=""):
    """Render the HTML template with placeholders.

    Tries to load the template file; falls back to legacy HTML if unavailable.
    """
    template_path = os.path.join(script_dir, "templates", "report_template.html")

    try:
        with open(template_path, encoding="utf-8") as f:
            template = f.read()

        # Replace placeholders
        html = template.replace("{{METADATA}}", metadata_html)
        html = html.replace("{{AI_ANALYSIS}}", ai_html)
        html = html.replace("{{ORIGINAL_REPORT}}", original_html)
        html = html.replace("{{VERSION}}", version)
        html = html.replace("{{TARGETED_REVIEW_SECTION}}", targeted_html)
        html = html.replace("{{ANALYSIS_DEMOGRAPHICS}}", analysis_demo_html)
        html = html.replace("{{FOLLOW_UP_SECTION}}", follow_up_html)
        return html

    except (FileNotFoundError, OSError) as e:
        logger.error(f"Template rendering failed, using fallback: {e}")
        return _build_legacy_html(
            metadata_html, ai_html, original_html,
            targeted_html, version
        )


def _build_legacy_html(metadata_html, ai_html, original_html, targeted_html, version):
    """Fallback legacy HTML (matching BuildHTMLDocumentLegacy in AHK)."""
    return f"""<!DOCTYPE html><html><head><meta charset="UTF-8"><title>AI Report Check</title>
<style>
body{{font-family:Consolas,Monaco,monospace;margin:20px;background:#1a1a1a;color:#e0e0e0;line-height:1.5;}}
h1{{color:#4dd0e1;border-bottom:2px solid #424242;padding-bottom:10px;}}
h2{{color:#ff8a65;margin-top:30px;}}
h3{{color:#ffa726;margin-top:25px;margin-bottom:10px;font-weight:600;}}
.section-header{{padding:8px 12px !important;background:#2a2a2a !important;border-radius:5px;border-left:4px solid;margin:20px 0 15px 0 !important;}}
h1.section-header{{border-left-color:#4dd0e1;color:#4dd0e1;}}
h2.section-header{{border-left-color:#ff8a65;color:#ff8a65;}}
h3.section-header{{border-left-color:#ffa726;color:#ffa726;}}
.report{{background:#2d2d2d;padding:20px;margin:15px 0;border-radius:8px;border:1px solid #424242;}}
.metadata{{background:#333;padding:10px;border-radius:6px;font-size:13px;color:#bbb;margin-bottom:15px;}}
pre{{white-space:pre-wrap;font-family:inherit;margin:0;}}
strong.highlight{{color:#80deea;}}
ul{{margin:10px 0;padding-left:20px;}}
li{{margin:5px 0;}}
</style></head>
<body>
<h1>AI Report Check</h1>
<div class="metadata">{metadata_html}</div>
{targeted_html}
<div class="report"><div>{ai_html}</div></div>
<div class="report"><h2>Original Report</h2><pre>{original_html}</pre></div>
<div style="text-align:center;margin-top:40px;font-size:12px;color:#666;">Report Check v{version}</div>
</body></html>"""


def _cleanup_old_reviews(output_dir, max_files=10):
    """Keep only the most recent N HTML review files."""
    try:
        files = sorted(
            Path(output_dir).glob("review_*.html"),
            key=lambda f: f.stat().st_mtime,
            reverse=True,
        )
        for old_file in files[max_files:]:
            try:
                old_file.unlink()
            except OSError:
                pass
    except Exception:
        pass
