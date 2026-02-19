; ==============================================
; Configuration Builder Class
; ==============================================
; Converts WebView form data into ConfigManager structure
; Used by SettingsGui to transform JavaScript form data into AHK Maps

class ConfigBuilder {
    ; Main entry point: Convert form data Map into ConfigManager structure
    ; @param formData - Map from JavaScript collectFormData()
    ; @return Map with "Settings", "API", "Beta" keys
    static BuildFromFormData(formData) {
        config := Map()

        ; Build each section
        config["Settings"] := this._BuildSettingsConfig(formData)
        config["API"] := this._BuildAPIConfig(formData)
        config["Beta"] := this._BuildBetaConfig(formData)

        return config
    }

    ; Build Settings section
    ; Includes: prompt_type, models, URLs, targeted_review, debug_logging, startup, dark mode
    static _BuildSettingsConfig(formData) {
        settings := Map()

        ; Current provider for determining which model/URL to save
        provider := formData.Get("Provider", "claude")

        ; Review mode (prompt_type)
        mode := formData.Get("reviewMode", "comprehensive")
        settings["prompt_type"] := mode

        ; API URLs - preserve all provider URLs
        settings["claude_url"] := this._GetProviderValue(formData, "APIURL", provider, "claude",
            "https://api.anthropic.com/v1/messages")
        settings["gemini_url"] := this._GetProviderValue(formData, "APIURL", provider, "gemini",
            "https://generativelanguage.googleapis.com/v1beta/models/")
        settings["openai_url"] := this._GetProviderValue(formData, "APIURL", provider, "openai",
            "https://api.openai.com/v1/chat/completions")

        ; Models - preserve all provider models
        ; Comprehensive models
        settings["comprehensive_claude_model"] := this._GetProviderValue(formData, "Model", provider, "claude",
            Constants.GetDefaultModel("claude", "comprehensive"), mode, "comprehensive")
        settings["comprehensive_gemini_model"] := this._GetProviderValue(formData, "Model", provider, "gemini",
            Constants.GetDefaultModel("gemini", "comprehensive"), mode, "comprehensive")
        settings["comprehensive_openai_model"] := this._GetProviderValue(formData, "Model", provider, "openai",
            Constants.GetDefaultModel("openai", "comprehensive"), mode, "comprehensive")

        ; Proofreading models
        settings["proofreading_claude_model"] := this._GetProviderValue(formData, "Model", provider, "claude",
            Constants.GetDefaultModel("claude", "proofreading"), mode, "proofreading")
        settings["proofreading_gemini_model"] := this._GetProviderValue(formData, "Model", provider, "gemini",
            Constants.GetDefaultModel("gemini", "proofreading"), mode, "proofreading")
        settings["proofreading_openai_model"] := this._GetProviderValue(formData, "Model", provider, "openai",
            Constants.GetDefaultModel("openai", "proofreading"), mode, "proofreading")

        ; Targeted review (child of demographic extraction)
        settings["targeted_review_enabled"] := this._ParseBool(formData.Get("TargetedReviewEnabled", false))

        ; Debug logging
        settings["debug_logging"] := this._ParseBool(formData.Get("DebugLogging", false))

        ; Startup
        settings["startup_enabled"] := this._ParseBool(formData.Get("StartupEnabled", false))

        ; Dark mode (stored in settings for persistence)
        settings["dark_mode_enabled"] := this._ParseBool(formData.Get("DarkModeEnabled", false))

        ; Max review files (not in form, preserve from config)
        if (ConfigManager.config.Has("Settings") && ConfigManager.config["Settings"].Has("max_review_files")) {
            settings["max_review_files"] := ConfigManager.config["Settings"]["max_review_files"]
        } else {
            settings["max_review_files"] := 10
        }

        return settings
    }

