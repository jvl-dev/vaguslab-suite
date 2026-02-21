#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================
; DICOM Service Settings — Standalone GUI
; ==============================================
; Launched via Run() from host apps or double-clicked directly.
; Reads/writes dicom-service/config.ini.

; Set custom icon
TraySetIcon(A_ScriptDir "\ds.ico")

; Include shared WebView2 vendor
#Include ..\shared\vendor\ComVar.ahk
#Include ..\shared\vendor\Promise.ahk
#Include ..\shared\vendor\WebView2.ahk
#Include ..\shared\vendor\WebViewToo.ahk

; Launch GUI
DicomSettingsGui.Show()

class DicomSettingsGui {
    static wvGui := ""
    static _configFile := A_ScriptDir "\config.ini"

    ; ==========================================
    ; Public API
    ; ==========================================
    static Show() {
        ; Create WebViewGui window
        this.wvGui := WebViewGui("+Resize -Caption",,, {})
        this.wvGui.OnEvent("Close", (*) => this._OnClose())

        ; Navigate to settings page (pass theme + shared path)
        isDark := IniRead(this._configFile, "gui", "dark_mode", "true") = "true"
        sharedDir := "file:///" StrReplace(A_ScriptDir "\..\shared\gui", "\", "/")
        htmlPath := "file:///" StrReplace(A_ScriptDir "\lib\gui\settings.html", "\", "/")
            . "?theme=" (isDark ? "dark" : "light")
            . "&shared=" sharedDir
        this.wvGui.Navigate(htmlPath)

        ; Register JS → AHK callbacks
        this._RegisterCallbacks()

        ; Apply dark title bar
        this._ApplyTitleBarTheme(isDark)

        ; Show window
        this.wvGui.Show("w600 h600")

        ; Populate form after page loads
        SetTimer(ObjBindMethod(this, "_PopulateForm"), -500)
    }

    ; ==========================================
    ; Callback Registration
    ; ==========================================
    static _RegisterCallbacks() {
        this.wvGui.AddCallbackToScript("AutoSaveSettings", ObjBindMethod(this, "_OnAutoSaveSettings"))
        this.wvGui.AddCallbackToScript("CloseSettings", ObjBindMethod(this, "_OnClose"))
        this.wvGui.AddCallbackToScript("MinimizeWindow", ObjBindMethod(this, "_OnMinimize"))
        this.wvGui.AddCallbackToScript("BrowseFolder", ObjBindMethod(this, "_OnBrowseFolder"))
        this.wvGui.AddCallbackToScript("BrowseFile", ObjBindMethod(this, "_OnBrowseFile"))
        this.wvGui.AddCallbackToScript("RestartService", ObjBindMethod(this, "_OnRestartService"))
        this.wvGui.AddCallbackToScript("ToggleDarkMode", ObjBindMethod(this, "_OnToggleDarkMode"))
    }

    ; ==========================================
    ; Form Population (AHK → JS)
    ; ==========================================
    static _PopulateForm() {
        if (this.wvGui = "")
            return

        js := ""

        ; Read settings from config.ini [service] section
        js .= "setValue('DicomCacheDirectory', '" this._EscapeJS(IniRead(this._configFile, "service", "dicom_cache_directory", "C:\Intelerad\InteleViewerDicom")) "');"
        js .= "setValue('PerfLogPath', '" this._EscapeJS(IniRead(this._configFile, "service", "perf_log_path", "")) "');"
        js .= "setValue('TimerInterval', '" IniRead(this._configFile, "service", "timer_interval", "2.0") "');"
        js .= "setValue('SearchTimeout', '" IniRead(this._configFile, "service", "search_timeout", "120") "');"
        js .= "setValue('CacheSize', '" IniRead(this._configFile, "service", "cache_size", "10") "');"
        js .= "setValue('MaxScanFolders', '" IniRead(this._configFile, "service", "max_scan_folders", "50") "');"

        ; Check service status via data/service.lock
        running := false
        pid := 0
        lockFile := A_ScriptDir "\data\service.lock"
        if (FileExist(lockFile)) {
            try {
                pidStr := Trim(FileRead(lockFile, "UTF-8"))
                pid := Integer(pidStr)
                if (ProcessExist(pid)) {
                    running := true
                }
            }
        }
        js .= "setStatus(" (running ? "true" : "false") ", " pid ");"

        this.wvGui.ExecuteScriptAsync(js)
    }

    ; ==========================================
    ; Auto-Save Handler
    ; ==========================================
    static _OnAutoSaveSettings(wv, rawJSON) {
        try {
            formData := this._ParseJSON(rawJSON)

            ; Write each setting to [service] section
            IniWrite(formData.Get("DicomCacheDirectory", "C:\Intelerad\InteleViewerDicom"), this._configFile, "service", "dicom_cache_directory")
            IniWrite(formData.Get("PerfLogPath", ""), this._configFile, "service", "perf_log_path")
            IniWrite(formData.Get("TimerInterval", "2.0"), this._configFile, "service", "timer_interval")
            IniWrite(formData.Get("SearchTimeout", "120"), this._configFile, "service", "search_timeout")
            IniWrite(formData.Get("CacheSize", "10"), this._configFile, "service", "cache_size")
            IniWrite(formData.Get("MaxScanFolders", "50"), this._configFile, "service", "max_scan_folders")

            ; Dark mode
            if (formData.Has("DarkModeEnabled")) {
                isDark := formData.Get("DarkModeEnabled", false)
                isDark := (isDark = "true" || isDark = true)
                IniWrite(isDark ? "true" : "false", this._configFile, "gui", "dark_mode")
                this._ApplyTitleBarTheme(isDark)
            }

        } catch as err {
            ; Best effort — settings GUI shouldn't crash on save errors
        }
    }

    ; ==========================================
    ; Service Control
    ; ==========================================
    static _OnRestartService(wv) {
        try {
            ; Kill existing service
            lockFile := A_ScriptDir "\data\service.lock"
            if (FileExist(lockFile)) {
                try {
                    pidStr := Trim(FileRead(lockFile, "UTF-8"))
                    pid := Integer(pidStr)
                    if (ProcessExist(pid)) {
                        ProcessClose(pid)
                        ProcessWaitClose(pid, 5)
                    }
                }
            }

            ; Find Python
            pythonPath := this._FindPython()
            if (pythonPath = "") {
                this.wvGui.ExecuteScriptAsync("showModal('Error', 'Python not found. Cannot restart service.', 'error')")
                return
            }

            ; Relaunch service
            serviceScript := A_ScriptDir "\dicom_service.py"
            cmd := '"' pythonPath '" "' serviceScript '"'
            Run(cmd,, "Hide")

            ; Refresh status after 2s
            SetTimer(ObjBindMethod(this, "_PopulateForm"), -2000)

        } catch as err {
            this.wvGui.ExecuteScriptAsync("showModal('Error', 'Failed to restart service: " this._EscapeJS(err.Message) "', 'error')")
        }
    }

    ; ==========================================
    ; Browse Handlers
    ; ==========================================
    static _OnBrowseFolder(wv, fieldId := "DicomCacheDirectory") {
        try {
            selectedFolder := DirSelect("*", 3, "Select Directory")
            if (selectedFolder != "") {
                js := "setValue('" this._EscapeJS(fieldId) "', '" this._EscapeJS(selectedFolder) "');"
                js .= "autoSave();"
                this.wvGui.ExecuteScriptAsync(js)
            }
        }
    }

    static _OnBrowseFile(wv, fieldId := "PerfLogPath") {
        try {
            selectedFile := FileSelect(1,, "Select File", "Log Files (*.log)")
            if (selectedFile != "") {
                js := "setValue('" this._EscapeJS(fieldId) "', '" this._EscapeJS(selectedFile) "');"
                js .= "autoSave();"
                this.wvGui.ExecuteScriptAsync(js)
            }
        }
    }

    ; ==========================================
    ; Dark Mode Toggle
    ; ==========================================
    static _OnToggleDarkMode(wv, enabled) {
        isDark := (enabled = "true" || enabled = true)
        IniWrite(isDark ? "true" : "false", this._configFile, "gui", "dark_mode")
        ; Reload page with new theme
        sharedDir := "file:///" StrReplace(A_ScriptDir "\..\shared\gui", "\", "/")
        htmlPath := "file:///" StrReplace(A_ScriptDir "\lib\gui\settings.html", "\", "/")
            . "?theme=" (isDark ? "dark" : "light")
            . "&shared=" sharedDir
        this.wvGui.Navigate(htmlPath)
        this._ApplyTitleBarTheme(isDark)
        SetTimer(ObjBindMethod(this, "_PopulateForm"), -500)
    }

    ; ==========================================
    ; Window Controls
    ; ==========================================
    static _OnMinimize(wv := "") {
        if (this.wvGui != "")
            this.wvGui.Minimize()
    }

    static _OnClose(wv := "") {
        ExitApp
    }

    ; ==========================================
    ; Title Bar Theme
    ; ==========================================
    static _ApplyTitleBarTheme(isDark) {
        if (!this.wvGui || !this.wvGui.Hwnd)
            return
        ; DWMWA_USE_IMMERSIVE_DARK_MODE = 20
        DllCall("Dwmapi.dll\DwmSetWindowAttribute"
            , "Ptr", this.wvGui.Hwnd
            , "UInt", 20
            , "Ptr*", isDark ? 1 : 0
            , "UInt", 4)
    }

    ; ==========================================
    ; Helper: Find Python
    ; ==========================================
    static _FindPython() {
        ; Try shared vaguslab embedded Python (dev layout)
        pythonPath := A_ScriptDir "\..\python-embedded\python.exe"
        if (FileExist(pythonPath))
            return pythonPath

        ; Production layout
        pythonPath := EnvGet("LOCALAPPDATA") "\vaguslab\python-embedded\python.exe"
        if (FileExist(pythonPath))
            return pythonPath

        return ""
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
        while (pos := RegExMatch(jsonStr, '"(\w+)"\s*:\s*("([^"]*)"|true|false|(\d+\.?\d*))', &match, pos)) {
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
