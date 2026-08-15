#Requires AutoHotkey v2.0
#Include ../WetRead.ahk
#Include TestRunner.ahk

class WetReadTest {
    static Tests := [
        "ClipboardFailureDoesNotTouchTheNote",
        "FailedSendRestoresThePreviousNoteAndClipboard",
        "SuccessfulSendRestoresTheClipboard",
        "UnsupportedUIADoesNotClearTheNote",
        "PostMutationUIAErrorRestoresThePreviousNote",
        "FailedUIAVerificationRestoresThePreviousNote",
        "UIABecomingUnsupportedStillRestoresAnEarlierWrite",
        "FailedControlVerificationRestoresThePreviousNote",
        "UnsupportedControlDoesNotAttemptRollback",
        "DirectRestoreFallsBackAfterPreferredException",
        "SendExceptionRestoresThePreviousNoteAndClipboard",
        "ClearFailureAfterMutationRestoresThePreviousNote",
        "ClipboardRestoreFailureIsReported",
        "UnreadableNoteDoesNotAttemptPaste",
        "UnreadableNativeFieldFailsClosed",
        "StickyRootMustBelongToPacsProcess",
        "StickyOpenerRejectsSameProcessWrongWindowButton",
        "StickyOpenerRejectsAmbiguousSameWindowButtons",
        "StickyOpenerRejectsTitleChangeBeforeInvoke",
        "StickyOpenerRejectsDuplicateAppearingBeforeInvoke",
        "StickyOpenerRejectsUnactivatedStickyWindow",
        "StickyOpenerPinsNewlyActiveExactWindow",
        "StickyDriverUsesExactValidatedWindowHandle",
        "StickyNoteTargetRequiresExpectedTypeProcessAndCapability",
        "StickyNoteTargetMustBeTheUniqueWritableField",
        "NativeDirectWriteRefusesStaleStickyTarget",
        "NativeFocusRefusesStaleStickyTargetBeforeAnyUIAction",
        "NativeControlWithoutHandleIsUnsupported",
        "NativeSendRefusesLostFocus",
        "NativeSendRefusesWrongStickyControlFocus",
        "NativeForwardVerificationRejectsCaseOnlyDifference",
        "NativeRollbackVerificationRejectsCaseOnlyDifference",
        "RoutingFailureReportsTheActualCause",
        "AttendingFailureIsReportedAcrossEveryStickySetupExit"
    ]

