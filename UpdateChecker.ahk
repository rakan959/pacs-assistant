#Requires AutoHotkey v2.0
#Include Settings.ahk
#Include Version.ahk

class UpdateChecker {
    ; Read through a property rather than copied into a static, so there is no second
    ; place a version is stated and can drift from the tag
    static currentVersion => AppVersion.current

    static repoUrl := "https://github.com/rakan959/pacs-assistant"

    ; GitHub's own prerelease flag decides what counts as a beta. /releases/latest
    ; excludes prereleases natively; asking for the newest release includes them.
    static latestStableUrl := "https://api.github.com/repos/rakan959/pacs-assistant/releases/latest"
    static newestReleaseUrl := "https://api.github.com/repos/rakan959/pacs-assistant/releases?per_page=1"

    static updateTimer := 0
    static skippedVersion := ""  ; Track which version the user chose to skip
    static lastRemindTime := 0   ; Track when the user last clicked "Remind Me Later"
    
    static Start() {
        ; Check for updates immediately if enabled
        if Settings.Get("AutoUpdate") {
            updateInfo := this.CheckForUpdates()
            if updateInfo.hasUpdate {
                this.ShowUpdateDialog()
            }
        }
        
        ; Set up hourly check if auto-update is enabled
        if Settings.Get("AutoUpdate") {
            this.StartAutoCheck()
        }
    }
    
    static StartAutoCheck() {
        ; Clear any existing timer
        if this.updateTimer {
            SetTimer(this.updateTimer, 0)
            this.updateTimer := 0
        }
        
        ; Set up new timer if auto-update is enabled
        if Settings.Get("AutoUpdate") {
            this.updateTimer := ObjBindMethod(this, "AutoCheck")
            SetTimer(this.updateTimer, 3600000)  ; Check every hour (3600000 ms)
        }
    }
    
    static StopAutoCheck() {
        if this.updateTimer {
            SetTimer(this.updateTimer, 0)
            this.updateTimer := 0
        }
    }
    
    static AutoCheck() {
        updateInfo := this.CheckForUpdates()
        if updateInfo.hasUpdate {
            this.ShowUpdateDialog()
        }
    }
    
    static OnSettingsChanged() {
        ; Restart auto-check with new settings
        this.StartAutoCheck()
    }
    
    ; Leading integer of a version field, 0 if there isn't one
    static ToInt(text) {
        if RegExMatch(text, "^\d+", &m)
            return Integer(m[0])
        return 0
    }

    static Sign(a, b) {
        return a < b ? -1 : (a > b ? 1 : 0)
    }

    /**
     * Parses a version string into SemVer components.
     *
     * Accepts SemVer ("v2.1.0-beta.1") and the older scheme ("v2.0b4"), normalising the
     * latter to its SemVer equivalent (2.0.0-b.4) so old and new tags still order
     * correctly against each other.
     *
     * The previous parser read only major and minor, so every patch release compared
     * equal - v2.0.1 and v2.0.9 were indistinguishable and no client would ever have
     * been offered a patch update.
     */
    static ParseVersion(version) {
        version := Trim(version)
        version := RegExReplace(version, "^[vV]")

        ; Legacy "2.0b4" / "2.0b" -> "2.0.0-b.4" / "2.0.0-b.0"
        if RegExMatch(version, "^(\d+)\.(\d+)b(\d*)$", &legacy)
            version := legacy[1] "." legacy[2] ".0-b." (legacy[3] != "" ? legacy[3] : "0")

        ; Build metadata takes no part in precedence
        core := version
        if (pos := InStr(core, "+"))
            core := SubStr(core, 1, pos - 1)

        prerelease := ""
        if (pos := InStr(core, "-")) {
            prerelease := SubStr(core, pos + 1)
            core := SubStr(core, 1, pos - 1)
        }

        parts := StrSplit(core, ".")

        return {
            major: this.ToInt(parts.Has(1) ? parts[1] : "0"),
            minor: this.ToInt(parts.Has(2) ? parts[2] : "0"),
            patch: this.ToInt(parts.Has(3) ? parts[3] : "0"),
            prerelease: prerelease,
            isPrerelease: prerelease != ""
        }
    }

