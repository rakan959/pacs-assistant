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
        "TestUnknownScopeFallsBackToAny",
        "TestScopeFlagsRoundTrip"
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

    TestUnknownScopeFallsBackToAny() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "nonsense"))
        Assert.Equal("Any", HotkeyManager.activeHotkeys["ActionOne"].scope)
    }

    TestScopeFlagsRoundTrip() {
        for scope in HotkeyManager.scopes {
            flags := HotkeyManager.FlagsFromScope(scope)
            Assert.Equal(scope, HotkeyManager.ScopeFromFlags(flags.requirePACS, flags.requirePowerScribe))
        }
    }

    Teardown() {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.activeHotkeys.Clear()
        HotkeyManager.hotkeyFunctions.Clear()
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}
