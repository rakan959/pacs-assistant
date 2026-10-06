; = CONTENTS
;   + Preamble
;   + Settings class (settings load/save, change listeners, mutation/dialog guards, settings dialog)
;   + SettingsConflictError (stale-revision save)

#Requires AutoHotkey v2.0
#Include AppStorage.ahk
#Include AppLog.ahk
#Include Version.ahk
#Include UITheme.ahk

class Settings {
    static settingsFile := AppStorage.DataRoot() "\settings.ini"
    static changeListeners := []
    static mutationGuard := (*) => true
    static dialogAcquire := (*) => true
    static dialogRelease := (*) => 0
    static dialogUnavailableNotifier := (text, title, options) => TrayTip(text, title, options)
    static writeTransactionActive := false
    static revision := 0
    static minRefreshIntervalSeconds := 10
    ; One day is a deliberate product bound as well as protection from AutoHotkey's
    ; DWORD-backed timer period wrapping after seconds are multiplied by 1000.
    static maxRefreshIntervalSeconds := 86400
    static dialogLogicalWidth := 440
    static dialogLogicalHeight := 420
    ; Keys are PascalCase, unlike other map keys (style guide s4), because each one is
    ; also the persisted settings.ini key name.
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
        "SwapMicrophoneOnLogin",
        "RestrictHotkeysByActiveWindow"
    ]

    /**
     * Alert sounds, in the order the settings dropdown shows them, each backed by a
     * distinct file shipped in %WinDir%\Media.
     *
     * This is the only place a sound is declared: alertSounds and soundFiles are
     * derived from it in __New, so the dropdown and the file lookup cannot disagree.
     *
     * A blank file means the entry is not backed by one - "Default Beep" is a
     * synthesised tone, so it works even where the Media folder has been stripped,
     * and "Custom File" defers to the user's own file.
     *
     * Sounds are named by file rather than by SoundPlay's "*N" aliases (MessageBeep).
     * Those name sound-scheme events, and the stock Windows scheme points Asterisk,
     * Exclamation and the default beep at one file (Windows Background.wav) and
     * Question at none, so the choices would not sound different.
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
    ; so an existing settings.ini keeps working.
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

    static TryParseRefreshInterval(value, &interval) {
        interval := 0
        if value is Integer {
            interval := value
            return true
        }
        ; Integer() truncates decimal strings, accepts exponent or signed forms, and
        ; wraps values beyond the 64-bit range. Persisted/user-entered seconds must
        ; be literal whole decimal digits so malformed text cannot silently become a
        ; different timer period; a value too long to convert saturates instead of
        ; wrapping, so the range check rejects it as too large.
        if (Type(value) != "String" || !RegExMatch(value, "^\d+$"))
            return false
        interval := StrLen(LTrim(value, "0")) > 18 ? 0x7FFFFFFFFFFFFFFF : Integer(value)
        return true
    }

    ; Get a setting value, returns the default if not found
    static Get(settingName) {
        fallback := this.defaultSettings.Has(settingName)
            ? this.defaultSettings[settingName]
            : false
        ; With a Default, IniRead returns it for a missing file, section or key; only
        ; an unreadable file raises. Parsing below must not hide its own bugs.
        try value := IniRead(this.settingsFile, "Settings", settingName, fallback)
        catch OSError
            return fallback

        if (settingName = "RefreshInterval") {
            if !this.TryParseRefreshInterval(value, &interval)
                return fallback
            return (interval >= this.minRefreshIntervalSeconds
                && interval <= this.maxRefreshIntervalSeconds)
                ? interval
                : fallback
        }
        if this.IsBooleanSetting(settingName) {
            if (value = "1")
                return true
            if (value = "0")
                return false
            return fallback
        }
        return value
    }

    ; Booleans persist as "1"/"0"; every other value is written as text.
    static WriteSetting(path, settingName, value) {
        IniWrite(this.IsBooleanSetting(settingName) ? (value ? "1" : "0") : value, path, "Settings", settingName)
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
                throw SettingsConflictError("Settings changed while this dialog was open")
            return this.CommitValues(values)
        } finally this.EndWriteTransaction()
    }

    static CommitValues(values, replacer?) {
        temporaryPath := AppStorage.UniqueSiblingPath(this.settingsFile, "tmp")
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
            ; Only a failed write or replace leaves the temporary copy behind.
            if FileExist(temporaryPath)
                try FileDelete(temporaryPath)
        }
        this.revision++
        return true
    }

    static RequireMutationAllowed() {
        if !this.mutationGuard.Call()
            throw Error("Settings cannot be changed while a clinical command, key capture, profile change, dialog or shutdown is in progress")
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
            ; catch Any: one failing listener must not stop the others.
            try listener.Call()
            catch Any as err {
                errors.Push(ErrorText.Message(err))
                AppLog.Write("Settings change listener failed: " ErrorText.Describe(err))
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
        ; The presentation lease excludes every clinical, capture, profile, settings
        ; and shutdown operation while the window is built; it is released once Show
        ; returns. Save is gated separately, by BeginWriteTransaction.
        if !this.dialogAcquire.Call("open Settings") {
            this.dialogUnavailableNotifier.Call(
                "Wait for the active clinical or configuration operation to finish before opening Settings.",
                "Settings Unavailable",
                "Icon!"
            )
            return false
        }
        try {
            settingsGui := UITheme.NewWindow("PACS Assistant - Settings")
            settingsGui.settingsRevision := this.revision
            checkboxes := Map()
            width := this.dialogLogicalWidth - 2 * UITheme.margin
            ; Page content sits inside the tab's border; x/w below are for that column.
            x := UITheme.margin + 16
            w := width - 32
            tab := settingsGui.Add(
                "Tab3",
                "xm ym w" width " h312",
                ["General", "PowerScribe", "Notifications"]
            )

            tab.UseTab(1)
            UITheme.AddSectionLabel(settingsGui, "Updates", "x" x " y" (UITheme.margin + 44) " w" w)
            checkboxes["AutoUpdate"] := settingsGui.Add("Checkbox", "x" x " y+8 w" w, "Check for updates &automatically")
            checkboxes["SkipBetaVersions"] := settingsGui.Add("Checkbox", "x" x " y+6 w" w, "Skip &beta versions")
            if AppVersion.isDevBuild
                UITheme.AddNote(settingsGui, "This is a development build, so it never checks for updates.", "x" x " y+6 w" w)
            UITheme.AddSectionLabel(settingsGui, "PACS worklist", "x" x " y+18 w" w)
            checkboxes["AutoRefreshPACS"] := settingsGui.Add("Checkbox", "x" x " y+8 w" w, "&Refresh PACS and scan for new studies automatically")
            settingsGui.Add("Text", "x" x " y+12", "Every")
            refreshIntervalEdit := settingsGui.Add("Edit", "x+6 yp-3 w64 Number Right", this.Get("RefreshInterval"))
            settingsGui.Add("Text", "x+6 yp+3", "seconds (" this.minRefreshIntervalSeconds " or more)")
            UITheme.AddNote(
                settingsGui,
                "New studies are announced only while a sound or notification is turned on in the Notifications tab.",
                "x" x " y+10 w" w
            )

            tab.UseTab(2)
            UITheme.AddSectionLabel(settingsGui, "Microphone", "x" x " y" (UITheme.margin + 44) " w" w)
            checkboxes["SwapMicrophoneOnLogin"] := settingsGui.Add("Checkbox", "x" x " y+8 w" w, "Select a &microphone when PowerScribe logs in")
            settingsGui.Add("Text", "x" x " y+12 w" w, "Microphone &name")
            micNameEdit := settingsGui.Add("Edit", "x" x " y+4 w" w, this.Get("MicrophoneName"))
            UITheme.SetPlaceholder(micNameEdit, "For example, PowerMic")
            UITheme.AddNote(
                settingsGui,
                "An exact device name is best. A partial name such as PowerMic works when it matches only one device.",
                "x" x " y+6 w" w
            )

            tab.UseTab(3)
            UITheme.AddSectionLabel(settingsGui, "When a new study arrives", "x" x " y" (UITheme.margin + 44) " w" w)
            checkboxes["AudioAlertNewCase"] := settingsGui.Add("Checkbox", "x" x " y+8 w" w, "Play a &sound")
            checkboxes["MessageBoxNewCase"] := settingsGui.Add("Checkbox", "x" x " y+6 w" w, "Show a &Windows notification")
            UITheme.AddSectionLabel(settingsGui, "Sound", "x" x " y+18 w" w)
            buttonWidth := UITheme.buttonWidth
            soundDropDown := settingsGui.Add("DropDownList", "x" x " y+8 w" (w - buttonWidth - UITheme.gap), this.alertSounds)
            soundDropDown.Value := this.FindSoundIndex(this.Get("AlertSound"))
            settingsGui.Add("Button", "x+" UITheme.gap " yp-1 w" buttonWidth " h" UITheme.buttonHeight, "&Test")
                .OnEvent("Click", (*) => (
                    settingsGui.Opt("+OwnDialogs"),
                    this.TestSound(soundDropDown.Text, customSoundEdit.Text)
                ))
            settingsGui.Add("Text", "x" x " y+12 w" w, "Custom sound file")
            customSoundEdit := settingsGui.Add("Edit", "x" x " y+4 w" (w - buttonWidth - UITheme.gap) " ReadOnly", this.Get("CustomSoundFile"))
            browseButton := settingsGui.Add("Button", "x+" UITheme.gap " yp-2 w" buttonWidth " h" UITheme.buttonHeight, "Br&owse...")
            browseButton.OnEvent("Click", (*) => (
                settingsGui.Opt("+OwnDialogs"),
                this.BrowseSound(customSoundEdit)
            ))
            UITheme.AddNote(settingsGui, "A .wav or .mp3 file, played when the sound is Custom File.", "x" x " y+6 w" w)

            for setting, checkbox in checkboxes {
                checkbox.Value := this.Get(setting)
            }

            ; Controls that only matter for one choice follow it.
            syncMicrophone := (*) => micNameEdit.Enabled := checkboxes["SwapMicrophoneOnLogin"].Value
            checkboxes["SwapMicrophoneOnLogin"].OnEvent("Click", syncMicrophone)
            syncMicrophone()
            syncCustomSound := (*) => browseButton.Enabled := soundDropDown.Text = "Custom File"
            soundDropDown.OnEvent("Change", syncCustomSound)
            syncCustomSound()

            tab.UseTab()
            controls := {
                checkboxes: checkboxes,
                refreshInterval: refreshIntervalEdit,
                micName: micNameEdit,
                soundDropDown: soundDropDown,
                customSound: customSoundEdit
            }
            cancel := (*) => settingsGui.Destroy()
            UITheme.AddFooter(settingsGui, width, [
                {
                    text: "Save",
                    default: true,
                    action: (*) => (settingsGui.Opt("+OwnDialogs"), this.SaveSettings(controls, settingsGui))
                },
                {text: "Cancel", action: cancel}
            ])
            ; The title-bar X must destroy like Cancel; Close only hides by default.
            settingsGui.OnEvent("Close", cancel)
            settingsGui.OnEvent("Escape", cancel)

            settingsGui.Show("w" this.dialogLogicalWidth " h" this.dialogLogicalHeight)
            return settingsGui
        } finally this.dialogRelease.Call()
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
            MsgBox("Could not play the custom sound file. Check that the file still exists and is a .wav or .mp3.", "Sound Unavailable", "Icon!")
        else
            MsgBox("'" selectedSound "' is not available on this machine (missing from " A_WinDir "\Media). Played the default beep instead.", "Sound Unavailable", "Icon!")
    }

    ; Save settings from GUI
    static SaveSettings(controls, settingsGui) {
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
        if !this.TryParseRefreshInterval(controls.refreshInterval.Value, &interval) {
            MsgBox("Refresh interval must be a whole number of seconds.", "Invalid Setting", "Icon!")
            return false
        }
        if (interval < this.minRefreshIntervalSeconds) {
            MsgBox("Refresh interval must be at least " this.minRefreshIntervalSeconds " seconds.", "Invalid Setting", "Icon!")
            return false
        }
        if (interval > this.maxRefreshIntervalSeconds) {
            MsgBox("Refresh interval cannot exceed " this.maxRefreshIntervalSeconds " seconds (one day).", "Invalid Setting", "Icon!")
            return false
        }

        ; Validate the microphone name is present when the swap is enabled, otherwise
        ; the setting silently does nothing
        micName := Trim(controls.micName.Value)
        if (controls.checkboxes["SwapMicrophoneOnLogin"].Value && micName = "") {
            MsgBox("Enter a microphone name to select on login, or turn off 'Set microphone on login'.", "Invalid Setting", "Icon!")
            return false
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
            AppLog.Write("Settings could not be saved: " ErrorText.Describe(err))
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
            MsgBox(warning, "Settings Need Restart", "Icon!")
            return false
        }
        return true
    }
}

; Raised when a dialog saves against a settings revision that has since changed,
; so callers can tell a stale dialog from a failed write without parsing text.
class SettingsConflictError extends Error {
}
