#Requires AutoHotkey v2.0
#Include ../WetRead.ahk
#Include TestRunner.ahk

class WetReadTest {
    static Tests := [
        "ClipboardFailureDoesNotTouchTheNote",
        "FailedSendRestoresThePreviousNoteAndClipboard",
        "SuccessfulSendRestoresTheClipboard",
        "UnsupportedUIADoesNotClearTheNote",
        "FailedUIAVerificationRestoresThePreviousNote",
        "UIABecomingUnsupportedStillRestoresAnEarlierWrite",
        "FailedControlVerificationRestoresThePreviousNote",
        "SendExceptionRestoresThePreviousNoteAndClipboard",
        "ClearFailureAfterMutationRestoresThePreviousNote",
        "ClipboardRestoreFailureIsReported",
        "UnreadableNoteDoesNotAttemptPaste",
        "UnreadableNativeFieldFailsClosed",
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
        this.throwOnClipboardRestore := false
        this.throwOnRead := false
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
        if (!this.uiaSupported || (this.uiaSupportedCalls > 0 && this.uiaCalls > this.uiaSupportedCalls))
            return false
        this.fieldValue := value = this.failedText ? "partial value" : value
        return true
    }

    WriteControl(field, value) {
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

class FakeWetReadField {
    SetFocus() {
    }

    Click(*) {
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
