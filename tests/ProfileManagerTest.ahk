#Requires AutoHotkey v2.0
#Include ../ProfileManager.ahk
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class ProfileManagerTest {
    static Tests := [
        "TestProfileSaveAndLoad",
        "TestDefaultProfileTracking",
        "TestProfileRename",
        "TestProfileDeletionRules",
        "TestCustomFunctionPersistence",
        "TestScopePersistence"
    ]

    Setup() {
        this.tempRoot := A_Temp "\pacs_profile_tests_" A_TickCount
        this.profilesDir := this.tempRoot "\profiles"
        DirCreate(this.profilesDir)
        
        this.originalConfig := ProfileManager.configPath
        this.originalProfiles := ProfileManager.profilesPath
        
        ProfileManager.configPath := this.tempRoot "\config.ini"
        ProfileManager.profilesPath := this.profilesDir
        ProfileManager.profiles := Map()
        ProfileManager.currentProfile := ""
        ProfileManager.defaultProfile := ""
    }
    
    TestProfileSaveAndLoad() {
        profile := {
            binds: Map(
                "Toggle Dictation", "^d",
                "Select Next Field", "^n"
            ),
            customFuncs: Map()
        }
        
        ProfileManager.profiles["TestProfile"] := profile
        ProfileManager.SaveProfile("TestProfile", profile.binds, profile.customFuncs)
        Assert.True(FileExist(ProfileManager.profilesPath "\TestProfile.ini") != "")
        
        ProfileManager.LoadProfiles()
        Assert.True(ProfileManager.profiles.Has("TestProfile"))
        Assert.Equal("^d", ProfileManager.profiles["TestProfile"].binds["Toggle Dictation"])
    }
    
    TestDefaultProfileTracking() {
        ProfileManager.profiles["DefaultTest"] := {binds: Map(), customFuncs: Map()}
        Assert.True(ProfileManager.SetDefaultProfile("DefaultTest"))
        ProfileManager.LoadProfiles()
        Assert.Equal("DefaultTest", ProfileManager.defaultProfile)
    }
    
    TestProfileRename() {
        ProfileManager.profiles["OldName"] := {binds: Map(), customFuncs: Map()}
        ProfileManager.SaveProfile("OldName", Map())
        
        Assert.True(ProfileManager.RenameProfile("OldName", "NewName"))
        Assert.True(ProfileManager.profiles.Has("NewName"))
        Assert.False(ProfileManager.profiles.Has("OldName"))
        Assert.True(FileExist(ProfileManager.profilesPath "\NewName.ini") != "")
        Assert.False(FileExist(ProfileManager.profilesPath "\OldName.ini"))
    }
    
    TestProfileDeletionRules() {
        ProfileManager.profiles["One"] := {binds: Map(), customFuncs: Map()}
        ProfileManager.profiles["Two"] := {binds: Map(), customFuncs: Map()}
        ProfileManager.SaveProfile("One", Map())
        ProfileManager.SaveProfile("Two", Map())
        
        Assert.True(ProfileManager.DeleteProfile("One"))
        Assert.False(ProfileManager.profiles.Has("One"))
        Assert.False(FileExist(ProfileManager.profilesPath "\One.ini"))
        
        Assert.False(ProfileManager.DeleteProfile("Two"))  ; last profile should not delete
        Assert.True(ProfileManager.profiles.Has("Two"))
    }
    
    TestCustomFunctionPersistence() {
        customFunc := PACSCommands.CreateCustomKeybind("{Tab}", "TestWindow")
        profile := {
            binds: Map("Custom: Test", "^t"),
            customFuncs: Map("Custom: Test", customFunc)
        }
        
        ProfileManager.profiles["CustomProfile"] := profile
        ProfileManager.SaveProfile("CustomProfile", profile.binds, profile.customFuncs)
        ProfileManager.LoadProfiles()
        
        Assert.True(ProfileManager.profiles["CustomProfile"].customFuncs.Has("Custom: Test"))
        loaded := ProfileManager.profiles["CustomProfile"].customFuncs["Custom: Test"]
        Assert.Equal("{Tab}", loaded.keys)
        Assert.Equal("TestWindow", loaded.window)
    }

    TestScopePersistence() {
        profile := {
            binds: Map("Toggle Dictation", "^d"),
            scopes: Map("Toggle Dictation", "restricted"),
            customFuncs: Map()
        }
        
        ProfileManager.profiles["ScopedProfile"] := profile
        ProfileManager.SaveProfile("ScopedProfile", profile.binds, profile.customFuncs, profile.scopes)
        ProfileManager.LoadProfiles()
        
        Assert.True(ProfileManager.profiles.Has("ScopedProfile"))
        loadedScope := ProfileManager.profiles["ScopedProfile"].scopes["Toggle Dictation"]
        Assert.Equal("restricted", loadedScope)
    }
    
    Teardown() {
        try {
            DirDelete(this.tempRoot, true)
        }
        ProfileManager.configPath := this.originalConfig
        ProfileManager.profilesPath := this.originalProfiles
        ProfileManager.profiles := Map()
        ProfileManager.currentProfile := ""
        ProfileManager.defaultProfile := ""
    }
}
