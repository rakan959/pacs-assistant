; = CONTENTS
;   + Preamble
;   + WetReadTest class (window matching, opening Sticky Notes, typing and saving the
;       note, text preparation, workflow notices and attending routing)
;   + Test doubles (titled window driver, opener driver, writer driver and field)

#Requires AutoHotkey v2.0
#Include ../WetRead.ahk
#Include TestRunner.ahk
#Include LogCapture.ahk

class WetReadTest {
    static tests := [
        "StickyWindowsMatchTitlesContainingStickyNotes",
        "PacsWindowsListTheActiveVuePacsWindowFirst",
        "OpenerTakesTheWindowTheButtonOpened",
        "OpenerWaitsForTheWindowToAppear",
        "OpenerTakesAReusedWindowPacsBroughtToTheFront",
        "OpenerNeverTakesABackgroundStickyNotesWindow",
        "OpenerRefusesTwoNewStickyNotesWindows",
        "OpenerUsesTheVuePacsWindowThatHasTheButton",
        "OpenerReportsAMissingButtonOrPacsWindow",
        "OpenerStopsWhenVuePacsCannotBeActivated",
        "WriterFollowsTheVersion2Sequence",
        "SaveWaitsUntilTheWholeNoteHasLanded",
        "NoteThatNeverCompletesIsNotSaved",
        "UnreadableNoteIsTypedButNotSaved",
        "ExistingNoteTextIsPartOfTheReadback",
        "ReadbackAcceptsEveryLineBreakForm",
        "FocusLossStopsBeforeTyping",
        "MissingTextFieldStopsBeforeTyping",
        "MissingOrUnresponsiveSaveLeavesTheNoteUnsaved",
        "ButtonIdentitiesAreLoggedOncePerRun",
        "PreparedTextTypesEachLineBreakOnceAndKeepsSymbols",
        "UnsavedWetReadIsReportedWithoutItsText",
        "AttendingFailureMessagesReadAsOneSentence",
        "RoutingFailureReportsTheActualCause",
        "OpenerFailureReasonIsShownAndLogged",
        "StickyOpenerFailureAlsoReportsAttendingOutcome",
        "UnexpectedWorkflowFaultsAreLoggedWithTheirStack",
        "WetReadStopsBeforeTypingAreLogged",
        "ThrowingStickyOpenerStillReportsAttendingOutcome",
        "ThrowingReportCaptureStillPastesAndReportsAttendingOutcome",
        "StickyNoteIsOpenedBeforePowerScribeRouting"
    ]

    ; v2.0b7 found the window with the default title match: any title containing
    ; "Sticky Notes", case-sensitive.
    StickyWindowsMatchTitlesContainingStickyNotes() {
        driver := TitledWindowDriver([
            {hwnd: 1, title: "Sticky Notes", exe: "mp.exe"},
            {hwnd: 2, title: "Sticky Notes - 12345678", exe: "mp.exe"},
            {hwnd: 3, title: "Notes", exe: "mp.exe"},
            {hwnd: 4, title: "sticky notes", exe: "notepad.exe"},
            {hwnd: 5, title: "Sticky Notes", exe: "ApplicationFrameHost.exe"}
        ])
        Assert.Equal("1,2,5", TitledWindowDriver.Join(driver.ListStickyWindows()))
    }

    PacsWindowsListTheActiveVuePacsWindowFirst() {
        driver := TitledWindowDriver([
            {hwnd: 10, title: "Vue PACS", exe: "mp.exe"},
            {hwnd: 11, title: "Explorer Portal", exe: "mp.exe"},
            {hwnd: 12, title: "Vue PACS Client", exe: "mp.exe"},
            {hwnd: 13, title: "Vue PACS", exe: "other.exe"}
        ])
        driver.active := 12
        Assert.Equal("12,10", TitledWindowDriver.Join(driver.ListPacsWindows()))
    }

