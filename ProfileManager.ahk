#Requires AutoHotkey v2.0
#Include PACSCommands.ahk
#Include Settings.ahk

class ProfileManager {
    static profiles := Map()
    static currentProfile := ""
    static defaultProfile := ""
    static availableFunctions := Map()  ; Now only stores built-in functions
    static configPath := A_ScriptDir "\config.ini"
    static profilesPath := A_ScriptDir "\profiles"
    static loadErrors := []
    static saveSequence := 0
    static missingValue := "{PACS-ASSISTANT-MISSING-INI-VALUE}"

    static __New() {
        ; Initialize available functions from PACSCommands
        this.availableFunctions := PACSCommands.commands

        ; Load default profile setting from config file
        try {
            this.defaultProfile := IniRead(this.configPath, "Settings", "DefaultProfile", "")
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
        ; Always refresh the in-memory profiles from disk
        previousProfile := this.currentProfile
        this.profiles := Map()
        this.loadErrors := []

        if DirExist(this.profilesPath) {
            Loop Files this.profilesPath "\*.ini" {
                profileName := StrReplace(A_LoopFileName, ".ini")
                try {
                    this.profiles[profileName] := this.LoadProfile(A_LoopFilePath)
                } catch as err {
                    this.loadErrors.Push({path: A_LoopFilePath, message: err.Message})
                }
            }
        }

        ; Prefer the configured default, otherwise preserve the current selection if
        ; it still exists. Never leave currentProfile pointing at a skipped file.
        if (this.defaultProfile != "" && this.profiles.Has(this.defaultProfile))
            this.currentProfile := this.defaultProfile
        else if (previousProfile != "" && this.profiles.Has(previousProfile))
            this.currentProfile := previousProfile
        else
            this.currentProfile := ""
    }

    static LoadProfile(path) {
        profile := this.NewProfile()
        IniRead(path)

        ; Every profile version has written [Functions] Order, including a newly
        ; created empty profile. Its absence distinguishes a malformed .ini from an
        ; intentionally empty profile.
        functionOrder := IniRead(path, "Functions", "Order", this.missingValue)
        if (functionOrder = this.missingValue)
            throw Error("Profile is missing [Functions] Order")

        ; Read the ordered list of functions
        functionList := StrSplit(functionOrder, "|")
        for funcName in functionList {
            if (funcName != "") {
                this.RequireSafeIniKey(funcName, "function")
                profile.binds[funcName] := IniRead(path, "Keybinds", funcName, "")
                ; Profiles written before scopes existed have no [Scopes] section;
                ; those binds default to firing in any window, as they always did.
                ; [KeybindScopes] is the older per-bind format and is migrated.
                profile.scopes[funcName] := IniRead(path, "Scopes", funcName, "")
                if (profile.scopes[funcName] = "") {
                    legacy := IniRead(path, "KeybindScopes", funcName, "")
                    profile.scopes[funcName] := this.MigrateLegacyScope(legacy)
                }
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
                this.RequireSafeIniKey(modality, "modality")
                profile.modalityAttendings[modality] := IniRead(path, "ModalityAttendings", modality, "")
            }
        }
        this.ValidateProfile(profile)
        return profile
    }

    static SaveProfile(name, profile) {
        if !this.IsValidProfileName(name)
            throw ValueError("Invalid profile name")
        this.ValidateProfile(profile)

        if !DirExist(this.profilesPath)
            DirCreate(this.profilesPath)

        path := this.ProfilePath(name)
        this.saveSequence++
        temporaryPath := path ".tmp-" DllCall("GetCurrentProcessId") "-" this.saveSequence

        try {
            this.WriteProfile(temporaryPath, profile)
            FileMove(temporaryPath, path, true)
        } catch as err {
            try FileDelete(temporaryPath)
            throw err
        }

        return true
    }

    static WriteProfile(path, profile) {
        ; The caller always provides a fresh temporary path. Writing a complete new
        ; file avoids stale INI keys and lets the final same-directory move replace
        ; the prior profile atomically.
        if FileExist(path)
            FileDelete(path)

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

    static ValidateProfile(profile) {
        for property in ["binds", "customFuncs", "scopes", "modalityAttendings"] {
            if !HasProp(profile, property) || !(profile.%property% is Map)
                throw TypeError("Profile is missing Map property: " property)
        }

        bindingOwners := Map()
        for funcName, bind in profile.binds {
            this.RequireSafeIniKey(funcName, "function")
            identity := StrLower(Trim(bind))
            if (identity != "") {
                if bindingOwners.Has(identity)
                    throw ValueError("Profile contains duplicate hotkey '" bind "' for '" bindingOwners[identity] "' and '" funcName "'")
                bindingOwners[identity] := funcName
            }
        }
        for funcName, _ in profile.customFuncs
            this.RequireSafeIniKey(funcName, "function")
        for funcName, _ in profile.scopes
            this.RequireSafeIniKey(funcName, "function")
        for modality, _ in profile.modalityAttendings
            this.RequireSafeIniKey(modality, "modality")
    }

    static RequireSafeIniKey(name, kind) {
        if !this.IsSafeIniKey(name)
            throw ValueError("Profile contains an unsafe " kind " name")
    }

    static IsSafeIniKey(name) {
        return Type(name) = "String"
            && name != ""
            && !RegExMatch(name, "[\x00-\x1F|=\[\]]")
    }

    static IsValidProfileName(name) {
        if (Type(name) != "String" || name = "" || name != Trim(name))
            return false
        if (name = "." || name = ".." || RegExMatch(name, "[\x00-\x1F<>:`"/\\|?*]"))
            return false
        if RegExMatch(name, "[ .]$")
            return false
        return !RegExMatch(name, "i)^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$")
    }

    static ProfilePath(name) {
        if !this.IsValidProfileName(name)
            throw ValueError("Invalid profile name")
        return this.profilesPath "\" name ".ini"
    }

    static CreateProfile(name) {
        if !this.IsValidProfileName(name) || this.profiles.Has(name)
            return false

        try {
            if FileExist(this.ProfilePath(name))
                return false
            profile := this.NewProfile()
            this.SaveProfile(name, profile)
            this.profiles[name] := profile
            return true
        } catch {
            return false
        }
    }

    /**
     * Maps a scope written under the older [KeybindScopes] scheme onto the current
     * per-bind scopes.
     *
     * That scheme stored "global" / "restricted" / "default", where "restricted"
     * meant any of PACS, PowerScribe or EPIC and "default" deferred to the
     * RestrictHotkeysByActiveWindow setting. Dropping those values would silently
     * unrestrict every bind in an existing profile, so they are translated instead.
     * "restricted" becomes "PACS or PowerScribe" - the nearest equivalent, though it
     * no longer covers EPIC.
     */
    static MigrateLegacyScope(legacy) {
        switch legacy {
            case "global": return "Any"
            case "restricted": return "PACS or PowerScribe"
            case "default": return Settings.Get("RestrictHotkeysByActiveWindow") ? "PACS or PowerScribe" : "Any"
            default: return "Any"
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
        if !this.IsValidProfileName(name) || !this.profiles.Has(name)
            return false

        try {
            IniWrite(name, this.configPath, "Settings", "DefaultProfile")
            this.defaultProfile := name
            return true
        } catch {
            return false
        }
    }

    static DeleteProfile(name) {
        if (this.profiles.Count <= 1 || !this.profiles.Has(name) || !this.IsValidProfileName(name)) {
            return false  ; Don't allow deleting the last profile
        }

        try {
            FileDelete(this.ProfilePath(name))
            this.profiles.Delete(name)

            ; If we deleted the default profile, clear it
            if (this.defaultProfile = name) {
                this.defaultProfile := ""
                IniDelete(this.configPath, "Settings", "DefaultProfile")
            }
            return true
        } catch {
            return false
        }
    }

    static RenameProfile(oldName, newName) {
        if (oldName = newName)
            return true

        if (!this.IsValidProfileName(oldName)
            || !this.IsValidProfileName(newName)
            || !this.profiles.Has(oldName)
            || this.profiles.Has(newName))
            return false

        oldPath := this.ProfilePath(oldName)
        newPath := this.ProfilePath(newName)
        if FileExist(newPath)
            return false

        profile := this.profiles[oldName]
        try {
            ; Persist the replacement before touching the original. SaveProfile's
            ; temporary-file move guarantees a failed save cannot truncate it.
            this.SaveProfile(newName, profile)
        } catch {
            return false
        }

        defaultChanged := this.defaultProfile = oldName
        if defaultChanged {
            try {
                IniWrite(newName, this.configPath, "Settings", "DefaultProfile")
            } catch {
                try FileDelete(newPath)
                return false
            }
        }

        try {
            FileDelete(oldPath)
        } catch {
            if defaultChanged
                try IniWrite(oldName, this.configPath, "Settings", "DefaultProfile")
            try FileDelete(newPath)
            return false
        }

        this.profiles[newName] := profile
        this.profiles.Delete(oldName)
        if defaultChanged
            this.defaultProfile := newName
        if (this.currentProfile = oldName)
            this.currentProfile := newName

        return true
    }
}