    ClipboardFailureDoesNotTouchTheNote() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.clipboardReady := false

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.False(result.success)
        Assert.Equal("clipboard", result.reason)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.clearCalls)
        Assert.Equal("original clipboard", driver.clipboardValue)
        Assert.True(result.clipboardRestored)
    }

    FailedSendRestoresThePreviousNoteAndClipboard() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.False(result.success)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal("original clipboard", driver.clipboardValue)
        Assert.True(result.clipboardRestored)
    }

    SuccessfulSendRestoresTheClipboard() {
        driver := FakeWetReadDriver("existing note", "original clipboard")

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.True(result.success)
        Assert.Equal("new wet read", driver.fieldValue)
        Assert.Equal("original clipboard", driver.clipboardValue)
        Assert.True(result.clipboardRestored)
    }

    UnsupportedUIADoesNotClearTheNote() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.uiaSupported := false

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.True(result.unsupported)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.clearCalls)
    }

    PostMutationUIAErrorRestoresThePreviousNote() {
        field := PostMutationFailingWetReadElement("existing note", "new wet read")
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadWindowDriver(true),
            FakeWetReadFocusDriver(true)
        )

        result := WetReadPasteEngine.Paste(
            field,
            "new wet read",
            "uia",
            driver
        )

        Assert.False(result.success)
        Assert.False(result.unsupported)
        Assert.True(result.restored)
        Assert.Equal("existing note", field.storedValue)
        Assert.True(field.writeCalls > 1)
    }

    FailedUIAVerificationRestoresThePreviousNote() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
    }

    UIABecomingUnsupportedStillRestoresAnEarlierWrite() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"
        driver.uiaSupportedCalls := 1

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.True(result.unsupported)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
    }

    FailedControlVerificationRestoresThePreviousNote() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "control", driver)

        Assert.False(result.success)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
    }

    UnsupportedControlDoesNotAttemptRollback() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.controlSupported := false

        result := WetReadPasteEngine.Paste(1, "new wet read", "control", driver)

        Assert.False(result.success)
        Assert.True(result.unsupported)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(1, driver.controlCalls)
    }

    DirectRestoreFallsBackAfterPreferredException() {
        driver := FakeWetReadDriver("partial value", "original clipboard")
        driver.throwOnUiaValue := "existing note"
        result := WetReadPasteEngine.NewResult()

        restored := WetReadPasteEngine.RestoreDirect(
            1,
            "existing note",
            "uia",
            driver,
            result
        )

        Assert.True(restored)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(1, driver.controlCalls)
    }

    SendExceptionRestoresThePreviousNoteAndClipboard() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.throwOnFailedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.False(result.success)
        Assert.True(result.restored)
        Assert.True(result.error != "")
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal("original clipboard", driver.clipboardValue)
    }

    ClearFailureAfterMutationRestoresThePreviousNote() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.clearFailuresRemaining := 1

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.False(result.success)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(2, driver.clearCalls)
        Assert.Equal("original clipboard", driver.clipboardValue)
    }

    ClipboardRestoreFailureIsReported() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.throwOnClipboardRestore := true

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.True(result.success)
        Assert.False(result.clipboardRestored)
        Assert.True(InStr(result.error, "Clipboard restore failed") > 0)
    }

    UnreadableNoteDoesNotAttemptPaste() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.throwOnRead := true

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.Equal("read", result.reason)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.clearCalls)
        Assert.Equal(0, driver.uiaCalls)
    }

    UnreadableNativeFieldFailsClosed() {
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadWindowDriver(true),
            FakeWetReadFocusDriver(true)
        )
        Assert.Throws(
            () => driver.Read(UnsupportedWetReadElement()),
            "cannot be read safely"
        )
    }

    StickyRootMustBelongToPacsProcess() {
        pacsRoot := FakeStickyTargetRoot(42, [])
        stickyRoot := FakeStickyTargetRoot(42, [], 200)
        unrelatedRoot := FakeStickyTargetRoot(99, [], 300)

        Assert.True(NativeWetReadDriver.IsExpectedStickyRoot(pacsRoot, stickyRoot))
        Assert.False(NativeWetReadDriver.IsExpectedStickyRoot(pacsRoot, unrelatedRoot))
    }

    StickyOpenerRejectsSameProcessWrongWindowButton() {
        wrongWindowButton := FakeStickyTargetElement(
            UIA.Type.Button,
            42,
            false,
            999,
            "scn_sticky_notes"
        )
        pacsRoot := FakeStickyTargetRoot(42, [wrongWindowButton], 100)
        driver := FakeStickyNoteWindowDriver(pacsRoot)

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(0, driver.invokeCalls)
    }

    StickyOpenerRejectsAmbiguousSameWindowButtons() {
        first := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        second := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [first, second], 100)
        driver := FakeStickyNoteWindowDriver(pacsRoot)

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(0, driver.invokeCalls)
    }

    StickyOpenerRejectsTitleChangeBeforeInvoke() {
        button := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        driver := FakeStickyNoteWindowDriver(pacsRoot)
        driver.livePacsTitle := "Different PACS Window"

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(0, driver.invokeCalls)
    }

    StickyOpenerRejectsDuplicateAppearingBeforeInvoke() {
        button := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        driver := FakeStickyNoteWindowDriver(pacsRoot)
        driver.exactPacsWindowCount := 2

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(0, driver.invokeCalls)
    }

    StickyOpenerRejectsUnactivatedStickyWindow() {
        button := FakeStickyTargetElement(
            UIA.Type.Button,
            42,
            false,
            100,
            "scn_sticky_notes"
        )
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        staleSticky := FakeStickyTargetRoot(42, [], 200)
        driver := FakeStickyNoteWindowDriver(pacsRoot, staleSticky, 0)

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(1, driver.invokeCalls)
    }

    StickyOpenerPinsNewlyActiveExactWindow() {
        button := FakeStickyTargetElement(
            UIA.Type.Button,
            42,
            false,
            100,
            "scn_sticky_notes"
        )
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        stickyRoot := FakeStickyTargetRoot(42, [], 200)
        driver := FakeStickyNoteWindowDriver(pacsRoot, stickyRoot, 200)

        session := StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"})

        Assert.Equal(100, session.pacsHwnd)
        Assert.Equal(200, session.stickyHwnd)
        Assert.True(session.stickyRoot = stickyRoot)
        Assert.Equal(1, driver.invokeCalls)
    }

    StickyDriverUsesExactValidatedWindowHandle() {
        driver := NativeWetReadDriver.ForRoot(FakeStickyTargetRoot(42, [], 200))

        Assert.Equal("ahk_id 200", driver.targetTitle)
    }

    StickyNoteTargetRequiresExpectedTypeProcessAndCapability() {
        valid := FakeStickyTargetElement(UIA.Type.Document, 42, true)
        root := FakeStickyTargetRoot(42, [valid])
        wrongType := FakeStickyTargetElement(UIA.Type.Button, 42, true)
        wrongProcess := FakeStickyTargetElement(UIA.Type.Edit, 99, true)
        wrongWindow := FakeStickyTargetElement(UIA.Type.Edit, 42, true, 200)
        noCapability := FakeStickyTargetElement(UIA.Type.Edit, 42, false)

        same := (left, right) => left == right
        Assert.True(NativeWetReadDriver.IsExpectedNoteField(root, valid, same))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, wrongType, same))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, wrongProcess, same))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, wrongWindow, same))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, noCapability, same))
    }

    StickyNoteTargetMustBeTheUniqueWritableField() {
        selected := FakeStickyTargetElement(UIA.Type.Document, 42, true)
        other := FakeStickyTargetElement(UIA.Type.Edit, 42, true)
        root := FakeStickyTargetRoot(42, [selected, other])

        Assert.False(NativeWetReadDriver.IsExpectedNoteField(
            root,
            selected,
            (left, right) => left == right
        ))
    }

    NativeDirectWriteRefusesStaleStickyTarget() {
        field := FakeWritableWetReadElement()
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadWindowDriver(true),
            FakeWetReadFocusDriver(false)
        )

        Assert.False(driver.WriteUIA(field, "new wet read"))
        Assert.Equal(0, field.writeCalls)
    }

    NativeFocusRefusesStaleStickyTargetBeforeAnyUIAction() {
        focusDriver := FakeWetReadFocusDriver(false)
        driver := NativeWetReadDriver(
            "ahk_id 200",
            FakeWetReadWindowDriver(true),
            focusDriver
        )

        Assert.Throws(
            () => driver.Focus(FakeWetReadField()),
            "no longer the unique expected target"
        )
        Assert.Equal(0, focusDriver.requestCalls)
    }

    NativeControlWithoutHandleIsUnsupported() {
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadWindowDriver(true),
            FakeWetReadFocusDriver(true)
        )

        Assert.False(driver.WriteControl({NativeWindowHandle: 0}, "new wet read"))
    }

    NativeSendRefusesLostFocus() {
        windowDriver := FakeWetReadWindowDriver(false)
        driver := NativeWetReadDriver("Sticky Notes", windowDriver)

        Assert.Throws(
            () => driver.Clear(FakeWetReadField()),
            "no longer active"
        )
        Assert.Equal(0, windowDriver.sent.Length)
    }

    NativeSendRefusesWrongStickyControlFocus() {
        windowDriver := FakeWetReadWindowDriver(true)
        focusDriver := FakeWetReadFocusDriver(false)
        driver := NativeWetReadDriver("Sticky Notes", windowDriver, focusDriver)

        Assert.Throws(
            () => driver.Clear(FakeWetReadField()),
            "expected text field"
        )
        Assert.Equal(0, windowDriver.sent.Length)
    }

    NativeForwardVerificationRejectsCaseOnlyDifference() {
        driver := FakeNativeWetReadValueDriver("New Wet Read")

        Assert.False(driver.WaitForValue(1, "new wet read", 150))
        Assert.True(driver.WaitForValue(1, "New Wet Read", 150))
    }

    NativeRollbackVerificationRejectsCaseOnlyDifference() {
        driver := FakeNativeWetReadValueDriver("previous note")

        Assert.False(driver.WaitForValue(1, "Previous Note", 150))
        Assert.True(driver.WaitForValue(1, "previous note", 150))
    }

    RoutingFailureReportsTheActualCause() {
        message := AttendingFailureMessage(
            "EXAMINATION: CT CHEST",
            Error("could not safely control PowerScribe")
        )

        Assert.True(InStr(message, "could not safely control PowerScribe") > 0)
        Assert.False(InStr(message, "Could not read the report") > 0)
    }

    AttendingFailureIsReportedAcrossEveryStickySetupExit() {
        routingCases := [
            {reportText: "", routingError: 0},
            {
                reportText: "EXAMINATION: CT CHEST",
                routingError: Error("simulated routing failure")
            }
        ]

        for routingCase in routingCases {
            for stage in ["opener", "root", "field", "semantic-target"] {
                notifications := []
                result := RunWetReadPasteWithAttendingOutcome(
                    ObjBindMethod(FakeEarlyWetReadExit, "Return", stage),
                    false,
                    routingCase.reportText,
                    routingCase.routingError,
                    RecordWetReadNotification.Bind(notifications)
                )

                Assert.Equal(stage, result)
                Assert.Equal(1, notifications.Length)
                Assert.Equal("Attending Not Assigned", notifications[1].title)
                Assert.True(InStr(notifications[1].text, "Set it manually") > 0)
            }
        }
    }
}

