#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include UIAValue.ahk

class NativePowerScribeSessionDriver {
    Capture(*) {
        try session := AppControl.ResolveUniqueExactWindow(
            AppControl.PowerScribeWindowSpec()
        )
        catch
            return 0
        if !session || !AppControl.ActivateWindow(session.target)
            return 0
        if !AppControl.ExactSessionIsUniqueAndLive(session)
            return 0
        return session
    }

    SessionFromHandle(hwnd) {
        if (hwnd <= 0)
            return 0
        target := "ahk_id " hwnd
        try {
            title := AppControl.windowDriver.GetTitle(hwnd)
            executable := AppControl.windowDriver.GetProcessName(hwnd)
            processId := AppControl.windowDriver.GetProcessId(hwnd)
        } catch {
            return 0
        }
        if (!(title == AppControl.powerScribeReportingTitle)
            || StrCompare(executable, AppControl.powerScribeExecutable, false) != 0
            || processId <= 0)
            return 0
        return {
            hwnd: hwnd,
            target: target,
            processId: processId,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable
        }
    }

    IsLive(session) {
        if (!IsObject(session)
            || !HasProp(session, "hwnd")
            || !HasProp(session, "target")
            || !HasProp(session, "processId"))
            return false
        current := this.SessionFromHandle(session.hwnd)
        return current
            && AppControl.ExactSessionIsUniqueAndLive(current)
            && current.hwnd = session.hwnd
            && current.processId = session.processId
            && current.target == session.target
    }

    Root(session) {
        if !this.IsLive(session)
            return 0
        try root := UIA.ElementFromHandle(session.target)
        catch
            return 0
        try {
            return root.WinId = session.hwnd && root.ProcessId = session.processId
                ? root
                : 0
        } catch {
            return 0
        }
    }
}

/**
 * The PowerScribe report itself: locating it, reading it, and routing it to an
 * attending. Split out of PACSCommands, which had become the command registry plus
 * every workflow's implementation in one file.
 */
class PowerScribe {
    static windowTitle := AppControl.PacsGracefulCloseTarget()
    static sessionDriver := NativePowerScribeSessionDriver()

    ; Positional path to the report text. Brittle - kept only as a last resort behind
    ; a property-based lookup.
    static reportPath := "YYYYV"

    ; Whether a piece of text reads like a report body rather than some other field
    static LooksLikeReport(text) {
        return RegExMatch(text, "i)EXAMINATION:") > 0
    }

    /**
     * Chooses report text only when every discovered report-shaped control agrees.
     * A history/prior-report pane can expose another EXAMINATION block in the same
     * window; choosing the first one could route the current study to its attending.
     */
    static SelectReportText(candidates, fallbackText := "") {
        reports := []
        for text in candidates {
            if this.LooksLikeReport(text)
                this.AddDistinctReport(reports, text)
        }
        if this.LooksLikeReport(fallbackText)
            this.AddDistinctReport(reports, fallbackText)
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

    static CaptureReport() {
        session := this.sessionDriver.Capture(this.windowTitle)
        if !session
            return {text: "", session: 0}
        text := this.ReadReportText(session)
        if (text != "")
            session.reportText := text
        return {text: text, session: session}
    }

    static ReadReportText(session) {
        root := this.sessionDriver.Root(session)
        if !root
            return ""

        ; The report editor presents as a Document, but has been seen as a plain Edit.
        candidates := []
        for condition in [{Type: "Document"}, {Type: "Edit"}] {
            try {
                elements := root.FindElements(condition)
            } catch {
                return ""
            }

            for el in elements {
                ; A returned candidate that cannot be fully identified/read makes
                ; the current-report set unknowable; never route from the remainder.
                try {
                    if !this.InspectExpectedReportControl(root, el)
                        return ""
                    readResult := UIAValue.TryRead(el)
                    if !readResult.supported
                        return ""
                    text := readResult.value
                } catch {
                    return ""
                }
                if (text = "")
                    continue
                candidates.Push(text)
            }
        }

        ; A positional result is another candidate, never an override. It must resolve
        ; to the same exact PowerScribe window and agree with the unique typed report.
        fallbackText := ""
        try {
            fallbackElement := root.ElementFromPath(this.reportPath)
            if this.IsExpectedReportControl(root, fallbackElement) {
                fallbackResult := UIAValue.TryRead(fallbackElement)
                if !fallbackResult.supported
                    return ""
                fallbackText := fallbackResult.value
            }
        }

        if !this.sessionDriver.IsLive(session)
            return ""
        return this.SelectReportText(candidates, fallbackText)
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

    static SetAttending(*) {
        ; A live PowerScribe capture has not established stable semantic identities
        ; for both the attending picker and its confirmation action. Until it does,
        ; routing remains read-only and callers report that assignment is manual.
        return false
    }
}

/**
 * Maps a report's EXAMINATION line onto a reading section.
 * The rules are evaluated in order and the first match wins, so narrower rules
 * (Peds ultrasound) must stay ahead of the broader ones (any ultrasound).
 */
class ReportModality {
    static rules := [
        {name: "Body",       pattern: "i)EXAMINATION:[\s]*((CT.*pelvis)|(XR.*abdomen)|(MRCP)|(MRI.*abdomen))"},
        {name: "Chest",      pattern: "i)EXAMINATION:[\s]*((CT.*chest)|(XR.*chest))"},
        {name: "Neuro",      pattern: "i)EXAMINATION:[\s]*((CT.*((facial)|(spine)|(head)|(escape)|(neck)))|(MRI.*((brain)|(spine)|(orbits)))|(MRA))"},
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

sendPs(x) {
    return PowerScribe.SendKeys(x)
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
            throw Error("The examination did not match a supported modality; assign the attending manually")
        attending := attendingLookup.Call(modality)

        if (attending != "" && !attendingWriter.Call(attending))
            throw Error(
                "PACS Assistant could not safely assign attending '" attending
                "'. Assign that attending manually in PowerScribe."
            )

        return modality
    }
}
