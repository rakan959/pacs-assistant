#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include TestRunner.ahk

class ProfileManagerTest {
    static Tests := [
        "TestProfileSaveAndLoad",
        "TestProfileNameContainingIniRoundTrips",
        "TestDefaultProfileTracking",
        "TestProfileRename",
        "TestProfileCaseOnlyRename",
        "TestProfileDeletionRules",
        "TestFailedDefaultDeletionPreservesProfile",
        "TestCustomFunctionPersistence",
        "TestUnboundCustomFunctionPersistence",
        "TestScopePersistence",
        "TestScopeDefaultsToAnyWhenAbsent",
        "TestLegacyScopeMigration",
        "TestMalformedLegacyScopeIsRejected",
        "TestLegacyProfileWithoutScopesSection",
        "TestModalityAttendingPersistence",
        "TestDefaultPathsAreAnchored",
        "TestProfileNameValidation",
        "TestCreateProfileRejectsUnsafeAndDuplicateNames",
        "TestSaveRejectsUnsafeIniKeys",
        "TestSaveRejectsMalformedCustomCommand",
        "TestFailedRenamePreservesOriginalProfile",
        "TestMalformedProfileDoesNotBlockValidProfiles",
        "TestDefaultProfileMustExist",
        "TestDuplicateBindingsAreRejected",
        "TestEquivalentModifierBindingsAreRejected",
        "TestUnknownScopeIsRejected"
    ]

    Setup() {
        this.tempRoot := A_Temp "\pacs_profile_tests_" A_TickCount
        this.profilesDir := this.tempRoot "\profiles"
        DirCreate(this.profilesDir)

        this.originalConfig := ProfileManager.configPath
        this.originalProfiles := ProfileManager.profilesPath
        this.originalRevisions := ProfileManager.profileRevisions

        ProfileManager.configPath := this.tempRoot "\config.ini"
        ProfileManager.profilesPath := this.profilesDir
        ProfileManager.profiles := Map()
        ProfileManager.profileRevisions := Map()
        ProfileManager.currentProfile := ""
        ProfileManager.defaultProfile := ""
        ProfileManager.loadErrors := []
    }

    TestProfileSaveAndLoad() {
        profile := ProfileManager.NewProfile()
        profile.binds["Toggle Dictation"] := "^d"
        profile.binds["Select Next Field"] := "^n"

        ProfileManager.profiles["TestProfile"] := profile
        ProfileManager.SaveProfile("TestProfile", profile)
        Assert.True(FileExist(ProfileManager.profilesPath "\TestProfile.ini") != "")

        ProfileManager.LoadProfiles()
        Assert.True(ProfileManager.profiles.Has("TestProfile"))
        Assert.Equal("^d", ProfileManager.profiles["TestProfile"].binds["Toggle Dictation"])
    }

