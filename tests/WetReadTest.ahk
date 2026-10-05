; = CONTENTS
;   + Preamble
;   + WetReadTest class (wet-read paste, UIA write/verify, sticky note targeting, attending routing)
;   + Test doubles (wet-read drivers/elements, sticky target elements, notification recorder)

#Requires AutoHotkey v2.0
#Include ../WetRead.ahk
#Include TestRunner.ahk
#Include LogCapture.ahk

class WetReadTest {
    static tests := [
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
        "NativeStickyButtonReportsWhetherClickActioned",
        "AttendingFailureMessagesReadAsOneSentence",
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
        "NativeStickySessionAcceptsTheOneNewOwnedStickyWindow",
        "NativeStickySessionRejectsANewSiblingStickyWindow",
        "NativeStickySessionRejectsAWrongOwner",
        "NativeStickySessionRejectsAReusedPreexistingWindow",
        "NativeStickySessionRejectsIncompleteSessionsAndFailedEnumeration",
        "NativeActivateStickyVerifiesIdentityAroundActivation",
        "PasteFailureDialogNamesEachOutcome",
        "UnconfirmedPasteIsLoggedWithItsReason",
        "LineEndingConversionProducesCrlfOnly",
        "StickyDriverUsesExactValidatedWindowHandle",
        "StickyNoteTargetRequiresExpectedTypeProcessAndCapability",
        "StickyNoteTargetMustBeTheUniqueWritableField",
        "StickyNoteTargetRejectsUnreadableWritableSibling",
        "NativeDirectWriteRefusesStaleStickyTarget",
        "NativeControlWithoutHandleIsUnsupported",
        "NativeControlWriteHasNoFocusSideEffect",
        "NativeForwardVerificationRejectsCaseOnlyDifference",
        "RoutingFailureReportsTheActualCause",
        "StickyOpenerFailureAlsoReportsAttendingOutcome",
        "ThrowingStickyOpenerStillReportsAttendingOutcome",
        "UnexpectedWorkflowFaultsAreLoggedWithTheirStack",
        "ThrowingReportCaptureStillPastesAndReportsAttendingOutcome",
        "StickyTargetIsPinnedBeforePowerScribeRouting"
    ]

    ClipboardPasteModeIsRejectedWithoutMutation() {
        driver := FakeWetReadDriver("existing note")

        result := WetReadPasteEngine.Paste(1, "new wet read", "send", driver)

        Assert.False(result.success)
        Assert.Equal("invalid-mode", result.reason)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.readCalls)
        Assert.Equal(0, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    UnsupportedUIADoesNotClearTheNote() {
        driver := FakeWetReadDriver("existing note")
        driver.uiaSupported := false

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.True(result.unsupported)
        Assert.True(result.unchanged)
        Assert.Equal("existing note", driver.fieldValue)
        Assert.Equal(0, driver.controlCalls)
    }

    PostMutationUIAErrorCanSucceedOnlyWithExactReadback() {
        field := PostMutationFailingWetReadElement("existing note", "new wet read")
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadTargetDriver(true)
        )

        result := WetReadPasteEngine.Paste(
            field,
            "new wet read",
            "uia",
            driver
        )

        Assert.True(result.success)
        Assert.False(result.unsupported)
        Assert.False(result.unchanged)
        Assert.Equal("new wet read", field.storedValue)
        Assert.Equal(1, field.writeCalls)
    }

