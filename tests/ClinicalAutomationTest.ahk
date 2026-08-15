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
        "AttendingNameUsesLiteralText",
        "AttendingStopsBeforeTextWhenFocusMoves",
        "AttendingRoutingUsesInjectedDependencies",
        "BlankAttendingSkipsPowerScribeWrite",
        "FailedAttendingControlIsReported",
        "RestartTreatsAlreadyExitedProcessAsStopped",
        "RestartDetectsStubbornProcess",
        "NativeLookupErrorsAreNotAbsence",
        "RestartLookupUncertaintyCancelsStop",
        "WindowOwnershipUncertaintyCancelsStop",
        "PacsLauncherRejectsNonShortcutMatch",
        "PacsLauncherAcceptsInstalledShortcut",
        "ReportSelectionUsesOnlyReportShapedText",
        "ReportSelectionRejectsUnrelatedFallbackText"
    ]

    Setup() {
        this.originalDriver := AppControl.windowDriver
        this.originalLifecycleDriver := HasProp(AppControl, "lifecycleDriver") ? AppControl.lifecycleDriver : 0
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
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

    AttendingNameUsesLiteralText() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attending := "Smith + Jones {Neuro}"

        Assert.True(PowerScribe.SetAttending(attending))
        Assert.Equal(9, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal(PowerScribe.windowTitle, driver.calls[1].value)
        Assert.Equal("active", driver.calls[2].kind)
        Assert.Equal("keys", driver.calls[3].kind)
        Assert.Equal("{Alt down}ta{Alt up}", driver.calls[3].value)
        Assert.Equal("active", driver.calls[5].kind)
        Assert.Equal("text", driver.calls[6].kind)
        Assert.Equal(attending, driver.calls[6].value)
        Assert.Equal("active", driver.calls[8].kind)
        Assert.Equal("keys", driver.calls[9].kind)
        Assert.Equal("{tab}{space}{tab}{Enter}", driver.calls[9].value)
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

    SendText(text) {
        this.calls.Push({kind: "text", value: text})
    }

    Pause(milliseconds) {
        this.calls.Push({kind: "pause", value: milliseconds})
    }
}

class FakeAppLifecycleDriver {
    __New(mode) {
        this.mode := mode
        this.launches := []
        this.killCalls := 0
    }

    FindProcess(target) {
        if (this.mode = "lookup-error")
            throw Error("lookup failed")
        if (this.mode = "ownership-error")
            return 0
        return 4242
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
        return this.mode = "stubborn"
    }

    WindowExists(hwnd) {
        return false
    }

    StopProcess(pid) {
        if (this.mode = "already-exited")
            throw Error("process disappeared before termination")
        return false
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
