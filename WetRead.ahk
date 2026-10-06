; = CONTENTS
;   + Preamble
;   + NativeStickyNoteWindowDriver (windows, UIA roots, clicks, keystrokes and readback)
;   + StickyNoteOpener (opens the Sticky Notes window of the study shown in Vue PACS)
;   + StickyNoteWriter (types the note, then saves it once the text has landed)
;   + CheckAttending, AttendingFailureMessage, RunPinnedWetReadWorkflow, WetRead,
;       PrepareWetReadText, PerformWetReadPaste, StopWetRead, ReportUnsavedWetRead
;       (file-scope wet-read workflow)

#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include AppLog.ahk
#Include ClinicalNotices.ahk
#Include ProfileManager.ahk
#Include PowerScribe.ahk
#Include UIAValue.ahk
#Include ErrorText.ahk

/**
 * The native side of a wet read: window lookup, UIA roots, clicks, keystrokes and
 * reading the note back. Titles are matched as substrings, without the global
 * title-match mode, as the v2.0b7 sequence this follows matched them.
 */
class NativeStickyNoteWindowDriver {
    static pacsTitleFragment := "Vue PACS"
    static stickyTitleFragment := "Sticky Notes"

    ; Visible Vue PACS windows: the active one first, then the rest in Z-order.
    ListPacsWindows() {
        active := this.ActiveWindow()
        windows := []
        for hwnd in this.ListVisibleWindows("ahk_exe " AppControl.vuePacsExecutable) {
            if !InStr(this.GetTitle(hwnd), NativeStickyNoteWindowDriver.pacsTitleFragment, true)
                continue
            if (hwnd = active)
                windows.InsertAt(1, hwnd)
            else
                windows.Push(hwnd)
        }
        return windows
    }

    ; Visible windows, of any process, whose title contains "Sticky Notes".
    ListStickyWindows() {
        windows := []
        for hwnd in this.ListVisibleWindows() {
            if InStr(this.GetTitle(hwnd), NativeStickyNoteWindowDriver.stickyTitleFragment, true)
                windows.Push(hwnd)
        }
        return windows
    }

    ListVisibleWindows(winTitle := "") {
        previousHiddenSetting := A_DetectHiddenWindows
        DetectHiddenWindows(false)
        try return winTitle = "" ? WinGetList() : WinGetList(winTitle)
        catch
            return []
        finally DetectHiddenWindows(previousHiddenSetting)
    }

    GetTitle(hwnd) {
        try return WinGetTitle("ahk_id " hwnd)
        return ""
    }

    ; A button's UIA identity, for the log. Only for buttons: their labels are UI
    ; text, while a list cell or the note itself can hold patient data.
    DescribeButton(element) {
        name := ""
        automationId := ""
        className := ""
        try name := element.Name
        try automationId := element.AutomationId
        try className := element.ClassName
        return "Name='" name "' AutomationId='" automationId "' ClassName='" className "'"
    }

    ; Process and window class, for the log; never the title, which can name a patient.
    Describe(hwnd) {
        if (hwnd <= 0)
            return "none"
        processName := ""
        className := ""
        try processName := WinGetProcessName("ahk_id " hwnd)
        try className := WinGetClass("ahk_id " hwnd)
        return processName "/" className
    }

    ActiveWindow() {
        try return WinActive("A")
        return 0
    }

    IsActive(hwnd) {
        return hwnd > 0 && this.ActiveWindow() = hwnd
    }

    ; Activates one exact HWND and waits up to two seconds for it to become active.
    Activate(hwnd) {
        try {
            WinActivate("ahk_id " hwnd)
            return WinWaitActive("ahk_id " hwnd, , 2) = hwnd
        } catch {
            return false
        }
    }

    GetRoot(hwnd) {
        try return UIA.ElementFromHandle("ahk_id " hwnd)
        return 0
    }

    FindByName(root, name) {
        try return root.FindElement({Name: name})
        return 0
    }

    FindByPath(root, path) {
        try return root.ElementFromPath(path)
        return 0
    }

    ; UIA-v2's semantic Click(): an Invoke-style action that needs neither focus
    ; nor the mouse.
    Invoke(element) {
        try return !!element.Click()
        return false
    }

    ; A real left click, with the mouse put back where it was (MoveBack 0).
    MouseClick(element) {
        element.Click("left", 1, "", "", false, 0)
    }

    ControlClick(element) {
        element.ControlClick()
    }

    SendKey(keys) {
        Send(keys)
    }

    ; Raw text: + ^ ! # { } are typed as themselves, and each line break is Enter.
    TypeText(text) {
        SendText(text)
    }

