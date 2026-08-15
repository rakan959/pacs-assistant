#Requires AutoHotkey v2.0
#Include ../KeybindGUI.ahk
#Include TestRunner.ahk

class KeybindGUITest {
    static Tests := [
        "TestSelectedFunctionPrefersBuiltIn",
        "TestSelectedFunctionSurvivesMissingCustomList",
        "TestPrettifyHotkey",
        "TestCustomFunctionNameChecksUnboundFunctions",
        "TestCustomFunctionNamesUsePersistedCaseInsensitiveIdentity",
        "TestStaleAddFunctionCannotClearANewerBinding",
        "TestProfileBindingOwnerUsesRuntimeIdentity",
        "TestCaptureSuppressesInputToTheForegroundWindow",
        "TestCapturedHotkeyUsesTerminationModifierSnapshot",
        "TestProfileSwitchPreparationStopsActiveCapture",
        "TestProfileSwitchAbortsWhenCaptureCannotStop",
        "TestCaptureStartFailureWarnsWhenRuntimeCannotBeRestored",
        "TestActiveCaptureBlocksSaveAndFunctionRemoval",
        "TestStaleRealCaptureRestoresCurrentProfileNotSnapshot",
        "TestCapturedBindPublishesDirtyStateBeforeReleasingOwner",
        "TestCancelCaptureWarnsWhenPriorRuntimeCannotBeRestored",
        "TestModifierRestartFailureWarnsWhenPriorRuntimeCannotBeRestored",
        "TestCaptureFailureRestoresBindingAndHookState",
        "TestStaleKeyCaptureCannotReinsertRemovedFunction",
        "TestRejectedCapturedKeyRestoresPriorBinding",
        "TestRejectedScopeChangeRestoresPriorScope",
        "TestStaleScopeDialogCannotModifyAReplacementRow",
        "TestFailedModalitySavePreservesLiveProfile",
        "TestStaleModalityDialogCannotWriteAnotherProfile",
        "TestOlderModalityDialogCannotOverwriteNewerSave",
        "TestDirtyKeybindMutationInvalidatesModalityDialog",
        "TestPreexistingDirtyProfileBlocksModalityDialog",
        "TestPreexistingDirtyProfileBlocksCustomDeletion",
        "TestDiscardBeforeAddFunctionRequiresFreshMainWindowControl",
        "TestStaleRenameDialogCannotRenameAnotherProfile",
        "TestDestroyedRenameDialogCannotMutateProfile",
        "TestRenameDialogCannotMutateSameNameReplacement",
        "TestRenamePromptHonorsDirtyCancel",
        "TestCaseOnlyRenamePersistsResolvedDirtyChanges",
        "TestDiscardBeforeRenameRestoresRuntimeAndMainView",
        "TestDiscardBeforeCaseRenameKeepsStoredRuntime",
        "TestSuccessfulMainRenameDoesNotReapplyHotkeys",
        "TestDefaultProfileSelectionRequiresExactRenderedName",
        "TestCreateProfileSurfacesStorageRecovery",
        "TestDirtyScopeEditBlocksProfileSwitchWhenCancelled",
        "TestClosingSavesDirtyProfileBeforeExit",
        "TestProfileSwitchCanDiscardDirtyChanges",
        "TestFailedCustomDeletePreservesLiveProfile",
        "TestRemoveFunctionKeepsProfileAndRowWhenNativeOffFails",
        "TestCustomDeleteRollsBackWhenLaterRegistrationFails",
        "TestStaleRemoveConfirmationCannotDeleteReplacementRow",
        "TestStaleCustomDeleteCannotDeleteRecreatedCommand",
        "TestRowDeleteAndRuntimeRestoreFailureRequiresRestartWarning",
        "TestRejectedKeybindWarnsWhenPriorRuntimeCannotBeRestored",
        "TestRejectedScopeWarnsWhenPriorRuntimeCannotBeRestored",
        "TestSavedProfileFailsWhenRuntimeCannotBeVerified",
        "TestStaleProfileDeleteCannotDeleteRecreatedProfile"
    ]

    Setup() {
        ; Build an instance without running the constructor, which would check GitHub
        ; for updates and load profiles
        this.gui := {base: KeybindGUI.Prototype, gui: ""}
        this.originalCaptureRuntimeProfile := KeybindGUI.captureRuntimeProfile
        this.originalCaptureTransactionActive := KeybindGUI.captureTransactionActive
        this.originalCaptureOwnerGui := KeybindGUI.captureOwnerGui
        this.originalProfileMutationRevisions := KeybindGUI.profileMutationRevisions
        KeybindGUI.captureRuntimeProfile := 0
        KeybindGUI.captureTransactionActive := false
        KeybindGUI.captureOwnerGui := 0
        KeybindGUI.profileMutationRevisions := Map()
    }

    Teardown() {
        KeybindGUI.captureRuntimeProfile := this.originalCaptureRuntimeProfile
        KeybindGUI.captureTransactionActive := this.originalCaptureTransactionActive
        KeybindGUI.captureOwnerGui := this.originalCaptureOwnerGui
        KeybindGUI.profileMutationRevisions := this.originalProfileMutationRevisions
    }

    TestSelectedFunctionPrefersBuiltIn() {
        Assert.Equal("Sign Report",
            this.gui.SelectedFunction({Text: "Sign Report"}, {Text: "Custom: Yell"}))
        Assert.Equal("Custom: Yell",
            this.gui.SelectedFunction({Text: ""}, {Text: "Custom: Yell"}))
        Assert.Equal("", this.gui.SelectedFunction({Text: ""}, {Text: ""}))
    }

    ; The custom-function list is only created when the profile has custom functions.
    ; Reading it unconditionally raised an unset-variable error inside the GUI
    ; callback whenever a profile had none and nothing was selected.
    TestSelectedFunctionSurvivesMissingCustomList() {
        Assert.Equal("Sign Report", this.gui.SelectedFunction({Text: "Sign Report"}, ""))
        Assert.Equal("", this.gui.SelectedFunction({Text: ""}, ""))
    }

    TestPrettifyHotkey() {
        Assert.Equal("Unassigned", this.gui.PrettifyHotkey(""))
        Assert.Equal("Ctrl + S", this.gui.PrettifyHotkey("^s"))
        Assert.Equal("Ctrl + Alt + D", this.gui.PrettifyHotkey("^!d"))
        Assert.Equal("Ctrl + Shift + V", this.gui.PrettifyHotkey("^+v"))
        Assert.Equal("Win + E", this.gui.PrettifyHotkey("#e"))
    }

    TestCustomFunctionNameChecksUnboundFunctions() {
        profile := ProfileManager.NewProfile()
        profile.customFuncs["Custom: Existing"] := {keys: "HELLO", window: ""}

        Assert.False(this.gui.CustomFunctionNameAvailable(profile, "Custom: Existing"))
        Assert.True(this.gui.CustomFunctionNameAvailable(profile, "Custom: New"))
    }

    TestCustomFunctionNamesUsePersistedCaseInsensitiveIdentity() {
        profile := ProfileManager.NewProfile()
        profile.customFuncs["Custom: Existing"] := {keys: "HELLO", window: ""}

        Assert.False(this.gui.CustomFunctionNameAvailable(profile, "Custom: existing"))
    }

