; = CONTENTS
;   + Preamble
;   + NativeMicrophoneSessionDriver (microphone picker window & UIA primitives)
;   + MicrophoneManager class (background microphone check, selection, notifications)

#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include AppControl.ahk
#Include UIAValue.ahk
#Include UIAElementIdentity.ahk
#Include ErrorText.ahk
#Include AppLog.ahk

class NativeMicrophoneSessionDriver {
    CaptureResult() {
        return AppControl.ResolveUniqueExactWindowStatus(AppControl.PowerScribeWindowSpec())
    }

    IsLive(session) {
        return AppControl.ExactSessionIsUniqueAndLive(session)
    }

    Root(session) {
        return this.IsLive(session) ? AppControl.VerifiedUiaRoot(session) : 0
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }

    Pause(milliseconds) {
        Sleep(milliseconds)
    }
}

/**
 * Selects a microphone on the PowerScribe login screen.
 *
 * The microphone dropdown only exists while the login screen is up, so its presence
 * is what identifies that screen - the window title is the same before and after
 * logging in.
 */
class MicrophoneManager {
    static sessionDriver := NativeMicrophoneSessionDriver()
    static automationAcquire := (*) => {status: "acquired", busyCommand: ""}
    static automationRelease := (*) => 0

    ; The login dropdown's stable semantic identity. Every candidate is enumerated
    ; and exactly one same-window enabled ComboBox is required before mutation.
    static comboAutomationId := "cmbMicrophone"

    static pollTimer := 0
    static pollInterval := 1000

    ; Login window currently being worked on, and how many times it has been tried.
    ; Bounded so a mismatched microphone name cannot retry forever.
    static attemptedWindow := 0
    static attemptedProcessId := 0
    static attempts := 0
    static maxAttempts := 3
    static failureNotified := false
    static lastError := ""
    ; Why SelectMicrophone stops when PowerScribe rerenders the login screen under it
    static selectorChangedReason := "the microphone selector changed before the selection could be made"
    static listChangedReason := "the microphone list changed before the selection could be made"
    static notifier := (text, title, options) => TrayTip(text, title, options)

    static Start() {
        this.StartMonitoring()
    }

    static StartMonitoring() {
        this.StopMonitoring()

        if !Settings.Get("SwapMicrophoneOnLogin")
            return
        if (Trim(Settings.Get("MicrophoneName")) = "")
            return

        this.pollTimer := ObjBindMethod(this, "CheckForLogin")
        SetTimer(this.pollTimer, this.pollInterval)
    }

    static StopMonitoring() {
        if this.pollTimer {
            SetTimer(this.pollTimer, 0)
            this.pollTimer := 0
        }
        this.attemptedWindow := 0
        this.attemptedProcessId := 0
        this.ResetAttemptState()
    }

    static OnSettingsChanged() {
        this.StartMonitoring()
    }

    static CheckForLogin() {
        lease := this.automationAcquire.Call("PowerScribe microphone check")
        if (!IsObject(lease)
            || !HasProp(lease, "status")
            || lease.status != "acquired")
            return false
        try return this.CheckForLoginWithinLease()
        finally this.automationRelease.Call()
    }

