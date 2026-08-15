#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include AppControl.ahk
#Include UIAValue.ahk

class NativeMicrophoneSessionDriver {
    CaptureResult() {
        try sessions := AppControl.ResolveExactWindows(
            AppControl.PowerScribeWindowSpec()
        )
        catch as err
            return {status: "error", session: 0, error: err.Message}
        if !sessions.Length
            return {status: "absent", session: 0}
        if sessions.Length > 1
            return {status: "ambiguous", session: 0}
        return {status: "unique", session: sessions[1]}
    }

    IsLive(session) {
        return AppControl.ExactSessionIsUniqueAndLive(session)
    }

    Root(session) {
        if !this.IsLive(session)
            return 0
        try root := UIA.ElementFromHandle(session.target)
        catch
            return 0
        try return root.WinId = session.hwnd && root.ProcessId = session.processId
            ? root
            : 0
        return 0
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

    ; The login dropdown's stable semantic identity. Every candidate is enumerated
    ; and exactly one same-window enabled ComboBox is required before mutation.
    static comboAutomationId := "cmbMicrophone"

    static pollTimer := 0
    static pollInterval := 1000

    ; Login window currently being worked on, and how many times it has been tried.
    ; Bounded so a mismatched microphone name cannot retry forever.
    static attemptedWindow := 0
    static attempts := 0
    static maxAttempts := 3
    static pickerPresent := false
    static failureNotified := false
    static lastError := ""
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
        this.pickerPresent := false
        this.ResetAttemptState()
    }

    static OnSettingsChanged() {
        this.StartMonitoring()
    }