    TestStaleAddFunctionCannotClearANewerBinding() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "PACS"
        dialog := FakeProfileDialog("Test")

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            result := this.gui.AddFunction("Sign Report", RejectingAddListView(), dialog)
            capturedBind := profile.binds["Sign Report"]
            capturedScope := profile.scopes["Sign Report"]
            capturedDestroyed := dialog.destroyed
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.Equal("^s", capturedBind)
        Assert.Equal("PACS", capturedScope)
        Assert.True(capturedDestroyed)
    }

    TestProfileBindingOwnerUsesRuntimeIdentity() {
        profile := ProfileManager.NewProfile()
        profile.binds["Existing"] := "^!s"
        profile.binds["Editing"] := "^e"

        Assert.Equal(
            "Existing",
            this.gui.FindProfileBindingOwner(profile, "!^S", "Editing")
        )
        Assert.Equal("", this.gui.FindProfileBindingOwner(profile, "^e", "Editing"))
    }

    TestCaptureSuppressesInputToTheForegroundWindow() {
        Assert.False(InStr(KeybindGUI.inputHookOptions, "V") > 0)
    }

    TestCapturedHotkeyUsesTerminationModifierSnapshot() {
        hook := FakeCaptureHook("S", "<^>!")

        Assert.Equal("^!S", this.gui.CapturedHotkey(hook))
    }

    TestProfileSwitchPreparationStopsActiveCapture() {
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        hook := FakeCaptureHook("F13")
        KeybindGUI.isListening := true
        KeybindGUI.listeningControl := {}
        KeybindGUI.activeInputHook := hook

        try {
            this.gui.PrepareForProfileSwitch()
            capturedListening := KeybindGUI.isListening
            capturedHook := KeybindGUI.activeInputHook
            capturedStopped := hook.stopped
        } finally {
            this.gui.StopListening()
            KeybindGUI.isListening := originalListening
            KeybindGUI.listeningControl := originalControl
            KeybindGUI.activeInputHook := originalHook
        }

        Assert.False(capturedListening)
        Assert.Equal(0, capturedHook)
        Assert.True(capturedStopped)
    }

    TestProfileSwitchAbortsWhenCaptureCannotStop() {
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        hook := FailingCaptureHook("F13")
        control := {}
        KeybindGUI.isListening := true
        KeybindGUI.listeningControl := control
        KeybindGUI.activeInputHook := hook

        threw := false
        try this.gui.PrepareForProfileSwitch()
        catch
            threw := true

        capturedListening := KeybindGUI.isListening
        capturedControl := KeybindGUI.listeningControl
        capturedHook := KeybindGUI.activeInputHook

        KeybindGUI.activeInputHook := 0
        KeybindGUI.isListening := false
        KeybindGUI.listeningControl := ""
        try HotkeyManager.DisableAllHotkeys()
        KeybindGUI.isListening := originalListening
        KeybindGUI.listeningControl := originalControl
        KeybindGUI.activeInputHook := originalHook

        Assert.True(threw)
        Assert.True(capturedListening)
        Assert.True(capturedControl == control)
        Assert.True(capturedHook == hook)
    }

    TestCaptureStartFailureWarnsWhenRuntimeCannotBeRestored() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalFunctions := HotkeyManager.hotkeyFunctions
        originalActive := HotkeyManager.activeHotkeys
        originalAdditional := HotkeyManager.additionalActiveHotkeys
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        profile := ProfileManager.NewProfile()
        notifications := CapturingNotificationDriver()
        gui := {
            base: CaptureStartRestoreFailingKeybindGUI.Prototype,
            restoreCalls: 0,
            notificationDriver: notifications
        }
        threw := false
        caughtMessage := ""

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.hotkeyFunctions := Map()
            HotkeyManager.activeHotkeys := Map()
            HotkeyManager.additionalActiveHotkeys := Map()
            KeybindGUI.isListening := false
            KeybindGUI.listeningControl := ""
            KeybindGUI.activeInputHook := 0

            try gui.BeginListening("Sign Report", {}, {})
            catch as err {
                threw := true
                caughtMessage := err.Message
            }
            capturedListening := KeybindGUI.isListening
            capturedHook := KeybindGUI.activeInputHook
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            HotkeyManager.hotkeyFunctions := originalFunctions
            HotkeyManager.activeHotkeys := originalActive
            HotkeyManager.additionalActiveHotkeys := originalAdditional
            KeybindGUI.isListening := originalListening
            KeybindGUI.listeningControl := originalControl
            KeybindGUI.activeInputHook := originalHook
        }

        Assert.True(threw)
        Assert.True(InStr(caughtMessage, "simulated hook start failure") > 0)
        Assert.False(capturedListening)
        Assert.Equal(0, capturedHook)
        Assert.Equal(1, gui.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated capture restore failure") > 0)
    }

    TestActiveCaptureBlocksSaveAndFunctionRemoval() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        originalActive := HotkeyManager.activeHotkeys
        tempRoot := A_Temp "\pacs_capture_mutation_gate_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        profile.binds["Custom: Keep"] := ""
        profile.scopes["Custom: Keep"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        customDialog := FakeProfileDialog("Test")
        gui := {base: CaptureMutationGuardGUI.Prototype}
        gui.confirmationDriver := AlwaysConfirmDriver()
        gui.notifications := []

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            Assert.True(gui.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(gui.BeginListening("Sign Report", listView, prompt))

            profile.binds["Sign Report"] := "^F14"
            saveResult := gui.SaveCurrentProfile()
            removeResult := gui.RemoveFunction(listView)
            scopeResult := gui.ApplyScope(
                "Sign Report",
                true,
                false,
                listView,
                1,
                prompt
            )
            renameResult := gui.PromptRenameProfile("Test")
            customDeleteResult := gui.DeleteCustomFunction(
                "Custom: Keep",
                customDialog
            )
            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
            storedBind := stored.binds["Sign Report"]
            stillBound := profile.binds.Has("Sign Report")
            customStillExists := profile.customFuncs.Has("Custom: Keep")
            rowCount := listView.GetCount()
        } finally {
            try gui.CancelKeybindPrompt(prompt)
            KeybindGUI.captureRuntimeProfile := 0
            KeybindGUI.isListening := false
            KeybindGUI.activeInputHook := 0
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            HotkeyManager.activeHotkeys := originalActive
            try DirDelete(tempRoot, true)
        }

        Assert.False(saveResult)
        Assert.False(removeResult)
        Assert.False(scopeResult)
        Assert.False(renameResult)
        Assert.False(customDeleteResult)
        Assert.Equal("^F13", storedBind)
        Assert.True(stillBound)
        Assert.True(customStillExists)
        Assert.Equal("Any", profile.scopes["Sign Report"])
        Assert.Equal(1, rowCount)
    }

    TestStaleRealCaptureRestoresCurrentProfileNotSnapshot() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalActive := HotkeyManager.activeHotkeys
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        gui := {base: CaptureMutationGuardGUI.Prototype}
        gui.notifications := []

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.activeHotkeys := Map()
            Assert.True(gui.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(gui.BeginListening("Sign Report", listView, prompt))
            hook := KeybindGUI.activeInputHook

            ; Simulate a later committed mutation despite the UI gate. Stale capture
            ; recovery must honor this current profile, not resurrect its snapshot.
            profile.binds.Delete("Sign Report")
            profile.scopes.Delete("Sign Report")
            listView.Delete(1)
            result := gui.OnInputEnd("Sign Report", listView, prompt, hook)

            runtimeAbsent := !HotkeyManager.activeHotkeys.Has("Sign Report")
            profileAbsent := !profile.binds.Has("Sign Report")
        } finally {
            try gui.StopListening()
            KeybindGUI.captureRuntimeProfile := 0
            KeybindGUI.isListening := false
            KeybindGUI.activeInputHook := 0
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            HotkeyManager.activeHotkeys := originalActive
        }

        Assert.False(result)
        Assert.True(profileAbsent)
        Assert.True(runtimeAbsent)
        Assert.True(prompt.destroyed)
    }

    TestCapturedBindPublishesDirtyStateBeforeReleasingOwner() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalActive := HotkeyManager.activeHotkeys
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        gui := {base: CapturePublicationOrderGUI.Prototype, events: []}

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.activeHotkeys := Map()
            Assert.True(gui.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(gui.BeginListening("Sign Report", listView, prompt))
            result := gui.OnInputEnd(
                "Sign Report",
                listView,
                prompt,
                KeybindGUI.activeInputHook
            )
        } finally {
            try gui.StopListening()
            KeybindGUI.captureRuntimeProfile := 0
            KeybindGUI.isListening := false
            KeybindGUI.activeInputHook := 0
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            HotkeyManager.activeHotkeys := originalActive
        }

        Assert.True(result)
        Assert.Equal(2, gui.events.Length)
        Assert.Equal("dirty", gui.events[1])
        Assert.Equal("release", gui.events[2])
    }

    TestCancelCaptureWarnsWhenPriorRuntimeCannotBeRestored() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalFunctions := HotkeyManager.hotkeyFunctions
        originalActive := HotkeyManager.activeHotkeys
        originalAdditional := HotkeyManager.additionalActiveHotkeys
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        profile := ProfileManager.NewProfile()
        prompt := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        gui := {
            base: CaptureCancelRestoreFailingKeybindGUI.Prototype,
            restoreCalls: 0,
            notificationDriver: notifications
        }

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.hotkeyFunctions := Map()
            HotkeyManager.activeHotkeys := Map()
            HotkeyManager.additionalActiveHotkeys := Map()
            KeybindGUI.isListening := false
            KeybindGUI.listeningControl := ""
            KeybindGUI.activeInputHook := 0

            Assert.True(gui.BeginListening("Sign Report", {}, prompt))
            result := gui.CancelKeybindPrompt(prompt)
            capturedListening := KeybindGUI.isListening
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            HotkeyManager.hotkeyFunctions := originalFunctions
            HotkeyManager.activeHotkeys := originalActive
            HotkeyManager.additionalActiveHotkeys := originalAdditional
            KeybindGUI.isListening := originalListening
            KeybindGUI.listeningControl := originalControl
            KeybindGUI.activeInputHook := originalHook
        }

        Assert.False(result)
        Assert.False(capturedListening)
        Assert.True(prompt.destroyed)
        Assert.Equal(1, gui.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated cancel restore failure") > 0)
    }

    TestModifierRestartFailureWarnsWhenPriorRuntimeCannotBeRestored() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalFunctions := HotkeyManager.hotkeyFunctions
        originalActive := HotkeyManager.activeHotkeys
        originalAdditional := HotkeyManager.additionalActiveHotkeys
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        prompt := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        gui := {
            base: ModifierRestartRestoreFailingKeybindGUI.Prototype,
            startCalls: 0,
            restoreCalls: 0,
            notificationDriver: notifications
        }
        threw := false

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.hotkeyFunctions := Map()
            HotkeyManager.activeHotkeys := Map()
            HotkeyManager.additionalActiveHotkeys := Map()
            KeybindGUI.isListening := false
            KeybindGUI.listeningControl := ""
            KeybindGUI.activeInputHook := 0
            Assert.True(gui.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(gui.BeginListening("Sign Report", listView, prompt))

            try gui.OnInputEnd(
                "Sign Report",
                listView,
                prompt,
                FakeCaptureHook("LShift")
            )
            catch
                threw := true
            capturedListening := KeybindGUI.isListening
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            HotkeyManager.hotkeyFunctions := originalFunctions
            HotkeyManager.activeHotkeys := originalActive
            HotkeyManager.additionalActiveHotkeys := originalAdditional
            KeybindGUI.isListening := originalListening
            KeybindGUI.listeningControl := originalControl
            KeybindGUI.activeInputHook := originalHook
        }

        Assert.True(threw)
        Assert.False(capturedListening)
        Assert.True(prompt.destroyed)
        Assert.Equal(2, gui.startCalls)
        Assert.Equal(1, gui.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated modifier restore failure") > 0)
    }

    TestCaptureFailureRestoresBindingAndHookState() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalFunctions := HotkeyManager.hotkeyFunctions
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook

        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "Any"
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        hook := FakeCaptureHook("F13")
        prompt := FakeProfileDialog()
        KeybindGUI.isListening := true
        KeybindGUI.listeningControl := FailingListView()
        KeybindGUI.activeInputHook := hook
        Assert.True(this.gui.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            KeybindGUI.listeningControl,
            1
        ))

        threw := false
        try this.gui.OnInputEnd("Sign Report", KeybindGUI.listeningControl, prompt, hook)
        catch {
            threw := true
        }

        capturedBind := profile.binds["Sign Report"]
        capturedListening := KeybindGUI.isListening
        capturedActiveHook := KeybindGUI.activeInputHook
        capturedStopped := hook.stopped
        capturedDestroyed := prompt.destroyed

        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.hotkeyFunctions := originalFunctions
        this.gui.StopListening()
        KeybindGUI.isListening := originalListening
        KeybindGUI.listeningControl := originalControl
        KeybindGUI.activeInputHook := originalHook
        ProfileManager.profiles := originalProfiles
        ProfileManager.currentProfile := originalCurrent

        Assert.True(threw)
        Assert.Equal("^s", capturedBind)
        Assert.False(capturedListening)
        Assert.Equal(0, capturedActiveHook)
        Assert.True(capturedStopped)
        Assert.True(capturedDestroyed)
    }

    TestStaleKeyCaptureCannotReinsertRemovedFunction() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        hook := FakeCaptureHook("F14")

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            Assert.True(this.gui.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            KeybindGUI.isListening := true
            KeybindGUI.listeningControl := listView
            KeybindGUI.activeInputHook := hook
            profile.binds.Delete("Sign Report")
            profile.scopes.Delete("Sign Report")
            listView.rows.RemoveAt(1)

            result := this.gui.OnInputEnd("Sign Report", listView, prompt, hook)
            bindStillAbsent := !profile.binds.Has("Sign Report")
            scopeStillAbsent := !profile.scopes.Has("Sign Report")
            runtimeAbsent := !HotkeyManager.activeHotkeys.Has("Sign Report")
            rowCount := listView.GetCount()
            destroyed := prompt.destroyed
        } finally {
            KeybindGUI.activeInputHook := 0
            KeybindGUI.isListening := false
            KeybindGUI.listeningControl := ""
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            KeybindGUI.isListening := originalListening
            KeybindGUI.listeningControl := originalControl
            KeybindGUI.activeInputHook := originalHook
        }

        Assert.False(result)
        Assert.True(bindStillAbsent)
        Assert.True(scopeStillAbsent)
        Assert.True(runtimeAbsent)
        Assert.Equal(0, rowCount)
        Assert.True(destroyed)
    }

    TestRejectedCapturedKeyRestoresPriorBinding() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalFunctions := HotkeyManager.hotkeyFunctions
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        hook := FakeCaptureHook("DefinitelyNotARealKeyName")
        prompt := FakeProfileDialog()

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
            Assert.True(this.gui.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(HotkeyManager.RegisterHotkey("Sign Report", "^F13"))
            KeybindGUI.isListening := true
            KeybindGUI.listeningControl := listView
            KeybindGUI.activeInputHook := hook

            this.gui.OnInputEnd("Sign Report", listView, prompt, hook)
            capturedBind := profile.binds["Sign Report"]
            capturedRuntimeBind := HotkeyManager.activeHotkeys.Has("Sign Report")
                ? HotkeyManager.activeHotkeys["Sign Report"].hotkey
                : ""
            capturedListBind := listView.GetText(1, 2)
            capturedDestroyed := prompt.destroyed
            capturedStopped := hook.stopped
        } finally {
            HotkeyManager.DisableAllHotkeys()
            HotkeyManager.hotkeyFunctions := originalFunctions
            this.gui.StopListening()
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.Equal("^F13", capturedBind)
        Assert.Equal("^F13", capturedRuntimeBind)
        Assert.Equal("Ctrl + F13", capturedListBind)
        Assert.True(capturedDestroyed)
        Assert.True(capturedStopped)
    }

    TestRejectedScopeChangeRestoresPriorScope() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalFunctions := HotkeyManager.hotkeyFunctions
        profile := ProfileManager.NewProfile()
        profile.binds["Missing Action"] := "^F14"
        profile.scopes["Missing Action"] := "Any"
        listView := FunctionalListView("Missing Action", "Ctrl + F14", "Any window")
        dialog := FakeProfileDialog()

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.hotkeyFunctions := Map()
            Assert.True(this.gui.CaptureFunctionDialogState(
                dialog,
                "Missing Action",
                listView,
                1
            ))

            this.gui.ApplyScope("Missing Action", true, false, listView, 1, dialog)
            capturedScope := profile.scopes["Missing Action"]
            capturedListScope := listView.GetText(1, 3)
            capturedDestroyed := dialog.destroyed
        } finally {
            HotkeyManager.DisableAllHotkeys()
            HotkeyManager.hotkeyFunctions := originalFunctions
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.Equal("Any", capturedScope)
        Assert.Equal("Any window", capturedListScope)
        Assert.False(capturedDestroyed)
    }

    TestStaleScopeDialogCannotModifyAReplacementRow() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.binds["Draft Report"] := "^F14"
        profile.scopes["Draft Report"] := "PowerScribe"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        listView.rows.Push(["Draft Report", "Ctrl + F14", "PowerScribe"])
        dialog := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        gui := {base: StaleScopeTrackingKeybindGUI.Prototype}
        gui.restoreCalls := 0
        gui.notificationDriver := notifications

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            Assert.True(gui.CaptureFunctionDialogState(
                dialog,
                "Sign Report",
                listView,
                1
            ))
            profile.binds.Delete("Sign Report")
            profile.scopes.Delete("Sign Report")
            listView.rows.RemoveAt(1)

            result := gui.ApplyScope(
                "Sign Report",
                true,
                false,
                listView,
                1,
                dialog
            )
            orphanScopeAbsent := !profile.scopes.Has("Sign Report")
            remainingName := listView.GetText(1, 1)
            remainingScope := listView.GetText(1, 3)
            destroyed := dialog.destroyed
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.True(orphanScopeAbsent)
        Assert.Equal("Draft Report", remainingName)
        Assert.Equal("PowerScribe", remainingScope)
        Assert.True(destroyed)
        Assert.Equal(0, gui.restoreCalls)
    }

    TestFailedModalitySavePreservesLiveProfile() {
        state := this.PrepareBlockedProfileSave()
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Neuro"] := "Old Attending"
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        dialog := FakeProfileDialog()

        try {
            this.gui.SaveModalityAttendings(
                Map("Neuro", {Value: "New Attending"}),
                dialog
            )
            savedValue := ProfileManager.profiles["Test"].modalityAttendings["Neuro"]
            destroyed := dialog.destroyed
        } finally {
            this.RestoreBlockedProfileSave(state)
        }

        Assert.Equal("Old Attending", savedValue)
        Assert.False(destroyed)
    }

    TestStaleModalityDialogCannotWriteAnotherProfile() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        tempRoot := A_Temp "\pacs_stale_dialog_" A_TickCount
        profileA := ProfileManager.NewProfile()
        profileA.modalityAttendings["Neuro"] := "A Attending"
        profileB := ProfileManager.NewProfile()
        profileB.modalityAttendings["Neuro"] := "B Attending"
        dialog := FakeProfileDialog("A")

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profiles := Map("A", profileA, "B", profileB)
            ProfileManager.currentProfile := "B"
            this.gui.SaveModalityAttendings(
                Map("Neuro", {Value: "Stale Attending"}),
                dialog
            )
            capturedA := ProfileManager.profiles["A"].modalityAttendings["Neuro"]
            capturedB := ProfileManager.profiles["B"].modalityAttendings["Neuro"]
            capturedDestroyed := dialog.destroyed
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            try DirDelete(tempRoot, true)
        }

        Assert.Equal("A Attending", capturedA)
        Assert.Equal("B Attending", capturedB)
        Assert.True(capturedDestroyed)
    }

    TestOlderModalityDialogCannotOverwriteNewerSave() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalRevisions := ProfileManager.profileRevisions
        originalProfilesPath := ProfileManager.profilesPath
        tempRoot := A_Temp "\pacs_same_profile_stale_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Neuro"] := "Old Attending"

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.profileRevisions := Map()
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            revision := ProfileManager.GetProfileRevision("Test")
            staleDialog := FakeProfileDialog("Test", revision)
            newerDialog := FakeProfileDialog("Test", revision)

            this.gui.SaveModalityAttendings(
                Map("Neuro", {Value: "New Attending"}),
                newerDialog
            )
            this.gui.SaveModalityAttendings(
                Map("Neuro", {Value: "Stale Attending"}),
                staleDialog
            )

            captured := ProfileManager.profiles["Test"].modalityAttendings["Neuro"]
            capturedDestroyed := staleDialog.destroyed
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profileRevisions := originalRevisions
            ProfileManager.profilesPath := originalProfilesPath
            try DirDelete(tempRoot, true)
        }

        Assert.Equal("New Attending", captured)
        Assert.True(capturedDestroyed)
    }

    TestDirtyKeybindMutationInvalidatesModalityDialog() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalRevisions := ProfileManager.profileRevisions
        originalProfilesPath := ProfileManager.profilesPath
        tempRoot := A_Temp "\pacs_dirty_modality_dialog_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.modalityAttendings["Neuro"] := "Old Attending"

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.profileRevisions := Map()
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            dialog := FakeProfileDialog("Test")

            profile.scopes["Sign Report"] := "PACS"
            this.gui.MarkProfileDirty("Test")
            result := this.gui.SaveModalityAttendings(
                Map("Neuro", {Value: "New Attending"}),
                dialog
            )

            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
            storedScope := stored.scopes["Sign Report"]
            storedAttending := stored.modalityAttendings["Neuro"]
            memoryScope := profile.scopes["Sign Report"]
            memoryAttending := profile.modalityAttendings["Neuro"]
            dirty := this.gui.IsProfileDirty("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profileRevisions := originalRevisions
            ProfileManager.profilesPath := originalProfilesPath
            try DirDelete(tempRoot, true)
        }

        Assert.False(result)
        Assert.Equal("Any", storedScope)
        Assert.Equal("Old Attending", storedAttending)
        Assert.Equal("PACS", memoryScope)
        Assert.Equal("Old Attending", memoryAttending)
        Assert.True(dirty)
        Assert.True(dialog.destroyed)
    }

    TestPreexistingDirtyProfileBlocksModalityDialog() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        gui := {
            base: DirtyPersistentOperationGUI.Prototype,
            dialogCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Cancel")
        }

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            gui.MarkProfileDirty("Test")
            result := gui.ShowModalityAttendingsDialog()
            dirty := gui.IsProfileDirty("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.True(dirty)
        Assert.Equal(0, gui.dialogCalls)
    }

    TestPreexistingDirtyProfileBlocksCustomDeletion() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_dirty_custom_delete_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        profile.binds["Custom: Keep"] := ""
        profile.scopes["Custom: Keep"] := "Any"
        selector := FakeProfileDialog("Test")
        gui := {base: DirtyPersistentOperationGUI.Prototype, dialogCalls: 0}
        gui.confirmationDriver := AlwaysConfirmDriver()

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)

            profile.scopes["Sign Report"] := "PACS"
            gui.MarkProfileDirty("Test")
            result := gui.DeleteCustomFunction("Custom: Keep", selector)
            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
            storedScope := stored.scopes["Sign Report"]
            storedCustom := stored.customFuncs.Has("Custom: Keep")
            memoryScope := profile.scopes["Sign Report"]
            memoryCustom := profile.customFuncs.Has("Custom: Keep")
            dirty := gui.IsProfileDirty("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.False(result)
        Assert.Equal("Any", storedScope)
        Assert.True(storedCustom)
        Assert.Equal("PACS", memoryScope)
        Assert.True(memoryCustom)
        Assert.True(dirty)
        Assert.True(selector.destroyed)
    }

    TestDiscardBeforeAddFunctionRequiresFreshMainWindowControl() {
        gui := {
            base: DirtyAddFunctionTestGUI.Prototype,
            dirty: true,
            resolveCalls: 0,
            dialogCalls: 0,
            notices: 0
        }

        result := gui.ShowAddFunctionDialog({destroyed: true})

        Assert.False(result)
        Assert.Equal(1, gui.resolveCalls)
        Assert.Equal(0, gui.dialogCalls)
        Assert.Equal(1, gui.notices)
    }

    TestStaleRenameDialogCannotRenameAnotherProfile() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalDefault := ProfileManager.defaultProfile
        originalProfilesPath := ProfileManager.profilesPath
        tempRoot := A_Temp "\pacs_stale_rename_" A_TickCount
        profileA := ProfileManager.NewProfile()
        profileB := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("A")

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.defaultProfile := ""
            ProfileManager.profiles := Map("A", profileA, "B", profileB)
            ProfileManager.currentProfile := "B"
            ProfileManager.SaveProfile("A", profileA)
            try this.gui.RenameProfile("A", "Renamed", dialog)

            keptA := ProfileManager.profiles.Has("A")
            keptB := ProfileManager.profiles.Has("B")
            createdRename := ProfileManager.profiles.Has("Renamed")
            capturedDestroyed := dialog.destroyed
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.defaultProfile := originalDefault
            ProfileManager.profilesPath := originalProfilesPath
            try DirDelete(tempRoot, true)
        }

        Assert.True(keptA)
        Assert.True(keptB)
        Assert.False(createdRename)
        Assert.True(capturedDestroyed)
    }

    TestDestroyedRenameDialogCannotMutateProfile() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("Old")
        gui := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        gui.createCalls := 0
        gui.applyCalls := 0

        try {
            ProfileManager.profiles := Map("Old", profile)
            ProfileManager.currentProfile := "Old"
            Assert.True(gui.CaptureRenameDialogState(dialog, "Old"))
            dialog.Destroy()
            result := gui.RenameProfile("Old", "New", dialog)
            keptOld := ProfileManager.profiles.Has("Old")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.True(keptOld)
        Assert.Equal(0, gui.createCalls)
    }

    TestRenameDialogCannotMutateSameNameReplacement() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalRevisions := ProfileManager.profileRevisions
        originalProfile := ProfileManager.NewProfile()
        replacement := ProfileManager.NewProfile()
        replacement.modalityAttendings["Marker"] := "replacement"
        dialog := FakeProfileDialog("Old")
        gui := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        gui.createCalls := 0
        gui.applyCalls := 0

        try {
            ProfileManager.profileRevisions := Map("Old", 1)
            ProfileManager.profiles := Map("Old", originalProfile)
            ProfileManager.currentProfile := "Old"
            Assert.True(gui.CaptureRenameDialogState(dialog, "Old"))
            ProfileManager.profiles["Old"] := replacement
            ProfileManager.profileRevisions["Old"] := 2
            result := gui.RenameProfile("Old", "New", dialog)
            keptReplacement := ProfileManager.profiles.Has("Old")
                && ProfileManager.profiles["Old"] = replacement
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profileRevisions := originalRevisions
        }

        Assert.False(result)
        Assert.True(keptReplacement)
        Assert.Equal(0, gui.createCalls)
    }

    TestRenamePromptHonorsDirtyCancel() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        gui := {
            base: DirtyRenameTestGUI.Prototype,
            dialogCreateCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Cancel")
        }

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            gui.MarkProfileDirty("Test")
            result := gui.PromptRenameProfile("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.True(gui.IsProfileDirty("Test"))
        Assert.Equal(0, gui.dialogCreateCalls)
    }

    TestCaseOnlyRenamePersistsResolvedDirtyChanges() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_dirty_case_rename_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        dialog := FakeProfileDialog("Night")
        gui := {
            base: DirtyRenameTestGUI.Prototype,
            createCalls: 0,
            applyCalls: 0,
            dialogCreateCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Yes")
        }
        gui.gui := FakeProfileDialog()

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.profiles := Map("Night", profile)
            ProfileManager.currentProfile := "Night"
            ProfileManager.SaveProfile("Night", profile)
            profile.scopes["Sign Report"] := "PACS"
            gui.MarkProfileDirty("Night")

            Assert.True(gui.ResolveDirtyProfileBeforeLeaving())
            Assert.True(gui.CaptureRenameDialogState(dialog, "Night"))
            Assert.True(gui.RenameProfile("Night", "night", dialog))
            reloaded := ProfileManager.LoadProfile(ProfileManager.ProfilePath("night"))
            persistedScope := reloaded.scopes["Sign Report"]
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.Equal("PACS", persistedScope)
        Assert.False(gui.IsProfileDirty("Night"))
        Assert.False(gui.IsProfileDirty("night"))
    }

    TestDiscardBeforeRenameRestoresRuntimeAndMainView() {
        state := this.PrepareDiscardRenameState("pacs_discard_rename_cancel_")
        gui := state.gui

        try {
            resolved := gui.ResolveDirtyProfileBeforeLeaving(true)
            memoryBind := ProfileManager.profiles["Night"].binds["Sign Report"]
            memoryScope := ProfileManager.profiles["Night"].scopes["Sign Report"]
            runtimeBind := HotkeyManager.activeHotkeys["Sign Report"].hotkey
            runtimeScope := HotkeyManager.activeHotkeys["Sign Report"].scope
        } finally {
            this.RestoreDiscardRenameState(state)
        }

        Assert.True(resolved)
        Assert.Equal("^F13", memoryBind)
        Assert.Equal("Any", memoryScope)
        Assert.Equal("^F13", runtimeBind)
        Assert.Equal("Any", runtimeScope)
        Assert.Equal("^F13", gui.visibleBind)
        Assert.Equal("Any", gui.visibleScope)
        Assert.Equal(1, gui.createCalls)
        Assert.False(gui.lastCreateAppliedBinds)
        Assert.False(gui.IsProfileDirty("Night"))
    }

    TestDiscardBeforeCaseRenameKeepsStoredRuntime() {
        state := this.PrepareDiscardRenameState("pacs_discard_case_rename_")
        gui := state.gui
        dialog := FakeProfileDialog("Night")

        try {
            Assert.True(gui.ResolveDirtyProfileBeforeLeaving(true))
            Assert.True(gui.CaptureRenameDialogState(dialog, "Night"))
            renamed := gui.RenameProfile("Night", "night", dialog)
            reloaded := ProfileManager.LoadProfile(ProfileManager.ProfilePath("night"))
            persistedBind := reloaded.binds["Sign Report"]
            persistedScope := reloaded.scopes["Sign Report"]
            runtimeBind := HotkeyManager.activeHotkeys["Sign Report"].hotkey
            runtimeScope := HotkeyManager.activeHotkeys["Sign Report"].scope
        } finally {
            this.RestoreDiscardRenameState(state)
        }

        Assert.True(renamed)
        Assert.Equal("^F13", persistedBind)
        Assert.Equal("Any", persistedScope)
        Assert.Equal("^F13", runtimeBind)
        Assert.Equal("Any", runtimeScope)
        Assert.Equal("^F13", gui.visibleBind)
        Assert.Equal("Any", gui.visibleScope)
        Assert.False(gui.IsProfileDirty("Night"))
        Assert.False(gui.IsProfileDirty("night"))
    }

    TestDefaultProfileSelectionRequiresExactRenderedName() {
        Assert.Equal(2, this.gui.DefaultProfileListIndex(["AA *", "A *"], "A"))
        Assert.Equal(1, this.gui.DefaultProfileListIndex(["A *", "AA *"], "A"))
        Assert.Equal(0, this.gui.DefaultProfileListIndex(["AA *"], "A"))
    }

    TestSuccessfulMainRenameDoesNotReapplyHotkeys() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalDefault := ProfileManager.defaultProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_rename_runtime_" A_TickCount
        profile := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("Old")
        gui := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        gui.gui := FakeProfileDialog()
        gui.createCalls := 0
        gui.applyCalls := 0

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.defaultProfile := ""
            ProfileManager.profiles := Map("Old", profile)
            ProfileManager.currentProfile := "Old"
            ProfileManager.SaveProfile("Old", profile)
            Assert.True(gui.CaptureRenameDialogState(dialog, "Old"))

            result := gui.RenameProfile("Old", "New", dialog)
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.defaultProfile := originalDefault
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.True(result)
        Assert.Equal(1, gui.createCalls)
        Assert.Equal(0, gui.applyCalls)
    }

    TestCreateProfileSurfacesStorageRecovery() {
        originalRecovery := ProfileManager.recoveryRequired
        originalLastError := ProfileManager.lastError
        notifications := CapturingNotificationDriver()
        gui := {base: KeybindGUI.Prototype, notificationDriver: notifications}
        dialog := FakeProfileDialog()

        try {
            ProfileManager.recoveryRequired := true
            ProfileManager.lastError := "simulated profile storage uncertainty"
            result := gui.CreateProfile("New Profile", dialog)
        } finally {
            ProfileManager.recoveryRequired := originalRecovery
            ProfileManager.lastError := originalLastError
        }

        Assert.False(result)
        Assert.True(InStr(notifications.message, "simulated profile storage uncertainty") > 0)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.False(dialog.destroyed)
    }

    TestDirtyScopeEditBlocksProfileSwitchWhenCancelled() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        dialog := FakeProfileDialog("Test")
        gui := {
            base: DirtyLeaveTestGUI.Prototype,
            prepareCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Cancel")
        }

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            Assert.True(gui.CaptureFunctionDialogState(dialog, "Sign Report", listView, 1))
            Assert.True(gui.ApplyScope("Sign Report", true, false, listView, 1, dialog))
            switchResult := gui.OpenProfileSelector()
            dirty := gui.IsProfileDirty("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(switchResult)
        Assert.True(dirty)
        Assert.Equal(0, gui.prepareCalls)
        Assert.Equal(0, gui.selectorCalls)
    }

    TestClosingSavesDirtyProfileBeforeExit() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_dirty_close_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        gui := {
            base: DirtyLeaveTestGUI.Prototype,
            prepareCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Yes")
        }

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            profile.scopes["Sign Report"] := "PACS"
            gui.MarkProfileDirty("Test")

            result := gui.CloseMainWindow()
            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
            persistedScope := stored.scopes["Sign Report"]
            dirty := gui.IsProfileDirty("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.True(result)
        Assert.Equal("PACS", persistedScope)
        Assert.False(dirty)
        Assert.Equal(1, gui.exitCalls)
    }

    TestProfileSwitchCanDiscardDirtyChanges() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_dirty_discard_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        gui := {
            base: DirtyLeaveTestGUI.Prototype,
            prepareCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("No")
        }

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            profile.scopes["Sign Report"] := "PACS"
            gui.MarkProfileDirty("Test")

            result := gui.OpenProfileSelector()
            restoredScope := ProfileManager.profiles["Test"].scopes["Sign Report"]
            dirty := gui.IsProfileDirty("Test")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.True(result)
        Assert.Equal("Any", restoredScope)
        Assert.False(dirty)
        Assert.Equal(1, gui.prepareCalls)
        Assert.Equal(1, gui.selectorCalls)
    }

    TestFailedCustomDeletePreservesLiveProfile() {
        state := this.PrepareBlockedProfileSave()
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Keep"] := "^k"
        profile.scopes["Custom: Keep"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        dialog := FakeProfileDialog()
        threw := false

        try {
            try this.gui.DeleteCustomFunction("Custom: Keep", dialog)
            catch {
                threw := true
            }
            stillConfigured := ProfileManager.profiles["Test"].customFuncs.Has("Custom: Keep")
            stillBound := ProfileManager.profiles["Test"].binds.Has("Custom: Keep")
            destroyed := dialog.destroyed
        } finally {
            try HotkeyManager.DisableAllHotkeys()
            this.RestoreBlockedProfileSave(state)
        }

        Assert.False(threw)
        Assert.True(stillConfigured)
        Assert.True(stillBound)
        Assert.False(destroyed)
    }

    TestRemoveFunctionKeepsProfileAndRowWhenNativeOffFails() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalDriver := HotkeyManager.hotkeyDriver
        originalFunctions := HotkeyManager.hotkeyFunctions
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F23", "Any window")
        driver := TransactionalHotkeyDriver()
        driver.failDisable["^F23"] := true
        threw := false

        try {
            HotkeyManager.activeHotkeys.Clear()
            HotkeyManager.additionalActiveHotkeys.Clear()
            HotkeyManager.hotkeyDriver := driver
            HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
            HotkeyManager.activeHotkeys["Sign Report"] := {hotkey: "^F23", scope: "Any"}
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"

            try result := this.gui.RemoveFunction(listView)
            catch {
                threw := true
                result := false
            }
            keptBind := profile.binds.Has("Sign Report") ? profile.binds["Sign Report"] : ""
            keptScope := profile.scopes.Has("Sign Report") ? profile.scopes["Sign Report"] : ""
            keptRow := listView.GetCount()
            tracked := HotkeyManager.activeHotkeys.Has("Sign Report")
        } finally {
            driver.failDisable.Clear()
            try HotkeyManager.DisableAllHotkeys()
            HotkeyManager.activeHotkeys.Clear()
            HotkeyManager.additionalActiveHotkeys.Clear()
            HotkeyManager.hotkeyDriver := originalDriver
            HotkeyManager.hotkeyFunctions := originalFunctions
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(threw)
        Assert.False(result)
        Assert.Equal("^F23", keptBind)
        Assert.Equal("Any", keptScope)
        Assert.Equal(1, keptRow)
        Assert.True(tracked)
    }

    TestCustomDeleteRollsBackWhenLaterRegistrationFails() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalDriver := HotkeyManager.hotkeyDriver
        originalFunctions := HotkeyManager.hotkeyFunctions
        tempRoot := A_Temp "\pacs_custom_runtime_rollback_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Keep"] := "^F23"
        profile.scopes["Custom: Keep"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        profile.binds["Draft Report"] := "^F24"
        profile.scopes["Draft Report"] := "Any"
        dialog := FakeProfileDialog("Test")
        driver := TransactionalHotkeyDriver()
        driver.failEnableCounts["^F24"] := 1
        threw := false

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            HotkeyManager.activeHotkeys.Clear()
            HotkeyManager.additionalActiveHotkeys.Clear()
            HotkeyManager.hotkeyDriver := driver
            HotkeyManager.hotkeyFunctions := PACSCommands.commands
            HotkeyManager.activeHotkeys["Custom: Keep"] := {hotkey: "^F23", scope: "Any"}
            HotkeyManager.activeHotkeys["Draft Report"] := {hotkey: "^F24", scope: "Any"}

            try result := this.gui.DeleteCustomFunction("Custom: Keep", dialog)
            catch {
                threw := true
                result := false
            }
            liveProfile := ProfileManager.profiles["Test"]
            storedProfile := ProfileManager.LoadProfile(tempRoot "\Test.ini")
            liveKept := liveProfile.customFuncs.Has("Custom: Keep")
                && liveProfile.binds.Has("Custom: Keep")
            storedKept := storedProfile.customFuncs.Has("Custom: Keep")
                && storedProfile.binds.Has("Custom: Keep")
            runtimeKept := HotkeyManager.activeHotkeys.Has("Custom: Keep")
            dialogKept := !dialog.destroyed
        } finally {
            driver.failEnableCounts.Clear()
            driver.failDisable.Clear()
            try HotkeyManager.DisableAllHotkeys()
            HotkeyManager.activeHotkeys.Clear()
            HotkeyManager.additionalActiveHotkeys.Clear()
            HotkeyManager.hotkeyDriver := originalDriver
            HotkeyManager.hotkeyFunctions := originalFunctions
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            try DirDelete(tempRoot, true)
        }

        Assert.False(threw)
        Assert.False(result)
        Assert.True(liveKept)
        Assert.True(storedKept)
        Assert.True(runtimeKept)
        Assert.True(dialogKept)
    }

    TestStaleRemoveConfirmationCannotDeleteReplacementRow() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        profile.binds["Draft Report"] := "^F24"
        profile.scopes["Draft Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F23", "Any window")
        gui := {base: PassiveRuntimeKeybindGUI.Prototype}
        gui.applyCalls := 0
        gui.confirmationDriver := RemoveRaceConfirmationDriver(profile, listView)

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            result := gui.RemoveFunction(listView)
            liveProfile := ProfileManager.profiles["Test"]
            keptSign := liveProfile.binds.Has("Sign Report")
                && liveProfile.binds["Sign Report"] == "^F22"
            keptDraft := liveProfile.binds.Has("Draft Report")
            rowOne := listView.GetText(1, 1)
            rowTwo := listView.GetText(2, 1)
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.True(keptSign)
        Assert.True(keptDraft)
        Assert.Equal("Draft Report", rowOne)
        Assert.Equal("Sign Report", rowTwo)
        Assert.Equal(0, gui.applyCalls)
    }

    TestStaleCustomDeleteCannotDeleteRecreatedCommand() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        tempRoot := A_Temp "\pacs_stale_custom_delete_" A_TickCount
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Keep"] := "^F23"
        profile.scopes["Custom: Keep"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "OLD", window: ""}
        dialog := FakeProfileDialog("Test")
        gui := {base: PassiveRuntimeKeybindGUI.Prototype, gui: ""}
        gui.applyCalls := 0
        gui.confirmationDriver := RecreateCustomConfirmationDriver(profile)
        threw := false

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            try result := gui.DeleteCustomFunction("Custom: Keep", dialog)
            catch {
                threw := true
                result := false
            }
            liveProfile := ProfileManager.profiles["Test"]
            keptRecreated := liveProfile.customFuncs.Has("Custom: Keep")
                && liveProfile.customFuncs["Custom: Keep"].keys == "NEW"
                && liveProfile.binds.Has("Custom: Keep")
                && liveProfile.binds["Custom: Keep"] == "^F22"
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            try DirDelete(tempRoot, true)
        }

        Assert.False(result)
        Assert.False(threw)
        Assert.True(keptRecreated)
        Assert.Equal(0, gui.applyCalls)
    }

    TestRowDeleteAndRuntimeRestoreFailureRequiresRestartWarning() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := ThrowingDeleteListView("Sign Report", "Ctrl + F23", "Any window")
        notifications := CapturingNotificationDriver()
        gui := {base: FailedRestoreKeybindGUI.Prototype}
        gui.applyCalls := 0
        gui.confirmationDriver := AlwaysConfirmDriver()
        gui.notificationDriver := notifications

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            result := gui.RemoveFunction(listView)
            keptBind := ProfileManager.profiles["Test"].binds.Has("Sign Report")
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.True(keptBind)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated restore failure") > 0)
    }

    TestRejectedKeybindWarnsWhenPriorRuntimeCannotBeRestored() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalListening := KeybindGUI.isListening
        originalControl := KeybindGUI.listeningControl
        originalHook := KeybindGUI.activeInputHook
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F23", "Any window")
        prompt := FakeProfileDialog("Test")
        hook := FakeCaptureHook("F24")
        notifications := CapturingNotificationDriver()
        gui := {base: RollbackFailingKeybindGUI.Prototype}
        gui.applyCalls := 0
        gui.restoreCalls := 0
        gui.notificationDriver := notifications

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            Assert.True(gui.CaptureFunctionDialogState(prompt, "Sign Report", listView, 1))
            KeybindGUI.isListening := true
            KeybindGUI.listeningControl := listView
            KeybindGUI.activeInputHook := hook

            result := gui.OnInputEnd("Sign Report", listView, prompt, hook)
            keptBind := profile.binds["Sign Report"]
            keptRow := listView.GetText(1, 2)
        } finally {
            KeybindGUI.activeInputHook := 0
            KeybindGUI.isListening := false
            KeybindGUI.listeningControl := ""
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            KeybindGUI.isListening := originalListening
            KeybindGUI.listeningControl := originalControl
            KeybindGUI.activeInputHook := originalHook
        }

        Assert.False(result)
        Assert.Equal("^F23", keptBind)
        Assert.Equal("Ctrl + F23", keptRow)
        Assert.Equal(1, gui.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated restore failure") > 0)
    }

    TestRejectedScopeWarnsWhenPriorRuntimeCannotBeRestored() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F23", "Any window")
        dialog := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        gui := {base: RollbackFailingKeybindGUI.Prototype}
        gui.applyCalls := 0
        gui.restoreCalls := 0
        gui.notificationDriver := notifications

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            Assert.True(gui.CaptureFunctionDialogState(dialog, "Sign Report", listView, 1))
            result := gui.ApplyScope("Sign Report", true, false, listView, 1, dialog)
            keptScope := profile.scopes["Sign Report"]
            keptRow := listView.GetText(1, 3)
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
        }

        Assert.False(result)
        Assert.Equal("Any", keptScope)
        Assert.Equal("Any window", keptRow)
        Assert.Equal(1, gui.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated restore failure") > 0)
    }

    TestSavedProfileFailsWhenRuntimeCannotBeVerified() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_saved_runtime_failure_" DllCall("GetTickCount64", "UInt64")
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        notifications := CapturingNotificationDriver()
        gui := {
            base: SaveRuntimeFailingKeybindGUI.Prototype,
            applyCalls: 0,
            restoreCalls: 0,
            notificationDriver: notifications
        }

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map("Test", 0)
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"

            result := gui.SaveCurrentProfile()
            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
            storedBind := stored.binds["Sign Report"]
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.False(result)
        Assert.Equal("^F13", storedBind)
        Assert.Equal(1, gui.applyCalls)
        Assert.Equal(1, gui.restoreCalls)
        Assert.True(InStr(notifications.message, "profile was saved") > 0)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated saved-profile restore failure") > 0)
    }

    TestStaleProfileDeleteCannotDeleteRecreatedProfile() {
        originalProfiles := ProfileManager.profiles
        originalCurrent := ProfileManager.currentProfile
        originalDefault := ProfileManager.defaultProfile
        originalProfilesPath := ProfileManager.profilesPath
        originalRevisions := ProfileManager.profileRevisions
        tempRoot := A_Temp "\pacs_stale_profile_delete_" A_TickCount
        oldProfile := ProfileManager.NewProfile()
        otherProfile := ProfileManager.NewProfile()
        selector := FakeProfileDialog()
        gui := {base: ProfileDeleteTestGUI.Prototype}

        try {
            try DirDelete(tempRoot, true)
            DirCreate(tempRoot)
            ProfileManager.profilesPath := tempRoot
            ProfileManager.profileRevisions := Map()
            ProfileManager.profiles := Map("A", oldProfile, "B", otherProfile)
            ProfileManager.currentProfile := "B"
            ProfileManager.defaultProfile := ""
            ProfileManager.SaveProfile("A", oldProfile)
            ProfileManager.SaveProfile("B", otherProfile)
            gui.confirmationDriver := RecreateProfileConfirmationDriver("A")

            result := gui.DeleteProfile("A", selector)
            keptReplacement := ProfileManager.profiles.Has("A")
                && ProfileManager.profiles["A"].modalityAttendings.Has("Marker")
                && ProfileManager.profiles["A"].modalityAttendings["Marker"] == "replacement"
            keptFile := FileExist(ProfileManager.ProfilePath("A")) != ""
        } finally {
            ProfileManager.profiles := originalProfiles
            ProfileManager.currentProfile := originalCurrent
            ProfileManager.defaultProfile := originalDefault
            ProfileManager.profilesPath := originalProfilesPath
            ProfileManager.profileRevisions := originalRevisions
            try DirDelete(tempRoot, true)
        }

        Assert.False(result)
        Assert.True(keptReplacement)
        Assert.True(keptFile)
        Assert.False(selector.destroyed)
    }

    PrepareBlockedProfileSave() {
        state := {
            profiles: ProfileManager.profiles,
            current: ProfileManager.currentProfile,
            profilesPath: ProfileManager.profilesPath,
            tempRoot: A_Temp "\pacs_gui_profile_" A_TickCount
        }
        try DirDelete(state.tempRoot, true)
        DirCreate(state.tempRoot)
        FileAppend("not a directory", state.tempRoot "\blocked")
        ProfileManager.profilesPath := state.tempRoot "\blocked"
        return state
    }

    RestoreBlockedProfileSave(state) {
        ProfileManager.profiles := state.profiles
        ProfileManager.currentProfile := state.current
        ProfileManager.profilesPath := state.profilesPath
        try DirDelete(state.tempRoot, true)
    }

    PrepareDiscardRenameState(prefix) {
        state := {
            profiles: ProfileManager.profiles,
            current: ProfileManager.currentProfile,
            profilesPath: ProfileManager.profilesPath,
            revisions: ProfileManager.profileRevisions,
            defaultProfile: ProfileManager.defaultProfile,
            activeHotkeys: HotkeyManager.activeHotkeys,
            tempRoot: A_Temp "\\" prefix A_TickCount
        }
        try DirDelete(state.tempRoot, true)
        DirCreate(state.tempRoot)
        ProfileManager.profilesPath := state.tempRoot
        ProfileManager.profileRevisions := Map()
        ProfileManager.defaultProfile := ""
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        ProfileManager.profiles := Map("Night", profile)
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)

        profile.binds["Sign Report"] := "^F14"
        profile.scopes["Sign Report"] := "PACS"
        HotkeyManager.activeHotkeys := Map(
            "Sign Report", {hotkey: "^F14", scope: "PACS"}
        )
        gui := {base: DiscardRenameTrackingGUI.Prototype}
        gui.gui := FakeProfileDialog()
        gui.createCalls := 0
        gui.lastCreateAppliedBinds := true
        gui.visibleBind := "^F14"
        gui.visibleScope := "PACS"
        gui.MarkProfileDirty("Night")
        gui.profileLeaveDriver := FixedProfileLeaveDriver("No")
        state.gui := gui
        return state
    }

    RestoreDiscardRenameState(state) {
        ProfileManager.profiles := state.profiles
        ProfileManager.currentProfile := state.current
        ProfileManager.profilesPath := state.profilesPath
        ProfileManager.profileRevisions := state.revisions
        ProfileManager.defaultProfile := state.defaultProfile
        HotkeyManager.activeHotkeys := state.activeHotkeys
        try DirDelete(state.tempRoot, true)
    }
}

