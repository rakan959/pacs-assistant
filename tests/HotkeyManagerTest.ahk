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
        "TestScopeRespectsSettings",
        "TestScopeOverrideGlobal"
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
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"])
    }
    
    TestReassignUpdatesBinding() {
        HotkeyManager.RegisterHotkey("ActionOne", "^a")
        HotkeyManager.RegisterHotkey("ActionOne", "^b")
        Assert.Equal("^b", HotkeyManager.activeHotkeys["ActionOne"])
    }
    
    TestUnassignClearsBinding() {
        HotkeyManager.RegisterHotkey("ActionTwo", "^c")
        HotkeyManager.RegisterHotkey("ActionTwo", "")
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
    }
    
    TestRejectsMissingFunction() {
        Assert.False(HotkeyManager.RegisterHotkey("MissingAction", "^d"))
        Assert.False(HotkeyManager.activeHotkeys.Has("MissingAction"))
    }
    
    TestDisableAllHotkeys() {
        HotkeyManager.RegisterHotkey("ActionOne", "^a")
        HotkeyManager.RegisterHotkey("ActionTwo", "^b")
        HotkeyManager.DisableAllHotkeys()
        Assert.Equal(0, HotkeyManager.activeHotkeys.Count)
    }

    TestScopeRespectsSettings() {
        Settings.Set("RestrictHotkeysByActiveWindow", true)
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
    }

    TestScopeOverrideGlobal() {
        Settings.Set("RestrictHotkeysByActiveWindow", true)
        Assert.True(HotkeyManager.RegisterHotkey("ActionTwo", "^b", "global"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionTwo"))
    }
    
    Teardown() {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.activeHotkeys.Clear()
        HotkeyManager.hotkeyFunctions.Clear()
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}
