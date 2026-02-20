; Radiology Report Review - Enhanced with Settings and Configuration
; Press Ctrl+Shift+` to review selected text with Claude

; ==============================================
; Compilation Directives (for building EXE)
; ==============================================
;@Ahk2Exe-SetMainIcon rc.ico
;@Ahk2Exe-SetVersion 0.30.2
;@Ahk2Exe-SetProductName Report Check
;@Ahk2Exe-SetDescription Radiology Report Checker
;@Ahk2Exe-SetCompanyName vaguslab
;@Ahk2Exe-SetCopyright © 2025 vaguslab. All rights reserved
;@Ahk2Exe-ExeName report-check.exe
;@Ahk2Exe-AddResource rc.ico, 160

#Requires AutoHotkey v2.0
#SingleInstance Force

; Close any other AutoHotkey instances running from this directory
; This handles migration from old script names (report check.ahk)
; Skip when compiled - not needed for standalone EXEs
if (!A_IsCompiled) {
    CloseOtherInstancesFromThisDir()
}

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

; Global version information - must be defined before includes
global VERSION := "0.30.2"

; ==============================================
; Include Module Files
; ==============================================
#Include lib\Constants.ahk
#Include lib\Logger.ahk
#Include lib\ResultHelper.ahk
#Include lib\SharedUtils.ahk
#Include lib\NotificationManager.ahk
#Include lib\ModifierKeyManager.ahk
#Include lib\VersionManager.ahk
#Include lib\ConfigManager.ahk
#Include lib\PromptCache.ahk
; #Include lib\APIManager.ahk  ; MIGRATED TO PYTHON: api_handler.py
#Include lib\APIRateLimiter.ahk
#Include ..\shared\vendor\ComVar.ahk
#Include ..\shared\vendor\Promise.ahk
#Include ..\shared\vendor\WebView2.ahk
#Include ..\shared\vendor\WebViewToo.ahk
#Include lib\ConfigBuilder.ahk
#Include lib\SettingsValidator.ahk
#Include lib\SettingsPresenter.ahk
#Include lib\SettingsGui.ahk
#Include lib\gui\IntegrityCheckGui.ahk
#Include lib\gui\ReviewGui.ahk
; #Include lib\TemplateManager.ahk  ; MIGRATED TO PYTHON: html_generator.py
; #Include lib\DicomDemographics.ahk  ; MIGRATED TO PYTHON: dicom-service/
; #Include lib\DicomMonitor.ahk  ; MIGRATED TO PYTHON: dicom-service/
; #Include lib\TargetedReviewManager.ahk  ; MIGRATED TO PYTHON: targeted_review.py

; ==============================================
; Main Application Functions
; ==============================================

; Log application startup
Logger.Info("Application started", {version: VERSION, ahk_version: A_AhkVersion})

; Log that rate limiter is enabled
Logger.Info("Rate limiter enabled", {min_interval_ms: Constants.API_RATE_LIMIT_MS})

; Initialize configuration
try {
    ConfigManager.LoadConfig()
    Logger.Info("Configuration loaded successfully")

    ; Apply debug logging setting if enabled
    if (ConfigManager.config["Settings"].Get("debug_logging", false)) {
        Logger.SetLevel(Logger.LOG_LEVEL_DEBUG)
        Logger.Info("Debug logging enabled")
    }
} catch as err {
    Logger.Error("Failed to load configuration", {error: err.Message})
    MsgBox("Error loading configuration: " err.Message)
    ExitApp
}

; Initialize prompt cache (loads all prompts into memory)
try {
    result := PromptCache.Initialize(ConfigManager.configDir)
    if (result.success) {
        Logger.Info("Prompt cache initialized successfully")
    } else {
        Logger.Warning("Prompt cache initialized with errors (using fallbacks)")
    }
} catch as err {
    Logger.Error("Failed to initialize prompt cache", {error: err.Message})
    ; Non-fatal - PromptCache has fallback mechanisms
}

; Targeted review manager initialization removed — now handled by Python backend
; (see targeted_review.py)

; Ensure the shared DICOM service is running (only if demographic extraction is enabled)
_dicomEnabled := ConfigManager.config["Beta"].Get("demographic_extraction_enabled", false)
Logger.Info("DICOM service check", {demographic_extraction_enabled: _dicomEnabled})
if (_dicomEnabled) {
    try {
        EnsureDicomService()
    } catch as err {
        Logger.Warning("Failed to ensure DICOM service", {error: err.Message})
        ; Non-fatal - targeted review will work without real-time monitoring
    }
}

; Heartbeat for the DICOM service — write a timestamp every 10 seconds so
; the service knows report-check is still alive.  If the heartbeat goes
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
StartDicomHeartbeat()

; Set custom icon on startup
SetCustomIcon()

; Function to set custom icon
SetCustomIcon() {
    try {
        ; NOTE: Compiled EXEs use a single embedded icon set at compile time
        ; This function only works for script mode (not compiled)
        if (!A_IsCompiled) {
            ; Look for icon file in script directory
            scriptDir := A_ScriptDir
            iconPath := scriptDir . "\rc.ico"

            ; Check if icon file exists
            if FileExist(iconPath) {
                ; Set tray icon
                TraySetIcon(iconPath)
            }
        }

        ; Set tooltip (works in both script and compiled modes)
        A_IconTip := "Report Check v" VERSION

    } catch as e {
        ; Set tooltip even without custom icon
        A_IconTip := "Report Check v" VERSION
    }
}

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

; Detect and log enterprise restrictions
enterpriseInfo := DetectEnterpriseRestrictions()

; Log at Info level only if restrictions detected, otherwise Debug level
if (enterpriseInfo.isDomain || enterpriseInfo.appLockerActive || enterpriseInfo.isEnterpriseEdition) {
    Logger.Info("Enterprise environment detected", {
        is_domain: enterpriseInfo.isDomain,
        domain: enterpriseInfo.domainName,
        is_enterprise_edition: enterpriseInfo.isEnterpriseEdition,
        windows_edition: enterpriseInfo.windowsEdition,
        applocker_active: enterpriseInfo.appLockerActive,
        detection_errors: enterpriseInfo.detectionErrors.Length > 0 ? enterpriseInfo.detectionErrors : "none"
    })
} else {
    Logger.Debug("Enterprise environment detection complete - no restrictions detected", {
        windows_edition: enterpriseInfo.windowsEdition
    })
}

; Setup System Tray Menu with error detection
trayMenuSuccess := false
try {
    A_TrayMenu.Delete()  ; Clear default menu
    A_TrayMenu.Add("Report Check v" VERSION, (*) => {})
    A_TrayMenu.Disable("Report Check v" VERSION)
    A_TrayMenu.Add()  ; Separator
    A_TrayMenu.Add("Settings", (*) => SettingsGui.Show())
    ; Integrity checks only available in script mode (verify .ahk files against server)
    if (!A_IsCompiled) {
        A_TrayMenu.Add("Check Integrity", (*) => RunIntegrityCheck())
        A_TrayMenu.Add()  ; Separator
    }
    A_TrayMenu.Add("Mode: Comprehensive", (*) => SwitchMode("comprehensive"))
    A_TrayMenu.Add("Mode: Proofreading", (*) => SwitchMode("proofreading"))
    A_TrayMenu.Add()  ; Separator
    A_TrayMenu.Add("Open Log Folder", (*) => Logger.OpenLogDirectory())
    A_TrayMenu.Add()  ; Separator
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.ClickCount := 1

    trayMenuSuccess := true
    Logger.Info("Tray menu initialized successfully")
} catch as err {
    Logger.Error("Failed to setup tray menu", {
        error: err.Message,
        line: err.Line,
        is_domain: enterpriseInfo.isDomain,
        applocker_active: enterpriseInfo.appLockerActive
    })

    ; Only log enterprise warning if restrictions are actually detected
    if (enterpriseInfo.isDomain || enterpriseInfo.appLockerActive) {
        Logger.Warning("Enterprise restrictions detected - custom tray menu may be blocked by Group Policy or AppLocker", {
            is_domain: enterpriseInfo.isDomain,
            domain: enterpriseInfo.domainName,
            applocker_active: enterpriseInfo.appLockerActive
        })
    }
}

; Update menu to show current mode
try {
    UpdateModeMenu()
} catch as err {
    Logger.Error("Failed to update mode menu checkmarks", {error: err.Message})
}

; Log final tray menu status
if (trayMenuSuccess) {
    Logger.Info("Tray menu setup complete")
} else {
    Logger.Warning("Tray menu setup incomplete - application may have limited tray functionality")
}

; Check for missing API key and prompt user (now that tray menu is ready)
; This is delayed until after tray menu setup to prevent blocking dialogs
; from interfering with initialization
provider := ConfigManager.GetProvider()
currentApiKey := ConfigManager.GetProviderAPIKey(provider)  ; Use proper method to handle encrypted keys

if (currentApiKey = "" || Trim(currentApiKey) = "") {
    ; Use longer delay to ensure all initialization is complete
    SetTimer(() => ConfigManager._PromptForAPIKey(), -1000)
    Logger.Info("API key missing - first-time setup dialog will appear after initialization")
}

; Run update check on startup (script mode only - compiled EXEs can't self-update)
if (!A_IsCompiled) {
    RunStartupUpdateCheck()
}

; Function to update mode menu checkmarks
UpdateModeMenu() {
    currentMode := ConfigManager.config["Settings"].Get("prompt_type", "comprehensive")

    ; Update checkmarks based on current mode
    if (currentMode = "comprehensive") {
        A_TrayMenu.Check("Mode: Comprehensive")
        A_TrayMenu.Uncheck("Mode: Proofreading")
    } else {
        A_TrayMenu.Uncheck("Mode: Comprehensive")
        A_TrayMenu.Check("Mode: Proofreading")
    }
}

; Function to switch between modes
SwitchMode(newMode) {
    ; Get current mode
    currentMode := ConfigManager.config["Settings"].Get("prompt_type", "comprehensive")

    ; If already in this mode, do nothing
    if (currentMode = newMode) {
        return
    }

    ; Update config
    ConfigManager.config["Settings"]["prompt_type"] := newMode
    ConfigManager.SaveConfig()

    ; Update menu display
    UpdateModeMenu()

    ; Refresh Settings GUI if it's open
    SettingsGui.RefreshModeDisplay()

    ; Show notification
    modeDisplay := (newMode = "comprehensive") ? "Comprehensive" : "Proofreading"
    NotifySuccess("Mode Changed", "Switched to " . modeDisplay . " mode")
}

; Comprehensive diagnose and fix function with interactive dialog
DiagnoseAndFixKeys() {
    ShowDiagnosticDialog()
}

; Show the diagnostic dialog with recheck capability
ShowDiagnosticDialog() {
    result := ModifierKeyManager.DiagnoseAndFix()
    message := ModifierKeyManager.FormatDiagnosticMessage(result) . "`n"

    if (result.stuckAfter.Length > 0) {
        response := MsgBox(message, "Modifier Key Diagnostics", 5)  ; 5=RetryCancel buttons
        if (response = "Retry")
            ShowDiagnosticDialog()
    } else {
        MsgBox(message, "Modifier Key Diagnostics", 0)
    }
}

