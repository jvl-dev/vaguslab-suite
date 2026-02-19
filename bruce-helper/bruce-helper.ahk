#Requires AutoHotkey v2.0
#SingleInstance Force

; ==========================================
; Bruce Helper → PowerScribe Auto-Paste Listener
; ==========================================
; This script automatically pastes Bruce radiology reports into PowerScribe
; when you click "PS Send" in the Bruce web interface.
;
; Usage:
; - Click "PS Send" in Bruce → Report auto-pastes to PowerScribe
;
; Supported PowerScribe Versions:
; - PowerScribe 360 (Nuance.PowerScribe360.exe)
; - PSOne (Nuance.PSOne.exe)
; ==========================================

; ==============================================
; Compilation Directives (for building EXE)
; ==============================================
;@Ahk2Exe-SetMainIcon helpbruce.ico
;@Ahk2Exe-SetVersion 0.2.0
;@Ahk2Exe-SetProductName Bruce Helper
;@Ahk2Exe-SetDescription Bruce Helper - PowerScribe Auto-Paste Listener for Bruce Radiology Reports
;@Ahk2Exe-SetCompanyName VagusLab
;@Ahk2Exe-SetCopyright © 2025 VagusLab. All rights reserved
;@Ahk2Exe-ExeName bruce-helper.exe
;@Ahk2Exe-AddResource helpbruce.ico, 160

; Close any other AutoHotkey instances running from this directory
; This handles migration from old script names
CloseOtherInstancesFromThisDir()

CloseOtherInstancesFromThisDir() {
    static thisDir := A_ScriptDir

    ; Get all AutoHotkey processes
    try {
        for process in ComObjGet("winmgmts:").ExecQuery("SELECT * FROM Win32_Process WHERE Name LIKE 'AutoHotkey%'") {
            ; Skip ourselves
            if (process.ProcessId = DllCall("GetCurrentProcessId"))
                continue

            ; Check if command line contains our directory
            if (InStr(process.CommandLine, thisDir)) {
                ; Kill the process
                try {
                    ProcessClose(process.ProcessId)
                } catch {
                    ; Ignore errors - process may have already closed
                }
            }
        }
    } catch {
        ; Ignore WMI errors - not critical to operation
    }
}

; ===== VERSION =====
global VERSION := "1.0.0"

; ===== LIBRARIES =====
#Include lib\Logger.ahk

; ===== CONSTANTS =====
; Centralized constants to avoid magic numbers
class Constants {
    ; DICOM/PSOne paths
    static PSONE_PERF_LOG_SUBPATH := "\AppData\Local\Nuance\PowerScribeOne\Logs\Perf\PSOnePerf.log"
    ; Update Server Configuration
    static UPDATE_SERVER := "https://ahk-updates.vaguslab.org"
    static APP_NAME := "bruce-helper"
    static API_KEY := "bf1a862ff248880acace0a1ca3b20392c21be1edb9845971656c950d98b5bec9"

    ; HTTP Timeouts (milliseconds)
    static HTTP_TIMEOUT_STANDARD := 10000        ; 10 seconds - Version checks
    static HTTP_TIMEOUT_DOWNLOAD := 30000        ; 30 seconds - File downloads

    ; Clipboard & PowerScribe Delays (milliseconds)
    static CLIPBOARD_WAIT_TIMEOUT := 2000        ; 2 seconds
    static CLIPBOARD_DEFER_DELAY := 200          ; 200ms - Defer clipboard processing
    static POWERSCRIBE_SELECT_DELAY := 50        ; 50ms - After Ctrl+A
    static POWERSCRIBE_ACTIVATION_DELAY := 100   ; 100ms - After window activation

    ; Notification Durations (milliseconds)
    static NOTIFICATION_DURATION := 3000         ; 3 seconds - Info/Success
    static NOTIFICATION_DURATION_ERROR := 5000   ; 5 seconds - Errors

    ; Content Validation
    static MIN_REPORT_LENGTH := 50               ; Minimum chars for Bruce report

    ; PowerScribe Process Names
    static POWERSCRIBE_360 := "ahk_exe Nuance.PowerScribe360.exe"
    static POWERSCRIBE_ONE := "ahk_exe Nuance.PSOne.exe"

    ; Bruce Report Markers
    static MARKER := "<<<BRUCE:"
    static END_MARKER := "<<<BRUCE:END>>>"
}

; ===== CONFIGURATION =====
; Load user preferences from config.ini (creates default if missing)
class Config {
    static configFile := A_ScriptDir "\config.ini"
    static settings := Map()

    ; Default settings
    static defaults := Map(
        "check_updates_on_startup", "true",
        "powerscribe_select_delay", "50",
        "clipboard_defer_delay", "200",
        "launch_on_startup", "false",
        "dicom_cache_dir", "C:\Intelerad\InteleViewerDicom",
        "perf_log_path", ""
    )

    ; Load configuration from INI file
    static Load() {
        ; Create config file with defaults if it doesn't exist
        if (!FileExist(this.configFile)) {
            this.CreateDefault()
        }

        ; Read settings from INI
        for key, defaultValue in this.defaults {
            value := IniRead(this.configFile, "Settings", key, defaultValue)
            this.settings[key] := value
        }

        ; Auto-migrate: Add any missing settings to existing config file
        this.MigrateMissingSettings()
    }

    ; Add missing settings to existing config files (auto-migration)
    static MigrateMissingSettings() {
        try {
            settingDocs := Map(
                "check_updates_on_startup", "Check for updates when script starts (true/false)",
                "powerscribe_select_delay", "Delay after Ctrl+A in PowerScribe (milliseconds)",
                "clipboard_defer_delay", "Delay before processing clipboard changes (milliseconds)",
                "launch_on_startup", "Launch Bruce Helper when Windows starts (true/false)",
                "dicom_cache_dir", "DICOM cache directory for InteleViewer integration (leave blank to disable)",
                "perf_log_path", "Override path to PSOnePerf.log (leave blank to use default per-user path)"
            )

            needsMigration := false
            for key, defaultValue in this.defaults {
                ; Check if setting exists in INI file
                testValue := IniRead(this.configFile, "Settings", key, "%%MISSING%%")
                if (testValue = "%%MISSING%%") {
                    needsMigration := true
                    ; Add missing setting with comment
                    IniWrite(defaultValue, this.configFile, "Settings", key)
                    Logger.Info("Added missing config setting", {key: key, value: defaultValue})
                }
            }

            ; If we added settings, add comments by regenerating the file properly
            if (needsMigration) {
                this.AddCommentsToConfig(settingDocs)
            }
        } catch as err {
            Logger.Warning("Config migration failed", {error: err.Message})
        }
    }

