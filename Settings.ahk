#Requires AutoHotkey v2.0

class Settings {
    static settingsFile := A_ScriptDir "\settings.ini"
    static changeListeners := []
    static defaultSettings := Map(
        "AutoUpdate", true,
        "SkipBetaVersions", true,
        "SkippedUpdateVersion", "",
        "AutoRefreshPACS", false,
        "RefreshInterval", 60,
        "AudioAlertNewCase", false,
        "MessageBoxNewCase", false,
        "AlertSound", "Default Beep",  ; Name from alertSounds
        "CustomSoundFile", "",         ; Path to custom sound file
        "AutoConvertWetReadLineEndings", true,  ; Convert LF to CRLF when pasting wet reads
        "SwapMicrophoneOnLogin", false,
        "MicrophoneName", "",          ; Blank = leave PowerScribe's selection alone
        ; Superseded by per-bind scopes, kept only so profiles written under the older
        ; [KeybindScopes] scheme migrate to the right scope. See
        ; ProfileManager.MigrateLegacyScope.
        "RestrictHotkeysByActiveWindow", true
    )

    ; Settings persisted as "1"/"0" rather than as free text
    static booleanSettings := [
        "AutoUpdate",
        "SkipBetaVersions",
        "AutoRefreshPACS",
        "AudioAlertNewCase",
        "MessageBoxNewCase",
        "AutoConvertWetReadLineEndings",
        "SwapMicrophoneOnLogin",
        "RestrictHotkeysByActiveWindow"
    ]

    /**
     * Alert sounds, in the order the settings dropdown shows them, each backed by a
     * distinct file shipped in %WinDir%\Media.
     *
     * This is the only place a sound is declared: alertSounds and soundFiles are
     * derived from it in __New. Keeping a name list and a name-to-file map by hand
     * meant adding a sound to one and not the other silently dropped the option or
     * broke it.
     *
     * A blank file means the entry is not backed by one - "Default Beep" is a
     * synthesised tone, so it works even where the Media folder has been stripped,
     * and "Custom File" defers to the user's own file.
     *
     * The previous implementation used SoundPlay's "*N" aliases (MessageBeep). Those
     * do not name sounds, they name *sound scheme events*, and the stock Windows
     * scheme points several events at one file - Asterisk, Exclamation and the
     * default beep all resolve to Windows Background.wav, and Question resolves to
     * nothing at all. Every option therefore played the same thing. Naming the files
     * directly is what makes the choices audibly different.
     */
    static soundCatalogue := [
        {name: "Default Beep", file: ""},
        {name: "Chime",        file: "chimes.wav"},
        {name: "Ding",         file: "ding.wav"},
        {name: "Chord",        file: "chord.wav"},
        {name: "Notification", file: "Windows Notify System Generic.wav"},
        {name: "Ring",         file: "Ring01.wav"},
        {name: "Alarm",        file: "Alarm01.wav"},
        {name: "Tada",         file: "tada.wav"},
        {name: "Custom File",  file: ""}
    ]

    ; Derived from soundCatalogue in __New
    static alertSounds := []
    static soundFiles := Map()

    ; Sound names written by versions <= v2.0b4, mapped onto their closest replacement
    ; so an existing settings.ini keeps working (and finally sounds distinct).
    static legacySoundAliases := Map(
        "Default",     "Default Beep",
        "Asterisk",    "Notification",
        "Exclamation", "Chime",
        "Hand",        "Chord",
        "Question",    "Ding"
    )

    static __New() {
        ; Derive the dropdown order and the name-to-file lookup from the one catalogue
        for entry in this.soundCatalogue {
            this.alertSounds.Push(entry.name)
            if (entry.file != "")
                this.soundFiles[entry.name] := entry.file
        }

        ; Create settings file if it doesn't exist
        if !FileExist(this.settingsFile) {
            this.SaveAllSettings()
        }
    }

    ; Whether a setting is stored as a boolean flag
    static IsBooleanSetting(settingName) {
        for name in this.booleanSettings {
            if (name = settingName)
                return true
        }
        return false
    }

    ; Get a setting value, returns the default if not found
    static Get(settingName) {
        fallback := this.defaultSettings.Has(settingName)
            ? this.defaultSettings[settingName]
            : false
        try {
            value := IniRead(this.settingsFile, "Settings", settingName)
            ; Handle numeric values
            if (settingName = "RefreshInterval") {
                interval := Integer(value)
                return interval >= 10 ? interval : fallback
            }
            ; Handle boolean values
            if this.IsBooleanSetting(settingName) {
                if (value = "1")
                    return true
                if (value = "0")
                    return false
                return fallback
            }
            ; Return string values as is
            return value
        } catch {
            return fallback
        }
    }