; Legacy function kept for backward compatibility (e.g., tray menu)
ResetStuckKeys() {
    result := ModifierKeyManager.ResetAllModifiers()

    ; Show appropriate notification based on result
    if (result.fixed.Length > 0) {
        NotifySuccess("Modifier Keys Reset", result.message)
    } else if (result.failed.Length > 0) {
        NotifyWarning("Reset Incomplete", result.message)
    } else {
        NotifyInfo("Modifier Keys", result.message)
    }
}

; Function to run integrity check on startup (silent mode)
RunStartupIntegrityCheck() {
    ; Safety check: integrity checks don't work in compiled mode
    if (A_IsCompiled) {
        return
    }

    ; Get startup integrity check setting (default: enabled)
    checkOnStartup := ConfigManager.config["Settings"].Get("check_integrity_on_startup", true)

    if (!checkOnStartup) {
        return
    }

    ; Run check in background
    SetTimer(() => PerformIntegrityCheck(true), -1000)  ; Run after 1 second delay
}

; Function to manually run integrity check (from menu)
RunIntegrityCheck() {
    ; Safety check: integrity checks don't work in compiled mode
    if (A_IsCompiled) {
        IntegrityCheckGui.ShowNotAvailable()
        return
    }

    PerformIntegrityCheck(false)  ; Show all results
}

