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
        "TestCaptureFailureRestoresBindingAndHookState",
        "TestRejectedCapturedKeyRestoresPriorBinding",
        "TestRejectedScopeChangeRestoresPriorScope",
        "TestFailedModalitySavePreservesLiveProfile",
        "TestStaleModalityDialogCannotWriteAnotherProfile",
        "TestOlderModalityDialogCannotOverwriteNewerSave",
        "TestStaleRenameDialogCannotRenameAnotherProfile",
        "TestFailedCustomDeletePreservesLiveProfile",
        "TestRemoveFunctionKeepsProfileAndRowWhenNativeOffFails",
        "TestCustomDeleteRollsBackWhenLaterRegistrationFails"
    ]

    Setup() {
        ; Build an instance without running the constructor, which would check GitHub
        ; for updates and load profiles
        this.gui := {base: KeybindGUI.Prototype, gui: ""}
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
}

class FailingListView {
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
    }

    Destroy() {
        this.destroyed := true
    }
}
