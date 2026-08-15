#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class UpdateCheckerTest {
    static Tests := [
        "TestVersionParsing",
        "TestVersionComparison",
        "TestVersionPrecedenceTable",
        "TestVersionEquivalence",
        "TestAutoCheckTimerRespectsSettings",
        "TestSettingsChangeRestartsTimer",
        "TestAutomaticCheckUsesAsyncTransport",
        "TestAutomaticCheckNeverOpensAnActivatingDialog",
        "TestManualCheckIsAsyncAndReportsNoUpdate",
        "TestManualCompletionDefersDialogDuringClinicalCommand",
        "TestAsyncRequestDisconnectBreaksCallbackOwnership",
        "TestSettingsChangeCancelsInFlightAutomaticCheck",
        "TestClinicalCommandBlocksUpdateExit",
        "TestVersionComesFromAppVersion",
        "TestJsonParserHandlesEscapesAndUnicode",
        "TestJsonParserRejectsUppercaseTokensAndEscapes",
        "TestReleaseParserKeepsAssetMetadataTogether",
        "TestReleaseParserAcceptsArrayResponse",
        "TestReleaseParserRejectsOversizedAsset",
        "TestReleaseStatusDistinguishesExpectedAbsenceFromFailure",
        "TestDownloadUrlMustBelongToThisRepository",
        "TestSha256KnownVector",
        "TestArtifactValidationRejectsNonExecutable",
        "TestUpdaterScriptRequiresHealthyRelaunch",
        "TestUpdaterScriptRecoversAfterPreSwapFailure",
        "TestUpdaterUsesPrivateTemporaryScript",
        "TestCleanupDoesNotOwnGenericScript",
        "TestUpdateDialogPreferencesCommitTogether",
        "TestUpdateDialogPreferenceFailurePreservesEveryValue",
        "TestStaleUpdateDialogCannotOverwriteNewerSettings",
        "TestSkippedVersionPersistsAcrossReload"
    ]

    Setup() {
        this.originalSettingsFile := Settings.settingsFile
        this.tempSettings := A_Temp "\update_settings_" A_TickCount ".ini"
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()
        this.originalTransport := UpdateChecker.transport
        this.originalClinicalActivityProbe := UpdateChecker.clinicalActivityProbe
        this.originalShutdownCoordinator := UpdateChecker.shutdownCoordinator
        this.originalUpdateCheckEligibleProbe := UpdateChecker.updateCheckEligibleProbe
        this.originalUpdateAvailableNotifier := UpdateChecker.updateAvailableNotifier
        this.originalManualResultNotifier := UpdateChecker.manualResultNotifier
        this.originalPendingUpdateInfo := UpdateChecker.pendingUpdateInfo
        this.originalNotifiedVersion := UpdateChecker.notifiedVersion
        this.originalUpdateDialog := UpdateChecker.updateDialog
        UpdateChecker.shutdownCoordinator := 0
        UpdateChecker.updateCheckEligibleProbe := (*) => true
        this.updateNotifications := []
        this.manualNotifications := []
        UpdateChecker.updateAvailableNotifier := (text, title, options) => this.updateNotifications.Push({
            text: text,
            title: title,
            options: options
        })
        UpdateChecker.manualResultNotifier := (text, title, options) => this.manualNotifications.Push({
            text: text,
            title: title,
            options: options
        })
        UpdateChecker.pendingUpdateInfo := 0
        UpdateChecker.notifiedVersion := ""
        UpdateChecker.updateDialog := 0
        UpdateChecker.activeRequest := 0
    }
    
    TestVersionParsing() {
        v1 := UpdateChecker.ParseVersion("v1.9")
        Assert.Equal(1, v1.major)
        Assert.Equal(9, v1.minor)
        Assert.Equal(0, v1.patch)
        Assert.False(v1.isPrerelease)

        v2 := UpdateChecker.ParseVersion("v2.0b4")
        Assert.Equal(2, v2.major)
        Assert.Equal(0, v2.minor)
        Assert.Equal(0, v2.patch)
        Assert.True(v2.isPrerelease)

        v3 := UpdateChecker.ParseVersion("v2.1.3-beta.4")
        Assert.Equal(2, v3.major)
        Assert.Equal(1, v3.minor)
        Assert.Equal(3, v3.patch)
        Assert.Equal("beta.4", v3.prerelease)
    }

    TestVersionComparison() {
        Assert.Equal(-1, UpdateChecker.CompareVersions("v1.9", "v2.0"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.1", "v2.0"))
        Assert.Equal(0, UpdateChecker.CompareVersions("v2.0", "v2.0"))

        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b1", "v2.0b2"))
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b", "v2.0"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.0", "v2.0b"))

        ; Patch releases used to compare equal, so nobody was ever offered one
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0.1", "v2.0.2"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.0.9", "v2.0.1"))

        ; SemVer prereleases
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.1.0-beta.1", "v2.1.0"))
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.1.0-beta.2", "v2.1.0-beta.10"))

        ; An install on the old scheme must see the first SemVer release as an update
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b7", "v2.1.0"))
    }

    ; Each pair is {older, newer} and is asserted in both directions
    TestVersionPrecedenceTable() {
        ordered := [
            ["v1.9.0", "v2.0.0"],
            ["v2.0.0", "v2.1.0"],
            ; Patch releases. The previous parser read only major and minor, so these
            ; compared equal and a patch update was never offered to anyone.
            ["v2.0.1", "v2.0.2"],
            ["v2.0.1", "v2.0.9"],
            ["v2.0.9", "v2.0.10"],
            ; A prerelease ranks below its release
            ["v2.1.0-beta.1", "v2.1.0"],
            ["v2.1.0-beta.1", "v2.1.0-beta.2"],
            ["v2.1.0-beta.2", "v2.1.0-beta.10"],
            [
                "v2.1.0-alpha.2",
                "v2.1.0-alpha.99999999999999999999999999999999999999999999999999"
            ],
            ["v2.1.0-alpha.1", "v2.1.0-beta.1"],
            ["v2.1.0-beta", "v2.1.0-beta.1"],
            ; Numeric identifiers rank below alphanumeric ones
            ["v2.1.0-1", "v2.1.0-alpha"],
            ; Legacy tags order among themselves
            ["v2.0b4", "v2.0b7"],
            ["v2.0b9", "v2.0b10"],
            ["v2.0b", "v2.0b1"],
            ["v2.0b7", "v2.0"],
            ["v1.0", "v2.0b1"],
            ; ... and against the SemVer tags replacing them, so an install on the old
            ; scheme still sees the first SemVer release as an update
            ["v2.0b7", "v2.1.0"],
            ["v2.0b7", "v2.1.0-beta.1"],
            ["v2.0b4", "v2.0.1"]
        ]

        for pair in ordered {
            Assert.Equal(-1, UpdateChecker.CompareVersions(pair[1], pair[2]),
                "Expected '" pair[1] "' < '" pair[2] "'")
            Assert.Equal(1, UpdateChecker.CompareVersions(pair[2], pair[1]),
                "Expected '" pair[2] "' > '" pair[1] "'")
        }
    }

    TestVersionEquivalence() {
        equal := [
            ["v2.0.0", "v2.0.0"],
            ["v2.0.0", "2.0.0"],
            ["v2.1.0-beta.1", "v2.1.0-beta.1"],
            ; Build metadata takes no part in precedence
            ["v2.1.0+abc123", "v2.1.0"],
            ; The short forms mean the same thing
            ["v2.0", "v2.0.0"]
        ]

        for pair in equal {
            Assert.Equal(0, UpdateChecker.CompareVersions(pair[1], pair[2]),
                "Expected '" pair[1] "' == '" pair[2] "'")
        }
    }

    ; The version is read from the CI-generated file, so it is stated in exactly one
    ; place and cannot drift from the tag it was built from
    TestVersionComesFromAppVersion() {
        Assert.Equal(AppVersion.current, UpdateChecker.currentVersion)
    }

    TestJsonParserHandlesEscapesAndUnicode() {
        parsed := JsonParser.Parse('{"text":"line 1\nquote: \"ok\"; slash: \\n; smile: \u263A; emoji: \uD83D\uDE00"}')
        Assert.Equal("line 1`nquote: `"ok`"; slash: \n; smile: " Chr(0x263A) "; emoji: " Chr(0x1F600), parsed["text"])
    }

    TestJsonParserRejectsUppercaseTokensAndEscapes() {
        invalidCases := [
            {input: "TRUE", error: "Expected a JSON value"},
            {input: "False", error: "Expected a JSON value"},
            {input: "NULL", error: "Expected a JSON value"},
            {input: '"\N"', error: "Invalid JSON escape sequence"},
            {input: '"\U263A"', error: "Invalid JSON escape sequence"}
        ]
        for invalidCase in invalidCases {
            Assert.Throws(
                ObjBindMethod(this, "ParseInvalidJson", invalidCase.input),
                invalidCase.error,
                "Invalid JSON was accepted: " invalidCase.input
            )
        }
    }

    ParseInvalidJson(input) {
        return JsonParser.Parse(input)
    }

    TestReleaseParserKeepsAssetMetadataTogether() {
        json := '{"tag_name":"v2.2.0","body":"Line 1\nLine 2","assets":['
            . '{"name":"notes.txt","size":12,"digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/notes.txt"},'
            . '{"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":1550000,"name":"pacs-assistant.exe"}'
            . ']}'

        release := UpdateChecker.ParseReleaseResponse(json)

        Assert.Equal("v2.2.0", release.version)
        Assert.Equal("Line 1`nLine 2", release.notes)
        Assert.Equal(1550000, release.assetSize)
        Assert.Equal("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", release.assetSha256)
        Assert.True(InStr(release.downloadUrl, "/pacs-assistant.exe") > 0)
    }

    TestReleaseParserAcceptsArrayResponse() {
        json := '[{"tag_name":"v2.2.0-beta.1","body":"Beta","assets":['
            . '{"name":"pacs-assistant.exe","size":42,"digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0-beta.1/pacs-assistant.exe"}'
            . ']}]'

        release := UpdateChecker.ParseReleaseResponse(json)
        Assert.Equal("v2.2.0-beta.1", release.version)
        Assert.Equal(42, release.assetSize)
    }

    TestReleaseParserRejectsOversizedAsset() {
        size := UpdateChecker.maxUpdateSizeBytes + 1
        json := '{"tag_name":"v9.0.0","body":"Large","assets":['
            . '{"name":"pacs-assistant.exe","size":' size
            . ',"digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"'
            . ',"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v9.0.0/pacs-assistant.exe"}'
            . ']}'

        Assert.Throws(
            (*) => UpdateChecker.ParseReleaseResponse(json),
            "invalid size"
        )
    }

    TestReleaseStatusDistinguishesExpectedAbsenceFromFailure() {
        Assert.True(UpdateChecker.ReleaseResponseAvailable(200, true))
        Assert.False(UpdateChecker.ReleaseResponseAvailable(404, true))
        Assert.Throws(
            () => UpdateChecker.ReleaseResponseAvailable(403, true),
            "HTTP 403"
        )
        Assert.Throws(
            () => UpdateChecker.ReleaseResponseAvailable(503, false),
            "HTTP 503"
        )
        Assert.Throws(
            () => UpdateChecker.ReleaseResponseAvailable(404, false),
            "HTTP 404"
        )
    }

    TestDownloadUrlMustBelongToThisRepository() {
        Assert.True(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "http://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/attacker/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/other.exe"
        ))
    }

    TestSha256KnownVector() {
        path := A_Temp "\pacs_sha256_" A_TickCount ".txt"
        FileAppend("abc", path, "UTF-8-RAW")
        try {
            Assert.Equal(
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                UpdateChecker.HashFileSha256(path)
            )
        } finally {
            try FileDelete(path)
        }
    }

    TestArtifactValidationRejectsNonExecutable() {
        path := A_Temp "\pacs_bad_update_" A_TickCount ".exe"
        FileAppend("not an executable", path, "UTF-8-RAW")
        try {
            digest := UpdateChecker.HashFileSha256(path)
            Assert.False(UpdateChecker.ValidateDownloadedArtifact(path, FileGetSize(path), digest, "v2.2.0"))
        } finally {
            try FileDelete(path)
        }
    }

    TestUpdaterScriptRequiresHealthyRelaunch() {
        script := UpdateChecker.BuildUpdaterScript()
        Assert.True(InStr(script, "Start-Process -FilePath $CurrentExe -PassThru") > 0)
        Assert.True(InStr(script, "Start-Sleep -Seconds 5") > 0)
        Assert.True(InStr(script, "$newProcess.HasExited") > 0)
    }

    TestUpdaterScriptRecoversAfterPreSwapFailure() {
        script := UpdateChecker.BuildUpdaterScript()

        Assert.True(InStr(script, "$ParentExited = $false") > 0)
        Assert.True(InStr(script, "$RecoveryLaunched = $false") > 0)
        Assert.True(InStr(script, "$RecoveryReady = $false") > 0)
        Assert.True(InStr(script, "if ($ParentExited -and -not $RecoveryLaunched)") > 0)
        Assert.True(InStr(script, "Start-Process -FilePath $CurrentExe") > 0)
    }

    TestUpdaterUsesPrivateTemporaryScript() {
        path := UpdateChecker.CreateUpdaterPath()

        Assert.True(InStr(path, A_Temp "\pacs-assistant-updater-") = 1)
        Assert.False(path = A_ScriptDir "\update.ps1")
    }

    TestCleanupDoesNotOwnGenericScript() {
        names := UpdateChecker.OwnedUpdateArtifactNames()

        for name in names
            Assert.False(name = "update.ps1")
        Assert.Equal(2, names.Length)
    }

    TestUpdateDialogPreferencesCommitTogether() {
        UpdateChecker.SaveUpdatePreferences(false, false, "v2.3.0")

        Assert.False(Settings.Get("AutoUpdate"))
        Assert.False(Settings.Get("SkipBetaVersions"))
        Assert.Equal("v2.3.0", Settings.Get("SkippedUpdateVersion"))
        Assert.Equal("v2.3.0", UpdateChecker.skippedVersion)
    }

    TestUpdateDialogPreferenceFailurePreservesEveryValue() {
        before := FileRead(Settings.settingsFile)

        Assert.Throws(
            () => UpdateChecker.SaveUpdatePreferences(
                false,
                false,
                "v2.3.0",
                FailUpdatePreferenceReplace
            ),
            "simulated update preference replace failure"
        )

        Assert.Equal(before, FileRead(Settings.settingsFile))
        Assert.True(Settings.Get("AutoUpdate"))
        Assert.True(Settings.Get("SkipBetaVersions"))
        Assert.Equal("", Settings.Get("SkippedUpdateVersion"))
        Assert.Equal("", UpdateChecker.skippedVersion)
    }

    TestStaleUpdateDialogCannotOverwriteNewerSettings() {
        capturedRevision := Settings.revision
        Settings.Set("AutoUpdate", false)

        result := UpdateChecker.TrySaveUpdatePreferences(
            capturedRevision,
            true,
            false
        )

        Assert.False(result)
        Assert.False(Settings.Get("AutoUpdate"))
        Assert.True(Settings.Get("SkipBetaVersions"))
    }

    TestSkippedVersionPersistsAcrossReload() {
        UpdateChecker.SaveUpdatePreferences(true, true, "v2.2.0")
        UpdateChecker.skippedVersion := ""

        UpdateChecker.LoadSkippedVersion()

        Assert.Equal("v2.2.0", UpdateChecker.skippedVersion)
        Assert.Equal("v2.2.0", Settings.Get("SkippedUpdateVersion"))
    }
    
    TestAutoCheckTimerRespectsSettings() {
        Settings.Set("AutoUpdate", true)
        UpdateChecker.StartAutoCheck()
        Assert.True(UpdateChecker.updateTimer != 0)
        
        Settings.Set("AutoUpdate", false)
        UpdateChecker.StartAutoCheck()
        Assert.Equal(0, UpdateChecker.updateTimer)
    }
    
    TestSettingsChangeRestartsTimer() {
        Settings.Set("AutoUpdate", true)
        UpdateChecker.StartAutoCheck()
        UpdateChecker.OnSettingsChanged()
        Assert.True(UpdateChecker.updateTimer != 0)
    }

    TestAutomaticCheckUsesAsyncTransport() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        Settings.Set("SkipBetaVersions", true)

        Assert.True(UpdateChecker.BeginAutoCheck(true))
        Assert.Equal(1, transport.asyncCalls)
        Assert.Equal(0, transport.syncCalls)
        Assert.True(UpdateChecker.activeRequest != 0)

        transport.Resolve({status: 404, body: ""})
        Assert.Equal(0, UpdateChecker.activeRequest)
    }

    TestAutomaticCheckNeverOpensAnActivatingDialog() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        Settings.Set("SkipBetaVersions", true)
        Assert.True(UpdateChecker.BeginAutoCheck(true))
        slot := UpdateChecker.activeRequest

        transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})

        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(0, slot.handle)
        Assert.True(IsObject(UpdateChecker.pendingUpdateInfo))
        Assert.Equal("v9.0.0", UpdateChecker.pendingUpdateInfo.latestVersion)
        Assert.Equal(0, UpdateChecker.updateDialog)
        Assert.Equal(1, this.updateNotifications.Length)
    }

    TestManualCheckIsAsyncAndReportsNoUpdate() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        Settings.Set("SkipBetaVersions", true)

        Assert.True(UpdateChecker.ShowUpdateDialog())
        Assert.Equal(1, transport.asyncCalls)
        Assert.Equal(0, transport.syncCalls)
        transport.Resolve({status: 404, body: ""})

        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(1, this.manualNotifications.Length)
        Assert.True(InStr(this.manualNotifications[1].text, "up to date") > 0)
    }

    TestManualCompletionDefersDialogDuringClinicalCommand() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        UpdateChecker.clinicalActivityProbe := (*) => false
        Assert.True(UpdateChecker.BeginManualCheck())
        UpdateChecker.clinicalActivityProbe := (*) => true

        transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})

        Assert.Equal(0, UpdateChecker.updateDialog)
        Assert.True(IsObject(UpdateChecker.pendingUpdateInfo))
        Assert.True(this.updateNotifications.Length >= 2)
    }

    TestAsyncRequestDisconnectBreaksCallbackOwnership() {
        operation := WinHttpTextRequest(
            FakeWinHttpRequest(),
            (*) => 0,
            (*) => 0
        )

        operation.Disconnect()

        Assert.Equal(0, operation.request)
        Assert.Equal(0, operation.onComplete)
        Assert.Equal(0, operation.onError)
    }

    TestSettingsChangeCancelsInFlightAutomaticCheck() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        Settings.Set("AutoUpdate", true)
        Assert.True(UpdateChecker.BeginAutoCheck(true))

        Settings.Set("AutoUpdate", false)
        UpdateChecker.OnSettingsChanged()

        Assert.True(transport.handle.cancelled)
        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(0, UpdateChecker.updateTimer)
    }

    TestClinicalCommandBlocksUpdateExit() {
        transport := CountingDownloadTransport()
        UpdateChecker.transport := transport
        coordinator := FakeShutdownCoordinator(false)
        UpdateChecker.shutdownCoordinator := coordinator

        result := UpdateChecker.PerformUpdate({}, {})

        Assert.False(result)
        Assert.Equal(0, transport.downloadCalls)
        Assert.Equal(1, coordinator.beginCalls)
        Assert.Equal(0, coordinator.completeCalls)
    }
    
    Teardown() {
        try UpdateChecker.CancelActiveCheck()
        UpdateChecker.StopAutoCheck()
        UpdateChecker.transport := this.originalTransport
        UpdateChecker.clinicalActivityProbe := this.originalClinicalActivityProbe
        UpdateChecker.shutdownCoordinator := this.originalShutdownCoordinator
        UpdateChecker.updateCheckEligibleProbe := this.originalUpdateCheckEligibleProbe
        UpdateChecker.updateAvailableNotifier := this.originalUpdateAvailableNotifier
        UpdateChecker.manualResultNotifier := this.originalManualResultNotifier
        UpdateChecker.pendingUpdateInfo := this.originalPendingUpdateInfo
        UpdateChecker.notifiedVersion := this.originalNotifiedVersion
        UpdateChecker.updateDialog := this.originalUpdateDialog
        UpdateChecker.skippedVersion := ""
        UpdateChecker.lastRemindTime := 0
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettingsFile
    }
}