    ; Add comments to config file (called after migration)
    static AddCommentsToConfig(settingDocs) {
        try {
            ; Read current values
            currentValues := Map()
            for key, _ in this.defaults {
                currentValues[key] := IniRead(this.configFile, "Settings", key, this.defaults[key])
            }

            ; Regenerate config with comments
            content := "; Bruce Helper Configuration`n"
            content .= "; Auto-updated with new settings`n`n"
            content .= "[Settings]`n"

            for key, defaultValue in this.defaults {
                if (settingDocs.Has(key)) {
                    content .= "; " settingDocs[key] "`n"
                }
                content .= key "=" currentValues[key] "`n`n"
            }

            ; Write back to file
            FileDelete(this.configFile)
            FileAppend(content, this.configFile, "UTF-8")
        } catch {
            ; If comment addition fails, the settings are still there
        }
    }

    ; Create default config.ini file
    static CreateDefault() {
        try {
            content := "; Bruce Helper Configuration`n"
            content .= "; Auto-generated on first run`n`n"
            content .= "[Settings]`n"
            content .= "; Check for updates when script starts (true/false)`n"
            content .= "check_updates_on_startup=" this.defaults["check_updates_on_startup"] "`n`n"
            content .= "; Delay after Ctrl+A in PowerScribe (milliseconds)`n"
            content .= "powerscribe_select_delay=" this.defaults["powerscribe_select_delay"] "`n`n"
            content .= "; Delay before processing clipboard changes (milliseconds)`n"
            content .= "clipboard_defer_delay=" this.defaults["clipboard_defer_delay"] "`n`n"
            content .= "; Launch Bruce Helper when Windows starts (true/false)`n"
            content .= "launch_on_startup=" this.defaults["launch_on_startup"] "`n`n"
            content .= "; DICOM cache directory for InteleViewer integration (leave blank to disable)`n"
            content .= "dicom_cache_dir=" this.defaults["dicom_cache_dir"] "`n`n"
            content .= "; Override path to PSOnePerf.log (leave blank to use default per-user path)`n"
            content .= "; %USERPROFILE% is expanded at runtime so the path stays portable across accounts`n"
            content .= "; Example: perf_log_path=%USERPROFILE%\AppData\Local\Nuance\PowerScribeOne\Logs\Perf\PSOnePerf.log`n"
            content .= "perf_log_path=" this.defaults["perf_log_path"] "`n"

            FileAppend(content, this.configFile, "UTF-8")
        } catch {
            ; If config creation fails, settings will use defaults
        }
    }

    ; Get a setting value
    static Get(key, defaultValue := "") {
        if (this.settings.Has(key)) {
            return this.settings[key]
        }
        return defaultValue != "" ? defaultValue : this.defaults.Get(key, "")
    }

    ; Get boolean setting
    static GetBool(key, defaultValue := false) {
        value := this.Get(key, defaultValue ? "true" : "false")
        return (value = "true" || value = "1" || value = "yes")
    }

    ; Get integer setting
    static GetInt(key, defaultValue := 0) {
        value := this.Get(key, String(defaultValue))
        return Integer(value)
    }
}

; Load configuration on startup
Config.Load()

; ===== CREATE DATA AND LOGS DIRECTORIES =====
; Create data/ and logs/ folders if they don't exist (for DICOM state and Python logs)
try {
    if !DirExist(A_ScriptDir "\data")
        DirCreate(A_ScriptDir "\data")
    if !DirExist(A_ScriptDir "\logs")
        DirCreate(A_ScriptDir "\logs")
}

; ===== ENSURE SHARED DICOM SERVICE =====
dicomCacheDir := Config.Get("dicom_cache_dir", "")
try {
    EnsureDicomService(dicomCacheDir)
} catch as err {
    Logger.Warning("Failed to ensure DICOM service", {error: err.Message})
}
StartDicomHeartbeat()

; ===== BUSY FLAG (prevents re-entry during clipboard processing) =====
global bruceHelperProcessing := false

; ===== CUSTOM ICON =====
if FileExist(A_ScriptDir "\helpbruce.ico")
    TraySetIcon(A_ScriptDir "\helpbruce.ico")

; ===== NOTIFICATION MANAGER =====
; Clean notification system to avoid race conditions
class NotificationManager {
    static currentTimer := ""
    static timerLock := false
    static timerID := 0

    static Show(title, message, duration := 3000) {
        if (this.timerLock) {
            Sleep(10)
        }

        this.timerLock := true

        try {
            if (this.currentTimer != "") {
                try {
                    SetTimer(this.currentTimer, 0)
                } catch {
                    ; Timer may already be deleted
                }
            }

            this.timerID += 1
            currentID := this.timerID

            TrayTip()
            TrayTip(title, message, "Mute")

            timerFunc := () => this._ClearWithIDCheck(currentID)
            SetTimer(timerFunc, -duration)
            this.currentTimer := timerFunc

        } finally {
            this.timerLock := false
        }
    }

    static _ClearWithIDCheck(expectedID) {
        if (this.timerID = expectedID) {
            TrayTip()
            if (this.currentTimer != "") {
                try {
                    SetTimer(this.currentTimer, 0)
                }
                this.currentTimer := ""
            }
        }
    }
}

; Notification shortcuts
NotifyInfo(title, message, duration := 0) {
    if (duration = 0)
        duration := Constants.NOTIFICATION_DURATION
    NotificationManager.Show(title, message, duration)
}

NotifySuccess(title, message, duration := 0) {
    if (duration = 0)
        duration := Constants.NOTIFICATION_DURATION
    NotificationManager.Show(title, message, duration)
}

NotifyError(title, message, duration := 0) {
    if (duration = 0)
        duration := Constants.NOTIFICATION_DURATION_ERROR
    NotificationManager.Show(title, message, duration)
}

; ===== AUTO-UPDATE FUNCTIONS =====

; Make HTTP request with timeout and API key
MakeHTTPRequest(url, method := "GET", headers := Map()) {
    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.Open(method, url, false)
        timeout := Constants.HTTP_TIMEOUT_STANDARD
        http.SetTimeouts(timeout, timeout, timeout, timeout)

        ; Add API key header
        http.SetRequestHeader("X-API-Key", Constants.API_KEY)

        ; Add any additional headers
        for key, value in headers {
            http.SetRequestHeader(key, value)
        }

        http.Send()
        http.WaitForResponse(10)

        if (http.Status < 200 || http.Status >= 300)
            throw Error("HTTP " http.Status " returned from " url)

        return http.ResponseText
    } catch as err {
        throw Error("HTTP request failed: " err.Message)
    }
}

