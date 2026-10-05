; = CONTENTS
;   + Preamble
;   + ClinicalAutomationTest class (window targeting, activation, clinical command, restart, graceful close)
;   + Test doubles (window/restart/close/PowerScribe drivers, report roots & elements, lifecycle drivers)

#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk
#Include FakeWindowList.ahk
#Include LogCapture.ahk

class ClinicalAutomationTest {
    static tests := [
        "ActivationFailureDoesNotSend",
        "ActivationCanSucceedButFocusCheckStopsSend",
        "TargetedSendActivatesBeforeSending",
        "AmbiguousTargetedSendDoesNotActivateOrSend",
        "SelectorSendStopsWhenTheWindowIsReplacedDuringActivation",
        "ExactSendStopsWhenTheWindowIsReplacedDuringActivation",
        "ExactWindowResolverRejectsSubstringAndDuplicateMatches",
        "PacsSeriesCommandsUseExactHwndTarget",
        "BuiltInClinicalCommandUsesConfirmedTarget",
        "WindowToggleRevalidatesUniqueSessionBeforeMutation",
        "WindowToggleMinimizesAVisibleWindowAndRestoresAMinimizedOne",
        "PowerScribeToggleCommandTargetsTheExactReportingWindow",
        "NativePowerScribeCaptureRejectsImpostorAndDuplicate",
        "NativePowerScribeLivenessRequiresExactIdentity",
        "TargetedCustomCommandUsesConfirmedTarget",
        "ClinicalCommandGateRejectsNestedBuiltIn",
        "ShutdownGateRejectsNewClinicalCommand",
        "ClinicalCommandDialogsWaitForTheLeaseRelease",
        "NoticesShowAtOnceOutsideACommandAndAfterAFailedCommand",
        "UnavailableAttendingAssignmentHasNoWindowSideEffects",
        "AttendingRoutingUsesInjectedDependencies",
        "BlankAttendingSkipsPowerScribeWrite",
        "UnknownExaminationRequiresManualAssignment",
        "UnavailableAttendingAssignmentIsReported",
        "NativeLookupErrorsAreNotAbsence",
        "WindowCloseUncertaintyCancelsStop",
        "WindowCloseCarriesAndRevalidatesCapturedSession",
        "WindowCloseRecheckRejectsNewDuplicate",
        "AmbiguousSharedHostWindowsAreNotClosed",
        "WindowStopSucceedsWhenTheExactWindowCloses",
        "RestartTargetPreflightPreventsPartialShutdown",
        "RestartStopsAfterRuntimeTargetFailure",
        "RestartRejectsBareProcessTermination",
        "RestartSpecsNeverHardStopPowerScribe",
        "RestartAbortsWhenPowerScribeSaveIsUnverified",
        "RestartAbortsForUnverifiedPowerScribeProcess",
        "RestartAbortsWhenAnotherPowerScribeProcessSurvivesGracefulClose",
        "RestartPreparationFailureHasNoClinicalSideEffects",
        "RestartSucceedsWhenEveryStepIsVerified",
        "RestartPreparationRejectsAmbiguousTargets",
        "RestartPreparationCapturesHiddenTrustedVueProcesses",
        "RestartAbortsWhenTargetReappearsBeforeLaunch",
        "RestartStopBoundaryFailureCancelsLaunch",
        "RestartNamesWhyATargetCouldNotBeStopped",
        "RestartRejectsMalformedStopResult",
        "RestartLaunchBoundaryFailuresAreReported",
        "RestartRequiresExpectedVueWindowAfterLaunch",
        "RestartLaunchProofRequiresANewStableVueSession",
        "GracefulCloseTimesOutAcross32BitTickWrap",
        "GracefulCloseSucceedsWhenTheProcessExits",
        "GracefulCloseRequiresCapturedProcessIdentity",
        "GracefulCloseRejectsSameProcessWrongTitleBeforeRequest",
        "GracefulCloseRejectsDuplicateExactWindowBeforeRequest",
        "GracefulCloseRequestsCloseForTheUniqueExactWindow",
        "RestartTargetsUseExactClinicalIdentities",
        "PacsLauncherRejectsNonShortcutMatch",
        "PacsLauncherRejectsRetargetedShortcut",
        "PacsLauncherRejectsUntrustedSameNamedExecutable",
        "PathsEqualRecognizesShortAndLongWindowsAliases",
        "PacsLauncherAcceptsInstalledShortcut",
        "ReportSelectionUsesOnlyReportShapedText",
        "ReportSelectionRejectsMultipleReportCandidates",
        "ReportSelectionRejectsUnrelatedFallbackText",
        "ReportControlIdentityRequiresEachProperty",
        "ReportCaptureReadsTheOneCurrentReport",
        "ReportCaptureFailsClosedOnEnumerationError",
        "ReportCaptureFailsClosedOnUnreadableSibling",
        "ReportCaptureFailsClosedOnUnsupportedSibling",
        "ExactWindowStatusDistinguishesAbsenceAmbiguityAndFailure"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "PowerScribeSession"
    ]

