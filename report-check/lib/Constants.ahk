; ==============================================
; Application Constants
; ==============================================
; Centralized constants to avoid magic numbers throughout codebase
; All timeouts in milliseconds, all dimensions in pixels

class Constants {
    ; ==============================================
    ; HTTP Timeouts (milliseconds)
    ; ==============================================

    ; API request timeouts (for Claude/Gemini API calls)
    static API_TIMEOUT_RESOLVE := 10000      ; 10 seconds - DNS resolution
    static API_TIMEOUT_CONNECT := 10000      ; 10 seconds - Connection establishment
    static API_TIMEOUT_SEND := 30000         ; 30 seconds - Sending request
    static API_TIMEOUT_RECEIVE := 120000     ; 120 seconds (2 minutes) - Receiving response (long for LLM processing)

    ; Version/update check timeouts (increased to handle slow server response)
    static UPDATE_TIMEOUT_RESOLVE := 15000   ; 15 seconds - DNS resolution
    static UPDATE_TIMEOUT_CONNECT := 15000   ; 15 seconds - Connection
    static UPDATE_TIMEOUT_SEND := 20000      ; 20 seconds - Send
    static UPDATE_TIMEOUT_RECEIVE := 30000   ; 30 seconds - Receive

    ; File download timeouts (longer for binary files)
    static DOWNLOAD_TIMEOUT_RESOLVE := 5000  ; 5 seconds
    static DOWNLOAD_TIMEOUT_CONNECT := 5000  ; 5 seconds
    static DOWNLOAD_TIMEOUT_SEND := 30000    ; 30 seconds
    static DOWNLOAD_TIMEOUT_RECEIVE := 30000 ; 30 seconds

    ; ==============================================
    ; UI Delays (milliseconds)
    ; ==============================================

    static CLIPBOARD_WAIT_TIMEOUT := 2000    ; 2 seconds - Wait for clipboard to populate
    static POWERSCRIBE_ACTIVATION_TIMEOUT := 3000  ; 3 seconds - Max wait for PowerScribe window activation
    static POWERSCRIBE_ACTIVATION_DELAY := 300     ; 300ms - Delay after window activation before sending keys
    static POWERSCRIBE_SELECT_DELAY := 300         ; 300ms - Delay after Ctrl+A in PowerScribe
    static POWERSCRIBE_RETRY_ATTEMPTS := 2         ; Number of retry attempts for window activation
    static POWERSCRIBE_RETRY_DELAY := 500          ; 500ms - Delay between retry attempts
    static NOTIFICATION_DURATION := 3000     ; 3 seconds - Default notification display time
    static NOTIFICATION_DURATION_ERROR := 5000   ; 5 seconds - Error notifications
    static NOTIFICATION_DURATION_WARNING := 4000 ; 4 seconds - Warning notifications
    static RELOAD_DELAY := 1000              ; 1 second - Delay before script reload after settings save
    static SETTINGS_SAVE_FEEDBACK_DELAY := 500  ; 500ms - Show "saving" feedback

    ; ==============================================
    ; Loop Safety Limits (prevent infinite loops)
    ; ==============================================

    static MAX_WHITESPACE_ITERATIONS := 100      ; Max iterations for whitespace skip loop
    static MAX_QUOTE_SEARCH_ITERATIONS := 1000   ; Max iterations for finding closing quote
    static MAX_BACKSLASH_COUNT_ITERATIONS := 100 ; Max iterations for counting escape backslashes
    static MAX_CLEANUP_ITERATIONS := 100         ; Max iterations for line break cleanup

    ; ==============================================
    ; API Parameters
    ; ==============================================

    ; API_MAX_TOKENS and API_TEMPERATURE removed — now per-mode in Python (api_handler.REVIEW_PROFILES)
    static API_RATE_LIMIT_MS := 2000         ; Minimum milliseconds between API calls (prevents accidental rapid-fire)

    ; Streaming follow-up parameters
    static STREAM_POLL_INTERVAL := 100       ; 100ms - poll interval for streaming file reads
    static STREAM_TIMEOUT := 120000          ; 120 seconds (2 minutes) - max wait for streaming response

    ; ==============================================
    ; GUI Dimensions (pixels)
    ; ==============================================

    ; Settings Window
    static SETTINGS_WINDOW_WIDTH := 650
    static SETTINGS_WINDOW_HEIGHT := 650

    static SETTINGS_TAB_X := 10
    static SETTINGS_TAB_Y := 10
    static SETTINGS_TAB_WIDTH := 630
    static SETTINGS_TAB_HEIGHT := 560

    static SETTINGS_BUTTON_SAVE_X := 470
    static SETTINGS_BUTTON_SAVE_Y := 585
    static SETTINGS_BUTTON_SAVE_WIDTH := 80
    static SETTINGS_BUTTON_SAVE_HEIGHT := 30

    static SETTINGS_BUTTON_CANCEL_X := 560
    static SETTINGS_BUTTON_CANCEL_Y := 585
    static SETTINGS_BUTTON_CANCEL_WIDTH := 80
    static SETTINGS_BUTTON_CANCEL_HEIGHT := 30