    ; Build API section
    ; Includes: provider and all API keys
    static _BuildAPIConfig(formData) {
        api := Map()

        ; Provider
        provider := formData.Get("Provider", "claude")
        api["provider"] := provider

        ; API Keys - preserve all provider keys, only update the current provider's key
        currentKey := formData.Get("APIKey", "")

        ; Get existing keys from ConfigManager
        existingAPI := ConfigManager.config.Has("API") ? ConfigManager.config["API"] : Map()

        api["claude_api_key"] := provider = "claude" ? currentKey : existingAPI.Get("claude_api_key", "")
        api["gemini_api_key"] := provider = "gemini" ? currentKey : existingAPI.Get("gemini_api_key", "")
        api["openai_api_key"] := provider = "openai" ? currentKey : existingAPI.Get("openai_api_key", "")

        ; Preserve verification hashes
        api["claude_verified_hash"] := existingAPI.Get("claude_verified_hash", "")
        api["claude_verified_date"] := existingAPI.Get("claude_verified_date", "")
        api["gemini_verified_hash"] := existingAPI.Get("gemini_verified_hash", "")
        api["gemini_verified_date"] := existingAPI.Get("gemini_verified_date", "")
        api["openai_verified_hash"] := existingAPI.Get("openai_verified_hash", "")
        api["openai_verified_date"] := existingAPI.Get("openai_verified_date", "")

        return api
    }

    ; Build Beta section
    ; Includes: mode override, powerscribe, demographic extraction, DICOM cache
    static _BuildBetaConfig(formData) {
        beta := Map()

        ; Mode override hotkeys
        beta["mode_override_hotkeys"] := this._ParseBool(formData.Get("BetaModeOverrideHotkeys", false))

        ; PowerScribe auto-select
        beta["powerscribe_autoselect"] := this._ParseBool(formData.Get("BetaPowerScribeAutoselect", false))

        ; Demographic extraction (parent feature)
        beta["demographic_extraction_enabled"] := this._ParseBool(formData.Get("DemographicExtractionEnabled", false))

        ; DICOM cache directory (child of demographic extraction)
        dicomDir := formData.Get("DicomCacheDirectory", "")
        if (dicomDir = "" || dicomDir = "Default directory") {
            dicomDir := Constants.DICOM_CACHE_DEFAULT
        }
        beta["dicom_cache_directory"] := dicomDir

        return beta
    }

    ; Helper: Get provider-specific value with fallback
    ; If the current provider matches, use the form value
    ; Otherwise, preserve the existing value from ConfigManager
    ; @param formData - Form data Map
    ; @param field - Field name in form data (e.g., "Model", "APIURL")
    ; @param currentProvider - Current provider from form
    ; @param targetProvider - Provider we're getting value for
    ; @param defaultValue - Default if not found
    ; @param currentMode - Current mode (for model selection)
    ; @param targetMode - Target mode (for model selection)
    static _GetProviderValue(formData, field, currentProvider, targetProvider, defaultValue, currentMode := "", targetMode := "") {
        ; If we're getting value for the current provider and current mode (or no mode specified), use form value
        if (currentProvider = targetProvider && (currentMode = "" || currentMode = targetMode)) {
            formValue := formData.Get(field, "")
            if (formValue != "" && formValue != "Default API URL") {
                return formValue
            }
        }

        ; Otherwise, preserve existing value from ConfigManager
        existingSettings := ConfigManager.config.Has("Settings") ? ConfigManager.config["Settings"] : Map()

        ; Determine the config key based on field and provider
        if (field = "APIURL") {
            configKey := targetProvider "_url"
        } else if (field = "Model") {
            configKey := targetMode "_" targetProvider "_model"
        } else {
            return defaultValue
        }

        return existingSettings.Get(configKey, defaultValue)
    }

    ; Helper: Parse boolean from JavaScript value
    ; JavaScript sends true/false as actual booleans in the JSON
    static _ParseBool(value) {
        if (Type(value) = "Integer") {
            return value != 0
        }
        if (Type(value) = "String") {
            return (value = "true" || value = "1")
        }
        return value ? true : false
    }
}
