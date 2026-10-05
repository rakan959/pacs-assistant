; = CONTENTS
;   + Preamble
;   + NativeStickyNoteWindowDriver / StickyNoteOpener (Sticky Notes discovery & pinning)
;   + NativeWetReadTargetDriver / NativeWetReadControlDriver / NativeWetReadDriver (UIA note field)
;   + WetReadPasteEngine (direct write and verification; never retries or rolls back)
;   + CheckAttending, AttendingFailureMessage, RunPinnedWetReadWorkflow, WetRead,
;       PerformWetReadPaste, ConvertWetReadLineEndings, StopWetRead,
;       ReportWetReadPasteResult, WetReadPasteFailureDialog, PromptWetReadMode
;       (file-scope wet-read workflow)

#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include AppLog.ahk
#Include ClinicalNotices.ahk
#Include Settings.ahk
#Include ProfileManager.ahk
#Include PowerScribe.ahk
#Include UIAValue.ahk
#Include ErrorText.ahk

/**
 * Resolves the PACS and Sticky Notes top-level windows without relying on the
 * process-wide substring title mode. The returned HWNDs are the transaction
 * identity for every later UIA and focus check.
 */
class NativeStickyNoteWindowDriver {
    ; The title of every Sticky Notes window, new or reused.
    static stickyTitle := "Sticky Notes"

    CaptureActivePacs(target) {
        if !IsObject(target) || !HasProp(target, "title") || !HasProp(target, "exe")
            return 0

        matches := this.FindExactPacsWindows(target)
        if !IsObject(matches)
            return 0
        if (matches.Length != 1)
            return 0

        hwnd := matches[1].hwnd
        return this.ActivateWindow(hwnd) ? hwnd : 0
    }

    ; Activates one exact HWND and waits up to two seconds for it to become active.
    ActivateWindow(hwnd) {
        try {
            WinActivate("ahk_id " hwnd)
            return WinWaitActive("ahk_id " hwnd, , 2) = hwnd
        } catch {
            return false
        }
    }

    ; FindProcessWindows lists hidden windows too (every GUI thread owns a hidden
    ; IME window), and an "ahk_id" lookup finds a hidden window only while hidden
    ; windows are detected, so the title read detects them whatever the caller's
    ; setting.
    GetTitle(hwnd) {
        previousHiddenSetting := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try return WinGetTitle("ahk_id " hwnd)
        finally DetectHiddenWindows(previousHiddenSetting)
    }

    ; A disappearing or opaque same-executable window makes uniqueness uncertain,
    ; so any lookup failure yields 0 rather than a silently shortened list.
    FindExactPacsWindows(target) {
        try return AppControl.ResolveExactWindows(target)
        catch
            return 0
    }

    IsExpectedPacsSession(target, hwnd, processId) {
        if (hwnd <= 0 || processId <= 0)
            return false
        matches := this.FindExactPacsWindows(target)
        return IsObject(matches)
            && matches.Length = 1
            && matches[1].hwnd = hwnd
            && matches[1].processId = processId
    }

    GetRoot(hwnd) {
        try return UIA.ElementFromHandle("ahk_id " hwnd)
        return 0
    }

    IsActive(hwnd) {
        try return WinActive("ahk_id " hwnd) = hwnd
        return false
    }

    ; UIA-v2's semantic Click() returns the pattern it used, or 0 when no pattern
    ; actioned the element.
    InvokeStickyButton(button) {
        try return !!button.Click()
        return false
    }

    WaitForActiveSticky(processId, timeoutSeconds) {
        deadline := DllCall("GetTickCount64", "UInt64") + timeoutSeconds * 1000
        while (DllCall("GetTickCount64", "UInt64") < deadline) {
            try {
                hwnd := WinActive("A")
                if (hwnd > 0
                    && WinGetPID("ahk_id " hwnd) = processId
                    && this.GetTitle(hwnd) == NativeStickyNoteWindowDriver.stickyTitle)
                    return hwnd
            }
            Sleep(25)
        }
        return 0
    }