    static WriteSetting(path, settingName, value) {
        ; Handle numeric values
        if (settingName = "RefreshInterval")
            IniWrite(value, path, "Settings", settingName)
        ; Handle boolean values
        else if this.IsBooleanSetting(settingName)
            IniWrite(value ? "1" : "0", path, "Settings", settingName)
        ; Handle string values
        else
            IniWrite(value, path, "Settings", settingName)
    }

    ; Save one setting value. Multi-value GUI changes use SaveValues so callers never
    ; observe a partially written settings form.
    static Set(settingName, value) {
        this.WriteSetting(this.settingsFile, settingName, value)
    }

    static NewTemporarySettingsPath() {
        stem := this.settingsFile ".tmp-" DllCall("GetCurrentProcessId") "-" A_TickCount
        path := stem
        suffix := 0
        while FileExist(path) {
            suffix++
            path := stem "-" suffix
        }
        return path
    }

    /**
     * Applies a settings batch to a same-directory copy and replaces the live file
     * only after every write succeeds. Existing unknown keys and settings managed by
     * other dialogs are retained.
     */
    static SaveValues(values, replacer?) {
        temporaryPath := this.NewTemporarySettingsPath()
        try {
            if FileExist(this.settingsFile)
                FileCopy(this.settingsFile, temporaryPath, true)

            for setting, value in values
                this.WriteSetting(temporaryPath, setting, value)

            if IsSet(replacer)
                replacer.Call(temporaryPath, this.settingsFile)
            else
                FileMove(temporaryPath, this.settingsFile, true)
        } finally {
            try FileDelete(temporaryPath)
        }
    }

    static AddChangeListener(listener) {
        if !IsObject(listener) || !HasMethod(listener, "Call")
            throw TypeError("Settings change listener must be callable")
        this.changeListeners.Push(listener)
        return listener
    }

    static NotifyChanged() {
        errors := []
        for listener in this.changeListeners.Clone() {
            try listener.Call()
            catch as err {
                errors.Push(err.Message)
                OutputDebug("Settings change listener failed: " err.Message)
            }
        }
        return errors
    }
    
    ; Save all settings to their default values
    static SaveAllSettings() {
        this.SaveValues(this.defaultSettings)
    }
    
