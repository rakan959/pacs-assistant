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
        "TestCaseOnlyRenameDoubleMoveFailureRemainsReloadable",
        "TestInterruptedCaseOnlyRenameIsRecoveredOnStartup",
        "TestInterruptedCaseOnlyRenameNeverOverwritesConflictingProfile",
        "TestProfileDeletionRules",
        "TestFailedDefaultDeletionPreservesProfile",
        "TestDefaultDeleteRollbackFailureIsSurfacedAndReconciled",
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
        "TestSaveRejectsCaseCollidingCustomCommands",
        "TestSaveRejectsCaseCollidingModalities",
        "TestSaveRejectsReservedModalityMetadataKey",
        "TestLoadRejectsCaseCollidingPersistedKeys",
        "TestLoadRejectsReservedModalityMetadataKey",
        "TestFailedRenamePreservesOriginalProfile",
        "TestRenameRollbackFailurePublishesTheRetainedCopy",
        "TestMalformedProfileDoesNotBlockValidProfiles",
        "TestDefaultProfileMustExist",
        "TestDuplicateBindingsAreRejected",
        "TestEquivalentModifierBindingsAreRejected",
        "TestEquivalentCustomCombinationBindingsAreRejected",
        "TestUnknownScopeIsRejected",
        "TestExplicitBlankPersistedScopeIsRejected",
        "TestPersistedMissingSentinelIsRejectedAsAScope",
        "TestNonCanonicalPersistedScopeIsRejected"
    ]

    Setup() {
        this.tempRoot := A_Temp "\pacs_profile_tests_" A_TickCount
        this.profilesDir := this.tempRoot "\profiles"
        DirCreate(this.profilesDir)

        this.originalConfig := ProfileManager.configPath
        this.originalProfiles := ProfileManager.profilesPath
        this.originalRevisions := ProfileManager.profileRevisions
        this.originalStorageDriver := ProfileManager.storageDriver
        this.originalLastError := ProfileManager.lastError
        this.originalRecoveryRequired := ProfileManager.recoveryRequired

        ProfileManager.configPath := this.tempRoot "\config.ini"
        ProfileManager.profilesPath := this.profilesDir
        ProfileManager.profiles := Map()
        ProfileManager.profileRevisions := Map()
        ProfileManager.currentProfile := ""
        ProfileManager.defaultProfile := ""
        ProfileManager.loadErrors := []
        ProfileManager.storageDriver := NativeProfileStorageDriver()
        ProfileManager.lastError := ""
        ProfileManager.recoveryRequired := false
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

    TestCaseOnlyRenameDoubleMoveFailureRemainsReloadable() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "Any"
        ProfileManager.profiles["Night"] := profile
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)
        driver := FaultInjectingProfileStorageDriver()
        driver.failMoveCalls[2] := true
        driver.failMoveCalls[3] := true
        ProfileManager.storageDriver := driver

        Assert.False(ProfileManager.RenameProfile("Night", "night"))
        Assert.True(FileExist(ProfileManager.ProfilePath("Night")) != "")
        Assert.False(ProfileManager.recoveryRequired)

        ; Simulate a restart: only canonical *.ini files are discovered.
        ProfileManager.storageDriver := NativeProfileStorageDriver()
        ProfileManager.LoadProfiles()
        Assert.True(ProfileManager.profiles.Has("Night"))
        Assert.Equal("^s", ProfileManager.profiles["Night"].binds["Sign Report"])
    }

    TestInterruptedCaseOnlyRenameIsRecoveredOnStartup() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "Any"
        canonicalPath := ProfileManager.profilesPath "\Night.ini"
        interruptedPath := canonicalPath ".case-rename-1234-1"
        ProfileManager.SaveProfile("Night", profile)
        FileMove(canonicalPath, interruptedPath)

        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.profiles.Has("Night"))
        Assert.Equal("^s", ProfileManager.profiles["Night"].binds["Sign Report"])
        Assert.True(FileExist(canonicalPath) != "")
        Assert.False(FileExist(interruptedPath) != "")
        Assert.False(ProfileManager.recoveryRequired)
        Assert.Equal(0, ProfileManager.loadErrors.Length)
    }

    TestInterruptedCaseOnlyRenameNeverOverwritesConflictingProfile() {
        original := ProfileManager.NewProfile()
        original.binds["Sign Report"] := "^s"
        original.scopes["Sign Report"] := "Any"
        ProfileManager.SaveProfile("Night", original)

        conflicting := ProfileManager.CloneProfile(original)
        conflicting.binds["Sign Report"] := "^n"
        conflictingPath := ProfileManager.profilesPath "\Conflicting.ini"
        ProfileManager.SaveProfile("Conflicting", conflicting)
        interruptedPath := ProfileManager.profilesPath "\Night.ini.case-rename-1234-1"
        FileMove(conflictingPath, interruptedPath)

        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.profiles.Has("Night"))
        Assert.Equal("^s", ProfileManager.profiles["Night"].binds["Sign Report"])
        Assert.True(FileExist(interruptedPath) != "")
        Assert.True(ProfileManager.recoveryRequired)
        Assert.Equal(1, ProfileManager.loadErrors.Length)
        Assert.True(InStr(ProfileManager.loadErrors[1].message, "conflicts") > 0)
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

    TestDefaultDeleteRollbackFailureIsSurfacedAndReconciled() {
        for name in ["One", "Two"] {
            ProfileManager.profiles[name] := ProfileManager.NewProfile()
            ProfileManager.SaveProfile(name, ProfileManager.profiles[name])
        }
        Assert.True(ProfileManager.SetDefaultProfile("One"))
        driver := FaultInjectingProfileStorageDriver()
        driver.failDeleteFiles[ProfileManager.ProfilePath("One")] := true
        driver.failWriteValues["One"] := true
        ProfileManager.storageDriver := driver

        Assert.False(ProfileManager.DeleteProfile("One"))
        Assert.True(ProfileManager.profiles.Has("One"))
        Assert.True(FileExist(ProfileManager.ProfilePath("One")) != "")
        Assert.Equal("", IniRead(
            ProfileManager.configPath,
            "Settings",
            "DefaultProfile",
            ""
        ))
        Assert.Equal("", ProfileManager.defaultProfile)
        Assert.True(ProfileManager.recoveryRequired)
        Assert.True(InStr(ProfileManager.lastError, "simulated INI write failure") > 0)
        Assert.False(ProfileManager.SetDefaultProfile("Two"))
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

    TestSaveRejectsCaseCollidingCustomCommands() {
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Foo"] := "^a"
        profile.binds["Custom: foo"] := "^b"
        profile.scopes["Custom: Foo"] := "Any"
        profile.scopes["Custom: foo"] := "Any"
        profile.customFuncs["Custom: Foo"] := {keys: "FIRST", window: ""}
        profile.customFuncs["Custom: foo"] := {keys: "SECOND", window: ""}

        Assert.Throws(
            () => ProfileManager.SaveProfile("CaseCollision", profile),
            "case-insensitive INI key"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\CaseCollision.ini"))
    }

    TestSaveRejectsCaseCollidingModalities() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Neuro"] := "First"
        profile.modalityAttendings["neuro"] := "Second"

        Assert.Throws(
            () => ProfileManager.SaveProfile("ModalityCollision", profile),
            "case-insensitive INI key"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\ModalityCollision.ini"))
    }

    TestSaveRejectsReservedModalityMetadataKey() {
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["oRdEr"] := "Attending"

        Assert.Throws(
            () => ProfileManager.SaveProfile("ReservedModality", profile),
            "reserved INI key"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\ReservedModality.ini"))
    }

    TestLoadRejectsCaseCollidingPersistedKeys() {
        path := ProfileManager.profilesPath "\PersistedCollision.ini"
        FileAppend(
            "[Functions]`n"
            . "Order=Custom: Foo|Custom: foo|`n"
            . "[Keybinds]`n"
            . "Custom: Foo=^a`n"
            . "[Scopes]`n"
            . "Custom: Foo=Any`n"
            . "[CustomFunctions]`n"
            . "Order=Custom: Foo|Custom: foo|`n"
            . "Custom: Foo_keys=FIRST`n"
            . "Custom: Foo_window=`n",
            path
        )

        Assert.Throws(
            () => ProfileManager.LoadProfile(path),
            "case-insensitive INI key"
        )
    }

    TestLoadRejectsReservedModalityMetadataKey() {
        path := ProfileManager.profilesPath "\PersistedReservedModality.ini"
        FileAppend(
            "[Functions]`n"
            . "Order=`n"
            . "[ModalityAttendings]`n"
            . "Order=Order|`n",
            path
        )

        Assert.Throws(
            () => ProfileManager.LoadProfile(path),
            "reserved INI key"
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

    TestRenameRollbackFailurePublishesTheRetainedCopy() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "Any"
        ProfileManager.profiles["Old"] := profile
        ProfileManager.SaveProfile("Old", profile)
        Assert.True(ProfileManager.SetDefaultProfile("Old"))
        driver := FaultInjectingProfileStorageDriver()
        driver.failDeleteFiles[ProfileManager.ProfilePath("Old")] := true
        driver.failWriteValues["Old"] := true
        ProfileManager.storageDriver := driver

        Assert.False(ProfileManager.RenameProfile("Old", "New"))
        Assert.True(ProfileManager.profiles.Has("Old"))
        Assert.True(ProfileManager.profiles.Has("New"))
        Assert.True(FileExist(ProfileManager.ProfilePath("Old")) != "")
        Assert.True(FileExist(ProfileManager.ProfilePath("New")) != "")
        Assert.Equal("New", IniRead(
            ProfileManager.configPath,
            "Settings",
            "DefaultProfile",
            ""
        ))
        Assert.Equal("New", ProfileManager.defaultProfile)
        Assert.True(ProfileManager.recoveryRequired)
        Assert.True(InStr(ProfileManager.lastError, "simulated INI write failure") > 0)
        ProfileManager.profiles["New"].binds["Sign Report"] := "^n"
        Assert.Equal("^s", ProfileManager.profiles["Old"].binds["Sign Report"])
        Assert.False(ProfileManager.RenameProfile("Old", "Another"))
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

    TestEquivalentCustomCombinationBindingsAreRejected() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "F23 & F24"
        profile.binds["Draft Report"] := "F23 & ~F24"

        Assert.Throws(
            () => ProfileManager.SaveProfile("CombinationDuplicates", profile),
            "duplicate hotkey"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\CombinationDuplicates.ini"))
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

    TestExplicitBlankPersistedScopeIsRejected() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "PACS"
        path := ProfileManager.profilesPath "\BlankScope.ini"
        ProfileManager.SaveProfile("BlankScope", profile)
        IniWrite("", path, "Scopes", "Sign Report")

        Assert.Throws(() => ProfileManager.LoadProfile(path), "hotkey scope")
    }

    TestPersistedMissingSentinelIsRejectedAsAScope() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "PACS"
        path := ProfileManager.profilesPath "\SentinelScope.ini"
        ProfileManager.SaveProfile("SentinelScope", profile)
        IniWrite("{PACS-ASSISTANT-MISSING-INI-VALUE}", path, "Scopes", "Sign Report")

        Assert.Throws(() => ProfileManager.LoadProfile(path), "hotkey scope")
    }

    TestNonCanonicalPersistedScopeIsRejected() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "PACS"
        path := ProfileManager.profilesPath "\NonCanonical.ini"
        ProfileManager.SaveProfile("NonCanonical", profile)
        IniWrite("pacs", path, "Scopes", "Sign Report")

        Assert.Throws(() => ProfileManager.LoadProfile(path), "hotkey scope")
    }

    Teardown() {
        try {
            DirDelete(this.tempRoot, true)
        }
        ProfileManager.configPath := this.originalConfig
        ProfileManager.profilesPath := this.originalProfiles
        ProfileManager.profiles := Map()
        ProfileManager.profileRevisions := this.originalRevisions
        ProfileManager.storageDriver := this.originalStorageDriver
        ProfileManager.lastError := this.originalLastError
        ProfileManager.recoveryRequired := this.originalRecoveryRequired
        ProfileManager.currentProfile := ""
        ProfileManager.defaultProfile := ""
        ProfileManager.loadErrors := []
    }
}

class FaultInjectingProfileStorageDriver extends NativeProfileStorageDriver {
    __New() {
        this.failDeleteFiles := Map()
        this.failWriteValues := Map()
        this.failMoveCalls := Map()
        this.moveCalls := 0
    }

    DeleteFile(path) {
        if this.failDeleteFiles.Has(path)
            throw Error("simulated file deletion failure")
        return super.DeleteFile(path)
    }

    WriteIni(value, path, section, key) {
        if this.failWriteValues.Has(value)
            throw Error("simulated INI write failure")
        return super.WriteIni(value, path, section, key)
    }

    MoveFile(sourcePath, destinationPath, overwrite := false) {
        this.moveCalls++
        if this.failMoveCalls.Has(this.moveCalls)
            throw Error("simulated file move failure")
        return super.MoveFile(sourcePath, destinationPath, overwrite)
    }
}
