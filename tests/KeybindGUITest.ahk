; = CONTENTS
;   + Preamble
;   + KeybindGUITest class (keybind GUI: capture, profile editing, save/rename/delete, modality/attending)
;   + Test doubles (ListView fakes, KeybindGUI capture/restore variants, capture owners, runtime fakes)

#Requires AutoHotkey v2.0
#Include ../KeybindGUI.ahk
#Include TestRunner.ahk
#Include ExclusiveOperationsFixture.ahk
#Include LogCapture.ahk

class KeybindGUITest {
    static tests := [
        "TestSelectedFunctionPrefersBuiltIn",
        "TestSelectedFunctionSurvivesMissingCustomList",
        "TestFunctionListsKeepOnlyTheLastClickedSelection",
        "TestPrettifyHotkey",
        "TestCustomFunctionNameChecksUnboundFunctions",
        "TestCustomFunctionNamesUsePersistedCaseInsensitiveIdentity",
        "TestCustomKeybindRejectsABlankLookingWindow",
        "TestAddedCustomKeybindSucceedsWhenCaptureDoesNotStart",
        "TestLoadErrorSummaryNamesEachFileAndCause",
        "TestStaleAddFunctionCannotClearANewerBinding",
        "TestProfileBindingOwnerUsesRuntimeIdentity",
        "TestCaptureSuppressesInputToTheForegroundWindow",
        "TestCapturedHotkeyUsesTerminationModifierSnapshot",
        "TestProfileSwitchPreparationStopsActiveCapture",
        "TestProfileSwitchAbortsWhenCaptureCannotStop",
        "TestCaptureStartFailureWarnsWhenRuntimeCannotBeRestored",
        "TestCapturePromptShowFailureRestoresRuntimeAndReleasesOwner",
        "TestStaleCaptureBeforeSuspensionReleasesWithoutRuntimeMutation",
        "TestActiveCaptureBlocksSaveAndFunctionRemoval",
        "TestClinicalCommandBlocksProfileMutationAndExit",
        "TestTrayExitUsesTheSameClinicalAndCaptureGate",
        "TestCaptureThatNeedsARestartDoesNotBlockExit",
        "TestBindForAMissingCommandIsReportedNotFailed",
        "TestStaleRealCaptureRestoresCurrentProfileNotSnapshot",
        "TestProfileBoundDialogRejectsSameNameReplacement",
        "TestCapturedBindPublishesDirtyStateBeforeReleasingOwner",
        "TestCancelCaptureWarnsWhenPriorRuntimeCannotBeRestored",
        "TestCancelCaptureRetainsTransactionWhenHookCannotStop",
        "TestOnInputEndRetainsCaptureWhenHookTeardownFails",
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
        "TestSaveBeforeAddFunctionOpensTheDialog",
        "TestStaleRenameDialogCannotRenameAnotherProfile",
        "TestRenameToAnInvalidNameSaysTheNameIsInvalid",
        "TestRenameDialogRefusesAProfileEditedSinceItOpened",
        "TestApplyBindsReleasesTheLeaseItTook",
        "TestFailedDiscardReloadIsReportedAndLogged",
        "TestDestroyedRenameDialogCannotMutateProfile",
        "TestRenameDialogCannotMutateSameNameReplacement",
        "TestRenamePromptHonorsDirtyCancel",
        "TestCaseOnlyRenamePersistsResolvedDirtyChanges",
        "TestSaveChoiceRejectsProfileChangedDuringDirtyPrompt",
        "TestDiscardBeforeRenameRestoresRuntimeAndMainView",
        "TestDiscardBeforeCaseRenameKeepsStoredRuntime",
        "TestSuccessfulMainRenameDoesNotReapplyHotkeys",
        "TestDefaultProfileSelectionRequiresExactRenderedName",
        "TestCreateProfileSurfacesStorageRecovery",
        "TestDirtyScopeEditBlocksProfileSwitchWhenCancelled",
        "TestClosingSavesDirtyProfileBeforeExit",
        "TestShutdownLeaseIsReleasedWhenTheDirtyPromptThrowsANonError",
        "TestNoticesUnderTheProfileLeaseWaitForItsRelease",
        "TestCancelledCandidateNoticeWaitsForTheLeaseAndIsLogged",
        "TestUnstoppableCaptureHookIsLogged",
        "TestProfileSwitchCanDiscardDirtyChanges",
        "TestFailedCustomDeletePreservesLiveProfile",
        "TestRemoveFunctionKeepsProfileAndRowWhenNativeOffFails",
        "TestCustomDeleteRollsBackWhenLaterRegistrationFails",
        "TestStaleRemoveConfirmationCannotDeleteReplacementRow",
        "TestStaleCustomDeleteCannotDeleteRecreatedCommand",
        "TestCustomDeleteRejectsConcurrentUnrelatedDirtyEdit",
        "TestRowDeleteAndRuntimeRestoreFailureRequiresRestartWarning",
        "TestRejectedKeybindWarnsWhenPriorRuntimeCannotBeRestored",
        "TestRejectedScopeWarnsWhenPriorRuntimeCannotBeRestored",
        "TestSavedProfileFailsWhenRuntimeCannotBeVerified",
        "TestConcurrentMutationDuringSaveRemainsDirtyAndRestoresNewRuntime",
        "TestClinicalCommandCannotInterruptProfileApply",
        "TestStaleProfileDeleteCannotDeleteRecreatedProfile",
        "TestProfileSelectorCloseCannotInterruptDefaultProfileTransaction",
        "TestProfileCreationCloseCannotInterruptStorageTransaction",
        "TestDestroyedNewProfileDialogCannotDispatchQueuedActions",
        "TestDestroyedProfileSelectorCannotDispatchQueuedActions",
        "TestSelectWithoutAHighlightedProfileSaysSo",
        "TestProfileDeletionRevalidatesTheSelectorAfterConfirmation",
        "TestConfirmedProfileDeletionDeletesAndRefreshesTheSelector"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "UseTempProfilesFolder",
        "PrepareBlockedProfileSave",
        "PrepareDiscardRenameState"
    ]

    Setup() {
        ; Build an instance without running the constructor, which loads profiles from
        ; disk and opens the main window, the profile selector or a new-profile prompt
        this.gui := {base: KeybindGUI.Prototype, gui: ""}
        this.originalLeases := ExclusiveOperationsFixture.ReleaseAll()
        this.tempProfilesRoot := ""
        this.originalCaptureRuntimeProfile := KeybindGUI.captureRuntimeProfile
        this.originalCaptureOwnerGui := KeybindGUI.captureOwnerGui
        this.originalProfileMutationRevisions := KeybindGUI.profileMutationRevisions
        this.originalShutdownAuthorized := KeybindGUI.shutdownAuthorized
        this.originalDeferredNotices := KeybindGUI.deferredNotices
        this.originalCommandAvailabilityProbe := PACSCommands.commandAvailabilityProbe
        KeybindGUI.captureRuntimeProfile := 0
        KeybindGUI.captureOwnerGui := 0
        KeybindGUI.profileMutationRevisions := Map()
        KeybindGUI.shutdownAuthorized := false
        KeybindGUI.deferredNotices := []
        PACSCommands.commandAvailabilityProbe := (*) => true

        ; Tests replace the loaded profiles and the listening state freely; Teardown
        ; restores them even when a test fails partway through.
        this.originalProfiles := ProfileManager.profiles
        this.originalCurrentProfile := ProfileManager.currentProfile
        this.originalDefaultProfile := ProfileManager.defaultProfile
        this.originalProfilesPath := ProfileManager.profilesPath
        this.originalProfileRevisions := ProfileManager.profileRevisions
        this.originalStorageDriver := ProfileManager.storageDriver
        this.originalRecoveryRequired := ProfileManager.recoveryRequired
        this.originalRecoveryCause := ProfileManager.recoveryCause
        this.originalStorageLastError := ProfileManager.lastError
        this.originalIsListening := KeybindGUI.isListening
        this.originalActiveInputHook := KeybindGUI.activeInputHook
        this.originalHotkeyFunctions := HotkeyManager.hotkeyFunctions
        this.originalActiveHotkeys := HotkeyManager.activeHotkeys
        this.originalHotkeyDriver := HotkeyManager.hotkeyDriver
        ; No test registers a real hotkey: a binding such as Ctrl+S would otherwise
        ; be live on the desktop while the suite runs. HotkeyManagerTest keeps the
        ; native key-name coverage.
        HotkeyManager.activeHotkeys := Map()
        HotkeyManager.hotkeyDriver := TransactionalHotkeyDriver()
        ; Saving a profile bumps its revision in place, so each test starts from
        ; fresh maps rather than the ones Teardown restores.
        ProfileManager.profiles := Map()
        ProfileManager.profileRevisions := Map()
    }

    Teardown() {
        ExclusiveOperationsFixture.Restore(this.originalLeases)
        if (this.tempProfilesRoot != "")
            try DirDelete(this.tempProfilesRoot, true)
        KeybindGUI.captureRuntimeProfile := this.originalCaptureRuntimeProfile
        KeybindGUI.captureOwnerGui := this.originalCaptureOwnerGui
        KeybindGUI.profileMutationRevisions := this.originalProfileMutationRevisions
        KeybindGUI.shutdownAuthorized := this.originalShutdownAuthorized
        KeybindGUI.deferredNotices := this.originalDeferredNotices
        PACSCommands.commandAvailabilityProbe := this.originalCommandAvailabilityProbe
        ProfileManager.profiles := this.originalProfiles
        ProfileManager.currentProfile := this.originalCurrentProfile
        ProfileManager.defaultProfile := this.originalDefaultProfile
        ProfileManager.profilesPath := this.originalProfilesPath
        ProfileManager.profileRevisions := this.originalProfileRevisions
        ProfileManager.storageDriver := this.originalStorageDriver
        ProfileManager.recoveryRequired := this.originalRecoveryRequired
        ProfileManager.recoveryCause := this.originalRecoveryCause
        ProfileManager.lastError := this.originalStorageLastError
        KeybindGUI.isListening := this.originalIsListening
        KeybindGUI.activeInputHook := this.originalActiveInputHook
        HotkeyManager.hotkeyFunctions := this.originalHotkeyFunctions
        HotkeyManager.activeHotkeys := this.originalActiveHotkeys
        HotkeyManager.hotkeyDriver := this.originalHotkeyDriver
    }

    TestSelectedFunctionPrefersBuiltIn() {
        Assert.Equal("Sign Report",
            this.gui.SelectedFunction({Text: "Sign Report"}, {Text: "Custom: Yell"}))
        Assert.Equal("Custom: Yell",
            this.gui.SelectedFunction({Text: ""}, {Text: "Custom: Yell"}))
        Assert.Equal("", this.gui.SelectedFunction({Text: ""}, {Text: ""}))
    }

    ; Add Selected must add what was clicked last, so choosing in one list clears
    ; the other.
    TestFunctionListsKeepOnlyTheLastClickedSelection() {
        dialog := Gui()
        try {
            lbBuiltIn := dialog.Add("ListBox", "w200 h80", ["Draft Report", "Sign Report"])
            lbCustom := dialog.Add("ListBox", "w200 h80", ["Custom: Macro"])
            this.gui.LinkFunctionLists(lbBuiltIn, lbCustom)

            SelectListBoxItem(lbBuiltIn, 1)
            SelectListBoxItem(lbCustom, 1)
            Assert.Equal("", lbBuiltIn.Text)
            Assert.Equal("Custom: Macro", this.gui.SelectedFunction(lbBuiltIn, lbCustom))

            SelectListBoxItem(lbBuiltIn, 2)
            Assert.Equal("", lbCustom.Text)
            Assert.Equal("Sign Report", this.gui.SelectedFunction(lbBuiltIn, lbCustom))
        } finally dialog.Destroy()
    }

