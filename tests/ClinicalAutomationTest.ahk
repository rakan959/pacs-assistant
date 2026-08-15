#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class ClinicalAutomationTest {
    static Tests := [
        "ActivationFailureDoesNotSend",
        "TargetedSendActivatesBeforeSending",
        "BuiltInClinicalCommandUsesConfirmedTarget",
        "TargetedCustomCommandUsesConfirmedTarget",
        "AttendingNameUsesLiteralText",
        "AttendingRoutingUsesInjectedDependencies",
        "BlankAttendingSkipsPowerScribeWrite",
        "FailedAttendingActivationIsReported",
        "ReportSelectionUsesOnlyReportShapedText",
        "ReportSelectionRejectsUnrelatedFallbackText"
    ]

    Setup() {
        this.originalDriver := AppControl.windowDriver
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

    TargetedSendActivatesBeforeSending() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        Assert.True(AppControl.SendKeysToWindow("Vue PACS Client", "{Right}"))
        Assert.Equal(2, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("Vue PACS Client", driver.calls[1].value)
        Assert.Equal("keys", driver.calls[2].kind)
        Assert.Equal("{Right}", driver.calls[2].value)
    }

    BuiltInClinicalCommandUsesConfirmedTarget() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver

        PACSCommands.commands["Sign Report"].Call()

        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal(PowerScribe.windowTitle, driver.calls[1].value)
        Assert.Equal("{F12}", driver.calls[2].value)
    }

    TargetedCustomCommandUsesConfirmedTarget() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        command := PACSCommands.CreateCustomKeybind("^d", "Custom Clinical Window")

        command.Call()

        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal("Custom Clinical Window", driver.calls[1].value)
        Assert.Equal("^d", driver.calls[2].value)
    }

    AttendingNameUsesLiteralText() {
        driver := FakeWindowDriver()
        AppControl.windowDriver := driver
        attending := "Smith + Jones {Neuro}"

        Assert.True(PowerScribe.SetAttending(attending))
        Assert.Equal(6, driver.calls.Length)
        Assert.Equal("activate", driver.calls[1].kind)
        Assert.Equal(PowerScribe.windowTitle, driver.calls[1].value)
        Assert.Equal("keys", driver.calls[2].kind)
        Assert.Equal("{Alt down}ta{Alt up}", driver.calls[2].value)
        Assert.Equal("text", driver.calls[4].kind)
        Assert.Equal(attending, driver.calls[4].value)
        Assert.Equal("keys", driver.calls[6].kind)
        Assert.Equal("{tab}{space}{tab}{Enter}", driver.calls[6].value)
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

    FailedAttendingActivationIsReported() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Chest"] := "Smith"
        ProfileManager.profiles["Test"] := profile
        ProfileManager.currentProfile := "Test"
        AppControl.windowDriver := FakeWindowDriver(false)

        Assert.Throws(
            () => checkAttending("EXAMINATION: CT CHEST"),
            "could not activate PowerScribe"
        )
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
        ProfileManager.profiles := this.originalProfiles
        ProfileManager.currentProfile := this.originalCurrentProfile
    }
}

class FakeWindowDriver {
    __New(activationResult := true) {
        this.activationResult := activationResult
        this.calls := []
    }

    Activate(title, timeoutSeconds) {
        this.calls.Push({kind: "activate", value: title, timeout: timeoutSeconds})
        return this.activationResult
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