; Perform the actual integrity check
PerformIntegrityCheck(silentMode := false) {
    ; Safety check: integrity checks don't work in compiled mode
    if (A_IsCompiled) {
        if (!silentMode) {
            IntegrityCheckGui.ShowNotAvailable()
        }
        return
    }

    try {
        ; Show checking dialog (non-silent) or tray tip (silent)
        if (!silentMode) {
            IntegrityCheckGui.Show()
        } else {
            NotifyInfo("Integrity Check", "Verifying all files...")
        }

        ; Run the integrity verification
        result := VersionManager.VerifyScriptIntegrity(VERSION)

        if (!result.success) {
            ; Error occurred (network timeout, server down, etc.)
            NotifyError("Integrity Check Failed", result.error)
            if (!silentMode) {
                IntegrityCheckGui.ShowError("Integrity check failed:`n`n" . result.error)
            } else {
                Logger.Warning("Integrity check skipped - server unavailable", {error: result.error})
            }
            return
        }

        if (result.verified) {
            ; Check if this is a development version
            if (result.HasProp("isDevelopment") && result.isDevelopment) {
                ; Development version - show info message
                if (!silentMode) {
                    NotifyInfo("Development Version", "Integrity check not available")
                    IntegrityCheckGui.ShowDev(result.message)
                }
            } else {
                ; All files verified successfully
                verifiedCount := result.verifiedCount

                if (!silentMode) {
                    NotifySuccess("Integrity Check Passed", verifiedCount . " files verified")
                    IntegrityCheckGui.ShowPassed(verifiedCount, VERSION)
                }
            }
        } else {
            ; Some files failed verification
            NotifyError("Security Warning", "Files have been modified!")

            if (!silentMode) {
                IntegrityCheckGui.ShowFailed(result.failedFiles.Length, VERSION, result.failedFiles)
            }
        }

    } catch as err {
        NotifyError("Integrity Check Error", "Unexpected error: " . err.Message)
        if (!silentMode) {
            IntegrityCheckGui.ShowError("An unexpected error occurred:`n`n" . err.Message)
        } else {
            Logger.Error("Integrity check skipped - unexpected error", {error: err.Message})
        }
    }
}