    ; Reads a text field through UIA Value, the legacy accessible value, the text
    ; pattern, or the field's own window, in that order.
    ReadText(element) {
        result := UIAValue.TryRead(element)
        if result.supported
            return result
        try {
            if element.IsTextPatternAvailable
                return {supported: true, value: element.TextPattern.DocumentRange.GetText(-1)}
        }
        try {
            if (hwnd := element.NativeWindowHandle)
                return {supported: true, value: ControlGetText(hwnd)}
        }
        return {supported: false, value: ""}
    }

    Now() {
        return DllCall("GetTickCount64", "UInt64")
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }
}

/**
 * Opens the Sticky Notes window of the study shown in Vue PACS, as v2.0b7 did at
 * the hospital: press the scn_sticky_notes button in the Vue PACS window, then take
 * the Sticky Notes window that appears.
 */
class StickyNoteOpener {
    static stickyButtonName := "scn_sticky_notes"
    static appearTimeoutMs := 3000
    static pollMs := 50

    __New(driver := 0) {
        this.driver := driver ? driver : NativeStickyNoteWindowDriver()
    }

    /**
     * @returns {pacsHwnd, stickyHwnd, driver} for the opened window, or {failure}
     * naming the step that did not happen. Nothing is typed here.
     */
    Open() {
        driver := this.driver
        pacsWindows := driver.ListPacsWindows()
        pacsHwnd := 0
        button := 0
        for hwnd in pacsWindows {
            root := driver.GetRoot(hwnd)
            if (root && (button := driver.FindByName(root, StickyNoteOpener.stickyButtonName))) {
                pacsHwnd := hwnd
                break
            }
        }
        if !pacsHwnd {
            return {failure: pacsWindows.Length
                ? "the Sticky Notes button was not found in Vue PACS"
                : "no Vue PACS window is open"}
        }
        if !driver.Activate(pacsHwnd)
            return {failure: "Vue PACS could not be brought to the front"}

        before := driver.ListStickyWindows()
        driver.Invoke(button)
        deadline := driver.Now() + StickyNoteOpener.appearTimeoutMs
        loop {
            opened := this.FindOpenedSticky(before)
            if opened.ambiguous
                return {failure: "more than one Sticky Notes window opened"}
            if opened.hwnd
                return {pacsHwnd: pacsHwnd, stickyHwnd: opened.hwnd, driver: driver}
            if (driver.Now() >= deadline)
                break
            driver.Pause(StickyNoteOpener.pollMs)
        }
        return {failure: "no Sticky Notes window opened within "
            . StickyNoteOpener.appearTimeoutMs // 1000 " seconds (active window: "
            . driver.Describe(driver.ActiveWindow()) ")"}
    }

    ; The window the button opened: the one new Sticky Notes window or, when PACS
    ; brought back a window it already had, the Sticky Notes window now active. A
    ; Sticky Notes window that was already open and stays in the background (another
    ; study's, or another program's) is never taken.
    FindOpenedSticky(before) {
        after := this.driver.ListStickyWindows()
        previous := Map()
        for hwnd in before
            previous[hwnd] := true
        opened := []
        for hwnd in after {
            if !previous.Has(hwnd)
                opened.Push(hwnd)
        }
        if (opened.Length > 1)
            return {hwnd: 0, ambiguous: true}
        if (opened.Length = 1)
            return {hwnd: opened[1], ambiguous: false}
        active := this.driver.ActiveWindow()
        for hwnd in after {
            if (hwnd = active)
                return {hwnd: hwnd, ambiguous: false}
        }
        return {hwnd: 0, ambiguous: false}
    }
}

/**
 * Fills in and saves a new note in an opened Sticky Notes window by the v2.0b7
 * sequence, with one change: Save is pressed only after the note reads back with
 * the whole text. Save is a UIA action, outside the keyboard queue, so v2.0b7's
 * fixed pause could press it while typed keys were still waiting to be processed.
 */
class StickyNoteWriter {
    ; UIA-v2 paths in the Sticky Notes window, as v2.0b7 used them.
    static newNotePath := "YY0"   ; Pane > Pane > first Button
    static noteTypePath := "87K/" ; List > first ListItem > last Text
    static noteTypeKey := "r"
    static noteFieldPath := "V"   ; first Document: the note text
    static savePath := "YY0/"     ; Pane > Pane > last Button
    static stepPauseMs := 100
    static pollMs := 100
    static buttonsLogged := false

    __New(session) {
        this.driver := session.driver
        this.stickyHwnd := session.stickyHwnd
    }