    FailedUIAVerificationDoesNotOverwriteChangedValue() {
        driver := FakeWetReadDriver("existing note")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.unchanged)
        Assert.Equal("value-changed", result.reason)
        Assert.Equal("partial value", driver.fieldValue)
        Assert.Equal(1, driver.uiaCalls)
    }

    UIAFailureDoesNotRetryWhenCapabilityChanges() {
        driver := FakeWetReadDriver("existing note")
        driver.failedText := "new wet read"
        driver.uiaSupportedCalls := 1

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.unsupported)
        Assert.False(result.unchanged)
        Assert.Equal("partial value", driver.fieldValue)
        Assert.Equal(1, driver.uiaCalls)
    }

    FailedControlVerificationDoesNotOverwriteChangedValue() {
        driver := FakeWetReadDriver("existing note")
        driver.failedText := "new wet read"

        result := WetReadPasteEngine.Paste(1, "new wet read", "control", driver)

        Assert.False(result.success)
        Assert.False(result.unchanged)
        Assert.Equal("value-changed", result.reason)
        Assert.Equal("partial value", driver.fieldValue)
        Assert.Equal(1, driver.controlCalls)
    }

    UnsupportedControlDoesNotAttemptRollback() {
        driver := FakeWetReadDriver("existing note")
        driver.controlSupported := false

        result := WetReadPasteEngine.Paste(1, "new wet read", "control", driver)

        Assert.False(result.success)
        Assert.True(result.unsupported)
        Assert.True(result.unchanged)
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
        Assert.False(result.unchanged)
        Assert.Equal("precondition-changed", result.reason)
        Assert.Equal(0, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    ConcurrentEditAfterWritePreventsRetryAndRollback() {
        driver := FakeWetReadDriver("existing note")
        driver.concurrentValueAfterWait := "user's newer note"

        result := WetReadPasteEngine.Paste(1, "new wet read", "uia", driver)

        Assert.False(result.success)
        Assert.False(result.unchanged)
        Assert.Equal("value-changed", result.reason)
        Assert.Equal("user's newer note", driver.fieldValue)
        Assert.Equal(1, driver.uiaCalls)
        Assert.Equal(0, driver.controlCalls)
    }

    UnreadableNoteDoesNotAttemptPaste() {
        driver := FakeWetReadDriver("existing note")
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
            FakeWetReadTargetDriver(true)
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

    NativeStickySessionAcceptsTheOneNewOwnedStickyWindow() {
        driver := PrimitiveStickyNoteWindowDriver.Standard()

        Assert.True(driver.IsExpectedStickySession(PrimitiveStickyNoteWindowDriver.Session()))
    }

    NativeStickySessionRejectsANewSiblingStickyWindow() {
        driver := PrimitiveStickyNoteWindowDriver.Standard()
        driver.AddWindow(201, "Sticky Notes", 100)

        Assert.False(driver.IsExpectedStickySession(PrimitiveStickyNoteWindowDriver.Session()))
    }

    NativeStickySessionRejectsAWrongOwner() {
        driver := PrimitiveStickyNoteWindowDriver.Standard()
        driver.owners[200] := 999

        Assert.False(driver.IsExpectedStickySession(PrimitiveStickyNoteWindowDriver.Session()))
    }

    NativeStickySessionRejectsAReusedPreexistingWindow() {
        driver := PrimitiveStickyNoteWindowDriver.Standard()
        session := PrimitiveStickyNoteWindowDriver.Session()
        session.preexistingProcessWindows := [100, 150, 200]

        Assert.False(driver.IsExpectedStickySession(session))
    }

    NativeStickySessionRejectsIncompleteSessionsAndFailedEnumeration() {
        driver := PrimitiveStickyNoteWindowDriver.Standard()
        Assert.False(driver.IsExpectedStickySession(0))
        for propertyName in ["pacsHwnd", "stickyHwnd", "processId", "preexistingProcessWindows"] {
            session := PrimitiveStickyNoteWindowDriver.Session()
            session.DeleteProp(propertyName)
            Assert.False(driver.IsExpectedStickySession(session), "Session without " propertyName " was accepted")
        }

        driver.processWindows := 0
        Assert.False(driver.IsExpectedStickySession(PrimitiveStickyNoteWindowDriver.Session()))

        ; A window that disappears while titles are read makes the set unknowable.
        vanishing := PrimitiveStickyNoteWindowDriver.Standard()
        vanishing.processWindows.Push(300)
        Assert.False(vanishing.IsExpectedStickySession(PrimitiveStickyNoteWindowDriver.Session()))
    }

    NativeActivateStickyVerifiesIdentityAroundActivation() {
        session := PrimitiveStickyNoteWindowDriver.Session()

        wrongOwner := PrimitiveStickyNoteWindowDriver.Standard()
        wrongOwner.owners[200] := 999
        Assert.False(wrongOwner.ActivateSticky(session))
        Assert.Equal(0, wrongOwner.activated.Length, "An unverified session must not be activated")

        failedActivation := PrimitiveStickyNoteWindowDriver.Standard()
        failedActivation.activationSucceeds := false
        Assert.False(failedActivation.ActivateSticky(session))

        siblingOnActivation := PrimitiveStickyNoteWindowDriver.Standard()
        siblingOnActivation.siblingOnActivation := 201
        Assert.False(siblingOnActivation.ActivateSticky(session))
        Assert.Equal(1, siblingOnActivation.activated.Length)

        verified := PrimitiveStickyNoteWindowDriver.Standard()
        Assert.True(verified.ActivateSticky(session))
        Assert.Equal(200, verified.activated[1])
    }

    PasteFailureDialogNamesEachOutcome() {
        Assert.Equal(0, WetReadPasteFailureDialog({success: true, unsupported: false, unchanged: false, reason: ""}, "uia"))

        unsupported := WetReadPasteFailureDialog({success: false, unsupported: true, unchanged: true, reason: "unsupported"}, "uia")
        Assert.Equal("Paste Method Unavailable", unsupported.title)
        Assert.True(InStr(unsupported.text, "UIA Value method"), unsupported.text)
        unsupportedControl := WetReadPasteFailureDialog({success: false, unsupported: true, unchanged: true, reason: "unsupported"}, "control")
        Assert.True(InStr(unsupportedControl.text, "ControlSetText method"), unsupportedControl.text)

        expectedTitles := [
            ["value-changed", false, "Sticky Note Changed"],
            ["precondition-changed", false, "Sticky Note Changed"],
            ["read", false, "Sticky Note Not Verified"],
            ["precondition-read", false, "Sticky Note Not Verified"],
            ["verification-error", false, "Sticky Note Not Verified"],
            ["verification", true, "Paste Failed"]
        ]
        for expected in expectedTitles {
            dialog := WetReadPasteFailureDialog(
                {success: false, unsupported: false, unchanged: expected[2], reason: expected[1]},
                "uia"
            )
            Assert.Equal(expected[3], dialog.title, "Wrong dialog for reason '" expected[1] "'")
        }

        ; The write may have happened, and the engine never restores.
        unconfirmed := WetReadPasteFailureDialog(
            {success: false, unsupported: false, unchanged: false, reason: "verification-error"},
            "uia"
        )
        Assert.True(InStr(unconfirmed.text, "not confirmed"), unconfirmed.text)
        Assert.False(InStr(unconfirmed.text, "restore"), unconfirmed.text)
    }

    UnconfirmedPasteIsLoggedWithItsReason() {
        failed := WetReadPasteEngine.NewResult()
        failed.reason := "verification-error"
        failed.error := "simulated readback failure"
        confirmed := WetReadPasteEngine.NewResult()
        confirmed.success := true

        capturedLog := LogCapture()
        try {
            Assert.False(ReportWetReadPasteResult(failed, "uia"))
            Assert.True(ReportWetReadPasteResult(confirmed, "uia"))
            loggedFailures := capturedLog.Count("Wet read paste not confirmed (verification-error): simulated readback failure")
            loggedEntries := capturedLog.Count("Wet read")
        } finally capturedLog.Restore()

        Assert.Equal(1, loggedFailures)
        Assert.Equal(1, loggedEntries)
        Assert.Equal(1, TestRunner.dialogs.Length)
        Assert.Equal("Sticky Note Not Verified", TestRunner.dialogs[1].title)
    }

    LineEndingConversionProducesCrlfOnly() {
        Assert.Equal("a`r`nb`r`nc`rd", ConvertWetReadLineEndings("a`nb`r`nc`rd"))
        Assert.Equal("", ConvertWetReadLineEndings(""))
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
            FakeWetReadTargetDriver(false)
        )

        Assert.False(driver.WriteUIA(field, "new wet read"))
        Assert.Equal(0, field.writeCalls)
    }

    NativeControlWithoutHandleIsUnsupported() {
        driver := NativeWetReadDriver(
            "Sticky Notes",
            FakeWetReadTargetDriver(true)
        )

        Assert.False(driver.WriteControl({NativeWindowHandle: 0}, "new wet read"))
    }

    NativeControlWriteHasNoFocusSideEffect() {
        controlDriver := FakeWetReadControlDriver()
        driver := NativeWetReadDriver(
            "ahk_id 200",
            FakeWetReadTargetDriver(true),
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

    ; The routing error is a cause; AttendingFailureMessage adds the instruction once.
    AttendingFailureMessagesReadAsOneSentence() {
        Assert.Equal(
            "The report was read, but the attending could not be assigned: attending 'Smith' cannot be selected in PowerScribe automatically. Set it manually.",
            AttendingFailureMessage("EXAMINATION: CT CHEST", Error("attending 'Smith' cannot be selected in PowerScribe automatically"))
        )
        try AttendingRouting.Route("EXAMINATION: PET UNKNOWN", (*) => "Smith", (*) => false)
        catch Error as err
            routingError := err
        Assert.Equal(
            "The report was read, but the attending could not be assigned: the examination did not match a supported modality. Set it manually.",
            AttendingFailureMessage("EXAMINATION: PET UNKNOWN", routingError)
        )
    }

    RoutingFailureReportsTheActualCause() {
        message := AttendingFailureMessage(
            "EXAMINATION: CT CHEST",
            Error("could not safely control PowerScribe")
        )

        Assert.True(InStr(message, "could not safely control PowerScribe") > 0)
        Assert.False(InStr(message, "Could not read the report") > 0)
    }

    ; UIA-v2's semantic Click() returns the pattern it used, or 0 when nothing
    ; actioned the button.
    NativeStickyButtonReportsWhetherClickActioned() {
        driver := NativeStickyNoteWindowDriver()

        Assert.True(driver.InvokeStickyButton(FakeClickResult("Invoke")))
        Assert.False(driver.InvokeStickyButton(FakeClickResult(0)))
        Assert.False(driver.InvokeStickyButton(FakeClickResult(Error("simulated UIA failure"))))
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
            RecordNotification.Bind(notifications)
        )

        Assert.False(result)
        Assert.Equal(0, captureCalls)
        Assert.Equal(2, notifications.Length)
        Assert.Equal("Sticky Note Target Not Verified", notifications[1].title)
        Assert.Equal("Attending Not Assigned", notifications[2].title)
        Assert.True(InStr(notifications[2].text, "Set it manually") > 0)
        ; PowerScribe was never asked, so it must not be blamed.
        Assert.True(InStr(notifications[2].text, "stopped before the report was read"), notifications[2].text)
        Assert.False(InStr(notifications[2].text, "PowerScribe"), notifications[2].text)
    }

    ; A fault the dialogs only summarize is logged with its stack. The routine
    ; routing outcome (an attending PowerScribe cannot select) is not logged.
    UnexpectedWorkflowFaultsAreLoggedWithTheirStack() {
        notifications := []
        notify := RecordNotification.Bind(notifications)
        session := {stickyHwnd: 1}
        capturedLog := LogCapture()
        try {
            RunPinnedWetReadWorkflow("wet read", "uia",
                (*) => {}.missingProperty, (*) => {text: "", session: 0}, (*) => true, (*) => true, notify)
            openerFaults := capturedLog.Count("the Sticky Notes target could not be verified: PropertyError")
            RunPinnedWetReadWorkflow("wet read", "uia",
                (*) => session, (*) => {}.missingProperty, (*) => true, (*) => true, notify)
            captureFaults := capturedLog.Count("could not read the PowerScribe report: PropertyError")
            RunPinnedWetReadWorkflow("wet read", "uia",
                (*) => session, (*) => {text: "EXAMINATION: CT HEAD", session: 0},
                (*) => FakeEarlyWetReadExit.Throw("attending 'Dr. A' cannot be selected in PowerScribe automatically"),
                (*) => true, notify)
            RunPinnedWetReadWorkflow("wet read", "uia",
                (*) => session, (*) => {text: "EXAMINATION: CT HEAD", session: 0},
                (*) => Integer("not a number"), (*) => true, notify)
            routingFaults := capturedLog.Count("Attending routing failed: TypeError")
            loggedEntries := 0
            for line in StrSplit(capturedLog.Text(), "`n") {
                if RegExMatch(line, "^\d{4}-\d{2}-\d{2} ")
                    loggedEntries++
            }
            stackLines := capturedLog.Count("WetReadTest.ahk (")
        } finally capturedLog.Restore()

        Assert.Equal(1, openerFaults)
        Assert.Equal(1, captureFaults)
        Assert.Equal(1, routingFaults)
        Assert.Equal(3, loggedEntries)
        Assert.True(stackLines >= 3, "each logged fault carries its call stack")
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
            RecordNotification.Bind(notifications)
        )
        catch Any
            escaped := true

        Assert.False(escaped)
        Assert.False(result)
        Assert.Equal(0, captureCalls)
        Assert.Equal(2, notifications.Length)
        Assert.Equal("Sticky Note Target Not Verified", notifications[1].title)
        Assert.True(InStr(notifications[1].text, "simulated opener failure") > 0)
        Assert.Equal("Attending Not Assigned", notifications[2].title)
        ; The opener error is reported once, in the sticky notice.
        Assert.False(InStr(notifications[2].text, "simulated opener failure"), notifications[2].text)
        Assert.True(InStr(notifications[2].text, "stopped before the report was read"), notifications[2].text)
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
            RecordNotification.Bind(notifications)
        )
        catch Any
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
    static Throw(message) {
        throw Error(message)
    }
}

class FakeWetReadDriver {
    __New(fieldValue) {
        this.fieldValue := fieldValue
        this.readCalls := 0
        this.failedText := ""
        this.uiaSupported := true
        this.uiaSupportedCalls := 0
        this.uiaCalls := 0
        this.controlSupported := true
        this.controlCalls := 0
        this.throwOnRead := false
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
        super.__New(firstValue)
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
        this.now := 0
    }

    Read(*) {
        return this.currentValue
    }

    NowMilliseconds() {
        return this.now
    }

    Pause(milliseconds) {
        this.now += milliseconds
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
    __New(elementType, processId, readable := false, windowId := 100, name := "") {
        this.Type := elementType
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
}

class FakeWetReadControlDriver {
    __New() {
        this.writes := []
    }

    SetText(hwnd, value) {
        this.writes.Push({hwnd: hwnd, value: value})
    }
}

class FakeWetReadTargetDriver {
    __New(matches) {
        this.matches := matches
    }

    IsExpectedTarget(*) {
        return this.matches
    }
}

; The real NativeStickyNoteWindowDriver gate over scripted Win32 primitives, so the
; session identity checks run as shipped. PACS window 100, process 42; window 150 is
; an unrelated pre-existing process window and 200 is the new Sticky Notes window.
class PrimitiveStickyNoteWindowDriver extends NativeStickyNoteWindowDriver {
    __New(processWindows, titles, owners) {
        this.processWindows := processWindows
        this.titles := titles
        this.owners := owners
        this.activationSucceeds := true
        this.siblingOnActivation := 0
        this.activated := []
    }

    static Standard() {
        return PrimitiveStickyNoteWindowDriver(
            [100, 150, 200],
            Map(100, "Vue PACS", 150, "Toolbar", 200, "Sticky Notes"),
            Map(200, 100)
        )
    }

    static Session() {
        return {
            pacsHwnd: 100,
            stickyHwnd: 200,
            processId: 42,
            preexistingProcessWindows: [100, 150]
        }
    }

    AddWindow(hwnd, title, owner) {
        this.processWindows.Push(hwnd)
        this.titles[hwnd] := title
        this.owners[hwnd] := owner
    }

    FindProcessWindows(processId) {
        return IsObject(this.processWindows) ? this.processWindows.Clone() : 0
    }

    GetTitle(hwnd) {
        if !this.titles.Has(hwnd)
            throw TargetError("Target window not found.")
        return this.titles[hwnd]
    }

    GetOwner(hwnd) {
        return this.owners.Has(hwnd) ? this.owners[hwnd] : 0
    }

    ActivateWindow(hwnd) {
        this.activated.Push(hwnd)
        if this.siblingOnActivation
            this.AddWindow(this.siblingOnActivation, "Sticky Notes", 100)
        return this.activationSucceeds
    }
}

class FakeClickResult {
    __New(result) {
        this.result := result
    }

    Click(*) {
        if (this.result is Error)
            throw this.result
        return this.result
    }
}
