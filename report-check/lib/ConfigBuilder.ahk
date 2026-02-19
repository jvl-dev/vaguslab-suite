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
    ; Includes: prompt_type, models, targeted_review, debug_logging, startup, dark mode
    static _BuildSettingsConfig(formData) {
        settings := Map()

        ; Current provider for determining which models to save
        provider := formData.Get("Provider", "claude")

        ; Review mode (prompt_type)
        mode := formData.Get("reviewMode", "comprehensive")
        settings["prompt_type"] := mode

        ; Models — the form now has explicit ComprehensiveModel and ProofreadingModel fields
        ; Save them for the active provider; preserve existing config for other providers
        existingSettings := ConfigManager.config.Has("Settings") ? ConfigManager.config["Settings"] : Map()

        for targetProvider in ["claude", "gemini", "openai"] {
            for targetMode in ["comprehensive", "proofreading"] {
                configKey := targetMode . "_" . targetProvider . "_model"
                if (targetProvider = provider) {
                    ; Active provider — read from the form dropdown
                    formField := (targetMode = "comprehensive") ? "ComprehensiveModel" : "ProofreadingModel"
                    formValue := formData.Get(formField, "")
                    settings[configKey] := (formValue != "") ? formValue : Constants.GetDefaultModel(targetProvider, targetMode)
                } else {
                    ; Non-active provider — preserve existing config value
                    settings[configKey] := existingSettings.Get(configKey, Constants.GetDefaultModel(targetProvider, targetMode))
                }
            }
        }

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