    /**
     * Compares two versions by SemVer precedence.
     * @returns -1 if v1 is older than v2, 1 if newer, 0 if equal
     */
    static CompareVersions(v1, v2) {
        a := this.ParseVersion(v1)
        b := this.ParseVersion(v2)

        if (a.major != b.major)
            return this.Sign(a.major, b.major)
        if (a.minor != b.minor)
            return this.Sign(a.minor, b.minor)
        if (a.patch != b.patch)
            return this.Sign(a.patch, b.patch)

        ; A prerelease ranks below the release it precedes
        if (!a.isPrerelease && !b.isPrerelease)
            return 0
        if (!a.isPrerelease)
            return 1
        if (!b.isPrerelease)
            return -1

        return this.ComparePrerelease(a.prerelease, b.prerelease)
    }

    /**
     * Compares dot-separated prerelease identifiers per SemVer: numeric identifiers
     * compare numerically, alphanumeric ones as text, numeric ranks below alphanumeric,
     * and a shorter set of identifiers ranks below a longer one that matches so far.
     */
    static ComparePrerelease(p1, p2) {
        left := StrSplit(p1, ".")
        right := StrSplit(p2, ".")

        loop Max(left.Length, right.Length) {
            if (A_Index > left.Length)
                return -1
            if (A_Index > right.Length)
                return 1

            x := left[A_Index]
            y := right[A_Index]
            xIsNum := RegExMatch(x, "^\d+$") > 0
            yIsNum := RegExMatch(y, "^\d+$") > 0

            if (xIsNum && yIsNum) {
                if (Integer(x) != Integer(y))
                    return this.Sign(Integer(x), Integer(y))
                continue
            }
            if (xIsNum)
                return -1
            if (yIsNum)
                return 1

            if (result := StrCompare(x, y, true))
                return result < 0 ? -1 : 1
        }

        return 0
    }
    
