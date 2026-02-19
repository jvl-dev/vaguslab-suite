; ==============================================
; Integrity Check GUI (WebViewToo)
; Themed dialog replacing native MsgBox for
; integrity check results.
; ==============================================

class IntegrityCheckGui {
    static wvGui := ""
    static _pendingJs := ""

    ; Create and show the dialog window (shows spinner by default)
    static Show() {
        if (this.wvGui != "") {
            try {
                this.wvGui.Show()
                return
            }
        }

        this._pendingJs := ""
        this.wvGui := WebViewGui("+Resize -Caption",,, {})
        this.wvGui.OnEvent("Close", (*) => this._Close())

        isDark := ConfigManager.config.Has("Settings") && ConfigManager.config["Settings"].Has("dark_mode_enabled")
            ? !!ConfigManager.config["Settings"]["dark_mode_enabled"] : true
        htmlPath := "file:///" StrReplace(A_ScriptDir "\lib\gui\integrity-check.html", "\", "/") "?theme=" (isDark ? "dark" : "light")
        this.wvGui.Navigate(htmlPath)

        this.wvGui.AddCallbackToScript("CloseWindow", ObjBindMethod(this, "_Close"))

        this.wvGui.Show("w420 h300")
    }

    ; Show "not available in compiled mode"
    static ShowNotAvailable() {
        this._ShowWithResult("showNotAvailable()")
    }

    ; Show error message
    static ShowError(message) {
        this._ShowWithResult("showError('" this._EscapeJS(message) "')")
    }

    ; Show development version info
    static ShowDev(message) {
        this._ShowWithResult("showDev('" this._EscapeJS(message) "')")
    }

    ; Show passed result
    static ShowPassed(verifiedCount, version) {
        this._ShowWithResult("showPassed(" verifiedCount ", '" this._EscapeJS(version) "')")
    }

    ; Show failed result with file list
    static ShowFailed(failedCount, version, failedFiles) {
        ; Build JS array of failed files
        jsArr := "["
        for i, failInfo in failedFiles {
            if (i > 1)
                jsArr .= ","
            jsArr .= "{file:'" this._EscapeJS(failInfo.file) "',reason:'" this._EscapeJS(failInfo.reason) "'}"
        }
        jsArr .= "]"
        this._ShowWithResult("showFailed(" failedCount ", '" this._EscapeJS(version) "', " jsArr ")")
    }

    ; Ensure window is open, then execute JS after page load delay
    static _ShowWithResult(js) {
        this.Show()
        ; Delay to ensure HTML page has loaded before executing JS
        this._pendingJs := js
        SetTimer(ObjBindMethod(this, "_ExecPending"), -500)
    }

    ; Execute pending JS after page load
    static _ExecPending() {
        if (this._pendingJs != "" && this.wvGui != "") {
            try this.wvGui.ExecuteScriptAsync(this._pendingJs)
            this._pendingJs := ""
        }
    }

    static _Close(wv := "") {
        try this.wvGui.Destroy()
        this.wvGui := ""
        this._pendingJs := ""
    }

    static _EscapeJS(str) {
        str := StrReplace(str, "\", "\\")
        str := StrReplace(str, "'", "\'")
        str := StrReplace(str, "``", "\``")
        str := StrReplace(str, "`n", "\n")
        str := StrReplace(str, "`r", "\r")
        str := StrReplace(str, "`t", "\t")
        return str
    }
}