    OpenerTakesTheWindowTheButtonOpened() {
        driver := FakeOpenerDriver([100], 100, [[7], [7, 200]])
        session := StickyNoteOpener(driver).Open()
        Assert.False(HasProp(session, "failure"), HasProp(session, "failure") ? session.failure : "")
        Assert.Equal(200, session.stickyHwnd)
        Assert.Equal(100, session.pacsHwnd)
        Assert.Equal(driver, session.driver)
        Assert.Equal("activate 100|invoke 100", driver.Log())
    }

    OpenerWaitsForTheWindowToAppear() {
        driver := FakeOpenerDriver([100], 100, [[], [], [], [200]])
        session := StickyNoteOpener(driver).Open()
        Assert.Equal(200, session.stickyHwnd)
        Assert.True(driver.clock > 0 && driver.clock < StickyNoteOpener.appearTimeoutMs, driver.clock)
    }

    ; PACS may raise a Sticky Notes window it already had instead of creating one.
    OpenerTakesAReusedWindowPacsBroughtToTheFront() {
        driver := FakeOpenerDriver([100], 100, [[200], [200]], 200)
        session := StickyNoteOpener(driver).Open()
        Assert.Equal(200, session.stickyHwnd)
    }

    ; Another study's note, or another program's "Sticky Notes" window, that stays in
    ; the background is never the target.
    OpenerNeverTakesABackgroundStickyNotesWindow() {
        driver := FakeOpenerDriver([100], 100, [[300], [300]])
        session := StickyNoteOpener(driver).Open()
        Assert.True(HasProp(session, "failure"))
        Assert.True(InStr(session.failure, "no Sticky Notes window opened within 3 seconds"), session.failure)
        Assert.True(InStr(session.failure, "fake.exe/FakeClass"), session.failure)
        Assert.True(driver.clock >= StickyNoteOpener.appearTimeoutMs)
    }

    OpenerRefusesTwoNewStickyNotesWindows() {
        driver := FakeOpenerDriver([100], 100, [[], [200, 201]])
        session := StickyNoteOpener(driver).Open()
        Assert.Equal("more than one Sticky Notes window opened", session.failure)
    }

    OpenerUsesTheVuePacsWindowThatHasTheButton() {
        driver := FakeOpenerDriver([100, 101], 101, [[], [200]])
        session := StickyNoteOpener(driver).Open()
        Assert.Equal(101, session.pacsHwnd)
        Assert.Equal("activate 101|invoke 101", driver.Log())
    }

    OpenerReportsAMissingButtonOrPacsWindow() {
        driver := FakeOpenerDriver([100], 0, [[]])
        Assert.Equal("the Sticky Notes button was not found in Vue PACS", StickyNoteOpener(driver).Open().failure)
        Assert.Equal("", driver.Log())

        driver := FakeOpenerDriver([], 0, [[]])
        Assert.Equal("no Vue PACS window is open", StickyNoteOpener(driver).Open().failure)
    }

    OpenerStopsWhenVuePacsCannotBeActivated() {
        driver := FakeOpenerDriver([100], 100, [[], [200]])
        driver.activateOk := false
        Assert.Equal("Vue PACS could not be brought to the front", StickyNoteOpener(driver).Open().failure)
        Assert.Equal("activate 100", driver.Log())
    }

    WriterFollowsTheVersion2Sequence() {
        driver := FakeWriterDriver()
        result := StickyNoteWriter(driver.Session()).Write("No acute findings.")
        Assert.True(result.saved, result.message)
        Assert.Equal(
            "activate|invoke YY0|mouse 87K/|key r|controlclick V|type No acute findings.|invoke YY0/",
            driver.Log()
        )
    }

    ; Regression for v2.0b7: Save is a UIA action outside the keyboard queue, so it
    ; must wait for the note to read back with the whole text, however slowly the
    ; typed keys are processed.
    SaveWaitsUntilTheWholeNoteHasLanded() {
        text := "Small left pleural effusion.`nNo pneumothorax."
        driver := FakeWriterDriver()
        driver.charsPerPoll := 4
        result := StickyNoteWriter(driver.Session()).Write(text)
        Assert.True(result.saved, result.message)
        Assert.True(driver.reads > 3, "the note was read back while it filled")
        Assert.Equal(StrLen(text), driver.visibleAtSave)
    }

