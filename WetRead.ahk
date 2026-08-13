#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include PowerScribe.ahk

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
	if (!noteField) {
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