    static CheckForLoginWithinLease() {
        try {
            resolution := this.sessionDriver.CaptureResult()
            if (!IsObject(resolution) || !HasProp(resolution, "status"))
                throw Error("PowerScribe window resolution returned an invalid result")

            if (resolution.status == "absent") {
                ; PowerScribe closed - allow the next login to be handled
                this.attemptedWindow := 0
                this.attemptedProcessId := 0
                this.ResetAttemptState()
                return
            }
            if (resolution.status == "ambiguous" || resolution.status == "error") {
                if (this.attempts >= this.maxAttempts)
                    return
                this.attempts++
                detail := resolution.status == "ambiguous"
                    ? "multiple exact PowerScribe reporting windows are open"
                    : "PowerScribe window lookup failed: " (HasProp(resolution, "error") ? resolution.error : "unknown error")
                this.RecordOperationalError(detail)
                this.RecordSelectionFailure(Settings.Get("MicrophoneName"))
                return
            }
            if (!(resolution.status == "unique")
                || !HasProp(resolution, "session")
                || !resolution.session)
                throw Error("PowerScribe window resolution returned an invalid unique result")
            session := resolution.session

            this.RecordAttemptedSession(session)

            comboResult := this.ResolveMicrophoneCombo(session)
            if (comboResult.status == "absent") {
                this.RecordPickerAbsence()
                return  ; Logged in, or the picker has not rendered yet
            }
            if !(comboResult.status == "found") {
                if (this.attempts >= this.maxAttempts)
                    return
                this.attempts++
                this.RecordOperationalError(comboResult.error)
                this.RecordSelectionFailure(Settings.Get("MicrophoneName"))
                return
            }
            combo := comboResult.combo

            if (this.attempts >= this.maxAttempts)
                return

            this.attempts++
            micName := Settings.Get("MicrophoneName")
            if this.SelectMicrophone(session, combo, micName)
                this.attempts := this.maxAttempts  ; Done with this window
            else
                this.RecordSelectionFailure(micName)
        } catch as err {
            ; Background polling must never surface an error dialog over PowerScribe,
            ; but it must leave evidence and eventually notify instead of disappearing.
            if (this.attempts >= this.maxAttempts)
                return
            this.attempts++
            this.RecordOperationalError(err)
            this.RecordSelectionFailure(Settings.Get("MicrophoneName"))
        }
    }

    static Notify(text, title, options := "") {
        try this.notifier.Call(text, title, options)
        catch Any as err {
            AppLog.Write("Microphone notification failed: " ErrorText.Describe(err))
        }
    }

    static ResetAttemptState() {
        this.attempts := 0
        this.failureNotified := false
        this.lastError := ""
    }

    ; HWNDs can be recycled across PowerScribe processes without an observed absent
    ; poll. Treat the concrete HWND/PID pair as the retry-session identity.
    static RecordAttemptedSession(session) {
        if (!IsObject(session)
            || !HasProp(session, "hwnd")
            || !HasProp(session, "processId")
            || session.hwnd <= 0
            || session.processId <= 0)
            throw Error("PowerScribe login session identity is invalid")
        if (session.hwnd = this.attemptedWindow
            && session.processId = this.attemptedProcessId)
            return false
        this.attemptedWindow := session.hwnd
        this.attemptedProcessId := session.processId
        this.ResetAttemptState()
        return true
    }

    ; Only a confirmed picker absence ends the current login interval. Provider errors
    ; and ambiguity are uncertainty, not evidence of disappearance, and must continue
    ; consuming the same bounded retry budget.
    static RecordPickerAbsence() {
        this.ResetAttemptState()
    }

    static RecordOperationalError(err) {
        this.lastError := ErrorText.Message(err)
        OutputDebug("PowerScribe microphone selection failed: " this.lastError)
    }

    static RecordSelectionFailure(micName) {
        if (this.attempts < this.maxAttempts || this.failureNotified)
            return
        this.failureNotified := true
        message := "PACS Assistant could not confirm microphone '" Trim(micName) "' after " this.attempts " attempts."
        if (this.lastError != "")
            message .= " Last error: " this.lastError
        ; Logged once per login session, with the notice, rather than once per poll.
        AppLog.Write("PowerScribe microphone was not changed: " message)
        this.Notify(message, "PowerScribe Microphone Not Changed", "Icon!")
    }

    ; Picker absence is expected after login. Identity ambiguity and provider failures
    ; remain distinct so the bounded background retry can notify instead of going quiet.
    static ResolveMicrophoneCombo(session) {
        try root := this.sessionDriver.Root(session)
        catch as err
            return {status: "error", combo: 0, error: err.Message}
        if !root
            return {
                status: "error",
                combo: 0,
                error: "PowerScribe UI Automation root could not be verified"
            }
        return this.ResolveMicrophoneComboInRoot(root)
    }

    static ResolveMicrophoneComboInRoot(root) {
        try {
            candidates := root.FindElements({AutomationId: this.comboAutomationId})
            if !IsObject(candidates)
                throw Error("microphone picker lookup returned an invalid collection")
            matches := []
            for candidate in candidates {
                if (this.InspectMicrophoneCombo(root, candidate)
                    && !UIAElementIdentity.Contains(matches, candidate))
                    matches.Push(candidate)
            }
        } catch as err {
            return {status: "error", combo: 0, error: err.Message}
        }

        if (matches.Length = 1)
            return {status: "found", combo: matches[1], error: ""}
        if (matches.Length > 1)
            return {
                status: "ambiguous",
                combo: 0,
                error: "multiple exact microphone pickers were found"
            }
        if candidates.Length
            return {
                status: "error",
                combo: 0,
                error: "the microphone picker did not have its expected identity or capability"
            }
        return {status: "absent", combo: 0, error: ""}
    }