    GetOwner(hwnd) {
        try return DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        return 0
    }

    FindProcessWindows(processId) {
        matches := []
        previousHiddenSetting := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try {
            try windows := WinGetList("ahk_pid " processId)
            catch
                return 0
            for hwnd in windows {
                try {
                    if (WinGetPID("ahk_id " hwnd) = processId)
                        matches.Push(hwnd)
                } catch {
                    return 0
                }
            }
            return matches
        } finally DetectHiddenWindows(previousHiddenSetting)
    }

    FindExactStickyWindows(processId) {
        windows := this.FindProcessWindows(processId)
        if !IsObject(windows)
            return 0
        matches := []
        for hwnd in windows {
            try {
                if (this.GetTitle(hwnd) == NativeStickyNoteWindowDriver.stickyTitle)
                    matches.Push(hwnd)
            } catch {
                return 0
            }
        }
        return matches
    }

    IsExpectedStickySession(session) {
        if (!IsObject(session)
            || !HasProp(session, "pacsHwnd")
            || !HasProp(session, "stickyHwnd")
            || !HasProp(session, "processId")
            || !HasProp(session, "preexistingProcessWindows"))
            return false
        windows := this.FindExactStickyWindows(session.processId)
        if !IsObject(windows)
            return false
        delta := StickyNoteOpener.NewWindowDelta(
            session.preexistingProcessWindows,
            windows
        )
        return IsObject(delta)
            && delta.Length = 1
            && delta[1] = session.stickyHwnd
            && this.GetOwner(session.stickyHwnd) = session.pacsHwnd
    }

    ActivateSticky(session) {
        if !this.IsExpectedStickySession(session)
            return false
        if !this.ActivateWindow(session.stickyHwnd)
            return false
        return this.IsExpectedStickySession(session)
    }
}

class StickyNoteOpener {
    ; The Name of the PACS toolbar button that opens a Sticky Notes window. The
    ; search and the check on each result must use the same value.
    static stickyButtonName := "scn_sticky_notes"

    __New(driver := 0) {
        this.driver := driver ? driver : NativeStickyNoteWindowDriver()
    }

    Open(pacsTarget) {
        driver := this.driver
        pacsHwnd := driver.CaptureActivePacs(pacsTarget)
        if (pacsHwnd <= 0)
            return 0

        pacsRoot := driver.GetRoot(pacsHwnd)
        if !this.IsExpectedPacsRoot(pacsRoot, pacsHwnd)
            return 0
        button := this.FindUniqueStickyButton(pacsRoot)
        if !button
            return 0

        ; Reacquire the root and semantic button immediately before the click. A
        ; study/window change between discovery and action must fail closed.
        if !driver.IsActive(pacsHwnd)
            return 0
        liveRoot := driver.GetRoot(pacsHwnd)
        if !this.SamePacsRoot(pacsRoot, liveRoot, pacsHwnd)
            return 0
        button := this.FindUniqueStickyButton(liveRoot)
        if (!button
            || !driver.IsExpectedPacsSession(pacsTarget, pacsHwnd, liveRoot.ProcessId)
            || !driver.IsActive(pacsHwnd))
            return 0

        ; Newness is an HWND property, not a title property. Snapshot every
        ; top-level window in the PACS process so a hidden/untitled window cannot
        ; be reused and retitled as "Sticky Notes" after the click.
        preexistingProcessWindows := driver.FindProcessWindows(liveRoot.ProcessId)
        if !IsObject(preexistingProcessWindows)
            return 0
        if !driver.InvokeStickyButton(button)
            return 0

        ; A pre-existing, inactive Sticky Notes window cannot satisfy this wait.
        ; Capture the window that became active as a concrete HWND.
        stickyHwnd := driver.WaitForActiveSticky(liveRoot.ProcessId, 2)
        if (stickyHwnd <= 0 || stickyHwnd = pacsHwnd)
            return 0
        postClickSticky := driver.FindExactStickyWindows(liveRoot.ProcessId)
        if !IsObject(postClickSticky)
            return 0
        newSticky := StickyNoteOpener.NewWindowDelta(
            preexistingProcessWindows,
            postClickSticky
        )
        if (!IsObject(newSticky)
            || newSticky.Length != 1
            || newSticky[1] != stickyHwnd)
            return 0
        owner := driver.GetOwner(stickyHwnd)
        if (owner != pacsHwnd)
            return 0

        stickyRoot := driver.GetRoot(stickyHwnd)
        if !NativeWetReadDriver.IsExpectedStickyRoot(liveRoot, stickyRoot)
            return 0
        try {
            if (stickyRoot.WinId != stickyHwnd)
                return 0
        } catch {
            return 0
        }

        return {
            pacsHwnd: pacsHwnd,
            pacsRoot: liveRoot,
            stickyHwnd: stickyHwnd,
            stickyRoot: stickyRoot,
            processId: liveRoot.ProcessId,
            preexistingProcessWindows: preexistingProcessWindows.Clone(),
            driver: driver
        }
    }

