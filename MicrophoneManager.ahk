#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include PowerScribe.ahk
#Include UIAValue.ahk

/**
 * Selects a microphone on the PowerScribe login screen.
 *
 * The microphone dropdown only exists while the login screen is up, so its presence
 * is what identifies that screen - the window title is the same before and after
 * logging in.
 */
class MicrophoneManager {
    ; The PowerScribe window is declared once, in PowerScribe, rather than restated
    ; here where the two copies could drift
    static winTitle => PowerScribe.windowTitle

    ; The dropdown, by AutomationId, with the positional path as a fallback for when
    ; the id changes. The fallback is only trusted if the element it lands on has the
    ; expected AutomationId, so a layout change can never make this poke some other
    ; control.
    static comboAutomationId := "cmbMicrophone"
    static comboPath := "Y3"

    static pollTimer := 0
    static pollInterval := 1000

    ; Login window currently being worked on, and how many times it has been tried.
    ; Bounded so a mismatched microphone name cannot retry forever.
    static attemptedWindow := 0
    static attempts := 0
    static maxAttempts := 3
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
        this.attempts := 0
        this.failureNotified := false
        this.lastError := ""
    }

    static OnSettingsChanged() {
        this.StartMonitoring()
    }

    static CheckForLogin() {
        try {
            hwnd := WinExist(this.winTitle)
            if !hwnd {
                ; PowerScribe closed - allow the next login to be handled
                this.attemptedWindow := 0
                this.attempts := 0
                this.failureNotified := false
                this.lastError := ""
                return
            }

            if (hwnd != this.attemptedWindow) {
                this.attemptedWindow := hwnd
                this.attempts := 0
                this.failureNotified := false
                this.lastError := ""
            }

            if (this.attempts >= this.maxAttempts)
                return

            combo := this.FindMicrophoneCombo(hwnd)
            if !combo
                return  ; Not on the login screen, or the picker has not rendered yet

            this.attempts++
            micName := Settings.Get("MicrophoneName")
            if this.SelectMicrophone(hwnd, combo, micName)
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
    static FindMicrophoneCombo(hwnd) {
        try {
            el := UIA.ElementFromHandle("ahk_id " hwnd)
        } catch {
            return 0
        }

        combo := el.WaitElement({AutomationId: this.comboAutomationId}, 500)
        if combo
            return combo

        ; Positional fallback, only accepted if it really is the microphone dropdown
        try {
            combo := el.ElementFromPath(this.comboPath)
            if (combo.AutomationId = this.comboAutomationId)
                return combo
        }

        return 0
    }

    /**
     * Selects micName in the dropdown, matching on substring so a stored name like
     * "PowerMic" matches "PowerMic III".
     * @returns true if the microphone ended up selected
     */
    static SelectMicrophone(hwnd, combo, micName) {
        micName := Trim(micName)
        if (micName = "")
            return false

        ; Already on the wanted microphone. Read through UIAValue so a combo box with
        ; no ValuePattern is handled as an unsupported capability rather than an error.
        if this.WaitForSelection(combo, micName, 0)
            return true

        ; Editable combo boxes accept the value directly; gated so an unsupported one
        ; falls through to the dropdown instead of erroring
        if UIAValue.Write(combo, micName) {
            if this.WaitForSelection(combo, micName, 300)
                return true
        }

        ; Otherwise open the list and pick the entry
        expanded := false
        try {
            combo.ExpandCollapsePattern.Expand()
            expanded := true
        } catch {
            try {
                combo.Click()
                expanded := true
            }
        }

        item := 0
        try {
            item := combo.WaitElement({Type: "ListItem", Name: micName, mm: "SubString"}, 1000)
        }
        if !item {
            ; Some frameworks host the dropdown list outside the combo element
            try {
                root := UIA.ElementFromHandle("ahk_id " hwnd)
                item := root.WaitElement({Type: "ListItem", Name: micName, mm: "SubString"}, 500)
            }
        }

        if !item {
            if expanded {
                try combo.ExpandCollapsePattern.Collapse()
            }
            return false
        }

        selected := false
        try {
            item.SelectionItemPattern.Select()
            selected := true
        } catch {
            try {
                item.Click()
                selected := true
            }
        }

        if expanded {
            try combo.ExpandCollapsePattern.Collapse()
        }

        return selected && this.WaitForSelection(combo, micName, 1000, item)
    }

    static WaitForSelection(combo, micName, timeoutMs, item := 0) {
        started := A_TickCount
        loop {
            if InStr(UIAValue.Read(combo), micName)
                return true
            if item {
                try {
                    if item.GetPropertyValue(UIA.Property.SelectionItemIsSelected)
                        return true
                }
            }
            if (A_TickCount - started >= timeoutMs)
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

        hwnd := WinExist(this.winTitle)
        if !hwnd {
            MsgBox("PowerScribe is not running.", "PACS Assistant", "Icon!")
            return false
        }

        combo := this.FindMicrophoneCombo(hwnd)
        if !combo {
            MsgBox("The microphone selector was not found. It is only available on the PowerScribe login screen.", "PACS Assistant", "Icon!")
            return false
        }

        if this.SelectMicrophone(hwnd, combo, micName)
            return true

        MsgBox("Could not select microphone '" micName "'. Check that the name matches an entry in the PowerScribe list.", "PACS Assistant", "Icon!")
        return false
    }
}