    static InspectMicrophoneCombo(root, candidate) {
        if !root || !candidate
            return false
        identityMatches := root.ProcessId > 0
            && root.WinId > 0
            && candidate.ProcessId = root.ProcessId
            && candidate.WinId = root.WinId
            && candidate.Type = UIA.Type.ComboBox
            && candidate.AutomationId == this.comboAutomationId
            && candidate.IsEnabled
            && candidate.IsExpandCollapsePatternAvailable
        if !identityMatches
            return false
        ; Selection is unsafe when the only authoritative postcondition cannot be
        ; read. Reject it before expanding or selecting anything.
        return UIAValue.TryRead(candidate).supported
    }

    static InspectMicrophoneItem(root, combo, item) {
        if (!root
            || !combo
            || !item
            || !this.InspectMicrophoneCombo(root, combo))
            return false
        if !(root.ProcessId > 0
            && root.WinId > 0
            && item.ProcessId = root.ProcessId
            && item.WinId = root.WinId
            && item.Type = UIA.Type.ListItem
            && item.IsEnabled
            && item.IsSelectionItemPatternAvailable
            && Trim(item.Name) != "")
            return false
        container := item.SelectionItemPattern.SelectionContainer
        return UIAElementIdentity.SameStrict(container, combo)
    }

    static ResolveMicrophoneItems(root, combo) {
        items := []
        try {
            if !this.InspectMicrophoneCombo(root, combo)
                throw Error("the microphone picker no longer has its expected identity")
            comboItems := combo.FindElements({Type: "ListItem"})
            if !IsObject(comboItems)
                throw Error("microphone item lookup returned an invalid collection")
            for item in comboItems {
                if (this.InspectMicrophoneItem(root, combo, item)
                    && !UIAElementIdentity.Contains(items, item))
                    items.Push(item)
            }
            ; Some UI frameworks host the open dropdown beside the ComboBox in the
            ; same top-level window, so enumerate the exact root as well and dedupe.
            rootItems := root.FindElements({Type: "ListItem"})
            if !IsObject(rootItems)
                throw Error("microphone item lookup returned an invalid collection")
            for item in rootItems {
                if (this.InspectMicrophoneItem(root, combo, item)
                    && !UIAElementIdentity.Contains(items, item))
                    items.Push(item)
            }
        } catch as err {
            return {status: "error", items: [], error: err.Message}
        }
        if items.Length
            return {status: "found", items: items, error: ""}
        ; No verified item says nothing about the configured name, so it is an error
        ; with its own reason rather than "no device by that name".
        return {
            status: "error",
            items: [],
            error: comboItems.Length
                ? "the microphone list items did not have their expected identity"
                : "the microphone list exposed no items"
        }
    }

    static ResolveMicrophoneItemResult(root, combo, configuredName) {
        configuredName := Trim(configuredName)
        if (configuredName = "")
            return {status: "absent", selection: 0, error: ""}

        itemResult := this.ResolveMicrophoneItems(root, combo)
        if (itemResult.status == "error")
            return {status: "error", selection: 0, error: itemResult.error}

        exact := []
        partial := []
        try {
            for item in itemResult.items {
                fullName := Trim(item.Name)
                if (StrCompare(fullName, configuredName, false) = 0)
                    exact.Push({item: item, name: fullName})
                else if InStr(fullName, configuredName, false)
                    partial.Push({item: item, name: fullName})
            }
        } catch as err {
            return {status: "error", selection: 0, error: err.Message}
        }
        if exact.Length = 1
            return {status: "found", selection: exact[1], error: ""}
        if exact.Length > 1
            return {status: "ambiguous", selection: 0, error: "multiple exact microphone items were found"}
        if partial.Length = 1
            return {status: "found", selection: partial[1], error: ""}
        if partial.Length > 1
            return {status: "ambiguous", selection: 0, error: "the microphone name matches multiple devices"}
        return {status: "absent", selection: 0, error: ""}
    }

