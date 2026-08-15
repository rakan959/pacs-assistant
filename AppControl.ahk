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

    IsActive(winTitle) {
        try return WinActive(winTitle) != 0
        return false
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
 * Process and window lifecycle primitives used by restartPACS. Every terminating
 * operation verifies the target is actually gone, while treating an already-exited
 * race as success.
 */
class NativeAppLifecycleDriver {
    FindProcess(target) {
        return ProcessExist(target)
    }

    FindWindow(target) {
        return WinExist(target)
    }

    GetWindowProcessId(hwnd) {
        return WinGetPID("ahk_id " hwnd)
    }

    ProcessExists(pid) {
        return ProcessExist(pid) != 0
    }

    WindowExists(hwnd) {
        return WinExist("ahk_id " hwnd) != 0
    }

    StopProcess(pid) {
        try ProcessClose(pid)
        catch {
            return !this.ProcessExists(pid)
        }

        try ProcessWaitClose(pid, 2)
        return !this.ProcessExists(pid)
    }

    KillWindow(hwnd) {
        try WinKill("ahk_id " hwnd)
        catch {
            return !this.WindowExists(hwnd)
        }
        return !this.WindowExists(hwnd)
    }

    Launch(path) {
        Run(path)
        return true
    }
}

/**
 * Starting, stopping and switching the clinical applications.
 */
class AppControl {
    ; A window title or body that looks like an unsaved-changes prompt
    static savePromptPattern := "i)(save|unsaved)"
    static activationTimeoutSeconds := 2
    static maxMatchingProcesses := 32
    static windowDriver := NativeWindowDriver()
    static lifecycleDriver := NativeAppLifecycleDriver()

    static ActivateWindow(winTitle) {
        return this.windowDriver.Activate(winTitle, this.activationTimeoutSeconds)
    }

    static SendKeysToWindow(winTitle, keys) {
        if !this.ActivateWindow(winTitle)
            return false

        return this.SendKeysToActiveWindow(winTitle, keys)
    }

    /**
     * Emits keys only while the intended target is still active. Activation and a
     * later send are separate OS operations; a popup or user focus change can occur
     * between them, so every focus-sensitive emission rechecks the postcondition.
     */
    static SendKeysToActiveWindow(winTitle, keys) {
        try {
            if !this.windowDriver.IsActive(winTitle)
                return false
            this.windowDriver.SendKeys(keys)
            return true
        } catch {
            return false
        }
    }

    static SendTextToActiveWindow(winTitle, text) {
        try {
            if !this.windowDriver.IsActive(winTitle)
                return false
            this.windowDriver.SendText(text)
            return true
        } catch {
            return false
        }
    }

    /**
     * Stops a target addressed by process name or window title.
     * @returns {found, stopped}; stopped is false on lookup uncertainty or when a
     * target survives termination, allowing restartPACS to fail closed.
     */
    static StopTarget(target) {
        driver := this.lifecycleDriver

        foundProcess := false
        stoppedProcesses := 0
        loop {
            try pid := driver.FindProcess(target)
            catch as err
                return {found: foundProcess, stopped: false, error: err.Message}
            if !pid
                break

            foundProcess := true
            if (stoppedProcesses >= this.maxMatchingProcesses) {
                return {
                    found: true,
                    stopped: false,
                    error: "Too many matching processes remained after bounded termination"
                }
            }

            try stopped := driver.StopProcess(pid)
            catch as err {
                ; A process may exit between discovery and termination. Verify the
                ; postcondition before reporting that race as a restart failure.
                try alreadyStopped := !driver.ProcessExists(pid)
                catch
                    alreadyStopped := false
                if !alreadyStopped
                    return {found: true, stopped: false, error: err.Message}
                stoppedProcesses++
                continue
            }
            if !stopped
                return {found: true, stopped: false}
            stoppedProcesses++
        }

        if foundProcess
            return {found: true, stopped: true}

        try hwnd := driver.FindWindow(target)
        catch as err
            return {found: false, stopped: false, error: err.Message}
        if !hwnd
            return {found: false, stopped: true}

        ; Capture ownership before killing the window: afterwards the handle may be
        ; invalid even though its process is still alive.
        try pid := driver.GetWindowProcessId(hwnd)
        catch as err
            return {found: true, stopped: false, error: err.Message}
        if !pid
            return {found: true, stopped: false, error: "Window process ownership could not be confirmed"}

        try windowStopped := driver.KillWindow(hwnd)
        catch as err
            return {found: true, stopped: false, error: err.Message}

        if pid {
            try processAlive := driver.ProcessExists(pid)
            catch as err
                return {found: true, stopped: false, error: err.Message}
            if processAlive {
                try processStopped := driver.StopProcess(pid)
                catch as err
                    return {found: true, stopped: false, error: err.Message}
                return {found: true, stopped: processStopped ? true : false}
            }
            return {found: true, stopped: true}
        }

        return {found: true, stopped: windowStopped ? true : false}
    }

    static LaunchVuePacs(directory) {
        try {
            ; Only the installed Windows shortcut is a valid launch target. A broad
            ; substring match could treat a similarly named script as PACS and report
            ; a successful restart after launching the wrong entry.
            Loop Files, directory "\Vue Client (Integrated).lnk", "F" {
                try return this.lifecycleDriver.Launch(A_LoopFileFullPath) ? true : false
                catch
                    return false
            }
        }
        return false
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
    failedTargets := []

    ; Close PowerScribe gracefully first so an in-progress report can be saved. The
    ; hard kill below still runs as a fallback if it does not exit in time.
    if WinExist("PowerScribe") {
        if closeWithSavePrompt("PowerScribe")
            anyClosed := true
    }

    for target in [
        "Command - ",
        "WinDbg:",
        "Vue PACS",
        "Explorer Portal",
        "PowerScribe",
        "Hyperspace",
        "mp.exe",
        "NativeBridge.exe"
    ] {
        result := AppControl.StopTarget(target)
        if result.found
            anyClosed := true
        if !result.stopped
            failedTargets.Push(target)
    }

    if failedTargets.Length {
        names := ""
        for target in failedTargets
            names .= (names = "" ? "" : ", ") target
        MsgBox(
            "PACS Assistant could not stop: " names ". The restart was cancelled to avoid launching duplicate clinical clients.",
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }

    if anyClosed {
        Sleep(500)
    }

    ; The shortcut sits on either the all-users desktop or this user's own
    if !(AppControl.LaunchVuePacs(A_DesktopCommon) || AppControl.LaunchVuePacs(A_Desktop)) {
        MsgBox "ERROR: PACS not found..."
        return false
    }
    return true
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