    /**
     * Turns a JSON string literal back into text.
     * Only the escapes GitHub actually emits in release notes are handled.
     */
    static DecodeJsonString(text) {
        text := StrReplace(text, "\r\n", "`n")
        text := StrReplace(text, "\n", "`n")
        text := StrReplace(text, "\t", "`t")
        text := StrReplace(text, "\/", "/")
        text := StrReplace(text, '\"', '"')
        return StrReplace(text, "\\", "\")
    }

    static CheckForUpdates() {
        ; Never offer to update an uncompiled run: PerformUpdate replaces
        ; A_ScriptFullPath, which for a script is main.ahk, so it would drop an EXE on
        ; top of the source. Untagged builds have no meaningful version to compare.
        if (!A_IsCompiled || AppVersion.isDevBuild)
            return { hasUpdate: false }

        ; Ask GitHub for the right release rather than filtering on the tag name.
        ; /releases/latest excludes prereleases natively; the newest release includes
        ; them. The old code parsed "beta" out of the tag, which disagreed with the
        ; prerelease flag GitHub actually stores, and - because every published release
        ; was named like a beta while SkipBetaVersions defaults on - meant no user with
        ; default settings was ever offered an update.
        url := Settings.Get("SkipBetaVersions") ? this.latestStableUrl : this.newestReleaseUrl

        try {
            ; Set up the HTTP request with headers for GitHub API
            whr := ComObject("WinHttp.WinHttpRequest.5.1")
            whr.Open("GET", url, true)
            whr.SetRequestHeader("User-Agent", "PACS-Assistant-Update-Checker")
            whr.SetRequestHeader("Accept", "application/vnd.github+json")
            whr.Send()
            whr.WaitForResponse()

            ; 404 is expected from /releases/latest when every release is a prerelease
            if (whr.Status = 200) {
                ; Parse the JSON response. per_page=1 keeps the array to a single
                ; release, so the first match of each field belongs to that release.
                responseText := whr.ResponseText

                ; Extract the required fields using RegEx since we know the format
                tagMatch := RegExMatch(responseText, '"tag_name"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"', &tag)
                bodyMatch := RegExMatch(responseText, '"body"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"', &body)
                ; Match the asset by name so a future extra asset cannot be picked up
                assetsMatch := RegExMatch(responseText, '"browser_download_url"\s*:\s*"([^"]+/pacs-assistant\.exe)"', &asset)

                if (!tagMatch)
                    return { hasUpdate: false }

                latestVersion := tag[1]
                releaseNotes := bodyMatch ? this.DecodeJsonString(body[1]) : "No release notes available."
                downloadUrl := assetsMatch ? asset[1] : ""

                ; Check if user chose to skip this version
                if (latestVersion = this.skippedVersion)
                    return { hasUpdate: false }
                    
                ; Check if we should wait before reminding again (4 hours)
                if (this.lastRemindTime && (A_TickCount - this.lastRemindTime) < 14400000)
                    return { hasUpdate: false }
                
                ; Compare versions using comparison logic
                compareResult := this.CompareVersions(this.currentVersion, latestVersion)
                
                if (compareResult < 0) {
                    if (downloadUrl = "")
                        return { hasUpdate: false }
                        
                    return {
                        hasUpdate: true,
                        currentVersion: this.currentVersion,
                        latestVersion: latestVersion,
                        downloadUrl: downloadUrl,
                        releaseNotes: releaseNotes
                    }
                }
            }
        } catch as err {
            ; Log quietly to avoid interrupting the user
            OutputDebug("Update check failed: " err.Message)
        }
        return { hasUpdate: false }
    }
    
    static ShowUpdateDialog() {
        updateInfo := this.CheckForUpdates()
        if (!updateInfo.hasUpdate)
            return
            
        ; Create update dialog with modern styling
        updateGui := Gui("+AlwaysOnTop", "PACS Assistant - Update Available")
        updateGui.SetFont("s10", "Segoe UI")  ; Modern font
        
        ; Header
        updateGui.Add("Text", "y10 w400", "A new version of PACS Assistant is available!")
        updateGui.Add("Text", "y+10", "Current version: " updateInfo.currentVersion)
        updateGui.Add("Text", "y+5", "Latest version: " updateInfo.latestVersion)
        
        ; Release notes with better formatting
        updateGui.Add("Text", "y+15", "What's New:")
        updateGui.Add("Edit", "y+5 r10 w400 ReadOnly", updateInfo.releaseNotes)
        
        ; Auto-update checkbox
        autoUpdateCheckbox := updateGui.Add("Checkbox", "y+10", "Automatically check for updates on launch")
        autoUpdateCheckbox.Value := Settings.Get("AutoUpdate")
        
        ; Skip beta versions checkbox
        skipBetaCheckbox := updateGui.Add("Checkbox", "y+5", "Skip beta versions")
        skipBetaCheckbox.Value := Settings.Get("SkipBetaVersions")
        
        ; Buttons
        buttonGroup := updateGui.Add("GroupBox", "y+15 w400 h50")
        updateGui.Add("Button", "xp+10 yp+15 w120", "Update Now").OnEvent("Click", (*) => this.PerformUpdate(updateInfo.downloadUrl, updateGui))
        updateGui.Add("Button", "x+10 w120", "Remind Me Later").OnEvent("Click", (*) => (
            this.lastRemindTime := A_TickCount,  ; Set the remind time
            updateGui.Destroy()
        ))
        updateGui.Add("Button", "x+10 w120", "Skip This Version").OnEvent("Click", (*) => (
            this.skippedVersion := updateInfo.latestVersion,  ; Set the skipped version
            updateGui.Destroy()
        ))
        
        ; Save settings when closing
        updateGui.OnEvent("Close", (*) => (
            Settings.Set("AutoUpdate", autoUpdateCheckbox.Value),
            Settings.Set("SkipBetaVersions", skipBetaCheckbox.Value)
        ))
        
        updateGui.Show()
    }
    
    static PerformUpdate(downloadUrl, updateGui) {
        try {
            ; Get the current executable path
            currentExe := A_ScriptFullPath
            backupExe := A_ScriptDir "\pacs-assistant.backup.exe"
            newExe := A_ScriptDir "\pacs-assistant.new.exe"
            
            ; Create backup of current executable
            if FileExist(currentExe)
                FileCopy(currentExe, backupExe, true)
                
            ; Download new version
            Download(downloadUrl, newExe)
            
            ; Create a batch file to perform the update after this process exits
            batchScript := "
            (
            @echo off
            timeout /t 1 /nobreak >nul
            move /y `"" newExe "`" `"" currentExe "`"
            start `"`" `"" currentExe "`"
            del `"%~f0`"
            )"
            
            FileAppend(batchScript, "update.bat")
            
            ; Run the update batch file and exit this process
            Run("update.bat", , "Hide")
            updateGui.Destroy()
            ExitApp
        } catch as err {
            MsgBox("Update failed: " err.Message, "Error", "Icon!")
            ; Restore from backup if it exists
            if FileExist(backupExe)
                FileMove(backupExe, currentExe, true)
        }
    }
}
