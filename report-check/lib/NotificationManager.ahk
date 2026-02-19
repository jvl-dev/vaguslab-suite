; ==============================================
; Notification Helper Functions
; ==============================================

; Class-based notification manager to avoid race conditions
class NotificationManager {
    static currentTimer := ""
    static timerLock := false
    static timerID := 0

    ; Unified notification system using TrayTip
    static Show(title, message, type := "info", duration := 3000) {
        ; Atomic cleanup of existing timer
        ; Using a lock pattern to prevent race conditions
        if (this.timerLock) {
            ; Another notification is being set up, wait briefly
            Sleep(10)
        }

        this.timerLock := true

        try {
            ; Cancel any existing notification timer
            if (this.currentTimer != "") {
                try {
                    SetTimer(this.currentTimer, 0)  ; Disable timer
                } catch {
                    ; Timer may already be deleted, ignore
                }
            }

            ; Increment timer ID to invalidate old timer references
            this.timerID += 1
            currentID := this.timerID

            ; Clear any existing notification first
            TrayTip()

            ; Show the notification (clean, no icon, silent)
            TrayTip(title, message, "Mute")

            ; Create timer function with ID check to prevent stale timer execution
            timerFunc := () => this._ClearWithIDCheck(currentID)
            SetTimer(timerFunc, -duration)
            this.currentTimer := timerFunc

        } finally {
            ; Always release lock
            this.timerLock := false
        }
    }

    ; Helper function to clear notification with ID check
    static _ClearWithIDCheck(expectedID) {
        ; Only clear if this is still the current timer
        if (this.timerID = expectedID) {
            TrayTip()

            ; Clean up timer reference
            if (this.currentTimer != "") {
                try {
                    SetTimer(this.currentTimer, 0)  ; Ensure timer is disabled
                }
                this.currentTimer := ""
            }
        }
        ; If IDs don't match, this is a stale timer - do nothing
    }
}

; Legacy global function for backward compatibility
ShowNotification(title, message, type := "info", duration := 3000) {
    NotificationManager.Show(title, message, type, duration)
}

; Quick notification shortcuts
NotifyInfo(title, message, duration := "") {
    if (duration = "")
        duration := Constants.NOTIFICATION_DURATION
    ShowNotification(title, message, "info", duration)
}

NotifySuccess(title, message, duration := "") {
    if (duration = "")
        duration := Constants.NOTIFICATION_DURATION
    ShowNotification(title, message, "success", duration)
}

NotifyWarning(title, message, duration := "") {
    if (duration = "")
        duration := Constants.NOTIFICATION_DURATION_WARNING
    ShowNotification(title, message, "warning", duration)
}

NotifyError(title, message, duration := "") {
    if (duration = "")
        duration := Constants.NOTIFICATION_DURATION_ERROR
    ShowNotification(title, message, "error", duration)
}