    static NewWindowDelta(before, after) {
        if !IsObject(before) || !IsObject(after)
            return 0
        previous := Map()
        for hwnd in before {
            if (hwnd <= 0 || previous.Has(hwnd))
                return 0
            previous[hwnd] := true
        }
        delta := []
        seen := Map()
        for hwnd in after {
            if (hwnd <= 0 || seen.Has(hwnd))
                return 0
            seen[hwnd] := true
            if !previous.Has(hwnd)
                delta.Push(hwnd)
        }
        return delta
    }

    IsExpectedPacsRoot(root, hwnd) {
        try return root && hwnd > 0 && root.WinId = hwnd && root.ProcessId > 0
        return false
    }

    SamePacsRoot(expected, actual, hwnd) {
        try return this.IsExpectedPacsRoot(actual, hwnd)
            && actual.ProcessId = expected.ProcessId
        return false
    }

    FindUniqueStickyButton(root) {
        candidates := []
        try elements := root.FindElements({Name: StickyNoteOpener.stickyButtonName})
        catch
            return 0

        for element in elements {
            try {
                if (element.Name == StickyNoteOpener.stickyButtonName
                    && element.Type = UIA.Type.Button
                    && element.IsEnabled
                    && element.ProcessId = root.ProcessId
                    && element.WinId = root.WinId) {
                    candidates.Push(element)
                }
            } catch {
                ; If an exact-name candidate cannot be inspected, uniqueness is
                ; unknown. Do not silently discard it and click another candidate.
                return 0
            }
        }
        return candidates.Length = 1 ? candidates[1] : 0
    }
}

; Re-proves, right before a write, that the field is still the note field of the
; pinned Sticky Notes window.
class NativeWetReadTargetDriver {
    IsExpectedTarget(targetTitle, field) {
        try root := UIA.ElementFromHandle(targetTitle)
        catch
            return false
        return NativeWetReadDriver.IsExpectedNoteField(root, field)
    }
}

class NativeWetReadControlDriver {
    SetText(hwnd, value) {
        ControlSetText(value, hwnd)
    }
}

/**
 * Native side effects for the wet-read paste transaction. Keeping them behind this
 * small interface makes failure behavior deterministic under test.
 */
class NativeWetReadDriver {
    ; Positional path to the note field. A locator only: IsExpectedNoteField proves
    ; what it finds before anything is written.
    static noteFieldPath := "YY0/"

    __New(
        targetTitle,
        targetDriver := NativeWetReadTargetDriver(),
        controlDriver := NativeWetReadControlDriver()
    ) {
        this.targetTitle := targetTitle
        this.targetDriver := targetDriver
        this.controlDriver := controlDriver
    }

