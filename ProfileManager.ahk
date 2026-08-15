#Requires AutoHotkey v2.0
#Include Settings.ahk
#Include HotkeyContract.ahk

class ProfileManager {
    static profiles := Map()
    static currentProfile := ""
    static defaultProfile := ""
    static configPath := A_ScriptDir "\config.ini"
    static profilesPath := A_ScriptDir "\profiles"
    static loadErrors := []
    static saveSequence := 0
    static missingValue := "{PACS-ASSISTANT-MISSING-INI-VALUE}"

    static __New() {
        ; Load default profile setting from config file
        try {
            this.defaultProfile := IniRead(this.configPath, "Settings", "DefaultProfile", "")
        }
    }

    ; Single construction point for a profile, so every field is always present
    static NewProfile() {
        return {
            binds: Map(),               ; funcName -> hotkey string
            customFuncs: Map(),         ; funcName -> {keys, window} configuration
            scopes: Map(),              ; funcName -> HotkeyManager scope name
            modalityAttendings: Map()   ; modality -> attending, "" = leave default
        }
    }

    ; Deep-enough copy for transactional GUI edits. Every current leaf is an immutable
    ; string, except custom command records, which are copied explicitly.
    static CloneProfile(profile) {
        this.ValidateProfile(profile)
        clone := this.NewProfile()
        for funcName, bind in profile.binds
            clone.binds[funcName] := bind
        for funcName, config in profile.customFuncs
            clone.customFuncs[funcName] := {keys: config.keys, window: config.window}
        for funcName, scope in profile.scopes
            clone.scopes[funcName] := scope
        for modality, attending in profile.modalityAttendings
            clone.modalityAttendings[modality] := attending
        return clone
    }

    static LoadProfiles() {
        ; Always refresh the in-memory profiles from disk
        previousProfile := this.currentProfile
        this.profiles := Map()
        this.loadErrors := []

        if DirExist(this.profilesPath) {
            Loop Files this.profilesPath "\*.ini" {
                ; Remove only the enumerated extension. StrReplace removed embedded
                ; occurrences too, so reading.ini.room.ini reloaded as reading.room.
                profileName := SubStr(A_LoopFileName, 1, -4)
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
                        profile.customFuncs[funcName] := {keys: keys, window: window}
                    }
                }
            }
        }

        ; New profiles persist the custom-command library independently of bindings,
        ; because removing a custom bind intentionally keeps the command available to
        ; add again. The legacy path above still loads bound custom commands from
        ; [Functions] Order when this independent order is absent.
        customFunctionList := StrSplit(IniRead(path, "CustomFunctions", "Order", ""), "|")
        for funcName in customFunctionList {
            if (funcName = "")
                continue
            this.RequireSafeIniKey(funcName, "function")
            if (InStr(funcName, "Custom: ") != 1)
                throw Error("Custom command name is missing the 'Custom: ' prefix")
            keys := IniRead(path, "CustomFunctions", funcName "_keys", "")
            window := IniRead(path, "CustomFunctions", funcName "_window", "")
            if (keys = "")
                throw Error("Custom command is missing keys: " funcName)
            profile.customFuncs[funcName] := {keys: keys, window: window}
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

        ; Save custom function configurations independently of bindings so an unbound
        ; command survives and remains available in the Add Function dialog.
        customFunctionList := ""
        for funcName, _ in profile.customFuncs
            customFunctionList .= funcName "|"
        IniWrite(customFunctionList, path, "CustomFunctions", "Order")
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
            identity := HotkeyContract.BindingIdentity(bind)
            if (identity != "") {
                if bindingOwners.Has(identity)
                    throw ValueError("Profile contains duplicate hotkey '" bind "' for '" bindingOwners[identity] "' and '" funcName "'")
                bindingOwners[identity] := funcName
            }
        }
        for funcName, config in profile.customFuncs {
            this.RequireSafeIniKey(funcName, "function")
            if (InStr(funcName, "Custom: ") != 1
                || !IsObject(config)
                || !HasProp(config, "keys")
                || Type(config.keys) != "String"
                || config.keys = ""
                || !HasProp(config, "window")
                || Type(config.window) != "String")
                throw ValueError("Profile contains invalid custom command configuration for '" funcName "'")
        }
        for funcName, _ in profile.binds {
            if (InStr(funcName, "Custom: ") = 1 && !profile.customFuncs.Has(funcName))
                throw ValueError("Profile is missing custom command configuration for '" funcName "'")
        }
        for funcName, scope in profile.scopes {
            this.RequireSafeIniKey(funcName, "function")
            if !HotkeyContract.IsValidScope(scope)
                throw ValueError("Profile contains an unknown hotkey scope for '" funcName "'")
        }
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
            case "": return "Any"
            default: throw ValueError("Profile contains an unknown legacy hotkey scope")
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
        if !HotkeyContract.IsValidScope(scope)
            throw ValueError("Unknown hotkey scope")
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

        wasDefault := this.defaultProfile = name
        if wasDefault {
            ; Clear the reference before deleting the only copy. If config cannot be
            ; updated, the operation must remain a no-op rather than report failure
            ; after the profile has already disappeared.
            try IniDelete(this.configPath, "Settings", "DefaultProfile")
            catch {
                return false
            }
        }

        try FileDelete(this.ProfilePath(name))
        catch {
            if wasDefault {
                try IniWrite(name, this.configPath, "Settings", "DefaultProfile")
                catch as rollbackError
                    OutputDebug("Default profile rollback failed: " rollbackError.Message)
            }
            return false
        }

        this.profiles.Delete(name)
        if wasDefault
            this.defaultProfile := ""
        return true
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