; ==============================================
; Startup Update Check
; ==============================================

; Function to run update check on startup (with delay)
RunStartupUpdateCheck() {
    ; Safety check: updates don't work in compiled mode
    if (A_IsCompiled) {
        return
    }

    ; Check if startup update check is enabled
    if (!Constants.UPDATE_CHECK_STARTUP) {
        return
    }

    ; Run check in background after 10 second delay
    SetTimer(() => PerformStartupUpdateCheck(), -10000)
}

; Perform the actual update check at startup
PerformStartupUpdateCheck() {
    ; Safety check: updates don't work in compiled mode
    if (A_IsCompiled) {
        return
    }

    try {
        ; Check for updates using the API
        result := VersionManager.CheckForUpdatesFromAPI(VERSION)

        if (!result.success) {
            ; Silent failure - just log it
            Logger.Warning("Startup update check failed", {error: result.error})
            return
        }

        if (!result.updateAvailable) {
            ; No update available - silent (no notification)
            Logger.Info("Update check complete - running latest version", {version: VERSION})
            return
        }

        ; Update is available - show toast notification
        Logger.Info("Update available", {
            current: VERSION,
            latest: result.version,
            releaseDate: result.releaseDate
        })

        ; Show toast notification about available update
        message := "Version " . result.version . " is available!`n"
        if (result.releaseDate != "") {
            message .= "Released: " . result.releaseDate . "`n"
        }
        message .= "Open Settings → Updates to install"

        NotifyInfo("Update Available", message, Constants.NOTIFICATION_DURATION_WARNING)

    } catch as err {
        ; Silent failure - just log it
        Logger.Error("Startup update check error", {error: err.Message})
    }
}

