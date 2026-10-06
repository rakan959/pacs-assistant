#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include AppLog.ahk
#Include UIAValue.ahk

class NativePowerScribeSessionDriver {
    ; The reporting window as v2.0b7 found it: the first window of the PowerScribe
    ; executable whose title contains "PowerScribe 360 | Reporting". Reading the
    ; report does not activate it.
    Capture() {
        try hwnds := AppControl.windowDriver.ListWindowsByExecutable(AppControl.powerScribeExecutable)
        catch
            return 0
        for hwnd in hwnds {
            try {
                title := AppControl.windowDriver.GetTitle(hwnd)
                if (!InStr(title, AppControl.powerScribeReportingTitle, true)
                    || StrCompare(AppControl.windowDriver.GetProcessName(hwnd), AppControl.powerScribeExecutable, false) != 0)
                    continue
                processId := AppControl.windowDriver.GetProcessId(hwnd)
            } catch {
                continue
            }
            if (processId > 0) {
                return {
                    hwnd: hwnd,
                    target: "ahk_id " hwnd,
                    processId: processId,
                    title: title,
                    exe: AppControl.powerScribeExecutable
                }
            }
        }
        return 0
    }

    ; The captured window still exists, in the same process, with a reporting title.
    IsLive(session) {
        if (!IsObject(session) || !HasProp(session, "hwnd") || !HasProp(session, "processId"))
            return false
        try return AppControl.windowDriver.GetProcessId(session.hwnd) = session.processId
            && InStr(AppControl.windowDriver.GetTitle(session.hwnd), AppControl.powerScribeReportingTitle, true) > 0
        return false
    }

    Root(session) {
        return this.IsLive(session) ? AppControl.VerifiedUiaRoot(session) : 0
    }
}

/**
 * The native side of the attending picker: activation, keystrokes and the focused
 * control. Tests replace it so the guard can be proven without typing.
 */
class NativeAttendingDriver {
    Activate(session) {
        return AppControl.windowDriver.Activate(session.target, AppControl.activationTimeoutSeconds)
    }

    SendKeys(keys) {
        Send(keys)
    }

    TypeText(text) {
        SendText(text)
    }

    ; {id, type, processId, element} of the focused control, or 0.
    FocusedControl() {
        try {
            element := UIA.GetFocusedElement()
            return {id: element.RuntimeId, type: element.Type, processId: element.ProcessId, element: element}
        }
        return 0
    }

    ; Control type, AutomationId and class for the log; never Name or value, which
    ; can hold what was typed.
    Describe(control) {
        automationId := ""
        className := ""
        try automationId := control.element.AutomationId
        try className := control.element.ClassName
        return "Type=" control.type " AutomationId='" automationId "' ClassName='" className "'"
    }

    Now() {
        return DllCall("GetTickCount64", "UInt64")
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }
}

/**
 * The PowerScribe report itself: locating it, reading it, and routing it to an
 * attending. PACSCommands keeps the command registry; the report workflow is here.
 */
class PowerScribe {
    static sessionDriver := NativePowerScribeSessionDriver()
    static attendingDriver := NativeAttendingDriver()
    static pickerTimeoutMs := 1500
    static pickerLogged := false

    ; v2.0b7's path to the report text (Pane > Pane > Pane > Pane > Document).
    static reportPath := "YYYYV"

    ; Whether a piece of text reads like a report body rather than some other field
    static LooksLikeReport(text) {
        return RegExMatch(text, "i)EXAMINATION:") > 0
    }

    /**
     * Chooses report text only when every report-shaped candidate agrees. A
     * history/prior-report pane can expose another EXAMINATION block in the same
     * window; choosing the first one could route the current study to its attending.
     */
    static SelectReportText(candidates) {
        reports := []
        for text in candidates {
            if this.LooksLikeReport(text)
                this.AddDistinctReport(reports, text)
        }
        return reports.Length = 1 ? reports[1] : ""
    }

    static AddDistinctReport(reports, text) {
        normalized := Trim(text)
        for existing in reports {
            if (StrCompare(Trim(existing), normalized, false) = 0)
                return
        }
        reports.Push(text)
    }

    static IsExpectedReportControl(root, control) {
        if !root || !control
            return false
        try return this.InspectExpectedReportControl(root, control)
        catch
            return false
    }

    static SendKeys(keys) {
        return AppControl.SendKeysToExactWindow(
            AppControl.PowerScribeWindowSpec(),
            keys
        )
    }

    /**
     * @returns {text, session}, plus {failure} naming why when text is blank
     */
    static CaptureReport() {
        session := this.sessionDriver.Capture()
        if !session
            return {text: "", session: 0, failure: "no PowerScribe reporting window was found"}
        text := this.ReadReportText(session)
        if (text = "")
            return {text: "", session: session, failure: "the report text was not found in PowerScribe"}
        return {text: text, session: session}
    }

    /**
     * The report at v2.0b7's path. When that is not report text, the one
     * report-shaped text among the window's document and edit controls; controls
     * that cannot be read, or belong to another window, are skipped.
     */
    static ReadReportText(session) {
        root := this.sessionDriver.Root(session)
        if !root
            return ""

        pathElement := 0
        try pathElement := root.ElementFromPath(this.reportPath)
        text := this.ReadReportControl(root, pathElement)
        if (text = "") {
            ; The report editor presents as a Document, but has been seen as a plain Edit.
            candidates := []
            for condition in [{Type: "Document"}, {Type: "Edit"}] {
                elements := []
                try elements := root.FindElements(condition)
                for element in elements {
                    if ((candidate := this.ReadReportControl(root, element)) != "")
                        candidates.Push(candidate)
                }
            }
            text := this.SelectReportText(candidates)
        }

        ; A report read while the window closed or changed belongs to no session.
        if !this.sessionDriver.IsLive(session)
            return ""
        return text
    }

