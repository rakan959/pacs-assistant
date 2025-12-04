#Requires AutoHotkey v2.0
#Include ../Settings.ahk
#Include TestRunner.ahk

class SettingsTest {
    static Tests := [
        "TestDefaultSettingsLoaded",
        "TestSetAndGetValues",
        "TestSystemSoundMappings",
        "TestFindSoundIndexFallback"
    ]

    Setup() {
        this.originalFile := Settings.settingsFile
        this.tempFile := A_Temp "\settings_test_" A_TickCount ".ini"
        Settings.settingsFile := this.tempFile
        Settings.SaveAllSettings()
    }
    
    TestDefaultSettingsLoaded() {
        Assert.True(Settings.Get("AutoUpdate"))
        Assert.True(Settings.Get("SkipBetaVersions"))
        Assert.False(Settings.Get("AutoRefreshPACS"))
        Assert.Equal(60, Settings.Get("RefreshInterval"))
        Assert.False(Settings.Get("AudioAlertNewCase"))
        Assert.False(Settings.Get("MessageBoxNewCase"))
        Assert.True(Settings.Get("AutoConvertWetReadLineEndings"))
        Assert.Equal("Default", Settings.Get("AlertSound"))
        Assert.Equal("", Settings.Get("CustomSoundFile"))
    }
    
    TestSetAndGetValues() {
        Settings.Set("RefreshInterval", 45)
        Assert.Equal(45, Settings.Get("RefreshInterval"))
        
        Settings.Set("AutoUpdate", false)
        Assert.False(Settings.Get("AutoUpdate"))

        Settings.Set("AutoConvertWetReadLineEndings", false)
        Assert.False(Settings.Get("AutoConvertWetReadLineEndings"))
        
        Settings.Set("AlertSound", "Asterisk")
        Assert.Equal("Asterisk", Settings.Get("AlertSound"))
    }
    
    TestSystemSoundMappings() {
        Assert.Equal("*-1", Settings.GetSystemSoundValue("Default"))
        Assert.Equal("*64", Settings.GetSystemSoundValue("Asterisk"))
        Assert.Equal("*48", Settings.GetSystemSoundValue("Exclamation"))
        Assert.Equal("*16", Settings.GetSystemSoundValue("Hand"))
        Assert.Equal("*32", Settings.GetSystemSoundValue("Question"))
    }
    
    TestFindSoundIndexFallback() {
        Assert.Equal(1, Settings.FindSoundIndex("Default"))
        Assert.Equal(2, Settings.FindSoundIndex("Asterisk"))
        Assert.Equal(1, Settings.FindSoundIndex("NotRealSound"))  ; should fall back to first entry
    }
    
    Teardown() {
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalFile
    }
}
