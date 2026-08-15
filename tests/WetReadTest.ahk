#Requires AutoHotkey v2.0
#Include ../WetRead.ahk
#Include TestRunner.ahk

class WetReadTest {
    static Tests := [
        "ClipboardPasteModeIsRejectedWithoutMutation",
        "UnsupportedUIADoesNotClearTheNote",
        "PostMutationUIAErrorCanSucceedOnlyWithExactReadback",
        "FailedUIAVerificationDoesNotOverwriteChangedValue",
        "UIAFailureDoesNotRetryWhenCapabilityChanges",
        "FailedControlVerificationDoesNotOverwriteChangedValue",
        "UnsupportedControlDoesNotAttemptRollback",
        "PreconditionChangeIsNotReportedAsRestored",
        "ConcurrentEditAfterWritePreventsRetryAndRollback",
        "UnreadableNoteDoesNotAttemptPaste",
        "UnreadableNativeFieldFailsClosed",
        "StickyRootMustBelongToPacsProcess",
        "StickyOpenerRejectsSameProcessWrongWindowButton",
        "StickyOpenerRejectsAmbiguousSameWindowButtons",
        "StickyOpenerRejectsUnreadableCandidateAlongsideValidButton",
        "StickyOpenerRejectsTitleChangeBeforeInvoke",
        "StickyOpenerRejectsDuplicateAppearingBeforeInvoke",
        "StickyOpenerRejectsUnactivatedStickyWindow",
        "StickyOpenerRejectsPreexistingReactivatedStickyWindow",
        "NativeProcessDiscoveryIncludesHiddenUntitledWindow",
        "StickyOpenerRejectsOwnerlessStickyWindow",
        "StickyOpenerPinsNewlyActiveExactWindow",
        "StickyOpenerRejectsTwoNewWindowsAfterInvoke",
        "StickySessionRejectsANewSiblingAfterCapture",
        "StickyDriverUsesExactValidatedWindowHandle",
        "StickyNoteTargetRequiresExpectedTypeProcessAndCapability",
        "StickyNoteTargetMustBeTheUniqueWritableField",
        "StickyNoteTargetRejectsUnreadableWritableSibling",
        "NativeDirectWriteRefusesStaleStickyTarget",
        "NativeControlWithoutHandleIsUnsupported",
        "NativeControlWriteHasNoFocusSideEffect",
        "NativeForwardVerificationRejectsCaseOnlyDifference",
        "NativeRollbackVerificationRejectsCaseOnlyDifference",
        "RoutingFailureReportsTheActualCause",
        "AttendingFailureIsReportedAcrossEveryStickySetupExit",
        "StickyOpenerFailureAlsoReportsAttendingOutcome",
        "ThrowingStickyOpenerStillReportsAttendingOutcome",
        "ThrowingReportCaptureStillPastesAndReportsAttendingOutcome",
        "StickyTargetIsPinnedBeforePowerScribeRouting"
    ]

    ClipboardPasteModeIsRejectedWithoutMutation() {
        driver := FakeWetReadDriver("existing note", "original clipboard")

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.False(result.success)
        Assert.Equal("invalid-mode", result.reason)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal("original clipboard", driver.clipboardValue)
        Assert.Equal(0, driver.readCalls)
        Assert.Equal(0, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    UnsupportedUIADoesNotClearTheNote() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.uiaSupported := false

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.True(result.unsupported)
        Assert.True(result.restored)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.controlCalls)
    }

    PostMutationUIAErrorCanSucceedOnlyWithExactReadback() {
        field := PostMutationFailingWetReadElement("existing note", "new wet read")
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadFocusDriver(true)
        )

        result := WetReadPasteEngine.Paste(
            field,
            "new wet read",
            "uia",
            driver
        )