    static RevalidateCombo(session, expectedCombo) {
        try {
            if !this.sessionDriver.IsLive(session)
                return 0
            root := this.sessionDriver.Root(session)
        } catch {
            return 0
        }
        if !root
            return 0
        result := this.ResolveMicrophoneComboInRoot(root)
        return result.status == "found"
            && UIAElementIdentity.Same(result.combo, expectedCombo)
            ? {root: root, combo: result.combo}
            : 0
    }

    static CollapseVerifiedCombo(session, expectedCombo) {
        current := this.RevalidateCombo(session, expectedCombo)
        if !current
            return false
        try {
            current.combo.ExpandCollapsePattern.Collapse()
            return true
        }
        return false
    }

    /**
     * Selects a real list item. Exact names win; a configured substring is accepted
     * only when it identifies exactly one full device name. Every way it stops
     * short records why in lastError, except a name that matches no device.
     * @returns true if the microphone ended up selected
     */
    static SelectMicrophone(session, combo, micName) {
        micName := Trim(micName)
        if (micName = "")
            return this.SelectionStopped("no microphone name is configured")

        current := this.RevalidateCombo(session, combo)
        if !current
            return this.SelectionStopped(this.selectorChangedReason)
        try {
            current.combo.ExpandCollapsePattern.Expand()
        } catch as err {
            this.RecordOperationalError(err)
            return false
        }

        current := this.RevalidateCombo(session, combo)
        if !current
            return this.SelectionStopped(this.selectorChangedReason)
        itemResult := this.ResolveMicrophoneItemResult(current.root, current.combo, micName)
        if (itemResult.error != "")
            this.RecordOperationalError(itemResult.error)
        if !(itemResult.status == "found") {
            this.CollapseVerifiedCombo(session, combo)
            return false
        }
        resolved := itemResult.selection

        if this.WaitForSelection(session, resolved.name, 0) {
            this.CollapseVerifiedCombo(session, combo)
            return true
        }

        ; Reacquire both semantic targets immediately before mutation. A dropdown can
        ; rerender after expansion; a saved wrapper is not sufficient proof.
        current := this.RevalidateCombo(session, combo)
        if !current
            return this.SelectionStopped(this.selectorChangedReason)
        liveResult := this.ResolveMicrophoneItemResult(current.root, current.combo, micName)
        if !(liveResult.status == "found") {
            this.CollapseVerifiedCombo(session, combo)
            return this.SelectionStopped(
                liveResult.error != "" ? liveResult.error : this.listChangedReason
            )
        }
        liveResolved := liveResult.selection
        if (!liveResolved
            || !(liveResolved.name == resolved.name)
            || !UIAElementIdentity.Same(liveResolved.item, resolved.item)) {
            this.CollapseVerifiedCombo(session, combo)
            return this.SelectionStopped(this.listChangedReason)
        }

        ; Item enumeration can yield while PowerScribe rerenders. Reacquire the
        ; exact ComboBox one final time and prove its value remains readable at the
        ; last safe boundary before SelectionItem.Select().
        finalCombo := this.RevalidateCombo(session, combo)
        if (!finalCombo
            || !UIAElementIdentity.Same(finalCombo.combo, current.combo)) {
            this.CollapseVerifiedCombo(session, combo)
            return this.SelectionStopped(this.selectorChangedReason)
        }
        try readable := UIAValue.TryRead(finalCombo.combo).supported
        catch as err {
            this.RecordOperationalError(err)
            this.CollapseVerifiedCombo(session, combo)
            return false
        }
        if !readable {
            this.CollapseVerifiedCombo(session, combo)
            return this.SelectionStopped("the microphone selector's value could not be read")
        }

        ; The final ComboBox read can itself rerender the dropdown. Reacquire the
        ; exact uniquely named item from that final root and prove it is the same
        ; semantic element immediately before SelectionItem.Select().
        finalItemResult := this.ResolveMicrophoneItemResult(
            finalCombo.root,
            finalCombo.combo,
            liveResolved.name
        )
        if !(finalItemResult.status == "found") {
            this.CollapseVerifiedCombo(session, combo)
            return this.SelectionStopped(
                finalItemResult.error != "" ? finalItemResult.error : this.listChangedReason
            )
        }
        finalResolved := finalItemResult.selection
        try itemIsExpected := finalResolved
            && finalResolved.name == liveResolved.name
            && UIAElementIdentity.Same(finalResolved.item, liveResolved.item)
            && this.InspectMicrophoneItem(
                finalCombo.root,
                finalCombo.combo,
                finalResolved.item
            )
        catch as err {
            this.RecordOperationalError(err)
            this.CollapseVerifiedCombo(session, combo)
            return false
        }
        if !itemIsExpected {
            this.CollapseVerifiedCombo(session, combo)
            return this.SelectionStopped(this.listChangedReason)
        }

        try finalResolved.item.SelectionItemPattern.Select()
        catch as err {
            this.RecordOperationalError(err)
            this.CollapseVerifiedCombo(session, combo)
            return false
        }

        succeeded := this.WaitForSelection(
            session,
            finalResolved.name,
            1000
        )
        this.CollapseVerifiedCombo(session, combo)
        if !succeeded
            return this.SelectionStopped("PowerScribe did not confirm the selection within 1 second")
        return true
    }

