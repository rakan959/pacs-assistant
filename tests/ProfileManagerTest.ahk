; = CONTENTS
;   + Preamble
;   + ProfileManagerTest class (profile CRUD, keybind/scope persistence, modality/attending)
;   + Test doubles (FaultInjectingProfileStorageDriver)

#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include TestRunner.ahk
#Include SettingsFixture.ahk
#Include LogCapture.ahk

class ProfileManagerTest {
    static tests := [
        "TestProfileSaveAndLoad",
        "TestProfileNameContainingIniRoundTrips",
        "TestDefaultProfileTracking",
        "TestStoredDefaultProfileIsReadAtStartup",
        "TestQuoteWrappedDefaultProfileIsReadAtStartup",
        "TestProfileRename",
        "TestProfileCaseOnlyRename",
        "TestLoadCanonicalizesCaseDriftedDefaultProfile",
        "TestCaseOnlyRenameDoubleMoveFailureRemainsReloadable",
        "TestCaseOnlyRenameRollbackFailureFollowsTheStoredName",
        "TestInterruptedCaseOnlyRenameIsRecoveredOnStartup",
        "TestInterruptedCaseOnlyRenameNeverOverwritesConflictingProfile",
        "TestRefusedChangeNamesTheEarlierStorageFailure",
        "TestSaveIsRefusedWhileStorageNeedsRecovery",
        "TestProfileDeletionRules",
        "TestFailedDefaultDeletionPreservesProfile",
        "TestDefaultDeleteRollbackFailureIsSurfacedAndReconciled",
        "TestCustomFunctionPersistence",
        "TestUnboundCustomFunctionPersistence",
        "TestFreeTextValuesRoundTripExactly",
        "TestUnquotedLegacyValuesStillLoad",
        "TestScopePersistence",
        "TestScopeDefaultsToAnyWhenAbsent",
        "TestLegacyScopeMigration",
        "TestMalformedLegacyScopeIsRejected",
        "TestLegacyProfileWithoutScopesSection",
        "TestModalityAttendingPersistence",
        "TestProfileNameValidation",
        "TestCreateProfileRejectsUnsafeAndDuplicateNames",
        "TestCreateProfileKeepsAnUnloadedFileOfThatName",
        "TestRenameKeepsAnUnloadedFileOfThatName",
        "TestNameDifferingOnlyInCaseNamesTheExistingProfile",
        "TestIniKeyRules",
        "TestSaveRejectsUnsafeIniKeys",
        "TestFailedSaveLeavesTheSavedFileUnchanged",
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
        this.tempRoot := TestTempPath("pacs-profile-tests")
        this.profilesDir := this.tempRoot "\profiles"
        DirCreate(this.profilesDir)

        this.originalConfig := ProfileManager.configPath
        this.originalProfilesPath := ProfileManager.profilesPath
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
        this.originalDefaultProfile := ProfileManager.defaultProfile
        this.originalLoadErrors := ProfileManager.loadErrors
        this.originalRevisions := ProfileManager.profileRevisions
        this.originalStorageDriver := ProfileManager.storageDriver
        this.originalLastError := ProfileManager.lastError
        this.originalRecoveryRequired := ProfileManager.recoveryRequired
        this.originalRecoveryCause := ProfileManager.recoveryCause

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
        ProfileManager.recoveryCause := ""
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
        ProfileManager.SaveProfile("DefaultTest", ProfileManager.profiles["DefaultTest"])
        Assert.True(ProfileManager.SetDefaultProfile("DefaultTest"))
        ProfileManager.LoadProfiles()
        Assert.Equal("DefaultTest", ProfileManager.defaultProfile)
    }

    ; LoadProfiles never reads config.ini; the class initializer does, at startup.
    TestStoredDefaultProfileIsReadAtStartup() {
        ProfileManager.profiles["Night"] := ProfileManager.NewProfile()
        ProfileManager.SaveProfile("Night", ProfileManager.profiles["Night"])
        Assert.True(ProfileManager.SetDefaultProfile("Night"))
        ProfileManager.defaultProfile := ""

        ProfileManager.__New()
        ProfileManager.LoadProfiles()

        Assert.Equal("Night", ProfileManager.defaultProfile)
        Assert.Equal("Night", ProfileManager.currentProfile)
    }

