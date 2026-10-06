#Requires AutoHotkey v2.0
#SingleInstance Off
#ErrorStdOut
#Warn All, StdOut
FileEncoding "UTF-8"

; Layout audit for every PACS Assistant window. Each view is opened in every state
; that changes its layout and checked by LayoutAudit at 100% to 200% scaling:
; nothing outside the window, no two controls overlapping, every label fitting its
; control, and the window fitting a 1366x768 screen at 150%. Windows flash on
; screen while it runs.
;
; Pass a folder as the first argument to also save a PNG of every view, menus
; included, for visual review. Run it with Invoke-AutoHotkeyChecked (README, "Tests").

#Include HarnessErrors.ahk
OnError(OnError_StdErr)

; Before execution reaches the class definitions included below (IsolatedStorage.ahk).
#Include IsolatedStorage.ahk
global tempDir := UseIsolatedDataRoot("pacs-assistant-ui-audit")

#Include ../KeybindGUI.ahk
#Include ../AppTray.ahk
#Include DesktopChecks.ahk
#Include LayoutAudit.ahk

global shotDir := A_Args.Length ? A_Args[1] : ""
global auditProcessId := DllCall("GetCurrentProcessId", "UInt")
global auditKB := 0

Main() {
    global auditKB
    if (shotDir != "")
        DirCreate(shotDir)
    TraySetIcon(A_ScriptDir "\..\pacs-assistant.ico")
    WriteProfiles()
    DesktopChecks.Out("PACS Assistant layout audit")
    DesktopChecks.Out("")

    ProfileManager.profiles := Map()
    ProfileManager.LoadProfiles()
    ProfileManager.currentProfile := "Neuro"
    ProfileManager.defaultProfile := "Neuro"
    kb := KeybindGUI()
    auditKB := kb
    AppTray.Install(kb)
    ; A set keybind for a command this version lacks cannot register: the list
    ; shows that row as not active. Its notice is swallowed instead of shown.
    kb.notificationDriver := {Notify: (*) => 0}
    ProfileManager.profiles["Neuro"].binds["Retired Command"] := "^!F15"
    kb.ApplyBinds()
    SwitchMainProfile(kb, "Neuro")

    AuditMainWindow(kb)
    AuditMainWindowProfile(kb, "Empty", "main window, profile with no functions")
    AuditMainWindowProfile(kb, "Full", "main window, every built-in command")
    AuditAddFunction(kb, "add function, every built-in command already added")
    SwitchMainProfile(kb, "Neuro")

    lv := kb.mainView.list
    AuditAddFunction(kb, "add function, with custom keybinds")
    AuditDialog("custom keybind", "PACS Assistant - Configure Custom Keybind", () => kb.ShowCustomKeybindDialog(lv))
    SelectFunction(lv, "Sign Report")
    AuditDialog("keybind scope, any window", "PACS Assistant - Keybind Scope", () => kb.ShowScopeDialog(lv))
    SelectFunction(lv, "Paste Wet Read")
    AuditDialog("keybind scope, PACS only", "PACS Assistant - Keybind Scope", () => kb.ShowScopeDialog(lv))
    AuditDialog("set keybind", "PACS Assistant - Set Keybind", () => kb.PromptKeybind("Sign Report", lv))
    AuditDialog("set keybind, a key with two warnings", "PACS Assistant - Set Keybind",
        () => kb.PromptKeybind("Sign Report", lv), true,
        (window) => kb.ShowCapturedKey("Sign Report", lv, window, "Tab"))
    AuditDialog("set keybind, a key another function has", "PACS Assistant - Set Keybind",
        () => kb.PromptKeybind("Sign Report", lv), true,
        (window) => kb.ShowCapturedKey("Sign Report", lv, window, "^F14"))
    AuditDialog("modality attendings", "PACS Assistant - Modality Attendings", () => kb.ShowModalityAttendingsDialog())
    AuditDialog("rename profile", "PACS Assistant - Rename Profile", () => kb.PromptRenameProfile("Neuro"))

    AuditSettings()
    AuditUpdateDialog()

    AuditDialog("profile selection", "PACS Assistant - Profile Selection", () => kb.OpenProfileSelector())
    Sleep(300)
    AuditNewProfilePrompt(kb)

    if (shotDir != "")
        CaptureMenus(kb)

    HotkeyManager.DisableAllHotkeys()
    UpdateChecker.StopAutoCheck()
    try kb.gui.Destroy()
    return DesktopChecks.Finish("views")
}

