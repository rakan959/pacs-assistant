#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class UpdateCheckerTest {
    static Tests := [
        "TestVersionParsing",
        "TestVersionComparison",
        "TestAutoCheckTimerRespectsSettings",
        "TestSettingsChangeRestartsTimer",
        "TestVersionComesFromAppVersion"
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
        Assert.Equal(0, v1.patch)
        Assert.False(v1.isPrerelease)

        v2 := UpdateChecker.ParseVersion("v2.0b4")
        Assert.Equal(2, v2.major)
        Assert.Equal(0, v2.minor)
        Assert.Equal(0, v2.patch)
        Assert.True(v2.isPrerelease)

        v3 := UpdateChecker.ParseVersion("v2.1.3-beta.4")
        Assert.Equal(2, v3.major)
        Assert.Equal(1, v3.minor)
        Assert.Equal(3, v3.patch)
        Assert.Equal("beta.4", v3.prerelease)
    }

    TestVersionComparison() {
        Assert.Equal(-1, UpdateChecker.CompareVersions("v1.9", "v2.0"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.1", "v2.0"))
        Assert.Equal(0, UpdateChecker.CompareVersions("v2.0", "v2.0"))

        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b1", "v2.0b2"))
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b", "v2.0"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.0", "v2.0b"))

        ; Patch releases used to compare equal, so nobody was ever offered one
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0.1", "v2.0.2"))
        Assert.Equal(1, UpdateChecker.CompareVersions("v2.0.9", "v2.0.1"))

        ; SemVer prereleases
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.1.0-beta.1", "v2.1.0"))
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.1.0-beta.2", "v2.1.0-beta.10"))

        ; An install on the old scheme must see the first SemVer release as an update
        Assert.Equal(-1, UpdateChecker.CompareVersions("v2.0b7", "v2.1.0"))
    }

    ; The version is read from the CI-generated file, so it is stated in exactly one
    ; place and cannot drift from the tag it was built from
    TestVersionComesFromAppVersion() {
        Assert.Equal(AppVersion.current, UpdateChecker.currentVersion)
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
