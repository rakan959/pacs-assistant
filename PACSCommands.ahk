#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include MicrophoneManager.ahk

class PACSCommands {
    static commands := Map(
        "Toggle Dictation", (*) => sendPs("{F4}"),
        "Select Next Field", (*) => (WinActivate("PowerScribe"), Send("{Tab}")),
        "Select Previous Field", (*) => (WinActivate("PowerScribe"), Send("+{Tab}")),
        "Delete Previous Word", (*) => (WinActivate("PowerScribe"), Send("^{Backspace}")),
        "Delete Next Word", (*) => (WinActivate("PowerScribe"), Send("^{Delete}")),
        "Draft Report", (*) => sendPs("{F9}"),
        "Sign Report", (*) => sendPs("{F12}"),
        "Open/Force Restart PACS", (*) => restartPACS(),
        "Paste Wet Read", (*) => wetRead(),
        "Toggle PowerScribe Window", (*) => toggleWindow("PowerScribe"),
        "Toggle EPIC Window", (*) => toggleWindow("Hyperspace"),
        "Next Series", (*) => (WinActivate("Vue PACS Client"), Send("{Right}")),
        "Previous Series", (*) => (WinActivate("Vue PACS Client"), Send("{Left}")),
        "Set PowerScribe Microphone", (*) => MicrophoneManager.ApplyNow()
    )

    ; A window title or body that looks like an unsaved-changes prompt
    static savePromptPattern := "i)(save|unsaved)"

    static psWindowTitle := "PowerScribe 360 | Reporting ahk_exe Nuance.PowerScribe360.exe"

    ; Positional path to the report text. Brittle - kept only as a last resort behind
    ; a property-based lookup.
    static reportPath := "YYYYV"

    ; Whether a piece of text reads like a report body rather than some other field
    static LooksLikeReport(text) {
        return RegExMatch(text, "i)EXAMINATION:") > 0
    }

    static CreateCustomKeybind(keys, targetWindow := "") {
        ; Create a function that stores its configuration
        func := targetWindow != "" ?
            (*) => (WinActivate(targetWindow), Send(keys)) :
            (*) => Send(keys)

        ; Store the configuration
        func.keys := keys
        func.window := targetWindow
        return func
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
        {name: "Ultrasound", pattern: "i)EXAMINATION:[\s]*US"}
    ]

    ; Used when nothing else matches
    static fallback := "MSK"

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
    WinActivate("PowerScribe")
    Send x
}

setAttending(x) {
    WinActivate("PowerScribe")
    Send "{Alt down}ta{Alt up}"
    Sleep(100)
    Send x
    Sleep(100)
    Send "{tab}{space}{tab}{Enter}"
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
        root := UIA.ElementFromHandle(PACSCommands.psWindowTitle)
    } catch {
        return ""
    }

    ; The report editor presents as a Document, but has been seen as a plain Edit
    best := ""
    for condition in [{Type: "Document"}, {Type: "Edit"}] {
        elements := ""
        try {
            elements := root.FindElements(condition)
        } catch {
            continue
        }

        for el in elements {
            text := ""
            try text := el.Value
            if (text = "")
                continue

            ; A real report names the study, so prefer that over any other text field
            if PACSCommands.LooksLikeReport(text)
                return text

            if (StrLen(text) > StrLen(best))
                best := text
        }
    }

    if (best != "")
        return best

    ; Positional fallback for the case where nothing matched by type
    try {
        return root.ElementFromPath(PACSCommands.reportPath).Value
    }

    return ""
}

/**
 * Assigns the report to the attending configured for its modality.
 * A modality configured with a blank attending is left alone so the report keeps
 * PowerScribe's own default attending.
 * @returns the modality the report was classified as
 */
checkAttending(haystack) {
    modality := ReportModality.Classify(haystack)
    attending := ProfileManager.GetModalityAttending(modality)

    if (attending != "")
        setAttending(attending)

    return modality
}

/**
 * Asks a window to close and answers the "save changes?" prompt if one appears.
 * Killing the process outright discards an in-progress report without ever showing
 * that prompt, which is why a restart has to go through here first.
 * @param winTitle Window to close
 * @param timeoutMs How long to keep answering prompts before giving up
 * @returns true if the owning process exited, false if it is still running
 */