    ; The custom-function list exists only when the profile has custom functions, so
    ; reading the selection must not assume it; otherwise the GUI callback raises an
    ; unset-variable error for a profile without any.
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
        Assert.Equal("Ctrl + Alt + Shift + Win + K", this.gui.PrettifyHotkey("#+!^k"))
        ; A trailing symbol is the key itself.
        Assert.Equal("Ctrl + +", this.gui.PrettifyHotkey("^+"))
        Assert.Equal("Ctrl + #", this.gui.PrettifyHotkey("^#"))
        ; Behavior prefixes are not shown; sided modifiers are.
        Assert.Equal("Ctrl + J", this.gui.PrettifyHotkey("~$^j"))
        Assert.Equal("LCtrl + J", this.gui.PrettifyHotkey("<^j"))
        Assert.Equal("F5", this.gui.PrettifyHotkey("*F5"))
        ; Key names use AutoHotkey's canonical spelling.
        Assert.Equal("Ctrl + NumpadAdd", this.gui.PrettifyHotkey("^numpadadd"))
        Assert.Equal("Ctrl + Escape", this.gui.PrettifyHotkey("^Esc"))
        Assert.Equal("Ctrl + NumpadHome", this.gui.PrettifyHotkey("^NumpadHome"))
        Assert.Equal("Ctrl + F13", this.gui.PrettifyHotkey("^F13"))
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

    ; Such a window matches nothing, so the command would silently never run.
    TestCustomKeybindRejectsABlankLookingWindow() {
        profile := ProfileManager.NewProfile()
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        dialog := FakeProfileDialog("Test")

        Assert.False(this.gui.AddCustomKeybind("Yell", "HELLO", " `t ", "", dialog))

        Assert.False(profile.customFuncs.Has("Custom: Yell"))
        Assert.Equal(1, TestRunner.dialogs.Length)
        Assert.Equal("Invalid Custom Keybind", TestRunner.dialogs[1].title)
        Assert.False(dialog.destroyed)
    }

    ; Like Add Function, the function is added and marked dirty whether or not
    ; key capture then starts.
    TestAddedCustomKeybindSucceedsWhenCaptureDoesNotStart() {
        profile := ProfileManager.NewProfile()
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        dialog := FakeProfileDialog("Test")
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        editor := {base: CaptureRefusingKeybindGUI.Prototype, gui: "", promptCalls: 0}

        Assert.True(editor.AddCustomKeybind("Yell", "HELLO", "", listView, dialog))

        Assert.Equal(1, editor.promptCalls)
        Assert.True(profile.customFuncs.Has("Custom: Yell"))
        Assert.Equal("Custom: Yell", listView.GetText(2, 1))
        Assert.True(editor.IsProfileDirty("Test"))
        Assert.True(dialog.destroyed)
    }

    TestLoadErrorSummaryNamesEachFileAndCause() {
        summary := KeybindGUI.LoadErrorSummary([
            {path: "C:\data\profiles\Night.ini", message: "Profile is missing [Functions] Order"},
            {path: "C:\data\profiles\Day.ini", message: "unknown legacy hotkey scope"}
        ])

        Assert.True(InStr(summary, "2 profile file(s) could not be loaded") = 1, summary)
        Assert.True(InStr(summary, "C:\data\profiles\Night.ini`nProfile is missing [Functions] Order"), summary)
        Assert.True(InStr(summary, "C:\data\profiles\Day.ini`nunknown legacy hotkey scope"), summary)
        Assert.True(InStr(summary, "error.log"), summary)
    }

    TestStaleAddFunctionCannotClearANewerBinding() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "PACS"
        dialog := FakeProfileDialog("Test")

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        result := this.gui.AddFunction("Sign Report", RejectingAddListView(), dialog)
        capturedBind := profile.binds["Sign Report"]
        capturedScope := profile.scopes["Sign Report"]
        capturedDestroyed := dialog.destroyed

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
        hook := FakeCaptureHook("F13")
        KeybindGUI.isListening := true
        KeybindGUI.activeInputHook := hook

        try {
            this.gui.PrepareForProfileSwitch()
            capturedListening := KeybindGUI.isListening
            capturedHook := KeybindGUI.activeInputHook
            capturedStopped := hook.stopped
        } finally {
            this.gui.StopListening()
        }