class FakeEarlyWetReadExit {
    static Return(stage) {
        return stage
    }
}

RecordWetReadNotification(notifications, text, title, options) {
    notifications.Push({text: text, title: title, options: options})
}

class FakeWetReadDriver {
    __New(fieldValue, clipboardValue) {
        this.fieldValue := fieldValue
        this.clipboardValue := clipboardValue
        this.clipboardReady := true
        this.failedText := ""
        this.throwOnFailedText := ""
        this.uiaSupported := true
        this.uiaSupportedCalls := 0
        this.uiaCalls := 0
        this.controlSupported := true
        this.controlCalls := 0
        this.throwOnClipboardRestore := false
        this.throwOnRead := false
        this.throwOnUiaValue := ""
        this.clearCalls := 0
        this.clearFailuresRemaining := 0
    }

    Read(field) {
        if this.throwOnRead
            throw Error("simulated unreadable field")
        return this.fieldValue
    }

    Focus(field) {
    }

    Clear(field) {
        this.clearCalls++
        this.fieldValue := ""
        if this.clearFailuresRemaining > 0 {
            this.clearFailuresRemaining--
            throw Error("simulated clear failure after mutation")
        }
    }

    CaptureClipboard() {
        return this.clipboardValue
    }

    SetClipboard(value) {
        this.clipboardValue := value
    }