closeWithSavePrompt(winTitle, timeoutMs := 8000) {
    if !WinExist(winTitle)
        return true

    hwnd := WinExist(winTitle)
    try {
        pid := WinGetPID("ahk_id " hwnd)
    } catch {
        return false
    }

    try {
        WinClose("ahk_id " hwnd)
    } catch {
        return false
    }

    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        if !ProcessExist(pid)
            return true

        dialog := findSaveChangesDialog(pid, hwnd)
        if dialog
            clickSaveChangesButton(dialog)

        Sleep(150)
    }

    return !ProcessExist(pid)
}

/**
 * Finds a dialog belonging to a process that is asking about unsaved changes.
 * @returns the dialog's window handle, or 0 if there isn't one
 */
findSaveChangesDialog(pid, mainHwnd) {
    try {
        windows := WinGetList("ahk_pid " pid)
    } catch {
        return 0
    }

    for hwnd in windows {
        if (hwnd = mainHwnd)
            continue

        title := ""
        body := ""
        try title := WinGetTitle("ahk_id " hwnd)
        try body := WinGetText("ahk_id " hwnd)

        if (title ~= PACSCommands.savePromptPattern || body ~= PACSCommands.savePromptPattern)
            return hwnd
    }
    return 0
}

/**
 * Clicks Yes/Save on an unsaved-changes dialog.
 * @returns true if a button was clicked
 */
clickSaveChangesButton(hwnd) {
    ; Standard Win32 dialog buttons
    try {
        for ctrl in WinGetControls("ahk_id " hwnd) {
            if !InStr(ctrl, "Button")
                continue

            caption := ""
            try caption := ControlGetText(ctrl, "ahk_id " hwnd)

            ; Strip the accelerator ampersand before matching ("&Yes" -> "Yes")
            if (StrReplace(caption, "&") ~= "i)^\s*(yes|save)\s*$") {
                ControlClick(ctrl, "ahk_id " hwnd)
                return true
            }
        }
    }

    ; Fall back to UIA for owner-drawn dialogs that expose no Win32 controls
    try {
        el := UIA.ElementFromHandle("ahk_id " hwnd)
        btn := el.FindElement([{Type: "Button", Name: "Yes"}, {Type: "Button", Name: "Save"}])
        btn.Click()
        return true
    }

    return false
}