    TestProfileNameContainingIniRoundTrips() {
        name := "reading.ini.room"
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        ProfileManager.profiles[name] := profile
        ProfileManager.SaveProfile(name, profile)

        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.profiles.Has(name))
        Assert.Equal("^s", ProfileManager.profiles[name].binds["Sign Report"])
        Assert.Equal(1, ProfileManager.profiles.Count)
    }

    TestDefaultProfileTracking() {
        ProfileManager.profiles["DefaultTest"] := ProfileManager.NewProfile()
        Assert.True(ProfileManager.SetDefaultProfile("DefaultTest"))
        ProfileManager.LoadProfiles()
        Assert.Equal("DefaultTest", ProfileManager.defaultProfile)
    }

    TestProfileRename() {
        ProfileManager.profiles["OldName"] := ProfileManager.NewProfile()
        ProfileManager.SaveProfile("OldName", ProfileManager.profiles["OldName"])

        Assert.True(ProfileManager.RenameProfile("OldName", "NewName"))
        Assert.True(ProfileManager.profiles.Has("NewName"))
        Assert.False(ProfileManager.profiles.Has("OldName"))
        Assert.True(FileExist(ProfileManager.profilesPath "\NewName.ini") != "")
        Assert.False(FileExist(ProfileManager.profilesPath "\OldName.ini"))
    }

    TestProfileCaseOnlyRename() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        ProfileManager.profiles["Night"] := profile
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)
        Assert.True(ProfileManager.SetDefaultProfile("Night"))

        Assert.True(ProfileManager.RenameProfile("Night", "night"))

        inMemoryName := ""
        for name, _ in ProfileManager.profiles
            inMemoryName := name
        diskName := ""
        Loop Files ProfileManager.profilesPath "\*.ini"
            diskName := A_LoopFileName

        Assert.True(inMemoryName == "night")
        Assert.True(diskName == "night.ini")
        Assert.True(ProfileManager.currentProfile == "night")
        Assert.True(ProfileManager.defaultProfile == "night")
        Assert.True(IniRead(ProfileManager.configPath, "Settings", "DefaultProfile") == "night")
    }

    TestProfileDeletionRules() {
        ProfileManager.profiles["One"] := ProfileManager.NewProfile()
        ProfileManager.profiles["Two"] := ProfileManager.NewProfile()
        ProfileManager.SaveProfile("One", ProfileManager.profiles["One"])
        ProfileManager.SaveProfile("Two", ProfileManager.profiles["Two"])

        Assert.True(ProfileManager.DeleteProfile("One"))
        Assert.False(ProfileManager.profiles.Has("One"))
        Assert.False(FileExist(ProfileManager.profilesPath "\One.ini"))

        Assert.False(ProfileManager.DeleteProfile("Two"))  ; last profile should not delete
        Assert.True(ProfileManager.profiles.Has("Two"))
    }

    TestFailedDefaultDeletionPreservesProfile() {
        for name in ["One", "Two"] {
            ProfileManager.profiles[name] := ProfileManager.NewProfile()
            ProfileManager.SaveProfile(name, ProfileManager.profiles[name])
        }
        Assert.True(ProfileManager.SetDefaultProfile("One"))

        ; Make the config path unwritable as an INI target. Deletion must fail before
        ; the profile file or in-memory profile is removed.
        FileDelete(ProfileManager.configPath)
        DirCreate(ProfileManager.configPath)

        Assert.False(ProfileManager.DeleteProfile("One"))
        Assert.True(ProfileManager.profiles.Has("One"))
        Assert.True(FileExist(ProfileManager.ProfilePath("One")) != "")
        Assert.Equal("One", ProfileManager.defaultProfile)
    }

    TestCustomFunctionPersistence() {
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Test"] := "^t"
        profile.customFuncs["Custom: Test"] := {keys: "{Tab}", window: "TestWindow"}

        ProfileManager.profiles["CustomProfile"] := profile
        ProfileManager.SaveProfile("CustomProfile", profile)
        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.profiles["CustomProfile"].customFuncs.Has("Custom: Test"))
        loaded := ProfileManager.profiles["CustomProfile"].customFuncs["Custom: Test"]
        Assert.Equal("{Tab}", loaded.keys)
        Assert.Equal("TestWindow", loaded.window)
    }

    TestUnboundCustomFunctionPersistence() {
        profile := ProfileManager.NewProfile()
        profile.customFuncs["Custom: Saved For Later"] := {keys: "{Tab}", window: "PowerScribe"}

        ProfileManager.profiles["CustomLibrary"] := profile
        ProfileManager.SaveProfile("CustomLibrary", profile)
        ProfileManager.LoadProfiles()

        loaded := ProfileManager.profiles["CustomLibrary"]
        Assert.True(loaded.customFuncs.Has("Custom: Saved For Later"))
        Assert.False(loaded.binds.Has("Custom: Saved For Later"))
        Assert.Equal("{Tab}", loaded.customFuncs["Custom: Saved For Later"].keys)
    }

    TestScopePersistence() {
        profile := ProfileManager.NewProfile()
        profile.binds["Toggle Dictation"] := "^d"
        profile.scopes["Toggle Dictation"] := "PACS or PowerScribe"

        ProfileManager.profiles["ScopedProfile"] := profile
        ProfileManager.SaveProfile("ScopedProfile", profile)
        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.profiles.Has("ScopedProfile"))
        Assert.Equal("PACS or PowerScribe", ProfileManager.profiles["ScopedProfile"].scopes["Toggle Dictation"])
    }

    ; A bind saved with no scope at all reloads as Any, which is how every bind
    ; behaved before scopes existed
    TestScopeDefaultsToAnyWhenAbsent() {
        profile := ProfileManager.NewProfile()
        profile.binds["Draft Report"] := "^f"
        ; deliberately no profile.scopes entry

        ProfileManager.SaveProfile("NoScope", profile)
        reloaded := ProfileManager.LoadProfile(ProfileManager.profilesPath "\NoScope.ini")

        Assert.Equal("^f", reloaded.binds["Draft Report"])
        Assert.Equal("Any", reloaded.scopes["Draft Report"])
    }

    ; A profile file written before scopes existed has no [Scopes] section at all
    TestLegacyProfileWithoutScopesSection() {
        path := ProfileManager.profilesPath "\Ancient.ini"
        IniWrite("Sign Report|Custom: Yell|", path, "Functions", "Order")
        IniWrite("^s", path, "Keybinds", "Sign Report")
        IniWrite("!y", path, "Keybinds", "Custom: Yell")
        IniWrite("HELLO", path, "CustomFunctions", "Custom: Yell_keys")
        IniWrite("", path, "CustomFunctions", "Custom: Yell_window")

        legacy := ProfileManager.LoadProfile(path)
        Assert.Equal("^s", legacy.binds["Sign Report"])
        Assert.Equal("Any", legacy.scopes["Sign Report"])
        Assert.True(legacy.customFuncs.Has("Custom: Yell"))
        Assert.Equal("HELLO", legacy.customFuncs["Custom: Yell"].keys)
        Assert.Equal(0, legacy.modalityAttendings.Count)

        ; Re-saving must not lose the custom function or invent modality entries
        ProfileManager.SaveProfile("AncientResaved", legacy)
        resaved := ProfileManager.LoadProfile(ProfileManager.profilesPath "\AncientResaved.ini")
        Assert.Equal("^s", resaved.binds["Sign Report"])
        Assert.Equal("Any", resaved.scopes["Sign Report"])
        Assert.Equal("HELLO", resaved.customFuncs["Custom: Yell"].keys)
    }

    ; Profiles written under the older [KeybindScopes] scheme must not silently lose
    ; their restriction when loaded by the per-bind scope code
    TestLegacyScopeMigration() {
        path := ProfileManager.profilesPath "\LegacyScoped.ini"
        IniWrite("Toggle Dictation|Sign Report|Draft Report|", path, "Functions", "Order")
        IniWrite("^d", path, "Keybinds", "Toggle Dictation")
        IniWrite("^s", path, "Keybinds", "Sign Report")
        IniWrite("^f", path, "Keybinds", "Draft Report")
        IniWrite("restricted", path, "KeybindScopes", "Toggle Dictation")
        IniWrite("global", path, "KeybindScopes", "Sign Report")
        IniWrite("default", path, "KeybindScopes", "Draft Report")

        loaded := ProfileManager.LoadProfile(path)
        Assert.Equal("PACS or PowerScribe", loaded.scopes["Toggle Dictation"])
        Assert.Equal("Any", loaded.scopes["Sign Report"])

        ; "default" resolves through the old global setting
        Assert.Equal(
            Settings.Get("RestrictHotkeysByActiveWindow") ? "PACS or PowerScribe" : "Any",
            loaded.scopes["Draft Report"]
        )
    }

    TestModalityAttendingPersistence() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Neuro"] := "Smith"
        profile.modalityAttendings["Chest"] := ""  ; configured as "leave the default"

        ProfileManager.profiles["ModalityProfile"] := profile
        ProfileManager.SaveProfile("ModalityProfile", profile)
        ProfileManager.LoadProfiles()
        ProfileManager.currentProfile := "ModalityProfile"

        Assert.Equal("Smith", ProfileManager.GetModalityAttending("Neuro"))
        Assert.Equal("", ProfileManager.GetModalityAttending("Chest"))
        ; Unconfigured modalities keep the pre-assignment behaviour
        Assert.Equal("Body", ProfileManager.GetModalityAttending("Body"))

        ; A blank assignment stays on file, so "leave PowerScribe's default" survives a
        ; reload rather than reverting to the modality name
        stored := ProfileManager.profiles["ModalityProfile"]
        Assert.True(stored.modalityAttendings.Has("Chest"))
        Assert.False(stored.modalityAttendings.Has("Body"), "Unconfigured modality must not be invented on load")
    }

    TestSaveRejectsMalformedCustomCommand() {
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Broken"] := "^b"
        profile.customFuncs["Custom: Broken"] := {window: "PowerScribe"}

        Assert.Throws(
            () => ProfileManager.SaveProfile("BrokenCustom", profile),
            "custom command configuration"
        )
    }

    TestMalformedLegacyScopeIsRejected() {
        path := ProfileManager.profilesPath "\MalformedLegacyScope.ini"
        IniWrite("Sign Report|", path, "Functions", "Order")
        IniWrite("^s", path, "Keybinds", "Sign Report")
        IniWrite("restrictd", path, "KeybindScopes", "Sign Report")

        Assert.Throws(
            () => ProfileManager.LoadProfile(path),
            "unknown legacy hotkey scope"
        )
    }

    TestDefaultPathsAreAnchored() {
        Assert.Equal(A_ScriptDir "\config.ini", this.originalConfig)
        Assert.Equal(A_ScriptDir "\profiles", this.originalProfiles)
    }

    TestProfileNameValidation() {
        Assert.True(ProfileManager.IsValidProfileName("Night Shift"))
        for name in ["", "..", "../escape", "folder\escape", "bad:name", "CON", "name.", "name "] {
            Assert.False(ProfileManager.IsValidProfileName(name), "Expected unsafe name to be rejected: " name)
        }
    }

    TestCreateProfileRejectsUnsafeAndDuplicateNames() {
        Assert.False(ProfileManager.CreateProfile("../escape"))
        Assert.Equal(0, ProfileManager.profiles.Count)

        Assert.True(ProfileManager.CreateProfile("Reading Room"))
        original := ProfileManager.profiles["Reading Room"]
        Assert.False(ProfileManager.CreateProfile("Reading Room"))
        Assert.True(ProfileManager.profiles["Reading Room"] = original)
        Assert.True(FileExist(ProfileManager.profilesPath "\Reading Room.ini") != "")
    }

    TestSaveRejectsUnsafeIniKeys() {
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Bad|Name"] := "^b"

        Assert.Throws(
            () => ProfileManager.SaveProfile("UnsafeKey", profile),
            "unsafe function name"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\UnsafeKey.ini"))
    }

    TestFailedRenamePreservesOriginalProfile() {
        original := ProfileManager.NewProfile()
        original.binds["Toggle Dictation"] := "^d"
        ProfileManager.profiles["Original"] := original
        ProfileManager.SaveProfile("Original", original)

        ; A directory at the destination path makes the final atomic replacement fail.
        DirCreate(ProfileManager.profilesPath "\Blocked.ini")

        Assert.False(ProfileManager.RenameProfile("Original", "Blocked"))
        Assert.True(ProfileManager.profiles.Has("Original"))
        Assert.False(ProfileManager.profiles.Has("Blocked"))
        Assert.True(FileExist(ProfileManager.profilesPath "\Original.ini") != "")
        reloaded := ProfileManager.LoadProfile(ProfileManager.profilesPath "\Original.ini")
        Assert.Equal("^d", reloaded.binds["Toggle Dictation"])
    }

    TestMalformedProfileDoesNotBlockValidProfiles() {
        good := ProfileManager.NewProfile()
        good.binds["Sign Report"] := "^s"
        ProfileManager.SaveProfile("Good", good)
        FileAppend("this is not an INI profile", ProfileManager.profilesPath "\Malformed.ini")

        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.profiles.Has("Good"))
        Assert.False(ProfileManager.profiles.Has("Malformed"))
        Assert.Equal(1, ProfileManager.loadErrors.Length)
    }

    TestDefaultProfileMustExist() {
        Assert.False(ProfileManager.SetDefaultProfile("Missing"))
        Assert.Equal("", ProfileManager.defaultProfile)
        Assert.False(FileExist(ProfileManager.configPath))
    }

    TestDuplicateBindingsAreRejected() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.binds["Draft Report"] := "^S"

        Assert.Throws(
            () => ProfileManager.SaveProfile("Duplicates", profile),
            "duplicate hotkey"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\Duplicates.ini"))
    }

    TestEquivalentModifierBindingsAreRejected() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^!s"
        profile.binds["Draft Report"] := "!^S"

        Assert.Throws(
            () => ProfileManager.SaveProfile("EquivalentDuplicates", profile),
            "duplicate hotkey"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\EquivalentDuplicates.ini"))
    }

    TestUnknownScopeIsRejected() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "PACS typo"

        Assert.Throws(
            () => ProfileManager.SaveProfile("UnknownScope", profile),
            "hotkey scope"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\UnknownScope.ini"))
    }

    Teardown() {
        try {
            DirDelete(this.tempRoot, true)
        }
        ProfileManager.configPath := this.originalConfig
        ProfileManager.profilesPath := this.originalProfiles
        ProfileManager.profiles := Map()
        ProfileManager.profileRevisions := this.originalRevisions
        ProfileManager.currentProfile := ""
        ProfileManager.defaultProfile := ""
        ProfileManager.loadErrors := []
    }
}
