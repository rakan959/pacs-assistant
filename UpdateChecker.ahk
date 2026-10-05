; = CONTENTS
;   + Preamble
;   + UpdateChecker class (version check, update download/verify, updater launch, dialog)

#Requires AutoHotkey v2.0
#Include Settings.ahk
#Include Version.ahk
#Include JsonParser.ahk
#Include ErrorText.ahk
#Include AppLog.ahk
#Include WinHttpTransport.ahk
#Include WinHttpTextRequest.ahk

class UpdateChecker {
    ; Read through a property rather than copied into a static, so there is no second
    ; place a version is stated and can drift from the tag
    static currentVersion => AppVersion.current

    ; GitHub's own prerelease flag decides what counts as a beta. /releases/latest
    ; excludes prereleases natively; asking for the newest release includes them.
    static latestStableUrl := "https://api.github.com/repos/rakan959/pacs-assistant/releases/latest"
    static newestReleaseUrl := "https://api.github.com/repos/rakan959/pacs-assistant/releases?per_page=1"
    static transport := WinHttpTransport()
    ; Wired by the composition root to the clinical command gate. Keeping the
    ; probe injectable avoids a dependency from the updater back into PACSCommands.
    static clinicalActivityProbe := (*) => false
    ; The two-phase shutdown owner (KeybindGUI), set by the composition root.
    ; PerformUpdate will not install without it.
    static shutdownCoordinator := 0
    static autoCheckIntervalMs := 60 * 60 * 1000
    static autoCheckFailureLogged := false
    ; "Remind Me Later" defers the automatic update notice for this long.
    static remindLaterMs := 4 * 60 * 60 * 1000
    static maxUpdateSizeBytes := 100 * 1024 * 1024
    static maxMetadataSizeBytes := 1024 * 1024
    static maxReleaseNotesCharacters := 20000
    static installProbeSequence := 0
    static moveFile := (source, destination) => FileMove(source, destination, false)
    ; The installed copy: the update is staged beside it and replaces it in place.
    static installDirectory := A_ScriptDir
    static installedExecutable := A_ScriptFullPath
    static compiledProbe := (*) => A_IsCompiled
    static launchUpdater := (command, workingDirectory) => Run(command, workingDirectory, "Hide")

    static updateTimer := 0
    static activeRequest := 0
    static cleanupTimer := 0
    static skippedVersion := ""  ; Track which version the user chose to skip
    static lastRemindTime := 0   ; Track when the user last clicked "Remind Me Later"
    static pendingUpdateInfo := 0
    static notifiedVersion := ""
    static updateDialog := 0
    static updateAvailableNotifier := (text, title, options) => TrayTip(text, title, options)
    static manualResultNotifier := (text, title, options) => TrayTip(text, title, options)
    static dialogAcquire := (*) => true
    static dialogRelease := (*) => 0
    static updateCheckEligibleProbe := (*) => A_IsCompiled && !AppVersion.isDevBuild

    static Start() {
        this.LoadSkippedVersion()
        this.ScheduleUpdateArtifactCleanup()
        this.StartAutoCheck()
        if Settings.Get("AutoUpdate")
            this.BeginAutoCheck()
    }

    static StartAutoCheck(cancelManualCheck := true) {
        this.StopAutoCheck(cancelManualCheck)

        ; Set up new timer if auto-update is enabled
        if Settings.Get("AutoUpdate") {
            this.updateTimer := ObjBindMethod(this, "BeginAutoCheck")
            SetTimer(this.updateTimer, this.autoCheckIntervalMs)
        }
    }

    static StopAutoCheck(cancelManualCheck := true) {
        if this.updateTimer {
            SetTimer(this.updateTimer, 0)
            this.updateTimer := 0
        }
        this.CancelActiveCheck(cancelManualCheck)
    }

    static CancelActiveCheck(cancelManualCheck := true) {
        if !this.activeRequest
            return
        slot := this.activeRequest
        if (slot.manual && !cancelManualCheck)
            return
        this.activeRequest := 0
        slot.completed := true
        handle := slot.handle
        slot.handle := 0
        if handle
            try handle.Cancel()
    }

    static BeginAutoCheck() {
        if this.activeRequest
            return false
        if !this.updateCheckEligibleProbe.Call()
            return false

        start := this.StartCheck(false)
        if start.error
            this.RecordAutoCheckFailure(start.error)
        return start.started
    }

    /**
     * Starts the release-metadata request for a new check and makes it the active
     * request. Its completion and failure go to the Complete/Fail method of the
     * matching kind.
     * @returns {started, error}: started when the request is in flight; error when
     * it could not start, 0 when it already finished synchronously
     */
    static StartCheck(manual) {
        stableOnly := Settings.Get("SkipBetaVersions")
        url := stableOnly ? this.latestStableUrl : this.newestReleaseUrl
        slot := {handle: 0, completed: false, manual: manual}
        this.activeRequest := slot
        try {
            slot.handle := this.transport.GetTextAsync(
                url,
                ObjBindMethod(this, manual ? "CompleteManualCheck" : "CompleteAutoCheck", slot, stableOnly),
                ObjBindMethod(this, manual ? "FailManualCheck" : "FailAutoCheck", slot),
                this.maxMetadataSizeBytes
            )
        } catch as err {
            this.ClaimSlot(slot)
            return {started: false, error: err}
        }
        if slot.handle
            return {started: true, error: 0}
        if (this.activeRequest = slot)
            this.activeRequest := 0
        return {started: false, error: slot.completed ? 0 : Error("The update request returned no handle")}
    }

