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

    __New() {
        ; The launch-time update check belongs to UpdateChecker.Start(), called from
        ; main.ahk under the same AutoUpdate setting. Repeating it here meant a second
        ; GitHub request every launch for a dialog that had already been offered.

        ProfileManager.LoadProfiles()
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

    CreateMainGUI() {
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
        this.gui.Add("Button", "x+10", "Switch Profile").OnEvent("Click", (*) => (this.gui.Destroy(), this.ShowProfileSelector()))

        ; Add Check for Updates button
        this.gui.Add("Button", "x+10", "Check for Updates").OnEvent("Click", (*) => UpdateChecker.ShowUpdateDialog())

        ; Add Settings button
        this.gui.Add("Button", "x+10", "Settings").OnEvent("Click", (*) => Settings.ShowDialog())

        ; Add modality attending assignments
        y += 30
        this.gui.Add("Button", "xm y" y " w160", "Modality Attendings").OnEvent("Click", (*) => this.ShowModalityAttendingsDialog())

        this.gui.OnEvent("Close", (*) => ExitApp())
        this.gui.Show()
        
        this.ApplyBinds()
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
        if (ProfileManager.defaultProfile != "") {
            for i, name in profileNames {
                if (InStr(name, ProfileManager.defaultProfile " *")) {
                    lb.Choose(i)
                    break
                }
            }
        }
        
        ; Add buttons
        buttonGroup := selectorGui.Add("GroupBox", "w190 h150", "Actions")
        
        selectorGui.Add("Button", "xp+10 yp+20 w170", "Select").OnEvent("Click", (*) => this.SelectProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "Set as Default").OnEvent("Click", (*) => this.SetDefaultProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "Rename").OnEvent("Click", (*) => this.PromptRenameProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "Delete Profile").OnEvent("Click", (*) => this.DeleteProfile(StrReplace(lb.Text, " *"), selectorGui))
        selectorGui.Add("Button", "w170", "New Profile").OnEvent("Click", (*) => (selectorGui.Destroy(), this.PromptNewProfile()))
        
        ; Add legend text
        selectorGui.Add("Text", "y+10", "* = Default Profile")
        
        selectorGui.Show()
    }

    PromptNewProfile() {
        inputGui := Gui(, "PACS Assistant - Create New Profile")
        inputGui.Add("Text",, "Enter profile name:")
        nameEdit := inputGui.Add("Edit", "w200")
        inputGui.Add("Button",, "OK").OnEvent("Click", (*) => this.CreateProfile(nameEdit.Value, inputGui))
        inputGui.Show()
    }

    CreateProfile(name, inputGui) {
        if name != "" {
            ProfileManager.profiles[name] := ProfileManager.NewProfile()
            ProfileManager.SaveProfile(name, ProfileManager.profiles[name])
            ProfileManager.currentProfile := name
            inputGui.Destroy()
            this.CreateMainGUI()
        }
    }

    SelectProfile(name, selectorGui) {
        if name != "" {
            ProfileManager.currentProfile := name
            selectorGui.Destroy()
            this.CreateMainGUI()
        }
    }

    SetDefaultProfile(name, selectorGui) {
        if (name = "") {
            MsgBox("Please select a profile first.", "Error", "Icon!")
            return
        }

        if (ProfileManager.SetDefaultProfile(name)) {
            selectorGui.Destroy()
            this.ShowProfileSelector()  ; Refresh the selector to show updated default
        } else {
            MsgBox("Failed to set default profile.", "Error", "Icon!")
        }
    }

    DeleteProfile(name, selectorGui) {
        if (name = "") {
            MsgBox("Please select a profile first.", "Error", "Icon!")
            return
        }

        if (MsgBox("Are you sure you want to delete profile '" name "'?", "Confirm Delete", "YesNo Icon!") = "Yes") {
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
            } else {
                MsgBox("Cannot delete the last remaining profile.", "Error", "Icon!")
            }
        }
    }

    /**
     * Takes ownership of key capture. Only one capture can be in flight at a time.
     * @returns true if capture started
     */
    BeginListening(funcName, control, promptGui) {
        if KeybindGUI.isListening
            return false

        KeybindGUI.isListening := true
        KeybindGUI.listeningControl := control
        this.StartInputHook(funcName, control, promptGui)
        return true
    }

    ; Creates the capture hook and records it so it can always be torn down again
    StartInputHook(funcName, control, promptGui) {
        ih := InputHook("V B")
        ih.KeyOpt("{All}", "E")
        ih.OnEnd := this.OnInputEnd.Bind(this, funcName, control, promptGui)
        KeybindGUI.activeInputHook := ih
        ih.Start()
    }

    OnInputEnd(funcName, control, promptGui, ih?) {
        ; Get current state of modifier keys
        hasCtrl := GetKeyState("Ctrl")
        hasAlt := GetKeyState("Alt")
        hasShift := GetKeyState("Shift")
        hasWin := GetKeyState("LWin") || GetKeyState("RWin")
        
        key := ih.EndKey
        
        ; Handle Escape to cancel
        if (key = "Escape") {
            this.StopListening()
            promptGui.Destroy()
            ; Ensure binds are reapplied even on cancel
            this.ApplyBinds()
            return
        }
        
        ; Skip if the key is just a modifier
        if key ~= "^[LR]?(Control|Alt|Shift|Win)$" {
            ; Create and start a new input hook since the old one is ended
            this.StartInputHook(funcName, control, promptGui)
            return
        }
        
        ; Build the hotkey string
        modifiers := ""
        modifiers .= hasCtrl ? "^" : ""
        modifiers .= hasAlt ? "!" : ""
        modifiers .= hasShift ? "+" : ""
        modifiers .= hasWin ? "#" : ""
        
        newBind := modifiers key
        
        ; Check if this hotkey is already assigned to another function
        currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
        for otherFunc, otherBind in currentProfile.binds {
            if (otherFunc != funcName && otherBind = newBind) {
                MsgBox("This hotkey is already assigned to '" otherFunc "'", "Duplicate Binding", "Icon!")
                this.StopListening()
                promptGui.Destroy()
                ; Ensure binds are reapplied even on duplicate binding
                this.ApplyBinds()
                return
            }
        }
        
        try {
            ; First disable all existing hotkeys
            HotkeyManager.DisableAllHotkeys()
            
            ; Update profile
            ProfileManager.profiles[ProfileManager.currentProfile].binds[funcName] := newBind
            
            ; Find and update the ListView row before destroying the prompt
            Loop control.GetCount() {
                if (control.GetText(A_Index, 1) = funcName) {
                    control.Modify(A_Index,, funcName, this.PrettifyHotkey(newBind))
                    break
                }
            }
            this.ResizeColumns(control)
            this.StopListening()
            promptGui.Destroy()


            ; Reapply all binds
            this.ApplyBinds()
        } catch as err {
            ; If anything goes wrong, ensure we reapply the binds
            this.ApplyBinds()
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
            }
            KeybindGUI.activeInputHook := 0
        }
        KeybindGUI.isListening := false
        KeybindGUI.listeningControl := ""
    }

    SaveCurrentProfile() {
        ProfileManager.SaveProfile(
            ProfileManager.currentProfile,
            ProfileManager.profiles[ProfileManager.currentProfile]
        )
        MsgBox("Profile saved successfully!", "Success")
        this.ApplyBinds()
    }

    ApplyBinds() {
        HotkeyManager.DisableAllHotkeys()
        currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
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
                    result := HotkeyManager.RegisterCustomHotkey(funcName, bind, currentProfile.customFuncs[funcName], scope)
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
        if (failed.Length) {
            errMsg := "These keybinds failed to register:" "`n"
            for item in failed {
                errMsg .= "- " item "`n"
            }
            MsgBox(RTrim(errMsg, "`n"), "Keybind Errors", "Icon!")
        }
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
        if (name = "") {
            MsgBox("Please select a profile first.", "Error", "Icon!")
            return
        }

        renameGui := Gui(, "PACS Assistant - Rename Profile")
        renameGui.Add("Text",, "Enter new name for profile '" name "':")
        nameEdit := renameGui.Add("Edit", "w200", name)
        renameGui.Add("Button",, "OK").OnEvent("Click", (*) => this.RenameProfile(name, nameEdit.Value, renameGui, parentGui))
        renameGui.Add("Button", "x+10", "Cancel").OnEvent("Click", (*) => renameGui.Destroy())
        renameGui.Show()
    }

    RenameProfile(oldName, newName, renameGui, parentGui := 0) {
        if (newName = "") {
            MsgBox("Profile name cannot be empty.", "Error", "Icon!")
            return
        }

        if (ProfileManager.RenameProfile(oldName, newName)) {
            renameGui.Destroy()
            if (parentGui) {
                parentGui.Destroy()
                this.ShowProfileSelector()  ; Refresh the selector
            } else {
                this.gui.Destroy()
                this.CreateMainGUI()  ; Refresh the main GUI
            }
        } else {
            MsgBox("Failed to rename profile. The name may already be in use.", "Error", "Icon!")
        }
    }

    ShowAddFunctionDialog(listView) {
        selectorGui := Gui(, "PACS Assistant - Add Function")
        
        ; Get list of unbound functions, separated by type
        builtInFunctions := []
        customFunctions := []
        
        ; Add built-in functions that aren't bound
        for funcName, _ in ProfileManager.availableFunctions {
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
        selectorGui.Add("Button", "w200", "Create New Custom Keybind").OnEvent("Click", (*) => (selectorGui.Destroy(), this.ShowCustomKeybindDialog(listView)))
        
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
        
        if (MsgBox("Are you sure you want to delete the custom function '" funcName "'?", "Confirm Delete", "YesNo Icon!") = "Yes") {
            currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
            
            ; Remove from current profile's custom functions
            currentProfile.customFuncs.Delete(funcName)
            
            ; Remove from current profile's bindings if it exists
            if (currentProfile.binds.Has(funcName)) {
                currentProfile.binds.Delete(funcName)
            }
            if (currentProfile.scopes.Has(funcName)) {
                currentProfile.scopes.Delete(funcName)
            }

            ; Save the current profile
            ProfileManager.SaveProfile(ProfileManager.currentProfile, currentProfile)

            ; Just destroy both GUIs and recreate them
            selectorGui.Destroy()
            this.gui.Destroy()
            this.CreateMainGUI()
            
            ; Show the add function dialog with the main ListView
            for ctrl in this.gui {
                if (ctrl.Type = "ListView") {
                    this.ShowAddFunctionDialog(ctrl)
                    break
                }
            }
        }
    }

    ShowCustomKeybindDialog(listView) {
        customGui := Gui(, "PACS Assistant - Configure Custom Keybind")
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
        
        ; Check if name already exists in current profile
        if ProfileManager.profiles[ProfileManager.currentProfile].binds.Has(funcName) {
            MsgBox("A keybind with this name already exists in this profile.", "Error", "Icon!")
            return
        }
        
        ; Create the custom function
        ProfileManager.profiles[ProfileManager.currentProfile].customFuncs[funcName] := PACSCommands.CreateCustomKeybind(keys, window)

        ; Add to profile with empty binding, active in any window until scoped
        ProfileManager.profiles[ProfileManager.currentProfile].binds[funcName] := ""
        ProfileManager.profiles[ProfileManager.currentProfile].scopes[funcName] := "Any"

        ; Add to ListView (removed type)
        listView.Add(, funcName, "Unassigned", this.ScopeLabel(funcName))
        this.ResizeColumns(listView)

        customGui.Destroy()
        
        ; Prompt user to set the keybind
        this.PromptKeybind(funcName, listView)
    }

    AddFunction(funcName, listView, selectorGui) {
        if (funcName = "") {
            MsgBox("Please select a function first.", "Error", "Icon!")
            return
        }
        
        ; Add to profile with empty binding, active in any window until scoped
        ProfileManager.profiles[ProfileManager.currentProfile].binds[funcName] := ""
        ProfileManager.profiles[ProfileManager.currentProfile].scopes[funcName] := "Any"

        ; Add to ListView (removed type)
        listView.Add(, funcName, "Unassigned", this.ScopeLabel(funcName))
        this.ResizeColumns(listView)

        selectorGui.Destroy()
        
        ; Prompt user to set the keybind
        this.PromptKeybind(funcName, listView)
    }

    RemoveFunction(listView) {
        if (listView.GetNext(0) = 0) {
            MsgBox("Please select a function to remove.", "Error", "Icon!")
            return
        }
        
        funcName := listView.GetText(listView.GetNext(0), 1)
        if (MsgBox("Remove '" funcName "' from the profile?", "Confirm Remove", "YesNo Icon!") = "Yes") {
            currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
            currentProfile.binds.Delete(funcName)
            if (currentProfile.scopes.Has(funcName)) {
                currentProfile.scopes.Delete(funcName)
            }
            ; No longer delete the custom function itself, only its binding
            listView.Delete(listView.GetNext(0))
            this.ResizeColumns(listView)
            this.ApplyBinds()
        }
    }

    ChangeSelectedKeybind(listView) {
        if (listView.GetNext(0) = 0) {
            MsgBox("Please select a function to change.", "Error", "Icon!")
            return
        }
        
        funcName := listView.GetText(listView.GetNext(0), 1)
        this.PromptKeybind(funcName, listView)
    }

    PromptKeybind(funcName, listView) {
        if KeybindGUI.isListening {
            MsgBox("Already waiting for a keybind. Finish or cancel that one first.", "Keybind In Progress", "Icon!")
            return
        }

        promptGui := Gui(, "PACS Assistant - Set Keybind")
        promptGui.Add("Text",, "Press keys for '" funcName "'...")
        promptGui.Add("Edit", "w200 ReadOnly", "Press keys...")
        promptGui.Add("Button",, "Cancel").OnEvent("Click", (*) => (this.StopListening(), promptGui.Destroy()))

        ; Closing with the X has to tear the hook down as well, otherwise it keeps
        ; capturing and rebinds the next key pressed anywhere
        promptGui.OnEvent("Close", (*) => this.StopListening())

        this.BeginListening(funcName, listView, promptGui)

        promptGui.Show()
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

        scopeGui := Gui(, "PACS Assistant - Keybind Scope")
        scopeGui.Add("Text",, "Only activate '" funcName "' when one of these is the active window:")
        pacsBox := scopeGui.Add("Checkbox", "y+10", "PACS")
        pacsBox.Value := flags.requirePACS
        psBox := scopeGui.Add("Checkbox", "y+5", "PowerScribe")
        psBox.Value := flags.requirePowerScribe
        scopeGui.Add("Text", "y+10", "Leave both unchecked to activate in any window.")

        scopeGui.Add("Button", "y+15 w80", "OK")
            .OnEvent("Click", (*) => this.ApplyScope(funcName, pacsBox.Value, psBox.Value, listView, rowIndex, scopeGui))
        scopeGui.Add("Button", "x+10 w80", "Cancel").OnEvent("Click", (*) => scopeGui.Destroy())
        scopeGui.Show()
    }

    ApplyScope(funcName, requirePACS, requirePowerScribe, listView, rowIndex, scopeGui) {
        ProfileManager.SetScope(funcName, HotkeyManager.ScopeFromFlags(requirePACS, requirePowerScribe))

        listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
        this.ResizeColumns(listView)

        scopeGui.Destroy()
        this.ApplyBinds()
    }

    ShowModalityAttendingsDialog() {
        if (ProfileManager.GetCurrentProfile() = 0) {
            MsgBox("Load a profile first.", "Error", "Icon!")
            return
        }

        modGui := Gui(, "PACS Assistant - Modality Attendings")
        modGui.Add("Text",, "Attending to assign per modality for '" ProfileManager.currentProfile "'.")
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
        for modality, edit in edits {
            ProfileManager.SetModalityAttending(modality, Trim(edit.Value))
        }

        ProfileManager.SaveProfile(
            ProfileManager.currentProfile,
            ProfileManager.profiles[ProfileManager.currentProfile]
        )
        modGui.Destroy()
    }
} 