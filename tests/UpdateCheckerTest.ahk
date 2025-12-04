#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class UpdateCheckerTest {
    static Tests := [
        "TestVersionParsing",
        "TestVersionComparison",
        "TestAutoCheckTimerRespectsSettings",
        "TestSettingsChangeRestartsTimer"
    ]

    Setup() {
        this.originalSettingsFile := Settings.settingsFile
        this.tempSettings := A_Temp "\update_settings_" A_TickCount ".ini"
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()
    }
    
    TestVersionParsing() {
        v1 := UpdateChecker.ParseVersion("v1.9")
        Assert.Equal(1, v1.major)
        Assert.Equal(9, v1.minor)
        Assert.False(v1.isBeta)
        Assert.Equal(0, v1.betaVersion)
        
        v2 := UpdateChecker.ParseVersion("v2.0b4")
        Assert.Equal(2, v2.major)
        Assert.Equal(0, v2.minor)
        Assert.True(v2.isBeta)
        Assert.Equal(4, v2.betaVersion)
    }
    
    TestVersionComparison() {
        Assert.Equal(-1, UpdateChecker.CompareVersions("v1.9", "v2.0"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.1", "v2.0"))
        Assert.Equal(0, UpdateChecker.CompareVersions("v2.0", "v2.0"))
        
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b1", "v2.0b2"))
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b", "v2.0"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.0", "v2.0b"))
    }
    
    TestAutoCheckTimerRespectsSettings() {
        Settings.Set("AutoUpdate", true)
        UpdateChecker.StartAutoCheck()
        Assert.True(UpdateChecker.updateTimer != 0)
        
        Settings.Set("AutoUpdate", false)
        UpdateChecker.StartAutoCheck()
        Assert.Equal(0, UpdateChecker.updateTimer)
    }
    
    TestSettingsChangeRestartsTimer() {
        Settings.Set("AutoUpdate", true)
        UpdateChecker.StartAutoCheck()
        UpdateChecker.OnSettingsChanged()
        Assert.True(UpdateChecker.updateTimer != 0)
    }
    
    Teardown() {
        UpdateChecker.StopAutoCheck()
        UpdateChecker.skippedVersion := ""
        UpdateChecker.lastRemindTime := 0
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettingsFile
    }
}
