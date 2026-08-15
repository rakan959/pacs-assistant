#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include Settings.ahk
#Include ProfileManager.ahk
#Include PowerScribe.ahk
#Include UIAValue.ahk

class NativeWetReadFocusDriver {
    RequestFocus(field) {
        try field.SetFocus()
        try field.Click("left")
    }

    IsExpectedTarget(targetTitle, field) {
        try root := UIA.ElementFromHandle(targetTitle)
        catch
            return false
        return NativeWetReadDriver.IsExpectedNoteField(root, field)
    }

    IsExpectedFocus(targetTitle, field) {
        try {
            focused := UIA.GetFocusedElement()
            return UIA.CompareElementsEx(field, focused)
                && this.IsExpectedTarget(targetTitle, focused)
        } catch {
            return false
        }
    }
}

/**
 * Native side effects for the wet-read paste transaction. Keeping them behind this
 * small interface makes rollback behavior deterministic under test.
 */
class NativeWetReadDriver {
    __New(
        targetTitle := "Sticky Notes",
        windowDriver := NativeWindowDriver(),
        focusDriver := NativeWetReadFocusDriver()
    ) {
        this.targetTitle := targetTitle
        this.windowDriver := windowDriver
        this.focusDriver := focusDriver
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

    static ForRoot(root, windowDriver := 0, focusDriver := 0) {
        hwnd := 0
        try hwnd := root.WinId
        if (hwnd <= 0)
            throw Error("Sticky Notes window handle could not be verified")
        return NativeWetReadDriver(
            "ahk_id " hwnd,
            windowDriver ? windowDriver : NativeWindowDriver(),
            focusDriver ? focusDriver : NativeWetReadFocusDriver()
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
                    if !this.HasExpectedNoteCapabilities(root, candidate)
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

        try {
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
        } catch {
            return false
        }
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

    Focus(field) {
        if !this.windowDriver.IsActive(this.targetTitle)
            throw Error(this.targetTitle " is no longer active; focus was not changed")

        loop 3 {
            this.focusDriver.RequestFocus(field)
            if this.focusDriver.IsExpectedFocus(this.targetTitle, field)
                return true
            Sleep(50)
        }
        throw Error(this.targetTitle " expected text field did not retain focus")
    }

    Clear(field) {
        this.Focus(field)
        this.SendKeysToTarget("^a{Backspace}", field)
        Sleep(50)
    }

    CaptureClipboard() {
        return ClipboardAll()
    }

    SetClipboard(value) {
        A_Clipboard := value
    }

    WaitForClipboard(timeoutSeconds) {
        return ClipWait(timeoutSeconds)
    }

    RestoreClipboard(value) {
        A_Clipboard := value
    }

    PasteClipboard(field) {
        this.Focus(field)
        this.SendKeysToTarget("^v", field)
    }

    SendKeysToTarget(keys, field := 0) {
        if !this.windowDriver.IsActive(this.targetTitle)
            throw Error(this.targetTitle " is no longer active; no keys were sent")
        if field && !this.focusDriver.IsExpectedFocus(this.targetTitle, field)
            throw Error(this.targetTitle " expected text field lost focus; no keys were sent")
        this.windowDriver.SendKeys(keys)
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
        ; Focus is only a best-effort aid for custom controls. The HWND-targeted write
        ; does not depend on it, so a focus refusal must not be misclassified as a
        ; possibly destructive ControlSetText failure.
        try ControlFocus(hwnd)
        ControlSetText(value, hwnd)
        return true
    }

    WaitForValue(field, expected, timeoutMs) {
        started := A_TickCount
        while (A_TickCount - started < timeoutMs) {
            current := ""
            try current := this.Read(field)
            if (current = expected)
                return true
            Sleep(100)
        }
        return false
    }
}

/**
 * Replaces a sticky-note value without sacrificing the previous note or clipboard
 * on a failed paste.
 */
class WetReadPasteEngine {
    static attempts := 3
    static verifyTimeoutMs := 2000

    static Paste(field, text, mode, driver := NativeWetReadDriver()) {
        result := this.NewResult()
        try originalValue := driver.Read(field)
        catch as err {
            result.reason := "read"
            result.error := err.Message
            return result
        }

        switch mode {
            case "send":
                return this.PasteWithClipboard(field, text, originalValue, driver, result)
            case "uia", "control":
                return this.PasteDirect(field, text, originalValue, mode, driver, result)
            default:
                result.reason := "invalid-mode"
                result.error := "Unknown wet-read paste mode: " mode
                return result
        }
    }

    static NewResult() {
        return {
            success: false,
            unsupported: false,
            restored: true,
            clipboardRestored: true,
            reason: "",
            error: ""
        }
    }

    static PasteWithClipboard(field, text, originalValue, driver, result) {
        backupCaptured := false
        fieldChanged := false

        try {
            clipboardBackup := driver.CaptureClipboard()
            backupCaptured := true
            driver.SetClipboard(text)
            if !driver.WaitForClipboard(0.5) {
                result.reason := "clipboard"
                return result
            }

            loop this.attempts {
                ; Clear can mutate before it raises. Mark the transaction dirty first
                ; so every uncertain/partial clear takes the rollback path.
                fieldChanged := true
                driver.Clear(field)
                driver.PasteClipboard(field)
                if driver.WaitForValue(field, text, this.verifyTimeoutMs) {
                    result.success := true
                    return result
                }
            }
            result.reason := "verification"
        } catch as err {
            result.reason := "error"
            result.error := err.Message
        } finally {
            if (!result.success && fieldChanged)
                result.restored := this.RestoreWithClipboard(field, originalValue, driver, result)

            if backupCaptured {
                try driver.RestoreClipboard(clipboardBackup)
                catch as restoreError {
                    result.clipboardRestored := false
                    this.AppendError(result, "Clipboard restore failed: " restoreError.Message)
                }
            }
        }

        return result
    }

    static RestoreWithClipboard(field, originalValue, driver, result) {
        try {
            driver.SetClipboard(originalValue)
            if (originalValue != "" && !driver.WaitForClipboard(0.5)) {
                this.AppendError(result, "Previous note could not be staged for restoration")
                return false
            }
            driver.Clear(field)
            if (originalValue != "")
                driver.PasteClipboard(field)
            return driver.WaitForValue(field, originalValue, this.verifyTimeoutMs)
        } catch as err {
            this.AppendError(result, "Previous note restore failed: " err.Message)
            return false
        }
    }

    static PasteDirect(field, text, originalValue, mode, driver, result) {
        fieldMayHaveChanged := false

        loop this.attempts {
            priorFieldChange := fieldMayHaveChanged
            try {
                wrote := mode = "uia"
                    ? driver.WriteUIA(field, text)
                    : driver.WriteControl(field, text)

                if !wrote {
                    ; Both native adapters check target capability before changing the
                    ; field. A false result is therefore unsupported, not a failed
                    ; mutation which needs a speculative rollback.
                    result.unsupported := true
                    result.reason := "unsupported"
                    if priorFieldChange
                        result.restored := this.RestoreDirect(field, originalValue, mode, driver, result)
                    return result
                }

                fieldMayHaveChanged := fieldMayHaveChanged || wrote
                if wrote && driver.WaitForValue(field, text, this.verifyTimeoutMs) {
                    result.success := true
                    return result
                }
            } catch as err {
                fieldMayHaveChanged := true
                result.reason := "error"
                this.AppendError(result, err.Message)
            }
        }

        if (result.reason = "")
            result.reason := "verification"
        if fieldMayHaveChanged
            result.restored := this.RestoreDirect(field, originalValue, mode, driver, result)
        return result
    }

    static RestoreDirect(field, originalValue, mode, driver, result) {
        restoreModes := mode = "uia" ? ["uia", "control"] : ["control", "uia"]
        for restoreMode in restoreModes {
            try {
                restored := restoreMode = "uia"
                    ? driver.WriteUIA(field, originalValue)
                    : driver.WriteControl(field, originalValue)
                if (restored && driver.WaitForValue(field, originalValue, this.verifyTimeoutMs))
                    return true
            } catch as err {
                label := restoreMode = "uia" ? "UIA" : "ControlSetText"
                this.AppendError(result, label " restore failed: " err.Message)
            }
        }
        return false
    }

    static AppendError(result, message) {
        result.error .= (result.error = "" ? "" : "; ") message
    }
}

/**
 * Assigns the current report to the profile's attending for its modality. A blank
 * assignment leaves PowerScribe's default unchanged.
 */
checkAttending(reportText) {
    return AttendingRouting.Route(
        reportText,
        ObjBindMethod(ProfileManager, "GetModalityAttending"),
        ObjBindMethod(PowerScribe, "SetAttending")
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

	; Read current report for attending selection. A failure here must not abort the
	; wet read - the sticky note is the point - but it does get reported at the end,
	; because a report that silently keeps the wrong attending goes to the wrong queue.
	attendingRouted := false
	attendingError := 0
	haystack := readReportText()
	if (haystack != "") {
		try {
			checkAttending(haystack)
			attendingRouted := true
		} catch as err
			attendingError := err
	}

	; Activate Vue PACS and open sticky notes. Fail before emitting any keys if PACS
	; cannot be confirmed as the active target.
	pacsTitle := "Vue PACS ahk_exe mp.exe"
	if !AppControl.ActivateWindow(pacsTitle) {
		MsgBox("Could not activate Vue PACS.")
		return
	}
	Sleep(150)
	try mpEl := UIA.ElementFromHandle(pacsTitle)
	catch {
		MsgBox("Could not connect to Vue PACS accessibility controls.")
		return
	}
	pacsPid := 0
	try pacsPid := mpEl.ProcessId
	if (pacsPid <= 0) {
		MsgBox("Vue PACS process identity could not be verified.")
		return
	}
	try {
		mpEl.FindElement({Name:"scn_sticky_notes"}).Click()
	} catch {
		MsgBox("Could not find Sticky Notes button in PACS.")
		return
	}

	; Bind the dialog to the PACS process. A plain title could match an unrelated
	; same-title window and turn that window into the trusted root for later writes.
	stickyTitle := "Sticky Notes ahk_pid " pacsPid
	if !WinWait(stickyTitle, , 2) {
		MsgBox("Sticky Notes window did not appear.")
		return
	}

	try sticky := UIA.ElementFromHandle(stickyTitle)
	catch {
		MsgBox("Could not connect to the Sticky Notes window.")
		return
	}
	if !NativeWetReadDriver.IsExpectedStickyRoot(mpEl, sticky) {
		MsgBox("Sticky Notes did not belong to the active Vue PACS process. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
		return
	}
	try wetReadDriver := NativeWetReadDriver.ForRoot(sticky)
	catch {
		MsgBox("Sticky Notes window identity could not be pinned. Nothing was pasted.", "Sticky Note Target Not Verified", "Icon!")
		return
	}
	try sticky.SetFocus()

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
		if !result.restored {
			MsgBox("The wet read failed and PACS Assistant could not restore the previous sticky note. Keep the window open and verify the note manually.", "Sticky Note Restore Failed", "Icon!")
		} else if (result.reason = "clipboard") {
			MsgBox("The wet read was not pasted because the clipboard did not become ready. The previous sticky note was left unchanged.", "Clipboard Not Ready", "Icon!")
		} else {
			MsgBox("The wet read was not pasted. The previous sticky note was restored; verify it before closing the window.", "Paste Failed", "Icon!")
		}
	}

	if !result.clipboardRestored {
		MsgBox("The wet read operation could not restore the clipboard. Copy any needed clipboard content again.", "Clipboard Restore Failed", "Icon!")
	}

	if !attendingRouted {
		MsgBox(AttendingFailureMessage(haystack, attendingError), "Attending Not Assigned", "Icon!")
	}
	Return
}

PromptWetReadMode() {
	modeGui := Gui("+AlwaysOnTop", "Wet Read Paste Mode")
	modeGui.Add("Text",, "Select paste method for this run:")

	; Default to cancelling. Closing the window with the X leaves whatever this holds,
	; and defaulting to "send" meant dismissing the dialog silently went ahead and
	; pasted rather than backing out.
	choice := "cancel"

	modeGui.Add("Button", "w200", "Original (Ctrl+V)").OnEvent("Click", (*) => (choice := "send", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "UIA Value pattern").OnEvent("Click", (*) => (choice := "uia", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "ControlSetText").OnEvent("Click", (*) => (choice := "control", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "Cancel").OnEvent("Click", (*) => (choice := "cancel", modeGui.Destroy()))
	modeGui.Show()
	WinWaitClose(modeGui.Hwnd)
	return choice
}