    NoteThatNeverCompletesIsNotSaved() {
        driver := FakeWriterDriver()
        driver.charsPerPoll := 2
        driver.maxVisible := 5
        result := StickyNoteWriter(driver.Session()).Write("Appendix is normal.")
        Assert.False(result.saved)
        Assert.True(result.typed)
        Assert.Equal("incomplete", result.reason)
        Assert.True(InStr(result.message, "did not click Save"), result.message)
        Assert.True(InStr(result.message, "Check the note, then click Save."), result.message)
        Assert.False(InStr(driver.Log(), "invoke YY0/"), driver.Log())
    }

    UnreadableNoteIsTypedButNotSaved() {
        driver := FakeWriterDriver()
        driver.readable := false
        result := StickyNoteWriter(driver.Session()).Write("Normal study.")
        Assert.False(result.saved)
        Assert.True(result.typed)
        Assert.Equal("unreadable", result.reason)
        Assert.True(InStr(driver.Log(), "type Normal study."), driver.Log())
        Assert.False(InStr(driver.Log(), "invoke YY0/"), driver.Log())
    }

    ExistingNoteTextIsPartOfTheReadback() {
        driver := FakeWriterDriver()
        driver.baseline := "Earlier note."
        driver.charsPerPoll := 3
        result := StickyNoteWriter(driver.Session()).Write("Earlier")
        Assert.True(result.saved, result.message)
        ; "Earlier" was already in the note; Save waits for the typed copy as well.
        Assert.Equal(StrLen("Earlier"), driver.visibleAtSave)
    }

    ReadbackAcceptsEveryLineBreakForm() {
        for lineBreak in ["`r`n", "`r", "`n"] {
            driver := FakeWriterDriver()
            driver.readLineBreak := lineBreak
            result := StickyNoteWriter(driver.Session()).Write("Line one`nLine two")
            Assert.True(result.saved, result.message)
        }
    }

    FocusLossStopsBeforeTyping() {
        driver := FakeWriterDriver()
        driver.loseFocusAfter := "mouse 87K/"
        result := StickyNoteWriter(driver.Session()).Write("Normal study.")
        Assert.False(result.saved)
        Assert.False(result.typed)
        Assert.True(InStr(result.message, "lost focus. Nothing was typed."), result.message)
        Assert.Equal("activate|invoke YY0|mouse 87K/", driver.Log())
    }

    MissingTextFieldStopsBeforeTyping() {
        driver := FakeWriterDriver()
        driver.elements["V"] := FakeWriterElement("V", UIA.Type.Button)
        result := StickyNoteWriter(driver.Session()).Write("Normal study.")
        Assert.False(result.typed)
        Assert.True(InStr(result.message, "text field was not found"), result.message)
        Assert.False(InStr(driver.Log(), "type "), driver.Log())

        driver := FakeWriterDriver()
        driver.elements.Delete("YY0")
        result := StickyNoteWriter(driver.Session()).Write("Normal study.")
        Assert.False(result.typed)
        Assert.Equal("activate", driver.Log())
    }

    MissingOrUnresponsiveSaveLeavesTheNoteUnsaved() {
        driver := FakeWriterDriver()
        driver.elements.Delete("YY0/")
        result := StickyNoteWriter(driver.Session()).Write("Normal study.")
        Assert.False(result.saved)
        Assert.True(result.typed)
        Assert.Equal("no-save", result.reason)

        driver := FakeWriterDriver()
        driver.saveResponds := false
        result := StickyNoteWriter(driver.Session()).Write("Normal study.")
        Assert.False(result.saved)
        Assert.Equal("save-not-pressed", result.reason)
    }

