#Requires AutoHotkey v2.0
#Include Settings.ahk
#Include Version.ahk
#Include JsonParser.ahk

/** Bounded WinHTTP transport for asynchronous checks and interactive downloads. */
class WinHttpTransport {
    static resolveTimeoutMs := 2000
    static connectTimeoutMs := 3000
    static sendTimeoutMs := 5000
    static receiveTimeoutMs := 10000

    CreateRequest(url, async := false) {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(
            WinHttpTransport.resolveTimeoutMs,
            WinHttpTransport.connectTimeoutMs,
            WinHttpTransport.sendTimeoutMs,
            WinHttpTransport.receiveTimeoutMs
        )
        request.Open("GET", url, async)
        request.SetRequestHeader("User-Agent", "PACS-Assistant-Update-Checker")
        request.SetRequestHeader("Accept", "application/vnd.github+json")
        return request
    }

    GetTextAsync(url, onComplete, onError, maximumSize) {
        request := this.CreateRequest(url, true)
        operation := WinHttpTextRequest(request, onComplete, onError, maximumSize)
        return operation.Start()
    }

    Download(url, destination, expectedSize, maximumSize) {
        if (!(expectedSize is Integer)
            || expectedSize <= 0
            || expectedSize > maximumSize)
            throw Error("Update download size is outside the allowed range")
        if !RegExMatch(url, "i)^https://github\.com(/.*)$", &match)
            throw Error("Update download URL is not a supported HTTPS GitHub URL")

        session := 0
        connection := 0
        request := 0
        output := 0
        completed := false
        try {
            session := DllCall(
                "winhttp\WinHttpOpen",
                "WStr", "PACS-Assistant-Update-Checker",
                "UInt", 1,
                "Ptr", 0,
                "Ptr", 0,
                "UInt", 0,
                "Ptr"
            )
            if !session
                throw OSError(A_LastError, "WinHttpOpen")
            connection := DllCall(
                "winhttp\WinHttpConnect",
                "Ptr", session,
                "WStr", "github.com",
                "UShort", 443,
                "UInt", 0,
                "Ptr"
            )
            if !connection
                throw OSError(A_LastError, "WinHttpConnect")
            request := DllCall(
                "winhttp\WinHttpOpenRequest",
                "Ptr", connection,
                "WStr", "GET",
                "WStr", match[1],
                "Ptr", 0,
                "Ptr", 0,
                "Ptr", 0,
                "UInt", 0x00800000,
                "Ptr"
            )
            if !request
                throw OSError(A_LastError, "WinHttpOpenRequest")
            if !DllCall(
                "winhttp\WinHttpSetTimeouts",
                "Ptr", request,
                "Int", WinHttpTransport.resolveTimeoutMs,
                "Int", WinHttpTransport.connectTimeoutMs,
                "Int", WinHttpTransport.sendTimeoutMs,
                "Int", WinHttpTransport.receiveTimeoutMs
            )
                throw OSError(A_LastError, "WinHttpSetTimeouts")
            if !DllCall(
                "winhttp\WinHttpSendRequest",
                "Ptr", request,
                "WStr", "Accept: application/octet-stream`r`n",
                "UInt", -1,
                "Ptr", 0,
                "UInt", 0,
                "UInt", 0,
                "UPtr", 0
            )
                throw OSError(A_LastError, "WinHttpSendRequest")
            if !DllCall("winhttp\WinHttpReceiveResponse", "Ptr", request, "Ptr", 0)
                throw OSError(A_LastError, "WinHttpReceiveResponse")

            status := 0
            statusSize := 4
            if !DllCall(
                "winhttp\WinHttpQueryHeaders",
                "Ptr", request,
                "UInt", 19 | 0x20000000,
                "Ptr", 0,
                "UInt*", &status,
                "UInt*", &statusSize,
                "Ptr", 0
            )
                throw OSError(A_LastError, "WinHttpQueryHeaders(status)")
            if (status != 200)
                throw Error("Update download returned HTTP " status)

            contentLength := 0
            contentLengthSize := 4
            if !DllCall(
                "winhttp\WinHttpQueryHeaders",
                "Ptr", request,
                "UInt", 5 | 0x20000000,
                "Ptr", 0,
                "UInt*", &contentLength,
                "UInt*", &contentLengthSize,
                "Ptr", 0
            )
                throw Error("Update download did not provide a valid Content-Length")
            if (contentLength != expectedSize || contentLength > maximumSize)
                throw Error("Update download Content-Length does not match trusted metadata")

            output := FileOpen(destination, "w")
            if !output
                throw Error("Update destination could not be opened")
            total := 0
            downloadBuffer := Buffer(64 * 1024)
            loop {
                available := 0
                if !DllCall(
                    "winhttp\WinHttpQueryDataAvailable",
                    "Ptr", request,
                    "UInt*", &available
                )
                    throw OSError(A_LastError, "WinHttpQueryDataAvailable")
                if !available
                    break
                readSize := Min(available, downloadBuffer.Size)
                bytesRead := 0
                if !DllCall(
                    "winhttp\WinHttpReadData",
                    "Ptr", request,
                    "Ptr", downloadBuffer.Ptr,
                    "UInt", readSize,
                    "UInt*", &bytesRead
                )
                    throw OSError(A_LastError, "WinHttpReadData")
                if !bytesRead
                    throw Error("Update download ended before its declared byte count")
                total += bytesRead
                if (total > expectedSize || total > maximumSize)
                    throw Error("Update download exceeded its trusted byte limit")
                if (output.RawWrite(downloadBuffer, bytesRead) != bytesRead)
                    throw Error("Update download could not be written completely")
            }
            output.Close()
            output := 0
            if (total != expectedSize)
                throw Error("Update download byte count does not match trusted metadata")
            completed := true
        } finally {
            if IsObject(output)
                try output.Close()
            for handle in [request, connection, session] {
                if handle
                    DllCall("winhttp\WinHttpCloseHandle", "Ptr", handle)
            }
            if !completed
                try FileDelete(destination)
        }
    }

