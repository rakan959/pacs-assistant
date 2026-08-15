#Requires AutoHotkey v2.0
#Include Settings.ahk
#Include Version.ahk
#Include JsonParser.ahk

/**
 * Bounded GitHub HTTP transport. The synchronous calls remain simple for the timer
 * workflow, while explicit WinHTTP timeouts prevent startup from hanging forever.
 */
class WinHttpTransport {
    static resolveTimeoutMs := 2000
    static connectTimeoutMs := 3000
    static sendTimeoutMs := 5000
    static receiveTimeoutMs := 10000

    CreateRequest(url) {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(
            WinHttpTransport.resolveTimeoutMs,
            WinHttpTransport.connectTimeoutMs,
            WinHttpTransport.sendTimeoutMs,
            WinHttpTransport.receiveTimeoutMs
        )
        request.Open("GET", url, false)
        request.SetRequestHeader("User-Agent", "PACS-Assistant-Update-Checker")
        request.SetRequestHeader("Accept", "application/vnd.github+json")
        return request
    }

    GetText(url) {
        request := this.CreateRequest(url)
        request.Send()
        return {status: request.Status, body: request.ResponseText}
    }

    Download(url, destination) {
        request := this.CreateRequest(url)
        request.Send()
        if (request.Status != 200)
            throw Error("Update download returned HTTP " request.Status)

        stream := ComObject("ADODB.Stream")
        stream.Type := 1  ; binary
        stream.Open()
        try {
            stream.Write(request.ResponseBody)
            stream.SaveToFile(destination, 2)  ; overwrite
        } finally {
            stream.Close()
        }
    }
}

class UpdateChecker {
    ; Read through a property rather than copied into a static, so there is no second
    ; place a version is stated and can drift from the tag
    static currentVersion => AppVersion.current

    static repoUrl := "https://github.com/rakan959/pacs-assistant"

    ; GitHub's own prerelease flag decides what counts as a beta. /releases/latest
    ; excludes prereleases natively; asking for the newest release includes them.
    static latestStableUrl := "https://api.github.com/repos/rakan959/pacs-assistant/releases/latest"
    static newestReleaseUrl := "https://api.github.com/repos/rakan959/pacs-assistant/releases?per_page=1"
    static transport := WinHttpTransport()

    static updateTimer := 0
    static cleanupTimer := 0
    static skippedVersion := ""  ; Track which version the user chose to skip
    static lastRemindTime := 0   ; Track when the user last clicked "Remind Me Later"
    
