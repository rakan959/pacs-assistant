#Requires AutoHotkey v2.0
#Include ../HotkeyContract.ahk
#Include TestRunner.ahk

class HotkeyContractTest {
    static tests := [
        "TestScopeFlagsRoundTrip",
        "TestScopeFromFlagsMatrix",
        "TestNonCanonicalScopeCasingIsRejected",
        "TestBindingIdentityMatchesAutoHotkeySemantics",
        "TestBindingIdentityEdgeCases",
        "TestNumpadKeysAreNotTheirDedicatedTwins",
        "TestPrefixSymbolsMayFollowModifiers",
        "TestShiftTypedCharacterIsShiftPlusItsKey",
        "TestShiftTypedSymbolEndingAHotkeyIsShiftPlusItsKey",
        "TestOnlySpacedAmpersandJoinsACombination"
    ]

    TestScopeFlagsRoundTrip() {
        for scope in HotkeyContract.scopes {
            flags := HotkeyContract.FlagsFromScope(scope)
            Assert.Equal(scope, HotkeyContract.ScopeFromFlags(flags.requirePACS, flags.requirePowerScribe))
        }
    }

    TestScopeFromFlagsMatrix() {
        Assert.Equal("Any", HotkeyContract.ScopeFromFlags(false, false))
        Assert.Equal("PACS", HotkeyContract.ScopeFromFlags(true, false))
        Assert.Equal("PowerScribe", HotkeyContract.ScopeFromFlags(false, true))
        Assert.Equal("PACS or PowerScribe", HotkeyContract.ScopeFromFlags(true, true))

        Assert.Throws(() => HotkeyContract.RequireScope(""), "Unknown hotkey scope")
        Assert.Equal("PACS", HotkeyContract.RequireScope("PACS"))
    }

    TestNonCanonicalScopeCasingIsRejected() {
        Assert.False(HotkeyContract.IsValidScope("pacs"))
        Assert.False(HotkeyContract.IsValidScope("Powerscribe"))
        Assert.Throws(() => HotkeyContract.RequireScope("pacs"), "Unknown hotkey scope")
    }

    TestBindingIdentityMatchesAutoHotkeySemantics() {
        Assert.Equal("^!a", HotkeyContract.BindingIdentity("!^A"))
        Assert.Equal("^escape", HotkeyContract.BindingIdentity("^Esc"))
        Assert.Equal("^a", HotkeyContract.BindingIdentity("~$^A"))
        Assert.NotEqual(
            HotkeyContract.BindingIdentity("^a"),
            HotkeyContract.BindingIdentity("*^a")
        )
        Assert.NotEqual(
            HotkeyContract.BindingIdentity("^a"),
            HotkeyContract.BindingIdentity("^a Up")
        )
        Assert.Equal(
            HotkeyContract.BindingIdentity("a & b"),
            HotkeyContract.BindingIdentity("~a & b")
        )
        Assert.Equal(
            HotkeyContract.BindingIdentity("a & b"),
            HotkeyContract.BindingIdentity("$a & b")
        )
        Assert.Equal(
            HotkeyContract.BindingIdentity("Esc & F24"),
            HotkeyContract.BindingIdentity("Escape & f24")
        )
    }

    ; With NumLock off a numpad key reports a navigation name, but it has its own
    ; scan code and AutoHotkey registers it as a separate hotkey.
    TestNumpadKeysAreNotTheirDedicatedTwins() {
        for pair in [["NumpadEnd", "End"], ["NumpadHome", "Home"], ["NumpadDel", "Delete"], ["NumpadUp", "Up"]] {
            Assert.NotEqual(
                HotkeyContract.BindingIdentity("^" pair[2]),
                HotkeyContract.BindingIdentity("^" pair[1]),
                pair[1]
            )
            Assert.NotEqual(
                HotkeyContract.BindingIdentity(pair[2] " & F24"),
                HotkeyContract.BindingIdentity(pair[1] " & F24"),
                pair[1] " in a combination"
            )
        }
        ; Aliases of one key still match.
        Assert.Equal(HotkeyContract.BindingIdentity("NumpadEnd"), HotkeyContract.BindingIdentity("sc04F"))
        Assert.Equal(HotkeyContract.BindingIdentity("End"), HotkeyContract.BindingIdentity("sc14F"))
        Assert.Equal(HotkeyContract.BindingIdentity("a"), HotkeyContract.BindingIdentity("vk41"))
    }