    static CheckForLogin() {
        try {
            resolution := this.sessionDriver.CaptureResult()
            if (!IsObject(resolution) || !HasProp(resolution, "status"))
                throw Error("PowerScribe window resolution returned an invalid result")

            if (resolution.status == "absent") {
                ; PowerScribe closed - allow the next login to be handled
                this.attemptedWindow := 0
                this.pickerPresent := false
                this.ResetAttemptState()
                return
            }
            if (resolution.status == "ambiguous" || resolution.status == "error") {
                this.RecordPickerPresence(false)
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

            if (session.hwnd != this.attemptedWindow) {
                this.attemptedWindow := session.hwnd
                this.pickerPresent := false
                this.ResetAttemptState()
            }

            combo := this.FindMicrophoneCombo(session)
            this.RecordPickerPresence(combo ? true : false)
            if !combo
                return  ; Not on the login screen, or the picker has not rendered yet

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
            this.attempts++
            this.RecordOperationalError(err)
            this.RecordSelectionFailure(Settings.Get("MicrophoneName"))
        }
    }

    static Notify(text, title, options := "") {
        try this.notifier.Call(text, title, options)
        catch as err {
            OutputDebug("Microphone notification failed: " err.Message)
        }
    }

    static ResetAttemptState() {
        this.attempts := 0
        this.failureNotified := false
        this.lastError := ""
    }

    ; A picker presence interval is one login session. Once it disappears, a later
    ; reappearance in the same HWND must receive a fresh bounded set of attempts.
    static RecordPickerPresence(present) {
        present := present ? true : false
        if (present = this.pickerPresent)
            return
        this.pickerPresent := present
        this.ResetAttemptState()
    }

    static RecordOperationalError(error) {
        this.lastError := IsObject(error) && HasProp(error, "Message") ? error.Message : String(error)
        OutputDebug("PowerScribe microphone selection failed: " this.lastError)
    }

    static RecordSelectionFailure(micName) {
        if (this.attempts < this.maxAttempts || this.failureNotified)
            return
        this.failureNotified := true
        this.Notify(
            "PACS Assistant could not confirm microphone '" Trim(micName) "' after " this.attempts " attempts.",
            "PowerScribe microphone was not changed",
            "Icon!"
        )
    }

    /**
     * @returns the microphone dropdown element, or 0 if it isn't present
     */
    static FindMicrophoneCombo(session) {
        try root := this.sessionDriver.Root(session)
        catch
            return 0
        return root ? this.FindMicrophoneComboInRoot(root) : 0
    }

    static FindMicrophoneComboInRoot(root) {
        matches := []
        try candidates := root.FindElements({AutomationId: this.comboAutomationId})
        catch
            return 0
        for candidate in candidates {
            if (this.IsExpectedMicrophoneCombo(root, candidate)
                && !this.ContainsSameElement(matches, candidate))
                matches.Push(candidate)
        }
        return matches.Length = 1 ? matches[1] : 0
    }

    static IsExpectedMicrophoneCombo(root, candidate) {
        if !root || !candidate
            return false
        try return root.ProcessId > 0
            && root.WinId > 0
            && candidate.ProcessId = root.ProcessId
            && candidate.WinId = root.WinId
            && candidate.Type = UIA.Type.ComboBox
            && candidate.AutomationId == this.comboAutomationId
            && candidate.IsEnabled
            && candidate.IsExpandCollapsePatternAvailable
        return false
    }

    static IsExpectedMicrophoneItem(root, item) {
        if !root || !item
            return false
        try return root.ProcessId > 0
            && root.WinId > 0
            && item.ProcessId = root.ProcessId
            && item.WinId = root.WinId
            && item.Type = UIA.Type.ListItem
            && item.IsEnabled
            && item.IsSelectionItemPatternAvailable
            && Trim(item.Name) != ""
        return false
    }

    static ContainsSameElement(elements, candidate) {
        for existing in elements {
            if this.SameElement(existing, candidate)
                return true
        }
        return false
    }

    static SameElement(left, right) {
        if !left || !right
            return false
        if (ObjPtr(left) = ObjPtr(right))
            return true
        try return UIA.CompareElementsEx(left, right)
        return false
    }

    static FindMicrophoneItems(root, combo) {
        items := []
        try {
            for item in combo.FindElements({Type: "ListItem"}) {
                if (this.IsExpectedMicrophoneItem(root, item)
                    && !this.ContainsSameElement(items, item))
                    items.Push(item)
            }
        }
        ; Some UI frameworks host the open dropdown beside the ComboBox in the same
        ; top-level window, so enumerate the exact root as well and deduplicate.
        try {
            for item in root.FindElements({Type: "ListItem"}) {
                if (this.IsExpectedMicrophoneItem(root, item)
                    && !this.ContainsSameElement(items, item))
                    items.Push(item)
            }
        }
        return items
    }

    static ResolveMicrophoneItem(root, combo, configuredName) {
        configuredName := Trim(configuredName)
        if (configuredName = ""
            || !this.IsExpectedMicrophoneCombo(root, combo))
            return 0

        exact := []
        partial := []
        for item in this.FindMicrophoneItems(root, combo) {
            fullName := Trim(item.Name)
            if (StrCompare(fullName, configuredName, false) = 0)
                exact.Push({item: item, name: fullName})
            else if InStr(fullName, configuredName, false)
                partial.Push({item: item, name: fullName})
        }
        if exact.Length
            return exact.Length = 1 ? exact[1] : 0
        return partial.Length = 1 ? partial[1] : 0
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
        combo := this.FindMicrophoneComboInRoot(root)
        return combo && this.SameElement(combo, expectedCombo)
            ? {root: root, combo: combo}
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
     * only when it identifies exactly one full device name.
     * @returns true if the microphone ended up selected
     */
    static SelectMicrophone(session, combo, micName) {
        micName := Trim(micName)
        if (micName = "")
            return false

        current := this.RevalidateCombo(session, combo)
        if !current
            return false
        try {
            current.combo.ExpandCollapsePattern.Expand()
        } catch as err {
            this.RecordOperationalError(err)
            return false
        }

        current := this.RevalidateCombo(session, combo)
        if !current
            return false
        resolved := this.ResolveMicrophoneItem(current.root, current.combo, micName)
        if !resolved {
            this.CollapseVerifiedCombo(session, combo)
            return false
        }

        if this.WaitForSelection(session, resolved.name, 0, resolved.item) {
            this.CollapseVerifiedCombo(session, combo)
            return true
        }

        ; Reacquire both semantic targets immediately before mutation. A dropdown can
        ; rerender after expansion; a saved wrapper is not sufficient proof.
        current := this.RevalidateCombo(session, combo)
        if !current
            return false
        liveResolved := this.ResolveMicrophoneItem(current.root, current.combo, micName)
        if (!liveResolved
            || !(liveResolved.name == resolved.name)
            || !this.SameElement(liveResolved.item, resolved.item)) {
            this.CollapseVerifiedCombo(session, combo)
            return false
        }

        try liveResolved.item.SelectionItemPattern.Select()
        catch as err {
            this.RecordOperationalError(err)
            this.CollapseVerifiedCombo(session, combo)
            return false
        }

        succeeded := this.WaitForSelection(
            session,
            liveResolved.name,
            1000,
            liveResolved.item
        )
        this.CollapseVerifiedCombo(session, combo)
        return succeeded
    }

    static WaitForSelection(session, fullName, timeoutMs, item := 0) {
        started := DllCall("GetTickCount64", "UInt64")
        loop {
            current := this.sessionDriver.Root(session)
            combo := current ? this.FindMicrophoneComboInRoot(current) : 0
            if combo {
                try value := UIAValue.TryRead(combo)
                catch
                    value := {supported: false, value: ""}
                if (value.supported
                    && StrCompare(Trim(value.value), Trim(fullName), false) = 0)
                    return true

                if item {
                    for currentItem in this.FindMicrophoneItems(current, combo) {
                        if (this.SameElement(currentItem, item)
                            && StrCompare(Trim(currentItem.Name), Trim(fullName), false) = 0) {
                            try {
                                if currentItem.GetPropertyValue(UIA.Property.SelectionItemIsSelected)
                                    return true
                            }
                        }
                    }
                }
            }
            if (DllCall("GetTickCount64", "UInt64") - started >= timeoutMs)
                return false
            Sleep(50)
        }
    }

    /**
     * Applies the configured microphone right now, reporting why if it can't.
     * Bound to the "Set PowerScribe Microphone" command.
     */
    static ApplyNow() {
        micName := Trim(Settings.Get("MicrophoneName"))
        if (micName = "") {
            MsgBox("No microphone is configured. Set one under Settings > PowerScribe.", "PACS Assistant", "Icon!")
            return false
        }

        resolution := this.sessionDriver.CaptureResult()
        if (!IsObject(resolution) || !HasProp(resolution, "status")) {
            MsgBox("PowerScribe window identity could not be verified.", "PACS Assistant", "Icon!")
            return false
        }
        if (resolution.status == "absent") {
            MsgBox("PowerScribe is not running.", "PACS Assistant", "Icon!")
            return false
        }
        if (resolution.status == "ambiguous") {
            MsgBox("Multiple exact PowerScribe reporting windows are open. Close the extra window before selecting a microphone.", "PACS Assistant", "Icon!")
            return false
        }
        if (!(resolution.status == "unique")
            || !HasProp(resolution, "session")
            || !resolution.session) {
            MsgBox("PowerScribe window identity could not be verified.", "PACS Assistant", "Icon!")
            return false
        }
        session := resolution.session

        combo := this.FindMicrophoneCombo(session)
        if !combo {
            MsgBox("The microphone selector was not found. It is only available on the PowerScribe login screen.", "PACS Assistant", "Icon!")
            return false
        }

        if this.SelectMicrophone(session, combo, micName)
            return true

        MsgBox("Could not select microphone '" micName "'. Check that the name matches an entry in the PowerScribe list.", "PACS Assistant", "Icon!")
        return false
    }
}
