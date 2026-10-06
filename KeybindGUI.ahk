; = CONTENTS
;   + Preamble
;   + KeybindGUI class (main window: profile & keybind editing, hotkey capture,
;       modality/attending assignment, save/rename/delete, profile switching)

#Requires AutoHotkey v2.0

#Include ExclusiveOperations.ahk
#Include AppLog.ahk
#Include HotkeyManager.ahk
#Include ProfileManager.ahk
#Include PACSCommands.ahk
#Include UpdateChecker.ahk
#Include Settings.ahk
#Include UITheme.ahk
#Include CommandInfo.ahk
#Include WindowPlacement.ahk
#Include KeybindCard.ahk
#Include RecentErrors.ahk
#Include StatusPanel.ahk

class KeybindGUI {
    gui := ""
    profileSelectorGui := 0
    ; Controls of the live main window that RefreshMainView updates; see BuildMainView.
    mainView := 0
    static isListening := false
    static activeInputHook := 0
    static captureRuntimeProfile := 0
    static captureOwnerGui := 0
    static profileMutationRevisions := Map()
    static shutdownAuthorized := false
    ; Notices raised while the profile-mutation lease is held; see NotifyUser.
    static deferredNotices := []
    ; The V option would pass the selected key through to the foreground application.
    ; Capture is intentionally suppressing: the key is configuration data only.
    static inputHookOptions := ""
    ; Modifier symbols and their display names, in display order.
    static modifierNames := [
        ["<^", "LCtrl"], [">^", "RCtrl"], ["^", "Ctrl"],
        ["<!", "LAlt"], [">!", "RAlt"], ["!", "Alt"],
        ["<+", "LShift"], [">+", "RShift"], ["+", "Shift"],
        ["<#", "LWin"], [">#", "RWin"], ["#", "Win"]
    ]
    ; Main window content width and keybind-list height at first show, in logical
    ; units. The window can be resized larger; the list takes the extra space.
    static mainContentWidth := 640
    static mainListHeight := 360
    static mainMinListHeight := 120
    ; The main list's groups, in display order, each with its built-in commands in
    ; the order they are listed. Presentation only: a function's group never affects
    ; its binding. Custom functions go to Custom; a name no group lists (such as a
    ; command from another version) goes to the last group.
    static functionGroups := [
        {name: "PowerScribe", functions: [
            "Toggle Dictation", "Draft Report", "Sign Report", "Select Next Field",
            "Select Previous Field", "Delete Previous Word", "Delete Next Word",
            "Set PowerScribe Microphone"
        ]},
        {name: "PACS", functions: ["Next Series", "Previous Series", "Open/Force Restart PACS"]},
        {name: "Wet reads", functions: ["Paste Wet Read", "Paste Wet Read (Clipboard)"]},
        {name: "Windows", functions: ["Toggle PowerScribe Window", "Toggle EPIC Window"]},
        {name: "Custom", functions: []},
        {name: "Not in this version", functions: []}
    ]
    static customGroupId := 5
    ; Default values ("Unassigned", "Any window") are drawn in this color
    ; (COLORREF, 0xBBGGRR): 4.5:1 against white, so still readable.
    static mutedTextColor := 0x767676
    ; A keybind that is set but not registered is drawn in Windows' error red
    ; (#C42B1C), 5.9:1 against white.
    static inactiveTextColor := 0x1C2BC4
    ; Why each set keybind of the last applied profile is not registered, by
    ; function name. Replaced by every ApplyProfileBinds.
    static runtimeFailures := Map()

    __New() {
        ProfileManager.LoadProfiles()
        if (ProfileManager.loadErrors.Length > 0)
            MsgBox(KeybindGUI.LoadErrorSummary(ProfileManager.loadErrors), "Profile Load Error", "Icon!")
        if ProfileManager.profiles.Count = 0 {
            this.PromptNewProfile()
        } else if (ProfileManager.defaultProfile != "" && ProfileManager.profiles.Has(ProfileManager.defaultProfile)) {
            ; If there's a valid default profile, load it directly, minimized to the
            ; tray when Settings asks for that. A window the user opens later always
            ; shows.
            ProfileManager.currentProfile := ProfileManager.defaultProfile
            this.CreateMainGUI(true, Settings.Get("StartMinimized"))
        } else {
            this.ShowProfileSelector()
        }
    }

    /**
     * Builds and shows the main window for the current profile: its keybind list,
     * the commands that edit it, and a status bar that says whether there are
     * unsaved changes and whether keybinds are suspended.
     */
    CreateMainGUI(applyBinds := true, startHidden := false) {
        profileName := ProfileManager.currentProfile
        this.gui := UITheme.NewWindow("PACS Assistant - " profileName, "+Resize")
        view := this.BuildMainView(this.gui, profileName)
        this.mainView := view

        ; Close hides the window after any callback that does not return true. Every
        ; successful path destroys or hides the window, or exits, so a refused close
        ; must keep it visible rather than strand the app with no window.
        this.gui.OnEvent("Close", (*) => (this.CloseMainWindow(), true))
        this.gui.OnEvent("Size", (window, minMax, *) => this.OnMainWindowSize(view, minMax))

        width := KeybindGUI.mainContentWidth + 2 * UITheme.margin
        height := this.MainViewHeight(view, KeybindGUI.FitListHeight(view))
        this.LayoutMainView(view, width, height)
        this.RefreshMainView()
        ; Built hidden, then moved to where it was last left, then shown.
        this.gui.Show("Hide w" width " h" height)
        ; Logical units, like the layout: Gui scales MinSize for the display itself.
        this.gui.Opt("+MinSize" width "x" this.MainViewHeight(view, KeybindGUI.mainMinListHeight))
        maximize := this.RestoreMainWindowPlacement()
        this.WatchMainWindowMoves()
        if startHidden {
            this.pendingMaximize := maximize
        } else {
            this.gui.Show(maximize ? "Maximize" : "")
            ; Start in the list, so the arrow keys, F2 and Delete work at once.
            view.list.Focus()
        }
        A_IconTip := "PACS Assistant - " profileName

        if applyBinds
            this.ApplyBinds()
    }

    ; Moves the hidden main window to its saved place when that is still on a
    ; monitor. @returns whether it was last maximized
    RestoreMainWindowPlacement() {
        saved := WindowPlacement.Load()
        if !WindowPlacement.IsReachable(saved, WindowPlacement.WorkAreas())
            return false
        WinMove(saved.x, saved.y, saved.w, saved.h, this.gui)
        return saved.maximized
    }

    ; Saves the window's place when the user finishes moving or resizing it
    ; (WM_EXITSIZEMOVE). Registered once; it acts only for the current main window.
    WatchMainWindowMoves() {
        if this.HasOwnProp("watchingMoves")
            return
        this.watchingMoves := true
        OnMessage(0x232, ObjBindMethod(this, "OnWindowMoved"))
    }

    OnWindowMoved(wParam, lParam, msg, hwnd) {
        if !(this.HasMainWindow() && hwnd = this.gui.Hwnd)
            return
        if (WinGetMinMax("ahk_id " hwnd) != 0)
            return
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        WindowPlacement.SaveRect(x, y, w, h)
    }

    OnMainWindowSize(view, minMax) {
        if (minMax = -1)
            return
        ; Remember maximizing and restoring, the changes WM_EXITSIZEMOVE misses.
        if (!HasProp(view, "lastMinMax") || view.lastMinMax != minMax) {
            if HasProp(view, "lastMinMax")
                WindowPlacement.SaveMaximized(minMax = 1)
            view.lastMinMax := minMax
        }
        this.LayoutMainView(view)
    }

    ; The window's X button: exits, or with Close to the tray only hides the window.
    CloseMainWindow() {
        if !Settings.Get("CloseToTray")
            return this.RequestExit()
        this.gui.Hide()
        if !KeybindGUI.closedToTrayNoticeShown {
            KeybindGUI.closedToTrayNoticeShown := true
            this.NotifyNonModal(
                "PACS Assistant is still running. Double-click its tray icon to open it; exit from the tray menu.",
                "Still Running",
                "Iconi"
            )
        }
        return false
    }

    static closedToTrayNoticeShown := false

    BuildMainView(mainGui, profileName) {
        view := {gui: mainGui, profileName: profileName}
        mainGui.MenuBar := this.BuildMainMenu(view)

        ; Header: which profile this is, a one-line summary, and the way to another.
        view.heading := UITheme.AddHeading(mainGui, profileName, "xm ym w400 h30", 15)
        view.summary := UITheme.AddNote(mainGui, "", "xm y+0 w400")
        view.switchButton := this.AddMainButton(mainGui, "S&witch Profile...", 140, (*) => this.OpenProfileSelector())

        ; Commands on the selected function. The last three need a selection and
        ; are enabled by RefreshMainView.
        view.addButton := this.AddMainButton(mainGui, "&Add Function...", 124, (*) => this.ShowAddFunctionDialog(view.list))
        view.keybindButton := this.AddMainButton(mainGui, "Set &Keybind...", 112, (*) => this.ChangeSelectedKeybind(view.list))
        view.scopeButton := this.AddMainButton(mainGui, "Set S&cope...", 104, (*) => this.ShowScopeDialog(view.list))
        view.removeButton := this.AddMainButton(mainGui, "&Remove", UITheme.buttonWidth, (*) => this.RemoveFunction(view.list))

        ; The keybind list: function, its key, and the window it is restricted to.
        ; LV0x10000 (double buffering) keeps it from flickering while resized.
        ; LV0x10000 double-buffers against flicker; LV0x400 asks for hover text.
        lv := mainGui.Add("ListView", "w600 h200 -Multi +LV0x10000 +LV0x400", ["Function", "Keybind", "Active In"])
        view.list := lv
        UITheme.UseExplorerTheme(lv)
        KeybindGUI.EnableFunctionGroups(lv)
        currentProfile := ProfileManager.profiles[profileName]
        for funcName in KeybindGUI.FunctionDisplayOrder(currentProfile.binds) {
            bind := currentProfile.binds[funcName]
            this.AddFunctionRow(lv, funcName, this.PrettifyHotkey(bind), this.ScopeLabel(funcName))
        }
        if lv.GetCount()
            lv.Modify(1, "Select Focus")  ; rows were added in display order
        lv.OnEvent("ItemSelect", (*) => this.RefreshMainView())
        lv.OnEvent("DoubleClick", (ctrl, row) => row ? this.ChangeSelectedKeybind(ctrl) : 0)
        lv.OnEvent("ContextMenu", (ctrl, row, *) => this.ShowFunctionMenu(ctrl, row))
        lv.OnNotify(-155, (ctrl, lParam) => this.OnFunctionListKey(ctrl, lParam))  ; LVN_KEYDOWN
        lv.OnNotify(-12, (ctrl, lParam) => KeybindGUI.OnFunctionListDraw(ctrl, lParam))  ; NM_CUSTOMDRAW
        lv.OnNotify(-158, (ctrl, lParam) => this.OnFunctionListInfoTip(ctrl, lParam))  ; LVN_GETINFOTIPW

        ; Footer: profile-wide settings at the left, Save at the right.
        view.rule := UITheme.AddSeparator(mainGui, "x0 w10 h1")
        view.attendingsButton := this.AddMainButton(mainGui, "Modality Atte&ndings...", 160, (*) => this.ShowModalityAttendingsDialog())
        view.settingsButton := this.AddMainButton(mainGui, "Settin&gs...", 104, (*) => Settings.ShowDialog())
        view.saveButton := this.AddMainButton(mainGui, "&Save Changes", 128, (*) => this.SaveCurrentProfile())

        view.status := mainGui.Add("StatusBar")
        scale := A_ScreenDPI / 96
        view.status.SetParts(Round(220 * scale), Round(200 * scale))
        view.status.OnEvent("DoubleClick", (bar, part) => part = 2 ? this.ShowStatus() : 0)
        return view
    }

    /**
     * Adds a function's row to a keybind list. In the main window's grouped list the
     * row is placed in its group at once: a grouped ListView does not show a row
     * that belongs to no group.
     * @returns the row number
     */
    AddFunctionRow(listView, funcName, bindText, scopeText) {
        row := listView.Add(, funcName, bindText, scopeText)
        if (row && HasProp(listView, "functionGroupsEnabled"))
            KeybindGUI.SetRowGroup(listView, row, KeybindGUI.FunctionGroupId(funcName))
        return row
    }

    ; The group a function's row goes in (a functionGroups index).
    static FunctionGroupId(funcName) {
        if (InStr(funcName, "Custom: ") = 1)
            return this.customGroupId
        for index, group in this.functionGroups {
            for name in group.functions {
                if (name == funcName)
                    return index
            }
        }
        return this.functionGroups.Length
    }

    ; A profile's function names in display order: each group's built-in commands
    ; in the order the group lists them, then custom functions, then the rest.
    static FunctionDisplayOrder(binds) {
        ordered := []
        listed := Map()
        for group in this.functionGroups {
            for name in group.functions {
                if binds.Has(name) {
                    ordered.Push(name)
                    listed[name] := true
                }
            }
        }
        for groupId in [this.customGroupId, this.functionGroups.Length] {
            for name, _ in binds {
                if (!listed.Has(name) && this.FunctionGroupId(name) = groupId) {
                    ordered.Push(name)
                    listed[name] := true
                }
            }
        }
        return ordered
    }

    ; Turns on group view and adds every group (LVM_ENABLEGROUPVIEW,
    ; LVM_INSERTGROUP). A group without rows is not shown.
    static EnableFunctionGroups(listView) {
        SendMessage(0x109D, true, 0, listView)
        ; LVGROUP up to uAlign: cbSize, mask, pszHeader, cchHeader, pszFooter,
        ; cchFooter, iGroupId, stateMask, state, uAlign.
        headerOffset := 8
        groupIdOffset := A_PtrSize = 8 ? 36 : 24
        size := A_PtrSize = 8 ? 56 : 40
        for index, group in this.functionGroups {
            header := group.name
            info := Buffer(size, 0)
            NumPut("UInt", size, info, 0)
            NumPut("UInt", 0x11, info, 4)  ; LVGF_HEADER | LVGF_GROUPID
            NumPut("Ptr", StrPtr(header), info, headerOffset)
            NumPut("Int", index, info, groupIdOffset)
            SendMessage(0x1091, -1, info.Ptr, listView)
        }
        listView.functionGroupsEnabled := true
    }

    ; LVM_SETITEMW with LVIF_GROUPID: moves a row into a group.
    static SetRowGroup(listView, row, groupId) {
        item := Buffer(A_PtrSize = 8 ? 88 : 60, 0)
        NumPut("UInt", 0x100, item, 0)
        NumPut("Int", row - 1, item, 4)
        NumPut("Int", groupId, item, A_PtrSize = 8 ? 52 : 40)
        SendMessage(0x104C, 0, item.Ptr, listView)
    }

    /**
     * NM_CUSTOMDRAW for the keybind list: draws the default values, "Unassigned"
     * and "Any window", in a muted color so the keybinds that are set stand out.
     * Any failure leaves the default drawing.
     */
    static OnFunctionListDraw(listView, lParam) {
        ; NMLVCUSTOMDRAW: dwDrawStage after the NMHDR header; dwItemSpec, clrText and
        ; iSubItem at their x64 or x86 offsets.
        stageOffset := 3 * A_PtrSize
        itemOffset := A_PtrSize = 8 ? 56 : 36
        textColorOffset := A_PtrSize = 8 ? 80 : 48
        subItemOffset := A_PtrSize = 8 ? 88 : 56
        try {
            stage := NumGet(lParam, stageOffset, "UInt")
            if (stage = 0x1)      ; CDDS_PREPAINT
                return 0x20       ; CDRF_NOTIFYITEMDRAW
            if (stage = 0x10001)  ; CDDS_ITEMPREPAINT
                return 0x20       ; CDRF_NOTIFYSUBITEMDRAW
            if (stage = 0x30001) {  ; CDDS_ITEMPREPAINT | CDDS_SUBITEM
                row := NumGet(lParam, itemOffset, "UPtr") + 1
                column := NumGet(lParam, subItemOffset, "Int") + 1
                text := column > 1 ? listView.GetText(row, column) : ""
                muted := (column = 2 && text == "Unassigned") || (column = 3 && text == "Any window")
                inactive := column = 2 && this.runtimeFailures.Has(listView.GetText(row, 1))
                ; Set for every cell: a color set for one cell carries into the next.
                color := inactive ? this.inactiveTextColor
                    : muted ? this.mutedTextColor
                    : DllCall("GetSysColor", "Int", 8, "UInt")
                NumPut("UInt", color, lParam, textColorOffset)
            }
        }
        return 0
    }

    AddMainButton(mainGui, text, width, action) {
        button := mainGui.Add("Button", "w" width " h" UITheme.buttonHeight, text)
        button.OnEvent("Click", action)
        return button
    }

    BuildMainMenu(view) {
        profileMenu := Menu()
        profileMenu.Add("&Switch Profile...", (*) => this.OpenProfileSelector())
        profileMenu.Add("&Rename Profile...", (*) => this.PromptRenameProfile(ProfileManager.currentProfile))
        profileMenu.Add("D&uplicate Profile...", (*) => this.DuplicateCurrentProfile())
        profileMenu.Add()
        profileMenu.Add(KeybindGUI.saveMenuItem, (*) => this.SaveCurrentProfile())
        profileMenu.Add(KeybindGUI.discardMenuItem, (*) => this.DiscardCurrentChanges())
        profileMenu.Add()
        profileMenu.Add("&Import Profile...", (*) => this.ImportProfile())
        profileMenu.Add("Ex&port Profile...", (*) => this.ExportCurrentProfile())
        profileMenu.Add()
        profileMenu.Add("E&xit", (*) => this.RequestExit())

        toolsMenu := Menu()
        toolsMenu.Add("S&tatus...", (*) => this.ShowStatus())
        toolsMenu.Add()
        toolsMenu.Add("Modality &Attendings...", (*) => this.ShowModalityAttendingsDialog())
        toolsMenu.Add("&Settings...", (*) => Settings.ShowDialog())
        toolsMenu.Add()
        toolsMenu.Add(KeybindGUI.suspendMenuItem, (*) => this.ToggleSuspend())
        toolsMenu.Add()
        toolsMenu.Add("Open &Data Folder", (*) => this.OpenDataFolder())

        helpMenu := Menu()
        helpMenu.Add("&Keybind Card...", (*) => this.ShowKeybindCard())
        helpMenu.Add("Recent &Errors...", (*) => RecentErrors.Show(this.HasMainWindow() ? this.gui : 0))
        helpMenu.Add()
        helpMenu.Add("Check for &Updates...", (*) => UpdateChecker.ShowUpdateDialog())
        helpMenu.Add()
        helpMenu.Add("&About PACS Assistant", (*) => this.ShowAbout())

        view.profileMenu := profileMenu
        view.menus := Map("Profile", profileMenu, "Tools", toolsMenu, "Help", helpMenu)
        bar := MenuBar()
        bar.Add("&Profile", profileMenu)
        bar.Add("&Tools", toolsMenu)
        bar.Add("&Help", helpMenu)
        return bar
    }

    static saveMenuItem := "&Save Changes"
    static discardMenuItem := "&Discard Changes..."
    static suspendMenuItem := "S&uspend Keybinds"

    /**
     * Turns every keybind off, or back on. Key capture and the background services
     * are unaffected. The window's title, status bar and menu, and the tray menu
     * (through onSuspendChanged), all show the state.
     * @returns whether keybinds are now suspended
     */
    ToggleSuspend() {
        Suspend(-1)
        this.RefreshMainView()
        if this.HasOwnProp("onSuspendChanged")
            this.onSuspendChanged.Call()
        return A_IsSuspended
    }

    ; Client height of the main window for a given keybind-list height.
    MainViewHeight(view, listHeight) {
        view.status.GetPos(,,, &statusHeight)
        return KeybindGUI.MainListTop() + listHeight + KeybindGUI.MainFooterHeight() + statusHeight
    }

    static MainListTop() => UITheme.margin + 62 + UITheme.buttonHeight + 10

    static MainFooterHeight() => UITheme.sectionGap + 1 + 12 + UITheme.buttonHeight + 14

    ; The first list height, reduced so the whole window fits the primary monitor's
    ; work area (title bar, menu and borders take about 90 logical units).
    static FitListHeight(view) {
        try {
            MonitorGetWorkArea(MonitorGetPrimary(),, &top,, &bottom)
            view.status.GetPos(,,, &statusHeight)
            available := (bottom - top) * 96 / A_ScreenDPI - 90
                - this.MainListTop() - this.MainFooterHeight() - statusHeight
            return Max(this.mainMinListHeight, Min(this.mainListHeight, Floor(available)))
        }
        return this.mainListHeight
    }

    /**
     * Positions the main window's controls for a client area of width x height
     * logical units, or for the window's current size when they are omitted.
     */
    LayoutMainView(view, width := 0, height := 0) {
        if !width
            view.gui.GetClientPos(,, &width, &height)
        m := UITheme.margin
        gap := UITheme.gap
        buttonHeight := UITheme.buttonHeight
        contentWidth := width - 2 * m

        view.heading.Move(m, m, contentWidth - 160, 30)
        view.summary.Move(m, m + 32, contentWidth - 160, 18)
        view.switchButton.Move(m + contentWidth - 140, m + 2, 140, buttonHeight)

        x := m
        for button in [view.addButton, view.keybindButton, view.scopeButton, view.removeButton] {
            button.GetPos(,, &buttonWidth)
            button.Move(x, m + 62, buttonWidth, buttonHeight)
            x += buttonWidth + gap
        }

        view.status.GetPos(,,, &statusHeight)
        listTop := KeybindGUI.MainListTop()
        listHeight := Max(40, height - statusHeight - KeybindGUI.MainFooterHeight() - listTop)
        view.list.Move(m, listTop, contentWidth, listHeight)

        ruleY := listTop + listHeight + UITheme.sectionGap
        view.rule.Move(0, ruleY, width, 1)
        buttonY := ruleY + 13
        view.attendingsButton.Move(m, buttonY, 160, buttonHeight)
        view.settingsButton.Move(m + 160 + gap, buttonY, 104, buttonHeight)
        view.saveButton.Move(m + contentWidth - 128, buttonY, 128, buttonHeight)
        this.ResizeColumns(view.list)
    }

    /**
     * Updates what the main window derives from state: the profile summary, which
     * commands are available, and the status bar. Purely presentational, so a
     * failure is logged instead of interrupting the profile operation that caused it.
     */
    RefreshMainView() {
        if !this.HasOwnProp("mainView")
            return false
        view := this.mainView
        try {
            if !(IsObject(view) && this.GuiIsLive(view.gui) && view.gui == this.gui)
                return false
            dirty := this.IsProfileDirty(view.profileName)
            selected := view.list.GetNext(0) > 0
            view.summary.Value := KeybindGUI.ProfileSummary(
                view.profileName = ProfileManager.defaultProfile,
                view.list.GetCount()
            )
            for button in [view.keybindButton, view.scopeButton, view.removeButton]
                button.Enabled := selected
            view.saveButton.Enabled := dirty
            for item in [KeybindGUI.saveMenuItem, KeybindGUI.discardMenuItem] {
                if dirty
                    view.profileMenu.Enable(item)
                else
                    view.profileMenu.Disable(item)
            }
            view.status.SetText(" " (dirty ? "Unsaved changes" : "All changes saved"), 1)
            view.status.SetText(" " this.CurrentKeybindStatusText(view.profileName), 2)
            ; Repaint the list, so rows follow the registration state.
            DllCall("InvalidateRect", "Ptr", view.list.Hwnd, "Ptr", 0, "Int", false)
            ; Suspended keybinds do nothing when pressed, so the title says so too.
            view.gui.Title := "PACS Assistant - " view.profileName (A_IsSuspended ? " (keybinds suspended)" : "")
            if A_IsSuspended
                view.menus["Tools"].Check(KeybindGUI.suspendMenuItem)
            else
                view.menus["Tools"].Uncheck(KeybindGUI.suspendMenuItem)
            ; Left-aligned: right-aligned text would sit under the size grip.
            view.status.SetText(" " AppVersion.current, 3)
            return true
        } catch Any as err {
            AppLog.Write("The main window could not be refreshed: " ErrorText.Describe(err))
            return false
        }
    }

    ; The keybind state of a profile (the current one by default) as the status
    ; bar and the Status window word it.
    CurrentKeybindStatusText(profileName := "") {
        profileName := profileName = "" ? ProfileManager.currentProfile : profileName
        configured := 0
        inactive := 0
        if ProfileManager.profiles.Has(profileName) {
            for funcName, bind in ProfileManager.profiles[profileName].binds {
                if (bind = "")
                    continue
                configured++
                if KeybindGUI.runtimeFailures.Has(funcName)
                    inactive++
            }
        }
        return KeybindGUI.KeybindStatusText(configured, inactive, A_IsSuspended)
    }

    ; The status bar's keybind state: how many of the set keybinds are live.
    static KeybindStatusText(configured, inactive, suspended) {
        if suspended
            return "Keybinds suspended"
        if (configured = 0)
            return "No keybinds set"
        noun := configured = 1 ? " keybind" : " keybinds"
        if (inactive = 0)
            return configured noun " active"
        return (configured - inactive) " of " configured noun " active"
    }

    ; Hover text for a function's row: what it does and, when its keybind is not
    ; registered, why.
    FunctionTip(funcName) {
        custom := 0
        if ProfileManager.profiles.Has(ProfileManager.currentProfile) {
            profile := ProfileManager.profiles[ProfileManager.currentProfile]
            if profile.customFuncs.Has(funcName)
                custom := profile.customFuncs[funcName]
        }
        text := CommandInfo.Describe(funcName, custom)
        if KeybindGUI.runtimeFailures.Has(funcName)
            text .= "`nNot active: " KeybindGUI.runtimeFailures[funcName]
        return text
    }

    ; LVN_GETINFOTIPW: fills the hover text of the row under the mouse.
    OnFunctionListInfoTip(listView, lParam) {
        ; NMLVGETINFOTIPW: pszText, cchTextMax and iItem after the NMHDR header.
        textOffset := A_PtrSize = 8 ? 32 : 16
        sizeOffset := A_PtrSize = 8 ? 40 : 20
        itemOffset := A_PtrSize = 8 ? 44 : 24
        try {
            capacity := NumGet(lParam, sizeOffset, "Int")
            text := this.FunctionTip(listView.GetText(NumGet(lParam, itemOffset, "Int") + 1, 1))
            if (capacity > 1)
                StrPut(SubStr(text, 1, capacity - 1), NumGet(lParam, textOffset, "Ptr"), "UTF-16")
        }
        return 0
    }

    ; The current profile's set keybinds, for the keybind card, in the main list's
    ; order and groups.
    KeybindCardRows() {
        rows := []
        if !ProfileManager.profiles.Has(ProfileManager.currentProfile)
            return rows
        profile := ProfileManager.profiles[ProfileManager.currentProfile]
        for funcName in KeybindGUI.FunctionDisplayOrder(profile.binds) {
            bind := profile.binds[funcName]
            if (bind = "")
                continue
            rows.Push({
                group: KeybindGUI.functionGroups[KeybindGUI.FunctionGroupId(funcName)].name,
                name: funcName,
                keybind: this.PrettifyHotkey(bind),
                activeIn: this.ScopeLabel(funcName)
            })
        }
        return rows
    }

    ; Tools > Status, also opened by double-clicking the status bar's keybind part.
    ShowStatus() => StatusPanel.Show(() => this.CurrentKeybindStatusText(), this.HasMainWindow() ? this.gui : 0)

    ; Help > Keybind Card: the profile's keys at a glance, to copy or print.
    ShowKeybindCard() {
        profileName := ProfileManager.currentProfile
        rows := this.KeybindCardRows()
        owner := this.HasMainWindow() ? "+Owner" this.gui.Hwnd : ""
        card := UITheme.NewWindow("PACS Assistant - Keybind Card", owner)
        width := 520
        UITheme.AddHeading(card, profileName " keybinds", "xm ym w" width)
        UITheme.AddNote(
            card,
            rows.Length ? "The keys set in this profile. Print a copy to keep beside the keyboard."
                : "No keybinds are set in this profile yet.",
            "xm y+4 w" width
        )
        list := card.Add("ListView", "xm y+12 w" width " r14 -Multi NoSortHdr +LV0x10000", ["Keybind", "Function", "Active In"])
        UITheme.UseExplorerTheme(list)
        KeybindGUI.EnableFunctionGroups(list)
        for row in rows {
            index := list.Add(, row.keybind, row.name, row.activeIn)
            KeybindGUI.SetRowGroup(list, index, KeybindGUI.FunctionGroupId(row.name))
        }
        UITheme.FillColumns(list, [130, 200])

        close := (*) => card.Destroy()
        footer := UITheme.AddFooter(
            card,
            width,
            [{text: "Close", default: true, action: close}],
            [
                {text: "Copy as &Text", width: 120, action: (*) => (
                    A_Clipboard := KeybindCard.Text(profileName, rows),
                    this.NotifyNonModal("The keybind card is on the clipboard.", "Keybind Card", "Iconi")
                )},
                {text: "Open &Printable Page", width: 160, action: (*) => this.OpenPrintableCard(profileName, rows, card)}
            ]
        )
        card.OnEvent("Close", close)
        card.OnEvent("Escape", close)
        UITheme.ShowDialog(card)
        footer["Close"].Focus()
        return card
    }

    OpenPrintableCard(profileName, rows, card) {
        try KeybindCard.OpenPrintable(profileName, rows)
        catch Any as err {
            AppLog.Write("The printable keybind card could not be opened: " ErrorText.Describe(err))
            card.Opt("+OwnDialogs")
            MsgBox("The printable page could not be opened.`n`n" ErrorText.Message(err), "Keybind Card", "Icon!")
        }
    }

    ; The line under the profile name.
    static ProfileSummary(isDefault, functionCount) {
        if (functionCount = 0)
            return "No functions yet. Click Add Function to bind your first command."
        text := functionCount (functionCount = 1 ? " function" : " functions")
        return isDefault ? text ", opens at startup" : text
    }

    ShowFunctionMenu(listView, row) {
        if !row
            return false
        commands := Menu()
        commands.Add("Set &Keybind...", (*) => this.ChangeSelectedKeybind(listView))
        commands.Add("Set S&cope...", (*) => this.ShowScopeDialog(listView))
        commands.Add()
        commands.Add("&Remove", (*) => this.RemoveFunction(listView))
        commands.Default := "Set &Keybind..."
        commands.Show()
        return true
    }

    ; Delete removes the selected function and F2 sets its keybind, like the
    ; matching buttons. Both run after the notification returns, so a confirmation
    ; or dialog never opens from inside the list's message handling.
    OnFunctionListKey(listView, lParam) {
        ; NMLVKEYDOWN: wVKey follows the NMHDR header.
        key := NumGet(lParam, 3 * A_PtrSize, "UShort")
        if !(key = 0x2E || key = 0x71) || !listView.GetNext(0)
            return
        if (key = 0x2E)
            SetTimer(() => this.RemoveFunction(listView), -1)
        else
            SetTimer(() => this.ChangeSelectedKeybind(listView), -1)
    }

    ; Brings the main window forward (from the tray), or the profile selector when
    ; no profile is open.
    ShowMainWindow() {
        if this.HasMainWindow() {
            hwnd := this.gui.Hwnd
            if !DllCall("IsWindowVisible", "Ptr", hwnd) {
                ; Hidden: started minimized to the tray, or closed to it.
                maximize := this.HasOwnProp("pendingMaximize") && this.pendingMaximize
                this.pendingMaximize := false
                this.gui.Show(maximize ? "Maximize" : "")
                try this.mainView.list.Focus()
            } else if (WinGetMinMax("ahk_id " hwnd) = -1)
                this.gui.Show("Restore")
            else
                this.gui.Show()
            return true
        }
        if this.ProfileSelectorIsCurrent(this.profileSelectorGui) {
            this.profileSelectorGui.Show()
            return true
        }
        return false
    }

    OpenDataFolder() {
        folder := AppStorage.DataRoot()
        try Run('explorer.exe "' folder '"')
        catch Any as err
            this.ShowNotice("The data folder could not be opened:`n" folder "`n`n" ErrorText.Message(err), "Data Folder Unavailable", "Icon!")
    }

    ShowAbout() {
        this.ShowNotice(
            "PACS Assistant " AppVersion.current
                . "`n`nKeybinds and automation for Vue PACS and PowerScribe."
                . "`n`nReleases and source: https://github.com/rakan959/pacs-assistant"
                . "`nLicense: GPL-3.0"
                . "`n`nSettings, profiles and error.log are kept in:`n" AppStorage.DataRoot(),
            "About PACS Assistant",
            "Iconi"
        )
    }

    OpenProfileSelector() {
        if !this.ProfileMutationAllowed("switch profiles")
            return false
        if !this.ResolveDirtyProfileBeforeLeaving()
            return false
        if !this.BeginProfileMutationTransaction("switch profiles")
            return false
        try {
            ; A selector has no active profile. Suspend the old profile before exposing
            ; any operation which can rename or delete it.
            this.PrepareForProfileSwitch()
            if this.HasMainWindow()
                this.gui.Destroy()
            this.gui := ""
            return this.ShowProfileSelector()
        } finally this.EndProfileMutationTransaction()
    }

    RequestExit() {
        if !this.BeginShutdown("close PACS Assistant")
            return false
        return this.CompleteShutdown()
    }

    BeginShutdown(action) {
        exemption := ExclusiveOperations.RestartExemption()
        if !this.OperationAllowed(action, exemption)
            return false

        if !ExclusiveOperations.TryBegin("shutdown", action, exemption*) {
            ; Another operation won the race since the check above; report it.
            this.OperationAllowed(action, exemption)
            return false
        }

        ; catch Any: whatever escapes, a held shutdown lease would block every
        ; clinical command until restart.
        try {
            if !this.ResolveDirtyProfileBeforeLeaving(false, true) {
                this.CancelShutdown()
                return false
            }
        } catch Any {
            this.CancelShutdown()
            throw
        }
        return true
    }

    CancelShutdown() {
        Critical("On")
        try {
            KeybindGUI.shutdownAuthorized := false
            ExclusiveOperations.End("shutdown")
        } finally Critical("Off")
    }

    CompleteShutdown() {
        if !ExclusiveOperations.shutdownActive
            return false
        KeybindGUI.shutdownAuthorized := true
        ExitApp()
        return true
    }

    HandleProcessExit(exitReason, exitCode) {
        if KeybindGUI.shutdownAuthorized
            return 0
        if !this.BeginShutdown("exit PACS Assistant")
            return 1
        KeybindGUI.shutdownAuthorized := true
        return 0
    }

    PrepareForProfileSwitch() {
        ; Destroying an owned key-capture dialog does not guarantee InputHook.Stop().
        ; Tear the hook down explicitly before its owner disappears, then suspend the
        ; old profile's runtime bindings while no profile is selected.
        this.StopListening()
        KeybindGUI.captureRuntimeProfile := 0
        HotkeyManager.DisableAllHotkeys()
    }

    HasMainWindow() {
        return this.GuiIsLive(this.gui)
    }

    GuiIsLive(targetGui) {
        if !IsObject(targetGui)
            return false
        ; WinExist follows DetectHiddenWindows and therefore reports a newly built,
        ; not-yet-shown Gui as absent. IsWindow proves the actual HWND lifetime for
        ; both pre-show validation and stale callback rejection after Destroy().
        try return targetGui.Hwnd > 0 && DllCall("IsWindow", "Ptr", targetGui.Hwnd)
        return false
    }

    NewProfileDialog(title, profileName := "", ownerGui := 0) {
        if (profileName = "")
            profileName := ProfileManager.currentProfile
        if !ownerGui && this.HasMainWindow()
            ownerGui := this.gui
        options := this.GuiIsLive(ownerGui) ? "+Owner" ownerGui.Hwnd : ""
        dialog := UITheme.NewWindow(title, options)
        dialog.profileName := profileName
        if (profileName != "" && ProfileManager.profiles.Has(profileName)) {
            ; Hold the exact object reference for the dialog's lifetime. Unlike a
            ; numeric revision, this cannot ABA-match a deleted/recreated profile of
            ; the same name because the retained object cannot be reused.
            dialog.profileObject := ProfileManager.profiles[profileName]
            dialog.profileStorageRevision := ProfileManager.GetProfileRevision(
                profileName
            )
            dialog.profileMutationSnapshot := KeybindGUI.GetProfileMutationRevision(
                profileName
            )
            dialog.ownerHwnd := this.GuiIsLive(ownerGui) ? ownerGui.Hwnd : 0
            dialog.requiresLiveProfileIdentity := true
        }
        return dialog
    }

    DialogProfileIsCurrent(dialog) {
        profileName := ""
        try profileName := dialog.profileName
        strongIdentityValid := true
        if HasProp(dialog, "requiresLiveProfileIdentity") {
            try strongIdentityValid := this.GuiIsLive(dialog)
                && (!dialog.ownerHwnd
                    || DllCall("IsWindow", "Ptr", dialog.ownerHwnd))
                && HasProp(dialog, "profileObject")
                && ProfileManager.profiles.Has(profileName)
                && ProfileManager.profiles[profileName] == dialog.profileObject
                && dialog.profileStorageRevision
                    = ProfileManager.GetProfileRevision(profileName)
                && dialog.profileMutationSnapshot
                    = KeybindGUI.GetProfileMutationRevision(profileName)
            catch
                strongIdentityValid := false
        }
        if (strongIdentityValid
            && profileName != ""
            && profileName = ProfileManager.currentProfile
            && ProfileManager.profiles.Has(profileName))
            return true

        ; An owned dialog normally disappears with its main window. This explicit
        ; identity gate is the data-integrity backstop for queued callbacks or any
        ; dialog that outlives a profile switch.
        message := "The active profile changed while this dialog was open. Reopen it before saving changes."
        if ExclusiveOperations.captureActive
            return this.AbortStaleCapture(dialog, message, "Profile Changed")
        try dialog.Destroy()
        this.NotifyUser(message, "Profile Changed", "Icon!")
        return false
    }

    FindUniqueFunctionRow(listView, funcName) {
        match := 0
        try rowCount := listView.GetCount()
        catch
            return 0
        loop rowCount {
            try rowName := listView.GetText(A_Index, 1)
            catch
                return 0
            if (rowName == funcName) {
                if match
                    return 0
                match := A_Index
            }
        }
        return match
    }

    CaptureFunctionDialogState(dialog, funcName, listView, rowIndex := 0) {
        if !this.DialogProfileIsCurrent(dialog)
            return false
        profile := ProfileManager.profiles[dialog.profileName]
        if !profile.binds.Has(funcName)
            return false
        if !rowIndex
            rowIndex := this.FindUniqueFunctionRow(listView, funcName)
        if !rowIndex
            return false

        try {
            if !(listView.GetText(rowIndex, 1) == funcName)
                return false
            dialog.functionName := funcName
            dialog.expectedBind := profile.binds[funcName]
            dialog.expectedScope := profile.scopes.Has(funcName)
                ? profile.scopes[funcName]
                : "Any"
            dialog.functionRow := rowIndex
            dialog.expectedRowBind := listView.GetText(rowIndex, 2)
            dialog.expectedRowScope := listView.GetText(rowIndex, 3)
            return true
        } catch {
            return false
        }
    }

    FunctionDialogIsCurrent(dialog, funcName, listView) {
        if !this.DialogProfileIsCurrent(dialog)
            return false

        valid := false
        try {
            profile := ProfileManager.profiles[dialog.profileName]
            currentScope := profile.scopes.Has(funcName)
                ? profile.scopes[funcName]
                : "Any"
            valid := HasProp(dialog, "functionName")
                && dialog.functionName == funcName
                && HasProp(dialog, "expectedBind")
                && profile.binds.Has(funcName)
                && profile.binds[funcName] == dialog.expectedBind
                && HasProp(dialog, "expectedScope")
                && currentScope == dialog.expectedScope
                && HasProp(dialog, "functionRow")
                && dialog.functionRow > 0
                && listView.GetText(dialog.functionRow, 1) == funcName
                && listView.GetText(dialog.functionRow, 2) == dialog.expectedRowBind
                && listView.GetText(dialog.functionRow, 3) == dialog.expectedRowScope
        }
        if valid
            return true

        if ExclusiveOperations.captureActive {
            return this.AbortStaleCapture(
                dialog,
                "The selected function changed while this dialog was open. Reopen it before applying changes.",
                "Function Changed"
            )
        }
        message := "The selected function changed while this dialog was open. Reopen it before applying changes."
        ; A scope dialog never suspends runtime bindings; capture recovery is
        ; handled above while its lease is held.
        this.NotifyUser(message, "Function Changed", "Icon!")
        try dialog.Destroy()
        return false
    }

    ShowProfileSelector() {
        if this.ProfileSelectorIsCurrent(this.profileSelectorGui) {
            try WinActivate("ahk_id " this.profileSelectorGui.Hwnd)
            return this.profileSelectorGui
        }
        selectorGui := UITheme.NewWindow("PACS Assistant - Profile Selection")
        listWidth := 280
        buttonWidth := 136
        contentWidth := listWidth + 12 + buttonWidth
        UITheme.AddHeading(selectorGui, "Choose a profile", "xm ym w" contentWidth)
        UITheme.AddNote(
            selectorGui,
            "Each profile keeps its own keybinds and modality attendings.",
            "xm y+4 w" contentWidth
        )

        profileNames := []
        for name, _ in ProfileManager.profiles
            profileNames.Push(name)
        ; -Hdr: a plain list of names, with the default profile labelled beside its name.
        lv := selectorGui.Add("ListView", "xm y+14 w" listWidth " h244 -Multi -Hdr +LV0x10000", ["Profile", "Default"])
        UITheme.UseExplorerTheme(lv)
        for name in profileNames
            lv.Add(, name, name = ProfileManager.defaultProfile ? "Default" : "")
        lv.ModifyCol(1, listWidth - 80)
        lv.ModifyCol(2, "AutoHdr")

        ; Start on the profile that was open, else the default one, else the first.
        preferred := this.ProfileListIndex(profileNames, ProfileManager.currentProfile)
        if !preferred
            preferred := this.ProfileListIndex(profileNames, ProfileManager.defaultProfile)
        if (!preferred && profileNames.Length)
            preferred := 1
        if preferred
            lv.Modify(preferred, "Select Focus Vis")

        selected := () => this.SelectedProfileName(lv)
        lv.GetPos(&listX, &listY)
        buttonX := listX + listWidth + 12
        buttons := {}
        buttons.open := selectorGui.Add("Button", "x" buttonX " y" listY " w" buttonWidth " h" UITheme.buttonHeight " Default", "&Open")
        buttons.open.OnEvent("Click", (*) => this.SelectProfile(selected(), selectorGui))
        newButton := selectorGui.Add("Button", "x" buttonX " y+" UITheme.gap " w" buttonWidth " h" UITheme.buttonHeight, "&New Profile...")
        newButton.OnEvent("Click", (*) => this.OpenNewProfilePrompt(selectorGui))
        buttons.duplicate := selectorGui.Add("Button", "x" buttonX " y+" UITheme.gap " w" buttonWidth " h" UITheme.buttonHeight, "D&uplicate...")
        buttons.duplicate.OnEvent("Click", (*) => this.DuplicateSelectedProfile(selected(), selectorGui))
        buttons.rename := selectorGui.Add("Button", "x" buttonX " y+" UITheme.gap " w" buttonWidth " h" UITheme.buttonHeight, "&Rename...")
        buttons.rename.OnEvent("Click", (*) => this.PromptRenameProfile(selected(), selectorGui))
        buttons.setDefault := selectorGui.Add("Button", "x" buttonX " y+" UITheme.gap " w" buttonWidth " h" UITheme.buttonHeight, "Set as &Default")
        buttons.setDefault.OnEvent("Click", (*) => this.SetDefaultProfile(selected(), selectorGui))
        buttons.delete := selectorGui.Add("Button", "x" buttonX " y+" UITheme.sectionGap " w" buttonWidth " h" UITheme.buttonHeight, "De&lete...")
        buttons.delete.OnEvent("Click", (*) => this.DeleteProfile(selected(), selectorGui))

        lv.OnEvent("ItemSelect", (*) => this.RefreshProfileSelectorButtons(lv, buttons))
        lv.OnEvent("DoubleClick", (ctrl, row) => row ? this.SelectProfile(selected(), selectorGui) : 0)
        this.RefreshProfileSelectorButtons(lv, buttons)
        selectorGui.contentWidth := contentWidth

        ; Return true so a refused close keeps the selector visible (see CreateMainGUI).
        selectorGui.OnEvent("Close", (*) => (this.CloseProfileSelector(selectorGui), true))
        this.RegisterProfileSelector(selectorGui)
        try UITheme.ShowDialog(selectorGui)
        catch Any as err {
            this.RetireProfileSelector(selectorGui)
            throw err
        }
        return selectorGui
    }

    RegisterProfileSelector(selectorGui) {
        if !IsObject(selectorGui)
            throw TypeError("Profile selector must be a GUI object")
        this.profileSelectorGui := selectorGui
        return selectorGui
    }

    ProfileSelectorIsCurrent(selectorGui) {
        return IsObject(selectorGui)
            && IsObject(this.profileSelectorGui)
            && ObjPtr(selectorGui) = ObjPtr(this.profileSelectorGui)
            && this.GuiIsLive(selectorGui)
    }

    RequireCurrentProfileSelector(selectorGui) {
        if this.ProfileSelectorIsCurrent(selectorGui)
            return true
        this.NotifyNonModal(
            "The profile selector changed or closed before that action ran. Reopen it and try again.",
            "Profile Selector Changed",
            "Icon!"
        )
        return false
    }

    RetireProfileSelector(selectorGui) {
        if (IsObject(this.profileSelectorGui)
            && IsObject(selectorGui)
            && ObjPtr(this.profileSelectorGui) = ObjPtr(selectorGui))
            this.profileSelectorGui := 0
        try selectorGui.Destroy()
    }

    ; Position of exactly this name in the selector's list, or 0.
    ProfileListIndex(profileNames, profileName) {
        if (profileName = "")
            return 0
        for index, name in profileNames {
            if (name == profileName)
                return index
        }
        return 0
    }

    SelectedProfileName(listView) {
        row := listView.GetNext(0)
        return row ? listView.GetText(row, 1) : ""
    }

    ; Buttons that act on a profile need one selected; Set as Default also needs it
    ; not to be the default already.
    RefreshProfileSelectorButtons(listView, buttons) {
        name := this.SelectedProfileName(listView)
        buttons.open.Enabled := name != ""
        buttons.duplicate.Enabled := name != ""
        buttons.rename.Enabled := name != ""
        buttons.delete.Enabled := name != ""
        buttons.setDefault.Enabled := name != "" && name != ProfileManager.defaultProfile
    }

    CloseProfileSelector(selectorGui) {
        if !this.RequireCurrentProfileSelector(selectorGui)
            return false
        if !this.BeginProfileMutationTransaction("close the profile selector")
            return false
        try {
            if !this.RequireCurrentProfileSelector(selectorGui)
                return false
            this.RetireProfileSelector(selectorGui)
            if this.HasMainWindow()
                return true
            if (ProfileManager.currentProfile != "" && ProfileManager.profiles.Has(ProfileManager.currentProfile)) {
                this.CreateMainGUI()
                return true
            }
        } finally this.EndProfileMutationTransaction()
        return this.RequestExit()
    }

    OpenNewProfilePrompt(selectorGui) {
        if !this.RequireCurrentProfileSelector(selectorGui)
            return false
        if !this.BeginProfileMutationTransaction("open the new-profile dialog")
            return false
        try {
            if !this.RequireCurrentProfileSelector(selectorGui)
                return false
            this.RetireProfileSelector(selectorGui)
            return this.PromptNewProfile()
        } finally this.EndProfileMutationTransaction()
    }

    PromptNewProfile() {
        inputGui := UITheme.NewWindow("PACS Assistant - Create New Profile")
        width := 320
        ; With no profile to return to, closing this prompt exits the app.
        firstProfile := ProfileManager.profiles.Count = 0
        UITheme.AddHeading(inputGui, firstProfile ? "Create your first profile" : "Create a profile", "xm ym w" width)
        ; Two lines tall: Import replaces it with the file it will create from.
        inputGui.importNote := UITheme.AddNote(
            inputGui,
            "A profile is a set of keybinds and modality attendings, such as one per rotation or shift.",
            "xm y+4 w" width " r2"
        )
        inputGui.Add("Text", "xm y+14 w" width, "Profile &name")
        nameEdit := inputGui.Add("Edit", "xm y+4 r1 w" width)
        UITheme.SetPlaceholder(nameEdit, "For example, Neuro or Night Float")
        close := (*) => (this.CloseNewProfilePrompt(inputGui), true)
        UITheme.AddFooter(
            inputGui,
            width,
            [
                {text: "Create", action: (*) => this.CreateProfile(nameEdit.Value, inputGui), default: true},
                {text: firstProfile ? "Exit" : "Cancel", action: close}
            ],
            [{text: "&Import...", action: (*) => this.ChooseImportForNewProfile(inputGui, nameEdit)}]
        )
        ; Return true so a refused close keeps the prompt visible (see CreateMainGUI).
        inputGui.OnEvent("Close", close)
        if !firstProfile
            inputGui.OnEvent("Escape", close)
        UITheme.ShowDialog(inputGui)
        return inputGui
    }

    CloseNewProfilePrompt(inputGui) {
        if !this.GuiIsLive(inputGui)
            return false
        if !this.BeginProfileMutationTransaction("close the new-profile dialog")
            return false
        try {
            if !this.GuiIsLive(inputGui)
                return false
            try inputGui.Destroy()
            if (ProfileManager.profiles.Count > 0) {
                this.ShowProfileSelector()
                return true
            }
        } finally this.EndProfileMutationTransaction()
        return this.RequestExit()
    }

    CreateProfile(name, inputGui) {
        name := Trim(name)
        if !this.GuiIsLive(inputGui)
            return false
        if !this.BeginProfileMutationTransaction("create a profile")
            return false
        inputDisabled := false
        try {
            if !this.GuiIsLive(inputGui)
                return false
            try {
                inputGui.Opt("+Disabled")
                inputDisabled := true
            } catch {
                this.NotifyUser(
                    "The new-profile dialog could not be locked for this change. Reopen it and try again.",
                    "Profile Creation Failed",
                    "Icon!"
                )
                return false
            }
            if !this.GuiIsLive(inputGui)
                return false
            created := HasProp(inputGui, "importSource")
                ? ProfileManager.CreateProfile(name, inputGui.importSource)
                : this.CreateProfileRecord(name)
            if created {
                ProfileManager.currentProfile := name
                inputGui.Destroy()
                this.CreateMainGUI()
                return true
            }
            this.NotifyUser(
                this.ProfileStorageFailureText(
                    "Enter a unique profile name without file-system characters or reserved Windows device names."
                ),
                ProfileManager.lastError != "" ? "Profile Creation Failed" : "Invalid Profile Name",
                "Icon!"
            )
            return false
        } finally {
            if inputDisabled
                try inputGui.Opt("-Disabled")
            this.EndProfileMutationTransaction()
        }
    }

    CreateProfileRecord(name) => ProfileManager.CreateProfile(name)

    ; The new-profile prompt's Import: reads a profile file, then Create makes the
    ; new profile from it under the name in the box, which starts as the file's.
    ChooseImportForNewProfile(inputGui, nameEdit) {
        chosen := this.ChooseProfileFile(inputGui)
        if !chosen
            return false
        inputGui.importSource := chosen.source
        nameEdit.Value := chosen.name
        inputGui.importNote.Value := "Create adds the keybinds and modality attendings in " chosen.fileName "."
        return true
    }

    ; A name for a new profile based on base: base itself when free, else base 2,
    ; base 3 and so on. Names are compared as Windows compares file names.
    UniqueProfileName(base) {
        base := Trim(base)
        if !ProfileManager.IsValidProfileName(base)
            base := "New profile"
        candidate := base
        suffix := 2
        while this.ProfileNameTaken(candidate)
            candidate := base " " suffix++
        return candidate
    }

    ProfileNameTaken(name) {
        for existing, _ in ProfileManager.profiles {
            if (existing = name)
                return true
        }
        return !!FileExist(ProfileManager.ProfilePath(name))
    }

    /**
     * Asks for the name of a new profile made from source (a copy of a profile, or
     * one read from a file), and creates it on Create. parentGui is the profile
     * selector when it was asked from there.
     */
    PromptProfileCopy(title, heading, note, source, suggestedName, parentGui := 0) {
        owner := parentGui ? parentGui : (this.HasMainWindow() ? this.gui : 0)
        dialog := UITheme.NewWindow(title, this.GuiIsLive(owner) ? "+Owner" owner.Hwnd : "")
        width := 340
        UITheme.AddHeading(dialog, heading, "xm ym w" width)
        UITheme.AddNote(dialog, note, "xm y+4 w" width)
        dialog.Add("Text", "xm y+14 w" width, "&Name for the new profile")
        nameEdit := dialog.Add("Edit", "xm y+4 r1 w" width, suggestedName)
        cancel := (*) => dialog.Destroy()
        UITheme.AddFooter(dialog, width, [
            {text: "Create", default: true, action: (*) => this.CreateProfileCopy(nameEdit.Value, source, dialog, parentGui)},
            {text: "Cancel", action: cancel}
        ])
        dialog.OnEvent("Close", cancel)
        dialog.OnEvent("Escape", cancel)
        UITheme.ShowDialog(dialog)
        return dialog
    }

    CreateProfileCopy(name, source, dialog, parentGui := 0) {
        name := Trim(name)
        if !this.GuiIsLive(dialog)
            return false
        if (parentGui && !this.RequireCurrentProfileSelector(parentGui)) {
            try dialog.Destroy()
            return false
        }
        if !this.BeginProfileMutationTransaction("create a profile")
            return false
        try {
            if !ProfileManager.CreateProfile(name, source) {
                this.NotifyUser(
                    this.ProfileStorageFailureText(
                        "Enter a unique profile name without file-system characters or reserved Windows device names."
                    ),
                    ProfileManager.lastError != "" ? "Profile Not Created" : "Invalid Profile Name",
                    "Icon!"
                )
                return false
            }
            dialog.Destroy()
            if parentGui {
                this.RetireProfileSelector(parentGui)
                this.ShowProfileSelector()
            } else {
                this.NotifyNonModal("'" name "' was created. Open it with Switch Profile.", "Profile Created", "Iconi")
            }
            return true
        } finally this.EndProfileMutationTransaction()
    }

    ; Profile > Duplicate Profile: copies the current profile as it is shown,
    ; unsaved changes included.
    DuplicateCurrentProfile() {
        name := ProfileManager.currentProfile
        if !ProfileManager.profiles.Has(name)
            return false
        return this.PromptProfileCopy(
            "PACS Assistant - Duplicate Profile",
            "Duplicate profile",
            "A new profile with the keybinds and modality attendings of '" name "'.",
            ProfileManager.CloneProfile(ProfileManager.profiles[name]),
            this.UniqueProfileName(name " copy")
        )
    }

    DuplicateSelectedProfile(name, selectorGui) {
        if !this.RequireCurrentProfileSelector(selectorGui)
            return false
        if (name = "" || !ProfileManager.profiles.Has(name)) {
            MsgBox("Please select a profile first.", "No Profile Selected", "Icon!")
            return false
        }
        return this.PromptProfileCopy(
            "PACS Assistant - Duplicate Profile",
            "Duplicate profile",
            "A new profile with the keybinds and modality attendings of '" name "'.",
            ProfileManager.CloneProfile(ProfileManager.profiles[name]),
            this.UniqueProfileName(name " copy"),
            selectorGui
        )
    }

    /**
     * Reads a profile file chosen by the user. The file must load and validate as
     * a profile; nothing is created until its new name is confirmed.
     * @returns {source, name} with a free name based on the file's, or 0
     */
    ChooseProfileFile(ownerGui := 0) {
        if this.GuiIsLive(ownerGui)
            ownerGui.Opt("+OwnDialogs")
        path := FileSelect(3, A_MyDocuments, "Import Profile", "PACS Assistant profiles (*.ini)")
        if (path = "")
            return 0
        try source := ProfileManager.LoadProfile(path)
        catch Any as err {
            this.ShowNotice(
                "This file is not a PACS Assistant profile, so nothing was imported.`n`n" ErrorText.Message(err),
                "Profile Not Imported",
                "Icon!"
            )
            return 0
        }
        SplitPath(path,,,, &stem)
        return {source: source, name: this.UniqueProfileName(stem), fileName: stem ".ini"}
    }

    ; Profile > Import Profile.
    ImportProfile() {
        chosen := this.ChooseProfileFile(this.HasMainWindow() ? this.gui : 0)
        if !chosen
            return false
        return this.PromptProfileCopy(
            "PACS Assistant - Import Profile",
            "Import profile",
            "A new profile with the keybinds and modality attendings in " chosen.fileName ".",
            chosen.source,
            chosen.name
        )
    }

    ; Profile > Export Profile: copies the saved profile file. Unsaved changes are
    ; saved or discarded first, so the file has what the window shows.
    ExportCurrentProfile() {
        name := ProfileManager.currentProfile
        if !this.ResolveDirtyProfileBeforeLeaving(true)
            return false
        if this.HasMainWindow()
            this.gui.Opt("+OwnDialogs")
        path := FileSelect("S16", A_MyDocuments "\" name ".ini", "Export Profile", "PACS Assistant profiles (*.ini)")
        if (path = "")
            return false
        if !RegExMatch(path, "i)\.ini$")
            path .= ".ini"
        try FileCopy(ProfileManager.ProfilePath(name), path, true)
        catch Any as err {
            AppLog.Write("Profile '" name "' could not be exported: " ErrorText.Describe(err))
            this.ShowNotice("The profile could not be exported.`n`n" ErrorText.Message(err), "Export Failed", "Icon!")
            return false
        }
        this.NotifyNonModal("'" name "' was exported to " path ".", "Profile Exported", "Iconi")
        return true
    }

    SelectProfile(name, selectorGui) {
        if !this.RequireCurrentProfileSelector(selectorGui)
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "No Profile Selected", "Icon!")
            return false
        }
        if !ProfileManager.profiles.Has(name)
            return false
        if !this.BeginProfileMutationTransaction("select a profile")
            return false
        try {
            if !this.RequireCurrentProfileSelector(selectorGui)
                return false
            ProfileManager.currentProfile := name
            this.RetireProfileSelector(selectorGui)
            this.CreateMainGUI()
            return true
        } finally this.EndProfileMutationTransaction()
    }