    /**
     * @param text The note, already prepared by PrepareWetReadText
     * @returns {saved, typed, message}. typed is true once any note text was sent;
     * message says what happened and what to do when saved is false.
     */
    Write(text) {
        driver := this.driver
        if !driver.Activate(this.stickyHwnd)
            return this.NotTyped("The Sticky Notes window could not be brought to the front")
        root := driver.GetRoot(this.stickyHwnd)
        if !root
            return this.NotTyped("The Sticky Notes window could not be read")

        if !(newNote := driver.FindByPath(root, StickyNoteWriter.newNotePath))
            return this.NotTyped("The Sticky Notes new-note button was not found")
        driver.Invoke(newNote)
        driver.Pause(StickyNoteWriter.stepPauseMs)

        if !(noteType := driver.FindByPath(root, StickyNoteWriter.noteTypePath))
            return this.NotTyped("The Sticky Notes note type was not found")
        driver.MouseClick(noteType)
        driver.Pause(StickyNoteWriter.stepPauseMs)
        if !driver.IsActive(this.stickyHwnd)
            return this.NotTyped("The Sticky Notes window lost focus")
        driver.SendKey(StickyNoteWriter.noteTypeKey)
        driver.Pause(StickyNoteWriter.stepPauseMs)

        field := driver.FindByPath(root, StickyNoteWriter.noteFieldPath)
        if !this.IsTextField(field)
            return this.NotTyped("The Sticky Notes text field was not found")
        driver.ControlClick(field)
        driver.Pause(StickyNoteWriter.stepPauseMs)
        baseline := driver.ReadText(field)
        if !driver.IsActive(this.stickyHwnd)
            return this.NotTyped("The Sticky Notes window lost focus")

        driver.TypeText(text)
        if !baseline.supported {
            return this.TypedNotSaved("unreadable",
                "PACS Assistant typed the wet read but cannot read this note back, so it did not click Save")
        }
        if !this.WaitForText(field, baseline.value, text) {
            return this.TypedNotSaved("incomplete",
                "The note did not show the whole wet read within " this.TimeoutMs(text) // 1000
                . " seconds, so PACS Assistant did not click Save")
        }
        if !(save := driver.FindByPath(root, StickyNoteWriter.savePath))
            return this.TypedNotSaved("no-save", "The Sticky Notes Save button was not found")
        if !driver.Invoke(save)
            return this.TypedNotSaved("save-not-pressed", "The Sticky Notes Save button did not respond")
        this.LogButtonIdentities(newNote, save)
        return {saved: true, typed: true, reason: "", message: ""}
    }

    ; The buttons are found by position, as v2.0b7 found them. Their names are
    ; logged once per run so a later build can find them by name instead.
    LogButtonIdentities(newNote, save) {
        if StickyNoteWriter.buttonsLogged
            return
        StickyNoteWriter.buttonsLogged := true
        AppLog.Write("Sticky Notes buttons: new note " this.driver.DescribeButton(newNote)
            . "; save " this.driver.DescribeButton(save))
    }

    IsTextField(field) {
        try return field && (field.Type = UIA.Type.Document || field.Type = UIA.Type.Edit)
        return false
    }

    ; The note is complete once it holds the typed text after whatever it held before.
    WaitForText(field, baselineText, text) {
        expected := StickyNoteWriter.Normalize(text)
        minimumLength := StrLen(StickyNoteWriter.Normalize(baselineText)) + StrLen(expected)
        deadline := this.driver.Now() + this.TimeoutMs(text)
        loop {
            current := this.driver.ReadText(field)
            if current.supported {
                value := StickyNoteWriter.Normalize(current.value)
                if (InStr(value, expected, true) && StrLen(value) >= minimumLength)
                    return true
            }
            if (this.driver.Now() >= deadline)
                return false
            this.driver.Pause(StickyNoteWriter.pollMs)
        }
    }

    ; Three seconds plus 25 ms a character, at most a minute.
    TimeoutMs(text) {
        return Min(60000, 3000 + 25 * StrLen(text))
    }