    ; Show settings dialog
    static ShowDialog() {
        ; Create GUI with proper margins
        settingsGui := Gui("+AlwaysOnTop +MinSize320", "PACS Assistant - Settings")
        settingsGui.SetFont("s10", "Segoe UI")
        
        ; Constants for layout
        margin := 20  ; Margin from window edge
        width := 320  ; Total window width
        contentWidth := width - (margin * 2)  ; Width of content area
        
        ; Create checkboxes for each setting
        y := margin
        checkboxes := Map()
        
        ; Updates section
        settingsGui.Add("GroupBox", "x" margin " y" y " w" contentWidth " h80", "Updates")
        checkboxes["AutoUpdate"] := settingsGui.Add("Checkbox", "x" margin+10 " y" y+25, "Automatically check for updates")
        checkboxes["SkipBetaVersions"] := settingsGui.Add("Checkbox", "x" margin+10 " y+10", "Skip beta versions")
        
        ; PACS section
        y += 100  ; Consistent spacing between sections
        settingsGui.Add("GroupBox", "x" margin " y" y " w" contentWidth " h140", "PACS")
        pacsY := y + 25
        checkboxes["AutoRefreshPACS"] := settingsGui.Add("Checkbox", "x" margin+10 " y" pacsY, "Auto refresh PACS")
        pacsY += 28
        settingsGui.Add("Text", "x" margin+10 " y" pacsY, "Refresh interval (seconds):")
        ; The edit sits below its label, not 5px under it - at the old offset the two
        ; drew on top of each other
        refreshIntervalEdit := settingsGui.Add("Edit", "x" margin+10 " y" pacsY+22 " w60 Number", this.Get("RefreshInterval"))
        pacsY += 52
        checkboxes["AutoConvertWetReadLineEndings"] := settingsGui.Add("Checkbox", "x" margin+10 " y" pacsY, "Convert clipboard line endings")

        ; Hotkey scope is set per keybind now (main window > Set Scope), so there is no
        ; global restrict checkbox here any more.

        ; PowerScribe section
        y += 160
        settingsGui.Add("GroupBox", "x" margin " y" y " w" contentWidth " h120", "PowerScribe")
        checkboxes["SwapMicrophoneOnLogin"] := settingsGui.Add("Checkbox", "x" margin+10 " y" y+25, "Set microphone on login")
        settingsGui.Add("Text", "x" margin+10 " y+15", "Microphone (blank = leave unchanged):")
        micNameEdit := settingsGui.Add("Edit", "x" margin+10 " y+5 w" contentWidth-20, this.Get("MicrophoneName"))

        ; Notifications section
        y += 140  ; Increased spacing between sections
        notificationsY := y
        
        ; Calculate height for notifications section based on its contents:
        ; - 25px top padding
        ; - 2 checkboxes (25px each + 10px spacing) = 60px
        ; - Alert Sound (20px label + 5px + 25px dropdown) = 50px
        ; - Custom Sound (20px label + 5px + 25px edit/browse) = 50px
        ; - 15px spacing
        ; - Test button (25px)
        ; - 25px bottom padding
        notificationsHeight := 250  ; Total height needed
        
        ; Add the notifications groupbox first
        settingsGui.Add("GroupBox", "x" margin " y" notificationsY " w" contentWidth " h" notificationsHeight, "Notifications")
        
        ; Add all notification controls with consistent spacing
        y := notificationsY  ; Reset y to start of notifications section
        checkboxes["AudioAlertNewCase"] := settingsGui.Add("Checkbox", "x" margin+10 " y" y+25, "Play sound on new case")
        checkboxes["MessageBoxNewCase"] := settingsGui.Add("Checkbox", "x" margin+10 " y+10", "Show message box on new case")
        
        ; Sound selection
        settingsGui.Add("Text", "x" margin+10 " y+15", "Alert Sound:")
        soundDropDown := settingsGui.Add("DropDownList", "x" margin+10 " y+5 w" contentWidth-20, this.alertSounds)
        soundDropDown.Value := this.FindSoundIndex(this.Get("AlertSound"))
        
        ; Custom sound file section
        settingsGui.Add("Text", "x" margin+10 " y+15", "Custom Sound File:")
        customSoundEdit := settingsGui.Add("Edit", "x" margin+10 " y+5 w" contentWidth-90 " ReadOnly", this.Get("CustomSoundFile"))
        settingsGui.Add("Button", "x+5 yp w60", "Browse").OnEvent("Click", (*) => this.BrowseSound(customSoundEdit))
        
        ; Test button with adjusted spacing
        settingsGui.Add("Button", "x" margin+10 " y+10 w60", "Test")  ; Changed from y+15 to y+10
            .OnEvent("Click", (*) => this.TestSound(soundDropDown.Text, customSoundEdit.Text))
        
        ; Set current values
        for setting, checkbox in checkboxes {
            checkbox.Value := this.Get(setting)
        }
        
        ; Add Save and Cancel buttons below the notifications section
        y := notificationsY + notificationsHeight + 20  ; Consistent 20px spacing after section
        
        ; Add Save and Cancel buttons in a centered position
        buttonWidth := 80
        spacing := 10
        totalButtonWidth := (buttonWidth * 2) + spacing
        startX := margin + (contentWidth - totalButtonWidth) // 2
        
        ; Add buttons with proper alignment
        controls := {
            checkboxes: checkboxes,
            refreshInterval: refreshIntervalEdit,
            micName: micNameEdit,
            soundDropDown: soundDropDown,
            customSound: customSoundEdit
        }
        settingsGui.Add("Button", "x" startX " y" y " w" buttonWidth, "Save")
            .OnEvent("Click", (*) => this.SaveSettings(controls, settingsGui))
        settingsGui.Add("Button", "x+" spacing " yp w" buttonWidth, "Cancel")
            .OnEvent("Click", (*) => settingsGui.Destroy())
        
        ; Add bottom margin
        y += margin * 2
        settingsGui.Add("Text", "x" margin " y" y " w0 h0")  ; Invisible control to enforce bottom margin
        
        settingsGui.Show()
    }
    
    ; Find index of sound in alertSounds array
    static FindSoundIndex(sound) {
        sound := this.NormalizeSoundName(sound)
        loop this.alertSounds.Length {
            if (this.alertSounds[A_Index] = sound)
                return A_Index
        }
        return 1  ; Default if not found
    }

