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
global RunPid := DllCall("GetCurrentProcessId")
global TempDir := A_Temp "\pacs-assistant-gui-smoke-" RunPid "-" DllCall("GetTickCount64", "UInt64") "-" Random(100000, 999999)
global OpenedWindows := []
global SmokeKB := 0
global OriginalConfigPath := ""
global OriginalProfilesPath := ""
global OriginalSettingsPath := ""

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

OpenAndCaptureWindow(title, action) {
    global OpenedWindows
    before := Map()
    for hwnd in WinGetList(title)
        before[hwnd] := true
    action.Call()
    Sleep(75)
    created := []
    for hwnd in WinGetList(title) {
        if !before.Has(hwnd)
            created.Push(hwnd)
    }
    if (created.Length != 1)
        throw Error("Expected one new '" title "' window, found " created.Length)
    OpenedWindows.Push(created[1])
    return created[1]
}

; Close only the exact HWND created by this smoke run.
CloseWindow(hwnd) {
    if (hwnd > 0 && WinExist("ahk_id " hwnd)) {
        WinClose("ahk_id " hwnd)
        Sleep(150)
    }
}

Cleanup(*) {
    global TempDir, OpenedWindows, SmokeKB, RunPid
    global OriginalConfigPath, OriginalProfilesPath, OriginalSettingsPath
    try HotkeyManager.DisableAllHotkeys()
    try UpdateChecker.StopAutoCheck()
    for hwnd in OpenedWindows
        try CloseWindow(hwnd)
    if SmokeKB
        try SmokeKB.gui.Destroy()
    if (OriginalConfigPath != "")
        ProfileManager.configPath := OriginalConfigPath
    if (OriginalProfilesPath != "")
        ProfileManager.profilesPath := OriginalProfilesPath
    if (OriginalSettingsPath != "")
        Settings.settingsFile := OriginalSettingsPath
    try SetWorkingDir(A_ScriptDir)

    ; The recursive cleanup target is private to this PID/run and must remain a
    ; direct child of the system temp directory.
    try {
        tempParent := RTrim(AppControl.NormalizePath(A_Temp), "\") "\"
        resolved := AppControl.NormalizePath(TempDir)
        expectedName := "pacs-assistant-gui-smoke-" RunPid "-"
        if (InStr(resolved, tempParent, true) = 1
            && InStr(SubStr(resolved, StrLen(tempParent) + 1), expectedName, true) = 1)
            DirDelete(resolved, true)
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
    global TestsRun, TestsFailed, TempDir, SmokeKB
    global OriginalConfigPath, OriginalProfilesPath, OriginalSettingsPath

    DirCreate(TempDir)
    DirCreate(TempDir "\profiles")
    SetWorkingDir(TempDir)
    OriginalConfigPath := ProfileManager.configPath
    OriginalProfilesPath := ProfileManager.profilesPath
    OriginalSettingsPath := Settings.settingsFile
    ProfileManager.configPath := TempDir "\config.ini"
    ProfileManager.profilesPath := TempDir "\profiles"
    Settings.settingsFile := TempDir "\settings.ini"
    Settings.SaveAllSettings()

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
    ProfileManager.defaultProfile := "Smoke"

    ; Exercise the real instance layout. Constructing an object from only the
    ; prototype bypasses instance-property initializers and can make the smoke test
    ; fail on fields that every production KeybindGUI instance owns.
    kb := 0
    Check("main window builds", () => (kb := KeybindGUI()))
    if !kb
        throw Error("The main KeybindGUI instance could not be constructed")
    SmokeKB := kb

    lv := FindListView(kb.gui)
    Assert(lv != 0, "main window has a keybind list")

    if (lv != 0) {
        Assert(lv.GetCount() = 3, "all three binds are listed")
        Assert(lv.GetCount("Col") = 3, "the list has a scope column")
        AssertScope(lv, "Draft Report", "PowerScribe")
        AssertScope(lv, "Sign Report", "Any window")

        lv.Modify(1, "Select Focus")
        scopeHwnd := 0
        Check("scope dialog builds", () => (
            scopeHwnd := OpenAndCaptureWindow(
                "PACS Assistant - Keybind Scope",
                () => kb.ShowScopeDialog(lv)
            )
        ))
        CloseWindow(scopeHwnd)
    }

    modalityHwnd := 0
    Check("modality attendings dialog builds", () => (
        modalityHwnd := OpenAndCaptureWindow(
            "PACS Assistant - Modality Attendings",
            () => kb.ShowModalityAttendingsDialog()
        )
    ))
    CloseWindow(modalityHwnd)

    settingsHwnd := 0
    Check("settings dialog builds", () => (
        settingsHwnd := OpenAndCaptureWindow(
            "PACS Assistant - Settings",
            () => Settings.ShowDialog()
        )
    ))
    CloseWindow(settingsHwnd)

    updateInfo := {
        hasUpdate: true,
        currentVersion: "v2.0.0",
        latestVersion: "v2.1.0",
        releaseNotes: "Smoke-test release"
    }
    updateHwnd := 0
    Check("update dialog builds", () => (
        updateHwnd := OpenAndCaptureWindow(
            "PACS Assistant - Update Available",
            () => UpdateChecker.ShowUpdateDialog(updateInfo)
        )
    ))
    CloseWindow(updateHwnd)
    Assert(!WinExist("ahk_id " updateHwnd), "closing update dialog commits preferences and closes")
    UpdateChecker.StopAutoCheck()

    registeredBeforeSwitch := HotkeyManager.activeHotkeys.Count
    selectorHwnd := 0
    Check("profile selector builds", () => (
        selectorHwnd := OpenAndCaptureWindow(
            "PACS Assistant - Profile Selection",
            () => kb.OpenProfileSelector()
        )
    ))
    Assert(HotkeyManager.activeHotkeys.Count = 0, "profile selection suspends the prior profile hotkeys")
    CloseWindow(selectorHwnd)
    Assert(HotkeyManager.activeHotkeys.Count = registeredBeforeSwitch, "closing profile selection restores the current profile")
    lv := FindListView(kb.gui)

    ; Regression for issue #22: closing the keybind prompt with the X has to tear the
    ; capture hook down. Left running, it would rebind the next key pressed anywhere.
    if (lv != 0) {
        registeredBeforeCapture := HotkeyManager.activeHotkeys.Count
        Assert(registeredBeforeCapture > 0, "profile hotkeys are active before keybind capture")
        captureHwnd := 0
        Check("keybind prompt builds", () => (
            captureHwnd := OpenAndCaptureWindow(
                "PACS Assistant - Set Keybind",
                () => kb.PromptKeybind("Sign Report", lv)
            )
        ))
        Assert(HotkeyManager.activeHotkeys.Count = 0, "keybind capture disables live clinical hotkeys")
        CloseWindow(captureHwnd)
        Assert(KeybindGUI.isListening = false, "closing the keybind prompt stops listening")
        Assert(KeybindGUI.activeInputHook = 0, "closing the keybind prompt tears down the input hook")
        Assert(HotkeyManager.activeHotkeys.Count = registeredBeforeCapture, "closing the keybind prompt restores profile hotkeys")
    }

    Out("")
    Out(TestsFailed = 0
        ? "PASS - " TestsRun " checks"
        : "FAIL - " TestsFailed " of " TestsRun " checks failed")

    return TestsFailed = 0 ? 0 : 1
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

OnExit(Cleanup)
exitCode := 1
try exitCode := Main()
catch as err {
    Out("FATAL -- " err.Message " (" err.File ":" err.Line ")")
    exitCode := 1
}
ExitApp(exitCode)
