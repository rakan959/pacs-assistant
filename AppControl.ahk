#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Thin wrapper around focus-sensitive AutoHotkey primitives. Tests replace this
 * driver so clinical commands can prove their target and payload without emitting
 * real keystrokes.
 */
class NativeWindowDriver {
    Activate(winTitle, timeoutSeconds) {
        try {
            if !WinExist(winTitle)
                return false
            WinActivate(winTitle)
            return WinWaitActive(winTitle, , timeoutSeconds) != 0
        } catch {
            return false
        }
    }

    SendKeys(keys) {
        Send(keys)
    }

    SendText(text) {
        SendText(text)
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }
}

/**
 * Starting, stopping and switching the clinical applications.
 */
class AppControl {
    ; A window title or body that looks like an unsaved-changes prompt
    static savePromptPattern := "i)(save|unsaved)"
    static activationTimeoutSeconds := 2
    static windowDriver := NativeWindowDriver()

    static ActivateWindow(winTitle) {
        return this.windowDriver.Activate(winTitle, this.activationTimeoutSeconds)
    }

    static SendKeysToWindow(winTitle, keys) {
        if !this.ActivateWindow(winTitle)
            return false

        try {
            this.windowDriver.SendKeys(keys)
            return true
        } catch {
            return false
        }
    }
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

        if (title ~= AppControl.savePromptPattern || body ~= AppControl.savePromptPattern)
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

    ; The shortcut sits on either the all-users desktop or this user's own
    launchVuePacs(directory) {
        Loop Files, directory "\*" {
            if InStr(A_LoopFileName, "Vue Client (Integrated)") {
                Run A_LoopFileFullPath
                return true
            }
        }
        return false
    }

    if !(launchVuePacs(A_DesktopCommon) || launchVuePacs(A_Desktop)) {
        MsgBox "ERROR: PACS not found..."
    }
}

toggleWindow(winName) {
    if WinExist(winName) {
        if WinGetMinMax(winName) = -1  ; -1 indicates window is minimized
        {
            AppControl.ActivateWindow(winName)  ; Restore and activate the window
        }
        else
        {
            WinMinimize(winName)  ; Minimize the window
        }
    }
}
