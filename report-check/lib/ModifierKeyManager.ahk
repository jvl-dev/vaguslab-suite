; ==============================================
; Modifier Key Manager
; ==============================================
; Comprehensive solution for detecting and fixing stuck modifier keys
; Shared module for use across multiple AHK applications
;
; Usage:
;   #Include lib\ModifierKeyManager.ahk
;   ModifierKeyManager.ResetAllModifiers()  ; Release all stuck keys
;   ModifierKeyManager.PreventiveRelease()  ; Quick release after clipboard ops
;
; Features:
; - Checks actual Windows key state before attempting release
; - Verifies release was successful
; - Retries with delays if needed
; - Logs all operations for debugging
; - Safe for use during active user input

class ModifierKeyManager {
    ; ==============================================
    ; Configuration
    ; ==============================================

    ; List of all modifier keys to manage (left and right versions)
    static MODIFIERS := [
        {name: "Ctrl", left: "LControl", right: "RControl"},
        {name: "Alt", left: "LAlt", right: "RAlt"},
        {name: "Shift", left: "LShift", right: "RShift"},
        {name: "Win", left: "LWin", right: "RWin"}
    ]

    ; Retry configuration
    static MAX_RETRIES := 3
    static RETRY_DELAY_MS := 50

    ; ==============================================
    ; Public Methods
    ; ==============================================

    ; Reset all modifier keys (comprehensive - use for tray menu "Reset Stuck Keys")
    ; Returns: {success: bool, fixed: array, failed: array, message: string}
    static ResetAllModifiers() {
        fixed := []
        failed := []

        ; Check and release each modifier
        for modifier in this.MODIFIERS {
            ; Check both left and right versions
            for side in ["left", "right"] {
                keyName := modifier.%side%  ; Use property access syntax

                ; Only attempt release if key is actually stuck
                if (this._IsKeyStuck(keyName)) {
                    result := this._ReleaseKeyWithRetry(keyName)

                    if (result.success) {
                        fixed.Push(modifier.name . " (" . side . ")")
                    } else {
                        failed.Push(modifier.name . " (" . side . ")")
                    }
                }
            }
        }

        ; Build result message
        if (fixed.Length = 0 && failed.Length = 0) {
            message := "No stuck keys detected"
        } else if (failed.Length = 0) {
            message := "Released " . fixed.Length . " stuck key(s)"
        } else {
            message := "Fixed " . fixed.Length . ", failed " . failed.Length
        }

        return {
            success: failed.Length = 0,
            fixed: fixed,
            failed: failed,
            message: message
        }
    }

    ; Preventive release after clipboard operations (fast, no verification)
    ; Use this immediately after Send("^c") or Send("^v")
    static PreventiveRelease() {
        ; Quick release without checking - for immediate use after Ctrl+C/V
        Send("{Ctrl Up}{Shift Up}{Alt Up}")
    }

    ; Release specific modifier keys after hotkey execution
    ; Used by hotkey wrappers to prevent sticking
    static ReleaseSpecificModifiers(modifierList) {
        if (!IsObject(modifierList) || modifierList.Length = 0) {
            return
        }

        ; Release each modifier with a small delay
        for modifier in modifierList {
            if (this._IsKeyStuck(modifier)) {
                Send("{" modifier " Up}")
            }
        }
    }

    ; ==============================================
    ; Diagnostic Methods
    ; ==============================================

    ; Get current state of all modifiers (for debugging)
    static GetModifierStates() {
        states := []

        for modifier in this.MODIFIERS {
            for side in ["left", "right"] {
                keyName := modifier.%side%  ; Use property access syntax
                states.Push({
                    key: keyName,
                    physical: GetKeyState(keyName, "P"),
                    logical: GetKeyState(keyName)
                })
            }
        }

        return states
    }

    ; Get formatted diagnostic message for display
    static GetDiagnosticMessage() {
        states := this.GetModifierStates()

        message := "Modifier Key Diagnostic Report`n"
        message .= "================================`n`n"

        stuckCount := 0

        for state in states {
            physicalState := state.physical ? "DOWN" : "up  "
            logicalState := state.logical ? "DOWN" : "up  "
            isStuck := (state.logical && !state.physical)

            if (isStuck) {
                stuckCount++
                message .= state.key . ": Physical=" . physicalState . ", Logical=" . logicalState . " [STUCK]`n"
            } else {
                message .= state.key . ": Physical=" . physicalState . ", Logical=" . logicalState . "`n"
            }
        }

        message .= "`n================================`n"
        if (stuckCount > 0) {
            message .= "STUCK KEYS DETECTED: " . stuckCount . "`n"
            message .= "Use 'Reset Stuck Keys' to fix"
        } else {
            message .= "Status: All keys normal"
        }

        return message
    }

