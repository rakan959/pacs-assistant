#Requires AutoHotkey v2.0
#Include HotkeyContract.ahk
#Include PACSCommands.ahk

class NativeHotkeyDriver {
    Enable(hotkeyStr, callback) {
        Hotkey(hotkeyStr, callback, "On")
    }

    Disable(hotkeyStr) {
        Hotkey(hotkeyStr, "Off")
    }
}

class HotkeyManager {
    static activeHotkeys := Map()  ; funcName -> {hotkey: "^j", scope: "PACS"}
    static hotkeyFunctions := PACSCommands.commands
    static hotkeyDriver := NativeHotkeyDriver()

    ; Why the last Register call failed. Registration reports failure by return value
    ; rather than a dialog, so KeybindGUI.ApplyProfileBinds can collect every failure
    ; and show one message instead of a dialog per bind.
    static lastError := ""

    ; One persistent predicate per scope. AutoHotkey identifies a hotkey *variant* by
    ; the exact function object handed to HotIf, so these are created once and reused:
    ; building a fresh closure per registration would create a new variant every time
    ; and leave the previous one registered and unreachable.
    static scopePredicates := Map(
        "PACS", (*) => HotkeyManager.PACSIsActive(),
        "PowerScribe", (*) => HotkeyManager.PowerScribeIsActive(),
        "PACS or PowerScribe", (*) => HotkeyManager.PACSIsActive() || HotkeyManager.PowerScribeIsActive()
    )

    static PACSIsActive(exactWindowProbe := 0) {
        specs := [
            AppControl.VuePacsWindowSpec(),
            AppControl.VuePacsClientWindowSpec()
        ]
        return exactWindowProbe
            ? exactWindowProbe.Call(specs)
            : AppControl.IsUniqueExactWindowActive(specs)
    }

    static PowerScribeIsActive(exactWindowProbe := 0) {
        specs := [AppControl.PowerScribeWindowSpec()]
        return exactWindowProbe
            ? exactWindowProbe.Call(specs)
            : AppControl.IsUniqueExactWindowActive(specs)
    }

    ; Enter the HotIf context a scope registers under. Always paired with ExitScope().
    static EnterScope(scope) {
        scope := HotkeyContract.RequireScope(scope)
        if this.scopePredicates.Has(scope)
            HotIf(this.scopePredicates[scope])
        else if (scope == "Any")
            HotIf()  ; Global context
        else
            throw ValueError("No restricted predicate is defined for hotkey scope: " scope)
    }

    static ExitScope() {
        HotIf()
    }

    static CallbackForScope(callback, scope) {
        scope := HotkeyContract.RequireScope(scope)
        if (scope == "Any")
            return callback
        return (args*) => HotkeyManager.InvokeCallbackForScope(
            scope,
            callback,
            args*
        )
    }

    static InvokeCallbackForScope(scope, callback, args*) {
        ; HotIf is evaluated when AutoHotkey accepts the physical key event. Focus
        ; can change before its callback runs, so restricted registrations require
        ; the same exact-window predicate again at the action boundary.
        try {
            if !this.scopePredicates.Has(scope)
                return false
            if !this.scopePredicates[scope].Call()
                return false
        } catch {
            return false
        }
        return callback.Call(args*)
    }

    static RegisterHotkey(funcName, hotkeyStr, scope := "Any") {
        callback := this.hotkeyFunctions.Has(funcName) ? this.hotkeyFunctions[funcName] : 0
        return this.Register(funcName, hotkeyStr, callback, scope)
    }

    static Register(funcName, hotkeyStr, callback, scope := "Any") {
        this.lastError := ""

        ; Skip registration if the hotkey is unassigned
        if (hotkeyStr = "") {
            return this.Unregister(funcName)
        }

        if !HotkeyContract.IsValidScope(scope) {
            this.lastError := "the hotkey scope is unknown"
            return false
        }

        if !callback {
            this.lastError := "no command is defined for it"
            return false
        }

        ; KeybindGUI.ApplyProfileBinds disables every hotkey before registering a
        ; profile, so a function is registered at most once. A live registration is
        ; not replaced in place: AutoHotkey finds an existing variant by its
        ; spelling, so re-registering under an alias (^Esc, then ^Escape) would
        ; leave the first variant live and untracked.
        if this.activeHotkeys.Has(funcName) {
            this.lastError := "'" funcName "' already has a registered hotkey"
            return false
        }

        owner := this.FindBindingOwner(hotkeyStr)
        if owner {
            this.lastError := "the hotkey is already registered to '" owner "'"
            return false
        }

        ; AutoHotkey itself is the final authority on key-name validity.
        try {
            this.EnterScope(scope)
            ; "On" is load-bearing. Hotkey() updates an existing variant's action but
            ; leaves its enabled state alone, so without it a bind that
            ; DisableAllHotkeys turned off would stay off after re-registration.
            this.hotkeyDriver.Enable(
                hotkeyStr,
                this.CallbackForScope(callback, scope)
            )
        } catch as err {
            this.lastError := err.Message
            return false
        } finally {
            this.ExitScope()
        }

        this.activeHotkeys[funcName] := {hotkey: hotkeyStr, scope: scope}
        return true
    }

    static FindBindingOwner(hotkeyStr) {
        identity := HotkeyContract.BindingIdentity(hotkeyStr)
        for funcName, entry in this.activeHotkeys {
            if (HotkeyContract.BindingIdentity(entry.hotkey) = identity)
                return funcName
        }
        return ""
    }

    static DisableEntry(entry) {
        try {
            this.EnterScope(entry.scope)
            this.hotkeyDriver.Disable(entry.hotkey)
        } finally {
            this.ExitScope()
        }
    }

    ; Turn off a single registration, re-entering the context it was created in.
    ; Hotkey(name, "Off") only affects the variant of the *current* HotIf context, so
    ; the scope has to be restored before the hotkey can be turned off. On failure,
    ; failureDetail names the hotkey that stayed on and why.
    static Unregister(funcName, &failureDetail := "") {
        this.lastError := ""
        failureDetail := ""
        if !this.activeHotkeys.Has(funcName)
            return true

        entry := this.activeHotkeys[funcName]
        try {
            this.DisableEntry(entry)
        } catch as err {
            ; Keep the registration tracked until the native provider proves it is
            ; disabled. Losing the registry entry here can leave a live clinical
            ; action enabled with no way for later profile operations to retire it.
            failureDetail := entry.hotkey ": " err.Message
            this.lastError := "the hotkey could not be disabled: " failureDetail
            return false
        }
        this.activeHotkeys.Delete(funcName)
        return true
    }

    static DisableAllHotkeys() {
        ; Unregister removes each entry it turns off, so walk a copy. An entry whose
        ; native Off call failed stays tracked.
        failed := ""
        for funcName, _ in this.activeHotkeys.Clone() {
            if !this.Unregister(funcName, &failureDetail)
                failed .= (failed = "" ? "" : ", ") funcName " (" failureDetail ")"
        }
        if (failed != "")
            throw Error("These hotkeys could not be disabled: " failed)
        return true
    }
}