    ; Line breaks read back as CR, LF or CRLF depending on the control.
    static Normalize(text) {
        return RTrim(StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n"), " `t`n")
    }

    NotTyped(message) {
        return {saved: false, typed: false, reason: "", message: message ". Nothing was typed."}
    }

    TypedNotSaved(reason, message) {
        return {saved: false, typed: true, reason: reason, message: message ". Check the note, then click Save."}
    }
}

/**
 * Routes the report to the attending the profile assigns to its modality. A blank
 * assignment leaves PowerScribe's default unchanged; any other assignment throws
 * until PowerScribe.SetAttending can drive the attending picker safely, so the
 * caller reports the attending as a manual step.
 */
CheckAttending(reportText, powerScribeSession := 0) {
    return AttendingRouting.Route(
        reportText,
        ObjBindMethod(ProfileManager, "GetModalityAttending"),
        (attending) => PowerScribe.SetAttending(attending, powerScribeSession, reportText)
    )
}

AttendingFailureMessage(reportText, routingError := 0) {
    if (reportText = "") {
        message := "Could not read the report from PowerScribe, so the attending was not assigned"
        if routingError
            message .= ": " ErrorText.Message(routingError)
        return message ". Set it manually."
    }

    if routingError
        return "The report was read, but the attending could not be assigned: " ErrorText.Message(routingError) ". Set it manually."

    return "The report was read, but no attending was assigned. Set it manually."
}

RunPinnedWetReadWorkflow(
    clipText,
    openSticky,
    captureReport,
    routeAttending,
    pasteAction,
    notifier := 0
) {
    ; Open the study's Sticky Notes window first, while Vue PACS still shows that
    ; study. Later PowerScribe focus changes must never decide which window gets
    ; the text.
    notify := notifier ? notifier : ObjBindMethod(ClinicalNotices, "Show")
    stickyFailure := "The Sticky Notes window for the study in Vue PACS could not be opened. Nothing was typed"
    reportAttempted := false
    attendingRouted := false
    attendingError := 0
    haystack := ""
    try {
        stickySession := 0
        try {
            stickySession := openSticky.Call()
        } catch Any as err {
            AppLog.WriteError(err, "Wet read stopped: the Sticky Notes window could not be opened")
            notify.Call(stickyFailure ": " ErrorText.Message(err), "Sticky Note Not Opened", "Icon!")
            return false
        }
        if (!stickySession || HasProp(stickySession, "failure")) {
            message := stickyFailure (stickySession ? ": " stickySession.failure : "") "."
            AppLog.Write("Wet read stopped: " message)
            notify.Call(message, "Sticky Note Not Opened", "Icon!")
            return false
        }

        reportAttempted := true
        reportCapture := 0
        try reportCapture := captureReport.Call()
        catch as err {
            AppLog.WriteError(err, "Wet read could not read the PowerScribe report")
            attendingError := err
        }
        if !attendingError {
            if (!IsObject(reportCapture)
                || !HasProp(reportCapture, "text")
                || !HasProp(reportCapture, "session")
                || Type(reportCapture.text) != "String") {
                attendingError := Error("PowerScribe returned an invalid report capture")
            } else
                haystack := reportCapture.text
        }

        if (haystack != "") {
            try {
                routeAttending.Call(haystack, reportCapture.session)
                attendingRouted := true
            } catch as err {
                ; A plain Error is a routing outcome the dialog states (an unmatched
                ; modality, an attending PowerScribe cannot select); any other type
                ; is a fault worth its stack.
                if !(Type(err) == "Error")
                    AppLog.WriteError(err, "Attending routing failed")
                attendingError := err
            }
        }

        return pasteAction.Call(clipText, stickySession)
    } finally {
        if !attendingRouted {
            message := reportAttempted
                ? AttendingFailureMessage(haystack, attendingError)
                : "The wet read stopped before the report was read, so the attending was not assigned. Set it manually."
            notify.Call(message, "Attending Not Assigned", "Icon!")
        }
    }
}

WetRead() {
    text := PrepareWetReadText(A_Clipboard)
    if (text = "") {
        ClinicalNotices.Show("No text in clipboard to paste as wet read.", "No Clipboard Text", "Icon!")
        return false
    }

    return RunPinnedWetReadWorkflow(
        text,
        (*) => StickyNoteOpener().Open(),
        (*) => PowerScribe.CaptureReport(),
        (reportText, session) => CheckAttending(reportText, session),
        PerformWetReadPaste
    )
}

; Each line break becomes one Enter. A Tab would move focus out of the note, and
; trailing breaks would be typed after the text the readback waits for, so tabs
; become spaces and trailing whitespace is dropped.
PrepareWetReadText(text) {
    text := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
    return RTrim(StrReplace(text, "`t", " "), " `n")
}

PerformWetReadPaste(text, stickySession) {
    if (!IsObject(stickySession)
        || !HasProp(stickySession, "driver")
        || !HasProp(stickySession, "stickyHwnd"))
        return StopWetRead("The Sticky Notes window was not opened. Nothing was typed.")
    result := StickyNoteWriter(stickySession).Write(text)
    if result.saved
        return true
    if !result.typed
        return StopWetRead(result.message)
    return ReportUnsavedWetRead(result)
}

; Ends a wet read that stopped before any note text was typed: logs the reason,
; shows it, and returns false.
StopWetRead(message) {
    AppLog.Write("Wet read stopped: " message)
    ClinicalNotices.Show(message, "Wet Read Stopped", "Icon!")
    return false
}

; The note text was typed but Save was not pressed. The note text is not logged.
ReportUnsavedWetRead(result) {
    AppLog.Write("Wet read typed but not saved (" result.reason ")")
    ClinicalNotices.Show(result.message, "Wet Read Not Saved", "Icon!")
    return false
}
