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
        "StickyNoteTargetRequiresExpectedTypeProcessAndCapability",
        "NativeControlWithoutHandleIsUnsupported",
        "NativeSendRefusesLostFocus",
        "RoutingFailureReportsTheActualCause"
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

        result := WetReadPasteEngine.Paste(
            field,
            "new wet read",
            "uia",
            NativeWetReadDriver()
        )

        Assert.False(result.success)
        Assert.False(result.unsupported)
        Assert.True(result.restored)
        Assert.Equal("existing note", field.storedValue)
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
        Assert.Throws(
            () => NativeWetReadDriver().Read(UnsupportedWetReadElement()),
            "cannot be read safely"
        )
    }

    StickyNoteTargetRequiresExpectedTypeProcessAndCapability() {
        root := FakeStickyTargetElement(UIA.Type.Window, 42)
        valid := FakeStickyTargetElement(UIA.Type.Document, 42, true)
        wrongType := FakeStickyTargetElement(UIA.Type.Button, 42, true)
        wrongProcess := FakeStickyTargetElement(UIA.Type.Edit, 99, true)
        noCapability := FakeStickyTargetElement(UIA.Type.Edit, 42, false)

        Assert.True(NativeWetReadDriver.IsExpectedNoteField(root, valid))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, wrongType))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, wrongProcess))
        Assert.False(NativeWetReadDriver.IsExpectedNoteField(root, noCapability))
    }

    NativeControlWithoutHandleIsUnsupported() {
        driver := NativeWetReadDriver()

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

    RoutingFailureReportsTheActualCause() {
        message := AttendingFailureMessage(
            "EXAMINATION: CT CHEST",
            Error("could not safely control PowerScribe")
        )

        Assert.True(InStr(message, "could not safely control PowerScribe") > 0)
        Assert.False(InStr(message, "Could not read the report") > 0)
    }
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

class UnsupportedWetReadElement {
    GetPropertyValue(propertyId) {
        return ""
    }
}

class PostMutationFailingWetReadElement {
    __New(value, failingValue) {
        this.storedValue := value
        this.failingValue := failingValue
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

class FakeStickyTargetElement {
    __New(type, processId, readable := false) {
        this.Type := type
        this.ProcessId := processId
        this.IsEnabled := true
        this.IsValuePatternAvailable := readable
        this.IsLegacyIAccessiblePatternAvailable := false
        this.NativeWindowHandle := 0
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
