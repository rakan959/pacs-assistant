#Requires AutoHotkey v2.0
#SingleInstance Off
#ErrorStdOut
#Warn All, StdOut
FileEncoding "UTF-8"

; Smoke test for the windows PACS Assistant builds. Syntax checking cannot catch a
; bad control reference or a broken layout, so this actually constructs each window,
; then closes it again. Windows will flash on screen while it runs.
;
; Run it with Invoke-AutoHotkeyChecked (README, "Tests"): AutoHotkey is a GUI-subsystem
; program, so a plain launch neither waits for the run nor reports its exit code.

#Include HarnessErrors.ahk
OnError(OnError_StdErr)

; Before execution reaches the class definitions included below (IsolatedStorage.ahk).
; Settings, config and profiles all live in tempDir for this run.
#Include IsolatedStorage.ahk
global tempDir := UseIsolatedDataRoot("pacs-assistant-gui-smoke")

#Include ../KeybindGUI.ahk
#Include DesktopChecks.ahk

global openedWindows := []
global smokeKB := 0

Out(text) => DesktopChecks.Out(text)

Check(label, action) {
    ; catch Any: a thrown non-Error value fails this check rather than the whole run.
    try action()
    catch Any as err
        return DesktopChecks.Record(false, label, ErrorText.Describe(err))
    return DesktopChecks.Record(true, label)
}

Assert(condition, label) => DesktopChecks.Record(condition, label)

OpenAndCaptureWindow(title, action) {
    global openedWindows
    ; Only this run's windows: another process, such as a running PACS Assistant,
    ; can open one with the same title meanwhile.
    title .= " ahk_pid " DllCall("GetCurrentProcessId", "UInt")
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
    openedWindows.Push(created[1])
    return created[1]
}

; WinExist ignores hidden windows, so it cannot tell a dialog that Close merely hid
; from one that was destroyed. IsWindow reports the HWND's real lifetime.
WindowIsAlive(hwnd) {
    return hwnd > 0 && DllCall("IsWindow", "Ptr", hwnd)
}

; Close only the exact HWND created by this smoke run.
CloseWindow(hwnd) {
    if (hwnd > 0 && WinExist("ahk_id " hwnd)) {
        WinClose("ahk_id " hwnd)
        Sleep(150)
    }
}

; Closes a dialog with X and checks it is destroyed. A dialog that never opened has
; already failed its build check, so there is nothing to report here.
AssertClosingDestroys(hwnd, message) {
    if !hwnd
        return
    CloseWindow(hwnd)
    Assert(!WindowIsAlive(hwnd), message)
}

; Registered to run before UseIsolatedDataRoot removes tempDir: the windows close
; first, and Windows cannot delete the working directory.
Cleanup(*) {
    global openedWindows, smokeKB
    try HotkeyManager.DisableAllHotkeys()
    try UpdateChecker.StopAutoCheck()
    for hwnd in openedWindows
        try CloseWindow(hwnd)
    if smokeKB
        try smokeKB.gui.Destroy()
    try SetWorkingDir(A_ScriptDir)
}

FindListView(guiObj) {
    for ctrl in guiObj {
        if (ctrl.Type = "ListView")
            return ctrl
    }
    return 0
}

Main() {
    global tempDir, smokeKB

    SetWorkingDir(tempDir)

    ; A profile with a built-in bind, a scoped bind and a custom function.
    ; F13-F15 do not exist on a normal keyboard, so applying these binds cannot
    ; swallow a key the user might actually press.
    path := tempDir "\profiles\Smoke.ini"
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
    smokeKB := kb

    lv := FindListView(kb.gui)
    Assert(lv != 0, "main window has a keybind list")

    ; A refused close (here: a clinical command holds the exclusive lease) must leave
    ; the main window visible. Gui hides a window after any Close callback that does
    ; not return true, which would strand the app with no visible window.
    mainHwnd := kb.gui.Hwnd
    PACSCommands.clinicalCommandActive := true
    PACSCommands.activeClinicalCommand := "Smoke Command"
    try {
        WinClose("ahk_id " mainHwnd)
        Sleep(150)
    } finally {
        PACSCommands.clinicalCommandActive := false
        PACSCommands.activeClinicalCommand := ""
    }
    Assert(DllCall("IsWindowVisible", "Ptr", mainHwnd), "a refused main-window close keeps the window visible")

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
        AssertClosingDestroys(scopeHwnd, "closing the scope dialog with X destroys it")
    }

    modalityHwnd := 0
    Check("modality attendings dialog builds", () => (
        modalityHwnd := OpenAndCaptureWindow(
            "PACS Assistant - Modality Attendings",
            () => kb.ShowModalityAttendingsDialog()
        )
    ))
    AssertClosingDestroys(modalityHwnd, "closing the modality attendings dialog with X destroys it")

    settingsHwnd := 0
    Check("settings dialog builds", () => (
        settingsHwnd := OpenAndCaptureWindow(
            "PACS Assistant - Settings",
            () => Settings.ShowDialog()
        )
    ))
    AssertClosingDestroys(settingsHwnd, "closing the settings dialog with X destroys it")

    ; The dialog offers only a newer version, so the run must not depend on the
    ; version of the build it runs in (a tag build may be v2.1.0 or later).
    AppVersion.current := "v0.0.1-test"
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
    AssertClosingDestroys(updateHwnd, "closing the update dialog with X destroys it")
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

    return DesktopChecks.Finish("checks")
}

AssertScope(listView, funcName, expected) {
    loop listView.GetCount() {
        if (listView.GetText(A_Index, 1) = funcName) {
            Assert(listView.GetText(A_Index, 3) = expected, "'" funcName "' shows scope '" expected "'")
            return
        }
    }
    Assert(false, "'" funcName "' is in the list")
}

OnExit(Cleanup, -1)
ExitApp(RunSmoke())

; Converts a fatal harness error into a nonzero exit. Keeping the catch inside a
; function keeps `err` local, so it cannot shadow every production `catch as err`.
RunSmoke() {
    exitCode := 1
    try exitCode := Main()
    catch Any as err {
        Out("FATAL -- " ErrorText.Describe(err))
        exitCode := 1
    }
    return exitCode
}
