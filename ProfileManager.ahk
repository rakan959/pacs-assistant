#Requires AutoHotkey v2.0
#Include Settings.ahk
#Include HotkeyContract.ahk

class NativeProfileStorageDriver {
    DeleteFile(path) => FileDelete(path)
    MoveFile(sourcePath, destinationPath, overwrite := false) =>
        FileMove(sourcePath, destinationPath, overwrite)
    DeleteIni(path, section, key) => IniDelete(path, section, key)
    WriteIni(value, path, section, key) => IniWrite(value, path, section, key)
    ReadIni(path, section, key, defaultValue := "") =>
        IniRead(path, section, key, defaultValue)
}

class ProfileManager {
    static profiles := Map()
    static currentProfile := ""
    static defaultProfile := ""
    static configPath := A_ScriptDir "\config.ini"
    static profilesPath := A_ScriptDir "\profiles"
    static loadErrors := []
    static saveSequence := 0
    static profileRevisions := Map()
    static storageDriver := NativeProfileStorageDriver()
    static lastError := ""
    static recoveryRequired := false

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
        this.profileRevisions := Map()
        this.loadErrors := []

        if DirExist(this.profilesPath) {
            Loop Files this.profilesPath "\*.ini" {
                ; Remove only the enumerated extension. StrReplace removed embedded
                ; occurrences too, so reading.ini.room.ini reloaded as reading.room.
                profileName := SubStr(A_LoopFileName, 1, -4)
                try {
                    this.profiles[profileName] := this.LoadProfile(A_LoopFilePath)
                    this.profileRevisions[profileName] := 0
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
        functionOrder := ""
        if !this.TryReadIniValue(path, "Functions", "Order", &functionOrder)
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
                persistedScope := ""
                if !this.TryReadIniValue(path, "Scopes", funcName, &persistedScope) {
                    legacy := IniRead(path, "KeybindScopes", funcName, "")
                    profile.scopes[funcName] := this.MigrateLegacyScope(legacy)
                } else
                    profile.scopes[funcName] := persistedScope
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
        this.RequireStorageHealthy()
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

        this.profileRevisions[name] := this.GetProfileRevision(name) + 1

        return true
    }

    static GetProfileRevision(name) {
        return this.profileRevisions.Has(name) ? this.profileRevisions[name] : 0
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

        ; Win32 INI section keys are case-insensitive even though AutoHotkey Maps
        ; are case-sensitive. Reject aliases before either save or load can collapse
        ; two logical commands/modalities into one physical key.
        this.RequireUniqueIniKeys(profile.binds, "function")
        this.RequireUniqueIniKeys(profile.customFuncs, "custom function")
        this.RequireUniqueIniKeys(profile.scopes, "scope function")
        this.RequireUniqueIniKeys(profile.modalityAttendings, "modality")

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
        for modality, _ in profile.modalityAttendings {
            this.RequireSafeIniKey(modality, "modality")
            if (StrLower(modality) == "order")
                throw ValueError("Profile modality name uses the reserved INI key 'Order'")
        }
    }

    static RequireUniqueIniKeys(values, kind) {
        identities := Map()
        for name, _ in values {
            identity := StrLower(name)
            if identities.Has(identity)
                throw ValueError(
                    "Profile contains a case-insensitive INI key collision for " kind
                    . ": '" identities[identity] "' and '" name "'"
                )
            identities[identity] := name
        }
    }

    static HasIniKeyIdentity(values, name) {
        identity := StrLower(name)
        for existingName, _ in values {
            if (StrLower(existingName) == identity)
                return true
        }
        return false
    }

    /**
     * Read an optional INI value without a collidable persisted sentinel. For a
     * missing key IniRead returns its caller-provided default, so two distinct
     * defaults disagree only when the key is actually absent. Any stored string,
     * including either default token or blank, is returned identically both times.
     */
    static TryReadIniValue(path, section, key, &value) {
        absentA := "{PACS-ASSISTANT-INI-ABSENT-A}"
        absentB := "{PACS-ASSISTANT-INI-ABSENT-B}"
        first := IniRead(path, section, key, absentA)
        second := IniRead(path, section, key, absentB)
        if !(first == second) {
            value := ""
            return false
        }
        value := first
        return true
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
        if !this.BeginStorageMutation()
            return false
        if !this.IsValidProfileName(name) || this.profiles.Has(name)
            return false

        try {
            if FileExist(this.ProfilePath(name))
                return false
            profile := this.NewProfile()
            this.SaveProfile(name, profile)
            this.profiles[name] := profile
            return true
        } catch as err {
            return this.FailStorageMutation("Profile creation failed: " err.Message)
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

    static SetDefaultProfile(name) {
        if !this.BeginStorageMutation()
            return false
        if !this.IsValidProfileName(name) || !this.profiles.Has(name)
            return false

        try {
            this.storageDriver.WriteIni(name, this.configPath, "Settings", "DefaultProfile")
            this.defaultProfile := name
            return true
        } catch as err {
            refreshError := this.RefreshDefaultProfileFromStorage()
            message := "Default-profile update failed: " err.Message
            if (refreshError != "")
                message .= "; the stored default could not be re-read: " refreshError
            return this.FailStorageMutation(message, true)
        }
    }

    static DeleteProfile(name) {
        if !this.BeginStorageMutation()
            return false
        if (this.profiles.Count <= 1 || !this.profiles.Has(name) || !this.IsValidProfileName(name)) {
            return false  ; Don't allow deleting the last profile
        }

        wasDefault := this.defaultProfile = name
        if wasDefault {
            ; Clear the reference before deleting the only copy. If config cannot be
            ; updated, the operation must remain a no-op rather than report failure
            ; after the profile has already disappeared.
            try this.storageDriver.DeleteIni(this.configPath, "Settings", "DefaultProfile")
            catch as err {
                return this.FailStorageMutation(
                    "Default-profile reference could not be cleared: " err.Message
                )
            }
        }

        try this.storageDriver.DeleteFile(this.ProfilePath(name))
        catch as deleteError {
            if wasDefault {
                try this.storageDriver.WriteIni(name, this.configPath, "Settings", "DefaultProfile")
                catch as rollbackError {
                    refreshError := this.RefreshDefaultProfileFromStorage()
                    message := "Profile deletion failed: " deleteError.Message
                        . "; restoring the default-profile reference also failed: " rollbackError.Message
                    if (refreshError != "")
                        message .= "; the stored default could not be re-read: " refreshError
                    return this.FailStorageMutation(message, true)
                }
            }
            return this.FailStorageMutation(
                "Profile file could not be deleted: " deleteError.Message
            )
        }

        this.profiles.Delete(name)
        if this.profileRevisions.Has(name)
            this.profileRevisions.Delete(name)
        if wasDefault
            this.defaultProfile := ""
        return true
    }

    static RenameProfile(oldName, newName) {
        if !this.BeginStorageMutation()
            return false
        if (oldName == newName)
            return true

        if (!this.IsValidProfileName(oldName)
            || !this.IsValidProfileName(newName)
            || !this.profiles.Has(oldName))
            return false

        oldPath := this.ProfilePath(oldName)
        newPath := this.ProfilePath(newName)
        if (oldName = newName)
            return this.RenameProfileCaseOnly(oldName, newName, oldPath, newPath)

        if this.profiles.Has(newName)
            return false
        if FileExist(newPath)
            return false

        profile := this.profiles[oldName]
        try {
            ; Persist the replacement before touching the original. SaveProfile's
            ; temporary-file move guarantees a failed save cannot truncate it.
            this.SaveProfile(newName, profile)
        } catch as err {
            return this.FailStorageMutation("Replacement profile could not be saved: " err.Message)
        }

        defaultChanged := this.defaultProfile = oldName
        if defaultChanged {
            try {
                this.storageDriver.WriteIni(newName, this.configPath, "Settings", "DefaultProfile")
            } catch as configError {
                rollbackError := ""
                try this.storageDriver.WriteIni(oldName, this.configPath, "Settings", "DefaultProfile")
                catch as err
                    rollbackError := err.Message
                if (rollbackError != "") {
                    this.PublishRetainedProfileCopy(newName, profile)
                    refreshError := this.RefreshDefaultProfileFromStorage()
                    message := "Default-profile rename update failed: " configError.Message
                        . "; restoring the original default also failed: " rollbackError
                    if (refreshError != "")
                        message .= "; the stored default could not be re-read: " refreshError
                    return this.FailStorageMutation(message, true)
                }

                cleanupError := this.DeleteReplacementProfileFile(newName, newPath)
                if (cleanupError != "") {
                    this.PublishRetainedProfileCopy(newName, profile)
                    return this.FailStorageMutation(
                        "Default-profile rename update failed: " configError.Message
                            . "; removing the retained replacement also failed: " cleanupError,
                        true
                    )
                }
                return this.FailStorageMutation(
                    "Default-profile rename update failed: " configError.Message
                )
            }
        }

        try {
            this.storageDriver.DeleteFile(oldPath)
        } catch as deleteError {
            rollbackError := ""
            if defaultChanged {
                try this.storageDriver.WriteIni(oldName, this.configPath, "Settings", "DefaultProfile")
                catch as err
                    rollbackError := err.Message
            }
            if (rollbackError != "") {
                ; The new file and its stored default remain a valid configuration.
                ; Publish that retained copy instead of leaving disk and memory split.
                this.PublishRetainedProfileCopy(newName, profile)
                refreshError := this.RefreshDefaultProfileFromStorage()
                message := "Original profile file could not be removed: " deleteError.Message
                    . "; restoring the original default also failed: " rollbackError
                if (refreshError != "")
                    message .= "; the stored default could not be re-read: " refreshError
                return this.FailStorageMutation(message, true)
            }

            cleanupError := this.DeleteReplacementProfileFile(newName, newPath)
            if (cleanupError != "") {
                this.PublishRetainedProfileCopy(newName, profile)
                return this.FailStorageMutation(
                    "Original profile file could not be removed: " deleteError.Message
                        . "; removing the retained replacement also failed: " cleanupError,
                    true
                )
            }
            return this.FailStorageMutation(
                "Original profile file could not be removed: " deleteError.Message
            )
        }

        this.profiles[newName] := profile
        this.profiles.Delete(oldName)
        if this.profileRevisions.Has(oldName)
            this.profileRevisions.Delete(oldName)
        if defaultChanged
            this.defaultProfile := newName
        if (this.currentProfile = oldName)
            this.currentProfile := newName

        return true
    }

    static RenameProfileCaseOnly(oldName, newName, oldPath, newPath) {
        ; Windows resolves both paths to the same file, so an ordinary replacement
        ; does not reliably update the directory entry's casing. Move through a
        ; unique same-directory name and roll back before reporting failure.
        try this.MoveProfileThroughTemporaryPath(oldPath, newPath)
        catch as err {
            if this.recoveryRequired
                return false
            return this.FailStorageMutation("Profile file could not be renamed: " err.Message)
        }

        defaultChanged := this.defaultProfile = oldName
        if defaultChanged {
            try {
                this.storageDriver.WriteIni(newName, this.configPath, "Settings", "DefaultProfile")
            } catch as configError {
                rollbackError := ""
                try this.MoveProfileThroughTemporaryPath(newPath, oldPath)
                catch as err
                    rollbackError := err.Message
                if (rollbackError = "") {
                    try this.storageDriver.WriteIni(oldName, this.configPath, "Settings", "DefaultProfile")
                    catch as err
                        rollbackError := err.Message
                }
                if (rollbackError != "") {
                    this.ReconcileCaseOnlyProfileName(oldName, newName, oldPath, newPath)
                    refreshError := this.RefreshDefaultProfileFromStorage()
                    message := "Default-profile case rename failed: " configError.Message
                        . "; restoring the original profile state also failed: " rollbackError
                    if (refreshError != "")
                        message .= "; the stored default could not be re-read: " refreshError
                    return this.FailStorageMutation(message, true)
                }
                return this.FailStorageMutation(
                    "Default-profile case rename failed: " configError.Message
                )
            }
        }

        profile := this.profiles[oldName]
        revision := this.GetProfileRevision(oldName)
        this.profiles.Delete(oldName)
        this.profiles[newName] := profile
        if this.profileRevisions.Has(oldName)
            this.profileRevisions.Delete(oldName)
        this.profileRevisions[newName] := revision + 1
        if defaultChanged
            this.defaultProfile := newName
        if (this.currentProfile = oldName)
            this.currentProfile := newName
        return true
    }

    static MoveProfileThroughTemporaryPath(sourcePath, destinationPath) {
        loop {
            this.saveSequence++
            temporaryPath := sourcePath ".case-rename-" DllCall("GetCurrentProcessId") "-" this.saveSequence
        } until !FileExist(temporaryPath)

        this.storageDriver.MoveFile(sourcePath, temporaryPath, false)
        try {
            this.storageDriver.MoveFile(temporaryPath, destinationPath, false)
        } catch as err {
            try this.storageDriver.MoveFile(temporaryPath, sourcePath, false)
            catch as rollbackError {
                message := "Profile file move failed: " err.Message
                    . "; the temporary file could not be restored from '" temporaryPath "': " rollbackError.Message
                this.FailStorageMutation(message, true)
            }
            throw err
        }
    }

    static BeginStorageMutation() {
        if this.recoveryRequired
            return false
        this.lastError := ""
        return true
    }

    static RequireStorageHealthy() {
        if this.recoveryRequired
            throw Error(
                "Profile storage is in a recovery-required state. Restart PACS Assistant before changing profiles."
            )
    }

    static FailStorageMutation(message, recoveryRequired := false) {
        this.lastError := message
        if recoveryRequired
            this.recoveryRequired := true
        OutputDebug("Profile storage operation failed: " message)
        return false
    }

    static RefreshDefaultProfileFromStorage() {
        try configured := this.storageDriver.ReadIni(
            this.configPath,
            "Settings",
            "DefaultProfile",
            ""
        )
        catch as err
            return err.Message
        this.defaultProfile := configured != "" && this.profiles.Has(configured)
            ? configured
            : ""
        return ""
    }

    static PublishRetainedProfileCopy(name, profile) {
        ; A failed rename may intentionally retain both files. Keep their in-memory
        ; records independent too, matching the two independent persisted snapshots.
        this.profiles[name] := this.CloneProfile(profile)
        if !this.profileRevisions.Has(name)
            this.profileRevisions[name] := 1
    }

    static DeleteReplacementProfileFile(name, path) {
        try this.storageDriver.DeleteFile(path)
        catch as err
            return err.Message
        if this.profileRevisions.Has(name)
            this.profileRevisions.Delete(name)
        return ""
    }

    static ReconcileCaseOnlyProfileName(oldName, newName, oldPath, newPath) {
        if (!FileExist(oldPath) && FileExist(newPath) && this.profiles.Has(oldName)) {
            profile := this.profiles[oldName]
            revision := this.GetProfileRevision(oldName)
            this.profiles.Delete(oldName)
            this.profiles[newName] := profile
            if this.profileRevisions.Has(oldName)
                this.profileRevisions.Delete(oldName)
            this.profileRevisions[newName] := revision + 1
            if (this.currentProfile == oldName)
                this.currentProfile := newName
        }
    }
}
