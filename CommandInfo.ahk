; = CONTENTS
;   + Preamble
;   + CommandInfo class (what each command does, and warnings about a key before
;       it is bound)

#Requires AutoHotkey v2.0

#Include HotkeyContract.ahk

/**
 * Plain-language facts about commands and keys, for the windows to show. Nothing
 * here changes what a command does: the descriptions restate PACSCommands and
 * the README, and KeyWarnings only advises before a key is accepted.
 */
class CommandInfo {
    ; One line per built-in command, keyed by its persisted name.
    static descriptions := Map(
        "Toggle Dictation", "Presses F4 in PowerScribe to start or stop dictation.",
        "Select Next Field", "Presses Tab in PowerScribe to move to the next field.",
        "Select Previous Field", "Presses Shift+Tab in PowerScribe to move to the previous field.",
        "Delete Previous Word", "Presses Ctrl+Backspace in PowerScribe.",
        "Delete Next Word", "Presses Ctrl+Delete in PowerScribe.",
        "Draft Report", "Presses F9 in PowerScribe to save the report as a draft.",
        "Sign Report", "Presses F12 in PowerScribe to sign the report.",
        "Open/Force Restart PACS", "Closes Vue PACS (and PowerScribe, leaving any save prompt to you) and opens it again. It stops without closing anything it cannot verify.",
        "Paste Wet Read", "Types the clipboard into a new Sticky Note on the open study in Vue PACS, and saves it once the whole note is in.",
        "Paste Wet Read (Clipboard)", "Like Paste Wet Read, but enters the note with one Ctrl+V, which is faster for long notes.",
        "Toggle PowerScribe Window", "Brings PowerScribe forward when it is minimized, and minimizes it otherwise.",
        "Toggle EPIC Window", "Not available yet: does nothing until EPIC's window can be identified safely.",
        "Next Series", "Presses the Right arrow in the Vue PACS viewer.",
        "Previous Series", "Presses the Left arrow in the Vue PACS viewer.",
        "Set PowerScribe Microphone", "Selects the microphone named in Settings in PowerScribe now."
    )

    /**
     * What a function does. A custom function's description is built from its
     * configuration, given as {keys, window}; an unknown name says it is not part
     * of this version.
     */
    static Describe(funcName, customConfig := 0) {
        if this.descriptions.Has(funcName)
            return this.descriptions[funcName]
        if (InStr(funcName, "Custom: ") = 1) {
            if !IsObject(customConfig)
                return "A custom keybind."
            target := customConfig.window = "" ? "whichever window is active" : "'" customConfig.window "'"
            return "Sends " customConfig.keys " to " target "."
        }
        return "This version of PACS Assistant has no command with this name, so its keybind does nothing."
    }

    ; Keys PowerScribe acts on itself: the ones the built-in commands send it.
    static powerScribeKeys := Map(
        "F4", "dictation", "F9", "Draft", "F12", "Sign", "Tab", "next field",
        "+Tab", "previous field", "^Backspace", "delete previous word",
        "^Delete", "delete next word"
    )

    ; Shortcuts that Windows or almost every program uses for itself.
    static sharedShortcuts := Map(
        "^c", "Copy", "^v", "Paste", "^x", "Cut", "^z", "Undo", "^y", "Redo",
        "^a", "Select All", "^s", "Save", "^f", "Find", "^p", "Print",
        "!F4", "closing a window", "!Tab", "switching windows",
        "#d", "showing the desktop", "#e", "File Explorer", "#r", "Run",
        "#Tab", "Task View", "^Escape", "the Start menu"
    )

    ; Keys that type or edit text: bound without a modifier, they stop typing.
    static typingKeys := Map(
        "Space", 1, "Enter", 1, "Tab", 1, "Backspace", 1, "Delete", 1, "Insert", 1,
        "Home", 1, "End", 1, "PgUp", 1, "PgDn", 1, "Left", 1, "Right", 1, "Up", 1, "Down", 1
    )

    /**
     * Warnings about binding hotkey (AutoHotkey syntax, as key capture produces)
     * to a function with the given scope ("Any", "PACS", "PowerScribe" or
     * "PACS or PowerScribe").
     * @returns Array of sentences, empty when the key is unremarkable
     */
    static KeyWarnings(hotkey, scope) {
        warnings := []
        prefix := HotkeyContract.ParsePrefix(hotkey, true)
        key := prefix.rest
        ; A modifier symbol that ends the hotkey is its key: ^+ is Ctrl and the + key.
        if (key = "") {
            key := SubStr(hotkey, -1)
            if prefix.modifiers.Has(key)
                prefix.modifiers.Delete(key)
        }
        modifiers := ""
        for symbol in ["^", "!", "+", "#"] {
            for modifier, _ in prefix.modifiers {
                if InStr(modifier, symbol) {
                    modifiers .= symbol
                    break
                }
            }
        }
        canonical := modifiers (StrLen(key) = 1 ? StrLower(key) : key)
        inPowerScribe := scope == "Any" || InStr(scope, "PowerScribe")

        if (modifiers = "" && (StrLen(key) = 1 || this.typingKeys.Has(key))) {
            where := scope == "Any" ? "every window, including in reports"
                : scope == "PACS" ? "PACS"
                : scope == "PowerScribe" ? "PowerScribe, including in reports"
                : "PACS and PowerScribe, including in reports"
            warnings.Push("Without Ctrl, Alt, Shift or Win, this key would stop typing in " where ".")
        }
        if (inPowerScribe && this.powerScribeKeys.Has(canonical))
            warnings.Push("PowerScribe uses this key for " this.powerScribeKeys[canonical]
                . "; while this keybind is active, it replaces that there.")
        if this.sharedShortcuts.Has(canonical) {
            where := scope == "Any" ? "in every program" : "in " scope
            warnings.Push("This is the usual shortcut for " this.sharedShortcuts[canonical]
                . "; this keybind replaces it " where ".")
        }
        return warnings
    }
}
