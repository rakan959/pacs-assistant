#Requires AutoHotkey v2.0
#Include HotkeyContract.ahk
#Include PACSCommands.ahk

class HotkeyManager {
    static activeHotkeys := Map()  ; funcName -> {hotkey: "^j", scope: "PACS"}
    static hotkeyFunctions := Map()

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
            this.Unregister(funcName)
            return true
        }

        if !HotkeyContract.IsValidScope(scope) {
            this.lastError := "the hotkey scope is unknown"
            return false
        }

        if !callback {
            this.lastError := "no command is defined for it"
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
            Hotkey(hotkeyStr, callback, "On")
        } catch as err {
            this.lastError := err.Message
            return false
        } finally {
            this.ExitScope()
        }

        if previous && !sameVariant {
            try {
                this.EnterScope(previous.scope)
                Hotkey(previous.hotkey, "Off")
            } catch as err {
                ; The replacement is live but the old variant could not be retired.
                ; Roll it back and keep the prior map entry rather than claiming an
                ; ambiguous two-registration state succeeded.
                try {
                    this.ExitScope()
                    this.EnterScope(scope)
                    Hotkey(hotkeyStr, "Off")
                } catch {
                    ; Preserve the original retirement error as the actionable cause.
                }
                this.lastError := "the previous hotkey could not be disabled: " err.Message
                return false
            } finally {
                this.ExitScope()
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
        return ""
    }

    ; Turn off a single registration, re-entering the context it was created in.
    ; Hotkey(name, "Off") only affects the variant of the *current* HotIf context, so
    ; the scope has to be restored before the hotkey can be turned off.
    static Unregister(funcName) {
        if !this.activeHotkeys.Has(funcName)
            return

        entry := this.activeHotkeys[funcName]
        this.activeHotkeys.Delete(funcName)

        try {
            this.EnterScope(entry.scope)
            Hotkey(entry.hotkey, "Off")
        } catch {
            ; The variant may no longer exist (e.g. it was never successfully created).
            ; There is nothing to turn off in that case.
        } finally {
            this.ExitScope()
        }
    }

    static DisableAllHotkeys() {
        ; Iterate a snapshot: Unregister mutates activeHotkeys
        for funcName, _ in this.activeHotkeys.Clone() {
            this.Unregister(funcName)
        }
        this.activeHotkeys.Clear()
    }
}
