; ==============================================
; Logger - Centralized Logging System
; ==============================================
; Provides structured logging with levels, rotation, and safe file operations
; Usage:
;   Logger.Error("API call failed", {provider: "Claude", error: "timeout"})
;   Logger.Info("Review completed successfully")
;   Logger.Debug("Processing report", {length: 1500})

class Logger {
    ; ==============================================
    ; Configuration
    ; ==============================================

    ; Log levels (higher number = more verbose)
    static LOG_LEVEL_NONE := 0
    static LOG_LEVEL_ERROR := 1
    static LOG_LEVEL_WARNING := 2
    static LOG_LEVEL_INFO := 3
    static LOG_LEVEL_DEBUG := 4

    ; Current log level (can be changed via ConfigManager)
    static currentLevel := this.LOG_LEVEL_INFO

    ; Log file settings
    static logDir := A_ScriptDir . "\logs"
    static maxLogFiles := 5  ; Keep last 5 days of logs
    static maxLogSizeMB := 10  ; Start new log if current exceeds 10MB

    ; Current log file path (initialized on first use)
    static currentLogFile := ""

    ; ==============================================
    ; Public Logging Methods
    ; ==============================================

    ; Log error message (always logged unless level is NONE)
    static Error(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_ERROR) {
            this._WriteLog("ERROR", message, context)
        }
    }

    ; Log warning message
    static Warning(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_WARNING) {
            this._WriteLog("WARNING", message, context)
        }
    }

    ; Log info message (default level)
    static Info(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_INFO) {
            this._WriteLog("INFO", message, context)
        }
    }

    ; Log debug message (verbose, only in debug mode)
    static Debug(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_DEBUG) {
            this._WriteLog("DEBUG", message, context)
        }
    }

    ; ==============================================
    ; Specialized Logging Methods
    ; ==============================================

    ; Log API call with timing information
    static LogAPICall(provider, model, success, durationMs := 0, errorMsg := "") {
        context := {
            provider: provider,
            model: model,
            success: success,
            duration_ms: durationMs
        }

        if (!success && errorMsg != "") {
            context.error := errorMsg
        }

        if (success) {
            this.Info("API call completed", context)
        } else {
            this.Error("API call failed", context)
        }
    }

    ; Log result object (from ResultHelper)
    static LogResult(result, operation := "") {
        if (!IsObject(result) || !result.HasProp("success")) {
            this.Warning("LogResult called with invalid result object")
            return
        }

        context := {operation: operation}

        ; Add all result properties to context
        for key, value in result.OwnProps() {
            if (key != "success") {
                context.%key% := value
            }
        }

        if (result.success) {
            this.Info("Operation succeeded: " . operation, context)
        } else {
            this.Error("Operation failed: " . operation, context)
        }
    }

    ; Log application startup
    static LogStartup(version) {
        this.Info("Application started", {
            version: version,
            script_dir: A_ScriptDir,
            ahk_version: A_AhkVersion,
            os_version: A_OSVersion
        })
    }

    ; Log configuration changes
    static LogConfigChange(setting, oldValue, newValue) {
        this.Info("Configuration changed", {
            setting: setting,
            old_value: oldValue,
            new_value: newValue
        })
    }

    ; ==============================================
    ; Log Level Management
    ; ==============================================

    ; Set current log level
    static SetLevel(level) {
        if (level >= this.LOG_LEVEL_NONE && level <= this.LOG_LEVEL_DEBUG) {
            this.currentLevel := level
            this.Info("Log level changed", {new_level: this._LevelToString(level)})
        }
    }

    ; Get current log level
    static GetLevel() {
        return this.currentLevel
    }

    ; ==============================================
    ; Internal Methods
    ; ==============================================

    ; Initialize logging system (create directory, rotate old logs)
    static _Initialize() {
        try {
            ; Create logs directory if it doesn't exist
            if (!DirExist(this.logDir)) {
                DirCreate(this.logDir)
            }

            ; Set current log file path
            this.currentLogFile := this.logDir . "\bruce-helper_" . FormatTime(, "yyyy-MM-dd") . ".log"

            ; Rotate old logs
            this._RotateLogs()

            ; Check if current log file is too large
            if (FileExist(this.currentLogFile)) {
                fileSize := FileGetSize(this.currentLogFile)
                if (fileSize > (this.maxLogSizeMB * 1024 * 1024)) {
                    ; Rename current log with timestamp
                    newName := this.logDir . "\bruce-helper_" . FormatTime(, "yyyy-MM-dd_HHmmss") . ".log"
                    try {
                        FileMove(this.currentLogFile, newName)
                    }
                }
            }

            return true
        } catch {
            ; If logging setup fails, silently continue (don't crash the app)
            return false
        }
    }

    ; Write log entry to file
    static _WriteLog(level, message, context := "") {
        try {
            ; Initialize on first use
            if (this.currentLogFile = "") {
                this._Initialize()
            }

            ; Build log entry
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            logEntry := "[" . timestamp . "] [" . level . "] " . message

            ; Add context if provided
            if (context != "") {
                contextStr := this._FormatContext(context)
                if (contextStr != "") {
                    logEntry .= " | " . contextStr
                }
            }

            ; Write to file (append mode)
            FileAppend(logEntry . "`n", this.currentLogFile, "UTF-8")

        } catch as err {
            ; If logging fails, silently continue (don't crash the app)
            ; Could optionally show tooltip in debug mode
        }
    }

    ; Format context object/map as string
    static _FormatContext(context) {
        try {
            if (!IsObject(context)) {
                return String(context)
            }

            parts := []
            ; Check if it's a Map
            if (context is Map) {
                for key, value in context {
                    parts.Push(key . "=" . this._FormatValue(value))
                }
            } else {
                ; It's an object with properties
                for key, value in context.OwnProps() {
                    parts.Push(key . "=" . this._FormatValue(value))
                }
            }

            ; Manually join array elements with ", "
            if (parts.Length > 0) {
                result := ""
                Loop parts.Length {
                    if (A_Index > 1) {
                        result .= ", "
                    }
                    result .= parts[A_Index]
                }
                return result
            }
            return ""
        } catch as err {
            ; Return error info for debugging
            return "[FormatContext error: " . err.Message . "]"
        }
    }

    ; Format a single value for logging
    static _FormatValue(value) {
        try {
            if (IsObject(value)) {
                return "[Object]"
            } else if (value = "") {
                return '""'
            } else {
                return String(value)
            }
        } catch {
            return "[Error formatting value]"
        }
    }

    ; Rotate old log files (keep only maxLogFiles)
    static _RotateLogs() {
        try {
            ; Get all log files sorted by modification time (oldest first)
            logFiles := []
            Loop Files, this.logDir . "\*.log" {
                logFiles.Push({
                    path: A_LoopFileFullPath,
                    time: FileGetTime(A_LoopFileFullPath, "M")  ; Modified time
                })
            }

            ; Sort by time (oldest first)
            if (logFiles.Length > 0) {
                ; Simple bubble sort
                Loop logFiles.Length - 1 {
                    outerIndex := A_Index
                    Loop logFiles.Length - outerIndex {
                        innerIndex := A_Index
                        if (logFiles[innerIndex].time > logFiles[innerIndex + 1].time) {
                            temp := logFiles[innerIndex]
                            logFiles[innerIndex] := logFiles[innerIndex + 1]
                            logFiles[innerIndex + 1] := temp
                        }
                    }
                }

                ; Delete oldest files if we have too many
                if (logFiles.Length > this.maxLogFiles) {
                    deleteCount := logFiles.Length - this.maxLogFiles
                    Loop deleteCount {
                        try {
                            FileDelete(logFiles[A_Index].path)
                        }
                    }
                }
            }
        } catch {
            ; If rotation fails, continue (don't crash the app)
        }
    }

    ; Convert log level number to string
    static _LevelToString(level) {
        switch level {
            case this.LOG_LEVEL_NONE: return "NONE"
            case this.LOG_LEVEL_ERROR: return "ERROR"
            case this.LOG_LEVEL_WARNING: return "WARNING"
            case this.LOG_LEVEL_INFO: return "INFO"
            case this.LOG_LEVEL_DEBUG: return "DEBUG"
            default: return "UNKNOWN"
        }
    }

    ; ==============================================
    ; Utility Methods
    ; ==============================================

    ; Get current log file path
    static GetLogFilePath() {
        if (this.currentLogFile = "") {
            this._Initialize()
        }
        return this.currentLogFile
    }

    ; Open log directory in Explorer
    static OpenLogDirectory() {
        try {
            if (!DirExist(this.logDir)) {
                DirCreate(this.logDir)
            }
            Run(this.logDir)
        }
    }

    ; Clear all log files (useful for testing)
    static ClearAllLogs() {
        try {
            Loop Files, this.logDir . "\*.log" {
                FileDelete(A_LoopFileFullPath)
            }
            this.Info("All log files cleared")
            return true
        } catch {
            return false
        }
    }
}
