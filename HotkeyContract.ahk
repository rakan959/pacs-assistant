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
     * Identity used to detect two bindings of the same key combination. Modifier
     * order, key-name casing and aliases of one key (Esc, Escape) are insignificant;
     * a numpad key is not its dedicated twin (NumpadEnd is not End). Tilde and
     * dollar alter the behavior of an existing hotkey rather than creating
     * independent variants; wildcard remains distinct. A character the keyboard
     * layout types with Shift is Shift plus its key (^? is ^+/). Custom
     * combinations, two keys joined by " & ", retain their written order.
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
        behavior := this.ParsePrefix(hotkeyStr, false)
        hotkeyBody := Trim(behavior.rest)
        ; Only " & " joins a combination; ^& is Ctrl and the & key.
        if InStr(hotkeyBody, " & ") {
            parts := StrSplit(hotkeyBody, " & ")
            if (parts.Length != 2)
                return (behavior.wildcard ? "*" : "")
                    . StrLower(RegExReplace(hotkeyBody, "\s+", " "))
            return (behavior.wildcard ? "*" : "")
                . this.NormalizeCombinationKey(parts[1])
                . " & "
                . this.NormalizeCombinationKey(parts[2])
        }

        prefix := this.ParsePrefix(hotkeyBody, true)
        key := Trim(prefix.rest)
        if (key = "") {
            ; A symbol that ends the hotkey is its key: ^+ is Ctrl and the + key.
            key := SubStr(hotkeyBody, -1)
            prefix := this.ParsePrefix(SubStr(hotkeyBody, 1, -1), true)
            if (prefix.rest != "")
                return StrLower((behavior.wildcard ? "*" : "") hotkeyBody)
        }
        wildcard := behavior.wildcard || prefix.wildcard

        keyUp := false
        if RegExMatch(key, "i)^(.+?)\s+up$", &upMatch) {
            key := upMatch[1]
            keyUp := true
        }

        ; With a left or right Shift, AutoHotkey keeps the character's hotkey apart
        ; from the base key's; treating them as one refuses a bind rather than
        ; letting one replace the other.
        if (this.IsShiftedCharacter(key, &baseKey)
            && !prefix.modifiers.Has("<+")
            && !prefix.modifiers.Has(">+")) {
            key := baseKey
            prefix.modifiers["+"] := true
        }
        key := this.CanonicalKeyName(key)

        identity := wildcard ? "*" : ""
        for token in ["<^", ">^", "^", "<!", ">!", "!", "<+", ">+", "+", "<#", ">#", "#"] {
            if prefix.modifiers.Has(token)
                identity .= token
        }
        identity .= StrLower(key)
        if keyUp
            identity .= " up"
        return identity
    }

    static NormalizeCombinationKey(key) {
        prefix := this.ParsePrefix(Trim(key), false)
        key := this.CanonicalKeyName(Trim(prefix.rest))
        return (prefix.wildcard ? "*" : "") StrLower(key)
    }

    /**
     * Whether key is a character that the keyboard layout types with Shift alone,
     * such as ? or & on a US layout. AutoHotkey registers such a key as Shift plus
     * the key that types it. Letters are the exception: ^F is the ^f hotkey.
     * @param baseKey receives the name of the key that types the character
     */
    static IsShiftedCharacter(key, &baseKey) {
        baseKey := ""
        if (StrLen(key) != 1 || IsAlpha(key))
            return false
        ; The low byte is the virtual key; the high byte the shift state, 1 = Shift.
        scan := DllCall("VkKeyScan", "UShort", Ord(key), "Short")
        if (scan = -1 || (scan >> 8) != 1)
            return false
        baseKey := GetKeyName(Format("vk{:02X}", scan & 0xFF))
        return baseKey != ""
    }

    /**
     * The canonical spelling of a key name, so that aliases of one key (Esc,
     * Escape, vk1B) compare equal. GetKeyName names a numpad navigation key after
     * its dedicated twin (NumpadEnd -> End), a different key with a different scan
     * code, so a name whose scan code differs from the key's is not used.
     * @returns the canonical name, or key unchanged when it has none
     */
    static CanonicalKeyName(key) {
        name := ""
        try name := GetKeyName(key)
        if (name = "" || GetKeySC(name) != GetKeySC(key))
            return key
        return name
    }

    /**
     * Consumes the prefix symbols at the start of a hotkey: ~ and $ (behavior only),
     * * (wildcard) and, when modifiers are allowed, ^ ! + # with an optional < or >
     * side. AutoHotkey accepts these in any order.
     * @returns {wildcard: true if * appeared, modifiers: Map of modifier tokens,
     *   rest: the text after the last prefix symbol}
     */
    static ParsePrefix(text, allowModifiers) {
        pattern := allowModifiers ? "^(?:[~$*]|[<>]?[\^!+#])" : "^[~$*]"
        wildcard := false
        modifiers := Map()
        while RegExMatch(text, pattern, &token) {
            if (token[0] = "*")
                wildcard := true
            else if (token[0] != "~" && token[0] != "$")
                modifiers[token[0]] := true
            text := SubStr(text, token.Len + 1)
        }
        return {wildcard: wildcard, modifiers: modifiers, rest: text}
    }
}