; Activate PowerScribe window with retry logic and full-screen detection
; Returns object with success status and diagnostic information
ActivatePowerScribeWindow() {
    result := {
        success: false,
        process: "",
        attempts: 0,
        fullscreen: false,
        error: ""
    }

    ; Define PowerScribe process names to try (in priority order)
    processes := [
        {exe: "ahk_exe Nuance.PowerScribe360.exe", name: "PowerScribe 360"},
        {exe: "ahk_exe Nuance.PSOne.exe", name: "PSOne"}
    ]

    ; Try each process type
    for processInfo in processes {
        ; Check if window exists
        if (!WinExist(processInfo.exe)) {
            Logger.Debug("PowerScribe process not found", {process: processInfo.name})
            continue
        }

        Logger.Debug("PowerScribe window found", {process: processInfo.name})

        ; Try activation with retry logic
        Loop Constants.POWERSCRIBE_RETRY_ATTEMPTS {
            result.attempts := A_Index

            Logger.Debug("Attempting window activation", {
                process: processInfo.name,
                attempt: A_Index
            })

            ; Check if window is full-screen before activation
            try {
                WinGetPos(&winX, &winY, &winWidth, &winHeight, processInfo.exe)
                ; Check if window dimensions match screen (full-screen detection)
                if (winWidth >= A_ScreenWidth && winHeight >= A_ScreenHeight) {
                    result.fullscreen := true
                    Logger.Debug("PowerScribe appears to be in full-screen mode")
                }
            } catch as err {
                Logger.Warning("Could not get window position", {error: err.Message})
            }

            ; Attempt to activate the window
            try {
                WinActivate(processInfo.exe)

                ; Wait for window to become active (with timeout)
                if (WinWaitActive(processInfo.exe, , Constants.POWERSCRIBE_ACTIVATION_TIMEOUT / 1000)) {
                    ; Window successfully activated
                    result.success := true
                    result.process := processInfo.name
                    Logger.Debug("Window activation confirmed", {
                        process: processInfo.name,
                        attempt: A_Index
                    })
                    return result
                } else {
                    ; Activation timed out
                    Logger.Warning("Window activation timeout", {
                        process: processInfo.name,
                        attempt: A_Index,
                        timeout_ms: Constants.POWERSCRIBE_ACTIVATION_TIMEOUT
                    })

                    ; If not last attempt, wait before retrying
                    if (A_Index < Constants.POWERSCRIBE_RETRY_ATTEMPTS) {
                        Sleep(Constants.POWERSCRIBE_RETRY_DELAY)
                    }
                }
            } catch as err {
                Logger.Error("Window activation error", {
                    process: processInfo.name,
                    attempt: A_Index,
                    error: err.Message
                })

                ; If not last attempt, wait before retrying
                if (A_Index < Constants.POWERSCRIBE_RETRY_ATTEMPTS) {
                    Sleep(Constants.POWERSCRIBE_RETRY_DELAY)
                }
            }
        }

        ; If we tried this process but failed, set error and continue to next process
        result.error := "Window activation timeout after " . result.attempts . " attempts"
    }

    ; If we get here, none of the processes worked
    if (result.process = "") {
        result.error := "PowerScribe window not found (tried PowerScribe 360 and PSOne)"
    }

    return result
}

; ==============================================
; Python Backend Helpers
; ==============================================

; Ensure the shared DICOM service process is running.
; Finds the service script (dev sibling → LOCALAPPDATA), checks if already
; running via lock file PID, and launches if needed.
EnsureDicomService() {
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

    ; Launch the service (reads its own config.ini for cache dir and other settings)
    pythonPath := GetPythonPath()
    if (pythonPath = "") {
        Logger.Warning("Cannot launch DICOM service — Python not found")
        return
    }

    cmd := '"' . pythonPath . '" "' . serviceScript . '"'

    try {
        Run(cmd,, "Hide")
        Logger.Info("DICOM service launched", {script: serviceScript})
    } catch as err {
        Logger.Warning("Failed to launch DICOM service", {error: err.Message})
    }
}

; Resolve embedded Python path: Config → shared %LOCALAPPDATA% → local fallback
GetPythonPath() {
    ; Try config first
    pythonPath := ConfigManager.config["Settings"].Get("python_path", "")
    if (pythonPath != "" && FileExist(pythonPath))
        return pythonPath

    ; Try shared vaguslab location (development)
    pythonPath := A_ScriptDir "\..\python-embedded\python.exe"
    if (FileExist(pythonPath))
        return pythonPath

    ; Try shared vaguslab location (production)
    pythonPath := EnvGet("LOCALAPPDATA") "\vaguslab\python-embedded\python.exe"
    if (FileExist(pythonPath))
        return pythonPath

    ; Try local python/ directory
    pythonPath := A_ScriptDir "\python\python.exe"
    if (FileExist(pythonPath))
        return pythonPath

    return ""  ; Not found
}