; Profiles that exercise each list state: Neuro has binds in every group, a scoped
; and an unassigned bind, a bound and an unbound custom keybind and a command this
; version does not have; Empty has none; Full has every built-in command.
WriteProfiles() {
    WriteProfile("Neuro",
        Map(
            "Toggle Dictation", "^F15", "Draft Report", "^F14", "Sign Report", "^F13",
            "Next Series", "^+F14", "Previous Series", "^+F15", "Open/Force Restart PACS", "",
            "Paste Wet Read", "^+F13", "Toggle PowerScribe Window", "^!F13",
            "Custom: Normal head CT", "^!F14", "Retired Command", ""
        ),
        Map(
            "Draft Report", "PowerScribe", "Toggle Dictation", "PowerScribe",
            "Paste Wet Read", "PACS", "Next Series", "PACS", "Previous Series", "PACS",
            "Custom: Normal head CT", "PACS or PowerScribe"
        ),
        Map(
            "Custom: Normal head CT", "No acute intracranial abnormality.",
            "Custom: Unbound macro", "{F9}"
        ),
        Map("Neuro", "Smith", "Body", "Lee")
    )
    WriteProfile("Empty", Map(), Map())
    everything := Map()
    for name, _ in PACSCommands.commands
        everything[name] := ""
    WriteProfile("Full", everything, Map())
}

WriteProfile(name, binds, scopes, customs := Map(), attendings := Map()) {
    path := tempDir "\profiles\" name ".ini"
    order := ""
    for funcName, bind in binds {
        order .= funcName "|"
        IniWrite(bind, path, "Keybinds", funcName)
        IniWrite(scopes.Has(funcName) ? scopes[funcName] : "Any", path, "Scopes", funcName)
    }
    IniWrite(order, path, "Functions", "Order")
    customOrder := ""
    for funcName, keys in customs {
        customOrder .= funcName "|"
        IniWrite(keys, path, "CustomFunctions", funcName "_keys")
        IniWrite("", path, "CustomFunctions", funcName "_window")
    }
    if (customOrder != "")
        IniWrite(customOrder, path, "CustomFunctions", "Order")
    modalities := ""
    for modality, attending in attendings {
        modalities .= modality "|"
        IniWrite(attending, path, "ModalityAttendings", modality)
    }
    if (modalities != "")
        IniWrite(modalities, path, "ModalityAttendings", "Order")
}

AuditMainWindow(kb) {
    window := kb.gui
    AuditView("main window", window, true)

    kb.MarkProfileDirty(ProfileManager.currentProfile)
    AuditView("main window, unsaved changes", window, true)
    kb.ClearProfileDirty(ProfileManager.currentProfile)

    kb.ToggleSuspend()
    AuditView("main window, keybinds suspended", window, true)
    kb.ToggleSuspend()

    WinGetPos(&x, &y, &width, &height, window)
    ; MinSize stops the window at its smallest size.
    WinMove(,, 200, 200, window)
    Sleep(250)
    AuditView("main window at its minimum size", window, true)
    window.GetClientPos(,, &minimumWidth, &minimumHeight)
    DesktopChecks.Record(
        LayoutAudit.FitsSmallScreen(minimumWidth, minimumHeight, true),
        "the main window's minimum size fits a 1366x768 screen at 150%",
        minimumWidth "x" minimumHeight
    )
    WinMaximize(window)
    Sleep(300)
    AuditView("main window, maximized", window, true)
    WinRestore(window)
    WinMove(x, y, width, height, window)
    Sleep(200)
}

AuditMainWindowProfile(kb, profileName, label) {
    SwitchMainProfile(kb, profileName)
    AuditView(label, kb.gui, true)
}

; Rebuilds the main window for another profile, without touching runtime hotkeys.
SwitchMainProfile(kb, profileName) {
    kb.gui.Destroy()
    ProfileManager.currentProfile := profileName
    kb.CreateMainGUI(false)
    Sleep(150)
}

; Selects the first command, as a click does, so the description shows.
AuditAddFunction(kb, label) {
    AuditDialog(label, "PACS Assistant - Add Function", () => kb.ShowAddFunctionDialog(kb.mainView.list), true,
        (window) => SelectFirstListBoxItem(window))
}

; ControlChooseIndex also reports a double-click, which would add the command, so
; the selection is made and only LBN_SELCHANGE is sent.
SelectFirstListBoxItem(window) {
    for ctrl in window {
        if (ctrl.Type = "ListBox" && ControlGetItems(ctrl).Length) {
            ctrl.Choose(1)
            id := DllCall("GetDlgCtrlID", "Ptr", ctrl.Hwnd, "Int")
            SendMessage(0x111, (1 << 16) | id, ctrl.Hwnd, window)  ; WM_COMMAND, LBN_SELCHANGE
            Sleep(100)
            return
        }
    }
}

