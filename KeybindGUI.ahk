#Requires AutoHotkey v2.0

#Include HotkeyManager.ahk
#Include ProfileManager.ahk
#Include PACSCommands.ahk
#Include UpdateChecker.ahk
#Include Settings.ahk

class KeybindGUI {
    gui := ""
    static isListening := false
    static listeningControl := ""
    static activeInputHook := 0
    static captureRuntimeProfile := 0
    static captureTransactionActive := false
    static captureOwnerGui := 0
    ; The V option would pass the selected key through to the foreground application.
    ; Capture is intentionally suppressing: the key is configuration data only.
    static inputHookOptions := ""

    __New() {
        ; The launch-time update check belongs to UpdateChecker.Start(), called from
        ; main.ahk under the same AutoUpdate setting. Repeating it here meant a second
        ; GitHub request every launch for a dialog that had already been offered.

        ProfileManager.LoadProfiles()
        if (ProfileManager.loadErrors.Length > 0) {
            MsgBox(
                ProfileManager.loadErrors.Length " profile file(s) could not be loaded. The original files were left unchanged.",
                "Profile Load Error",
                "Icon!"
            )
        }
        if ProfileManager.profiles.Count = 0 {
            this.PromptNewProfile()
        } else if (ProfileManager.defaultProfile != "" && ProfileManager.profiles.Has(ProfileManager.defaultProfile)) {
            ; If there's a valid default profile, load it directly
            ProfileManager.currentProfile := ProfileManager.defaultProfile
            this.CreateMainGUI()
        } else {
            this.ShowProfileSelector()
        }
    }

    CreateMainGUI(applyBinds := true) {
        this.gui := Gui(, "PACS Assistant - " ProfileManager.currentProfile)
        this.gui.Add("Text",, "Current Profile: " ProfileManager.currentProfile)
        
        ; Add rename button next to profile name
        this.gui.Add("Button", "x+10 yp-4 w60", "Rename").OnEvent("Click", (*) => this.PromptRenameProfile(ProfileManager.currentProfile))
        
        this.gui.Add("Text", "xm y+20", "Active Keybinds:")
        y := 70
        
        ; Create ListView for keybinds with adjusted column widths (removed Type column)
        lv := this.gui.Add("ListView", "xm y" y " w520 h200", ["Function", "Keybind", "Active In"])

        ; Populate ListView with current bindings (no more type column)
        currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
        for funcName, bind in currentProfile.binds {
            lv.Add(, funcName, this.PrettifyHotkey(bind), this.ScopeLabel(funcName))
        }

        this.ResizeColumns(lv)

        ; Add buttons below ListView
        y += 210
        this.gui.Add("Button", "xm y" y " w120", "Add Function").OnEvent("Click", (*) => this.ShowAddFunctionDialog(lv))
        this.gui.Add("Button", "x+10 yp w120", "Remove Function").OnEvent("Click", (*) => this.RemoveFunction(lv))
        this.gui.Add("Button", "x+10 yp w120", "Change Keybind").OnEvent("Click", (*) => this.ChangeSelectedKeybind(lv))
        this.gui.Add("Button", "x+10 yp w120", "Set Scope").OnEvent("Click", (*) => this.ShowScopeDialog(lv))

        ; Add profile management buttons
        y += 30
        this.gui.Add("Button", "xm y" y, "Save").OnEvent("Click", (*) => this.SaveCurrentProfile())
        this.gui.Add("Button", "x+10", "Switch Profile").OnEvent("Click", (*) => this.OpenProfileSelector())

        ; Add Check for Updates button
        this.gui.Add("Button", "x+10", "Check for Updates").OnEvent("Click", (*) => UpdateChecker.ShowUpdateDialog())

        ; Add Settings button
        this.gui.Add("Button", "x+10", "Settings").OnEvent("Click", (*) => Settings.ShowDialog())

        ; Add modality attending assignments
        y += 30
        this.gui.Add("Button", "xm y" y " w160", "Modality Attendings").OnEvent("Click", (*) => this.ShowModalityAttendingsDialog())

        this.gui.OnEvent("Close", (*) => this.CloseMainWindow())
        this.gui.Show()
        
        if applyBinds
            this.ApplyBinds()
    }

    OpenProfileSelector() {
        if !this.ProfileMutationAllowed("switch profiles")
            return false
        if !this.ResolveDirtyProfileBeforeLeaving()
            return false
        ; A selector has no active profile. Suspend the old profile before exposing any
        ; operation which can rename or delete it.
        this.PrepareForProfileSwitch()
        if this.HasMainWindow()
            this.gui.Destroy()
        this.gui := ""
        return this.ShowProfileSelector()
    }

    CloseMainWindow() {
        if !this.ProfileMutationAllowed("close PACS Assistant")
            return false
        if !this.ResolveDirtyProfileBeforeLeaving()
            return false
        this.RequestExit()
        return true
    }

    RequestExit() {
        ExitApp()
    }

    PrepareForProfileSwitch() {
        ; Destroying an owned key-capture dialog does not guarantee InputHook.Stop().
        ; Tear the hook down explicitly before its owner disappears, then suspend the
        ; old profile's runtime bindings while no profile is selected.
        this.StopListening()
        KeybindGUI.captureRuntimeProfile := 0
        HotkeyManager.DisableAllHotkeys()
    }

    HasMainWindow() {
        return this.GuiIsLive(this.gui)
    }

    GuiIsLive(gui) {
        if !IsObject(gui)
            return false
        try return gui.Hwnd && WinExist("ahk_id " gui.Hwnd)
        return false
    }

    NewProfileDialog(title, profileName := "", ownerGui := 0) {
        if (profileName = "")
            profileName := ProfileManager.currentProfile
        if !ownerGui && this.HasMainWindow()
            ownerGui := this.gui
        options := this.GuiIsLive(ownerGui) ? "+Owner" ownerGui.Hwnd : ""
        dialog := Gui(options, title)
        dialog.profileName := profileName
        return dialog
    }

    DialogProfileIsCurrent(dialog) {
        profileName := ""
        try profileName := dialog.profileName
        if (profileName != ""
            && profileName = ProfileManager.currentProfile
            && ProfileManager.profiles.Has(profileName))
            return true

        ; An owned dialog normally disappears with its main window. This explicit
        ; identity gate is the data-integrity backstop for queued callbacks or any
        ; dialog that outlives a profile switch.
        message := "The active profile changed while this dialog was open. Reopen it before saving changes."
        if KeybindGUI.captureTransactionActive
            return this.AbortStaleCapture(dialog, message, "Profile Changed")
        this.StopListening()
        try dialog.Destroy()
        MsgBox(message, "Profile Changed", "Icon!")
        return false
    }

    FindUniqueFunctionRow(listView, funcName) {
        match := 0
        try rowCount := listView.GetCount()
        catch
            return 0
        Loop rowCount {
            try rowName := listView.GetText(A_Index, 1)
            catch
                return 0
            if (rowName == funcName) {
                if match
                    return 0
                match := A_Index
            }
        }
        return match
    }

    CaptureFunctionDialogState(dialog, funcName, listView, rowIndex := 0) {
        if !this.DialogProfileIsCurrent(dialog)
            return false
        profile := ProfileManager.profiles[dialog.profileName]
        if !profile.binds.Has(funcName)
            return false
        if !rowIndex
            rowIndex := this.FindUniqueFunctionRow(listView, funcName)
        if !rowIndex
            return false

        try {
            if !(listView.GetText(rowIndex, 1) == funcName)
                return false
            dialog.functionName := funcName
            dialog.expectedBind := profile.binds[funcName]
            dialog.expectedScope := profile.scopes.Has(funcName)
                ? profile.scopes[funcName]
                : "Any"
            dialog.functionRow := rowIndex
            dialog.expectedRowBind := listView.GetText(rowIndex, 2)
            dialog.expectedRowScope := listView.GetText(rowIndex, 3)
            return true
        } catch {
            return false
        }
    }

