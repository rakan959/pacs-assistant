; = CONTENTS
;   + Preamble
;   + MicrophoneManagerTest class (microphone selection, combo resolution, picker session)
;   + Test doubles (session drivers, combo/item/expand/selection patterns, fixture)

#Requires AutoHotkey v2.0
#Include ../MicrophoneManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk
#Include SettingsFixture.ahk
#Include LogCapture.ahk

class MicrophoneManagerTest {
    static tests := [
        "FailureBeforeTheAttemptLimitStaysQuiet",
        "WaitForSelectionRequiresTheExactResolvedValue",
        "WaitForSelectionIgnoresDisplayCasing",
        "MicrophoneComboRequiresExactIdentityAndCapability",
        "MicrophoneComboMustBeUniqueWithinTheExactWindow",
        "UnreadableMicrophoneComboAlongsideValidFailsClosed",
        "UnsupportedMicrophoneValuePreventsAnySelectionMutation",
        "PartialMicrophoneNameMustResolveUniquely",
        "ExactMicrophoneNameWinsOverPartialMatches",
        "MicrophoneItemIdentityRequiresEachProperty",
        "MicrophoneItemMustBelongToTheExactCombo",
        "UnreadableMicrophoneItemAlongsideValidDoesNotSelect",
        "ItemInvalidatedByFinalComboCheckIsNotSelected",
        "SelectionStopsWhenATargetChangesBeforeSelect",
        "SelectionUsesOneExactItemWithoutDirectTextWrite",
        "SelectedItemCannotReplaceTheComboValuePostcondition",
        "AmbiguousPartialSelectionDoesNotMutate",
        "PickerLookupErrorsReachTheBoundedFailureNotification",
        "FinalSelectionFailureNotifiesOnce",
        "OperationalErrorIsRecorded",
        "PickerReappearanceStartsANewLoginSession",
        "PickerUncertaintyConsumesOneBoundedSessionBudget",
        "ActiveClinicalLeaseSkipsBackgroundMicrophoneCheck",
        "RecycledWindowHandleWithNewProcessStartsANewLoginSession",
        "MonitoringStartsOnlyWithSwapEnabledAndANamedMicrophone",
        "SettingsChangeArmsAndDisarmsTheLoginCheck",
        "ApplyNowSelectsTheConfiguredMicrophone",
        "LoginCheckSelectsOnceAndStaysQuiet",
        "UnmatchedNameStopsAfterTheAttemptLimit",
        "ClosedPowerScribeIsNotAFailure",
        "UnusablePickerIsAFailureNotALogin",
        "ApplyNowNamesEachFailureAndKeepsTheResolutionError",
        "UnconfirmedSelectionNamesTheTimeoutNotTheName",
        "UnverifiableMicrophoneListIsNotBlamedOnTheName",
        "AmbiguousNameReasonReachesBothNotices"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "ChangePicker"
    ]