    ; Content margins and spacing
    static CONTENT_MARGIN_LEFT := 20
    static CONTENT_MARGIN_TOP := 50
    static CONTENT_WIDTH := 610
    static GROUPBOX_INDENT := 10             ; Indent for content inside groupbox

    ; Review Results Window
    static REVIEW_WINDOW_WIDTH := 1400
    static REVIEW_WINDOW_HEIGHT := 900
    static REVIEW_WEBVIEW_MARGIN := 10

    ; ==============================================
    ; File System
    ; ==============================================

    static MAX_REVIEW_FILES_DEFAULT := 10    ; Default max files for review history
    static CONFIG_ENCODING := "UTF-8"        ; Configuration file encoding
    static DICOM_CACHE_DEFAULT := "C:\Intelerad\InteleViewerDicom"  ; Default DICOM cache directory
    static PSONE_PERF_LOG_SUBPATH := "\AppData\Local\Nuance\PowerScribeOne\Logs\Perf\PSOnePerf.log"  ; Relative to USERPROFILE

    ; ==============================================
    ; Update System
    ; ==============================================

    static UPDATE_CHECK_STARTUP := true      ; Check for updates on startup
    static UPDATE_CHECK_SILENT := true       ; Silent update checks on startup

    ; ==============================================
    ; AI Provider Model Registry (single source of truth)
    ; ==============================================
    ; GUI-available models — shown in dropdown and accepted by config validation.
    ; Order matters: first model in each list is the dropdown default for that mode.

    static CLAUDE_MODELS := ["claude-sonnet-4-6", "claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001", "claude-sonnet-4-20250514"]
    static GEMINI_MODELS := ["gemini-3-flash-preview", "gemini-2.5-flash", "gemini-2.5-pro"]
    static OPENAI_MODELS := ["gpt-4o", "gpt-4o-mini"]

    ; Default models per mode (index into the arrays above)
    static CLAUDE_DEFAULT_COMPREHENSIVE  := "claude-sonnet-4-6"
    static CLAUDE_DEFAULT_PROOFREADING   := "claude-sonnet-4-20250514"
    static GEMINI_DEFAULT_COMPREHENSIVE  := "gemini-2.5-flash"
    static GEMINI_DEFAULT_PROOFREADING   := "gemini-2.5-flash"
    static OPENAI_DEFAULT_COMPREHENSIVE  := "gpt-4o"
    static OPENAI_DEFAULT_PROOFREADING   := "gpt-4o-mini"

    ; Helper: get models array for a provider
    static GetModels(provider) {
        if (provider = "claude")
            return this.CLAUDE_MODELS
        if (provider = "gemini")
            return this.GEMINI_MODELS
        if (provider = "openai")
            return this.OPENAI_MODELS
        return []
    }

    ; Helper: get default model for a provider + mode
    static GetDefaultModel(provider, mode := "comprehensive") {
        if (provider = "claude")
            return (mode = "proofreading") ? this.CLAUDE_DEFAULT_PROOFREADING : this.CLAUDE_DEFAULT_COMPREHENSIVE
        if (provider = "gemini")
            return (mode = "proofreading") ? this.GEMINI_DEFAULT_PROOFREADING : this.GEMINI_DEFAULT_COMPREHENSIVE
        if (provider = "openai")
            return (mode = "proofreading") ? this.OPENAI_DEFAULT_PROOFREADING : this.OPENAI_DEFAULT_COMPREHENSIVE
        return ""
    }

    ; Helper: check if model is valid for a provider
    static IsValidModel(model, provider) {
        for m in this.GetModels(provider) {
            if (m = model)
                return true
        }
        return false
    }

    ; ==============================================
    ; HTTP Status Codes (for user-friendly messages)
    ; ==============================================

    static HTTP_OK := 200
    static HTTP_BAD_REQUEST := 400
    static HTTP_UNAUTHORIZED := 401
    static HTTP_FORBIDDEN := 403
    static HTTP_NOT_FOUND := 404
    static HTTP_TOO_MANY_REQUESTS := 429
    static HTTP_INTERNAL_ERROR := 500
    static HTTP_BAD_GATEWAY := 502
    static HTTP_SERVICE_UNAVAILABLE := 503

    ; ==============================================
    ; Helper Methods
    ; ==============================================

    ; Get all API request timeouts as array [resolve, connect, send, receive]
    static GetAPITimeouts() {
        return [
            this.API_TIMEOUT_RESOLVE,
            this.API_TIMEOUT_CONNECT,
            this.API_TIMEOUT_SEND,
            this.API_TIMEOUT_RECEIVE
        ]
    }

    ; Get all update check timeouts as array
    static GetUpdateTimeouts() {
        return [
            this.UPDATE_TIMEOUT_RESOLVE,
            this.UPDATE_TIMEOUT_CONNECT,
            this.UPDATE_TIMEOUT_SEND,
            this.UPDATE_TIMEOUT_RECEIVE
        ]
    }

    ; Get all download timeouts as array
    static GetDownloadTimeouts() {
        return [
            this.DOWNLOAD_TIMEOUT_RESOLVE,
            this.DOWNLOAD_TIMEOUT_CONNECT,
            this.DOWNLOAD_TIMEOUT_SEND,
            this.DOWNLOAD_TIMEOUT_RECEIVE
        ]
    }
}
