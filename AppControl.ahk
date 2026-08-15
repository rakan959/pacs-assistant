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

    CloseWindow(hwnd) {
        try WinClose("ahk_id " hwnd, , 2)
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
    static powerScribeExecutable := "Nuance.PowerScribe360.exe"
    static powerScribeReportingTitle := "PowerScribe 360 | Reporting"
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

    /**
     * Stops an explicitly typed process or closes an explicitly typed window.
     * Process names are never reused as title selectors, and window targets never
     * escalate to terminating a shared owner process.
     * @returns {found, stopped}; stopped is false on lookup uncertainty or when a
     * target survives, allowing restartPACS to fail closed.
     */
    static StopTarget(target, targetKind) {
        if (targetKind = "process")
            return this.StopProcessTarget(target)
        if (targetKind = "window")
            return this.CloseWindowTarget(target)
        return {found: false, stopped: false, error: "Unsupported restart target kind: " targetKind}
    }

    static StopProcessTarget(target) {
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

        return {found: foundProcess, stopped: true}
    }

    static CloseWindowTarget(target) {
        driver := this.lifecycleDriver
        try hwnd := driver.FindWindow(target)
        catch as err
            return {found: false, stopped: false, error: err.Message}
        if !hwnd
            return {found: false, stopped: true}

        ; Shared-host windows (currently Explorer Portal in Edge) are closed and
        ; verified by HWND only. Keep resolving the exact title/executable until
        ; every matching window is gone, bounded against a respawning provider.
        stoppedWindows := 0
        loop {
            if (stoppedWindows >= this.maxMatchingProcesses) {
                return {
                    found: true,
                    stopped: false,
                    error: "Too many matching windows remained after bounded closure"
                }
            }
            try windowStopped := driver.CloseWindow(hwnd)
            catch as err
                return {found: true, stopped: false, error: err.Message}
            if !windowStopped
                return {found: true, stopped: false}
            stoppedWindows++

            try hwnd := driver.FindWindow(target)
            catch as err
                return {found: true, stopped: false, error: err.Message}
            if !hwnd
                return {found: true, stopped: true}
        }
    }

    static PacsRestartTargetSpecs() {
        return [
            {
                target: "Explorer Portal ahk_exe msedge.exe",
                label: "Explorer Portal",
                kind: "window"
            },
            ; closeWithSavePrompt handles the report dialog first. The hard-stop
            ; fallback must address the known executable because the window can
            ; disappear while its background process remains alive.
            {target: this.powerScribeExecutable, label: "PowerScribe", kind: "process"},
            {target: "mp.exe", kind: "process"},
            {target: "NativeBridge.exe", kind: "process"}
        ]
    }

    static PacsGracefulCloseTarget() {
        return this.powerScribeReportingTitle " " this.PowerScribeProcessTarget()
    }

    static PowerScribeProcessTarget() {
        return "ahk_exe " this.powerScribeExecutable
    }

    static StopTargetSpecs(specs) {
        anyStopped := false
        failedTargets := []
        for spec in specs {
            target := spec.target
            if !HasProp(spec, "kind") {
                failedTargets.Push(HasProp(spec, "label") ? spec.label : target)
                continue
            }
            result := this.StopTarget(target, spec.kind)
            if result.found
                anyStopped := true
            if !result.stopped
                failedTargets.Push(HasProp(spec, "label") ? spec.label : target)
        }
        return {anyStopped: anyStopped, failedTargets: failedTargets}
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

    ; Close PowerScribe gracefully first so an in-progress report can be saved. The
    ; hard kill below still runs as a fallback if it does not exit in time.
    powerScribeTarget := AppControl.PacsGracefulCloseTarget()
    if WinExist(powerScribeTarget) {
        if closeWithSavePrompt(powerScribeTarget)
            anyClosed := true
    }

    stopResult := AppControl.StopTargetSpecs(AppControl.PacsRestartTargetSpecs())
    anyClosed := anyClosed || stopResult.anyStopped
    failedTargets := stopResult.failedTargets

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
