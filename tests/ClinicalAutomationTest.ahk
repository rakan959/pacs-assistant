#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class ClinicalAutomationTest {
    static Tests := [
        "ActivationFailureDoesNotSend",
        "ActivationCanSucceedButFocusCheckStopsSend",
        "TargetedSendActivatesBeforeSending",
        "ExactWindowResolverRejectsSubstringAndDuplicateMatches",
        "PacsSeriesCommandsUseExactHwndTarget",
        "BuiltInClinicalCommandUsesConfirmedTarget",
        "NativePowerScribeCaptureRejectsImpostorAndDuplicate",
        "TargetedCustomCommandUsesConfirmedTarget",
        "AttendingTargetRequiresSemanticControlIdentity",
        "NativeAttendingWriteRefusesLostControlFocus",
        "AttendingVerificationRejectsSubstringNearMatch",
        "NativeAttendingPickerAbsenceRejectsReplacementControl",
        "NativeAttendingPickerRequiresUniqueSemanticControl",
        "AttendingNameUsesLiteralText",
        "AttendingStopsBeforeTextWhenControlMissing",
        "AttendingStopsBeforeConfirmationWhenValueUnverified",
        "AttendingStopsBeforeConfirmationWhenPickerLosesFocus",
        "AttendingReportsUnconfirmedSubmission",
        "AttendingRejectsClosureWithoutCommittedReadback",
        "AttendingRequiresVerificationPickerDismissal",
        "AttendingFinalReadbackMustStillMatchBeforeDismissal",
        "AttendingTransactionUsesCapturedExactWindow",
        "CapturedReportSessionRoutesToSameWindow",
        "AttendingRejectsSameWindowReportChange",
        "AttendingStopsBeforeTextWhenFocusMoves",
        "AttendingRoutingUsesInjectedDependencies",
        "BlankAttendingSkipsPowerScribeWrite",
        "UnknownExaminationRequiresManualAssignment",
        "FailedAttendingControlIsReported",
        "RestartTreatsAlreadyExitedProcessAsStopped",
        "RestartDetectsStubbornProcess",
        "RestartStopsEveryMatchingProcess",
        "RestartCapsRespawningProcessTermination",
        "RestartRecheckUncertaintyFailsClosed",
        "NativeLookupErrorsAreNotAbsence",
        "RestartLookupUncertaintyCancelsStop",
        "WindowCloseUncertaintyCancelsStop",
        "SharedHostWindowStopDoesNotTerminateOwner",
        "ProcessTargetNeverFallsThroughToSameTitleWindow",
        "RestartSpecsNeverHardStopPowerScribe",
        "RestartAbortsWhenPowerScribeSaveIsUnverified",
        "RestartAbortsForUnverifiedPowerScribeProcess",
        "GracefulCloseTimesOutAcross32BitTickWrap",
        "GracefulCloseRequiresCapturedProcessIdentity",
        "GracefulCloseRejectsSameProcessWrongTitleBeforeRequest",
        "GracefulCloseRejectsDuplicateExactWindowBeforeRequest",
        "RestartTargetsUseExactClinicalIdentities",
        "PacsLauncherRejectsNonShortcutMatch",
        "PacsLauncherAcceptsInstalledShortcut",
        "ReportSelectionUsesOnlyReportShapedText",
        "ReportSelectionRejectsMultipleReportCandidates",
        "ReportSelectionRejectsUnrelatedFallbackText"
    ]

    Setup() {
        this.originalDriver := AppControl.windowDriver
        this.originalLifecycleDriver := HasProp(AppControl, "lifecycleDriver") ? AppControl.lifecycleDriver : 0
        this.originalAttendingDriver := HasProp(PowerScribe, "attendingControlDriver")
            ? PowerScribe.attendingControlDriver
            : 0
        this.originalPowerScribeSessionDriver := HasProp(PowerScribe, "sessionDriver")
            ? PowerScribe.sessionDriver
            : 0
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
        PowerScribe.attendingControlDriver := FakeAttendingControlDriver()
        PowerScribe.sessionDriver := FakePowerScribeSessionDriver()
        ProfileManager.profiles := Map()
        ProfileManager.currentProfile := ""
    }

    ActivationFailureDoesNotSend() {
        driver := FakeWindowDriver(false)
        AppControl.windowDriver := driver

        Assert.False(AppControl.SendKeysToWindow("PowerScribe", "{F12}"))
        Assert.Equal(1, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
    }

    ActivationCanSucceedButFocusCheckStopsSend() {
        driver := FakeWindowDriver(true, false)
        AppControl.windowDriver := driver

        Assert.False(AppControl.SendKeysToWindow("PowerScribe", "{F12}"))
        Assert.Equal(2, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("active", driver.calls[2].kind)
    }

    TargetedSendActivatesBeforeSending() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        Assert.True(AppControl.SendKeysToWindow("Vue PACS Client", "{Right}"))
        Assert.Equal(3, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("Vue PACS Client", driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("Vue PACS Client", driver.calls[2].value)
        Assert.Equal("keys", driver.calls[3].kind)
        Assert.Equal("{Right}", driver.calls[3].value)
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

        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("Custom Clinical Window", driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("^d", driver.calls[3].value)
    }

    AttendingTargetRequiresSemanticControlIdentity() {
        root := FakeAttendingTargetElement(UIA.Type.Window, 42)
        valid := FakeAttendingTargetElement(UIA.Type.ComboBox, 42, "Attending", "attendingPicker", true)
        wrongType := FakeAttendingTargetElement(UIA.Type.Button, 42, "Attending", "attendingPicker", true)
        wrongMeaning := FakeAttendingTargetElement(UIA.Type.Edit, 42, "Report", "reportEditor", true)
        wrongProcess := FakeAttendingTargetElement(UIA.Type.Edit, 99, "Attending", "attendingPicker", true)
        wrongWindow := FakeAttendingTargetElement(UIA.Type.Edit, 42, "Attending", "attendingPicker", true, 200)

        Assert.True(NativeAttendingControlDriver.IsExpectedControl(root, valid))
        Assert.False(NativeAttendingControlDriver.IsExpectedControl(root, wrongType))
        Assert.False(NativeAttendingControlDriver.IsExpectedControl(root, wrongMeaning))
        Assert.False(NativeAttendingControlDriver.IsExpectedControl(root, wrongProcess))
        Assert.False(NativeAttendingControlDriver.IsExpectedControl(root, wrongWindow))
    }

    NativeAttendingWriteRefusesLostControlFocus() {
        control := {writeCalls: 0}
        driver := NativeAttendingControlDriver((*) => false)

        Assert.False(driver.WriteAndVerify(PowerScribe.windowTitle, control, "Smith"))
        Assert.Equal(0, control.writeCalls)
    }

    AttendingVerificationRejectsSubstringNearMatch() {
        driver := NativeAttendingControlDriver()

        Assert.True(driver.HasExpectedValue(FakeAttendingValueElement(" Smith "), "smith"))
        Assert.False(driver.HasExpectedValue(FakeAttendingValueElement("Smithson"), "Smith"))
    }

    NativeAttendingPickerAbsenceRejectsReplacementControl() {
        driver := NativeAttendingControlDriver()
        replacement := FakeAttendingTargetElement(
            UIA.Type.Edit,
            42,
            "Attending",
            "attendingPickerReplacement",
            true
        )

        Assert.False(driver.PickerIsAbsentFromRoot(FakeAttendingRoot([replacement])))
        Assert.True(driver.PickerIsAbsentFromRoot(FakeAttendingRoot()))
    }

    NativeAttendingPickerRequiresUniqueSemanticControl() {
        driver := NativeAttendingControlDriver()
        first := FakeAttendingTargetElement(UIA.Type.Edit, 42, "Attending", "attendingOne", true)
        second := FakeAttendingTargetElement(UIA.Type.ComboBox, 42, "Attending", "attendingTwo", true)

        Assert.Equal(0, driver.UniqueExpectedControl(FakeAttendingRoot([first], [second])))
        Assert.True(driver.UniqueExpectedControl(FakeAttendingRoot([first])) = first)
    }

    AttendingNameUsesLiteralText() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attendingDriver := FakeAttendingControlDriver()
        PowerScribe.attendingControlDriver := attendingDriver
        attending := "Smith + Jones {Neuro}"

        Assert.True(PowerScribe.SetAttending(attending))
        Assert.Equal(13, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("ahk_id 100", driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("keys", driver.calls[3].kind)
        Assert.Equal("{Alt down}ta{Alt up}", driver.calls[3].value)
        Assert.Equal("active", driver.calls[5].kind)
        Assert.Equal(1, attendingDriver.writes.Length)
        Assert.Equal(attending, attendingDriver.writes[1].value)
        Assert.Equal("active", driver.calls[7].kind)
        Assert.Equal("keys", driver.calls[8].kind)
        Assert.Equal("{tab}{space}{tab}{Enter}", driver.calls[8].value)
        Assert.Equal("active", driver.calls[9].kind)
        Assert.Equal("{Alt down}ta{Alt up}", driver.calls[10].value)
        Assert.Equal("active", driver.calls[12].kind)
        Assert.Equal("{Escape}", driver.calls[13].value)
    }

    AttendingStopsBeforeTextWhenControlMissing() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        PowerScribe.attendingControlDriver := FakeAttendingControlDriver(0)

        Assert.False(PowerScribe.SetAttending("Smith"))
        for call in driver.calls
            Assert.False(call.kind = "text", "Attending text must not be sent to an unidentified control")
    }

    AttendingStopsBeforeConfirmationWhenValueUnverified() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        PowerScribe.attendingControlDriver := FakeAttendingControlDriver({}, false)

        Assert.False(PowerScribe.SetAttending("Smith"))
        Assert.Equal(1, PowerScribe.attendingControlDriver.writes.Length)
        for call in driver.calls
            Assert.False(call.kind = "keys" && call.value = "{tab}{space}{tab}{Enter}", "Unverified attending must not be confirmed")
    }

    AttendingStopsBeforeConfirmationWhenPickerLosesFocus() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        PowerScribe.attendingControlDriver := FakeAttendingControlDriver({}, true, false)

        Assert.False(PowerScribe.SetAttending("Smith"))
        for call in driver.calls
            Assert.False(call.kind = "keys" && call.value = "{tab}{space}{tab}{Enter}", "Attending confirmation requires the verified picker to retain focus")
    }

    AttendingReportsUnconfirmedSubmission() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attendingDriver := FakeAttendingControlDriver({}, true, true, false)
        PowerScribe.attendingControlDriver := attendingDriver

        Assert.False(PowerScribe.SetAttending("Smith"))
        Assert.Equal(1, attendingDriver.confirmationChecks)
    }

    AttendingRejectsClosureWithoutCommittedReadback() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attendingDriver := FakeAttendingControlDriver({}, true, true, true, false)
        PowerScribe.attendingControlDriver := attendingDriver

        Assert.False(PowerScribe.SetAttending("Smith"))
        Assert.Equal(1, attendingDriver.committedValueChecks)
        Assert.Equal(2, attendingDriver.confirmationChecks)
        Assert.True(this.DriverSentKeys(driver, "{Escape}"))
    }

    AttendingRequiresVerificationPickerDismissal() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attendingDriver := FakeAttendingControlDriver({}, true, true, true, true, false)
        PowerScribe.attendingControlDriver := attendingDriver

        Assert.False(PowerScribe.SetAttending("Smith"))
        Assert.Equal(2, attendingDriver.confirmationChecks)
    }

    AttendingFinalReadbackMustStillMatchBeforeDismissal() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attendingDriver := FakeAttendingControlDriver({}, true, [true, false])
        PowerScribe.attendingControlDriver := attendingDriver

        Assert.False(PowerScribe.SetAttending("Smith"))
        Assert.False(this.DriverSentKeys(driver, "{Escape}"))
    }

    AttendingTransactionUsesCapturedExactWindow() {
        session := {hwnd: 701, target: "ahk_id 701", processId: 42}
        sessionDriver := FakePowerScribeSessionDriver(session)
        PowerScribe.sessionDriver := sessionDriver
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        Assert.True(PowerScribe.SetAttending("Smith", session))

        Assert.Equal(0, sessionDriver.captureCalls)
        for call in driver.calls {
            if (call.kind = "activate" || call.kind = "active")
                Assert.Equal(session.target, call.value)
        }
    }

    CapturedReportSessionRoutesToSameWindow() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Chest"] := "Smith"
        ProfileManager.profiles["Test"] := profile
        ProfileManager.currentProfile := "Test"
        session := {hwnd: 702, target: "ahk_id 702", processId: 42}
        sessionDriver := FakePowerScribeSessionDriver(session)
        PowerScribe.sessionDriver := sessionDriver
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        Assert.Equal("Chest", checkAttending("EXAMINATION: CT CHEST", session))

        Assert.Equal(0, sessionDriver.captureCalls)
        for call in driver.calls {
            if (call.kind = "activate" || call.kind = "active")
                Assert.Equal(session.target, call.value)
        }
    }

    AttendingRejectsSameWindowReportChange() {
        originalReport := "EXAMINATION: CT CHEST`nFINDINGS: Original"
        session := {
            hwnd: 703,
            target: "ahk_id 703",
            processId: 42,
            reportText: originalReport
        }
        sessionDriver := FakePowerScribeSessionDriver(
            session,
            "EXAMINATION: MRI BRAIN`nFINDINGS: Different study"
        )
        PowerScribe.sessionDriver := sessionDriver
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        Assert.False(PowerScribe.SetAttending("Smith", session, originalReport))
        Assert.False(this.DriverSentKeys(driver, "{Alt down}ta{Alt up}"))
    }

    DriverSentKeys(driver, expected) {
        for call in driver.calls {
            if (call.kind = "keys" && call.value = expected)
                return true
        }
        return false
    }

    AttendingStopsBeforeTextWhenFocusMoves() {
        driver := FakeWindowDriver(true, [true, false])
        AppControl.windowDriver := driver

        Assert.False(PowerScribe.SetAttending("Smith"))

        for call in driver.calls
            Assert.False(call.kind = "text", "Attending text must not be sent after focus moves")
        Assert.Equal(5, driver.calls.Length)
        Assert.Equal("active", driver.calls[5].kind)
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
            "could not safely control PowerScribe"
        )
    }

    RestartTreatsAlreadyExitedProcessAsStopped() {
        AppControl.lifecycleDriver := FakeAppLifecycleDriver("already-exited")

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.True(result.found)
        Assert.True(result.stopped)
    }

    RestartDetectsStubbornProcess() {
        AppControl.lifecycleDriver := FakeAppLifecycleDriver("stubborn")

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.True(result.found)
        Assert.False(result.stopped)
    }

    RestartStopsEveryMatchingProcess() {
        driver := MultipleProcessLifecycleDriver([101, 202])
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.True(result.found)
        Assert.True(result.stopped)
        Assert.Equal(2, driver.stoppedPids.Length)
        Assert.Equal(101, driver.stoppedPids[1])
        Assert.Equal(202, driver.stoppedPids[2])
    }

    RestartCapsRespawningProcessTermination() {
        driver := RespawningProcessLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.Equal(AppControl.maxMatchingProcesses, driver.stopCalls)
        Assert.True(InStr(result.error, "Too many") > 0)
    }

    RestartRecheckUncertaintyFailsClosed() {
        driver := UncertainRecheckLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.Equal(1, driver.stopCalls)
        Assert.True(InStr(result.error, "recheck failed") > 0)
    }

    NativeLookupErrorsAreNotAbsence() {
        driver := NativeAppLifecycleDriver()

        Assert.Throws(() => driver.FindProcess({}))
        Assert.Throws(() => driver.ProcessExists({}))
    }

    RestartLookupUncertaintyCancelsStop() {
        AppControl.lifecycleDriver := FakeAppLifecycleDriver("lookup-error")

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.False(result.found)
        Assert.False(result.stopped)
        Assert.True(InStr(result.error, "lookup failed") > 0)
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

    SharedHostWindowStopDoesNotTerminateOwner() {
        driver := SharedHostWindowLifecycleDriver()
        AppControl.lifecycleDriver := driver
        AppControl.windowDriver := driver

        result := AppControl.StopTarget(
            AppControl.ExplorerPortalWindowSpec(),
            "window"
        )

        Assert.True(result.found)
        Assert.True(result.stopped)
        Assert.Equal(0, driver.processLookupCalls)
        Assert.Equal(2, driver.closeCalls)
        Assert.Equal(0, driver.killCalls)
        Assert.Equal(0, driver.stopProcessCalls)
        Assert.Equal(1, driver.windows.Length)
        Assert.Equal(51515, driver.windows[1])
    }

    ProcessTargetNeverFallsThroughToSameTitleWindow() {
        driver := SameTitleWindowLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe", "process")

        Assert.False(result.found)
        Assert.True(result.stopped)
        Assert.Equal(0, driver.windowLookupCalls)
        Assert.Equal(0, driver.killCalls)
        Assert.Equal(0, driver.stopProcessCalls)
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
            if (spec.kind = "window") {
                Assert.True(IsObject(spec.target))
                Assert.True(HasProp(spec.target, "title"))
                Assert.True(HasProp(spec.target, "exe"))
                continue
            }
            Assert.Equal("process", spec.kind)
            Assert.True(RegExMatch(spec.target, "i)^[^\\/:*?`"<>|]+\.exe$") > 0)
            Assert.NotEqual(AppControl.powerScribeExecutable, spec.target)
        }

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

    PacsLauncherAcceptsInstalledShortcut() {
        root := A_Temp "\pacs_launch_" A_TickCount "_" Random(1000, 9999)
        DirCreate(root)
        shortcut := root "\Vue Client (Integrated).lnk"
        FileAppend("test shortcut", shortcut)
        driver := FakeAppLifecycleDriver("launcher")
        AppControl.lifecycleDriver := driver

        try {
            Assert.True(AppControl.LaunchVuePacs(root))
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

    Teardown() {
        AppControl.windowDriver := this.originalDriver
        if this.originalLifecycleDriver
            AppControl.lifecycleDriver := this.originalLifecycleDriver
        PowerScribe.attendingControlDriver := this.originalAttendingDriver
        PowerScribe.sessionDriver := this.originalPowerScribeSessionDriver
        ProfileManager.profiles := this.originalProfiles
        ProfileManager.currentProfile := this.originalCurrentProfile
    }
}

class FakeWindowDriver {
    __New(activationResult := true, activeResults := true) {
        this.activationResult := activationResult
        this.activeResults := activeResults is Array ? activeResults.Clone() : [activeResults]
        this.calls := []
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

class FakePacsRestartDriver {
    __New(powerScribeWindows, powerScribePid, closeResult) {
        this.powerScribeWindows := powerScribeWindows
        this.powerScribePid := powerScribePid
        this.closeResult := closeResult
        this.closeCalls := 0
        this.stopCalls := 0
        this.launchCalls := 0
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
        return {anyStopped: false, failedTargets: []}
    }

    Pause(*) {
    }

    Launch() {
        this.launchCalls++
        return true
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

class FakeAttendingControlDriver {
    __New(
        control := {},
        valueMatches := true,
        canConfirm := true,
        confirmationCompleted := true,
        committedValueMatches := true,
        verificationDismissed := true
    ) {
        this.control := control
        this.valueMatches := valueMatches
        this.confirmationAllowed := canConfirm is Array ? canConfirm.Clone() : canConfirm
        this.pickerClosures := [confirmationCompleted, verificationDismissed]
        this.confirmationChecks := 0
        this.committedValueMatches := committedValueMatches
        this.committedValueChecks := 0
        this.writes := []
    }

    FindExpectedControl(*) {
        return this.control
    }

    WriteAndVerify(windowTitle, control, value) {
        this.writes.Push({windowTitle: windowTitle, control: control, value: value})
        return this.valueMatches
    }

    CanConfirm(*) {
        if this.confirmationAllowed is Array
            return this.confirmationAllowed.Length
                ? this.confirmationAllowed.RemoveAt(1)
                : false
        return this.confirmationAllowed
    }

    WaitForPickerAbsent(*) {
        this.confirmationChecks++
        return this.pickerClosures.Length ? this.pickerClosures.RemoveAt(1) : false
    }

    WaitForStableExpectedValue(*) {
        this.committedValueChecks++
        return this.committedValueMatches
    }

    ControlHasExpectedFocus(*) {
        return true
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

class FakeAttendingTargetElement {
    __New(type, processId, name := "", automationId := "", writable := false, windowId := 100) {
        this.Type := type
        this.ProcessId := processId
        this.WinId := windowId
        this.Name := name
        this.AutomationId := automationId
        this.IsEnabled := true
        this.IsValuePatternAvailable := writable
        this.IsLegacyIAccessiblePatternAvailable := false
        this.NativeWindowHandle := 0
    }
}

class FakeAttendingValueElement {
    __New(value) {
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

class FakeAttendingRoot {
    __New(editControls := [], comboControls := []) {
        this.ProcessId := 42
        this.WinId := 100
        this.editControls := editControls
        this.comboControls := comboControls
    }

    FindElements(condition) {
        if (condition.Type = "Edit")
            return this.editControls
        if (condition.Type = "ComboBox")
            return this.comboControls
        return []
    }
}

class FakeAppLifecycleDriver {
    __New(mode) {
        this.mode := mode
        this.launches := []
        this.killCalls := 0
        this.processAvailable := true
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
}

class MultipleProcessLifecycleDriver {
    __New(pids) {
        this.pids := pids.Clone()
        this.stoppedPids := []
    }

    FindProcess(target) {
        return this.pids.Length ? this.pids[1] : 0
    }

    StopProcess(pid) {
        this.stoppedPids.Push(pid)
        this.pids.RemoveAt(1)
        return true
    }

    ProcessExists(pid) {
        return false
    }

    FindWindow(target) {
        return 0
    }
}

class RespawningProcessLifecycleDriver {
    __New() {
        this.stopCalls := 0
    }

    FindProcess(target) {
        return 101
    }

    StopProcess(pid) {
        this.stopCalls++
        return true
    }

    ProcessExists(pid) {
        return false
    }
}

class UncertainRecheckLifecycleDriver {
    __New() {
        this.lookupCalls := 0
        this.stopCalls := 0
    }

    FindProcess(target) {
        this.lookupCalls++
        if (this.lookupCalls > 1)
            throw Error("recheck failed")
        return 101
    }

    StopProcess(pid) {
        this.stopCalls++
        return true
    }

    ProcessExists(pid) {
        return false
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
