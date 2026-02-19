; ==============================================
; Prompt Cache Manager
; ==============================================
; Caches system prompts in memory to avoid disk I/O on every review
; Validates prompt content and provides fallback mechanisms
;
; Benefits:
; - No disk I/O during reviews (performance improvement)
; - Validates prompts at startup (catches issues early)
; - Centralized prompt management
; - Fallback to safe defaults if files missing

class PromptCache {
    ; Minimum acceptable prompt length (characters)
    static MIN_PROMPT_LENGTH := 50

    ; Prompt types we support
    static PROMPT_TYPES := ["comprehensive", "proofreading"]

    ; Fallback prompt if files are missing or invalid
    static FALLBACK_PROMPT := "You are a radiology report checking assistant. Review the provided radiology report and provide constructive, professional feedback. Focus on clinical accuracy, clarity, completeness, and adherence to standard reporting conventions."

    ; Initialize the prompt cache - load all prompts from disk
    ; Should be called once at application startup
    ; Returns: {success: bool, errors: Array}
    static Initialize(configDir) {
        Logger.Info("Initializing prompt cache from: " . configDir)

        errors := []
        loadedCount := 0

        try {
            ; Clear any existing cache
            PromptCacheState.cache := Map()

            ; Load each prompt type
            for index, promptType in this.PROMPT_TYPES {
                result := this._LoadPromptFile(configDir, promptType)

                if (result.success) {
                    ; Cache the validated prompt
                    PromptCacheState.cache[promptType] := result.content
                    loadedCount += 1
                    Logger.Info("Prompt cached successfully: " . promptType . " (" . StrLen(result.content) . " characters)")
                } else {
                    ; Store fallback and track error
                    PromptCacheState.cache[promptType] := this.FALLBACK_PROMPT
                    errors.Push(result.error)
                    Logger.Warning("Prompt load failed for " . promptType . ", using fallback: " . result.error)
                }
            }

            ; Mark as initialized
            PromptCacheState.isInitialized := true

            ; Log summary
            if (errors.Length = 0) {
                Logger.Info("Prompt cache initialized successfully: " . loadedCount . " of " . this.PROMPT_TYPES.Length . " prompts loaded")
                return {success: true, errors: errors}
            } else {
                Logger.Warning("Prompt cache initialized with errors: " . loadedCount . " loaded, " . errors.Length . " failed out of " . this.PROMPT_TYPES.Length . " total")

                ; Show warning to user if any prompts failed
                errorMsg := "Warning: Some prompt files could not be loaded:`n`n"
                for index, err in errors {
                    errorMsg .= "• " . err . "`n"
                }
                errorMsg .= "`nFallback prompts will be used. Application will still function, but prompts may be basic."

                MsgBox(errorMsg, "Prompt Loading Warning", 48)

                return {success: false, errors: errors}
            }

        } catch as err {
            Logger.Error("Fatal error initializing prompt cache: " . err.Message . " (at " . err.What . ")")

            ; Emergency fallback - cache basic prompts for all types
            for index, promptType in this.PROMPT_TYPES {
                PromptCacheState.cache[promptType] := this.FALLBACK_PROMPT
            }

            PromptCacheState.isInitialized := true

            MsgBox("Error: Could not initialize prompt cache: " . err.Message . "`n`n" .
                   "Basic fallback prompts will be used.",
                   "Prompt Cache Error", 16)

            return {success: false, errors: [err.Message]}
        }
    }

    ; Load a single prompt file from disk with validation
    ; Returns: {success: bool, content: string, error: string}
    static _LoadPromptFile(configDir, promptType) {
        promptFile := A_ScriptDir "\prompts\system_prompt_" . promptType . ".txt"

        if (!FileExist(promptFile)) {
            return {
                success: false,
                content: "",
                error: promptType . " prompt not found: " . promptFile
            }
        }

        try {
            ; Read file with explicit UTF-8 encoding
            content := FileRead(promptFile, "UTF-8")

            ; Strip UTF-8 BOM if present (EF BB BF bytes)
            ; In AHK v2, BOM might appear as special characters at start
            if (SubStr(content, 1, 1) = Chr(0xFEFF)) {
                content := SubStr(content, 2)
            }

            ; Validate the content
            validationResult := this._ValidatePrompt(content, promptType)

            if (validationResult.valid) {
                return {
                    success: true,
                    content: content,
                    error: ""
                }
            } else {
                return {
                    success: false,
                    content: "",
                    error: promptType . " prompt validation failed: " . validationResult.error
                }
            }

        } catch as err {
            return {
                success: false,
                content: "",
                error: promptType . " prompt read error: " . err.Message
            }
        }
    }