; Calculate SHA-256 hash of a file using PowerShell
CalculateSHA256(filePath) {
    try {
        ; Create temp file for output
        tempFile := A_Temp "\hash_" A_TickCount ".txt"

        ; Use PowerShell to calculate SHA-256 hash (hidden window)
        psCommand := 'powershell.exe -NoProfile -WindowStyle Hidden -Command "(Get-FileHash -Algorithm SHA256 \"' filePath '\").Hash | Out-File -FilePath \"' tempFile '\" -Encoding UTF8"'

        shell := ""
        try {
            ; Run PowerShell hidden and wait for completion
            shell := ComObject("WScript.Shell")
            shell.Run(psCommand, 0, true)  ; 0 = hidden window, true = wait
        } finally {
            ; Release COM object
            shell := ""
        }

        ; Read the hash from temp file
        if (!FileExist(tempFile))
            throw Error("Hash calculation failed - output file not created")

        calculatedHash := FileRead(tempFile, "UTF-8")

        ; Clean up temp file
        try {
            FileDelete(tempFile)
        }

        ; Remove any newlines, spaces, BOM, or other whitespace
        calculatedHash := StrReplace(calculatedHash, "`r", "")
        calculatedHash := StrReplace(calculatedHash, "`n", "")
        calculatedHash := StrReplace(calculatedHash, Chr(0xFEFF), "")  ; Remove BOM
        calculatedHash := Trim(calculatedHash)

        return calculatedHash
    } catch as err {
        throw Error("SHA-256 calculation failed: " err.Message)
    }
}

; Compare semantic versions (e.g., "0.1.3" vs "0.2.0")
; Returns: -1 if current < latest, 0 if equal, 1 if current > latest
CompareVersions(current, latest) {
    currentParts := StrSplit(current, ".")
    latestParts := StrSplit(latest, ".")

    maxLen := Max(currentParts.Length, latestParts.Length)

    loop maxLen {
        currentNum := (A_Index <= currentParts.Length) ? Integer(currentParts[A_Index]) : 0
        latestNum := (A_Index <= latestParts.Length) ? Integer(latestParts[A_Index]) : 0

        if (currentNum < latestNum)
            return -1
        else if (currentNum > latestNum)
            return 1
    }

    return 0
}

; Get release notes from version info
GetReleaseNotes(versionInfo) {
    try {
        if (versionInfo.Has("release_notes"))
            return versionInfo["release_notes"]
        return "No release notes available."
    } catch {
        return "No release notes available."
    }
}

; Main update check function - returns result object instead of showing dialogs
CheckForUpdates(silentMode := true) {
    global VERSION

    result := {
        success: false,
        updateAvailable: false,
        error: "",
        version: "",
        releaseDate: "",
        releaseNotes: "",
        sha256: ""
    }

    try {
        ; Make API request to check version
        versionUrl := Constants.UPDATE_SERVER "/api/versions/" Constants.APP_NAME
        response := MakeHTTPRequest(versionUrl)

        ; Parse JSON response
        versionData := ""
        try {
            versionData := Jxon_Load(&response)
        } catch {
            throw Error("Failed to parse version data")
        }

        ; Validate response has required fields
        if (!versionData.Has("latest_version")) {
            throw Error("Invalid server response - app may not be registered on update server")
        }

        ; Extract latest version
        latestVersion := versionData["latest_version"]

        ; Get current version info
        if (!versionData.Has("version_info")) {
            throw Error("Invalid server response - missing version info")
        }
        currentVersionInfo := versionData["version_info"]

        ; Compare versions
        comparison := CompareVersions(VERSION, latestVersion)

        result.success := true

        if (comparison >= 0) {
            ; Already up-to-date
            result.updateAvailable := false
            return result
        }

        ; Update available
        result.updateAvailable := true
        result.version := latestVersion
        result.releaseDate := currentVersionInfo.Has("release_date") ? currentVersionInfo["release_date"] : "Unknown"
        result.releaseNotes := GetReleaseNotes(currentVersionInfo)
        result.sha256 := currentVersionInfo.Has("sha256") ? currentVersionInfo["sha256"] : ""

        ; Show toast notification in silent mode (startup)
        if (silentMode) {
            message := "Version " . result.version . " is available!`n"
            if (result.releaseDate != "") {
                message .= "Released: " . result.releaseDate . "`n"
            }
            message .= "Open Settings to install"

            NotifyInfo("Update Available", message, Constants.NOTIFICATION_DURATION_ERROR)
        }

        return result

    } catch as err {
        result.success := false
        result.error := err.Message

        ; Only show error notification if not silent
        if (!silentMode) {
            NotifyError("Update Check Failed", "Could not check for updates: " err.Message)
        }

        return result
    }
}

; Perform the actual update download and installation
PerformUpdate(version, versionInfo) {
    http := ""
    stream := ""

    try {
        NotifyInfo("Updating", "Downloading update...")

        ; Download new version using binary stream
        downloadUrl := Constants.UPDATE_SERVER "/api/download/" Constants.APP_NAME "/" version
        tempFile := A_Temp "\bruce-helper-update.ahk"

        try {
            http := ComObject("WinHttp.WinHttpRequest.5.1")
            http.Open("GET", downloadUrl, false)
            http.SetRequestHeader("X-API-Key", Constants.API_KEY)
            timeout := Constants.HTTP_TIMEOUT_DOWNLOAD
            http.SetTimeouts(timeout, timeout, timeout, timeout)
            http.Send()

            if (http.Status != 200)
                throw Error("Download failed with status " http.Status)

            ; Delete existing temp file if it exists
            try {
                FileDelete(tempFile)
            } catch {
                ; File may not exist
            }

            ; Save binary response to file using ADODB.Stream
            stream := ComObject("ADODB.Stream")
            stream.Type := 1  ; Binary
            stream.Open()
            stream.Write(http.ResponseBody)
            stream.SaveToFile(tempFile, 2)  ; Overwrite if exists

        } finally {
            ; Ensure COM objects are properly released
            if (stream != "") {
                try stream.Close()
            }
            stream := ""
            http := ""
        }

        ; Get expected SHA-256 hash
        if (!versionInfo.Has("sha256")) {
            FileDelete(tempFile)
            throw Error("Server response missing SHA-256 hash")
        }
        expectedHash := versionInfo["sha256"]

        ; Verify SHA-256 hash
        NotifyInfo("Updating", "Verifying download...")
        actualHash := CalculateSHA256(tempFile)

        if (StrLower(actualHash) != StrLower(expectedHash)) {
            FileDelete(tempFile)
            throw Error("Download verification failed - SHA-256 mismatch")
        }

        ; Create backup of current script
        backupFile := A_ScriptFullPath ".bak"
        try {
            FileDelete(backupFile)
        } catch {
            ; Backup may not exist
        }
        FileCopy(A_ScriptFullPath, backupFile, 1)

        ; Clean up orphaned startup shortcuts before installing new version
        CleanupOrphanedShortcuts()

        ; Replace current script with new version
        FileCopy(tempFile, A_ScriptFullPath, 1)
        FileDelete(tempFile)

        ; Show success message
        NotifySuccess("Update Complete", "Restarting Bruce Helper...")
        Sleep(1000)

        ; Reload script
        Reload()

    } catch as err {
        ; Cleanup
        if (stream != "") {
            try stream.Close()
        }
        stream := ""
        http := ""

        ; Restore backup if it exists
        backupFile := A_ScriptFullPath ".bak"
        if (FileExist(backupFile)) {
            try {
                FileCopy(backupFile, A_ScriptFullPath, 1)
                NotifyError("Update Failed", "Update failed, backup restored: " err.Message)
            } catch {
                NotifyError("Update Failed", "Critical: Update and restore failed: " err.Message)
            }
        } else {
            NotifyError("Update Failed", "Update failed: " err.Message)
        }
    }
}

