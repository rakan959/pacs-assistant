#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class ClinicalAutomationTest {
    static Tests := [
        "ActivationFailureDoesNotSend",
        "ActivationCanSucceedButFocusCheckStopsSend",
        "TargetedSendActivatesBeforeSending",
        "BuiltInClinicalCommandUsesConfirmedTarget",
        "TargetedCustomCommandUsesConfirmedTarget",
        "AttendingTargetRequiresSemanticControlIdentity",
        "NativeAttendingWriteRefusesLostControlFocus",
        "AttendingNameUsesLiteralText",
        "AttendingStopsBeforeTextWhenControlMissing",
        "AttendingStopsBeforeConfirmationWhenValueUnverified",
        "AttendingStopsBeforeConfirmationWhenPickerLosesFocus",
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
        "WindowOwnershipUncertaintyCancelsStop",
        "SharedHostWindowStopDoesNotTerminateOwner",
        "PacsLauncherRejectsNonShortcutMatch",
        "PacsLauncherAcceptsInstalledShortcut",
        "ReportSelectionUsesOnlyReportShapedText",
        "ReportSelectionRejectsUnrelatedFallbackText"
    ]

    Setup() {
        this.originalDriver := AppControl.windowDriver
        this.originalLifecycleDriver := HasProp(AppControl, "lifecycleDriver") ? AppControl.lifecycleDriver : 0
        this.originalAttendingDriver := HasProp(PowerScribe, "attendingControlDriver")
            ? PowerScribe.attendingControlDriver
            : 0
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
        PowerScribe.attendingControlDriver := FakeAttendingControlDriver()
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

    BuiltInClinicalCommandUsesConfirmedTarget() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        PACSCommands.commands["Sign Report"].Call()

        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal(PowerScribe.windowTitle, driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("{F12}", driver.calls[3].value)
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

    AttendingNameUsesLiteralText() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attendingDriver := FakeAttendingControlDriver()
        PowerScribe.attendingControlDriver := attendingDriver
        attending := "Smith + Jones {Neuro}"

        Assert.True(PowerScribe.SetAttending(attending))
        Assert.Equal(8, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal(PowerScribe.windowTitle, driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("keys", driver.calls[3].kind)
        Assert.Equal("{Alt down}ta{Alt up}", driver.calls[3].value)
        Assert.Equal("active", driver.calls[5].kind)
        Assert.Equal(1, attendingDriver.writes.Length)
        Assert.Equal(attending, attendingDriver.writes[1].value)
        Assert.Equal("active", driver.calls[7].kind)
        Assert.Equal("keys", driver.calls[8].kind)
        Assert.Equal("{tab}{space}{tab}{Enter}", driver.calls[8].value)
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

        result := AppControl.StopTarget("mp.exe")

        Assert.True(result.found)
        Assert.True(result.stopped)
    }

    RestartDetectsStubbornProcess() {
        AppControl.lifecycleDriver := FakeAppLifecycleDriver("stubborn")

        result := AppControl.StopTarget("mp.exe")

        Assert.True(result.found)
        Assert.False(result.stopped)
    }

    RestartStopsEveryMatchingProcess() {
        driver := MultipleProcessLifecycleDriver([101, 202])
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe")

        Assert.True(result.found)
        Assert.True(result.stopped)
        Assert.Equal(2, driver.stoppedPids.Length)
        Assert.Equal(101, driver.stoppedPids[1])
        Assert.Equal(202, driver.stoppedPids[2])
    }

    RestartCapsRespawningProcessTermination() {
        driver := RespawningProcessLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe")

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.Equal(AppControl.maxMatchingProcesses, driver.stopCalls)
        Assert.True(InStr(result.error, "Too many") > 0)
    }

    RestartRecheckUncertaintyFailsClosed() {
        driver := UncertainRecheckLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("mp.exe")

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

        result := AppControl.StopTarget("mp.exe")

        Assert.False(result.found)
        Assert.False(result.stopped)
        Assert.True(InStr(result.error, "lookup failed") > 0)
    }

    WindowOwnershipUncertaintyCancelsStop() {
        driver := FakeAppLifecycleDriver("ownership-error")
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget("Vue PACS")

        Assert.True(result.found)
        Assert.False(result.stopped)
        Assert.True(InStr(result.error, "ownership failed") > 0)
        Assert.Equal(0, driver.killCalls)
    }

    SharedHostWindowStopDoesNotTerminateOwner() {
        driver := SharedHostWindowLifecycleDriver()
        AppControl.lifecycleDriver := driver

        result := AppControl.StopTarget(
            "Explorer Portal ahk_exe msedge.exe",
            true
        )

        Assert.True(result.found)
        Assert.True(result.stopped)
        Assert.Equal(0, driver.processLookupCalls)
        Assert.Equal(2, driver.killCalls)
        Assert.Equal(0, driver.stopProcessCalls)
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

class FakeAttendingControlDriver {
    __New(control := {}, valueMatches := true, canConfirm := true) {
        this.control := control
        this.valueMatches := valueMatches
        this.confirmationAllowed := canConfirm
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
        return this.confirmationAllowed
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
        if (this.mode = "ownership-error")
            return 0
        return this.processAvailable ? 4242 : 0
    }

    FindWindow(target) {
        if (this.mode = "ownership-error")
            return 31337
        return 0
    }

    GetWindowProcessId(hwnd) {
        if (this.mode = "ownership-error")
            throw Error("ownership failed")
        return 0
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
        this.windows := [31337, 41414]
        this.processLookupCalls := 0
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

    GetWindowProcessId(*) {
        return 4242
    }

    ProcessExists(*) {
        return true
    }

    KillWindow(*) {
        this.killCalls++
        this.windows.RemoveAt(1)
        return true
    }

    StopProcess(*) {
        this.stopProcessCalls++
        return true
    }
}