class FailingListView {
    GetText(row, column) {
        return ["Sign Report", "Ctrl + S", "Any window"][column]
    }

    GetCount() {
        throw Error("simulated ListView failure")
    }
}

class RejectingAddListView {
    Add(*) {
        throw Error("a stale dialog must not append a duplicate row")
    }
}

class FunctionalListView {
    __New(functionName, binding, scope) {
        this.rows := [[functionName, binding, scope]]
    }

    GetCount() {
        return this.rows.Length
    }

    GetText(row, column) {
        return this.rows[row][column]
    }

    Modify(row, options := "", values*) {
        for column, value in values
            this.rows[row][column] := value
    }

    ModifyCol(*) {
    }
}

class RemovableListView extends FunctionalListView {
    GetNext(*) {
        return this.rows.Length ? 1 : 0
    }

    Delete(row) {
        this.rows.RemoveAt(row)
    }
}

class ThrowingDeleteListView extends RemovableListView {
    Delete(*) {
        throw Error("simulated ListView delete failure")
    }
}

class PassiveRuntimeKeybindGUI extends KeybindGUI {
    applyCalls := 0

    ApplyProfileCandidate(*) {
        this.applyCalls++
        return true
    }

    ResizeColumns(*) {
    }
}

class FailedRestoreKeybindGUI extends PassiveRuntimeKeybindGUI {
    RestoreRuntimeProfile(profile, &errorText) {
        errorText := "simulated restore failure"
        return false
    }
}

