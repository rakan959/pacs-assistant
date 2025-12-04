#Requires AutoHotkey v2.0
#Include PACSCommands.ahk

class ProfileManager {
    static profiles := Map()
    static currentProfile := ""
    static defaultProfile := ""
    static availableFunctions := Map()  ; Now only stores built-in functions
    static configPath := "config.ini"
    static profilesPath := "profiles"

    static __New() {
        ; Initialize available functions from PACSCommands
        this.availableFunctions := PACSCommands.commands

        ; Load default profile setting from config file
        try {
            this.defaultProfile := IniRead(this.configPath, "Settings", "DefaultProfile", "")
        }
    }

    static LoadProfiles() {
        ; Always refresh the in-memory profiles from disk
        this.profiles := Map()
        try {
            Loop Files this.profilesPath "\*.ini" {
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
        binds := Map()
        customFuncs := Map()  ; Store custom functions for this profile
        try {
            IniRead(path)
            ; Read the ordered list of functions
            functionList := StrSplit(IniRead(path, "Functions", "Order", ""), "|")
            for funcName in functionList {
                if (funcName != "") {
                    binds[funcName] := IniRead(path, "Keybinds", funcName, "")
                    ; If it's a custom function, load its configuration
                    if (InStr(funcName, "Custom: ") = 1) {
                        keys := IniRead(path, "CustomFunctions", funcName "_keys", "")
                        window := IniRead(path, "CustomFunctions", funcName "_window", "")
                        if (keys != "") {
                            customFuncs[funcName] := PACSCommands.CreateCustomKeybind(keys, window)
                        }
                    }
                }
            }
        }
        return {binds: binds, customFuncs: customFuncs}
    }

    static SaveProfile(name, binds, customFuncs := 0) {
        if !DirExist(this.profilesPath)
            DirCreate(this.profilesPath)
        
        path := this.profilesPath "/" name ".ini"
        
        ; Save the ordered list of functions
        functionList := ""
        for funcName, _ in binds {
            functionList .= funcName "|"
        }
        IniWrite(functionList, path, "Functions", "Order")
        
        ; Save the keybinds
        for funcName, bind in binds {
            IniWrite(bind, path, "Keybinds", funcName)
        }

        ; Save custom function configurations if provided
        if (customFuncs) {
            for funcName, func in customFuncs {
                if (InStr(funcName, "Custom: ") = 1) {
                    ; We need to store the configuration that created this custom function
                    ; This is a placeholder - you'll need to modify PACSCommands to expose these values
                    IniWrite(func.keys, path, "CustomFunctions", funcName "_keys")
                    IniWrite(func.window, path, "CustomFunctions", funcName "_window")
                }
            }
        }
    }

    static SetDefaultProfile(name) {
        if !DirExist(this.profilesPath)
            DirCreate(this.profilesPath)
        
        this.defaultProfile := name
        try {
            IniWrite(name, this.configPath, "Settings", "DefaultProfile")
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
            FileDelete(this.profilesPath "/" name ".ini")
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
            
        if (newName = "" || this.profiles.Has(newName))
            return false
            
        try {
            ; Save the binds
            binds := this.profiles[oldName].binds
            customFuncs := this.profiles[oldName].customFuncs
            
            ; Delete old profile
            FileDelete(this.profilesPath "/" oldName ".ini")
            this.profiles.Delete(oldName)
            
            ; Create new profile
            this.profiles[newName] := {binds: binds, customFuncs: customFuncs}
            this.SaveProfile(newName, binds, customFuncs)
            
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