    TestBindingIdentityEdgeCases() {
        ; Left/right modifiers are distinct hotkeys in AutoHotkey; the generic form
        ; is a third variant. Modifier order still does not matter.
        Assert.NotEqual(HotkeyContract.BindingIdentity("<^a"), HotkeyContract.BindingIdentity("^a"))
        Assert.NotEqual(HotkeyContract.BindingIdentity("<^a"), HotkeyContract.BindingIdentity(">^a"))
        Assert.Equal(HotkeyContract.BindingIdentity(">!<^x"), HotkeyContract.BindingIdentity("<^>!X"))
        Assert.Equal("", HotkeyContract.BindingIdentity("   "))
        ; Three-key combinations are not valid AutoHotkey syntax; they keep a
        ; normalized literal identity so two spellings still collide.
        Assert.Equal(HotkeyContract.BindingIdentity("a & b & c"), HotkeyContract.BindingIdentity("A  &  B  &  C"))
        Assert.Equal("*a & b", HotkeyContract.BindingIdentity("*a & b"))
        Assert.Throws(ObjBindMethod(HotkeyContract, "BindingIdentity", 42), "Hotkey must be a string")
    }

    ; AutoHotkey 2.0.26 registers ^? as ^+/ (registering one replaces the other)
    ; and keeps it apart from ^/. Letters are the exception: ^F is ^f.
    TestShiftTypedCharacterIsShiftPlusItsKey() {
        character := ShiftTypedCharacter(["?", "&", "%", ":", "_"], &baseKey)

        Assert.Equal(HotkeyContract.BindingIdentity("^+" baseKey), HotkeyContract.BindingIdentity("^" character))
        Assert.Equal(HotkeyContract.BindingIdentity("^+" baseKey), HotkeyContract.BindingIdentity("^+" character))
        Assert.Equal(HotkeyContract.BindingIdentity("^+" baseKey " up"), HotkeyContract.BindingIdentity("^" character " up"))
        Assert.NotEqual(HotkeyContract.BindingIdentity("^" baseKey), HotkeyContract.BindingIdentity("^" character))
        Assert.Equal(HotkeyContract.BindingIdentity("^f"), HotkeyContract.BindingIdentity("^F"))
    }

    ; ^+ is Ctrl and the + key, which on a US layout is the ^+= hotkey.
    TestShiftTypedSymbolEndingAHotkeyIsShiftPlusItsKey() {
        symbol := ShiftTypedCharacter(["+", "!", "#", "^"], &baseKey)

        Assert.Equal(HotkeyContract.BindingIdentity("^+" baseKey), HotkeyContract.BindingIdentity("^" symbol))
    }

    ; "a&b" is not a valid hotkey; ^& is Ctrl and the & key, so modifier order
    ; does not matter for it.
    TestOnlySpacedAmpersandJoinsACombination() {
        Assert.Equal(HotkeyContract.BindingIdentity("$^!&"), HotkeyContract.BindingIdentity("$!^&"))
        Assert.False(InStr(HotkeyContract.BindingIdentity("^&"), " & "))
        Assert.Equal("f13 & f14", HotkeyContract.BindingIdentity("F13 & F14"))
    }

    ; AutoHotkey accepts ~ $ * among the modifier symbols in any order.
    TestPrefixSymbolsMayFollowModifiers() {
        Assert.Equal(HotkeyContract.BindingIdentity("^a"), HotkeyContract.BindingIdentity("^~a"))
        Assert.Equal(HotkeyContract.BindingIdentity("^a"), HotkeyContract.BindingIdentity("^$a"))
        Assert.Equal(HotkeyContract.BindingIdentity("*^a"), HotkeyContract.BindingIdentity("^*a"))
        Assert.Equal("*<^>!x", HotkeyContract.BindingIdentity(">!~*<^X"))
    }
}

; The first of candidates that this keyboard layout types with Shift alone, read
; from Windows rather than from HotkeyContract.
ShiftTypedCharacter(candidates, &baseKey) {
    for candidate in candidates {
        scan := DllCall("VkKeyScan", "UShort", Ord(candidate), "Short")
        if (scan != -1 && (scan >> 8) = 1) {
            baseKey := GetKeyName(Format("vk{:02X}", scan & 0xFF))
            return candidate
        }
    }
    names := ""
    for candidate in candidates
        names .= " " candidate
    throw Error("This keyboard layout types none of these with Shift alone:" names)
}
