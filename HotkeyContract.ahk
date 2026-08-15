#Requires AutoHotkey v2.0

/**
 * Canonical contract shared by persisted profiles, the editor, and runtime hotkey
 * registration. Keeping scope validation and binding identity here prevents storage
 * and AutoHotkey from disagreeing about what one binding means.
 */
class HotkeyContract {
    static scopes := [
        "Any",
        "PACS",
        "PowerScribe",
        "PACS or PowerScribe"
    ]

    static IsValidScope(scope) {
        if (Type(scope) != "String")
            return false
        for name in this.scopes {
            if (name == scope)
                return true
        }
        return false
    }

    static RequireScope(scope) {
        if !this.IsValidScope(scope)
            throw ValueError("Unknown hotkey scope")
        return scope
    }

    static ScopeFromFlags(requirePACS, requirePowerScribe) {
        if (requirePACS && requirePowerScribe)
            return "PACS or PowerScribe"
        if requirePACS
            return "PACS"
        if requirePowerScribe
            return "PowerScribe"
        return "Any"
    }

    static FlagsFromScope(scope) {
        this.RequireScope(scope)
        return {
            requirePACS: (scope == "PACS" || scope == "PACS or PowerScribe"),
            requirePowerScribe: (scope == "PowerScribe" || scope == "PACS or PowerScribe")
        }
    }

    /**
     * Identity used to detect bindings which AutoHotkey treats as one hotkey.
     * Modifier order and key-name casing are insignificant. Tilde and dollar alter
     * the behavior of an existing hotkey rather than creating independent variants;
     * wildcard remains distinct. Custom combinations retain their written order.
     */
    static BindingIdentity(hotkeyStr) {
        if (Type(hotkeyStr) != "String")
            throw TypeError("Hotkey must be a string")

        hotkeyStr := Trim(hotkeyStr)
        if (hotkeyStr = "")
            return ""

        ; AutoHotkey applies ~ and $ to an existing variant's behavior. They do
        ; not create a separate custom-combination identity, and $ has no effect
        ; on a custom combination at all. Normalize those behavior prefixes before
        ; the early custom-combination return while preserving wildcard identity.
        wildcardPrefix := false
        prefixPosition := 1
        while (prefixPosition <= StrLen(hotkeyStr)) {
            prefixChar := SubStr(hotkeyStr, prefixPosition, 1)
            if (prefixChar = "~" || prefixChar = "$") {
                prefixPosition++
                continue
            }
            if (prefixChar = "*") {
                wildcardPrefix := true
                prefixPosition++
                continue
            }
            break
        }
        hotkeyBody := Trim(SubStr(hotkeyStr, prefixPosition))
        if InStr(hotkeyBody, "&") {
            parts := StrSplit(hotkeyBody, "&")
            if (parts.Length != 2)
                return (wildcardPrefix ? "*" : "")
                    . StrLower(RegExReplace(hotkeyBody, "\s+", " "))
            return (wildcardPrefix ? "*" : "")
                . this.NormalizeCombinationKey(parts[1])
                . " & "
                . this.NormalizeCombinationKey(parts[2])
        }
        hotkeyStr := (wildcardPrefix ? "*" : "") hotkeyBody

        modifiers := Map()
        wildcard := false
        position := 1
        while (position <= StrLen(hotkeyStr)) {
            char := SubStr(hotkeyStr, position, 1)
            if (char = "~" || char = "$") {
                position++
                continue
            }
            if (char = "*") {
                wildcard := true
                position++
                continue
            }
            if (char = "<" || char = ">") {
                next := SubStr(hotkeyStr, position + 1, 1)
                if (next != "" && InStr("^!+#", next)) {
                    modifiers[char next] := true
                    position += 2
                    continue
                }
            }
            if InStr("^!+#", char) {
                modifiers[char] := true
                position++
                continue
            }
            break
        }

        key := Trim(SubStr(hotkeyStr, position))
        if (key = "")
            return StrLower(hotkeyStr)

        keyUp := false
        if RegExMatch(key, "i)^(.+?)\s+up$", &upMatch) {
            key := upMatch[1]
            keyUp := true
        }

        try {
            normalizedKey := GetKeyName(key)
            if (normalizedKey != "")
                key := normalizedKey
        }

        identity := wildcard ? "*" : ""
        for token in ["<^", ">^", "^", "<!", ">!", "!", "<+", ">+", "+", "<#", ">#", "#"] {
            if modifiers.Has(token)
                identity .= token
        }
        identity .= StrLower(key)
        if keyUp
            identity .= " up"
        return identity
    }

    static NormalizeCombinationKey(key) {
        key := Trim(key)
        wildcard := false
        position := 1
        while (position <= StrLen(key)) {
            char := SubStr(key, position, 1)
            if (char = "~" || char = "$") {
                position++
                continue
            }
            if (char = "*") {
                wildcard := true
                position++
                continue
            }
            break
        }
        key := Trim(SubStr(key, position))
        try {
            normalizedKey := GetKeyName(key)
            if (normalizedKey != "")
                key := normalizedKey
        }
        return (wildcard ? "*" : "") StrLower(key)
    }
}
