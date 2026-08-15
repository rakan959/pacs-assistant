#Requires AutoHotkey v2.0
#Include ../MicrophoneManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class MicrophoneManagerTest {
    static Tests := [
        "WaitForSelectionRequiresTheExactResolvedValue",
        "WaitForSelectionIgnoresDisplayCasing",
        "MicrophoneComboRequiresExactIdentityAndCapability",
        "MicrophoneComboMustBeUniqueWithinTheExactWindow",
        "UnreadableMicrophoneComboAlongsideValidFailsClosed",
        "UnsupportedMicrophoneValuePreventsAnySelectionMutation",
        "PartialMicrophoneNameMustResolveUniquely",
        "ExactMicrophoneNameWinsOverPartialMatches",
        "MicrophoneItemMustBelongToTheExactCombo",
        "UnreadableMicrophoneItemAlongsideValidDoesNotSelect",
        "SelectionUsesOneExactItemWithoutDirectTextWrite",
        "SelectedItemCannotReplaceTheComboValuePostcondition",
        "AmbiguousPartialSelectionDoesNotMutate",
        "PickerLookupErrorsReachTheBoundedFailureNotification",
        "FinalSelectionFailureNotifiesOnce",
        "OperationalErrorIsRecorded",
        "PickerReappearanceStartsANewLoginSession",
        "PickerUncertaintyConsumesOneBoundedSessionBudget",
        "ActiveClinicalLeaseSkipsBackgroundMicrophoneCheck",
        "RecycledWindowHandleWithNewProcessStartsANewLoginSession"
    ]

    Setup() {
        this.originalNotifier := MicrophoneManager.notifier
        this.originalSessionDriver := MicrophoneManager.sessionDriver
        this.originalAutomationAcquire := MicrophoneManager.automationAcquire
        this.originalAutomationRelease := MicrophoneManager.automationRelease
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
        MicrophoneManager.attemptedWindow := 0
        MicrophoneManager.attemptedProcessId := 0
    }

    WaitForSelectionRequiresTheExactResolvedValue() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo._value := "PowerMic III"
        MicrophoneManager.sessionDriver := fixture.driver

        Assert.True(MicrophoneManager.WaitForSelection(
            fixture.session,
            "PowerMic III",
            0
        ))
        Assert.False(MicrophoneManager.WaitForSelection(
            fixture.session,
            "PowerMic",
            0
        ))
    }

    WaitForSelectionIgnoresDisplayCasing() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo._value := "POWERMIC III"
        MicrophoneManager.sessionDriver := fixture.driver

        Assert.True(MicrophoneManager.WaitForSelection(
            fixture.session,
            "powermic iii",
            0
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

        result := MicrophoneManager.ResolveMicrophoneComboInRoot(fixture.root)
        Assert.Equal("ambiguous", result.status)
        Assert.Equal(0, result.combo)
    }

    UnreadableMicrophoneComboAlongsideValidFailsClosed() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.root.combos.Push(UnreadableMicrophoneCombo(
            fixture.session.processId,
            fixture.session.hwnd
        ))

        result := MicrophoneManager.ResolveMicrophoneComboInRoot(fixture.root)
        Assert.Equal("error", result.status)
        Assert.Equal(0, result.combo)
    }

    UnsupportedMicrophoneValuePreventsAnySelectionMutation() {
        fixture := MicrophoneFixture([])
        combo := UnsupportedValueMicrophoneCombo(
            fixture.session.processId,
            fixture.session.hwnd,
            MicrophoneManager.comboAutomationId
        )
        item := FakeMicrophoneItem(
            fixture.session.processId,
            fixture.session.hwnd,
            "PowerMic III",
            combo
        )
        combo.items := [item]
        fixture.root.combos := [combo]
        fixture.root.items := [item]
        MicrophoneManager.sessionDriver := fixture.driver

        result := MicrophoneManager.SelectMicrophone(
            fixture.session,
            combo,
            "PowerMic"
        )

        Assert.False(result)
        Assert.Equal(0, combo.expandCalls)
        Assert.Equal(0, item.selectCalls)
    }

    PartialMicrophoneNameMustResolveUniquely() {
        fixture := MicrophoneFixture(["PowerMic III", "PowerMic Mobile"])

        result := MicrophoneManager.ResolveMicrophoneItemResult(
            fixture.root,
            fixture.combo,
            "PowerMic"
        )
        Assert.Equal("ambiguous", result.status)
    }

    ExactMicrophoneNameWinsOverPartialMatches() {
        fixture := MicrophoneFixture(["PowerMic III", "PowerMic III Mobile"])

        result := MicrophoneManager.ResolveMicrophoneItemResult(
            fixture.root,
            fixture.combo,
            "PowerMic III"
        )
        resolved := result.selection

        Assert.True(IsObject(resolved))
        Assert.Equal("PowerMic III", resolved.name)
        Assert.True(resolved.item == fixture.items[1])
    }

    MicrophoneItemMustBelongToTheExactCombo() {
        fixture := MicrophoneFixture([])
        unrelatedCombo := FakeMicrophoneCombo(42, 100, "unrelatedCombo")
        unrelatedItem := FakeMicrophoneItem(
            42,
            100,
            "PowerMic III",
            unrelatedCombo
        )
        fixture.root.items := [unrelatedItem]

        result := MicrophoneManager.ResolveMicrophoneItemResult(
            fixture.root,
            fixture.combo,
            "PowerMic"
        )
        Assert.Equal("absent", result.status)
    }

    UnreadableMicrophoneItemAlongsideValidDoesNotSelect() {
        fixture := MicrophoneFixture(["PowerMic III"])
        unreadable := UnreadableMicrophoneItem(
            fixture.session.processId,
            fixture.session.hwnd,
            fixture.combo
        )
        fixture.items.Push(unreadable)
        fixture.combo.items := fixture.items
        fixture.root.items := fixture.items
        MicrophoneManager.sessionDriver := fixture.driver

        succeeded := MicrophoneManager.SelectMicrophone(
            fixture.session,
            fixture.combo,
            "PowerMic"
        )

        Assert.False(succeeded)
        Assert.Equal(0, fixture.items[1].selectCalls)
        Assert.True(InStr(MicrophoneManager.lastError, "unreadable microphone item") > 0)
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

    SelectedItemCannotReplaceTheComboValuePostcondition() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.items[1].updatesComboOnSelect := false
        MicrophoneManager.sessionDriver := fixture.driver

        succeeded := MicrophoneManager.SelectMicrophone(
            fixture.session,
            fixture.combo,
            "PowerMic"
        )

        Assert.False(succeeded)
        Assert.Equal("Internal Microphone", fixture.combo._value)
        Assert.Equal(1, fixture.items[1].selectCalls)
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

    PickerLookupErrorsReachTheBoundedFailureNotification() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.driver.rootError := "simulated picker lookup failure"
        MicrophoneManager.sessionDriver := fixture.driver

        Loop MicrophoneManager.maxAttempts
            MicrophoneManager.CheckForLogin()

        Assert.Equal(MicrophoneManager.maxAttempts, MicrophoneManager.attempts)
        Assert.True(MicrophoneManager.failureNotified)
        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("simulated picker lookup failure", MicrophoneManager.lastError)
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
        Assert.Equal(MicrophoneManager.maxAttempts, MicrophoneManager.attempts)
    }

    PickerUncertaintyConsumesOneBoundedSessionBudget() {
        fixture := MicrophoneFixture([])
        driver := SequencedMicrophoneSessionDriver(
            fixture.session,
            fixture.root,
            ["unique", "error", "unique", "error"]
        )
        MicrophoneManager.sessionDriver := driver

        Loop 4
            MicrophoneManager.CheckForLogin()

        Assert.Equal(MicrophoneManager.maxAttempts, MicrophoneManager.attempts)
        Assert.True(MicrophoneManager.failureNotified)
        Assert.Equal(1, this.notifications.Length)
    }

    ActiveClinicalLeaseSkipsBackgroundMicrophoneCheck() {
        fixture := MicrophoneFixture(["PowerMic III"])
        originalClinicalActive := PACSCommands.clinicalCommandActive
        originalClinicalName := PACSCommands.activeClinicalCommand
        MicrophoneManager.sessionDriver := fixture.driver
        MicrophoneManager.automationAcquire := ObjBindMethod(
            PACSCommands,
            "AcquireClinicalAutomation"
        )
        MicrophoneManager.automationRelease := ObjBindMethod(
            PACSCommands,
            "ReleaseClinicalAutomation"
        )

        try {
            PACSCommands.clinicalCommandActive := true
            PACSCommands.activeClinicalCommand := "Sign Report"
            result := MicrophoneManager.CheckForLogin()
        } finally {
            PACSCommands.clinicalCommandActive := originalClinicalActive
            PACSCommands.activeClinicalCommand := originalClinicalName
        }

        Assert.False(result)
        Assert.Equal(0, fixture.driver.captureCalls)
    }

    RecycledWindowHandleWithNewProcessStartsANewLoginSession() {
        MicrophoneManager.attemptedWindow := 100
        MicrophoneManager.attemptedProcessId := 41
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.failureNotified := true
        MicrophoneManager.lastError := "old process failure"

        changed := MicrophoneManager.RecordAttemptedSession({
            hwnd: 100,
            processId: 42
        })

        Assert.True(changed)
        Assert.Equal(100, MicrophoneManager.attemptedWindow)
        Assert.Equal(42, MicrophoneManager.attemptedProcessId)
        Assert.Equal(0, MicrophoneManager.attempts)
        Assert.False(MicrophoneManager.failureNotified)
        Assert.Equal("", MicrophoneManager.lastError)
    }

    Teardown() {
        MicrophoneManager.notifier := this.originalNotifier
        MicrophoneManager.sessionDriver := this.originalSessionDriver
        MicrophoneManager.automationAcquire := this.originalAutomationAcquire
        MicrophoneManager.automationRelease := this.originalAutomationRelease
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
        MicrophoneManager.pickerPresent := false
        MicrophoneManager.attemptedWindow := 0
        MicrophoneManager.attemptedProcessId := 0
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
        this.rootError := ""
        this.captureCalls := 0
    }

    CaptureResult() {
        this.captureCalls++
        return {status: "unique", session: this.session}
    }

    IsLive(session) {
        return IsObject(session)
            && session.hwnd = this.session.hwnd
            && session.processId = this.session.processId
    }

    Root(session) {
        if (this.rootError != "")
            throw Error(this.rootError)
        return this.IsLive(session) ? this._root : 0
    }
}

