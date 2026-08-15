#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class ClinicalAutomationTest {
    static Tests := [
        "ActivationFailureDoesNotSend",
        "ActivationCanSucceedButFocusCheckStopsSend",
        "TargetedSendActivatesBeforeSending",
        "AmbiguousTargetedSendDoesNotActivateOrSend",
        "ExactWindowResolverRejectsSubstringAndDuplicateMatches",
        "PacsSeriesCommandsUseExactHwndTarget",
        "BuiltInClinicalCommandUsesConfirmedTarget",
        "WindowToggleRevalidatesUniqueSessionBeforeMutation",
        "NativePowerScribeCaptureRejectsImpostorAndDuplicate",
        "TargetedCustomCommandUsesConfirmedTarget",
        "ClinicalCommandGateRejectsNestedBuiltIn",
        "ShutdownGateRejectsNewClinicalCommand",
        "UnavailableAttendingAssignmentHasNoWindowSideEffects",
        "AttendingRoutingUsesInjectedDependencies",
        "BlankAttendingSkipsPowerScribeWrite",
        "UnknownExaminationRequiresManualAssignment",
        "FailedAttendingControlIsReported",
        "NativeLookupErrorsAreNotAbsence",
        "WindowCloseUncertaintyCancelsStop",
        "WindowCloseCarriesAndRevalidatesCapturedSession",
        "AmbiguousSharedHostWindowsAreNotClosed",
        "RestartRejectsBareProcessTermination",
        "RestartSpecsNeverHardStopPowerScribe",
        "RestartAbortsWhenPowerScribeSaveIsUnverified",
        "RestartAbortsForUnverifiedPowerScribeProcess",
        "RestartAbortsWhenAnotherPowerScribeProcessSurvivesGracefulClose",
        "RestartPreparationFailureHasNoClinicalSideEffects",
        "RestartPreparationCapturesHiddenTrustedVueProcesses",
        "RestartAbortsWhenTargetReappearsBeforeLaunch",
        "RestartStopBoundaryFailureCancelsLaunch",
        "RestartRejectsMalformedStopResult",
        "RestartLaunchBoundaryFailuresAreReported",
        "RestartRequiresExpectedVueWindowAfterLaunch",
        "RestartLaunchProofRequiresANewStableVueSession",
        "GracefulCloseTimesOutAcross32BitTickWrap",
        "GracefulCloseRequiresCapturedProcessIdentity",
        "GracefulCloseRejectsSameProcessWrongTitleBeforeRequest",
        "GracefulCloseRejectsDuplicateExactWindowBeforeRequest",
        "RestartTargetsUseExactClinicalIdentities",
        "PacsLauncherRejectsNonShortcutMatch",
        "PacsLauncherRejectsRetargetedShortcut",
        "PacsLauncherRejectsUntrustedSameNamedExecutable",
        "PacsLauncherAcceptsInstalledShortcut",
        "ReportSelectionUsesOnlyReportShapedText",
        "ReportSelectionRejectsMultipleReportCandidates",
        "ReportSelectionRejectsUnrelatedFallbackText",
        "ReportCaptureFailsClosedOnEnumerationError",
        "ReportCaptureFailsClosedOnUnreadableSibling",
        "ReportCaptureFailsClosedOnUnsupportedSibling"
    ]

    Setup() {
        this.originalDriver := AppControl.windowDriver
        this.originalLifecycleDriver := HasProp(AppControl, "lifecycleDriver") ? AppControl.lifecycleDriver : 0
        this.originalPowerScribeSessionDriver := HasProp(PowerScribe, "sessionDriver")
            ? PowerScribe.sessionDriver
            : 0
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
        this.originalClinicalCommandActive := PACSCommands.clinicalCommandActive
        this.originalActiveClinicalCommand := PACSCommands.activeClinicalCommand
        this.originalBusyNotifier := PACSCommands.busyNotifier
        this.originalCommandAvailabilityProbe := PACSCommands.commandAvailabilityProbe
        this.busyNotifications := []
        PowerScribe.sessionDriver := FakePowerScribeSessionDriver()
        ProfileManager.profiles := Map()
        ProfileManager.currentProfile := ""
        PACSCommands.clinicalCommandActive := false
        PACSCommands.activeClinicalCommand := ""
        PACSCommands.busyNotifier := (text, title, options) => this.busyNotifications.Push({
            text: text,
            title: title,
            options: options
        })
        PACSCommands.commandAvailabilityProbe := (*) => true
    }

    ActivationFailureDoesNotSend() {
        driver := FakeWindowDriver(false)
        AppControl.windowDriver := driver

        Assert.False(AppControl.SendKeysToWindow("PowerScribe", "{F12}"))
        Assert.Equal(3, driver.calls.Length)
        Assert.Equal("activate", driver.calls[3].kind)
        Assert.Equal("ahk_id 501", driver.calls[3].value)
    }

    ActivationCanSucceedButFocusCheckStopsSend() {
        driver := FakeWindowDriver(true, false)
        AppControl.windowDriver := driver

        Assert.False(AppControl.SendKeysToWindow("PowerScribe", "{F12}"))
        Assert.Equal(6, driver.calls.Length)
        Assert.Equal("activate", driver.calls[3].kind)
        Assert.Equal("active", driver.calls[6].kind)
    }

    TargetedSendActivatesBeforeSending() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        Assert.True(AppControl.SendKeysToWindow("Vue PACS Client", "{Right}"))
        Assert.Equal(7, driver.calls.Length)
        Assert.Equal("activate", driver.calls[3].kind)
        Assert.Equal("ahk_id 501", driver.calls[3].value)
        Assert.Equal("active", driver.calls[6].kind)
        Assert.Equal("ahk_id 501", driver.calls[6].value)
        Assert.Equal("keys", driver.calls[7].kind)
        Assert.Equal("{Right}", driver.calls[7].value)
    }

    AmbiguousTargetedSendDoesNotActivateOrSend() {
        driver := FakeWindowDriver(true, true, [
            {hwnd: 501, pid: 42},
            {hwnd: 502, pid: 43}
        ])
        AppControl.windowDriver := driver

        Assert.False(AppControl.SendKeysToWindow("Clinical Window", "^d"))
        Assert.Equal(1, driver.calls.Length)
        Assert.Equal("list", driver.calls[1].kind)
    }

    ExactWindowResolverRejectsSubstringAndDuplicateMatches() {
        exact := {hwnd: 501, title: "Vue PACS Client", exe: "mp.exe", pid: 42}
        suffix := {hwnd: 502, title: "Vue PACS Client Extra", exe: "mp.exe", pid: 42}
        spec := AppControl.ExactWindowSpec("Vue PACS Client", "mp.exe")

        AppControl.windowDriver := FakeExactWindowDriver([exact, suffix])
        Assert.Equal(501, AppControl.ResolveUniqueExactWindow(spec).hwnd)

        AppControl.windowDriver := FakeExactWindowDriver([suffix])
        Assert.Equal(0, AppControl.ResolveUniqueExactWindow(spec))

        AppControl.windowDriver := FakeExactWindowDriver([exact, {
            hwnd: 503,
            title: "Vue PACS Client",
            exe: "mp.exe",
            pid: 43
        }])
        Assert.Equal(0, AppControl.ResolveUniqueExactWindow(spec))
    }

    PacsSeriesCommandsUseExactHwndTarget() {
        driver := FakeExactWindowDriver([{
            hwnd: 501,
            title: "Vue PACS Client",
            exe: "mp.exe",
            pid: 42
        }])
        AppControl.windowDriver := driver

        PACSCommands.commands["Next Series"].Call()

        expected := "ahk_id 501"
        Assert.Equal(expected, driver.calls[1].value)
        Assert.Equal(expected, driver.calls[2].value)
        Assert.Equal("{Right}", driver.calls[3].value)
    }

    BuiltInClinicalCommandUsesConfirmedTarget() {
        driver := FakeExactWindowDriver([{
            hwnd: 601,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 77
        }])
        AppControl.windowDriver := driver

        PACSCommands.commands["Sign Report"].Call()

        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("ahk_id 601", driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("{F12}", driver.calls[3].value)
    }

    WindowToggleRevalidatesUniqueSessionBeforeMutation() {
        spec := AppControl.ExactWindowSpec("PowerScribe 360 | Reporting", "Nuance.PowerScribe360.exe")
        driver := ToggleRaceWindowDriver([{
            hwnd: 501,
            title: spec.title,
            exe: spec.exe,
            pid: 42
        }])
        AppControl.windowDriver := driver
        driver.addDuplicateOnStateRead := true

        result := AppControl.ToggleExactWindow(spec)

        Assert.False(result)
        Assert.Equal(0, driver.minimizeCalls)
        Assert.Equal(0, driver.activateCalls)
    }

    NativePowerScribeCaptureRejectsImpostorAndDuplicate() {
        exact := {
            hwnd: 601,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 77
        }
        suffix := {
            hwnd: 602,
            title: AppControl.powerScribeReportingTitle " Extra",
            exe: AppControl.powerScribeExecutable,
            pid: 77
        }
        nativeDriver := NativePowerScribeSessionDriver()

        AppControl.windowDriver := FakeExactWindowDriver([exact, suffix])
        Assert.Equal(601, nativeDriver.Capture(PowerScribe.windowTitle).hwnd)

        AppControl.windowDriver := FakeExactWindowDriver([suffix])
        Assert.Equal(0, nativeDriver.Capture(PowerScribe.windowTitle))

        AppControl.windowDriver := FakeExactWindowDriver([exact, {
            hwnd: 603,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 78
        }])
        Assert.Equal(0, nativeDriver.Capture(PowerScribe.windowTitle))
    }

    TargetedCustomCommandUsesConfirmedTarget() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        command := PACSCommands.CreateCustomKeybind("^d", "Custom Clinical Window")

        command.Call()

        Assert.Equal("activate", driver.calls[3].kind)
        Assert.Equal("ahk_id 501", driver.calls[3].value)
        Assert.Equal("active", driver.calls[6].kind)
        Assert.Equal("^d", driver.calls[7].value)
    }

    ClinicalCommandGateRejectsNestedBuiltIn() {
        driver := FakeExactWindowDriver([{
            hwnd: 501,
            title: "Vue PACS Client",
            exe: "mp.exe",
            pid: 42
        }])
        AppControl.windowDriver := driver

        nestedResult := PACSCommands.RunClinicalCommand(
            "Outer clinical workflow",
            (*) => PACSCommands.commands["Next Series"].Call()
        )
        callsDuringOuter := driver.calls.Length
        gateReleased := !PACSCommands.clinicalCommandActive

        PACSCommands.commands["Next Series"].Call()

        Assert.False(nestedResult)
        Assert.Equal(0, callsDuringOuter)
        Assert.Equal(1, this.busyNotifications.Length)
        Assert.True(gateReleased)
        Assert.Equal("keys", driver.calls[3].kind)
        Assert.Equal("{Right}", driver.calls[3].value)
    }

    ShutdownGateRejectsNewClinicalCommand() {
        callbackCalls := 0
        PACSCommands.commandAvailabilityProbe := (*) => false

        result := PACSCommands.RunClinicalCommand(
            "Sign Report",
            (*) => callbackCalls++
        )

        Assert.False(result)
        Assert.Equal(0, callbackCalls)
        Assert.False(PACSCommands.clinicalCommandActive)
        Assert.Equal(1, this.busyNotifications.Length)
        Assert.True(InStr(this.busyNotifications[1].text, "shutting down") > 0)
    }

    UnavailableAttendingAssignmentHasNoWindowSideEffects() {
        windowDriver := FakeWindowDriver()
        sessionDriver := FakePowerScribeSessionDriver()
        PowerScribe.sessionDriver := sessionDriver
        AppControl.windowDriver := windowDriver

        Assert.False(PowerScribe.SetAttending("Smith"))
        Assert.Equal(0, sessionDriver.captureCalls)
        Assert.Equal(0, windowDriver.calls.Length)
    }

    AttendingRoutingUsesInjectedDependencies() {
        lookedUp := []
        assigned := []
        lookup := (modality) => (lookedUp.Push(modality), "Smith")
        writer := (attending) => (assigned.Push(attending), true)

        modality := AttendingRouting.Route("EXAMINATION: CT CHEST", lookup, writer)

        Assert.Equal("Chest", modality)
        Assert.Equal("Chest", lookedUp[1])
        Assert.Equal("Smith", assigned[1])
    }

    BlankAttendingSkipsPowerScribeWrite() {
        writes := []

        modality := AttendingRouting.Route(
            "EXAMINATION: MRI BRAIN",
            (*) => "",
            (attending) => writes.Push(attending)
        )

        Assert.Equal("Neuro", modality)
        Assert.Equal(0, writes.Length)
    }

    UnknownExaminationRequiresManualAssignment() {
        lookups := 0
        writes := 0

        Assert.Throws(
            () => AttendingRouting.Route(
                "EXAMINATION: PET UNKNOWN PROTOCOL",
                (*) => lookups++,
                (*) => writes++
            ),
            "manual"
        )
        Assert.Equal(0, lookups)
        Assert.Equal(0, writes)
    }

    FailedAttendingControlIsReported() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Chest"] := "Smith"
        ProfileManager.profiles["Test"] := profile
        ProfileManager.currentProfile := "Test"
        AppControl.windowDriver := FakeWindowDriver(false)

        Assert.Throws(
            () => checkAttending("EXAMINATION: CT CHEST"),
            "could not safely assign attending 'Smith'"
        )
    }

    NativeLookupErrorsAreNotAbsence() {
        driver := NativeAppLifecycleDriver()

        Assert.Throws(() => driver.FindProcess({}))
        Assert.Throws(() => driver.ProcessExists({}))
    }

    WindowCloseUncertaintyCancelsStop() {
        driver := FakeAppLifecycleDriver("close-error")
        AppControl.lifecycleDriver := driver
        AppControl.windowDriver := driver

        result := AppControl.StopTarget(
            AppControl.ExactWindowSpec("Vue PACS", "mp.exe"),
            "window"
        )

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.True(InStr(result.error, "close failed") > 0)
        Assert.Equal(0, driver.killCalls)
    }

    WindowCloseCarriesAndRevalidatesCapturedSession() {
        driver := RetitledWindowDriver()
        AppControl.lifecycleDriver := NativeAppLifecycleDriver()
        AppControl.windowDriver := driver

        result := AppControl.StopTarget(
            AppControl.ExplorerPortalWindowSpec(),
            "window"
        )

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.True(driver.titleReads >= 2)
    }

    AmbiguousSharedHostWindowsAreNotClosed() {
        driver := SharedHostWindowLifecycleDriver()
        AppControl.lifecycleDriver := driver
        AppControl.windowDriver := driver

        result := AppControl.StopTarget(
            AppControl.ExplorerPortalWindowSpec(),
            "window"
        )

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.True(InStr(result.error, "multiple") > 0)
        Assert.Equal(0, driver.processLookupCalls)
        Assert.Equal(0, driver.closeCalls)
        Assert.Equal(0, driver.killCalls)
        Assert.Equal(0, driver.stopProcessCalls)
        Assert.Equal(3, driver.windows.Length)
    }

    RestartRejectsBareProcessTermination() {
        driver := SameTitleWindowLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.False(result.found)
        Assert.False(result.stopped)
        Assert.Equal(0, driver.windowLookupCalls)
        Assert.Equal(0, driver.killCalls)
        Assert.Equal(0, driver.stopProcessCalls)
        Assert.True(InStr(result.error, "not supported") > 0)
    }

    RestartSpecsNeverHardStopPowerScribe() {
        for spec in AppControl.PacsRestartTargetSpecs() {
            Assert.False(
                spec.kind = "process" && spec.target = AppControl.powerScribeExecutable,
                "PowerScribe must not be hard-killed after an unverified save"
            )
        }
    }

    RestartAbortsWhenPowerScribeSaveIsUnverified() {
        driver := FakePacsRestartDriver([{
            hwnd: 601,
            target: "ahk_id 601",
            processId: 77
        }], 77, false)

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartAbortsForUnverifiedPowerScribeProcess() {
        driver := FakePacsRestartDriver([], 77, true)

        Assert.False(restartPACS(driver))
        Assert.Equal(0, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartAbortsWhenAnotherPowerScribeProcessSurvivesGracefulClose() {
        driver := FakePacsRestartDriver([{
            hwnd: 601,
            target: "ahk_id 601",
            processId: 77
        }], 88, true)

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartPreparationFailureHasNoClinicalSideEffects() {
        driver := FakePacsRestartDriver([{
            hwnd: 601,
            target: "ahk_id 601",
            processId: 77
        }], 0, true)
        driver.prepareResult := false

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.prepareCalls)
        Assert.Equal(0, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartPreparationCapturesHiddenTrustedVueProcesses() {
        originalWindowDriver := AppControl.windowDriver
        originalLifecycleDriver := AppControl.lifecycleDriver
        trustedPath := A_Temp "\Philips\Vue\mp.exe"
        try {
            AppControl.windowDriver := FakeExactWindowDriver([{
                hwnd: 501,
                title: AppControl.vuePacsTitle,
                exe: AppControl.vuePacsExecutable,
                pid: 42
            }])
            AppControl.lifecycleDriver := FakeProcessInventoryLifecycleDriver(
                Map(42, trustedPath, 99, trustedPath),
                [
                    {processId: 42, name: AppControl.vuePacsExecutable, path: trustedPath},
                    {processId: 99, name: AppControl.vuePacsExecutable, path: trustedPath}
                ]
            )
            driver := NativePacsRestartDriver()

            Assert.True(driver.PrepareRestart())
            Assert.True(driver.priorVueProcessIds.Has(42))
            Assert.True(driver.priorVueProcessIds.Has(99))
            Assert.Equal(trustedPath, driver.trustedVueExecutablePath)
        } finally {
            AppControl.windowDriver := originalWindowDriver
            AppControl.lifecycleDriver := originalLifecycleDriver
        }
    }

    RestartAbortsWhenTargetReappearsBeforeLaunch() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.quiescent := false

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(1, driver.verifyCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartStopBoundaryFailureCancelsLaunch() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.stopError := "simulated stop failure"

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartRejectsMalformedStopResult() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.stopResult := {anyStopped: false}

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartLaunchBoundaryFailuresAreReported() {
        launchDriver := FakePacsRestartDriver([], 0, true)
        launchDriver.launchError := "simulated launch failure"
        Assert.False(restartPACS(launchDriver))
        Assert.Equal(1, launchDriver.launchCalls)
        Assert.Equal(0, launchDriver.waitForLaunchCalls)

        verifyDriver := FakePacsRestartDriver([], 0, true)
        verifyDriver.waitForLaunchError := "simulated launch verification failure"
        Assert.False(restartPACS(verifyDriver))
        Assert.Equal(1, verifyDriver.launchCalls)
        Assert.Equal(1, verifyDriver.waitForLaunchCalls)
    }

    RestartRequiresExpectedVueWindowAfterLaunch() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.launchVerified := false

        Assert.False(restartPACS(driver))
        Assert.Equal(1, driver.launchCalls)
        Assert.Equal(1, driver.waitForLaunchCalls)
    }

    RestartLaunchProofRequiresANewStableVueSession() {
        originalWindowDriver := AppControl.windowDriver
        originalLifecycleDriver := AppControl.lifecycleDriver
        trustedPath := A_Temp "\Philips\Vue\mp.exe"
        try {
            native := NativePacsRestartDriver()
            native.trustedVueExecutablePath := trustedPath
            AppControl.lifecycleDriver := FakeProcessInventoryLifecycleDriver(
                Map(
                    42, trustedPath,
                    43, trustedPath,
                    51, trustedPath,
                    52, trustedPath,
                    61, trustedPath
                ),
                []
            )
            native.priorVueProcessIds := Map(42, true)
            AppControl.windowDriver := SequencedLaunchWindowDriver([
                [{hwnd: 701, pid: 42}],
                [{hwnd: 702, pid: 43}]
            ])
            Assert.False(native.WaitForLaunch(350))

            native.priorVueProcessIds := Map()
            AppControl.windowDriver := SequencedLaunchWindowDriver([
                [{hwnd: 801, pid: 51}],
                [{hwnd: 802, pid: 52}]
            ])
            Assert.False(native.WaitForLaunch(350))

            AppControl.windowDriver := SequencedLaunchWindowDriver([
                [{hwnd: 901, pid: 61}],
                [{hwnd: 901, pid: 61}]
            ])
            Assert.True(native.WaitForLaunch(350))
        } finally {
            AppControl.windowDriver := originalWindowDriver
            AppControl.lifecycleDriver := originalLifecycleDriver
        }
    }

    GracefulCloseTimesOutAcross32BitTickWrap() {
        driver := FakeGracefulCloseDriver(0xFFFFFFFF - 50, 77)

        Assert.False(closeWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(1, driver.closeRequests)
        Assert.True(driver.pauseCalls >= 2)
    }

    GracefulCloseRequiresCapturedProcessIdentity() {
        driver := FakeGracefulCloseDriver(1000, 88)

        Assert.False(closeWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(0, driver.closeRequests)
    }

    GracefulCloseRejectsSameProcessWrongTitleBeforeRequest() {
        driver := FakeGracefulCloseDriver(1000, 77, false)

        Assert.False(closeWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(0, driver.closeRequests)
    }

    GracefulCloseRejectsDuplicateExactWindowBeforeRequest() {
        driver := FakeGracefulCloseDriver(1000, 77, false)

        Assert.False(closeWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(0, driver.closeRequests)
    }

    PowerScribeSession() {
        return {
            hwnd: 601,
            target: "ahk_id 601",
            processId: 77,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable
        }
    }

    RestartTargetsUseExactClinicalIdentities() {
        specs := AppControl.PacsRestartTargetSpecs()

        for spec in specs {
            Assert.True(HasProp(spec, "kind"))
            Assert.Equal("window", spec.kind)
            Assert.True(IsObject(spec.target))
            Assert.True(HasProp(spec.target, "title"))
            Assert.True(HasProp(spec.target, "exe"))
        }
        Assert.Equal(3, specs.Length)

        Assert.Equal(
            "PowerScribe 360 | Reporting ahk_exe " AppControl.powerScribeExecutable,
            PowerScribe.windowTitle
        )
        Assert.Equal(PowerScribe.windowTitle, AppControl.PacsGracefulCloseTarget())
    }

    PacsLauncherRejectsNonShortcutMatch() {
        root := A_Temp "\pacs_launch_" A_TickCount "_" Random(1000, 9999)
        DirCreate(root)
        FileAppend("not a shortcut", root "\Vue Client (Integrated) helper.cmd")
        driver := FakeAppLifecycleDriver("launcher")
        AppControl.lifecycleDriver := driver

        try {
            Assert.False(AppControl.LaunchVuePacs(root))
            Assert.Equal(0, driver.launches.Length)
        } finally {
            DirDelete(root, true)
        }
    }

    PacsLauncherRejectsRetargetedShortcut() {
        root := A_Temp "\pacs_launch_retarget_" A_TickCount "_" Random(1000, 9999)
        DirCreate(root)
        shortcut := root "\Vue Client (Integrated).lnk"
        target := root "\notepad.exe"
        FileAppend("test shortcut", shortcut)
        FileAppend("test target", target)
        driver := FakeAppLifecycleDriver("launcher")
        driver.shortcutTarget := target
        AppControl.lifecycleDriver := driver

        try Assert.False(AppControl.LaunchVuePacs(root, root "\mp.exe"))
        finally DirDelete(root, true)

        Assert.Equal(0, driver.launches.Length)
    }

    PacsLauncherRejectsUntrustedSameNamedExecutable() {
        root := A_Temp "\pacs_launch_untrusted_" A_TickCount "_" Random(1000, 9999)
        trustedRoot := root "\trusted"
        otherRoot := root "\other"
        DirCreate(trustedRoot)
        DirCreate(otherRoot)
        shortcut := root "\Vue Client (Integrated).lnk"
        trustedTarget := trustedRoot "\mp.exe"
        otherTarget := otherRoot "\mp.exe"
        FileAppend("test shortcut", shortcut)
        FileAppend("trusted target", trustedTarget)
        FileAppend("untrusted target", otherTarget)
        driver := FakeAppLifecycleDriver("launcher")
        driver.shortcutTarget := otherTarget
        AppControl.lifecycleDriver := driver

        try Assert.False(AppControl.LaunchVuePacs(root, trustedTarget))
        finally DirDelete(root, true)

        Assert.Equal(0, driver.launches.Length)
    }

    PacsLauncherAcceptsInstalledShortcut() {
        root := A_Temp "\pacs_launch_" A_TickCount "_" Random(1000, 9999)
        DirCreate(root)
        shortcut := root "\Vue Client (Integrated).lnk"
        target := root "\mp.exe"
        FileAppend("test shortcut", shortcut)
        FileAppend("test target", target)
        driver := FakeAppLifecycleDriver("launcher")
        driver.shortcutTarget := target
        AppControl.lifecycleDriver := driver

        try {
            Assert.True(AppControl.LaunchVuePacs(root, target))
            Assert.Equal(1, driver.launches.Length)
            Assert.Equal(shortcut, driver.launches[1])
        } finally {
            DirDelete(root, true)
        }
    }

    ReportSelectionUsesOnlyReportShapedText() {
        report := "EXAMINATION: MRI BRAIN`n`nFINDINGS: Normal."
        candidates := [
            "Search",
            "This is a very long unrelated document value that must never determine routing.",
            report
        ]

        Assert.Equal(report, PowerScribe.SelectReportText(candidates, "unrelated fallback"))
    }

    ReportSelectionRejectsMultipleReportCandidates() {
        Assert.Equal(
            "",
            PowerScribe.SelectReportText([
                "EXAMINATION: MRI BRAIN`nFINDINGS: Current report.",
                "EXAMINATION: CT CHEST`nFINDINGS: Prior report."
            ])
        )
        Assert.Equal(
            "",
            PowerScribe.SelectReportText(
                ["EXAMINATION: MRI BRAIN"],
                "EXAMINATION: CT CHEST"
            )
        )
    }

    ReportSelectionRejectsUnrelatedFallbackText() {
        Assert.Equal(
            "",
            PowerScribe.SelectReportText(["Search", "Patient information"], "long unrelated fallback text")
        )
        fallbackReport := "EXAMINATION: XR KNEE`nFINDINGS: No fracture."
        Assert.Equal(fallbackReport, PowerScribe.SelectReportText([], fallbackReport))
    }

    ReportCaptureFailsClosedOnEnumerationError() {
        session := {hwnd: 800, target: "ahk_id 800", processId: 42}
        PowerScribe.sessionDriver := FixedReportRootSessionDriver(
            session,
            ThrowingReportEnumerationRoot(800, 42)
        )

        Assert.Equal("", PowerScribe.ReadReportText(session))
    }

    ReportCaptureFailsClosedOnUnreadableSibling() {
        session := {hwnd: 801, target: "ahk_id 801", processId: 42}
        valid := FakePowerScribeReportElement(
            801,
            42,
            "EXAMINATION: CT CHEST`nFINDINGS: Current report."
        )
        PowerScribe.sessionDriver := FixedReportRootSessionDriver(
            session,
            UncertainReportRoot(801, 42, [valid, {}])
        )

        Assert.Equal("", PowerScribe.ReadReportText(session))
    }

    ReportCaptureFailsClosedOnUnsupportedSibling() {
        session := {hwnd: 802, target: "ahk_id 802", processId: 42}
        valid := FakePowerScribeReportElement(
            802,
            42,
            "EXAMINATION: CT CHEST`nFINDINGS: Current report."
        )
        PowerScribe.sessionDriver := FixedReportRootSessionDriver(
            session,
            UncertainReportRoot(802, 42, [valid, UnsupportedPowerScribeReportElement(802, 42)])
        )

        Assert.Equal("", PowerScribe.ReadReportText(session))
    }

    Teardown() {
        AppControl.windowDriver := this.originalDriver
        if this.originalLifecycleDriver
            AppControl.lifecycleDriver := this.originalLifecycleDriver
        PowerScribe.sessionDriver := this.originalPowerScribeSessionDriver
        ProfileManager.profiles := this.originalProfiles
        ProfileManager.currentProfile := this.originalCurrentProfile
        PACSCommands.clinicalCommandActive := this.originalClinicalCommandActive
        PACSCommands.activeClinicalCommand := this.originalActiveClinicalCommand
        PACSCommands.busyNotifier := this.originalBusyNotifier
        PACSCommands.commandAvailabilityProbe := this.originalCommandAvailabilityProbe
    }
}

class FakeWindowDriver {
    __New(activationResult := true, activeResults := true, selectorWindows := 0) {
        this.activationResult := activationResult
        this.activeResults := activeResults is Array ? activeResults.Clone() : [activeResults]
        this.selectorWindows := IsObject(selectorWindows)
            ? selectorWindows.Clone()
            : [{hwnd: 501, pid: 42}]
        this.calls := []
    }

    ListWindows(selector) {
        this.calls.Push({kind: "list", value: selector})
        handles := []
        for window in this.selectorWindows
            handles.Push(window.hwnd)
        return handles
    }

    GetProcessId(hwnd) {
        this.calls.Push({kind: "pid", value: hwnd})
        for window in this.selectorWindows {
            if (window.hwnd = hwnd)
                return window.pid
        }
        return 0
    }

    Activate(title, timeoutSeconds) {
        this.calls.Push({kind: "activate", value: title, timeout: timeoutSeconds})
        return this.activationResult
    }

    IsActive(title) {
        this.calls.Push({kind: "active", value: title})
        return this.activeResults.Length ? this.activeResults.RemoveAt(1) : true
    }

    SendKeys(keys) {
        this.calls.Push({kind: "keys", value: keys})
    }

    Pause(milliseconds) {
        this.calls.Push({kind: "pause", value: milliseconds})
    }
}

class FakeExactWindowDriver extends FakeWindowDriver {
    __New(windows) {
        super.__New()
        this.windows := windows.Clone()
    }

    ListWindowsByExecutable(executable) {
        handles := []
        for window in this.windows {
            if (window.exe = executable)
                handles.Push(window.hwnd)
        }
        return handles
    }

    Window(hwnd) {
        for window in this.windows {
            if (window.hwnd = hwnd)
                return window
        }
        throw Error("unknown fake window")
    }

    GetTitle(hwnd) {
        return this.Window(hwnd).title
    }

    GetProcessName(hwnd) {
        return this.Window(hwnd).exe
    }

    GetProcessId(hwnd) {
        return this.Window(hwnd).pid
    }
}

class ToggleRaceWindowDriver extends FakeExactWindowDriver {
    __New(windows) {
        super.__New(windows)
        this.addDuplicateOnStateRead := false
        this.minimizeCalls := 0
        this.activateCalls := 0
    }

    GetMinMax(*) {
        if this.addDuplicateOnStateRead {
            first := this.windows[1]
            this.windows.Push({
                hwnd: 777,
                title: first.title,
                exe: first.exe,
                pid: 77
            })
        }
        return 0
    }

    Minimize(*) {
        this.minimizeCalls++
    }

    Activate(*) {
        this.activateCalls++
        return true
    }
}

class SequencedLaunchWindowDriver extends FakeExactWindowDriver {
    __New(snapshots) {
        this.snapshots := snapshots.Clone()
        this.snapshotIndex := 0
        super.__New([])
    }

    ListWindowsByExecutable(executable) {
        if (executable != AppControl.vuePacsExecutable)
            return []
        this.snapshotIndex := Min(this.snapshotIndex + 1, this.snapshots.Length)
        this.windows := []
        for item in this.snapshots[this.snapshotIndex] {
            this.windows.Push({
                hwnd: item.hwnd,
                title: AppControl.vuePacsTitle,
                exe: AppControl.vuePacsExecutable,
                pid: item.pid
            })
        }
        return super.ListWindowsByExecutable(executable)
    }
}

class FakePacsRestartDriver {
    __New(powerScribeWindows, powerScribePid, closeResult) {
        this.powerScribeWindows := powerScribeWindows
        this.powerScribePid := powerScribePid
        this.closeResult := closeResult
        this.closeCalls := 0
        this.stopCalls := 0
        this.launchCalls := 0
        this.verifyCalls := 0
        this.waitForLaunchCalls := 0
        this.prepareCalls := 0
        this.prepareResult := true
        this.quiescent := true
        this.launchVerified := true
        this.stopResult := {anyStopped: false, failedTargets: []}
        this.stopError := ""
        this.launchError := ""
        this.waitForLaunchError := ""
    }

    PrepareRestart() {
        this.prepareCalls++
        return this.prepareResult
    }

    FindPowerScribeWindows() {
        return this.powerScribeWindows
    }

    FindPowerScribeProcess() {
        return this.powerScribePid
    }

    ClosePowerScribe(*) {
        this.closeCalls++
        return this.closeResult
    }

    StopTargets(*) {
        this.stopCalls++
        if (this.stopError != "")
            throw Error(this.stopError)
        return this.stopResult
    }

    Pause(*) {
    }

    Launch() {
        this.launchCalls++
        if (this.launchError != "")
            throw Error(this.launchError)
        return true
    }

    VerifyQuiescence() {
        this.verifyCalls++
        return {
            clear: this.quiescent,
            error: this.quiescent ? "" : "Vue PACS reappeared"
        }
    }

    WaitForLaunch(*) {
        this.waitForLaunchCalls++
        if (this.waitForLaunchError != "")
            throw Error(this.waitForLaunchError)
        return this.launchVerified
    }
}

class FakeProcessInventoryLifecycleDriver {
    __New(pathsByProcessId, processes) {
        this.pathsByProcessId := pathsByProcessId
        this.processes := processes
    }

    ProcessPath(processId) {
        if !this.pathsByProcessId.Has(processId)
            throw Error("unknown process")
        return this.pathsByProcessId[processId]
    }

    ListProcessesByExecutable(*) {
        return this.processes
    }
}

class FakeGracefulCloseDriver {
    __New(now, processId, sessionValid := true) {
        this.now := now
        this.processId := processId
        this.sessionValid := sessionValid
        this.closeRequests := 0
        this.pauseCalls := 0
    }

    FindWindow(*) {
        return 601
    }

    GetProcessId(*) {
        return this.processId
    }

    IsExpectedSession(*) {
        return this.sessionValid
    }

    RequestClose(*) {
        this.closeRequests++
    }

    ProcessExists(*) {
        return true
    }

    NowMilliseconds() {
        return this.now
    }

    Pause(milliseconds) {
        this.pauseCalls++
        this.now += milliseconds
    }
}

class FakePowerScribeSessionDriver {
    __New(session := 0, reportText := "EXAMINATION: CT CHEST") {
        this.session := session ? session : {hwnd: 100, target: "ahk_id 100", processId: 42}
        if !HasProp(this.session, "reportText")
            this.session.reportText := reportText
        this.reportText := reportText
        this.captureCalls := 0
    }

    Capture(*) {
        this.captureCalls++
        return this.session
    }

    IsLive(session) {
        return session && session.hwnd = this.session.hwnd
    }

    Root(session) {
        return this.IsLive(session)
            ? FakePowerScribeReportRoot(session.hwnd, session.processId, this.reportText)
            : 0
    }
}

class FakePowerScribeReportRoot {
    __New(hwnd, processId, reportText) {
        this.WinId := hwnd
        this.ProcessId := processId
        this.report := FakePowerScribeReportElement(hwnd, processId, reportText)
    }

    FindElements(condition) {
        return condition.Type = "Document" ? [this.report] : []
    }

    ElementFromPath(*) {
        return this.report
    }
}

class FakePowerScribeReportElement {
    __New(hwnd, processId, value) {
        this.WinId := hwnd
        this.ProcessId := processId
        this.Type := UIA.Type.Document
        this.value := value
    }

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return this.value
            case UIA.Property.IsValuePatternAvailable: return true
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return false
        }
        return ""
    }
}

class UnsupportedPowerScribeReportElement {
    __New(hwnd, processId) {
        this.WinId := hwnd
        this.ProcessId := processId
        this.Type := UIA.Type.Document
    }

    GetPropertyValue(*) {
        return ""
    }
}

class FixedReportRootSessionDriver {
    __New(session, root) {
        this.session := session
        this.rootElement := root
    }

    Root(session) {
        return this.IsLive(session) ? this.rootElement : 0
    }

    IsLive(session) {
        return session.hwnd = this.session.hwnd
            && session.processId = this.session.processId
    }
}

class ThrowingReportEnumerationRoot {
    __New(hwnd, processId) {
        this.WinId := hwnd
        this.ProcessId := processId
    }

    FindElements(*) {
        throw Error("simulated report enumeration failure")
    }
}

class UncertainReportRoot {
    __New(hwnd, processId, controls) {
        this.WinId := hwnd
        this.ProcessId := processId
        this.controls := controls
    }

    FindElements(condition) {
        return condition.Type = "Document" ? this.controls : []
    }

    ElementFromPath(*) {
        throw Error("no positional fallback")
    }
}

class FakeAppLifecycleDriver {
    __New(mode) {
        this.mode := mode
        this.launches := []
        this.killCalls := 0
        this.processAvailable := true
        this.shortcutTarget := ""
    }

    FindProcess(target) {
        if (this.mode = "lookup-error")
            throw Error("lookup failed")
        if (this.mode = "close-error")
            return 0
        return this.processAvailable ? 4242 : 0
    }

    FindWindow(target) {
        if (this.mode = "close-error")
            return 31337
        return 0
    }

    ListWindowsByExecutable(*) {
        return this.mode = "close-error" ? [31337] : []
    }

    GetTitle(*) {
        return "Vue PACS"
    }

    GetProcessName(*) {
        return "mp.exe"
    }

    GetProcessId(*) {
        return 4242
    }

    GetWindowProcessId(hwnd) {
        return 0
    }

    CloseWindow(*) {
        if (this.mode = "close-error")
            throw Error("close failed")
        return true
    }

    ProcessExists(pid) {
        return this.mode = "stubborn" && this.processAvailable
    }

    WindowExists(hwnd) {
        return false
    }

    StopProcess(pid) {
        if (this.mode = "already-exited") {
            this.processAvailable := false
            throw Error("process disappeared before termination")
        }
        if (this.mode = "stubborn")
            return false
        this.processAvailable := false
        return true
    }

    KillWindow(hwnd) {
        this.killCalls++
        return true
    }

    Launch(path) {
        this.launches.Push(path)
        return true
    }

    ResolveShortcut(path) {
        if (this.shortcutTarget != "")
            return this.shortcutTarget
        SplitPath(path, , &directory)
        return directory "\mp.exe"
    }
}

class SharedHostWindowLifecycleDriver {
    __New() {
        this.windows := [31337, 41414, 51515]
        this.processLookupCalls := 0
        this.closeCalls := 0
        this.killCalls := 0
        this.stopProcessCalls := 0
    }

    FindProcess(*) {
        this.processLookupCalls++
        return 4242
    }

    FindWindow(*) {
        return this.windows.Length ? this.windows[1] : 0
    }

    ListWindowsByExecutable(*) {
        return this.windows.Clone()
    }

    GetTitle(hwnd) {
        return hwnd = 51515 ? "Explorer Portal Extra" : "Explorer Portal"
    }

    GetProcessName(*) {
        return "msedge.exe"
    }

    GetProcessId(*) {
        return 4242
    }

    GetWindowProcessId(*) {
        return 4242
    }

    ProcessExists(*) {
        return true
    }

    CloseWindow(hwnd) {
        this.closeCalls++
        if IsObject(hwnd)
            hwnd := hwnd.hwnd
        for index, candidate in this.windows {
            if (candidate = hwnd) {
                this.windows.RemoveAt(index)
                break
            }
        }
        return true
    }

    KillWindow(*) {
        this.killCalls++
        return false
    }

    StopProcess(*) {
        this.stopProcessCalls++
        return true
    }
}

class RetitledWindowDriver {
    __New() {
        this.titleReads := 0
    }

    ListWindowsByExecutable(*) {
        return [31337]
    }

    GetTitle(*) {
        this.titleReads++
        return this.titleReads = 1 ? "Explorer Portal" : "Unrelated Edge Window"
    }

    GetProcessName(*) {
        return "msedge.exe"
    }

    GetProcessId(*) {
        return 4242
    }

}

class SameTitleWindowLifecycleDriver {
    __New() {
        this.windowLookupCalls := 0
        this.killCalls := 0
        this.stopProcessCalls := 0
    }

    FindProcess(*) {
        return 0
    }

    FindWindow(*) {
        this.windowLookupCalls++
        return 31337
    }

    GetWindowProcessId(*) {
        return 4242
    }

    KillWindow(*) {
        this.killCalls++
        return true
    }

    ProcessExists(*) {
        return false
    }

    StopProcess(*) {
        this.stopProcessCalls++
        return true
    }
}
