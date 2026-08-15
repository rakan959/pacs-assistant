#Requires AutoHotkey v2.0
#Include ../MicrophoneManager.ahk
#Include TestRunner.ahk

class MicrophoneManagerTest {
    static Tests := [
        "WaitForSelectionRequiresTheExactResolvedValue",
        "WaitForSelectionIgnoresDisplayCasing",
        "MicrophoneComboRequiresExactIdentityAndCapability",
        "MicrophoneComboMustBeUniqueWithinTheExactWindow",
        "PartialMicrophoneNameMustResolveUniquely",
        "ExactMicrophoneNameWinsOverPartialMatches",
        "SelectionUsesOneExactItemWithoutDirectTextWrite",
        "AmbiguousPartialSelectionDoesNotMutate",
        "FinalSelectionFailureNotifiesOnce",
        "OperationalErrorIsRecorded",
        "PickerReappearanceStartsANewLoginSession"
    ]

    Setup() {
        this.originalNotifier := MicrophoneManager.notifier
        this.originalSessionDriver := MicrophoneManager.sessionDriver
        this.notifications := []
        MicrophoneManager.notifier := (text, title, options) => this.notifications.Push({
            text: text,
            title: title,
            options: options
        })
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
        MicrophoneManager.pickerPresent := false
    }

    WaitForSelectionRequiresTheExactResolvedValue() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo._value := "PowerMic III"
        MicrophoneManager.sessionDriver := fixture.driver

        Assert.True(MicrophoneManager.WaitForSelection(
            fixture.session,
            "PowerMic III",
            0,
            fixture.items[1]
        ))
        Assert.False(MicrophoneManager.WaitForSelection(
            fixture.session,
            "PowerMic",
            0,
            fixture.items[1]
        ))
    }

    WaitForSelectionIgnoresDisplayCasing() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo._value := "POWERMIC III"
        MicrophoneManager.sessionDriver := fixture.driver

        Assert.True(MicrophoneManager.WaitForSelection(
            fixture.session,
            "powermic iii",
            0,
            fixture.items[1]
        ))
    }

    MicrophoneComboRequiresExactIdentityAndCapability() {
        fixture := MicrophoneFixture(["PowerMic III"])
        root := fixture.root

        Assert.True(MicrophoneManager.IsExpectedMicrophoneCombo(root, fixture.combo))
        Assert.False(MicrophoneManager.IsExpectedMicrophoneCombo(
            root,
            FakeMicrophoneCombo(99, 100, MicrophoneManager.comboAutomationId)
        ))
        Assert.False(MicrophoneManager.IsExpectedMicrophoneCombo(
            root,
            FakeMicrophoneCombo(42, 200, MicrophoneManager.comboAutomationId)
        ))
        Assert.False(MicrophoneManager.IsExpectedMicrophoneCombo(
            root,
            FakeMicrophoneCombo(42, 100, "otherCombo")
        ))
        Assert.False(MicrophoneManager.IsExpectedMicrophoneCombo(
            root,
            FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId, false)
        ))
        noExpand := FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId)
        noExpand.IsExpandCollapsePatternAvailable := false
        Assert.False(MicrophoneManager.IsExpectedMicrophoneCombo(root, noExpand))
        wrongType := FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId)
        wrongType.Type := UIA.Type.Edit
        Assert.False(MicrophoneManager.IsExpectedMicrophoneCombo(root, wrongType))
    }

    MicrophoneComboMustBeUniqueWithinTheExactWindow() {
        fixture := MicrophoneFixture(["PowerMic III"])
        duplicate := FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId)
        fixture.root.combos.Push(duplicate)

        Assert.Equal(0, MicrophoneManager.FindMicrophoneComboInRoot(fixture.root))
    }

    PartialMicrophoneNameMustResolveUniquely() {
        fixture := MicrophoneFixture(["PowerMic III", "PowerMic Mobile"])

        Assert.Equal(0, MicrophoneManager.ResolveMicrophoneItem(
            fixture.root,
            fixture.combo,
            "PowerMic"
        ))
    }

    ExactMicrophoneNameWinsOverPartialMatches() {
        fixture := MicrophoneFixture(["PowerMic III", "PowerMic III Mobile"])

        resolved := MicrophoneManager.ResolveMicrophoneItem(
            fixture.root,
            fixture.combo,
            "PowerMic III"
        )

        Assert.True(IsObject(resolved))
        Assert.Equal("PowerMic III", resolved.name)
        Assert.True(resolved.item == fixture.items[1])
    }

    SelectionUsesOneExactItemWithoutDirectTextWrite() {
        fixture := MicrophoneFixture(["Internal Microphone", "PowerMic III"])
        MicrophoneManager.sessionDriver := fixture.driver

        succeeded := MicrophoneManager.SelectMicrophone(
            fixture.session,
            fixture.combo,
            "PowerMic"
        )

        Assert.True(succeeded)
        Assert.Equal("PowerMic III", fixture.combo._value)
        Assert.Equal(1, fixture.items[2].selectCalls)
        Assert.Equal(0, fixture.combo.writeCalls)
    }

    AmbiguousPartialSelectionDoesNotMutate() {
        fixture := MicrophoneFixture(["PowerMic III", "PowerMic Mobile"])
        MicrophoneManager.sessionDriver := fixture.driver

        succeeded := MicrophoneManager.SelectMicrophone(
            fixture.session,
            fixture.combo,
            "PowerMic"
        )

        Assert.False(succeeded)
        Assert.Equal(0, fixture.items[1].selectCalls)
        Assert.Equal(0, fixture.items[2].selectCalls)
        Assert.Equal(0, fixture.combo.writeCalls)
    }

    FinalSelectionFailureNotifiesOnce() {
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.RecordSelectionFailure("PowerMic")
        MicrophoneManager.RecordSelectionFailure("PowerMic")

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "PowerMic") > 0)
        Assert.Equal("PowerScribe microphone was not changed", this.notifications[1].title)
    }

    OperationalErrorIsRecorded() {
        MicrophoneManager.RecordOperationalError(Error("UIA unavailable"))

        Assert.Equal("UIA unavailable", MicrophoneManager.lastError)
    }

    PickerReappearanceStartsANewLoginSession() {
        MicrophoneManager.pickerPresent := true
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.failureNotified := true
        MicrophoneManager.lastError := "old failure"

        MicrophoneManager.RecordPickerPresence(false)
        Assert.False(MicrophoneManager.pickerPresent)
        Assert.Equal(0, MicrophoneManager.attempts)
        Assert.False(MicrophoneManager.failureNotified)
        Assert.Equal("", MicrophoneManager.lastError)

        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.RecordPickerPresence(true)
        Assert.True(MicrophoneManager.pickerPresent)
        Assert.Equal(0, MicrophoneManager.attempts)
    }

    Teardown() {
        MicrophoneManager.notifier := this.originalNotifier
        MicrophoneManager.sessionDriver := this.originalSessionDriver
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
        MicrophoneManager.pickerPresent := false
    }
}