        Assert.False(capturedListening)
        Assert.Equal(0, capturedHook)
        Assert.True(capturedStopped)
    }

    TestProfileSwitchAbortsWhenCaptureCannotStop() {
        hook := FailingCaptureHook("F13")
        KeybindGUI.isListening := true
        KeybindGUI.activeInputHook := hook

        threw := false
        caughtMessage := ""
        try this.gui.PrepareForProfileSwitch()
        catch Any as err {
            threw := true
            caughtMessage := ErrorText.Message(err)
        }

        capturedListening := KeybindGUI.isListening
        capturedHook := KeybindGUI.activeInputHook

        KeybindGUI.activeInputHook := 0
        KeybindGUI.isListening := false

        Assert.True(threw)
        Assert.True(InStr(caughtMessage, "simulated InputHook stop failure") > 0, caughtMessage)
        Assert.True(capturedListening)
        Assert.True(capturedHook == hook)
    }

    TestCaptureStartFailureWarnsWhenRuntimeCannotBeRestored() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        prompt := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        editor := {
            base: CaptureStartRestoreFailingKeybindGUI.Prototype,
            restoreCalls: 0,
            notificationDriver: notifications
        }
        threw := false
        caughtMessage := ""

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.hotkeyFunctions := Map()
        HotkeyManager.activeHotkeys := Map()
        KeybindGUI.isListening := false
        KeybindGUI.activeInputHook := 0

        Assert.True(editor.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))
        try editor.BeginListening("Sign Report", listView, prompt)
        catch Error as err {
            threw := true
            caughtMessage := err.Message
        }
        capturedListening := KeybindGUI.isListening
        capturedHook := KeybindGUI.activeInputHook

        Assert.True(threw)
        Assert.True(InStr(caughtMessage, "simulated hook start failure") > 0)
        Assert.False(capturedListening)
        Assert.Equal(0, capturedHook)
        Assert.Equal(1, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated capture restore failure") > 0)
    }

    TestCapturePromptShowFailureRestoresRuntimeAndReleasesOwner() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := ThrowingShowProfileDialog("Test")
        owner := FakeCaptureOwnerGui()
        editor := {
            base: ShowFailureRecoveryGUI.Prototype,
            gui: owner,
            restoreCalls: 0,
            notifications: []
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.activeHotkeys := Map()
        KeybindGUI.isListening := false
        KeybindGUI.activeInputHook := 0
        Assert.True(editor.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))
        Assert.True(editor.BeginListening("Sign Report", listView, prompt))
        hook := KeybindGUI.activeInputHook

        result := editor.ShowStartedCapturePrompt(prompt)

        Assert.False(result)
        Assert.True(prompt.destroyed)
        Assert.True(hook.stopped)
        Assert.Equal(1, editor.restoreCalls)
        Assert.False(ExclusiveOperations.captureActive)
        Assert.False(owner.disabled)
    }

    TestActiveCaptureBlocksSaveAndFunctionRemoval() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        profile.binds["Custom: Keep"] := ""
        profile.scopes["Custom: Keep"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        customDialog := FakeProfileDialog("Test")
        ; A dialog left over from another profile: without the lease check its
        ; staleness handling would end the capture it does not own.
        staleDialog := FakeProfileDialog("Other")
        editor := {base: CaptureMutationGuardGUI.Prototype}
        editor.confirmationDriver := AlwaysConfirmDriver()
        editor.notifications := []

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            Assert.True(editor.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(editor.BeginListening("Sign Report", listView, prompt))

            profile.binds["Sign Report"] := "^F14"
            saveResult := editor.SaveCurrentProfile()
            removeResult := editor.RemoveFunction(listView)
            scopeResult := editor.ApplyScope(
                "Sign Report",
                true,
                false,
                listView,
                1,
                prompt
            )
            renameResult := editor.PromptRenameProfile("Test")
            customDeleteResult := editor.DeleteCustomFunction(
                "Custom: Keep",
                customDialog
            )
            addFunctionResult := editor.AddFunction("Draft Report", listView, staleDialog)
            addCustomResult := editor.AddCustomKeybind("Macro", "HELLO", "", listView, staleDialog)
            captureStillListening := KeybindGUI.isListening
            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
            storedBind := stored.binds["Sign Report"]
            stillBound := profile.binds.Has("Sign Report")
            customStillExists := profile.customFuncs.Has("Custom: Keep")
            rowCount := listView.GetCount()
        } finally {
            try editor.CancelKeybindPrompt(prompt)
            KeybindGUI.captureRuntimeProfile := 0
            KeybindGUI.isListening := false
            KeybindGUI.activeInputHook := 0
        }

        Assert.False(saveResult)
        Assert.False(removeResult)
        Assert.False(scopeResult)
        Assert.False(renameResult)
        Assert.False(customDeleteResult)
        Assert.False(addFunctionResult)
        Assert.False(addCustomResult)
        Assert.True(captureStillListening, "another dialog's action ended the active capture")
        Assert.False(profile.binds.Has("Draft Report"))
        Assert.Equal(1, profile.customFuncs.Count)
        Assert.Equal("^F13", storedBind)
        Assert.True(stillBound)
        Assert.True(customStillExists)
        Assert.Equal("Any", profile.scopes["Sign Report"])
        Assert.Equal(1, rowCount)
    }

    TestProfileBoundDialogRejectsSameNameReplacement() {
        oldProfile := ProfileManager.NewProfile()
        replacement := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("Test", 1)
        dialog.requiresLiveProfileIdentity := true
        dialog.profileObject := oldProfile
        dialog.profileStorageRevision := 1
        dialog.profileMutationSnapshot := 0
        dialog.ownerHwnd := 0
        editor := {base: LiveDialogIdentityGUI.Prototype}

        ProfileManager.profiles := Map("Test", oldProfile)
        ProfileManager.currentProfile := "Test"
        ProfileManager.profileRevisions := Map("Test", 1)
        ProfileManager.profiles["Test"] := replacement

        result := editor.DialogProfileIsCurrent(dialog)

        Assert.False(result)
        Assert.True(dialog.destroyed)
    }

    TestClinicalCommandBlocksProfileMutationAndExit() {
        editor := {
            base: DirtyLeaveTestGUI.Prototype,
            exitCalls: 0,
            notifications: []
        }
        editor.notificationDriver := ArrayNotificationDriver(editor.notifications)
        PACSCommands.clinicalCommandActive := true
        PACSCommands.activeClinicalCommand := "Paste Wet Read"

        mutationAllowed := editor.ProfileMutationAllowed("change profiles")
        closeResult := editor.RequestExit()

        Assert.False(mutationAllowed)
        Assert.False(closeResult)
        Assert.Equal(0, editor.exitCalls)
        Assert.Equal(2, editor.notifications.Length)
        Assert.True(InStr(editor.notifications[1].message, "Paste Wet Read") > 0)
    }

    TestProfileSelectorCloseCannotInterruptDefaultProfileTransaction() {
        profile := ProfileManager.NewProfile()
        selector := ReentrantSelectorDialog()
        editor := {
            base: ProfileSelectorTransactionGUI.Prototype,
            mainWindowCalls: 0,
            selectorCalls: 0,
            notifications: []
        }
        editor.notificationDriver := ArrayNotificationDriver(editor.notifications)
        driver := ReentrantDefaultProfileStorageDriver(
            (*) => editor.CloseProfileSelector(selector),
            selector
        )

        ProfileManager.profiles := Map("Night", profile)
        ProfileManager.currentProfile := "Night"
        ProfileManager.defaultProfile := ""
        ProfileManager.storageDriver := driver
        editor.RegisterProfileSelector(selector)
        result := editor.SetDefaultProfile("Night", selector)
        capturedDefault := ProfileManager.defaultProfile

        Assert.True(result)
        Assert.True(driver.closeAttempted)
        Assert.False(driver.closeResult)
        Assert.True(driver.observedDisabled)
        Assert.Equal(1, selector.destroyCalls)
        Assert.Equal(0, editor.mainWindowCalls)
        Assert.Equal(1, editor.selectorCalls)
        Assert.Equal("Night", capturedDefault)
    }

    TestProfileCreationCloseCannotInterruptStorageTransaction() {
        inputGui := ReentrantSelectorDialog()
        editor := {
            base: ReentrantProfileCreationGUI.Prototype,
            inputGui: inputGui,
            mainWindowCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            closeAttempted: false,
            closeResult: true,
            observedDisabled: false
        }

        ProfileManager.profiles := Map("Existing", ProfileManager.NewProfile())
        ProfileManager.currentProfile := ""

        result := editor.CreateProfile("New", inputGui)
        capturedCurrent := ProfileManager.currentProfile

        Assert.True(result)
        Assert.True(editor.closeAttempted)
        Assert.False(editor.closeResult)
        Assert.True(editor.observedDisabled)
        Assert.Equal(1, inputGui.destroyCalls)
        Assert.Equal(1, editor.mainWindowCalls)
        Assert.Equal(0, editor.selectorCalls)
        Assert.Equal(0, editor.exitCalls)
        Assert.Equal("New", capturedCurrent)
    }

    TestDestroyedNewProfileDialogCannotDispatchQueuedActions() {
        inputGui := FakeProfileDialog()
        editor := {
            base: QueuedNewProfileGUI.Prototype,
            mainWindowCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            createRecordCalls: 0
        }

        ProfileManager.profiles := Map("Existing", ProfileManager.NewProfile())
        ProfileManager.currentProfile := "Existing"
        inputGui.Destroy()

        closeResult := editor.CloseNewProfilePrompt(inputGui)
        createResult := editor.CreateProfile("Queued", inputGui)
        queuedExists := ProfileManager.profiles.Has("Queued")

        Assert.False(closeResult)
        Assert.False(createResult)
        Assert.False(queuedExists)
        Assert.Equal(0, editor.createRecordCalls)
        Assert.Equal(0, editor.mainWindowCalls)
        Assert.Equal(0, editor.selectorCalls)
        Assert.Equal(0, editor.exitCalls)
    }

    ; Like Set as Default, Rename and Delete, Select explains a click with nothing
    ; highlighted instead of doing nothing.
    TestSelectWithoutAHighlightedProfileSaysSo() {
        selector := FakeProfileDialog("")
        editor := {
            base: ProfileSelectorTransactionGUI.Prototype,
            mainWindowCalls: 0,
            selectorCalls: 0
        }
        ProfileManager.profiles := Map("A", ProfileManager.NewProfile())
        ProfileManager.currentProfile := ""
        editor.RegisterProfileSelector(selector)

        Assert.False(editor.SelectProfile("", selector))

        Assert.Equal(1, TestRunner.dialogs.Length)
        Assert.Equal("No Profile Selected", TestRunner.dialogs[1].title)
        Assert.Equal(0, editor.mainWindowCalls)
        Assert.False(selector.destroyed)
    }

    TestDestroyedProfileSelectorCannotDispatchQueuedActions() {
        selector := ReentrantSelectorDialog()
        confirmation := CountingRejectConfirmationDriver()
        editor := {
            base: ProfileSelectorTransactionGUI.Prototype,
            mainWindowCalls: 0,
            selectorCalls: 0,
            promptCalls: 0,
            dialogCalls: 0,
            exitCalls: 0,
            confirmationDriver: confirmation
        }

        ProfileManager.profiles := Map(
            "A", ProfileManager.NewProfile(),
            "B", ProfileManager.NewProfile()
        )
        ProfileManager.currentProfile := "A"
        editor.RegisterProfileSelector(selector)

        Assert.True(editor.CloseProfileSelector(selector))
        selectResult := editor.SelectProfile("B", selector)
        newResult := editor.OpenNewProfilePrompt(selector)
        renameResult := editor.PromptRenameProfile("B", selector)
        deleteResult := editor.DeleteProfile("B", selector)

        Assert.False(selectResult)
        Assert.False(newResult)
        Assert.False(renameResult)
        Assert.False(deleteResult)
        Assert.Equal(1, editor.mainWindowCalls)
        Assert.Equal(0, editor.promptCalls)
        Assert.Equal(0, editor.dialogCalls)
        Assert.Equal(0, editor.selectorCalls)
        Assert.Equal(0, confirmation.calls)
    }

    ; The confirmation holds no lease, so clinical commands and monitoring keep
    ; running while it is open. The selector is disabled meanwhile; if it is closed
    ; anyway, the deletion is revalidated and does not happen.
    TestProfileDeletionRevalidatesTheSelectorAfterConfirmation() {
        this.UseTempProfilesFolder()
        selector := ReentrantSelectorDialog()
        editor := {
            base: ProfileSelectorTransactionGUI.Prototype,
            mainWindowCalls: 0,
            selectorCalls: 0,
            promptCalls: 0,
            dialogCalls: 0,
            exitCalls: 0
        }
        confirmation := ReentrantProfileDeleteConfirmationDriver(
            (*) => editor.CloseProfileSelector(selector),
            selector
        )
        editor.confirmationDriver := confirmation

        ProfileManager.profiles := Map(
            "A", ProfileManager.NewProfile(),
            "B", ProfileManager.NewProfile()
        )
        ProfileManager.currentProfile := "A"
        ProfileManager.defaultProfile := ""
        ProfileManager.SaveProfile("A", ProfileManager.profiles["A"])
        ProfileManager.SaveProfile("B", ProfileManager.profiles["B"])
        editor.RegisterProfileSelector(selector)

        result := editor.DeleteProfile("B", selector)
        bStillExists := ProfileManager.profiles.Has("B")

        Assert.False(result)
        Assert.True(confirmation.observedDisabled)
        Assert.Equal("", confirmation.observedLease)
        Assert.True(confirmation.closeResult)
        Assert.True(bStillExists)
        Assert.Equal(1, selector.destroyCalls)
        Assert.Equal(1, editor.mainWindowCalls)
        Assert.Equal(0, editor.selectorCalls)
    }

    TestConfirmedProfileDeletionDeletesAndRefreshesTheSelector() {
        this.UseTempProfilesFolder()
        selector := ReentrantSelectorDialog()
        editor := {
            base: ProfileSelectorTransactionGUI.Prototype,
            mainWindowCalls: 0,
            selectorCalls: 0
        }
        confirmation := ReentrantProfileDeleteConfirmationDriver((*) => false, selector)
        editor.confirmationDriver := confirmation

        ProfileManager.profiles := Map(
            "A", ProfileManager.NewProfile(),
            "B", ProfileManager.NewProfile()
        )
        ProfileManager.currentProfile := "A"
        ProfileManager.defaultProfile := ""
        ProfileManager.SaveProfile("A", ProfileManager.profiles["A"])
        ProfileManager.SaveProfile("B", ProfileManager.profiles["B"])
        editor.RegisterProfileSelector(selector)

        Assert.True(editor.DeleteProfile("B", selector))

        Assert.Equal("", confirmation.observedLease)
        Assert.False(ProfileManager.profiles.Has("B"))
        Assert.False(FileExist(ProfileManager.ProfilePath("B")))
        Assert.Equal(1, selector.destroyCalls)
        Assert.Equal(1, editor.selectorCalls)
        Assert.Equal("", ExclusiveOperations.Active())
    }

    ; A capture that could not be undone keeps its lease against clinical commands,
    ; and its notice asks for a restart, so exiting must still be possible.
    TestCaptureThatNeedsARestartDoesNotBlockExit() {
        editor := {base: KeybindGUI.Prototype, notifications: []}
        editor.notificationDriver := ArrayNotificationDriver(editor.notifications)
        PACSCommands.commandAvailabilityProbe := (*) => ExclusiveOperations.Active("clinical") = ""

        try {
            Assert.True(ExclusiveOperations.TryBegin("capture", "change a keybind"))
            ExclusiveOperations.captureRestartRequired := true
            clinical := PACSCommands.AcquireClinicalAutomation("Sign Report")
            exitResult := editor.HandleProcessExit("Menu", 0)
        } finally editor.CancelShutdown()

        Assert.Equal("unavailable", clinical.status)
        Assert.Equal(0, exitResult)
        Assert.Equal(0, editor.notifications.Length)

        ; A capture later released normally no longer needs the restart.
        editor.ReleaseCaptureTransaction()
        Assert.False(ExclusiveOperations.captureRestartRequired)
    }

    ; A bind for a command this version does not have is left out of the runtime
    ; and reported once, so it cannot fail the apply, or every later restore and
    ; save, which would leave a capture holding its lease.
    TestBindForAMissingCommandIsReportedNotFailed() {
        notifications := []
        editor := {base: KeybindGUI.Prototype, gui: ""}
        editor.notificationDriver := ArrayNotificationDriver(notifications)
        HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.binds["Retired Command"] := "^F14"
        profile.binds["Unbound Retired Command"] := ""

        capturedLog := LogCapture()
        try {
            shownResult := editor.ApplyProfileBinds(profile, true)
            quietResult := editor.ApplyProfileBinds(profile, false)
            logged := capturedLog.Count("were not registered: Retired Command")
        } finally capturedLog.Restore()

        Assert.True(shownResult)
        Assert.True(quietResult)
        Assert.True(HotkeyManager.activeHotkeys.Has("Sign Report"))
        Assert.False(HotkeyManager.activeHotkeys.Has("Retired Command"))
        Assert.Equal(1, notifications.Length)
        Assert.Equal("Keybinds Not Registered", notifications[1].title)
        Assert.True(InStr(notifications[1].message, "not registered: Retired Command. "), notifications[1].message)
        Assert.Equal(1, logged)
    }

    TestTrayExitUsesTheSameClinicalAndCaptureGate() {
        editor := {base: KeybindGUI.Prototype, notifications: []}
        editor.notificationDriver := ArrayNotificationDriver(editor.notifications)

        try {
            PACSCommands.clinicalCommandActive := true
            PACSCommands.activeClinicalCommand := "Paste Wet Read"
            clinicalResult := editor.HandleProcessExit("Menu", 0)

            PACSCommands.clinicalCommandActive := false
            PACSCommands.activeClinicalCommand := ""
            ExclusiveOperations.captureActive := true
            captureResult := editor.HandleProcessExit("Menu", 0)

            ExclusiveOperations.captureActive := false
            cleanResult := editor.HandleProcessExit("Menu", 0)
            authorized := KeybindGUI.shutdownAuthorized
        } finally {
            editor.CancelShutdown()
            ExclusiveOperations.captureActive := false
        }

        Assert.Equal(1, clinicalResult)
        Assert.Equal(1, captureResult)
        Assert.Equal(0, cleanResult)
        Assert.True(authorized)
        Assert.Equal(2, editor.notifications.Length)
    }

    TestStaleRealCaptureRestoresCurrentProfileNotSnapshot() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        editor := {base: CaptureMutationGuardGUI.Prototype}
        editor.notifications := []

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.activeHotkeys := Map()
            Assert.True(editor.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(editor.BeginListening("Sign Report", listView, prompt))
            hook := KeybindGUI.activeInputHook

            ; Simulate a later committed mutation despite the UI gate. Stale capture
            ; recovery must honor this current profile, not resurrect its snapshot.
            profile.binds.Delete("Sign Report")
            profile.scopes.Delete("Sign Report")
            listView.Delete(1)
            result := editor.OnInputEnd("Sign Report", listView, prompt, hook)

            runtimeAbsent := !HotkeyManager.activeHotkeys.Has("Sign Report")
            profileAbsent := !profile.binds.Has("Sign Report")
        } finally {
            try editor.StopListening()
        }

        Assert.False(result)
        Assert.True(profileAbsent)
        Assert.True(runtimeAbsent)
        Assert.True(prompt.destroyed)
    }

    TestStaleCaptureBeforeSuspensionReleasesWithoutRuntimeMutation() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        editor := {base: StaleBeforeSuspensionGUI.Prototype}
        editor.gui := FakeCaptureOwnerGui()
        editor.notifications := []
        editor.restoreCalls := 0
        editor.onAcquired := (*) => (profile.binds["Sign Report"] := "^F14")

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.activeHotkeys := Map("Sign Report", {hotkey: "^F13"})
        Assert.True(editor.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))

        result := editor.BeginListening("Sign Report", listView, prompt)

        captureActive := ExclusiveOperations.captureActive
        captureOwner := KeybindGUI.captureOwnerGui
        ownerDisabled := editor.gui.disabled
        runtimeStillTracked := HotkeyManager.activeHotkeys.Has("Sign Report")

        Assert.False(result)
        Assert.False(captureActive)
        Assert.False(IsObject(captureOwner))
        Assert.False(ownerDisabled)
        Assert.Equal(0, editor.restoreCalls)
        Assert.True(runtimeStillTracked)
        Assert.True(prompt.destroyed)
    }

    TestCapturedBindPublishesDirtyStateBeforeReleasingOwner() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        editor := {base: CapturePublicationOrderGUI.Prototype, events: []}

        try {
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            HotkeyManager.activeHotkeys := Map()
            Assert.True(editor.CaptureFunctionDialogState(
                prompt,
                "Sign Report",
                listView,
                1
            ))
            Assert.True(editor.BeginListening("Sign Report", listView, prompt))
            result := editor.OnInputEnd(
                "Sign Report",
                listView,
                prompt,
                KeybindGUI.activeInputHook
            )
        } finally {
            try editor.StopListening()
        }

        Assert.True(result)
        Assert.Equal(2, editor.events.Length)
        Assert.Equal("dirty", editor.events[1])
        Assert.Equal("release", editor.events[2])
    }

    TestCancelCaptureWarnsWhenPriorRuntimeCannotBeRestored() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        prompt := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        editor := {
            base: CaptureCancelRestoreFailingKeybindGUI.Prototype,
            restoreCalls: 0,
            notificationDriver: notifications
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.hotkeyFunctions := Map()
        HotkeyManager.activeHotkeys := Map()
        KeybindGUI.isListening := false
        KeybindGUI.activeInputHook := 0

        Assert.True(editor.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))
        Assert.True(editor.BeginListening("Sign Report", listView, prompt))
        result := editor.CancelKeybindPrompt(prompt)
        capturedListening := KeybindGUI.isListening

        Assert.False(result)
        Assert.False(capturedListening)
        ; The lease stays against clinical commands, marked as awaiting a restart.
        Assert.True(ExclusiveOperations.captureActive)
        Assert.True(ExclusiveOperations.captureRestartRequired)
        Assert.True(prompt.destroyed)
        Assert.Equal(1, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated cancel restore failure") > 0)
    }

    TestCancelCaptureRetainsTransactionWhenHookCannotStop() {
        profile := ProfileManager.NewProfile()
        prompt := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        hook := FailingCaptureHook("F13")
        editor := {
            base: StopFailureCancelGUI.Prototype,
            restoreCalls: 0,
            notificationDriver: notifications
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        KeybindGUI.isListening := true
        KeybindGUI.activeInputHook := hook
        KeybindGUI.captureRuntimeProfile := ProfileManager.CloneProfile(profile)
        ExclusiveOperations.captureActive := true

        result := editor.CancelKeybindPrompt(prompt)
        hookRetained := KeybindGUI.activeInputHook = hook
        listeningRetained := KeybindGUI.isListening
        transactionRetained := ExclusiveOperations.captureActive

        Assert.False(result)
        Assert.True(hookRetained)
        Assert.True(listeningRetained)
        Assert.True(transactionRetained)
        Assert.True(ExclusiveOperations.captureRestartRequired)
        Assert.False(prompt.destroyed)
        Assert.Equal(0, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "restart PACS Assistant") > 0)
    }

    TestOnInputEndRetainsCaptureWhenHookTeardownFails() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        editor := {
            base: OnEndStopFailureGUI.Prototype,
            notifications: [],
            restoreCalls: 0
        }
        threw := false
        caughtMessage := ""

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.activeHotkeys := Map()
        Assert.True(editor.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))
        Assert.True(editor.BeginListening("Sign Report", listView, prompt))
        hook := KeybindGUI.activeInputHook
        try editor.OnInputEnd("Sign Report", listView, prompt, hook)
        catch Any as err {
            threw := true
            caughtMessage := ErrorText.Message(err)
        }

        capturedHook := KeybindGUI.activeInputHook
        capturedListening := KeybindGUI.isListening
        capturedTransaction := ExclusiveOperations.captureActive
        capturedBind := profile.binds["Sign Report"]

        Assert.True(threw)
        Assert.True(InStr(caughtMessage, "simulated InputHook stop failure") > 0, caughtMessage)
        Assert.True(capturedHook == hook)
        Assert.True(capturedListening)
        Assert.True(capturedTransaction)
        Assert.Equal("^F13", capturedBind)
        Assert.False(prompt.destroyed)
        Assert.Equal(0, editor.restoreCalls)
        Assert.Equal(1, editor.notifications.Length)
        Assert.True(InStr(editor.notifications[1].message, "restart PACS Assistant") > 0)
    }

    TestModifierRestartFailureWarnsWhenPriorRuntimeCannotBeRestored() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        prompt := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        editor := {
            base: ModifierRestartRestoreFailingKeybindGUI.Prototype,
            startCalls: 0,
            restoreCalls: 0,
            notificationDriver: notifications
        }
        threw := false
        caughtMessage := ""

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.hotkeyFunctions := Map()
        HotkeyManager.activeHotkeys := Map()
        KeybindGUI.isListening := false
        KeybindGUI.activeInputHook := 0
        Assert.True(editor.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))
        Assert.True(editor.BeginListening("Sign Report", listView, prompt))

        try editor.OnInputEnd(
            "Sign Report",
            listView,
            prompt,
            FakeCaptureHook("LShift")
        )
        catch Any as err {
            threw := true
            caughtMessage := ErrorText.Message(err)
        }
        capturedListening := KeybindGUI.isListening

        Assert.True(threw)
        Assert.True(InStr(caughtMessage, "simulated modifier hook restart failure") > 0, caughtMessage)
        Assert.False(capturedListening)
        Assert.True(prompt.destroyed)
        Assert.Equal(2, editor.startCalls)
        Assert.Equal(1, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated modifier restore failure") > 0)
    }

    TestCaptureFailureRestoresBindingAndHookState() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^s"
        profile.scopes["Sign Report"] := "Any"
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        hook := FakeCaptureHook("F13")
        prompt := FakeProfileDialog()
        KeybindGUI.isListening := true
        listView := FailingListView()
        KeybindGUI.activeInputHook := hook
        Assert.True(this.gui.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))

        threw := false
        caughtMessage := ""
        try this.gui.OnInputEnd("Sign Report", listView, prompt, hook)
        catch Any as err {
            threw := true
            caughtMessage := ErrorText.Message(err)
        }

        capturedBind := profile.binds["Sign Report"]
        capturedListening := KeybindGUI.isListening
        capturedActiveHook := KeybindGUI.activeInputHook
        capturedStopped := hook.stopped
        capturedDestroyed := prompt.destroyed

        this.gui.StopListening()

        Assert.True(threw)
        Assert.True(InStr(caughtMessage, "simulated ListView failure") > 0, caughtMessage)
        Assert.Equal("^s", capturedBind)
        Assert.False(capturedListening)
        Assert.Equal(0, capturedActiveHook)
        Assert.True(capturedStopped)
        Assert.True(capturedDestroyed)
    }

    TestStaleKeyCaptureCannotReinsertRemovedFunction() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        prompt := FakeProfileDialog("Test")
        hook := FakeCaptureHook("F14")

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        Assert.True(this.gui.CaptureFunctionDialogState(
            prompt,
            "Sign Report",
            listView,
            1
        ))
        KeybindGUI.isListening := true
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

        Assert.False(result)
        Assert.True(bindStillAbsent)
        Assert.True(scopeStillAbsent)
        Assert.True(runtimeAbsent)
        Assert.Equal(0, rowCount)
        Assert.True(destroyed)
    }

    TestRejectedCapturedKeyRestoresPriorBinding() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        hook := FakeCaptureHook("DefinitelyNotARealKeyName")
        prompt := FakeProfileDialog()
        ; Stands in for AutoHotkey rejecting the key name; HotkeyManagerTest covers
        ; the native rejection itself.
        HotkeyManager.hotkeyDriver.failEnableCounts["DefinitelyNotARealKeyName"] := 1

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
            this.gui.StopListening()
        }

        Assert.Equal("^F13", capturedBind)
        Assert.Equal("^F13", capturedRuntimeBind)
        Assert.Equal("Ctrl + F13", capturedListBind)
        Assert.True(capturedDestroyed)
        Assert.True(capturedStopped)
    }

    TestRejectedScopeChangeRestoresPriorScope() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F14"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F14", "Any window")
        dialog := FakeProfileDialog()

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
        ; The scoped candidate fails to register; the restore that follows succeeds.
        HotkeyManager.hotkeyDriver.failEnableCounts["^F14"] := 1
        Assert.True(this.gui.CaptureFunctionDialogState(
            dialog,
            "Sign Report",
            listView,
            1
        ))

        this.gui.ApplyScope("Sign Report", true, false, listView, 1, dialog)
        capturedScope := profile.scopes["Sign Report"]
        capturedListScope := listView.GetText(1, 3)
        capturedDestroyed := dialog.destroyed

        Assert.Equal("Any", capturedScope)
        Assert.Equal("Any window", capturedListScope)
        Assert.False(capturedDestroyed)
    }

    TestStaleScopeDialogCannotModifyAReplacementRow() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.binds["Draft Report"] := "^F14"
        profile.scopes["Draft Report"] := "PowerScribe"
        listView := FunctionalListView("Sign Report", "Ctrl + F13", "Any window")
        listView.rows.Push(["Draft Report", "Ctrl + F14", "PowerScribe"])
        dialog := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        editor := {base: StaleScopeTrackingKeybindGUI.Prototype}
        editor.restoreCalls := 0
        editor.notificationDriver := notifications

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        Assert.True(editor.CaptureFunctionDialogState(
            dialog,
            "Sign Report",
            listView,
            1
        ))
        profile.binds.Delete("Sign Report")
        profile.scopes.Delete("Sign Report")
        listView.rows.RemoveAt(1)

        result := editor.ApplyScope(
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

        Assert.False(result)
        Assert.True(orphanScopeAbsent)
        Assert.Equal("Draft Report", remainingName)
        Assert.Equal("PowerScribe", remainingScope)
        Assert.True(destroyed)
        Assert.Equal(0, editor.restoreCalls)
    }

    TestFailedModalitySavePreservesLiveProfile() {
        this.PrepareBlockedProfileSave()
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Neuro"] := "Old Attending"
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        dialog := FakeProfileDialog()

        capturedLog := LogCapture()
        try {
            this.gui.SaveModalityAttendings(
                Map("Neuro", {Value: "New Attending"}),
                dialog
            )
            logged := capturedLog.Count("Attending assignments could not be saved: ")
        } finally capturedLog.Restore()
        savedValue := ProfileManager.profiles["Test"].modalityAttendings["Neuro"]
        destroyed := dialog.destroyed

        Assert.Equal("Old Attending", savedValue)
        Assert.False(destroyed)
        Assert.Equal(1, logged)
    }

    TestStaleModalityDialogCannotWriteAnotherProfile() {
        this.UseTempProfilesFolder()
        profileA := ProfileManager.NewProfile()
        profileA.modalityAttendings["Neuro"] := "A Attending"
        profileB := ProfileManager.NewProfile()
        profileB.modalityAttendings["Neuro"] := "B Attending"
        dialog := FakeProfileDialog("A")

        ProfileManager.profiles := Map("A", profileA, "B", profileB)
        ProfileManager.currentProfile := "B"
        this.gui.SaveModalityAttendings(
            Map("Neuro", {Value: "Stale Attending"}),
            dialog
        )
        capturedA := ProfileManager.profiles["A"].modalityAttendings["Neuro"]
        capturedB := ProfileManager.profiles["B"].modalityAttendings["Neuro"]
        capturedDestroyed := dialog.destroyed

        Assert.Equal("A Attending", capturedA)
        Assert.Equal("B Attending", capturedB)
        Assert.True(capturedDestroyed)
    }

    TestOlderModalityDialogCannotOverwriteNewerSave() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.modalityAttendings["Neuro"] := "Old Attending"

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        ProfileManager.SaveProfile("Test", profile)
        editor := {base: LiveDialogIdentityGUI.Prototype, gui: ""}
        staleDialog := ProfileBoundFakeDialog("Test")
        newerDialog := ProfileBoundFakeDialog("Test")

        Assert.True(editor.SaveModalityAttendings(
            Map("Neuro", {Value: "New Attending"}),
            newerDialog
        ))
        Assert.False(editor.SaveModalityAttendings(
            Map("Neuro", {Value: "Stale Attending"}),
            staleDialog
        ))

        captured := ProfileManager.profiles["Test"].modalityAttendings["Neuro"]
        capturedDestroyed := staleDialog.destroyed

        Assert.Equal("New Attending", captured)
        Assert.True(capturedDestroyed)
    }

    TestDirtyKeybindMutationInvalidatesModalityDialog() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.modalityAttendings["Neuro"] := "Old Attending"

        ProfileManager.profiles := Map("Test", profile)
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

        Assert.False(result)
        Assert.Equal("Any", storedScope)
        Assert.Equal("Old Attending", storedAttending)
        Assert.Equal("PACS", memoryScope)
        Assert.Equal("Old Attending", memoryAttending)
        Assert.True(dirty)
        Assert.True(dialog.destroyed)
    }

    TestPreexistingDirtyProfileBlocksModalityDialog() {
        profile := ProfileManager.NewProfile()
        editor := {
            base: DirtyPersistentOperationGUI.Prototype,
            dialogCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Cancel")
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        editor.MarkProfileDirty("Test")
        result := editor.ShowModalityAttendingsDialog()
        dirty := editor.IsProfileDirty("Test")

        Assert.False(result)
        Assert.True(dirty)
        Assert.Equal(0, editor.dialogCalls)
    }

    TestPreexistingDirtyProfileBlocksCustomDeletion() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        profile.binds["Custom: Keep"] := ""
        profile.scopes["Custom: Keep"] := "Any"
        selector := FakeProfileDialog("Test")
        editor := {base: DirtyPersistentOperationGUI.Prototype, dialogCalls: 0}
        editor.confirmationDriver := AlwaysConfirmDriver()

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        ProfileManager.SaveProfile("Test", profile)

        profile.scopes["Sign Report"] := "PACS"
        editor.MarkProfileDirty("Test")
        result := editor.DeleteCustomFunction("Custom: Keep", selector)
        stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
        storedScope := stored.scopes["Sign Report"]
        storedCustom := stored.customFuncs.Has("Custom: Keep")
        memoryScope := profile.scopes["Sign Report"]
        memoryCustom := profile.customFuncs.Has("Custom: Keep")
        dirty := editor.IsProfileDirty("Test")

        Assert.False(result)
        Assert.Equal("Any", storedScope)
        Assert.True(storedCustom)
        Assert.Equal("PACS", memoryScope)
        Assert.True(memoryCustom)
        Assert.True(dirty)
        Assert.True(selector.destroyed)
    }

    TestDiscardBeforeAddFunctionRequiresFreshMainWindowControl() {
        editor := {
            base: DirtyAddFunctionTestGUI.Prototype,
            gui: {},
            rebuildsWindow: true,
            resolveCalls: 0,
            dialogCalls: 0,
            notices: 0
        }

        result := editor.ShowAddFunctionDialog({destroyed: true})

        Assert.False(result)
        Assert.Equal(1, editor.resolveCalls)
        Assert.Equal(0, editor.dialogCalls)
        Assert.Equal(1, editor.notices)
    }

    TestSaveBeforeAddFunctionOpensTheDialog() {
        ; Save keeps the main window, so its ListView is still the live one.
        editor := {
            base: DirtyAddFunctionTestGUI.Prototype,
            gui: {},
            rebuildsWindow: false,
            resolveCalls: 0,
            dialogCalls: 0,
            notices: 0
        }

        Assert.Throws(ObjBindMethod(editor, "ShowAddFunctionDialog", {}), "dialog reached")

        Assert.Equal(1, editor.resolveCalls)
        Assert.Equal(1, editor.dialogCalls)
        Assert.Equal(0, editor.notices)
    }

    ; A main-window rename dialog captured for one profile is otherwise intact here;
    ; once another profile is current its OK must not rename the captured one.
    TestStaleRenameDialogCannotRenameAnotherProfile() {
        this.UseTempProfilesFolder()
        profileA := ProfileManager.NewProfile()
        profileB := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("A")
        editor := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        editor.createCalls := 0
        editor.applyCalls := 0
        editor.gui := FakeProfileDialog()

        ProfileManager.defaultProfile := ""
        ProfileManager.profiles := Map("A", profileA, "B", profileB)
        ProfileManager.currentProfile := "A"
        ProfileManager.SaveProfile("A", profileA)
        Assert.True(editor.CaptureRenameDialogState(dialog, "A"))
        ProfileManager.currentProfile := "B"
        result := editor.RenameProfile("A", "Renamed", dialog)

        Assert.False(result)
        Assert.True(ProfileManager.profiles.Has("A"))
        Assert.True(ProfileManager.profiles.Has("B"))
        Assert.False(ProfileManager.profiles.Has("Renamed"))
        Assert.True(dialog.destroyed)
        Assert.Equal(0, editor.createCalls)
    }

    ; An invalid new name is reported as invalid, not as possibly in use, and
    ; nothing is renamed.
    TestRenameToAnInvalidNameSaysTheNameIsInvalid() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        editor := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        editor.createCalls := 0
        editor.applyCalls := 0
        editor.gui := FakeProfileDialog()
        ProfileManager.profiles := Map("Night", profile)
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)

        for invalidName in ["Night/Call", "CON", "Night."] {
            dialog := FakeProfileDialog("Night")
            Assert.True(editor.CaptureRenameDialogState(dialog, "Night"))
            Assert.False(editor.RenameProfile("Night", invalidName, dialog), invalidName)
            Assert.Equal("Invalid Profile Name", TestRunner.dialogs[-1].title, invalidName)
            Assert.True(ProfileManager.profiles.Has("Night"), invalidName)
        }
        Assert.Equal(0, editor.createCalls)
    }

    ; An edit made in place while the rename dialog was open (capture, Add Function,
    ; scope) keeps the profile object and revision; renaming would clear that
    ; unsaved edit, so the dialog is refused instead.
    TestRenameDialogRefusesAProfileEditedSinceItOpened() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        editor := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        editor.createCalls := 0
        editor.applyCalls := 0
        editor.gui := FakeProfileDialog()
        ProfileManager.profiles := Map("Night", profile)
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)
        dialog := FakeProfileDialog("Night")
        Assert.True(editor.CaptureRenameDialogState(dialog, "Night"))

        profile.binds["Sign Report"] := "^F13"
        editor.MarkProfileDirty("Night")
        result := editor.RenameProfile("Night", "Day", dialog)

        Assert.False(result)
        Assert.True(ProfileManager.profiles.Has("Night"))
        Assert.False(ProfileManager.profiles.Has("Day"))
        Assert.True(editor.IsProfileDirty("Night"))
    }

    ; With no lease held, as at startup, ApplyBinds takes the profile lease for its
    ; own work and releases it, so clinical commands can run afterwards.
    TestApplyBindsReleasesTheLeaseItTook() {
        editor := {base: KeybindGUI.Prototype, gui: ""}
        HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        PACSCommands.commandAvailabilityProbe := (*) => ExclusiveOperations.Active("clinical") = ""

        Assert.True(editor.ApplyBinds())
        Assert.True(HotkeyManager.activeHotkeys.Has("Sign Report"))
        Assert.Equal("", ExclusiveOperations.Active())
        lease := PACSCommands.AcquireClinicalAutomation("Sign Report")
        PACSCommands.ReleaseClinicalAutomation()
        Assert.Equal("acquired", lease.status)
    }

    ; A discard whose saved profile cannot be reloaded keeps the changes, says so,
    ; and leaves the reason in error.log.
    TestFailedDiscardReloadIsReportedAndLogged() {
        this.UseTempProfilesFolder()
        notifications := []
        editor := {base: KeybindGUI.Prototype, gui: "", profileLeaveDriver: FixedProfileLeaveDriver("No")}
        editor.notificationDriver := ArrayNotificationDriver(notifications)
        ; Never saved, so there is no file to reload.
        ProfileManager.profiles := Map("Test", ProfileManager.NewProfile())
        ProfileManager.currentProfile := "Test"
        editor.MarkProfileDirty("Test")

        capturedLog := LogCapture()
        try {
            result := editor.ResolveDirtyProfileBeforeLeaving()
            logged := capturedLog.Count("Saved profile 'Test' could not be reloaded to discard changes: ")
        } finally capturedLog.Restore()

        Assert.False(result)
        Assert.True(editor.IsProfileDirty("Test"))
        Assert.Equal(1, notifications.Length)
        Assert.Equal("Discard Failed", notifications[1].title)
        Assert.Equal(1, logged)
    }

    TestDestroyedRenameDialogCannotMutateProfile() {
        profile := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("Old")
        editor := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        editor.createCalls := 0
        editor.applyCalls := 0

        ProfileManager.profiles := Map("Old", profile)
        ProfileManager.currentProfile := "Old"
        Assert.True(editor.CaptureRenameDialogState(dialog, "Old"))
        dialog.Destroy()
        result := editor.RenameProfile("Old", "New", dialog)
        keptOld := ProfileManager.profiles.Has("Old")

        Assert.False(result)
        Assert.True(keptOld)
        Assert.Equal(0, editor.createCalls)
    }

    TestRenameDialogCannotMutateSameNameReplacement() {
        originalProfile := ProfileManager.NewProfile()
        replacement := ProfileManager.NewProfile()
        replacement.modalityAttendings["Marker"] := "replacement"
        dialog := FakeProfileDialog("Old")
        editor := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        editor.createCalls := 0
        editor.applyCalls := 0

        ProfileManager.profileRevisions := Map("Old", 1)
        ProfileManager.profiles := Map("Old", originalProfile)
        ProfileManager.currentProfile := "Old"
        Assert.True(editor.CaptureRenameDialogState(dialog, "Old"))
        ProfileManager.profiles["Old"] := replacement
        ProfileManager.profileRevisions["Old"] := 2
        result := editor.RenameProfile("Old", "New", dialog)
        keptReplacement := ProfileManager.profiles.Has("Old")
            && ProfileManager.profiles["Old"] = replacement

        Assert.False(result)
        Assert.True(keptReplacement)
        Assert.Equal(0, editor.createCalls)
    }

    TestRenamePromptHonorsDirtyCancel() {
        profile := ProfileManager.NewProfile()
        editor := {
            base: DirtyRenameTestGUI.Prototype,
            dialogCreateCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Cancel")
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        editor.MarkProfileDirty("Test")
        result := editor.PromptRenameProfile("Test")

        Assert.False(result)
        Assert.True(editor.IsProfileDirty("Test"))
        Assert.Equal(0, editor.dialogCreateCalls)
    }

    TestCaseOnlyRenamePersistsResolvedDirtyChanges() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        dialog := FakeProfileDialog("Night")
        editor := {
            base: DirtyRenameTestGUI.Prototype,
            createCalls: 0,
            applyCalls: 0,
            dialogCreateCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Yes")
        }
        editor.gui := FakeProfileDialog()

        ProfileManager.profiles := Map("Night", profile)
        ProfileManager.currentProfile := "Night"
        ProfileManager.SaveProfile("Night", profile)
        profile.scopes["Sign Report"] := "PACS"
        editor.MarkProfileDirty("Night")

        Assert.True(editor.ResolveDirtyProfileBeforeLeaving())
        Assert.True(editor.CaptureRenameDialogState(dialog, "Night"))
        Assert.True(editor.RenameProfile("Night", "night", dialog))
        reloaded := ProfileManager.LoadProfile(ProfileManager.ProfilePath("night"))
        persistedScope := reloaded.scopes["Sign Report"]

        Assert.Equal("PACS", persistedScope)
        Assert.False(editor.IsProfileDirty("Night"))
        Assert.False(editor.IsProfileDirty("night"))
    }

    TestSaveChoiceRejectsProfileChangedDuringDirtyPrompt() {
        this.UseTempProfilesFolder()
        prompted := ProfileManager.NewProfile()
        prompted.binds["Sign Report"] := "^F13"
        prompted.scopes["Sign Report"] := "Any"
        replacement := ProfileManager.NewProfile()
        replacement.binds["Draft Report"] := "^F14"
        replacement.scopes["Draft Report"] := "Any"
        editor := {
            base: DirtyLeaveTestGUI.Prototype,
            profileLeaveDriver: CallbackProfileLeaveDriver(
                "Yes",
                (*) => ProfileManager.currentProfile := "Replacement"
            )
        }

        ProfileManager.profileRevisions := Map("Prompted", 0, "Replacement", 0)
        ProfileManager.profiles := Map("Prompted", prompted, "Replacement", replacement)
        ProfileManager.currentProfile := "Prompted"
        ProfileManager.SaveProfile("Prompted", prompted)
        editor.MarkProfileDirty("Prompted")

        result := editor.ResolveDirtyProfileBeforeLeaving()
        replacementWasSaved := FileExist(ProfileManager.ProfilePath("Replacement")) != ""
        promptedRemainsDirty := editor.IsProfileDirty("Prompted")

        Assert.False(result)
        Assert.False(replacementWasSaved)
        Assert.True(promptedRemainsDirty)
    }

    TestDiscardBeforeRenameRestoresRuntimeAndMainView() {
        state := this.PrepareDiscardRenameState()
        editor := state.gui

        resolved := editor.ResolveDirtyProfileBeforeLeaving(true)
        memoryBind := ProfileManager.profiles["Night"].binds["Sign Report"]
        memoryScope := ProfileManager.profiles["Night"].scopes["Sign Report"]
        runtimeBind := HotkeyManager.activeHotkeys["Sign Report"].hotkey
        runtimeScope := HotkeyManager.activeHotkeys["Sign Report"].scope

        Assert.True(resolved)
        Assert.Equal("^F13", memoryBind)
        Assert.Equal("Any", memoryScope)
        Assert.Equal("^F13", runtimeBind)
        Assert.Equal("Any", runtimeScope)
        Assert.Equal("^F13", editor.visibleBind)
        Assert.Equal("Any", editor.visibleScope)
        Assert.Equal(1, editor.createCalls)
        Assert.False(editor.lastCreateAppliedBinds)
        Assert.False(editor.IsProfileDirty("Night"))
    }

    TestDiscardBeforeCaseRenameKeepsStoredRuntime() {
        state := this.PrepareDiscardRenameState()
        editor := state.gui
        dialog := FakeProfileDialog("Night")

        Assert.True(editor.ResolveDirtyProfileBeforeLeaving(true))
        Assert.True(editor.CaptureRenameDialogState(dialog, "Night"))
        renamed := editor.RenameProfile("Night", "night", dialog)
        reloaded := ProfileManager.LoadProfile(ProfileManager.ProfilePath("night"))
        persistedBind := reloaded.binds["Sign Report"]
        persistedScope := reloaded.scopes["Sign Report"]
        runtimeBind := HotkeyManager.activeHotkeys["Sign Report"].hotkey
        runtimeScope := HotkeyManager.activeHotkeys["Sign Report"].scope

        Assert.True(renamed)
        Assert.Equal("^F13", persistedBind)
        Assert.Equal("Any", persistedScope)
        Assert.Equal("^F13", runtimeBind)
        Assert.Equal("Any", runtimeScope)
        Assert.Equal("^F13", editor.visibleBind)
        Assert.Equal("Any", editor.visibleScope)
        Assert.False(editor.IsProfileDirty("Night"))
        Assert.False(editor.IsProfileDirty("night"))
    }

    TestDefaultProfileSelectionRequiresExactRenderedName() {
        Assert.Equal(2, this.gui.DefaultProfileListIndex(["AA *", "A *"], "A"))
        Assert.Equal(1, this.gui.DefaultProfileListIndex(["A *", "AA *"], "A"))
        Assert.Equal(0, this.gui.DefaultProfileListIndex(["AA *"], "A"))
    }

    TestSuccessfulMainRenameDoesNotReapplyHotkeys() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        dialog := FakeProfileDialog("Old")
        editor := {base: RenameRuntimeTrackingKeybindGUI.Prototype}
        editor.gui := FakeProfileDialog()
        editor.createCalls := 0
        editor.applyCalls := 0

        ProfileManager.defaultProfile := ""
        ProfileManager.profiles := Map("Old", profile)
        ProfileManager.currentProfile := "Old"
        ProfileManager.SaveProfile("Old", profile)
        Assert.True(editor.CaptureRenameDialogState(dialog, "Old"))

        result := editor.RenameProfile("Old", "New", dialog)

        Assert.True(result)
        Assert.Equal(1, editor.createCalls)
        Assert.Equal(0, editor.applyCalls)
    }

    TestCreateProfileSurfacesStorageRecovery() {
        notifications := CapturingNotificationDriver()
        editor := {base: ProfileSelectorTransactionGUI.Prototype, notificationDriver: notifications}
        dialog := FakeProfileDialog()

        ProfileManager.recoveryRequired := true
        ProfileManager.recoveryCause := "simulated profile storage uncertainty"
        result := editor.CreateProfile("New Profile", dialog)

        Assert.False(result)
        Assert.True(InStr(notifications.message, "simulated profile storage uncertainty") > 0)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.False(dialog.destroyed)
    }

    TestDirtyScopeEditBlocksProfileSwitchWhenCancelled() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Unassigned", "Any window")
        dialog := FakeProfileDialog("Test")
        editor := {
            base: DirtyLeaveTestGUI.Prototype,
            prepareCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Cancel")
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        Assert.True(editor.CaptureFunctionDialogState(dialog, "Sign Report", listView, 1))
        Assert.True(editor.ApplyScope("Sign Report", true, false, listView, 1, dialog))
        switchResult := editor.OpenProfileSelector()
        dirty := editor.IsProfileDirty("Test")

        Assert.False(switchResult)
        Assert.True(dirty)
        Assert.Equal(0, editor.prepareCalls)
        Assert.Equal(0, editor.selectorCalls)
    }

    TestClosingSavesDirtyProfileBeforeExit() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        editor := {
            base: DirtyLeaveTestGUI.Prototype,
            prepareCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("Yes")
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        ProfileManager.SaveProfile("Test", profile)
        profile.scopes["Sign Report"] := "PACS"
        editor.MarkProfileDirty("Test")

        result := editor.RequestExit()
        stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
        persistedScope := stored.scopes["Sign Report"]
        dirty := editor.IsProfileDirty("Test")

        Assert.True(result)
        Assert.Equal("PACS", persistedScope)
        Assert.False(dirty)
        Assert.Equal(1, editor.exitCalls)
    }

    ; A held shutdown lease blocks every clinical command until restart, so it must be
    ; released whatever escapes the dirty-profile prompt, a non-Error value included.
    TestShutdownLeaseIsReleasedWhenTheDirtyPromptThrowsANonError() {
        editor := {base: NonErrorDirtyPromptGUI.Prototype, gui: ""}

        threw := false
        try editor.BeginShutdown("close PACS Assistant")
        catch Any
            threw := true

        Assert.True(threw)
        Assert.False(ExclusiveOperations.shutdownActive)
        Assert.Equal("", ExclusiveOperations.Active())
    }

    ; The profile-mutation lease refuses clinical commands, so a modal notice shown
    ; under it would keep them refused until the user dismissed it.
    TestNoticesUnderTheProfileLeaseWaitForItsRelease() {
        notifications := LeaseObservingNotificationDriver()
        editor := {base: KeybindGUI.Prototype, gui: "", notificationDriver: notifications}

        Assert.True(editor.BeginProfileMutationTransaction("save the profile"))
        editor.NotifyUser("first", "Save Failed", "Icon!")
        editor.NotifyUser("second", "Keybind Errors", "Icon!")
        Assert.Equal(0, notifications.calls.Length)

        editor.EndProfileMutationTransaction()
        Assert.Equal(2, notifications.calls.Length)
        Assert.Equal("first", notifications.calls[1].message)
        Assert.Equal("second", notifications.calls[2].message)
        Assert.False(notifications.calls[1].leaseHeld)
        Assert.Equal(0, KeybindGUI.deferredNotices.Length)

        ; Without the lease a notice shows at once.
        editor.NotifyUser("third", "Profile Changed", "Icon!")
        Assert.Equal(3, notifications.calls.Length)
    }

    ; RemoveFunction and DeleteCustomFunction call ApplyProfileCandidate under the
    ; profile-mutation lease.
    TestCancelledCandidateNoticeWaitsForTheLeaseAndIsLogged() {
        notifications := LeaseObservingNotificationDriver()
        editor := {base: KeybindGUI.Prototype, gui: "", notificationDriver: notifications}
        HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
        candidate := ProfileManager.NewProfile()
        candidate.binds["Sign Report"] := "^F13"
        candidate.scopes["Sign Report"] := "Nowhere"

        capturedLog := LogCapture()
        try {
            Assert.True(editor.BeginProfileMutationTransaction("remove a function"))
            Assert.False(editor.ApplyProfileCandidate(candidate, ProfileManager.NewProfile(), "function removal"))
            shownUnderLease := notifications.calls.Length
            editor.EndProfileMutationTransaction()
            logged := capturedLog.Count("Keybinds failed to register: Sign Report (")
        } finally capturedLog.Restore()

        Assert.Equal(0, shownUnderLease)
        Assert.Equal(1, notifications.calls.Length)
        Assert.False(notifications.calls[1].leaseHeld)
        Assert.True(InStr(notifications.calls[1].message, "function removal was not applied"), notifications.calls[1].message)
        ; Names the bind that failed, not only the last registration's reason.
        Assert.True(InStr(notifications.calls[1].message, "Sign Report (the hotkey scope is unknown)"), notifications.calls[1].message)
        Assert.Equal(1, logged)
    }

    TestUnstoppableCaptureHookIsLogged() {
        KeybindGUI.activeInputHook := FailingCaptureHook("F13")
        KeybindGUI.isListening := true

        capturedLog := LogCapture()
        try {
            Assert.Throws(ObjBindMethod(this.gui, "StopListening"), "Input capture could not be stopped")
            logged := capturedLog.Count("Key capture could not be stopped: Error: simulated InputHook stop failure")
        } finally capturedLog.Restore()

        Assert.Equal(1, logged)
    }

    TestProfileSwitchCanDiscardDirtyChanges() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := ""
        profile.scopes["Sign Report"] := "Any"
        editor := {
            base: DirtyLeaveTestGUI.Prototype,
            prepareCalls: 0,
            selectorCalls: 0,
            exitCalls: 0,
            profileLeaveDriver: FixedProfileLeaveDriver("No")
        }

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        ProfileManager.SaveProfile("Test", profile)
        profile.scopes["Sign Report"] := "PACS"
        editor.MarkProfileDirty("Test")

        result := editor.OpenProfileSelector()
        restoredScope := ProfileManager.profiles["Test"].scopes["Sign Report"]
        dirty := editor.IsProfileDirty("Test")

        Assert.True(result)
        Assert.Equal("Any", restoredScope)
        Assert.False(dirty)
        Assert.Equal(1, editor.prepareCalls)
        Assert.Equal(1, editor.selectorCalls)
    }

    TestFailedCustomDeletePreservesLiveProfile() {
        this.PrepareBlockedProfileSave()
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Keep"] := "^k"
        profile.scopes["Custom: Keep"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "HELLO", window: ""}
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        dialog := FakeProfileDialog()
        threw := false

        capturedLog := LogCapture()
        try {
            try this.gui.DeleteCustomFunction("Custom: Keep", dialog)
            catch Any {
                threw := true
            }
            logged := capturedLog.Count("Custom function deletion could not be saved: ")
        } finally capturedLog.Restore()
        stillConfigured := ProfileManager.profiles["Test"].customFuncs.Has("Custom: Keep")
        stillBound := ProfileManager.profiles["Test"].binds.Has("Custom: Keep")
        destroyed := dialog.destroyed

        Assert.False(threw)
        Assert.Equal(1, logged)
        Assert.True(stillConfigured)
        Assert.True(stillBound)
        Assert.False(destroyed)
    }

    TestRemoveFunctionKeepsProfileAndRowWhenNativeOffFails() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F23", "Any window")
        driver := TransactionalHotkeyDriver()
        driver.failDisable["^F23"] := true
        threw := false

        try {
            HotkeyManager.activeHotkeys.Clear()
            HotkeyManager.hotkeyDriver := driver
            HotkeyManager.hotkeyFunctions := Map("Sign Report", (*) => 0)
            HotkeyManager.activeHotkeys["Sign Report"] := {hotkey: "^F23", scope: "Any"}
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"

            try result := this.gui.RemoveFunction(listView)
            catch Any {
                threw := true
                result := false
            }
            keptBind := profile.binds.Has("Sign Report") ? profile.binds["Sign Report"] : ""
            keptScope := profile.scopes.Has("Sign Report") ? profile.scopes["Sign Report"] : ""
            keptRow := listView.GetCount()
            tracked := HotkeyManager.activeHotkeys.Has("Sign Report")
        } finally {
            driver.failDisable.Clear()
            HotkeyManager.activeHotkeys.Clear()
        }

        Assert.False(threw)
        Assert.False(result)
        Assert.Equal("^F23", keptBind)
        Assert.Equal("Any", keptScope)
        Assert.Equal(1, keptRow)
        Assert.True(tracked)
    }

    TestCustomDeleteRollsBackWhenLaterRegistrationFails() {
        tempRoot := this.UseTempProfilesFolder()
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
            ProfileManager.profiles := Map("Test", profile)
            ProfileManager.currentProfile := "Test"
            ProfileManager.SaveProfile("Test", profile)
            HotkeyManager.activeHotkeys.Clear()
            HotkeyManager.hotkeyDriver := driver
            HotkeyManager.hotkeyFunctions := PACSCommands.commands
            HotkeyManager.activeHotkeys["Custom: Keep"] := {hotkey: "^F23", scope: "Any"}
            HotkeyManager.activeHotkeys["Draft Report"] := {hotkey: "^F24", scope: "Any"}

            try result := this.gui.DeleteCustomFunction("Custom: Keep", dialog)
            catch Any {
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
            HotkeyManager.activeHotkeys.Clear()
        }

        Assert.False(threw)
        Assert.False(result)
        Assert.True(liveKept)
        Assert.True(storedKept)
        Assert.True(runtimeKept)
        Assert.True(dialogKept)
    }

    TestStaleRemoveConfirmationCannotDeleteReplacementRow() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        profile.binds["Draft Report"] := "^F24"
        profile.scopes["Draft Report"] := "Any"
        listView := RemovableListView("Sign Report", "Ctrl + F23", "Any window")
        editor := {base: PassiveRuntimeKeybindGUI.Prototype}
        editor.applyCalls := 0
        editor.confirmationDriver := RemoveRaceConfirmationDriver(profile, listView)

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        result := editor.RemoveFunction(listView)
        liveProfile := ProfileManager.profiles["Test"]
        keptSign := liveProfile.binds.Has("Sign Report")
            && liveProfile.binds["Sign Report"] == "^F22"
        keptDraft := liveProfile.binds.Has("Draft Report")
        rowOne := listView.GetText(1, 1)
        rowTwo := listView.GetText(2, 1)

        Assert.False(result)
        Assert.True(keptSign)
        Assert.True(keptDraft)
        Assert.Equal("Draft Report", rowOne)
        Assert.Equal("Sign Report", rowTwo)
        Assert.Equal(0, editor.applyCalls)
    }

    TestStaleCustomDeleteCannotDeleteRecreatedCommand() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Keep"] := "^F23"
        profile.scopes["Custom: Keep"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "OLD", window: ""}
        dialog := FakeProfileDialog("Test")
        editor := {base: PassiveRuntimeKeybindGUI.Prototype, gui: ""}
        editor.applyCalls := 0
        editor.confirmationDriver := RecreateCustomConfirmationDriver(profile)
        threw := false

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        try result := editor.DeleteCustomFunction("Custom: Keep", dialog)
        catch Any {
            threw := true
            result := false
        }
        liveProfile := ProfileManager.profiles["Test"]
        keptRecreated := liveProfile.customFuncs.Has("Custom: Keep")
            && liveProfile.customFuncs["Custom: Keep"].keys == "NEW"
            && liveProfile.binds.Has("Custom: Keep")
            && liveProfile.binds["Custom: Keep"] == "^F22"

        Assert.False(result)
        Assert.False(threw)
        Assert.True(keptRecreated)
        Assert.Equal(0, editor.applyCalls)
    }

    TestCustomDeleteRejectsConcurrentUnrelatedDirtyEdit() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Custom: Keep"] := "^F23"
        profile.scopes["Custom: Keep"] := "Any"
        profile.customFuncs["Custom: Keep"] := {keys: "OLD", window: ""}
        profile.binds["Sign Report"] := "^F12"
        profile.scopes["Sign Report"] := "Any"
        dialog := FakeProfileDialog("Test")
        editor := {base: PassiveRuntimeKeybindGUI.Prototype, gui: ""}
        editor.applyCalls := 0
        editor.confirmationDriver := DirtyOtherBindConfirmationDriver(editor, profile)

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        ProfileManager.SaveProfile("Test", profile)

        result := editor.DeleteCustomFunction("Custom: Keep", dialog)
        stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
        liveKept := profile.customFuncs.Has("Custom: Keep")
        storedKept := stored.customFuncs.Has("Custom: Keep")
        storedScope := stored.scopes["Sign Report"]
        dirtyKept := editor.IsProfileDirty("Test")

        Assert.False(result)
        Assert.True(liveKept)
        Assert.True(storedKept)
        Assert.Equal("Any", storedScope)
        Assert.True(dirtyKept)
        Assert.Equal(0, editor.applyCalls)
    }

    TestRowDeleteAndRuntimeRestoreFailureRequiresRestartWarning() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := ThrowingDeleteListView("Sign Report", "Ctrl + F23", "Any window")
        notifications := CapturingNotificationDriver()
        editor := {base: FailedRestoreKeybindGUI.Prototype}
        editor.applyCalls := 0
        editor.confirmationDriver := AlwaysConfirmDriver()
        editor.notificationDriver := notifications

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        result := editor.RemoveFunction(listView)
        keptBind := ProfileManager.profiles["Test"].binds.Has("Sign Report")

        Assert.False(result)
        Assert.True(keptBind)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated restore failure") > 0)
    }

    TestRejectedKeybindWarnsWhenPriorRuntimeCannotBeRestored() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F23", "Any window")
        prompt := FakeProfileDialog("Test")
        hook := FakeCaptureHook("F24")
        notifications := CapturingNotificationDriver()
        editor := {base: RollbackFailingKeybindGUI.Prototype}
        editor.applyCalls := 0
        editor.restoreCalls := 0
        editor.notificationDriver := notifications

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        Assert.True(editor.CaptureFunctionDialogState(prompt, "Sign Report", listView, 1))
        KeybindGUI.isListening := true
        KeybindGUI.activeInputHook := hook

        result := editor.OnInputEnd("Sign Report", listView, prompt, hook)
        keptBind := profile.binds["Sign Report"]
        keptRow := listView.GetText(1, 2)

        Assert.False(result)
        Assert.Equal("^F23", keptBind)
        Assert.Equal("Ctrl + F23", keptRow)
        Assert.Equal(1, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated restore failure") > 0)
    }

    TestRejectedScopeWarnsWhenPriorRuntimeCannotBeRestored() {
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F23"
        profile.scopes["Sign Report"] := "Any"
        listView := FunctionalListView("Sign Report", "Ctrl + F23", "Any window")
        dialog := FakeProfileDialog("Test")
        notifications := CapturingNotificationDriver()
        editor := {base: RollbackFailingKeybindGUI.Prototype}
        editor.applyCalls := 0
        editor.restoreCalls := 0
        editor.notificationDriver := notifications

        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        Assert.True(editor.CaptureFunctionDialogState(dialog, "Sign Report", listView, 1))
        result := editor.ApplyScope("Sign Report", true, false, listView, 1, dialog)
        keptScope := profile.scopes["Sign Report"]
        keptRow := listView.GetText(1, 3)

        Assert.False(result)
        Assert.Equal("Any", keptScope)
        Assert.Equal("Any window", keptRow)
        Assert.Equal(1, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "simulated restore failure") > 0)
    }

    TestSavedProfileFailsWhenRuntimeCannotBeVerified() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        notifications := CapturingNotificationDriver()
        editor := {
            base: SaveRuntimeFailingKeybindGUI.Prototype,
            applyCalls: 0,
            restoreCalls: 0,
            notificationDriver: notifications
        }

        ProfileManager.profileRevisions := Map("Test", 0)
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"

        result := editor.SaveCurrentProfile()
        stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
        storedBind := stored.binds["Sign Report"]

        Assert.False(result)
        Assert.Equal("^F13", storedBind)
        Assert.Equal(1, editor.applyCalls)
        Assert.Equal(1, editor.restoreCalls)
        Assert.True(InStr(notifications.message, "profile was saved") > 0)
        Assert.True(InStr(notifications.message, "Restart PACS Assistant") > 0)
        Assert.True(InStr(notifications.message, "Sign Report (simulated registration failure)") > 0)
        Assert.True(InStr(notifications.message, "simulated saved-profile restore failure") > 0)
    }

    TestConcurrentMutationDuringSaveRemainsDirtyAndRestoresNewRuntime() {
        this.UseTempProfilesFolder()
        profile := ProfileManager.NewProfile()
        profile.binds["Sign Report"] := "^F13"
        profile.scopes["Sign Report"] := "Any"
        notifications := CapturingNotificationDriver()
        editor := {
            base: ConcurrentSaveMutationGUI.Prototype,
            applyCalls: 0,
            restoreCalls: 0,
            restoredAttending: "",
            notificationDriver: notifications
        }

        ProfileManager.profileRevisions := Map("Test", 0)
        ProfileManager.profiles := Map("Test", profile)
        ProfileManager.currentProfile := "Test"
        editor.MarkProfileDirty("Test")

        result := editor.SaveCurrentProfile()
        stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath("Test"))
        storedHasConcurrent := stored.modalityAttendings.Has("Concurrent")
        memoryValue := profile.modalityAttendings["Concurrent"]
        dirty := editor.IsProfileDirty("Test")
        transactionReleased := !ExclusiveOperations.profileMutationActive

        Assert.False(result)
        Assert.False(storedHasConcurrent)
        Assert.Equal("New Attending", memoryValue)
        Assert.True(dirty)
        Assert.Equal(1, editor.applyCalls)
        Assert.Equal(1, editor.restoreCalls)
        Assert.Equal("New Attending", editor.restoredAttending)
        Assert.True(transactionReleased)
        Assert.True(InStr(notifications.message, "newer edits remain unsaved") > 0)
    }

    TestClinicalCommandCannotInterruptProfileApply() {
        originalNotifier := PACSCommands.busyNotifier
        notifications := []
        callbackCalls := 0
        editor := {base: InterruptingProfileApplyGUI.Prototype}
        editor.callback := (*) => callbackCalls++
        ; The same clinical-entry check main.ahk installs
        PACSCommands.commandAvailabilityProbe := (*) => ExclusiveOperations.Active("clinical") = ""
        PACSCommands.busyNotifier := (text, title, options) => notifications.Push(text)

        try {
            Assert.True(editor.BeginProfileMutationTransaction("test profile apply"))
            Assert.True(editor.ApplyProfileBinds(ProfileManager.NewProfile(), false))
            result := editor.commandResult
        } finally {
            editor.EndProfileMutationTransaction()
            PACSCommands.busyNotifier := originalNotifier
        }

        Assert.False(result)
        Assert.Equal(0, callbackCalls)
        Assert.Equal(1, notifications.Length)
    }

    TestStaleProfileDeleteCannotDeleteRecreatedProfile() {
        this.UseTempProfilesFolder()
        oldProfile := ProfileManager.NewProfile()
        otherProfile := ProfileManager.NewProfile()
        selector := FakeProfileDialog()
        editor := {base: ProfileDeleteTestGUI.Prototype}

        ProfileManager.profiles := Map("A", oldProfile, "B", otherProfile)
        ProfileManager.currentProfile := "B"
        ProfileManager.defaultProfile := ""
        ProfileManager.SaveProfile("A", oldProfile)
        ProfileManager.SaveProfile("B", otherProfile)
        editor.confirmationDriver := RecreateProfileConfirmationDriver("A")
        editor.RegisterProfileSelector(selector)

        result := editor.DeleteProfile("A", selector)
        keptReplacement := ProfileManager.profiles.Has("A")
            && ProfileManager.profiles["A"].modalityAttendings.Has("Marker")
            && ProfileManager.profiles["A"].modalityAttendings["Marker"] == "replacement"
        keptFile := FileExist(ProfileManager.ProfilePath("A")) != ""

        Assert.False(result)
        Assert.True(keptReplacement)
        Assert.True(keptFile)
        Assert.False(selector.destroyed)
    }

    ; A fresh, empty profiles folder for this test; Teardown removes it.
    UseTempProfilesFolder() {
        this.tempProfilesRoot := TestTempPath("pacs-gui-profiles")
        DirCreate(this.tempProfilesRoot)
        ProfileManager.profilesPath := this.tempProfilesRoot
        return this.tempProfilesRoot
    }

    ; Points profile storage at a file, so every save fails.
    PrepareBlockedProfileSave() {
        root := this.UseTempProfilesFolder()
        FileAppend("not a directory", root "\blocked")
        ProfileManager.profilesPath := root "\blocked"
    }

    PrepareDiscardRenameState() {
        this.UseTempProfilesFolder()
        state := {}
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
        editor := {base: DiscardRenameTrackingGUI.Prototype}
        editor.gui := FakeProfileDialog()
        editor.createCalls := 0
        editor.lastCreateAppliedBinds := true
        editor.visibleBind := "^F14"
        editor.visibleScope := "PACS"
        editor.MarkProfileDirty("Night")
        editor.profileLeaveDriver := FixedProfileLeaveDriver("No")
        state.gui := editor
        return state
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

class CaptureRefusingKeybindGUI extends KeybindGUI {
    ; As when another capture is already waiting for a key.
    PromptKeybind(*) {
        this.promptCalls++
        return false
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

    Add(options := "", values*) {
        this.rows.Push(values)
        return this.rows.Length
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
    ApplyProfileCandidate(*) {
        this.applyCalls++
        return true
    }

    ResizeColumns(*) {
    }
}

class StaleBeforeSuspensionGUI extends KeybindGUI {
    HasMainWindow() {
        return true
    }

    BeginCaptureTransaction(action := "start key capture") {
        acquired := super.BeginCaptureTransaction(action)
        if acquired
            this.onAcquired.Call()
        return acquired
    }

    RestoreRuntimeProfile(*) {
        this.restoreCalls++
        return false
    }

    NotifyUser(text, title, options := "") {
        this.notifications.Push({text: text, title: title, options: options})
    }
}

class FakeCaptureOwnerGui {
    __New() {
        this.disabled := false
    }

    Opt(option) {
        if (option = "+Disabled")
            this.disabled := true
        else if (option = "-Disabled")
            this.disabled := false
    }
}

class FailedRestoreKeybindGUI extends PassiveRuntimeKeybindGUI {
    RestoreRuntimeProfile(profile, &failureText) {
        failureText := "simulated restore failure"
        return false
    }
}

class RollbackFailingKeybindGUI extends KeybindGUI {
    ApplyBinds(*) {
        this.applyCalls++
        return false
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        failureText := "simulated restore failure"
        return false
    }

    ResizeColumns(*) {
    }
}

class CaptureStartRestoreFailingKeybindGUI extends KeybindGUI {
    StartInputHook(*) {
        throw Error("simulated hook start failure")
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        failureText := "simulated capture restore failure"
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

    RestoreRuntimeProfile(profile, &failureText) {
        failureText := ""
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

class ShowFailureRecoveryGUI extends CaptureMutationGuardGUI {
    HasMainWindow() {
        return true
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        return super.RestoreRuntimeProfile(profile, &failureText)
    }
}

class LiveDialogIdentityGUI extends KeybindGUI {
    GuiIsLive(*) {
        return true
    }

    StopListening() {
        return true
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

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        failureText := "simulated cancel restore failure"
        return false
    }
}

class StopFailureCancelGUI extends KeybindGUI {
    RestoreCapturedRuntimeAndNotify(*) {
        this.restoreCalls++
        return true
    }
}

class OnEndStopFailureGUI extends CaptureMutationGuardGUI {
    StartInputHook(*) {
        KeybindGUI.activeInputHook := FailingCaptureHook("F14")
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        return super.RestoreRuntimeProfile(profile, &failureText)
    }
}

class InterruptingProfileApplyGUI extends KeybindGUI {
    ApplyProfileBinds(*) {
        this.commandResult := PACSCommands.RunClinicalCommand(
            "interrupted command",
            this.callback
        )
        return true
    }
}

class ModifierRestartRestoreFailingKeybindGUI extends KeybindGUI {
    StartInputHook(*) {
        this.startCalls++
        if (this.startCalls > 1)
            throw Error("simulated modifier hook restart failure")
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        failureText := "simulated modifier restore failure"
        return false
    }
}

class SaveRuntimeFailingKeybindGUI extends KeybindGUI {
    ApplyProfileBinds(profile, showErrors := true, &failureText := "") {
        this.applyCalls++
        failureText := "Sign Report (simulated registration failure)"
        return false
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        failureText := "simulated saved-profile restore failure"
        return false
    }
}

class ConcurrentSaveMutationGUI extends KeybindGUI {
    ApplyProfileBinds(*) {
        this.applyCalls++
        profile := ProfileManager.profiles["Test"]
        profile.modalityAttendings["Concurrent"] := "New Attending"
        ; This deliberately bypasses the public GUI mutation guard to prove the
        ; save postcondition still catches an unexpected reentrant writer.
        this.MarkProfileDirty("Test")
        return true
    }

    RestoreRuntimeProfile(profile, &failureText) {
        this.restoreCalls++
        failureText := ""
        this.restoredAttending := profile.modalityAttendings["Concurrent"]
        return true
    }
}

class StaleScopeTrackingKeybindGUI extends KeybindGUI {
    RestoreRuntimeProfile(*) {
        this.restoreCalls++
        return true
    }
}

; A double whose dialogs are plain objects: one counts as live until its Destroy()
; has run.
class FakeWindowKeybindGUI extends KeybindGUI {
    static IsLive(targetGui) {
        return IsObject(targetGui) && (!HasProp(targetGui, "destroyed") || !targetGui.destroyed)
    }

    GuiIsLive(targetGui) {
        return FakeWindowKeybindGUI.IsLive(targetGui)
    }
}

class RenameRuntimeTrackingKeybindGUI extends FakeWindowKeybindGUI {
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
        if !this.BeginShutdown("close PACS Assistant")
            return false
        this.exitCalls++
        this.CancelShutdown()
        return true
    }
}

class DirtyRenameTestGUI extends DirtyLeaveTestGUI {
    GuiIsLive(targetGui) {
        return FakeWindowKeybindGUI.IsLive(targetGui)
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

class DiscardRenameTrackingGUI extends FakeWindowKeybindGUI {
    HasMainWindow() {
        return this.GuiIsLive(this.gui)
    }

    RestoreRuntimeProfile(profile, &failureText) {
        failureText := ""
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
    NewProfileDialog(*) {
        this.dialogCalls++
        return FakeProfileDialog(ProfileManager.currentProfile)
    }

    NotifyUser(*) {
    }
}

class DirtyAddFunctionTestGUI extends KeybindGUI {
    ResolveDirtyProfileBeforeLeaving(*) {
        this.resolveCalls++
        ; Discard rebuilds the main window; Save keeps it.
        if this.rebuildsWindow
            this.gui := {}
        return true
    }

    NewProfileDialog(*) {
        this.dialogCalls++
        ; The rest of the dialog needs a real window; reaching it is the result.
        throw Error("dialog reached")
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

class CallbackProfileLeaveDriver extends FixedProfileLeaveDriver {
    __New(choice, callback) {
        super.__New(choice)
        this.callback := callback
    }

    Choose(*) {
        this.callback.Call()
        return this.choice
    }
}

class ProfileDeleteTestGUI extends FakeWindowKeybindGUI {
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

class DirtyOtherBindConfirmationDriver extends AlwaysConfirmDriver {
    __New(editor, profile) {
        this.gui := editor
        this.profile := profile
    }

    Confirm(*) {
        this.profile.scopes["Sign Report"] := "PowerScribe"
        this.gui.MarkProfileDirty("Test")
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

class LeaseObservingNotificationDriver {
    __New() {
        this.calls := []
    }

    Notify(message, *) {
        this.calls.Push({message: message, leaseHeld: ExclusiveOperations.profileMutationActive})
        return "OK"
    }
}

class ArrayNotificationDriver {
    __New(messages) {
        this.messages := messages
    }

    Notify(message, title, options := "") {
        this.messages.Push({message: message, title: title, options: options})
    }
}

class NonErrorDirtyPromptGUI extends KeybindGUI {
    ResolveDirtyProfileBeforeLeaving(*) {
        throw "simulated non-Error value"
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

; Selects a ListBox item the way a click does: the selection, then the
; LBN_SELCHANGE notification that raises the control's Change event.
SelectListBoxItem(listBox, index) {
    listBox.Choose(index)
    controlId := DllCall("GetDlgCtrlID", "Ptr", listBox.Hwnd, "Int")
    SendMessage(0x0111, (1 << 16) | controlId, listBox.Hwnd, listBox.Gui)  ; WM_COMMAND, LBN_SELCHANGE
    Sleep(20)
}

class FakeProfileDialog {
    __New(profileName := "Test", profileRevision?) {
        this.destroyed := false
        this.profileName := profileName
        this.profileRevision := IsSet(profileRevision)
            ? profileRevision
            : ProfileManager.GetProfileRevision(profileName)
        this.disabled := false
    }

    Destroy() {
        this.destroyed := true
    }

    Opt(option) {
        if (option = "+Disabled")
            this.disabled := true
        else if (option = "-Disabled")
            this.disabled := false
    }
}

; A fake dialog carrying the profile identity NewProfileDialog records for a real
; one, so DialogProfileIsCurrent applies its full check.
ProfileBoundFakeDialog(profileName) {
    dialog := FakeProfileDialog(profileName)
    dialog.requiresLiveProfileIdentity := true
    dialog.profileObject := ProfileManager.profiles[profileName]
    dialog.profileStorageRevision := ProfileManager.GetProfileRevision(profileName)
    dialog.profileMutationSnapshot := KeybindGUI.GetProfileMutationRevision(profileName)
    dialog.ownerHwnd := 0
    return dialog
}

class ReentrantSelectorDialog extends FakeProfileDialog {
    __New() {
        super.__New()
        this.destroyCalls := 0
    }

    Destroy() {
        this.destroyCalls++
        super.Destroy()
    }
}

class ReentrantDefaultProfileStorageDriver {
    __New(callback, selector) {
        this.callback := callback
        this.selector := selector
        this.closeAttempted := false
        this.closeResult := true
        this.observedDisabled := false
    }

    WriteIniText(*) {
        this.closeAttempted := true
        this.observedDisabled := this.selector.disabled
        this.closeResult := this.callback.Call()
    }
}

class ProfileSelectorTransactionGUI extends FakeWindowKeybindGUI {
    HasMainWindow() {
        return false
    }

    CreateMainGUI(*) {
        this.mainWindowCalls++
    }

    ShowProfileSelector() {
        this.selectorCalls++
        return true
    }

    PromptNewProfile() {
        this.promptCalls++
        return true
    }

    NewProfileDialog(*) {
        this.dialogCalls++
        return FakeProfileDialog()
    }
}

class CountingRejectConfirmationDriver {
    __New() {
        this.calls := 0
    }

    Confirm(*) {
        this.calls++
        return false
    }
}

class ReentrantProfileDeleteConfirmationDriver {
    __New(callback, selector) {
        this.callback := callback
        this.selector := selector
        this.observedDisabled := false
        this.closeResult := true
    }

    Confirm(*) {
        this.observedDisabled := this.selector.disabled
        this.observedLease := ExclusiveOperations.Active()
        this.closeResult := this.callback.Call()
        return true
    }
}

class ReentrantProfileCreationGUI extends ProfileSelectorTransactionGUI {
    CreateProfileRecord(name) {
        this.closeAttempted := true
        this.observedDisabled := this.inputGui.disabled
        this.closeResult := this.CloseNewProfilePrompt(this.inputGui)
        ProfileManager.profiles[name] := ProfileManager.NewProfile()
        return true
    }

    RequestExit() {
        this.exitCalls++
        return true
    }
}

class QueuedNewProfileGUI extends ProfileSelectorTransactionGUI {
    CreateProfileRecord(name) {
        this.createRecordCalls++
        ProfileManager.profiles[name] := ProfileManager.NewProfile()
        return true
    }

    RequestExit() {
        this.exitCalls++
        return true
    }
}

class ThrowingShowProfileDialog extends FakeProfileDialog {
    Show(*) {
        throw Error("simulated GUI Show failure")
    }
}