class FakeShutdownCoordinator {
    __New(beginResult := true) {
        this.beginResult := beginResult
        this.beginCalls := 0
        this.completeCalls := 0
        this.cancelCalls := 0
    }

    BeginShutdown(*) {
        this.beginCalls++
        return this.beginResult
    }

    CompleteShutdown(*) {
        this.completeCalls++
        return true
    }

    CancelShutdown(*) {
        this.cancelCalls++
    }
}

class FakeAsyncUpdateTransport {
    __New() {
        this.asyncCalls := 0
        this.syncCalls := 0
        this.onComplete := 0
        this.onError := 0
        this.handle := FakeAsyncUpdateHandle()
    }

    GetText(*) {
        this.syncCalls++
        throw Error("synchronous transport must not be used")
    }

    GetTextAsync(url, onComplete, onError) {
        this.asyncCalls++
        this.onComplete := onComplete
        this.onError := onError
        return this.handle
    }

    Resolve(response) {
        this.onComplete.Call(response)
    }
}

class FakeAsyncUpdateHandle {
    __New() {
        this.cancelled := false
    }

    Cancel() {
        this.cancelled := true
    }
}

class FakeWinHttpRequest {
    Abort() {
    }
}

class CountingDownloadTransport {
    __New() {
        this.downloadCalls := 0
    }

    Download(*) {
        this.downloadCalls++
    }
}

FailUpdatePreferenceReplace(*) {
    throw Error("simulated update preference replace failure")
}

UpdateReleaseJson(version) {
    return '{"tag_name":"' version '","body":"Release notes","assets":['
        . '{"name":"pacs-assistant.exe","size":1550000,'
        . '"digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
        . '"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/'
        . version '/pacs-assistant.exe"}'
        . ']}'
}