    ; The first saved note records the buttons' names for a later name-based lookup;
    ; the note text never reaches the log.
    ButtonIdentitiesAreLoggedOncePerRun() {
        StickyNoteWriter.buttonsLogged := false
        capturedLog := LogCapture()
        try {
            loop 2 {
                driver := FakeWriterDriver()
                Assert.True(StickyNoteWriter(driver.Session()).Write("Private note text").saved)
            }
            logged := capturedLog.Text()
            entries := capturedLog.Count("Sticky Notes buttons: new note button YY0; save button YY0/")
        } finally capturedLog.Restore()
        Assert.Equal(1, entries, logged)
        Assert.False(InStr(logged, "Private note text"), logged)
    }

    ; SendText types + ^ ! # { } as themselves; v2.0b7's Send read them as keys.
    PreparedTextTypesEachLineBreakOnceAndKeepsSymbols() {
        Assert.Equal("a`nb`nc", PrepareWetReadText("a`r`nb`rc"))
        Assert.Equal("Level 1+ {x} #3 ^ !", PrepareWetReadText("Level 1+ {x} #3 ^ !"))
        Assert.Equal("a b", PrepareWetReadText("a`tb"))
        Assert.Equal("  Indented`nline", PrepareWetReadText("  Indented`r`nline`r`n`r`n  `t"))
        Assert.Equal("", PrepareWetReadText(" `r`n`t"))
    }

