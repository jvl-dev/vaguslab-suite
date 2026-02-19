; ==============================================
; Version Management Class
; ==============================================
class VersionManager {
    ; API Configuration
    static API_URL := "https://ahk-updates.vaguslab.org"
    static API_KEY := "87f828d97c2101b4a83219312e2741e108aa101412bbbe8771edbcc0384f4520"
    static APP_NAME := "report-check"

    ; Compare two version strings (wrapper for SharedUtils implementation)
    ; Returns: 1 if version1 > version2, -1 if version1 < version2, 0 if equal
    static CompareVersions(version1, version2) {
        return SharedUtils.CompareVersions(version1, version2)
    }
    
    ; Extract version from the script file content
    static ExtractVersionFromFile(filepath) {
        try {
            ; Read the first few lines of the file (version should be near the top)
            fileContent := FileRead(filepath, "UTF-8")
            
            ; Look for version patterns in the file content
            patterns := [
                'global\s+VERSION\s*:=\s*"([^"]+)"',     ; global VERSION := "0.2.0"
                "global\s+VERSION\s*:=\s*'([^']+)'",     ; global VERSION := '0.2.0'
                'VERSION\s*:=\s*"([^"]+)"',              ; VERSION := "0.2.0"
                "VERSION\s*:=\s*'([^']+)'",              ; VERSION := '0.2.0'
                '; Version\s*[:\-]\s*([0-9.]+)',         ; ; Version: 0.2.0
                '; Version\s+([0-9.]+)',                 ; ; Version 0.2.0
                'static\s+VERSION\s*:=\s*"([^"]+)"'      ; static VERSION := "0.2.0"
            ]
            
            for pattern in patterns {
                if (RegExMatch(fileContent, "i)" pattern, &match)) {
                    return match[1]
                }
            }
            
            return ""
            
        } catch as err {
            return ""
        }
    }
    
    ; Find newer versions in downloads folder
    static FindNewerVersions(currentVersion) {
        downloadsFolder := EnvGet("USERPROFILE") "\Downloads"  ; Primary Downloads folder
        if (!DirExist(downloadsFolder)) {
            ; Try alternative path
            downloadsFolder := A_MyDocuments "\..\Downloads"
        }
        
        if (!DirExist(downloadsFolder)) {
            return []
        }
        
        newerFiles := []
        
        ; Search for files matching our naming pattern
        searchPatterns := [
            "report check*.ahk",
            "report-check*.ahk", 
            "reportcheck*.ahk",
            "*report*check*.ahk"
        ]
        
        for pattern in searchPatterns {
            Loop Files, downloadsFolder "\" pattern {
                ; Skip if this is the same file as currently running
                if (A_LoopFileFullPath = A_ScriptFullPath) {
                    continue
                }
                
                foundVersion := this.ExtractVersionFromFile(A_LoopFileFullPath)
                if (foundVersion != "" && this.CompareVersions(foundVersion, currentVersion) > 0) {
                    newerFiles.Push({
                        filename: A_LoopFileName,
                        fullPath: A_LoopFileFullPath,
                        version: foundVersion,
                        modified: A_LoopFileTimeModified
                    })
                }
            }
        }
        
        ; Sort by version (newest first) - Fixed sorting method
        if (newerFiles.Length > 1) {
            ; Create a simple bubble sort since AHK v2 array sorting can be problematic
            Loop newerFiles.Length - 1 {
                i := A_Index
                Loop newerFiles.Length - i {
                    j := A_Index + i
                    if (this.CompareVersions(newerFiles[i].version, newerFiles[j].version) < 0) {
                        ; Swap elements
                        temp := newerFiles[i]
                        newerFiles[i] := newerFiles[j]
                        newerFiles[j] := temp
                    }
                }
            }
        }
        