    FailureBeforeTheAttemptLimitStaysQuiet() {
        fixture := MicrophoneFixture(["PowerMic III"])
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "SpeechMike")
        MicrophoneManager.CheckForLogin()
        Assert.Equal(1, MicrophoneManager.attempts)
        Assert.Equal(0, this.notifications.Length)
    }

    Setup() {
        this.savedSettings := UseTestSettings("microphone-settings")
        this.originalNotifier := MicrophoneManager.notifier
        this.originalSessionDriver := MicrophoneManager.sessionDriver
        this.originalAutomationAcquire := MicrophoneManager.automationAcquire
        this.originalAutomationRelease := MicrophoneManager.automationRelease
        this.notifications := []
        MicrophoneManager.notifier := RecordNotification.Bind(this.notifications)
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
        MicrophoneManager.attemptedWindow := 0
        MicrophoneManager.attemptedProcessId := 0
    }

    MonitoringStartsOnlyWithSwapEnabledAndANamedMicrophone() {
        cases := [
            {swap: false, name: "PowerMic", armed: false},
            {swap: true, name: "   ", armed: false},
            {swap: true, name: "PowerMic", armed: true}
        ]
        try {
            for expected in cases {
                Settings.SaveValues(Map("SwapMicrophoneOnLogin", expected.swap, "MicrophoneName", expected.name))
                MicrophoneManager.StartMonitoring()
                armed := IsObject(MicrophoneManager.pollTimer)
                MicrophoneManager.StopMonitoring()
                Assert.Equal(expected.armed, armed, "swap=" expected.swap " name='" expected.name "'")
            }
        } finally MicrophoneManager.StopMonitoring()
    }

    ; A settings save takes effect without a restart.
    SettingsChangeArmsAndDisarmsTheLoginCheck() {
        try {
            Settings.SaveValues(Map("SwapMicrophoneOnLogin", true, "MicrophoneName", "PowerMic"))
            MicrophoneManager.OnSettingsChanged()
            Assert.True(IsObject(MicrophoneManager.pollTimer))

            SetTestSetting("SwapMicrophoneOnLogin", false)
            MicrophoneManager.OnSettingsChanged()
            Assert.Equal(0, MicrophoneManager.pollTimer)
        } finally MicrophoneManager.StopMonitoring()
    }

    ; Each recheck before Select() stops the selection when its target changed.
    ; Root reads during a selection: 1 and 2 revalidate the picker around Expand,
    ; 3 checks whether the microphone is already selected, 4 re-resolves the picker
    ; and item, and 5 is the final picker read.
    SelectionStopsWhenATargetChangesBeforeSelect() {
        cases := [
            {label: "picker replaced", atRead: 1, change: "combo", reason: MicrophoneManager.selectorChangedReason},
            {label: "item replaced before the live check", atRead: 4, change: "item",
                reason: MicrophoneManager.listChangedReason},
            {label: "item replaced before the final check", atRead: 5, change: "item",
                reason: MicrophoneManager.listChangedReason},
            {label: "picker unreadable once the final read resolved it", atRead: 5, change: "unreadable",
                reason: "the microphone selector's value could not be read"}
        ]
        for testCase in cases {
            fixture := MicrophoneFixture(["PowerMic III"])
            original := fixture.items[1]
            replacement := FakeMicrophoneItem(fixture.session.processId, fixture.session.hwnd, "PowerMic III", fixture.combo)
            ; Closures cannot see the loop variable, so they use local copies.
            atRead := testCase.atRead
            change := testCase.change
            MicrophoneManager.sessionDriver := HookedMicrophoneSessionDriver(
                fixture.session,
                fixture.root,
                (read) => read = atRead ? this.ChangePicker(fixture, replacement, change) : 0
            )
            MicrophoneManager.lastError := ""

            Assert.False(MicrophoneManager.SelectMicrophone(fixture.session, fixture.combo, "PowerMic III"), testCase.label)
            Assert.Equal(0, original.selectCalls, testCase.label)
            Assert.Equal(0, replacement.selectCalls, testCase.label)
            Assert.Equal(testCase.reason, MicrophoneManager.lastError, testCase.label)
        }
    }

    ; Changes the picker as PowerScribe can between reads: a new ComboBox, a
    ; rerendered list item, or a value that stops being readable right after the
    ; read that resolves the picker.
    ChangePicker(fixture, replacement, change) {
        switch change {
            case "combo":
                fixture.root.combos := [FakeMicrophoneCombo(
                    fixture.session.processId,
                    fixture.session.hwnd,
                    MicrophoneManager.comboAutomationId
                )]
            case "item":
                fixture.combo.items := [replacement]
                fixture.root.items := [replacement]
            case "unreadable":
                fixture.combo.valueReadsLeft := 1
        }
    }

    ApplyNowSelectsTheConfiguredMicrophone() {
        fixture := MicrophoneFixture(["Internal Microphone", "PowerMic III"])
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "PowerMic III")

        Assert.True(MicrophoneManager.ApplyNow())

        Assert.Equal(0, TestRunner.dialogs.Length)
        Assert.Equal(0, fixture.items[1].selectCalls)
        Assert.Equal(1, fixture.items[2].selectCalls)
    }

    ; One verified selection per login window; later polls of the same window
    ; neither select again nor notify.
    LoginCheckSelectsOnceAndStaysQuiet() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo.expandCalls := 0
        fixture.combo.ExpandCollapsePattern := CountingMicrophoneExpandPattern(fixture.combo)
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "PowerMic III")

        MicrophoneManager.CheckForLogin()
        MicrophoneManager.CheckForLogin()

        Assert.Equal(MicrophoneManager.maxAttempts, MicrophoneManager.attempts)
        Assert.Equal(1, fixture.items[1].selectCalls)
        ; The picker stays on screen until the user logs in; it is not reopened.
        Assert.Equal(1, fixture.combo.expandCalls)
        Assert.Equal(0, this.notifications.Length)
    }

    ; Bounded so a mismatched microphone name cannot retry forever.
    UnmatchedNameStopsAfterTheAttemptLimit() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo.expandCalls := 0
        fixture.combo.ExpandCollapsePattern := CountingMicrophoneExpandPattern(fixture.combo)
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "SpeechMike")

        loop MicrophoneManager.maxAttempts + 2
            MicrophoneManager.CheckForLogin()

        Assert.Equal(MicrophoneManager.maxAttempts, MicrophoneManager.attempts)
        Assert.Equal(MicrophoneManager.maxAttempts, fixture.combo.expandCalls)
        Assert.Equal(0, fixture.items[1].selectCalls)
        Assert.Equal(1, this.notifications.Length)
    }

    ; PowerScribe not running is the normal state between sessions.
    ClosedPowerScribeIsNotAFailure() {
        fixture := MicrophoneFixture(["PowerMic III"])
        MicrophoneManager.sessionDriver := SequencedMicrophoneSessionDriver(fixture.session, fixture.root, ["absent"])
        SetTestSetting("MicrophoneName", "PowerMic III")

        loop MicrophoneManager.maxAttempts + 1
            MicrophoneManager.CheckForLogin()

        Assert.Equal(0, MicrophoneManager.attempts)
        Assert.Equal(0, this.notifications.Length)
    }

    ; A picker that is present but unusable is not the logged-in state, where the
    ; picker is gone.
    UnusablePickerIsAFailureNotALogin() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.combo.IsEnabled := false
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "PowerMic III")

        loop MicrophoneManager.maxAttempts + 1
            MicrophoneManager.CheckForLogin()

        Assert.Equal(0, fixture.items[1].selectCalls)
        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("PowerScribe Microphone Not Changed", this.notifications[1].title)
        Assert.True(InStr(this.notifications[1].text, "expected identity or capability"), this.notifications[1].text)
    }

    ApplyNowNamesEachFailureAndKeepsTheResolutionError() {
        fixture := MicrophoneFixture([])
        capturedLog := LogCapture()
        try {
            SetTestSetting("MicrophoneName", "")
            Assert.False(MicrophoneManager.ApplyNow())

            SetTestSetting("MicrophoneName", "PowerMic III")
            MicrophoneManager.sessionDriver := SequencedMicrophoneSessionDriver(fixture.session, fixture.root, ["error"])
            Assert.False(MicrophoneManager.ApplyNow())
            MicrophoneManager.sessionDriver := SequencedMicrophoneSessionDriver(fixture.session, fixture.root, ["absent"])
            Assert.False(MicrophoneManager.ApplyNow())
            ; Each dialog is also in error.log, the provider error included.
            loggedUnverified := capturedLog.Count("PowerScribe Not Verified: PowerScribe window identity could not be verified. simulated provider uncertainty")
            loggedTotal := capturedLog.Count("Not Running: ") + capturedLog.Count("Not Verified: ") + capturedLog.Count("Microphone Configured: ")
        } finally capturedLog.Restore()
        Assert.Equal(1, loggedUnverified)
        Assert.Equal(3, loggedTotal)

        Assert.Equal(3, TestRunner.dialogs.Length)
        Assert.Equal("No Microphone Configured", TestRunner.dialogs[1].title)
        Assert.Equal("PowerScribe Not Verified", TestRunner.dialogs[2].title)
        Assert.True(InStr(TestRunner.dialogs[2].text, "simulated provider uncertainty"), TestRunner.dialogs[2].text)
        Assert.Equal("PowerScribe Not Running", TestRunner.dialogs[3].title)
    }

    ; Select() ran on the one exact match, but PowerScribe never showed it selected.
    UnconfirmedSelectionNamesTheTimeoutNotTheName() {
        fixture := MicrophoneFixture(["PowerMic III"])
        fixture.items[1].updatesComboOnSelect := false
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "PowerMic III")

        Assert.False(MicrophoneManager.ApplyNow())
        Assert.Equal(1, fixture.items[1].selectCalls)
        Assert.Equal(
            "Could not select microphone 'PowerMic III': PowerScribe did not confirm the selection within 1 second.",
            TestRunner.dialogs[1].text
        )
    }

    ; A list with no items, or none that verify, is not a misspelled name.
    UnverifiableMicrophoneListIsNotBlamedOnTheName() {
        empty := MicrophoneFixture([])
        disabled := MicrophoneFixture(["PowerMic III"])
        disabled.items[1].IsEnabled := false
        SetTestSetting("MicrophoneName", "PowerMic III")

        MicrophoneManager.sessionDriver := empty.driver
        Assert.False(MicrophoneManager.ApplyNow())
        MicrophoneManager.sessionDriver := disabled.driver
        Assert.False(MicrophoneManager.ApplyNow())

        Assert.Equal(
            "Could not select microphone 'PowerMic III': the microphone list exposed no items.",
            TestRunner.dialogs[1].text
        )
        Assert.Equal(
            "Could not select microphone 'PowerMic III': the microphone list items did not have their expected identity.",
            TestRunner.dialogs[2].text
        )
        Assert.Equal(0, disabled.items[1].selectCalls)
    }

    ; "PowerMic" matches two devices: the advice must not blame the name's spelling.
    AmbiguousNameReasonReachesBothNotices() {
        fixture := MicrophoneFixture(["PowerMic II", "PowerMic III"])
        MicrophoneManager.sessionDriver := fixture.driver
        SetTestSetting("MicrophoneName", "PowerMic")

        Assert.False(MicrophoneManager.ApplyNow())
        Assert.Equal("Microphone Not Selected", TestRunner.dialogs[1].title)
        Assert.Equal(
            "Could not select microphone 'PowerMic': the microphone name matches multiple devices.",
            TestRunner.dialogs[1].text
        )

        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.RecordSelectionFailure("PowerMic")
        Assert.True(InStr(this.notifications[1].text, "Last error: the microphone name matches multiple devices"), this.notifications[1].text)
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

        Assert.True(MicrophoneManager.InspectMicrophoneCombo(root, fixture.combo))
        Assert.False(MicrophoneManager.InspectMicrophoneCombo(
            root,
            FakeMicrophoneCombo(99, 100, MicrophoneManager.comboAutomationId)
        ))
        Assert.False(MicrophoneManager.InspectMicrophoneCombo(
            root,
            FakeMicrophoneCombo(42, 200, MicrophoneManager.comboAutomationId)
        ))
        Assert.False(MicrophoneManager.InspectMicrophoneCombo(
            root,
            FakeMicrophoneCombo(42, 100, "otherCombo")
        ))
        Assert.False(MicrophoneManager.InspectMicrophoneCombo(
            root,
            FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId, false)
        ))
        noExpand := FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId)
        noExpand.IsExpandCollapsePatternAvailable := false
        Assert.False(MicrophoneManager.InspectMicrophoneCombo(root, noExpand))
        wrongType := FakeMicrophoneCombo(42, 100, MicrophoneManager.comboAutomationId)
        wrongType.Type := UIA.Type.Edit
        Assert.False(MicrophoneManager.InspectMicrophoneCombo(root, wrongType))
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

    ; A microphone item must be an enabled, selectable, named list item in the
    ; picker's process and window, contained by the picker; each condition alone
    ; rejects it.
    MicrophoneItemIdentityRequiresEachProperty() {
        fixture := MicrophoneFixture(["Desk Mic"])
        Assert.True(MicrophoneManager.InspectMicrophoneItem(fixture.root, fixture.combo, fixture.items[1]))
        variants := [
            {label: "process", property: "ProcessId", value: fixture.session.processId + 1},
            {label: "window", property: "WinId", value: fixture.session.hwnd + 1},
            {label: "type", property: "Type", value: UIA.Type.Button},
            {label: "disabled", property: "IsEnabled", value: false},
            {label: "not selectable", property: "IsSelectionItemPatternAvailable", value: false},
            {label: "blank name", property: "Name", value: "  "},
            {label: "no container", property: "combo", value: 0}
        ]
        for variant in variants {
            item := FakeMicrophoneItem(fixture.session.processId, fixture.session.hwnd, "Desk Mic", fixture.combo)
            item.%variant.property% := variant.value
            Assert.False(MicrophoneManager.InspectMicrophoneItem(fixture.root, fixture.combo, item), variant.label)
        }
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
        ; Never selectable; and the picker's own list is empty, which is the reason.
        Assert.Equal(0, result.selection)
        Assert.Equal("error", result.status)
        Assert.Equal("the microphone list exposed no items", result.error)
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

    ItemInvalidatedByFinalComboCheckIsNotSelected() {
        fixture := MicrophoneFixture([])
        item := InvalidatableMicrophoneItem(
            fixture.session.processId,
            fixture.session.hwnd,
            "PowerMic III",
            fixture.combo
        )
        fixture.items := [item]
        fixture.combo.items := fixture.items
        fixture.root.items := fixture.items
        ; Root read 5 is the final picker read before Select().
        fixture.driver := HookedMicrophoneSessionDriver(
            fixture.session,
            fixture.root,
            (read) => read = 5 ? item.valid := false : 0
        )
        MicrophoneManager.sessionDriver := fixture.driver

        succeeded := MicrophoneManager.SelectMicrophone(
            fixture.session,
            fixture.combo,
            "PowerMic"
        )

        Assert.False(succeeded)
        Assert.Equal(0, item.selectCalls)
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

        capturedLog := LogCapture()
        try {
            loop MicrophoneManager.maxAttempts
                MicrophoneManager.CheckForLogin()
        } finally {
            logged := capturedLog.Count("PowerScribe microphone was not changed: ")
            capturedLog.Restore()
        }

        Assert.Equal(MicrophoneManager.maxAttempts, MicrophoneManager.attempts)
        Assert.True(MicrophoneManager.failureNotified)
        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("simulated picker lookup failure", MicrophoneManager.lastError)
        ; The notice and one log entry per login session carry the cause.
        Assert.True(InStr(this.notifications[1].text, "Last error: simulated picker lookup failure"), this.notifications[1].text)
        Assert.Equal(1, logged)
    }

    FinalSelectionFailureNotifiesOnce() {
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.RecordSelectionFailure("PowerMic")
        MicrophoneManager.RecordSelectionFailure("PowerMic")

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "PowerMic") > 0)
        Assert.Equal("PowerScribe Microphone Not Changed", this.notifications[1].title)
    }

    OperationalErrorIsRecorded() {
        MicrophoneManager.RecordOperationalError(Error("UIA unavailable"))

        Assert.Equal("UIA unavailable", MicrophoneManager.lastError)
    }

    PickerReappearanceStartsANewLoginSession() {
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.failureNotified := true
        MicrophoneManager.lastError := "old failure"

        MicrophoneManager.RecordPickerAbsence()
        Assert.Equal(0, MicrophoneManager.attempts)
        Assert.False(MicrophoneManager.failureNotified)
        Assert.Equal("", MicrophoneManager.lastError)
    }

    PickerUncertaintyConsumesOneBoundedSessionBudget() {
        fixture := MicrophoneFixture([])
        driver := SequencedMicrophoneSessionDriver(
            fixture.session,
            fixture.root,
            ["unique", "error", "unique", "error"]
        )
        MicrophoneManager.sessionDriver := driver

        loop 4
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
        RestoreTestSettings(this.savedSettings)
        MicrophoneManager.notifier := this.originalNotifier
        MicrophoneManager.sessionDriver := this.originalSessionDriver
        MicrophoneManager.automationAcquire := this.originalAutomationAcquire
        MicrophoneManager.automationRelease := this.originalAutomationRelease
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
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
        ; Simulated clock: selection waits advance it instead of sleeping.
        this.now := 0
    }

    NowMilliseconds() {
        return this.now
    }

    Pause(milliseconds) {
        this.now += milliseconds
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

; Calls onRoot(read) before each Root read, numbered from 1, so a test can change
; the picker at an exact point in a selection.
class HookedMicrophoneSessionDriver extends FakeMicrophoneSessionDriver {
    __New(session, root, onRoot) {
        super.__New(session, root)
        this.onRoot := onRoot
        this.rootCalls := 0
    }

    Root(session) {
        this.rootCalls++
        this.onRoot.Call(this.rootCalls)
        return super.Root(session)
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
            elementType := criteria.Type
            if (elementType = "ComboBox" || elementType = UIA.Type.ComboBox)
                return this.combos.Clone()
            if (elementType = "ListItem" || elementType = UIA.Type.ListItem)
                return this.items.Clone()
        }
        return []
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
        ; When set (>= 0), how many more value reads succeed before the value can no
        ; longer be read, as when the picker rerenders.
        this.valueReadsLeft := -1
    }

    GetPropertyValue(propertyId) {
        readable := this.valueReadsLeft != 0
        switch propertyId {
            case UIA.Property.ValueValue:
                if (this.valueReadsLeft > 0)
                    this.valueReadsLeft--
                return readable ? this._value : ""
            case UIA.Property.IsValuePatternAvailable: return readable && this.IsValuePatternAvailable
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return this.IsLegacyIAccessiblePatternAvailable
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
        ; Neither value pattern is available, and the property API returns its
        ; empty default.
        this.IsValuePatternAvailable := false
        this._value := ""
        this.expandCalls := 0
        this.ExpandCollapsePattern := CountingMicrophoneExpandPattern(this)
    }
}

class FakeMicrophoneExpandPattern {
    __New(combo) {
        this.combo := combo
    }

    Expand() {
    }

    Collapse() {
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
        this.selectCalls := 0
        this.updatesComboOnSelect := true
        this.combo := combo
        this.SelectionItemPattern := FakeMicrophoneSelectionPattern(this)
    }
}

class InvalidatableMicrophoneItem {
    __New(processId, windowId, name, combo) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Name := name
        this.AutomationId := ""
        this.IsEnabled := true
        this.IsSelectionItemPatternAvailable := true
        this.selectCalls := 0
        this.updatesComboOnSelect := true
        this.combo := combo
        this.valid := true
        this.SelectionItemPattern := FakeMicrophoneSelectionPattern(this)
    }

    Type {
        get {
            if !this.valid
                throw Error("microphone item became stale")
            return UIA.Type.ListItem
        }
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
        if this.item.updatesComboOnSelect
            this.item.combo._value := this.item.Name
    }
}