class SequencedMicrophoneSessionDriver extends FakeMicrophoneSessionDriver {
    __New(session, root, statuses) {
        super.__New(session, root)
        this.statuses := statuses
        this.captureCalls := 0
        this.rootCallsThisPoll := 0
    }

    CaptureResult() {
        this.captureCalls++
        this.rootCallsThisPoll := 0
        index := Min(this.captureCalls, this.statuses.Length)
        status := this.statuses[index]
        if (status == "unique")
            return {status: "unique", session: this.session}
        return {status: status, session: 0, error: "simulated provider uncertainty"}
    }

    Root(session) {
        this.rootCallsThisPoll++
        return this.rootCallsThisPoll = 1 ? this._root : 0
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
        this.ClassName := "FakeMicrophoneCombo"
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

class UnreadableMicrophoneCombo {
    __New(processId, windowId) {
        this.ProcessId := processId
        this.WinId := windowId
        this.AutomationId := MicrophoneManager.comboAutomationId
    }

    Type {
        get {
            throw Error("unreadable microphone combo")
        }
    }
}

class UnsupportedValueMicrophoneCombo extends FakeMicrophoneCombo {
    __New(processId, windowId, automationId) {
        super.__New(processId, windowId, automationId)
        this.expandCalls := 0
        this.ExpandCollapsePattern := CountingMicrophoneExpandPattern(this)
    }

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return ""
            case UIA.Property.IsValuePatternAvailable: return false
            case UIA.Property.LegacyIAccessibleValue: return ""
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return false
        }
        return ""
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

class CountingMicrophoneExpandPattern extends FakeMicrophoneExpandPattern {
    Expand() {
        this.combo.expandCalls++
        super.Expand()
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
        this.updatesComboOnSelect := true
        this.combo := combo
        this.SelectionItemPattern := FakeMicrophoneSelectionPattern(this)
    }

    GetPropertyValue(propertyId) {
        if (propertyId = UIA.Property.SelectionItemIsSelected)
            return this.selected
        return ""
    }
}

class UnreadableMicrophoneItem {
    __New(processId, windowId, combo) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Name := "PowerMic III"
        this.combo := combo
    }

    Type {
        get {
            throw Error("unreadable microphone item")
        }
    }
}

class FakeMicrophoneSelectionPattern {
    __New(item) {
        this.item := item
    }

    SelectionContainer => this.item.combo

    Select() {
        this.item.selectCalls++
        this.item.selected := true
        if this.item.updatesComboOnSelect
            this.item.combo._value := this.item.Name
    }
}