    ; Validate prompt content
    ; Returns: {valid: bool, error: string}
    static _ValidatePrompt(content, promptType) {
        ; Check if content is empty or whitespace only
        trimmedContent := Trim(content)
        if (trimmedContent = "") {
            return {
                valid: false,
                error: "Prompt is empty or contains only whitespace"
            }
        }

        ; Check minimum length
        if (StrLen(trimmedContent) < this.MIN_PROMPT_LENGTH) {
            return {
                valid: false,
                error: "Prompt too short (minimum " . this.MIN_PROMPT_LENGTH . " characters, got " . StrLen(trimmedContent) . ")"
            }
        }

        ; All checks passed
        return {valid: true, error: ""}
    }

    ; Get a prompt from the cache with dynamic date injection
    ; If modeOverride is provided, use that mode instead
    ; Returns: prompt string (never returns empty - uses fallback if needed)
    static GetPrompt(modeOverride := "") {
        ; Determine which prompt type to retrieve
        promptType := "comprehensive"

        if (modeOverride != "" && (modeOverride = "comprehensive" || modeOverride = "proofreading")) {
            promptType := modeOverride
        } else if (ConfigManager.config.Has("Settings") && ConfigManager.config["Settings"].Has("prompt_type")) {
            promptType := ConfigManager.config["Settings"]["prompt_type"]
        }

        ; Check if cache is initialized
        if (!PromptCacheState.isInitialized) {
            Logger.Warning("Prompt cache not initialized, using fallback prompt")
            return this.FALLBACK_PROMPT
        }

        ; Retrieve from cache
        prompt := ""
        if (PromptCacheState.cache.Has(promptType)) {
            Logger.Debug("Prompt retrieved from cache: " . promptType)
            prompt := PromptCacheState.cache[promptType]
        } else {
            ; Should never happen if Initialize() ran, but be defensive
            Logger.Warning("Prompt type not in cache, using fallback: " . promptType)
            prompt := this.FALLBACK_PROMPT
        }

        ; Inject current date dynamically
        prompt := this._InjectCurrentDate(prompt)

        return prompt
    }

    ; Inject current date into the system prompt
    ; Replaces placeholder variables with actual current date values
    ; Returns: modified prompt string
    static _InjectCurrentDate(prompt) {
        ; Get current date in DD/MM/YYYY format (e.g., "9/11/2025")
        currentDate := FormatTime(A_Now, "d/M/yyyy")

        ; Get current date in long format (e.g., "9 November 2025")
        currentDateLong := FormatTime(A_Now, "d MMMM yyyy")

        ; Get current year (e.g., "2025")
        currentYear := FormatTime(A_Now, "yyyy")

        ; Get previous year (e.g., "2024")
        previousYear := currentYear - 1

        ; Replace placeholder variables with actual values
        ; {{CURRENT_DATE}} → "9/11/2025 (9 November 2025)"
        prompt := StrReplace(prompt, "{{CURRENT_DATE}}",
                            currentDate . " (" . currentDateLong . ")")

        ; {{CURRENT_YEAR}} → "2025"
        prompt := StrReplace(prompt, "{{CURRENT_YEAR}}", currentYear)

        ; {{PREVIOUS_YEAR}} → "2024"
        prompt := StrReplace(prompt, "{{PREVIOUS_YEAR}}", previousYear)

        Logger.Debug("Date variables injected into prompt: " . currentDate . " (" . currentDateLong . "), year: " . currentYear)

        return prompt
    }

    ; Reload all prompts from disk (useful for development or if files change)
    ; Returns: {success: bool, errors: Array}
    static Reload(configDir) {
        Logger.Info("Reloading prompt cache from disk")
        PromptCacheState.isInitialized := false
        return this.Initialize(configDir)
    }

    ; Check if cache is initialized and ready
    static IsInitialized() {
        return PromptCacheState.isInitialized
    }

    ; Get cache statistics for debugging
    static GetStats() {
        stats := {
            initialized: PromptCacheState.isInitialized,
            cached_prompts: PromptCacheState.cache.Count,
            prompt_types: []
        }

        for promptType, content in PromptCacheState.cache {
            stats.prompt_types.Push({
                type: promptType,
                length: StrLen(content),
                preview: SubStr(content, 1, 50) . "..."
            })
        }

        return stats
    }
}

; Separate global state holder (AHK v2 pattern for mutable state)
class PromptCacheState {
    ; Cache storage - Maps prompt type to content
    static cache := Map()

    ; Flag to track if cache has been initialized
    static isInitialized := false
}