    UnsavedWetReadIsReportedWithoutItsText() {
        capturedLog := LogCapture()
        try {
            driver := FakeWriterDriver()
            driver.maxVisible := 3
            Assert.False(PerformWetReadPaste("Private note text", driver.Session()))
            logged := capturedLog.Text()
        } finally capturedLog.Restore()
        Assert.True(InStr(logged, "Wet read typed but not saved (incomplete)"), logged)
        Assert.False(InStr(logged, "Private note text"), logged)
        Assert.Equal("Wet Read Not Saved", TestRunner.dialogs[-1].title)
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

    OpenerFailureReasonIsShownAndLogged() {
        notifications := []
        capturedLog := LogCapture()
        try {
            RunPinnedWetReadWorkflow("wet read",
                (*) => {failure: "the Sticky Notes button was not found in Vue PACS"},
                (*) => {text: "", session: 0}, (*) => true, (*) => true,
                RecordNotification.Bind(notifications))
            logged := capturedLog.Count("Wet read stopped: The Sticky Notes window for the study in Vue PACS could not be opened. Nothing was typed: the Sticky Notes button was not found in Vue PACS.")
        } finally capturedLog.Restore()
        Assert.Equal(1, logged)
        Assert.Equal("Sticky Note Not Opened", notifications[1].title)
        Assert.True(InStr(notifications[1].text, "button was not found in Vue PACS"), notifications[1].text)
    }

    StickyOpenerFailureAlsoReportsAttendingOutcome() {
        notifications := []
        captureCalls := 0

        result := RunPinnedWetReadWorkflow(
            "wet read",
            (*) => 0,
            (*) => (captureCalls++, {text: "", session: 0}),
            (*) => true,
            (*) => true,
            RecordNotification.Bind(notifications)
        )

        Assert.False(result)
        Assert.Equal(0, captureCalls)
        Assert.Equal(2, notifications.Length)
        Assert.Equal("Sticky Note Not Opened", notifications[1].title)
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
            RunPinnedWetReadWorkflow("wet read",
                (*) => {}.missingProperty, (*) => {text: "", session: 0}, (*) => true, (*) => true, notify)
            openerFaults := capturedLog.Count("the Sticky Notes window could not be opened: PropertyError")
            RunPinnedWetReadWorkflow("wet read",
                (*) => session, (*) => {}.missingProperty, (*) => true, (*) => true, notify)
            captureFaults := capturedLog.Count("could not read the PowerScribe report: PropertyError")
            RunPinnedWetReadWorkflow("wet read",
                (*) => session, (*) => {text: "EXAMINATION: CT HEAD", session: 0},
                (*) => ThrowError("attending 'Dr. A' cannot be selected in PowerScribe automatically"),
                (*) => true, notify)
            RunPinnedWetReadWorkflow("wet read",
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

    WetReadStopsBeforeTypingAreLogged() {
        notifications := []
        capturedLog := LogCapture()
        try {
            RunPinnedWetReadWorkflow("wet read",
                (*) => 0, (*) => {text: "", session: 0}, (*) => true, (*) => true,
                RecordNotification.Bind(notifications))
            Assert.False(PerformWetReadPaste("wet read", 0))
            driver := FakeWriterDriver()
            driver.activateOk := false
            Assert.False(PerformWetReadPaste("wet read", driver.Session()))
            openerStops := capturedLog.Count("Wet read stopped: The Sticky Notes window for the study in Vue PACS could not be opened")
            pasteStops := capturedLog.Count("Wet read stopped: The Sticky Notes window was not opened. Nothing was typed.")
            activationStops := capturedLog.Count("Wet read stopped: The Sticky Notes window could not be brought to the front. Nothing was typed.")
        } finally capturedLog.Restore()

        Assert.Equal(1, openerStops)
        Assert.Equal(1, pasteStops)
        Assert.Equal(1, activationStops)
        Assert.Equal("Wet Read Stopped", TestRunner.dialogs[-1].title)
    }

    ThrowingStickyOpenerStillReportsAttendingOutcome() {
        notifications := []
        captureCalls := 0
        escaped := false

        try result := RunPinnedWetReadWorkflow(
            "wet read",
            ThrowError.Bind("simulated opener failure"),
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
        Assert.Equal("Sticky Note Not Opened", notifications[1].title)
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
            (*) => stickySession,
            ThrowError.Bind("simulated report failure"),
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

    StickyNoteIsOpenedBeforePowerScribeRouting() {
        events := []
        stickySession := {stickyHwnd: 200}
        openSticky := (*) => (events.Push("open-sticky"), stickySession)
        captureReport := (*) => (
            events.Push("capture-report"),
            {text: "EXAMINATION: CT CHEST", session: {hwnd: 300}}
        )
        routeAttending := (*) => events.Push("route-attending")
        pasteAction := (text, session) => (
            events.Push("type-into-opened-sticky"),
            session = stickySession
        )

        result := RunPinnedWetReadWorkflow(
            "wet read",
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
        Assert.Equal("type-into-opened-sticky", events[4])
    }
}

; The native driver over a fixed set of windows, for its title and process matching.
class TitledWindowDriver extends NativeStickyNoteWindowDriver {
    __New(windows) {
        this.windows := windows
        this.active := 0
    }

    ListVisibleWindows(winTitle := "") {
        exe := RegExMatch(winTitle, "^ahk_exe (.+)$", &match) ? match[1] : ""
        list := []
        for window in this.windows {
            if (exe = "" || window.exe = exe)
                list.Push(window.hwnd)
        }
        return list
    }

    GetTitle(hwnd) {
        for window in this.windows {
            if (window.hwnd = hwnd)
                return window.title
        }
        return ""
    }

    ActiveWindow() => this.active

    static Join(list) {
        text := ""
        for item in list
            text .= (text = "" ? "" : ",") item
        return text
    }
}

; Opener double. stickyLists holds successive ListStickyWindows results: the first
; is the list before the button is pressed; the last repeats.
class FakeOpenerDriver {
    __New(pacsWindows, buttonWindow, stickyLists, activeAfterClick := 0) {
        this.pacsWindows := pacsWindows
        this.buttonWindow := buttonWindow
        this.stickyLists := stickyLists
        this.activeAfterClick := activeAfterClick
        this.listCalls := 0
        this.activateOk := true
        this.active := 0
        this.clock := 0
        this.actions := []
    }

    ListPacsWindows() => this.pacsWindows.Clone()
    GetRoot(hwnd) => {hwnd: hwnd}

    FindByName(root, name) {
        if (root.hwnd = this.buttonWindow && name == StickyNoteOpener.stickyButtonName)
            return {hwnd: root.hwnd}
        return 0
    }

    Activate(hwnd) {
        this.actions.Push("activate " hwnd)
        if this.activateOk
            this.active := hwnd
        return this.activateOk
    }

    ListStickyWindows() {
        this.listCalls++
        return this.stickyLists[Min(this.listCalls, this.stickyLists.Length)].Clone()
    }

    Invoke(button) {
        this.actions.Push("invoke " button.hwnd)
        if this.activeAfterClick
            this.active := this.activeAfterClick
        return true
    }

    ActiveWindow() => this.active
    Describe(hwnd) => "fake.exe/FakeClass"
    Now() => this.clock

    Pause(milliseconds) {
        this.clock += milliseconds
    }

    Log() {
        text := ""
        for action in this.actions
            text .= (text = "" ? "" : "|") action
        return text
    }
}

class FakeWriterElement {
    __New(path, type := UIA.Type.Button) {
        this.path := path
        this.Type := type
    }
}

; Writer double. The note field shows the typed text charsPerPoll characters per
; read (0 = at once), stopping at maxVisible, after any baseline text.
class FakeWriterDriver {
    __New() {
        this.elements := Map(
            "YY0", FakeWriterElement("YY0"),
            "87K/", FakeWriterElement("87K/", UIA.Type.Text),
            "V", FakeWriterElement("V", UIA.Type.Document),
            "YY0/", FakeWriterElement("YY0/")
        )
        this.actions := []
        this.activateOk := true
        this.active := 0
        this.loseFocusAfter := ""
        this.readable := true
        this.baseline := ""
        this.typed := ""
        this.charsPerPoll := 0
        this.maxVisible := -1
        this.visible := 0
        this.readLineBreak := "`r`n"
        this.reads := 0
        this.saveResponds := true
        this.visibleAtSave := -1
        this.clock := 0
    }

    Session() => {stickyHwnd: 200, pacsHwnd: 100, driver: this}

    Record(action) {
        this.actions.Push(action)
        if (action = this.loseFocusAfter)
            this.active := 0
    }

    Activate(hwnd) {
        this.Record("activate")
        if this.activateOk
            this.active := hwnd
        return this.activateOk
    }

    IsActive(hwnd) => this.active = hwnd
    GetRoot(hwnd) => {hwnd: hwnd}
    FindByPath(root, path) => this.elements.Has(path) ? this.elements[path] : 0

    Invoke(element) {
        this.Record("invoke " element.path)
        if (element.path = StickyNoteWriter.savePath) {
            this.visibleAtSave := this.visible
            return this.saveResponds
        }
        return true
    }

    DescribeButton(element) => "button " element.path
    MouseClick(element) => this.Record("mouse " element.path)
    SendKey(keys) => this.Record("key " keys)
    ControlClick(element) => this.Record("controlclick " element.path)

    TypeText(text) {
        this.Record("type " text)
        this.typed := text
        this.visible := this.charsPerPoll ? 0 : StrLen(text)
        if (this.maxVisible >= 0)
            this.visible := Min(this.visible, this.maxVisible)
    }

    ReadText(element) {
        if !this.readable
            return {supported: false, value: ""}
        this.reads++
        if (this.typed != "" && this.charsPerPoll) {
            limit := this.maxVisible >= 0 ? this.maxVisible : StrLen(this.typed)
            this.visible := Min(this.visible + this.charsPerPoll, limit, StrLen(this.typed))
        }
        shown := SubStr(this.typed, 1, this.visible)
        return {supported: true, value: StrReplace(this.baseline shown, "`n", this.readLineBreak)}
    }

    Now() => this.clock

    Pause(milliseconds) {
        this.clock += milliseconds
    }

    Log() {
        text := ""
        for action in this.actions
            text .= (text = "" ? "" : "|") action
        return text
    }
}
