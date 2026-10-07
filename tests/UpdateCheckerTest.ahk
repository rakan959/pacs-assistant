; = CONTENTS
;   + Preamble
;   + UpdateCheckerTest class (version parsing, auto/manual checks, update dialog,
;       install sequence, install-path and updater-script handling; trust checks are
;       in UpdateVerificationTest)
;   + Test doubles (transports, shutdown coordinator, json/info helpers)

#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk
#Include SettingsFixture.ahk
#Include FakePresentationLease.ahk
#Include LogCapture.ahk

class UpdateCheckerTest {
    static tests := [
        "TestVersionParsing",
        "TestVersionPrecedenceTable",
        "TestVersionEquivalence",
        "TestAutoCheckTimerRespectsSettings",
        "TestAutomaticCheckFailuresAreLoggedOncePerOutage",
        "TestRemindLaterDefersOnlyTheAutomaticNotice",
        "TestRemindLaterAnnouncesTheVersionAgainAfterTheDelay",
        "TestManualCheckReportsASkippedVersion",
        "TestSettingsChangeKeepsAnUpdateDeferredByRemindLater",
        "TestSettingsChangeRestartsTimer",
        "TestChecksRecordTheirOutcomeForStatus",
        "TestAutomaticCheckUsesAsyncTransport",
        "TestOnlyCompiledReleaseBuildsCheckForUpdates",
        "TestSynchronousAsyncFailureIsNotReportedAsStarted",
        "TestRequestWithoutAHandleIsReportedAsNotStarted",
        "TestAutomaticCheckNeverOpensAnActivatingDialog",
        "TestManualCheckIsAsyncAndReportsNoUpdate",
        "TestSettingsChangeDoesNotSilentlyCancelManualCheck",
        "TestCachedPrereleaseIsInvalidatedWhenBetaSkippingEnabled",
        "TestSkippedCachedVersionCannotReopen",
        "TestManualCompletionDefersDialogDuringClinicalCommand",
        "TestUpdateDialogRequiresPresentationLease",
        "TestUpdateDialogReleasesItsPresentationLease",
        "TestFailedUpdateNowLeavesTheDialogButtonsUsable",
        "TestStaleUpdateDialogClosesAfterItsConflictNotice",
        "TestNewerReleaseReplacesAnOpenUpdateDialog",
        "TestSettingsChangeCancelsInFlightAutomaticCheck",
        "TestClinicalCommandBlocksUpdateExit",
        "TestReadOnlyInstallDirectoryBlocksUpdateBeforeShutdown",
        "TestFolderThatCannotRenameFailsTheWriteProbe",
        "TestUpdaterPathFailureReleasesShutdownTransaction",
        "TestVerifiedUpdateLaunchesTheUpdaterOnce",
        "TestUpdateIsNotDownloadedWhenItCannotBeTrusted",
        "TestRejectedDownloadIsDiscardedWithoutLaunchingTheUpdater",
        "TestUpdateIsNotInstalledWithoutAShutdownCoordinator",
        "TestUpdateSkippedSinceItWasOfferedIsNotInstalled",
        "TestVersionComesFromAppVersion",
        "TestReleaseParserShortensOversizedNotes",
        "TestUpdaterScriptRequiresHealthyRelaunch",
        "TestUpdaterScriptRecoversAfterPreSwapFailure",
        "TestUpdaterScriptLogsItsFailure",
        "TestUpdaterUsesPrivateTemporaryScript",
        "TestCleanupDoesNotOwnGenericScript",
        "TestUpdateDialogPreferencesCommitTogether",
        "TestUnchangedUpdateDialogPreservesSettingsRevision",
        "TestManualFailuresAreLogged",
        "TestStaleUpdateDialogCannotOverwriteNewerSettings",
        "TestSkippedVersionPersistsAcrossReload"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "LaunchedScriptPath",
        "UseTestInstall"
    ]

