#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk

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
        "Previous Series", (*) => (WinActivate("Vue PACS Client"), Send("{Left}"))
    )

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

pacsActive() {
    return WinActive("PowerScribe") or WinActive("ahk_exe mp.exe")
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

closeKill(x) {
    if ProcessExist(x) {
        ProcessClose(x)
    } else if WinExist(x) {
        WinKill(x)
        if WinExist(x) {
            ProcessClose(WinGetProcessName(x))
        }
    }
}

checkAttending(haystack) {
    bodyStr := "i)EXAMINATION:[\s]*((CT.*pelvis)|(XR.*abdomen)|(MRCP)|(MRI.*abdomen))"
    chestStr := "i)EXAMINATION:[\s]*((CT.*chest)|(XR.*chest))"
    pedsStr := "i)EXAMINATION:[\s]*((US.*((right lower quadrant)|(neurosonography))))"
    neuroStr := "i)EXAMINATION:[\s]*((CT.*((facial)|(spine)|(head)|(escape)|(neck)))|(MRI.*((brain)|(spine)|(orbits)))|(MRA))"
    usStr := "i)EXAMINATION:[\s]*US"
    nucsStr := "i)EXAMINATION:[\s]*NM"

    if RegExMatch(haystack, bodyStr) {
		setAttending("Body")
	} else if RegExMatch(haystack, chestStr) {
		setAttending("Chest")
	} else if RegExMatch(haystack, neuroStr) {
		setAttending("Neuro")
	} else if RegExMatch(haystack, nucsStr) {
		setAttending("Nucs")
	} else if RegExMatch(haystack, pedsStr) {
		setAttending("Peds")
	} else if RegExMatch(haystack, usStr) {
		setAttending("Ultrasound")
	} else {
		setAttending("MSK")
	}
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

	; Read current report for attending selection
	try {
		NuanceEl := UIA.ElementFromHandle("PowerScribe 360 | Reporting ahk_exe Nuance.PowerScribe360.exe")
		haystack := NuanceEl.ElementFromPath("YYYYV").Value
		checkAttending(haystack)
	} catch {
		; continue even if attending detection fails
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
	try {
		noteField := sticky.ElementFromPath("YY0/")
	} catch {
		MsgBox("Could not locate Sticky Notes text field.")
		return
	}

	; Optionally normalize line endings to CRLF for sticky note field
	if (Settings.Get("AutoConvertWetReadLineEndings")) {
		clipText := RegExReplace(clipText, "(\r)?\n", "`r`n")
	}

	; Clear and paste with verification using clipboard (faster and preserves order)
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
		Send("^v")
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
	Return
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