        return newerFiles
    }
    
    ; Perform the update (LEGACY - kept for backward compatibility)
    ; New code should use PerformCompleteUpdate() instead
    static PerformUpdate(sourceFile, targetDir) {
        try {
            ; Ensure target directory exists
            if (!DirExist(targetDir)) {
                DirCreate(targetDir)
            }

            ; Create backup of current file
            currentFile := A_ScriptFullPath
            backupFile := targetDir "\report-check.backup.ahk"

            if (FileExist(currentFile)) {
                FileCopy(currentFile, backupFile, 1)  ; Overwrite if exists
            }

            ; Copy new file to target location
            targetFile := targetDir "\report-check.ahk"
            FileCopy(sourceFile, targetFile, 1)  ; Overwrite if exists

            return {success: true, targetFile: targetFile, backupFile: backupFile}

        } catch as err {
            return {success: false, error: err.Message}
        }
    }

    ; Clean up old script files with outdated naming patterns
    ; This prevents conflicts when updating from old naming conventions
    static CleanupOldScriptFiles(targetDir) {
        try {
            ; Patterns for old script names to remove
            oldPatterns := [
                "report check.ahk",        ; Old name with space
                "reportcheck.ahk",         ; Old name without space or hyphen
                "report check*.ahk",       ; Any variants with space
                "reportcheck*.ahk",        ; Any variants without separators
                "report-check*.ahk"        ; Any variants with hyphen
            ]

            removedFiles := []

            for pattern in oldPatterns {
                Loop Files, targetDir "\" pattern {
                    ; Skip if this is the current correct name
                    if (A_LoopFileName = "report-check.ahk") {
                        continue
                    }

                    ; Skip if it's a backup file
                    if (InStr(A_LoopFileName, ".backup.")) {
                        continue
                    }

                    ; Delete the old file
                    try {
                        FileDelete(A_LoopFileFullPath)
                        removedFiles.Push(A_LoopFileName)
                    } catch {
                        ; Ignore errors - file might be in use
                    }
                }
            }

            return {success: true, removedFiles: removedFiles}

        } catch as err {
            return {success: false, error: err.Message}
        }
    }

    ; Clean up orphaned shortcuts in Startup folder
    ; Similar to the installer's CleanOrphanedShortcuts function
    static CleanupOrphanedShortcuts() {
        try {
            startupDir := A_Startup  ; AutoHotkey built-in variable for Startup folder

            ; Patterns to search for (old and new naming conventions)
            patterns := [
                "*report check*.lnk",      ; Old name with space
                "*reportcheck*.lnk",       ; Old name without separators
                "*report-check*.lnk"       ; New name with hyphen
            ]

            removedShortcuts := []

            for pattern in patterns {
                Loop Files, startupDir "\" pattern {
                    ; Read the shortcut to see what it points to
                    try {
                        ; Use COM to read shortcut target
                        shell := ComObject("WScript.Shell")
                        shortcut := shell.CreateShortcut(A_LoopFileFullPath)
                        targetPath := shortcut.TargetPath

                        ; Check if shortcut is valid
                        SplitPath(targetPath, &targetFileName)
                        shouldRemove := false

                        ; Remove if filename is not "report-check.ahk"
                        if (targetFileName != "report-check.ahk") {
                            shouldRemove := true
                        }
                        ; Remove if target file doesn't exist (orphaned shortcut)
                        else if (!FileExist(targetPath)) {
                            shouldRemove := true
                        }

                        if (shouldRemove) {
                            FileDelete(A_LoopFileFullPath)
                            removedShortcuts.Push(A_LoopFileName)
                        }
                    } catch {
                        ; If we can't read the shortcut, it's probably orphaned - remove it
                        try {
                            FileDelete(A_LoopFileFullPath)
                            removedShortcuts.Push(A_LoopFileName)
                        } catch {
                            ; Ignore if we can't delete
                        }
                    }
                }
            }

            return {success: true, removedShortcuts: removedShortcuts}

        } catch as err {
            return {success: false, error: err.Message}
        }
    }

    ; Perform a complete update of all files (main script + lib modules + pref files)
    ; This is the new recommended update method
    ; progressCallback: function(fileIndex, totalFiles, filename, status)
    ;   - status can be: "downloading", "installing", "complete"
    static PerformCompleteUpdate(version, targetDir, progressCallback := "") {
        try {
            ; Get list of all files in the release
            filesResult := this.GetReleaseFiles(version)
            if (!filesResult.success) {
                return {success: false, error: "Failed to get file list: " . filesResult.error}
            }

            files := filesResult.files
            totalFiles := files.Length

            if (totalFiles = 0) {
                return {success: false, error: "No files found in release"}
            }

            ; Create temp directory for downloads
            tempDir := A_Temp . "\update_" . this.APP_NAME . "_" . version . "_" . A_TickCount
            if (!DirExist(tempDir)) {
                DirCreate(tempDir)
            }

            downloadedFiles := []

            ; Phase 1: Download all files
            for index, fileInfo in files {
                if (progressCallback) {
                    progressCallback(index, totalFiles, fileInfo.filename, "downloading")
                }

                ; Download file
                ; Convert forward slashes to backslashes for Windows paths
                windowsPath := StrReplace(fileInfo.path, "/", "\")
                targetPath := tempDir "\" . windowsPath

                ; Create subdirectories if needed
                SplitPath(targetPath, , &fileDir)
                if (!DirExist(fileDir)) {
                    DirCreate(fileDir)
                }

                ; Use original path (with forward slashes) for URL
                downloadResult := this.DownloadFromAPI(version, targetPath, fileInfo.path)
                if (!downloadResult.success) {
                    ; Cleanup temp directory on failure
                    try {
                        DirDelete(tempDir, 1)
                    }
                    return {success: false, error: "Failed to download " . fileInfo.filename . ": " . downloadResult.error}
                }

                downloadedFiles.Push({
                    filename: fileInfo.filename,
                    path: fileInfo.path,
                    localPath: targetPath,
                    size: fileInfo.size
                })

                ; Add small delay between downloads to avoid rate limiting
                ; Skip delay on last file
                if (index < totalFiles) {
                    Sleep(50)
                }
            }

            ; Phase 2: Create backup of current installation
            if (progressCallback) {
                progressCallback(0, totalFiles, "", "backing_up")
            }

            backupDir := targetDir . "\backup_" . FormatTime(A_Now, "yyyyMMddHHmmss")
            if (!DirExist(backupDir)) {
                DirCreate(backupDir)
            }

            ; Backup main script
            if (FileExist(A_ScriptFullPath)) {
                FileCopy(A_ScriptFullPath, backupDir . "\report-check.ahk", 1)
            }

            ; Backup lib directory
            if (DirExist(targetDir . "\lib")) {
                DirCopy(targetDir . "\lib", backupDir . "\lib", 1)
            }

            ; Phase 3.5: Clean up old files and shortcuts
            if (progressCallback) {
                progressCallback(0, totalFiles, "", "cleaning")
            }

            ; Remove old script files with outdated naming
            this.CleanupOldScriptFiles(targetDir)

            ; Remove orphaned shortcuts
            this.CleanupOrphanedShortcuts()

            ; Phase 4: Install all files
            if (progressCallback) {
                progressCallback(0, totalFiles, "", "installing")
            }

            for index, fileInfo in downloadedFiles {
                ; Convert forward slashes to backslashes for Windows paths
                windowsPath := StrReplace(fileInfo.path, "/", "\")

                ; Special handling for system_prompt files:
                ; - Server stores them in root for simplicity
                ; - Local installation needs them in pref/ folder
                ; - Never overwrite existing files (preserve user customizations)
                if (RegExMatch(fileInfo.filename, "i)^system_prompt.*\.txt$")) {
                    ; Map to pref directory
                    targetPath := targetDir . "\pref\" . fileInfo.filename

                    ; Only copy if file doesn't exist (preserve user customizations)
                    if (!FileExist(targetPath)) {
                        ; Ensure pref directory exists
                        if (!DirExist(targetDir . "\pref")) {
                            DirCreate(targetDir . "\pref")
                        }
                        FileCopy(fileInfo.localPath, targetPath, 0)
                    }
                    ; else skip - preserve existing user file
                } else {
                    ; Normal file handling - use path as-is and overwrite
                    targetPath := targetDir . "\" . windowsPath

                    ; Create subdirectories if needed
                    SplitPath(targetPath, , &fileDir)
                    if (!DirExist(fileDir)) {
                        DirCreate(fileDir)
                    }

                    ; Copy file to target location (overwrite to ensure update)
                    FileCopy(fileInfo.localPath, targetPath, 1)
                }
            }

            ; Cleanup temp directory
            try {
                DirDelete(tempDir, 1)
            }

            if (progressCallback) {
                progressCallback(totalFiles, totalFiles, "", "complete")
            }

            return {
                success: true,
                filesInstalled: totalFiles,
                backupDir: backupDir,
                targetFile: targetDir . "\report-check.ahk"
            }

        } catch as err {
            ; Cleanup temp directory on error
            try {
                if (IsSet(tempDir) && DirExist(tempDir)) {
                    DirDelete(tempDir, 1)
                }
            }
            return {success: false, error: "Update error: " . err.Message}
        }
    }

    ; Check and download missing prompt files after update
    static EnsurePromptFiles(version) {
        try {
            prefDir := A_ScriptDir "\pref"

            ; Ensure pref directory exists
            if (!DirExist(prefDir)) {
                DirCreate(prefDir)
            }

            ; List of required prompt files
            promptFiles := [
                "system_prompt_comprehensive.txt",
                "system_prompt_proofreading.txt",
                "system_prompt_targeted_review.txt"
            ]

            missingFiles := []

            ; Check which files are missing
            for promptFile in promptFiles {
                fullPath := prefDir "\" promptFile
                if (!FileExist(fullPath)) {
                    missingFiles.Push(promptFile)
                }
            }

            ; Download missing files
            if (missingFiles.Length > 0) {
                for promptFile in missingFiles {
                    result := this.DownloadPromptFile(version, promptFile, prefDir)
                    if (!result.success) {
                        ; Log error but don't fail the update
                        ; User can manually restore prompt files if needed
                    }
                }
            }

            return {success: true, downloadedCount: missingFiles.Length}

        } catch as err {
            ; Don't fail update if prompt download fails
            return {success: false, error: err.Message}
        }
    }

    ; Download a specific prompt file from API
    ; Uses binary download method (same as DownloadFromAPI) to ensure reliability
    static DownloadPromptFile(version, filename, targetDir) {
        try {
            targetPath := targetDir "\" filename
            url := this.API_URL . "/api/download/" . this.APP_NAME . "/" . version . "/" . filename

            ; Retry logic for rate limiting (429 errors)
            maxRetries := 3
            retryDelay := 1000  ; Start with 1 second

            Loop maxRetries {
                attempt := A_Index
                http := ""
                stream := ""

                try {
                    http := ComObject("WinHttp.WinHttpRequest.5.1")
                    http.Open("GET", url, false)
                    http.SetRequestHeader("X-API-Key", this.API_KEY)
                    timeouts := Constants.GetDownloadTimeouts()
                    http.SetTimeouts(timeouts[1], timeouts[2], timeouts[3], timeouts[4])
                    http.Send()

                    ; Check for rate limiting
                    if (http.Status = 429) {
                        ; Release COM objects before retry
                        http := ""

                        Logger.Debug("Rate limit hit for prompt file, retrying...", {
                            filename: filename,
                            attempt: attempt,
                            delay: retryDelay
                        })

                        ; If this was the last attempt, fail
                        if (attempt = maxRetries) {
                            Logger.Error("Prompt file download rate limited", {
                                filename: filename,
                                version: version
                            })
                            return {success: false, error: "Rate limit exceeded (429). Please try again in a few moments."}
                        }

                        ; Wait with exponential backoff before retrying
                        Sleep(retryDelay)
                        retryDelay *= 2  ; Double delay for next retry
                        continue  ; Retry
                    }

                    if (http.Status != 200) {
                        Logger.Error("Prompt file download failed", {
                            filename: filename,
                            version: version,
                            status: http.Status
                        })
                        return {success: false, error: "Download failed with status " . http.Status}
                    }

                    ; Create parent directory if needed
                    SplitPath(targetPath, , &fileDir)
                    if (!DirExist(fileDir)) {
                        DirCreate(fileDir)
                    }

                    ; Save binary response to file (works for both text and binary)
                    stream := ComObject("ADODB.Stream")
                    stream.Type := 1  ; Binary
                    stream.Open()
                    stream.Write(http.ResponseBody)
                    stream.SaveToFile(targetPath, 2)  ; Overwrite if exists

                    Logger.Debug("Prompt file downloaded successfully", {
                        filename: filename,
                        version: version
                    })

                    return {success: true, filePath: targetPath}

                } finally {
                    ; Ensure COM objects are properly released
                    if (stream != "") {
                        try stream.Close()
                    }
                    stream := ""
                    http := ""
                }
            }

            ; Should not reach here, but just in case
            return {success: false, error: "Download failed after " . maxRetries . " retries"}

        } catch as err {
            Logger.Error("Prompt file download error", {
                filename: filename,
                error: err.Message
            })
            return {success: false, error: "Download error: " . err.Message}
        }
    }

    ; Restore prompt files from server (overwrites local customizations)
    ; This is different from EnsurePromptFiles - this OVERWRITES existing files
    ; progressCallback: function(fileIndex, totalFiles, filename, status)
    static RestorePromptFiles(version, progressCallback := "") {
        try {
            Logger.Info("Starting prompt file restore from server", {
                version: version
            })

            prefDir := A_ScriptDir . "\pref"

            ; Ensure pref directory exists
            if (!DirExist(prefDir)) {
                DirCreate(prefDir)
            }

            ; List of prompt files to restore
            promptFiles := [
                "system_prompt_comprehensive.txt",
                "system_prompt_proofreading.txt",
                "system_prompt_targeted_review.txt"
            ]

            totalFiles := promptFiles.Length

            ; Create backup directory
            backupDir := prefDir . "\backup\prompts_" . FormatTime(A_Now, "yyyyMMddHHmmss")
            if (!DirExist(backupDir)) {
                DirCreate(backupDir)
            }

            ; Backup existing prompt files
            if (progressCallback) {
                progressCallback(0, totalFiles, "", "backing_up")
            }

            backedUpCount := 0
            for promptFile in promptFiles {
                sourcePath := prefDir "\" promptFile
                if (FileExist(sourcePath)) {
                    FileCopy(sourcePath, backupDir "\" promptFile, 1)
                    backedUpCount++
                }
            }

            Logger.Info("Backed up existing prompt files", {
                count: backedUpCount,
                backup_dir: backupDir
            })

            ; Download each prompt file from server
            downloadedFiles := []
            skippedFiles := []
            for index, promptFile in promptFiles {
                if (progressCallback) {
                    progressCallback(index, totalFiles, promptFile, "downloading")
                }

                ; Download to temp location first
                tempPath := A_Temp . "\prompt_" . A_TickCount . "_" . promptFile
                result := this.DownloadPromptFile(version, promptFile, A_Temp)

                if (!result.success) {
                    ; Skip files that don't exist on server (404) instead of failing
                    if (InStr(result.error, "404")) {
                        Logger.Warn("Skipping prompt file not available on server", {
                            filename: promptFile,
                            version: version
                        })
                        skippedFiles.Push(promptFile)
                        continue  ; Skip this file and continue with others
                    }

                    ; For other errors, fail the operation
                    return {
                        success: false,
                        error: "Failed to download " . promptFile . ": " . result.error,
                        backupDir: backupDir
                    }
                }

                ; Add small delay between downloads to avoid rate limiting
                if (index < totalFiles) {
                    Sleep(50)
                }

                ; Read and validate the downloaded content
                if (progressCallback) {
                    progressCallback(index, totalFiles, promptFile, "validating")
                }

                try {
                    content := FileRead(result.filePath, "UTF-8")

                    ; Strip UTF-8 BOM if present
                    if (SubStr(content, 1, 1) = Chr(0xFEFF)) {
                        content := SubStr(content, 2)
                    }

                    ; Validate using PromptCache validation
                    ; Determine prompt type from filename
                    if (RegExMatch(promptFile, "comprehensive")) {
                        promptType := "comprehensive"
                    } else if (RegExMatch(promptFile, "targeted")) {
                        promptType := "targeted"
                    } else {
                        promptType := "proofreading"
                    }
                    validationResult := PromptCache._ValidatePrompt(content, promptType)

                    if (!validationResult.valid) {
                        ; Clean up temp file
                        try FileDelete(result.filePath)
                        return {
                            success: false,
                            error: promptFile . " validation failed: " . validationResult.error,
                            backupDir: backupDir
                        }
                    }

                    downloadedFiles.Push({
                        filename: promptFile,
                        tempPath: result.filePath,
                        content: content
                    })

                } catch as err {
                    return {
                        success: false,
                        error: "Error processing " . promptFile . ": " . err.Message,
                        backupDir: backupDir
                    }
                }
            }

            ; Install validated files (overwrite existing)
            if (progressCallback) {
                progressCallback(0, totalFiles, "", "installing")
            }

            for index, fileInfo in downloadedFiles {
                targetPath := prefDir "\" fileInfo.filename

                ; Delete existing file
                if (FileExist(targetPath)) {
                    FileDelete(targetPath)
                }

                ; Move temp file to target
                FileMove(fileInfo.tempPath, targetPath, 1)
            }

            Logger.Info("Prompt file restore completed", {
                files_restored: downloadedFiles.Length,
                files_skipped: skippedFiles.Length,
                backed_up: backedUpCount,
                version: version
            })

            return {
                success: true,
                filesRestored: downloadedFiles.Length,
                skippedFiles: skippedFiles,
                backedUpCount: backedUpCount,
                backupDir: backupDir
            }

        } catch as err {
            Logger.Error("Prompt file restore failed", {
                error: err.Message,
                version: version
            })

            return {
                success: false,
                error: "Restore error: " . err.Message,
                backupDir: IsSet(backupDir) ? backupDir : ""
            }
        }
    }

    ; ==============================================
    ; API-Based Update Methods
    ; ==============================================

    ; Check for updates from API server
    static CheckForUpdatesFromAPI(currentVersion) {
        try {
            url := this.API_URL . "/api/versions/" . this.APP_NAME

            http := ""
            try {
                http := ComObject("WinHttp.WinHttpRequest.5.1")
                http.Open("GET", url, false)
                http.SetRequestHeader("X-API-Key", this.API_KEY)
                timeouts := Constants.GetUpdateTimeouts()
                http.SetTimeouts(timeouts[1], timeouts[2], timeouts[3], timeouts[4])
                http.Send()

                if (http.Status != 200) {
                    return {success: false, error: "API returned status " . http.Status}
                }

                ; Parse JSON response
                response := this._ParseJSON(http.ResponseText)

                if (!response.Has("latest_version")) {
                    return {success: false, error: "Invalid API response"}
                }

                latestVersion := response["latest_version"]

                ; Check if update is available
                cmp := this.CompareVersions(latestVersion, currentVersion)
                if (cmp > 0) {
                    versionInfo := response["version_info"]

                    ; Get SHA-256, use empty string if not available
                    sha256 := versionInfo.Has("sha256") ? versionInfo["sha256"] : ""

                    return {
                        success: true,
                        updateAvailable: true,
                        version: latestVersion,
                        releaseNotes: versionInfo.Has("release_notes") ? versionInfo["release_notes"] : "",
                        releaseDate: versionInfo.Has("release_date") ? versionInfo["release_date"] : "",
                        sha256: sha256,
                        filename: versionInfo.Has("filename") ? versionInfo["filename"] : ""
                    }
                }

                ; Current version is newer than server — dev/unreleased build
                if (cmp < 0) {
                    return {success: true, updateAvailable: false, devVersion: true, latestRelease: latestVersion}
                }

                return {success: true, updateAvailable: false}

            } finally {
                ; Release COM object
                http := ""
            }

        } catch as err {
            return {success: false, error: "API error: " . err.Message}
        }
    }

    ; Get list of all files in a release
    static GetReleaseFiles(version) {
        try {
            url := this.API_URL . "/api/files/" . this.APP_NAME . "/" . version

            http := ""
            try {
                http := ComObject("WinHttp.WinHttpRequest.5.1")
                http.Open("GET", url, false)
                http.SetRequestHeader("X-API-Key", this.API_KEY)
                timeouts := Constants.GetUpdateTimeouts()
                http.SetTimeouts(timeouts[1], timeouts[2], timeouts[3], timeouts[4])
                http.Send()

                if (http.Status != 200) {
                    return {success: false, error: "API returned status " . http.Status}
                }

                ; Parse JSON response to get list of files
                files := this._ParseFilesJSON(http.ResponseText)

                if (files.Length = 0) {
                    return {success: false, error: "No files found in release"}
                }

                return {success: true, files: files}

            } finally {
                ; Release COM object
                http := ""
            }

        } catch as err {
            return {success: false, error: "API error: " . err.Message}
        }
    }

    ; Download update from API server
    ; filename parameter supports subdirectory paths like "lib/ConfigManager.ahk"
    static DownloadFromAPI(version, targetPath := "", filename := "") {
        try {
            ; Use temp directory if no target specified
            if (targetPath = "") {
                targetPath := A_Temp . "\update_" . this.APP_NAME . "_" . version . ".ahk"
            }

            ; Build URL - append filename if provided for specific file downloads
            url := this.API_URL . "/api/download/" . this.APP_NAME . "/" . version
            if (filename != "") {
                url .= "/" . filename
            }

            ; Retry logic for rate limiting (429 errors)
            maxRetries := 3
            retryDelay := 1000  ; Start with 1 second

            Loop maxRetries {
                attempt := A_Index
                http := ""
                stream := ""

                try {
                    http := ComObject("WinHttp.WinHttpRequest.5.1")
                    http.Open("GET", url, false)
                    http.SetRequestHeader("X-API-Key", this.API_KEY)
                    timeouts := Constants.GetDownloadTimeouts()
                    http.SetTimeouts(timeouts[1], timeouts[2], timeouts[3], timeouts[4])  ; Longer timeout for download
                    http.Send()

                    ; Check for rate limiting
                    if (http.Status = 429) {
                        ; Release COM objects before retry
                        http := ""

                        ; If this was the last attempt, fail
                        if (attempt = maxRetries) {
                            return {success: false, error: "Rate limit exceeded (429). Please try again in a few moments."}
                        }

                        ; Wait with exponential backoff before retrying
                        Sleep(retryDelay)
                        retryDelay *= 2  ; Double delay for next retry
                        continue  ; Retry
                    }

                    if (http.Status != 200) {
                        return {success: false, error: "Download failed with status " . http.Status}
                    }

                    ; Create parent directory if needed
                    SplitPath(targetPath, , &fileDir)
                    if (!DirExist(fileDir)) {
                        DirCreate(fileDir)
                    }

                    ; Save binary response to file
                    ; Create file stream to write binary data
                    stream := ComObject("ADODB.Stream")
                    stream.Type := 1  ; Binary
                    stream.Open()
                    stream.Write(http.ResponseBody)
                    stream.SaveToFile(targetPath, 2)  ; Overwrite if exists

                    return {success: true, filePath: targetPath}

                } finally {
                    ; Ensure COM objects are properly released
                    if (stream != "") {
                        try stream.Close()
                    }
                    stream := ""
                    http := ""
                }
            }

            ; Should not reach here, but just in case
            return {success: false, error: "Download failed after " . maxRetries . " retries"}

        } catch as err {
            return {success: false, error: "Download error: " . err.Message}
        }
    }

    ; ==============================================
    ; Self-Integrity Check Methods
    ; ==============================================

    ; Calculate SHA-256 hash of a file using PowerShell
    static CalculateFileSHA256(filePath) {
        try {
            ; Create temp file for output
            tempFile := A_Temp . "\hash_" . A_TickCount . ".txt"

            ; Use PowerShell to calculate SHA-256 hash (hidden window)
            psCommand := 'powershell.exe -NoProfile -WindowStyle Hidden -Command "(Get-FileHash -Algorithm SHA256 \"' . filePath . '\").Hash | Out-File -FilePath \"' . tempFile . '\" -Encoding UTF8"'

            shell := ""
            try {
                ; Run PowerShell hidden and wait for completion
                shell := ComObject("WScript.Shell")
                shell.Run(psCommand, 0, true)  ; 0 = hidden window, true = wait for completion
            } finally {
                ; Release COM object
                shell := ""
            }

            ; Read the hash from temp file
            if (!FileExist(tempFile)) {
                return {success: false, error: "Hash calculation failed - output file not created"}
            }

            calculatedHash := FileRead(tempFile, "UTF-8")

            ; Clean up temp file
            try {
                FileDelete(tempFile)
            }

            ; Remove any newlines, spaces, BOM, or other whitespace
            calculatedHash := StrReplace(calculatedHash, "`r", "")
            calculatedHash := StrReplace(calculatedHash, "`n", "")
            calculatedHash := StrReplace(calculatedHash, Chr(0xFEFF), "")  ; Remove BOM
            calculatedHash := Trim(calculatedHash)

            return {success: true, hash: calculatedHash}

        } catch as err {
            return {success: false, error: "Hash calculation error: " . err.Message}
        }
    }

    ; Verify integrity of all installation files (main script, lib modules)
    ; Note: Prompt files in pref/ are skipped as users may customize them
    static VerifyScriptIntegrity(currentVersion) {
        try {
            ; Get list of all files that should be in this version
            filesResult := this.GetReleaseFiles(currentVersion)

            if (!filesResult.success) {
                ; Check if this is a 404 error (version not found on server)
                if (InStr(filesResult.error, "404")) {
                    ; Verify if this is truly a development version by checking against latest server version
                    updateCheck := this.CheckForUpdatesFromAPI(currentVersion)

                    if (updateCheck.success) {
                        if (updateCheck.HasProp("version")) {
                            ; Update available means current < latest, so this is an old/missing version
                            latestVersion := updateCheck.version
                            return {
                                success: false,
                                error: "Version " . currentVersion . " not found on server.`n`nThis version may have been removed or never existed.`nLatest available version: " . latestVersion
                            }
                        } else {
                            ; No update available means current >= latest
                            ; If we get 404 for file list but current >= latest, this must be a dev version
                            return {
                                success: true,
                                verified: true,
                                isDevelopment: true,
                                message: "Development version " . currentVersion . " is not yet available on the server.`n`nIntegrity check cannot be performed for unreleased versions."
                            }
                        }
                    } else {
                        ; Couldn't check latest version - assume development version (original behavior)
                        errorMsg := updateCheck.HasProp("error") ? updateCheck.error : "Unknown error"
                        return {
                            success: true,
                            verified: true,
                            isDevelopment: true,
                            message: "Version " . currentVersion . " is not available on the server.`n`nIntegrity check cannot be performed.`n`n(Could not verify if this is a development version: " . errorMsg . ")"
                        }
                    }
                }

                return {
                    success: false,
                    error: "Failed to get file list from server: " . filesResult.error
                }
            }

            files := filesResult.files
            baseDir := A_ScriptDir

            failedFiles := []
            verifiedCount := 0
            skippedCount := 0

            ; Check each file in the release
            for index, fileInfo in files {
                ; Convert forward slashes to backslashes for Windows paths
                windowsPath := StrReplace(fileInfo.path, "/", "\")
                filePath := baseDir . "\" . windowsPath

                ; Skip non-.ahk files
                if (!RegExMatch(fileInfo.filename, "i)\.ahk$")) {
                    skippedCount++
                    continue
                }

                ; Check if file exists
                if (!FileExist(filePath)) {
                    failedFiles.Push({
                        file: fileInfo.filename,
                        reason: "File missing"
                    })
                    continue
                }

                ; Calculate actual hash
                hashResult := this.CalculateFileSHA256(filePath)
                if (!hashResult.success) {
                    failedFiles.Push({
                        file: fileInfo.filename,
                        reason: "Hash calculation failed: " . hashResult.error
                    })
                    continue
                }

                actualHash := hashResult.hash

                ; Skip if no expected hash (shouldn't happen with GetReleaseFiles, but be safe)
                if (!fileInfo.HasProp("sha256") || fileInfo.sha256 = "") {
                    skippedCount++
                    continue
                }

                ; Compare hashes
                if (StrLower(actualHash) != StrLower(fileInfo.sha256)) {
                    failedFiles.Push({
                        file: fileInfo.filename,
                        reason: "Hash mismatch",
                        expected: fileInfo.sha256,
                        actual: actualHash
                    })
                } else {
                    verifiedCount++
                }
            }

            ; Build result
            if (failedFiles.Length > 0) {
                ; Some files failed verification
                errorMsg := "Integrity check failed for " . failedFiles.Length . " file(s):`n`n"
                for failInfo in failedFiles {
                    errorMsg .= "• " . failInfo.file . ": " . failInfo.reason . "`n"
                }

                return {
                    success: true,
                    verified: false,
                    message: errorMsg,
                    failedFiles: failedFiles,
                    verifiedCount: verifiedCount,
                    totalFiles: files.Length
                }
            } else {
                ; All files verified successfully
                return {
                    success: true,
                    verified: true,
                    message: "All " . verifiedCount . " files verified successfully",
                    verifiedCount: verifiedCount,
                    skippedCount: skippedCount,
                    totalFiles: files.Length
                }
            }

        } catch as err {
            return {
                success: false,
                error: "Integrity check error: " . err.Message
            }
        }
    }


    ; Simple JSON parser for API responses
    static _ParseJSON(jsonString) {
        ; Create a Map to store the parsed data
        result := Map()

        try {
            ; Remove whitespace
            json := Trim(jsonString)

            ; Simple regex-based parsing for our specific API response format
            ; Extract app_name
            if (RegExMatch(json, '"app_name"\s*:\s*"([^"]+)"', &match)) {
                result["app_name"] := match[1]
            }

            ; Extract latest_version
            if (RegExMatch(json, '"latest_version"\s*:\s*"([^"]+)"', &match)) {
                result["latest_version"] := match[1]
            }

            ; Extract version_info object
            if (RegExMatch(json, '"version_info"\s*:\s*\{([^}]+)\}', &match)) {
                versionInfo := Map()
                versionInfoStr := match[1]

                ; Extract fields from version_info
                if (RegExMatch(versionInfoStr, '"version"\s*:\s*"([^"]+)"', &m)) {
                    versionInfo["version"] := m[1]
                }
                if (RegExMatch(versionInfoStr, '"sha256"\s*:\s*"([^"]+)"', &m)) {
                    versionInfo["sha256"] := m[1]
                }
                if (RegExMatch(versionInfoStr, '"release_notes"\s*:\s*"([^"]+)"', &m)) {
                    versionInfo["release_notes"] := m[1]
                }
                if (RegExMatch(versionInfoStr, '"release_date"\s*:\s*"([^"]+)"', &m)) {
                    versionInfo["release_date"] := m[1]
                }
                if (RegExMatch(versionInfoStr, '"filename"\s*:\s*"([^"]+)"', &m)) {
                    versionInfo["filename"] := m[1]
                }

                result["version_info"] := versionInfo
            }

            return result

        } catch as err {
            throw Error("JSON parsing failed: " . err.Message)
        }
    }

    ; Parse file list JSON response from /api/files endpoint
    ; Returns array of file objects with filename, path, size, and sha256
    static _ParseFilesJSON(jsonString) {
        files := []

        try {
            json := Trim(jsonString)

            ; Extract the files array - find everything between "files": [ and the closing ]
            if (RegExMatch(json, '"files"\s*:\s*\[(.*)\]', &filesMatch)) {
                filesArrayStr := filesMatch[1]

                ; Find all file objects within the array
                ; Pattern matches: {"filename": "...", "path": "...", "size": ..., "sha256": "..."}
                pos := 1
                while (pos := RegExMatch(filesArrayStr, "\{[^}]+\}", &objMatch, pos)) {
                    objStr := objMatch[0]
                    fileInfo := {}

                    ; Extract filename
                    if (RegExMatch(objStr, '"filename"\s*:\s*"([^"]+)"', &m)) {
                        fileInfo.filename := m[1]
                    }

                    ; Extract path
                    if (RegExMatch(objStr, '"path"\s*:\s*"([^"]+)"', &m)) {
                        fileInfo.path := m[1]
                    }

                    ; Extract size
                    if (RegExMatch(objStr, '"size"\s*:\s*(\d+)', &m)) {
                        fileInfo.size := Integer(m[1])
                    }

                    ; Extract sha256
                    if (RegExMatch(objStr, '"sha256"\s*:\s*"([^"]+)"', &m)) {
                        fileInfo.sha256 := m[1]
                    }

                    ; Only add if we have required fields
                    if (fileInfo.HasProp("filename") && fileInfo.HasProp("path") && fileInfo.HasProp("sha256")) {
                        files.Push(fileInfo)
                    }

                    pos += StrLen(objMatch[0])
                }
            }

            return files

        } catch as err {
            throw Error("Files JSON parsing failed: " . err.Message)
        }
    }
}