AuditSettings() {
    AuditDialog("settings, development build", "PACS Assistant - Settings", () => Settings.ShowDialog())
    isDevBuild := AppVersion.isDevBuild
    try {
        AppVersion.isDevBuild := false
        Settings.SaveValues(Map(
            "SwapMicrophoneOnLogin", true,
            "MicrophoneName", "Nuance PowerMic III",
            "AlertSound", "Custom File",
            "CustomSoundFile", "C:\Users\Example\Music\Reading room alerts\new study chime long name.wav",
            "AutoRefreshPACS", true,
            "AudioAlertNewCase", true,
            "SkipBetaVersions", false
        ))
        AuditDialog("settings, release build with every option on", "PACS Assistant - Settings", () => Settings.ShowDialog())
    } finally AppVersion.isDevBuild := isDevBuild
}

AuditUpdateDialog() {
    AppVersion.current := "v2.0.19"
    notes := "What's changed`r`n`r`n- Wet reads wait for the note to fill before saving.`r`n- A cleaner main window."
    longNotes := notes
    loop 30
        longNotes .= "`r`n- Release note line " A_Index " describing one more change in some detail."
    for index, releaseNotes in [notes, longNotes] {
        info := {
            hasUpdate: true,
            currentVersion: "v2.0.19",
            latestVersion: index = 1 ? "v2.1.0" : "v2.10.0-beta.12",
            releaseNotes: releaseNotes
        }
        AuditDialog(
            index = 1 ? "update available" : "update available, long notes and a beta version",
            "PACS Assistant - Update Available",
            () => UpdateChecker.ShowUpdateDialog(info)
        )
    }
    UpdateChecker.StopAutoCheck()
}

AuditNewProfilePrompt(kb) {
    prompt := 0
    AuditDialog("new profile", "PACS Assistant - Create New Profile", () => (prompt := kb.PromptNewProfile()), false)
    if IsObject(prompt)
        try prompt.Destroy()
    ; First run: no profile exists, so the prompt offers Exit instead of Cancel.
    profiles := ProfileManager.profiles
    ProfileManager.profiles := Map()
    try {
        AuditDialog("new profile, first run", "PACS Assistant - Create New Profile", () => (prompt := kb.PromptNewProfile()), false)
        if IsObject(prompt)
            try prompt.Destroy()
    } finally ProfileManager.profiles := profiles
}

SelectFunction(listView, funcName) {
    loop listView.GetCount() {
        if (listView.GetText(A_Index, 1) == funcName) {
            listView.Modify(A_Index, "Select Focus")
            return
        }
    }
    throw Error("No '" funcName "' row")
}

; Opens a view, puts it in a state when given prepare, audits it, and closes it
; with its title-bar X unless told not to.
AuditDialog(label, title, action, close := true, prepare := 0) {
    window := 0
    try window := OpenView(title, action)
    catch Any as err
        return DesktopChecks.Record(false, label, ErrorText.Describe(err))
    try {
        if prepare
            prepare.Call(window)
        AuditView(label, window)
    } finally {
        if close
            CloseView(window)
    }
}

AuditView(label, window, isMain := false) {
    WinActivate(window)
    Sleep(150)
    problems := LayoutAudit.Problems(window)
    window.GetClientPos(,, &width, &height)
    if (!isMain && !LayoutAudit.FitsSmallScreen(width, height))
        problems.Push("the window (" width "x" height ") does not fit a 1366x768 screen at 150%")
    detail := ""
    for problem in problems
        detail .= "`n         " problem
    DesktopChecks.Record(problems.Length = 0, label, detail)
    if (shotDir != "")
        CaptureWindow(window.Hwnd, ShotName(label))
}

OpenView(title, action) {
    title .= " ahk_pid " auditProcessId
    before := Map()
    for hwnd in WinGetList(title)
        before[hwnd] := true
    action.Call()
    Sleep(150)
    for hwnd in WinGetList(title) {
        if !before.Has(hwnd)
            return GuiFromHwnd(hwnd)
    }
    throw Error("No new '" title "' window opened")
}

CloseView(window) {
    hwnd := 0
    try hwnd := window.Hwnd
    if (hwnd && WinExist("ahk_id " hwnd)) {
        WinClose("ahk_id " hwnd)
        Sleep(150)
    }
}

ShotName(label) {
    static count := 0
    count++
    return Format("{:02}-", count) RegExReplace(StrLower(label), "[^a-z0-9]+", "-")
}