    FunctionDialogIsCurrent(dialog, funcName, listView) {
        if !this.DialogProfileIsCurrent(dialog)
            return false

        valid := false
        try {
            profile := ProfileManager.profiles[dialog.profileName]
            currentScope := profile.scopes.Has(funcName)
                ? profile.scopes[funcName]
                : "Any"
            valid := HasProp(dialog, "functionName")
                && dialog.functionName == funcName
                && HasProp(dialog, "expectedBind")
                && profile.binds.Has(funcName)
                && profile.binds[funcName] == dialog.expectedBind
                && HasProp(dialog, "expectedScope")
                && currentScope == dialog.expectedScope
                && HasProp(dialog, "functionRow")
                && dialog.functionRow > 0
                && listView.GetText(dialog.functionRow, 1) == funcName
                && listView.GetText(dialog.functionRow, 2) == dialog.expectedRowBind
                && listView.GetText(dialog.functionRow, 3) == dialog.expectedRowScope
        }
        if valid
            return true

        if KeybindGUI.captureTransactionActive {
            return this.AbortStaleCapture(
                dialog,
                "The selected function changed while this dialog was open. Reopen it before applying changes.",
                "Function Changed"
            )
        }
        try this.StopListening()
        catch as err {
            MsgBox(
                "The key-capture hook could not be stopped after the function changed. Restart PACS Assistant before pressing another shortcut.`n`n" err.Message,
                "Function Changed",
                "Icon!"
            )
            return false
        }
        message := "The selected function changed while this dialog was open. Reopen it before applying changes."
        if IsObject(KeybindGUI.captureRuntimeProfile) {
            this.RestoreCapturedRuntimeAndNotify(
                ProfileManager.profiles[dialog.profileName],
                message,
                "Function Changed",
                true
            )
        } else {
            ; A scope dialog never suspends runtime bindings. Rejecting a stale
            ; callback must not create an unnecessary Off/On failure boundary.
            this.NotifyUser(message, "Function Changed", "Icon!")
        }
        try dialog.Destroy()
        return false
    }

    ShowProfileSelector() {
        selectorGui := Gui(, "PACS Assistant - Profile Selection")
        selectorGui.Add("Text",, "Select profile:")
        
        ; Add profiles listbox with default profile marked
        profileNames := []
        for name, _ in ProfileManager.profiles {
            ; Add asterisk to mark default profile
            profileNames.Push(name (name = ProfileManager.defaultProfile ? " *" : ""))
        }
        lb := selectorGui.Add("ListBox", "w200 h150", profileNames)
        
        ; If there's a default profile, select it in the listbox
        defaultIndex := this.DefaultProfileListIndex(
            profileNames,
            ProfileManager.defaultProfile
        )
        if defaultIndex
            lb.Choose(defaultIndex)
        
        ; Add buttons
        selectorGui.Add("GroupBox", "w190 h150", "Actions")
        
        selectorGui.Add("Button", "xp+10 yp+20 w170", "Select").OnEvent("Click", (*) => this.SelectProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "Set as Default").OnEvent("Click", (*) => this.SetDefaultProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "Rename").OnEvent("Click", (*) => this.PromptRenameProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "Delete Profile").OnEvent("Click", (*) => this.DeleteProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "New Profile").OnEvent("Click", (*) => this.OpenNewProfilePrompt(selectorGui))
        
        ; Add legend text
        selectorGui.Add("Text", "y+10", "* = Default Profile")
        
        selectorGui.OnEvent("Close", (*) => this.CloseProfileSelector(selectorGui))
        selectorGui.Show()
        return selectorGui
    }

    DefaultProfileListIndex(profileNames, defaultProfile) {
        if (defaultProfile = "")
            return 0
        renderedDefault := defaultProfile " *"
        for index, renderedName in profileNames {
            if (renderedName == renderedDefault)
                return index
        }
        return 0
    }

    CloseProfileSelector(selectorGui) {
        try selectorGui.Destroy()
        if this.HasMainWindow()
            return
        if (ProfileManager.currentProfile != "" && ProfileManager.profiles.Has(ProfileManager.currentProfile)) {
            this.CreateMainGUI()
            return
        }
        ExitApp()
    }

    OpenNewProfilePrompt(selectorGui) {
        selectorGui.Destroy()
        return this.PromptNewProfile()
    }

    PromptNewProfile() {
        inputGui := Gui(, "PACS Assistant - Create New Profile")
        inputGui.Add("Text",, "Enter profile name:")
        nameEdit := inputGui.Add("Edit", "w200")
        inputGui.Add("Button",, "OK").OnEvent("Click", (*) => this.CreateProfile(nameEdit.Value, inputGui))
        inputGui.OnEvent("Close", (*) => this.CloseNewProfilePrompt(inputGui))
        inputGui.Show()
        return inputGui
    }

    CloseNewProfilePrompt(inputGui) {
        try inputGui.Destroy()
        if (ProfileManager.profiles.Count > 0) {
            this.ShowProfileSelector()
            return
        }
        ExitApp()
    }

    CreateProfile(name, inputGui) {
        if !this.ProfileMutationAllowed("create a profile")
            return false
        name := Trim(name)
        if ProfileManager.CreateProfile(name) {
            ProfileManager.currentProfile := name
            inputGui.Destroy()
            this.CreateMainGUI()
            return true
        } else {
            this.NotifyUser(
                this.ProfileStorageFailureText(
                    "Enter a unique profile name without file-system characters or reserved Windows device names."
                ),
                ProfileManager.lastError != "" ? "Profile Creation Failed" : "Invalid Profile Name",
                "Icon!"
            )
            return false
        }
    }

    SelectProfile(name, selectorGui) {
        if !this.ProfileMutationAllowed("select a profile")
            return false
        if name != "" {
            ProfileManager.currentProfile := name
            selectorGui.Destroy()
            this.CreateMainGUI()
        }
    }