    WaitForClipboard(timeoutSeconds) {
        return this.clipboardReady
    }

    RestoreClipboard(value) {
        if this.throwOnClipboardRestore
            throw Error("simulated clipboard restore failure")
        this.clipboardValue := value
    }

    PasteClipboard(field) {
        if (this.clipboardValue = this.throwOnFailedText)
            throw Error("simulated paste failure")
        this.fieldValue := this.clipboardValue = this.failedText ? "partial value" : this.clipboardValue
    }

    WriteUIA(field, value) {
        this.uiaCalls++
        if (value = this.throwOnUiaValue)
            throw Error("simulated UIA restore failure")
        if (!this.uiaSupported || (this.uiaSupportedCalls > 0 && this.uiaCalls > this.uiaSupportedCalls))
            return false
        this.fieldValue := value = this.failedText ? "partial value" : value
        return true
    }

    WriteControl(field, value) {
        this.controlCalls++
        if !this.controlSupported
            return false
        this.fieldValue := value = this.failedText ? "partial value" : value
        return true
    }

    WaitForValue(field, expected, timeoutMs) {
        return this.fieldValue = expected
    }
}

class FakeNativeWetReadValueDriver extends NativeWetReadDriver {
    __New(currentValue) {
        this.currentValue := currentValue
    }