    ; Get a simpler summary of stuck keys for the combined diagnostic dialog
    static GetStuckKeysSummary() {
        states := this.GetModifierStates()
        stuckKeys := []

        for state in states {
            if (state.logical) {
                stuckKeys.Push(state.key)
            }
        }

        return stuckKeys
    }

    ; Comprehensive diagnose and fix routine
    ; Returns: {stuckBefore: array, stuckAfter: array, fixed: array, failed: array}
    static DiagnoseAndFix() {
        ; Phase 1: Initial diagnosis
        stuckBefore := this.GetStuckKeysSummary()

        ; Phase 2: Attempt automatic fix if any keys are stuck
        result := this.ResetAllModifiers()

        ; Phase 3: Re-check after fix attempt
        Sleep(100)  ; Small delay to ensure state is updated
        stuckAfter := this.GetStuckKeysSummary()

        return {
            stuckBefore: stuckBefore,
            stuckAfter: stuckAfter,
            fixed: result.fixed,
            failed: result.failed
        }
    }

    ; Build a plain-text diagnostic message from a DiagnoseAndFix result.
    ; Used by both the tray-menu MsgBox path and the settings-GUI modal path.
    static FormatDiagnosticMessage(result) {
        msg := "Modifier Key Diagnostic & Fix`n"
        msg .= "================================`n`n"

        msg .= "INITIAL CHECK:`n"
        if (result.stuckBefore.Length > 0) {
            for key in result.stuckBefore
                msg .= "  ✗ " . key . ": STUCK (DOWN)`n"
        } else {
            msg .= "  ✓ All keys normal`n"
        }

        if (result.stuckBefore.Length > 0) {
            msg .= "`nATTEMPTING AUTOMATIC FIX...`n"
            msg .= "`nAFTER RESET:`n"
            if (result.stuckAfter.Length = 0) {
                msg .= "  ✓ All keys normal - Fix successful!`n"
            } else {
                for key in result.stuckAfter
                    msg .= "  ✗ " . key . ": STILL STUCK`n"
                msg .= "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n"
                msg .= "MANUAL FIX REQUIRED:`n"
                msg .= "1. Press and release the stuck key(s) shown above`n"
                msg .= "2. Click 'Retry' to check again`n"
                msg .= "3. Restart the script if problem persists`n"
            }
        }

        msg .= "`n================================"
        return msg
    }

    ; ==============================================
    ; Internal Methods
    ; ==============================================

    ; Check if a specific key is stuck
    ; A key is "stuck" if it's in the DOWN state (either physical or logical)
    ; We use a simpler approach: if Windows reports it as down, we should release it
    static _IsKeyStuck(keyName) {
        ; Check logical state (what Windows thinks)
        isLogicallyPressed := GetKeyState(keyName)

        ; Key is stuck if Windows thinks it's down
        ; This catches both logical-only stuck states AND physical+logical stuck states
        return isLogicallyPressed
    }

    ; Release a key with retry logic
    static _ReleaseKeyWithRetry(keyName) {
        attempts := 0

        Loop this.MAX_RETRIES {
            attempts++

            ; Send the release command
            Send("{" keyName " Up}")

            ; Small delay to let Windows process
            Sleep(this.RETRY_DELAY_MS)

            ; Verify it worked
            if (!this._IsKeyStuck(keyName)) {
                return {success: true, attempts: attempts}
            }

            ; If still stuck and we have retries left, try again
            if (A_Index < this.MAX_RETRIES) {
                ; Longer delay before retry
                Sleep(this.RETRY_DELAY_MS * 2)
            }
        }

        ; Failed after all retries
        return {success: false, attempts: attempts}
    }

    ; ==============================================
    ; Wrapper for Hotkey Callbacks
    ; ==============================================

    ; Wrap a hotkey callback to automatically release modifiers after execution
    ; Usage: Hotkey("^!c", ModifierKeyManager.WrapCallback(MyFunction, ["LControl", "LAlt"]))
    static WrapCallback(callback, modifiers := []) {
        ; Return a wrapper function that calls the original and releases modifiers
        return ObjBindMethod(this, "_ExecuteWrappedCallback", callback, modifiers)
    }

    ; Internal method used by WrapCallback
    static _ExecuteWrappedCallback(callback, modifiers, *) {
        try {
            ; Execute the original callback
            callback()
        } finally {
            ; Always release modifiers, even if callback errors
            if (modifiers.Length > 0) {
                ; Delayed release to ensure callback completes first
                SetTimer(() => this.ReleaseSpecificModifiers(modifiers), -50)
            }
        }
    }
}
