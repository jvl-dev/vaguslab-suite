; ==============================================
; Shared Utilities Class
; ==============================================
; Common utility functions used across multiple modules
; to eliminate code duplication and provide centralized
; implementations of frequently used operations.

class SharedUtils {
    
    ; ==============================================
    ; String Utilities
    ; ==============================================
    
    ; Repeat a character or string a specified number of times
    static RepeatChar(char, count) {
        local result := ""
        Loop count {
            result .= char
        }
        return result
    }
    
    ; ==============================================
    ; JSON Utilities
    ; ==============================================
    
    ; Comprehensive JSON string escaping
    ; Handles all JSON special characters according to RFC 7159
    static EscapeJSONString(str) {
        if (str = "") {
            return ""
        }
        
        ; Escape characters in the correct order to avoid double-escaping
        safeStr := StrReplace(str, "\", "\\")     ; Escape backslashes first
        safeStr := StrReplace(safeStr, '"', '\"') ; Escape quotes
        safeStr := StrReplace(safeStr, "`n", "\n") ; Escape newlines
        safeStr := StrReplace(safeStr, "`r", "\r") ; Escape carriage returns
        safeStr := StrReplace(safeStr, "`t", "\t") ; Escape tabs
        safeStr := StrReplace(safeStr, "/", "\/")  ; Escape forward slashes (optional but safer)
        safeStr := StrReplace(safeStr, "`b", "\b") ; Escape backspace
        safeStr := StrReplace(safeStr, "`f", "\f") ; Escape form feed
        return safeStr
    }
    
    ; Unescape JSON strings back to original format
    static UnescapeJSONString(str) {
        if (str = "") {
            return ""
        }
        
        ; Unescape in reverse order
        safeStr := StrReplace(str, "\f", "`f")    ; Unescape form feed
        safeStr := StrReplace(safeStr, "\b", "`b") ; Unescape backspace
        safeStr := StrReplace(safeStr, "\/", "/")  ; Unescape forward slashes
        safeStr := StrReplace(safeStr, "\t", "`t") ; Unescape tabs
        safeStr := StrReplace(safeStr, "\r", "`r") ; Unescape carriage returns
        safeStr := StrReplace(safeStr, "\n", "`n") ; Unescape newlines
        safeStr := StrReplace(safeStr, '\"', '"')  ; Unescape quotes
        safeStr := StrReplace(safeStr, "\\", "\")  ; Unescape backslashes last
        return safeStr
    }
    
    ; ==============================================
    ; Validation Utilities
    ; ==============================================
    
    ; Validate Anthropic/Claude API key format
    static ValidateAPIKey(apiKey) {
        return this.ValidateClaudeAPIKey(apiKey)
    }

    ; Validate Claude API key format
    static ValidateClaudeAPIKey(apiKey) {
        ; Claude API keys have specific format
        apiKey := Trim(apiKey)

        ; Must start with sk-ant-
        if (!RegExMatch(apiKey, "^sk-ant-")) {
            return {valid: false, error: "Claude API keys must start with 'sk-ant-'"}
        }

        ; Check minimum length (Claude keys are typically 108 characters)
        if (StrLen(apiKey) < 40) {
            return {valid: false, error: "API key too short (minimum 40 characters)"}
        }

        ; Check for valid characters (alphanumeric, hyphens, underscores)
        if (!RegExMatch(apiKey, "^[a-zA-Z0-9\-_]+$")) {
            return {valid: false, error: "API key contains invalid characters"}
        }

        return {valid: true, error: ""}
    }

    ; Validate Gemini API key format
    static ValidateGeminiAPIKey(apiKey) {
        ; Gemini API keys have specific format
        apiKey := Trim(apiKey)

        ; Check for empty
        if (apiKey = "") {
            return {valid: false, error: "API key cannot be empty"}
        }

        ; Gemini keys are typically 39 characters, alphanumeric with hyphens and underscores
        keyLength := StrLen(apiKey)
        if (keyLength < 30 || keyLength > 50) {
            return {valid: false, error: "API key length unusual (expected 30-50 characters)"}
        }

        ; Check for valid characters (alphanumeric, hyphens, underscores)
        if (!RegExMatch(apiKey, "^[a-zA-Z0-9\-_]+$")) {
            return {valid: false, error: "API key contains invalid characters"}
        }

        return {valid: true, error: ""}
    }

    ; Validate OpenAI API key format
    static ValidateOpenAIAPIKey(apiKey) {
        ; OpenAI API keys have specific format
        apiKey := Trim(apiKey)

        ; Check for empty
        if (apiKey = "") {
            return {valid: false, error: "API key cannot be empty"}
        }

        ; OpenAI keys start with "sk-" (both old and new format)
        ; New format: sk-proj-... (longer)
        if (!RegExMatch(apiKey, "^sk-")) {
            return {valid: false, error: "OpenAI API keys must start with 'sk-'"}
        }

        ; Check minimum length
        if (StrLen(apiKey) < 20) {
            return {valid: false, error: "API key too short"}
        }

        ; Check for valid characters (alphanumeric, hyphens, underscores, and periods)
        ; Modern OpenAI keys can contain periods (e.g., sk-proj-...)
        if (!RegExMatch(apiKey, "^[a-zA-Z0-9\-_.]+$")) {
            return {valid: false, error: "API key contains invalid characters"}
        }

        return {valid: true, error: ""}
    }
    
    ; Validate URL format
    static ValidateURL(url) {
        url := Trim(url)
        
        ; Basic URL validation
        if (!RegExMatch(url, "^https?://")) {
            return false
        }
        
        ; Check for basic URL structure
        if (!RegExMatch(url, "^https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}")) {
            return false
        }
        
        return true
    }
    
    ; ==============================================
    ; File Utilities
    ; ==============================================
    
    ; Safely create a directory if it doesn't exist
    static EnsureDirectoryExists(dirPath) {
        try {
            if (!DirExist(dirPath)) {
                DirCreate(dirPath)
                return true
            }
            return true
        } catch as err {
            return false
        }
    }
    
    ; ==============================================
    ; Array Utilities
    ; ==============================================
    
    ; Join array elements with a separator (replacement for _StrJoin)
    static JoinArray(arr, separator) {
        result := ""
        for i, item in arr {
            if (i > 1)
                result .= separator
            result .= item
        }
        return result
    }
    
    ; ==============================================
    ; Version Utilities
    ; ==============================================

    ; Compare version strings (e.g., "1.2.3" vs "1.2.4")
    ; Returns: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
    static CompareVersions(version1, version2) {
        ; Split versions into components
        parts1 := StrSplit(version1, ".")
        parts2 := StrSplit(version2, ".")

        ; Pad arrays to same length
        maxLength := Max(parts1.Length, parts2.Length)

        ; Compare each component
        Loop maxLength {
            v1 := (A_Index <= parts1.Length) ? Integer(parts1[A_Index]) : 0
            v2 := (A_Index <= parts2.Length) ? Integer(parts2[A_Index]) : 0

            if (v1 < v2) {
                return -1
            } else if (v1 > v2) {
                return 1
            }
        }

        return 0  ; Versions are equal
    }

    ; ==============================================
    ; HTML Utilities
    ; ==============================================

    ; ==============================================
    ; Date Verification
    ; ==============================================

    ; Pre-verify all DD/MM/YYYY dates in report text against today's date.
    ; Returns a verification summary block to prepend to the report, or ""
    ; if no dates were found. Each date is tagged as PAST, TODAY, or FUTURE.
    static PreVerifyDates(reportText) {
        today := FormatTime(A_Now, "yyyyMMdd")
        todayDisplay := FormatTime(A_Now, "d/M/yyyy")

        results := []
        startPos := 1

        ; Find all DD/MM/YYYY dates (1-2 digit day/month, 4-digit year)
        while (startPos <= StrLen(reportText)) {
            if !RegExMatch(reportText, "(\d{1,2})/(\d{1,2})/(\d{4})", &m, startPos)
                break

            day := m[1], month := m[2], year := m[3]
            dateStr := m[0]

            ; Zero-pad for comparison
            dayPad := Format("{:02}", Integer(day))
            monthPad := Format("{:02}", Integer(month))
            compDate := year . monthPad . dayPad

            ; Determine status
            if (compDate > today)
                status := "FUTURE"
            else if (compDate = today)
                status := "TODAY"
            else
                status := "PAST"

            ; Build long-form date for clarity
            try {
                ; Construct AHK timestamp: YYYYMMDD
                ahkDate := year . monthPad . dayPad
                longDate := FormatTime(ahkDate, "d MMMM yyyy")
            } catch {
                longDate := dateStr
            }

            ; Only add unique date entries
            isDuplicate := false
            for existing in results {
                if (existing.dateStr = dateStr) {
                    isDuplicate := true
                    break
                }
            }
            if (!isDuplicate)
                results.Push({dateStr: dateStr, longDate: longDate, status: status})

            startPos := m.Pos + m.Len
        }

        if (results.Length = 0)
            return ""

        ; Build verification block
        block := "[DATE VERIFICATION — computed by system, not the AI model]`n"
        block .= "Today's date: " . todayDisplay . "`n"
        for item in results {
            block .= "• " . item.dateStr . " (" . item.longDate . ") → " . item.status . "`n"
        }
        block .= "[END DATE VERIFICATION]"

        return block
    }

    ; Escape HTML special characters to prevent breaking HTML structure
    ; This handles ASCII special chars while preserving Unicode (em dashes, smart quotes, etc.)
    static EscapeHTML(str) {
        if (str = "")
            return ""

        ; Escape HTML entities in correct order
        ; & must be first to avoid double-escaping
        str := StrReplace(str, "&", "&amp;")   ; Ampersand
        str := StrReplace(str, "<", "&lt;")    ; Less than (critical for "lesion < 5mm")
        str := StrReplace(str, ">", "&gt;")    ; Greater than (critical for "grade > 2")
        str := StrReplace(str, '"', "&quot;")  ; Double quotes

        ; Note: We do NOT escape Unicode characters (—, •, ", etc.)
        ; These are handled by proper UTF-8 encoding

        return str
    }
}