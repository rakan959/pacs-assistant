#Requires AutoHotkey v2.0
#Include ../StartupShortcut.ahk
#Include TestRunner.ahk

class StartupShortcutTest {
    static tests := [
        "TestEnablingCreatesAShortcutToThisBuild",
        "TestDisablingRemovesTheShortcutAndToleratesItsAbsence",
        "TestAShortcutToAnotherCopyIsNotEnabled"
    ]

    ; Never the real Startup folder: a private folder under A_Temp.
    Setup() {
        this.originalFolder := StartupShortcut.folder
        this.folder := A_Temp "\pacs-startup-test-" DllCall("GetCurrentProcessId")
        DirCreate(this.folder)
        StartupShortcut.folder := this.folder
    }

    Teardown() {
        StartupShortcut.folder := this.originalFolder
        try DirDelete(this.folder, true)
    }

    TestEnablingCreatesAShortcutToThisBuild() {
        Assert.False(StartupShortcut.IsEnabled())
        StartupShortcut.Set(true)
        Assert.True(StartupShortcut.IsEnabled())
        FileGetShortcut(StartupShortcut.Path(), &target,, &arguments)
        ; A source run starts the interpreter with this script.
        Assert.Equal(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, target)
        if !A_IsCompiled
            Assert.Equal('"' A_ScriptFullPath '"', arguments)
    }

    ; A shortcut left by a copy that has since moved: the option shows off, and
    ; turning it on points the shortcut at this build again.
    TestAShortcutToAnotherCopyIsNotEnabled() {
        FileCreateShortcut(A_WinDir "\notepad.exe", StartupShortcut.Path())
        Assert.False(StartupShortcut.IsEnabled())
        StartupShortcut.Set(true)
        Assert.True(StartupShortcut.IsEnabled())
    }

    TestDisablingRemovesTheShortcutAndToleratesItsAbsence() {
        StartupShortcut.Set(true)
        StartupShortcut.Set(false)
        Assert.False(StartupShortcut.IsEnabled())
        StartupShortcut.Set(false)
        Assert.False(StartupShortcut.IsEnabled())
    }
}
