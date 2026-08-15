#Requires AutoHotkey v2.0

/**
 * Canonical persisted hotkey-scope contract shared by profile storage and runtime
 * registration. Unknown stored values are rejected by ProfileManager; Normalize is
 * retained for defensive runtime callers that do not come from a profile.
 */
class HotkeyScope {
    static names := [
        "Any",
        "PACS",
        "PowerScribe",
        "PACS or PowerScribe"
    ]

    static IsValid(scope) {
        if (Type(scope) != "String")
            return false
        for name in this.names {
            if (name = scope)
                return true
        }
        return false
    }

    static Normalize(scope) {
        return this.IsValid(scope) ? scope : "Any"
    }

    static FromFlags(requirePACS, requirePowerScribe) {
        if (requirePACS && requirePowerScribe)
            return "PACS or PowerScribe"
        if requirePACS
            return "PACS"
        if requirePowerScribe
            return "PowerScribe"
        return "Any"
    }

    static Flags(scope) {
        scope := this.Normalize(scope)
        return {
            requirePACS: (scope = "PACS" || scope = "PACS or PowerScribe"),
            requirePowerScribe: (scope = "PowerScribe" || scope = "PACS or PowerScribe")
        }
    }
}