    static IsExpectedStickyRoot(pacsRoot, stickyRoot) {
        if !pacsRoot || !stickyRoot
            return false
        try {
            pacsProcess := pacsRoot.ProcessId
            return pacsProcess > 0
                && stickyRoot.ProcessId = pacsProcess
                && stickyRoot.WinId > 0
        } catch {
            return false
        }
    }

    static ForRoot(root, targetDriver := 0, controlDriver := 0) {
        hwnd := 0
        try hwnd := root.WinId
        if (hwnd <= 0)
            throw Error("Sticky Notes window handle could not be verified")
        return NativeWetReadDriver(
            "ahk_id " hwnd,
            targetDriver ? targetDriver : NativeWetReadTargetDriver(),
            controlDriver ? controlDriver : NativeWetReadControlDriver()
        )
    }

    /**
     * Positional UIA paths are permitted only as locators. Verify that the result
     * is an enabled, writable text control owned by the Sticky Notes process before
     * any paste transaction can mutate it.
     */
    static IsExpectedNoteField(root, field, comparator := 0) {
        if !this.HasExpectedNoteCapabilities(root, field)
            return false

        ; Sticky Notes exposes no stable Name/AutomationId in the recorded UIA
        ; contract. Fail closed unless the located field is the sole writable text
        ; control in that exact window; a shifted positional path can otherwise
        ; select a different Edit control that passes the structural checks below.
        eligibleCount := 0
        selectedMatch := false
        try {
            for typeName in ["Document", "Edit"] {
                for candidate in root.FindElements({Type: typeName}) {
                    if !this.InspectExpectedNoteCapabilities(root, candidate)
                        continue
                    eligibleCount++
                    if (eligibleCount > 1)
                        return false
                    if this.ElementsMatch(field, candidate, comparator)
                        selectedMatch := true
                }
            }
        } catch {
            return false
        }
        return eligibleCount = 1 && selectedMatch
    }

    static HasExpectedNoteCapabilities(root, field) {
        if !root || !field
            return false

        try return this.InspectExpectedNoteCapabilities(root, field)
        catch
            return false
    }

    static InspectExpectedNoteCapabilities(root, field) {
        rootProcess := root.ProcessId
        if (rootProcess <= 0 || field.ProcessId != rootProcess)
            return false
        rootWindow := root.WinId
        if (rootWindow <= 0 || field.WinId != rootWindow)
            return false
        if (field.Type != UIA.Type.Document && field.Type != UIA.Type.Edit)
            return false
        if !field.IsEnabled
            return false
        return field.IsValuePatternAvailable
            || field.IsLegacyIAccessiblePatternAvailable
            || field.NativeWindowHandle
    }

    static ElementsMatch(left, right, comparator := 0) {
        if comparator
            return comparator.Call(left, right) ? true : false
        try return UIA.CompareElementsEx(left, right)
        return false
    }

    Read(field) {
        if !this.targetDriver.IsExpectedTarget(this.targetTitle, field)
            throw Error("Sticky Notes value cannot be read safely")
        result := UIAValue.TryRead(field)
        if !result.supported
            throw Error("Sticky Notes value cannot be read safely")
        return result.value
    }

    WriteUIA(field, value) {
        if !this.targetDriver.IsExpectedTarget(this.targetTitle, field)
            return false
        return UIAValue.Write(field, value)
    }

    WriteControl(field, value) {
        if !this.targetDriver.IsExpectedTarget(this.targetTitle, field)
            return false
        hwnd := 0
        try hwnd := field.NativeWindowHandle
        ; ControlSetText requires a concrete ControlID in AutoHotkey v2. An empty
        ; identifier raises before mutation, so report this mode as unsupported.
        if !hwnd
            return false
        ; The HWND-targeted write does not require focus. A ControlFocus here would
        ; add a second mutation boundary, where the provider could rerender between
        ; validation and SetText, so this is exactly one validated action.
        this.controlDriver.SetText(hwnd, value)
        return true
    }

