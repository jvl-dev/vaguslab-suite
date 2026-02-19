; ==============================================
; Result Helper - Standardized Error Handling
; ==============================================
; Provides consistent result object pattern for all operations
; Usage:
;   result := ResultHelper.Success({data: value})
;   result := ResultHelper.Error("Error message", {context: "details"})
;   if (result.success) { ... }

class ResultHelper {
    ; Create a successful result object
    ; data: optional data to include in result
    static Success(data := "") {
        result := {success: true}

        ; Merge data properties into result if provided
        if (IsObject(data)) {
            for key, value in data.OwnProps() {
                result.%key% := value
            }
        }

        return result
    }

    ; Create an error result object
    ; errorMessage: human-readable error description
    ; data: optional additional context (error codes, details, etc.)
    static Error(errorMessage, data := "") {
        result := {
            success: false,
            error: errorMessage
        }

        ; Merge additional data if provided
        if (IsObject(data)) {
            for key, value in data.OwnProps() {
                result.%key% := value
            }
        }

        return result
    }

    ; Create error from exception
    ; err: AHK error object
    ; context: optional description of what was being attempted
    static FromException(err, context := "") {
        errorMsg := context != ""
            ? context . ": " . err.Message
            : err.Message

        return this.Error(errorMsg, {
            exceptionType: Type(err),
            exceptionMessage: err.Message,
            what: err.What,
            extra: err.Extra
        })
    }

    ; Check if result indicates success
    ; result: result object to check
    static IsSuccess(result) {
        return IsObject(result) && result.HasProp("success") && result.success
    }

    ; Check if result indicates error
    ; result: result object to check
    static IsError(result) {
        return IsObject(result) && result.HasProp("success") && !result.success
    }

    ; Get error message from result, or empty string if success
    ; result: result object
    static GetError(result) {
        if (this.IsError(result) && result.HasProp("error")) {
            return result.error
        }
        return ""
    }

    ; Convert legacy return values to result objects
    ; Handles: true/false, error strings, or existing result objects
    static Normalize(value) {
        ; Already a result object
        if (IsObject(value) && value.HasProp("success")) {
            return value
        }

        ; Boolean true = success
        if (value = true) {
            return this.Success()
        }

        ; Boolean false = error without message
        if (value = false) {
            return this.Error("Operation failed")
        }

        ; String = error message
        if (Type(value) = "String" && value != "") {
            return this.Error(value)
        }

        ; Empty string or 0 = error
        if (value = "" || value = 0) {
            return this.Error("Operation failed")
        }

        ; Any other value = success with data
        return this.Success({value: value})
    }
}