class RollbackFailingKeybindGUI extends KeybindGUI {
    ApplyBinds(*) {
        this.applyCalls++
        return false
    }

    RestoreRuntimeProfile(profile, &errorText) {
        this.restoreCalls++
        errorText := "simulated restore failure"
        return false
    }

    ResizeColumns(*) {
    }
}

class CaptureStartRestoreFailingKeybindGUI extends KeybindGUI {
    StartInputHook(*) {
        throw Error("simulated hook start failure")
    }

    RestoreRuntimeProfile(profile, &errorText) {
        this.restoreCalls++
        errorText := "simulated capture restore failure"
        return false
    }
}

class CaptureMutationGuardGUI extends KeybindGUI {
    StartInputHook(*) {
        KeybindGUI.activeInputHook := FakeCaptureHook("F14")
    }

    HasMainWindow() {
        return false
    }

    ApplyProfileBinds(*) {
        return true
    }

    RestoreRuntimeProfile(profile, &errorText) {
        errorText := ""
        HotkeyManager.activeHotkeys := Map()
        for funcName, bind in profile.binds {
            if (bind != "")
                HotkeyManager.activeHotkeys[funcName] := {
                    hotkey: bind,
                    scope: profile.scopes.Has(funcName)
                        ? profile.scopes[funcName]
                        : "Any"
                }
        }
        return true
    }

