#Requires AutoHotkey v2.0
#Include PACSCommands.ahk

class ProfileManager {
    static profiles := Map()
    static currentProfile := ""
    static defaultProfile := ""
    static availableFunctions := Map()  ; Now only stores built-in functions

    static __New() {
        ; Initialize available functions from PACSCommands
        this.availableFunctions := PACSCommands.commands

        ; Load default profile setting from config file
        try {
            this.defaultProfile := IniRead("config.ini", "Settings", "DefaultProfile", "")
        }
    }

    ; Single construction point for a profile, so every field is always present
    static NewProfile() {
        return {
            binds: Map(),               ; funcName -> hotkey string
            customFuncs: Map(),         ; funcName -> bound function
            scopes: Map(),              ; funcName -> HotkeyManager scope name
            modalityAttendings: Map()   ; modality -> attending, "" = leave default
        }
    }

    static LoadProfiles() {
        try {
            Loop Files "profiles/*.ini" {
                profileName := StrReplace(A_LoopFileName, ".ini")
                this.profiles[profileName] := this.LoadProfile(A_LoopFilePath)
            }
            ; Set current profile to default if it exists and is valid
            if (this.defaultProfile != "" && this.profiles.Has(this.defaultProfile)) {
                this.currentProfile := this.defaultProfile
            }
        }
    }

    static LoadProfile(path) {
        profile := this.NewProfile()
        try {
            IniRead(path)
            ; Read the ordered list of functions
            functionList := StrSplit(IniRead(path, "Functions", "Order", ""), "|")
            for funcName in functionList {
                if (funcName != "") {
                    profile.binds[funcName] := IniRead(path, "Keybinds", funcName, "")
                    ; Profiles written before scopes existed have no [Scopes] section;
                    ; those binds default to firing in any window, as they always did.
                    profile.scopes[funcName] := IniRead(path, "Scopes", funcName, "Any")
                    ; If it's a custom function, load its configuration
                    if (InStr(funcName, "Custom: ") = 1) {
                        keys := IniRead(path, "CustomFunctions", funcName "_keys", "")
                        window := IniRead(path, "CustomFunctions", funcName "_window", "")
                        if (keys != "") {
                            profile.customFuncs[funcName] := PACSCommands.CreateCustomKeybind(keys, window)
                        }
                    }
                }
            }

            ; Modality -> attending assignments. Only the modalities named in Order are
            ; treated as configured; a modality absent from Order falls back to its
            ; built-in default, while one listed with a blank value means "leave
            ; PowerScribe's default attending alone".
            modalityList := StrSplit(IniRead(path, "ModalityAttendings", "Order", ""), "|")
            for modality in modalityList {
                if (modality != "") {
                    profile.modalityAttendings[modality] := IniRead(path, "ModalityAttendings", modality, "")
                }
            }
        }
        return profile
    }

    static SaveProfile(name, profile) {
        if !DirExist("profiles")
            DirCreate("profiles")

        path := "profiles/" name ".ini"

        ; Save the ordered list of functions
        functionList := ""
        for funcName, _ in profile.binds {
            functionList .= funcName "|"
        }
        IniWrite(functionList, path, "Functions", "Order")

        ; Save the keybinds and their window scopes
        for funcName, bind in profile.binds {
            IniWrite(bind, path, "Keybinds", funcName)
            IniWrite(profile.scopes.Has(funcName) ? profile.scopes[funcName] : "Any", path, "Scopes", funcName)
        }

        ; Save custom function configurations
        for funcName, func in profile.customFuncs {
            if (InStr(funcName, "Custom: ") = 1) {
                IniWrite(func.keys, path, "CustomFunctions", funcName "_keys")
                IniWrite(func.window, path, "CustomFunctions", funcName "_window")
            }
        }

        ; Save modality -> attending assignments
        modalityList := ""
        for modality, _ in profile.modalityAttendings {
            modalityList .= modality "|"
        }
        IniWrite(modalityList, path, "ModalityAttendings", "Order")
        for modality, attending in profile.modalityAttendings {
            IniWrite(attending, path, "ModalityAttendings", modality)
        }
    }

    ; The profile object currently in use, or 0 if none is loaded
    static GetCurrentProfile() {
        if (this.currentProfile != "" && this.profiles.Has(this.currentProfile))
            return this.profiles[this.currentProfile]
        return 0
    }

    ; The scope a bind should be registered under
    static GetScope(funcName) {
        profile := this.GetCurrentProfile()
        if (profile && profile.scopes.Has(funcName))
            return profile.scopes[funcName]
        return "Any"
    }

    static SetScope(funcName, scope) {
        profile := this.GetCurrentProfile()
        if profile
            profile.scopes[funcName] := scope
    }

    /**
     * Attending to assign for a modality.
     * Returns "" when the modality is configured with no attending, which means the
     * report is left with PowerScribe's own default attending.
     * Unconfigured modalities fall back to the modality name, which is the behaviour
     * from before assignments existed.
     */
    static GetModalityAttending(modality) {
        profile := this.GetCurrentProfile()
        if (profile && profile.modalityAttendings.Has(modality))
            return profile.modalityAttendings[modality]
        return modality
    }

    static SetModalityAttending(modality, attending) {
        profile := this.GetCurrentProfile()
        if profile
            profile.modalityAttendings[modality] := attending
    }

    static SetDefaultProfile(name) {
        if !DirExist("profiles")
            DirCreate("profiles")

        this.defaultProfile := name
        try {
            IniWrite(name, "config.ini", "Settings", "DefaultProfile")
            return true
        } catch {
            return false
        }
    }

    static DeleteProfile(name) {
        if (this.profiles.Count <= 1) {
            return false  ; Don't allow deleting the last profile
        }

        try {
            FileDelete("profiles/" name ".ini")
            this.profiles.Delete(name)

            ; If we deleted the default profile, clear it
            if (this.defaultProfile = name) {
                this.defaultProfile := ""
                IniDelete("config.ini", "Settings", "DefaultProfile")
            }
            return true
        } catch {
            return false
        }
    }

    static RenameProfile(oldName, newName) {
        if (oldName = newName)
            return true

        if (newName = "" || this.profiles.Has(newName))
            return false

        try {
            profile := this.profiles[oldName]

            ; Delete old profile
            FileDelete("profiles/" oldName ".ini")
            this.profiles.Delete(oldName)

            ; Create new profile
            this.profiles[newName] := profile
            this.SaveProfile(newName, profile)

            ; Update default profile if needed
            if (this.defaultProfile = oldName) {
                this.SetDefaultProfile(newName)
            }

            ; Update current profile if needed
            if (this.currentProfile = oldName) {
                this.currentProfile := newName
            }

            return true
        } catch {
            return false
        }
    }
}