; Parse a simple JSON response — extract a string value by key name
; Returns empty string if key not found
_ExtractJSONStringValue(jsonStr, key) {
    ; Find "key": "value" or "key": null
    marker := '"' . key . '"'
    pos := InStr(jsonStr, marker)
    if (pos <= 0)
        return ""

    ; Skip past the key, colon, and any whitespace
    pos += StrLen(marker)
    while (pos <= StrLen(jsonStr)) {
        char := SubStr(jsonStr, pos, 1)
        if (char = '"') {
            ; Found opening quote — extract value
            pos += 1
            endPos := pos
            while (endPos <= StrLen(jsonStr)) {
                ch := SubStr(jsonStr, endPos, 1)
                if (ch = '"') {
                    ; Check if escaped
                    backslashCount := 0
                    checkPos := endPos - 1
                    while (checkPos > 0 && SubStr(jsonStr, checkPos, 1) = "\") {
                        backslashCount += 1
                        checkPos -= 1
                    }
                    if (Mod(backslashCount, 2) = 0)
                        return SubStr(jsonStr, pos, endPos - pos)
                }
                endPos += 1
            }
            return SubStr(jsonStr, pos)
        } else if (char = "n") {
            ; Could be null
            return ""
        } else if (char = ":" || char = " " || char = "`t" || char = "`n" || char = "`r") {
            pos += 1
        } else {
            return ""
        }
    }
    return ""
}

; Check if a JSON key has a boolean true value
_ExtractJSONBoolValue(jsonStr, key) {
    marker := '"' . key . '"'
    pos := InStr(jsonStr, marker)
    if (pos <= 0)
        return false
    pos += StrLen(marker)
    ; Skip : and whitespace, look for "true"
    remaining := SubStr(jsonStr, pos, 20)
    return InStr(remaining, "true") > 0
}

