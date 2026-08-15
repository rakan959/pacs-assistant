#Requires AutoHotkey v2.0
#Include ../Settings.ahk
#Include TestRunner.ahk

class SettingsTest {
    static Tests := [
        "TestDefaultSettingsLoaded",
        "TestSetAndGetValues",
        "TestMalformedPersistedSettingsUseDefaults",
        "TestAlertSoundsAreDistinct",
        "TestLegacyAliasesAreSelectable",
        "TestLegacySoundNamesMigrate",
        "TestFindSoundIndexFallback",
        "TestSavingSettingsNotifiesListeners",
        "TestChangeListenersAllRun",
        "TestChangeListenerFailureDoesNotBlockLaterListeners"
    ]

    Setup() {
        this.originalFile := Settings.settingsFile
        this.originalListeners := Settings.changeListeners
        this.tempFile := A_Temp "\settings_test_" A_TickCount ".ini"
        Settings.settingsFile := this.tempFile
        Settings.changeListeners := []
        Settings.SaveAllSettings()
    }
    
    TestDefaultSettingsLoaded() {
        Assert.True(Settings.Get("AutoUpdate"))
        Assert.True(Settings.Get("SkipBetaVersions"))
        Assert.Equal("", Settings.Get("SkippedUpdateVersion"))
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

    TestMalformedPersistedSettingsUseDefaults() {
        IniWrite("-1", Settings.settingsFile, "Settings", "RefreshInterval")
        IniWrite("not-a-boolean", Settings.settingsFile, "Settings", "AutoUpdate")

        Assert.Equal(Settings.defaultSettings["RefreshInterval"], Settings.Get("RefreshInterval"))
        Assert.Equal(Settings.defaultSettings["AutoUpdate"], Settings.Get("AutoUpdate"))
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

    ; Every legacy name must land on a sound that is actually selectable, or an old
    ; settings.ini would resolve to an option no longer in the list
    TestLegacyAliasesAreSelectable() {
        for legacy, current in Settings.legacySoundAliases {
            found := false
            for name in Settings.alertSounds {
                if (name == current)
                    found := true
            }
            Assert.True(found, "Legacy sound '" legacy "' maps to '" current "', which is not selectable")
        }
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

    TestSavingSettingsNotifiesListeners() {
        calls := []
        Settings.AddChangeListener((*) => calls.Push("changed"))
        controls := {
            checkboxes: Map(
                "AutoUpdate", {Value: false},
                "SwapMicrophoneOnLogin", {Value: false}
            ),
            refreshInterval: {Value: 45},
            micName: {Value: ""},
            soundDropDown: {Text: "Ding"},
            customSound: {Text: ""}
        }
        dialog := FakeSettingsDialog()

        Settings.SaveSettings(controls, dialog)

        Assert.True(dialog.destroyed)
        Assert.Equal(1, calls.Length)
        Assert.False(Settings.Get("AutoUpdate"))
        Assert.Equal(45, Settings.Get("RefreshInterval"))
    }

    TestChangeListenersAllRun() {
        calls := []
        Settings.AddChangeListener((*) => calls.Push("updater"))
        Settings.AddChangeListener((*) => calls.Push("monitor"))

        errors := Settings.NotifyChanged()

        Assert.Equal(2, calls.Length)
        Assert.Equal("updater", calls[1])
        Assert.Equal("monitor", calls[2])
        Assert.Equal(0, errors.Length)
    }

    TestChangeListenerFailureDoesNotBlockLaterListeners() {
        calls := []
        Settings.AddChangeListener(ThrowSettingsListener)
        Settings.AddChangeListener((*) => calls.Push("after failure"))

        errors := Settings.NotifyChanged()

        Assert.Equal(1, calls.Length)
        Assert.Equal("after failure", calls[1])
        Assert.Equal(1, errors.Length)
        Assert.True(InStr(errors[1], "listener failed") > 0)
    }
    
    Teardown() {
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalFile
        Settings.changeListeners := this.originalListeners
    }
}

ThrowSettingsListener(*) {
    throw Error("listener failed")
}

class FakeSettingsDialog {
    __New() {
        this.destroyed := false
    }

    Destroy() {
        this.destroyed := true
    }
}