    SetDefaultProfile(name, selectorGui) {
        if !this.ProfileMutationAllowed("change the default profile")
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "Error", "Icon!")
            return
        }

        if (ProfileManager.SetDefaultProfile(name)) {
            selectorGui.Destroy()
            this.ShowProfileSelector()  ; Refresh the selector to show updated default
        } else {
            MsgBox(
                this.ProfileStorageFailureText("Failed to set default profile."),
                "Profile Update Failed",
                "Icon!"
            )
        }
    }

    DeleteProfile(name, selectorGui) {
        if !this.ProfileMutationAllowed("delete a profile")
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "Error", "Icon!")
            return
        }

        deletionState := this.CaptureProfileDeletionState(name)
        if !deletionState {
            MsgBox("The selected profile is no longer available.", "Profile Changed", "Icon!")
            return false
        }

        if this.ConfirmDestructiveAction(
            "Are you sure you want to delete profile '" name "'?",
            "Confirm Delete"
        ) {
            if !this.ProfileDeletionStateIsCurrent(deletionState) {
                this.NotifyUser(
                    "The selected profile changed while confirmation was open. Reopen the profile selector before deleting it.",
                    "Profile Changed",
                    "Icon!"
                )
                return false
            }
            if (ProfileManager.DeleteProfile(name)) {
                if (name = ProfileManager.currentProfile) {
                    ; If we deleted the current profile, switch to another one
                    for newName, _ in ProfileManager.profiles {
                        if (newName != name) {
                            ProfileManager.currentProfile := newName
                            break
                        }
                    }
                }
                selectorGui.Destroy()
                this.ShowProfileSelector()  ; Refresh the selector
                return true
            } else {
                MsgBox(
                    this.ProfileStorageFailureText("Cannot delete the last remaining profile."),
                    "Profile Delete Failed",
                    "Icon!"
                )
            }
        }
        return false
    }

    CaptureProfileDeletionState(name) {
        if (!ProfileManager.profiles.Has(name)
            || !ProfileManager.IsValidProfileName(name))
            return 0
        profile := ProfileManager.profiles[name]
        return {
            name: name,
            profilePointer: ObjPtr(profile),
            revision: ProfileManager.GetProfileRevision(name),
            profileCount: ProfileManager.profiles.Count,
            currentProfile: ProfileManager.currentProfile,
            defaultProfile: ProfileManager.defaultProfile
        }
    }

    ProfileDeletionStateIsCurrent(state) {
        if (!state
            || !ProfileManager.profiles.Has(state.name)
            || ProfileManager.profiles.Count != state.profileCount
            || ProfileManager.GetProfileRevision(state.name) != state.revision
            || !(ProfileManager.currentProfile == state.currentProfile)
            || !(ProfileManager.defaultProfile == state.defaultProfile))
            return false
        return ObjPtr(ProfileManager.profiles[state.name]) = state.profilePointer
    }

    /**
     * Takes ownership of key capture. Only one capture can be in flight at a time.
     * @returns true if capture started
     */
    BeginListening(funcName, control, promptGui) {
        if (KeybindGUI.isListening || KeybindGUI.captureTransactionActive)
            return false

        ; Capture the runtime contract before disabling anything. A failed hook start
        ; must either restore this exact set or visibly require an application restart.
        originalProfile := ProfileManager.CloneProfile(
            ProfileManager.profiles[ProfileManager.currentProfile]
        )
        KeybindGUI.captureRuntimeProfile := originalProfile
        this.BeginCaptureTransaction()

        KeybindGUI.isListening := true
        KeybindGUI.listeningControl := control
        try {
            ; The key the user presses to define a bind must be captured as data only.
            ; Leaving live clinical hotkeys registered here could execute that same key
            ; (including Draft/Sign) while it is being selected.
            HotkeyManager.DisableAllHotkeys()
            this.StartInputHook(funcName, control, promptGui)
        }
        catch as err {
            stopError := ""
            try this.StopListening()
            catch as cleanupError
                stopError := cleanupError.Message

            restored := false
            if (stopError != "") {
                this.NotifyUser(
                    "Input capture failed to start, and its hook could not be safely stopped: " stopError
                        . ". Restart PACS Assistant before using its shortcuts.",
                    "Capture Recovery Failed",
                    "Icon!"
                )
            } else {
                restored := this.RestoreCapturedRuntimeAndNotify(
                    originalProfile,
                    "Input capture failed to start. No keybind was changed.",
                    "Capture Recovery Failed",
                    false
                )
            }
            if restored
                this.ReleaseCaptureTransaction()
            throw err
        }
        return true
    }

    ; Creates the capture hook and records it so it can always be torn down again
    StartInputHook(funcName, control, promptGui) {
        ih := InputHook(KeybindGUI.inputHookOptions)
        ih.KeyOpt("{All}", "E")
        ih.OnEnd := this.OnInputEnd.Bind(this, funcName, control, promptGui)
        KeybindGUI.activeInputHook := ih
        ih.Start()
    }

    ; Duplicate detection has to use the same identity as runtime registration and
    ; profile validation. InputHook reports letters with canonical casing, while an
    ; older profile may contain the same bind in lower case.
    FindProfileBindingOwner(profile, hotkeyStr, exceptFuncName := "") {
        identity := HotkeyManager.HotkeyIdentity(hotkeyStr)
        for funcName, bind in profile.binds {
            if (funcName != exceptFuncName
                && HotkeyManager.HotkeyIdentity(bind) = identity)
                return funcName
        }
        return ""
    }

    OnInputEnd(funcName, control, promptGui, ih?) {
        ; Stop(), timeout, and replacement by another InputHook all raise OnEnd too.
        ; Only a real end key is input to bind; treating a stopped hook's blank EndKey
        ; as data silently unassigned the command while cancelling the dialog.
        if (ih.EndReason != "EndKey")
            return

        if !this.FunctionDialogIsCurrent(promptGui, funcName, control)
            return false

        key := ih.EndKey
        
        ; Handle Escape to cancel
        if (key = "Escape") {
            this.CancelKeybindPrompt(promptGui)
            return
        }
        
        ; Skip if the key is just a modifier
        if key ~= "^[LR]?(Control|Alt|Shift|Win)$" {
            ; Create and start a new input hook since the old one is ended
            try this.StartInputHook(funcName, control, promptGui)
            catch as err {
                this.CancelKeybindPrompt(promptGui)
                throw err
            }
            return
        }
        
        newBind := this.CapturedHotkey(ih)
        
        currentProfile := ProfileManager.profiles[promptGui.profileName]
        hadBinding := currentProfile.binds.Has(funcName)
        oldBind := hadBinding ? currentProfile.binds[funcName] : ""
        bindingChanged := false
        modifiedRow := 0

        try {
            ; Check if this hotkey is already assigned to another function
            owner := this.FindProfileBindingOwner(currentProfile, newBind, funcName)
            if owner {
                MsgBox("This hotkey is already assigned to '" owner "'", "Duplicate Binding", "Icon!")
                this.CancelKeybindPrompt(promptGui)
                return
            }

            ; First disable all existing hotkeys
            HotkeyManager.DisableAllHotkeys()
            
            ; Update profile
            currentProfile.binds[funcName] := newBind
            bindingChanged := true
            
            ; Find and update the ListView row before destroying the prompt
            Loop control.GetCount() {
                if (control.GetText(A_Index, 1) = funcName) {
                    control.Modify(A_Index,, funcName, this.PrettifyHotkey(newBind))
                    modifiedRow := A_Index
                    break
                }
            }
            this.ResizeColumns(control)
            this.StopListening()
            promptGui.Destroy()


            ; Reapply all binds
            if !this.ApplyBinds() {
                if hadBinding
                    currentProfile.binds[funcName] := oldBind
                else
                    currentProfile.binds.Delete(funcName)
                if modifiedRow
                    control.Modify(modifiedRow,, funcName, this.PrettifyHotkey(oldBind))
                ; The failed candidate has already been reported. Restore the prior
                ; runtime set quietly when possible, but surface uncertainty when
                ; native teardown/re-registration cannot prove that restoration.
                restored := this.RestoreCapturedRuntimeAndNotify(
                    currentProfile,
                    "The new keybind was rejected and the previous profile value was retained.",
                    "Keybind Recovery Failed",
                    false
                )
                if restored
                    this.ReleaseCaptureTransaction()
                return false
            }
            KeybindGUI.captureRuntimeProfile := 0
            this.MarkProfileDirty(promptGui.profileName)
            ; Dirty publication must precede re-enabling the owner: a queued
            ; Close/Switch callback must observe the Save/Discard/Cancel gate.
            this.ReleaseCaptureTransaction()
            return true
        } catch as err {
            if bindingChanged {
                if hadBinding
                    currentProfile.binds[funcName] := oldBind
                else
                    currentProfile.binds.Delete(funcName)
            }
            if modifiedRow
                try control.Modify(modifiedRow,, funcName, this.PrettifyHotkey(oldBind))
            this.StopListening()
            try promptGui.Destroy()
            ; Preserve the original control/apply exception, but never hide an
            ; uncertain live shortcut state behind the restored profile value.
            restored := this.RestoreCapturedRuntimeAndNotify(
                currentProfile,
                "The keybind change failed and the previous profile value was retained.",
                "Keybind Recovery Failed",
                false
            )
            if restored
                this.ReleaseCaptureTransaction()
            throw err
        }
    }

    /**
     * Ends key capture and tears down the hook.
     *
     * Stopping the hook is the important part. A hook left running after its dialog
     * went away kept listening, so the next key pressed anywhere fired OnInputEnd and
     * silently rebound whichever function had been open - binds "breaking" with no
     * apparent cause.
     */
    StopListening() {
        if KeybindGUI.activeInputHook {
            try {
                KeybindGUI.activeInputHook.Stop()
            } catch as err {
                ; Preserve the live hook and listening state so callers cannot tear
                ; down its profile/dialog while it may still capture the next key.
                throw Error("Input capture could not be stopped: " err.Message)
            }
            KeybindGUI.activeInputHook := 0
        }
        KeybindGUI.isListening := false
        KeybindGUI.listeningControl := ""
        return true
    }

    CapturedHotkey(ih) {
        ; EndMods is the capture-time snapshot. GetKeyState races the user releasing a
        ; modifier between the terminating key event and this callback.
        modifiers := ""
        modifiers .= InStr(ih.EndMods, "^") ? "^" : ""
        modifiers .= InStr(ih.EndMods, "!") ? "!" : ""
        modifiers .= InStr(ih.EndMods, "+") ? "+" : ""
        modifiers .= InStr(ih.EndMods, "#") ? "#" : ""
        return modifiers ih.EndKey
    }

    CancelKeybindPrompt(promptGui) {
        this.StopListening()
        fallbackProfile := ProfileManager.CloneProfile(
            ProfileManager.profiles[ProfileManager.currentProfile]
        )
        restored := this.RestoreCapturedRuntimeAndNotify(
            fallbackProfile,
            "Key capture was cancelled. No keybind was changed.",
            "Capture Recovery Failed",
            false
        )
        try promptGui.Destroy()
        if restored
            this.ReleaseCaptureTransaction()
        return restored
    }

    SaveCurrentProfile() {
        if !this.ProfileMutationAllowed("save the profile")
            return false
        profileName := ProfileManager.currentProfile
        try {
            ; One immutable snapshot is both the persisted value and the runtime
            ; contract. Success is not published until that same snapshot is live.
            savedProfile := ProfileManager.CloneProfile(
                ProfileManager.profiles[profileName]
            )
            ProfileManager.SaveProfile(profileName, savedProfile)
        } catch as err {
            MsgBox("The profile could not be saved. The previous file was left unchanged.`n`n" err.Message, "Save Failed", "Icon!")
            return false
        }

        applyError := ""
        runtimeApplied := false
        try runtimeApplied := this.ApplyProfileBinds(savedProfile, false)
        catch as err
            applyError := err.Message

        if !runtimeApplied {
            if (applyError = "")
                applyError := "one or more saved keybinds could not be registered"
            restoreError := ""
            if !this.RestoreRuntimeProfile(savedProfile, &restoreError) {
                message := "The profile was saved, but its runtime shortcuts could not be verified."
                    . "`n`n" applyError
                    . "`n`nThe saved runtime bindings also could not be fully restored: " restoreError
                    . ". Restart PACS Assistant before relying on its shortcuts."
                this.NotifyUser(message, "Profile Saved - Restart Required", "Icon!")
                return false
            }
        }

        MsgBox("Profile saved successfully!", "Success")
        this.ClearProfileDirty(profileName)
        return true
    }

    EnsureDirtyProfiles() {
        if !this.HasOwnProp("dirtyProfiles")
            this.dirtyProfiles := Map()
        return this.dirtyProfiles
    }

    MarkProfileDirty(profileName := "") {
        if (profileName = "")
            profileName := ProfileManager.currentProfile
        if (profileName != "")
            this.EnsureDirtyProfiles()[profileName] := true
    }

    ClearProfileDirty(profileName) {
        dirty := this.EnsureDirtyProfiles()
        if dirty.Has(profileName)
            dirty.Delete(profileName)
    }

    IsProfileDirty(profileName := "") {
        if (profileName = "")
            profileName := ProfileManager.currentProfile
        return profileName != "" && this.EnsureDirtyProfiles().Has(profileName)
    }

    ChooseUnsavedProfileAction(profileName) {
        if this.HasOwnProp("profileLeaveDriver")
            return this.profileLeaveDriver.Choose(profileName)
        return MsgBox(
            "Profile '" profileName "' has unsaved keybind changes."
                . "`n`nYes = Save, No = Discard, Cancel = keep editing.",
            "Unsaved Profile Changes",
            "YesNoCancel Icon!"
        )
    }

    ResolveDirtyProfileBeforeLeaving(refreshMainWindow := false) {
        profileName := ProfileManager.currentProfile
        if !this.IsProfileDirty(profileName)
            return true

        choice := this.ChooseUnsavedProfileAction(profileName)
        if (choice == "Cancel")
            return false
        if (choice == "Yes")
            return this.SaveCurrentProfile()
        if !(choice == "No")
            return false

        originalProfile := ProfileManager.profiles[profileName]
        try {
            stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath(profileName))
        } catch as err {
            this.NotifyUser(
                "The saved profile could not be reloaded, so the unsaved changes were retained.`n`n" err.Message,
                "Discard Failed",
                "Icon!"
            )
            return false
        }

        restoreError := ""
        if !this.RestoreRuntimeProfile(stored, &restoreError) {
            this.RestoreRuntimeAndNotify(
                originalProfile,
                "The unsaved changes were retained because the saved runtime bindings could not be restored.`n`n" restoreError,
                "Discard Failed"
            )
            return false
        }

        ProfileManager.profiles[profileName] := stored
        ProfileManager.profileRevisions[profileName] :=
            ProfileManager.GetProfileRevision(profileName) + 1
        this.ClearProfileDirty(profileName)

        if (refreshMainWindow && this.HasMainWindow()) {
            try {
                this.gui.Destroy()
                ; The stored profile is already the verified live runtime contract.
                ; Rebuild only the view; re-registering would add another failure edge.
                this.CreateMainGUI(false)
            } catch as err {
                this.NotifyUser(
                    "The saved profile was restored, but the main window could not be refreshed.`n`n" err.Message,
                    "Profile View Refresh Failed",
                    "Icon!"
                )
                return false
            }
        }
        return true
    }

    ApplyBinds(showErrors := true) {
        currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
        return this.ApplyProfileBinds(currentProfile, showErrors)
    }

    ApplyProfileBinds(currentProfile, showErrors := true) {
        HotkeyManager.DisableAllHotkeys()
        if (!currentProfile.HasProp("scopes"))
            currentProfile.scopes := Map()
        failed := []

        ; Ensure built-in hotkey functions are loaded
        if (HotkeyManager.hotkeyFunctions.Count = 0) {
            HotkeyManager.hotkeyFunctions := PACSCommands.commands
        }

        for funcName, bind in currentProfile.binds {
            scope := currentProfile.scopes.Has(funcName) ? currentProfile.scopes[funcName] : "Any"
            try {
                if (currentProfile.customFuncs.Has(funcName)) {
                    config := currentProfile.customFuncs[funcName]
                    callback := PACSCommands.CreateCustomKeybind(config.keys, config.window)
                    result := HotkeyManager.RegisterCustomHotkey(funcName, bind, callback, scope)
                } else {
                    result := HotkeyManager.RegisterHotkey(funcName, bind, scope)
                }

                if !result {
                    failed.Push(funcName (HotkeyManager.lastError != "" ? " (" HotkeyManager.lastError ")" : ""))
                }
            } catch as err {
                failed.Push(funcName " (" err.Message ")")
            }
        }

        ; One message for the whole apply rather than a dialog per bind
        if (failed.Length && showErrors) {
            errMsg := "These keybinds failed to register:" "`n"
            for item in failed {
                errMsg .= "- " item "`n"
            }
            MsgBox(RTrim(errMsg, "`n"), "Keybind Errors", "Icon!")
        }
        return failed.Length = 0
    }

    RestoreRuntimeProfile(profile, &errorText) {
        errorText := ""
        try {
            if this.ApplyProfileBinds(profile, false)
                return true
            errorText := "one or more previous keybinds could not be re-registered"
        } catch as err {
            errorText := err.Message
        }
        return false
    }

    ConfirmDestructiveAction(message, title) {
        if this.HasOwnProp("confirmationDriver")
            return this.confirmationDriver.Confirm(message, title)
        return MsgBox(message, title, "YesNo Icon!") = "Yes"
    }

    NotifyUser(message, title, options := "") {
        if this.HasOwnProp("notificationDriver")
            return this.notificationDriver.Notify(message, title, options)
        return MsgBox(message, title, options)
    }

    ProfileMutationAllowed(action) {
        if !KeybindGUI.captureTransactionActive
            return true
        this.NotifyUser(
            "Finish or cancel the active key capture before you " action ".",
            "Keybind In Progress",
            "Icon!"
        )
        return false
    }

    BeginCaptureTransaction() {
        KeybindGUI.captureTransactionActive := true
        KeybindGUI.captureOwnerGui := 0
        hasMainWindow := false
        try hasMainWindow := this.HasMainWindow()
        if hasMainWindow {
            KeybindGUI.captureOwnerGui := this.gui
            try this.gui.Opt("+Disabled")
        }
    }

    ReleaseCaptureTransaction() {
        ownerGui := KeybindGUI.captureOwnerGui
        KeybindGUI.captureOwnerGui := 0
        KeybindGUI.captureTransactionActive := false
        if IsObject(ownerGui)
            try ownerGui.Opt("-Disabled")
    }

    AbortStaleCapture(dialog, message, title) {
        try this.StopListening()
        catch as err {
            this.NotifyUser(
                message "`n`nThe input hook could not be stopped: " err.Message
                    . ". Restart PACS Assistant before pressing another shortcut.",
                title,
                "Icon!"
            )
            return false
        }

        currentProfile := 0
        currentName := ProfileManager.currentProfile
        if (currentName != "" && ProfileManager.profiles.Has(currentName))
            currentProfile := ProfileManager.CloneProfile(ProfileManager.profiles[currentName])
        ; A stale callback must never restore the pre-capture snapshot over a newer
        ; committed profile mutation. The current profile is now authoritative.
        KeybindGUI.captureRuntimeProfile := 0
        restored := false
        if currentProfile {
            restored := this.RestoreRuntimeAndNotify(
                currentProfile,
                message,
                title,
                true
            )
        } else {
            this.NotifyUser(
                message "`n`nNo current profile could be verified. Restart PACS Assistant before relying on its shortcuts.",
                title,
                "Icon!"
            )
        }
        try dialog.Destroy()
        if restored
            this.ReleaseCaptureTransaction()
        return false
    }

    RestoreRuntimeAndNotify(originalProfile, message, title, notifyOnSuccess := true) {
        restoreError := ""
        restored := this.RestoreRuntimeProfile(originalProfile, &restoreError)
        if !restored {
            message .= "`n`nThe previous runtime bindings could not be fully restored: " restoreError
                . ". Restart PACS Assistant before relying on its shortcuts."
        }
        if (notifyOnSuccess || !restored)
            this.NotifyUser(message, title, "Icon!")
        return restored
    }

    RestoreCapturedRuntimeAndNotify(fallbackProfile, message, title, notifyOnSuccess := true) {
        originalProfile := IsObject(KeybindGUI.captureRuntimeProfile)
            ? KeybindGUI.captureRuntimeProfile
            : fallbackProfile
        try return this.RestoreRuntimeAndNotify(
            originalProfile,
            message,
            title,
            notifyOnSuccess
        )
        finally KeybindGUI.captureRuntimeProfile := 0
    }

    CaptureFunctionRemovalState(listView) {
        try row := listView.GetNext(0)
        catch
            return 0
        if !row
            return 0

        profileName := ProfileManager.currentProfile
        if (profileName = "" || !ProfileManager.profiles.Has(profileName))
            return 0
        profile := ProfileManager.profiles[profileName]

        try {
            funcName := listView.GetText(row, 1)
            if (!profile.binds.Has(funcName)
                || this.FindUniqueFunctionRow(listView, funcName) != row)
                return 0
            return {
                profileName: profileName,
                profilePointer: ObjPtr(profile),
                profileRevision: ProfileManager.GetProfileRevision(profileName),
                functionName: funcName,
                bind: profile.binds[funcName],
                hasScope: profile.scopes.Has(funcName),
                scope: profile.scopes.Has(funcName) ? profile.scopes[funcName] : "",
                row: row,
                rowBind: listView.GetText(row, 2),
                rowScope: listView.GetText(row, 3)
            }
        }
        return 0
    }

    FunctionRemovalStateIsCurrent(state, listView) {
        if (!state
            || !(ProfileManager.currentProfile == state.profileName)
            || !ProfileManager.profiles.Has(state.profileName)
            || ProfileManager.GetProfileRevision(state.profileName) != state.profileRevision)
            return false

        profile := ProfileManager.profiles[state.profileName]
        if (ObjPtr(profile) != state.profilePointer
            || !profile.binds.Has(state.functionName)
            || !(profile.binds[state.functionName] == state.bind)
            || profile.scopes.Has(state.functionName) != state.hasScope)
            return false
        if (state.hasScope && !(profile.scopes[state.functionName] == state.scope))
            return false

        try return listView.GetNext(0) = state.row
            && this.FindUniqueFunctionRow(listView, state.functionName) = state.row
            && listView.GetText(state.row, 1) == state.functionName
            && listView.GetText(state.row, 2) == state.rowBind
            && listView.GetText(state.row, 3) == state.rowScope
        return false
    }

    CaptureCustomDeletionState(funcName, selectorGui) {
        if !this.DialogProfileIsCurrent(selectorGui)
            return 0
        profileName := selectorGui.profileName
        profile := ProfileManager.profiles[profileName]
        if !profile.customFuncs.Has(funcName)
            return 0
        config := profile.customFuncs[funcName]
        if (!IsObject(config)
            || !HasProp(config, "keys")
            || !HasProp(config, "window"))
            return 0
        return {
            profileName: profileName,
            profilePointer: ObjPtr(profile),
            profileRevision: ProfileManager.GetProfileRevision(profileName),
            functionName: funcName,
            configPointer: ObjPtr(config),
            keys: config.keys,
            window: config.window,
            hasBind: profile.binds.Has(funcName),
            bind: profile.binds.Has(funcName) ? profile.binds[funcName] : "",
            hasScope: profile.scopes.Has(funcName),
            scope: profile.scopes.Has(funcName) ? profile.scopes[funcName] : ""
        }
    }

    CustomDeletionStateIsCurrent(state, selectorGui) {
        if (!state
            || !this.DialogProfileIsCurrent(selectorGui)
            || !(selectorGui.profileName == state.profileName)
            || ProfileManager.GetProfileRevision(state.profileName) != state.profileRevision)
            return false
        profile := ProfileManager.profiles[state.profileName]
        if (ObjPtr(profile) != state.profilePointer
            || !profile.customFuncs.Has(state.functionName))
            return false
        config := profile.customFuncs[state.functionName]
        return IsObject(config)
            && ObjPtr(config) = state.configPointer
            && HasProp(config, "keys")
            && config.keys == state.keys
            && HasProp(config, "window")
            && config.window == state.window
            && profile.binds.Has(state.functionName) = state.hasBind
            && (!state.hasBind || profile.binds[state.functionName] == state.bind)
            && profile.scopes.Has(state.functionName) = state.hasScope
            && (!state.hasScope || profile.scopes[state.functionName] == state.scope)
    }

    ApplyProfileCandidate(candidate, originalProfile, operationName) {
        applyError := ""
        try {
            if this.ApplyProfileBinds(candidate, false)
                return true
            applyError := HotkeyManager.lastError != ""
                ? HotkeyManager.lastError
                : "one or more candidate keybinds could not be registered"
        } catch as err {
            applyError := err.Message
        }

        restoreError := ""
        restored := this.RestoreRuntimeProfile(originalProfile, &restoreError)
        message := "The " operationName " was not applied because its runtime keybind state could not be verified."
        if (applyError != "")
            message .= "`n`n" applyError
        if !restored
            message .= "`n`nThe previous runtime bindings also could not be fully restored: " restoreError
                . ". Restart PACS Assistant before relying on its shortcuts."
        MsgBox(message, "Keybind Change Cancelled", "Icon!")
        return false
    }

    PrettifyHotkey(hotkeyStr) {
        if (hotkeyStr = "")
            return "Unassigned"
            
        modifiers := ""
        key := hotkeyStr
        
        ; Extract modifiers in order
        if (InStr(key, "^")) {
            modifiers .= "Ctrl + "
            key := StrReplace(key, "^")
        }
        if (InStr(key, "!")) {
            modifiers .= "Alt + "
            key := StrReplace(key, "!")
        }
        if (InStr(key, "+")) {
            modifiers .= "Shift + "
            key := StrReplace(key, "+")
        }
        if (InStr(key, "#")) {
            modifiers .= "Win + "
            key := StrReplace(key, "#")
        }
        
        ; Capitalize the key
        key := Format("{:U}", key)
        
        return modifiers key
    }

    PromptRenameProfile(name, parentGui := 0) {
        if !this.ProfileMutationAllowed("rename a profile")
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "Error", "Icon!")
            return false
        }
        ; A case-only rename moves the existing file rather than rewriting it. Make
        ; the current in-memory profile match disk before capturing the dialog so no
        ; dirty binding can be silently discarded when the dirty flag is rekeyed.
        if (!parentGui
            && name == ProfileManager.currentProfile
            && !this.ResolveDirtyProfileBeforeLeaving(true))
            return false

        renameGui := this.NewProfileDialog(
            "PACS Assistant - Rename Profile",
            name,
            parentGui
        )
        if !this.CaptureRenameDialogState(renameGui, name) {
            renameGui.Destroy()
            return false
        }
        renameGui.Add("Text",, "Enter new name for profile '" name "':")
        nameEdit := renameGui.Add("Edit", "w200", name)
        renameGui.Add("Button",, "OK").OnEvent("Click", (*) => this.RenameProfile(name, nameEdit.Value, renameGui, parentGui))
        renameGui.Add("Button", "x+10", "Cancel").OnEvent("Click", (*) => renameGui.Destroy())
        renameGui.Show()
        return true
    }

    CaptureRenameDialogState(renameGui, name) {
        if !ProfileManager.profiles.Has(name)
            return false
        renameGui.profileName := name
        renameGui.profilePointer := ObjPtr(ProfileManager.profiles[name])
        renameGui.profileRevision := ProfileManager.GetProfileRevision(name)
        return true
    }

    RenameProfile(oldName, newName, renameGui, parentGui := 0) {
        if !this.ProfileMutationAllowed("rename a profile")
            return false
        if !this.RenameDialogIsCurrent(oldName, renameGui, parentGui)
            return false

        newName := Trim(newName)
        if (newName = "") {
            MsgBox("Profile name cannot be empty.", "Error", "Icon!")
            return
        }

        if (ProfileManager.RenameProfile(oldName, newName)) {
            this.ClearProfileDirty(oldName)
            this.ClearProfileDirty(newName)
            renameGui.Destroy()
            if (parentGui) {
                parentGui.Destroy()
                this.ShowProfileSelector()  ; Refresh the selector
            } else {
                this.gui.Destroy()
                ; Renaming changes storage/display identity only. Rebuilding the
                ; window must not tear down and re-register unchanged hotkeys.
                this.CreateMainGUI(false)
            }
            return true
        } else {
            MsgBox(
                this.ProfileStorageFailureText(
                    "Failed to rename profile. The name may already be in use."
                ),
                "Profile Rename Failed",
                "Icon!"
            )
            return false
        }
    }

    ProfileStorageFailureText(fallback) {
        message := ProfileManager.lastError != ""
            ? ProfileManager.lastError
            : fallback
        if ProfileManager.recoveryRequired
            message .= "`n`nProfile storage could not be fully restored. Restart PACS Assistant before changing profiles again."
        return message
    }

    RenameDialogIsCurrent(oldName, renameGui, parentGui := 0) {
        capturedName := ""
        try capturedName := renameGui.profileName
        valid := this.GuiIsLive(renameGui)
            && capturedName == oldName
            && ProfileManager.profiles.Has(oldName)
            && !this.IsProfileDirty(oldName)
            && HasProp(renameGui, "profilePointer")
            && ObjPtr(ProfileManager.profiles[oldName]) = renameGui.profilePointer
            && HasProp(renameGui, "profileRevision")
            && ProfileManager.GetProfileRevision(oldName) = renameGui.profileRevision
        if valid {
            valid := parentGui
                ? this.GuiIsLive(parentGui)
                : ProfileManager.currentProfile = oldName
        }
        if valid
            return true

        try renameGui.Destroy()
        MsgBox(
            "The profile context changed while this rename dialog was open. Reopen it before renaming.",
            "Profile Changed",
            "Icon!"
        )
        return false
    }

    ShowAddFunctionDialog(listView) {
        selectorGui := this.NewProfileDialog("PACS Assistant - Add Function")
        
        ; Get list of unbound functions, separated by type
        builtInFunctions := []
        customFunctions := []
        
        ; Add built-in functions that aren't bound
        for funcName, _ in PACSCommands.commands {
            if !ProfileManager.profiles[ProfileManager.currentProfile].binds.Has(funcName) {
                builtInFunctions.Push(funcName)
            }
        }
        
        ; Add ALL custom functions from current profile that aren't bound
        for funcName, _ in ProfileManager.profiles[ProfileManager.currentProfile].customFuncs {
            if !ProfileManager.profiles[ProfileManager.currentProfile].binds.Has(funcName) {
                customFunctions.Push(funcName)
            }
        }
        
        ; Add custom keybind creation button
        selectorGui.Add("Button", "w200", "Create New Custom Keybind").OnEvent("Click", (*) => (
            selectorGui.Destroy(),
            this.ShowCustomKeybindDialog(listView, selectorGui.profileName)
        ))
        
        ; Add built-in functions section
        selectorGui.Add("Text", "xm y+20", "Built-in Functions:")
        lbBuiltIn := selectorGui.Add("ListBox", "w200 h150", builtInFunctions)
        
        ; Add custom functions section (now always show if there are any custom functions).
        ; lbCustom stays defined either way - the Add Selected handler reads it, and an
        ; unassigned local raised an unset-variable error whenever a profile had no
        ; custom functions and nothing was selected in the built-in list.
        lbCustom := ""
        if (customFunctions.Length > 0) {
            selectorGui.Add("Text", "xm y+10", "Custom Functions:")
            lbCustom := selectorGui.Add("ListBox", "w200 h100", customFunctions)
            selectorGui.Add("Button", "y+5 w200", "Delete Selected Custom Function").OnEvent("Click", (*) => this.DeleteCustomFunction(lbCustom.Text, selectorGui))
        }

        ; Add action buttons
        selectorGui.Add("Button", "xm y+10", "Add Selected").OnEvent("Click", (*) => this.AddFunction(this.SelectedFunction(lbBuiltIn, lbCustom), listView, selectorGui))
        selectorGui.Add("Button", "x+10", "Cancel").OnEvent("Click", (*) => selectorGui.Destroy())
        
        selectorGui.Show()
    }

    /**
     * The function selected in either list, built-in first.
     * Accepts "" for a list that was not created, which is why it takes the controls
     * rather than their text.
     * @returns the selected name, or "" when neither list has a selection
     */
    SelectedFunction(lbBuiltIn, lbCustom) {
        if (lbBuiltIn && lbBuiltIn.Text != "")
            return lbBuiltIn.Text
        if (lbCustom && lbCustom.Text != "")
            return lbCustom.Text
        return ""
    }

    DeleteCustomFunction(funcName, selectorGui) {
        if !this.ProfileMutationAllowed("delete a custom function")
            return false
        if !this.DialogProfileIsCurrent(selectorGui)
            return false

        if (funcName = "") {
            MsgBox("Please select a custom function to delete.", "Error", "Icon!")
            return
        }

        ; Note the parentheses: without them this parses as "(!InStr(...)) = 1", which
        ; is true only when the prefix is absent entirely and lets a name containing
        ; "Custom: " anywhere past the start through
        if (InStr(funcName, "Custom: ") != 1) {
            MsgBox("Only custom functions can be deleted.", "Error", "Icon!")
            return
        }

        deletionState := this.CaptureCustomDeletionState(funcName, selectorGui)
        if !deletionState {
            this.NotifyUser(
                "The selected custom function changed. Reopen Add Function before deleting it.",
                "Function Changed",
                "Icon!"
            )
            return false
        }
        
        if this.ConfirmDestructiveAction(
            "Are you sure you want to delete the custom function '" funcName "'?",
            "Confirm Delete"
        ) {
            if !this.CustomDeletionStateIsCurrent(deletionState, selectorGui) {
                this.NotifyUser(
                    "The selected custom function changed while confirmation was open. Reopen Add Function before deleting it.",
                    "Function Changed",
                    "Icon!"
                )
                return false
            }

            profileName := deletionState.profileName
            originalProfile := ProfileManager.profiles[profileName]
            candidate := ProfileManager.CloneProfile(originalProfile)
            
            ; Remove from a candidate and publish it only after the atomic file save.
            candidate.customFuncs.Delete(funcName)
            
            ; Remove from current profile's bindings if it exists
            if (candidate.binds.Has(funcName)) {
                candidate.binds.Delete(funcName)
            }
            if (candidate.scopes.Has(funcName)) {
                candidate.scopes.Delete(funcName)
            }

            ; Prove that every old native variant can be retired and every remaining
            ; bind can be registered before changing the file, live profile, or UI.
            if !this.ApplyProfileCandidate(candidate, originalProfile, "custom-function deletion")
                return false

            if !this.CustomDeletionStateIsCurrent(deletionState, selectorGui) {
                this.RestoreRuntimeAndNotify(
                    originalProfile,
                    "The selected custom function changed before deletion completed. The previous profile was retained.",
                    "Function Changed"
                )
                return false
            }

            try ProfileManager.SaveProfile(profileName, candidate)
            catch as err {
                message := "The custom function could not be deleted. The previous profile was left unchanged.`n`n" err.Message
                this.RestoreRuntimeAndNotify(originalProfile, message, "Delete Failed")
                return false
            }
            ProfileManager.profiles[profileName] := candidate
            this.ClearProfileDirty(profileName)

            ; Just destroy both GUIs and recreate them
            selectorGui.Destroy()
            this.gui.Destroy()
            ; The candidate was already applied transactionally above. Rebuilding the
            ; window must not tear it down and create a second failure boundary.
            this.CreateMainGUI(false)
            
            ; Show the add function dialog with the main ListView
            for ctrl in this.gui {
                if (ctrl.Type = "ListView") {
                    this.ShowAddFunctionDialog(ctrl)
                    break
                }
            }
            return true
        }
        return false
    }

    ShowCustomKeybindDialog(listView, profileName := "") {
        customGui := this.NewProfileDialog("PACS Assistant - Configure Custom Keybind", profileName)
        customGui.Add("Text",, "Name for this keybind:")
        nameEdit := customGui.Add("Edit", "w200")
        
        customGui.Add("Text", "y+10", "Keys to send (e.g. {Tab}, ^c, Hello):")
        keysEdit := customGui.Add("Edit", "w200")
        
        customGui.Add("Text", "y+10", "Target window (optional):")
        windowEdit := customGui.Add("Edit", "w200")
        
        customGui.Add("Button", "y+10", "OK").OnEvent("Click", (*) => this.AddCustomKeybind(nameEdit.Value, keysEdit.Value, windowEdit.Value, listView, customGui))
        customGui.Add("Button", "x+10", "Cancel").OnEvent("Click", (*) => customGui.Destroy())
        
        ; Add help text
        customGui.Add("Text", "y+20", "Examples:")
        customGui.Add("Text",, "{Tab} = Tab key`n^c = Ctrl+C`nHello = types 'Hello'")
        
        customGui.Show()
    }

    AddCustomKeybind(name, keys, window, listView, customGui) {
        if !this.ProfileMutationAllowed("create a custom keybind")
            return false
        if !this.DialogProfileIsCurrent(customGui)
            return false
        profileName := customGui.profileName

        name := Trim(name)
        if (name = "") {
            MsgBox("Please enter a name for the keybind.", "Error", "Icon!")
            return
        }
        if (keys = "") {
            MsgBox("Please enter keys to send.", "Error", "Icon!")
            return
        }
        
        ; Create unique function name
        funcName := "Custom: " name
        if !ProfileManager.IsSafeIniKey(funcName) {
            MsgBox("The keybind name cannot contain |, =, square brackets, or line breaks.", "Invalid Keybind Name", "Icon!")
            return
        }
        
        ; Check if name already exists in current profile
        currentProfile := ProfileManager.profiles[profileName]
        if !this.CustomFunctionNameAvailable(currentProfile, funcName) {
            MsgBox("A keybind with this name already exists in this profile.", "Error", "Icon!")
            return
        }
        
        ; Persist configuration only. ApplyBinds creates the runtime callback at the
        ; application boundary, keeping profile storage independent of commands.
        currentProfile.customFuncs[funcName] := {keys: keys, window: window}

        ; Add to profile with empty binding, active in any window until scoped
        currentProfile.binds[funcName] := ""
        currentProfile.scopes[funcName] := "Any"

        ; Add to ListView (removed type)
        listView.Add(, funcName, "Unassigned", this.ScopeLabel(funcName))
        this.ResizeColumns(listView)
        this.MarkProfileDirty(profileName)

        customGui.Destroy()
        
        ; Prompt user to set the keybind
        this.PromptKeybind(funcName, listView, profileName)
    }

    CustomFunctionNameAvailable(profile, funcName) {
        return !ProfileManager.HasIniKeyIdentity(profile.binds, funcName)
            && !ProfileManager.HasIniKeyIdentity(profile.customFuncs, funcName)
    }

    AddFunction(funcName, listView, selectorGui) {
        if !this.ProfileMutationAllowed("add a function")
            return false
        if !this.DialogProfileIsCurrent(selectorGui)
            return false

        if (funcName = "") {
            MsgBox("Please select a function first.", "Error", "Icon!")
            return
        }

        profileName := selectorGui.profileName
        profile := ProfileManager.profiles[profileName]
        stillAvailable := !ProfileManager.HasIniKeyIdentity(profile.binds, funcName)
            && (PACSCommands.commands.Has(funcName) || profile.customFuncs.Has(funcName))
        if !stillAvailable {
            selectorGui.Destroy()
            MsgBox(
                "The selected function changed while this dialog was open. Reopen Add Function before making another change.",
                "Function List Changed",
                "Icon!"
            )
            return false
        }

        ; Add to profile with empty binding, active in any window until scoped
        profile.binds[funcName] := ""
        profile.scopes[funcName] := "Any"

        ; Add to ListView (removed type)
        listView.Add(, funcName, "Unassigned", this.ScopeLabel(funcName))
        this.ResizeColumns(listView)
        this.MarkProfileDirty(profileName)

        selectorGui.Destroy()
        
        ; Prompt user to set the keybind
        this.PromptKeybind(funcName, listView, profileName)
        return true
    }

    RemoveFunction(listView) {
        if !this.ProfileMutationAllowed("remove a function")
            return false
        removalState := this.CaptureFunctionRemovalState(listView)
        if !removalState {
            MsgBox("Please select a function to remove.", "Error", "Icon!")
            return
        }
        
        funcName := removalState.functionName
        if this.ConfirmDestructiveAction(
            "Remove '" funcName "' from the profile?",
            "Confirm Remove"
        ) {
            if !this.FunctionRemovalStateIsCurrent(removalState, listView) {
                this.NotifyUser(
                    "The selected function changed while confirmation was open. Reopen the removal prompt before making another change.",
                    "Function Changed",
                    "Icon!"
                )
                return false
            }

            profileName := removalState.profileName
            originalProfile := ProfileManager.profiles[profileName]
            candidate := ProfileManager.CloneProfile(originalProfile)
            candidate.binds.Delete(funcName)
            if candidate.scopes.Has(funcName)
                candidate.scopes.Delete(funcName)

            if !this.ApplyProfileCandidate(candidate, originalProfile, "function removal")
                return false

            if !this.FunctionRemovalStateIsCurrent(removalState, listView) {
                this.RestoreRuntimeAndNotify(
                    originalProfile,
                    "The selected function changed before removal completed. The previous profile was retained.",
                    "Function Changed"
                )
                return false
            }

            try listView.Delete(removalState.row)
            catch as err {
                this.RestoreRuntimeAndNotify(
                    originalProfile,
                    "The function row could not be removed, so the previous profile was retained.`n`n" err.Message,
                    "Function Removal Failed"
                )
                return false
            }
            ; No longer delete the custom function itself, only its binding.
            ProfileManager.profiles[profileName] := candidate
            this.MarkProfileDirty(profileName)
            try this.ResizeColumns(listView)
            return true
        }
        return false
    }

    ChangeSelectedKeybind(listView) {
        if (listView.GetNext(0) = 0) {
            MsgBox("Please select a function to change.", "Error", "Icon!")
            return
        }
        
        funcName := listView.GetText(listView.GetNext(0), 1)
        this.PromptKeybind(funcName, listView)
    }

    PromptKeybind(funcName, listView, profileName := "") {
        if KeybindGUI.isListening {
            MsgBox("Already waiting for a keybind. Finish or cancel that one first.", "Keybind In Progress", "Icon!")
            return
        }

        promptGui := this.NewProfileDialog("PACS Assistant - Set Keybind", profileName)
        promptGui.Add("Text",, "Press keys for '" funcName "'...")
        promptGui.Add("Edit", "w200 ReadOnly", "Press keys...")
        promptGui.Add("Button",, "Cancel").OnEvent("Click", (*) => this.CancelKeybindPrompt(promptGui))

        ; Closing with the X has to tear the hook down as well, otherwise it keeps
        ; capturing and rebinds the next key pressed anywhere
        promptGui.OnEvent("Close", (*) => this.CancelKeybindPrompt(promptGui))

        if !this.CaptureFunctionDialogState(promptGui, funcName, listView) {
            promptGui.Destroy()
            MsgBox(
                "The selected function could not be verified. Refresh the profile and try again.",
                "Function Not Available",
                "Icon!"
            )
            return false
        }

        this.BeginListening(funcName, listView, promptGui)

        promptGui.Show()
        return true
    }

    ResizeColumns(listView) {
        listView.ModifyCol(1, "AutoHdr")  ; Function column
        listView.ModifyCol(2, "AutoHdr")  ; Keybind column
        listView.ModifyCol(3, "AutoHdr")  ; Scope column
    }

    ; How a bind's window scope reads in the ListView
    ScopeLabel(funcName) {
        scope := ProfileManager.GetScope(funcName)
        return scope = "Any" ? "Any window" : scope
    }

    ShowScopeDialog(listView) {
        if (listView.GetNext(0) = 0) {
            MsgBox("Please select a function first.", "Error", "Icon!")
            return
        }

        rowIndex := listView.GetNext(0)
        funcName := listView.GetText(rowIndex, 1)
        flags := HotkeyManager.FlagsFromScope(ProfileManager.GetScope(funcName))

        scopeGui := this.NewProfileDialog("PACS Assistant - Keybind Scope")
        scopeGui.Add("Text",, "Only activate '" funcName "' when one of these is the active window:")
        pacsBox := scopeGui.Add("Checkbox", "y+10", "PACS")
        pacsBox.Value := flags.requirePACS
        psBox := scopeGui.Add("Checkbox", "y+5", "PowerScribe")
        psBox.Value := flags.requirePowerScribe
        scopeGui.Add("Text", "y+10", "Leave both unchecked to activate in any window.")

        if !this.CaptureFunctionDialogState(scopeGui, funcName, listView, rowIndex) {
            scopeGui.Destroy()
            MsgBox(
                "The selected function could not be verified. Refresh the profile and try again.",
                "Function Not Available",
                "Icon!"
            )
            return false
        }

        scopeGui.Add("Button", "y+15 w80", "OK")
            .OnEvent("Click", (*) => this.ApplyScope(funcName, pacsBox.Value, psBox.Value, listView, rowIndex, scopeGui))
        scopeGui.Add("Button", "x+10 w80", "Cancel").OnEvent("Click", (*) => scopeGui.Destroy())
        scopeGui.Show()
    }

    ApplyScope(funcName, requirePACS, requirePowerScribe, listView, rowIndex, scopeGui) {
        if !this.ProfileMutationAllowed("change a keybind scope")
            return false
        if !this.FunctionDialogIsCurrent(scopeGui, funcName, listView)
            return false

        oldScope := ProfileManager.GetScope(funcName)
        newScope := HotkeyManager.ScopeFromFlags(requirePACS, requirePowerScribe)
        currentProfile := ProfileManager.profiles[scopeGui.profileName]
        changed := false

        try {
            ProfileManager.SetScope(funcName, newScope)
            changed := true
            listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
            this.ResizeColumns(listView)

            if !this.ApplyBinds() {
                ProfileManager.SetScope(funcName, oldScope)
                listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
                this.ResizeColumns(listView)
                this.RestoreRuntimeAndNotify(
                    currentProfile,
                    "The scope change was rejected and the previous profile value was retained.",
                    "Scope Recovery Failed",
                    false
                )
                return false
            }

            scopeGui.Destroy()
            this.MarkProfileDirty(scopeGui.profileName)
            return true
        } catch as err {
            if changed
                ProfileManager.SetScope(funcName, oldScope)
            try listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
            try this.ResizeColumns(listView)
            try this.RestoreRuntimeAndNotify(
                currentProfile,
                "The scope change failed and the previous profile value was retained.",
                "Scope Recovery Failed",
                false
            )
            throw err
        }
    }

    ShowModalityAttendingsDialog() {
        if (ProfileManager.GetCurrentProfile() = 0) {
            MsgBox("Load a profile first.", "Error", "Icon!")
            return
        }

        modGui := this.NewProfileDialog("PACS Assistant - Modality Attendings")
        modGui.profileRevision := ProfileManager.GetProfileRevision(modGui.profileName)
        modGui.Add("Text",, "Attending to assign per modality for '" modGui.profileName "'.")
        modGui.Add("Text", "y+5", "Leave a modality blank to keep PowerScribe's default attending.")

        edits := Map()
        for modality in ReportModality.names {
            modGui.Add("Text", "xm y+10 w100", modality ":")
            edits[modality] := modGui.Add("Edit", "x+5 yp-3 w220", ProfileManager.GetModalityAttending(modality))
        }

        modGui.Add("Button", "xm y+15 w80", "Save").OnEvent("Click", (*) => this.SaveModalityAttendings(edits, modGui))
        modGui.Add("Button", "x+10 w80", "Cancel").OnEvent("Click", (*) => modGui.Destroy())
        modGui.Show()
    }

    SaveModalityAttendings(edits, modGui) {
        if !this.ProfileMutationAllowed("save attending assignments")
            return false
        if !this.DialogProfileIsCurrent(modGui)
            return false
        profileName := modGui.profileName
        if (!HasProp(modGui, "profileRevision")
            || modGui.profileRevision != ProfileManager.GetProfileRevision(profileName)) {
            try modGui.Destroy()
            MsgBox(
                "Attending assignments changed while this dialog was open. Reopen it before saving.",
                "Attending Assignments Changed",
                "Icon!"
            )
            return false
        }
        candidate := ProfileManager.CloneProfile(ProfileManager.profiles[profileName])
        for modality, edit in edits {
            candidate.modalityAttendings[modality] := Trim(edit.Value)
        }

        try {
            ProfileManager.SaveProfile(profileName, candidate)
        } catch as err {
            MsgBox("The attending assignments could not be saved. The previous file was left unchanged.`n`n" err.Message, "Save Failed", "Icon!")
            return
        }
        ProfileManager.profiles[profileName] := candidate
        this.ClearProfileDirty(profileName)
        modGui.Destroy()
        return true
    }
}