        Assert.True(result.success)
        Assert.False(result.unsupported)
        Assert.False(result.restored)
        Assert.Equal("new wet read", field.storedValue)
        Assert.Equal(1, field.writeCalls)
    }

    FailedUIAVerificationDoesNotOverwriteChangedValue() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.restored)
        Assert.Equal("value-changed", result.reason)
        Assert.Equal("partial value", driver.fieldValue)
        Assert.Equal(1, driver.uiaCalls)
    }

    UIAFailureDoesNotRetryWhenCapabilityChanges() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"
        driver.uiaSupportedCalls := 1

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.unsupported)
        Assert.False(result.restored)
        Assert.Equal("partial value", driver.fieldValue)
        Assert.Equal(1, driver.uiaCalls)
    }

    FailedControlVerificationDoesNotOverwriteChangedValue() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "control", driver)

        Assert.False(result.success)
        Assert.False(result.restored)
        Assert.Equal("value-changed", result.reason)
        Assert.Equal("partial value", driver.fieldValue)
        Assert.Equal(1, driver.controlCalls)
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

    PreconditionChangeIsNotReportedAsRestored() {
        driver := PreconditionChangingWetReadDriver(
            "existing note",
            "user's newer note"
        )

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.restored)
        Assert.Equal("precondition-changed", result.reason)
        Assert.Equal(0, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    ConcurrentEditAfterWritePreventsRetryAndRollback() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.concurrentValueAfterWait := "user's newer note"

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.restored)
        Assert.Equal("value-changed", result.reason)
        Assert.Equal("user's newer note", driver.fieldValue)
        Assert.Equal(1, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    UnreadableNoteDoesNotAttemptPaste() {
        driver := FakeWetReadDriver("existing note", "original clipboard")
        driver.throwOnRead := true

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.Equal("read", result.reason)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    UnreadableNativeFieldFailsClosed() {
        driver := NativeWetReadDriver(
            "Sticky Notes",
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

    StickyOpenerRejectsUnreadableCandidateAlongsideValidButton() {
        valid := FakeStickyTargetElement(
            UIA.Type.Button,
            42,
            false,
            100,
            "scn_sticky_notes"
        )
        unreadable := UnreadableStickyTargetElement(42, 100)
        pacsRoot := FakeStickyTargetRoot(42, [valid, unreadable], 100)
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

    StickyOpenerRejectsPreexistingReactivatedStickyWindow() {
        button := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        stickyRoot := FakeStickyTargetRoot(42, [], 200)
        driver := FakeStickyNoteWindowDriver(pacsRoot, stickyRoot, 200)
        driver.preexistingProcessWindows := [100, 200]

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(1, driver.invokeCalls)
    }

    NativeProcessDiscoveryIncludesHiddenUntitledWindow() {
        hiddenWindow := Gui()
        hiddenWindow.Show("Hide")
        try {
            windows := NativeStickyNoteWindowDriver().FindProcessWindows(
                DllCall("GetCurrentProcessId")
            )
            found := false
            for hwnd in windows {
                if (hwnd = hiddenWindow.Hwnd) {
                    found := true
                    break
                }
            }
            Assert.True(found)
        } finally hiddenWindow.Destroy()
    }

    StickyOpenerRejectsOwnerlessStickyWindow() {
        button := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        stickyRoot := FakeStickyTargetRoot(42, [], 200)
        driver := FakeStickyNoteWindowDriver(pacsRoot, stickyRoot, 200)
        driver.stickyOwner := 0

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
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

    StickyOpenerRejectsTwoNewWindowsAfterInvoke() {
        button := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        stickyRoot := FakeStickyTargetRoot(42, [], 200)
        driver := FakeStickyNoteWindowDriver(pacsRoot, stickyRoot, 200)
        driver.postClickStickyWindows := [200, 201]

        Assert.Equal(0, StickyNoteOpener(driver).Open({title: "Vue PACS", exe: "mp.exe"}))
        Assert.Equal(1, driver.invokeCalls)
    }

    StickySessionRejectsANewSiblingAfterCapture() {
        button := FakeStickyTargetElement(UIA.Type.Button, 42, false, 100, "scn_sticky_notes")
        pacsRoot := FakeStickyTargetRoot(42, [button], 100)
        stickyRoot := FakeStickyTargetRoot(42, [], 200)
        driver := FakeStickyNoteWindowDriver(pacsRoot, stickyRoot, 200)
        opener := StickyNoteOpener(driver)
        session := opener.Open({title: "Vue PACS", exe: "mp.exe"})

        driver.postClickStickyWindows := [200, 201]

        Assert.False(driver.IsExpectedStickySession(session))
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

    StickyNoteTargetRejectsUnreadableWritableSibling() {
        selected := FakeStickyTargetElement(UIA.Type.Document, 42, true)
        unreadable := UnreadableNoteFieldElement()
        root := FakeStickyTargetRoot(42, [selected, unreadable])

        Assert.False(NativeWetReadDriver.IsExpectedNoteField(
            root,
            selected,
            (left, right) => left = right
        ))
    }

    NativeDirectWriteRefusesStaleStickyTarget() {
        field := FakeWritableWetReadElement()
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadFocusDriver(false)
        )

        Assert.False(driver.WriteUIA(field, "new wet read"))
        Assert.Equal(0, field.writeCalls)
    }

    NativeControlWithoutHandleIsUnsupported() {
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadFocusDriver(true)
        )

        Assert.False(driver.WriteControl({NativeWindowHandle: 0}, "new wet read"))
    }

    NativeControlWriteHasNoFocusSideEffect() {
        controlDriver := FakeWetReadControlDriver()
        driver := NativeWetReadDriver(
            "ahk_id 200",
            FakeWetReadFocusDriver(true),
            controlDriver
        )

        Assert.True(driver.WriteControl({NativeWindowHandle: 555}, "new wet read"))
        Assert.Equal(1, controlDriver.writes.Length)
        Assert.Equal(555, controlDriver.writes[1].hwnd)
        Assert.Equal("new wet read", controlDriver.writes[1].value)
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

    StickyOpenerFailureAlsoReportsAttendingOutcome() {
        notifications := []
        captureCalls := 0

        result := RunPinnedWetReadWorkflow(
            "wet read",
            "uia",
            (*) => 0,
            (*) => (captureCalls++, {text: "", session: 0}),
            (*) => true,
            (*) => true,
            RecordWetReadNotification.Bind(notifications)
        )

        Assert.False(result)
        Assert.Equal(0, captureCalls)
        Assert.Equal(2, notifications.Length)
        Assert.Equal("Sticky Note Target Not Verified", notifications[1].title)
        Assert.Equal("Attending Not Assigned", notifications[2].title)
        Assert.True(InStr(notifications[2].text, "Set it manually") > 0)
    }

    ThrowingStickyOpenerStillReportsAttendingOutcome() {
        notifications := []
        captureCalls := 0
        escaped := false

        try result := RunPinnedWetReadWorkflow(
            "wet read",
            "uia",
            ObjBindMethod(FakeEarlyWetReadExit, "Throw", "simulated opener failure"),
            (*) => (captureCalls++, {text: "", session: 0}),
            (*) => true,
            (*) => true,
            RecordWetReadNotification.Bind(notifications)
        )
        catch
            escaped := true

        Assert.False(escaped)
        Assert.False(result)
        Assert.Equal(0, captureCalls)
        Assert.Equal(2, notifications.Length)
        Assert.Equal("Sticky Note Target Not Verified", notifications[1].title)
        Assert.True(InStr(notifications[1].text, "simulated opener failure") > 0)
        Assert.Equal("Attending Not Assigned", notifications[2].title)
    }

    ThrowingReportCaptureStillPastesAndReportsAttendingOutcome() {
        notifications := []
        routeCalls := 0
        pasteCalls := 0
        stickySession := {stickyHwnd: 200}
        escaped := false

        try result := RunPinnedWetReadWorkflow(
            "wet read",
            "uia",
            (*) => stickySession,
            ObjBindMethod(FakeEarlyWetReadExit, "Throw", "simulated report failure"),
            (*) => routeCalls++,
            (*) => (pasteCalls++, true),
            RecordWetReadNotification.Bind(notifications)
        )
        catch
            escaped := true

        Assert.False(escaped)
        Assert.True(result)
        Assert.Equal(0, routeCalls)
        Assert.Equal(1, pasteCalls)
        Assert.Equal(1, notifications.Length)
        Assert.Equal("Attending Not Assigned", notifications[1].title)
        Assert.True(InStr(notifications[1].text, "simulated report failure") > 0)
    }

    StickyTargetIsPinnedBeforePowerScribeRouting() {
        events := []
        stickySession := {stickyHwnd: 200}
        openSticky := (*) => (events.Push("open-sticky"), stickySession)
        captureReport := (*) => (
            events.Push("capture-report"),
            {text: "EXAMINATION: CT CHEST", session: {hwnd: 300}}
        )
        routeAttending := (*) => events.Push("route-attending")
        pasteAction := (text, mode, session) => (
            events.Push("paste-pinned-sticky"),
            session = stickySession
        )

        result := RunPinnedWetReadWorkflow(
            "wet read",
            "uia",
            openSticky,
            captureReport,
            routeAttending,
            pasteAction,
            (*) => 0
        )

        Assert.True(result)
        Assert.Equal("open-sticky", events[1])
        Assert.Equal("capture-report", events[2])
        Assert.Equal("route-attending", events[3])
        Assert.Equal("paste-pinned-sticky", events[4])
    }
}

class FakeEarlyWetReadExit {
    static Return(stage) {
        return stage
    }

    static Throw(message) {
        throw Error(message)
    }
}

RecordWetReadNotification(notifications, text, title, options) {
    notifications.Push({text: text, title: title, options: options})
}

class FakeWetReadDriver {
    __New(fieldValue, clipboardValue) {
        this.fieldValue := fieldValue
        this.clipboardValue := clipboardValue
        this.readCalls := 0
        this.failedText := ""
        this.uiaSupported := true
        this.uiaSupportedCalls := 0
        this.uiaCalls := 0
        this.controlSupported := true
        this.controlCalls := 0
        this.throwOnRead := false
        this.throwOnUiaValue := ""
        this.concurrentValueAfterWait := ""
    }

    Read(field) {
        this.readCalls++
        if this.throwOnRead
            throw Error("simulated unreadable field")
        return this.fieldValue
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
        if (this.concurrentValueAfterWait != "") {
            this.fieldValue := this.concurrentValueAfterWait
            this.concurrentValueAfterWait := ""
            return false
        }
        return this.fieldValue = expected
    }
}

class PreconditionChangingWetReadDriver extends FakeWetReadDriver {
    __New(firstValue, secondValue) {
        super.__New(firstValue, "")
        this.firstValue := firstValue
        this.secondValue := secondValue
    }

    Read(*) {
        this.readCalls++
        return this.readCalls = 1 ? this.firstValue : this.secondValue
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

class UnreadableStickyTargetElement {
    __New(processId, windowId) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Name := "scn_sticky_notes"
        this.IsEnabled := true
    }

    Type {
        get {
            throw Error("simulated unreadable UIA property")
        }
    }
}

class UnreadableNoteFieldElement {
    Type := UIA.Type.Document

    ProcessId {
        get {
            throw Error("simulated unreadable note-field property")
        }
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
        this.preexistingProcessWindows := [pacsRoot.WinId]
        this.postClickStickyWindows := activatedStickyHwnd > 0
            ? [activatedStickyHwnd]
            : []
        this.stickyWindowQueries := 0
        this.stickyOwner := pacsRoot.WinId
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
        return this.stickyOwner
    }

    FindProcessWindows(*) {
        this.stickyWindowQueries++
        return (this.stickyWindowQueries = 1
            ? this.preexistingProcessWindows
            : this.postClickStickyWindows).Clone()
    }

    FindExactStickyWindows(*) {
        this.stickyWindowQueries++
        return this.postClickStickyWindows.Clone()
    }


    IsExpectedStickySession(session) {
        windows := this.FindExactStickyWindows(session.processId)
        delta := StickyNoteOpener.NewWindowDelta(
            session.preexistingProcessWindows,
            windows
        )
        return IsObject(delta)
            && delta.Length = 1
            && delta[1] = session.stickyHwnd
            && this.stickyOwner = session.pacsHwnd
    }

    ActivateSticky(session) {
        return session.stickyHwnd = this.activatedStickyHwnd
            && this.stickyOwner = session.pacsHwnd
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

class FakeWetReadControlDriver {
    __New() {
        this.writes := []
    }

    SetText(hwnd, value) {
        this.writes.Push({hwnd: hwnd, value: value})
    }
}

class FakeWetReadFocusDriver {
    __New(matches) {
        this.matches := matches
    }

    IsExpectedTarget(*) {
        return this.matches
    }

}
