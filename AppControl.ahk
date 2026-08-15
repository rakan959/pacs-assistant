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

    ListWindowsByExecutable(executable) {
        return WinGetList("ahk_exe " executable)
    }

    GetTitle(hwnd) {
        return WinGetTitle("ahk_id " hwnd)
    }

    GetProcessName(hwnd) {
        return WinGetProcessName("ahk_id " hwnd)
    }

    GetProcessId(hwnd) {
        return WinGetPID("ahk_id " hwnd)
    }

    GetMinMax(target) {
        return WinGetMinMax(target)
    }

    Minimize(target) {
        WinMinimize(target)
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
    static activationTimeoutSeconds := 2
    static maxMatchingProcesses := 32
    static powerScribeExecutable := "Nuance.PowerScribe360.exe"
    static powerScribeReportingTitle := "PowerScribe 360 | Reporting"
    static vuePacsExecutable := "mp.exe"
    static vuePacsTitle := "Vue PACS"
    static vuePacsClientTitle := "Vue PACS Client"
    static explorerPortalExecutable := "msedge.exe"
    static explorerPortalTitle := "Explorer Portal"
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

    static ExactWindowSpec(title, executable) {
        if !(Type(title) == "String") || title = ""
            throw ValueError("Exact window title is required")
        if !(Type(executable) == "String") || executable = ""
            throw ValueError("Exact window executable is required")
        return {title: title, exe: executable}
    }

    static PowerScribeWindowSpec() {
        return this.ExactWindowSpec(
            this.powerScribeReportingTitle,
            this.powerScribeExecutable
        )
    }

    static VuePacsWindowSpec() {
        return this.ExactWindowSpec(this.vuePacsTitle, this.vuePacsExecutable)
    }

    static VuePacsClientWindowSpec() {
        return this.ExactWindowSpec(this.vuePacsClientTitle, this.vuePacsExecutable)
    }

    static ExplorerPortalWindowSpec() {
        return this.ExactWindowSpec(
            this.explorerPortalTitle,
            this.explorerPortalExecutable
        )
    }

    /**
     * Enumerates by executable, then exact-compares the title and captures the
     * concrete HWND/PID. Global A_TitleMatchMode never participates.
     */
    static ResolveExactWindows(spec) {
        if !IsObject(spec) || !HasProp(spec, "title") || !HasProp(spec, "exe")
            throw TypeError("Exact window spec is required")
        this.ExactWindowSpec(spec.title, spec.exe)

        sessions := []
        seen := Map()
        for hwnd in this.windowDriver.ListWindowsByExecutable(spec.exe) {
            if (hwnd <= 0 || seen.Has(hwnd))
                continue
            seen[hwnd] := true
            title := this.windowDriver.GetTitle(hwnd)
            executable := this.windowDriver.GetProcessName(hwnd)
            processId := this.windowDriver.GetProcessId(hwnd)
            if (title == spec.title && executable = spec.exe && processId > 0) {
                sessions.Push({
                    hwnd: hwnd,
                    target: "ahk_id " hwnd,
                    processId: processId,
                    title: spec.title,
                    exe: spec.exe
                })
            }
        }
        return sessions
    }

    static ResolveUniqueExactWindow(spec) {
        sessions := this.ResolveExactWindows(spec)
        return sessions.Length = 1 ? sessions[1] : 0
    }

    static ExactSessionIsUniqueAndLive(session) {
        if !session || !HasProp(session, "title") || !HasProp(session, "exe")
            return false
        try sessions := this.ResolveExactWindows(
            this.ExactWindowSpec(session.title, session.exe)
        )
        catch
            return false
        return sessions.Length = 1
            && sessions[1].hwnd = session.hwnd
            && sessions[1].processId = session.processId
    }

    static SendKeysToExactWindow(spec, keys) {
        try session := this.ResolveUniqueExactWindow(spec)
        catch
            return false
        if !session || !this.windowDriver.Activate(
            session.target,
            this.activationTimeoutSeconds
        )
            return false
        return this.SendKeysToActiveExactWindow(session, keys)
    }

    static SendKeysToActiveExactWindow(session, keys) {
        try {
            if !this.ExactSessionIsUniqueAndLive(session)
                return false
            if !this.windowDriver.IsActive(session.target)
                return false
            this.windowDriver.SendKeys(keys)
            return true
        } catch {
            return false
        }
    }

    static ToggleExactWindow(spec) {
        try session := this.ResolveUniqueExactWindow(spec)
        catch
            return false
        if !session
            return false
        try {
            if (this.windowDriver.GetMinMax(session.target) = -1)
                return this.windowDriver.Activate(
                    session.target,
                    this.activationTimeoutSeconds
                )
            this.windowDriver.Minimize(session.target)
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
        if !IsObject(target)
            return {found: false, stopped: false, error: "Exact window spec is required"}
        return this.CloseExactWindowTarget(target)
    }

    static CloseExactWindowTarget(spec) {
        foundWindow := false
        stoppedWindows := 0
        loop {
            try sessions := this.ResolveExactWindows(spec)
            catch as err
                return {found: foundWindow, stopped: false, error: err.Message}
            if !sessions.Length
                return {found: foundWindow, stopped: true}
            foundWindow := true

            for session in sessions {
                if (stoppedWindows >= this.maxMatchingProcesses) {
                    return {
                        found: true,
                        stopped: false,
                        error: "Too many matching windows remained after bounded closure"
                    }
                }
                try windowStopped := this.lifecycleDriver.CloseWindow(session.hwnd)
                catch as err
                    return {found: true, stopped: false, error: err.Message}
                if !windowStopped
                    return {found: true, stopped: false}
                stoppedWindows++
            }
        }
    }

    static PacsRestartTargetSpecs() {
        return [
            {
                target: this.ExplorerPortalWindowSpec(),
                label: "Explorer Portal",
                kind: "window"
            },
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

class NativeGracefulCloseDriver {
    FindWindow(target) {
        return WinExist(target)
    }

    GetProcessId(hwnd) {
        return WinGetPID("ahk_id " hwnd)
    }

    RequestClose(hwnd) {
        WinClose("ahk_id " hwnd)
    }

    ProcessExists(pid) {
        return ProcessExist(pid) != 0
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }
}

/**
 * Asks the exact reporting window to close and waits for its process to exit. A
 * save dialog is intentionally left for the user: without a captured stable dialog
 * identity, automatically clicking a generic Yes/Save control could action an
 * unrelated same-process dialog.
 * @param winTitle Window to close
 * @param timeoutMs How long to wait for the user/save flow before giving up
 * @returns true if the owning process exited, false if it is still running
 */
closeWithSavePrompt(winTitle, timeoutMs := 8000, driver := 0, expectedPid := 0) {
    driver := driver ? driver : NativeGracefulCloseDriver()
    try hwnd := driver.FindWindow(winTitle)
    catch
        return false
    if !hwnd {
        if !expectedPid
            return true
        try return !driver.ProcessExists(expectedPid)
        return false
    }
    try {
        pid := driver.GetProcessId(hwnd)
    } catch {
        return false
    }
    if (expectedPid && pid != expectedPid)
        return false

    try {
        driver.RequestClose(hwnd)
    } catch {
        return false
    }

    deadline := driver.NowMilliseconds() + timeoutMs
    while (driver.NowMilliseconds() < deadline) {
        if !driver.ProcessExists(pid)
            return true
        driver.Pause(150)
    }

    try return !driver.ProcessExists(pid)
    return false
}

class NativePacsRestartDriver {
    FindPowerScribeWindows() {
        return AppControl.ResolveExactWindows(AppControl.PowerScribeWindowSpec())
    }

    FindPowerScribeProcess() {
        return AppControl.lifecycleDriver.FindProcess(AppControl.powerScribeExecutable)
    }

    ClosePowerScribe(session) {
        return closeWithSavePrompt(session.target, 8000, 0, session.processId)
    }

    StopTargets() {
        return AppControl.StopTargetSpecs(AppControl.PacsRestartTargetSpecs())
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }

    Launch() {
        return AppControl.LaunchVuePacs(A_DesktopCommon)
            || AppControl.LaunchVuePacs(A_Desktop)
    }
}

restartPACS(driver := 0) {
    driver := driver ? driver : NativePacsRestartDriver()
    anyClosed := false

    ; PowerScribe is never a force-kill target. A failed/slow save or an unverified
    ; running process aborts the restart rather than risking an in-progress report.
    try powerScribeWindows := driver.FindPowerScribeWindows()
    catch as err {
        MsgBox(
            "PowerScribe window identity could not be verified. The restart was cancelled.`n`n" err.Message,
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }
    if (powerScribeWindows.Length > 1) {
        MsgBox(
            "Multiple PowerScribe reporting windows were found. Close them manually before restarting PACS.",
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }
    if (powerScribeWindows.Length = 1) {
        try closedSafely := driver.ClosePowerScribe(powerScribeWindows[1])
        catch
            closedSafely := false
        if !closedSafely {
            MsgBox(
                "PowerScribe did not close after its save prompt. The restart was cancelled to protect the in-progress report.",
                "PACS Restart Cancelled",
                "Icon!"
            )
            return false
        }
        anyClosed := true
    } else {
        try powerScribePid := driver.FindPowerScribeProcess()
        catch as err {
            MsgBox(
                "PowerScribe process state could not be verified. The restart was cancelled.`n`n" err.Message,
                "PACS Restart Cancelled",
                "Icon!"
            )
            return false
        }
        if powerScribePid {
            MsgBox(
                "PowerScribe is running without a uniquely verified reporting window. Close it manually before restarting PACS.",
                "PACS Restart Cancelled",
                "Icon!"
            )
            return false
        }
    }

    stopResult := driver.StopTargets()
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
        driver.Pause(500)
    }

    ; The shortcut sits on either the all-users desktop or this user's own
    if !driver.Launch() {
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
