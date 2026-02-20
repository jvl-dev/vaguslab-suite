; ==============================================
; Review GUI (WebView2)
; Displays review results in a WebView window
; with follow-up conversation and streaming support.
; ==============================================

class ReviewGui {
    static wvGui := ""
    static sessionId := ""
    static _pollTimer := 0
    static _streamFile := ""
    static _statusFile := ""
    static _streamPos := 0
    static _lastStreamActivity := 0
    static _streamMode := ""  ; "initial" for first review, "follow_up" for conversation

    ; Show a completed review HTML file in the WebView window
    static Show(htmlFile, sessionId := "") {
        ; Close existing window if open
        if (this.wvGui != "") {
            this._StopPolling()
            try this.wvGui.Destroy()
            this.wvGui := ""
        }

        this.sessionId := sessionId
        this._streamMode := ""

        ; Create WebView window
        this.wvGui := WebViewGui("+Resize", "Report Check - Review",, {})
        this.wvGui.OnEvent("Close", (*) => this._Close())

        ; Navigate to the HTML file
        htmlPath := "file:///" StrReplace(htmlFile, "\", "/") this._GetThemeParam()
        this.wvGui.Navigate(htmlPath)

        ; Register JS → AHK callbacks
        this._RegisterCallbacks()

        ; Match native title bar to app theme
        this._ApplyTitleBarTheme()

        ; Show window
        this.wvGui.Show("w" Constants.REVIEW_WINDOW_WIDTH " h" Constants.REVIEW_WINDOW_HEIGHT)
    }

    ; Show the streaming UI immediately, then poll for tokens
    ; Used for initial review — opens window instantly while API streams
    static ShowStreaming(streamFile, statusFile) {
        ; Close existing window if open
        if (this.wvGui != "") {
            this._StopPolling()
            try this.wvGui.Destroy()
            this.wvGui := ""
        }

        this.sessionId := ""
        this._streamMode := "initial"

        ; Create WebView window
        this.wvGui := WebViewGui("+Resize", "Report Check - Review",, {})
        this.wvGui.OnEvent("Close", (*) => this._Close())

        ; Navigate to the streaming template
        htmlPath := "file:///" StrReplace(A_ScriptDir "\templates\streaming_review.html", "\", "/") this._GetThemeParam()
        this.wvGui.Navigate(htmlPath)

        ; Register callbacks (persist across navigations)
        this._RegisterCallbacks()

        ; Match native title bar to app theme
        this._ApplyTitleBarTheme()

        ; Show window
        this.wvGui.Show("w" Constants.REVIEW_WINDOW_WIDTH " h" Constants.REVIEW_WINDOW_HEIGHT)

        ; Start polling the stream file
        this._streamFile := streamFile
        this._statusFile := statusFile
        this._streamPos := 0
        this._lastStreamActivity := A_TickCount

        pollFn := ObjBindMethod(this, "_PollStream")
        this._pollTimer := pollFn
        SetTimer(pollFn, Constants.STREAM_POLL_INTERVAL)
    }

    ; ==========================================
    ; Callback Registration
    ; ==========================================
    static _RegisterCallbacks() {
        this.wvGui.AddCallbackToScript("SendFollowUp", ObjBindMethod(this, "_OnSendFollowUp"))
        this.wvGui.AddCallbackToScript("CloseWindow", ObjBindMethod(this, "_Close"))
    }

    ; ==========================================
    ; Follow-up Handler
    ; ==========================================
    static _OnSendFollowUp(wv, userText) {
        if (this.sessionId = "" || Trim(userText) = "")
            return

        ; Disable input while processing
        this.wvGui.ExecuteScriptAsync("setFollowUpEnabled(false)")

        ; Prepare temp directory and files
        requestDir := A_Temp "\ReportCheck"
        if (!DirExist(requestDir))
            DirCreate(requestDir)

        requestFile := requestDir "\request.json"
        responseFile := requestDir "\response.json"
        tick := A_TickCount
        streamFile := requestDir "\stream_" tick ".txt"
        statusFile := requestDir "\stream_status_" tick ".json"
        try FileDelete(requestFile)
        try FileDelete(responseFile)
        try FileDelete(streamFile)
        try FileDelete(statusFile)

        configFile := ConfigManager.configFile

        ; Build request JSON
        request := '{"command":"stream_follow_up"'
                 . ',"session_id":"' . this.sessionId . '"'
                 . ',"user_message":"' . this._EscapeJSON(userText) . '"'
                 . ',"stream_file":"' . StrReplace(streamFile, "\", "\\") . '"'
                 . ',"status_file":"' . StrReplace(statusFile, "\", "\\") . '"'
                 . ',"config_path":"' . StrReplace(configFile, "\", "\\") . '"'
                 . '}'
        FileAppend(request, requestFile, "UTF-8-RAW")

        ; Show typing indicator in WebView
        this.wvGui.ExecuteScriptAsync("showTypingIndicator()")

        ; Launch Python non-blocking
        pythonPath := GetPythonPath()
        Run('"' . pythonPath . '" "' . A_ScriptDir . '\backend.py" "' . requestFile . '"',, "Hide")

        ; Start polling the stream file
        this._streamMode := "follow_up"
        this._streamFile := streamFile
        this._statusFile := statusFile
        this._streamPos := 0
        this._lastStreamActivity := A_TickCount

        pollFn := ObjBindMethod(this, "_PollStream")
        this._pollTimer := pollFn
        SetTimer(pollFn, Constants.STREAM_POLL_INTERVAL)
    }

    ; ==========================================
    ; Stream Polling
    ; ==========================================
    static _PollStream() {
        ; Safety: if window was closed, stop polling
        if (this.wvGui = "") {
            this._StopPolling()
            return
        }

        ; Check for status file (completion signal)
        if (FileExist(this._statusFile)) {
            try {
                ; Read any remaining content first
                this._ReadStreamChunks()

                ; Stop polling
                this._StopPolling()

                ; Read status
                statusJSON := FileRead(this._statusFile, "UTF-8")

                ; Check for error in status
                errorMsg := _ExtractJSONStringValue(statusJSON, "error")

                if (this._streamMode = "initial") {
                    ; Initial review mode: navigate to final HTML on success
                    this._HandleInitialComplete(statusJSON, errorMsg)
                } else {
                    ; Follow-up mode: finalize the streaming message
                    this._HandleFollowUpComplete(errorMsg)
                }

                ; Cleanup temp files
                try FileDelete(this._streamFile)
                try FileDelete(this._statusFile)
            } catch as err {
                Logger.Error("Error reading stream status", {error: err.Message})
                this._StopPolling()
                this.wvGui.ExecuteScriptAsync("streamError('Error reading response status')")
            }
            return
        }

        ; Check for timeout
        if (A_TickCount - this._lastStreamActivity > Constants.STREAM_TIMEOUT) {
            this._StopPolling()
            this.wvGui.ExecuteScriptAsync("streamError('Response timed out after " Constants.STREAM_TIMEOUT / 1000 " seconds')")
            try FileDelete(this._streamFile)
            try FileDelete(this._statusFile)
            return
        }

        ; Read new content from stream file
        this._ReadStreamChunks()
    }

    ; Handle completion of initial streaming review
    static _HandleInitialComplete(statusJSON, errorMsg) {
        if (errorMsg != "") {
            this.wvGui.ExecuteScriptAsync("streamError('" this._EscapeJS(errorMsg) "')")
            return
        }

        ; Extract html_file and session_id from status
        htmlFile := _ExtractJSONStringValue(statusJSON, "html_file")
        newSessionId := _ExtractJSONStringValue(statusJSON, "session_id")

        if (htmlFile = "" || !FileExist(htmlFile)) {
            this.wvGui.ExecuteScriptAsync("streamError('Review completed but HTML file not found')")
            return
        }

        ; Tell the streaming page we're done (removes cursor)
        this.wvGui.ExecuteScriptAsync("streamComplete()")

        ; Update session ID
        this.sessionId := newSessionId
        this._streamMode := ""

        Logger.Info("Streaming review complete — navigating to final HTML", {
            session_id: newSessionId, html_file: htmlFile
        })

        ; Navigate to the final review HTML (with follow-up section, targeted review, etc.)
        htmlPath := "file:///" StrReplace(htmlFile, "\", "/") this._GetThemeParam()
        this.wvGui.Navigate(htmlPath)

        ; Re-register callbacks after navigation (in case host objects don't persist)
        this._RegisterCallbacks()
    }

    ; Handle completion of a follow-up stream
    static _HandleFollowUpComplete(errorMsg) {
        if (errorMsg != "") {
            this.wvGui.ExecuteScriptAsync("streamError('" this._EscapeJS(errorMsg) "')")
        } else {
            this.wvGui.ExecuteScriptAsync("streamComplete()")
        }
    }

    static _ReadStreamChunks() {
        if (!FileExist(this._streamFile))
            return

        try {
            content := FileRead(this._streamFile, "UTF-8")
            contentLen := StrLen(content)
            if (contentLen > this._streamPos) {
                newContent := SubStr(content, this._streamPos + 1)
                this._streamPos := contentLen
                this._lastStreamActivity := A_TickCount

                ; Push new content to WebView
                this.wvGui.ExecuteScriptAsync("appendStreamChunk('" this._EscapeJS(newContent) "')")
            }
        } catch {
            ; File may be locked by Python — will retry next poll
        }
    }

    static _StopPolling() {
        if (this._pollTimer) {
            SetTimer(this._pollTimer, 0)
            this._pollTimer := 0
        }
    }

    ; ==========================================
    ; Window Close
    ; ==========================================
    static _Close(wv := "") {
        this._StopPolling()
        if (this.wvGui != "") {
            try this.wvGui.Destroy()
            this.wvGui := ""
        }
        this.sessionId := ""
        this._streamMode := ""
    }

    ; ==========================================
    ; Helpers
    ; ==========================================
    static _EscapeJSON(text) {
        text := StrReplace(text, "\", "\\")
        text := StrReplace(text, '"', '\"')
        text := StrReplace(text, "`n", "\n")
        text := StrReplace(text, "`r", "\r")
        text := StrReplace(text, "`t", "\t")
        return text
    }

    static _GetThemeParam() {
        isDark := ConfigManager.config["Settings"].Get("dark_mode_enabled", true)
        sharedDir := "file:///" StrReplace(A_ScriptDir "\..\shared\gui", "\", "/")
        return "?theme=" (isDark ? "dark" : "light") "&shared=" sharedDir
    }

    ; Set native Windows title bar to dark/light to match app theme
    static _ApplyTitleBarTheme() {
        if (!this.wvGui || !this.wvGui.Hwnd)
            return
        isDark := ConfigManager.config["Settings"].Get("dark_mode_enabled", true)
        ; DWMWA_USE_IMMERSIVE_DARK_MODE = 20
        DllCall("Dwmapi.dll\DwmSetWindowAttribute"
            , "Ptr", this.wvGui.Hwnd
            , "UInt", 20
            , "Ptr*", isDark ? 1 : 0
            , "UInt", 4)
    }

    static _EscapeJS(str) {
        str := StrReplace(str, "\", "\\")
        str := StrReplace(str, "'", "\'")
        str := StrReplace(str, '"', '\"')
        str := StrReplace(str, "``", "\``")
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        return str
    }
}