    static Start() {
        this.LoadSkippedVersion()
        this.ScheduleUpdateArtifactCleanup()
        if !Settings.Get("AutoUpdate")
            return

        ; Check for updates immediately, reusing the result rather than asking again
        updateInfo := this.CheckForUpdates()
        if updateInfo.hasUpdate {
            this.ShowUpdateDialog(updateInfo)
        }

        this.StartAutoCheck()
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
            this.ShowUpdateDialog(updateInfo)
        }
    }
    
    static OnSettingsChanged() {
        ; Restart auto-check with new settings
        this.StartAutoCheck()
    }

    static LoadSkippedVersion() {
        this.skippedVersion := Settings.Get("SkippedUpdateVersion")
        return this.skippedVersion
    }

    static SkipVersion(version) {
        if (Type(version) != "String" || Trim(version) = "")
            throw ValueError("Skipped update version must be a non-empty string")
        Settings.Set("SkippedUpdateVersion", version)
        this.skippedVersion := version
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
    
    ; Compatibility helper retained for callers that hold the contents of one JSON
    ; string literal rather than a complete document.
    static DecodeJsonString(text) {
        return JsonParser.Parse(Chr(34) text Chr(34))
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
        if !(size is Integer) || size <= 0
            throw Error("Release asset has an invalid size")

        notes := "No release notes available."
        if (release.Has("body") && Type(release["body"]) = "String" && release["body"] != "")
            notes := release["body"]

        return {
            version: release["tag_name"],
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
            response := this.transport.GetText(url)

            ; 404 is expected from /releases/latest when every release is a prerelease
            if (response.status = 200) {
                release := this.ParseReleaseResponse(response.body)
                latestVersion := release.version

                ; Check if user chose to skip this version
                if (latestVersion = this.skippedVersion)
                    return { hasUpdate: false }
                    
                ; Check if we should wait before reminding again (4 hours)
                if (this.lastRemindTime && (A_TickCount - this.lastRemindTime) < 14400000)
                    return { hasUpdate: false }
                
                ; Compare versions using comparison logic
                compareResult := this.CompareVersions(this.currentVersion, latestVersion)
                
                if (compareResult < 0) {
                    return {
                        hasUpdate: true,
                        currentVersion: this.currentVersion,
                        latestVersion: latestVersion,
                        downloadUrl: release.downloadUrl,
                        downloadSize: release.assetSize,
                        downloadSha256: release.assetSha256,
                        releaseNotes: release.notes
                    }
                }
            }
        } catch as err {
            ; Log quietly to avoid interrupting the user
            OutputDebug("Update check failed: " err.Message)
        }
        return { hasUpdate: false }
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
        if !IsSet(updateInfo)
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
        
        ; Persisting the two checkboxes has to happen on every way out of the dialog.
        ; It used to live only in the Close handler, and Gui.Destroy() does not raise
        ; Close - so every button discarded the user's choices.
        saveChoices := (*) => (
            Settings.Set("AutoUpdate", autoUpdateCheckbox.Value),
            Settings.Set("SkipBetaVersions", skipBetaCheckbox.Value),
            this.OnSettingsChanged()
        )
        dismiss := (*) => (saveChoices(), updateGui.Destroy())

        ; Buttons
        buttonGroup := updateGui.Add("GroupBox", "y+15 w400 h50")
        updateGui.Add("Button", "xp+10 yp+15 w120", "Update Now").OnEvent("Click", (*) => (
            saveChoices(),
            this.PerformUpdate(updateInfo, updateGui)
        ))
        updateGui.Add("Button", "x+10 w120", "Remind Me Later").OnEvent("Click", (*) => (
            this.lastRemindTime := A_TickCount,  ; Set the remind time
            dismiss()
        ))
        updateGui.Add("Button", "x+10 w120", "Skip This Version").OnEvent("Click", (*) => (
            this.SkipVersion(updateInfo.latestVersion),
            dismiss()
        ))

        updateGui.OnEvent("Close", saveChoices)

        updateGui.Show()
    }
    
    static HashFileSha256(path) {
        algorithm := 0
        hash := 0
        file := 0

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

            file := FileOpen(path, "r")
            if !file
                throw OSError(A_LastError, , "Could not open update for hashing")
            readBuffer := Buffer(1024 * 1024)
            while (bytesRead := file.RawRead(readBuffer)) {
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
            if IsObject(file)
                file.Close()
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
            file := FileOpen(path, "r")
            if !file
                return false

            signature := Buffer(2)
            if (file.RawRead(signature) != 2 || NumGet(signature, 0, "UShort") != 0x5A4D)
                return false

            file.Pos := 0x3C
            offsetBuffer := Buffer(4)
            if (file.RawRead(offsetBuffer) != 4)
                return false
            peOffset := NumGet(offsetBuffer, 0, "UInt")
            if (peOffset < 64 || peOffset + 4 > size)
                return false

            file.Pos := peOffset
            peSignature := Buffer(4)
            return file.RawRead(peSignature) = 4
                && NumGet(peSignature, 0, "UInt") = 0x00004550
        } catch {
            return false
        } finally {
            if IsSet(file) && IsObject(file)
                file.Close()
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
        currentExe := A_ScriptFullPath
        backupExe := A_ScriptDir "\pacs-assistant.backup.exe"
        newExe := A_ScriptDir "\pacs-assistant.new.exe"
        updaterPath := this.CreateUpdaterPath()

        try {
            this.CancelUpdateArtifactCleanup()
            if !A_IsCompiled
                throw Error("Automatic update is only available in the compiled application")
            if !this.IsTrustedDownloadUrl(updateInfo.downloadUrl)
                throw Error("The release download URL is not trusted")
            if (FileExist(newExe))
                FileDelete(newExe)
            if (FileExist(updaterPath))
                throw Error("The private updater script path already exists")

            this.transport.Download(updateInfo.downloadUrl, newExe)
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
            ExitApp
        } catch as err {
            MsgBox("Update failed: " err.Message, "Error", "Icon!")
            ; The running executable is not touched until the updater starts after
            ; ExitApp, so a preflight failure only needs to remove staged artifacts.
            try FileDelete(newExe)
            try FileDelete(updaterPath)
            this.ScheduleUpdateArtifactCleanup()
        }
    }
}