; Clean up orphaned startup shortcuts that don't point to the current script
CleanupOrphanedShortcuts() {
    try {
        startupFolder := A_Startup

        ; Look for any bruce-helper related shortcuts in startup folder
        Loop Files, startupFolder "\*.lnk"
        {
            shortcutPath := A_LoopFileFullPath
            shortcutName := A_LoopFileName

            ; Only process bruce-helper related shortcuts
            if (!InStr(shortcutName, "bruce-helper") && !InStr(shortcutName, "bruce helper") && !InStr(shortcutName, "brucehelper"))
                continue

            try {
                ; Use COM to read the shortcut target
                shell := ComObject("WScript.Shell")
                shortcut := shell.CreateShortcut(shortcutPath)
                targetPath := shortcut.TargetPath

                ; Clean up COM objects
                shortcut := ""
                shell := ""

                ; Normalize paths for comparison (handles forward/backslashes, trailing slashes, case)
                targetPath := NormalizePath(targetPath)
                currentScript := NormalizePath(A_ScriptFullPath)

                ; If the shortcut doesn't point to the current script location, remove it
                if (targetPath != currentScript) {
                    try {
                        FileDelete(shortcutPath)
                    } catch {
                        ; Failed to delete, continue with other shortcuts
                    }
                }
            } catch {
                ; If we can't read the shortcut, skip it (don't delete what we can't verify)
                continue
            }
        }
    } catch {
        ; Cleanup failed, but don't block the update process
        return
    }
}

; JSON parser (Jxon) - Minimal implementation for parsing update responses
Jxon_Load(&src) {
    return _Jxon_Parse(&src)
}

_Jxon_Parse(&src) {
    ; Skip whitespace
    _Jxon_SkipWhitespace(&src)

    if (src = "")
        throw Error("Empty JSON")

    ch := SubStr(src, 1, 1)

    if (ch = "{")
        return _Jxon_ParseObject(&src)
    else if (ch = "[")
        return _Jxon_ParseArray(&src)
    else if (ch = '"')
        return _Jxon_ParseString(&src)
    else if (ch = "t" || ch = "f")
        return _Jxon_ParseBool(&src)
    else if (ch = "n")
        return _Jxon_ParseNull(&src)
    else if (InStr("0123456789-", ch))
        return _Jxon_ParseNumber(&src)
    else
        throw Error("Invalid JSON")
}

_Jxon_SkipWhitespace(&src) {
    while (src != "" && InStr(" `t`r`n", SubStr(src, 1, 1))) {
        src := SubStr(src, 2)
    }
}

_Jxon_ParseObject(&src) {
    obj := Map()
    src := SubStr(src, 2)  ; Skip '{'

    _Jxon_SkipWhitespace(&src)

    if (SubStr(src, 1, 1) = "}") {
        src := SubStr(src, 2)
        return obj
    }

    loop {
        _Jxon_SkipWhitespace(&src)

        ; Parse key
        if (SubStr(src, 1, 1) != '"')
            throw Error("Expected string key")

        key := _Jxon_ParseString(&src)

        _Jxon_SkipWhitespace(&src)

        ; Expect ':'
        if (SubStr(src, 1, 1) != ":")
            throw Error("Expected ':'")
        src := SubStr(src, 2)

        _Jxon_SkipWhitespace(&src)

        ; Parse value
        value := _Jxon_Parse(&src)
        obj[key] := value

        _Jxon_SkipWhitespace(&src)

        ch := SubStr(src, 1, 1)
        if (ch = "}")
            break
        else if (ch = ",")
            src := SubStr(src, 2)
        else
            throw Error("Expected ',' or '}'")
    }

    src := SubStr(src, 2)  ; Skip '}'
    return obj
}

_Jxon_ParseArray(&src) {
    arr := []
    src := SubStr(src, 2)  ; Skip '['

    _Jxon_SkipWhitespace(&src)

    if (SubStr(src, 1, 1) = "]") {
        src := SubStr(src, 2)
        return arr
    }

    loop {
        _Jxon_SkipWhitespace(&src)

        value := _Jxon_Parse(&src)
        arr.Push(value)

        _Jxon_SkipWhitespace(&src)

        ch := SubStr(src, 1, 1)
        if (ch = "]")
            break
        else if (ch = ",")
            src := SubStr(src, 2)
        else
            throw Error("Expected ',' or ']'")
    }

    src := SubStr(src, 2)  ; Skip ']'
    return arr
}

