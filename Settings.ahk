#Requires AutoHotkey v2.0
#Include AppStorage.ahk

class Settings {
    static settingsFile := AppStorage.DataRoot() "\settings.ini"
    static changeListeners := []
    static mutationGuard := (*) => true
    static dialogGuard := (*) => true
    static writeTransactionActive := false
    static revision := 0
    static minRefreshIntervalSeconds := 10
    ; One day is a deliberate product bound as well as protection from AutoHotkey's
    ; DWORD-backed timer period wrapping after seconds are multiplied by 1000.
    static maxRefreshIntervalSeconds := 86400
    static dialogLogicalWidth := 400
    static dialogLogicalHeight := 420
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

        try {
            AppStorage.Ensure()
            ; Create settings file if it doesn't exist
            if !FileExist(this.settingsFile)
                this.SaveAllSettings()
        } catch as err {
            MsgBox(
                "PACS Assistant could not initialize its writable data folder:`n"
                    . AppStorage.DataRoot() "`n`n" err.Message,
                "PACS Assistant Storage Error",
                "Icon!"
            )
            ExitApp(1)
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
                return (interval >= this.minRefreshIntervalSeconds
                    && interval <= this.maxRefreshIntervalSeconds)
                    ? interval
                    : fallback
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
        this.BeginWriteTransaction()
        try {
            this.WriteSetting(this.settingsFile, settingName, value)
            this.revision++
        } finally this.EndWriteTransaction()
    }

    static NewTemporarySettingsPath() {
        stem := this.settingsFile ".tmp-" DllCall("GetCurrentProcessId") "-"
            . DllCall("GetTickCount64", "UInt64")
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
        this.BeginWriteTransaction()
        try {
            if IsSet(replacer)
                return this.CommitValues(values, replacer)
            return this.CommitValues(values)
        } finally this.EndWriteTransaction()
    }

    static SaveValuesAtRevision(values, expectedRevision) {
        this.BeginWriteTransaction()
        try {
            if (this.revision != expectedRevision)
                throw Error("Settings changed while this dialog was open")
            return this.CommitValues(values)
        } finally this.EndWriteTransaction()
    }

    static CommitValues(values, replacer?) {
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
        this.revision++
        return true
    }

    static RequireMutationAllowed() {
        if !this.mutationGuard.Call()
            throw Error("Settings cannot be changed while a clinical command or shutdown transaction is active")
    }

    static BeginWriteTransaction() {
        Critical("On")
        try {
            ; Recheck the composition-root guard inside the same non-interruptible
            ; boundary that publishes the settings transaction.
            this.RequireMutationAllowed()
            if this.writeTransactionActive
                throw Error("Another settings write is already in progress")
            this.writeTransactionActive := true
        } finally Critical("Off")
    }