    WaitForValue(field, expected, timeoutMs) {
        started := this.NowMilliseconds()
        while (this.NowMilliseconds() - started < timeoutMs) {
            current := ""
            try current := this.Read(field)
            if (current == expected)
                return true
            this.Pause(100)
        }
        return false
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }
}

/**
 * Replaces a sticky-note value through one verified direct-write primitive. It does
 * not retry or speculatively restore after an unexpected value appears.
 */
class WetReadPasteEngine {
    static verifyTimeoutMs := 2000

    static Paste(field, text, mode, driver) {
        result := this.NewResult()
        if (mode != "uia" && mode != "control") {
            result.reason := "invalid-mode"
            result.error := "Unknown wet-read paste mode: " mode
            return result
        }

        try originalValue := driver.Read(field)
        catch as err {
            result.reason := "read"
            result.error := err.Message
            return result
        }
        return this.PasteDirect(field, text, originalValue, mode, driver, result)
    }

    static NewResult() {
        return {
            success: false,
            unsupported: false,
            ; The note is proven to still hold its original value. The engine never
            ; writes it back; this only records that nothing was changed.
            unchanged: false,
            reason: "",
            error: ""
        }
    }

    static PasteDirect(field, text, originalValue, mode, driver, result) {
        ; UIA exposes no generation token or atomic compare-and-set operation. Read
        ; the exact original value at the last safe point, perform one write, and
        ; never retry or restore after an unexpected value appears: either action
        ; could overwrite a user's newer edit.
        try currentValue := driver.Read(field)
        catch as err {
            result.reason := "precondition-read"
            result.error := err.Message
            return result
        }
        if !(currentValue == originalValue) {
            result.reason := "precondition-changed"
            result.error := "Sticky Notes changed before the write; no mutation was attempted"
            return result
        }

        wrote := false
        writeError := 0
        try wrote := mode = "uia"
            ? driver.WriteUIA(field, text)
            : driver.WriteControl(field, text)
        catch as err {
            ; Some providers throw after applying a value. Treat the state as unknown
            ; until an exact readback proves either the requested or original value.
            writeError := err
        }

        if (!wrote && !writeError) {
            result.unsupported := true
            ; The driver's unsupported result guarantees that no write occurred,
            ; and the exact original value was proven at the precondition boundary.
            result.unchanged := true
            result.reason := "unsupported"
            return result
        }

        result.unchanged := false
        if writeError {
            result.reason := "error"
            this.AppendError(result, writeError.Message)
        }

        try {
            if driver.WaitForValue(field, text, this.verifyTimeoutMs) {
                result.success := true
                return result
            }
            observedValue := driver.Read(field)
        } catch as err {
            result.reason := "verification-error"
            this.AppendError(result, err.Message)
            return result
        }

        if (observedValue == text) {
            result.success := true
            return result
        }
        if (observedValue == originalValue) {
            result.unchanged := true
            result.reason := "verification"
            return result
        }

        result.reason := "value-changed"
        this.AppendError(
            result,
            "Sticky Notes changed during verification; no retry or rollback was attempted"
        )
        return result
    }

