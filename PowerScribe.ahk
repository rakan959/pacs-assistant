#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include UIAValue.ahk

; Attending-picker target validation. This keeps focus-sensitive clinical input
; behind a semantic UIA identity check and an observable write postcondition.
class NativeAttendingControlDriver {
    static confirmationAttempts := 10
    static confirmationPollMs := 50

    __New(focusVerifier := 0) {
        this.focusVerifier := focusVerifier
    }

    FindExpectedControl(windowTitle) {
        try {
            root := UIA.ElementFromHandle(windowTitle)
            control := UIA.GetFocusedElement()
            return NativeAttendingControlDriver.IsExpectedControl(root, control)
                ? control
                : 0
        } catch {
            return 0
        }
    }

    static IsExpectedControl(root, control) {
        if !root || !control
            return false

        try {
            rootProcess := root.ProcessId
            if (rootProcess <= 0 || control.ProcessId != rootProcess)
                return false
            rootWindow := root.WinId
            if (rootWindow <= 0 || control.WinId != rootWindow)
                return false
            if (control.Type != UIA.Type.Edit && control.Type != UIA.Type.ComboBox)
                return false
            if !control.IsEnabled
                return false

            identity := control.Name " " control.AutomationId
            if !InStr(StrLower(identity), "attend")
                return false

            ; Direct mutation is permitted only through ValuePattern. Avoid falling
            ; back to SendText, which could land in the report if focus moved.
            return control.IsValuePatternAvailable
        } catch {
            return false
        }
    }

    WriteAndVerify(windowTitle, control, expected) {
        if !this.ControlHasExpectedFocus(windowTitle, control)
            return false

        try root := UIA.ElementFromHandle(windowTitle)
        catch
            return false
        if !NativeAttendingControlDriver.IsExpectedControl(root, control)
            return false

        try {
            if !UIAValue.Write(control, expected)
                return false
        } catch {
            return false
        }

        return this.HasExpectedValue(control, expected)
    }

    HasExpectedValue(control, expected) {
        try result := UIAValue.TryRead(control)
        catch
            return false
        if !result.supported
            return false

        actual := StrLower(Trim(result.value))
        expected := StrLower(Trim(expected))
        return expected != "" && actual = expected
    }

    ControlHasExpectedFocus(windowTitle, control) {
        if this.focusVerifier
            return this.focusVerifier.Call(windowTitle, control) ? true : false

        try {
            root := UIA.ElementFromHandle(windowTitle)
            focused := UIA.GetFocusedElement()
            return UIA.CompareElementsEx(control, focused)
                && NativeAttendingControlDriver.IsExpectedControl(root, focused)
        } catch {
            return false
        }
    }

    CanConfirm(windowTitle, control, expected) {
        return this.ControlHasExpectedFocus(windowTitle, control)
            && this.HasExpectedValue(control, expected)
    }

    WaitForConfirmation(windowTitle, control) {
        loop NativeAttendingControlDriver.confirmationAttempts {
            if this.ConfirmationControlClosed(windowTitle, control)
                return true
            Sleep(NativeAttendingControlDriver.confirmationPollMs)
        }
        return false
    }

    ConfirmationControlClosed(windowTitle, control) {
        try root := UIA.ElementFromHandle(windowTitle)
        catch
            return false

        try {
            for typeName in ["Edit", "ComboBox"] {
                for candidate in root.FindElements({Type: typeName}) {
                    if UIA.CompareElementsEx(control, candidate)
                        return false
                }
            }
            ; A complete, successful traversal that no longer contains the exact
            ; picker is the observable postcondition that its confirmation UI closed.
            return true
        } catch {
            return false
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
    static attendingControlDriver := NativeAttendingControlDriver()

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
        try {
            rootProcess := root.ProcessId
            rootWindow := root.WinId
            return rootProcess > 0
                && control.ProcessId = rootProcess
                && rootWindow > 0
                && control.WinId = rootWindow
                && (control.Type = UIA.Type.Document || control.Type = UIA.Type.Edit)
        } catch {
            return false
        }
    }

    static SendKeys(keys) {
        return AppControl.SendKeysToWindow(this.windowTitle, keys)
    }

    static SetAttending(attending) {
        if !AppControl.ActivateWindow(this.windowTitle)
            return false

        driver := AppControl.windowDriver
        try {
            if !AppControl.SendKeysToActiveWindow(this.windowTitle, "{Alt down}ta{Alt up}")
                return false
            driver.Pause(100)

            ; The shortcut is only a locator action. Prove the focused element is
            ; PowerScribe's writable attending field before placing clinical data.
            control := this.attendingControlDriver.FindExpectedControl(this.windowTitle)
            if !control
                return false
            if !driver.IsActive(this.windowTitle)
                return false
            if !this.attendingControlDriver.WriteAndVerify(this.windowTitle, control, attending)
                return false

            driver.Pause(100)
            if !this.attendingControlDriver.CanConfirm(this.windowTitle, control, attending)
                return false
            if !AppControl.SendKeysToActiveWindow(
                this.windowTitle,
                "{tab}{space}{tab}{Enter}"
            )
                return false
            return this.attendingControlDriver.WaitForConfirmation(
                this.windowTitle,
                control
            )
        } catch {
            return false
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
            throw Error("Attending could not be assigned because PACS Assistant could not safely control PowerScribe")

        return modality
    }
}

/**
 * Reads the text of the report currently open in PowerScribe.
 *
 * The report control used to be addressed by a fixed positional path. When
 * PowerScribe's element tree shifted, that path stopped resolving and threw, taking
 * the whole wet read down with it - the sticky note never got pasted either
 * (issue #28). Candidates are matched on their control type instead, and the one
 * whose text actually reads like a report wins; the positional path is only a last
 * resort.
 *
 * @returns the report text, or "" if it could not be read
 */
readReportText() {
    try {
        root := UIA.ElementFromHandle(PowerScribe.windowTitle)
    } catch {
        return ""
    }

    ; The report editor presents as a Document, but has been seen as a plain Edit.
    candidates := []
    for condition in [{Type: "Document"}, {Type: "Edit"}] {
        elements := ""
        try {
            elements := root.FindElements(condition)
        } catch {
            continue
        }

        for el in elements {
            if !PowerScribe.IsExpectedReportControl(root, el)
                continue
            text := ""
            try text := UIAValue.Read(el)
            if (text = "")
                continue
            candidates.Push(text)
        }
    }

    ; A positional result is another candidate, never an override. It must resolve
    ; to the same exact PowerScribe window and agree with the unique typed report.
    fallbackText := ""
    try {
        fallbackElement := root.ElementFromPath(PowerScribe.reportPath)
        if PowerScribe.IsExpectedReportControl(root, fallbackElement)
            fallbackText := UIAValue.Read(fallbackElement)
    }

    return PowerScribe.SelectReportText(candidates, fallbackText)
}