_Jxon_ParseString(&src) {
    src := SubStr(src, 2)  ; Skip opening '"'
    str := ""

    loop {
        if (src = "")
            throw Error("Unterminated string")

        ch := SubStr(src, 1, 1)
        src := SubStr(src, 2)

        if (ch = '"')
            break
        else if (ch = "\") {
            if (src = "")
                throw Error("Unterminated string")

            escapeCh := SubStr(src, 1, 1)
            src := SubStr(src, 2)

            if (escapeCh = "n")
                str .= "`n"
            else if (escapeCh = "r")
                str .= "`r"
            else if (escapeCh = "t")
                str .= "`t"
            else if (escapeCh = '"')
                str .= '"'
            else if (escapeCh = "\")
                str .= "\"
            else
                str .= escapeCh
        } else {
            str .= ch
        }
    }

    return str
}

_Jxon_ParseNumber(&src) {
    numStr := ""

    while (src != "" && InStr("0123456789.-+eE", SubStr(src, 1, 1))) {
        numStr .= SubStr(src, 1, 1)
        src := SubStr(src, 2)
    }

    return Number(numStr)
}

_Jxon_ParseBool(&src) {
    if (SubStr(src, 1, 4) = "true") {
        src := SubStr(src, 5)
        return true
    } else if (SubStr(src, 1, 5) = "false") {
        src := SubStr(src, 6)
        return false
    }
    throw Error("Invalid boolean")
}

_Jxon_ParseNull(&src) {
    if (SubStr(src, 1, 4) = "null") {
        src := SubStr(src, 5)
        return ""
    }
    throw Error("Invalid null")
}

; ===== STARTUP MANAGEMENT =====
; Normalize path for comparison (handles forward/backslashes, trailing slashes, case)
NormalizePath(path) {
    ; Replace forward slashes with backslashes
    path := StrReplace(path, "/", "\")
    ; Remove trailing backslash
    path := RTrim(path, "\")
    ; Convert to lowercase for case-insensitive comparison
    path := StrLower(path)
    return path
}

IsStartupEnabled() {
    startupPath := A_Startup "\" A_ScriptName ".lnk"
    return FileExist(startupPath)
}

; Sync startup state with config.ini setting
SyncStartupWithConfig() {
    try {
        shouldBeEnabled := Config.GetBool("launch_on_startup", false)
        currentlyEnabled := IsStartupEnabled()

        if (shouldBeEnabled && !currentlyEnabled) {
            ; Config says enabled but shortcut doesn't exist - create it
            EnableStartup()
        } else if (!shouldBeEnabled && currentlyEnabled) {
            ; Config says disabled but shortcut exists - remove it
            DisableStartup()
        }
        ; If they match, do nothing
    } catch {
        ; Sync failed, but don't block execution
    }
}

EnableStartup() {
    try {
        startupPath := A_Startup "\" A_ScriptName ".lnk"

        ; Get icon path if available
        iconPath := A_ScriptDir "\helpbruce.ico"
        if !FileExist(iconPath)
            iconPath := ""

        ; Create shortcut with proper parameters (working dir is crucial for AHK v2)
        FileCreateShortcut(A_ScriptFullPath, startupPath, A_ScriptDir, "", "Bruce Helper Auto-Paste Listener", iconPath)
        return true
    } catch {
        return false
    }
}

DisableStartup() {
    try {
        startupPath := A_Startup "\" A_ScriptName ".lnk"
        if FileExist(startupPath)
            FileDelete(startupPath)
        return true
    } catch {
        return false
    }
}

; ===== STARTUP =====
; One-time migration: If startup shortcut exists but config doesn't have it set, update config
; This preserves existing user preferences when upgrading to version with persistent startup setting
if (IsStartupEnabled() && !Config.GetBool("launch_on_startup", false)) {
    try {
        IniWrite("true", Config.configFile, "Settings", "launch_on_startup")
        Config.Load()  ; Reload to pick up the change
    } catch {
        ; Migration failed, but don't block execution
    }
}

NotifySuccess("Bruce Helper v" VERSION " Started", "Listener active")
A_IconTip := "Bruce Helper v" VERSION "`n" .
             "Auto-paste: Enabled"

; Sync startup shortcut with config setting (preserves setting across updates)
SyncStartupWithConfig()

; Check for updates on startup (if enabled in config) - silent mode with toast notifications
if (Config.GetBool("check_updates_on_startup", true))
    CheckForUpdates(true)  ; true = silent mode, shows toast notification if update available

; ===== CLIPBOARD MONITOR (Auto-Paste) =====
OnClipboardChange ClipboardMonitor

ClipboardMonitor(DataType) {
    ; Only process text
    if DataType != 1
        return

    ; If already processing a clipboard change, skip this one to prevent interference
    global bruceHelperProcessing
    if (bruceHelperProcessing) {
        return
    }

    ; Defer ALL clipboard reading to let OnClipboardChange return immediately
    ; This prevents blocking other scripts during their ClipWait operations
    ; Configurable delay gives enough time for other scripts (like report-check) to complete their operations
    deferDelay := Config.GetInt("clipboard_defer_delay", Constants.CLIPBOARD_DEFER_DELAY)
    SetTimer () => ProcessClipboardChange(), -deferDelay
}

ProcessClipboardChange() {
    ; Prevent re-entry - this function should only run once at a time
    global bruceHelperProcessing
    if (bruceHelperProcessing) {
        return
    }

    bruceHelperProcessing := true

    try {
        ; Read clipboard once and store it - exit silently if locked by another script
        clipText := ""
        try {
            clipText := A_Clipboard
        } catch {
            ; Clipboard locked by another script, exit gracefully
            return
        }

        ; Quick exit for short content (likely not a Bruce report)
        ; Bruce reports are typically 200+ characters
        if (StrLen(clipText) < Constants.MIN_REPORT_LENGTH) {
            return
        }

        ; Ultra-fast string search before regex (InStr is much faster than RegExMatch)
        ; This provides a quick rejection path for non-Bruce clipboard content
        if !InStr(clipText, Constants.MARKER) {
            return  ; Not a Bruce report - exit immediately
        }

        ; Full validation with regex (only reached if basic marker found)
        if !RegExMatch(clipText, Constants.MARKER "\d+>>>")
            return  ; Not a Bruce report - exit immediately

        ; Validate end marker
        if !InStr(clipText, Constants.END_MARKER)
            return

        ; Extract clean content (remove markers)
        cleaned := RegExReplace(clipText, Constants.MARKER "\d+>>>\s*\n", "")
        cleaned := RegExReplace(cleaned, "\s*\n" Constants.END_MARKER, "")
        cleaned := Trim(cleaned)

        ; Update clipboard with clean text - wrap in try/catch
        try {
            A_Clipboard := cleaned
            Sleep 100
        } catch {
            return  ; Failed to update clipboard, exit gracefully
        }

        ; Auto-paste to PowerScribe
        PasteToPowerScribe()

    } finally {
        ; Always clear busy flag, even if an error occurs
        bruceHelperProcessing := false
    }
}


; ===== MAIN PASTE FUNCTION =====
PasteToPowerScribe() {
    ; Verify clipboard has content (exit silently if empty)
    if !A_Clipboard
        return

    ; Find and activate PowerScribe window
    powerScribeFound := false
    activeExe := ""

    ; Try PowerScribe 360 first
    if WinExist(Constants.POWERSCRIBE_360) {
        WinActivate Constants.POWERSCRIBE_360
        Sleep Constants.POWERSCRIBE_ACTIVATION_DELAY
        powerScribeFound := true
        activeExe := "PowerScribe 360"
    }
    ; Try PSOne if PowerScribe 360 not found
    else if WinExist(Constants.POWERSCRIBE_ONE) {
        WinActivate Constants.POWERSCRIBE_ONE
        Sleep Constants.POWERSCRIBE_ACTIVATION_DELAY
        powerScribeFound := true
        activeExe := "PSOne"
    }

    ; Exit silently if PowerScribe not found
    if !powerScribeFound
        return

    ; Wait for window to be active
    activated := false
    if WinActive(Constants.POWERSCRIBE_360) || WinActive(Constants.POWERSCRIBE_ONE) {
        activated := true
    } else {
        ; Try waiting up to 2 seconds
        Loop 20 {
            if WinActive(Constants.POWERSCRIBE_360) || WinActive(Constants.POWERSCRIBE_ONE) {
                activated := true
                break
            }
            Sleep 100
        }
    }

    ; Exit silently if activation failed
    if !activated
        return

    ; Optional: Check for unsaved changes (asterisk in title)
    winTitle := WinGetTitle("A")
    if InStr(winTitle, "*") {
        result := MsgBox("PowerScribe has unsaved changes.`n`nReplace with Bruce report?",
                         "Confirm Paste", "YesNo 0")
        if result = "No"
            return
    }

    ; Select all existing text
    Send "^a"
    selectDelay := Config.GetInt("powerscribe_select_delay", Constants.POWERSCRIBE_SELECT_DELAY)
    Sleep selectDelay

    ; Paste the report (replaces selected text)
    Send "^v"
    Sleep 100

    ; Success notification
    NotifySuccess("Bruce Helper → " activeExe, "Report pasted successfully")
}

; ===== ENTERPRISE ENVIRONMENT DETECTION =====
; Function to detect enterprise environment restrictions
DetectEnterpriseRestrictions() {
    restrictions := {
        isDomain: false,
        domainName: "",
        isEnterpriseEdition: false,
        windowsEdition: "",
        appLockerActive: false,
        detectionErrors: []
    }

    try {
        ; Check if computer is domain-joined
        try {
            objWMI := ComObjGet("winmgmts:\\.\root\cimv2")
            colItems := objWMI.ExecQuery("SELECT * FROM Win32_ComputerSystem")
            for objItem in colItems {
                if (objItem.PartOfDomain) {
                    restrictions.isDomain := true
                    restrictions.domainName := objItem.Domain
                }
            }
        } catch as err {
            restrictions.detectionErrors.Push("Domain check failed: " . err.Message)
        }

        ; Check Windows edition
        try {
            restrictions.windowsEdition := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "EditionID")
            if (InStr(restrictions.windowsEdition, "Enterprise") || InStr(restrictions.windowsEdition, "Education")) {
                restrictions.isEnterpriseEdition := true
            }
        } catch as err {
            restrictions.detectionErrors.Push("Edition check failed: " . err.Message)
        }

        ; Try to detect AppLocker (check if service exists and is running)
        try {
            objWMI := ComObjGet("winmgmts:\\.\root\cimv2")
            colItems := objWMI.ExecQuery("SELECT * FROM Win32_Service WHERE Name='AppIDSvc'")
            for objItem in colItems {
                if (objItem.State = "Running") {
                    restrictions.appLockerActive := true
                }
            }
        } catch as err {
            restrictions.detectionErrors.Push("AppLocker check failed: " . err.Message)
        }

    } catch as err {
        restrictions.detectionErrors.Push("General detection error: " . err.Message)
    }

    return restrictions
}

; ===== TRAY MENU =====
; Detect and log enterprise restrictions
enterpriseInfo := DetectEnterpriseRestrictions()

; Setup System Tray Menu with error detection
trayMenuSuccess := false
try {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Bruce Helper v" VERSION, (*) => {})
    A_TrayMenu.Disable("Bruce Helper v" VERSION)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Settings", (*) => ShowSettingsGUI())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.ClickCount := 1

    trayMenuSuccess := true

} catch as err {
    ; Build error message with actual failure details
    errorMsg := "Failed to setup tray menu`n" .
                "Error: " . err.Message

    ; Only add enterprise context if restrictions are actually detected
    if (enterpriseInfo.isDomain || enterpriseInfo.appLockerActive) {
        errorMsg .= "`n`nEnterprise restrictions detected:`n" .
                    "Domain: " . (enterpriseInfo.isDomain ? enterpriseInfo.domainName : "None") . "`n" .
                    "AppLocker: " . (enterpriseInfo.appLockerActive ? "Active" : "Inactive")
    }

    NotifyError("Tray Menu Error", errorMsg)
}

CheckPowerScribeStatus(*) {
    ps360 := WinExist(Constants.POWERSCRIBE_360) ? "✓" : "✗"
    psone := WinExist(Constants.POWERSCRIBE_ONE) ? "✓" : "✗"

    status := "PowerScribe Status:`n`n" .
              ps360 " PowerScribe 360 (Nuance.PowerScribe360.exe)`n" .
              psone " PSOne (Nuance.PSOne.exe)`n`n" .
              "Clipboard Monitor: Active"

    MsgBox status, "Bruce Helper", 0
}

; ===== SETTINGS GUI =====
global settingsGui := ""
global updateStatusText := ""
global updateAvailableText := ""
global primaryUpdateBtn := ""
global cancelUpdateBtn := ""
global updateState := "check"
global newestUpdateVersion := ""
global newestUpdateSHA256 := ""

ShowSettingsGUI(*) {
    global settingsGui, updateStatusText, updateAvailableText, primaryUpdateBtn, cancelUpdateBtn, updateState

    ; If GUI already exists, just show it
    if (settingsGui && WinExist("ahk_id " settingsGui.Hwnd)) {
        settingsGui.Show()
        return
    }

    ; Create new GUI with modern styling
    settingsGui := Gui("+Resize MinSize500x450", "Bruce Helper Settings")
    settingsGui.SetFont("s10", "Segoe UI")
    settingsGui.OnEvent("Close", (*) => settingsGui.Hide())

    ; Set custom icon if available
    try {
        iconPath := A_ScriptDir . "\helpbruce.ico"
        if FileExist(iconPath) {
            settingsGui.Opt("+Icon" . iconPath)
        }
    } catch {
        ; Continue without icon
    }

    ; Add Tab Control
    tabs := settingsGui.Add("Tab3", "x10 y10 w530 h400", ["Main", "About"])

    ; ===== MAIN TAB =====
    tabs.UseTab(1)

    settingsGui.Add("GroupBox", "x20 y50 w510 h120", "Status")
    settingsGui.Add("Text", "x30 y75 w150", "PowerScribe 360:")
    ps360Status := WinExist(Constants.POWERSCRIBE_360) ? "✓ Running" : "✗ Not Found"
    settingsGui.Add("Text", "x180 y75 w260 c" (WinExist(Constants.POWERSCRIBE_360) ? "Green" : "Red"), ps360Status)

    settingsGui.Add("Text", "x30 y100 w150", "PSOne:")
    psoneStatus := WinExist(Constants.POWERSCRIBE_ONE) ? "✓ Running" : "✗ Not Found"
    settingsGui.Add("Text", "x180 y100 w260 c" (WinExist(Constants.POWERSCRIBE_ONE) ? "Green" : "Red"), psoneStatus)

    settingsGui.Add("Text", "x30 y125 w150", "Clipboard Monitor:")
    settingsGui.Add("Text", "x180 y125 w260 cGreen", "✓ Active")

    ; Startup Options
    settingsGui.Add("GroupBox", "x20 y180 w510 h100", "Startup Options")
    startupCheckbox := settingsGui.Add("CheckBox", "x30 y205 w480 vStartupEnabled",
        "Launch Bruce Helper when Windows starts")
    startupCheckbox.Value := IsStartupEnabled() ? 1 : 0

    updateCheckbox := settingsGui.Add("CheckBox", "x30 y235 w480 vCheckUpdatesOnStartup",
        "Check for updates when script starts")
    updateCheckbox.Value := Config.GetBool("check_updates_on_startup", true) ? 1 : 0

    ; ===== ABOUT TAB =====
    tabs.UseTab(2)

    settingsGui.Add("GroupBox", "x20 y50 w510 h140", "About Bruce Helper")
    settingsGui.Add("Text", "x30 y75 w490 h25 +Center", "Bruce Helper → PowerScribe Listener")
    settingsGui.Add("Text", "x30 y100 w490 h25 +Center c888888", "Version " VERSION)

    settingsGui.Add("Text", "x30 y135 w490 h50",
        "Automatically pastes Bruce radiology reports into PowerScribe when you click 'PS Send' in the Bruce web interface.")

    ; Update Options
    settingsGui.Add("GroupBox", "x20 y200 w510 h180", "Updates")

    updateStatusText := settingsGui.Add("Text", "x30 y225 w490 h25", "Current version: " VERSION)
    updateStatusText.SetFont("s10")

    updateAvailableText := settingsGui.Add("Text", "x30 y255 w490 h40 Hidden", "")
    updateAvailableText.SetFont("s9")

    primaryUpdateBtn := settingsGui.Add("Button", "x30 y305 w150 h40", "Check for Updates")
    primaryUpdateBtn.OnEvent("Click", (*) => OnPrimaryUpdateClick())
    primaryUpdateBtn.SetFont("s10")

    cancelUpdateBtn := settingsGui.Add("Button", "x190 y305 w80 h40 Hidden", "Cancel")
    cancelUpdateBtn.OnEvent("Click", (*) => ResetUpdateUI())
    cancelUpdateBtn.SetFont("s10")

    updateState := "check"

    ; Reset tab usage
    tabs.UseTab()

    ; Add Save and Close buttons
    btnSave := settingsGui.Add("Button", "x380 y420 w70 h30", "Save")
    btnClose := settingsGui.Add("Button", "x460 y420 w70 h30", "Close")

    btnSave.OnEvent("Click", (*) => SaveSettings())
    btnClose.OnEvent("Click", (*) => settingsGui.Hide())

    ; Show the GUI
    settingsGui.Show("w550 h480")
}

; ===== UPDATE FLOW FUNCTIONS =====
OnPrimaryUpdateClick() {
    global updateState
    if (updateState = "check") {
        CheckForUpdatesInGUI()
    } else if (updateState = "install") {
        InstallUpdate()
    }
}

ResetUpdateUI() {
    global updateState, primaryUpdateBtn, cancelUpdateBtn, updateAvailableText, updateStatusText
    updateState := "check"
    primaryUpdateBtn.Text := "Check for Updates"
    primaryUpdateBtn.Enabled := true
    cancelUpdateBtn.Visible := false
    updateAvailableText.Visible := false
    updateStatusText.Text := "Current version: " VERSION
    updateStatusText.SetFont("s10")
}

CheckForUpdatesInGUI() {
    global updateState, primaryUpdateBtn, cancelUpdateBtn, updateAvailableText, updateStatusText
    global newestUpdateVersion, newestUpdateSHA256

    try {
        updateStatusText.Text := "Checking for updates..."
        updateStatusText.SetFont("s10")

        result := CheckForUpdates(false)  ; false = not silent, but we handle UI ourselves

        if (!result.success) {
            updateStatusText.Text := "Error: " . result.error
            updateStatusText.SetFont("s10")
            NotifyError("Update Check Failed", result.error)
            return
        }

        if (!result.updateAvailable) {
            updateStatusText.Text := "Current version: " VERSION " (latest)"
            updateStatusText.SetFont("s10")
            NotifyInfo("Update Check", "You are running the latest version.")
        } else {
            updateStatusText.Text := "Current: " VERSION " → Available: " . result.version
            updateStatusText.SetFont("s10")

            updateAvailableText.Text := "Release: " . result.releaseDate . " - " . result.releaseNotes
            updateAvailableText.Visible := true

            updateState := "install"
            primaryUpdateBtn.Text := "Install Update"
            cancelUpdateBtn.Visible := true

            newestUpdateVersion := result.version
            newestUpdateSHA256 := result.sha256

            NotifyInfo("Update Available", "Version " . result.version . " found!")
        }

    } catch as err {
        updateStatusText.Text := "Error checking for updates"
        updateStatusText.SetFont("s10")
        NotifyError("Update Check Failed", err.Message)
    }
}

InstallUpdate() {
    global newestUpdateVersion, newestUpdateSHA256, updateState, primaryUpdateBtn, updateStatusText

    if (newestUpdateVersion = "") {
        NotifyError("Update Error", "No update version selected")
        return
    }

    ; Build version info object
    versionInfo := Map()
    versionInfo["sha256"] := newestUpdateSHA256

    result := MsgBox(
        "Install update v" . newestUpdateVersion . "?`n`n" .
        "• File will be downloaded and verified (SHA-256)`n" .
        "• Current version will be backed up`n" .
        "• Application will restart automatically`n`n" .
        "Continue?",
        "Confirm Update Installation",
        "YesNo Icon?")

    if (result != "Yes") {
        return
    }

    try {
        updateState := "installing"
        updateStatusText.Text := "Installing update..."
        updateStatusText.SetFont("s10")
        primaryUpdateBtn.Text := "Installing..."
        primaryUpdateBtn.Enabled := false

        PerformUpdate(newestUpdateVersion, versionInfo)

    } catch as err {
        NotifyError("Update Failed", err.Message)
        updateState := "install"
        primaryUpdateBtn.Text := "Install Update"
        primaryUpdateBtn.Enabled := true
    }
}

SaveSettings() {
    global settingsGui

    try {
        values := settingsGui.Submit(0)

        ; Handle startup setting
        currentlyEnabled := IsStartupEnabled()
        wantsEnabled := values.StartupEnabled

        if (wantsEnabled && !currentlyEnabled) {
            if (EnableStartup()) {
                NotifySuccess("Settings Saved", "Startup enabled successfully")
            } else {
                NotifyError("Error", "Failed to enable startup")
                return
            }
        } else if (!wantsEnabled && currentlyEnabled) {
            if (DisableStartup()) {
                NotifySuccess("Settings Saved", "Startup disabled successfully")
            } else {
                NotifyError("Error", "Failed to disable startup")
                return
            }
        } else {
            NotifySuccess("Settings Saved", "Settings saved successfully")
        }

        ; Save check updates on startup setting to config.ini
        checkUpdates := values.CheckUpdatesOnStartup ? "true" : "false"
        IniWrite(checkUpdates, Config.configFile, "Settings", "check_updates_on_startup")

        ; Save launch on startup setting to config.ini (preserves across updates)
        launchOnStartup := values.StartupEnabled ? "true" : "false"
        IniWrite(launchOnStartup, Config.configFile, "Settings", "launch_on_startup")

        ; Reload config to pick up changes
        Config.Load()

        settingsGui.Hide()

    } catch as err {
        NotifyError("Error", "Failed to save settings: " err.Message)
    }
}

; ===============================================================================
; === SHARED INFRASTRUCTURE (Python path, DICOM service, heartbeat) ===
; ===============================================================================

; Resolve embedded Python path: shared ../python-embedded → %LOCALAPPDATA% → local fallback
GetPythonPath() {
    ; Try shared vaguslab location (development)
    pythonPath := A_ScriptDir "\..\python-embedded\python.exe"
    if (FileExist(pythonPath))
        return pythonPath

    ; Try shared vaguslab location (production)
    pythonPath := EnvGet("LOCALAPPDATA") "\vaguslab\python-embedded\python.exe"
    if (FileExist(pythonPath))
        return pythonPath

    ; Try local python/ directory (legacy standalone)
    pythonPath := A_ScriptDir "\python\python.exe"
    if (FileExist(pythonPath))
        return pythonPath

    return ""  ; Not found
}

; Ensure the shared DICOM service process is running.
; Finds the service script (dev sibling → LOCALAPPDATA), checks if already
; running via lock file PID, and launches if needed.
EnsureDicomService(cacheDir := "") {
    ; Locate dicom_service.py
    serviceScript := ""

    ; Dev layout: sibling directory
    devPath := A_ScriptDir . "\..\dicom-service\dicom_service.py"
    if (FileExist(devPath))
        serviceScript := devPath

    ; Production layout: shared LOCALAPPDATA
    if (serviceScript = "") {
        prodPath := EnvGet("LOCALAPPDATA") . "\vaguslab\dicom-service\dicom_service.py"
        if (FileExist(prodPath))
            serviceScript := prodPath
    }

    if (serviceScript = "") {
        Logger.Warning("DICOM service script not found")
        return
    }

    ; Check if already running via lock file
    lockFile := ""
    devLock := A_ScriptDir . "\..\dicom-service\data\service.lock"
    prodLock := EnvGet("LOCALAPPDATA") . "\vaguslab\dicom-service\data\service.lock"

    if (FileExist(devPath))
        lockFile := devLock
    else
        lockFile := prodLock

    if (FileExist(lockFile)) {
        try {
            pidStr := Trim(FileRead(lockFile, "UTF-8"))
            pid := Integer(pidStr)
            ; Check if process is still alive via ProcessExist
            if (ProcessExist(pid)) {
                Logger.Info("DICOM service already running", {pid: pid})
                return
            }
            ; Process not found — stale lock
            Logger.Info("Stale DICOM service lock — will relaunch")
        } catch {
            ; Invalid PID or read error — continue to launch
            Logger.Info("Invalid DICOM service lock — will relaunch")
        }
    }

    ; Launch the service
    pythonPath := GetPythonPath()
    if (pythonPath = "") {
        Logger.Warning("Cannot launch DICOM service — Python not found")
        return
    }

    cmd := '"' . pythonPath . '" "' . serviceScript . '"'
    if (cacheDir != "")
        cmd .= ' --cache-dir "' . cacheDir . '"'

    try {
        Run(cmd,, "Hide")
        Logger.Info("DICOM service launched", {script: serviceScript, cache_dir: cacheDir})
    } catch as err {
        Logger.Warning("Failed to launch DICOM service", {error: err.Message})
    }
}

; Heartbeat for the DICOM service — write a timestamp every 10 seconds so
; the service knows bruce-helper is still alive.  If the heartbeat goes
; stale (>30 s), the service shuts itself down and releases file locks.
global _heartbeatFile := ""
StartDicomHeartbeat() {
    global _heartbeatFile
    ; Resolve the data directory — create it if the service is installed but
    ; the data dir hasn't been created yet (race: the service may not have
    ; run _acquire_lock() yet when we get here).
    devDataDir := A_ScriptDir . "\..\dicom-service\data"
    prodDataDir := EnvGet("LOCALAPPDATA") . "\vaguslab\dicom-service\data"

    dataDir := ""
    if (FileExist(A_ScriptDir . "\..\dicom-service\dicom_service.py")) {
        ; Dev layout — service is installed; ensure data dir exists
        if (!DirExist(devDataDir))
            try DirCreate(devDataDir)
        dataDir := devDataDir
    } else if (FileExist(EnvGet("LOCALAPPDATA") . "\vaguslab\dicom-service\dicom_service.py")) {
        ; Production layout — service is installed; ensure data dir exists
        if (!DirExist(prodDataDir))
            try DirCreate(prodDataDir)
        dataDir := prodDataDir
    }

    if (dataDir = "")
        return  ; service not installed

    _heartbeatFile := dataDir . "\heartbeat"
    WriteDicomHeartbeat()  ; write immediately
    SetTimer(WriteDicomHeartbeat, 10000)  ; then every 10 s
}
WriteDicomHeartbeat() {
    global _heartbeatFile
    if (_heartbeatFile = "")
        return
    try {
        f := FileOpen(_heartbeatFile, "w", "UTF-8")
        f.Write(A_Now)
        f.Close()
    } catch {
        ; best-effort
    }
}

; ===============================================================================
; === PYTHON WEBSOCKET SERVER ===
; ===============================================================================
; Launches embedded Python WebSocket server for browser communication
; ===============================================================================

global PYTHON_PID := 0

; Start Python WebSocket server in background
StartPythonServer() {
    global PYTHON_PID

    pythonPath := GetPythonPath()
    serverPath := A_ScriptDir "\server.py"
    pidFile    := A_ScriptDir "\data\server.pid"

    if (pythonPath = "") {
        NotifyError("Python Error", "Python not found — check python-embedded or local python/ directory")
        return
    }

    if !FileExist(serverPath) {
        NotifyError("Python Error", "server.py not found at: " serverPath)
        return
    }

    ; Kill any previously running server before starting a new one.
    ; Two sources: the PID file written by server.py (survives AHK restarts)
    ; and PYTHON_PID (valid when the same AHK instance started the server).
    killedOld := false
    if FileExist(pidFile) {
        try {
            existingPid := Integer(Trim(FileRead(pidFile)))
            if (existingPid > 0 && ProcessExist(existingPid)) {
                try ProcessClose(existingPid)
                killedOld := true
            }
        }
        try FileDelete(pidFile)
    }
    if (PYTHON_PID != 0 && ProcessExist(PYTHON_PID)) {
        try ProcessClose(PYTHON_PID)
        killedOld := true
    }
    PYTHON_PID := 0
    ; Give the OS time to release port 8765 before binding again.
    if killedOld
        Sleep(400)

    ; Launch hidden Python server
    try {
        Run('"' pythonPath '" "' serverPath '"', , "Hide", &PID)
        PYTHON_PID := PID
        NotifyInfo("WebSocket API Started", "Python server started on ws://localhost:8765")
    } catch as err {
        NotifyError("Python Error", "Failed to start server: " err.Message)
    }
}

; Cleanup on exit
OnExit(CleanupOnExit)

CleanupOnExit(*) {
    ; Stop heartbeat timer
    SetTimer(WriteDicomHeartbeat, 0)

    ; Kill Python server via TerminateProcess (ProcessClose in AHK v2).
    ; ProcessWaitClose blocks until the OS has fully released all file handles,
    ; so files in the bruce-helper directory are not "in use" after AHK exits.
    global PYTHON_PID
    if (PYTHON_PID != 0) {
        try ProcessClose(PYTHON_PID)
        try ProcessWaitClose(PYTHON_PID, 3)  ; Wait up to 3 s for handles to release
        PYTHON_PID := 0
    }
}

; Start Python server automatically
StartPythonServer()

; ===============================================================================
; === END PYTHON WEBSOCKET SERVER ===
; ===============================================================================
