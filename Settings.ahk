#Requires AutoHotkey v2.0

class Settings {
    static settingsFile := A_ScriptDir "\settings.ini"
    static defaultSettings := Map(
        "AutoUpdate", true,
        "SkipBetaVersions", true,
        "AutoRefreshPACS", false,
        "RefreshInterval", 60,
        "AudioAlertNewCase", false,
        "MessageBoxNewCase", false,
        "AlertSound", "Default Beep",  ; Name from alertSounds
        "CustomSoundFile", "",         ; Path to custom sound file
        "SwapMicrophoneOnLogin", false,
        "MicrophoneName", ""           ; Blank = leave PowerScribe's selection alone
    )

    ; Settings persisted as "1"/"0" rather than as free text
    static booleanSettings := [
        "AutoUpdate",
        "SkipBetaVersions",
        "AutoRefreshPACS",
        "AudioAlertNewCase",
        "MessageBoxNewCase",
        "SwapMicrophoneOnLogin"
    ]

    ; Alert sounds, each backed by a distinct file shipped in %WinDir%\Media.
    ;
    ; The previous implementation used SoundPlay's "*N" aliases (MessageBeep). Those
    ; do not name sounds, they name *sound scheme events*, and the stock Windows
    ; scheme points several events at one file - Asterisk, Exclamation and the
    ; default beep all resolve to Windows Background.wav, and Question resolves to
    ; nothing at all. Every option therefore played the same thing. Naming the files
    ; directly is what actually makes the choices audibly different.
    static soundFiles := Map(
        "Chime",        "chimes.wav",
        "Ding",         "ding.wav",
        "Chord",        "chord.wav",
        "Notification", "Windows Notify System Generic.wav",
        "Ring",         "Ring01.wav",
        "Alarm",        "Alarm01.wav",
        "Tada",         "tada.wav"
    )

    ; Order shown in the settings dropdown. "Default Beep" is a generated tone, so it
    ; works even on a machine with a stripped Media folder; "Custom File" defers to
    ; the user's own file.
    static alertSounds := [
        "Default Beep",
        "Chime",
        "Ding",
        "Chord",
        "Notification",
        "Ring",
        "Alarm",
        "Tada",
        "Custom File"
    ]

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
        try {
            value := IniRead(this.settingsFile, "Settings", settingName)
            ; Handle numeric values
            if (settingName = "RefreshInterval")
                return Integer(value)
            ; Handle boolean values
            if this.IsBooleanSetting(settingName)
                return value = "1" ? true : false
            ; Return string values as is
            return value
        } catch {
            return this.defaultSettings.Has(settingName) ? this.defaultSettings[settingName] : false
        }
    }

    ; Save a setting value
    static Set(settingName, value) {
        ; Handle numeric values
        if (settingName = "RefreshInterval")
            IniWrite(value, this.settingsFile, "Settings", settingName)
        ; Handle boolean values
        else if this.IsBooleanSetting(settingName)
            IniWrite(value ? "1" : "0", this.settingsFile, "Settings", settingName)
        ; Handle string values
        else
            IniWrite(value, this.settingsFile, "Settings", settingName)
    }
    
    ; Save all settings to their default values
    static SaveAllSettings() {
        for setting, value in this.defaultSettings {
            this.Set(setting, value)
        }
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
        settingsGui.Add("GroupBox", "x" margin " y" y " w" contentWidth " h110", "PACS")  ; Increased height to 110
        checkboxes["AutoRefreshPACS"] := settingsGui.Add("Checkbox", "x" margin+10 " y" y+25, "Auto refresh PACS")
        settingsGui.Add("Text", "x" margin+10 " y+15", "Refresh interval (seconds):")
        refreshIntervalEdit := settingsGui.Add("Edit", "x" margin+10 " y+5 w60 Number", this.Get("RefreshInterval"))

        ; PowerScribe section
        y += 130
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
    static SaveSettings(controls, settingsGui) {
        ; Validate refresh interval
        interval := Integer(controls.refreshInterval.Value)
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

        ; Save all checkbox settings
        for setting, checkbox in controls.checkboxes {
            this.Set(setting, checkbox.Value)
        }

        ; Save refresh interval
        this.Set("RefreshInterval", interval)

        ; Save microphone name
        this.Set("MicrophoneName", micName)

        ; Save sound settings
        this.Set("AlertSound", controls.soundDropDown.Text)
        this.Set("CustomSoundFile", controls.customSound.Text)

        settingsGui.Destroy()

        ; Notify PACSMonitor of settings change
        if IsSet(PACSMonitor)
            PACSMonitor.OnSettingsChanged()

        ; Notify MicrophoneManager of settings change
        if IsSet(MicrophoneManager)
            MicrophoneManager.OnSettingsChanged()
    }
} 