    Setup() {
        this.savedSettings := UseTestSettings("update-settings")
        Settings.SaveAllSettings()
        this.originalTransport := UpdateChecker.transport
        this.originalClinicalActivityProbe := UpdateChecker.clinicalActivityProbe
        this.originalShutdownCoordinator := UpdateChecker.shutdownCoordinator
        this.originalUpdateCheckEligibleProbe := UpdateChecker.updateCheckEligibleProbe
        this.originalUpdateAvailableNotifier := UpdateChecker.updateAvailableNotifier
        this.originalManualResultNotifier := UpdateChecker.manualResultNotifier
        this.originalDialogAcquire := UpdateChecker.dialogAcquire
        this.originalDialogRelease := UpdateChecker.dialogRelease
        this.originalAutoCheckFailureLogged := UpdateChecker.autoCheckFailureLogged
        this.originalMoveFile := UpdateChecker.moveFile
        this.originalPendingUpdateInfo := UpdateChecker.pendingUpdateInfo
        this.originalNotifiedVersion := UpdateChecker.notifiedVersion
        this.originalUpdateDialog := UpdateChecker.updateDialog
        this.originalInstallDirectory := UpdateChecker.installDirectory
        this.originalInstalledExecutable := UpdateChecker.installedExecutable
        this.originalCompiledProbe := UpdateChecker.compiledProbe
        this.originalLaunchUpdater := UpdateChecker.launchUpdater
        ; Never the folder beside the test scripts: the write probe and staged
        ; files go to a private folder, and no updater is ever really launched.
        this.UseTestInstall()
        ; CI writes Version.ahk from the release tag before the tests run, so the
        ; running version must not decide whether a test's release is newer. A
        ; distinct value still shows the version comes from AppVersion.
        this.originalAppVersion := AppVersion.current
        AppVersion.current := "v0.0.1-test"
        UpdateChecker.shutdownCoordinator := 0
        UpdateChecker.updateCheckEligibleProbe := (*) => true
        this.updateNotifications := []
        this.manualNotifications := []
        UpdateChecker.updateAvailableNotifier := RecordNotification.Bind(this.updateNotifications)
        UpdateChecker.manualResultNotifier := RecordNotification.Bind(this.manualNotifications)
        UpdateChecker.dialogAcquire := (*) => true
        UpdateChecker.dialogRelease := (*) => 0
        UpdateChecker.pendingUpdateInfo := 0
        UpdateChecker.notifiedVersion := ""
        UpdateChecker.updateDialog := 0
        UpdateChecker.activeRequest := 0
        UpdateChecker.autoCheckFailureLogged := false
        this.originalLastCheckTime := UpdateChecker.lastCheckTime
        this.originalLastCheckError := UpdateChecker.lastCheckError
        UpdateChecker.lastCheckTime := ""
        UpdateChecker.lastCheckError := ""
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

    TestUnchangedUpdateDialogPreservesSettingsRevision() {
        settingsGui := Settings.ShowDialog()
        updateGui := UpdateChecker.ShowUpdateDialog(ValidUpdateInfo())
        try {
            revision := Settings.revision
            Assert.True(UpdateChecker.SaveDialogChoices(updateGui, Settings.Get("AutoUpdate"), Settings.Get("SkipBetaVersions")))
            Assert.Equal(revision, Settings.revision)
            ClickDialogButton(settingsGui, "Save")
            for dialog in TestRunner.dialogs
                Assert.False(dialog.title = "Settings Changed")
        } finally {
            try settingsGui.Destroy()
            UpdateChecker.CloseUpdateDialog(updateGui)
        }
    }

    TestManualFailuresAreLogged() {
        capturedLog := LogCapture()
        try {
            UpdateChecker.transport := NullHandleAsyncTransport()
            Assert.False(UpdateChecker.BeginManualCheck())
            transport := FakeAsyncUpdateTransport()
            UpdateChecker.transport := transport
            Assert.True(UpdateChecker.BeginManualCheck())
            transport.onError.Call(Error("test network failure"))
            Assert.True(UpdateChecker.BeginManualCheck())
            transport.Resolve({status: 200, body: "invalid JSON"})
            Assert.Equal(3, capturedLog.Count("Update check failed:"))
        } finally capturedLog.Restore()
    }

    ; Each pair is {older, newer} and is asserted in both directions
    TestVersionPrecedenceTable() {
        ordered := [
            ["v1.9.0", "v2.0.0"],
            ["v2.0.0", "v2.1.0"],
            ["v1.9", "v2.0"],
            ["v2.0", "v2.1"],
            ; Patch releases are distinct versions, compared numerically.
            ["v2.0.1", "v2.0.2"],
            ["v2.0.1", "v2.0.9"],
            ["v2.0.9", "v2.0.10"],
            ; 2^64 + 1, which Integer() alone would wrap to 1
            ["v2.0.0", "v18446744073709551617.0.0"],
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
            ["v2.0b1", "v2.0b2"],
            ["v2.0b9", "v2.0b10"],
            ["v2.0b", "v2.0b1"],
            ["v2.0b", "v2.0"],
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

    ; Notes are display-only: long ones are shortened, never a reason to refuse the
    ; update. The cut never leaves half of a surrogate pair.
    TestReleaseParserShortensOversizedNotes() {
        notes := ""
        loop UpdateChecker.maxReleaseNotesCharacters - 1
            notes .= "x"
        notes .= "\ud83d\ude00tail"
        json := StrReplace(
            UpdateReleaseJson("v9.0.0"),
            '"body":"Release notes"',
            '"body":"' notes '"'
        )

        release := UpdateChecker.ParseReleaseResponse(json)

        cutAt := UpdateChecker.maxReleaseNotesCharacters - 1
        Assert.Equal(SubStr(release.notes, 1, cutAt), SubStr(notes, 1, cutAt))
        marker := "`n`n[Release notes shortened"
        Assert.Equal(marker, SubStr(release.notes, cutAt + 1, StrLen(marker)))
        Assert.True(InStr(release.notes, "release page on GitHub"), release.notes)
    }

    ; The script runs only on an installed workstation, so these pin its control
    ; flow rather than its text: each statement is matched where it must sit.
    TestUpdaterScriptRequiresHealthyRelaunch() {
        script := UpdateChecker.BuildUpdaterScript()
        ; A new build that exits within five seconds throws inside the try, which
        ; sends the update to the recovery block.
        Assert.True(RegExMatch(script,
            "\$NewProcess = Start-Process -FilePath \$CurrentExe -PassThru\R"
            . "\s*Start-Sleep -Seconds 5\R"
            . "\s*\$NewProcess\.Refresh\(\)\R"
            . "\s*if \(\$NewProcess\.HasExited\) \{\R"
            . "\s*throw '"
        ), script)
    }

    TestUpdaterScriptRecoversAfterPreSwapFailure() {
        script := UpdateChecker.BuildUpdaterScript()
        recovery := SubStr(script, InStr(script, "} catch {"))

        Assert.True(InStr(recovery, "if ($ParentExited -and -not $RecoveryLaunched) {"), recovery)
        Assert.True(InStr(recovery, "$RecoveryReady = -not $SwapStarted"), recovery)
        Assert.True(InStr(recovery, "if ($RecoveryReady -and (Test-Path -LiteralPath $CurrentExe -PathType Leaf)) {"), recovery)
        Assert.True(RegExMatch(recovery, "Start-Process -FilePath \$CurrentExe\R\s*\$RecoveryLaunched = \$true"), recovery)
        Assert.True(InStr(recovery, "throw $UpdateError"), recovery)
    }

    ; The app has exited when the updater fails, so the updater itself records the
    ; failure in error.log, whose path the app passes as the fifth argument.
    TestUpdaterScriptLogsItsFailure() {
        script := UpdateChecker.BuildUpdaterScript()
        recovery := SubStr(script, InStr(script, "} catch {"))
        Assert.True(InStr(script, "$LogPath = [string]$args[4]"), script)
        Assert.True(RegExMatch(recovery, "\[IO\.File\]::AppendAllText\(\$LogPath, .*\R(?:.*\R)*?\s*throw \$UpdateError"), recovery)

        command := UpdateChecker.UpdaterCommand("C:\t\u.ps1", "C:\app\a.exe", "C:\app\a.new.exe", "C:\app\a.old.exe")
        tail := ' "C:\app\a.old.exe" "' AppLog.Path() '"'
        Assert.Equal(tail, SubStr(command, -StrLen(tail)))
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
        Assert.True(UpdateChecker.TrySaveUpdatePreferences(
            Settings.revision,
            false,
            false,
            "v2.3.0"
        ))

        Assert.False(Settings.Get("AutoUpdate"))
        Assert.False(Settings.Get("SkipBetaVersions"))
        Assert.Equal("v2.3.0", Settings.Get("SkippedUpdateVersion"))
        Assert.Equal("v2.3.0", UpdateChecker.skippedVersion)
    }

    TestStaleUpdateDialogCannotOverwriteNewerSettings() {
        capturedRevision := Settings.revision
        SetTestSetting("AutoUpdate", false)

        result := UpdateChecker.TrySaveUpdatePreferences(
            capturedRevision,
            true,
            false
        )

        Assert.False(result)
        Assert.Equal("Settings Changed", TestRunner.dialogs[1].title)
        Assert.False(Settings.Get("AutoUpdate"))
        Assert.True(Settings.Get("SkipBetaVersions"))
    }

    TestSkippedVersionPersistsAcrossReload() {
        Assert.True(UpdateChecker.TrySaveUpdatePreferences(
            Settings.revision,
            true,
            true,
            "v2.2.0"
        ))
        UpdateChecker.skippedVersion := ""

        UpdateChecker.LoadSkippedVersion()

        Assert.Equal("v2.2.0", UpdateChecker.skippedVersion)
        Assert.Equal("v2.2.0", Settings.Get("SkippedUpdateVersion"))
    }

    TestAutoCheckTimerRespectsSettings() {
        SetTestSetting("AutoUpdate", true)
        UpdateChecker.StartAutoCheck()
        Assert.True(UpdateChecker.updateTimer != 0)

        SetTestSetting("AutoUpdate", false)
        UpdateChecker.StartAutoCheck()
        Assert.Equal(0, UpdateChecker.updateTimer)
    }

    TestSettingsChangeRestartsTimer() {
        SetTestSetting("AutoUpdate", true)
        UpdateChecker.StartAutoCheck()
        previousTimer := UpdateChecker.updateTimer
        UpdateChecker.OnSettingsChanged()
        Assert.True(IsObject(UpdateChecker.updateTimer), "Auto-update must keep a timer armed")
        Assert.False(UpdateChecker.updateTimer == previousTimer, "A settings change must re-arm the timer")

        SetTestSetting("AutoUpdate", false)
        UpdateChecker.OnSettingsChanged()
        Assert.Equal(0, UpdateChecker.updateTimer)
    }

    ; Tools > Status reports "up to date" only after a check succeeded, and names
    ; the error of one that failed.
    TestChecksRecordTheirOutcomeForStatus() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport

        Assert.True(UpdateChecker.BeginAutoCheck())
        Assert.Equal("", UpdateChecker.lastCheckTime, "nothing has finished while the request runs")
        transport.onError.Call(Error("The server could not be reached"))
        Assert.Equal("", UpdateChecker.lastCheckTime)
        Assert.Equal("The server could not be reached", UpdateChecker.lastCheckError)

        Assert.True(UpdateChecker.BeginAutoCheck())
        transport.Resolve({status: 200, body: UpdateReleaseJson("v0.0.0")})
        Assert.True(UpdateChecker.lastCheckTime != "")
        Assert.Equal("", UpdateChecker.lastCheckError)

        Assert.True(UpdateChecker.BeginManualCheck())
        transport.Resolve({status: 200, body: "invalid JSON"})
        Assert.True(UpdateChecker.lastCheckError != "", "a manual check that fails is recorded too")

        UpdateChecker.transport := NullHandleAsyncTransport()
        UpdateChecker.lastCheckError := ""
        Assert.False(UpdateChecker.BeginManualCheck())
        Assert.True(UpdateChecker.lastCheckError != "", "a manual check that cannot start is recorded too")
    }

    TestAutomaticCheckUsesAsyncTransport() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("SkipBetaVersions", true)

        Assert.True(UpdateChecker.BeginAutoCheck())
        Assert.Equal(1, transport.asyncCalls)
        Assert.Equal(0, transport.syncCalls)
        Assert.True(UpdateChecker.activeRequest != 0)
        Assert.Equal(UpdateChecker.latestStableUrl, transport.url)
        Assert.Equal(UpdateChecker.maxMetadataSizeBytes, transport.maximumSize)

        transport.Resolve({status: 404, body: ""})
        Assert.Equal(0, UpdateChecker.activeRequest)

        ; With betas offered, the newest release of any kind is queried instead.
        SetTestSetting("SkipBetaVersions", false)
        Assert.True(UpdateChecker.BeginAutoCheck())
        Assert.Equal(UpdateChecker.newestReleaseUrl, transport.url)
        transport.Resolve({status: 404, body: ""})
    }

    ; README: development and source builds skip update checks entirely.
    TestOnlyCompiledReleaseBuildsCheckForUpdates() {
        UpdateChecker.updateCheckEligibleProbe := this.originalUpdateCheckEligibleProbe
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        originalDevBuild := AppVersion.isDevBuild
        cases := [
            {label: "source run", compiled: false, devBuild: false, eligible: false},
            {label: "source run of a dev build", compiled: false, devBuild: true, eligible: false},
            {label: "compiled dev build", compiled: true, devBuild: true, eligible: false},
            {label: "compiled release build", compiled: true, devBuild: false, eligible: true}
        ]
        try {
            for testCase in cases {
                UpdateChecker.compiledProbe := testCase.compiled ? (*) => true : (*) => false
                AppVersion.isDevBuild := testCase.devBuild
                requests := transport.asyncCalls

                Assert.Equal(testCase.eligible, UpdateChecker.BeginAutoCheck(), testCase.label)
                if testCase.eligible
                    transport.Resolve({status: 404, body: ""})
                Assert.Equal(testCase.eligible, UpdateChecker.BeginManualCheck(), testCase.label)
                if testCase.eligible
                    transport.Resolve({status: 404, body: ""})
                else {
                    Assert.Equal("Development Build", this.manualNotifications[-1].title, testCase.label)
                    Assert.True(InStr(this.manualNotifications[-1].text, "This is v0.0.1-test,") = 1, testCase.label)
                }
                Assert.Equal(requests + (testCase.eligible ? 2 : 0), transport.asyncCalls, testCase.label)
            }
        } finally AppVersion.isDevBuild := originalDevBuild
    }

    ; An offline workstation fails the hourly check every time: one log entry per
    ; outage, and a new outage after a successful check is logged again.
    TestAutomaticCheckFailuresAreLoggedOncePerOutage() {
        capturedLog := LogCapture()
        try {
            transport := FakeAsyncUpdateTransport()
            UpdateChecker.transport := transport
            loop 2 {
                Assert.True(UpdateChecker.BeginAutoCheck())
                transport.Resolve({status: 503, body: ""})
            }
            Assert.Equal(1, capturedLog.Count("Automatic update check failed: Error: GitHub release request returned HTTP 503"))

            Assert.True(UpdateChecker.BeginAutoCheck())
            transport.Resolve({status: 404, body: ""})
            Assert.True(UpdateChecker.BeginAutoCheck())
            transport.Resolve({status: 503, body: ""})
            Assert.Equal(2, capturedLog.Count("Automatic update check failed"))
        } finally capturedLog.Restore()
    }

    TestRequestWithoutAHandleIsReportedAsNotStarted() {
        UpdateChecker.transport := NullHandleAsyncTransport()
        capturedLog := LogCapture()
        try {
            Assert.False(UpdateChecker.BeginAutoCheck())
            Assert.Equal(0, UpdateChecker.activeRequest)
            Assert.Equal(1, capturedLog.Count("Automatic update check failed: Error: The update request returned no handle"))
        } finally capturedLog.Restore()

        Assert.False(UpdateChecker.BeginManualCheck())
        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(1, this.manualNotifications.Length)
        Assert.True(InStr(this.manualNotifications[1].text, "could not start"), this.manualNotifications[1].text)
    }

    TestSynchronousAsyncFailureIsNotReportedAsStarted() {
        UpdateChecker.transport := SynchronousFailingAsyncTransport()

        Assert.False(UpdateChecker.BeginAutoCheck())
        Assert.Equal(0, UpdateChecker.activeRequest)

        Assert.False(UpdateChecker.BeginManualCheck())
        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(1, this.manualNotifications.Length)
        Assert.True(InStr(this.manualNotifications[1].text, "synchronous failure") > 0)
        Assert.Equal(0, this.updateNotifications.Length)
    }

    TestAutomaticCheckNeverOpensAnActivatingDialog() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("SkipBetaVersions", true)
        Assert.True(UpdateChecker.BeginAutoCheck())
        slot := UpdateChecker.activeRequest

        transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})

        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(0, slot.handle)
        Assert.True(IsObject(UpdateChecker.pendingUpdateInfo))
        Assert.Equal("v9.0.0", UpdateChecker.pendingUpdateInfo.latestVersion)
        Assert.Equal(0, UpdateChecker.updateDialog)
        Assert.Equal(1, this.updateNotifications.Length)
    }

    ; "Remind Me Later" quiets the hourly notice; a check the user asks for still
    ; finds the update instead of reporting "up to date".
    TestRemindLaterDefersOnlyTheAutomaticNotice() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("SkipBetaVersions", true)
        UpdateChecker.lastRemindTime := DllCall("GetTickCount64", "UInt64")

        Assert.True(UpdateChecker.BeginAutoCheck())
        transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})
        Assert.Equal(0, this.updateNotifications.Length)
        Assert.Equal(0, UpdateChecker.pendingUpdateInfo)

        ; A refused presentation lease keeps the dialog closed but shows the path
        ; reached it.
        UpdateChecker.dialogAcquire := (*) => false
        Assert.True(UpdateChecker.BeginManualCheck())
        transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})
        Assert.Equal(1, this.manualNotifications.Length)
        Assert.Equal("Update Dialog Unavailable", this.manualNotifications[1].title)
        Assert.Equal("v9.0.0", UpdateChecker.pendingUpdateInfo.latestVersion)
    }

    TestSettingsChangeKeepsAnUpdateDeferredByRemindLater() {
        SetTestSetting("SkipBetaVersions", true)
        info := ValidUpdateInfo()
        UpdateChecker.pendingUpdateInfo := info
        UpdateChecker.lastRemindTime := DllCall("GetTickCount64", "UInt64")

        UpdateChecker.OnSettingsChanged()

        Assert.True(UpdateChecker.pendingUpdateInfo = info)
    }

    TestRemindLaterAnnouncesTheVersionAgainAfterTheDelay() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("SkipBetaVersions", true)
        check := () => (
            UpdateChecker.BeginAutoCheck(),
            transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})
        )

        check()
        Assert.Equal(1, this.updateNotifications.Length)

        UpdateChecker.RemindLater()
        check()
        Assert.Equal(1, this.updateNotifications.Length)

        UpdateChecker.lastRemindTime -= UpdateChecker.remindLaterMs + 1000
        check()
        Assert.Equal(2, this.updateNotifications.Length)
        check()
        Assert.Equal(2, this.updateNotifications.Length)
    }

    TestManualCheckReportsASkippedVersion() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("SkipBetaVersions", true)
        UpdateChecker.skippedVersion := "v9.0.0"

        Assert.True(UpdateChecker.BeginManualCheck())
        transport.Resolve({status: 200, body: UpdateReleaseJson("v9.0.0")})

        Assert.Equal(1, this.manualNotifications.Length)
        Assert.Equal("Update Skipped", this.manualNotifications[1].title)
        Assert.True(InStr(this.manualNotifications[1].text, "v9.0.0"), this.manualNotifications[1].text)
        Assert.Equal(0, UpdateChecker.updateDialog)
    }

    TestManualCheckIsAsyncAndReportsNoUpdate() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("SkipBetaVersions", true)

        Assert.True(UpdateChecker.ShowUpdateDialog())
        Assert.Equal(1, transport.asyncCalls)
        Assert.Equal(0, transport.syncCalls)
        transport.Resolve({status: 404, body: ""})

        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(1, this.manualNotifications.Length)
        ; Check for Updates is where a user finds the version to report.
        Assert.Equal("PACS Assistant v0.0.1-test is up to date.", this.manualNotifications[1].text)
    }

    TestSettingsChangeDoesNotSilentlyCancelManualCheck() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("AutoUpdate", true)
        Assert.True(UpdateChecker.BeginManualCheck())
        slot := UpdateChecker.activeRequest

        UpdateChecker.OnSettingsChanged()

        Assert.True(UpdateChecker.activeRequest = slot)
        Assert.False(transport.handle.cancelled)
        transport.Resolve({status: 404, body: ""})
        Assert.True(InStr(this.manualNotifications[1].text, "up to date") > 0)
    }

    TestCachedPrereleaseIsInvalidatedWhenBetaSkippingEnabled() {
        SetTestSetting("SkipBetaVersions", false)
        UpdateChecker.pendingUpdateInfo := {
            hasUpdate: true,
            latestVersion: "v9.0.0-beta.1",
            isPrerelease: true
        }

        SetTestSetting("SkipBetaVersions", true)
        UpdateChecker.OnSettingsChanged()

        Assert.Equal(0, UpdateChecker.pendingUpdateInfo)
    }

    TestSkippedCachedVersionCannotReopen() {
        UpdateChecker.pendingUpdateInfo := {
            hasUpdate: true,
            latestVersion: "v9.0.0",
            isPrerelease: false
        }

        SetTestSetting("SkippedUpdateVersion", "v9.0.0")
        UpdateChecker.OnSettingsChanged()

        Assert.Equal(0, UpdateChecker.pendingUpdateInfo)
        Assert.Equal("v9.0.0", UpdateChecker.skippedVersion)
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
        Assert.Equal(
            "Version v9.0.0 is available. Use Check for Updates once the active clinical command finishes.",
            this.updateNotifications[-1].text
        )
    }

    TestUpdateDialogRequiresPresentationLease() {
        lease := FakePresentationLease(false)
        UpdateChecker.dialogAcquire := ObjBindMethod(lease, "Acquire")
        UpdateChecker.dialogRelease := ObjBindMethod(lease, "Release")

        result := UpdateChecker.ShowUpdateDialog(ValidUpdateInfo())
        if IsObject(result)
            UpdateChecker.CloseUpdateDialog(result)

        Assert.False(result)
        Assert.Equal(1, lease.acquireCalls)
        Assert.Equal(0, lease.releaseCalls)
        Assert.True(IsObject(UpdateChecker.pendingUpdateInfo))
        Assert.Equal(1, this.manualNotifications.Length)
    }

    ; The lease covers building the dialog only. Held on, it would refuse every
    ; clinical command and profile change until a restart.
    TestUpdateDialogReleasesItsPresentationLease() {
        lease := FakePresentationLease(true)
        UpdateChecker.dialogAcquire := ObjBindMethod(lease, "Acquire")
        UpdateChecker.dialogRelease := ObjBindMethod(lease, "Release")

        result := UpdateChecker.ShowUpdateDialog(ValidUpdateInfo())
        try {
            Assert.True(IsObject(result))
            Assert.Equal(1, lease.acquireCalls)
            Assert.Equal(1, lease.releaseCalls)
        } finally {
            if IsObject(result)
                UpdateChecker.CloseUpdateDialog(result)
        }
    }

    ; Update Now keeps the dialog open when the update does not start, so the
    ; preferences it saved must not make the next button report a conflict.
    TestFailedUpdateNowLeavesTheDialogButtonsUsable() {
        UpdateChecker.shutdownCoordinator := FakeShutdownCoordinator(false)
        updateGui := UpdateChecker.ShowUpdateDialog(ValidUpdateInfo())
        Assert.True(IsObject(updateGui))
        try {
            ClickDialogButton(updateGui, "Update Now")
            Assert.True(UpdateChecker.UpdateDialogIsLive(), "a refused update must keep the dialog open")
            ClickDialogButton(updateGui, "Remind Me Later")
        } finally {
            if UpdateChecker.UpdateDialogIsLive()
                UpdateChecker.CloseUpdateDialog(updateGui)
        }

        for dialog in TestRunner.dialogs
            Assert.False(dialog.title = "Settings Changed", "Remind Me Later reported a settings conflict")
        Assert.Equal(1, UpdateChecker.shutdownCoordinator.beginCalls)
        Assert.True(UpdateChecker.lastRemindTime > 0)
        Assert.Equal(0, UpdateChecker.updateDialog)
    }

    ; A dialog whose settings changed underneath cannot save; after saying so once it
    ; closes, and Check for Updates reopens it from the pending update.
    TestStaleUpdateDialogClosesAfterItsConflictNotice() {
        updateGui := UpdateChecker.ShowUpdateDialog(ValidUpdateInfo())
        Assert.True(IsObject(updateGui))
        try {
            SetTestSetting("AutoUpdate", false)
            ClickDialogButton(updateGui, "Remind Me Later")
            stillOpen := UpdateChecker.UpdateDialogIsLive()
        } finally {
            if UpdateChecker.UpdateDialogIsLive()
                UpdateChecker.CloseUpdateDialog(updateGui)
        }

        conflicts := 0
        for dialog in TestRunner.dialogs
            conflicts += dialog.title = "Settings Changed"
        Assert.Equal(1, conflicts)
        Assert.False(stillOpen)
        Assert.Equal(0, UpdateChecker.lastRemindTime)
    }

    ; A dialog opened for one version is replaced, not re-shown, once a newer
    ; release is pending: its buttons would act on the older version.
    TestNewerReleaseReplacesAnOpenUpdateDialog() {
        older := ValidUpdateInfo()
        newer := ValidUpdateInfo()
        newer.latestVersion := "v9.1.0"
        first := UpdateChecker.ShowUpdateDialog(older)
        Assert.True(IsObject(first))
        try {
            UpdateChecker.RecordAvailableUpdate(newer)
            second := UpdateChecker.ShowUpdateDialog()
            again := UpdateChecker.ShowUpdateDialog()
        } finally {
            if UpdateChecker.UpdateDialogIsLive()
                UpdateChecker.CloseUpdateDialog(UpdateChecker.updateDialog)
            try first.Destroy()
        }

        Assert.False(first == second)
        Assert.Equal("v9.1.0", second.latestVersion)
        Assert.True(again == second, "the same version re-shows the open dialog")
    }

    TestSettingsChangeCancelsInFlightAutomaticCheck() {
        transport := FakeAsyncUpdateTransport()
        UpdateChecker.transport := transport
        SetTestSetting("AutoUpdate", true)
        Assert.True(UpdateChecker.BeginAutoCheck())

        SetTestSetting("AutoUpdate", false)
        UpdateChecker.OnSettingsChanged()

        Assert.True(transport.handle.cancelled)
        Assert.Equal(0, UpdateChecker.activeRequest)
        Assert.Equal(0, UpdateChecker.updateTimer)
    }

    TestClinicalCommandBlocksUpdateExit() {
        transport := RecordingDownloadTransport()
        UpdateChecker.transport := transport
        coordinator := FakeShutdownCoordinator(false)
        UpdateChecker.shutdownCoordinator := coordinator

        result := UpdateChecker.PerformUpdate(ValidUpdateInfo(), {})

        Assert.False(result)
        Assert.Equal(0, transport.downloads.Length)
        Assert.Equal(1, coordinator.beginCalls)
        Assert.Equal(0, coordinator.completeCalls)
    }

    ; A failed FileMove throws a plain Error rather than OSError. A folder that
    ; allows writing but not renaming must still fail the probe, not escape it.
    TestFolderThatCannotRenameFailsTheWriteProbe() {
        probes := []
        UpdateChecker.moveFile := (source, destination) => (
            probes.Push(source),
            FileDelete(source),
            FileMove(source, destination, false)
        )
        capturedLog := LogCapture()
        try {
            writable := UpdateChecker.InstallDirectoryIsWritable()
            logged := capturedLog.Count("failed the update write probe")
        } finally capturedLog.Restore()

        Assert.False(writable)
        Assert.Equal(1, probes.Length)
        Assert.False(FileExist(probes[1]))
        Assert.False(FileExist(probes[1] ".moved"))
        Assert.Equal(1, logged)
    }

    TestReadOnlyInstallDirectoryBlocksUpdateBeforeShutdown() {
        transport := RecordingDownloadTransport()
        ReadOnlyInstallUpdateChecker.transport := transport
        coordinator := FakeShutdownCoordinator(true)
        ReadOnlyInstallUpdateChecker.shutdownCoordinator := coordinator

        result := ReadOnlyInstallUpdateChecker.PerformUpdate(ValidUpdateInfo(), {})

        Assert.False(result)
        ; The dialog proves the writability gate refused, not an earlier eligibility exit.
        Assert.Equal(1, TestRunner.dialogs.Length)
        Assert.Equal("Update Requires a Writable App Folder", TestRunner.dialogs[1].title)
        Assert.Equal(0, coordinator.beginCalls)
        Assert.Equal(0, coordinator.cancelCalls)
        Assert.Equal(0, coordinator.completeCalls)
        Assert.Equal(0, transport.downloads.Length)
    }

    TestUpdaterPathFailureReleasesShutdownTransaction() {
        coordinator := FakeShutdownCoordinator(true)
        ThrowingUpdaterPathChecker.shutdownCoordinator := coordinator

        capturedLog := LogCapture()
        try result := ThrowingUpdaterPathChecker.PerformUpdate(ValidUpdateInfo(), {})
        finally {
            ; The failure path re-arms the 30-second artifact cleanup on the subclass.
            ThrowingUpdaterPathChecker.CancelUpdateArtifactCleanup()
            logged := capturedLog.Count("Update failed: Error: simulated updater path failure")
            capturedLog.Restore()
        }

        Assert.False(result)
        Assert.Equal(1, logged)
        Assert.Equal(1, coordinator.beginCalls)
        Assert.Equal(0, coordinator.completeCalls)
        Assert.Equal(1, coordinator.cancelCalls)
    }

    ; A verified download is staged beside the app, the updater script is written,
    ; and the updater is launched once, with this install's paths, before shutdown.
    TestVerifiedUpdateLaunchesTheUpdaterOnce() {
        launches := this.launches
        updateInfo := InterpreterUpdateInfo()
        transport := RecordingDownloadTransport(A_AhkPath)
        UpdateChecker.transport := transport
        coordinator := FakeShutdownCoordinator(true)
        UpdateChecker.shutdownCoordinator := coordinator
        updateGui := FakeUpdateGui()
        transport.observedGui := updateGui

        result := UpdateChecker.PerformUpdate(updateInfo, updateGui)

        newExe := this.installRoot "\pacs-assistant.new.exe"
        Assert.True(result)
        Assert.Equal(1, transport.downloads.Length)
        ; Its buttons would otherwise run against the shutdown lease mid-download.
        Assert.True(transport.downloads[1].guiDisabled)
        Assert.Equal(updateInfo.downloadUrl, transport.downloads[1].url)
        ; The transport requires the response to be exactly this size.
        Assert.Equal(updateInfo.downloadSize, transport.downloads[1].expectedSize)
        Assert.Equal(newExe, transport.downloads[1].destination)
        Assert.True(FileExist(newExe), "the verified download must stay staged for the updater")
        Assert.Equal(1, launches.Length)
        scriptPath := this.LaunchedScriptPath(launches[1])
        Assert.Equal(UpdateChecker.BuildUpdaterScript(), FileRead(scriptPath, "UTF-8"))
        Assert.Equal(this.installRoot, launches[1].workingDirectory)
        Assert.Equal(UpdateChecker.UpdaterCommand(
            scriptPath,
            this.installRoot "\pacs-assistant.exe",
            newExe,
            this.installRoot "\pacs-assistant.backup.exe"
        ), launches[1].command)
        Assert.Equal(1, updateGui.destroyCalls)
        Assert.Equal(1, coordinator.completeCalls)
        Assert.Equal(0, coordinator.cancelCalls)
        Assert.Equal(0, TestRunner.dialogs.Length)
    }

    ; An uncompiled build has no executable to replace, and a release asset outside
    ; this repository's releases is never fetched.
    TestUpdateIsNotDownloadedWhenItCannotBeTrusted() {
        launches := this.launches
        trusted := InterpreterUpdateInfo()
        foreign := InterpreterUpdateInfo()
        foreign.downloadUrl := StrReplace(foreign.downloadUrl, "/rakan959/", "/someone-else/")
        cases := [
            {label: "uncompiled build", compiled: false, updateInfo: trusted,
                reason: "only available in the compiled application"},
            {label: "foreign download URL", compiled: true, updateInfo: foreign,
                reason: "download URL is not trusted"}
        ]
        for testCase in cases {
            UpdateChecker.compiledProbe := testCase.compiled ? (*) => true : (*) => false
            transport := RecordingDownloadTransport(A_AhkPath)
            UpdateChecker.transport := transport
            coordinator := FakeShutdownCoordinator(true)
            UpdateChecker.shutdownCoordinator := coordinator

            result := UpdateChecker.PerformUpdate(testCase.updateInfo, FakeUpdateGui())

            Assert.False(result, testCase.label)
            Assert.Equal(0, transport.downloads.Length, testCase.label)
            Assert.Equal(1, coordinator.cancelCalls, testCase.label)
            Assert.Equal(0, coordinator.completeCalls, testCase.label)
            Assert.Equal("Update Failed", TestRunner.dialogs[-1].title, testCase.label)
            Assert.True(InStr(TestRunner.dialogs[-1].text, testCase.reason), testCase.label)
        }
        Assert.Equal(0, launches.Length)
    }

    ; A download that fails verification is deleted, and no updater is launched to
    ; install it.
    TestRejectedDownloadIsDiscardedWithoutLaunchingTheUpdater() {
        launches := this.launches
        updateInfo := InterpreterUpdateInfo()
        digest := updateInfo.downloadSha256
        updateInfo.downloadSha256 := (SubStr(digest, 1, 1) = "0" ? "1" : "0") SubStr(digest, 2)
        transport := RecordingDownloadTransport(A_AhkPath)
        UpdateChecker.transport := transport
        coordinator := FakeShutdownCoordinator(true)
        UpdateChecker.shutdownCoordinator := coordinator
        updateGui := FakeUpdateGui()
        transport.observedGui := updateGui

        result := UpdateChecker.PerformUpdate(updateInfo, updateGui)

        Assert.False(result)
        Assert.Equal(1, transport.downloads.Length)
        Assert.True(transport.downloads[1].guiDisabled)
        ; Re-enabled, so the update can be retried or dismissed.
        Assert.False(updateGui.disabled)
        Assert.False(FileExist(this.installRoot "\pacs-assistant.new.exe"))
        Assert.Equal(0, launches.Length)
        Assert.Equal(0, updateGui.destroyCalls)
        Assert.Equal(1, coordinator.cancelCalls)
        Assert.Equal(0, coordinator.completeCalls)
        Assert.Equal(1, TestRunner.dialogs.Length)
        Assert.True(InStr(TestRunner.dialogs[1].text, "SHA-256"))
    }

    ; Installing ends the app, which only the shutdown coordinator may do: without
    ; one, nothing is downloaded or launched.
    TestUpdateIsNotInstalledWithoutAShutdownCoordinator() {
        launches := this.launches
        transport := RecordingDownloadTransport(A_AhkPath)
        UpdateChecker.transport := transport

        Assert.Throws(
            () => UpdateChecker.PerformUpdate(InterpreterUpdateInfo(), FakeUpdateGui()),
            "shutdownCoordinator must be set"
        )
        Assert.Equal(0, transport.downloads.Length)
        Assert.Equal(0, launches.Length)
    }

    ; Update Now re-checks eligibility: a version skipped since the dialog opened
    ; is not downloaded and shutdown is not started.
    TestUpdateSkippedSinceItWasOfferedIsNotInstalled() {
        updateInfo := InterpreterUpdateInfo()
        transport := RecordingDownloadTransport(A_AhkPath)
        UpdateChecker.transport := transport
        coordinator := FakeShutdownCoordinator(true)
        UpdateChecker.shutdownCoordinator := coordinator
        UpdateChecker.skippedVersion := updateInfo.latestVersion

        Assert.False(UpdateChecker.PerformUpdate(updateInfo, FakeUpdateGui()))
        Assert.Equal("Update No Longer Eligible", TestRunner.dialogs[-1].title)
        Assert.Equal(0, coordinator.beginCalls)
        Assert.Equal(0, transport.downloads.Length)
        Assert.Equal(0, this.launches.Length)
    }

    Teardown() {
        AppVersion.current := this.originalAppVersion
        try UpdateChecker.CancelActiveCheck()
        UpdateChecker.StopAutoCheck()
        UpdateChecker.transport := this.originalTransport
        UpdateChecker.clinicalActivityProbe := this.originalClinicalActivityProbe
        UpdateChecker.shutdownCoordinator := this.originalShutdownCoordinator
        UpdateChecker.updateCheckEligibleProbe := this.originalUpdateCheckEligibleProbe
        UpdateChecker.updateAvailableNotifier := this.originalUpdateAvailableNotifier
        UpdateChecker.manualResultNotifier := this.originalManualResultNotifier
        UpdateChecker.dialogAcquire := this.originalDialogAcquire
        UpdateChecker.dialogRelease := this.originalDialogRelease
        UpdateChecker.autoCheckFailureLogged := this.originalAutoCheckFailureLogged
        UpdateChecker.lastCheckTime := this.originalLastCheckTime
        UpdateChecker.lastCheckError := this.originalLastCheckError
        UpdateChecker.moveFile := this.originalMoveFile
        UpdateChecker.pendingUpdateInfo := this.originalPendingUpdateInfo
        UpdateChecker.notifiedVersion := this.originalNotifiedVersion
        UpdateChecker.updateDialog := this.originalUpdateDialog
        UpdateChecker.CancelUpdateArtifactCleanup()
        UpdateChecker.installDirectory := this.originalInstallDirectory
        UpdateChecker.installedExecutable := this.originalInstalledExecutable
        UpdateChecker.compiledProbe := this.originalCompiledProbe
        UpdateChecker.launchUpdater := this.originalLaunchUpdater
        ; A launch is only recorded, so the script it names is still on disk.
        for launch in this.launches
            try FileDelete(this.LaunchedScriptPath(launch))
        try DirDelete(this.installRoot, true)
        UpdateChecker.skippedVersion := ""
        UpdateChecker.lastRemindTime := 0
        RestoreTestSettings(this.savedSettings)
    }

    ; Points the installer at a private folder standing in for the app folder, and
    ; records each updater launch, as {command, workingDirectory}, in this.launches
    ; instead of running it.
    UseTestInstall() {
        this.installRoot := TestTempPath("update-install")
        DirCreate(this.installRoot)
        UpdateChecker.installDirectory := this.installRoot
        UpdateChecker.installedExecutable := this.installRoot "\pacs-assistant.exe"
        UpdateChecker.compiledProbe := (*) => true
        launches := this.launches := []
        UpdateChecker.launchUpdater := (command, workingDirectory) => launches.Push(
            {command: command, workingDirectory: workingDirectory}
        )
    }

    ; The updater script a recorded launch would run, or "" when it names none.
    LaunchedScriptPath(launch) {
        return RegExMatch(launch.command, '-File "([^"]+)"', &match) ? match[1] : ""
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
        this.url := ""
        this.maximumSize := 0
        this.handle := FakeAsyncUpdateHandle()
    }

    GetText(*) {
        this.syncCalls++
        throw Error("synchronous transport must not be used")
    }

    GetTextAsync(url, onComplete, onError, maximumSize := 0) {
        this.asyncCalls++
        this.url := url
        this.maximumSize := maximumSize
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

class NullHandleAsyncTransport {
    GetTextAsync(*) {
        return 0
    }
}

class SynchronousFailingAsyncTransport {
    GetTextAsync(url, onComplete, onError, maximumSize := 0) {
        onError.Call(Error("synchronous failure"))
        return 0
    }
}

class ThrowingUpdaterPathChecker extends UpdateChecker {
    static CreateUpdaterPath() {
        throw Error("simulated updater path failure")
    }
}

class ReadOnlyInstallUpdateChecker extends UpdateChecker {
    static InstallDirectoryIsWritable() => false
}

; Records each download; given a source file, it "downloads" a copy of it.
class RecordingDownloadTransport {
    __New(sourcePath := "") {
        this.sourcePath := sourcePath
        this.downloads := []
        ; An update dialog whose state each download records.
        this.observedGui := 0
    }

    Download(url, destination, expectedSize, maximumSize) {
        this.downloads.Push({
            url: url,
            destination: destination,
            expectedSize: expectedSize,
            guiDisabled: IsObject(this.observedGui) && this.observedGui.disabled
        })
        if (this.sourcePath != "")
            FileCopy(this.sourcePath, destination)
    }
}

class FakeUpdateGui {
    __New() {
        this.destroyCalls := 0
        this.disabled := false
    }

    Opt(options) {
        if (options = "+Disabled")
            this.disabled := true
        else if (options = "-Disabled")
            this.disabled := false
    }

    Destroy() {
        this.destroyCalls++
    }
}

UpdateReleaseJson(version) {
    return '{"tag_name":"' version '","prerelease":false'
        . ',"body":"Release notes","assets":['
        . '{"name":"pacs-assistant.exe","size":1550000,'
        . '"digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",'
        . '"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/'
        . version '/pacs-assistant.exe"}'
        . ']}'
}

; Clicks a dialog button the way a user does, then lets its handler run. The text
; is the label as shown, without the & that marks its keyboard mnemonic.
ClickDialogButton(dialogGui, text) {
    for , control in dialogGui {
        if (control.Type = "Button" && StrReplace(control.Text, "&") = text) {
            SendMessage(0xF5, 0, 0, control)  ; BM_CLICK
            Sleep(50)
            return
        }
    }
    throw Error("The dialog has no '" text "' button")
}

; An update whose release asset is the running interpreter: a real executable
; with a known size, digest and version, so the downloaded copy passes validation.
InterpreterUpdateInfo() {
    version := "v" FileGetVersion(A_AhkPath)
    return {
        hasUpdate: true,
        currentVersion: UpdateChecker.currentVersion,
        latestVersion: version,
        isPrerelease: false,
        downloadUrl: "https://github.com/rakan959/pacs-assistant/releases/download/" version "/pacs-assistant.exe",
        downloadSize: FileGetSize(A_AhkPath),
        downloadSha256: UpdateChecker.HashFileSha256(A_AhkPath),
        releaseNotes: "Release notes"
    }
}

ValidUpdateInfo() {
    return {
        hasUpdate: true,
        currentVersion: UpdateChecker.currentVersion,
        latestVersion: "v9.0.0",
        isPrerelease: false,
        downloadUrl: "https://github.com/rakan959/pacs-assistant/releases/download/v9.0.0/pacs-assistant.exe",
        downloadSize: 1550000,
        downloadSha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        releaseNotes: "Release notes"
    }
}