    static AppendError(result, message) {
        result.error .= (result.error = "" ? "" : "; ") message
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
    pasteMode,
    openSticky,
    captureReport,
    routeAttending,
    pasteAction,
    notifier := 0
) {
    ; Establish the study-specific PACS target first. Later PowerScribe focus changes
    ; must never decide which Sticky Notes window receives the text.
    notify := notifier ? notifier : ObjBindMethod(ClinicalNotices, "Show")
    stickyFailure := "A new Sticky Notes window for the active Vue PACS study could not be verified. Nothing was pasted"
    reportAttempted := false
    attendingRouted := false
    attendingError := 0
    haystack := ""
    try {
        stickySession := 0
        try {
            stickySession := openSticky.Call()
        } catch Any as err {
            AppLog.WriteError(err, "Wet read stopped: the Sticky Notes target could not be verified")
            notify.Call(stickyFailure ": " ErrorText.Message(err), "Sticky Note Target Not Verified", "Icon!")
            return false
        }
        if !stickySession {
            AppLog.Write("Wet read stopped: " stickyFailure ".")
            notify.Call(stickyFailure ".", "Sticky Note Target Not Verified", "Icon!")
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

        return pasteAction.Call(clipText, pasteMode, stickySession)
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
    ; Use clipboard contents; bail out if empty to avoid blank notes
    clipText := A_Clipboard
    if (clipText = "") {
        ClinicalNotices.Show("No text in clipboard to paste as wet read.", "No Clipboard Text", "Icon!")
        return false
    }

    ; Choose paste strategy before any window focus changes
    pasteMode := PromptWetReadMode()
    if (pasteMode = "cancel")
        return false

    return RunPinnedWetReadWorkflow(
        clipText,
        pasteMode,
        (*) => StickyNoteOpener().Open(AppControl.VuePacsWindowSpec()),
        (*) => PowerScribe.CaptureReport(),
        (reportText, session) => CheckAttending(reportText, session),
        PerformWetReadPaste
    )
}

PerformWetReadPaste(clipText, pasteMode, stickySession) {
    ; Reacquire the exact new window pinned before PowerScribe routing. Never resolve
    ; Sticky Notes again by title or accept a reused/pre-existing study window.
    if (!IsObject(stickySession)
        || !HasProp(stickySession, "driver")
        || !stickySession.driver.ActivateSticky(stickySession)) {
        return StopWetRead("The pinned Sticky Notes window is no longer the verified target. Nothing was pasted.")
    }
    sticky := stickySession.driver.GetRoot(stickySession.stickyHwnd)
    if (!sticky
        || !NativeWetReadDriver.IsExpectedStickyRoot(stickySession.pacsRoot, sticky)) {
        return StopWetRead("The pinned Sticky Notes UI target could not be reacquired. Nothing was pasted.")
    }
    try {
        if (sticky.WinId != stickySession.stickyHwnd) {
            return StopWetRead("The pinned Sticky Notes UI target changed. Nothing was pasted.")
        }
    } catch {
        return StopWetRead("The pinned Sticky Notes UI target could not be verified. Nothing was pasted.")
    }
    try wetReadDriver := NativeWetReadDriver.ForRoot(sticky)
    catch {
        return StopWetRead("Sticky Notes window identity could not be pinned. Nothing was pasted.")
    }
    ; Get note input field
    noteField := ""
    try noteField := sticky.ElementFromPath(NativeWetReadDriver.noteFieldPath)
    if (!noteField) {
        ; Try another attempt after slight delay
        Sleep(200)
        try noteField := sticky.ElementFromPath(NativeWetReadDriver.noteFieldPath)
    }
    if (!noteField) {
        return StopWetRead("Could not locate the Sticky Notes text field. Nothing was pasted.")
    }
    if !NativeWetReadDriver.IsExpectedNoteField(sticky, noteField) {
        return StopWetRead("Sticky Notes returned an unexpected text target. Nothing was pasted; verify the window and try again.")
    }

    if Settings.Get("AutoConvertWetReadLineEndings")
        clipText := ConvertWetReadLineEndings(clipText)

    result := WetReadPasteEngine.Paste(
        noteField,
        clipText,
        pasteMode,
        wetReadDriver
    )

    return ReportWetReadPasteResult(result, pasteMode)
}

; Sticky Notes expects CRLF; a bare LF from the clipboard renders as one long line.
ConvertWetReadLineEndings(text) {
    return RegExReplace(text, "\r?\n", "`r`n")
}

; Ends a wet read that stopped before anything was pasted: logs the reason, shows
; it, and returns false.
StopWetRead(message) {
    AppLog.Write("Wet read stopped: " message)
    ClinicalNotices.Show(message, "Sticky Note Target Not Verified", "Icon!")
    return false
}

/**
 * Shows the dialog for a finished paste transaction and records a failure, with its
 * reason, in error.log. The note text is not logged.
 * @returns true when the paste was confirmed
 */
ReportWetReadPasteResult(result, pasteMode) {
    failure := WetReadPasteFailureDialog(result, pasteMode)
    if !failure
        return true
    AppLog.Write("Wet read paste not confirmed (" result.reason ")"
        . (result.error != "" ? ": " result.error : ""))
    ClinicalNotices.Show(failure.text, failure.title, "Icon!")
    return false
}

/**
 * The dialog that explains a finished paste transaction.
 * @param result WetReadPasteEngine.Paste result
 * @param pasteMode "uia" or "control", named in the unsupported-method message
 * @returns {text, title}, or 0 when the paste succeeded
 */
WetReadPasteFailureDialog(result, pasteMode) {
    if result.unsupported {
        method := pasteMode = "uia" ? "UIA Value" : "ControlSetText"
        return {
            text: "This Sticky Notes field does not expose a verified target for the " method " method. Run the wet read again and choose another paste method.",
            title: "Paste Method Unavailable"
        }
    }
    if result.success
        return 0
    if (result.reason = "value-changed") {
        return {
            text: "The Sticky Notes value changed while PACS Assistant was verifying the wet read. No retry or rollback was attempted, so a newer edit was not overwritten. Keep the window open and verify the note manually.",
            title: "Sticky Note Changed"
        }
    }
    if (result.reason = "precondition-changed") {
        return {
            text: "Sticky Notes changed before PACS Assistant wrote anything. No paste or rollback was attempted, so the newer note was not overwritten. Keep the window open and verify it manually.",
            title: "Sticky Note Changed"
        }
    }
    if (result.reason = "read" || result.reason = "precondition-read") {
        return {
            text: "PACS Assistant could not verify the current Sticky Notes value, so no paste or rollback was attempted. Keep the window open and verify it manually.",
            title: "Sticky Note Not Verified"
        }
    }
    if (result.reason = "verification-error") {
        return {
            text: "PACS Assistant could not read the note back after writing it, so the wet read is not confirmed. No retry or rollback was attempted. Keep the window open and check the note before pasting again.",
            title: "Sticky Note Not Verified"
        }
    }
    if result.unchanged {
        return {
            text: "The wet read was not pasted. The sticky note still matches its original value; verify it before closing the window.",
            title: "Paste Failed"
        }
    }
    return {
        text: "PACS Assistant could not confirm the wet read. Keep the window open and check the note before pasting again.",
        title: "Sticky Note Not Verified"
    }
}

PromptWetReadMode() {
    ; DPI policy: default DPIScale ON - system-DPI-aware, auto-scaled.
    modeGui := Gui("+AlwaysOnTop", "Wet Read Paste Mode")
    modeGui.Add("Text",, "Select paste method for this run:")

    ; Closing the window must never choose a mutation method implicitly.
    choice := "cancel"

    modeGui.Add("Button", "w200", "UIA Value pattern").OnEvent("Click", (*) => (choice := "uia", modeGui.Destroy()))
    modeGui.Add("Button", "w200", "ControlSetText").OnEvent("Click", (*) => (choice := "control", modeGui.Destroy()))
    modeGui.Add("Button", "w200", "Cancel").OnEvent("Click", (*) => (choice := "cancel", modeGui.Destroy()))
    ; The X button must destroy, not merely hide: WinWaitClose also returns for a
    ; hidden window, but the hidden Gui would outlive this function, kept alive by
    ; its own button callbacks.
    modeGui.OnEvent("Close", (*) => modeGui.Destroy())
    modeGui.Show()
    WinWaitClose(modeGui.Hwnd)
    return choice
}
