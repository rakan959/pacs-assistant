#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
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
	NuanceEl := UIA.ElementFromHandle("PowerScribe 360 | Reporting ahk_exe Nuance.PowerScribe360.exe")
	haystack := NuanceEl.ElementFromPath("YYYYV").Value
	checkAttending(haystack)
	Sleep(100)
	WinActivate("Vue PACS ahk_exe mp.exe")
	Sleep(100)
	mpEl := UIA.ElementFromHandle("Vue PACS ahk_exe mp.exe")
	Sleep(100)
	mpEl.FindElement({Name:"scn_sticky_notes"}).Click()
	WinWait("Sticky Notes", , 1)
	mpEl := UIA.ElementFromHandle("Sticky Notes")
	Sleep(100)
	mpEl.ElementFromPath("YY0").Click()
	Sleep(100)
	MouseGetPos &xpos, &ypos
	mpEl.ElementFromPath("87K/").Click("left")
	MouseMove xpos, ypos
	Sleep(100)
	Send('r')
	Sleep(100)
	mpEl.ElementFromPath("V").ControlClick()
	Sleep(100)
	Send A_Clipboard
	Sleep(2*StrLen(A_Clipboard))
	mpEl.ElementFromPath("YY0/").Click()
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