    NotifyUser(message, title, options := "") {
        this.notifications.Push({
            message: message,
            title: title,
            options: options
        })
    }
}

class CapturePublicationOrderGUI extends CaptureMutationGuardGUI {
    MarkProfileDirty(profileName := "") {
        this.events.Push("dirty")
        return super.MarkProfileDirty(profileName)
    }

    ReleaseCaptureTransaction() {
        this.events.Push("release")
        return super.ReleaseCaptureTransaction()
    }
}

class CaptureCancelRestoreFailingKeybindGUI extends KeybindGUI {
    StartInputHook(*) {
    }

    RestoreRuntimeProfile(profile, &errorText) {
        this.restoreCalls++
        errorText := "simulated cancel restore failure"
        return false
    }
}

class ModifierRestartRestoreFailingKeybindGUI extends KeybindGUI {
    StartInputHook(*) {
        this.startCalls++
        if (this.startCalls > 1)
            throw Error("simulated modifier hook restart failure")
    }

    RestoreRuntimeProfile(profile, &errorText) {
        this.restoreCalls++
        errorText := "simulated modifier restore failure"
        return false
    }
}

class SaveRuntimeFailingKeybindGUI extends KeybindGUI {
    ApplyProfileBinds(*) {
        this.applyCalls++
        return false
    }