    static CompleteAutoCheck(slot, stableOnly, response) {
        if !this.ClaimSlot(slot)
            return

        try {
            updateInfo := this.ProcessReleaseResponse(response, stableOnly)
            this.autoCheckFailureLogged := false
            if updateInfo.hasUpdate
                this.RecordAvailableUpdate(updateInfo)
        } catch as err {
            this.RecordAutoCheckFailure(err)
        }
    }

    ; Marks a check's slot finished and drops it as the active request. Returns
    ; false when a cancel or the other completion callback already claimed it.
    static ClaimSlot(slot) {
        if slot.completed
            return false
        slot.completed := true
        slot.handle := 0
        if (this.activeRequest = slot)
            this.activeRequest := 0
        return true
    }

    static FailAutoCheck(slot, err) {
        if !this.ClaimSlot(slot)
            return
        this.RecordAutoCheckFailure(err)
    }

    ; The hourly check fails every time on an offline workstation, so only the first
    ; failure after a successful check is logged.
    static RecordAutoCheckFailure(err) {
        OutputDebug("Update check failed: " ErrorText.Message(err))
        if this.autoCheckFailureLogged
            return
        this.autoCheckFailureLogged := true
        AppLog.Write("Automatic update check failed: " ErrorText.Describe(err))
    }

    static OnSettingsChanged() {
        ; Reconfigure only the automatic schedule. A manual check is a user-visible
        ; operation and must complete (or explicitly report failure), never vanish
        ; because an unrelated setting was saved while its request was in flight.
        this.LoadSkippedVersion()
        ; Only a preference change invalidates a pending update; the reminder
        ; defers notices, not the update itself.
        if (IsObject(this.pendingUpdateInfo)
            && !this.UpdateInfoIsEligible(this.pendingUpdateInfo, false)) {
            if this.UpdateDialogIsLive()
                this.CloseUpdateDialog(this.updateDialog)
            this.pendingUpdateInfo := 0
            this.notifiedVersion := ""
        }
        this.StartAutoCheck(false)
    }

    static RecordAvailableUpdate(updateInfo) {
        this.pendingUpdateInfo := updateInfo
        if (this.notifiedVersion == updateInfo.latestVersion)
            return
        this.notifiedVersion := updateInfo.latestVersion
        try this.updateAvailableNotifier.Call(
            "Version " updateInfo.latestVersion " is available. Use Check for Updates when ready.",
            "PACS Assistant Update Available",
            "Iconi"
        )
    }

    static LoadSkippedVersion() {
        this.skippedVersion := Settings.Get("SkippedUpdateVersion")
        return this.skippedVersion
    }

    static TrySaveUpdatePreferences(expectedRevision, autoUpdate, skipBetaVersions, skippedVersion?) {
        values := Map(
            "AutoUpdate", autoUpdate ? true : false,
            "SkipBetaVersions", skipBetaVersions ? true : false
        )
        if IsSet(skippedVersion) {
            if (Type(skippedVersion) != "String" || Trim(skippedVersion) = "")
                return false
            values["SkippedUpdateVersion"] := skippedVersion
        }
        try {
            Settings.SaveValuesAtRevision(values, expectedRevision)
            if IsSet(skippedVersion)
                this.skippedVersion := skippedVersion
        } catch SettingsConflictError {
            MsgBox(
                "Settings changed while this update dialog was open. Reopen it before saving preferences.",
                "Settings Changed",
                "Icon!"
            )
            return false
        } catch as err {
            AppLog.Write("Update preferences could not be saved: " ErrorText.Describe(err))
            MsgBox(
                "The update preferences could not be saved. The previous settings were left unchanged.`n`n" err.Message,
                "Save Failed",
                "Icon!"
            )
            return false
        }

        try this.OnSettingsChanged()
        catch as err {
            MsgBox(
                "The update preferences were saved, but the automatic-check schedule could not be refreshed. Restart PACS Assistant to apply it.`n`n" err.Message,
                "Update Schedule Failed",
                "Icon!"
            )
            return false
        }
        return true
    }

