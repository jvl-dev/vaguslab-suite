; ==============================================
; Settings Presenter - Business Logic Layer
; ==============================================
; Coordinates between GUI, Validator, and ConfigManager
; Contains no direct GUI code - operates on data only

class SettingsPresenter {
    ; Save settings workflow
    ; Returns: {success: bool, error: string, needsReload: bool}
    static SaveSettings(values, provider, selectedMode) {
        try {
            apiKey := Trim(values.APIKey)

            ; Check if API key is empty - if so, only save non-API settings
            if (apiKey = "") {
                ; Show warning but allow saving non-API settings
                result := MsgBox("Warning: No API key configured.`n`n" .
                                "Report Check will not function until you add an API key.`n`n" .
                                "Your other settings (startup, mode, beta features) will be saved.`n`n" .
                                "Continue saving?",
                                "No API Key", 4 + 48)

                if (result = "No") {
                    return {success: false, error: "Save cancelled by user", needsReload: false}
                }

                ; Save only non-API settings
                this._SaveBasicSettings(values)
                this._SaveBetaSettings(values)

                ; Save to file
                if (!ConfigManager.SaveConfig()) {
                    return {success: false, error: "Failed to save configuration to file", needsReload: false}
                }

                return {success: true, error: "", needsReload: true}
            }

            ; API key present - validate all API inputs
            if (!SettingsValidator.ValidateAPIInputs(values, provider)) {
                return {success: false, error: "Validation failed", needsReload: false}
            }

            ; Save basic settings
            this._SaveBasicSettings(values)

            ; Handle API key changes and verification
            keyResult := this._HandleAPIKeyChange(apiKey, provider, values)
            if (!keyResult.success) {
                return {success: false, error: keyResult.error, needsReload: false}
            }

            ; Update provider and model settings
            this._SaveProviderSettings(provider, selectedMode, values)

            ; Update Beta settings
            this._SaveBetaSettings(values)

            ; Save to file
            if (!ConfigManager.SaveConfig()) {
                return {success: false, error: "Failed to save configuration to file", needsReload: false}
            }

            return {success: true, error: "", needsReload: true}

        } catch as err {
            return {success: false, error: err.Message, needsReload: false}
        }
    }