class MicrophoneFixture {
    __New(names) {
        this.session := {
            hwnd: 100,
            target: "ahk_id 100",
            processId: 42,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable
        }
        this.combo := FakeMicrophoneCombo(
            this.session.processId,
            this.session.hwnd,
            MicrophoneManager.comboAutomationId
        )
        this.items := []
        for name in names
            this.items.Push(FakeMicrophoneItem(
                this.session.processId,
                this.session.hwnd,
                name,
                this.combo
            ))
        this.combo.items := this.items
        this.root := FakeMicrophoneRoot(
            this.session.processId,
            this.session.hwnd,
            [this.combo],
            this.items
        )
        this.driver := FakeMicrophoneSessionDriver(this.session, this.root)
    }
}

class FakeMicrophoneSessionDriver {
    __New(session, root) {
        this.session := session
        this._root := root
    }

    IsLive(session) {
        return IsObject(session)
            && session.hwnd = this.session.hwnd
            && session.processId = this.session.processId
    }

    Root(session) {
        return this.IsLive(session) ? this._root : 0
    }
}

class FakeMicrophoneRoot {
    __New(processId, windowId, combos, items) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Type := UIA.Type.Window
        this.combos := combos
        this.items := items
    }

    FindElements(criteria) {
        if HasProp(criteria, "AutomationId")
            return this.combos.Clone()
        if HasProp(criteria, "Type") {
            type := criteria.Type
            if (type = "ComboBox" || type = UIA.Type.ComboBox)
                return this.combos.Clone()
            if (type = "ListItem" || type = UIA.Type.ListItem)
                return this.items.Clone()
        }
        return []
    }

    ElementExist(*) {
        return this.combos.Length ? this.combos[1] : 0
    }

    ElementFromPath(*) {
        return this.combos.Length ? this.combos[1] : 0
    }
}

class FakeMicrophoneCombo {
    __New(processId, windowId, automationId, enabled := true) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Type := UIA.Type.ComboBox
        this.AutomationId := automationId
        this.Name := "Microphone"
        this.IsEnabled := enabled
        this.IsExpandCollapsePatternAvailable := true
        this.IsValuePatternAvailable := true
        this.IsLegacyIAccessiblePatternAvailable := false
        this.writeCalls := 0
        this._value := "Internal Microphone"
        this.items := []
        this.ExpandCollapsePattern := FakeMicrophoneExpandPattern(this)
    }

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return this._value
            case UIA.Property.IsValuePatternAvailable: return true
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return false
        }
        return ""
    }

    Value {
        get => this._value
        set {
            this.writeCalls++
            this._value := value
        }
    }

    FindElements(*) {
        return this.items.Clone()
    }

    Click(*) {
        this.ExpandCollapsePattern.Expand()
        return "Expand"
    }
}

class FakeMicrophoneExpandPattern {
    __New(combo) {
        this.combo := combo
    }

    Expand() {
        this.combo.expanded := true
    }

    Collapse() {
        this.combo.expanded := false
    }
}

class FakeMicrophoneItem {
    __New(processId, windowId, name, combo) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Type := UIA.Type.ListItem
        this.Name := name
        this.AutomationId := ""
        this.IsEnabled := true
        this.IsSelectionItemPatternAvailable := true
        this.selected := false
        this.selectCalls := 0
        this.combo := combo
        this.SelectionItemPattern := FakeMicrophoneSelectionPattern(this)
    }

    GetPropertyValue(propertyId) {
        if (propertyId = UIA.Property.SelectionItemIsSelected)
            return this.selected
        return ""
    }
}

class FakeMicrophoneSelectionPattern {
    __New(item) {
        this.item := item
    }

    Select() {
        this.item.selectCalls++
        this.item.selected := true
        this.item.combo._value := this.item.Name
    }
}
