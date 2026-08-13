#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk

/**
 * Selects a microphone on the PowerScribe login screen.
 *
 * The microphone dropdown only exists while the login screen is up, so its presence
 * is what identifies that screen - the window title is the same before and after
 * logging in.
 */
class MicrophoneManager {
    static winTitle := "PowerScribe 360 | Reporting ahk_exe Nuance.PowerScribe360.exe"

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
                return
            }

            if (hwnd != this.attemptedWindow) {
                this.attemptedWindow := hwnd
                this.attempts := 0
            }

            if (this.attempts >= this.maxAttempts)
                return

            combo := this.FindMicrophoneCombo(hwnd)
            if !combo
                return  ; Not on the login screen, or the picker has not rendered yet

            this.attempts++
            if this.SelectMicrophone(hwnd, combo, Settings.Get("MicrophoneName"))
                this.attempts := this.maxAttempts  ; Done with this window
        } catch {
            ; Background polling must never surface an error dialog over PowerScribe
        }
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

        ; Already on the wanted microphone
        try {
            if InStr(combo.Value, micName)
                return true
        }

        ; Editable combo boxes accept the value directly
        try {
            combo.Value := micName
            if InStr(combo.Value, micName)
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

        return selected
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
