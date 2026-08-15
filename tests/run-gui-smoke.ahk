#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off

; Smoke test for the windows PACS Assistant builds. Syntax checking cannot catch a
; bad control reference or a broken layout, so this actually constructs each window,
; then closes it again. Windows will flash on screen while it runs.
;
; Run with:
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" tests\run-gui-smoke.ahk

#Include ../KeybindGUI.ahk

global TestsRun := 0
global TestsFailed := 0
global TempDir := A_Temp "\pacs-assistant-gui-smoke"

Out(text) {
    FileAppend(text "`n", "*")
}

Check(label, action) {
    global TestsRun, TestsFailed
    TestsRun++
    try {
        action()
        Out("  ok   " label)
    } catch as err {
        TestsFailed++
        Out("  FAIL " label " -- " err.Message " (" err.File ":" err.Line ")")
    }
}

Assert(condition, label) {
    global TestsRun, TestsFailed
    TestsRun++
    if condition {
        Out("  ok   " label)
        return
    }
    TestsFailed++
    Out("  FAIL " label)
}

; Closes a window by title and lets its event handlers run
CloseWindow(title) {
    if WinExist(title) {
        WinClose(title)
        Sleep(150)
    }
}

FindListView(guiObj) {
    for ctrl in guiObj {
        if (ctrl.Type = "ListView")
            return ctrl
    }
    return 0
}

Main() {
    global TestsRun, TestsFailed, TempDir

    try DirDelete(TempDir, true)
    DirCreate(TempDir)
    DirCreate(TempDir "\profiles")
    SetWorkingDir(TempDir)
    originalConfigPath := ProfileManager.configPath
    originalProfilesPath := ProfileManager.profilesPath
    ProfileManager.configPath := TempDir "\config.ini"
    ProfileManager.profilesPath := TempDir "\profiles"

    ; A profile with a built-in bind, a scoped bind and a custom function.
    ; F13/F14 do not exist on a normal keyboard, so applying these binds cannot
    ; swallow a key the user might actually press.
    path := TempDir "\profiles\Smoke.ini"
    IniWrite("Sign Report|Draft Report|Custom: Smoke|", path, "Functions", "Order")
    IniWrite("^F13", path, "Keybinds", "Sign Report")
    IniWrite("^F14", path, "Keybinds", "Draft Report")
    IniWrite("^F15", path, "Keybinds", "Custom: Smoke")
    IniWrite("Any", path, "Scopes", "Sign Report")
    IniWrite("PowerScribe", path, "Scopes", "Draft Report")
    IniWrite("Any", path, "Scopes", "Custom: Smoke")
    IniWrite("HELLO", path, "CustomFunctions", "Custom: Smoke_keys")
    IniWrite("", path, "CustomFunctions", "Custom: Smoke_window")
    IniWrite("Neuro|", path, "ModalityAttendings", "Order")
    IniWrite("Smith", path, "ModalityAttendings", "Neuro")

    Out("PACS Assistant GUI smoke test")
    Out("")

    ProfileManager.profiles := Map()
    ProfileManager.LoadProfiles()
    ProfileManager.currentProfile := "Smoke"

    ; Build an instance without running the constructor, which would go and check
    ; GitHub for updates
    kb := {base: KeybindGUI.Prototype, gui: ""}

    Check("main window builds", () => kb.CreateMainGUI())

    lv := FindListView(kb.gui)
    Assert(lv != 0, "main window has a keybind list")

    if (lv != 0) {
        Assert(lv.GetCount() = 3, "all three binds are listed")
        Assert(lv.GetCount("Col") = 3, "the list has a scope column")
        AssertScope(lv, "Draft Report", "PowerScribe")
        AssertScope(lv, "Sign Report", "Any window")

        lv.Modify(1, "Select Focus")
        Check("scope dialog builds", () => kb.ShowScopeDialog(lv))
        CloseWindow("PACS Assistant - Keybind Scope")
    }

    Check("modality attendings dialog builds", () => kb.ShowModalityAttendingsDialog())
    CloseWindow("PACS Assistant - Modality Attendings")

    Check("settings dialog builds", () => Settings.ShowDialog())
    CloseWindow("PACS Assistant - Settings")

    Check("profile selector builds", () => kb.ShowProfileSelector())
    CloseWindow("PACS Assistant - Profile Selection")

    ; Regression for issue #22: closing the keybind prompt with the X has to tear the
    ; capture hook down. Left running, it would rebind the next key pressed anywhere.
    if (lv != 0) {
        Check("keybind prompt builds", () => kb.PromptKeybind("Sign Report", lv))
        CloseWindow("PACS Assistant - Set Keybind")
        Assert(KeybindGUI.isListening = false, "closing the keybind prompt stops listening")
        Assert(KeybindGUI.activeInputHook = 0, "closing the keybind prompt tears down the input hook")
    }

    ; Leave no hotkeys registered behind
    HotkeyManager.DisableAllHotkeys()
    try kb.gui.Destroy()

    ProfileManager.configPath := originalConfigPath
    ProfileManager.profilesPath := originalProfilesPath
    SetWorkingDir(A_ScriptDir)
    try DirDelete(TempDir, true)
    try FileDelete(A_ScriptDir "\settings.ini")

    Out("")
    Out(TestsFailed = 0
        ? "PASS - " TestsRun " checks"
        : "FAIL - " TestsFailed " of " TestsRun " checks failed")

    ExitApp(TestsFailed = 0 ? 0 : 1)
}

AssertScope(listView, funcName, expected) {
    Loop listView.GetCount() {
        if (listView.GetText(A_Index, 1) = funcName) {
            Assert(listView.GetText(A_Index, 3) = expected, "'" funcName "' shows scope '" expected "'")
            return
        }
    }
    Assert(false, "'" funcName "' is in the list")
}

Main()
