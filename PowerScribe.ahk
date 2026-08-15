#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include UIAValue.ahk

class NativePowerScribeSessionDriver {
    Capture(selector) {
        if !AppControl.ActivateWindow(selector)
            return 0
        try hwnd := WinActive(selector)
        catch
            return 0
        return this.SessionFromHandle(hwnd)
    }

    SessionFromHandle(hwnd) {
        if (hwnd <= 0)
            return 0
        target := "ahk_id " hwnd
        try {
            if !WinExist(target)
                return 0
            title := WinGetTitle(target)
            executable := WinGetProcessName(target)
            processId := WinGetPID(target)
        } catch {
            return 0
        }
        if (!(title == AppControl.powerScribeReportingTitle)
            || StrCompare(executable, AppControl.powerScribeExecutable, false) != 0
            || processId <= 0)
            return 0
        return {hwnd: hwnd, target: target, processId: processId}
    }

    IsLive(session) {
        if (!IsObject(session)
            || !HasProp(session, "hwnd")
            || !HasProp(session, "target")
            || !HasProp(session, "processId"))
            return false
        current := this.SessionFromHandle(session.hwnd)
        return current
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
            expected := this.UniqueExpectedControl(root)
            if !expected
                return 0
            if !UIA.CompareElementsEx(expected, control)
                return 0
            return NativeAttendingControlDriver.IsExpectedControl(root, control) ? control : 0
        } catch {
            return 0
        }
    }

    ExpectedControls(root) {
        matches := []
        for typeName in ["Edit", "ComboBox"] {
            for candidate in root.FindElements({Type: typeName}) {
                if NativeAttendingControlDriver.IsExpectedControl(root, candidate)
                    matches.Push(candidate)
            }
        }
        return matches
    }

    UniqueExpectedControl(root) {
        try matches := this.ExpectedControls(root)
        catch
            return 0
        return matches.Length = 1 ? matches[1] : 0
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
            expected := this.UniqueExpectedControl(root)
            return expected
                && UIA.CompareElementsEx(expected, control)
                && UIA.CompareElementsEx(control, focused)
                && NativeAttendingControlDriver.IsExpectedControl(root, focused)
        } catch {
            return false
        }
    }

    CanConfirm(windowTitle, control, expected) {
        return this.ControlHasExpectedFocus(windowTitle, control)
            && this.HasExpectedValue(control, expected)
    }

    WaitForPickerAbsent(windowTitle) {
        loop NativeAttendingControlDriver.confirmationAttempts {
            try root := UIA.ElementFromHandle(windowTitle)
            catch
                return false
            if this.PickerIsAbsentFromRoot(root)
                return true
            Sleep(NativeAttendingControlDriver.confirmationPollMs)
        }
        return false
    }

    PickerIsAbsentFromRoot(root) {
        try return this.ExpectedControls(root).Length = 0
        catch
            return false
    }

    WaitForStableExpectedValue(windowTitle, control, expected) {
        stableReads := 0
        loop NativeAttendingControlDriver.confirmationAttempts {
            if this.CanConfirm(windowTitle, control, expected) {
                stableReads++
                if (stableReads >= 2)
                    return true
            } else {
                stableReads := 0
            }
            Sleep(NativeAttendingControlDriver.confirmationPollMs)
        }
        return false
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
            elements := ""
            try {
                elements := root.FindElements(condition)
            } catch {
                continue
            }

            for el in elements {
                if !this.IsExpectedReportControl(root, el)
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
            fallbackElement := root.ElementFromPath(this.reportPath)
            if this.IsExpectedReportControl(root, fallbackElement)
                fallbackText := UIAValue.Read(fallbackElement)
        }

        if !this.sessionDriver.IsLive(session)
            return ""
        return this.SelectReportText(candidates, fallbackText)
    }

    static ReportMatches(session, expectedReportText) {
        if (expectedReportText = "")
            return false
        current := this.ReadReportText(session)
        return current != "" && current == expectedReportText
    }

    static SetAttending(attending, session := 0, expectedReportText := "") {
        if !session {
            capture := this.CaptureReport()
            session := capture.session
            if (expectedReportText = "")
                expectedReportText := capture.text
        } else if (expectedReportText = "" && HasProp(session, "reportText")) {
            expectedReportText := session.reportText
        }
        if !session || !this.sessionDriver.IsLive(session)
            return false
        if !this.ReportMatches(session, expectedReportText)
            return false
        target := session.target
        if !AppControl.ActivateWindow(target)
            return false
        if !this.sessionDriver.IsLive(session)
            return false

        driver := AppControl.windowDriver
        try {
            if !AppControl.SendKeysToActiveWindow(target, "{Alt down}ta{Alt up}")
                return false
            driver.Pause(100)
            if !this.ReportMatches(session, expectedReportText)
                return false

            ; The shortcut is only a locator action. Prove the focused element is
            ; PowerScribe's writable attending field before placing clinical data.
            control := this.attendingControlDriver.FindExpectedControl(target)
            if !control
                return false
            if !driver.IsActive(target)
                return false
            if !this.attendingControlDriver.WriteAndVerify(target, control, attending)
                return false

            driver.Pause(100)
            if !this.ReportMatches(session, expectedReportText)
                return false
            if !this.attendingControlDriver.CanConfirm(target, control, attending)
                return false
            if !AppControl.SendKeysToActiveWindow(
                target,
                "{tab}{space}{tab}{Enter}"
            )
                return false
            ; Closing the original picker proves only that the UI changed. Reopen the
            ; same semantic picker and read the committed value back before reporting
            ; success; a cancelled or rerendered picker therefore fails closed.
            if !this.attendingControlDriver.WaitForPickerAbsent(target)
                return false
            if !this.ReportMatches(session, expectedReportText)
                return false
            if !AppControl.SendKeysToActiveWindow(
                target,
                "{Alt down}ta{Alt up}"
            )
                return false
            driver.Pause(100)

            verificationControl := this.attendingControlDriver.FindExpectedControl(target)
            if !verificationControl
                return false
            committed := this.attendingControlDriver.WaitForStableExpectedValue(
                target,
                verificationControl,
                attending
            )
            if !this.ReportMatches(session, expectedReportText)
                return false

            ; Escape is safe only while the unique verified attending field retains
            ; focus in the exact reporting window. Always dismiss a safely identified
            ; verification picker, even when its readback exposed a failed commit.
            if !this.attendingControlDriver.CanConfirm(
                target,
                verificationControl,
                attending
            )
                return false
            if !AppControl.SendKeysToActiveWindow(target, "{Escape}")
                return false
            if !this.attendingControlDriver.WaitForPickerAbsent(target)
                return false
            return committed
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
    return PowerScribe.CaptureReport().text
}