    ; Records why SelectMicrophone stopped short and returns its false result.
    static SelectionStopped(reason) {
        this.RecordOperationalError(reason)
        return false
    }

    static WaitForSelection(session, fullName, timeoutMs) {
        started := this.sessionDriver.NowMilliseconds()
        loop {
            try current := this.sessionDriver.Root(session)
            catch
                current := 0
            result := current
                ? this.ResolveMicrophoneComboInRoot(current)
                : {status: "error", combo: 0}
            if (result.status == "found") {
                try value := UIAValue.TryRead(result.combo)
                catch
                    value := {supported: false, value: ""}
                if (value.supported
                    && StrCompare(Trim(value.value), Trim(fullName), false) = 0)
                    return true
            }
            if (this.sessionDriver.NowMilliseconds() - started >= timeoutMs)
                return false
            this.sessionDriver.Pause(50)
        }
    }

    /**
     * Applies the configured microphone right now, reporting why if it can't.
     * Bound to the "Set PowerScribe Microphone" command.
     */
    static ApplyNow() {
        micName := Trim(Settings.Get("MicrophoneName"))
        if (micName = "")
            return this.ApplyNowFailed("No microphone is configured. Set one under Settings > PowerScribe.", "No Microphone Configured")

        resolution := this.sessionDriver.CaptureResult()
        status := IsObject(resolution) && HasProp(resolution, "status") ? resolution.status : ""
        if (status == "absent")
            return this.ApplyNowFailed("PowerScribe is not running.", "PowerScribe Not Running")
        if (status == "ambiguous")
            return this.ApplyNowFailed(
                "Multiple exact PowerScribe reporting windows are open. Close the extra window before selecting a microphone.",
                "Multiple PowerScribe Windows"
            )
        if (!(status == "unique") || !HasProp(resolution, "session") || !resolution.session) {
            detail := status == "error" && HasProp(resolution, "error") && resolution.error != ""
                ? "`n`n" resolution.error
                : ""
            return this.ApplyNowFailed("PowerScribe window identity could not be verified." detail, "PowerScribe Not Verified")
        }
        session := resolution.session

        comboResult := this.ResolveMicrophoneCombo(session)
        if (comboResult.status == "absent")
            return this.ApplyNowFailed(
                "The microphone selector was not found. It is only available on the PowerScribe login screen.",
                "Microphone Selector Not Found"
            )
        if !(comboResult.status == "found")
            return this.ApplyNowFailed(
                "The microphone selector identity could not be verified.`n`n" comboResult.error,
                "Microphone Selector Not Verified"
            )

        this.lastError := ""
        if this.SelectMicrophone(session, comboResult.combo, micName)
            return true
        ; SelectMicrophone records why, e.g. a name that matches several devices.
        return this.ApplyNowFailed(
            "Could not select microphone '" micName "'"
                . (this.lastError != ""
                    ? ": " this.lastError "."
                    : ". Check that the name matches an entry in the PowerScribe list."),
            "Microphone Not Selected"
        )
    }

    ; ApplyNow runs from the user's own hotkey, so its result is a dialog; the log
    ; keeps it for later diagnosis.
    static ApplyNowFailed(message, title) {
        AppLog.Write(title ": " StrReplace(message, "`n`n", " "))
        MsgBox(message, title, "Icon!")
        return false
    }
}
