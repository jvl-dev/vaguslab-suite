; ==============================================
; Settings GUI Class - WebViewToo Modern UI
; ==============================================
; Handles GUI creation and event routing using WebViewToo
; Business logic delegated to SettingsPresenter
; Validation logic delegated to SettingsValidator

class SettingsGui {
    static wvGui := ""
    static isUpdating := false
    static originalWindowTitle := "Report Check Settings"
    static updateState := "check"
    static newestUpdateVersion := ""
    static newestUpdateSHA256 := ""
    static lastTestedKey := ""
    static lastTestResult := false
    static populatedProvider := ""
    static _dicomLockTimer := 0

    ; ==========================================
    ; Public API - Main Entry Point
    ; ==========================================
    static Show() {
        ; Block opening settings during update process
        if (this.isUpdating) {
            if (this.wvGui != "") {
                this._ShowModal("Update In Progress", "Cannot open settings while an update is in progress.<br><br>Please wait for the update to complete.", "warning")
            } else {
                MsgBox("Cannot open settings while an update is in progress.`n`nPlease wait for the update to complete.", "Update In Progress", 48)
            }
            return
        }

        ; Create WebViewGui window
        this.wvGui := WebViewGui("+Resize -Caption",,, {})
        this.wvGui.OnEvent("Close", (*) => this._OnCloseSettings())

        ; Set custom icon if available
        try {
            iconPath := A_ScriptDir . "\RadReview.ico"
            if FileExist(iconPath) {
                ; Note: WebViewGui doesn't support SetIcon directly, but the icon is set via the .exe
            }
        }

        ; Navigate to settings page (pass theme via query param to prevent flash)
        isDark := ConfigManager.config.Has("Settings") && ConfigManager.config["Settings"].Has("dark_mode_enabled")
            ? !!ConfigManager.config["Settings"]["dark_mode_enabled"] : true
        htmlPath := "file:///" StrReplace(A_ScriptDir "\lib\gui\settings.html", "\", "/") "?theme=" (isDark ? "dark" : "light")
        this.wvGui.Navigate(htmlPath)

        ; Register all JS → AHK callback functions
        this._RegisterCallbacks()

        ; Show the window
        this.wvGui.Show("w700 h850")

        ; Populate form after a short delay (ensures page is loaded)
        SetTimer(ObjBindMethod(this, "_PopulateForm"), -500)

        ; Start DICOM lock status polling (updates every 3 seconds)
        this._dicomLockTimer := ObjBindMethod(this, "_RefreshDicomLockStatus")
        SetTimer(this._dicomLockTimer, 3000)
    }

    ; ==========================================
    ; Callback Registration
    ; ==========================================
    static _RegisterCallbacks() {
        this.wvGui.AddCallbackToScript("AutoSaveSettings", ObjBindMethod(this, "_OnAutoSaveSettings"))
        this.wvGui.AddCallbackToScript("CloseSettings", ObjBindMethod(this, "_OnCloseSettings"))
        this.wvGui.AddCallbackToScript("MinimizeWindow", ObjBindMethod(this, "_OnMinimizeWindow"))
        this.wvGui.AddCallbackToScript("TestAPIKey", ObjBindMethod(this, "_OnTestAPIKey"))
        this.wvGui.AddCallbackToScript("ReloadFromFile", ObjBindMethod(this, "_OnReloadFromFile"))
        this.wvGui.AddCallbackToScript("RestoreFromServer", ObjBindMethod(this, "_OnRestoreFromServer"))
        this.wvGui.AddCallbackToScript("ConfirmRestoreFromServer", ObjBindMethod(this, "_OnConfirmRestoreFromServer"))
        this.wvGui.AddCallbackToScript("BrowseDicomCache", ObjBindMethod(this, "_OnBrowseDicomCache"))
        this.wvGui.AddCallbackToScript("DiagnoseKeys", ObjBindMethod(this, "_OnDiagnoseKeys"))
        this.wvGui.AddCallbackToScript("RetryDiagnoseKeys", ObjBindMethod(this, "_ShowDiagnosticDialog"))
        this.wvGui.AddCallbackToScript("OpenReadme", ObjBindMethod(this, "_OnOpenReadme"))
        this.wvGui.AddCallbackToScript("OnUpdateClick", ObjBindMethod(this, "_OnUpdateClick"))
        this.wvGui.AddCallbackToScript("CancelUpdate", ObjBindMethod(this, "_OnCancelUpdate"))
    }

    ; ==========================================
    ; Form Population (AHK → JS)
    ; ==========================================
    static _PopulateForm() {
        js := ""

        ; Get current config
        config := ConfigManager.config
        api := config["API"]
        settings := config["Settings"]
        beta := config["Beta"]

        ; Current provider
        provider := api.Get("provider", "claude")
        this.populatedProvider := provider

        ; Mode Tab - Review Mode
        mode := settings.Get("prompt_type", "comprehensive")
        js .= "setRadio('reviewMode', '" mode "');"

        ; Update mode warning visibility
        js .= "updateModeWarning();"

        ; Prompts Tab - Update mode display
        promptData := SettingsPresenter.GetPromptData(mode)
        js .= "setText('promptsModeText', 'Current Mode: " this._EscapeJS(promptData.modeDisplay) " (change in Mode tab)');"
        js .= "setText('promptsModeLabel', 'AI instructions for " this._EscapeJS(promptData.modeDisplay) " mode:');"

        ; System prompt
        systemPromptForGUI := StrReplace(promptData.systemPrompt, "`n", "\n")
        systemPromptForGUI := this._EscapeJS(systemPromptForGUI)
        js .= "setValue('promptsSystemPrompt', '" systemPromptForGUI "');"

        ; API Tab - Provider
        js .= "setSelectValue('Provider', '" provider "');"

        ; API Key (get from SettingsPresenter for decryption)
        providerData := SettingsPresenter.GetProviderData(provider, mode)
        apiKey := providerData.apiKey
        js .= "setValue('APIKey', '" this._EscapeJS(apiKey) "');"

        ; Model dropdowns (on Mode tab, populated from provider)
        js .= this._BuildModelDropdowns(provider)

        ; Set selected values for each mode's dropdown
        comprehensiveModel := settings.Get("comprehensive_" . provider . "_model", Constants.GetDefaultModel(provider, "comprehensive"))
        proofreadingModel := settings.Get("proofreading_" . provider . "_model", Constants.GetDefaultModel(provider, "proofreading"))
        js .= "setSelectValue('ComprehensiveModel', '" this._EscapeJS(comprehensiveModel) "');"
        js .= "setSelectValue('ProofreadingModel', '" this._EscapeJS(proofreadingModel) "');"

        ; API Status
        statusData := SettingsPresenter.GetAPIKeyStatus(apiKey, provider, this.lastTestedKey, this.lastTestResult)
        if (apiKey != "") {
            js .= "setHTML('apiStatus', '" this._EscapeJS(statusData.status) "');"
            js .= "setStyle('apiStatus', 'display', 'block');"
            statusClass := statusData.verified ? "success" : "error"
            js .= "document.getElementById('apiStatus').className = 'api-status " statusClass "';"
        } else {
            js .= "setStyle('apiStatus', 'display', 'none');"
        }

        ; Beta Tab
        js .= "setCheckbox('BetaModeOverrideHotkeys', " (beta.Get("mode_override_hotkeys", false) ? "true" : "false") ");"
        js .= "setCheckbox('BetaPowerScribeAutoselect', " (beta.Get("powerscribe_autoselect", false) ? "true" : "false") ");"
        js .= "setCheckbox('DemographicExtractionEnabled', " (beta.Get("demographic_extraction_enabled", false) ? "true" : "false") ");"

        dicomDir := beta.Get("dicom_cache_directory", Constants.DICOM_CACHE_DEFAULT)
        js .= "setValue('DicomCacheDirectory', '" this._EscapeJS(dicomDir) "');"

        js .= "setCheckbox('TargetedReviewEnabled', " (settings.Get("targeted_review_enabled", false) ? "true" : "false") ");"

        ; Update dependencies
        js .= "updateDependencies();"

        ; About Tab - Version
        js .= "setText('aboutVersion', 'Report Check v" this._EscapeJS(VERSION) "');"

        ; Dark mode
        isDark := settings.Get("dark_mode_enabled", true)
        js .= "setCheckbox('DarkModeEnabled', " (isDark ? "true" : "false") ");"
        js .= "setTheme('" (isDark ? "dark" : "light") "');"

        ; Startup
        js .= "setCheckbox('StartupEnabled', " (ConfigManager.IsStartupEnabled() ? "true" : "false") ");"

        ; Debug logging
        js .= "setCheckbox('DebugLogging', " (settings.Get("debug_logging", false) ? "true" : "false") ");"

        ; Update section (only in script mode)
        if (!A_IsCompiled) {
            js .= "setStyle('updateCard', 'display', 'block');"
            js .= "setText('updateStatusText', 'Current version: " this._EscapeJS(VERSION) "');"
        }

        ; DICOM lock indicator
        js .= this._BuildDicomLockJS()

        ; Execute all JS at once
        this.wvGui.ExecuteScriptAsync(js)
    }

    ; Build model dropdown options for both Comprehensive and Proofreading dropdowns
    static _BuildModelDropdowns(provider) {
        models := Constants.GetModels(provider)
        modelsJS := "["
        for model in models {
            if (A_Index > 1)
                modelsJS .= ","
            modelsJS .= "'" . this._EscapeJS(model) . "'"
        }
        modelsJS .= "]"
        return "populateModelDropdowns(" . modelsJS . ");"
    }

    ; ==========================================
    ; Auto-Save Handler
    ; ==========================================
    static _OnAutoSaveSettings(wv, rawFormData) {
        try {
            ; WebView2 host objects pass JS objects as COM IDispatch proxies,
            ; which don't support AHK Map methods like .Get().  The JS side now
            ; sends JSON.stringify(collectFormData()), so parse it into a Map.
            formData := this._ParseJSON(rawFormData)

            ; Detect provider change: if the form's provider differs from what was
            ; populated, the API key/URL/model fields still show the OLD provider's
            ; data.  Repopulate the form for the new provider instead of saving stale
            ; values that would overwrite the new provider's stored key.
            newProvider := formData.Get("Provider", "claude")
            if (this.populatedProvider != "" && newProvider != this.populatedProvider) {
                ; Update provider in config first
                ConfigManager.config["API"]["provider"] := newProvider
                ConfigManager.SaveConfig()
                ; Repopulate form with the new provider's data
                SetTimer(ObjBindMethod(this, "_PopulateForm"), -100)
                return
            }

            ; Snapshot old mode BEFORE merging so prompts-tab refresh works
            oldMode := ConfigManager.config["Settings"].Get("prompt_type", "comprehensive")

            ; Convert form data to config structure using ConfigBuilder
            newConfig := ConfigBuilder.BuildFromFormData(formData)

            ; Merge into ConfigManager.config
            for section, sectionData in newConfig {
                if (!ConfigManager.config.Has(section)) {
                    ConfigManager.config[section] := Map()
                }
                for key, value in sectionData {
                    ConfigManager.config[section][key] := value
                }
            }

            ; Handle startup setting
            ConfigManager.ToggleStartup(formData.Get("StartupEnabled", false))

            ; Handle debug logging (apply immediately)
            debugEnabled := ConfigManager.config["Settings"].Get("debug_logging", false)
            if (debugEnabled) {
                Logger.SetLevel(Logger.LOG_LEVEL_DEBUG)
            } else {
                Logger.SetLevel(Logger.LOG_LEVEL_INFO)
            }

            ; Save config to file
            ConfigManager.SaveConfig()

            ; Launch DICOM service if demographic extraction is enabled
            ; (handles first-time enable and restart-after-settings-change)
            if (ConfigManager.config["Beta"].Get("demographic_extraction_enabled", false)) {
                try {
                    cacheDir := ConfigManager.config["Beta"].Get("dicom_cache_directory", Constants.DICOM_CACHE_DEFAULT)
                    EnsureDicomService(cacheDir)
                    StartDicomHeartbeat()
                } catch as err {
                    Logger.Warning("Failed to ensure DICOM service after settings change", {error: err.Message})
                }
            }

            ; Update tray menu mode
            UpdateModeMenu()

            ; Refresh prompts tab display if mode changed (compare against pre-merge value)
            newMode := formData.Get("reviewMode", "comprehensive")
            if (newMode != oldMode) {
                promptData := SettingsPresenter.GetPromptData(newMode)
                js := ""
                js .= "setText('promptsModeText', 'Current Mode: " this._EscapeJS(promptData.modeDisplay) " (change in Mode tab)');"
                js .= "setText('promptsModeLabel', 'AI instructions for " this._EscapeJS(promptData.modeDisplay) " mode:');"
                systemPromptForGUI := StrReplace(promptData.systemPrompt, "`n", "\n")
                systemPromptForGUI := this._EscapeJS(systemPromptForGUI)
                js .= "setValue('promptsSystemPrompt', '" systemPromptForGUI "');"
                this.wvGui.ExecuteScriptAsync(js)
            }

        } catch as err {
            Logger.Error("Auto-save error: " err.Message)
        }
    }

    ; ==========================================
    ; Window Control Handlers
    ; ==========================================
    static _OnMinimizeWindow(wv := "") {
        if (this.wvGui != "")
            this.wvGui.Minimize()
    }

    static _OnCloseSettings(wv := "") {
        ; Prevent closing during update
        if (this.isUpdating) {
            this._ShowModal("Update In Progress",
                "Cannot close settings while an update is in progress.<br><br>" .
                "Please wait for the update to complete.",
                "warning")
            return  ; Don't close
        }

        ; Stop DICOM lock polling
        if (this._dicomLockTimer) {
            SetTimer(this._dicomLockTimer, 0)
            this._dicomLockTimer := 0
        }

        ; Destroy the WebViewGui
        if (this.wvGui != "") {
            this.wvGui.Destroy()
            this.wvGui := ""
        }

        ; Always reload the app so all saved settings (dark mode, API config,
        ; beta features, etc.) take effect.  The previous approach only reloaded
        ; for a few specific fields, which left most settings (including dark
        ; mode) stuck until the user manually restarted.
        Reload
    }

    ; ==========================================
    ; API Key Testing
    ; ==========================================
    static _OnTestAPIKey(wv, rawFormData := "") {
        try {
            ; Parse form data passed directly from JS (avoids WebView2 ExecuteScript encoding issues)
            formData := this._ParseJSON(rawFormData)

            apiKey := formData.Get("APIKey", "")
            provider := formData.Get("Provider", "claude")

            if (apiKey = "") {
                this._ShowModal("No API Key", "Please enter an API key to test.", "warning")
                return
            }

            ; Show testing message
            this._UpdateAPIStatus("Testing connection...", "info")

            ; Test the key via SettingsPresenter
            testResult := SettingsPresenter.TestAPIKey(apiKey, provider)

            this.lastTestedKey := apiKey
            this.lastTestResult := testResult.success

            ; Update UI with result
            if (testResult.success) {
                this._UpdateAPIStatus("API key verified successfully", "success")
                this._ShowModal("Success", "API key verified successfully!", "success")
            } else {
                this._UpdateAPIStatus("API key verification failed: " testResult.error, "error")
                this._ShowModal("Verification Failed", "API key verification failed:<br><br>" testResult.error, "error")
            }

        } catch as err {
            Logger.Error("Test API key error: " err.Message)
            this._UpdateAPIStatus("Error testing key", "error")
        }
    }

    ; Update API status display
    static _UpdateAPIStatus(message, type) {
        js := "setHTML('apiStatus', '" this._EscapeJS(message) "');"
        js .= "setStyle('apiStatus', 'display', 'block');"
        js .= "document.getElementById('apiStatus').className = 'api-status " type "';"
        this.wvGui.ExecuteScriptAsync(js)
    }

    ; ==========================================
    ; Prompts Handlers
    ; ==========================================
    static _OnReloadFromFile(wv) {
        try {
            ; Reload prompts from disk into the cache
            reloadResult := PromptCache.Reload(ConfigManager.configDir)

            if (!reloadResult.success) {
                errorMsg := "Warning: Some prompts could not be reloaded:<br><br>"
                for index, err in reloadResult.errors {
                    errorMsg .= "• " err . "<br>"
                }
                this._ShowModal("Prompt Reload Warning", errorMsg, "warning")
            } else {
                this._ShowModal("Success", "System prompt has been refreshed from file.", "success")
            }

            ; Get the freshly reloaded prompt data
            mode := ConfigManager.config["Settings"]["prompt_type"]
            promptData := SettingsPresenter.GetPromptData(mode)
            systemPromptForGUI := StrReplace(promptData.systemPrompt, "`n", "\n")
            systemPromptForGUI := this._EscapeJS(systemPromptForGUI)

            js := "setValue('promptsSystemPrompt', '" systemPromptForGUI "');"
            this.wvGui.ExecuteScriptAsync(js)

        } catch as err {
            this._ShowModal("Error", "Error reloading prompts: " err.Message, "error")
        }
    }

    static _OnRestoreFromServer(wv) {
        ; Show confirmation modal
        this._ShowModal(
            "Confirm Restore from Server",
            "Restore prompt files from server?<br><br>" .
            "This will:<br>" .
            "• Download the latest default prompts from the server<br>" .
            "• OVERWRITE your local customizations<br>" .
            "• Backup your current prompts to pref\backup\<br><br>" .
            "Continue?",
            "warning",
            [
                {label: "Yes, Restore", style: "primary", action: "ConfirmRestoreFromServer"},
                {label: "Cancel", style: "secondary", action: "close"}
            ]
        )
    }

    static _OnConfirmRestoreFromServer(wv) {
        try {
            Logger.Info("User initiated prompt restore from server")

            ; Show progress
            this._ShowModal("Restoring Prompts", "Downloading latest prompts from server...", "info")

            ; Get the latest published version from the server API
            url := VersionManager.API_URL . "/api/versions/" . VersionManager.APP_NAME
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", url, false)
            http.SetRequestHeader("X-API-Key", VersionManager.API_KEY)
            timeouts := Constants.GetUpdateTimeouts()
            http.SetTimeouts(timeouts[1], timeouts[2], timeouts[3], timeouts[4])
            http.Send()

            if (http.Status != 200) {
                httpStatus := http.Status
                http := ""
                this._ShowModal("Connection Error", "Failed to connect to update server: API returned status " httpStatus, "error")
                return
            }

            responseText := http.ResponseText
            http := ""

            ; Parse the JSON to get latest_version
            latestVersion := this._ExtractJSONValue(responseText, "latest_version")
            if (latestVersion = "") {
                this._ShowModal("Error", "Failed to parse server response", "error")
                return
            }

            ; Download and restore prompts using VersionManager
            result := VersionManager.RestorePromptFiles(latestVersion)

            if (result.success) {
                ; Reload prompts into cache
                PromptCache.Reload(ConfigManager.configDir)

                ; Refresh display
                mode := ConfigManager.config["Settings"]["prompt_type"]
                promptData := SettingsPresenter.GetPromptData(mode)
                systemPromptForGUI := StrReplace(promptData.systemPrompt, "`n", "\n")
                systemPromptForGUI := this._EscapeJS(systemPromptForGUI)

                js := "setValue('promptsSystemPrompt', '" systemPromptForGUI "');"
                this.wvGui.ExecuteScriptAsync(js)

                ; Check if any files were skipped
                filesCount := result.HasOwnProp("filesRestored") ? result.filesRestored : 0
                skippedFiles := result.HasOwnProp("skippedFiles") ? result.skippedFiles : []

                if (skippedFiles.Length > 0) {
                    ; Show warning if files were skipped
                    skippedList := ""
                    for index, filename in skippedFiles {
                        skippedList .= "<br>• " filename
                    }
                    this._ShowModal("Partial Restore",
                        filesCount . " prompt file(s) restored successfully, but " . skippedFiles.Length . " file(s) were not available on server:<br>" . skippedList . "<br><br>The application may not function correctly until all prompt files are available.",
                        "warning")
                } else {
                    ; All files restored successfully
                    this._ShowModal("Success", filesCount . " prompt file(s) restored successfully from server version " . latestVersion, "success")
                }
            } else {
                this._ShowModal("Error", "Failed to restore prompts: " result.error, "error")
            }

        } catch as err {
            Logger.Error("Restore from server error: " err.Message)
            this._ShowModal("Error", "Error restoring prompts: " err.Message, "error")
        }
    }

    ; ==========================================
    ; DICOM Cache Browser
    ; ==========================================
    static _OnBrowseDicomCache(wv) {
        try {
            selectedFolder := DirSelect("*", 3, "Select DICOM Cache Directory")

            if (selectedFolder != "") {
                ; Update form
                js := "setValue('DicomCacheDirectory', '" this._EscapeJS(selectedFolder) "');"
                this.wvGui.ExecuteScriptAsync(js)

                ; Trigger auto-save
                js := "autoSave();"
                this.wvGui.ExecuteScriptAsync(js)
            }
        } catch as err {
            Logger.Error("Browse DICOM cache error: " err.Message)
        }
    }

    ; ==========================================
    ; Troubleshooting
    ; ==========================================
    static _OnDiagnoseKeys(wv) {
        this._ShowDiagnosticDialog()
    }

    static _ShowDiagnosticDialog() {
        result := ModifierKeyManager.DiagnoseAndFix()
        plainText := ModifierKeyManager.FormatDiagnosticMessage(result)
        message := "<div style='font-family: Consolas, Monaco, monospace; white-space: pre-wrap;'>" . plainText . "</div>"

        if (result.stuckAfter.Length > 0) {
            this._ShowModalWithCallback("Modifier Key Diagnostics", message, "warning",
                [{label: "Retry", action: "RetryDiagnoseKeys", style: "primary"},
                 {label: "Cancel", action: "close", style: "secondary"}])
        } else {
            this._ShowModal("Modifier Key Diagnostics", message, "success")
        }
    }

    static _ShowModalWithCallback(title, body, icon, buttons) {
        if (!this.wvGui) {
            return
        }

        ; Build buttons array for JavaScript
        buttonsJS := "["
        for btn in buttons {
            if (A_Index > 1) {
                buttonsJS .= ","
            }
            buttonsJS .= "{label:'" . this._EscapeJS(btn.label) . "',action:'" . this._EscapeJS(btn.action) . "',style:'" . this._EscapeJS(btn.style) . "'}"
        }
        buttonsJS .= "]"

        js := "showModal('" . this._EscapeJS(title) . "', `"" . this._EscapeJS(body) . "`", '" . icon . "', " . buttonsJS . ");"
        this.wvGui.ExecuteScriptAsync(js)
    }

    static _OnOpenReadme(wv) {
        try {
            readmePath := A_ScriptDir "\README.md"
            if FileExist(readmePath) {
                Run(readmePath)
            }
        } catch as err {
            Logger.Error("Open README error: " err.Message)
        }
    }

    ; ==========================================
    ; Update Handlers
    ; ==========================================
    static _OnUpdateClick(wv) {
        if (A_IsCompiled) {
            return
        }

        if (this.updateState = "check") {
            this._CheckForUpdates()
        } else if (this.updateState = "install") {
            this._InstallUpdate()
        }
    }

    static _OnCancelUpdate(wv) {
        this._ResetUpdateUI()
    }

    static _CheckForUpdates() {
        if (A_IsCompiled)
            return

        try {
            ; Update UI
            this.wvGui.ExecuteScriptAsync("setText('updateStatusText', 'Checking for updates...')")

            ; Check for updates using correct method
            result := VersionManager.CheckForUpdatesFromAPI(VERSION)

            if (!result.success) {
                js := "setText('updateStatusText', 'Error: " this._EscapeJS(result.error) "');"
                js .= "setStyle('updateStatusText', 'color', 'var(--color-danger)');"
                this.wvGui.ExecuteScriptAsync(js)
                this._ResetUpdateUI()
                return
            }

            if (!result.updateAvailable) {
                if (result.HasProp("devVersion") && result.devVersion) {
                    js := "setText('updateStatusText', 'Development version: " this._EscapeJS(VERSION) " (latest release: " this._EscapeJS(result.latestRelease) ")');"
                    js .= "setStyle('updateStatusText', 'color', 'var(--color-text-secondary)');"
                } else {
                    js := "setText('updateStatusText', 'Current version: " this._EscapeJS(VERSION) " (latest)');"
                    js .= "setStyle('updateStatusText', 'color', 'var(--color-success)');"
                }
                this.wvGui.ExecuteScriptAsync(js)
                return
            }

            ; Update available
            this.updateState := "install"
            this.newestUpdateVersion := result.version

            js := "document.getElementById('primaryUpdateBtn').innerText = 'Install Update';"
            js .= "setStyle('cancelUpdateBtn', 'display', 'inline-block');"
            js .= "setText('updateStatusText', 'Current: " this._EscapeJS(VERSION) " → Available: " this._EscapeJS(result.version) "');"
            js .= "setStyle('updateStatusText', 'color', 'var(--color-text)');"
            js .= "setText('updateAvailableText', 'Release: " this._EscapeJS(result.releaseDate) " - " this._EscapeJS(result.releaseNotes) "');"
            js .= "setStyle('updateAvailableText', 'display', 'block');"
            this.wvGui.ExecuteScriptAsync(js)

        } catch as err {
            Logger.Error("Check for updates error: " err.Message)
            this._ResetUpdateUI()
        }
    }

    static _InstallUpdate() {
        if (A_IsCompiled)
            return

        try {
            this.isUpdating := true
            this.updateState := "installing"

            ; Update UI
            js := "setText('updateStatusText', 'Preparing update...');"
            js .= "document.getElementById('primaryUpdateBtn').innerText = 'Preparing...';"
            js .= "setDisabled('primaryUpdateBtn', true);"
            js .= "setStyle('cancelUpdateBtn', 'display', 'none');"
            js .= "setStyle('updateProgress', 'display', 'block');"
            js .= "document.getElementById('updateProgressBar').style.width = '0%';"
            js .= "setText('updateProgressText', '0%');"
            js .= "setText('updateProgressDetails', 'Initializing...');"
            this.wvGui.ExecuteScriptAsync(js)

            ; Perform update with progress callback
            targetDir := A_ScriptDir
            updateResult := VersionManager.PerformCompleteUpdate(
                this.newestUpdateVersion,
                targetDir,
                ObjBindMethod(this, "_UpdateProgress")
            )

            if (!updateResult.success) {
                this.isUpdating := false
                this._ShowModal("Update Failed", "Update failed: " updateResult.error, "error")
                this.updateState := "install"
                js := "document.getElementById('primaryUpdateBtn').innerText = 'Install Update';"
                js .= "setDisabled('primaryUpdateBtn', false);"
                js .= "setStyle('cancelUpdateBtn', 'display', 'inline-block');"
                js .= "setStyle('updateProgress', 'display', 'none');"
                js .= "setText('updateStatusText', 'Update failed: " this._EscapeJS(updateResult.error) "');"
                js .= "setStyle('updateStatusText', 'color', 'var(--color-danger)');"
                this.wvGui.ExecuteScriptAsync(js)
                return
            }

            ; Success - countdown and reload
            Loop 3 {
                countdown := 4 - A_Index  ; 3, 2, 1
                js := "setText('updateProgressDetails', 'Restarting in " countdown " second" (countdown > 1 ? "s" : "") "...');"
                this.wvGui.ExecuteScriptAsync(js)
                Sleep(1000)
            }
            Reload

        } catch as err {
            this.isUpdating := false
            this._ShowModal("Update Error", "Error installing update: " err.Message, "error")
            this.updateState := "install"
            js := "document.getElementById('primaryUpdateBtn').innerText = 'Install Update';"
            js .= "setDisabled('primaryUpdateBtn', false);"
            js .= "setStyle('cancelUpdateBtn', 'display', 'inline-block');"
            js .= "setStyle('updateProgress', 'display', 'none');"
            js .= "setText('updateStatusText', 'Update error: " this._EscapeJS(err.Message) "');"
            js .= "setStyle('updateStatusText', 'color', 'var(--color-danger)');"
            this.wvGui.ExecuteScriptAsync(js)
        }
    }

    static _UpdateProgress(fileIndex, totalFiles, filename, status) {
        try {
            statusText := ""
            btnText := "Installing..."
            progressPercent := 0
            progressDetails := ""

            if (status = "downloading") {
                progressPercent := (fileIndex / totalFiles) * 50  ; 0-50%
                statusText := "Downloading updates..."
                progressDetails := "File " fileIndex " of " totalFiles ": " filename
                btnText := "Downloading..."
            } else if (status = "backing_up") {
                progressPercent := 55
                statusText := "Creating backup..."
                progressDetails := "Backing up current installation"
                btnText := "Backing up..."
            } else if (status = "cleaning") {
                progressPercent := 60
                statusText := "Cleaning up..."
                progressDetails := "Removing old files"
                btnText := "Cleaning..."
            } else if (status = "extracting") {
                progressPercent := 60 + ((fileIndex / totalFiles) * 10)  ; 60-70%
                statusText := "Extracting files..."
                progressDetails := "File " fileIndex " of " totalFiles
                btnText := "Extracting..."
            } else if (status = "installing") {
                progressPercent := 60 + ((fileIndex / totalFiles) * 35)  ; 60-95%
                statusText := "Installing update..."
                progressDetails := "File " fileIndex " of " totalFiles ": " filename
                btnText := "Installing..."
            } else if (status = "complete") {
                progressPercent := 100
                statusText := "Update complete!"
                progressDetails := "Restarting in 3 seconds..."
                btnText := "Complete!"
            }

            ; Update UI with progress
            js := "setText('updateStatusText', '" this._EscapeJS(statusText) "');"
            js .= "document.getElementById('primaryUpdateBtn').innerText = '" this._EscapeJS(btnText) "';"

            ; Show and update progress bar
            js .= "setStyle('updateProgress', 'display', 'block');"
            js .= "document.getElementById('updateProgressBar').style.width = '" Round(progressPercent) "%';"
            js .= "setText('updateProgressText', '" Round(progressPercent) "%');"
            js .= "setText('updateProgressDetails', '" this._EscapeJS(progressDetails) "');"

            this.wvGui.ExecuteScriptAsync(js)
        }
    }

    static _ResetUpdateUI() {
        this.updateState := "check"
        this.newestUpdateVersion := ""
        js := "document.getElementById('primaryUpdateBtn').innerText = 'Check for Updates';"
        js .= "setDisabled('primaryUpdateBtn', false);"
        js .= "setStyle('cancelUpdateBtn', 'display', 'none');"
        js .= "setStyle('updateAvailableText', 'display', 'none');"
        js .= "setStyle('updateProgress', 'display', 'none');"
        js .= "setText('updateStatusText', 'Current version: " this._EscapeJS(VERSION) "');"
        js .= "setStyle('updateStatusText', 'color', 'var(--color-text-label)');"
        try this.wvGui.ExecuteScriptAsync(js)
    }

    ; ==========================================
    ; DICOM Lock Status
    ; ==========================================
    static _BuildDicomLockJS() {
        demographicEnabled := ConfigManager.config["Beta"].Get("demographic_extraction_enabled", false)
        isLocked := false
        if (demographicEnabled) {
            try {
                ; Check if the DICOM service has a study locked by reading current_study.json
                ; Dev sibling layout first, then LOCALAPPDATA
                stateFile := A_ScriptDir . "\..\dicom-service\data\current_study.json"
                if (!FileExist(stateFile))
                    stateFile := EnvGet("LOCALAPPDATA") . "\vaguslab\dicom-service\data\current_study.json"
                if (FileExist(stateFile)) {
                    content := Trim(FileRead(stateFile, "UTF-8"))
                    isLocked := content != "" && content != "{}"
                }
            }
        }
        return "updateDicomLockStatus(" (demographicEnabled ? "true" : "false") ", " (isLocked ? "true" : "false") ");"
    }

    static _RefreshDicomLockStatus() {
        if (this.wvGui = "")
            return
        try {
            this.wvGui.ExecuteScriptAsync(this._BuildDicomLockJS())
        }
    }

    ; ==========================================
    ; Helper: Show Modal
    ; ==========================================
    static _ShowModal(title, body, icon := "info", buttons := "") {
        if (this.wvGui = "")
            return

        title := this._EscapeJS(title)
        body := this._EscapeJS(body)

        if (buttons = "") {
            js := "showModal('" title "', '" body "', '" icon "');"
        } else {
            buttonsJSON := this._EncodeButtonsJSON(buttons)
            js := "showModal('" title "', '" body "', '" icon "', " buttonsJSON ");"
        }

        this.wvGui.ExecuteScriptAsync(js)
    }

    ; ==========================================
    ; Helper: Escape JavaScript
    ; ==========================================
    static _EscapeJS(str) {
        str := StrReplace(str, "\", "\\")
        str := StrReplace(str, '"', '\"')
        str := StrReplace(str, "'", "\'")
        str := StrReplace(str, "``", "\``")
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        return str
    }

    ; ==========================================
    ; Helper: Encode Buttons JSON
    ; ==========================================
    static _EncodeButtonsJSON(buttons) {
        json := "["
        for index, btn in buttons {
            if (index > 1)
                json .= ","
            json .= "{"
            json .= "'label':'" this._EscapeJS(btn.label) "',"
            json .= "'style':'" this._EscapeJS(btn.style) "',"
            json .= "'action':'" this._EscapeJS(btn.action) "'"
            json .= "}"
        }
        json .= "]"
        return json
    }

    ; ==========================================
    ; Helper: Parse JSON (simple)
    ; ==========================================
    static _ParseJSON(jsonStr) {
        ; Remove outer quotes if present
        jsonStr := Trim(jsonStr, '"')

        ; This is a simplified parser - in production you'd want a proper JSON parser
        ; For now, we'll use RegEx to extract key-value pairs
        data := Map()

        ; Extract all "key": value pairs
        pos := 1
        while (pos := RegExMatch(jsonStr, '"(\w+)"\s*:\s*("([^"]*)"|true|false|(\d+))', &match, pos)) {
            key := match[1]
            if (match[3] != "") {
                ; String value — unescape JSON sequences (e.g. \\ → \)
                value := SharedUtils.UnescapeJSONString(match[3])
            } else if (match[0] ~= "true") {
                value := true
            } else if (match[0] ~= "false") {
                value := false
            } else {
                ; Number
                value := match[4]
            }
            data[key] := value
            pos += StrLen(match[0])
        }

        return data
    }

    ; ==========================================
    ; Helper: Extract JSON Value
    ; ==========================================
    static _ExtractJSONValue(jsonStr, key) {
        pattern := '"' key '"\s*:\s*"([^"]*)"'
        if (RegExMatch(jsonStr, pattern, &match)) {
            return match[1]
        }
        return ""
    }

    ; ==========================================
    ; Public API - Refresh Mode Display
    ; ==========================================
    static RefreshModeDisplay() {
        ; Called from external code when mode changes
        ; Update the GUI if it's open
        if (this.wvGui != "" && this.wvGui.Hwnd) {
            mode := ConfigManager.config["Settings"].Get("prompt_type", "comprehensive")
            js := "setRadio('reviewMode', '" mode "');"
            js .= "updateModeWarning();"
            this.wvGui.ExecuteScriptAsync(js)
        }
    }
}
