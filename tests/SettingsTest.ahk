#Requires AutoHotkey v2.0
#Include ../Settings.ahk
#Include TestRunner.ahk

class SettingsTest {
    static Tests := [
        "TestDefaultSettingsLoaded",
        "TestSetAndGetValues",
        "TestAlertSoundsAreDistinct",
        "TestLegacySoundNamesMigrate",
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
        Assert.True(Settings.Get("RestrictHotkeysByActiveWindow"))
        Assert.Equal("Default Beep", Settings.Get("AlertSound"))
        Assert.Equal("", Settings.Get("CustomSoundFile"))
        Assert.False(Settings.Get("SwapMicrophoneOnLogin"))
        Assert.Equal("", Settings.Get("MicrophoneName"))
    }
    
    TestSetAndGetValues() {
        Settings.Set("RefreshInterval", 45)
        Assert.Equal(45, Settings.Get("RefreshInterval"))
        
        Settings.Set("AutoUpdate", false)
        Assert.False(Settings.Get("AutoUpdate"))

        Settings.Set("AutoConvertWetReadLineEndings", false)
        Assert.False(Settings.Get("AutoConvertWetReadLineEndings"))

        Settings.Set("RestrictHotkeysByActiveWindow", false)
        Assert.False(Settings.Get("RestrictHotkeysByActiveWindow"))
        
        Settings.Set("AlertSound", "Asterisk")
        Assert.Equal("Asterisk", Settings.Get("AlertSound"))
    }
    
    ; The alert sounds used to be MessageBeep aliases, which the stock Windows sound
    ; scheme collapses onto a couple of files, so every option sounded the same. Each
    ; one must now resolve to its own file.
    TestAlertSoundsAreDistinct() {
        seen := Map()
        for name, file in Settings.soundFiles {
            path := Settings.ResolveSoundFile(name)
            Assert.True(path != "", "No file for alert sound: " name " (" file ")")
            Assert.False(seen.Has(path), "Alert sound reuses another sound's file: " name)
            seen[path] := name
        }
        Assert.Equal(Settings.soundFiles.Count, seen.Count)

        ; These two are handled without a file
        Assert.Equal("", Settings.ResolveSoundFile("Default Beep"))
        Assert.Equal("", Settings.ResolveSoundFile("Custom File"))
    }

    TestLegacySoundNamesMigrate() {
        Assert.Equal("Default Beep", Settings.NormalizeSoundName("Default"))
        Assert.Equal("Notification", Settings.NormalizeSoundName("Asterisk"))
        Assert.Equal("Chime", Settings.NormalizeSoundName("Exclamation"))
        Assert.Equal("Chord", Settings.NormalizeSoundName("Hand"))
        Assert.Equal("Ding", Settings.NormalizeSoundName("Question"))
        Assert.Equal("Tada", Settings.NormalizeSoundName("Tada"))
        Assert.Equal("Default Beep", Settings.NormalizeSoundName("NotRealSound"))
    }

    TestFindSoundIndexFallback() {
        Assert.Equal("Default Beep", Settings.alertSounds[Settings.FindSoundIndex("Default")])
        Assert.Equal("Notification", Settings.alertSounds[Settings.FindSoundIndex("Asterisk")])
        Assert.Equal("Default Beep", Settings.alertSounds[Settings.FindSoundIndex("NotRealSound")])
    }
    
    Teardown() {
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalFile
    }
}
