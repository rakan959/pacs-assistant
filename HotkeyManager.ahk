#Requires AutoHotkey v2.0
#Include PACSCommands.ahk

class HotkeyManager {
    static activeHotkeys := Map()
    static hotkeyFunctions := Map()

    static __New() {
        ; Initialize hotkey functions from PACSCommands
        this.hotkeyFunctions := PACSCommands.commands
    }

    static RegisterHotkey(funcName, hotkeyStr) {
        ; Disable existing hotkey if it exists
        if this.activeHotkeys.Has(funcName) {
            try {
                Hotkey(this.activeHotkeys[funcName], "Off")
                this.activeHotkeys.Delete(funcName)
            }
        }

        ; Skip registration if the hotkey is unassigned
        if (hotkeyStr = "")
            return true

        ; Make sure we have a command to bind before attempting registration
        if !this.hotkeyFunctions.Has(funcName) {
            MsgBox("No command found for '" funcName "'. The keybind was not registered.")
            return false
        }

        ; Register new hotkey
        try {
            Hotkey(hotkeyStr, this.hotkeyFunctions[funcName])
            this.activeHotkeys[funcName] := hotkeyStr
            return true
        } catch as err {
            MsgBox("Error setting hotkey: " hotkeyStr " for " funcName "`nError: " err.Message)
            return false
        }
    }

    static RegisterCustomHotkey(funcName, hotkeyStr, customFunc) {
        ; Disable existing hotkey if it exists
        if this.activeHotkeys.Has(funcName) {
            try {
                Hotkey(this.activeHotkeys[funcName], "Off")
                this.activeHotkeys.Delete(funcName)
            }
        }

        ; Skip registration if the hotkey is unassigned
        if (hotkeyStr = "")
            return true

        ; Register new hotkey with the custom function
        try {
            Hotkey(hotkeyStr, customFunc)
            this.activeHotkeys[funcName] := hotkeyStr
            return true
        } catch as err {
            MsgBox("Error setting hotkey: " hotkeyStr " for " funcName "`nError: " err.Message)
            return false
        }
    }

    static DisableAllHotkeys() {
        for funcName, hk in this.activeHotkeys {
            try {
                Hotkey(hk, "Off")
            }
        }
        this.activeHotkeys.Clear()
    }
} 
