; ==============================================
; Logger - Centralized Logging System
; ==============================================
; Provides structured logging with levels and daily log files
; Usage:
;   Logger.Error("API call failed", {provider: "Claude", error: "timeout"})
;   Logger.Info("Review completed successfully")
;   Logger.Debug("Processing report", {length: 1500})

class Logger {
    ; Log levels (higher number = more verbose)
    static LOG_LEVEL_NONE := 0
    static LOG_LEVEL_ERROR := 1
    static LOG_LEVEL_WARNING := 2
    static LOG_LEVEL_INFO := 3
    static LOG_LEVEL_DEBUG := 4

    static currentLevel := this.LOG_LEVEL_INFO
    static logDir := A_ScriptDir . "\logs"
    static maxLogFiles := 5
    static currentLogFile := ""

    ; --- Public Logging Methods ---

    static Error(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_ERROR)
            this._WriteLog("ERROR", message, context)
    }

    static Warning(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_WARNING)
            this._WriteLog("WARNING", message, context)
    }

    static Info(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_INFO)
            this._WriteLog("INFO", message, context)
    }

    static Debug(message, context := "") {
        if (this.currentLevel >= this.LOG_LEVEL_DEBUG)
            this._WriteLog("DEBUG", message, context)
    }

    ; --- Log Level Management ---

    static SetLevel(level) {
        if (level >= this.LOG_LEVEL_NONE && level <= this.LOG_LEVEL_DEBUG) {
            this.currentLevel := level
            levelNames := Map(0, "NONE", 1, "ERROR", 2, "WARNING", 3, "INFO", 4, "DEBUG")
            this.Info("Log level changed", {new_level: levelNames.Get(level, "UNKNOWN")})
        }
    }

    static GetLevel() {
        return this.currentLevel
    }

    ; --- Utility Methods ---

    static GetLogFilePath() {
        this._EnsureInit()
        return this.currentLogFile
    }

    static OpenLogDirectory() {
        try {
            if (!DirExist(this.logDir))
                DirCreate(this.logDir)
            Run(this.logDir)
        }
    }

    ; --- Internal Methods ---

    static _EnsureInit() {
        if (this.currentLogFile = "") {
            try {
                if (!DirExist(this.logDir))
                    DirCreate(this.logDir)
                this.currentLogFile := this.logDir . "\report-check_" . FormatTime(, "yyyy-MM-dd") . ".log"
                this._CleanOldLogs()
            }
        }
    }

    static _WriteLog(level, message, context := "") {
        try {
            this._EnsureInit()
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            logEntry := "[" . timestamp . "] [" . level . "] " . message
            if (context != "") {
                contextStr := this._FormatContext(context)
                if (contextStr != "")
                    logEntry .= " | " . contextStr
            }
            FileAppend(logEntry . "`n", this.currentLogFile, "UTF-8")
        } catch {
            ; If logging fails, silently continue (don't crash the app)
        }
    }

    static _FormatContext(context) {
        try {
            if (!IsObject(context))
                return String(context)
            parts := []
            if (context is Map) {
                for key, value in context
                    parts.Push(key . "=" . this._FormatValue(value))
            } else {
                for key, value in context.OwnProps()
                    parts.Push(key . "=" . this._FormatValue(value))
            }
            if (parts.Length > 0) {
                result := ""
                Loop parts.Length {
                    if (A_Index > 1)
                        result .= ", "
                    result .= parts[A_Index]
                }
                return result
            }
            return ""
        } catch as err {
            return "[FormatContext error: " . err.Message . "]"
        }
    }

    static _FormatValue(value) {
        try {
            if (IsObject(value))
                return "[Object]"
            else if (value = "")
                return '""'
            else
                return String(value)
        } catch {
            return "[Error formatting value]"
        }
    }

    ; Delete oldest log files when more than maxLogFiles exist
    static _CleanOldLogs() {
        try {
            fileCount := 0
            oldestTime := ""
            oldestPath := ""
            Loop Files, this.logDir . "\report-check_*.log" {
                fileCount += 1
                modTime := A_LoopFileTimeModified
                if (oldestTime = "" || modTime < oldestTime) {
                    oldestTime := modTime
                    oldestPath := A_LoopFileFullPath
                }
            }
            if (fileCount > this.maxLogFiles && oldestPath != "") {
                try FileDelete(oldestPath)
                ; Recurse in case multiple files need cleanup
                this._CleanOldLogs()
            }
        } catch {
            ; If cleanup fails, continue (don't crash the app)
        }
    }
}