    ; Save basic settings (startup, mode, debug logging)
    static _SaveBasicSettings(values) {
        ; Handle startup setting
        ConfigManager.ToggleStartup(values.StartupEnabled)

        ; Handle mode selection - save to config
        if (values.ModeComprehensive = 1) {
            ConfigManager.config["Settings"]["prompt_type"] := "comprehensive"
        } else if (values.ModeProofreading = 1) {
            ConfigManager.config["Settings"]["prompt_type"] := "proofreading"
        }

        ; Handle debug logging setting
        ConfigManager.config["Settings"]["debug_logging"] := values.DebugLogging ? true : false

        ; Apply immediately to Logger (don't wait for restart)
        if (values.DebugLogging) {
            Logger.SetLevel(Logger.LOG_LEVEL_DEBUG)
        } else {
            Logger.SetLevel(Logger.LOG_LEVEL_INFO)
        }
    }

    ; Handle API key changes and verification
    ; Returns: {success: bool, error: string, verified: bool}
    static _HandleAPIKeyChange(apiKey, provider, values) {
        if (apiKey = "") {
            return {success: true, error: "", verified: false}
        }

        keyField := provider . "_api_key"
        currentStoredKey := this._GetDecryptedStoredKey(keyField)

        ; Check if key changed
        keyChanged := (apiKey != currentStoredKey)

        if (keyChanged) {
            ; For new keys, just save them
            ; Verification is handled separately via Test button
            ConfigManager.config["API"][keyField] := apiKey
            return {success: true, error: "", verified: false}
        }

        ; Key unchanged - continue saving
        return {success: true, error: "", verified: false}
    }

    ; Get the stored API key, decrypting if necessary
    static _GetDecryptedStoredKey(keyField) {
        currentStoredKey := ConfigManager.config["API"].Get(keyField, "")

        if (currentStoredKey != "" && ConfigManager.IsAPIKeyEncrypted(currentStoredKey)) {
            currentStoredKey := ConfigManager.DeobfuscateAPIKey(currentStoredKey)
        }

        return currentStoredKey
    }

    ; Save provider-specific settings (URL, model)
    static _SaveProviderSettings(provider, selectedMode, values) {
        ; Update provider in configuration
        ConfigManager.config["API"]["provider"] := provider

        ; Update provider-specific URL and model
        if (provider = "claude") {
            ConfigManager.config["Settings"]["claude_url"] := values.APIURL
            if (selectedMode != "") {
                modelField := selectedMode . "_claude_model"
                ConfigManager.config["Settings"][modelField] := values.Model
            }
        } else if (provider = "gemini") {
            ConfigManager.config["Settings"]["gemini_url"] := values.APIURL
            if (selectedMode != "") {
                modelField := selectedMode . "_gemini_model"
                ConfigManager.config["Settings"][modelField] := values.Model
            }
        } else if (provider = "openai") {
            ConfigManager.config["Settings"]["openai_url"] := values.APIURL
            if (selectedMode != "") {
                modelField := selectedMode . "_openai_model"
                ConfigManager.config["Settings"][modelField] := values.Model
            }
        }
    }

    ; Save Beta feature settings
    static _SaveBetaSettings(values) {
        ConfigManager.config["Beta"]["demographic_extraction_enabled"] := !!values.DemographicExtractionEnabled
        ConfigManager.config["Beta"]["mode_override_hotkeys"] := !!values.BetaModeOverrideHotkeys
        ConfigManager.config["Beta"]["powerscribe_autoselect"] := !!values.BetaPowerScribeAutoselect
        ConfigManager.config["Beta"]["dicom_cache_directory"] := Trim(values.DicomCacheDirectory)

        ; Targeted Review is in Settings section (not Beta) but shown on Beta tab
        if (values.HasProp("TargetedReviewEnabled")) {
            ConfigManager.config["Settings"]["targeted_review_enabled"] := !!values.TargetedReviewEnabled
        }
    }

    ; Handle provider change (auto-save)
    static ChangeProvider(provider) {
        ConfigManager.SetProvider(provider)
        ConfigManager.SaveConfig()
    }

    ; Handle mode change (auto-save)
    static ChangeMode(selectedMode) {
        ConfigManager.config["Settings"]["prompt_type"] := selectedMode
        ConfigManager.SaveConfig()
    }

    ; Get provider-specific data for UI display
    ; Returns: {apiKey: string, apiUrl: string, models: array, currentModel: string}
    static GetProviderData(provider, promptType) {
        api := ConfigManager.config["API"]
        settings := ConfigManager.config["Settings"]

        ; Get API key
        apiKey := api.Get(provider . "_api_key", "")
        if (apiKey != "" && ConfigManager.IsAPIKeyEncrypted(apiKey)) {
            apiKey := ConfigManager.DeobfuscateAPIKey(apiKey)
        }

        ; Provider-specific data (models and defaults from Constants registry)
        urlField := provider . "_url"
        modelField := promptType . "_" . provider . "_model"
        models := Constants.GetModels(provider)
        defaultModel := Constants.GetDefaultModel(provider, promptType)
        if (provider = "claude") {
            apiUrl := settings.Get(urlField, "https://api.anthropic.com/v1/messages")
        } else if (provider = "gemini") {
            apiUrl := settings.Get(urlField, "https://generativelanguage.googleapis.com/v1beta/models/")
        } else if (provider = "openai") {
            apiUrl := settings.Get(urlField, "https://api.openai.com/v1/chat/completions")
        }
        currentModel := settings.Get(modelField, defaultModel)

        ; Find model index
        modelIndex := 1
        Loop models.Length {
            if (models[A_Index] = currentModel) {
                modelIndex := A_Index
                break
            }
        }

        return {
            apiKey: apiKey,
            apiUrl: apiUrl,
            models: models,
            currentModel: currentModel,
            modelIndex: modelIndex
        }
    }

    ; Check API key verification status
    ; Returns: {status: string, color: string, verified: bool}
    static GetAPIKeyStatus(apiKey, provider, lastTestedKey, lastTestResult) {
        if (apiKey = "" || Trim(apiKey) = "") {
            return {status: "No API key configured", color: "c0x808080", verified: false}
        }

        ; Check format validity
        isValidFormat := SettingsValidator.ValidateAPIKeyFormat(apiKey, provider)

        if (!isValidFormat) {
            errorMsg := SettingsValidator.GetAPIKeyFormatError(provider)
            return {status: errorMsg, color: "c0xFF6B6B", verified: false}
        }

        ; Check persistent verification
        if (ConfigManager.IsAPIKeyVerified(provider)) {
            verifiedDate := ConfigManager.GetVerificationDate(provider)
            statusText := (verifiedDate != "") ? "API key verified " . verifiedDate : "API key verified"
            return {status: statusText, color: "c0x45B7D1", verified: true}
        }

        ; Check session verification
        if (apiKey = lastTestedKey && lastTestResult) {
            return {status: "API key verified in this session", color: "c0x45B7D1", verified: true}
        }

        ; Not verified
        return {status: "Click 'Test Key' to verify API key", color: "c0x808080", verified: false}
    }

    ; Test API key connection
    ; Returns: {success: bool, error: string, message: string}
    static TestAPIKey(apiKey, provider) {
        result := ConfigManager.VerifyAndSaveAPIKey(apiKey, true, provider)

        if (result.success) {
            return {
                success: true,
                error: "",
                message: "✅ Connection successful! API key is valid"
            }
        } else {
            return {
                success: false,
                error: result.error,
                message: result.error
            }
        }
    }

    ; Auto-verify API key (no notifications)
    ; Returns: {success: bool, error: string, message: string}
    static AutoVerifyAPIKey(apiKey, provider) {
        if (apiKey = "") {
            return {success: false, error: "No key", message: ""}
        }

        result := ConfigManager.VerifyAndSaveAPIKey(apiKey, false, provider)

        if (result.success) {
            return {
                success: true,
                error: "",
                message: "API key verified successfully"
            }
        } else {
            return {
                success: false,
                error: result.error,
                message: result.error
            }
        }
    }

    ; Handle API key change event
    ; Returns: {shouldClearVerification: bool, newStatus: object}
    static OnAPIKeyChanged(apiKey, provider, lastTestedKey, currentStoredKey) {
        ; Clear session test result if key changed
        shouldClearSession := (apiKey != lastTestedKey)

        ; Clear persistent verification if key actually modified
        shouldClearPersistent := false
        if (currentStoredKey != "" && apiKey != "" && apiKey != currentStoredKey) {
            shouldClearPersistent := true
        }

        return {
            shouldClearSession: shouldClearSession,
            shouldClearPersistent: shouldClearPersistent
        }
    }

    ; Get prompt display data for Prompts tab
    ; Returns: {modeDisplay: string, systemPrompt: string}
    static GetPromptData(promptType) {
        modeDisplay := (promptType = "comprehensive") ? "Comprehensive Review" : "Proofreading Only"

        ; Get system prompt (includes dynamically injected date)
        ; Temporarily set mode to get correct prompt
        oldMode := ConfigManager.config["Settings"]["prompt_type"]
        ConfigManager.config["Settings"]["prompt_type"] := promptType
        systemPrompt := ConfigManager.GetCurrentPrompt()
        ConfigManager.config["Settings"]["prompt_type"] := oldMode

        return {
            modeDisplay: modeDisplay,
            systemPrompt: systemPrompt
        }
    }

    ; Get model data for specific mode
    ; Returns: {modelIndex: int}
    static GetModelForMode(provider, promptType) {
        settings := ConfigManager.config["Settings"]
        models := Constants.GetModels(provider)
        defaultModel := Constants.GetDefaultModel(provider, promptType)
        modelField := promptType . "_" . provider . "_model"
        currentModel := settings.Get(modelField, defaultModel)

        modelIndex := 1
        Loop models.Length {
            if (models[A_Index] = currentModel) {
                modelIndex := A_Index
                break
            }
        }
        return {modelIndex: modelIndex}
    }

    ; Get list of available models for a provider
    ; Returns: Array of model names
    static GetModelsForProvider(provider, promptType := "") {
        return Constants.GetModels(provider)
    }
}
