#Requires AutoHotkey v2.0
#Include ../HotkeyManager.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class HotkeyManagerTest {
    static Tests := [
        "TestRegistersAndStoresHotkeys",
        "TestReassignUpdatesBinding",
        "TestUnassignClearsBinding",
        "TestRejectsMissingFunction",
        "TestDisableAllHotkeys",
        "TestRegistersWithScope",
        "TestUnknownScopeIsRejectedWithoutReplacingRegistration",
        "TestNonCanonicalScopeCasingIsRejected",
        "TestScopeFlagsRoundTrip",
        "TestScopeFromFlagsMatrix",
        "TestHotkeyIdentityMatchesAutoHotkeySemantics",
        "TestScopePredicatesAreStable",
        "TestPowerScribeScopeUsesExecutableSelector",
        "TestDuplicateHotkeyIsRejectedWithoutReplacingOwner",
        "TestEquivalentModifierOrderIsRejected",
        "TestMissingCallbackReassignmentPreservesExistingRegistration",
        "TestInvalidHotkeyReassignmentPreservesExistingRegistration"
    ]

    Setup() {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.activeHotkeys.Clear()

        this.func1Calls := 0
        this.func2Calls := 0
        this.func1 := (*) => (this.func1Calls++, 0)
        this.func2 := (*) => (this.func2Calls++, 0)

        HotkeyManager.hotkeyFunctions := Map(
            "ActionOne", this.func1,
            "ActionTwo", this.func2
        )

        ; Isolate settings
        this.originalSettings := Settings.settingsFile
        this.tempSettings := A_Temp "\hk_scope_test_" A_TickCount ".ini"
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()
    }

    TestRegistersAndStoresHotkeys() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal("Any", HotkeyManager.activeHotkeys["ActionOne"].scope)
    }

    TestReassignUpdatesBinding() {
        HotkeyManager.RegisterHotkey("ActionOne", "^a")
        HotkeyManager.RegisterHotkey("ActionOne", "^b")
        Assert.Equal("^b", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
    }

    TestUnassignClearsBinding() {
        HotkeyManager.RegisterHotkey("ActionTwo", "^c")
        HotkeyManager.RegisterHotkey("ActionTwo", "")
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
    }

    TestRejectsMissingFunction() {
        Assert.False(HotkeyManager.RegisterHotkey("MissingAction", "^d"))
        Assert.False(HotkeyManager.activeHotkeys.Has("MissingAction"))
        ; Failure is reported by return value plus lastError, not a dialog, so
        ; ApplyBinds can collect every failure into one message
        Assert.True(HotkeyManager.lastError != "")
    }

    TestDisableAllHotkeys() {
        HotkeyManager.RegisterHotkey("ActionOne", "^a")
        HotkeyManager.RegisterHotkey("ActionTwo", "^b")
        HotkeyManager.DisableAllHotkeys()
        Assert.Equal(0, HotkeyManager.activeHotkeys.Count)
    }

    TestRegistersWithScope() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "PowerScribe"))
        Assert.Equal("PowerScribe", HotkeyManager.activeHotkeys["ActionOne"].scope)

        ; Re-registering under a different scope must replace, not accumulate
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "PACS"))
        Assert.Equal("PACS", HotkeyManager.activeHotkeys["ActionOne"].scope)
        Assert.Equal(1, HotkeyManager.activeHotkeys.Count)
    }

    TestUnknownScopeIsRejectedWithoutReplacingRegistration() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "PACS"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "^b", "nonsense"))
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal("PACS", HotkeyManager.activeHotkeys["ActionOne"].scope)
    }

    TestScopeFlagsRoundTrip() {
        for scope in HotkeyManager.scopes {
            flags := HotkeyManager.FlagsFromScope(scope)
            Assert.Equal(scope, HotkeyManager.ScopeFromFlags(flags.requirePACS, flags.requirePowerScribe))
        }
    }

    TestScopeFromFlagsMatrix() {
        Assert.Equal("Any", HotkeyManager.ScopeFromFlags(false, false))
        Assert.Equal("PACS", HotkeyManager.ScopeFromFlags(true, false))
        Assert.Equal("PowerScribe", HotkeyManager.ScopeFromFlags(false, true))
        Assert.Equal("PACS or PowerScribe", HotkeyManager.ScopeFromFlags(true, true))

        Assert.Throws(() => HotkeyManager.NormalizeScope(""), "Unknown hotkey scope")
        Assert.Equal("PACS", HotkeyManager.NormalizeScope("PACS"))
    }

    TestNonCanonicalScopeCasingIsRejected() {
        Assert.False(HotkeyContract.IsValidScope("pacs"))
        Assert.False(HotkeyContract.IsValidScope("Powerscribe"))
        Assert.Throws(() => HotkeyManager.NormalizeScope("pacs"), "Unknown hotkey scope")
        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "^F22", "pacs"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionOne"))
    }

    TestHotkeyIdentityMatchesAutoHotkeySemantics() {
        Assert.Equal("^!a", HotkeyManager.HotkeyIdentity("!^A"))
        Assert.Equal("^escape", HotkeyManager.HotkeyIdentity("^Esc"))
        Assert.Equal("^a", HotkeyManager.HotkeyIdentity("~$^A"))
        Assert.NotEqual(
            HotkeyManager.HotkeyIdentity("^a"),
            HotkeyManager.HotkeyIdentity("*^a")
        )
        Assert.NotEqual(
            HotkeyManager.HotkeyIdentity("^a"),
            HotkeyManager.HotkeyIdentity("^a Up")
        )
    }

    ; AutoHotkey identifies a hotkey variant by the exact function object handed to
    ; HotIf, so a fresh closure per registration would leak an unreachable variant
    ; every time a bind is re-applied
    TestScopePredicatesAreStable() {
        for scope in HotkeyManager.scopes {
            if (scope == "Any") {
                Assert.False(HotkeyManager.scopePredicates.Has(scope), "'Any' must register globally, with no predicate")
                continue
            }
            Assert.True(HotkeyManager.scopePredicates.Has(scope), "No HotIf predicate for scope: " scope)
            Assert.True(HotkeyManager.scopePredicates[scope] == HotkeyManager.scopePredicates[scope],
                "Predicate for '" scope "' is not a stable object")
        }
    }

    TestPowerScribeScopeUsesExecutableSelector() {
        selectors := []

        active := HotkeyManager.PowerScribeIsActive(
            (selector) => (selectors.Push(selector), true)
        )

        Assert.True(active)
        Assert.Equal(1, selectors.Length)
        Assert.Equal("ahk_exe " AppControl.powerScribeExecutable, selectors[1])
    }

    TestDuplicateHotkeyIsRejectedWithoutReplacingOwner() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionTwo", "^A"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
        Assert.True(InStr(HotkeyManager.lastError, "ActionOne") > 0)
    }

    TestEquivalentModifierOrderIsRejected() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^!a"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionTwo", "!^A"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
    }

    TestMissingCallbackReassignmentPreservesExistingRegistration() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))

        Assert.False(HotkeyManager.Register("ActionOne", "^b", 0))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
    }

    TestInvalidHotkeyReassignmentPreservesExistingRegistration() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^F13"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "DefinitelyNotARealKeyName"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal("^F13", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal("Any", HotkeyManager.activeHotkeys["ActionOne"].scope)
        Assert.True(InStr(HotkeyManager.lastError, "Invalid key name") > 0)
    }

    Teardown() {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.activeHotkeys.Clear()
        HotkeyManager.hotkeyFunctions.Clear()
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}
