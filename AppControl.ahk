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

    ListWindows(selector) {
        return WinGetList(selector)
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
 * Process-observation and exact-window lifecycle primitives used by restartPACS.
 * Production restart never terminates a process discovered only by basename.
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

    CloseWindow(session) {
        if !AppControl.ExactSessionIsUniqueAndLive(session)
            return false
        hwnd := session.hwnd
        try WinClose(session.target, , 2)
        catch {
            return !this.WindowExists(hwnd)
        }
        return !this.WindowExists(hwnd)
    }

    Launch(path) {
        Run(path)
        return true
    }

    ResolveShortcut(path) {
        target := ""
        FileGetShortcut(path, &target)
        return target
    }

    ProcessPath(pid) {
        if (!(pid is Integer) || pid <= 0)
            throw ValueError("A positive process ID is required")
        processes := this.QueryProcesses("ProcessId = " pid)
        if (processes.Length != 1 || processes[1].path = "")
            throw Error("Process executable path could not be verified")
        return processes[1].path
    }

    ListProcessesByExecutable(executable) {
        if (Type(executable) != "String" || executable = "")
            throw ValueError("An executable name is required")
        escaped := StrReplace(executable, "'", "''")
        return this.QueryProcesses("Name = '" escaped "'")
    }

    QueryProcesses(whereClause) {
        locator := ComObject("WbemScripting.SWbemLocator")
        service := locator.ConnectServer(".", "root\cimv2")
        results := []
        for process in service.ExecQuery(
            "SELECT ProcessId, Name, ExecutablePath FROM Win32_Process WHERE " whereClause
        ) {
            path := ""
            try path := String(process.ExecutablePath)
            results.Push({
                processId: Integer(process.ProcessId),
                name: String(process.Name),
                path: path
            })
        }
        return results
    }
}

/**
 * Starting, stopping and switching the clinical applications.
 */