    ; Leading integer of a version field, 0 if there isn't one. Integer() wraps
    ; beyond the 64-bit range, so a longer number saturates instead.
    static ToInt(text) {
        if !RegExMatch(text, "^\d+", &m)
            return 0
        return StrLen(LTrim(m[0], "0")) > 18 ? 0x7FFFFFFFFFFFFFFF : Integer(m[0])
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
     * Patch takes part in precedence, so v2.0.1 and v2.0.9 are distinct versions and
     * a patch release is offered as an update.
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
                if (result := this.CompareNumericIdentifiers(x, y))
                    return result
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

    ; SemVer does not bound numeric identifier length. Compare normalized digit
    ; strings by magnitude rather than coercing them into AutoHotkey's fixed-width
    ; Integer representation.
    static CompareNumericIdentifiers(left, right) {
        left := RegExReplace(left, "^0+(?=\d)")
        right := RegExReplace(right, "^0+(?=\d)")
        if (StrLen(left) != StrLen(right))
            return this.Sign(StrLen(left), StrLen(right))
        result := StrCompare(left, right, true)
        return result < 0 ? -1 : (result > 0 ? 1 : 0)
    }

    static ParseReleaseResponse(responseText) {
        document := JsonParser.Parse(responseText)
        if (document is Array) {
            if (document.Length = 0)
                throw Error("GitHub returned an empty release list")
            release := document[1]
        } else {
            release := document
        }

        if !(release is Map) || !release.Has("tag_name") || Type(release["tag_name"]) != "String"
            throw Error("Release metadata is missing tag_name")
        if (!release.Has("prerelease")
            || !(release["prerelease"] is Integer)
            || (release["prerelease"] != 0 && release["prerelease"] != 1))
            throw Error("Release metadata is missing a valid prerelease flag")
        if !release.Has("assets") || !(release["assets"] is Array)
            throw Error("Release metadata is missing assets")

        selectedAsset := 0
        for asset in release["assets"] {
            if (asset is Map && asset.Has("name") && asset["name"] = "pacs-assistant.exe") {
                selectedAsset := asset
                break
            }
        }
        if !selectedAsset
            throw Error("Release does not contain pacs-assistant.exe")

        for field in ["browser_download_url", "digest", "size"] {
            if !selectedAsset.Has(field)
                throw Error("Release asset is missing " field)
        }

        downloadUrl := selectedAsset["browser_download_url"]
        digest := selectedAsset["digest"]
        size := selectedAsset["size"]
        if !this.IsTrustedDownloadUrl(downloadUrl)
            throw Error("Release asset has an untrusted download URL")
        if (Type(digest) != "String" || !RegExMatch(digest, "i)^sha256:([0-9a-f]{64})$", &digestMatch))
            throw Error("Release asset is missing a valid SHA-256 digest")
        if !(size is Integer) || size <= 0 || size > this.maxUpdateSizeBytes
            throw Error("Release asset has an invalid size")

        notes := "No release notes available."
        if (release.Has("body") && Type(release["body"]) = "String" && release["body"] != "")
            notes := release["body"]
        if (StrLen(notes) > this.maxReleaseNotesCharacters)
            notes := this.TruncateReleaseNotes(notes)

        return {
            version: release["tag_name"],
            isPrerelease: release["prerelease"] ? true : false,
            notes: notes,
            downloadUrl: downloadUrl,
            assetSize: size,
            assetSha256: StrLower(digestMatch[1])
        }
    }

    ; The tag segment may be percent-encoded (GitHub encodes "+" build metadata),
    ; but a literal or encoded dot segment would let the path climb out of
    ; /releases/download/ before the digest check ever runs.
    static IsTrustedDownloadUrl(url) {
        return Type(url) = "String"
            && RegExMatch(
                url,
                "i)^https://github\.com/rakan959/pacs-assistant/releases/download/(?!(?:\.|%2e){1,2}/)[^/?#]+/pacs-assistant\.exe$"
            ) > 0
    }

    static ReleaseResponseAvailable(status, stableOnly) {
        if (status = 200)
            return true
        ; GitHub's /releases/latest endpoint returns 404 when a repository has only
        ; prereleases. That is an expected "nothing eligible" result for users who
        ; skip betas; every other status is operational failure evidence.
        if (stableOnly && status = 404)
            return false
        throw Error("GitHub release request returned HTTP " status)
    }

    /**
     * @param respectReminder false for a check the user asked for: "Remind Me Later"
     * defers only the automatic notice
     * @returns The update info, or {hasUpdate: false}; when the only newer version is
     * the one the user skipped, also skippedVersion
     */
    static ProcessReleaseResponse(response, stableOnly, respectReminder := true) {
        if !this.ReleaseResponseAvailable(response.status, stableOnly)
            return { hasUpdate: false }

        release := this.ParseReleaseResponse(response.body)
        latestVersion := release.version
        updateInfo := {
            hasUpdate: true,
            currentVersion: this.currentVersion,
            latestVersion: latestVersion,
            isPrerelease: release.isPrerelease,
            downloadUrl: release.downloadUrl,
            downloadSize: release.assetSize,
            downloadSha256: release.assetSha256,
            releaseNotes: release.notes
        }
        if (stableOnly && updateInfo.isPrerelease)
            return { hasUpdate: false }
        if !this.UpdateInfoIsEligible(updateInfo, respectReminder) {
            if (latestVersion == this.skippedVersion
                && this.CompareVersions(this.currentVersion, latestVersion) < 0)
                return { hasUpdate: false, skippedVersion: latestVersion }
            return { hasUpdate: false }
        }

        return updateInfo
    }

    static UpdateInfoIsEligible(updateInfo, respectReminder := true) {
        if (!IsObject(updateInfo)
            || !HasProp(updateInfo, "hasUpdate")
            || !updateInfo.hasUpdate
            || !HasProp(updateInfo, "latestVersion")
            || Type(updateInfo.latestVersion) != "String")
            return false
        isPrerelease := HasProp(updateInfo, "isPrerelease")
            ? !!updateInfo.isPrerelease
            : this.ParseVersion(updateInfo.latestVersion).isPrerelease
        if (Settings.Get("SkipBetaVersions") && isPrerelease)
            return false
        if (updateInfo.latestVersion == this.skippedVersion)
            return false
        if (respectReminder
            && this.lastRemindTime
            && (DllCall("GetTickCount64", "UInt64") - this.lastRemindTime) < this.remindLaterMs)
            return false
        return this.CompareVersions(this.currentVersion, updateInfo.latestVersion) < 0
    }

    ; Notes are display-only, so long ones are cut rather than blocking the update.
    static TruncateReleaseNotes(notes) {
        kept := SubStr(notes, 1, this.maxReleaseNotesCharacters)
        ; Never end on the first half of a UTF-16 surrogate pair.
        lastCode := Ord(SubStr(kept, -1))
        if (lastCode >= 0xD800 && lastCode <= 0xDBFF)
            kept := SubStr(kept, 1, -1)
        return kept "`n`n[Release notes shortened. The release page on GitHub has the full text.]"
    }

    static BeginManualCheck() {
        if this.clinicalActivityProbe.Call() {
            this.manualResultNotifier.Call(
                "Wait for the active clinical command to finish before checking for updates.",
                "Clinical Command In Progress",
                "Icon!"
            )
            return false
        }
        if this.activeRequest {
            this.manualResultNotifier.Call(
                "An update check is already in progress.",
                "Checking for Updates",
                "Iconi"
            )
            return false
        }
        if !this.updateCheckEligibleProbe.Call() {
            this.manualResultNotifier.Call(
                "Update checks are available in tagged release builds.",
                "Development Build",
                "Iconi"
            )
            return false
        }

        start := this.StartCheck(true)
        if !start.started {
            if start.error
                this.manualResultNotifier.Call(
                    "The update check could not start: " ErrorText.Message(start.error),
                    "Update Check Failed",
                    "Icon!"
                )
            return false
        }
        try this.updateAvailableNotifier.Call(
            "Checking GitHub for a PACS Assistant update...",
            "Checking for Updates",
            "Iconi"
        )
        return true
    }

    static CompleteManualCheck(slot, stableOnly, response) {
        if !this.ClaimSlot(slot)
            return
        try {
            updateInfo := this.ProcessReleaseResponse(response, stableOnly, false)
            if (!updateInfo.hasUpdate && HasProp(updateInfo, "skippedVersion")) {
                this.manualResultNotifier.Call(
                    "Version " updateInfo.skippedVersion " is available, but it was skipped with Skip This Version.",
                    "Update Skipped",
                    "Iconi"
                )
                return
            }
            if !updateInfo.hasUpdate {
                this.manualResultNotifier.Call(
                    "PACS Assistant is up to date.",
                    "No Update Available",
                    "Iconi"
                )
                return
            }
            this.pendingUpdateInfo := updateInfo
            ; Nothing reopens the dialog later, so the notice says how to.
            if this.clinicalActivityProbe.Call() {
                this.updateAvailableNotifier.Call(
                    "Version " updateInfo.latestVersion " is available. Use Check for Updates once the active clinical command finishes.",
                    "PACS Assistant Update Available",
                    "Iconi"
                )
                return
            }
            this.ShowUpdateDialog(updateInfo)
        } catch as err {
            this.manualResultNotifier.Call(
                "The update check failed: " err.Message,
                "Update Check Failed",
                "Icon!"
            )
        }
    }

    static FailManualCheck(slot, err) {
        if !this.ClaimSlot(slot)
            return
        this.manualResultNotifier.Call(
            "The update check failed: " ErrorText.Message(err),
            "Update Check Failed",
            "Icon!"
        )
    }

    /**
     * Shows the update dialog.
     * @param updateInfo Result of an earlier asynchronous release check. Callers that
     * already checked pass theirs; asking again costs a second HTTP round trip against
     * an unauthenticated 60/hour GitHub limit and can return a different answer from
     * the one the caller acted on.
     */
    static ShowUpdateDialog(updateInfo?) {
        fromCache := !IsSet(updateInfo)
        if !IsSet(updateInfo) {
            if (IsObject(this.pendingUpdateInfo) && this.pendingUpdateInfo.hasUpdate)
                updateInfo := this.pendingUpdateInfo
            else
                return this.BeginManualCheck()
        }
        ; Every caller is a user request, so "Remind Me Later" does not apply here.
        if !this.UpdateInfoIsEligible(updateInfo, false) {
            if (IsObject(this.pendingUpdateInfo) && this.pendingUpdateInfo = updateInfo)
                this.pendingUpdateInfo := 0
            return fromCache ? this.BeginManualCheck() : false
        }
        this.pendingUpdateInfo := updateInfo
        if this.clinicalActivityProbe.Call() {
            this.manualResultNotifier.Call(
                "Wait for the active clinical command to finish before opening the update dialog.",
                "Clinical Command In Progress",
                "Icon!"
            )
            return false
        }
        if !this.dialogAcquire.Call("open the update dialog") {
            this.manualResultNotifier.Call(
                "Wait for the active clinical or configuration operation to finish before opening the update dialog.",
                "Update Dialog Unavailable",
                "Icon!"
            )
            return false
        }
        try {
            if this.UpdateDialogIsLive() {
                if (this.updateDialog.latestVersion == updateInfo.latestVersion) {
                    try WinActivate("ahk_id " this.updateDialog.Hwnd)
                    return this.updateDialog
                }
                ; A newer release was announced since this dialog opened, and its
                ; buttons act on the version it shows, so it is replaced.
                this.CloseUpdateDialog(this.updateDialog)
            }

            ; Create update dialog with modern styling
            ; DPI policy: default DPIScale ON - system-DPI-aware, auto-scaled.
            updateGui := Gui(, "PACS Assistant - Update Available")
            updateGui.settingsRevision := Settings.revision
            updateGui.latestVersion := updateInfo.latestVersion
            updateGui.SetFont("s10", "Segoe UI")  ; Modern font

            ; Header
            updateGui.Add("Text", "y10 w400", "A new version of PACS Assistant is available!")
            updateGui.Add("Text", "y+10", "Current version: " updateInfo.currentVersion)
            updateGui.Add("Text", "y+5", "Latest version: " updateInfo.latestVersion)

            ; Release notes with better formatting
            updateGui.Add("Text", "y+15", "What's New:")
            updateGui.Add("Edit", "y+5 r10 w400 ReadOnly", updateInfo.releaseNotes)

            ; Auto-update checkbox
            autoUpdateCheckbox := updateGui.Add("Checkbox", "y+10", "Automatically check for updates")
            autoUpdateCheckbox.Value := Settings.Get("AutoUpdate")

            ; Skip beta versions checkbox
            skipBetaCheckbox := updateGui.Add("Checkbox", "y+5", "Skip beta versions")
            skipBetaCheckbox.Value := Settings.Get("SkipBetaVersions")

            ; Gui.Destroy() does not raise Close, so every way out of the dialog saves
            ; the two checkboxes itself.
            saveChoices := (*) => this.SaveDialogChoices(
                updateGui,
                autoUpdateCheckbox.Value,
                skipBetaCheckbox.Value
            )
            saveSkippedChoices := (*) => this.SaveDialogChoices(
                updateGui,
                autoUpdateCheckbox.Value,
                skipBetaCheckbox.Value,
                updateInfo.latestVersion
            )
            dismiss := (*) => (
                saveChoices(),
                this.CloseUpdateDialog(updateGui)
            )

            ; Buttons
            updateGui.Add("GroupBox", "y+15 w400 h50")
            updateGui.Add("Button", "xp+10 yp+15 w120", "Update Now").OnEvent("Click", (*) => (
                saveChoices() && this.PerformUpdate(updateInfo, updateGui)
            ))
            updateGui.Add("Button", "x+10 w120", "Remind Me Later").OnEvent("Click", (*) => (
                saveChoices() && (this.RemindLater(), this.CloseUpdateDialog(updateGui))
            ))
            updateGui.Add("Button", "x+10 w120", "Skip This Version").OnEvent("Click", (*) => (
                saveSkippedChoices() && this.CloseUpdateDialog(updateGui)
            ))

            updateGui.OnEvent("Close", dismiss)

            this.updateDialog := updateGui
            updateGui.Show()
            return updateGui
        } finally this.dialogRelease.Call()
    }

    ; Saves the update dialog's choices at the settings revision it was opened at.
    ; The dialog stays open when Update Now does not start, so a successful save
    ; moves it to the revision that save wrote. A dialog whose settings changed
    ; underneath can never save; once it has said so it closes, and Check for
    ; Updates reopens it from the pending update.
    static SaveDialogChoices(updateGui, autoUpdate, skipBetaVersions, skippedVersion?) {
        if this.TrySaveUpdatePreferences(
            updateGui.settingsRevision,
            autoUpdate,
            skipBetaVersions,
            skippedVersion?
        ) {
            updateGui.settingsRevision := Settings.revision
            return true
        }
        if (updateGui.settingsRevision != Settings.revision)
            this.CloseUpdateDialog(updateGui)
        return false
    }

    ; Defers the automatic notice for remindLaterMs. The version counts as not yet
    ; announced, so the first automatic check after the delay announces it again.
    static RemindLater() {
        this.lastRemindTime := DllCall("GetTickCount64", "UInt64")
        this.notifiedVersion := ""
    }

    static UpdateDialogIsLive() {
        if !IsObject(this.updateDialog)
            return false
        try return this.updateDialog.Hwnd > 0
            && WinExist("ahk_id " this.updateDialog.Hwnd)
        return false
    }

    static CloseUpdateDialog(updateGui) {
        if (this.updateDialog == updateGui)
            this.updateDialog := 0
        try updateGui.Destroy()
        return true
    }

    static HashFileSha256(path) {
        algorithm := 0
        hash := 0
        inputFile := 0

        try {
            this.CheckNtStatus(
                DllCall("bcrypt\BCryptOpenAlgorithmProvider",
                    "Ptr*", &algorithm,
                    "WStr", "SHA256",
                    "Ptr", 0,
                    "UInt", 0,
                    "UInt"),
                "BCryptOpenAlgorithmProvider"
            )

            objectLength := this.GetBcryptUIntProperty(algorithm, "ObjectLength")
            digestLength := this.GetBcryptUIntProperty(algorithm, "HashDigestLength")
            hashObject := Buffer(objectLength)
            this.CheckNtStatus(
                DllCall("bcrypt\BCryptCreateHash",
                    "Ptr", algorithm,
                    "Ptr*", &hash,
                    "Ptr", hashObject.Ptr,
                    "UInt", hashObject.Size,
                    "Ptr", 0,
                    "UInt", 0,
                    "UInt", 0,
                    "UInt"),
                "BCryptCreateHash"
            )

            inputFile := FileOpen(path, "r")
            ; FileOpen skips a leading byte-order mark; the digest covers every byte.
            inputFile.Pos := 0
            readBuffer := Buffer(1024 * 1024)
            while (bytesRead := inputFile.RawRead(readBuffer)) {
                this.CheckNtStatus(
                    DllCall("bcrypt\BCryptHashData",
                        "Ptr", hash,
                        "Ptr", readBuffer.Ptr,
                        "UInt", bytesRead,
                        "UInt", 0,
                        "UInt"),
                    "BCryptHashData"
                )
            }

            digest := Buffer(digestLength)
            this.CheckNtStatus(
                DllCall("bcrypt\BCryptFinishHash",
                    "Ptr", hash,
                    "Ptr", digest.Ptr,
                    "UInt", digest.Size,
                    "UInt", 0,
                    "UInt"),
                "BCryptFinishHash"
            )

            hex := ""
            loop digest.Size
                hex .= Format("{:02x}", NumGet(digest, A_Index - 1, "UChar"))
            return hex
        } finally {
            if IsObject(inputFile)
                inputFile.Close()
            if hash
                DllCall("bcrypt\BCryptDestroyHash", "Ptr", hash)
            if algorithm
                DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", algorithm, "UInt", 0)
        }
    }

    static GetBcryptUIntProperty(handle, propertyName) {
        value := Buffer(4)
        written := 0
        this.CheckNtStatus(
            DllCall("bcrypt\BCryptGetProperty",
                "Ptr", handle,
                "WStr", propertyName,
                "Ptr", value.Ptr,
                "UInt", value.Size,
                "UInt*", &written,
                "UInt", 0,
                "UInt"),
            "BCryptGetProperty(" propertyName ")"
        )
        return NumGet(value, 0, "UInt")
    }

    static CheckNtStatus(status, operation) {
        if (status != 0)
            throw Error(operation " failed with NTSTATUS " Format("0x{:08X}", status & 0xFFFFFFFF))
    }

    static IsPortableExecutable(path) {
        try {
            size := FileGetSize(path)
            if (size < 64)
                return false
            executableFile := FileOpen(path, "r")
            ; FileOpen skips a leading byte-order mark; the header starts at byte 0.
            executableFile.Pos := 0

            signature := Buffer(2)
            if (executableFile.RawRead(signature) != 2 || NumGet(signature, 0, "UShort") != 0x5A4D)
                return false

            executableFile.Pos := 0x3C
            offsetBuffer := Buffer(4)
            if (executableFile.RawRead(offsetBuffer) != 4)
                return false
            peOffset := NumGet(offsetBuffer, 0, "UInt")
            if (peOffset < 64 || peOffset + 4 > size)
                return false

            executableFile.Pos := peOffset
            peSignature := Buffer(4)
            return executableFile.RawRead(peSignature) = 4
                && NumGet(peSignature, 0, "UInt") = 0x00004550
        } catch OSError {
            return false
        } finally {
            if IsSet(executableFile) && IsObject(executableFile)
                executableFile.Close()
        }
    }

    static ValidateDownloadedArtifact(path, expectedSize, expectedSha256, expectedVersion) {
        if (!FileExist(path)
            || expectedSize <= 0
            || !RegExMatch(expectedSha256, "i)^[0-9a-f]{64}$")
            || FileGetSize(path) != expectedSize
            || StrLower(this.HashFileSha256(path)) != StrLower(expectedSha256)
            || !this.IsPortableExecutable(path)) {
            return false
        }

        ; FileGetVersion raises OSError for an image without a version resource.
        try fileVersion := this.ParseVersion(FileGetVersion(path))
        catch OSError {
            return false
        }
        expected := this.ParseVersion(expectedVersion)
        return fileVersion.major = expected.major
            && fileVersion.minor = expected.minor
            && fileVersion.patch = expected.patch
    }

    static OwnedUpdateArtifactNames() {
        return ["pacs-assistant.backup.exe", "pacs-assistant.new.exe"]
    }

    static CreateUpdaterPath() {
        guid := Buffer(16)
        status := DllCall("ole32\CoCreateGuid", "Ptr", guid.Ptr, "Int")
        if status != 0
            throw Error("Could not allocate a private updater identifier")

        textBuffer := Buffer(39 * 2, 0)
        length := DllCall(
            "ole32\StringFromGUID2",
            "Ptr", guid.Ptr,
            "Ptr", textBuffer.Ptr,
            "Int", 39,
            "Int"
        )
        if length <= 0
            throw Error("Could not format the private updater identifier")

        identifier := StrReplace(StrReplace(StrGet(textBuffer, "UTF-16"), "{"), "}")
        return A_Temp "\pacs-assistant-updater-" identifier ".ps1"
    }

    static InstallDirectoryIsWritable() {
        probePath := ""
        movedPath := ""
        probeFile := 0
        try {
            loop {
                this.installProbeSequence++
                suffix := DllCall("GetCurrentProcessId") "-"
                    . DllCall("GetTickCount64", "UInt64") "-"
                    . this.installProbeSequence
                probePath := this.installDirectory "\.pacs-assistant-update-probe-" suffix ".tmp"
                movedPath := probePath ".moved"
            } until !FileExist(probePath) && !FileExist(movedPath)

            ; In-place update needs directory create, write, rename, and delete
            ; permission. Probe that complete contract before acquiring shutdown or
            ; downloading an executable that cannot be installed.
            probeFile := FileOpen(probePath, "w", "UTF-8-RAW")
            probeFile.Write("PACS Assistant update write probe")
            probeFile.Close()
            probeFile := 0
            this.moveFile.Call(probePath, movedPath)
            FileDelete(movedPath)
            return true
        } catch Error as err {
            ; FileMove reports failure as a plain Error, the other file calls as
            ; OSError; either means the folder cannot take an in-place update.
            AppLog.Write("The app folder failed the update write probe: " ErrorText.Describe(err))
            return false
        } finally {
            if IsObject(probeFile)
                try probeFile.Close()
            if (probePath != "" && FileExist(probePath))
                try FileDelete(probePath)
            if (movedPath != "" && FileExist(movedPath))
                try FileDelete(movedPath)
        }
    }

    ; The hidden PowerShell command that runs the updater script after this process
    ; exits; the arguments are the ones BuildUpdaterScript reads from $args.
    static UpdaterCommand(updaterPath, currentExe, newExe, backupExe) {
        powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        return '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'
            . updaterPath '" ' DllCall("GetCurrentProcessId")
            . ' "' currentExe '" "' newExe '" "' backupExe '" "' AppLog.Path() '"'
    }

    static BuildUpdaterScript() {
        script := "
        (
        $ParentPid = [int]$args[0]
        $CurrentExe = [string]$args[1]
        $NewExe = [string]$args[2]
        $BackupExe = [string]$args[3]
        $LogPath = [string]$args[4]

        $ParentExited = $false
        $RecoveryLaunched = $false
        $RecoveryReady = $false
        $SwapStarted = $false
        $NewProcess = $null

        $ErrorActionPreference = 'Stop'
        try {
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
                if ([DateTime]::UtcNow -ge $deadline) {
                    throw 'PACS Assistant did not exit before the update timeout.'
                }
                Start-Sleep -Milliseconds 200
            }

            $ParentExited = $true

            if (Test-Path -LiteralPath $BackupExe) {
                Remove-Item -LiteralPath $BackupExe -Force
            }
            Move-Item -LiteralPath $CurrentExe -Destination $BackupExe
            $SwapStarted = $true

            Move-Item -LiteralPath $NewExe -Destination $CurrentExe
            $NewProcess = Start-Process -FilePath $CurrentExe -PassThru
            Start-Sleep -Seconds 5
            $NewProcess.Refresh()
            if ($NewProcess.HasExited) {
                throw 'The updated PACS Assistant exited during its startup health check.'
            }
        } catch {
            $UpdateError = $_
            if ($ParentExited -and -not $RecoveryLaunched) {
                $RecoveryReady = -not $SwapStarted
                try {
                    if ($null -ne $NewProcess -and -not $NewProcess.HasExited) {
                        Stop-Process -Id $NewProcess.Id -Force -ErrorAction SilentlyContinue
                        Wait-Process -Id $NewProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
                    }
                } catch {}

                if ($SwapStarted) {
                    try {
                        if (Test-Path -LiteralPath $CurrentExe) {
                            Remove-Item -LiteralPath $CurrentExe -Force
                        }
                        if (Test-Path -LiteralPath $BackupExe) {
                            Move-Item -LiteralPath $BackupExe -Destination $CurrentExe
                        }
                        $RecoveryReady = Test-Path -LiteralPath $CurrentExe -PathType Leaf
                    } catch {
                        $RecoveryReady = $false
                    }
                }

                if ($RecoveryReady -and (Test-Path -LiteralPath $CurrentExe -PathType Leaf)) {
                    try {
                        Start-Process -FilePath $CurrentExe
                        $RecoveryLaunched = $true
                    } catch {}
                }
            }

            # PACS Assistant has exited, so this is the only record of the failure.
            try {
                $entry = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff') + ' Update install failed: ' + $UpdateError + '; previous version relaunched: ' + $RecoveryLaunched + [char]10
                [IO.File]::AppendAllText($LogPath, $entry, (New-Object System.Text.UTF8Encoding $false))
            } catch {}

            throw $UpdateError
        } finally {
            Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
        }
        )"
        return script
    }

