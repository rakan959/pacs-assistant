#Requires AutoHotkey v2.0
#Include ../CommandInfo.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class CommandInfoTest {
    static tests := [
        "TestEveryBuiltInCommandIsDescribed",
        "TestCustomAndUnknownFunctionsAreDescribed",
        "TestModifiedFunctionKeysRaiseNoWarning",
        "TestUnmodifiedTypingKeysWarnByScope",
        "TestPowerScribeKeysWarnOnlyWhereTheyApply",
        "TestSharedShortcutsWarn",
        "TestAModifierSymbolAsTheKeyIsReadAsTheKey"
    ]

    ; A new built-in command must be described on purpose, not fall through to the
    ; "no command with this name" text.
    TestEveryBuiltInCommandIsDescribed() {
        for name, _ in PACSCommands.commands
            Assert.True(CommandInfo.descriptions.Has(name), name)
        for name, _ in CommandInfo.descriptions
            Assert.True(PACSCommands.commands.Has(name), "described but not a command: " name)
    }

    TestCustomAndUnknownFunctionsAreDescribed() {
        Assert.Equal(
            "Sends {F9} to whichever window is active.",
            CommandInfo.Describe("Custom: Draft", {keys: "{F9}", window: ""})
        )
        Assert.Equal(
            "Sends ^c to 'ahk_exe notepad.exe'.",
            CommandInfo.Describe("Custom: Copy", {keys: "^c", window: "ahk_exe notepad.exe"})
        )
        Assert.True(InStr(CommandInfo.Describe("Retired Command"), "no command with this name") > 0)
    }

    TestModifiedFunctionKeysRaiseNoWarning() {
        for keyText in ["^F13", "^!F14", "+F15", "F16", "^+F13", "#F20", "NumpadAdd"]
            Assert.Equal(0, CommandInfo.KeyWarnings(keyText, "Any").Length, keyText)
    }

    TestUnmodifiedTypingKeysWarnByScope() {
        for keyText in ["a", "1", "Space", "Enter", "Backspace", "Left"] {
            warnings := CommandInfo.KeyWarnings(keyText, "Any")
            Assert.Equal(1, warnings.Length, keyText)
            Assert.True(InStr(warnings[1], "every window") > 0, keyText)
        }
        Assert.True(InStr(CommandInfo.KeyWarnings("a", "PACS")[1], "in PACS") > 0)
        ; With a modifier the key no longer types (Ctrl+Q is no common shortcut).
        Assert.Equal(0, CommandInfo.KeyWarnings("^q", "PACS").Length)
    }

    TestPowerScribeKeysWarnOnlyWhereTheyApply() {
        Assert.True(InStr(CommandInfo.KeyWarnings("F9", "Any")[1], "Draft") > 0)
        Assert.True(InStr(CommandInfo.KeyWarnings("F12", "PowerScribe")[1], "Sign") > 0)
        Assert.Equal(0, CommandInfo.KeyWarnings("F9", "PACS").Length)
        Assert.True(InStr(CommandInfo.KeyWarnings("^Backspace", "PACS or PowerScribe")[1], "delete previous word") > 0)
    }

    TestSharedShortcutsWarn() {
        warnings := CommandInfo.KeyWarnings("^c", "Any")
        Assert.Equal(1, warnings.Length)
        Assert.True(InStr(warnings[1], "Copy") > 0 && InStr(warnings[1], "every program") > 0)
        Assert.True(InStr(CommandInfo.KeyWarnings("!F4", "PACS")[1], "closing a window") > 0)
        ; Capture reports letters in either case; both are the same shortcut.
        Assert.Equal(1, CommandInfo.KeyWarnings("^V", "Any").Length)
    }

    TestAModifierSymbolAsTheKeyIsReadAsTheKey() {
        ; ^+ is Ctrl and the + key, not Ctrl+Shift with no key.
        Assert.Equal(0, CommandInfo.KeyWarnings("^+", "Any").Length)
        Assert.Equal(1, CommandInfo.KeyWarnings("+", "Any").Length)
    }
}