class AppControl {
    static activationTimeoutSeconds := 2
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
        try session := this.ResolveUniqueWindowSelector(winTitle)
        catch
            return false
        if (!session
            || !this.windowDriver.Activate(
                session.target,
                this.activationTimeoutSeconds
            ))
            return false
        return this.SendKeysToActiveSelectorWindow(session, keys)
    }

    static ResolveUniqueWindowSelector(selector) {
        if (Type(selector) != "String" || Trim(selector) = "")
            throw ValueError("A nonblank window selector is required")
        selector := Trim(selector)
        handles := this.windowDriver.ListWindows(selector)
        if !IsObject(handles)
            throw Error("Window lookup returned an invalid collection")

        unique := []
        seen := Map()
        for hwnd in handles {
            if (hwnd <= 0 || seen.Has(hwnd))
                continue
            seen[hwnd] := true
            unique.Push(hwnd)
        }
        if (unique.Length != 1)
            return 0
        hwnd := unique[1]
        processId := this.windowDriver.GetProcessId(hwnd)
        if (processId <= 0)
            return 0
        return {
            hwnd: hwnd,
            target: "ahk_id " hwnd,
            processId: processId,
            selector: selector
        }
    }

    static SelectorSessionIsUniqueAndLive(session) {
        if (!session
            || !HasProp(session, "hwnd")
            || !HasProp(session, "processId")
            || !HasProp(session, "selector")
            || session.hwnd <= 0
            || session.processId <= 0)
            return false
        try current := this.ResolveUniqueWindowSelector(session.selector)
        catch
            return false
        return current
            && current.hwnd = session.hwnd
            && current.processId = session.processId
    }

    static SendKeysToActiveSelectorWindow(session, keys) {
        try {
            if (!this.SelectorSessionIsUniqueAndLive(session)
                || !this.windowDriver.IsActive(session.target))
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

    static ResolveUniqueExactWindowAcross(specs) {
        if !IsObject(specs) || !specs.Length
            throw ValueError("At least one exact window spec is required")
        sessions := []
        seen := Map()
        for spec in specs {
            for session in this.ResolveExactWindows(spec) {
                if seen.Has(session.hwnd)
                    continue
                seen[session.hwnd] := true
                sessions.Push(session)
            }
        }
        return sessions.Length = 1 ? sessions[1] : 0
    }

    static ExactSessionIsUniqueAcross(session, specs) {
        try current := this.ResolveUniqueExactWindowAcross(specs)
        catch
            return false
        return current
            && current.hwnd = session.hwnd
            && current.processId = session.processId
    }

    static IsUniqueExactWindowActive(specs) {
        try session := this.ResolveUniqueExactWindowAcross(specs)
        catch
            return false
        if !session || !this.ExactSessionIsUniqueAcross(session, specs)
            return false
        try return this.windowDriver.IsActive(session.target)
        return false
    }

    static ExactSessionIsUniqueAndLive(session) {
        return this.ExactSessionIsLive(session, true)
    }

    static ExactSessionIsLive(session, requireUnique := false) {
        if (!session
            || !HasProp(session, "hwnd")
            || !HasProp(session, "processId")
            || !HasProp(session, "title")
            || !HasProp(session, "exe"))
            return false
        try sessions := this.ResolveExactWindows(
            this.ExactWindowSpec(session.title, session.exe)
        )
        catch
            return false
        if (requireUnique && sessions.Length != 1)
            return false
        for liveSession in sessions {
            if (liveSession.hwnd = session.hwnd
                && liveSession.processId = session.processId)
                return true
        }
        return false
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
            state := this.windowDriver.GetMinMax(session.target)
            ; GetMinMax can yield to a provider/window transition. Reacquire the
            ; exact set at the final boundary before either visible side effect.
            if !this.ExactSessionIsUniqueAndLive(session)
                return false
            if (state = -1)
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
     * Closes an explicitly typed exact window. Bare process targets are rejected:
     * the repository has no trustworthy installed full-path/creation identity for
     * the generic PACS executables, so basename termination cannot be made safe.
     * @returns {found, stopped}; stopped is false on lookup uncertainty or when a
     * target survives, allowing restartPACS to fail closed.
     */
    static StopTarget(target, targetKind) {
        if (targetKind = "window")
            return this.CloseWindowTarget(target)
        if (targetKind = "process") {
            return {
                found: false,
                stopped: false,
                error: "Bare-name process termination is not supported"
            }
        }
        return {found: false, stopped: false, error: "Unsupported restart target kind: " targetKind}
    }

    static CloseWindowTarget(target) {
        if !IsObject(target)
            return {found: false, stopped: false, error: "Exact window spec is required"}
        return this.CloseExactWindowTarget(target)
    }

    static CloseExactWindowTarget(spec) {
        try sessions := this.ResolveExactWindows(spec)
        catch as err
            return {found: false, stopped: false, error: err.Message}
        if !sessions.Length
            return {found: false, stopped: true}
        ; Exact title/executable equality is still not ownership proof for a shared
        ; host such as Edge. Multiple matches are ambiguity, not a set of windows
        ; PACS Assistant is authorized to close.
        if (sessions.Length != 1) {
            return {
                found: true,
                stopped: false,
                error: "multiple exact windows matched; none were closed"
            }
        }

        try windowStopped := this.lifecycleDriver.CloseWindow(sessions[1])
        catch as err
            return {found: true, stopped: false, error: err.Message}
        if !windowStopped
            return {found: true, stopped: false, error: "the exact window did not close"}

        try remaining := this.ResolveExactWindows(spec)
        catch as err
            return {found: true, stopped: false, error: err.Message}
        return remaining.Length
            ? {found: true, stopped: false, error: "the exact window remained or reappeared"}
            : {found: true, stopped: true, error: ""}
    }

    static PacsRestartTargetSpecs() {
        return [
            {
                target: this.ExplorerPortalWindowSpec(),
                label: "Explorer Portal",
                kind: "window"
            },
            {
                target: this.VuePacsWindowSpec(),
                label: this.vuePacsTitle,
                kind: "window"
            },
            {
                target: this.VuePacsClientWindowSpec(),
                label: this.vuePacsClientTitle,
                kind: "window"
            }
        ]
    }

    static PacsGracefulCloseTarget() {
        return this.powerScribeReportingTitle " " this.PowerScribeProcessTarget()
    }

    static PowerScribeProcessTarget() {
        return "ahk_exe " this.powerScribeExecutable
    }

    /**
     * Resolves every restart target without mutating it. The restart is an
     * all-target transaction: known ambiguity or lookup failure must be found
     * before PowerScribe or any PACS window is closed.
     */
    static PreflightTargetSpecs(specs) {
        failedTargets := []
        if (Type(specs) != "Array")
            return {clear: false, failedTargets: ["restart target list"]}

        for spec in specs {
            label := this.RestartTargetLabel(spec)
            if (!IsObject(spec)
                || !HasProp(spec, "kind")
                || spec.kind != "window"
                || !HasProp(spec, "target")
                || !IsObject(spec.target)) {
                failedTargets.Push(label)
                continue
            }

            try sessions := this.ResolveExactWindows(spec.target)
            catch {
                failedTargets.Push(label)
                continue
            }
            if (Type(sessions) != "Array" || sessions.Length > 1)
                failedTargets.Push(label)
        }
        return {
            clear: failedTargets.Length = 0,
            failedTargets: failedTargets
        }
    }

    static RestartTargetLabel(spec) {
        if (IsObject(spec)
            && HasProp(spec, "label")
            && Type(spec.label) = "String"
            && spec.label != "")
            return spec.label
        return "restart target"
    }

    static StopTargetSpecs(specs) {
        preflight := this.PreflightTargetSpecs(specs)
        if !preflight.clear {
            return {
                anyStopped: false,
                failedTargets: preflight.failedTargets
            }
        }

        anyStopped := false
        failedTargets := []
        for spec in specs {
            target := spec.target
            result := this.StopTarget(target, spec.kind)
            if (result.found && result.stopped)
                anyStopped := true
            if !result.stopped {
                failedTargets.Push(this.RestartTargetLabel(spec))
                ; Once the transaction is partial, do not close additional
                ; clinical clients. The caller will cancel rather than launch.
                break
            }
        }
        return {anyStopped: anyStopped, failedTargets: failedTargets}
    }

    static LaunchVuePacs(directory, expectedExecutablePath := "") {
        if (Type(expectedExecutablePath) != "String"
            || expectedExecutablePath = ""
            || !this.IsExpectedVueLaunchTarget(expectedExecutablePath))
            return false
        try {
            ; Only the installed Windows shortcut is a valid launch target. A broad
            ; substring match could treat a similarly named script as PACS and report
            ; a successful restart after launching the wrong entry.
            Loop Files, directory "\Vue Client (Integrated).lnk", "F" {
                try {
                    target := this.lifecycleDriver.ResolveShortcut(A_LoopFileFullPath)
                    if !this.IsExpectedVueLaunchTarget(target)
                        return false
                    if !this.PathsEqual(target, expectedExecutablePath)
                        return false
                    return this.lifecycleDriver.Launch(A_LoopFileFullPath) ? true : false
                }
                catch
                    return false
            }
        }
        return false
    }

    static IsExpectedVueLaunchTarget(path) {
        if (Type(path) != "String" || path = "" || !FileExist(path))
            return false
        SplitPath(path, &fileName, , &extension)
        return StrCompare(fileName, this.vuePacsExecutable, false) = 0
            && StrCompare(extension, "exe", false) = 0
    }

    static PathsEqual(left, right) {
        try return StrCompare(
            this.NormalizePath(left),
            this.NormalizePath(right),
            false
        ) = 0
        return false
    }

    static NormalizePath(path) {
        pathBuffer := Buffer(32768 * 2, 0)
        length := DllCall(
            "GetFullPathNameW",
            "WStr", path,
            "UInt", 32768,
            "Ptr", pathBuffer.Ptr,
            "Ptr", 0,
            "UInt"
        )
        if (!length || length >= 32768)
            throw OSError(A_LastError, "GetFullPathNameW")
        return StrGet(pathBuffer, length, "UTF-16")
    }
}

class NativeGracefulCloseDriver {
    FindWindow(target) {
        return WinExist(target)
    }

    GetProcessId(hwnd) {
        return WinGetPID("ahk_id " hwnd)
    }

    IsExpectedSession(session) {
        return AppControl.ExactSessionIsUniqueAndLive(session)
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
 * @param session Captured exact reporting-window session
 * @param timeoutMs How long to wait for the user/save flow before giving up
 * @returns true if the owning process exited, false if it is still running
 */
closeWithSavePrompt(session, timeoutMs := 8000, driver := 0) {
    driver := driver ? driver : NativeGracefulCloseDriver()
    if (!IsObject(session)
        || !HasProp(session, "hwnd")
        || !HasProp(session, "target")
        || !HasProp(session, "processId")
        || !HasProp(session, "title")
        || !HasProp(session, "exe"))
        return false

    try hwnd := driver.FindWindow(session.target)
    catch
        return false
    if !hwnd {
        try return !driver.ProcessExists(session.processId)
        return false
    }
    if (hwnd != session.hwnd)
        return false
    try {
        pid := driver.GetProcessId(hwnd)
    } catch {
        return false
    }
    if (pid != session.processId)
        return false

    ; HWNDs can be recycled, titles can change, and another exact reporting window
    ; can appear after capture. Re-enumerate the exact title/executable contract at
    ; the last safe point before WinClose and require the original unique HWND/PID.
    try expectedSession := driver.IsExpectedSession(session)
    catch
        return false
    if !expectedSession
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
    __New() {
        this.priorVueProcessIds := Map()
        this.trustedVueExecutablePath := ""
    }

    FindPowerScribeWindows() {
        return AppControl.ResolveExactWindows(AppControl.PowerScribeWindowSpec())
    }

    FindPowerScribeProcess() {
        return AppControl.lifecycleDriver.FindProcess(AppControl.powerScribeExecutable)
    }

    ClosePowerScribe(session) {
        return closeWithSavePrompt(session, 8000)
    }

    PrepareRestart() {
        ; Establish the installed Vue identity and complete pre-restart process set
        ; before any clinical window is closed. The restart cannot safely infer an
        ; installation from an arbitrary same-named shortcut target.
        preflight := AppControl.PreflightTargetSpecs(
            AppControl.PacsRestartTargetSpecs()
        )
        if !preflight.clear {
            names := ""
            for label in preflight.failedTargets
                names .= (names = "" ? "" : ", ") label
            throw Error("Restart target identity could not be verified: " names)
        }
        this.priorVueProcessIds := this.CaptureVueProcessIds()
        return true
    }

    StopTargets() {
        return AppControl.StopTargetSpecs(AppControl.PacsRestartTargetSpecs())
    }

    CaptureVueProcessIds() {
        sessions := []
        for spec in [AppControl.VuePacsWindowSpec(), AppControl.VuePacsClientWindowSpec()] {
            for session in AppControl.ResolveExactWindows(spec)
                sessions.Push(session)
        }
        if !sessions.Length
            throw Error("A running exact Vue PACS window is required to verify the installed executable")

        trustedPath := ""
        for session in sessions {
            path := AppControl.lifecycleDriver.ProcessPath(session.processId)
            if (path = "")
                throw Error("Vue PACS process path could not be verified")
            if (trustedPath = "")
                trustedPath := path
            else if !AppControl.PathsEqual(path, trustedPath)
                throw Error("Vue PACS windows are owned by different executable paths")
        }

        processIds := Map()
        for process in AppControl.lifecycleDriver.ListProcessesByExecutable(
            AppControl.vuePacsExecutable
        ) {
            if (process.path = "")
                throw Error("An mp.exe process path could not be verified")
            if AppControl.PathsEqual(process.path, trustedPath)
                processIds[process.processId] := true
        }
        for session in sessions {
            if !processIds.Has(session.processId)
                throw Error("Vue PACS process inventory changed during capture")
        }
        this.trustedVueExecutablePath := trustedPath
        return processIds
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }

    VerifyQuiescence() {
        try {
            if AppControl.ResolveExactWindows(AppControl.PowerScribeWindowSpec()).Length
                return {clear: false, error: "PowerScribe reporting window reappeared"}
            if AppControl.lifecycleDriver.FindProcess(AppControl.powerScribeExecutable)
                return {clear: false, error: "PowerScribe process is still running"}
            for processId in this.priorVueProcessIds {
                if AppControl.lifecycleDriver.ProcessExists(processId)
                    return {clear: false, error: "A previous Vue PACS process is still running"}
            }
            for process in AppControl.lifecycleDriver.ListProcessesByExecutable(
                AppControl.vuePacsExecutable
            ) {
                if (process.path = "")
                    return {clear: false, error: "An mp.exe process path could not be verified"}
                if AppControl.PathsEqual(process.path, this.trustedVueExecutablePath)
                    return {clear: false, error: "A Vue PACS process appeared before launch"}
            }
            for spec in AppControl.PacsRestartTargetSpecs() {
                if AppControl.ResolveExactWindows(spec.target).Length
                    return {clear: false, error: spec.label " reappeared"}
            }
        } catch as err {
            return {clear: false, error: err.Message}
        }
        return {clear: true, error: ""}
    }

    Launch() {
        if (this.trustedVueExecutablePath = "")
            return false
        return AppControl.LaunchVuePacs(A_DesktopCommon, this.trustedVueExecutablePath)
            || AppControl.LaunchVuePacs(A_Desktop, this.trustedVueExecutablePath)
    }

    WaitForLaunch(timeoutMs := 15000) {
        deadline := DllCall("GetTickCount64", "UInt64") + timeoutMs
        stableReads := 0
        stableSession := 0
        while (DllCall("GetTickCount64", "UInt64") < deadline) {
            try sessions := AppControl.ResolveExactWindows(AppControl.VuePacsWindowSpec())
            catch
                return false
            if (sessions.Length > 1)
                return false
            if (sessions.Length = 1) {
                session := sessions[1]
                if this.priorVueProcessIds.Has(session.processId)
                    return false
                try processPath := AppControl.lifecycleDriver.ProcessPath(session.processId)
                catch
                    return false
                if !AppControl.PathsEqual(processPath, this.trustedVueExecutablePath)
                    return false
                if stableSession {
                    if (session.hwnd != stableSession.hwnd
                        || session.processId != stableSession.processId)
                        return false
                } else {
                    stableSession := session
                }
                stableReads++
                if (stableReads >= 2)
                    return true
            } else {
                stableReads := 0
                stableSession := 0
            }
            Sleep(100)
        }
        return false
    }
}

restartPACS(driver := 0) {
    driver := driver ? driver : NativePacsRestartDriver()
    anyClosed := false

    ; Resolve the installed Vue executable and every already-running instance
    ; before touching PowerScribe or PACS. Failure here must have no side effects.
    try prepared := driver.PrepareRestart()
    catch as err {
        MsgBox(
            "The Vue PACS installation or restart target identities could not be verified. The restart was cancelled before closing any clinical window.`n`n" err.Message,
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }
    if !prepared {
        MsgBox(
            "The Vue PACS installation or restart target identities could not be verified. The restart was cancelled before closing any clinical window.",
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }

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
    }

    ; A second/background PowerScribe process may have no reporting window. Check
    ; again even after the verified reporting process exits, before closing PACS.
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

    try stopResult := driver.StopTargets()
    catch as err {
        MsgBox(
            "PACS target shutdown could not be completed or verified. The restart was cancelled.`n`n" err.Message,
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }
    if (!IsObject(stopResult)
        || !HasProp(stopResult, "anyStopped")
        || !HasProp(stopResult, "failedTargets")
        || Type(stopResult.failedTargets) != "Array") {
        MsgBox(
            "PACS target shutdown returned an invalid verification result. The restart was cancelled.",
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }
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
        try driver.Pause(500)
        catch as err {
            MsgBox(
                "The restart stabilization wait failed. PACS was not relaunched.`n`n" err.Message,
                "PACS Restart Cancelled",
                "Icon!"
            )
            return false
        }
    }


    try quiescence := driver.VerifyQuiescence()
    catch as err
        quiescence := {clear: false, error: err.Message}
    if (!IsObject(quiescence) || !HasProp(quiescence, "clear") || !quiescence.clear) {
        detail := IsObject(quiescence) && HasProp(quiescence, "error")
            ? quiescence.error
            : "restart target state could not be verified"
        MsgBox(
            "A clinical client reappeared before launch. The restart was cancelled.`n`n" detail,
            "PACS Restart Cancelled",
            "Icon!"
        )
        return false
    }

    ; The shortcut sits on either the all-users desktop or this user's own
    try launched := driver.Launch()
    catch as err {
        MsgBox(
            "The verified PACS shortcut could not be launched.`n`n" err.Message,
            "PACS Launch Failed",
            "Icon!"
        )
        return false
    }
    if !launched {
        MsgBox(
            "The verified PACS shortcut was not found or could not be launched.",
            "PACS Launch Failed",
            "Icon!"
        )
        return false
    }
    try launchVerified := driver.WaitForLaunch()
    catch as err {
        MsgBox(
            "The PACS shortcut ran, but the new Vue PACS window could not be verified.`n`n" err.Message,
            "PACS Launch Not Verified",
            "Icon!"
        )
        return false
    }
    if !launchVerified {
        MsgBox(
            "The PACS shortcut ran, but one unique Vue PACS window did not appear. Check the client before trying again.",
            "PACS Launch Not Verified",
            "Icon!"
        )
        return false
    }
    return true
}
