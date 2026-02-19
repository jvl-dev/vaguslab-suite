; ==============================================
; API Rate Limiter
; ==============================================
; Prevents rapid-fire API calls that could:
; - Trigger rate limits from providers
; - Rack up unexpected costs
; - Get API key throttled or banned
; - Cause multiple simultaneous API calls

class APIRateLimiter {
    ; Get minimum interval from Constants
    static GetMinInterval() {
        return Constants.API_RATE_LIMIT_MS
    }

    ; Check if an API call can be made now
    ; Returns: bool (true = allowed, false = blocked)
    static CanMakeCall() {
        ; FIRST: Block if a call is currently in progress
        if (APIRateLimiterState.isCallInProgress) {
            Logger.Warning("API call blocked - review already in progress")
            NotifyWarning("Review In Progress", "Please wait for current review to complete")
            return false
        }

        ; SECOND: Check minimum time between calls
        now := A_TickCount
        elapsed := now - APIRateLimiterState.lastCallTime
        minInterval := this.GetMinInterval()

        ; First call ever - always allow
        if (APIRateLimiterState.lastCallTime = 0) {
            Logger.Info("Rate limiter: First API call allowed")
            return true
        }

        ; Check if enough time has passed since last call
        if (elapsed < minInterval) {
            remaining := minInterval - elapsed
            remainingSec := Round(remaining / 1000, 1)

            Logger.Warning("API call blocked by rate limit", {
                elapsed_ms: elapsed,
                required_ms: minInterval,
                remaining_ms: remaining
            })

            NotifyWarning("Rate Limit",
                "Please wait " . remainingSec . " seconds between reviews")

            return false
        }

        ; Both checks passed - allow call
        Logger.Info("Rate limiter: API call allowed", {elapsed_ms: elapsed})
        return true
    }

    ; Mark that an API call has started
    static StartCall() {
        APIRateLimiterState.isCallInProgress := true
        Logger.Info("Rate limiter: API call started")
    }

    ; Mark that an API call has ended
    static EndCall() {
        APIRateLimiterState.isCallInProgress := false
        APIRateLimiterState.lastCallTime := A_TickCount
        Logger.Info("Rate limiter: API call ended")
    }

    ; Reset the rate limiter (useful for testing or error recovery)
    static Reset() {
        APIRateLimiterState.isCallInProgress := false
        APIRateLimiterState.lastCallTime := 0
        Logger.Info("Rate limiter reset")
    }

    ; Get time remaining until next call is allowed (in milliseconds)
    ; Returns: int (0 if call can be made now, otherwise ms remaining)
    static GetTimeRemaining() {
        ; If call in progress, return a large number
        if (APIRateLimiterState.isCallInProgress) {
            return 999999
        }

        if (APIRateLimiterState.lastCallTime = 0) {
            return 0
        }

        now := A_TickCount
        elapsed := now - APIRateLimiterState.lastCallTime
        minInterval := this.GetMinInterval()

        if (elapsed >= minInterval) {
            return 0
        }

        return minInterval - elapsed
    }

    ; Get the minimum interval in seconds (for display purposes)
    static GetMinIntervalSeconds() {
        return this.GetMinInterval() / 1000
    }

    ; Check if a call is currently in progress
    static IsCallInProgress() {
        return APIRateLimiterState.isCallInProgress
    }
}

; Separate global state holder (AHK v2 pattern for mutable state)
class APIRateLimiterState {
    static isCallInProgress := false
    static lastCallTime := 0
}
