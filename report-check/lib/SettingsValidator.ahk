; ==============================================
; Settings Validation Logic
; ==============================================
; Extracted from SettingsGui to separate validation concerns
; Pure validation logic with no GUI dependencies

class SettingsValidator {
    ; Validate URL format
    ; Returns: {valid: bool, error: string}
    static ValidateURL(url) {
        ; Trim whitespace
        url := Trim(url)

        ; Check for empty URL
        if (url = "") {
            return {valid: false, error: "URL cannot be empty"}
        }

        ; Basic URL validation - check if it starts with http:// or https://
        if (!RegExMatch(url, "^https?://")) {
            return {valid: false, error: "URL must start with http:// or https://"}
        }

        ; Check for common URL structure issues
        if (InStr(url, " ")) {
            return {valid: false, error: "URL cannot contain spaces"}
        }

        ; Check for minimum valid URL structure (protocol + domain)
        if (!RegExMatch(url, "^https?://[a-zA-Z0-9\-\.]+")) {
            return {valid: false, error: "URL must have a valid domain name"}
        }

        ; Check for obviously invalid characters (< > " ')
        ; Note: Using separate checks to avoid string escaping issues
        if (RegExMatch(url, '[<>"' . "'" . '``]')) {
            return {valid: false, error: "URL contains invalid characters"}
        }

        ; Provider-specific validation
        if (InStr(url, "anthropic.com")) {
            ; Claude URL should end with /messages
            if (!InStr(url, "/messages")) {
                return {valid: false, error: "Claude URL should end with /messages (e.g., https://api.anthropic.com/v1/messages)"}
            }
        } else if (InStr(url, "googleapis.com")) {
            ; Gemini URL should contain /models/
            if (!InStr(url, "/models/")) {
                return {valid: false, error: "Gemini URL should contain /models/ (e.g., https://generativelanguage.googleapis.com/v1beta/models/)"}
            }
        } else if (InStr(url, "openai.com")) {
            ; OpenAI URL should contain /chat/completions
            if (!InStr(url, "/chat/completions")) {
                return {valid: false, error: "OpenAI URL should end with /chat/completions (e.g., https://api.openai.com/v1/chat/completions)"}
            }
        }

        return {valid: true}
    }

    ; Validate all settings inputs before save (delegates to ValidateAPIInputs)
    ; Returns: bool (true = valid, false = invalid with message box shown)
    static ValidateAllInputs(values, provider) {
        return this.ValidateAPIInputs(values, provider)
    }

    ; Validate API-related inputs (API Key, URL, Model) with provider-specific format checks
    ; Returns: bool (true = valid, false = invalid with message box shown)
    static ValidateAPIInputs(values, provider) {
        ; Validate API URL
        urlValidation := this.ValidateURL(values.APIURL)
        if (!urlValidation.valid) {
            MsgBox("Invalid API URL: " . urlValidation.error, "Validation Error", 16)
            return false
        }

        ; Validate API Key is present
        apiKey := Trim(values.APIKey)
        if (apiKey = "") {
            MsgBox("API Key cannot be empty. Please enter your API key.", "Validation Error", 16)
            return false
        }

        ; Validate Model is selected
        if (!values.HasProp("Model") || values.Model = "") {
            MsgBox("Please select a model from the dropdown.", "Validation Error", 16)
            return false
        }

        ; Validate API Key format based on provider
        formatCheck := ""
        if (provider = "claude") {
            formatCheck := SharedUtils.ValidateClaudeAPIKey(apiKey)
        } else if (provider = "gemini") {
            formatCheck := SharedUtils.ValidateGeminiAPIKey(apiKey)
        } else if (provider = "openai") {
            formatCheck := SharedUtils.ValidateOpenAIAPIKey(apiKey)
        }

        if (formatCheck != "" && !formatCheck.valid) {
            result := MsgBox("API Key Format Issue: " . formatCheck.error . "`n`nDo you want to save it anyway?",
                            "API Key Format Warning", 4 + 48)
            if (result = "No") {
                return false
            }
        }

        return true
    }

    ; Validate API key format for display (no msgbox)
    ; Returns: bool
    static ValidateAPIKeyFormat(apiKey, provider) {
        if (provider = "claude") {
            return ConfigManager.ValidateAPIKey(apiKey)
        } else if (provider = "gemini") {
            return (StrLen(apiKey) >= 20)
        } else if (provider = "openai") {
            validation := SharedUtils.ValidateOpenAIAPIKey(apiKey)
            return validation.valid
        }
        return false
    }

    ; Get validation error message for API key format
    ; Returns: string
    static GetAPIKeyFormatError(provider) {
        if (provider = "claude") {
            return "Invalid format - should start with 'sk-ant-'"
        } else if (provider = "gemini") {
            return "Invalid Gemini API key format"
        } else if (provider = "openai") {
            return "Invalid format - should start with 'sk-'"
        }
        return "Invalid API key format"
    }
}