; Screenshots of the menu bar menus, the list's context menu and the tray menu.
; Windows draws menus, and Show does not return while one is open, so a second
; process captures the screen around the window and then closes the menu.
CaptureMenus(kb) {
    window := kb.gui
    WinActivate(window)
    Sleep(150)
    CoordMode("Menu", "Client")
    CoordMode("Mouse", "Client")
    scale := A_ScreenDPI / 96
    ; Each menu bar menu opens where it would drop down from the bar.
    for index, entry in [["Profile", 0], ["Tools", 52], ["Help", 100]] {
        name := entry[1], x := Round(entry[2] * scale)
        CaptureOpenMenu(ShotName("menu " name), () => kb.mainView.menus[name].Show(x, 0))
    }
    SelectFunction(kb.mainView.list, "Sign Report")
    kb.mainView.list.GetPos(&listX, &listY)
    MouseMove(Round((listX + 80) * scale), Round((listY + 60) * scale), 0)
    CaptureOpenMenu(ShotName("menu function context"), () => kb.ShowFunctionMenu(kb.mainView.list, 1))
    CaptureOpenMenu(ShotName("menu tray"), () => A_TrayMenu.Show())
}

CaptureOpenMenu(name, opener) {
    WinGetPos(&x, &y, &w, &h, auditKB.gui)
    ; Every menu opens over the window, so the window's rectangle holds it.
    Run(Format('"{}" "{}" --capture-menu "{}" {} {} {} {}',
        A_AhkPath, A_ScriptFullPath, shotDir "\" name ".png", x, y, w, h))
    opener.Call()
    Sleep(400)
}

; Helper mode: wait for the menu, save the screen rectangle, close the menu.
CaptureMenuHelper(path, left, top, width, height) {
    global shotDir
    Sleep(900)
    SplitPath(path, &fileName, &shotDir, , &name)
    CaptureRect(Integer(left), Integer(top), Integer(width), Integer(height), name)
    Send("{Escape}")
    return 0
}

CaptureWindow(hwnd, name) {
    DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
    Sleep(300)
    ; The visible frame, without the invisible resize border.
    rect := Buffer(16, 0)
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16)
    left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
    CaptureRect(left, top, NumGet(rect, 8, "Int") - left, NumGet(rect, 12, "Int") - top, name)
}

; Copies a screen rectangle to <shotDir>\<name>.png.
CaptureRect(left, top, width, height, name) {
    screen := DllCall("GetDC", "Ptr", 0, "Ptr")
    memory := DllCall("CreateCompatibleDC", "Ptr", screen, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", screen, "Int", width, "Int", height, "Ptr")
    previous := DllCall("SelectObject", "Ptr", memory, "Ptr", bitmap, "Ptr")
    DllCall("BitBlt", "Ptr", memory, "Int", 0, "Int", 0, "Int", width, "Int", height,
        "Ptr", screen, "Int", left, "Int", top, "UInt", 0x00CC0020)  ; SRCCOPY
    DllCall("SelectObject", "Ptr", memory, "Ptr", previous)
    SavePng(bitmap, shotDir "\" name ".png")
    DllCall("DeleteObject", "Ptr", bitmap)
    DllCall("DeleteDC", "Ptr", memory)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
}

SavePng(bitmapHandle, path) {
    static token := 0
    if !token {
        DllCall("LoadLibrary", "Str", "gdiplus")
        input := Buffer(24, 0)
        NumPut("UInt", 1, input)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", input, "Ptr", 0)
    }
    image := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", bitmapHandle, "Ptr", 0, "Ptr*", &image)
    encoder := Buffer(16)
    DllCall("ole32\CLSIDFromString", "Str", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", encoder)
    status := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", image, "Str", path, "Ptr", encoder, "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
    if status
        throw Error("Could not save " path " (GDI+ status " status ")")
}

; Registered to run before UseIsolatedDataRoot removes tempDir.
Cleanup(*) {
    try HotkeyManager.DisableAllHotkeys()
    try UpdateChecker.StopAutoCheck()
    if IsObject(auditKB)
        try auditKB.gui.Destroy()
    try SetWorkingDir(A_ScriptDir)
}

OnExit(Cleanup, -1)
ExitApp(RunAudit())

; Converts a fatal harness error into a nonzero exit (see run-gui-smoke.ahk).
RunAudit() {
    if (A_Args.Length = 6 && A_Args[1] = "--capture-menu")
        return CaptureMenuHelper(A_Args[2], A_Args[3], A_Args[4], A_Args[5], A_Args[6])
    exitCode := 1
    try exitCode := Main()
    catch Any as err {
        DesktopChecks.Out("FATAL -- " ErrorText.Describe(err))
        exitCode := 1
    }
    return exitCode
}
