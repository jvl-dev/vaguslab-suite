; ==============================================
; Configuration Management Class
; ==============================================

class ConfigManager {
    static config := Map()
    static configDir := A_ScriptDir "\pref"
    static configFile := this.configDir "\config.json"
    static startupShortcutPath := A_Startup "\" A_ScriptName ".lnk"
    
    ; Read system prompt from file based on current mode
    ; LEGACY/FALLBACK METHOD: Kept for fallback if PromptCache fails to initialize
    ; Normal operation uses PromptCache.GetPrompt() via GetCurrentPrompt()
    ; If modeOverride is provided, use that instead of the config setting
    static GetDefaultPrompt(modeOverride := "") {
        try {
            ; Get prompt type from config if available, or use override
            promptType := "comprehensive"
            if (modeOverride != "" && (modeOverride = "comprehensive" || modeOverride = "proofreading")) {
                promptType := modeOverride
            } else if (this.config.Has("Settings") && this.config["Settings"].Has("prompt_type")) {
                promptType := this.config["Settings"]["prompt_type"]
            }

            ; Load prompt from shipped prompts/ directory
            promptFile := A_ScriptDir "\prompts\system_prompt_" . promptType . ".txt"

            if FileExist(promptFile) {
                return FileRead(promptFile, "UTF-8")
            }

            ; Try fallback to comprehensive if selected file doesn't exist
            if (promptType != "comprehensive") {
                fallbackFile := A_ScriptDir "\prompts\system_prompt_comprehensive.txt"
                if FileExist(fallbackFile) {
                    MsgBox("Warning: " . promptType . " prompt file not found.`n`n" .
                           "Using comprehensive review prompt instead.",
                           "Missing Prompt File", 48)
                    return FileRead(fallbackFile, "UTF-8")
                }
            }

            ; File doesn't exist - warn user and use fallback
            MsgBox("Warning: Prompt files not found in " . this.configDir . "`n`n" .
                   "Using basic fallback prompt. For full functionality, please restore prompt files from backup or reinstall the application.",
                   "Missing System Prompt", 48)
            return "You are a radiology report checking assistant. Provide constructive feedback on reports."

        } catch as err {
            ; File read failed - warn user and use fallback
            MsgBox("Warning: Could not read system prompt: " . err.Message . "`n`n" .
                   "Using basic fallback prompt. For full functionality, please restore system_prompt files.",
                   "System Prompt Error", 48)
            return "You are a radiology report checking assistant. Provide constructive feedback on reports."
        }
    }

    ; Note: Prompt files are managed externally (installed with the app or
    ; restored from server).  GetDefaultPrompt() shows a warning and uses
    ; a fallback if the files are missing.

    static CreateDefaultConfig() {
        try {
            ; Delete existing config file first
            if FileExist(this.configFile)
                FileDelete(this.configFile)

            ; Create default configuration as clean JSON structure
            ; NOTE: System prompt is stored in system_prompt.txt, not in config.json
            defaultConfig := {
                api: {
                    provider: "claude",
                    claude_api_key: "",
                    gemini_api_key: "",
                    openai_api_key: "",
                    claude_verified_hash: "",
                    claude_verified_date: "",
                    gemini_verified_hash: "",
                    gemini_verified_date: "",
                    openai_verified_hash: "",
                    openai_verified_date: ""
                },
                settings: {
                    comprehensive_claude_model: Constants.GetDefaultModel("claude", "comprehensive"),
                    comprehensive_gemini_model: Constants.GetDefaultModel("gemini", "comprehensive"),
                    comprehensive_openai_model: Constants.GetDefaultModel("openai", "comprehensive"),
                    proofreading_claude_model: Constants.GetDefaultModel("claude", "proofreading"),
                    proofreading_gemini_model: Constants.GetDefaultModel("gemini", "proofreading"),
                    proofreading_openai_model: Constants.GetDefaultModel("openai", "proofreading"),
                    startup_enabled: true,
                    max_review_files: 10,
                    prompt_type: "comprehensive",
                    targeted_review_enabled: false,
                    debug_logging: false,
                    dark_mode_enabled: true
                },
                beta: {
                    demographic_extraction_enabled: false,
                    mode_override_hotkeys: false,
                    powerscribe_autoselect: false,
                    dicom_cache_directory: Constants.DICOM_CACHE_DEFAULT
                }
            }

            ; Convert to JSON and save with UTF-8 encoding
            jsonString := this._MapToJSON(defaultConfig)
            FileAppend(jsonString, this.configFile, "UTF-8")
            
        } catch as err {
            throw Error("Could not create configuration file: " err.Message)
        }
    }