    ; Map a stored sound name onto a currently supported one
    static NormalizeSoundName(sound) {
        if this.legacySoundAliases.Has(sound)
            return this.legacySoundAliases[sound]
        for name in this.alertSounds {
            if (name = sound)
                return name
        }
        return "Default Beep"
    }

    ; Full path of the .wav backing a named sound, or "" if it has no file
    ; (or the file is missing on this machine)
    static ResolveSoundFile(sound) {
        sound := this.NormalizeSoundName(sound)
        if !this.soundFiles.Has(sound)
            return ""
        path := A_WinDir "\Media\" this.soundFiles[sound]
        return FileExist(path) ? path : ""
    }

    ; Play an alert sound. Returns true if the requested sound played; false if it
    ; could not and the fallback beep was used instead - the alert is never silent.
    static PlayAlertSound(sound, customFile?) {
        sound := this.NormalizeSoundName(sound)

        if (sound = "Custom File") {
            file := IsSet(customFile) ? customFile : this.Get("CustomSoundFile")
            if (file != "" && FileExist(file)) {
                try {
                    SoundPlay(file)
                    return true
                }
            }
            SoundBeep(750, 300)
            return false
        }

        if (sound != "Default Beep") {
            path := this.ResolveSoundFile(sound)
            if (path != "") {
                try {
                    SoundPlay(path)
                    return true
                }
            }
            SoundBeep(750, 300)
            return false
        }

        SoundBeep(750, 300)
        return true
    }

    ; Browse for custom sound file
    static BrowseSound(editControl) {
        file := FileSelect(3,, "Select Sound File", "Sound Files (*.wav; *.mp3)")
        if file
            editControl.Value := file
    }

    ; Test selected sound
    static TestSound(selectedSound, customFile) {
        if this.PlayAlertSound(selectedSound, customFile)
            return

        if (selectedSound = "Custom File")
            MsgBox("Could not play the custom sound file. Check that the file still exists and is a .wav or .mp3.", "Error", "Icon!")
        else
            MsgBox("'" selectedSound "' is not available on this machine (missing from " A_WinDir "\Media). Played the default beep instead.", "Sound Unavailable", "Icon!")
    }
    
    ; Save settings from GUI
    static SaveSettings(controls, settingsGui, liveRefreshFailureNotifier?) {
        ; Validate refresh interval
        try interval := Integer(controls.refreshInterval.Value)
        catch {
            MsgBox("Refresh interval must be a whole number of seconds.", "Invalid Setting", "Icon!")
            return
        }
        if (interval < 10) {
            MsgBox("Refresh interval must be at least 10 seconds.", "Invalid Setting", "Icon!")
            return
        }

        ; Validate the microphone name is present when the swap is enabled, otherwise
        ; the setting silently does nothing
        micName := Trim(controls.micName.Value)
        if (controls.checkboxes["SwapMicrophoneOnLogin"].Value && micName = "") {
            MsgBox("Enter a microphone name to select on login, or turn off 'Set microphone on login'.", "Invalid Setting", "Icon!")
            return
        }

        values := Map()

        ; Collect all checkbox settings
        for setting, checkbox in controls.checkboxes {
            values[setting] := checkbox.Value
        }

        values["RefreshInterval"] := interval
        values["MicrophoneName"] := micName
        values["AlertSound"] := controls.soundDropDown.Text
        values["CustomSoundFile"] := controls.customSound.Text

        try this.SaveValues(values)
        catch as err {
            MsgBox(
                "The settings could not be saved. The previous file was left unchanged.`n`n" err.Message,
                "Save Failed",
                "Icon!"
            )
            return false
        }

        settingsGui.Destroy()
        listenerErrors := this.NotifyChanged()
        if listenerErrors.Length {
            details := ""
            for message in listenerErrors
                details .= (details = "" ? "" : "`n") "- " message
            serviceLabel := listenerErrors.Length = 1 ? "running service" : "running services"
            warning := "The settings were saved, but " listenerErrors.Length
                . " " serviceLabel " could not apply them. Restart PACS Assistant to apply every change."
                . (details = "" ? "" : "`n`n" details)
            if IsSet(liveRefreshFailureNotifier)
                liveRefreshFailureNotifier.Call(warning, listenerErrors)
            else
                MsgBox(warning, "Settings Need Restart", "Icon!")
            return false
        }
        return true
    }
}
