#Requires AutoHotkey v2.0
#Include PACSCommands.ahk

class HotkeyManager {
    static activeHotkeys := Map()  ; funcName -> {hotkey: "^j", scope: "PACS"}
    static hotkeyFunctions := Map()

    ; Scope names in the order they are presented, and the only values persisted to a
    ; profile. "Any" means the bind fires regardless of which window has focus.
    static scopes := [
        "Any",
        "PACS",
        "PowerScribe",
        "PACS or PowerScribe"
    ]

    ; One persistent predicate per scope. AutoHotkey identifies a hotkey *variant* by
    ; the exact function object handed to HotIf, so these are created once and reused:
    ; building a fresh closure per registration would create a new variant every time
    ; and leave the previous one registered and unreachable.
    static scopePredicates := Map(
        "PACS", (*) => WinActive("ahk_exe mp.exe"),
        "PowerScribe", (*) => WinActive("PowerScribe"),
        "PACS or PowerScribe", (*) => WinActive("ahk_exe mp.exe") || WinActive("PowerScribe")
    )

    static __New() {
        ; Initialize hotkey functions from PACSCommands
        this.hotkeyFunctions := PACSCommands.commands
    }

    ; Coerce a stored/unknown scope onto a supported one
    static NormalizeScope(scope) {
        for name in this.scopes {
            if (name = scope)
                return name
        }
        return "Any"
    }

    ; Build a scope name from the two "only when ... is active" checkboxes
    static ScopeFromFlags(requirePACS, requirePowerScribe) {
        if (requirePACS && requirePowerScribe)
            return "PACS or PowerScribe"
        if (requirePACS)
            return "PACS"
        if (requirePowerScribe)
            return "PowerScribe"
        return "Any"
    }

    ; Inverse of ScopeFromFlags
    static FlagsFromScope(scope) {
        scope := this.NormalizeScope(scope)
        return {
            requirePACS: (scope = "PACS" || scope = "PACS or PowerScribe"),
            requirePowerScribe: (scope = "PowerScribe" || scope = "PACS or PowerScribe")
        }
    }

    ; Enter the HotIf context a scope registers under. Always paired with ExitScope().
    static EnterScope(scope) {
        scope := this.NormalizeScope(scope)
        if this.scopePredicates.Has(scope)
            HotIf(this.scopePredicates[scope])
        else
            HotIf()  ; Global context
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
        ; Drop any previous registration first, in the context it was made under
        this.Unregister(funcName)

        ; Skip registration if the hotkey is unassigned
        if (hotkeyStr = "")
            return true

        if !callback {
            MsgBox("No action is defined for '" funcName "'. The keybind was not applied.", "Keybind Error", "Icon!")
            return false
        }

        scope := this.NormalizeScope(scope)
        try {
            this.EnterScope(scope)
            ; "On" is load-bearing. Hotkey() updates an existing variant's action but
            ; leaves its enabled state alone, so a bind that DisableAllHotkeys turned
            ; off stayed dead after being re-registered - which is how binds silently
            ; stopped working after editing a keybind or switching profiles.
            Hotkey(hotkeyStr, callback, "On")
            this.activeHotkeys[funcName] := {hotkey: hotkeyStr, scope: scope}
            return true
        } catch as err {
            MsgBox("Error setting hotkey: " hotkeyStr " for " funcName "`nError: " err.Message)
            return false
        } finally {
            this.ExitScope()
        }
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