    ; IniRead drops one pair of outer quotes, which a profile name may carry.
    TestQuoteWrappedDefaultProfileIsReadAtStartup() {
        name := "'Night'"
        ProfileManager.profiles[name] := ProfileManager.NewProfile()
        ProfileManager.SaveProfile(name, ProfileManager.profiles[name])
        Assert.True(ProfileManager.SetDefaultProfile(name))
        ProfileManager.defaultProfile := ""

        ProfileManager.__New()
        ProfileManager.LoadProfiles()

        Assert.Equal(name, ProfileManager.defaultProfile)
        Assert.Equal(name, ProfileManager.currentProfile)
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
        loop files ProfileManager.profilesPath "\*.ini"
            diskName := A_LoopFileName

        Assert.True(inMemoryName == "night")
        Assert.True(diskName == "night.ini")
        Assert.True(ProfileManager.currentProfile == "night")
        Assert.True(ProfileManager.defaultProfile == "night")
        Assert.Equal("night", IniRead(ProfileManager.configPath, "Settings", "DefaultProfile", "<missing>"))
    }

    TestLoadCanonicalizesCaseDriftedDefaultProfile() {
        ; A crash after the case-only file move but before config publication can
        ; leave the persisted default using the old casing. Windows still has one
        ; profile identity, so startup must bind that default to the canonical
        ; filename instead of silently dropping the selection.
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        ProfileManager.profiles["night"] := profile
        ProfileManager.SaveProfile("night", profile)
        ProfileManager.defaultProfile := "Night"

        ProfileManager.LoadProfiles()

        Assert.True(ProfileManager.defaultProfile == "night")
        Assert.True(ProfileManager.currentProfile == "night")
        Assert.True(ProfileManager.profiles.Has("night"))
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

    TestCaseOnlyRenameRollbackFailureFollowsTheStoredName() {
        ; Publishing the new default fails and so does the first move back, so the
        ; file keeps the new casing. Memory must follow the name Windows stored.
        profile := ProfileManager.NewProfile()
        ProfileManager.profiles["Night"] := profile
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)
        Assert.True(ProfileManager.SetDefaultProfile("Night"))
        driver := FaultInjectingProfileStorageDriver()
        driver.failWriteValues["night"] := true
        driver.failMoveCalls[3] := true
        ProfileManager.storageDriver := driver

        Assert.False(ProfileManager.RenameProfile("Night", "night"))

        diskName := ""
        loop files ProfileManager.profilesPath "\*.ini"
            diskName := A_LoopFileName
        Assert.True(diskName == "night.ini", diskName)
        Assert.True(ProfileManager.recoveryRequired)
        Assert.True(ProfileManager.profiles.Has("night"))
        Assert.False(ProfileManager.profiles.Has("Night"))
        Assert.True(ProfileManager.currentProfile == "night")
        Assert.True(ProfileManager.defaultProfile == "night")
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
        ; A later change is refused with that cause, not an unrelated reason.
        Assert.False(ProfileManager.CreateProfile("Fresh"))
        Assert.True(InStr(ProfileManager.lastError, "An earlier profile storage operation could not be completed: "), ProfileManager.lastError)
        Assert.True(InStr(ProfileManager.lastError, "conflicts"), ProfileManager.lastError)
    }

    ; Once storage needs a restart, every refused change says so and why, rather
    ; than a reason that belongs to that change or the earlier failure's own text.
    TestRefusedChangeNamesTheEarlierStorageFailure() {
        Assert.False(ProfileManager.FailStorageMutation("simulated rollback failure", true))
        expected := "An earlier profile storage operation could not be completed: simulated rollback failure"

        Assert.False(ProfileManager.CreateProfile("Fresh"))
        Assert.Equal(expected, ProfileManager.lastError)
        Assert.False(ProfileManager.SetDefaultProfile("Fresh"))
        Assert.Equal(expected, ProfileManager.lastError)
    }