    static LoadConfig() {
        ; Ensure the configuration directory exists
        if !DirExist(this.configDir) {
            DirCreate(this.configDir)
        }

        ; Migrate from old INI config if it exists
        oldIniFile := this.configDir "\config.ini"
        if FileExist(oldIniFile) && !FileExist(this.configFile) {
            this._MigrateFromINI(oldIniFile)
        }
        
        ; Check if config file exists and create it if it doesn't
        if !FileExist(this.configFile) {
            try {
                this.CreateDefaultConfig()
            } catch as err {
                MsgBox("Failed to create config file: " err.Message, "Configuration Error", 16)
                ExitApp
            }
        }
        
        ; Load the JSON configuration  
        try {
            jsonContent := FileRead(this.configFile, "UTF-8")
            
            ; Simple approach: manually extract values using RegEx
            this.config := Map()
            
            ; API section
            provider := this._ExtractJSONValue(jsonContent, "provider")
            claudeApiKey := this._ExtractJSONValue(jsonContent, "claude_api_key")
            geminiApiKey := this._ExtractJSONValue(jsonContent, "gemini_api_key")
            openaiApiKey := this._ExtractJSONValue(jsonContent, "openai_api_key")

            ; Handle migration from old single api_key format
            oldApiKey := this._ExtractJSONValue(jsonContent, "api_key")
            if (oldApiKey != "" && claudeApiKey = "") {
                claudeApiKey := oldApiKey
            }

            ; Load provider-specific verification hashes
            claudeVerifiedHash := this._ExtractJSONValue(jsonContent, "claude_verified_hash")
            claudeVerifiedDate := this._ExtractJSONValue(jsonContent, "claude_verified_date")
            geminiVerifiedHash := this._ExtractJSONValue(jsonContent, "gemini_verified_hash")
            geminiVerifiedDate := this._ExtractJSONValue(jsonContent, "gemini_verified_date")
            openaiVerifiedHash := this._ExtractJSONValue(jsonContent, "openai_verified_hash")
            openaiVerifiedDate := this._ExtractJSONValue(jsonContent, "openai_verified_date")

            ; Handle migration from old single hash format
            oldHash := this._ExtractJSONValue(jsonContent, "verified_key_hash")
            oldDate := this._ExtractJSONValue(jsonContent, "verified_date")
            if (oldHash != "" && claudeVerifiedHash = "") {
                claudeVerifiedHash := oldHash
                claudeVerifiedDate := oldDate
            }

            this.config["API"] := Map(
                "provider", provider != "" ? provider : "claude",
                "claude_api_key", claudeApiKey,
                "gemini_api_key", geminiApiKey,
                "openai_api_key", openaiApiKey,
                "claude_verified_hash", claudeVerifiedHash,
                "claude_verified_date", claudeVerifiedDate,
                "gemini_verified_hash", geminiVerifiedHash,
                "gemini_verified_date", geminiVerifiedDate,
                "openai_verified_hash", openaiVerifiedHash,
                "openai_verified_date", openaiVerifiedDate
            )

            ; NOTE: System prompt is read from system_prompt.txt file, not stored in config

            ; Settings section
            ; Load mode-specific models
            comprehensiveClaudeModel := this._ExtractJSONValue(jsonContent, "comprehensive_claude_model")
            comprehensiveGeminiModel := this._ExtractJSONValue(jsonContent, "comprehensive_gemini_model")
            comprehensiveOpenaiModel := this._ExtractJSONValue(jsonContent, "comprehensive_openai_model")
            proofreadingClaudeModel := this._ExtractJSONValue(jsonContent, "proofreading_claude_model")
            proofreadingGeminiModel := this._ExtractJSONValue(jsonContent, "proofreading_gemini_model")
            proofreadingOpenaiModel := this._ExtractJSONValue(jsonContent, "proofreading_openai_model")

            ; Handle migration from old single model format
            oldClaudeModel := this._ExtractJSONValue(jsonContent, "claude_model")
            oldGeminiModel := this._ExtractJSONValue(jsonContent, "gemini_model")
            oldModel := this._ExtractJSONValue(jsonContent, "model")

            ; Migrate old format to new mode-specific format
            if (oldModel != "" && comprehensiveClaudeModel = "") {
                comprehensiveClaudeModel := oldModel
            }
            if (oldClaudeModel != "" && comprehensiveClaudeModel = "") {
                ; Migrate old claude_model to both modes
                comprehensiveClaudeModel := oldClaudeModel
                proofreadingClaudeModel := oldClaudeModel
            }
            if (oldGeminiModel != "" && comprehensiveGeminiModel = "") {
                ; Migrate old gemini_model to both modes
                comprehensiveGeminiModel := oldGeminiModel
                proofreadingGeminiModel := oldGeminiModel
            }

            startupEnabled := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "startup_enabled"))
            maxReviewFiles := this._ExtractJSONValue(jsonContent, "max_review_files")
            maxReviewFiles := (maxReviewFiles != "" && maxReviewFiles > 0) ? Integer(maxReviewFiles) : 10
            promptType := this._ExtractJSONValue(jsonContent, "prompt_type")
            promptType := (promptType != "" && (promptType = "comprehensive" || promptType = "proofreading")) ? promptType : "comprehensive"
            targetedReviewEnabled := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "targeted_review_enabled"))
            ; Default to false if not explicitly set (beta feature, disabled by default)
            if (this._ExtractJSONValue(jsonContent, "targeted_review_enabled") = "") {
                targetedReviewEnabled := false
            }
            debugLogging := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "debug_logging"))
            darkModeEnabled := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "dark_mode_enabled"))
            ; Default to true if not explicitly set (dark mode is default)
            if (this._ExtractJSONValue(jsonContent, "dark_mode_enabled") = "") {
                darkModeEnabled := true
            }

            ; Load Beta settings
            demographicExtractionEnabled := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "demographic_extraction_enabled"))
            modeOverrideHotkeys := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "mode_override_hotkeys"))
            powerscribeAutoselect := this._ParseJSONBoolean(this._ExtractJSONValue(jsonContent, "powerscribe_autoselect"))
            dicomCacheDirectory := this._ExtractJSONValue(jsonContent, "dicom_cache_directory")
            if (dicomCacheDirectory = "") {
                dicomCacheDirectory := Constants.DICOM_CACHE_DEFAULT
            }

            this.config["Settings"] := Map(
                "comprehensive_claude_model", comprehensiveClaudeModel != "" ? comprehensiveClaudeModel : Constants.GetDefaultModel("claude", "comprehensive"),
                "comprehensive_gemini_model", comprehensiveGeminiModel != "" ? comprehensiveGeminiModel : Constants.GetDefaultModel("gemini", "comprehensive"),
                "comprehensive_openai_model", comprehensiveOpenaiModel != "" ? comprehensiveOpenaiModel : Constants.GetDefaultModel("openai", "comprehensive"),
                "proofreading_claude_model", proofreadingClaudeModel != "" ? proofreadingClaudeModel : Constants.GetDefaultModel("claude", "proofreading"),
                "proofreading_gemini_model", proofreadingGeminiModel != "" ? proofreadingGeminiModel : Constants.GetDefaultModel("gemini", "proofreading"),
                "proofreading_openai_model", proofreadingOpenaiModel != "" ? proofreadingOpenaiModel : Constants.GetDefaultModel("openai", "proofreading"),
                "startup_enabled", startupEnabled,
                "max_review_files", maxReviewFiles,
                "prompt_type", promptType,
                "targeted_review_enabled", targetedReviewEnabled,
                "debug_logging", debugLogging,
                "dark_mode_enabled", darkModeEnabled
            )

            this.config["Beta"] := Map(
                "demographic_extraction_enabled", demographicExtractionEnabled,
                "mode_override_hotkeys", modeOverrideHotkeys,
                "powerscribe_autoselect", powerscribeAutoselect,
                "dicom_cache_directory", dicomCacheDirectory
            )

            ; Validate loaded configuration and fix any issues
            this._ValidateAndFixConfig()

            ; BUGFIX: Sync startup config with actual shortcut state
            this._SyncStartupState()

            ; Check if we need to migrate plaintext API key to encrypted
            ; Do this first, before any prompts
            this._MigrateAPIKeyIfNeeded()

            ; Note: First-time API key setup prompt is now triggered from main script
            ; after tray menu initialization completes (see report-check.ahk)
            ; This prevents blocking dialogs from interfering with tray menu setup

        } catch as err {
            MsgBox("Error loading configuration: " err.Message, "Configuration Error", 16)
            
            result := MsgBox("Would you like to reset to default configuration?", 
                           "Configuration Error", 4)
            if (result = "Yes") {
                try {
                    this.CreateDefaultConfig()
                    this.LoadConfig()
                } catch as err2 {
                    MsgBox("Failed to create new configuration: " err2.Message, "Fatal Error", 16)
                    ExitApp
                }
            } else {
                ExitApp
            }
        }
    }

    static SaveConfig() {
        try {
            ; Convert config Maps back to nested object structure
            api := this.config["API"]
            settings := this.config["Settings"]

            ; Handle API keys — obfuscate plaintext keys before writing to disk
            rawClaudeKey := api.Get("claude_api_key", "")
            rawGeminiKey := api.Get("gemini_api_key", "")
            rawOpenaiKey := api.Get("openai_api_key", "")

            encryptedClaudeKey := ""
            if (rawClaudeKey != "") {
                encryptedClaudeKey := this.IsAPIKeyEncrypted(rawClaudeKey)
                    ? rawClaudeKey : this.ObfuscateAPIKey(rawClaudeKey)
            }

            encryptedGeminiKey := ""
            if (rawGeminiKey != "") {
                encryptedGeminiKey := this.IsAPIKeyEncrypted(rawGeminiKey)
                    ? rawGeminiKey : this.ObfuscateAPIKey(rawGeminiKey)
            }

            encryptedOpenaiKey := ""
            if (rawOpenaiKey != "") {
                encryptedOpenaiKey := this.IsAPIKeyEncrypted(rawOpenaiKey)
                    ? rawOpenaiKey : this.ObfuscateAPIKey(rawOpenaiKey)
            }

            ; NOTE: System prompt is stored in system_prompt.txt file, not in config.json
            beta := this.config["Beta"]
            configData := {
                api: {
                    provider: api.Get("provider", "claude"),
                    claude_api_key: encryptedClaudeKey,
                    gemini_api_key: encryptedGeminiKey,
                    openai_api_key: encryptedOpenaiKey,
                    claude_verified_hash: api.Get("claude_verified_hash", ""),
                    claude_verified_date: api.Get("claude_verified_date", ""),
                    gemini_verified_hash: api.Get("gemini_verified_hash", ""),
                    gemini_verified_date: api.Get("gemini_verified_date", ""),
                    openai_verified_hash: api.Get("openai_verified_hash", ""),
                    openai_verified_date: api.Get("openai_verified_date", "")
                },
                settings: {
                    comprehensive_claude_model: settings.Get("comprehensive_claude_model", Constants.GetDefaultModel("claude", "comprehensive")),
                    comprehensive_gemini_model: settings.Get("comprehensive_gemini_model", Constants.GetDefaultModel("gemini", "comprehensive")),
                    comprehensive_openai_model: settings.Get("comprehensive_openai_model", Constants.GetDefaultModel("openai", "comprehensive")),
                    proofreading_claude_model: settings.Get("proofreading_claude_model", Constants.GetDefaultModel("claude", "proofreading")),
                    proofreading_gemini_model: settings.Get("proofreading_gemini_model", Constants.GetDefaultModel("gemini", "proofreading")),
                    proofreading_openai_model: settings.Get("proofreading_openai_model", Constants.GetDefaultModel("openai", "proofreading")),
                    startup_enabled: settings.Get("startup_enabled", true),
                    max_review_files: settings.Get("max_review_files", 10),
                    prompt_type: settings.Get("prompt_type", "comprehensive"),
                    targeted_review_enabled: settings.Get("targeted_review_enabled", false),
                    debug_logging: settings.Get("debug_logging", false),
                    dark_mode_enabled: settings.Get("dark_mode_enabled", true)
                },
                beta: {
                    demographic_extraction_enabled: beta.Get("demographic_extraction_enabled", false),
                    mode_override_hotkeys: beta.Get("mode_override_hotkeys", false),
                    powerscribe_autoselect: beta.Get("powerscribe_autoselect", false),
                    dicom_cache_directory: beta.Get("dicom_cache_directory", Constants.DICOM_CACHE_DEFAULT)
                }
            }

            ; Convert to JSON and save
            jsonString := this._MapToJSON(configData)

            ; Atomic write: write to temp file first, then move to replace config file
            ; This prevents data loss if write fails mid-operation
            tempFile := this.configFile . ".tmp"

            ; Delete leftover temp file to prevent FileAppend from appending
            ; to stale data from a previous failed save
            if FileExist(tempFile)
                FileDelete(tempFile)

            ; Write to temp file with UTF-8 encoding
            FileAppend(jsonString, tempFile, "UTF-8")

            ; Verify temp file was created successfully
            if (!FileExist(tempFile)) {
                throw Error("Failed to write temporary config file")
            }

            ; Atomic replace (1 = overwrite if exists)
            FileMove(tempFile, this.configFile, 1)

            return true
        } catch as err {
            ; Clean up temp file if it exists
            try {
                if FileExist(tempFile)
                    FileDelete(tempFile)
            }
            return false
        }
    }


    static GetCurrentPrompt(modeOverride := "") {
        ; Use cached prompt system for performance (no disk I/O)
        ; If cache is not initialized, fall back to legacy disk read
        if (PromptCache.IsInitialized()) {
            return PromptCache.GetPrompt(modeOverride)
        } else {
            Logger.Warning("PromptCache not initialized, falling back to disk read")
            return this.GetDefaultPrompt(modeOverride)
        }
    }
    
    ; DEPRECATED: User message prefix is no longer used
    ; Date information has been moved to system prompts for better architecture
    ; This function is kept for reference but should not be called
    ; static GetUserMessagePrefix() {
    ;     ; Simple date reference in European format
    ;     currentDate := FormatTime(, "d/M/yyyy")
    ;     currentDateLong := FormatTime(, "d MMMM yyyy")
    ;
    ;     ; Concise date and instruction
    ;     dateInfo := "CRITICAL: The current year is " . A_YYYY . ". Today's date is " . currentDate . " (" . currentDateLong . ", DD/MM/YYYY format). You are in New Zealand - ALL dates use DD/MM/YYYY format (day/month/year). Examples: 05/03/" . A_YYYY . " = 5 March " . A_YYYY . " (NOT May 3, " . A_YYYY . "), 08/07/" . (A_YYYY - 1) . " = 8 July " . (A_YYYY - 1) . " (NOT 7 August " . (A_YYYY - 1) . "). When checking dates: (1) Parse all dates as DD/MM/YYYY, (2) Comparison studies must have dates BEFORE today (" . currentDate . "), (3) Only flag if a comparison date is AFTER today or creates a logical impossibility. DO NOT flag comparison dates that are appropriately in the past."
    ;
    ;     ; Single query instruction to prevent conversation mode responses
    ;     queryInfo := " This is a single, standalone review request - provide your complete analysis without offering follow-up questions or suggesting further conversation."
    ;
    ;     ; Brief instruction
    ;     instruction := "Please review this radiology report:"
    ;
    ;     return dateInfo . queryInfo . "`n`n" . instruction . "`n`n"
    ; }

    ; Get current provider (claude or gemini)
    static GetProvider() {
        return this.config["API"].Get("provider", "claude")
    }

    ; Set current provider
    static SetProvider(provider) {
        this.config["API"]["provider"] := provider
    }

    ; Get API key for specific provider
    static GetProviderAPIKey(provider) {
        keyField := provider . "_api_key"
        apiKey := this.config["API"].Get(keyField, "")

        ; If key is obfuscated, de-obfuscate it
        if (this.IsAPIKeyEncrypted(apiKey)) {
            return this.DeobfuscateAPIKey(apiKey)
        }

        ; If it's plaintext, return as-is (for backward compatibility)
        return apiKey
    }

    ; Get model for specific provider based on current mode
    static GetProviderModel(provider, modeOverride := "") {
        ; Get current mode, or use override if provided
        promptType := "comprehensive"
        if (modeOverride != "" && (modeOverride = "comprehensive" || modeOverride = "proofreading")) {
            promptType := modeOverride
        } else {
            promptType := this.config["Settings"].Get("prompt_type", "comprehensive")
        }

        ; Build mode-specific model field name
        modelField := promptType . "_" . provider . "_model"

        defaultModel := Constants.GetDefaultModel(provider, promptType)
        return this.config["Settings"].Get(modelField, defaultModel)
    }

    ; Legacy methods for backward compatibility
    static GetAPIKey() {
        provider := this.GetProvider()
        return this.GetProviderAPIKey(provider)
    }

    static GetModel() {
        provider := this.GetProvider()
        return this.GetProviderModel(provider)
    }
    
    static _setupGui := ""
    static _setupKeyVerified := false

    static _PromptForAPIKey() {
        ; Create WebView-based setup dialog matching the new GUI styling
        try {
            this._setupKeyVerified := false

            isDark := this.config.Has("Settings") && this.config["Settings"].Has("dark_mode_enabled")
                ? !!this.config["Settings"]["dark_mode_enabled"] : true
            htmlPath := "file:///" StrReplace(A_ScriptDir "\lib\gui\setup.html", "\", "/") "?theme=" (isDark ? "dark" : "light")

            this._setupGui := WebViewGui("+AlwaysOnTop -Caption",,, {})
            this._setupGui.OnEvent("Close", (*) => this._OnSetupClose())
            this._setupGui.Navigate(htmlPath)

            ; Register callbacks
            this._setupGui.AddCallbackToScript("TestSetupKey", ObjBindMethod(this, "_OnTestSetupKey"))
            this._setupGui.AddCallbackToScript("SaveSetupKey", ObjBindMethod(this, "_OnSaveSetupKey"))
            this._setupGui.AddCallbackToScript("SkipSetup", ObjBindMethod(this, "_OnSkipSetup"))

            this._setupGui.Show("w500 h480")
        } catch as err {
            Logger.Warning("First-time setup dialog failed to display", {error: err.Message})
        }
    }

    static _OnSetupClose() {
        if (this._setupGui != "") {
            this._setupGui.Destroy()
            this._setupGui := ""
        }
        NotifyInfo("Setup Incomplete", "API key setup skipped. You can configure it later in Settings.", 4000)
    }

    static _OnSkipSetup(wv := "") {
        if (this._setupGui != "") {
            this._setupGui.Destroy()
            this._setupGui := ""
        }
        NotifyInfo("Setup Incomplete", "API key setup skipped. You can configure it later in Settings.", 4000)
    }

    static _OnTestSetupKey(wv, rawFormData) {
        try {
            formData := this._ParseSetupJSON(rawFormData)
            apiKey := Trim(formData.Get("APIKey", ""))
            provider := formData.Get("Provider", "claude")

            if (apiKey = "") {
                this._SetupStatus("Please enter an API key first", "error")
                return
            }

            ; Show testing status and disable buttons
            this._SetupStatus("Testing API key...", "info")
            this._setupGui.ExecuteScriptAsync("setButtonsEnabled(false)")

            ; Verify with server (without notifications — we'll update the UI directly)
            result := this.VerifyAndSaveAPIKey(apiKey, false, provider)

            if (result.success) {
                this._setupKeyVerified := true
                this._SetupStatus("API key verified successfully!", "success")
            } else {
                this._setupKeyVerified := false
                this._SetupStatus("Verification failed: " result.error, "error")
            }

            this._setupGui.ExecuteScriptAsync("setButtonsEnabled(true)")
        } catch as err {
            this._SetupStatus("Error testing key: " err.Message, "error")
            this._setupGui.ExecuteScriptAsync("setButtonsEnabled(true)")
        }
    }

    static _OnSaveSetupKey(wv, rawFormData) {
        try {
            formData := this._ParseSetupJSON(rawFormData)
            apiKey := Trim(formData.Get("APIKey", ""))
            provider := formData.Get("Provider", "claude")

            if (apiKey = "") {
                this._SetupStatus("Please enter an API key", "error")
                return
            }

            ; Provider-specific format validation
            if (provider = "claude") {
                if (!this.ValidateAPIKey(apiKey)) {
                    this._SetupStatus("Invalid Claude API key format", "error")
                    return
                }
            } else if (provider = "gemini") {
                if (StrLen(apiKey) < 20) {
                    this._SetupStatus("Invalid Gemini API key format", "error")
                    return
                }
            } else if (provider = "openai") {
                validation := SharedUtils.ValidateOpenAIAPIKey(apiKey)
                if (!validation.valid) {
                    this._SetupStatus(validation.error, "error")
                    return
                }
            }

            ; Save the API key
            if (!this._setupKeyVerified) {
                keyField := provider . "_api_key"
                this.config["API"][keyField] := apiKey
            }
            this.SetProvider(provider)
            this.SaveConfig()

            ; Close the setup dialog
            if (this._setupGui != "") {
                this._setupGui.Destroy()
                this._setupGui := ""
            }

            if (this._setupKeyVerified) {
                NotifySuccess("Setup Complete", "Verified API key saved successfully")
            } else {
                NotifySuccess("Setup Complete", "API key saved successfully")
            }
        } catch as err {
            this._SetupStatus("Error saving: " err.Message, "error")
        }
    }

    static _SetupStatus(message, type) {
        if (this._setupGui = "")
            return
        escapedMsg := StrReplace(message, "\", "\\")
        escapedMsg := StrReplace(escapedMsg, "'", "\'")
        escapedMsg := StrReplace(escapedMsg, "`n", "\n")
        this._setupGui.ExecuteScriptAsync("setStatus('" escapedMsg "', '" type "')")
    }

    static _ParseSetupJSON(jsonStr) {
        ; Remove outer quotes if present
        jsonStr := Trim(jsonStr, '"')
        data := Map()
        pos := 1
        while (pos := RegExMatch(jsonStr, '"(\w+)"\s*:\s*("([^"]*)"|true|false|(\d+))', &match, pos)) {
            key := match[1]
            if (match[3] != "") {
                value := match[3]
            } else if (match[0] ~= "true") {
                value := true
            } else if (match[0] ~= "false") {
                value := false
            } else {
                value := match[4]
            }
            data[key] := value
            pos += StrLen(match[0])
        }
        return data
    }

    ; Verify API key with provider servers via Python backend
    static _VerifyAPIKeyWithServer(apiKey, provider := "") {
        try {
            if (provider = "")
                provider := this.GetProvider()

            Logger.Info("Validating API key via Python backend", {provider: provider})

            ; Format validation stays in AHK (instant, no subprocess needed)
            if (provider = "claude") {
                formatCheck := SharedUtils.ValidateClaudeAPIKey(apiKey)
            } else if (provider = "gemini") {
                formatCheck := SharedUtils.ValidateGeminiAPIKey(apiKey)
            } else if (provider = "openai") {
                formatCheck := SharedUtils.ValidateOpenAIAPIKey(apiKey)
            } else {
                return {success: false, error: "Unknown provider: " . provider}
            }
            if (!formatCheck.valid) {
                Logger.Warning(provider . " API key format invalid", {error: formatCheck.error})
                return {success: false, error: formatCheck.error}
            }

            ; Delegate server verification to Python backend
            pythonPath := GetPythonPath()
            if (pythonPath = "")
                return {success: false, error: "Python not found - check Settings"}

            requestDir := A_Temp "\ReportCheck"
            if (!DirExist(requestDir))
                DirCreate(requestDir)

            requestFile := requestDir "\request.json"
            responseFile := requestDir "\response.json"
            try FileDelete(requestFile)
            try FileDelete(responseFile)

            request := '{"command":"test_api_key"'
                     . ',"provider":"' . provider . '"'
                     . ',"api_key":"' . apiKey . '"'
                     . ',"config_path":"' . StrReplace(this.configFile, "\", "\\") . '"'
                     . '}'
            FileAppend(request, requestFile, "UTF-8-RAW")

            RunWait('"' . pythonPath . '" "' . A_ScriptDir . '\backend.py" "' . requestFile . '"',, "Hide")

            if (!FileExist(responseFile))
                return {success: false, error: "Python backend did not respond"}

            responseJSON := FileRead(responseFile, "UTF-8")
            success := InStr(responseJSON, '"success": true') || InStr(responseJSON, '"success":true')

            if (success) {
                Logger.Info(provider . " API key validation successful")
                return {success: true, error: ""}
            } else {
                errorMsg := _ExtractJSONStringValue(responseJSON, "error")
                if (errorMsg = "")
                    errorMsg := "API key validation failed"
                Logger.Warning(provider . " API key validation failed", {error: errorMsg})
                return {success: false, error: errorMsg}
            }

        } catch as err {
            Logger.Error("API key verification error", {error: err.Message})
            return {success: false, error: "Verification failed: " . err.Message}
        }
    }

    static ValidateAPIKey(apiKey) {
        return SharedUtils.ValidateAPIKey(apiKey)
    }


    ; UPDATED: New method to check if startup is enabled - now reads from config
    static IsStartupEnabled() {
        ; Load from config if available, otherwise check shortcut
        if (this.config.Has("Settings") && this.config["Settings"].Has("startup_enabled")) {
            return !!this.config["Settings"]["startup_enabled"]
        }
        
        ; Fallback to checking shortcut existence
        return FileExist(this.startupShortcutPath) ? true : false
    }
    
    ; UPDATED: New method to toggle startup - now saves to config
    static ToggleStartup(enable) {
        success := false
        
        if (enable) {
            try {
                ; Get the correct paths dynamically
                targetPath := A_ScriptFullPath
                iconPath := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\RadReview.ico"
                
                ; Create description using actual script name
                description := RegExReplace(A_ScriptName, "\.(exe|ahk)$", "") " - Radiology Report Review Tool"

                ; Create the shortcut
                FileCreateShortcut(
                    targetPath,              ; Target 
                    this.startupShortcutPath,
                    A_ScriptDir,        
                    "",                      
                    description,             
                    iconPath                 
                )
                success := true
            } catch as err {
                MsgBox("Failed to create startup shortcut: " err.Message, "Startup Error", 16)
                success := false
            }
        } else {
            try {
                if FileExist(this.startupShortcutPath)
                    FileDelete(this.startupShortcutPath)
                success := true
            } catch as err {
                MsgBox("Failed to remove startup shortcut: " err.Message, "Startup Error", 16)
                success := false
            }
        }

        ; Update config if operation was successful
        if (success) {
            if (!this.config.Has("Settings")) {
                this.config["Settings"] := Map()
            }
            this.config["Settings"]["startup_enabled"] := enable
        }
        
        return success
    }

    ; BUGFIX: Sync startup config with actual shortcut state on load
    static _SyncStartupState() {
        if (!this.config.Has("Settings")) {
            this.config["Settings"] := Map()
        }

        configEnabled := this.config["Settings"].Has("startup_enabled") ?
                        !!this.config["Settings"]["startup_enabled"] : false
        shortcutExists := FileExist(this.startupShortcutPath) ? true : false

        ; If config says enabled but shortcut doesn't exist, create it
        if (configEnabled && !shortcutExists) {
            this.ToggleStartup(true)
        }
        ; If config says disabled but shortcut exists, remove it
        else if (!configEnabled && shortcutExists) {
            this.ToggleStartup(false)
        }
    }
    
    ; JSON Helper Functions
    
    static _ExtractJSONValue(jsonContent, key) {
        ; Simple flat regex to extract a JSON value by key.
        ; LIMITATION: has no section awareness — finds the first matching key
        ; anywhere in the file.  This works because our config keys are currently
        ; unique across all sections, but would break if two sections ever shared
        ; a key name.  A proper JSON parser would fix this.
        pattern := '"' . key . '":\s*"([^"]*)"'
        if (RegExMatch(jsonContent, pattern, &match)) {
            return SharedUtils.UnescapeJSONString(match[1])
        }
        
        ; Try boolean/number pattern
        pattern := '"' . key . '":\s*([^,}\s]+)'
        if (RegExMatch(jsonContent, pattern, &match)) {
            return Trim(match[1])
        }
        
        return ""
    }
    
    ; Helper to parse JSON boolean values (handles both string and native booleans)
    static _ParseJSONBoolean(value) {
        if (value = "true" || value = true)
            return true
        if (value = "false" || value = false)
            return false
        if (value = "1" || value = 1)
            return true
        if (value = "0" || value = 0)
            return false
        return false  ; Default to false for any other value
    }
    
    static _MapToJSON(obj, indent := 0) {
        spaces := SharedUtils.RepeatChar("  ", indent)
        nextSpaces := SharedUtils.RepeatChar("  ", indent + 1)
        
        if (Type(obj) = "Map") {
            ; Convert Map to object notation
            result := "{`n"
            entries := []
            for key, value in obj {
                entries.Push(nextSpaces . '"' . SharedUtils.EscapeJSONString(key) . '": ' . this._MapToJSON(value, indent + 1))
            }
            result .= SharedUtils.JoinArray(entries, ",`n") . "`n" . spaces . "}"
            return result
        }
        else if (Type(obj) = "Object" || Type(obj) = "Map") {
            ; Handle regular objects
            result := "{`n"
            entries := []
            for key, value in obj.OwnProps() {
                entries.Push(nextSpaces . '"' . SharedUtils.EscapeJSONString(key) . '": ' . this._MapToJSON(value, indent + 1))
            }
            result .= SharedUtils.JoinArray(entries, ",`n") . "`n" . spaces . "}"
            return result
        }
        else if (Type(obj) = "Array") {
            result := "[`n"
            entries := []
            for value in obj {
                entries.Push(nextSpaces . this._MapToJSON(value, indent + 1))
            }
            result .= SharedUtils.JoinArray(entries, ",`n") . "`n" . spaces . "]"
            return result
        }
        else if (Type(obj) = "String") {
            return '"' . SharedUtils.EscapeJSONString(obj) . '"'
        }
        else if (Type(obj) = "Integer" || Type(obj) = "Float") {
            return String(obj)
        }
        else if (obj = true || obj = false) {
            return obj ? "true" : "false"
        }
        else {
            return "null"
        }
    }
    
    
    static _MigrateFromINI(iniFile) {
        try {
            ; Read existing INI config and migrate to JSON
            apiKey := IniRead(iniFile, "API", "api_key", "")
            
            defaultPrompt := IniRead(iniFile, "Prompts", "default_prompt", this.GetDefaultPrompt())
            customPrompt := IniRead(iniFile, "Prompts", "custom_prompt", "")
            useCustom := IniRead(iniFile, "Prompts", "use_custom_prompt", "false")
            
            apiUrl := IniRead(iniFile, "Settings", "api_url", "https://api.anthropic.com/v1/messages")
            model := IniRead(iniFile, "Settings", "model", "claude-sonnet-4-20250514")
            startupEnabled := IniRead(iniFile, "Settings", "startup_enabled", "1")
            
            ; Create JSON config with migrated data
            migratedConfig := {
                api: {
                    api_key: apiKey,
                    verified_key_hash: "",
                    verified_date: ""
                },
                prompts: {
                    default_prompt: defaultPrompt,
                    custom_prompt: customPrompt,
                    use_custom_prompt: (useCustom = "true")
                },
                settings: {
                    api_url: apiUrl,
                    model: model,
                    startup_enabled: (startupEnabled = "1")
                }
            }
            
            ; Save as JSON
            jsonString := this._MapToJSON(migratedConfig)
            FileAppend(jsonString, this.configFile, "UTF-8")
            
            ; Rename old INI file to backup
            FileMove(iniFile, iniFile . ".backup")
            
        } catch as err {
            ; If migration fails, just create default config
            this.CreateDefaultConfig()
        }
    }
    
    ; Migrate plaintext API keys to encrypted format if needed
    static _MigrateAPIKeyIfNeeded() {
        try {
            needsSave := false

            ; Check Claude key
            claudeKey := this.config["API"].Get("claude_api_key", "")
            if (claudeKey != "" && !this.IsAPIKeyEncrypted(claudeKey)) {
                needsSave := true
            }

            ; Check Gemini key
            geminiKey := this.config["API"].Get("gemini_api_key", "")
            if (geminiKey != "" && !this.IsAPIKeyEncrypted(geminiKey)) {
                needsSave := true
            }

            ; Check OpenAI key
            openaiKey := this.config["API"].Get("openai_api_key", "")
            if (openaiKey != "" && !this.IsAPIKeyEncrypted(openaiKey)) {
                needsSave := true
            }

            ; Single save to encrypt all plaintext keys at once
            if (needsSave) {
                this.SaveConfig()
            }
        } catch {
            ; If migration fails, continue with existing keys
        }
    }
    
    ; ==============================================
    ; API Key Verification Functions
    ; ==============================================
    
    ; Unified method to verify API key with server and save with persistence
    static VerifyAndSaveAPIKey(apiKey, showNotifications := true, provider := "") {
        try {
            ; Use current provider if not specified
            if (provider = "") {
                provider := this.GetProvider()
            }

            Logger.Info("Starting API key verification", {provider: provider})

            ; Verify with server (format validation is now done inside _VerifyAPIKeyWithServer)
            result := this._VerifyAPIKeyWithServer(apiKey, provider)

            if (result.success) {
                ; Save key and mark as verified in one operation
                keyField := provider . "_api_key"
                this.config["API"][keyField] := apiKey
                this.MarkAPIKeyVerified(apiKey, provider)
                this.SaveConfig()

                Logger.Info("API key verified and saved", {provider: provider})

                if (showNotifications) {
                    NotifySuccess("API Key Verified", "Key verified and saved successfully")
                }

                return {success: true, error: ""}
            } else {
                Logger.Warning("API key verification failed", {provider: provider, error: result.error})

                if (showNotifications) {
                    NotifyError("Verification Failed", result.error)
                }
                return {success: false, error: result.error}
            }

        } catch as err {
            if (showNotifications) {
                NotifyError("Verification Error", "Error during verification: " . err.Message)
            }
            return {success: false, error: "Error during verification: " . err.Message}
        }
    }
    
    ; Check if current API key is verified (provider-specific)
    static IsAPIKeyVerified(provider := "") {
        try {
            if (provider = "") {
                provider := this.GetProvider()
            }

            currentKey := this.GetProviderAPIKey(provider)  ; Get decrypted key
            if (currentKey = "")
                return false

            hashField := provider . "_verified_hash"
            storedHash := this.config["API"].Get(hashField, "")
            if (storedHash = "")
                return false

            ; Create hash of current key and compare
            currentHash := this._CreateVerificationHash(currentKey)
            return (currentHash = storedHash)
        } catch {
            return false
        }
    }

    ; Mark API key as verified (provider-specific)
    ; Mark API key as verified in memory (caller is responsible for calling SaveConfig)
    static MarkAPIKeyVerified(apiKey, provider := "") {
        try {
            if (provider = "") {
                provider := this.GetProvider()
            }

            verificationHash := this._CreateVerificationHash(apiKey)
            verificationDate := FormatTime(, "yyyy-MM-dd HH:mm:ss")

            hashField := provider . "_verified_hash"
            dateField := provider . "_verified_date"

            this.config["API"][hashField] := verificationHash
            this.config["API"][dateField] := verificationDate
        } catch {
            ; Ignore verification errors
        }
    }

    ; Get verification date for current key (provider-specific)
    static GetVerificationDate(provider := "") {
        if (provider = "") {
            provider := this.GetProvider()
        }

        if (this.IsAPIKeyVerified(provider)) {
            dateField := provider . "_verified_date"
            return this.config["API"].Get(dateField, "")
        }
        return ""
    }
    
    ; Create a simple hash for verification (not cryptographic security)
    static _CreateVerificationHash(apiKey) {
        if (apiKey = "")
            return ""
            
        ; Create a simple hash using key characteristics
        hash := StrLen(apiKey)
        if (StrLen(apiKey) >= 10) {
            hash .= "_" . Ord(SubStr(apiKey, 5, 1)) . Ord(SubStr(apiKey, 10, 1))
        }
        if (StrLen(apiKey) >= 20) {
            hash .= "_" . Ord(SubStr(apiKey, -5, 1))
        }
        return hash
    }
    
    ; ==============================================
    ; API Key Obfuscation Functions
    ; ==============================================
    ; NOTE: These use XOR with machine-specific data, which is trivially
    ; reversible by anyone with access to the machine.  The purpose is to
    ; prevent casual reading of keys in the config file, not to provide
    ; cryptographic security.

    ; Obfuscate API key using XOR with machine-specific data
    static ObfuscateAPIKey(plaintext) {
        if (plaintext = "")
            return ""
        
        ; Create machine+user specific key
        machineKey := A_ComputerName . "|" . A_UserName . "|" . this._GetSystemInfo()
        return this._XOREncrypt(plaintext, machineKey)
    }
    
    ; De-obfuscate API key using XOR with machine-specific data
    static DeobfuscateAPIKey(encrypted) {
        if (encrypted = "")
            return ""

        machineKey := A_ComputerName . "|" . A_UserName . "|" . this._GetSystemInfo()
        return this._XORDecrypt(encrypted, machineKey)
    }

    ; Backward-compatible aliases
    static EncryptAPIKey(plaintext) => this.ObfuscateAPIKey(plaintext)
    static DecryptAPIKey(encrypted) => this.DeobfuscateAPIKey(encrypted)
    
    ; Get system-specific info that stays consistent
    static _GetSystemInfo() {
        try {
            ; Try to get C: drive volume serial number
            for item in ComObjGet("winmgmts:").ExecQuery("SELECT VolumeSerialNumber FROM Win32_LogicalDisk WHERE DeviceID='C:'")
                return item.VolumeSerialNumber
        } catch {
            ; Fallback to script directory if WMI fails
            return StrReplace(A_ScriptDir, "\", "_")
        }
        return "fallback"
    }
    
    ; XOR-scramble text with key and return as hex string
    static _XOREncrypt(text, key) {
        result := ""
        keyLen := StrLen(key)

        Loop StrLen(text) {
            textChar := Ord(SubStr(text, A_Index, 1))
            keyChar := Ord(SubStr(key, Mod(A_Index - 1, keyLen) + 1, 1))
            result .= Chr(textChar ^ keyChar)
        }

        return this._ToHex(result)
    }

    ; Reverse XOR-scramble (symmetric — same operation as encrypt)
    static _XORDecrypt(encrypted, key) {
        try {
            binaryData := this._FromHex(encrypted)
            result := ""
            keyLen := StrLen(key)

            Loop StrLen(binaryData) {
                encChar := Ord(SubStr(binaryData, A_Index, 1))
                keyChar := Ord(SubStr(key, Mod(A_Index - 1, keyLen) + 1, 1))
                result .= Chr(encChar ^ keyChar)
            }

            return result
        } catch {
            return ""
        }
    }

    ; Encode a string as uppercase hex (two hex chars per character)
    static _ToHex(str) {
        result := ""
        Loop StrLen(str) {
            result .= Format("{:02X}", Ord(SubStr(str, A_Index, 1)))
        }
        return result
    }

    ; Decode a hex string back to characters
    static _FromHex(hexStr) {
        try {
            result := ""
            Loop StrLen(hexStr) // 2 {
                hex := SubStr(hexStr, (A_Index - 1) * 2 + 1, 2)
                if (hex != "") {
                    result .= Chr("0x" . hex)
                }
            }
            return result
        } catch {
            return ""
        }
    }
    
    ; Check if API key is obfuscated (i.e. stored as hex-encoded XOR output rather than plaintext)
    static IsAPIKeyEncrypted(keyData) {
        ; Try to de-obfuscate — if the result doesn't look like a known key format, it's plaintext
        if (keyData = "")
            return false

        ; If it starts with sk-ant-, it's a plaintext Claude key
        if (SubStr(keyData, 1, 7) = "sk-ant-")
            return false

        ; If it starts with "AI", it's likely a plaintext Gemini key
        if (SubStr(keyData, 1, 2) = "AI")
            return false

        ; If it starts with "sk-", it's likely a plaintext OpenAI key
        if (SubStr(keyData, 1, 3) = "sk-" && SubStr(keyData, 1, 7) != "sk-ant-")
            return false

        ; Try to decrypt and see if result looks like an API key (Claude, Gemini, or OpenAI)
        try {
            decrypted := this.DeobfuscateAPIKey(keyData)
            ; Check if de-obfuscated result looks like a Claude, Gemini, or OpenAI key
            isClaude := (SubStr(decrypted, 1, 7) = "sk-ant-")
            isGemini := (SubStr(decrypted, 1, 2) = "AI" && StrLen(decrypted) >= 30)
            isOpenAI := (SubStr(decrypted, 1, 3) = "sk-" && SubStr(decrypted, 1, 7) != "sk-ant-" && StrLen(decrypted) >= 20)
            return (isClaude || isGemini || isOpenAI)
        } catch {
            return false
        }
    }

    ; ==============================================
    ; Configuration Validation
    ; ==============================================

    ; Validate and fix loaded configuration
    ; Ensures all values are within valid ranges and of correct types
    static _ValidateAndFixConfig() {
        settings := this.config["Settings"]
        fixed := false

        ; Validate models for all providers and modes using Constants registry
        for provider in ["claude", "gemini", "openai"] {
            for mode in ["comprehensive", "proofreading"] {
                field := mode . "_" . provider . "_model"
                currentModel := settings.Get(field, "")
                if (currentModel = "" || !Constants.IsValidModel(currentModel, provider)) {
                    defaultModel := Constants.GetDefaultModel(provider, mode)
                    if (currentModel != defaultModel) {
                        Logger.Warning("Invalid " . mode . " " . provider . " model, resetting to default", {model: currentModel})
                        settings[field] := defaultModel
                        fixed := true
                    }
                }
            }
        }

        ; Validate max_review_files range
        maxReviewFiles := settings.Get("max_review_files", 10)
        if (!IsInteger(maxReviewFiles) || maxReviewFiles < 1 || maxReviewFiles > 100) {
            Logger.Warning("Invalid max_review_files value, resetting to default", {value: maxReviewFiles})
            settings["max_review_files"] := 10
            fixed := true
        }

        ; Validate prompt_type
        promptType := settings.Get("prompt_type", "comprehensive")
        if (promptType != "comprehensive" && promptType != "proofreading") {
            Logger.Warning("Invalid prompt_type value, resetting to default", {value: promptType})
            settings["prompt_type"] := "comprehensive"
            fixed := true
        }

        ; Validate provider
        provider := this.config["API"].Get("provider", "claude")
        if (provider != "claude" && provider != "gemini" && provider != "openai") {
            Logger.Warning("Invalid provider value, resetting to default", {value: provider})
            this.config["API"]["provider"] := "claude"
            fixed := true
        }

        ; Fix over-escaped DICOM cache directory (caused by prior auto-save bug)
        beta := this.config["Beta"]
        dicomDir := beta.Get("dicom_cache_directory", "")
        if (dicomDir != "" && InStr(dicomDir, "\\")) {
            ; Collapse any runs of multiple backslashes down to single backslashes
            while (InStr(dicomDir, "\\")) {
                dicomDir := StrReplace(dicomDir, "\\", "\")
            }
            beta["dicom_cache_directory"] := dicomDir
            Logger.Warning("Fixed over-escaped DICOM cache directory path")
            fixed := true
        }

        ; If any fixes were made, save the corrected configuration
        if (fixed) {
            Logger.Info("Configuration validation fixed issues, saving corrected config")
            this.SaveConfig()
        }
    }
}