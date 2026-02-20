; ==============================================
; Bruce Helper Settings GUI (WebViewToo)
; ==============================================
; WebView2-based settings window with auto-save.
; Follows the same patterns as report-check's SettingsGui.

class BruceSettingsGui {
    static wvGui := ""
    static updateState := "check"
    static newestUpdateVersion := ""
    static newestUpdateSHA256 := ""
    static _statusPollTimer := 0

    ; ==========================================
    ; Public API
    ; ==========================================
    static Show() {
        ; If already open, bring to front
        if (this.wvGui != "") {
            try {
                this.wvGui.Show()
                return
            } catch {
                this.wvGui := ""
            }
        }

        ; Create WebViewGui window
        this.wvGui := WebViewGui("+Resize -Caption",,, {})
        this.wvGui.OnEvent("Close", (*) => this._OnClose())

        ; Navigate to settings page (pass theme + shared path)
        isDark := Config.GetBool("dark_mode_enabled", true)
        sharedDir := "file:///" StrReplace(A_ScriptDir "\..\shared\gui", "\", "/")
        htmlPath := "file:///" StrReplace(A_ScriptDir "\lib\gui\settings.html", "\", "/")
            . "?theme=" (isDark ? "dark" : "light")
            . "&shared=" sharedDir
        this.wvGui.Navigate(htmlPath)

        ; Register JS → AHK callbacks
        this._RegisterCallbacks()

        ; Apply dark title bar
        this._ApplyTitleBarTheme()

        ; Show window
        this.wvGui.Show("w600 h700")

        ; Populate form after page loads
        SetTimer(ObjBindMethod(this, "_PopulateForm"), -500)

        ; Start live status polling (every 3 seconds)
        this._statusPollTimer := ObjBindMethod(this, "_RefreshStatus")
        SetTimer(this._statusPollTimer, 3000)
    }

    ; ==========================================
    ; Callback Registration
    ; ==========================================
    static _RegisterCallbacks() {
        this.wvGui.AddCallbackToScript("AutoSaveSettings", ObjBindMethod(this, "_OnAutoSaveSettings"))
        this.wvGui.AddCallbackToScript("CloseSettings", ObjBindMethod(this, "_OnClose"))
        this.wvGui.AddCallbackToScript("MinimizeWindow", ObjBindMethod(this, "_OnMinimize"))
        this.wvGui.AddCallbackToScript("OnUpdateClick", ObjBindMethod(this, "_OnUpdateClick"))
        this.wvGui.AddCallbackToScript("CancelUpdate", ObjBindMethod(this, "_OnCancelUpdate"))
    }

    ; ==========================================
    ; Form Population (AHK → JS)
    ; ==========================================
    static _PopulateForm() {
        if (this.wvGui = "")
            return

        js := ""

        ; Startup toggles
        js .= "setCheckbox('LaunchOnStartup', " (IsStartupEnabled() ? "true" : "false") ");"
        js .= "setCheckbox('CheckUpdatesOnStartup', " (Config.GetBool("check_updates_on_startup", true) ? "true" : "false") ");"

        ; Timing
        js .= "setValue('PowerscribeSelectDelay', '" Config.GetInt("powerscribe_select_delay", 50) "');"
        js .= "setValue('ClipboardDeferDelay', '" Config.GetInt("clipboard_defer_delay", 200) "');"

        ; Dark mode
        isDark := Config.GetBool("dark_mode_enabled", true)
        js .= "setCheckbox('DarkModeEnabled', " (isDark ? "true" : "false") ");"
        js .= "setTheme('" (isDark ? "dark" : "light") "');"

        ; About
        js .= "setText('aboutVersion', 'Bruce Helper v" this._EscapeJS(VERSION) "');"
        js .= "setText('updateStatusText', 'Current version: " this._EscapeJS(VERSION) "');"

        ; Status indicators (also used by live polling)
        js .= this._BuildStatusJS()

        this.wvGui.ExecuteScriptAsync(js)
    }

    ; ==========================================
    ; Auto-Save Handler
    ; ==========================================
    static _OnAutoSaveSettings(wv, rawJSON) {
        try {
            formData := this._ParseJSON(rawJSON)

            ; Handle startup toggle
            wantsStartup := formData.Get("LaunchOnStartup", false)
            if (wantsStartup && !IsStartupEnabled()) {
                EnableStartup()
            } else if (!wantsStartup && IsStartupEnabled()) {
                DisableStartup()
            }

            ; Write all settings to INI
            IniWrite(wantsStartup ? "true" : "false", Config.configFile, "Settings", "launch_on_startup")
            IniWrite(formData.Get("CheckUpdatesOnStartup", true) ? "true" : "false", Config.configFile, "Settings", "check_updates_on_startup")
            IniWrite(formData.Get("PowerscribeSelectDelay", "50"), Config.configFile, "Settings", "powerscribe_select_delay")
            IniWrite(formData.Get("ClipboardDeferDelay", "200"), Config.configFile, "Settings", "clipboard_defer_delay")
            IniWrite(formData.Get("DarkModeEnabled", true) ? "true" : "false", Config.configFile, "Settings", "dark_mode_enabled")

            ; Reload config in memory
            Config.Load()

        } catch as err {
            Logger.Error("Auto-save error: " err.Message)
        }
    }

    ; ==========================================
    ; Window Controls
    ; ==========================================
    static _OnMinimize(wv := "") {
        if (this.wvGui != "")
            this.wvGui.Minimize()
    }

    static _OnClose(wv := "") {
        ; Stop status polling
        if (this._statusPollTimer) {
            SetTimer(this._statusPollTimer, 0)
            this._statusPollTimer := 0
        }

        if (this.wvGui != "") {
            this.wvGui.Destroy()
            this.wvGui := ""
        }
    }


    ; ==========================================
    ; Live Status Polling
    ; ==========================================
    static _BuildStatusJS() {
        js := ""
        js .= "setStatus('statusPS360', " (WinExist(Constants.POWERSCRIBE_360) ? "true" : "false") ");"
        js .= "setStatus('statusPSOne', " (WinExist(Constants.POWERSCRIBE_ONE) ? "true" : "false") ");"
        js .= "setStatus('statusClipboard', true);"
        js .= "setStatus('statusWebSocket', " (PYTHON_PID != 0 && ProcessExist(PYTHON_PID) ? "true" : "false") ");"

        ; DICOM service: check lock file PID
        dicomRunning := false
        lockFile := A_ScriptDir "\..\dicom-service\data\service.lock"
        if (!FileExist(lockFile))
            lockFile := EnvGet("LOCALAPPDATA") "\vaguslab\dicom-service\data\service.lock"
        if (FileExist(lockFile)) {
            try {
                pidStr := Trim(FileRead(lockFile, "UTF-8"))
                if (ProcessExist(Integer(pidStr)))
                    dicomRunning := true
            }
        }
        js .= "setStatus('statusDicom', " (dicomRunning ? "true" : "false") ");"

        ; DICOM lock indicator (study locked)
        isLocked := false
        try {
            stateFile := A_ScriptDir "\..\dicom-service\data\current_study.json"
            if (!FileExist(stateFile))
                stateFile := EnvGet("LOCALAPPDATA") "\vaguslab\dicom-service\data\current_study.json"
            if (FileExist(stateFile)) {
                content := Trim(FileRead(stateFile, "UTF-8"))
                isLocked := content != "" && content != "{}"
            }
        }
        js .= "updateDicomLockStatus(" (dicomRunning ? "true" : "false") ", " (isLocked ? "true" : "false") ");"

        return js
    }

    static _RefreshStatus() {
        if (this.wvGui = "")
            return
        try {
            this.wvGui.ExecuteScriptAsync(this._BuildStatusJS())
        }
    }

    ; ==========================================
    ; Update Handlers
    ; ==========================================
    static _OnUpdateClick(wv) {
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
        try {
            this.wvGui.ExecuteScriptAsync("setText('updateStatusText', 'Checking for updates...')")

            result := CheckForUpdates(false)

            if (!result.success) {
                js := "setText('updateStatusText', 'Error: " this._EscapeJS(result.error) "');"
                js .= "setStyle('updateStatusText', 'color', 'var(--color-danger)');"
                this.wvGui.ExecuteScriptAsync(js)
                return
            }

            if (!result.updateAvailable) {
                js := "setText('updateStatusText', 'Current version: " this._EscapeJS(VERSION) " (latest)');"
                js .= "setStyle('updateStatusText', 'color', 'var(--color-success)');"
                this.wvGui.ExecuteScriptAsync(js)
                return
            }

            ; Update available
            this.updateState := "install"
            this.newestUpdateVersion := result.version
            this.newestUpdateSHA256 := result.sha256

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
        if (this.newestUpdateVersion = "")
            return

        try {
            this.updateState := "installing"

            js := "setText('updateStatusText', 'Installing update...');"
            js .= "document.getElementById('primaryUpdateBtn').innerText = 'Installing...';"
            js .= "setDisabled('primaryUpdateBtn', true);"
            js .= "setStyle('cancelUpdateBtn', 'display', 'none');"
            this.wvGui.ExecuteScriptAsync(js)

            ; Build version info for PerformUpdate
            versionInfo := Map()
            versionInfo["sha256"] := this.newestUpdateSHA256

            PerformUpdate(this.newestUpdateVersion, versionInfo)

        } catch as err {
            Logger.Error("Install update error: " err.Message)
            this._ShowModal("Update Failed", "Error: " err.Message, "error")
            this.updateState := "install"
            js := "document.getElementById('primaryUpdateBtn').innerText = 'Install Update';"
            js .= "setDisabled('primaryUpdateBtn', false);"
            js .= "setStyle('cancelUpdateBtn', 'display', 'inline-block');"
            this.wvGui.ExecuteScriptAsync(js)
        }
    }

    static _ResetUpdateUI() {
        this.updateState := "check"
        this.newestUpdateVersion := ""
        this.newestUpdateSHA256 := ""
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
    ; Title Bar Theme
    ; ==========================================
    static _ApplyTitleBarTheme() {
        if (!this.wvGui || !this.wvGui.Hwnd)
            return
        isDark := Config.GetBool("dark_mode_enabled", true)
        ; DWMWA_USE_IMMERSIVE_DARK_MODE = 20
        DllCall("Dwmapi.dll\DwmSetWindowAttribute"
            , "Ptr", this.wvGui.Hwnd
            , "UInt", 20
            , "Ptr*", isDark ? 1 : 0
            , "UInt", 4)
    }

    ; ==========================================
    ; Helper: Show Modal
    ; ==========================================
    static _ShowModal(title, body, icon := "info") {
        if (this.wvGui = "")
            return
        js := "showModal('" this._EscapeJS(title) "', '" this._EscapeJS(body) "', '" icon "');"
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
    ; Helper: Parse JSON
    ; ==========================================
    static _ParseJSON(jsonStr) {
        jsonStr := Trim(jsonStr, '"')
        data := Map()

        pos := 1
        while (pos := RegExMatch(jsonStr, '"(\w+)"\s*:\s*("([^"]*)"|true|false|(\d+))', &match, pos)) {
            key := match[1]
            if (match[3] != "") {
                value := match[3]
                ; Unescape JSON backslashes
                value := StrReplace(value, "\\", "\")
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
}