    RestoreRuntimeProfile(profile, &errorText) {
        this.restoreCalls++
        errorText := "simulated saved-profile restore failure"
        return false
    }
}

class StaleScopeTrackingKeybindGUI extends KeybindGUI {
    RestoreRuntimeProfile(*) {
        this.restoreCalls++
        return true
    }
}

class RenameRuntimeTrackingKeybindGUI extends KeybindGUI {
    GuiIsLive(gui) {
        return !HasProp(gui, "destroyed") || !gui.destroyed
    }

    CreateMainGUI(applyBinds := true) {
        this.createCalls++
        if applyBinds
            this.applyCalls++
    }
}

class DirtyLeaveTestGUI extends KeybindGUI {
    ApplyBinds(*) {
        return true
    }

    ApplyProfileBinds(*) {
        return true
    }

    PrepareForProfileSwitch() {
        this.prepareCalls++
    }

    HasMainWindow() {
        return false
    }

    ShowProfileSelector() {
        this.selectorCalls++
        return true
    }

    RequestExit() {
        this.exitCalls++
    }
}

class DirtyRenameTestGUI extends DirtyLeaveTestGUI {
    GuiIsLive(gui) {
        return !HasProp(gui, "destroyed") || !gui.destroyed
    }

    NewProfileDialog(*) {
        this.dialogCreateCalls++
        throw Error("rename dialog must not be created")
    }

