#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class UpdateCheckerTest {
    static Tests := [
        "TestVersionParsing",
        "TestVersionComparison",
        "TestVersionPrecedenceTable",
        "TestVersionEquivalence",
        "TestAutoCheckTimerRespectsSettings",
        "TestSettingsChangeRestartsTimer",
        "TestVersionComesFromAppVersion",
        "TestJsonParserHandlesEscapesAndUnicode",
        "TestJsonParserRejectsUppercaseTokensAndEscapes",
        "TestReleaseParserKeepsAssetMetadataTogether",
        "TestReleaseParserAcceptsArrayResponse",
        "TestDownloadUrlMustBelongToThisRepository",
        "TestSha256KnownVector",
        "TestArtifactValidationRejectsNonExecutable",
        "TestUpdaterScriptRequiresHealthyRelaunch",
        "TestUpdaterScriptRecoversAfterPreSwapFailure",
        "TestUpdaterUsesPrivateTemporaryScript",
        "TestCleanupDoesNotOwnGenericScript",
        "TestSkippedVersionPersistsAcrossReload"
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

    ; Each pair is {older, newer} and is asserted in both directions
    TestVersionPrecedenceTable() {
        ordered := [
            ["v1.9.0", "v2.0.0"],
            ["v2.0.0", "v2.1.0"],
            ; Patch releases. The previous parser read only major and minor, so these
            ; compared equal and a patch update was never offered to anyone.
            ["v2.0.1", "v2.0.2"],
            ["v2.0.1", "v2.0.9"],
            ["v2.0.9", "v2.0.10"],
            ; A prerelease ranks below its release
            ["v2.1.0-beta.1", "v2.1.0"],
            ["v2.1.0-beta.1", "v2.1.0-beta.2"],
            ["v2.1.0-beta.2", "v2.1.0-beta.10"],
            ["v2.1.0-alpha.1", "v2.1.0-beta.1"],
            ["v2.1.0-beta", "v2.1.0-beta.1"],
            ; Numeric identifiers rank below alphanumeric ones
            ["v2.1.0-1", "v2.1.0-alpha"],
            ; Legacy tags order among themselves
            ["v2.0b4", "v2.0b7"],
            ["v2.0b9", "v2.0b10"],
            ["v2.0b", "v2.0b1"],
            ["v2.0b7", "v2.0"],
            ["v1.0", "v2.0b1"],
            ; ... and against the SemVer tags replacing them, so an install on the old
            ; scheme still sees the first SemVer release as an update
            ["v2.0b7", "v2.1.0"],
            ["v2.0b7", "v2.1.0-beta.1"],
            ["v2.0b4", "v2.0.1"]
        ]

        for pair in ordered {
            Assert.Equal(-1, UpdateChecker.CompareVersions(pair[1], pair[2]),
                "Expected '" pair[1] "' < '" pair[2] "'")
            Assert.Equal(1, UpdateChecker.CompareVersions(pair[2], pair[1]),
                "Expected '" pair[2] "' > '" pair[1] "'")
        }
    }

    TestVersionEquivalence() {
        equal := [
            ["v2.0.0", "v2.0.0"],
            ["v2.0.0", "2.0.0"],
            ["v2.1.0-beta.1", "v2.1.0-beta.1"],
            ; Build metadata takes no part in precedence
            ["v2.1.0+abc123", "v2.1.0"],
            ; The short forms mean the same thing
            ["v2.0", "v2.0.0"]
        ]

        for pair in equal {
            Assert.Equal(0, UpdateChecker.CompareVersions(pair[1], pair[2]),
                "Expected '" pair[1] "' == '" pair[2] "'")
        }
    }

    ; The version is read from the CI-generated file, so it is stated in exactly one
    ; place and cannot drift from the tag it was built from
    TestVersionComesFromAppVersion() {
        Assert.Equal(AppVersion.current, UpdateChecker.currentVersion)
    }

    TestJsonParserHandlesEscapesAndUnicode() {
        parsed := JsonParser.Parse('{"text":"line 1\nquote: \"ok\"; slash: \\n; smile: \u263A; emoji: \uD83D\uDE00"}')
        Assert.Equal("line 1`nquote: `"ok`"; slash: \n; smile: " Chr(0x263A) "; emoji: " Chr(0x1F600), parsed["text"])
    }

    TestJsonParserRejectsUppercaseTokensAndEscapes() {
        for invalid in ["TRUE", "False", "NULL", '"\N"', '"\U263A"']
            Assert.Throws(() => JsonParser.Parse(invalid), "", "Invalid JSON was accepted: " invalid)
    }

    TestReleaseParserKeepsAssetMetadataTogether() {
        json := '{"tag_name":"v2.2.0","body":"Line 1\nLine 2","assets":['
            . '{"name":"notes.txt","size":12,"digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/notes.txt"},'
            . '{"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":1550000,"name":"pacs-assistant.exe"}'
            . ']}'

        release := UpdateChecker.ParseReleaseResponse(json)

        Assert.Equal("v2.2.0", release.version)
        Assert.Equal("Line 1`nLine 2", release.notes)
        Assert.Equal(1550000, release.assetSize)
        Assert.Equal("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", release.assetSha256)
        Assert.True(InStr(release.downloadUrl, "/pacs-assistant.exe") > 0)
    }

    TestReleaseParserAcceptsArrayResponse() {
        json := '[{"tag_name":"v2.2.0-beta.1","body":"Beta","assets":['
            . '{"name":"pacs-assistant.exe","size":42,"digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0-beta.1/pacs-assistant.exe"}'
            . ']}]'

        release := UpdateChecker.ParseReleaseResponse(json)
        Assert.Equal("v2.2.0-beta.1", release.version)
        Assert.Equal(42, release.assetSize)
    }

    TestDownloadUrlMustBelongToThisRepository() {
        Assert.True(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "http://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/attacker/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/other.exe"
        ))
    }

    TestSha256KnownVector() {
        path := A_Temp "\pacs_sha256_" A_TickCount ".txt"
        FileAppend("abc", path, "UTF-8-RAW")
        try {
            Assert.Equal(
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                UpdateChecker.HashFileSha256(path)
            )
        } finally {
            try FileDelete(path)
        }
    }

    TestArtifactValidationRejectsNonExecutable() {
        path := A_Temp "\pacs_bad_update_" A_TickCount ".exe"
        FileAppend("not an executable", path, "UTF-8-RAW")
        try {
            digest := UpdateChecker.HashFileSha256(path)
            Assert.False(UpdateChecker.ValidateDownloadedArtifact(path, FileGetSize(path), digest, "v2.2.0"))
        } finally {
            try FileDelete(path)
        }
    }

    TestUpdaterScriptRequiresHealthyRelaunch() {
        script := UpdateChecker.BuildUpdaterScript()
        Assert.True(InStr(script, "Start-Process -FilePath $CurrentExe -PassThru") > 0)
        Assert.True(InStr(script, "Start-Sleep -Seconds 5") > 0)
        Assert.True(InStr(script, "$newProcess.HasExited") > 0)
    }

    TestUpdaterScriptRecoversAfterPreSwapFailure() {
        script := UpdateChecker.BuildUpdaterScript()

        Assert.True(InStr(script, "$ParentExited = $false") > 0)
        Assert.True(InStr(script, "$RecoveryLaunched = $false") > 0)
        Assert.True(InStr(script, "$RecoveryReady = $false") > 0)
        Assert.True(InStr(script, "if ($ParentExited -and -not $RecoveryLaunched)") > 0)
        Assert.True(InStr(script, "Start-Process -FilePath $CurrentExe") > 0)
    }

    TestUpdaterUsesPrivateTemporaryScript() {
        path := UpdateChecker.CreateUpdaterPath()

        Assert.True(InStr(path, A_Temp "\pacs-assistant-updater-") = 1)
        Assert.False(path = A_ScriptDir "\update.ps1")
    }

    TestCleanupDoesNotOwnGenericScript() {
        names := UpdateChecker.OwnedUpdateArtifactNames()

        for name in names
            Assert.False(name = "update.ps1")
        Assert.Equal(2, names.Length)
    }

    TestSkippedVersionPersistsAcrossReload() {
        UpdateChecker.SkipVersion("v2.2.0")
        UpdateChecker.skippedVersion := ""

        UpdateChecker.LoadSkippedVersion()

        Assert.Equal("v2.2.0", UpdateChecker.skippedVersion)
        Assert.Equal("v2.2.0", Settings.Get("SkippedUpdateVersion"))
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
