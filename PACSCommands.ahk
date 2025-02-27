#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

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