    CreateMainGUI(applyBinds := true) {
        this.createCalls++
        if applyBinds
            this.applyCalls++
    }
}

class DiscardRenameTrackingGUI extends KeybindGUI {
    GuiIsLive(gui) {
        return IsObject(gui) && (!HasProp(gui, "destroyed") || !gui.destroyed)
    }

    HasMainWindow() {
        return this.GuiIsLive(this.gui)
    }

    RestoreRuntimeProfile(profile, &errorText) {
        errorText := ""
        HotkeyManager.activeHotkeys := Map(
            "Sign Report", {
                hotkey: profile.binds["Sign Report"],
                scope: profile.scopes["Sign Report"]
            }
        )
        return true
    }

    CreateMainGUI(applyBinds := true) {
        this.createCalls++
        this.lastCreateAppliedBinds := applyBinds
        profile := ProfileManager.profiles[ProfileManager.currentProfile]
        this.visibleBind := profile.binds["Sign Report"]
        this.visibleScope := profile.scopes["Sign Report"]
        this.gui := FakeProfileDialog()
    }
}

class DirtyPersistentOperationGUI extends KeybindGUI {
    HasMainWindow() {
        return false
    }

    NewProfileDialog(*) {
        this.dialogCalls++
        return FakeProfileDialog(ProfileManager.currentProfile)
    }