    static EndWriteTransaction() {
        Critical("On")
        try this.writeTransactionActive := false
        finally Critical("Off")
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
        if !this.dialogGuard.Call() {
            MsgBox(
                "Wait for the active clinical or configuration operation to finish before opening Settings.",
                "Settings Unavailable",
                "Icon!"
            )
            return false
        }
        settingsGui := Gui(, "PACS Assistant - Settings")
        settingsGui.settingsRevision := this.revision
        settingsGui.SetFont("s10", "Segoe UI")
        checkboxes := Map()
        tab := settingsGui.Add(
            "Tab3",
            "x20 y15 w360 h330",
            ["General", "PowerScribe", "Notifications"]
        )

        tab.UseTab(1)
        settingsGui.Add("GroupBox", "x35 y55 w330 h75", "Updates")
        checkboxes["AutoUpdate"] := settingsGui.Add("Checkbox", "x50 y78", "Automatically check for updates")
        checkboxes["SkipBetaVersions"] := settingsGui.Add("Checkbox", "x50 y103", "Skip beta versions")
        settingsGui.Add("GroupBox", "x35 y140 w330 h175", "PACS and wet reads")
        checkboxes["AutoRefreshPACS"] := settingsGui.Add("Checkbox", "x50 y165", "Auto refresh PACS")
        settingsGui.Add("Text", "x50 y195", "Refresh interval (seconds):")
        refreshIntervalEdit := settingsGui.Add("Edit", "x50 y218 w75 Number", this.Get("RefreshInterval"))
        checkboxes["AutoConvertWetReadLineEndings"] := settingsGui.Add("Checkbox", "x50 y258", "Convert clipboard line endings")

        tab.UseTab(2)
        settingsGui.Add("GroupBox", "x35 y55 w330 h140", "PowerScribe login")
        checkboxes["SwapMicrophoneOnLogin"] := settingsGui.Add("Checkbox", "x50 y82", "Set microphone on login")
        settingsGui.Add("Text", "x50 y115", "Microphone (blank = leave unchanged):")
        micNameEdit := settingsGui.Add("Edit", "x50 y140 w300", this.Get("MicrophoneName"))

        tab.UseTab(3)
        settingsGui.Add("GroupBox", "x35 y55 w330 h260", "New-study notifications")
        checkboxes["AudioAlertNewCase"] := settingsGui.Add("Checkbox", "x50 y80", "Play sound on new case")
        checkboxes["MessageBoxNewCase"] := settingsGui.Add("Checkbox", "x50 y106", "Show Windows notification on new case")
        settingsGui.Add("Text", "x50 y140", "Alert sound:")
        soundDropDown := settingsGui.Add("DropDownList", "x50 y163 w300", this.alertSounds)
        soundDropDown.Value := this.FindSoundIndex(this.Get("AlertSound"))
        settingsGui.Add("Text", "x50 y200", "Custom sound file:")
        customSoundEdit := settingsGui.Add("Edit", "x50 y223 w225 ReadOnly", this.Get("CustomSoundFile"))
        settingsGui.Add("Button", "x285 y221 w65", "Browse")
            .OnEvent("Click", (*) => this.BrowseSound(customSoundEdit))
        settingsGui.Add("Button", "x50 y263 w65", "Test")
            .OnEvent("Click", (*) => this.TestSound(soundDropDown.Text, customSoundEdit.Text))

        for setting, checkbox in checkboxes {
            checkbox.Value := this.Get(setting)
        }

        tab.UseTab()
        controls := {
            checkboxes: checkboxes,
            refreshInterval: refreshIntervalEdit,
            micName: micNameEdit,
            soundDropDown: soundDropDown,
            customSound: customSoundEdit
        }
        settingsGui.Add("Button", "x110 y365 w80 Default", "Save")
            .OnEvent("Click", (*) => this.SaveSettings(controls, settingsGui))
        settingsGui.Add("Button", "x210 y365 w80", "Cancel")
            .OnEvent("Click", (*) => settingsGui.Destroy())

        settingsGui.Show("w" this.dialogLogicalWidth " h" this.dialogLogicalHeight)
        return settingsGui
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
            soundPath := IsSet(customFile) ? customFile : this.Get("CustomSoundFile")
            if (soundPath != "" && FileExist(soundPath)) {
                try {
                    SoundPlay(soundPath)
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
        selectedPath := FileSelect(3,, "Select Sound File", "Sound Files (*.wav; *.mp3)")
        if selectedPath
            editControl.Value := selectedPath
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
        if (!HasProp(settingsGui, "settingsRevision")
            || settingsGui.settingsRevision != this.revision) {
            try settingsGui.Destroy()
            MsgBox(
                "Settings changed while this dialog was open. Reopen it before saving.",
                "Settings Changed",
                "Icon!"
            )
            return false
        }

        ; Validate refresh interval
        try interval := Integer(controls.refreshInterval.Value)
        catch {
            MsgBox("Refresh interval must be a whole number of seconds.", "Invalid Setting", "Icon!")
            return
        }
        if (interval < this.minRefreshIntervalSeconds) {
            MsgBox("Refresh interval must be at least " this.minRefreshIntervalSeconds " seconds.", "Invalid Setting", "Icon!")
            return
        }
        if (interval > this.maxRefreshIntervalSeconds) {
            MsgBox("Refresh interval cannot exceed " this.maxRefreshIntervalSeconds " seconds (one day).", "Invalid Setting", "Icon!")
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

        try this.SaveValuesAtRevision(values, settingsGui.settingsRevision)
        catch as err {
            if (settingsGui.settingsRevision != this.revision) {
                try settingsGui.Destroy()
                MsgBox(
                    "Settings changed while this dialog was being saved. Reopen it before saving.",
                    "Settings Changed",
                    "Icon!"
                )
                return false
            }
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