; Main function to review radiology report
; If modeOverride is provided ("comprehensive" or "proofreading"), use that mode instead of current setting
ReviewRadiologyReport(modeOverride := "") {
    ; Check rate limiter before proceeding
    if (!APIRateLimiter.CanMakeCall()) {
        Logger.Warning("Review blocked by rate limiter")
        return
    }

    Logger.Info("Review initiated", {mode_override: modeOverride != "" ? modeOverride : "none"})

    ; Verify Python is available
    pythonPath := GetPythonPath()
    if (pythonPath = "") {
        Logger.Error("Python not found — check python_path in Settings or install embedded Python")
        NotifyError("Error", "Python not found. Check Settings or install embedded Python.")
        return
    }

    savedClipboard := ClipboardAll()

    try {
        ; --- AHK-native: clipboard capture (unchanged) ---
        modeText := ""
        if (modeOverride = "comprehensive") {
            modeText := " (Forced Comprehensive)"
        } else if (modeOverride = "proofreading") {
            modeText := " (Forced Proofreading)"
        }
        NotifyInfo("Processing..." . modeText, "Capturing selected text")

        ; PowerScribe auto-select
        powerscribeAutoselect := ConfigManager.config["Beta"].Get("powerscribe_autoselect", false)
        powerscribeActivated := false

        if (powerscribeAutoselect) {
            activationResult := ActivatePowerScribeWindow()
            if (activationResult.success) {
                powerscribeActivated := true
                Logger.Info("PowerScribe window activated", {process: activationResult.process})
                Sleep(Constants.POWERSCRIBE_ACTIVATION_DELAY)
                Send("^a")
                Sleep(Constants.POWERSCRIBE_SELECT_DELAY)
            } else {
                Logger.Warning("PowerScribe activation failed", {reason: activationResult.error})
            }
        }

        ; Copy selected text
        try {
            A_Clipboard := ""
        } catch as err {
            Logger.Warning("Failed to clear clipboard", {error: err.Message})
        }
        Send("^c")
        ModifierKeyManager.PreventiveRelease()

        if (!ClipWait(Constants.CLIPBOARD_WAIT_TIMEOUT / 1000)) {
            A_Clipboard := savedClipboard
            Logger.Warning("Clipboard timeout - no text captured")
            NotifyError("Error", "No text selected or clipboard timeout")
            return
        }

        try {
            originalReport := A_Clipboard
        } catch as err {
            A_Clipboard := savedClipboard
            Logger.Error("Failed to read clipboard", {error: err.Message})
            NotifyError("Error", "Failed to read clipboard: " . err.Message)
            return
        }

        reportLength := StrLen(originalReport)
        Logger.Debug("Text captured from clipboard", {length: reportLength})

        ; Deselect text in PowerScribe
        if (powerscribeActivated) {
            reactivationResult := ActivatePowerScribeWindow()
            if (reactivationResult.success) {
                Sleep(200)
                Send("{Right}")
                Sleep(100)
            }
        }

        savedClipboard := ""

        ; --- Delegate to Python backend (streaming) ---
        provider := ConfigManager.GetProvider()
        providerName := (provider = "gemini") ? "Gemini" : (provider = "openai") ? "OpenAI" : "Claude"
        NotifyInfo("Sending to " . providerName . "..." . modeText, "Analyzing your report")

        APIRateLimiter.StartCall()

        ; Prepare temp directory and files
        requestDir := A_Temp "\ReportCheck"
        if (!DirExist(requestDir))
            DirCreate(requestDir)

        ; Write report text to separate file (avoids JSON escaping)
        reportFile := requestDir "\report_text.txt"
        try FileDelete(reportFile)
        FileAppend(originalReport, reportFile, "UTF-8-RAW")

        ; Prepare streaming files
        tick := A_TickCount
        requestFile := requestDir "\request.json"
        streamFile := requestDir "\stream_" tick ".txt"
        statusFile := requestDir "\stream_status_" tick ".json"
        try FileDelete(requestFile)
        try FileDelete(streamFile)
        try FileDelete(statusFile)

        ; Write request JSON with stream_review command
        request := '{"command":"stream_review"'
                 . ',"report_text_file":"' . StrReplace(reportFile, "\", "\\") . '"'
                 . ',"mode_override":"' . modeOverride . '"'
                 . ',"config_path":"' . StrReplace(ConfigManager.configFile, "\", "\\") . '"'
                 . ',"stream_file":"' . StrReplace(streamFile, "\", "\\") . '"'
                 . ',"status_file":"' . StrReplace(statusFile, "\", "\\") . '"'
                 . ',"version":"' . VERSION . '"'
                 . '}'
        FileAppend(request, requestFile, "UTF-8-RAW")

        ; Open streaming UI immediately (shows spinner → streaming tokens)
        ReviewGui.ShowStreaming(streamFile, statusFile)

        ; Launch Python non-blocking — ReviewGui handles the rest via polling
        Logger.Info("Launching Python backend (streaming)", {python: pythonPath})
        Run('"' . pythonPath . '" "' . A_ScriptDir . '\backend.py" "' . requestFile . '"',, "Hide")

        APIRateLimiter.EndCall()

    } catch as err {
        Logger.Error("Unexpected error in ReviewRadiologyReport", {
            error: err.Message, what: err.What, extra: err.Extra, file: err.File, line: err.Line
        })
        if (savedClipboard != "") {
            try {
                A_Clipboard := savedClipboard
            }
        }
        NotifyError("Error", "Unexpected error: " . err.Message)

    } finally {
        if (APIRateLimiter.IsCallInProgress())
            APIRateLimiter.EndCall()
        ModifierKeyManager.PreventiveRelease()
        savedClipboard := ""
    }
}

; --- HTML generation, markdown conversion, and targeted review ---
; MIGRATED TO PYTHON: html_generator.py, targeted_review.py
; These functions have been removed. Python backend handles all
; HTML generation, markdown-to-HTML conversion, and targeted review.

; Copy text to clipboard function
CopyToClipboard(text) {
    A_Clipboard := text
    NotifySuccess("Copied", "Text copied to clipboard")
}

; Set up hotkeys
^F11:: {
    ReviewRadiologyReport()
}

; Conditionally register mode override hotkeys if beta feature is enabled
if (ConfigManager.config["Beta"].Get("mode_override_hotkeys", false)) {
    Hotkey("^F10", (*) => ReviewRadiologyReport("comprehensive"))  ; Ctrl + F10 - Force comprehensive mode
    Hotkey("^F9", (*) => ReviewRadiologyReport("proofreading"))  ; Ctrl + F9 - Force proofreading mode
}

; DICOM service runs independently — no exit handler needed

; Show startup notification
NotifySuccess("Report Check v" VERSION " started", "Ready for report review")