restartPACS() {
    anyClosed := false

    ; Helper function to track if anything was closed
    closeKillAndTrack(x) {
        if ProcessExist(x) {
            ProcessClose(x)
            anyClosed := true
        } else if WinExist(x) {
            WinKill(x)
            if WinExist(x) {
                ProcessClose(WinGetProcessName(x))
            }
            anyClosed := true
        }
    }

    ; Close PowerScribe gracefully first so an in-progress report can be saved. The
    ; hard kill below still runs as a fallback if it does not exit in time.
    if WinExist("PowerScribe") {
        if closeWithSavePrompt("PowerScribe")
            anyClosed := true
    }

    closeKillAndTrack("Command - ")
    closeKillAndTrack("WinDbg:")
    closeKillAndTrack("Vue PACS")
    closeKillAndTrack("Explorer Portal")
    closeKillAndTrack("PowerScribe")
    closeKillAndTrack("Hyperspace")
    closeKillAndTrack("mp.exe")
    closeKillAndTrack("NativeBridge.exe")

    if anyClosed {
        Sleep(500)
    }

    found := False

    Loop Files, A_DesktopCommon "\*"
    {
        if InStr(A_LoopFileName, "Vue Client (Integrated)")
        {
            found := True
            Run A_LoopFileFullPath
            break
        }
    }
    if !found
    {
        Loop Files, A_Desktop "\*"
            {
                if InStr(A_LoopFileName, "Vue Client (Integrated)")
                {
                    found := True
                    Run A_LoopFileFullPath
                    break
                }
            }
    }
    if !found
    {
        MsgBox "ERROR: PACS not found..."
    }

	Return

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
	haystack := readReportText()
	if (haystack != "") {
		try {
			checkAttending(haystack)
			attendingRouted := true
		}
	}

	; Activate Vue PACS and open sticky notes
	WinActivate("Vue PACS ahk_exe mp.exe")
	Sleep(150)
	mpEl := UIA.ElementFromHandle("Vue PACS ahk_exe mp.exe")
	try {
		mpEl.FindElement({Name:"scn_sticky_notes"}).Click()
	} catch {
		MsgBox("Could not find Sticky Notes button in PACS.")
		return
	}

	; Wait for sticky notes window
	if !WinWait("Sticky Notes", , 2) {
		MsgBox("Sticky Notes window did not appear.")
		return
	}

	sticky := UIA.ElementFromHandle("Sticky Notes")
	try sticky.SetFocus()

	; Helper to ensure the text field is focused
	focusNoteField(field) {
		loop 3 {
			try field.SetFocus()
			catch
			try field.Click("left")
			Sleep(50)
		}
	}

	; Get note input field
	noteField := ""
	try noteField := sticky.ElementFromPath("YY0/")
	if (!IsSet(noteField) || noteField = "" || !noteField) {
		; Try another attempt after slight delay
		Sleep(200)
		try noteField := sticky.ElementFromPath("YY0/")
	}
	if (!noteField) {
		MsgBox("Could not locate Sticky Notes text field.")
		return
	}

	; Optionally normalize line endings to CRLF for sticky note field
	if (Settings.Get("AutoConvertWetReadLineEndings")) {
		clipText := RegExReplace(clipText, "(\r)?\n", "`r`n")
	}

	; Clear and paste with verification using selected strategy
	focusNoteField(noteField)
	Send("^a")
	Send("{Backspace}")
	Sleep(50)

	success := false
	clipBackup := ClipboardAll()
	A_Clipboard := clipText
	ClipWait(0.5)

	loop 3 {
		focusNoteField(noteField)
		switch pasteMode {
			case "send":
				Send("^v")
			case "uia":
				try noteField.Value := clipText
			case "control":
				try {
					hwnd := noteField.NativeWindowHandle
					if hwnd {
						ControlFocus("ahk_id " hwnd)
						ControlSetText("ahk_id " hwnd, clipText)
					} else {
						ControlSetText("", clipText, "Sticky Notes")
					}
				}
		}
		; Wait until text matches or timeout
		start := A_TickCount
		while (A_TickCount - start < 2000) {
			try {
				current := noteField.Value
			} catch {
				current := ""
			}
			if (current = clipText) {
				success := true
				break
			}
			Sleep(100)
		}
		if success
			break
		; Retry: clear and try again
		focusNoteField(noteField)
		Send("^a")
		Send("{Backspace}")
		Sleep(100)
	}

	; Restore original clipboard
	try {
		A_Clipboard := clipBackup
	}

	if !success {
		MsgBox("Wet read may not have pasted fully. Please verify the sticky note.")
	}

	if !attendingRouted {
		MsgBox("Could not read the report from PowerScribe, so the attending was not assigned. Set it manually.", "Attending Not Assigned", "Icon!")
	}
	Return
}

PromptWetReadMode() {
	modeGui := Gui("+AlwaysOnTop", "Wet Read Paste Mode")
	modeGui.Add("Text",, "Select paste method for this run:")
	choice := "send"
	modeGui.Add("Button", "w200", "Original (Ctrl+V)").OnEvent("Click", (*) => (choice := "send", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "UIA Value pattern").OnEvent("Click", (*) => (choice := "uia", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "ControlSetText").OnEvent("Click", (*) => (choice := "control", modeGui.Destroy()))
	modeGui.Add("Button", "w200", "Cancel").OnEvent("Click", (*) => (choice := "cancel", modeGui.Destroy()))
	modeGui.Show()
	WinWaitClose(modeGui.Hwnd)
	return choice
}

toggleWindow(winName) {
    if WinExist(winName) {
        if WinGetMinMax(winName) = -1  ; -1 indicates window is minimized
        {
            WinActivate(winName)  ; Restore and activate the window
        }
        else
        {
            WinMinimize(winName)  ; Minimize the window
        }
    }
}