    NotifyUser(*) {
    }
}

class DirtyAddFunctionTestGUI extends KeybindGUI {
    IsProfileDirty(*) {
        return this.dirty
    }

    ResolveDirtyProfileBeforeLeaving(*) {
        this.resolveCalls++
        this.dirty := false
        return true
    }

    NewProfileDialog(*) {
        this.dialogCalls++
        throw Error("A stale ListView must not reach dialog creation")
    }

    NotifyUser(*) {
        this.notices++
    }
}

class FixedProfileLeaveDriver {
    __New(choice) {
        this.choice := choice
    }

    Choose(*) {
        return this.choice
    }
}

class ProfileDeleteTestGUI extends KeybindGUI {
    ShowProfileSelector() {
    }
}

class AlwaysConfirmDriver {
    Confirm(*) {
        return true
    }
}

class RemoveRaceConfirmationDriver extends AlwaysConfirmDriver {
    __New(profile, listView) {
        this.profile := profile
        this.listView := listView
    }

    Confirm(*) {
        this.profile.binds["Sign Report"] := "^F22"
        this.listView.rows.InsertAt(1, ["Draft Report", "Ctrl + F24", "Any window"])
        return true
    }
}

class RecreateCustomConfirmationDriver extends AlwaysConfirmDriver {
    __New(profile) {
        this.profile := profile
    }

    Confirm(*) {
        this.profile.customFuncs.Delete("Custom: Keep")
        this.profile.customFuncs["Custom: Keep"] := {keys: "NEW", window: ""}
        this.profile.binds["Custom: Keep"] := "^F22"
        return true
    }
}

class RecreateProfileConfirmationDriver extends AlwaysConfirmDriver {
    __New(profileName) {
        this.profileName := profileName
    }

    Confirm(*) {
        replacement := ProfileManager.NewProfile()
        replacement.modalityAttendings["Marker"] := "replacement"
        ProfileManager.profiles[this.profileName] := replacement
        ProfileManager.SaveProfile(this.profileName, replacement)
        return true
    }
}

class CapturingNotificationDriver {
    __New() {
        this.message := ""
    }

    Notify(message, *) {
        this.message := message
        return "OK"
    }
}

class TransactionalHotkeyDriver {
    __New() {
        this.failDisable := Map()
        this.failEnableCounts := Map()
    }

    Enable(hotkeyStr, callback) {
        if (this.failEnableCounts.Has(hotkeyStr)
            && this.failEnableCounts[hotkeyStr] > 0) {
            this.failEnableCounts[hotkeyStr]--
            throw Error("simulated native On failure")
        }
    }

    Disable(hotkeyStr) {
        if this.failDisable.Has(hotkeyStr)
            throw Error("simulated native Off failure")
    }
}

class FakeCaptureHook {
    __New(endKey, endMods := "") {
        this.EndKey := endKey
        this.EndMods := endMods
        this.EndReason := "EndKey"
        this.stopped := false
    }

    Stop() {
        this.stopped := true
    }
}

class FailingCaptureHook extends FakeCaptureHook {
    Stop() {
        throw Error("simulated InputHook stop failure")
    }
}

class FakeProfileDialog {
    __New(profileName := "Test", profileRevision?) {
        this.destroyed := false
        this.profileName := profileName
        this.profileRevision := IsSet(profileRevision)
            ? profileRevision
            : ProfileManager.GetProfileRevision(profileName)
        this.profileMutationRevision := KeybindGUI.GetProfileMutationRevision(profileName)
    }

    Destroy() {
        this.destroyed := true
    }
}