    ; The report text of one document or edit control of this window, or "".
    static ReadReportControl(root, control) {
        if !this.IsExpectedReportControl(root, control)
            return ""
        try result := UIAValue.TryRead(control)
        catch
            return ""
        return result.supported && this.LooksLikeReport(result.value) ? result.value : ""
    }

    static InspectExpectedReportControl(root, control) {
        rootProcess := root.ProcessId
        rootWindow := root.WinId
        return rootProcess > 0
            && control.ProcessId = rootProcess
            && rootWindow > 0
            && control.WinId = rootWindow
            && (control.Type = UIA.Type.Document || control.Type = UIA.Type.Edit)
    }

    /**
     * Assigns the attending by v2.0b7's keystrokes: Alt+T, A opens the attending
     * picker; then the name, Tab, Space, Tab, Enter. One guard v2.0b7 lacked:
     * nothing is typed until focus has moved, within PowerScribe, to a control that
     * is not a document, because keys that reach the report editor would change
     * the report.
     * @returns true once the keys were sent; throws a plain Error naming why not
     */
    static SetAttending(attending, session := 0, *) {
        driver := this.attendingDriver
        if !session
            session := this.sessionDriver.Capture()
        if !session
            throw Error("no PowerScribe reporting window was found")
        if !driver.Activate(session)
            throw Error("PowerScribe could not be brought to the front")
        before := driver.FocusedControl()
        if !before
            throw Error("the focused PowerScribe control could not be read, so nothing was typed")
        driver.SendKeys("{Alt down}ta{Alt up}")
        picker := this.WaitForPickerFocus(session, before)
        if !picker
            throw Error("the attending picker did not take focus after Alt+T, A, so nothing was typed")
        driver.Pause(100)
        driver.TypeText(attending)
        driver.Pause(100)
        driver.SendKeys("{Tab}{Space}{Tab}{Enter}")
        if !this.pickerLogged {
            this.pickerLogged := true
            AppLog.Write("PowerScribe attending picker focus: " driver.Describe(picker))
        }
        return true
    }

    static WaitForPickerFocus(session, before) {
        driver := this.attendingDriver
        deadline := driver.Now() + this.pickerTimeoutMs
        loop {
            focus := driver.FocusedControl()
            if (focus
                && focus.processId = session.processId
                && focus.type != UIA.Type.Document
                && !(focus.id == before.id))
                return focus
            if (driver.Now() >= deadline)
                return 0
            driver.Pause(50)
        }
    }
}

/**
 * Maps a report's EXAMINATION line onto a reading section.
 * The rules are evaluated in order and the first match wins, so narrower rules
 * (Peds ultrasound) must stay ahead of the broader ones (any ultrasound).
 */
class ReportModality {
    static rules := [
        {name: "Body",       pattern: "i)EXAMINATION:[\s]*((CT.*pelvis)|(XR.*abdomen)|(MRCP)|(MRI?\b.*abdomen))"},
        {name: "Chest",      pattern: "i)EXAMINATION:[\s]*((CT.*chest)|(XR.*chest))"},
        {name: "Neuro",      pattern: "i)EXAMINATION:[\s]*((CT.*((facial)|(spine)|(head)|(escape)|(neck)))|(MRI?\b.*((brain)|(spine)|(orbits)))|(MRA))"},
        {name: "Nucs",       pattern: "i)EXAMINATION:[\s]*NM"},
        {name: "Peds",       pattern: "i)EXAMINATION:[\s]*((US.*((right lower quadrant)|(neurosonography))))"},
        {name: "Ultrasound", pattern: "i)EXAMINATION:[\s]*US"},
        ; Specific Body/Chest/Neuro rules above win first. Remaining radiographs
        ; and explicitly musculoskeletal CT/MR anatomy route to MSK.
        {name: "MSK", pattern: "i)EXAMINATION:[\s]*((XR\b)|((CT|MR|MRI)\b.*(extremity|shoulder|humerus|elbow|forearm|wrist|hand|finger|thumb|hip|femur|knee|tibia|fibula|ankle|foot|toe|joint|bone|musculoskeletal|pelvis)))"}
    ]

    ; Unknown study names require manual review; they must not silently assign an
    ; unrelated attending.
    static fallback := "Unknown"

    ; Every modality that can be assigned an attending, in display order
    static names := ["Body", "Chest", "Neuro", "Nucs", "Peds", "Ultrasound", "MSK"]

    static Classify(reportText) {
        for rule in this.rules {
            if RegExMatch(reportText, rule.pattern)
                return rule.name
        }
        return this.fallback
    }
}

/**
 * Pure attending-routing policy. Profile lookup and PowerScribe mutation are passed
 * in by the workflow layer so classification and failure behavior remain testable
 * without global profile state or a live clinical application.
 */
class AttendingRouting {
    static Route(reportText, attendingLookup, attendingWriter) {
        modality := ReportModality.Classify(reportText)
        if (modality = ReportModality.fallback)
            throw Error("the examination did not match a supported modality")
        attending := attendingLookup.Call(modality)

        if (attending != "" && !attendingWriter.Call(attending))
            throw Error("attending '" attending "' cannot be selected in PowerScribe automatically")

        return modality
    }
}
