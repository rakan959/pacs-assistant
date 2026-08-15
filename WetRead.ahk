#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include Settings.ahk
#Include ProfileManager.ahk
#Include PowerScribe.ahk
#Include UIAValue.ahk

/**
 * Resolves the PACS and Sticky Notes top-level windows without relying on the
 * process-wide substring title mode. The returned HWNDs are the transaction
 * identity for every later UIA and focus check.
 */
class NativeStickyNoteWindowDriver {
    CaptureActivePacs(target) {
        if !IsObject(target) || !HasProp(target, "title") || !HasProp(target, "exe")
            return 0

        matches := this.FindExactPacsWindows(target)
        if !IsObject(matches)
            return 0
        if (matches.Length != 1)
            return 0

        hwnd := matches[1].hwnd
        try {
            WinActivate("ahk_id " hwnd)
            return WinWaitActive("ahk_id " hwnd, , 2) = hwnd ? hwnd : 0
        } catch {
            return 0
        }
    }

    FindExactPacsWindows(target) {
        matches := []
        try windows := WinGetList("ahk_exe " target.exe)
        catch
            return 0

        for hwnd in windows {
            try {
                title := WinGetTitle("ahk_id " hwnd)
                processName := WinGetProcessName("ahk_id " hwnd)
                processId := WinGetPID("ahk_id " hwnd)
            } catch {
                ; A disappearing/opaque same-process window makes uniqueness
                ; uncertain. Do not silently exclude it from the candidate set.
                return 0
            }
            if (title == target.title && StrLower(processName) == StrLower(target.exe))
                matches.Push({hwnd: hwnd, processId: processId})
        }
        return matches
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

    InvokeStickyButton(button) {
        try {
            button.Click()
            return true
        } catch {
            return false
        }
    }

    WaitForActiveSticky(processId, timeoutSeconds) {
        deadline := DllCall("GetTickCount64", "UInt64") + timeoutSeconds * 1000
        while (DllCall("GetTickCount64", "UInt64") < deadline) {
            try {
                hwnd := WinActive("A")
                if (hwnd > 0
                    && WinGetPID("ahk_id " hwnd) = processId
                    && WinGetTitle("ahk_id " hwnd) == "Sticky Notes")
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
                if (WinGetTitle("ahk_id " hwnd) == "Sticky Notes")
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
        try {
            WinActivate("ahk_id " session.stickyHwnd)
            if (WinWaitActive("ahk_id " session.stickyHwnd, , 2) != session.stickyHwnd)
                return false
        } catch {
            return false
        }
        return this.IsExpectedStickySession(session)
    }
}

class StickyNoteOpener {
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
        try elements := root.FindElements({Name: "scn_sticky_notes"})
        catch
            return 0

        for element in elements {
            try {
                if (element.Name == "scn_sticky_notes"
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

class NativeWetReadFocusDriver {
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
 * small interface makes rollback behavior deterministic under test.
 */
class NativeWetReadDriver {
    __New(
        targetTitle := "Sticky Notes",
        focusDriver := NativeWetReadFocusDriver(),
        controlDriver := NativeWetReadControlDriver()
    ) {
        this.targetTitle := targetTitle
        this.focusDriver := focusDriver
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

    static ForRoot(root, focusDriver := 0, controlDriver := 0) {
        hwnd := 0
        try hwnd := root.WinId
        if (hwnd <= 0)
            throw Error("Sticky Notes window handle could not be verified")
        return NativeWetReadDriver(
            "ahk_id " hwnd,
            focusDriver ? focusDriver : NativeWetReadFocusDriver(),
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
        if !this.focusDriver.IsExpectedTarget(this.targetTitle, field)
            throw Error("Sticky Notes value cannot be read safely")
        result := UIAValue.TryRead(field)
        if !result.supported
            throw Error("Sticky Notes value cannot be read safely")
        return result.value
    }

    WriteUIA(field, value) {
        if !this.focusDriver.IsExpectedTarget(this.targetTitle, field)
            return false
        return UIAValue.Write(field, value)
    }

    WriteControl(field, value) {
        if !this.focusDriver.IsExpectedTarget(this.targetTitle, field)
            return false
        hwnd := 0
        try hwnd := field.NativeWindowHandle
        ; ControlSetText requires a concrete ControlID in AutoHotkey v2. An empty
        ; identifier raises before mutation, so report this mode as unsupported rather
        ; than entering rollback and claiming an untouched note could not be restored.
        if !hwnd
            return false
        ; The HWND-targeted write does not require focus. A best-effort ControlFocus
        ; here created a second mutation boundary where the provider could rerender
        ; after validation and before SetText, so do exactly one validated action.
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
            Sleep(100)
        }
        return false
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }
}

/**
 * Replaces a sticky-note value through a verified direct-write primitive and
 * restores the previous note if verification fails.
 */
class WetReadPasteEngine {
    static verifyTimeoutMs := 2000

    static Paste(field, text, mode, driver := NativeWetReadDriver()) {
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
            restored: true,
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
            result.reason := "unsupported"
            return result
        }

        result.restored := false
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
            result.restored := true
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
 * Assigns the current report to the profile's attending for its modality. A blank
 * assignment leaves PowerScribe's default unchanged.
 */
checkAttending(reportText, powerScribeSession := 0) {
    return AttendingRouting.Route(
        reportText,
        ObjBindMethod(ProfileManager, "GetModalityAttending"),
        (attending) => PowerScribe.SetAttending(attending, powerScribeSession, reportText)
    )
}

AttendingFailureMessage(reportText, routingError := 0) {
	if (reportText = "")
		return "Could not read the report from PowerScribe, so the attending was not assigned. Set it manually."

	if routingError {
		detail := IsObject(routingError) && HasProp(routingError, "Message")
			? routingError.Message
			: String(routingError)
		return "The report was read, but the attending could not be assigned: " detail ". Set it manually."
	}

	return "The report was read, but no attending was assigned. Set it manually."
}

RunWetReadPasteWithAttendingOutcome(
	pasteAction,
	attendingRouted,
	reportText,
	routingError := 0,
	notifier := 0
) {
	; The sticky workflow contains several legitimate fail-closed early returns. Keep
	; attending outcome reporting outside that control flow so none of those exits can
	; suppress the clinically distinct manual-routing warning.
	try return pasteAction.Call()
	finally {
		if !attendingRouted {
			message := AttendingFailureMessage(reportText, routingError)
			if notifier
				notifier.Call(message, "Attending Not Assigned", "Icon!")
			else
				MsgBox(message, "Attending Not Assigned", "Icon!")
		}
	}
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
	stickySession := openSticky.Call()
	if !stickySession {
		message := "A new Sticky Notes window for the active Vue PACS study could not be verified. Nothing was pasted."
		if notifier
			notifier.Call(message, "Sticky Note Target Not Verified", "Icon!")
		else
			MsgBox(message, "Sticky Note Target Not Verified", "Icon!")
		return RunWetReadPasteWithAttendingOutcome(
			(*) => false,
			false,
			"",
			0,
			notifier
		)
	}

	attendingRouted := false
	attendingError := 0
	reportCapture := captureReport.Call()
	haystack := reportCapture.text
	if (haystack != "") {
		try {
			routeAttending.Call(haystack, reportCapture.session)
			attendingRouted := true
		} catch as err
			attendingError := err
	}

	return RunWetReadPasteWithAttendingOutcome(
		pasteAction.Bind(clipText, pasteMode, stickySession),
		attendingRouted,
		haystack,
		attendingError,
		notifier
	)
}

wetRead() {
	; Use clipboard contents; bail out if empty to avoid blank notes
	clipText := A_Clipboard
	if (clipText = "") {
		MsgBox("No text in clipboard to paste as wet read.")
		return
	}

	; Choose paste strategy before any window focus changes
	pasteMode := PromptWetReadMode()
	if (pasteMode = "cancel") {
		return
	}

	return RunPinnedWetReadWorkflow(
		clipText,
		pasteMode,
		(*) => StickyNoteOpener().Open({title: "Vue PACS", exe: "mp.exe"}),
		(*) => PowerScribe.CaptureReport(),
		(reportText, session) => checkAttending(reportText, session),
		PerformWetReadPaste
	)
}

PerformWetReadPaste(clipText, pasteMode, stickySession) {
	; Reacquire the exact new window pinned before PowerScribe routing. Never resolve
	; Sticky Notes again by title or accept a reused/pre-existing study window.
	if (!IsObject(stickySession)
		|| !HasProp(stickySession, "driver")
		|| !stickySession.driver.ActivateSticky(stickySession)) {
		MsgBox("The pinned Sticky Notes window is no longer the verified target. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
		return
	}
	sticky := stickySession.driver.GetRoot(stickySession.stickyHwnd)
	if (!sticky
		|| !NativeWetReadDriver.IsExpectedStickyRoot(stickySession.pacsRoot, sticky)) {
		MsgBox("The pinned Sticky Notes UI target could not be reacquired. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
		return
	}
	try {
		if (sticky.WinId != stickySession.stickyHwnd) {
			MsgBox("The pinned Sticky Notes UI target changed. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
			return
		}
	} catch {
		MsgBox("The pinned Sticky Notes UI target could not be verified. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
		return
	}
	try wetReadDriver := NativeWetReadDriver.ForRoot(sticky)
	catch {
		MsgBox("Sticky Notes window identity could not be pinned. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
		return
	}
	; Get note input field
	noteField := ""
	try noteField := sticky.ElementFromPath("YY0/")
	if (!noteField) {
		; Try another attempt after slight delay
		Sleep(200)
		try noteField := sticky.ElementFromPath("YY0/")
	}
	if (!noteField) {
		MsgBox("Could not locate Sticky Notes text field.")
		return
	}
	if !NativeWetReadDriver.IsExpectedNoteField(sticky, noteField) {
		MsgBox("Sticky Notes returned an unexpected text target. Nothing was pasted; verify the window and try again.", "Sticky Note Target Not Verified", "Icon!")
		return
	}

	; Optionally normalize line endings to CRLF for sticky note field
	if (Settings.Get("AutoConvertWetReadLineEndings")) {
		clipText := RegExReplace(clipText, "(\r)?\n", "`r`n")
	}

	result := WetReadPasteEngine.Paste(
		noteField,
		clipText,
		pasteMode,
		wetReadDriver
	)

	if result.unsupported {
		method := pasteMode = "uia" ? "UIA Value" : "ControlSetText"
		MsgBox("This Sticky Notes field does not expose a verified target for the " method " method. Run the wet read again and choose another paste method.", "Paste Method Unavailable", "Icon!")
	} else if !result.success {
		if (result.reason = "value-changed") {
			MsgBox("The Sticky Notes value changed while PACS Assistant was verifying the wet read. No retry or rollback was attempted, so a newer edit was not overwritten. Keep the window open and verify the note manually.", "Sticky Note Changed", "Icon!")
		} else if !result.restored {
			MsgBox("The wet read failed and PACS Assistant could not restore the previous sticky note. Keep the window open and verify the note manually.", "Sticky Note Restore Failed", "Icon!")
		} else {
			MsgBox("The wet read was not pasted. The previous sticky note was restored; verify it before closing the window.", "Paste Failed", "Icon!")
		}
	}

	Return
}

PromptWetReadMode() {
	modeGui := Gui("+AlwaysOnTop", "Wet Read Paste Mode")
	modeGui.Add("Text",, "Select paste method for this run:")

	; Closing the window must never choose a mutation method implicitly.
	choice := "cancel"

	modeGui.Add("Button", "w200", "UIA Value pattern").OnEvent("Click", (*) => (choice := "uia", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "ControlSetText").OnEvent("Click", (*) => (choice := "control", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "Cancel").OnEvent("Click", (*) => (choice := "cancel", modeGui.Destroy()))
	modeGui.Show()
	WinWaitClose(modeGui.Hwnd)
	return choice
}
