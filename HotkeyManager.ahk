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
    ; Registrations whose rollback could not be verified remain separately tracked.
    ; Losing either possibly-live variant would make later teardown fail open.
    static additionalActiveHotkeys := Map()
    static hotkeyFunctions := Map()
    static hotkeyDriver := NativeHotkeyDriver()

    ; Why the last Register call failed. Registration reports failure by return value
    ; rather than a dialog, so ApplyBinds can collect every failure and show one
    ; message instead of a dialog per bind.
    static lastError := ""

    ; Scope names in the order they are presented, and the only values persisted to a
    ; profile. "Any" means the bind fires regardless of which window has focus.
    static scopes := HotkeyContract.scopes

    ; One persistent predicate per scope. AutoHotkey identifies a hotkey *variant* by
    ; the exact function object handed to HotIf, so these are created once and reused:
    ; building a fresh closure per registration would create a new variant every time
    ; and leave the previous one registered and unreachable.
    static scopePredicates := Map(
        "PACS", (*) => WinActive("ahk_exe mp.exe"),
        "PowerScribe", (*) => HotkeyManager.PowerScribeIsActive(),
        "PACS or PowerScribe", (*) => WinActive("ahk_exe mp.exe") || HotkeyManager.PowerScribeIsActive()
    )

    static __New() {
        ; Initialize hotkey functions from PACSCommands
        this.hotkeyFunctions := PACSCommands.commands
    }

    ; Validate a scope at the runtime boundary. Registration must never broaden an
    ; unknown value to the global context.
    static NormalizeScope(scope) {
        return HotkeyContract.RequireScope(scope)
    }

    ; Build a scope name from the two "only when ... is active" checkboxes
    static ScopeFromFlags(requirePACS, requirePowerScribe) {
        return HotkeyContract.ScopeFromFlags(requirePACS, requirePowerScribe)
    }

    static PowerScribeIsActive(activeWindowMatcher := 0) {
        selector := AppControl.PowerScribeProcessTarget()
        return activeWindowMatcher
            ? activeWindowMatcher.Call(selector)
            : WinActive(selector)
    }

    ; Inverse of ScopeFromFlags
    static FlagsFromScope(scope) {
        return HotkeyContract.FlagsFromScope(scope)
    }

    ; Enter the HotIf context a scope registers under. Always paired with ExitScope().
    static EnterScope(scope) {
        scope := this.NormalizeScope(scope)
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

    static RegisterHotkey(funcName, hotkeyStr, scope := "Any") {
        callback := this.hotkeyFunctions.Has(funcName) ? this.hotkeyFunctions[funcName] : 0
        return this.Register(funcName, hotkeyStr, callback, scope)
    }

    static RegisterCustomHotkey(funcName, hotkeyStr, customFunc, scope := "Any") {
        return this.Register(funcName, hotkeyStr, customFunc, scope)
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

        if this.additionalActiveHotkeys.Count {
            this.lastError := "a previous hotkey rollback is still active; disable all hotkeys or restart before registering another bind"
            return false
        }

        owner := this.FindBindingOwner(hotkeyStr, funcName)
        if owner {
            this.lastError := "the hotkey is already registered to '" owner "'"
            return false
        }

        previous := this.activeHotkeys.Has(funcName)
            ? this.activeHotkeys[funcName]
            : 0
        sameVariant := previous
            && this.HotkeyIdentity(previous.hotkey) = this.HotkeyIdentity(hotkeyStr)
            && previous.scope = scope

        ; AutoHotkey itself is the final authority on key-name validity. Activate a
        ; distinct replacement before retiring the known-good variant, so a rejected
        ; key or provider error cannot silently unbind the command.
        try {
            this.EnterScope(scope)
            ; "On" is load-bearing. Hotkey() updates an existing variant's action but
            ; leaves its enabled state alone, so a bind that DisableAllHotkeys turned
            ; off stayed dead after being re-registered - which is how binds silently
            ; stopped working after editing a keybind or switching profiles.
            this.hotkeyDriver.Enable(hotkeyStr, callback)
        } catch as err {
            this.lastError := err.Message
            return false
        } finally {
            this.ExitScope()
        }

        if previous && !sameVariant {
            try {
                this.DisableEntry(previous)
            } catch as err {
                ; The replacement is live but the old variant could not be retired.
                ; Roll it back and keep the prior map entry rather than claiming an
                ; ambiguous two-registration state succeeded.
                try {
                    this.DisableEntry({hotkey: hotkeyStr, scope: scope})
                } catch as rollbackErr {
                    ; Both variants may now be live. Keep the replacement reachable
                    ; so DisableAllHotkeys can retry it and block new registrations
                    ; until native teardown is proven.
                    this.TrackAdditionalActiveHotkey(funcName, hotkeyStr, scope)
                    this.lastError := "the previous hotkey could not be disabled: " err.Message
                        . "; the replacement rollback also failed: " rollbackErr.Message
                    return false
                }
                this.lastError := "the previous hotkey could not be disabled: " err.Message
                return false
            }
        }

        this.activeHotkeys[funcName] := {hotkey: hotkeyStr, scope: scope}
        return true
    }

    static HotkeyIdentity(hotkeyStr) {
        return HotkeyContract.BindingIdentity(hotkeyStr)
    }

    static FindBindingOwner(hotkeyStr, exceptFuncName := "") {
        identity := this.HotkeyIdentity(hotkeyStr)
        for funcName, entry in this.activeHotkeys {
            if (funcName != exceptFuncName && this.HotkeyIdentity(entry.hotkey) = identity)
                return funcName
        }
        for _, entry in this.additionalActiveHotkeys {
            if (!(entry.funcName == exceptFuncName)
                && this.HotkeyIdentity(entry.hotkey) = identity)
                return entry.funcName
        }
        return ""
    }

    static TrackAdditionalActiveHotkey(funcName, hotkeyStr, scope) {
        entry := {funcName: funcName, hotkey: hotkeyStr, scope: scope}
        key := funcName Chr(31) scope Chr(31) this.HotkeyIdentity(hotkeyStr)
        this.additionalActiveHotkeys[key] := entry
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
    ; the scope has to be restored before the hotkey can be turned off.
    static Unregister(funcName) {
        this.lastError := ""
        failures := []

        if this.activeHotkeys.Has(funcName) {
            entry := this.activeHotkeys[funcName]
            try {
                this.DisableEntry(entry)
                this.activeHotkeys.Delete(funcName)
            } catch as err {
                ; Keep the registration tracked until the native provider proves it
                ; is disabled. Losing the registry entry here can leave a live clinical
                ; action enabled with no way for later profile operations to retire it.
                failures.Push(entry.hotkey ": " err.Message)
            }
        }

        for trackingKey, entry in this.additionalActiveHotkeys.Clone() {
            if !(entry.funcName == funcName)
                continue
            try {
                this.DisableEntry(entry)
                this.additionalActiveHotkeys.Delete(trackingKey)
            } catch as err {
                failures.Push(entry.hotkey ": " err.Message)
            }
        }

        if failures.Length {
            detail := ""
            for failure in failures
                detail .= (detail = "" ? "" : "; ") failure
            this.lastError := "the hotkey could not be disabled: " detail
            return false
        }
        return true
    }

    static DisableAllHotkeys() {
        ; Build one function-name set across both registries. Unregister mutates both
        ; maps but retains every entry whose native Off call could not be proven.
        functionNames := Map()
        for funcName, _ in this.activeHotkeys
            functionNames[funcName] := true
        for _, entry in this.additionalActiveHotkeys
            functionNames[entry.funcName] := true

        failed := []
        for funcName, _ in functionNames {
            if !this.Unregister(funcName)
                failed.Push(funcName)
        }
        if failed.Length {
            names := ""
            for funcName in failed
                names .= (names = "" ? "" : ", ") funcName
            throw Error("These hotkeys could not be disabled: " names)
        }
        return true
    }
}