    static ReadBoundedTextResponse(request, maximumSize) {
        if (!(maximumSize is Integer) || maximumSize <= 0)
            throw ValueError("A positive metadata response limit is required")
        try {
            contentLengthText := request.GetResponseHeader("Content-Length")
            if (contentLengthText != "") {
                contentLength := Integer(contentLengthText)
                if (contentLength < 0 || contentLength > maximumSize)
                    throw Error("Update metadata response exceeded its byte limit")
            }
        } catch as err {
            if InStr(err.Message, "exceeded its byte limit")
                throw
            ; Chunked responses legitimately omit Content-Length. The decoded body
            ; still receives the same bound immediately after completion.
        }
        body := request.ResponseText
        if (StrPut(body, "UTF-8") - 1 > maximumSize)
            throw Error("Update metadata response exceeded its byte limit")
        return body
    }
}

class WinHttpTextRequest {
    __New(request, onComplete, onError, maximumSize) {
        this.request := request
        this.onComplete := onComplete
        this.onError := onError
        this.done := false
        this.pollTimer := 0
        this.startedAt := 0
        this.maximumSize := maximumSize
    }

    Start() {
        try {
            this.startedAt := this.NowMilliseconds()
            this.request.Send()
            this.pollTimer := ObjBindMethod(this, "Poll")
            SetTimer(this.pollTimer, 50)
            return this
        } catch as err {
            this.Fail(err)
            return 0
        }
    }

    Poll() {
        if this.done
            return
        try {
            if !this.request.WaitForResponse(0) {
                maxDuration := WinHttpTransport.resolveTimeoutMs
                    + WinHttpTransport.connectTimeoutMs
                    + WinHttpTransport.sendTimeoutMs
                    + WinHttpTransport.receiveTimeoutMs
                    + 2000
                if (this.NowMilliseconds() - this.startedAt > maxDuration)
                    this.Fail(Error("WinHTTP asynchronous request timed out"))
                return
            }
            response := {
                status: this.request.Status,
                body: WinHttpTransport.ReadBoundedTextResponse(
                    this.request,
                    this.maximumSize
                )
            }
        } catch as err {
            this.Fail(err)
            return
        }

        callback := this.onComplete
        this.Disconnect()
        try callback.Call(response)
        catch as err {
            OutputDebug("Asynchronous update completion failed: " err.Message)
        }
    }

    Fail(error) {
        if this.done
            return
        callback := this.onError
        this.Disconnect()
        try callback.Call(error)
        catch as err {
            OutputDebug("Asynchronous update error handling failed: " err.Message)
        }
    }

    Disconnect() {
        if this.done
            return
        this.done := true
        if this.pollTimer {
            SetTimer(this.pollTimer, 0)
            this.pollTimer := 0
        }
        this.request := 0
        this.onComplete := 0
        this.onError := 0
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }

    Cancel() {
        if this.done
            return
        request := this.request
        this.Disconnect()
        try request.Abort()
    }
}

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
    ; The composition root supplies the authoritative two-phase shutdown owner.
    ; Tests may leave this unset and exercise the legacy clinical probe directly.
    static shutdownCoordinator := 0
    static maxUpdateSizeBytes := 100 * 1024 * 1024
    static maxMetadataSizeBytes := 1024 * 1024
    static maxReleaseNotesCharacters := 20000
    static installProbeSequence := 0

    static updateTimer := 0
    static activeRequest := 0
    static cleanupTimer := 0
    static skippedVersion := ""  ; Track which version the user chose to skip
    static lastRemindTime := 0   ; Track when the user last clicked "Remind Me Later"
    static pendingUpdateInfo := 0
    static notifiedVersion := ""
    static updateDialog := 0
    static updateAvailableNotifier := (text, title, options) => TrayTip(text, title, options)
    static manualResultNotifier := (text, title, options) => MsgBox(text, title, options)
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
            SetTimer(this.updateTimer, 3600000)  ; Check every hour (3600000 ms)
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
        if (HasProp(slot, "manual") && slot.manual && !cancelManualCheck)
            return
        this.activeRequest := 0
        slot.completed := true
        handle := slot.handle
        slot.handle := 0
        if handle
            try handle.Cancel()
    }

    static BeginAutoCheck(force := false) {
        if this.activeRequest
            return false
        if (!force && !this.updateCheckEligibleProbe.Call())
            return false

        stableOnly := Settings.Get("SkipBetaVersions")
        url := stableOnly ? this.latestStableUrl : this.newestReleaseUrl
        slot := {handle: 0, completed: false}
        this.activeRequest := slot

        try {
            slot.handle := this.transport.GetTextAsync(
                url,
                ObjBindMethod(this, "CompleteAutoCheck", slot, stableOnly),
                ObjBindMethod(this, "FailAutoCheck", slot),
                this.maxMetadataSizeBytes
            )
        } catch as err {
            slot.completed := true
            slot.handle := 0
            if (this.activeRequest = slot)
                this.activeRequest := 0
            OutputDebug("Update check failed: " err.Message)
            return false
        }

        if !slot.handle {
            if (this.activeRequest = slot)
                this.activeRequest := 0
            return false
        }
        return true
    }

    static CompleteAutoCheck(slot, stableOnly, response) {
        if slot.completed
            return
        slot.completed := true
        slot.handle := 0
        if (this.activeRequest = slot)
            this.activeRequest := 0

        try {
            updateInfo := this.ProcessReleaseResponse(response, stableOnly)
            if updateInfo.hasUpdate
                this.RecordAvailableUpdate(updateInfo)
        } catch as err {
            OutputDebug("Update check failed: " err.Message)
        }
    }

    static FailAutoCheck(slot, error) {
        if slot.completed
            return
        slot.completed := true
        slot.handle := 0
        if (this.activeRequest = slot)
            this.activeRequest := 0
        message := IsObject(error) && HasProp(error, "Message") ? error.Message : String(error)
        OutputDebug("Update check failed: " message)
    }
    
    static OnSettingsChanged() {
        ; Reconfigure only the automatic schedule. A manual check is a user-visible
        ; operation and must complete (or explicitly report failure), never vanish
        ; because an unrelated setting was saved while its request was in flight.
        this.LoadSkippedVersion()
        if (IsObject(this.pendingUpdateInfo)
            && !this.UpdateInfoIsEligible(this.pendingUpdateInfo)) {
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
            "PACS Assistant update available",
            "Iconi"
        )
    }

    static LoadSkippedVersion() {
        this.skippedVersion := Settings.Get("SkippedUpdateVersion")
        return this.skippedVersion
    }

    /**
     * Commits every preference represented by one update-dialog action as a single
     * settings transaction. The optional skipped version belongs in that same batch:
     * the user clicked one button, so a disk failure must preserve all prior values.
     */
    static SaveUpdatePreferences(autoUpdate, skipBetaVersions, skippedVersion?, replacer?) {
        values := Map(
            "AutoUpdate", autoUpdate ? true : false,
            "SkipBetaVersions", skipBetaVersions ? true : false
        )
        if IsSet(skippedVersion) {
            if (Type(skippedVersion) != "String" || Trim(skippedVersion) = "")
                throw ValueError("Skipped update version must be a non-empty string")
            values["SkippedUpdateVersion"] := skippedVersion
        }

        if IsSet(replacer)
            Settings.SaveValues(values, replacer)
        else
            Settings.SaveValues(values)

        if IsSet(skippedVersion)
            this.skippedVersion := skippedVersion
        return true
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
        } catch as err {
            MsgBox(
                (InStr(err.Message, "Settings changed")
                    ? "Settings changed while this update dialog was open. Reopen it before saving preferences."
                    : "The update preferences could not be saved. The previous settings were left unchanged.`n`n" err.Message),
                InStr(err.Message, "Settings changed") ? "Settings Changed" : "Save Failed",
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
            throw Error("Release notes exceed the display limit")

        return {
            version: release["tag_name"],
            isPrerelease: release["prerelease"] ? true : false,
            notes: notes,
            downloadUrl: downloadUrl,
            assetSize: size,
            assetSha256: StrLower(digestMatch[1])
        }
    }

    static IsTrustedDownloadUrl(url) {
        return Type(url) = "String"
            && RegExMatch(
                url,
                "i)^https://github\.com/rakan959/pacs-assistant/releases/download/[^/?#]+/pacs-assistant\.exe$"
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

    static ProcessReleaseResponse(response, stableOnly) {
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
        if !this.UpdateInfoIsEligible(updateInfo)
            return { hasUpdate: false }

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
            && (DllCall("GetTickCount64", "UInt64") - this.lastRemindTime) < 14400000)
            return false
        return this.CompareVersions(this.currentVersion, updateInfo.latestVersion) < 0
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

        stableOnly := Settings.Get("SkipBetaVersions")
        url := stableOnly ? this.latestStableUrl : this.newestReleaseUrl
        slot := {handle: 0, completed: false, manual: true}
        this.activeRequest := slot
        try {
            slot.handle := this.transport.GetTextAsync(
                url,
                ObjBindMethod(this, "CompleteManualCheck", slot, stableOnly),
                ObjBindMethod(this, "FailManualCheck", slot),
                this.maxMetadataSizeBytes
            )
        } catch as err {
            slot.completed := true
            slot.handle := 0
            if (this.activeRequest = slot)
                this.activeRequest := 0
            this.manualResultNotifier.Call(
                "The update check could not start: " err.Message,
                "Update Check Failed",
                "Icon!"
            )
            return false
        }
        if !slot.handle {
            if (this.activeRequest = slot)
                this.activeRequest := 0
            if !slot.completed {
                this.manualResultNotifier.Call(
                    "The update check could not start.",
                    "Update Check Failed",
                    "Icon!"
                )
            }
            return false
        }
        try this.updateAvailableNotifier.Call(
            "Checking GitHub for a PACS Assistant update...",
            "Checking for updates",
            "Iconi"
        )
        return true
    }

    static CompleteManualCheck(slot, stableOnly, response) {
        if slot.completed
            return
        slot.completed := true
        slot.handle := 0
        if (this.activeRequest = slot)
            this.activeRequest := 0
        try {
            updateInfo := this.ProcessReleaseResponse(response, stableOnly)
            if !updateInfo.hasUpdate {
                this.manualResultNotifier.Call(
                    "PACS Assistant is up to date.",
                    "No Update Available",
                    "Iconi"
                )
                return
            }
            this.pendingUpdateInfo := updateInfo
            if this.clinicalActivityProbe.Call() {
                this.updateAvailableNotifier.Call(
                    "The update is ready to review after the active clinical command finishes.",
                    "PACS Assistant update available",
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

    static FailManualCheck(slot, error) {
        if slot.completed
            return
        slot.completed := true
        slot.handle := 0
        if (this.activeRequest = slot)
            this.activeRequest := 0
        message := IsObject(error) && HasProp(error, "Message")
            ? error.Message
            : String(error)
        this.manualResultNotifier.Call(
            "The update check failed: " message,
            "Update Check Failed",
            "Icon!"
        )
    }
    
    /**
     * Shows the update dialog.
     * @param updateInfo Result of an earlier CheckForUpdates call. Callers that
     * already checked pass theirs; asking again cost a second HTTP round trip against
     * an unauthenticated 60/hour GitHub limit, and could return a different answer -
     * the rate-limit and remind-later gates would suppress a dialog the first call had
     * already authorised.
     */
    static ShowUpdateDialog(updateInfo?) {
        fromCache := !IsSet(updateInfo)
        if !IsSet(updateInfo) {
            if (IsObject(this.pendingUpdateInfo) && this.pendingUpdateInfo.hasUpdate)
                updateInfo := this.pendingUpdateInfo
            else
                return this.BeginManualCheck()
        }
        if !this.UpdateInfoIsEligible(updateInfo) {
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
        if this.UpdateDialogIsLive() {
            try WinActivate("ahk_id " this.updateDialog.Hwnd)
            return this.updateDialog
        }
            
        ; Create update dialog with modern styling
        updateGui := Gui(, "PACS Assistant - Update Available")
        updateGui.settingsRevision := Settings.revision
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
        
        ; Persisting the two checkboxes has to happen on every way out of the dialog.
        ; It used to live only in the Close handler, and Gui.Destroy() does not raise
        ; Close - so every button discarded the user's choices.
        saveChoices := (*) => this.TrySaveUpdatePreferences(
            updateGui.settingsRevision,
            autoUpdateCheckbox.Value,
            skipBetaCheckbox.Value
        )
        saveSkippedChoices := (*) => this.TrySaveUpdatePreferences(
            updateGui.settingsRevision,
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
            saveChoices() && (
                this.lastRemindTime := DllCall("GetTickCount64", "UInt64"),
                this.CloseUpdateDialog(updateGui)
            )
        ))
        updateGui.Add("Button", "x+10 w120", "Skip This Version").OnEvent("Click", (*) => (
            saveSkippedChoices() && this.CloseUpdateDialog(updateGui)
        ))

        updateGui.OnEvent("Close", dismiss)

        this.updateDialog := updateGui
        updateGui.Show()
        return updateGui
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
            if !inputFile
                throw OSError(A_LastError, , "Could not open update for hashing")
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
            if !executableFile
                return false

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
        } catch {
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

        try fileVersion := this.ParseVersion(FileGetVersion(path))
        catch {
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
                probePath := A_ScriptDir "\.pacs-assistant-update-probe-" suffix ".tmp"
                movedPath := probePath ".moved"
            } until !FileExist(probePath) && !FileExist(movedPath)

            ; In-place update needs directory create, write, rename, and delete
            ; permission. Probe that complete contract before acquiring shutdown or
            ; downloading an executable that cannot be installed.
            probeFile := FileOpen(probePath, "w")
            if !probeFile
                return false
            probeFile.Write("PACS Assistant update write probe")
            probeFile.Close()
            probeFile := 0
            FileMove(probePath, movedPath, false)
            FileDelete(movedPath)
            return true
        } catch {
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

    static BuildUpdaterScript() {
        script := "
        (
        $ParentPid = [int]$args[0]
        $CurrentExe = [string]$args[1]
        $NewExe = [string]$args[2]
        $BackupExe = [string]$args[3]

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

            throw $UpdateError
        } finally {
            Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
        }
        )"
        return script
    }

    static CleanupUpdateArtifacts() {
        for name in this.OwnedUpdateArtifactNames() {
            path := A_ScriptDir "\" name
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
        shutdownStarted := false
        if IsObject(this.shutdownCoordinator) {
            if !this.shutdownCoordinator.BeginShutdown("install the update")
                return false
            shutdownStarted := true
        } else if this.clinicalActivityProbe.Call() {
            MsgBox(
                "Wait for the active clinical command to finish before updating PACS Assistant.",
                "Clinical Command In Progress",
                "Icon!"
            )
            return false
        }
        currentExe := ""
        backupExe := ""
        newExe := ""
        updaterPath := ""
        try {
            ; Every operation after acquiring the shutdown lease belongs inside this
            ; recovery boundary. Even allocating a GUID-backed temporary path can
            ; fail, and must release the lease rather than blocking the app forever.
            currentExe := A_ScriptFullPath
            backupExe := A_ScriptDir "\pacs-assistant.backup.exe"
            newExe := A_ScriptDir "\pacs-assistant.new.exe"
            updaterPath := this.CreateUpdaterPath()
            this.CancelUpdateArtifactCleanup()
            if !A_IsCompiled
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
            powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
            command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'
                . updaterPath '" ' DllCall("GetCurrentProcessId")
                . ' "' currentExe '" "' newExe '" "' backupExe '"'
            Run(command, A_ScriptDir, "Hide")
            updateGui.Destroy()
            if shutdownStarted
                return this.shutdownCoordinator.CompleteShutdown()
            ExitApp
        } catch as err {
            if shutdownStarted
                this.shutdownCoordinator.CancelShutdown()
            MsgBox("Update failed: " err.Message, "Error", "Icon!")
            ; The running executable is not touched until the updater starts after
            ; ExitApp, so a preflight failure only needs to remove staged artifacts.
            if (newExe != "")
                try FileDelete(newExe)
            if (updaterPath != "")
                try FileDelete(updaterPath)
            this.ScheduleUpdateArtifactCleanup()
            return false
        }
    }
}