    Setup() {
        this.originalDriver := AppControl.windowDriver
        this.originalLifecycleDriver := AppControl.lifecycleDriver
        this.originalPowerScribeSessionDriver := PowerScribe.sessionDriver
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
        this.originalClinicalCommandActive := PACSCommands.clinicalCommandActive
        this.originalActiveClinicalCommand := PACSCommands.activeClinicalCommand
        this.originalBusyNotifier := PACSCommands.busyNotifier
        this.originalCommandAvailabilityProbe := PACSCommands.commandAvailabilityProbe
        this.originalNoticePresenter := ClinicalNotices.presenter
        this.busyNotifications := []
        PowerScribe.sessionDriver := FakePowerScribeSessionDriver()
        ProfileManager.profiles := Map()
        ProfileManager.currentProfile := ""
        PACSCommands.clinicalCommandActive := false
        PACSCommands.activeClinicalCommand := ""
        PACSCommands.busyNotifier := RecordNotification.Bind(this.busyNotifications)
        PACSCommands.commandAvailabilityProbe := (*) => true
    }

    ExactWindowStatusDistinguishesAbsenceAmbiguityAndFailure() {
        spec := AppControl.ExplorerPortalWindowSpec()
        portal := {hwnd: 100, pid: 42, exe: "msedge.exe", title: "Explorer Portal", active: false}
        AppControl.windowDriver := FakeWindowList([])
        Assert.Equal("absent", AppControl.ResolveUniqueExactWindowStatus(spec).status)

        AppControl.windowDriver := FakeWindowList([portal])
        unique := AppControl.ResolveUniqueExactWindowStatus(spec)
        Assert.Equal("unique", unique.status)
        Assert.Equal(100, unique.session.hwnd)

        second := {hwnd: 101, pid: 43, exe: "msedge.exe", title: "Explorer Portal", active: false}
        AppControl.windowDriver := FakeWindowList([portal, second])
        Assert.Equal("ambiguous", AppControl.ResolveUniqueExactWindowStatus(spec).status)

        ; A title read failing mid-enumeration is uncertainty, not absence.
        AppControl.windowDriver := FakeWindowList([portal], true)
        failed := AppControl.ResolveUniqueExactWindowStatus(spec)
        Assert.Equal("error", failed.status)
        Assert.True(InStr(failed.error, "simulated title failure"), failed.error)
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

    ; The selector is resolved again after activation; a different window or process
    ; now behind it gets no keys.
    SelectorSendStopsWhenTheWindowIsReplacedDuringActivation() {
        for replacement in [{hwnd: 502, pid: 42}, {hwnd: 501, pid: 43}] {
            ; A closure cannot see the loop variable, so it captures a local copy.
            moved := replacement
            driver := FakeWindowDriver()
            driver.onActivate := (activated) => activated.selectorWindows := [moved]
            AppControl.windowDriver := driver

            Assert.False(AppControl.SendKeysToWindow("Vue PACS Client", "{Right}"))
            for call in driver.calls
                Assert.False(call.kind = "keys", "keys reached hwnd " moved.hwnd " pid " moved.pid)
        }
    }

    ; The exact window is resolved again after activation; a recreated window or a
    ; new process with the same title and executable gets no keys.
    ExactSendStopsWhenTheWindowIsReplacedDuringActivation() {
        original := {hwnd: 601, title: AppControl.powerScribeReportingTitle, exe: AppControl.powerScribeExecutable, pid: 77}
        AppControl.windowDriver := FakeExactWindowDriver([original])
        Assert.True(AppControl.SendKeysToExactWindow(AppControl.PowerScribeWindowSpec(), "{F12}"))

        for replacement in [{hwnd: 602, pid: 77}, {hwnd: 601, pid: 78}] {
            moved := {hwnd: replacement.hwnd, title: original.title, exe: original.exe, pid: replacement.pid}
            driver := FakeExactWindowDriver([original])
            driver.onActivate := (activated) => activated.windows := [moved]
            AppControl.windowDriver := driver

            Assert.False(AppControl.SendKeysToExactWindow(AppControl.PowerScribeWindowSpec(), "{F12}"))
            for call in driver.calls
                Assert.False(call.kind = "keys", "keys reached hwnd " moved.hwnd " pid " moved.pid)
        }
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

    WindowToggleMinimizesAVisibleWindowAndRestoresAMinimizedOne() {
        spec := AppControl.ExactWindowSpec("PowerScribe 360 | Reporting", "Nuance.PowerScribe360.exe")
        driver := ToggleRaceWindowDriver([{
            hwnd: 501,
            title: spec.title,
            exe: spec.exe,
            pid: 42
        }])
        AppControl.windowDriver := driver

        Assert.True(AppControl.ToggleExactWindow(spec))
        Assert.Equal(1, driver.minimizeCalls)
        Assert.Equal(0, driver.activateCalls)

        driver.minMax := -1
        Assert.True(AppControl.ToggleExactWindow(spec))
        Assert.Equal(1, driver.minimizeCalls)
        Assert.Equal(1, driver.activateCalls)
    }

    ; The registered command, not a helper, decides which window it toggles: only
    ; the exact PowerScribe reporting window, never a same-titled impostor.
    PowerScribeToggleCommandTargetsTheExactReportingWindow() {
        reporting := ToggleRaceWindowDriver([{
            hwnd: 601,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 77
        }])
        AppControl.windowDriver := reporting
        PACSCommands.commands["Toggle PowerScribe Window"].Call()
        Assert.Equal(1, reporting.minimizeCalls)

        impostor := ToggleRaceWindowDriver([{
            hwnd: 602,
            title: AppControl.powerScribeReportingTitle,
            exe: "notepad.exe",
            pid: 78
        }])
        AppControl.windowDriver := impostor
        PACSCommands.commands["Toggle PowerScribe Window"].Call()
        Assert.Equal(0, impostor.minimizeCalls)
        Assert.Equal(0, impostor.activateCalls)
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
        Assert.Equal(601, nativeDriver.Capture().hwnd)

        AppControl.windowDriver := FakeExactWindowDriver([suffix])
        Assert.Equal(0, nativeDriver.Capture())

        AppControl.windowDriver := FakeExactWindowDriver([exact, {
            hwnd: 603,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 78
        }])
        Assert.Equal(0, nativeDriver.Capture())
    }

    NativePowerScribeLivenessRequiresExactIdentity() {
        nativeDriver := NativePowerScribeSessionDriver()
        expected := {
            hwnd: 601,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 77
        }
        AppControl.windowDriver := FakeExactWindowDriver([expected])
        session := nativeDriver.Capture()
        Assert.True(nativeDriver.IsLive(session))

        ; The same HWND under another title, executable or process is not this session.
        for changed in [
            {hwnd: 601, title: expected.title " Extra", exe: expected.exe, pid: 77},
            {hwnd: 601, title: expected.title, exe: "not-powerscribe.exe", pid: 77},
            {hwnd: 601, title: expected.title, exe: expected.exe, pid: 78}
        ] {
            AppControl.windowDriver := FakeExactWindowDriver([changed])
            Assert.False(nativeDriver.IsLive(session), changed.title " / " changed.exe " / " changed.pid)
        }

        ; A second exact reporting window makes the target ambiguous.
        AppControl.windowDriver := FakeExactWindowDriver([expected, {
            hwnd: 602,
            title: expected.title,
            exe: expected.exe,
            pid: 79
        }])
        Assert.False(nativeDriver.IsLive(session))

        ; A session captured for another window is never PowerScribe.
        AppControl.windowDriver := FakeExactWindowDriver([{hwnd: 603, title: "Other", exe: expected.exe, pid: 77}])
        Assert.False(nativeDriver.IsLive({
            hwnd: 603,
            target: "ahk_id 603",
            processId: 77,
            title: "Other",
            exe: expected.exe
        }))
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

    ; A dialog left open under the clinical lease would refuse every other clinical
    ; command until dismissed, so each dialog a command can end with is shown only
    ; after the lease is released.
    ClinicalCommandDialogsWaitForTheLeaseRelease() {
        presented := []
        ClinicalNotices.presenter := (text, title, options) => presented.Push(
            {title: title, leaseHeld: PACSCommands.clinicalCommandActive}
        )
        unconfirmed := WetReadPasteEngine.NewResult()
        unconfirmed.reason := "verification-error"
        sources := Map(
            "Sticky Note Target Not Verified", (*) => StopWetRead("stopped"),
            "Sticky Note Not Verified", (*) => ReportWetReadPasteResult(unconfirmed, "uia"),
            "PACS Restart Cancelled", (*) => StopRestart("stopped"),
            "Microphone Not Selected", (*) => MicrophoneManager.ApplyNowFailed("not selected", "Microphone Not Selected"),
            ; The Sticky Notes stop, then the attending notice.
            "Attending Not Assigned", (*) => RunPinnedWetReadWorkflow("note", "uia", (*) => 0, (*) => 0, (*) => 0, (*) => true)
        )
        capturedLog := LogCapture()
        try {
            for title, source in sources {
                presented.Length := 0
                PACSCommands.RunClinicalCommand("Test command", source)
                Assert.True(presented.Length >= 1, title " was not shown")
                Assert.Equal(title, presented[-1].title)
                for notice in presented
                    Assert.False(notice.leaseHeld, notice.title " was shown under the lease")
            }
        } finally capturedLog.Restore()
        Assert.Equal(0, TestRunner.dialogs.Length)
    }

    ; Outside a clinical command a notice shows at once; a notice queued by a command
    ; that then fails still shows once the lease is released.
    NoticesShowAtOnceOutsideACommandAndAfterAFailedCommand() {
        presented := []
        ClinicalNotices.presenter := (text, title, options) => presented.Push(
            {title: title, leaseHeld: PACSCommands.clinicalCommandActive}
        )

        ClinicalNotices.Show("shown now", "Immediate")
        Assert.Equal(1, presented.Length)

        Assert.Throws(() => PACSCommands.RunClinicalCommand("Failing command", (*) => (
            ClinicalNotices.Show("queued", "Queued"),
            ThrowError("simulated command failure")
        )), "simulated command failure")
        Assert.Equal(2, presented.Length)
        Assert.Equal("Queued", presented[2].title)
        Assert.False(presented[2].leaseHeld)
        Assert.False(ClinicalNotices.deferring)
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
            "did not match a supported modality"
        )
        Assert.Equal(0, lookups)
        Assert.Equal(0, writes)
    }

    UnavailableAttendingAssignmentIsReported() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Chest"] := "Smith"
        ProfileManager.profiles["Test"] := profile
        ProfileManager.currentProfile := "Test"

        Assert.Throws(
            () => CheckAttending("EXAMINATION: CT CHEST"),
            "attending 'Smith' cannot be selected in PowerScribe automatically"
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

    WindowCloseRecheckRejectsNewDuplicate() {
        driver := DuplicateAppearingWindowDriver()
        AppControl.windowDriver := driver
        session := {
            hwnd: driver.primaryHwnd,
            target: "ahk_id " driver.primaryHwnd,
            processId: 4242,
            title: AppControl.explorerPortalTitle,
            exe: AppControl.explorerPortalExecutable
        }

        result := NativeAppLifecycleDriver().CloseWindow(session)

        Assert.False(result)
        Assert.Equal(1, driver.listCalls)
    }

    WindowStopSucceedsWhenTheExactWindowCloses() {
        driver := SharedHostWindowLifecycleDriver()
        driver.windows := [31337]
        AppControl.lifecycleDriver := driver
        AppControl.windowDriver := driver

        result := AppControl.StopTarget(
            AppControl.ExplorerPortalWindowSpec(),
            "window"
        )

        Assert.True(result.found)
        Assert.True(result.stopped)
        Assert.Equal("", result.error)
        Assert.Equal(1, driver.closeCalls)
        Assert.Equal(0, driver.windows.Length)
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
        Assert.Equal(3, driver.windows.Length)
    }

    RestartTargetPreflightPreventsPartialShutdown() {
        specs := [
            {
                target: AppControl.ExactWindowSpec("First Target", "first.exe"),
                label: "First Target",
                kind: "window"
            },
            {
                target: AppControl.ExactWindowSpec("Second Target", "second.exe"),
                label: "Second Target",
                kind: "window"
            }
        ]
        AppControl.windowDriver := FakeExactWindowDriver([
            {hwnd: 101, title: "First Target", exe: "first.exe", pid: 11},
            {hwnd: 102, title: "First Target", exe: "first.exe", pid: 12},
            {hwnd: 201, title: "Second Target", exe: "second.exe", pid: 21}
        ])
        lifecycle := CountingCloseLifecycleDriver()
        AppControl.lifecycleDriver := lifecycle

        result := AppControl.StopTargetSpecs(specs)

        Assert.False(result.anyStopped)
        Assert.Equal(1, result.failedTargets.Length)
        Assert.Equal("First Target", result.failedTargets[1])
        ; The user can fix this one, so the reason says how.
        Assert.Equal("First Target (2 windows are open; close the extra ones)", result.details[1])
        Assert.Equal(0, lifecycle.closeCalls)
    }

    RestartStopsAfterRuntimeTargetFailure() {
        specs := [
            {
                target: AppControl.ExactWindowSpec("First Target", "first.exe"),
                label: "First Target",
                kind: "window"
            },
            {
                target: AppControl.ExactWindowSpec("Second Target", "second.exe"),
                label: "Second Target",
                kind: "window"
            }
        ]
        AppControl.windowDriver := FakeExactWindowDriver([
            {hwnd: 101, title: "First Target", exe: "first.exe", pid: 11},
            {hwnd: 201, title: "Second Target", exe: "second.exe", pid: 21}
        ])
        lifecycle := CountingCloseLifecycleDriver(true)
        AppControl.lifecycleDriver := lifecycle

        result := AppControl.StopTargetSpecs(specs)

        Assert.False(result.anyStopped)
        Assert.Equal(1, result.failedTargets.Length)
        Assert.Equal("First Target", result.failedTargets[1])
        Assert.True(InStr(result.details[1], "First Target (") = 1 && StrLen(result.details[1]) > StrLen("First Target ()"), result.details[1])
        Assert.Equal(1, lifecycle.closeCalls)
    }

    RestartRejectsBareProcessTermination() {
        driver := UntouchedLifecycleDriver()
        AppControl.lifecycleDriver := driver
        AppControl.windowDriver := driver

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.False(result.found)
        Assert.False(result.stopped)
        Assert.Equal(0, driver.calls.Length)
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

        Assert.False(RestartPACS(driver))
        Assert.Equal(1, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartAbortsForUnverifiedPowerScribeProcess() {
        driver := FakePacsRestartDriver([], 77, true)

        Assert.False(RestartPACS(driver))
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

        Assert.False(RestartPACS(driver))
        Assert.Equal(1, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartSucceedsWhenEveryStepIsVerified() {
        driver := FakePacsRestartDriver([{
            hwnd: 601,
            target: "ahk_id 601",
            processId: 77
        }], 0, true)
        driver.stopResult := {anyStopped: true, failedTargets: []}

        Assert.True(RestartPACS(driver))
        Assert.Equal(1, driver.closeCalls)
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(1, driver.verifyCalls)
        Assert.Equal(1, driver.launchCalls)
        Assert.Equal(1, driver.waitForLaunchCalls)
        Assert.Equal(0, TestRunner.dialogs.Length)
    }

    RestartPreparationFailureHasNoClinicalSideEffects() {
        driver := FakePacsRestartDriver([{
            hwnd: 601,
            target: "ahk_id 601",
            processId: 77
        }], 0, true)
        driver.prepareResult := false

        Assert.False(RestartPACS(driver))
        Assert.Equal(1, driver.prepareCalls)
        Assert.Equal(0, driver.closeCalls)
        Assert.Equal(0, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartPreparationRejectsAmbiguousTargets() {
        trustedPath := A_Temp "\Philips\Vue\mp.exe"
        AppControl.windowDriver := FakeExactWindowDriver([
            {
                hwnd: 501,
                title: AppControl.vuePacsTitle,
                exe: AppControl.vuePacsExecutable,
                pid: 42
            },
            {
                hwnd: 601,
                title: AppControl.explorerPortalTitle,
                exe: AppControl.explorerPortalExecutable,
                pid: 51
            },
            {
                hwnd: 602,
                title: AppControl.explorerPortalTitle,
                exe: AppControl.explorerPortalExecutable,
                pid: 52
            }
        ])
        AppControl.lifecycleDriver := FakeProcessInventoryLifecycleDriver(
            Map(42, trustedPath),
            [{processId: 42, name: AppControl.vuePacsExecutable, path: trustedPath}]
        )

        Assert.Throws(
            () => NativePacsRestartDriver().PrepareRestart(),
            "Explorer Portal"
        )
    }

    RestartPreparationCapturesHiddenTrustedVueProcesses() {
        trustedPath := A_Temp "\Philips\Vue\mp.exe"
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
    }

    RestartAbortsWhenTargetReappearsBeforeLaunch() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.quiescent := false

        Assert.False(RestartPACS(driver))
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(1, driver.verifyCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartStopBoundaryFailureCancelsLaunch() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.stopError := "simulated stop failure"

        capturedLog := LogCapture()
        try {
            Assert.False(RestartPACS(driver))
            logged := capturedLog.Count("PACS Restart Cancelled: PACS target shutdown could not be completed or verified.")
        } finally capturedLog.Restore()
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
        Assert.Equal(1, logged)
    }

    RestartNamesWhyATargetCouldNotBeStopped() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.stopResult := {
            anyStopped: false,
            failedTargets: ["Explorer Portal"],
            details: ["Explorer Portal (the exact window did not close)"]
        }

        Assert.False(RestartPACS(driver))
        Assert.True(InStr(TestRunner.dialogs[TestRunner.dialogs.Length].text,
            "could not stop: Explorer Portal (the exact window did not close)."), TestRunner.dialogs[TestRunner.dialogs.Length].text)
    }

    RestartRejectsMalformedStopResult() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.stopResult := {anyStopped: false}

        Assert.False(RestartPACS(driver))
        Assert.Equal(1, driver.stopCalls)
        Assert.Equal(0, driver.launchCalls)
    }

    RestartLaunchBoundaryFailuresAreReported() {
        falseDriver := FakePacsRestartDriver([], 0, true)
        falseDriver.launchSucceeded := false
        Assert.False(RestartPACS(falseDriver))
        Assert.Equal(1, falseDriver.launchCalls)
        Assert.Equal(0, falseDriver.waitForLaunchCalls)

        launchDriver := FakePacsRestartDriver([], 0, true)
        launchDriver.launchError := "simulated launch failure"
        Assert.False(RestartPACS(launchDriver))
        Assert.Equal(1, launchDriver.launchCalls)
        Assert.Equal(0, launchDriver.waitForLaunchCalls)

        verifyDriver := FakePacsRestartDriver([], 0, true)
        verifyDriver.waitForLaunchError := "simulated launch verification failure"
        Assert.False(RestartPACS(verifyDriver))
        Assert.Equal(1, verifyDriver.launchCalls)
        Assert.Equal(1, verifyDriver.waitForLaunchCalls)
    }

    RestartRequiresExpectedVueWindowAfterLaunch() {
        driver := FakePacsRestartDriver([], 0, true)
        driver.launchVerified := false

        Assert.False(RestartPACS(driver))
        Assert.Equal(1, driver.launchCalls)
        Assert.Equal(1, driver.waitForLaunchCalls)
    }

    RestartLaunchProofRequiresANewStableVueSession() {
        trustedPath := A_Temp "\Philips\Vue\mp.exe"
        native := SimulatedClockRestartDriver()
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
    }

    GracefulCloseSucceedsWhenTheProcessExits() {
        driver := FakeGracefulCloseDriver(1000, 77, true)

        Assert.True(CloseWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(1, driver.closeRequests)
    }

    GracefulCloseTimesOutAcross32BitTickWrap() {
        driver := FakeGracefulCloseDriver(0xFFFFFFFF - 50, 77)

        Assert.False(CloseWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(1, driver.closeRequests)
        Assert.True(driver.pauseCalls >= 2)
    }

    GracefulCloseRequiresCapturedProcessIdentity() {
        driver := FakeGracefulCloseDriver(1000, 88)

        Assert.False(CloseWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(0, driver.closeRequests)
    }

    ; These keep the shipped identity check (AppControl.ExactSessionIsUniqueAndLive)
    ; and vary only the windows it sees.
    GracefulCloseRejectsSameProcessWrongTitleBeforeRequest() {
        AppControl.windowDriver := FakeExactWindowDriver([
            {hwnd: 601, title: AppControl.powerScribeReportingTitle " Extra", exe: AppControl.powerScribeExecutable, pid: 77}
        ])
        driver := ExactGateGracefulCloseDriver(1000, 77)

        Assert.False(CloseWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(0, driver.closeRequests)
    }

    GracefulCloseRejectsDuplicateExactWindowBeforeRequest() {
        AppControl.windowDriver := FakeExactWindowDriver([
            {hwnd: 601, title: AppControl.powerScribeReportingTitle, exe: AppControl.powerScribeExecutable, pid: 77},
            {hwnd: 602, title: AppControl.powerScribeReportingTitle, exe: AppControl.powerScribeExecutable, pid: 78}
        ])
        driver := ExactGateGracefulCloseDriver(1000, 77)

        Assert.False(CloseWithSavePrompt(this.PowerScribeSession(), 300, driver))
        Assert.Equal(0, driver.closeRequests)
    }

    GracefulCloseRequestsCloseForTheUniqueExactWindow() {
        AppControl.windowDriver := FakeExactWindowDriver([
            {hwnd: 601, title: AppControl.powerScribeReportingTitle, exe: AppControl.powerScribeExecutable, pid: 77}
        ])
        driver := ExactGateGracefulCloseDriver(1000, 77)

        CloseWithSavePrompt(this.PowerScribeSession(), 300, driver)

        Assert.Equal(1, driver.closeRequests)
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
    }

    PacsLauncherRejectsNonShortcutMatch() {
        root := TestTempPath("pacs-launch")
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
        root := TestTempPath("pacs-launch-retarget")
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
        root := TestTempPath("pacs-launch-untrusted")
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
        root := TestTempPath("pacs-launch")
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
            Assert.True(AppControl.PathsEqual(shortcut, driver.launches[1]))
        } finally {
            DirDelete(root, true)
        }
    }

    PathsEqualRecognizesShortAndLongWindowsAliases() {
        longPath := A_ProgramFiles
        shortPathBuffer := Buffer(32768 * 2, 0)
        length := DllCall(
            "GetShortPathNameW",
            "WStr", longPath,
            "Ptr", shortPathBuffer.Ptr,
            "UInt", 32768,
            "UInt"
        )
        Assert.True(length > 0 && length < 32768)
        shortPath := StrGet(shortPathBuffer, length, "UTF-16")
        Assert.NotEqual(longPath, shortPath)
        Assert.True(AppControl.PathsEqual(longPath, shortPath))
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

    ; The report control must be a document or edit control in the root's process
    ; and window; each condition alone rejects it.
    ReportControlIdentityRequiresEachProperty() {
        root := {ProcessId: 77, WinId: 601}
        Assert.True(PowerScribe.InspectExpectedReportControl(root, {ProcessId: 77, WinId: 601, Type: UIA.Type.Document}))
        Assert.True(PowerScribe.InspectExpectedReportControl(root, {ProcessId: 77, WinId: 601, Type: UIA.Type.Edit}))
        cases := [
            {label: "other process", root: root, control: {ProcessId: 78, WinId: 601, Type: UIA.Type.Document}},
            {label: "other window", root: root, control: {ProcessId: 77, WinId: 602, Type: UIA.Type.Document}},
            {label: "text control", root: root, control: {ProcessId: 77, WinId: 601, Type: UIA.Type.Text}},
            {label: "no root process", root: {ProcessId: 0, WinId: 601},
                control: {ProcessId: 0, WinId: 601, Type: UIA.Type.Document}},
            {label: "no root window", root: {ProcessId: 77, WinId: 0},
                control: {ProcessId: 77, WinId: 0, Type: UIA.Type.Document}}
        ]
        for testCase in cases
            Assert.False(PowerScribe.InspectExpectedReportControl(testCase.root, testCase.control), testCase.label)
    }

    ReportCaptureReadsTheOneCurrentReport() {
        report := "EXAMINATION: CT CHEST`nFINDINGS: Current report."
        driver := FakePowerScribeSessionDriver(report)
        PowerScribe.sessionDriver := driver

        capture := PowerScribe.CaptureReport()

        Assert.Equal(report, capture.text)
        Assert.True(capture.session == driver.session)
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
        AppControl.lifecycleDriver := this.originalLifecycleDriver
        PowerScribe.sessionDriver := this.originalPowerScribeSessionDriver
        ProfileManager.profiles := this.originalProfiles
        ProfileManager.currentProfile := this.originalCurrentProfile
        PACSCommands.clinicalCommandActive := this.originalClinicalCommandActive
        PACSCommands.activeClinicalCommand := this.originalActiveClinicalCommand
        PACSCommands.busyNotifier := this.originalBusyNotifier
        PACSCommands.commandAvailabilityProbe := this.originalCommandAvailabilityProbe
        ClinicalNotices.presenter := this.originalNoticePresenter
        ClinicalNotices.deferring := false
        ClinicalNotices.deferred := []
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
        ; Called with the driver on each activation, to change the windows mid-send.
        this.onActivate := 0
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
        if this.onActivate
            this.onActivate.Call(this)
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
        this.list := FakeWindowList(windows)
    }

    ; Subclasses add or replace windows between polls.
    windows {
        get => this.list.windows
        set => this.list.windows := value
    }

    ListWindowsByExecutable(executable) => this.list.ListWindowsByExecutable(executable)
    GetTitle(hwnd) => this.list.GetTitle(hwnd)
    GetProcessName(hwnd) => this.list.GetProcessName(hwnd)
    GetProcessId(hwnd) => this.list.GetProcessId(hwnd)
}

class ToggleRaceWindowDriver extends FakeExactWindowDriver {
    __New(windows) {
        super.__New(windows)
        this.addDuplicateOnStateRead := false
        this.minMax := 0
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
        return this.minMax
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
        this.launchSucceeded := true
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
        return this.launchSucceeded
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

class CountingCloseLifecycleDriver {
    __New(failAll := false) {
        this.failAll := failAll
        this.closeCalls := 0
    }

    CloseWindow(*) {
        this.closeCalls++
        if this.failAll
            throw Error("simulated close failure")
        return true
    }
}

class ExactGateGracefulCloseDriver extends FakeGracefulCloseDriver {
    IsExpectedSession(session) {
        return NativeGracefulCloseDriver.Prototype.IsExpectedSession.Call(this, session)
    }
}

class FakeGracefulCloseDriver {
    __New(now, processId, exitsAfterClose := false) {
        this.now := now
        this.processId := processId
        this.exitsAfterClose := exitsAfterClose
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
        return true
    }

    RequestClose(*) {
        this.closeRequests++
    }

    ProcessExists(*) {
        return !(this.exitsAfterClose && this.closeRequests > 0)
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
    __New(reportText := "EXAMINATION: CT CHEST") {
        this.session := {hwnd: 100, target: "ahk_id 100", processId: 42}
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
        this.shortcutTarget := ""
    }

    FindProcess(target) {
        return this.mode = "close-error" ? 0 : 4242
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

    CloseWindow(*) {
        if (this.mode = "close-error")
            throw Error("close failed")
        return true
    }

    ProcessExists(pid) {
        return false
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
    }

    FindProcess(*) {
        this.processLookupCalls++
        return 4242
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
}

class DuplicateAppearingWindowDriver {
    __New() {
        this.primaryHwnd := 987654321
        this.listCalls := 0
    }

    ListWindowsByExecutable(*) {
        this.listCalls++
        return [this.primaryHwnd, this.primaryHwnd + 1]
    }

    GetTitle(*) => AppControl.explorerPortalTitle
    GetProcessName(*) => AppControl.explorerPortalExecutable
    GetProcessId(*) => 4242
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

; Records any call at all; a test that expects no lifecycle or window action
; asserts that calls stays empty.
class UntouchedLifecycleDriver {
    __New() {
        this.calls := []
    }

    __Call(name, params) {
        this.calls.Push(name)
        return 0
    }
}

; Runs the real launch-stability loop against a simulated clock, so the required
; two stable polls never depend on real 100 ms sleeps fitting a 350 ms budget.
class SimulatedClockRestartDriver extends NativePacsRestartDriver {
    __New() {
        super.__New()
        this.now := 0
    }

    NowMilliseconds() {
        return this.now
    }

    Pause(milliseconds) {
        this.now += milliseconds
    }
}