    SetDefaultProfile(name, selectorGui) {
        if !this.RequireCurrentProfileSelector(selectorGui)
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "No Profile Selected", "Icon!")
            return false
        }

        if !this.BeginProfileMutationTransaction("change the default profile")
            return false
        selectorDisabled := false
        try {
            if !this.RequireCurrentProfileSelector(selectorGui)
                return false
            try {
                selectorGui.Opt("+Disabled")
                selectorDisabled := true
            } catch {
                this.NotifyUser(
                    "The profile selector could not be locked for this change. Reopen it and try again.",
                    "Profile Update Failed",
                    "Icon!"
                )
                return false
            }
            if (ProfileManager.SetDefaultProfile(name)) {
                this.RetireProfileSelector(selectorGui)
                this.ShowProfileSelector()  ; Refresh the selector to show updated default
                return true
            }
            this.NotifyUser(
                this.ProfileStorageFailureText("Failed to set default profile."),
                "Profile Update Failed",
                "Icon!"
            )
            return false
        } finally {
            if selectorDisabled
                try selectorGui.Opt("-Disabled")
            this.EndProfileMutationTransaction()
        }
    }

    DeleteProfile(name, selectorGui) {
        if !this.RequireCurrentProfileSelector(selectorGui)
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "No Profile Selected", "Icon!")
            return false
        }

        ; The confirmation does not hold the profile lease, so a dialog left open does
        ; not block clinical commands or monitoring. The selector is disabled while it
        ; is open, and the deletion is revalidated under the lease after the answer.
        if !this.ProfileMutationAllowed("delete a profile")
            return false
        selectorDisabled := false
        leaseHeld := false
        try {
            try {
                selectorGui.Opt("+Disabled")
                selectorDisabled := true
            } catch {
                this.NotifyUser(
                    "The profile selector could not be locked for deletion. Reopen it and try again.",
                    "Profile Delete Failed",
                    "Icon!"
                )
                return false
            }
            deletionState := this.CaptureProfileDeletionState(name)
            if !deletionState {
                this.NotifyUser(
                    "The selected profile is no longer available.",
                    "Profile Changed",
                    "Icon!"
                )
                return false
            }
            if !this.ConfirmDestructiveAction(
                "Are you sure you want to delete profile '" name "'?",
                "Confirm Delete"
            )
                return false
            if !this.BeginProfileMutationTransaction("delete a profile")
                return false
            leaseHeld := true
            if (!this.RequireCurrentProfileSelector(selectorGui)
                || !this.ProfileDeletionStateIsCurrent(deletionState)) {
                this.NotifyUser(
                    "The selected profile changed while confirmation was open. Reopen the profile selector before deleting it.",
                    "Profile Changed",
                    "Icon!"
                )
                return false
            }
            if (ProfileManager.DeleteProfile(name)) {
                if (name = ProfileManager.currentProfile) {
                    ; If we deleted the current profile, switch to another one
                    for newName, _ in ProfileManager.profiles {
                        if (newName != name) {
                            ProfileManager.currentProfile := newName
                            break
                        }
                    }
                }
                this.RetireProfileSelector(selectorGui)
                this.ShowProfileSelector()  ; Refresh the selector
                return true
            }
            this.NotifyUser(
                this.ProfileStorageFailureText("Cannot delete the last remaining profile."),
                "Profile Delete Failed",
                "Icon!"
            )
        } finally {
            if (selectorDisabled && this.ProfileSelectorIsCurrent(selectorGui))
                try selectorGui.Opt("-Disabled")
            if leaseHeld
                this.EndProfileMutationTransaction()
        }
        return false
    }

    CaptureProfileDeletionState(name) {
        if (!ProfileManager.profiles.Has(name)
            || !ProfileManager.IsValidProfileName(name))
            return 0
        profile := ProfileManager.profiles[name]
        return {
            name: name,
            profilePointer: ObjPtr(profile),
            revision: ProfileManager.GetProfileRevision(name),
            profileCount: ProfileManager.profiles.Count,
            currentProfile: ProfileManager.currentProfile,
            defaultProfile: ProfileManager.defaultProfile
        }
    }

    ProfileDeletionStateIsCurrent(state) {
        if (!state
            || !ProfileManager.profiles.Has(state.name)
            || ProfileManager.profiles.Count != state.profileCount
            || ProfileManager.GetProfileRevision(state.name) != state.revision
            || !(ProfileManager.currentProfile == state.currentProfile)
            || !(ProfileManager.defaultProfile == state.defaultProfile))
            return false
        return ObjPtr(ProfileManager.profiles[state.name]) = state.profilePointer
    }

    /**
     * Takes ownership of key capture. Only one capture can be in flight at a time.
     * @returns true if capture started
     */
    BeginListening(funcName, control, promptGui) {
        if !this.BeginCaptureTransaction("start key capture")
            return false

        ; The dialog snapshot was captured before acquisition. Revalidate it while the
        ; capture lease excludes every profile mutation and clinical callback.
        if !this.FunctionDialogIsCurrent(promptGui, funcName, control)
            return false

        ; Capture the runtime contract before disabling anything. A failed hook start
        ; must either restore this exact set or visibly require an application restart.
        try originalProfile := ProfileManager.CloneProfile(
                ProfileManager.profiles[ProfileManager.currentProfile]
            )
        catch Any as err {
            this.ReleaseCaptureTransaction()
            throw err
        }
        KeybindGUI.captureRuntimeProfile := originalProfile

        KeybindGUI.isListening := true
        try {
            ; The key the user presses to define a bind must be captured as data only.
            ; Leaving live clinical hotkeys registered here could execute that same key
            ; (including Draft/Sign) while it is being selected.
            HotkeyManager.DisableAllHotkeys()
            this.StartInputHook(funcName, control, promptGui)
        }
        catch as err {
            stopError := ""
            try this.StopListening()
            catch as cleanupError
                stopError := cleanupError.Message

            restored := false
            if (stopError != "") {
                this.NotifyUser(
                    "Input capture failed to start, and its hook could not be safely stopped: " stopError
                        . ". Restart PACS Assistant before using its shortcuts.",
                    "Capture Recovery Failed",
                    "Icon!"
                )
            } else {
                restored := this.RestoreCapturedRuntimeAndNotify(
                    originalProfile,
                    "Input capture failed to start. No keybind was changed.",
                    "Capture Recovery Failed",
                    false
                )
            }
            if restored
                this.ReleaseCaptureTransaction()
            throw err
        }
        return true
    }

    ; Creates the capture hook and records it so it can always be torn down again
    StartInputHook(funcName, control, promptGui) {
        ih := InputHook(KeybindGUI.inputHookOptions)
        ih.KeyOpt("{All}", "E")
        ih.OnEnd := this.OnInputEnd.Bind(this, funcName, control, promptGui)
        KeybindGUI.activeInputHook := ih
        ih.Start()
    }

    ; Duplicate detection has to use the same identity as runtime registration and
    ; profile validation. InputHook reports letters with canonical casing, while an
    ; older profile may contain the same bind in lower case.
    FindProfileBindingOwner(profile, hotkeyStr, exceptFuncName := "") {
        identity := HotkeyContract.BindingIdentity(hotkeyStr)
        for funcName, bind in profile.binds {
            if (funcName != exceptFuncName
                && HotkeyContract.BindingIdentity(bind) = identity)
                return funcName
        }
        return ""
    }

    OnInputEnd(funcName, control, promptGui, ih) {
        ; Stop(), timeout, and replacement by another InputHook all raise OnEnd too.
        ; Only a real end key is input to bind: a stopped hook's EndKey is blank and
        ; must not unassign the command.
        if (ih.EndReason != "EndKey")
            return false

        if !this.FunctionDialogIsCurrent(promptGui, funcName, control)
            return false

        key := ih.EndKey

        ; Handle Escape to cancel
        if (key = "Escape") {
            this.CancelKeybindPrompt(promptGui)
            return false
        }

        ; Skip if the key is just a modifier
        if key ~= "^[LR]?(Control|Alt|Shift|Win)$" {
            ; Create and start a new input hook since the old one is ended
            try this.StartInputHook(funcName, control, promptGui)
            catch Any as err {
                this.CancelKeybindPrompt(promptGui)
                throw err
            }
            return false
        }

        newBind := this.CapturedHotkey(ih)
        ; The key-capture window shows the key and any warning about it, and binds
        ; it only on Use Keybind. A caller without that window binds it at once.
        if HasProp(promptGui, "showCapturedKey")
            return promptGui.showCapturedKey.Call(newBind)
        return this.CommitCapturedKey(funcName, control, promptGui, newBind)
    }

    /**
     * Binds a captured key to the function: refuses a key another function has,
     * then applies the profile and keeps the change only if the key registers.
     * Ends the capture either way.
     */
    CommitCapturedKey(funcName, control, promptGui, newBind) {
        currentProfile := ProfileManager.profiles[promptGui.profileName]
        hadBinding := currentProfile.binds.Has(funcName)
        oldBind := hadBinding ? currentProfile.binds[funcName] : ""
        bindingChanged := false
        modifiedRow := 0

        try {
            ; Check if this hotkey is already assigned to another function
            owner := this.FindProfileBindingOwner(currentProfile, newBind, funcName)
            if owner {
                MsgBox("This hotkey is already assigned to '" owner "'", "Duplicate Binding", "Icon!")
                this.CancelKeybindPrompt(promptGui)
                return false
            }

            ; Update profile
            currentProfile.binds[funcName] := newBind
            bindingChanged := true

            ; Find and update the ListView row before destroying the prompt
            loop control.GetCount() {
                if (control.GetText(A_Index, 1) = funcName) {
                    control.Modify(A_Index,, funcName, this.PrettifyHotkey(newBind))
                    modifiedRow := A_Index
                    break
                }
            }
            this.ResizeColumns(control)
            this.StopListening()
            promptGui.Destroy()

            ; Reapply all binds. A key that cannot register is left out of an apply
            ; (ApplyProfileBinds), so a new one must also be checked to be live.
            if (!this.ApplyBinds()
                || newBind != "" && !HotkeyManager.activeHotkeys.Has(funcName)) {
                if hadBinding
                    currentProfile.binds[funcName] := oldBind
                else
                    currentProfile.binds.Delete(funcName)
                if modifiedRow
                    control.Modify(modifiedRow,, funcName, this.PrettifyHotkey(oldBind))
                ; The failed candidate has already been reported. Restore the prior
                ; runtime set quietly when possible, but surface uncertainty when
                ; native teardown/re-registration cannot prove that restoration.
                restored := this.RestoreCapturedRuntimeAndNotify(
                    currentProfile,
                    "The new keybind was rejected and the previous profile value was retained.",
                    "Keybind Recovery Failed",
                    false
                )
                if restored
                    this.ReleaseCaptureTransaction()
                return false
            }
            KeybindGUI.captureRuntimeProfile := 0
            this.MarkProfileDirty(promptGui.profileName)
            ; Dirty publication must precede re-enabling the owner: a queued
            ; Close/Switch callback must observe the Save/Discard/Cancel gate.
            this.ReleaseCaptureTransaction()
            return true
        } catch as err {
            if bindingChanged {
                if hadBinding
                    currentProfile.binds[funcName] := oldBind
                else
                    currentProfile.binds.Delete(funcName)
            }
            if modifiedRow
                try control.Modify(modifiedRow,, funcName, this.PrettifyHotkey(oldBind))
            try this.StopListening()
            catch as stopError {
                ; The hook may still be live. Do not restore, destroy, or release the
                ; capture boundary: any of those would publish an unprovable state.
                this.NotifyUser(
                    "The keybind change failed, and input capture could not be stopped. Keep this dialog open and restart PACS Assistant before relying on its shortcuts."
                        . "`n`nOriginal error: " err.Message
                        . "`n`nCapture stop error: " stopError.Message,
                    "Capture Recovery Failed - Restart Required",
                    "Icon!"
                )
                throw err
            }
            try promptGui.Destroy()
            ; Preserve the original control/apply exception, but never hide an
            ; uncertain live shortcut state behind the restored profile value.
            restored := this.RestoreCapturedRuntimeAndNotify(
                currentProfile,
                "The keybind change failed and the previous profile value was retained.",
                "Keybind Recovery Failed",
                false
            )
            if restored
                this.ReleaseCaptureTransaction()
            throw err
        }
    }

    /**
     * Ends key capture and tears down the hook.
     *
     * Stopping the hook is the important part: a hook left running after its dialog
     * closes would capture the next key pressed anywhere and rebind whichever
     * function had been open.
     */
    StopListening() {
        if KeybindGUI.activeInputHook {
            try {
                KeybindGUI.activeInputHook.Stop()
            } catch as err {
                ; Preserve the live hook and listening state so callers cannot tear
                ; down its profile/dialog while it may still capture the next key.
                ; Only a restart ends it now.
                this.RequireCaptureRestart()
                AppLog.Write("Key capture could not be stopped: " ErrorText.Describe(err))
                throw Error("Input capture could not be stopped: " err.Message)
            }
            KeybindGUI.activeInputHook := 0
        }
        KeybindGUI.isListening := false
        return true
    }

    CapturedHotkey(ih) {
        ; EndMods is the capture-time snapshot. GetKeyState races the user releasing a
        ; modifier between the terminating key event and this callback.
        modifiers := ""
        modifiers .= InStr(ih.EndMods, "^") ? "^" : ""
        modifiers .= InStr(ih.EndMods, "!") ? "!" : ""
        modifiers .= InStr(ih.EndMods, "+") ? "+" : ""
        modifiers .= InStr(ih.EndMods, "#") ? "#" : ""
        return modifiers ih.EndKey
    }

    CancelKeybindPrompt(promptGui) {
        try this.StopListening()
        catch as err {
            ; The hook may still be live. Retain the capture snapshot, dialog, and
            ; listening state. RequireCaptureRestart re-enables the owner for exit,
            ; while the capture lease continues to refuse unsafe profile changes.
            this.NotifyUser(
                "Key capture could not be stopped and may still be active. Keep this dialog open and restart PACS Assistant before relying on its shortcuts.`n`n" err.Message,
                "Capture Stop Failed - Restart Required",
                "Icon!"
            )
            return false
        }
        fallbackProfile := ProfileManager.CloneProfile(
            ProfileManager.profiles[ProfileManager.currentProfile]
        )
        restored := this.RestoreCapturedRuntimeAndNotify(
            fallbackProfile,
            "Key capture was cancelled. No keybind was changed.",
            "Capture Recovery Failed",
            false
        )
        try promptGui.Destroy()
        if restored
            this.ReleaseCaptureTransaction()
        return restored
    }

    SaveCurrentProfile(allowDuringShutdown := false, expectedMutationState := 0) {
        if !this.BeginProfileMutationTransaction("save the profile", allowDuringShutdown)
            return false
        try {
            if IsObject(expectedMutationState) {
                profileName := expectedMutationState.profileName
                if (!this.IsProfileDirty(profileName)
                    || !this.ProfileMutationStateIsCurrent(expectedMutationState)) {
                    this.NotifyUser(
                        "The profile changed while the save prompt was open. Review the current changes and try again.",
                        "Profile Changed",
                        "Icon!"
                    )
                    return false
                }
                mutationState := expectedMutationState
            } else {
                profileName := ProfileManager.currentProfile
                mutationState := this.CaptureProfileMutationState(profileName)
            }
            try {
                ; One immutable snapshot is both the persisted value and the runtime
                ; contract. Success is not published until that same snapshot is live.
                savedProfile := ProfileManager.CloneProfile(
                    ProfileManager.profiles[profileName]
                )
                ProfileManager.SaveProfile(profileName, savedProfile)
            } catch as err {
                AppLog.Write("Profile '" profileName "' could not be saved: " ErrorText.Describe(err))
                this.NotifyUser("The profile could not be saved. The previous file was left unchanged.`n`n" err.Message, "Save Failed", "Icon!")
                return false
            }

            if !this.ProfileMutationStateIsCurrent(mutationState) {
                return this.RecoverConcurrentProfileSave(
                    profileName,
                    "The profile changed while it was being saved. The saved snapshot is intact, but the newer edits remain unsaved."
                )
            }

            applyError := ""
            failedBinds := ""
            runtimeApplied := false
            try runtimeApplied := this.ApplyProfileBinds(savedProfile, false, &failedBinds)
            catch as err
                applyError := err.Message

            if !runtimeApplied {
                if (applyError = "")
                    applyError := "These saved keybinds could not be registered: " failedBinds
                restoreError := ""
                if !this.RestoreRuntimeProfile(savedProfile, &restoreError) {
                    message := "The profile was saved, but its runtime shortcuts could not be verified."
                        . "`n`n" applyError
                        . "`n`nThe saved runtime bindings also could not be fully restored: " restoreError
                        . ". Restart PACS Assistant before relying on its shortcuts."
                    this.NotifyUser(message, "Profile Saved - Restart Required", "Icon!")
                    return false
                }
            }

            if !this.ProfileMutationStateIsCurrent(mutationState) {
                return this.RecoverConcurrentProfileSave(
                    profileName,
                    "The profile changed while its saved shortcuts were being applied. The newer edits remain unsaved."
                )
            }

            this.NotifyNonModal("Profile saved successfully.", "Profile Saved", "Iconi")
            this.ClearProfileDirty(profileName)
            return true
        } finally this.EndProfileMutationTransaction()
    }

    CaptureProfileMutationState(profileName) {
        if (profileName = "" || !ProfileManager.profiles.Has(profileName))
            return 0
        profile := ProfileManager.profiles[profileName]
        return {
            profileName: profileName,
            profileObject: profile,
            mutationRevision: KeybindGUI.GetProfileMutationRevision(profileName)
        }
    }

    ProfileMutationStateIsCurrent(state) {
        return IsObject(state)
            && ProfileManager.currentProfile == state.profileName
            && ProfileManager.profiles.Has(state.profileName)
            && ProfileManager.profiles[state.profileName] == state.profileObject
            && KeybindGUI.GetProfileMutationRevision(state.profileName) = state.mutationRevision
    }

    RecoverConcurrentProfileSave(profileName, message) {
        restoreError := ""
        currentProfile := ProfileManager.profiles.Has(profileName)
            ? ProfileManager.CloneProfile(ProfileManager.profiles[profileName])
            : 0
        if !IsObject(currentProfile) || !this.RestoreRuntimeProfile(currentProfile, &restoreError) {
            if (restoreError = "")
                restoreError := "the current profile is no longer available"
            this.NotifyUser(
                message "`n`nThe newer runtime shortcuts could not be verified: " restoreError
                    . ". Restart PACS Assistant before relying on its shortcuts.",
                "Profile Changed - Restart Required",
                "Icon!"
            )
            return false
        }
        this.NotifyUser(
            message " Save again after reviewing them.",
            "Profile Changed During Save",
            "Icon!"
        )
        return false
    }

    EnsureDirtyProfiles() {
        if !this.HasOwnProp("dirtyProfiles")
            this.dirtyProfiles := Map()
        return this.dirtyProfiles
    }

    static GetProfileMutationRevision(profileName) {
        return this.profileMutationRevisions.Has(profileName)
            ? this.profileMutationRevisions[profileName]
            : 0
    }

    static AdvanceProfileMutationRevision(profileName) {
        nextRevision := this.GetProfileMutationRevision(profileName) + 1
        this.profileMutationRevisions[profileName] := nextRevision
        return nextRevision
    }

    MarkProfileDirty(profileName) {
        if (profileName != "") {
            this.EnsureDirtyProfiles()[profileName] := true
            KeybindGUI.AdvanceProfileMutationRevision(profileName)
        }
        this.RefreshMainView()
    }

    ClearProfileDirty(profileName) {
        dirty := this.EnsureDirtyProfiles()
        if dirty.Has(profileName)
            dirty.Delete(profileName)
        this.RefreshMainView()
    }

    IsProfileDirty(profileName) {
        return profileName != "" && this.EnsureDirtyProfiles().Has(profileName)
    }

    ChooseUnsavedProfileAction(profileName) {
        if this.HasOwnProp("profileLeaveDriver")
            return this.profileLeaveDriver.Choose(profileName)
        return MsgBox(
            "Profile '" profileName "' has unsaved keybind changes."
                . "`n`nYes = Save, No = Discard, Cancel = keep editing.",
            "Unsaved Profile Changes",
            "YesNoCancel Icon!"
        )
    }

    ResolveDirtyProfileBeforeLeaving(refreshMainWindow := false, allowDuringShutdown := false) {
        profileName := ProfileManager.currentProfile
        if !this.IsProfileDirty(profileName)
            return true
        mutationState := this.CaptureProfileMutationState(profileName)

        choice := this.ChooseUnsavedProfileAction(profileName)
        if (choice == "Cancel")
            return false
        if (choice == "Yes")
            return this.SaveCurrentProfile(allowDuringShutdown, mutationState)
        if !(choice == "No")
            return false
        return this.DiscardProfileChanges(profileName, mutationState, refreshMainWindow, allowDuringShutdown)
    }

    ; Profile > Discard Changes: after a confirmation, restores the saved profile.
    DiscardCurrentChanges() {
        profileName := ProfileManager.currentProfile
        if !this.IsProfileDirty(profileName)
            return false
        mutationState := this.CaptureProfileMutationState(profileName)
        if !this.ConfirmDestructiveAction(
            "Discard the unsaved changes to '" profileName "'? Its saved keybinds are restored.",
            "Discard Changes"
        )
            return false
        return this.DiscardProfileChanges(profileName, mutationState, true)
    }

    /**
     * Restores a dirty profile from its file: the runtime keybinds first, then the
     * profile, then (with refreshMainWindow) the main window. Refused when the
     * profile changed since mutationState was captured, as while a prompt was open.
     */
    DiscardProfileChanges(profileName, mutationState, refreshMainWindow, allowDuringShutdown := false) {
        if !this.BeginProfileMutationTransaction("discard unsaved profile changes", allowDuringShutdown)
            return false
        try {
            if (!this.IsProfileDirty(profileName)
                || !this.ProfileMutationStateIsCurrent(mutationState)) {
                this.NotifyUser(
                    "The profile changed while the discard prompt was open. Review the current changes and try again.",
                    "Profile Changed",
                    "Icon!"
                )
                return false
            }

            originalProfile := ProfileManager.profiles[profileName]
            try {
                stored := ProfileManager.LoadProfile(ProfileManager.ProfilePath(profileName))
            } catch as err {
                AppLog.Write("Saved profile '" profileName "' could not be reloaded to discard changes: " ErrorText.Describe(err))
                this.NotifyUser(
                    "The saved profile could not be reloaded, so the unsaved changes were retained.`n`n" err.Message,
                    "Discard Failed",
                    "Icon!"
                )
                return false
            }

            restoreError := ""
            if !this.RestoreRuntimeProfile(stored, &restoreError) {
                this.RestoreRuntimeAndNotify(
                    originalProfile,
                    "The unsaved changes were retained because the saved runtime bindings could not be restored.`n`n" restoreError,
                    "Discard Failed"
                )
                return false
            }

            ProfileManager.profiles[profileName] := stored
            ProfileManager.profileRevisions[profileName] :=
                ProfileManager.GetProfileRevision(profileName) + 1
            this.ClearProfileDirty(profileName)

            if (refreshMainWindow && this.HasMainWindow()) {
                try {
                    this.gui.Destroy()
                    ; The stored profile is already the verified live runtime contract.
                    ; Rebuild only the view; re-registering would add another failure edge.
                    this.CreateMainGUI(false)
                } catch as err {
                    AppLog.Write("The main window could not be refreshed after a discard: " ErrorText.Describe(err))
                    this.NotifyUser(
                        "The saved profile was restored, but the main window could not be refreshed.`n`n" err.Message,
                        "Profile View Refresh Failed",
                        "Icon!"
                    )
                    return false
                }
            }
            return true
        } finally this.EndProfileMutationTransaction()
    }

    ApplyBinds() {
        ownsTransaction := false
        if (!ExclusiveOperations.captureActive
            && !ExclusiveOperations.profileMutationActive) {
            if !this.BeginProfileMutationTransaction("apply profile keybinds")
                return false
            ownsTransaction := true
        }
        try {
            currentProfile := ProfileManager.profiles[ProfileManager.currentProfile]
            return this.ApplyProfileBinds(currentProfile, true)
        } finally {
            if ownsTransaction
                this.EndProfileMutationTransaction()
        }
    }

    /**
     * Registers every bind of a profile. On failure, failureText lists each bind that
     * failed with its reason, as "Name (reason); Name (reason)".
     *
     * A bind that can never register (one for a command this version does not
     * have, or one whose key AutoHotkey rejects, as after a hand edit or on another
     * keyboard layout) stays in the profile but is left out of the runtime, and is
     * reported when showErrors is set, so it cannot fail every later apply,
     * restore and save. A newly captured key is checked separately (OnInputEnd).
     */
    ApplyProfileBinds(currentProfile, showErrors := true, &failureText := "") {
        failureText := ""
        HotkeyManager.DisableAllHotkeys()
        failed := []
        unavailable := ""
        rejected := ""
        ; Why each set keybind is not live, for the main window to show per row.
        failureReasons := Map()

        for funcName, bind in currentProfile.binds {
            if (!currentProfile.customFuncs.Has(funcName)
                && !HotkeyManager.hotkeyFunctions.Has(funcName)) {
                if (bind != "") {
                    unavailable .= (unavailable = "" ? "" : ", ") funcName
                    failureReasons[funcName] := "this version of PACS Assistant has no command with this name."
                }
                continue
            }
            scope := currentProfile.scopes.Has(funcName) ? currentProfile.scopes[funcName] : "Any"
            try {
                if (currentProfile.customFuncs.Has(funcName)) {
                    config := currentProfile.customFuncs[funcName]
                    callback := PACSCommands.CreateCustomKeybind(config.keys, config.window, funcName)
                    result := HotkeyManager.Register(funcName, bind, callback, scope)
                } else {
                    result := HotkeyManager.RegisterHotkey(funcName, bind, scope)
                }

                if (!result && HotkeyManager.lastErrorKind == "invalidHotkey") {
                    rejected .= (rejected = "" ? "" : ", ") funcName " (" bind ")"
                    failureReasons[funcName] := "AutoHotkey does not accept this key on this computer."
                } else if !result {
                    failed.Push(funcName (HotkeyManager.lastError != "" ? " (" HotkeyManager.lastError ")" : ""))
                    failureReasons[funcName] := HotkeyManager.lastError != "" ? HotkeyManager.lastError : "it could not be registered."
                }
            } catch as err {
                failed.Push(funcName " (" err.Message ")")
                failureReasons[funcName] := err.Message
            }
        }
        KeybindGUI.runtimeFailures := failureReasons
        this.RefreshMainView()

        if (showErrors && (unavailable != "" || rejected != "")) {
            reasons := []
            if (unavailable != "")
                reasons.Push("for commands this version of PACS Assistant does not have: " unavailable)
            if (rejected != "")
                reasons.Push("with keys AutoHotkey does not accept on this computer: " rejected)
            details := ""
            for reason in reasons
                details .= (A_Index > 1 ? "; " : "") reason
            AppLog.Write("Keybinds were not registered, " details)
            notice := "These keybinds were not registered:"
            for reason in reasons
                notice .= "`n- " reason
            this.NotifyUser(notice "`n`nReassign or remove them in the profile.", "Keybinds Not Registered", "Icon!")
        }
        if !failed.Length
            return true
        ; Logged on every failed apply, including the silent ones a restore or a
        ; candidate check makes; one dialog for the whole apply when shown.
        errMsg := "These keybinds failed to register:"
        for item in failed {
            errMsg .= "`n- " item
            failureText .= (A_Index > 1 ? "; " : "") item
        }
        AppLog.Write("These keybinds failed to register: " failureText)
        if showErrors
            this.NotifyUser(errMsg, "Keybind Errors", "Icon!")
        return false
    }

    RestoreRuntimeProfile(profile, &failureText) {
        failureText := ""
        try {
            if this.ApplyProfileBinds(profile, false, &failureText)
                return true
        } catch as err {
            failureText := err.Message
            AppLog.Write("Runtime keybinds could not be restored: " ErrorText.Describe(err))
        }
        return false
    }

    static LoadErrorSummary(loadErrors) {
        text := loadErrors.Length " profile file(s) could not be loaded. The original files were left unchanged."
        for loadError in loadErrors
            text .= "`n`n" loadError.path "`n" loadError.message
        return text "`n`nThis list is also in error.log in the PACS Assistant data folder."
    }

    ConfirmDestructiveAction(message, title) {
        if this.HasOwnProp("confirmationDriver")
            return this.confirmationDriver.Confirm(message, title)
        return MsgBox(message, title, "YesNo Icon!") = "Yes"
    }

    /**
     * Shows a modal notice. Under the profile-mutation lease the notice waits until
     * EndProfileMutationTransaction releases it: the lease refuses clinical commands
     * and pauses background monitoring, so a dialog left open under it would stop
     * both until dismissed.
     */
    NotifyUser(message, title, options := "") {
        if ExclusiveOperations.profileMutationActive
            KeybindGUI.deferredNotices.Push({message: message, title: title, options: options})
        else
            this.ShowNotice(message, title, options)
    }

    ShowNotice(message, title, options := "") {
        if this.HasOwnProp("notificationDriver")
            return this.notificationDriver.Notify(message, title, options)
        return MsgBox(message, title, options)
    }

    ShowDeferredNotices() {
        notices := KeybindGUI.deferredNotices
        KeybindGUI.deferredNotices := []
        for notice in notices
            this.ShowNotice(notice.message, notice.title, notice.options)
    }

    ; Non-modal: for messages that need no acknowledgement.
    NotifyNonModal(message, title, options := "") {
        if this.HasOwnProp("notificationDriver")
            return this.notificationDriver.Notify(message, title, options)
        return TrayTip(message, title, options)
    }

    ProfileMutationAllowed(action, allowDuringShutdown := false) {
        return this.OperationAllowed(action, ExclusiveOperations.ShutdownExemption(allowDuringShutdown))
    }

    ; Whether no exclusive operation outside exemption is active; if one is, says
    ; which in a non-modal notice.
    OperationAllowed(action, exemption) {
        active := ExclusiveOperations.Active(exemption*)
        switch active, true {
            case "":
                return true
            case "clinical":
                message := "Wait for '" PACSCommands.activeClinicalCommand "' to finish before you " action "."
                title := "Clinical Command In Progress"
            case "capture":
                message := ExclusiveOperations.captureRestartRequired
                    ? "Restart PACS Assistant before you " action ". Key capture could not be recovered."
                    : "Finish or cancel the active key capture before you " action "."
                title := ExclusiveOperations.captureRestartRequired ? "Restart Required" : "Keybind In Progress"
            case "profileMutation":
                message := "Wait for the current profile operation ('"
                    . ExclusiveOperations.profileMutationAction
                    . "') to finish before you " action "."
                title := "Profile Operation In Progress"
            case "settingsWrite":
                message := "Wait for the current settings operation to finish before you " action "."
                title := "Settings Operation In Progress"
            case "uiPresentation":
                message := "Wait for the current dialog operation ('"
                    . ExclusiveOperations.uiPresentationAction
                    . "') to finish before you " action "."
                title := "Dialog Operation In Progress"
            case "shutdown":
                message := "PACS Assistant is preparing to " ExclusiveOperations.shutdownAction
                    . ". Wait for that operation to finish before you " action "."
                title := "Shutdown In Progress"
        }
        this.NotifyNonModal(message, title, "Icon!")
        return false
    }

    BeginProfileMutationTransaction(action, allowDuringShutdown := false) {
        if !this.ProfileMutationAllowed(action, allowDuringShutdown)
            return false
        exemption := ExclusiveOperations.ShutdownExemption(allowDuringShutdown)
        if ExclusiveOperations.TryBegin("profileMutation", action, exemption*)
            return true
        ; Another operation won the race since the check above; report it.
        this.ProfileMutationAllowed(action, allowDuringShutdown)
        return false
    }

    EndProfileMutationTransaction() {
        ExclusiveOperations.End("profileMutation")
        this.ShowDeferredNotices()
    }

    BeginCaptureTransaction(action := "start key capture") {
        if !this.ProfileMutationAllowed(action)
            return false
        if !ExclusiveOperations.TryBegin("capture", action) {
            ; Another operation won the race since the check above; report it.
            this.ProfileMutationAllowed(action)
            return false
        }
        KeybindGUI.captureOwnerGui := 0
        hasMainWindow := false
        try hasMainWindow := this.HasMainWindow()
        if hasMainWindow {
            KeybindGUI.captureOwnerGui := this.gui
            try this.gui.Opt("+Disabled")
        }
        return true
    }

    ReleaseCaptureTransaction() {
        Critical("On")
        try {
            ownerGui := KeybindGUI.captureOwnerGui
            if IsObject(ownerGui)
                try ownerGui.Opt("-Disabled")
            KeybindGUI.captureOwnerGui := 0
            ExclusiveOperations.captureRestartRequired := false
            ; This is the terminal publication step: callbacks can enter only after
            ; the owner/UI/runtime/dirty state has already been finalized.
            ExclusiveOperations.End("capture")
        } finally Critical("Off")
    }

    RequireCaptureRestart() {
        ExclusiveOperations.captureRestartRequired := true
        ; Keep the capture lease to refuse unsafe edits, but let the owner window's
        ; Close action use the restart exemption and exit normally.
        if IsObject(KeybindGUI.captureOwnerGui)
            try KeybindGUI.captureOwnerGui.Opt("-Disabled")
    }

    AbortStaleCapture(dialog, message, title) {
        ; BeginListening revalidates its dialog after taking the capture lease but
        ; before suspending hotkeys or starting InputHook. If that snapshot is stale,
        ; release directly: an Off/On "restore" would introduce a failure boundary
        ; despite there being no runtime mutation to undo.
        if (!KeybindGUI.isListening
            && !IsObject(KeybindGUI.activeInputHook)
            && !IsObject(KeybindGUI.captureRuntimeProfile)) {
            try dialog.Destroy()
            this.NotifyUser(message, title, "Icon!")
            this.ReleaseCaptureTransaction()
            return false
        }

        try this.StopListening()
        catch as err {
            this.NotifyUser(
                message "`n`nThe input hook could not be stopped: " err.Message
                    . ". Restart PACS Assistant before pressing another shortcut.",
                title,
                "Icon!"
            )
            return false
        }

        currentProfile := 0
        currentName := ProfileManager.currentProfile
        if (currentName != "" && ProfileManager.profiles.Has(currentName))
            currentProfile := ProfileManager.CloneProfile(ProfileManager.profiles[currentName])
        ; A stale callback must never restore the pre-capture snapshot over a newer
        ; committed profile mutation. The current profile is now authoritative.
        KeybindGUI.captureRuntimeProfile := 0
        restored := false
        if currentProfile {
            restored := this.RestoreRuntimeAndNotify(
                currentProfile,
                message,
                title,
                true
            )
        } else {
            AppLog.Write("Runtime keybinds could not be restored: no current profile could be verified")
            this.NotifyUser(
                message "`n`nNo current profile could be verified. Restart PACS Assistant before relying on its shortcuts.",
                title,
                "Icon!"
            )
        }
        try dialog.Destroy()
        if restored
            this.ReleaseCaptureTransaction()
        else
            this.RequireCaptureRestart()
        return false
    }

    RestoreRuntimeAndNotify(originalProfile, message, title, notifyOnSuccess := true) {
        restoreError := ""
        restored := this.RestoreRuntimeProfile(originalProfile, &restoreError)
        if !restored {
            message .= "`n`nThe previous runtime bindings could not be fully restored: " restoreError
                . ". Restart PACS Assistant before relying on its shortcuts."
        }
        if (notifyOnSuccess || !restored)
            this.NotifyUser(message, title, "Icon!")
        return restored
    }

    RestoreCapturedRuntimeAndNotify(fallbackProfile, message, title, notifyOnSuccess := true) {
        originalProfile := IsObject(KeybindGUI.captureRuntimeProfile)
            ? KeybindGUI.captureRuntimeProfile
            : fallbackProfile
        try {
            restored := this.RestoreRuntimeAndNotify(
                originalProfile,
                message,
                title,
                notifyOnSuccess
            )
        } finally KeybindGUI.captureRuntimeProfile := 0
        ; The caller keeps the capture lease; the notice asked for a restart.
        if !restored
            this.RequireCaptureRestart()
        return restored
    }

    CaptureFunctionRemovalState(listView) {
        try row := listView.GetNext(0)
        catch
            return 0
        if !row
            return 0

        profileName := ProfileManager.currentProfile
        if (profileName = "" || !ProfileManager.profiles.Has(profileName))
            return 0
        profile := ProfileManager.profiles[profileName]

        try {
            funcName := listView.GetText(row, 1)
            if (!profile.binds.Has(funcName)
                || this.FindUniqueFunctionRow(listView, funcName) != row)
                return 0
            return {
                profileName: profileName,
                profilePointer: ObjPtr(profile),
                profileRevision: ProfileManager.GetProfileRevision(profileName),
                functionName: funcName,
                bind: profile.binds[funcName],
                hasScope: profile.scopes.Has(funcName),
                scope: profile.scopes.Has(funcName) ? profile.scopes[funcName] : "",
                row: row,
                rowBind: listView.GetText(row, 2),
                rowScope: listView.GetText(row, 3)
            }
        }
        return 0
    }

    FunctionRemovalStateIsCurrent(state, listView) {
        if (!state
            || !(ProfileManager.currentProfile == state.profileName)
            || !ProfileManager.profiles.Has(state.profileName)
            || ProfileManager.GetProfileRevision(state.profileName) != state.profileRevision)
            return false

        profile := ProfileManager.profiles[state.profileName]
        if (ObjPtr(profile) != state.profilePointer
            || !profile.binds.Has(state.functionName)
            || !(profile.binds[state.functionName] == state.bind)
            || profile.scopes.Has(state.functionName) != state.hasScope)
            return false
        if (state.hasScope && !(profile.scopes[state.functionName] == state.scope))
            return false

        try return listView.GetNext(0) = state.row
            && this.FindUniqueFunctionRow(listView, state.functionName) = state.row
            && listView.GetText(state.row, 1) == state.functionName
            && listView.GetText(state.row, 2) == state.rowBind
            && listView.GetText(state.row, 3) == state.rowScope
        return false
    }

    CaptureCustomDeletionState(funcName, selectorGui) {
        if !this.DialogProfileIsCurrent(selectorGui)
            return 0
        profileName := selectorGui.profileName
        if this.IsProfileDirty(profileName)
            return 0
        profile := ProfileManager.profiles[profileName]
        if !profile.customFuncs.Has(funcName)
            return 0
        config := profile.customFuncs[funcName]
        if (!IsObject(config)
            || !HasProp(config, "keys")
            || !HasProp(config, "window"))
            return 0
        return {
            profileName: profileName,
            profilePointer: ObjPtr(profile),
            profileRevision: ProfileManager.GetProfileRevision(profileName),
            mutationRevision: KeybindGUI.GetProfileMutationRevision(profileName),
            functionName: funcName,
            configPointer: ObjPtr(config),
            keys: config.keys,
            window: config.window,
            hasBind: profile.binds.Has(funcName),
            bind: profile.binds.Has(funcName) ? profile.binds[funcName] : "",
            hasScope: profile.scopes.Has(funcName),
            scope: profile.scopes.Has(funcName) ? profile.scopes[funcName] : ""
        }
    }

    CustomDeletionStateIsCurrent(state, selectorGui) {
        if (!state
            || !this.DialogProfileIsCurrent(selectorGui)
            || !(selectorGui.profileName == state.profileName)
            || ProfileManager.GetProfileRevision(state.profileName) != state.profileRevision
            || KeybindGUI.GetProfileMutationRevision(state.profileName) != state.mutationRevision
            || this.IsProfileDirty(state.profileName))
            return false
        profile := ProfileManager.profiles[state.profileName]
        if (ObjPtr(profile) != state.profilePointer
            || !profile.customFuncs.Has(state.functionName))
            return false
        config := profile.customFuncs[state.functionName]
        return IsObject(config)
            && ObjPtr(config) = state.configPointer
            && HasProp(config, "keys")
            && config.keys == state.keys
            && HasProp(config, "window")
            && config.window == state.window
            && profile.binds.Has(state.functionName) = state.hasBind
            && (!state.hasBind || profile.binds[state.functionName] == state.bind)
            && profile.scopes.Has(state.functionName) = state.hasScope
            && (!state.hasScope || profile.scopes[state.functionName] == state.scope)
    }

    ApplyProfileCandidate(candidate, originalProfile, operationName) {
        applyError := ""
        failedBinds := ""
        try {
            if this.ApplyProfileBinds(candidate, false, &failedBinds)
                return true
            applyError := "These keybinds could not be registered: " failedBinds
        } catch as err {
            applyError := err.Message
        }

        restoreError := ""
        restored := this.RestoreRuntimeProfile(originalProfile, &restoreError)
        message := "The " operationName " was not applied because its runtime keybind state could not be verified."
        if (applyError != "")
            message .= "`n`n" applyError
        if !restored
            message .= "`n`nThe previous runtime bindings also could not be fully restored: " restoreError
                . ". Restart PACS Assistant before relying on its shortcuts."
        ; Callers hold the profile-mutation lease; NotifyUser shows this after it.
        this.NotifyUser(message, "Keybind Change Cancelled", "Icon!")
        return false
    }

    /**
     * Display form of a hotkey, such as "Ctrl + Shift + V". ~ $ * change only how a
     * hotkey behaves, so they are not shown; a symbol that ends the hotkey is its
     * key (^+ is Ctrl and the + key). A custom combination ("a & b") shows as
     * written, in capitals.
     */
    PrettifyHotkey(hotkeyStr) {
        if (hotkeyStr = "")
            return "Unassigned"
        if InStr(hotkeyStr, " & ")
            return StrUpper(hotkeyStr)

        prefix := HotkeyContract.ParsePrefix(Trim(hotkeyStr), true)
        key := Trim(prefix.rest)
        if (key = "") {
            key := SubStr(Trim(hotkeyStr), -1)
            if prefix.modifiers.Has(key)
                prefix.modifiers.Delete(key)
        }

        text := ""
        for modifier in KeybindGUI.modifierNames {
            if prefix.modifiers.Has(modifier[1])
                text .= modifier[2] " + "
        }
        release := RegExMatch(key, "i)^(.+?)\s+up$", &upMatch)
        if release
            key := upMatch[1]
        ; A single character shows as typed (GetKeyName("+") is the unshifted "=");
        ; named keys use the canonical spelling.
        name := StrLen(key) = 1 ? StrUpper(key) : HotkeyContract.CanonicalKeyName(key)
        if (name = "")
            name := key
        return text name (release ? " Up" : "")
    }

    PromptRenameProfile(name, parentGui := 0) {
        if !this.ProfileMutationAllowed("rename a profile")
            return false
        if (parentGui && !this.RequireCurrentProfileSelector(parentGui))
            return false
        if (name = "") {
            MsgBox("Please select a profile first.", "No Profile Selected", "Icon!")
            return false
        }
        ; A case-only rename moves the existing file rather than rewriting it. Make
        ; the current in-memory profile match disk before capturing the dialog so no
        ; dirty binding can be silently discarded when the dirty flag is rekeyed.
        if (!parentGui
            && name == ProfileManager.currentProfile
            && !this.ResolveDirtyProfileBeforeLeaving(true))
            return false

        selectorTransaction := false
        if parentGui {
            if !this.BeginProfileMutationTransaction("open the profile rename dialog")
                return false
            selectorTransaction := true
        }
        try {
            if (parentGui && !this.RequireCurrentProfileSelector(parentGui))
                return false
            renameGui := this.NewProfileDialog(
                "PACS Assistant - Rename Profile",
                name,
                parentGui
            )
            if !this.CaptureRenameDialogState(renameGui, name) {
                renameGui.Destroy()
                return false
            }
            width := 320
            UITheme.AddHeading(renameGui, "Rename profile", "xm ym w" width)
            UITheme.AddNote(renameGui, "Its keybinds and modality attendings stay with it.", "xm y+4 w" width)
            renameGui.Add("Text", "xm y+14 w" width, "&New name for '" name "'")
            nameEdit := renameGui.Add("Edit", "xm y+4 r1 w" width, name)
            cancel := (*) => renameGui.Destroy()
            UITheme.AddFooter(renameGui, width, [
                {text: "Rename", action: (*) => this.RenameProfile(name, nameEdit.Value, renameGui, parentGui), default: true},
                {text: "Cancel", action: cancel}
            ])
            ; The title-bar X must destroy like Cancel; Close only hides by default.
            renameGui.OnEvent("Close", cancel)
            renameGui.OnEvent("Escape", cancel)
            UITheme.ShowDialog(renameGui)
            return true
        } finally {
            if selectorTransaction
                this.EndProfileMutationTransaction()
        }
    }

    CaptureRenameDialogState(renameGui, name) {
        if !ProfileManager.profiles.Has(name)
            return false
        renameGui.profileName := name
        renameGui.profilePointer := ObjPtr(ProfileManager.profiles[name])
        renameGui.profileRevision := ProfileManager.GetProfileRevision(name)
        return true
    }

    RenameProfile(oldName, newName, renameGui, parentGui := 0) {
        if !this.RenameDialogIsCurrent(oldName, renameGui, parentGui)
            return false

        newName := Trim(newName)
        if (newName = "") {
            MsgBox("Profile name cannot be empty.", "Invalid Profile Name", "Icon!")
            return false
        }
        if !ProfileManager.IsValidProfileName(newName) {
            MsgBox(
                "Enter a profile name without file-system characters or reserved Windows device names.",
                "Invalid Profile Name",
                "Icon!"
            )
            return false
        }

        if !this.BeginProfileMutationTransaction("rename a profile")
            return false
        try {
            if !this.RenameDialogIsCurrent(oldName, renameGui, parentGui)
                return false
            if (ProfileManager.RenameProfile(oldName, newName)) {
                this.ClearProfileDirty(oldName)
                this.ClearProfileDirty(newName)
                renameGui.Destroy()
                if (parentGui) {
                    parentGui.Destroy()
                    this.ShowProfileSelector()  ; Refresh the selector
                } else {
                    this.gui.Destroy()
                    ; Renaming changes storage/display identity only. Rebuilding the
                    ; window must not tear down and re-register unchanged hotkeys.
                    this.CreateMainGUI(false)
                }
                return true
            }
            this.NotifyUser(
                this.ProfileStorageFailureText(
                    "Failed to rename profile. The name may already be in use."
                ),
                "Profile Rename Failed",
                "Icon!"
            )
            return false
        } finally this.EndProfileMutationTransaction()
    }

    ProfileStorageFailureText(fallback) {
        message := ProfileManager.lastError != ""
            ? ProfileManager.lastError
            : fallback
        if ProfileManager.recoveryRequired
            message .= "`n`nProfile storage could not be fully restored. Restart PACS Assistant before changing profiles again."
        return message
    }

    RenameDialogIsCurrent(oldName, renameGui, parentGui := 0) {
        capturedName := ""
        try capturedName := renameGui.profileName
        valid := this.GuiIsLive(renameGui)
            && capturedName == oldName
            && ProfileManager.profiles.Has(oldName)
            && !this.IsProfileDirty(oldName)
            && HasProp(renameGui, "profilePointer")
            && ObjPtr(ProfileManager.profiles[oldName]) = renameGui.profilePointer
            && HasProp(renameGui, "profileRevision")
            && ProfileManager.GetProfileRevision(oldName) = renameGui.profileRevision
        if valid {
            valid := parentGui
                ? this.ProfileSelectorIsCurrent(parentGui)
                : ProfileManager.currentProfile = oldName
        }
        if valid
            return true

        try renameGui.Destroy()
        this.NotifyUser(
            "The profile context changed while this rename dialog was open. Reopen it before renaming.",
            "Profile Changed",
            "Icon!"
        )
        return false
    }

    ShowAddFunctionDialog(listView) {
        if !this.ProfileMutationAllowed("edit profile functions")
            return false
        ; Custom deletion persists the whole profile. Resolve any pending keybind
        ; edits before opening a dialog that can reach that persistence boundary.
        ; Discard rebuilds the owner and invalidates the ListView supplied by its
        ; click callback, so require a fresh click from the rebuilt window. Save
        ; keeps the window, so the dialog opens as asked.
        ownerBefore := this.gui
        if !this.ResolveDirtyProfileBeforeLeaving(true)
            return false
        if !(this.gui == ownerBefore) {
            this.NotifyUser(
                "The pending profile changes were resolved. Click Add Function again in the refreshed window.",
                "Profile Refreshed"
            )
            return false
        }
        selectorGui := this.NewProfileDialog("PACS Assistant - Add Function")

        ; Get list of unbound functions, separated by type
        builtInFunctions := []
        customFunctions := []

        ; Add built-in functions that aren't bound
        for funcName, _ in PACSCommands.commands {
            if !ProfileManager.profiles[ProfileManager.currentProfile].binds.Has(funcName) {
                builtInFunctions.Push(funcName)
            }
        }

        ; Add ALL custom functions from current profile that aren't bound
        for funcName, _ in ProfileManager.profiles[ProfileManager.currentProfile].customFuncs {
            if !ProfileManager.profiles[ProfileManager.currentProfile].binds.Has(funcName) {
                customFunctions.Push(funcName)
            }
        }

        width := 400
        UITheme.AddHeading(selectorGui, "Add a function", "xm ym w" width)
        UITheme.AddNote(
            selectorGui,
            "Choose a command for '" selectorGui.profileName "'. You'll press its keybind next.",
            "xm y+4 w" width
        )

        ; Each list exists only when it has something to add. A list left out stays
        ; "", which SelectedFunction accepts.
        selectorGui.Add("Text", "xm y+14 w" (width - 130), "&Built-in commands")
        lbBuiltIn := ""
        if (builtInFunctions.Length > 0) {
            ; Add All, on the label's row: every command left, each unassigned.
            selectorGui.Add("Button", "x" (UITheme.margin + width - 120) " yp-6 w120 h26", "Add &All (" builtInFunctions.Length ")")
                .OnEvent("Click", (*) => this.AddAllFunctions(listView, selectorGui))
            lbBuiltIn := selectorGui.Add("ListBox", "xm y+4 w" width " r6", builtInFunctions)
        } else
            UITheme.AddNote(selectorGui, "Every built-in command is already in this profile.", "xm y+4 w" width)

        lbCustom := ""
        if (customFunctions.Length > 0) {
            selectorGui.Add("Text", "xm y+14 w" width, "&Custom keybinds")
            lbCustom := selectorGui.Add("ListBox", "xm y+4 w" width " r3", customFunctions)
            selectorGui.Add("Button", "x" (UITheme.margin + width - 180) " y+" UITheme.gap " w180 h" UITheme.buttonHeight, "&Delete Custom Keybind...")
                .OnEvent("Click", (*) => this.DeleteCustomFunction(lbCustom.Text, selectorGui))
            if lbBuiltIn
                this.LinkFunctionLists(lbBuiltIn, lbCustom)
        }

        ; What the selected command does, three lines tall so the window keeps its
        ; size as the selection changes.
        description := UITheme.AddNote(selectorGui, "Select a command to see what it does.", "xm y+12 w" width " r3")
        profile := ProfileManager.profiles[ProfileManager.currentProfile]
        describe := (*) => (
            selected := this.SelectedFunction(lbBuiltIn, lbCustom),
            description.Value := selected = ""
                ? "Select a command to see what it does."
                : CommandInfo.Describe(selected, profile.customFuncs.Has(selected) ? profile.customFuncs[selected] : 0)
        )

        add := (*) => this.AddFunction(this.SelectedFunction(lbBuiltIn, lbCustom), listView, selectorGui)
        for functionList in [lbBuiltIn, lbCustom] {
            if functionList {
                functionList.OnEvent("DoubleClick", add)
                functionList.OnEvent("Change", describe)
            }
        }
        cancel := (*) => selectorGui.Destroy()
        footer := UITheme.AddFooter(
            selectorGui,
            width,
            [
                {text: "Add", action: add, default: true},
                {text: "Cancel", action: cancel}
            ],
            [{text: "Create Custom &Keybind...", width: 170, action: (*) => (
                selectorGui.Destroy(),
                this.ShowCustomKeybindDialog(listView, selectorGui.profileName)
            )}]
        )
        ; With nothing left to add, only a new custom keybind remains.
        footer["Add"].Enabled := !!(lbBuiltIn || lbCustom)
        ; The title-bar X must destroy like Cancel; Close only hides by default.
        selectorGui.OnEvent("Close", cancel)
        selectorGui.OnEvent("Escape", cancel)

        UITheme.ShowDialog(selectorGui)
        return true
    }

    ; One selection across both lists: choosing in one clears the other, so Add
    ; Selected adds the function clicked last.
    LinkFunctionLists(lbBuiltIn, lbCustom) {
        lbBuiltIn.OnEvent("Change", (*) => lbCustom.Choose(0))
        lbCustom.OnEvent("Change", (*) => lbBuiltIn.Choose(0))
    }

    /**
     * The function selected in either list, built-in first.
     * Accepts "" for a list that was not created, which is why it takes the controls
     * rather than their text.
     * @returns the selected name, or "" when neither list has a selection
     */
    SelectedFunction(lbBuiltIn, lbCustom) {
        if (lbBuiltIn && lbBuiltIn.Text != "")
            return lbBuiltIn.Text
        if (lbCustom && lbCustom.Text != "")
            return lbCustom.Text
        return ""
    }

    DeleteCustomFunction(funcName, selectorGui) {
        if !this.ProfileMutationAllowed("delete a custom function")
            return false
        if !this.DialogProfileIsCurrent(selectorGui)
            return false

        if this.IsProfileDirty(selectorGui.profileName) {
            try selectorGui.Destroy()
            this.NotifyUser(
                "The profile changed while Add Function was open. Save or discard those keybind edits, then reopen it before deleting a custom function.",
                "Unsaved Profile Changes",
                "Icon!"
            )
            return false
        }

        if (funcName = "") {
            MsgBox("Please select a custom function to delete.", "No Function Selected", "Icon!")
            return false
        }

        if (InStr(funcName, "Custom: ") != 1) {
            MsgBox("Only custom functions can be deleted.", "Built-in Function", "Icon!")
            return false
        }

        deletionState := this.CaptureCustomDeletionState(funcName, selectorGui)
        if !deletionState {
            this.NotifyUser(
                "The selected custom function changed. Reopen Add Function before deleting it.",
                "Function Changed",
                "Icon!"
            )
            return false
        }

        if this.ConfirmDestructiveAction(
            "Are you sure you want to delete the custom function '" funcName "'?",
            "Confirm Delete"
        ) {
            if !this.CustomDeletionStateIsCurrent(deletionState, selectorGui) {
                this.NotifyUser(
                    "The selected custom function changed while confirmation was open. Reopen Add Function before deleting it.",
                    "Function Changed",
                    "Icon!"
                )
                return false
            }

            if !this.BeginProfileMutationTransaction("delete a custom function")
                return false
            try {
                if !this.CustomDeletionStateIsCurrent(deletionState, selectorGui) {
                    this.NotifyUser(
                        "The selected custom function changed before deletion began. Reopen Add Function before deleting it.",
                        "Function Changed",
                        "Icon!"
                    )
                    return false
                }

                profileName := deletionState.profileName
                originalProfile := ProfileManager.profiles[profileName]
                candidate := ProfileManager.CloneProfile(originalProfile)

                ; Remove from a candidate and publish it only after the atomic file save.
                candidate.customFuncs.Delete(funcName)

                ; Remove from current profile's bindings if it exists
                if (candidate.binds.Has(funcName)) {
                    candidate.binds.Delete(funcName)
                }
                if (candidate.scopes.Has(funcName)) {
                    candidate.scopes.Delete(funcName)
                }

                ; Prove that every old native variant can be retired and every remaining
                ; bind can be registered before changing the file, live profile, or UI.
                if !this.ApplyProfileCandidate(candidate, originalProfile, "custom-function deletion")
                    return false

                if !this.CustomDeletionStateIsCurrent(deletionState, selectorGui) {
                    this.RestoreRuntimeAndNotify(
                        originalProfile,
                        "The selected custom function changed before deletion completed. The previous profile was retained.",
                        "Function Changed"
                    )
                    return false
                }

                try ProfileManager.SaveProfile(profileName, candidate)
                catch as err {
                    AppLog.Write("Custom function deletion could not be saved: " ErrorText.Describe(err))
                    message := "The custom function could not be deleted. The previous profile was left unchanged.`n`n" err.Message
                    this.RestoreRuntimeAndNotify(originalProfile, message, "Delete Failed")
                    return false
                }
                ProfileManager.profiles[profileName] := candidate
                this.ClearProfileDirty(profileName)
            } finally this.EndProfileMutationTransaction()

            ; The candidate was already applied transactionally above. Rebuilding the
            ; window must not tear it down and create a second failure boundary.
            selectorGui.Destroy()
            this.gui.Destroy()
            this.CreateMainGUI(false)

            ; Reopen Add Function only after releasing the publication boundary.
            for ctrl in this.gui {
                if (ctrl.Type = "ListView") {
                    this.ShowAddFunctionDialog(ctrl)
                    break
                }
            }
            return true
        }
        return false
    }

    ShowCustomKeybindDialog(listView, profileName := "") {
        customGui := this.NewProfileDialog("PACS Assistant - Configure Custom Keybind", profileName)
        width := 360
        UITheme.AddHeading(customGui, "Create a custom keybind", "xm ym w" width)
        UITheme.AddNote(customGui, "Sends keys or text when you press its keybind.", "xm y+4 w" width)

        customGui.Add("Text", "xm y+14 w" width, "&Name")
        nameEdit := customGui.Add("Edit", "xm y+4 r1 w" width)
        UITheme.SetPlaceholder(nameEdit, "For example, Normal chest")

        customGui.Add("Text", "xm y+12 w" width, "&Keys to send")
        keysEdit := customGui.Add("Edit", "xm y+4 r1 w" width)
        UITheme.SetPlaceholder(keysEdit, "{F9}, ^c or text to type")
        UITheme.AddNote(
            customGui,
            "AutoHotkey Send syntax: {Tab} presses Tab, ^c presses Ctrl+C, and other text is typed as written.",
            "xm y+4 w" width
        )

        customGui.Add("Text", "xm y+12 w" width, "&Target window (optional)")
        windowEdit := customGui.Add("Edit", "xm y+4 r1 w" width)
        UITheme.SetPlaceholder(windowEdit, "Whichever window is active")
        UITheme.AddNote(
            customGui,
            "An AutoHotkey window selector, such as a title or ahk_exe app.exe. The keybind does nothing unless exactly one window matches.",
            "xm y+4 w" width
        )

        cancel := (*) => customGui.Destroy()
        UITheme.AddFooter(customGui, width, [
            {text: "Create", action: (*) => this.AddCustomKeybind(nameEdit.Value, keysEdit.Value, windowEdit.Value, listView, customGui), default: true},
            {text: "Cancel", action: cancel}
        ])
        ; The title-bar X must destroy like Cancel; Close only hides by default.
        customGui.OnEvent("Close", cancel)
        customGui.OnEvent("Escape", cancel)

        UITheme.ShowDialog(customGui)
        return true
    }

    AddCustomKeybind(name, keys, window, listView, customGui) {
        if !this.ProfileMutationAllowed("create a custom keybind")
            return false
        if !this.DialogProfileIsCurrent(customGui)
            return false
        profileName := customGui.profileName

        name := Trim(name)
        if (name = "") {
            MsgBox("Please enter a name for the keybind.", "Invalid Custom Keybind", "Icon!")
            return false
        }
        if (keys = "") {
            MsgBox("Please enter keys to send.", "Invalid Custom Keybind", "Icon!")
            return false
        }
        ; A blank-looking window would match no window, so the command would never run.
        if (window != "" && Trim(window, " `t") = "") {
            MsgBox("Leave the target window empty to send to any window, or enter a window title.", "Invalid Custom Keybind", "Icon!")
            return false
        }

        ; Create unique function name
        funcName := "Custom: " name
        if !ProfileManager.IsSafeIniKey(funcName) {
            MsgBox("The keybind name cannot contain |, =, square brackets, or line breaks.", "Invalid Custom Keybind", "Icon!")
            return false
        }

        ; Check if name already exists in current profile
        currentProfile := ProfileManager.profiles[profileName]
        if !this.CustomFunctionNameAvailable(currentProfile, funcName) {
            MsgBox("A keybind with this name already exists in this profile.", "Invalid Custom Keybind", "Icon!")
            return false
        }

        if !this.BeginProfileMutationTransaction("create a custom keybind")
            return false
        row := 0
        try {
            if (!this.DialogProfileIsCurrent(customGui)
                || !this.CustomFunctionNameAvailable(
                    ProfileManager.profiles[profileName],
                    funcName
                ))
                return false
            currentProfile := ProfileManager.profiles[profileName]
            try {
                ; Persist configuration only. ApplyBinds creates the runtime callback
                ; at the application boundary.
                currentProfile.customFuncs[funcName] := {keys: keys, window: window}
                currentProfile.binds[funcName] := ""
                currentProfile.scopes[funcName] := "Any"
                row := this.AddFunctionRow(listView, funcName, "Unassigned", "Any window")
                this.ResizeColumns(listView)
                this.MarkProfileDirty(profileName)
            } catch Any {
                if currentProfile.customFuncs.Has(funcName)
                    currentProfile.customFuncs.Delete(funcName)
                if currentProfile.binds.Has(funcName)
                    currentProfile.binds.Delete(funcName)
                if currentProfile.scopes.Has(funcName)
                    currentProfile.scopes.Delete(funcName)
                if row
                    try listView.Delete(row)
                throw
            }
        } finally this.EndProfileMutationTransaction()

        customGui.Destroy()

        ; Prompt user to set the keybind
        this.PromptKeybind(funcName, listView, profileName)
        return true
    }

    CustomFunctionNameAvailable(profile, funcName) {
        return !ProfileManager.HasIniKeyIdentity(profile.binds, funcName)
            && !ProfileManager.HasIniKeyIdentity(profile.customFuncs, funcName)
    }

    /**
     * Add Function's Add All: adds every built-in command the profile does not
     * have, unassigned and active in any window, in one change. Nothing is bound,
     * so no key capture follows; the keys are set from the list.
     * @returns whether any command was added
     */
    AddAllFunctions(listView, selectorGui) {
        if !this.ProfileMutationAllowed("add functions")
            return false
        if !this.DialogProfileIsCurrent(selectorGui)
            return false
        if !this.BeginProfileMutationTransaction("add functions")
            return false
        added := []
        rows := []
        try {
            if !this.DialogProfileIsCurrent(selectorGui)
                return false
            profileName := selectorGui.profileName
            profile := ProfileManager.profiles[profileName]
            try {
                for funcName, _ in PACSCommands.commands {
                    if ProfileManager.HasIniKeyIdentity(profile.binds, funcName)
                        continue
                    profile.binds[funcName] := ""
                    profile.scopes[funcName] := "Any"
                    added.Push(funcName)
                    rows.Push(this.AddFunctionRow(listView, funcName, "Unassigned", "Any window"))
                }
                if added.Length {
                    this.ResizeColumns(listView)
                    this.MarkProfileDirty(profileName)
                }
            } catch Any {
                for funcName in added {
                    profile.binds.Delete(funcName)
                    profile.scopes.Delete(funcName)
                }
                ; Newest first, so earlier row numbers stay valid.
                loop rows.Length
                    try listView.Delete(rows[rows.Length - A_Index + 1])
                throw
            }
        } finally this.EndProfileMutationTransaction()
        selectorGui.Destroy()
        return added.Length > 0
    }

    AddFunction(funcName, listView, selectorGui) {
        if !this.ProfileMutationAllowed("add a function")
            return false
        if !this.DialogProfileIsCurrent(selectorGui)
            return false

        if (funcName = "") {
            MsgBox("Please select a function first.", "No Function Selected", "Icon!")
            return false
        }

        profileName := selectorGui.profileName
        profile := ProfileManager.profiles[profileName]
        stillAvailable := !ProfileManager.HasIniKeyIdentity(profile.binds, funcName)
            && (PACSCommands.commands.Has(funcName) || profile.customFuncs.Has(funcName))
        if !stillAvailable {
            selectorGui.Destroy()
            MsgBox(
                "The selected function changed while this dialog was open. Reopen Add Function before making another change.",
                "Function List Changed",
                "Icon!"
            )
            return false
        }

        if !this.BeginProfileMutationTransaction("add a function")
            return false
        row := 0
        try {
            if !this.DialogProfileIsCurrent(selectorGui)
                return false
            profile := ProfileManager.profiles[profileName]
            stillAvailable := !ProfileManager.HasIniKeyIdentity(profile.binds, funcName)
                && (PACSCommands.commands.Has(funcName) || profile.customFuncs.Has(funcName))
            if !stillAvailable
                return false
            try {
                profile.binds[funcName] := ""
                profile.scopes[funcName] := "Any"
                row := this.AddFunctionRow(listView, funcName, "Unassigned", "Any window")
                this.ResizeColumns(listView)
                this.MarkProfileDirty(profileName)
            } catch Any {
                if profile.binds.Has(funcName)
                    profile.binds.Delete(funcName)
                if profile.scopes.Has(funcName)
                    profile.scopes.Delete(funcName)
                if row
                    try listView.Delete(row)
                throw
            }
        } finally this.EndProfileMutationTransaction()

        selectorGui.Destroy()

        ; Prompt user to set the keybind
        this.PromptKeybind(funcName, listView, profileName)
        return true
    }

    RemoveFunction(listView) {
        if !this.ProfileMutationAllowed("remove a function")
            return false
        removalState := this.CaptureFunctionRemovalState(listView)
        if !removalState {
            MsgBox("Please select a function to remove.", "No Function Selected", "Icon!")
            return false
        }

        funcName := removalState.functionName
        if this.ConfirmDestructiveAction(
            "Remove '" funcName "' from the profile?",
            "Confirm Remove"
        ) {
            if !this.FunctionRemovalStateIsCurrent(removalState, listView) {
                this.NotifyUser(
                    "The selected function changed while confirmation was open. Reopen the removal prompt before making another change.",
                    "Function Changed",
                    "Icon!"
                )
                return false
            }

            if !this.BeginProfileMutationTransaction("remove a function")
                return false
            try {
                if !this.FunctionRemovalStateIsCurrent(removalState, listView)
                    return false
                profileName := removalState.profileName
                originalProfile := ProfileManager.profiles[profileName]
                candidate := ProfileManager.CloneProfile(originalProfile)
                candidate.binds.Delete(funcName)
                if candidate.scopes.Has(funcName)
                    candidate.scopes.Delete(funcName)

                if !this.ApplyProfileCandidate(candidate, originalProfile, "function removal")
                    return false

                if !this.FunctionRemovalStateIsCurrent(removalState, listView) {
                    this.RestoreRuntimeAndNotify(
                        originalProfile,
                        "The selected function changed before removal completed. The previous profile was retained.",
                        "Function Changed"
                    )
                    return false
                }

                try listView.Delete(removalState.row)
                catch as err {
                    this.RestoreRuntimeAndNotify(
                        originalProfile,
                        "The function row could not be removed, so the previous profile was retained.`n`n" err.Message,
                        "Function Removal Failed"
                    )
                    return false
                }
                ; Removing a row unbinds a custom function but keeps its definition;
                ; DeleteCustomFunction removes the definition.
                ProfileManager.profiles[profileName] := candidate
                this.MarkProfileDirty(profileName)
                try this.ResizeColumns(listView)
                return true
            } finally this.EndProfileMutationTransaction()
        }
        return false
    }

    ChangeSelectedKeybind(listView) {
        if (listView.GetNext(0) = 0) {
            MsgBox("Please select a function to change.", "No Function Selected", "Icon!")
            return false
        }

        funcName := listView.GetText(listView.GetNext(0), 1)
        return this.PromptKeybind(funcName, listView)
    }

    PromptKeybind(funcName, listView, profileName := "") {
        if KeybindGUI.isListening {
            MsgBox("Already waiting for a keybind. Finish or cancel that one first.", "Keybind In Progress", "Icon!")
            return false
        }

        promptGui := this.NewProfileDialog("PACS Assistant - Set Keybind", profileName)
        width := 380
        UITheme.AddHeading(promptGui, "Press the new keybind", "xm ym w" width)
        UITheme.AddNote(
            promptGui,
            "For '" funcName "'. Current keybind: " this.CurrentBindLabel(promptGui.profileName, funcName) ".",
            "xm y+4 w" width
        )
        ; 0x200 (SS_CENTERIMAGE) centres the single line vertically in the well.
        promptGui.SetFont("s12", UITheme.headingFontName)
        promptGui.keyWell := promptGui.Add("Text", "xm y+14 w" width " h56 Center 0x200 Background" UITheme.panelColor, "")
        UITheme.UseBodyFont(promptGui)
        ; One area for guidance, then for the captured key's warnings; four lines
        ; tall so the window keeps its size.
        promptGui.message := UITheme.AddNote(promptGui, "", "xm y+10 w" width " r4")
        cancel := (*) => this.CancelKeybindPrompt(promptGui)
        footer := UITheme.AddFooter(promptGui, width, [
            {text: "&Use Keybind", width: 112, default: true, action: (*) => this.UseCapturedKey(funcName, listView, promptGui)},
            {text: "&Try Again", action: (*) => this.RetryCapture(funcName, listView, promptGui)},
            {text: "Cancel", action: cancel}
        ])
        promptGui.useButton := footer["&Use Keybind"]
        promptGui.retryButton := footer["&Try Again"]
        promptGui.showCapturedKey := (newBind) => this.ShowCapturedKey(funcName, listView, promptGui, newBind)
        this.ResetCapturePrompt(promptGui)
        ; While a key is being captured the hook takes Esc itself; afterwards Esc
        ; reaches the window.
        promptGui.OnEvent("Escape", cancel)

        ; Closing with the X has to tear the hook down as well, otherwise it keeps
        ; capturing and rebinds the next key pressed anywhere
        ; Return true: when the hook cannot be stopped the prompt must stay open.
        promptGui.OnEvent("Close", (*) => (this.CancelKeybindPrompt(promptGui), true))

        if !this.CaptureFunctionDialogState(promptGui, funcName, listView) {
            promptGui.Destroy()
            MsgBox(
                "The selected function could not be verified. Refresh the profile and try again.",
                "Function Not Available",
                "Icon!"
            )
            return false
        }

        if !this.BeginListening(funcName, listView, promptGui) {
            ; A refusal can leave an earlier capture lease held. This new prompt
            ; has never owned its hook and must not remain as a hidden window.
            try promptGui.Destroy()
            return false
        }

        return this.ShowStartedCapturePrompt(promptGui)
    }

    ; The capture prompt waiting for a key: nothing to use yet.
    ResetCapturePrompt(promptGui) {
        promptGui.keyWell.SetFont("c" UITheme.secondaryColor)
        promptGui.keyWell.Value := "Waiting for a key..."
        this.SetCaptureMessage(promptGui, "Hold Ctrl, Alt, Shift or Win, then press the key. Esc cancels.", false)
        promptGui.useButton.Enabled := false
        promptGui.retryButton.Enabled := false
    }

    SetCaptureMessage(promptGui, text, isWarning) {
        promptGui.message.SetFont("c" (isWarning ? UITheme.warningColor : UITheme.secondaryColor))
        promptGui.message.Value := text
    }

    /**
     * Shows a captured key and waits for Use Keybind or Try Again. A key another
     * function already has cannot be used; any other warning (a key that types,
     * one PowerScribe uses, a common shortcut) is advice.
     */
    ShowCapturedKey(funcName, listView, promptGui, newBind) {
        if !this.FunctionDialogIsCurrent(promptGui, funcName, listView)
            return false
        profile := ProfileManager.profiles[promptGui.profileName]
        owner := this.FindProfileBindingOwner(profile, newBind, funcName)
        if (owner != "")
            warnings := ["'" owner "' already uses this keybind. Try another key."]
        else
            warnings := CommandInfo.KeyWarnings(newBind, profile.scopes.Has(funcName) ? profile.scopes[funcName] : "Any")
        message := ""
        for warning in warnings {
            if (A_Index <= 2)
                message .= (message = "" ? "" : " ") warning
        }
        promptGui.capturedBind := newBind
        promptGui.keyWell.SetFont("c" UITheme.textColor)
        promptGui.keyWell.Value := this.PrettifyHotkey(newBind)
        if (message = "")
            this.SetCaptureMessage(promptGui, "Use this keybind, or press Try Again for a different one.", false)
        else
            this.SetCaptureMessage(promptGui, message, true)
        promptGui.useButton.Enabled := owner = ""
        promptGui.retryButton.Enabled := true
        (owner = "" ? promptGui.useButton : promptGui.retryButton).Focus()
        return true
    }

    UseCapturedKey(funcName, listView, promptGui) {
        if !HasProp(promptGui, "capturedBind")
            return false
        if !this.FunctionDialogIsCurrent(promptGui, funcName, listView)
            return false
        return this.CommitCapturedKey(funcName, listView, promptGui, promptGui.capturedBind)
    }

    ; Discards the captured key and listens for another.
    RetryCapture(funcName, listView, promptGui) {
        if !this.FunctionDialogIsCurrent(promptGui, funcName, listView)
            return false
        try this.StopListening()
        catch as err {
            this.NotifyUser(
                "Key capture could not be restarted, and may still be active. Keep this dialog open and restart PACS Assistant before relying on its shortcuts.`n`n" err.Message,
                "Capture Stop Failed - Restart Required",
                "Icon!"
            )
            return false
        }
        KeybindGUI.isListening := true
        try this.StartInputHook(funcName, listView, promptGui)
        catch Any as err {
            this.CancelKeybindPrompt(promptGui)
            throw err
        }
        if HasProp(promptGui, "capturedBind")
            promptGui.DeleteProp("capturedBind")
        this.ResetCapturePrompt(promptGui)
        return true
    }

    ; Display form of a function's current keybind, for the capture prompt.
    CurrentBindLabel(profileName, funcName) {
        try {
            profile := ProfileManager.profiles[profileName]
            if profile.binds.Has(funcName)
                return this.PrettifyHotkey(profile.binds[funcName])
        }
        return "Unassigned"
    }

    ShowStartedCapturePrompt(promptGui) {
        try {
            UITheme.ShowDialog(promptGui)
            return true
        } catch as err {
            restored := this.CancelKeybindPrompt(promptGui)
            if restored {
                this.NotifyUser(
                    "The key-capture window could not be shown. Input capture was stopped and the previous shortcuts were restored.`n`n" err.Message,
                    "Key Capture Could Not Start",
                    "Icon!"
                )
            }
            return false
        }
    }

    ; Sizes the Function and Keybind columns to their contents (never narrower than a
    ; readable minimum) and gives the Active In column the rest of the list's width,
    ; measured inside any vertical scrollbar, so the list never scrolls sideways.
    ResizeColumns(listView) {
        if !HasProp(listView, "Hwnd") {
            ; A test's stand-in list has no window to measure.
            loop 3
                listView.ModifyCol(A_Index, "AutoHdr")
            return
        }
        UITheme.FillColumns(listView, [200, 140])  ; Function, Keybind; Active In fills
    }

    ; How a bind's window scope reads in the ListView
    ScopeLabel(funcName) {
        scope := ProfileManager.GetScope(funcName)
        return scope = "Any" ? "Any window" : scope
    }

    ShowScopeDialog(listView) {
        if !this.ProfileMutationAllowed("change a keybind scope")
            return false
        if (listView.GetNext(0) = 0) {
            MsgBox("Please select a function first.", "No Function Selected", "Icon!")
            return false
        }

        rowIndex := listView.GetNext(0)
        funcName := listView.GetText(rowIndex, 1)
        flags := HotkeyContract.FlagsFromScope(ProfileManager.GetScope(funcName))

        scopeGui := this.NewProfileDialog("PACS Assistant - Keybind Scope")
        width := 340
        UITheme.AddHeading(scopeGui, "Where should this keybind work?", "xm ym w" width)
        UITheme.AddNote(
            scopeGui,
            "'" funcName "' (" this.CurrentBindLabel(scopeGui.profileName, funcName) ")",
            "xm y+4 w" width
        )
        restricted := flags.requirePACS || flags.requirePowerScribe
        anyRadio := scopeGui.Add("Radio", "xm y+14 w" width " Group" (restricted ? "" : " Checked"), "In &any window")
        onlyRadio := scopeGui.Add("Radio", "xm y+8 w" width (restricted ? " Checked" : ""), "&Only when one of these is the active window:")
        pacsBox := scopeGui.Add("Checkbox", "xm+22 y+8 w" (width - 22), "&PACS")
        pacsBox.Value := flags.requirePACS
        psBox := scopeGui.Add("Checkbox", "xm+22 y+6 w" (width - 22), "Power&Scribe")
        psBox.Value := flags.requirePowerScribe
        UITheme.AddNote(
            scopeGui,
            "Outside these windows the key goes to whichever app is in front, as if this keybind did not exist.",
            "xm y+14 w" width
        )
        syncChoices := (*) => (pacsBox.Enabled := onlyRadio.Value, psBox.Enabled := onlyRadio.Value)
        anyRadio.OnEvent("Click", syncChoices)
        onlyRadio.OnEvent("Click", syncChoices)
        syncChoices()

        if !this.CaptureFunctionDialogState(scopeGui, funcName, listView, rowIndex) {
            scopeGui.Destroy()
            MsgBox(
                "The selected function could not be verified. Refresh the profile and try again.",
                "Function Not Available",
                "Icon!"
            )
            return false
        }

        cancel := (*) => scopeGui.Destroy()
        UITheme.AddFooter(scopeGui, width, [
            {
                text: "OK",
                default: true,
                action: (*) => this.SubmitScope(
                    funcName, anyRadio.Value, pacsBox.Value, psBox.Value, listView, rowIndex, scopeGui
                )
            },
            {text: "Cancel", action: cancel}
        ])
        ; The title-bar X must destroy like Cancel; Close only hides by default.
        scopeGui.OnEvent("Close", cancel)
        scopeGui.OnEvent("Escape", cancel)
        UITheme.ShowDialog(scopeGui)
        return true
    }

    /**
     * The scope flags a choice in the scope dialog stands for: none for "any
     * window", else the ticked windows.
     * @returns {requirePACS, requirePowerScribe}, or 0 when "only these windows" was
     *     chosen without ticking any
     */
    static ScopeChoice(anyWindow, requirePACS, requirePowerScribe) {
        if anyWindow
            return {requirePACS: false, requirePowerScribe: false}
        if !(requirePACS || requirePowerScribe)
            return 0
        return {requirePACS: !!requirePACS, requirePowerScribe: !!requirePowerScribe}
    }

    SubmitScope(funcName, anyWindow, requirePACS, requirePowerScribe, listView, rowIndex, scopeGui) {
        choice := KeybindGUI.ScopeChoice(anyWindow, requirePACS, requirePowerScribe)
        if !choice {
            try scopeGui.Opt("+OwnDialogs")
            MsgBox("Tick PACS, PowerScribe or both, or choose In any window.", "Choose a Window", "Icon!")
            return false
        }
        return this.ApplyScope(funcName, choice.requirePACS, choice.requirePowerScribe, listView, rowIndex, scopeGui)
    }

    ApplyScope(funcName, requirePACS, requirePowerScribe, listView, rowIndex, scopeGui) {
        if !this.ProfileMutationAllowed("change a keybind scope")
            return false
        if !this.FunctionDialogIsCurrent(scopeGui, funcName, listView)
            return false

        if !this.BeginProfileMutationTransaction("change a keybind scope")
            return false
        try {
            if !this.FunctionDialogIsCurrent(scopeGui, funcName, listView)
                return false
            oldScope := ProfileManager.GetScope(funcName)
            newScope := HotkeyContract.ScopeFromFlags(requirePACS, requirePowerScribe)
            currentProfile := ProfileManager.profiles[scopeGui.profileName]
            changed := false

            try {
                ProfileManager.SetScope(funcName, newScope)
                changed := true
                listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
                this.ResizeColumns(listView)

                if !this.ApplyBinds() {
                    ProfileManager.SetScope(funcName, oldScope)
                    listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
                    this.ResizeColumns(listView)
                    this.RestoreRuntimeAndNotify(
                        currentProfile,
                        "The scope change was rejected and the previous profile value was retained.",
                        "Scope Recovery Failed",
                        false
                    )
                    return false
                }

                scopeGui.Destroy()
                this.MarkProfileDirty(scopeGui.profileName)
                return true
            } catch as err {
                if changed
                    ProfileManager.SetScope(funcName, oldScope)
                try listView.Modify(rowIndex,, funcName, listView.GetText(rowIndex, 2), this.ScopeLabel(funcName))
                try this.ResizeColumns(listView)
                try this.RestoreRuntimeAndNotify(
                    currentProfile,
                    "The scope change failed and the previous profile value was retained.",
                    "Scope Recovery Failed",
                    false
                )
                throw err
            }
        } finally this.EndProfileMutationTransaction()
    }

    ShowModalityAttendingsDialog() {
        if !this.ProfileMutationAllowed("edit attending assignments")
            return false
        if (ProfileManager.GetCurrentProfile() = 0) {
            MsgBox("Load a profile first.", "No Profile Loaded", "Icon!")
            return false
        }
        ; This dialog saves a complete profile snapshot. Force an explicit decision
        ; on pending keybind edits before capturing that snapshot.
        if !this.ResolveDirtyProfileBeforeLeaving(true)
            return false

        ; NewProfileDialog records the profile object and both revisions;
        ; DialogProfileIsCurrent rejects the save if any of them changed.
        modGui := this.NewProfileDialog("PACS Assistant - Modality Attendings")
        width := 360
        labelWidth := 90
        UITheme.AddHeading(modGui, "Modality attendings", "xm ym w" width)
        UITheme.AddNote(
            modGui,
            "The attending for each modality in '" modGui.profileName "'. Wet reads use the one for the study's modality; leave a modality blank to keep PowerScribe's default attending.",
            "xm y+4 w" width
        )

        edits := Map()
        first := true
        for modality in ReportModality.names {
            modGui.Add("Text", "xm y+" (first ? 16 : 10) " w" labelWidth, modality)
            attendingEdit := modGui.Add("Edit", "x+" UITheme.gap " yp-3 r1 w" (width - labelWidth - UITheme.gap), ProfileManager.GetModalityAttending(modality))
            UITheme.SetPlaceholder(attendingEdit, "PowerScribe default")
            edits[modality] := attendingEdit
            first := false
        }

        cancel := (*) => modGui.Destroy()
        UITheme.AddFooter(modGui, width, [
            {text: "Save", action: (*) => this.SaveModalityAttendings(edits, modGui), default: true},
            {text: "Cancel", action: cancel}
        ])
        ; The title-bar X must destroy like Cancel; Close only hides by default.
        modGui.OnEvent("Close", cancel)
        modGui.OnEvent("Escape", cancel)
        UITheme.ShowDialog(modGui)
        return true
    }

    SaveModalityAttendings(edits, modGui) {
        if !this.ProfileMutationAllowed("save attending assignments")
            return false
        if !this.DialogProfileIsCurrent(modGui)
            return false
        profileName := modGui.profileName
        if this.IsProfileDirty(profileName) {
            try modGui.Destroy()
            this.NotifyUser(
                "The profile has unsaved keybind changes. Save or discard them before saving attending assignments.",
                "Unsaved Profile Changes",
                "Icon!"
            )
            return false
        }
        candidate := ProfileManager.CloneProfile(ProfileManager.profiles[profileName])
        for modality, attendingEdit in edits {
            candidate.modalityAttendings[modality] := Trim(attendingEdit.Value)
        }

        if !this.BeginProfileMutationTransaction("save attending assignments")
            return false
        try {
            ; Revalidate after acquiring the serialization boundary. A callback may
            ; have run between the dialog checks and the transaction acquisition.
            if !this.DialogProfileIsCurrent(modGui)
                return false
            try ProfileManager.SaveProfile(profileName, candidate)
            catch as err {
                AppLog.Write("Attending assignments could not be saved: " ErrorText.Describe(err))
                this.NotifyUser("The attending assignments could not be saved. The previous file was left unchanged.`n`n" err.Message, "Save Failed", "Icon!")
                return false
            }
            ProfileManager.profiles[profileName] := candidate
            this.ClearProfileDirty(profileName)
        } finally this.EndProfileMutationTransaction()
        modGui.Destroy()
        return true
    }
}