    static CleanupUpdateArtifacts() {
        for name in this.OwnedUpdateArtifactNames() {
            path := this.installDirectory "\" name
            try {
                if FileExist(path)
                    FileDelete(path)
            }
        }
        this.cleanupTimer := 0
    }

    static ScheduleUpdateArtifactCleanup() {
        if this.cleanupTimer
            SetTimer(this.cleanupTimer, 0)
        this.cleanupTimer := ObjBindMethod(this, "CleanupUpdateArtifacts")
        ; The updater watches the replacement for five seconds and may still need
        ; the backup during that window. Reaching 30 seconds of normal app runtime is
        ; the signal that the staged rollback files can be retired.
        SetTimer(this.cleanupTimer, -30000)
    }

    static CancelUpdateArtifactCleanup() {
        if this.cleanupTimer
            SetTimer(this.cleanupTimer, 0)
        this.cleanupTimer := 0
    }

    static PerformUpdate(updateInfo, updateGui) {
        if !IsObject(this.shutdownCoordinator)
            throw Error("UpdateChecker.shutdownCoordinator must be set before an update is installed")
        if !this.UpdateInfoIsEligible(updateInfo, false) {
            MsgBox(
                "This update is no longer eligible under the current preferences. Check for updates again.",
                "Update No Longer Eligible",
                "Icon!"
            )
            return false
        }
        if !this.InstallDirectoryIsWritable() {
            MsgBox(
                "PACS Assistant can run from this location, but Windows does not allow it to replace files there. "
                    . "Move the application to a folder you can write to, or install the update manually.",
                "Update Requires a Writable App Folder",
                "Icon!"
            )
            return false
        }
        if !this.shutdownCoordinator.BeginShutdown("install the update")
            return false
        currentExe := ""
        backupExe := ""
        newExe := ""
        updaterPath := ""
        try {
            ; Every operation after acquiring the shutdown lease belongs inside this
            ; recovery boundary. Even allocating a GUID-backed temporary path can
            ; fail, and must release the lease rather than blocking the app forever.
            ; The download runs while messages are still pumped, so the dialog's
            ; buttons would otherwise run mid-install, against the shutdown lease.
            try updateGui.Opt("+Disabled")
            currentExe := this.installedExecutable
            backupExe := this.installDirectory "\pacs-assistant.backup.exe"
            newExe := this.installDirectory "\pacs-assistant.new.exe"
            updaterPath := this.CreateUpdaterPath()
            this.CancelUpdateArtifactCleanup()
            if !this.compiledProbe.Call()
                throw Error("Automatic update is only available in the compiled application")
            if !this.IsTrustedDownloadUrl(updateInfo.downloadUrl)
                throw Error("The release download URL is not trusted")
            if (FileExist(newExe))
                FileDelete(newExe)
            if (FileExist(updaterPath))
                throw Error("The private updater script path already exists")

            this.transport.Download(
                updateInfo.downloadUrl,
                newExe,
                updateInfo.downloadSize,
                this.maxUpdateSizeBytes
            )
            if !this.ValidateDownloadedArtifact(
                newExe,
                updateInfo.downloadSize,
                updateInfo.downloadSha256,
                updateInfo.latestVersion
            ) {
                throw Error("The downloaded update failed size, SHA-256, PE, or version validation")
            }

            FileAppend(this.BuildUpdaterScript(), updaterPath, "UTF-8-RAW")
            this.launchUpdater.Call(
                this.UpdaterCommand(updaterPath, currentExe, newExe, backupExe),
                this.installDirectory
            )
            updateGui.Destroy()
            return this.shutdownCoordinator.CompleteShutdown()
        } catch as err {
            this.shutdownCoordinator.CancelShutdown()
            ; The dialog stays open so the update can be retried or dismissed.
            try updateGui.Opt("-Disabled")
            ; Includes a rejected download (size, SHA-256, PE or version check).
            AppLog.Write("Update failed: " ErrorText.Describe(err))
            MsgBox("Update failed: " err.Message, "Update Failed", "Icon!")
            ; The running executable is not touched until the updater runs after the
            ; app exits, so a preflight failure only needs to remove staged artifacts.
            if (newExe != "")
                try FileDelete(newExe)
            if (updaterPath != "")
                try FileDelete(updaterPath)
            this.ScheduleUpdateArtifactCleanup()
            return false
        }
    }
}