    Read(*) {
        return this.currentValue
    }
}

class UnsupportedWetReadElement {
    GetPropertyValue(propertyId) {
        return ""
    }
}

class PostMutationFailingWetReadElement {
    __New(value, failingValue) {
        this.storedValue := value
        this.failingValue := failingValue
        this.writeCalls := 0
    }

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return this.storedValue
            case UIA.Property.IsValuePatternAvailable: return true
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return false
        }
        return ""
    }

    Value {
        get => this.storedValue
        set {
            this.writeCalls++
            this.storedValue := value
            if (value = this.failingValue)
                throw Error("provider failed after mutation")
        }
    }
}

class FakeWetReadField {
    SetFocus() {
    }

    Click(*) {
    }
}

class FakeWritableWetReadElement {
    __New() {
        this.writeCalls := 0
        this.storedValue := ""
    }

    GetPropertyValue(property) {
        return property = UIA.Property.IsValuePatternAvailable
    }

    Value {
        get => this.storedValue
        set {
            this.writeCalls++
            this.storedValue := value
        }
    }
}

class FakeStickyTargetElement {
    __New(type, processId, readable := false, windowId := 100, name := "") {
        this.Type := type
        this.ProcessId := processId
        this.WinId := windowId
        this.Name := name
        this.IsEnabled := true
        this.IsValuePatternAvailable := readable
        this.IsLegacyIAccessiblePatternAvailable := false
        this.NativeWindowHandle := 0
    }
}

class FakeStickyTargetRoot {
    __New(processId, children, windowId := 100) {
        this.ProcessId := processId
        this.WinId := windowId
        this.children := children
    }

    FindElements(condition) {
        matches := []
        for child in this.children {
            if (HasProp(condition, "Name") && child.Name = condition.Name)
                matches.Push(child)
            else if (HasProp(condition, "Type")
                && ((condition.Type = "Document" && child.Type = UIA.Type.Document)
                || (condition.Type = "Edit" && child.Type = UIA.Type.Edit)))
                matches.Push(child)
        }
        return matches
    }
}

class FakeStickyNoteWindowDriver {
    __New(pacsRoot, stickyRoot := 0, activatedStickyHwnd := 0) {
        this.pacsRoot := pacsRoot
        this.stickyRoot := stickyRoot
        this.activatedStickyHwnd := activatedStickyHwnd
        this.invokeCalls := 0
        this.livePacsTitle := "Vue PACS"
        this.exactPacsWindowCount := 1
    }

    CaptureActivePacs(*) {
        return this.pacsRoot.WinId
    }

    GetRoot(hwnd) {
        if (hwnd = this.pacsRoot.WinId)
            return this.pacsRoot
        if (this.stickyRoot && hwnd = this.stickyRoot.WinId)
            return this.stickyRoot
        return 0
    }

    IsActive(hwnd) {
        return hwnd = this.pacsRoot.WinId
    }

    IsExpectedPacsSession(target, hwnd, processId) {
        return this.exactPacsWindowCount = 1
            && this.livePacsTitle == target.title
            && hwnd = this.pacsRoot.WinId
            && processId = this.pacsRoot.ProcessId
    }

    InvokeStickyButton(*) {
        this.invokeCalls++
        return true
    }

    WaitForActiveSticky(*) {
        return this.activatedStickyHwnd
    }

    GetOwner(*) {
        return 0
    }
}

class FakeWetReadWindowDriver {
    __New(active) {
        this.active := active
        this.sent := []
    }

    IsActive(title) {
        return this.active
    }

    SendKeys(keys) {
        this.sent.Push(keys)
    }
}

class FakeWetReadFocusDriver {
    __New(matches) {
        this.matches := matches
        this.requestCalls := 0
    }

    RequestFocus(*) {
        this.requestCalls++
    }

    IsExpectedTarget(*) {
        return this.matches
    }

    IsExpectedFocus(*) {
        return this.matches
    }
}
