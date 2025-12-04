#Requires AutoHotkey v2.0
#Include PACSCommands.ahk
#Include Settings.ahk

class HotkeyManager {
    static activeHotkeys := Map()
    static hotkeyFunctions := Map()
    static allowedWindows := ["PowerScribe", "Vue PACS", "Vue PACS Client", "Hyperspace", "ahk_exe mp.exe", "ahk_exe Nuance.PowerScribe360.exe"]

    static __New() {
        ; Initialize hotkey functions from PACSCommands
        this.hotkeyFunctions := PACSCommands.commands
    }

    static RegisterHotkey(funcName, hotkeyStr, scope := "default") {
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

        ; Resolve scope (default uses global setting)
        resolvedScope := scope = "default" ? (Settings.Get("RestrictHotkeysByActiveWindow") ? "restricted" : "global") : scope

        ; Register new hotkey
        try {
            boundFunc := this.hotkeyFunctions[funcName]
            handler := (*) => (this.IsHotkeyAllowed(resolvedScope) ? boundFunc() : 0)
            Hotkey(hotkeyStr, handler)
            this.activeHotkeys[funcName] := hotkeyStr
            return true
        } catch as err {
            MsgBox("Error setting hotkey: " hotkeyStr " for " funcName "`nError: " err.Message)
            return false
        }
    }

    static RegisterCustomHotkey(funcName, hotkeyStr, customFunc, scope := "default") {
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
            resolvedScope := scope = "default" ? (Settings.Get("RestrictHotkeysByActiveWindow") ? "restricted" : "global") : scope
            handler := (*) => (this.IsHotkeyAllowed(resolvedScope) ? customFunc() : 0)
            Hotkey(hotkeyStr, handler)
            this.activeHotkeys[funcName] := hotkeyStr
            return true
        } catch as err {
            MsgBox("Error setting hotkey: " hotkeyStr " for " funcName "`nError: " err.Message)
            return false
        }
    }

    static IsHotkeyAllowed(scope) {
        if (scope = "global")
            return true
        for winId in this.allowedWindows {
            if WinActive(winId)
                return true
        }
        return false
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