    ; A save then would write a profile file the failed operation may still need.
    TestSaveIsRefusedWhileStorageNeedsRecovery() {
        Assert.False(ProfileManager.FailStorageMutation("simulated rollback failure", true))

        Assert.Throws(
            () => ProfileManager.SaveProfile("Fresh", ProfileManager.NewProfile()),
            "recovery-required"
        )
        Assert.False(FileExist(ProfileManager.profilesPath "\Fresh.ini"))
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

    ; IniRead trims spaces and strips outer quotes, so free text is written quoted.
    ; Unquoted, keys of " " would reload as "" and make the whole profile
    ; unloadable, and a whitespace-only target window would reload as "" (any window).
    TestFreeTextValuesRoundTripExactly() {
        values := [" ", "Hello ", " lead", '"quoted"', "'single'", '""', "`t tab", 'a "mid" b']
        profile := ProfileManager.NewProfile()
        for index, value in values {
            profile.customFuncs["Custom: Edge " index] := {keys: value, window: value}
            profile.modalityAttendings["Edge" index] := value
        }

        ProfileManager.profiles["EdgeValues"] := profile
        ProfileManager.SaveProfile("EdgeValues", profile)
        ProfileManager.LoadProfiles()

        Assert.Equal(0, ProfileManager.loadErrors.Length)
        loaded := ProfileManager.profiles["EdgeValues"]
        for index, value in values {
            Assert.Equal(value, loaded.customFuncs["Custom: Edge " index].keys)
            Assert.Equal(value, loaded.customFuncs["Custom: Edge " index].window)
            Assert.Equal(value, loaded.modalityAttendings["Edge" index])
        }
    }

    ; Profiles written before values were quoted still load unchanged.
    TestUnquotedLegacyValuesStillLoad() {
        path := ProfileManager.profilesPath "\Legacy.ini"
        IniWrite("", path, "Functions", "Order")
        IniWrite("Custom: Old|", path, "CustomFunctions", "Order")
        IniWrite("HELLO", path, "CustomFunctions", "Custom: Old_keys")
        IniWrite("PowerScribe", path, "CustomFunctions", "Custom: Old_window")
        IniWrite("Neuro|", path, "ModalityAttendings", "Order")
        IniWrite("Smith", path, "ModalityAttendings", "Neuro")

        loaded := ProfileManager.LoadProfile(path)

        Assert.Equal("HELLO", loaded.customFuncs["Custom: Old"].keys)
        Assert.Equal("PowerScribe", loaded.customFuncs["Custom: Old"].window)
        Assert.Equal("Smith", loaded.modalityAttendings["Neuro"])
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

        ; "default" resolves through the old global setting, so pin that setting in an
        ; isolated file and check both of its values explicitly.
        savedSettings := UseTestSettings("legacy-scope-settings")
        try {
            SetTestSetting("RestrictHotkeysByActiveWindow", true)
            restricted := ProfileManager.LoadProfile(path)
            SetTestSetting("RestrictHotkeysByActiveWindow", false)
            unrestricted := ProfileManager.LoadProfile(path)
        } finally RestoreTestSettings(savedSettings)

        Assert.Equal("PACS or PowerScribe", restricted.scopes["Toggle Dictation"])
        Assert.Equal("Any", restricted.scopes["Sign Report"])
        Assert.Equal("PACS or PowerScribe", restricted.scopes["Draft Report"])
        Assert.Equal("Any", unrestricted.scopes["Draft Report"])
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

    TestProfileNameValidation() {
        Assert.True(ProfileManager.IsValidProfileName("Night Shift"))
        for name in ["", "..", "../escape", "folder\escape", "bad:name", "CON", "name.", "name ",
            " name", "CON.txt", "lpt1", "tab`there", 5] {
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

    ; A profile file that failed to load is not in the loaded set, but it is still
    ; the user's data: creating a profile of that name must not overwrite it.
    TestCreateProfileKeepsAnUnloadedFileOfThatName() {
        path := ProfileManager.profilesPath "\Broken.ini"
        FileAppend("[Functions]`nnot a valid profile`n", path, "UTF-16")

        Assert.False(ProfileManager.CreateProfile("Broken"))

        Assert.False(ProfileManager.profiles.Has("Broken"))
        Assert.Equal("[Functions]`nnot a valid profile`n", FileRead(path, "UTF-16"))
        ; The name is valid and not listed, so the refusal must say what blocks it.
        Assert.True(InStr(ProfileManager.lastError, path " already exists but is not loaded"), ProfileManager.lastError)
    }

    TestRenameKeepsAnUnloadedFileOfThatName() {
        ProfileManager.profiles["Day"] := ProfileManager.NewProfile()
        ProfileManager.SaveProfile("Day", ProfileManager.profiles["Day"])
        path := ProfileManager.profilesPath "\Broken.ini"
        FileAppend("[Functions]`nnot a valid profile`n", path, "UTF-16")

        Assert.False(ProfileManager.RenameProfile("Day", "Broken"))

        Assert.True(ProfileManager.profiles.Has("Day"))
        Assert.Equal("[Functions]`nnot a valid profile`n", FileRead(path, "UTF-16"))
        Assert.True(InStr(ProfileManager.lastError, path " already exists but is not loaded"), ProfileManager.lastError)
    }

    ; Windows file names ignore case, so the other profile owns the file.
    TestNameDifferingOnlyInCaseNamesTheExistingProfile() {
        Assert.True(ProfileManager.CreateProfile("Reading Room"))

        Assert.False(ProfileManager.CreateProfile("reading room"))

        Assert.False(ProfileManager.profiles.Has("reading room"))
        Assert.Equal("A profile named 'Reading Room' already exists.", ProfileManager.lastError)
    }

    ; INI keys are written as "key=value" lines inside [sections], and the Order
    ; lists join keys with "|", so these characters would corrupt the file.
    TestIniKeyRules() {
        for name in ["Sign Report", "Custom: Yell", "Custom: Ultrasound (US)"]
            Assert.True(ProfileManager.IsSafeIniKey(name), name)
        for name in ["", "a|b", "a=b", "[a", "a]", "a`nb", "a`rb", "a`tb", "a" Chr(1) "b", 5]
            Assert.False(ProfileManager.IsSafeIniKey(name), "Expected unsafe key to be rejected: " name)
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

    ; The save writes a temporary file and moves it over the profile, so a write
    ; that fails partway leaves the saved file exactly as it was.
    TestFailedSaveLeavesTheSavedFileUnchanged() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.modalityAttendings["Neuro"] := "Dr Old"
        ProfileManager.SaveProfile("Night", profile)
        path := ProfileManager.ProfilePath("Night")
        savedText := FileRead(path)
        revision := ProfileManager.GetProfileRevision("Night")

        profile.modalityAttendings["Neuro"] := "Dr New"
        originalWrite := ProfileManager.GetOwnPropDesc("WriteIniText")
        ProfileManager.DefineProp("WriteIniText", {call: FailAttendingWrite})
        try {
            Assert.Throws(() => ProfileManager.SaveProfile("Night", profile), "simulated attending write failure")
        } finally ProfileManager.DefineProp("WriteIniText", originalWrite)

        Assert.True(FileRead(path) == savedText, "the saved profile file changed")
        Assert.Equal(revision, ProfileManager.GetProfileRevision("Night"))
        Assert.Equal("Dr Old", ProfileManager.LoadProfile(path).modalityAttendings["Neuro"])
        leftovers := []
        loop files ProfileManager.profilesPath "\*"
            if (A_LoopFileName != "Night.ini")
                leftovers.Push(A_LoopFileName)
        Assert.Equal(0, leftovers.Length, leftovers.Length ? leftovers[1] : "")

        FailAttendingWrite(this, value, path, section, key) {
            if (section = "ModalityAttendings")
                throw Error("simulated attending write failure")
            originalWrite.Call(this, value, path, section, key)
        }
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

        capturedLog := LogCapture()
        try ProfileManager.LoadProfiles()
        finally {
            logged := capturedLog.Count("Profile could not be loaded: " ProfileManager.profilesPath "\Malformed.ini: ")
            capturedLog.Restore()
        }
        Assert.Equal(1, logged)

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
        try DirDelete(this.tempRoot, true)
        ProfileManager.configPath := this.originalConfig
        ProfileManager.profilesPath := this.originalProfilesPath
        ProfileManager.profiles := this.originalProfiles
        ProfileManager.currentProfile := this.originalCurrentProfile
        ProfileManager.defaultProfile := this.originalDefaultProfile
        ProfileManager.loadErrors := this.originalLoadErrors
        ProfileManager.profileRevisions := this.originalRevisions
        ProfileManager.storageDriver := this.originalStorageDriver
        ProfileManager.lastError := this.originalLastError
        ProfileManager.recoveryRequired := this.originalRecoveryRequired
        ProfileManager.recoveryCause := this.originalRecoveryCause
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

    WriteIniText(value, path, section, key) {
        if this.failWriteValues.Has(value)
            throw Error("simulated INI write failure")
        return super.WriteIniText(value, path, section, key)
    }

    MoveFile(sourcePath, destinationPath, overwrite := false) {
        this.moveCalls++
        if this.failMoveCalls.Has(this.moveCalls)
            throw Error("simulated file move failure")
        return super.MoveFile(sourcePath, destinationPath, overwrite)
    }
}
