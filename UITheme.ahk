; = CONTENTS
;   + Preamble
;   + UITheme class (shared fonts, colors, spacing and the building blocks every
;       window is made from: heading, note, section label, footer button row)

#Requires AutoHotkey v2.0

#Include DarkMenuBar.ahk

/**
 * The one visual language of PACS Assistant's windows.
 *
 * Every window is built from the same type scale, spacing and footer so the app
 * reads as one product: a heading that says what the window is for, secondary notes
 * that explain consequences, and a separated button row with the primary action at
 * the right. Coordinates are logical (96 DPI) units; Gui's default DPIScale converts
 * them for the monitor.
 */
class UITheme {
    static fontName := "Segoe UI"
    static headingFontName := "Segoe UI Semibold"
    static fontSize := 9
    static headingSize := 12

    /**
     * The colors of each mode, as RGB hex. In light and dark, every text color is
     * 4.5:1 or more against the backgrounds it is drawn on (WCAG AA for body text;
     * UIThemeTest). High contrast uses Windows' own colors throughout ("Default"),
     * so the user's contrast theme decides them.
     */
    static palettes := Map(
        "light", {
            window: "FFFFFF", text: "1B1B1B", secondary: "5E5E5E", warning: "A35200",
            ok: "107C10", separator: "E1E1E1", panel: "F5F5F5", field: "FFFFFF",
            muted: "767676", error: "C42B1C"
        },
        "dark", {
            window: "202020", text: "E6E6E6", secondary: "A8A8A8", warning: "F2A65A",
            ok: "6CCB5F", separator: "3A3A3A", panel: "2B2B2B", field: "2B2B2B",
            muted: "9A9A9A", error: "FF99A4"
        },
        "contrast", {
            window: "Default", text: "Default", secondary: "Default", warning: "Default",
            ok: "Default", separator: "Default", panel: "Default", field: "Default",
            muted: "Default", error: "Default"
        }
    )
    ; "light", "dark" or "contrast", chosen by UpdateMode as each window is made.
    static mode := "light"
    ; The Theme setting: "Match Windows", "Light" or "Dark". Settings connects it.
    static themeSetting := (*) => "Light"
    static highContrastProbe := (*) => UITheme.HighContrastIsOn()
    static windowsDarkProbe := (*) => UITheme.WindowsAppsAreDark()

    static Color(name) => this.palettes[this.mode].%name%
    static windowColor => this.Color("window")
    static textColor => this.Color("text")
    static secondaryColor => this.Color("secondary")
    ; Amber for advice that needs attention.
    static warningColor => this.Color("warning")
    static okColor => this.Color("ok")
    static separatorColor => this.Color("separator")
    ; Fills read-only areas.
    static panelColor => this.Color("panel")

    ; A palette color as a GDI COLORREF (0xBBGGRR), or -1 in high contrast, where
    ; Windows' own colors apply.
    static ColorRef(name) => this.HexToColorRef(this.Color(name))

    static HexToColorRef(value) {
        if (value = "Default")
            return -1
        rgb := Integer("0x" value)
        return ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
    }

    /**
     * The mode for a Theme setting: high contrast whenever Windows has it on;
     * otherwise dark for "Dark", or for "Match Windows" while Windows apps are
     * dark; otherwise light.
     */
    static ModeFor(setting, windowsAppsDark, highContrast) {
        if highContrast
            return "contrast"
        if (setting = "Dark" || (setting = "Match Windows" && windowsAppsDark))
            return "dark"
        return "light"
    }

    ; Chooses the mode for the windows made from now on.
    ; @returns the mode
    static UpdateMode() {
        mode := this.ModeFor(this.themeSetting.Call(), this.windowsDarkProbe.Call(), this.highContrastProbe.Call())
        if (mode != this.mode) {
            this.mode := mode
            this.UseDarkMenus(mode = "dark")
        }
        return mode
    }

    static HighContrastIsOn() {
        ; HIGHCONTRAST: cbSize, dwFlags (HCF_HIGHCONTRASTON = 1), lpszDefaultScheme
        info := Buffer(8 + A_PtrSize, 0)
        NumPut("UInt", info.Size, info, 0)
        if !DllCall("SystemParametersInfo", "UInt", 0x42, "UInt", info.Size, "Ptr", info, "UInt", 0)
            return false
        return !!(NumGet(info, 4, "UInt") & 1)
    }

    static WindowsAppsAreDark() {
        try return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme") = 0
        return false
    }

    ; Dark drop-down, context and tray menus (uxtheme's undocumented
    ; SetPreferredAppMode and FlushMenuThemes, ordinals 135 and 136, Windows 10
    ; 1903 and later). Without them the menus simply stay light. Hover tooltips
    ; stay light either way.
    static UseDarkMenus(dark) {
        try {
            uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
            DllCall(DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr"), "Int", dark ? 2 : 0)
            DllCall(DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr"))
        }
    }

    ; Spacing scale: window edge to content, between related controls, between
    ; groups, and the standard button size.
    static margin := 20
    static gap := 8
    static sectionGap := 16
    static buttonWidth := 96
    static buttonHeight := 28

    /**
     * A new window in the app's style. Options and title are Gui's own.
     * @returns Gui
     */
    static NewWindow(title, options := "") {
        this.UpdateMode()
        ; DPI policy: default DPIScale ON - system-DPI-aware, auto-scaled.
        window := Gui(options, title)
        ; The mode it is built in: a window rebuilt for a theme change compares it.
        window.themeMode := this.mode
        this.Style(window)
        return window
    }

    ; Applies the shared background, margins and body font to an existing Gui.
    static Style(window) {
        window.BackColor := this.windowColor
        window.MarginX := this.margin
        window.MarginY := this.margin
        this.UseBodyFont(window)
        return window
    }

    ; The body font keeps the system text color: giving a Button, CheckBox, Radio,
    ; GroupBox or Tab a color of its own strips its Windows theme.
    static UseBodyFont(window) {
        window.SetFont("s" this.fontSize " norm cDefault", this.fontName)
    }

    ; The window's title line: what it is for, in the heading face.
    static AddHeading(window, text, options := "", size := 0) {
        return this.AddColoredText(window, text, options, this.textColor, size ? size : this.headingSize, this.headingFontName)
    }

    ; Secondary explanatory text. Give it a width so long notes wrap.
    static AddNote(window, text, options := "") {
        return this.AddColoredText(window, text, options, this.secondaryColor, this.fontSize, this.fontName)
    }

    ; A label that opens a group of related settings.
    static AddSectionLabel(window, text, options := "") {
        return this.AddColoredText(window, text, options, this.textColor, this.fontSize, this.headingFontName)
    }

    ; A Text control with its own color; ApplyTheme leaves such a control alone.
    static AddColoredText(window, text, options, color, size, face) {
        window.SetFont("s" size " norm c" color, face)
        try control := window.Add("Text", options, text)
        finally this.UseBodyFont(window)
        control.themed := true
        return control
    }

    ; A one-pixel rule: give it w1 or h1 in the options. In high contrast it is
    ; Windows' etched line, drawn in the contrast theme's colors.
    static AddSeparator(window, options) {
        ; SS_ETCHEDVERT for a vertical rule (w1), else SS_ETCHEDHORZ.
        if (this.mode = "contrast")
            return window.Add("Text", options (RegExMatch(options, "(^|\s)w1(\s|$)") ? " 0x11" : " 0x10"))
        return window.Add("Text", options " Background" this.separatorColor)
    }

    /**
     * Gives a built window the current mode's look where creation could not. In
     * dark mode: the title bar and menu bar, each control's dark Windows theme, and
     * light text on plain Text controls, fields and lists. Light and high contrast
     * need nothing more. Call it once the controls are added, before showing.
     */
    static ApplyTheme(window) {
        dark := this.mode = "dark"
        ; DWMWA_USE_IMMERSIVE_DARK_MODE: the title bar.
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", window.Hwnd, "Int", 20, "Int*", dark, "Int", 4)
        if dark && window.MenuBar
            DarkMenuBar.Attach(window.Hwnd)
        else
            DarkMenuBar.Detach(window.Hwnd)
        if !dark
            return window
        for ctrl in window
            this.ApplyDarkTheme(ctrl)
        return window
    }

    static ApplyDarkTheme(ctrl) {
        switch ctrl.Type, false {
            case "Button":
                this.SetControlTheme(ctrl, "DarkMode_Explorer")
            case "CheckBox", "Radio":
                ; Windows 11's dark theme draws these with light text.
                this.SetControlTheme(ctrl, "DarkMode_DarkTheme")
            case "Edit":
                ctrl.Opt("+Background" this.Color("field"))
                ctrl.SetFont("c" this.textColor)
                ; ES_MULTILINE: dark scrollbars; a one-line field: a dark frame.
                this.SetControlTheme(ctrl, ControlGetStyle(ctrl) & 0x4 ? "DarkMode_Explorer" : "DarkMode_CFD")
            case "DDL", "ComboBox":
                this.SetControlTheme(ctrl, "DarkMode_CFD")
            case "ListBox":
                ctrl.Opt("+Background" this.Color("field"))
                ctrl.SetFont("c" this.textColor)
                this.SetControlTheme(ctrl, "DarkMode_Explorer")
            case "ListView":
                ; DarkMode_Explorer draws group headers navy on black; the dark
                ; ItemsView theme draws them light (its scrollbar stays light).
                grouped := SendMessage(0x10AF, 0, 0, ctrl)  ; LVM_ISGROUPVIEWENABLED
                this.SetControlTheme(ctrl, grouped ? "DarkMode_ItemsView" : "DarkMode_Explorer")
                background := this.ColorRef("window")
                SendMessage(0x1001, 0, background, ctrl)  ; LVM_SETBKCOLOR
                SendMessage(0x1026, 0, background, ctrl)  ; LVM_SETTEXTBKCOLOR
                SendMessage(0x1024, 0, this.ColorRef("text"), ctrl)  ; LVM_SETTEXTCOLOR
                header := SendMessage(0x101F, 0, 0, ctrl)  ; LVM_GETHEADER
                if header
                    DllCall("uxtheme\SetWindowTheme", "Ptr", header, "Str", "DarkMode_ItemsView", "Ptr", 0)
            case "Text":
                if !HasProp(ctrl, "themed")
                    ctrl.SetFont("c" this.textColor)
        }
    }

    /**
     * Copies what has been entered in a window into its rebuilt copy. Both were
     * built by the same code, so their controls pair up in order; if they do not,
     * nothing is copied.
     * @returns whether the values were copied
     */
    static CopyInputs(source, target) {
        sources := [], targets := []
        for ctrl in source
            sources.Push(ctrl)
        for ctrl in target
            targets.Push(ctrl)
        if (sources.Length != targets.Length)
            return false
        for index, ctrl in sources {
            if (ctrl.Type != targets[index].Type)
                return false
        }
        for index, ctrl in sources {
            if (ctrl.Type ~= "i)^(CheckBox|Radio|Edit|DDL|ComboBox|ListBox)$")
                targets[index].Value := ctrl.Value
        }
        return true
    }

    static SetControlTheme(ctrl, name) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", name, "Ptr", 0)
    }

    /**
     * Adds the footer: a rule across the full window width, then the buttons, with
     * the right-hand group aligned to the content's right edge. Each button is
     * {text, action, width?, default?}; the right-hand group is listed left to right,
     * so the primary action goes last.
     *
     * The rule is placed sectionGap below the lowest control added so far, so add
     * the footer after all other content.
     * @returns Map of button text to its control
     */
    static AddFooter(window, contentWidth, rightButtons, leftButtons := []) {
        bottom := this.ContentBottom(window)
        ruleY := bottom + this.sectionGap
        this.AddSeparator(window, "x0 y" ruleY " w" (contentWidth + 2 * this.margin) " h1")
        buttonY := ruleY + 1 + 12
        buttons := Map()

        x := this.margin
        for spec in leftButtons {
            buttons[spec.text] := this.AddFooterButton(window, spec, x, buttonY)
            x += this.SpecWidth(spec) + this.gap
        }

        total := 0
        for spec in rightButtons
            total += this.SpecWidth(spec) + (A_Index > 1 ? this.gap : 0)
        x := this.margin + contentWidth - total
        for spec in rightButtons {
            buttons[spec.text] := this.AddFooterButton(window, spec, x, buttonY)
            x += this.SpecWidth(spec) + this.gap
        }
        window.contentWidth := contentWidth
        return buttons
    }

    static SpecWidth(spec) => HasProp(spec, "width") ? spec.width : this.buttonWidth

    static AddFooterButton(window, spec, x, y) {
        options := "x" x " y" y " w" this.SpecWidth(spec) " h" this.buttonHeight
        if (HasProp(spec, "default") && spec.default)
            options .= " Default"
        button := window.Add("Button", options, spec.text)
        button.OnEvent("Click", spec.action)
        return button
    }

    ; Lowest bottom edge of the controls added so far, in logical units.
    static ContentBottom(window) {
        bottom := 0
        for ctrl in window {
            ctrl.GetPos(, &y,, &h)
            bottom := Max(bottom, y + h)
        }
        return bottom
    }

    /**
     * Shows a dialog built with AddFooter at its content width; the height follows
     * the content. Extra Show options (such as a position) may be appended.
     */
    static ShowDialog(window, options := "") {
        width := HasProp(window, "contentWidth") ? window.contentWidth + 2 * this.margin : 0
        this.ApplyTheme(window)
        window.Show(Trim((width ? "w" width " " : "") options))
        return window
    }

    /**
     * Sizes a report ListView's columns to their contents, each at least its
     * minimum (logical units), and gives the last column the rest of the list's
     * width inside any vertical scrollbar, so the list never scrolls sideways.
     */
    static FillColumns(listView, minimums) {
        scale := A_ScreenDPI / 96
        used := 0
        for index, minimum in minimums {
            listView.ModifyCol(index, "AutoHdr")
            ; LVM_GETCOLUMNWIDTH and LVM_SETCOLUMNWIDTH work in pixels.
            width := Max(SendMessage(0x101D, index - 1, 0, listView), Round(minimum * scale))
            SendMessage(0x101E, index - 1, width, listView)
            used += width
        }
        ; Not auto-sized first: a last column wider than the list adds a sideways
        ; scrollbar that stays.
        rect := Buffer(16, 0)
        DllCall("GetClientRect", "Ptr", listView.Hwnd, "Ptr", rect)
        fill := Max(NumGet(rect, 8, "Int") - used, Round(100 * scale))
        SendMessage(0x101E, minimums.Length, fill, listView)
    }

    ; The modern list look (hover highlight, rounded selection) used by Explorer.
    static UseExplorerTheme(ctrl) {
        DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "Explorer", "Ptr", 0)
    }

    ; Scrolls a one-line Edit to the end of its text, so a long path shows its file
    ; name (EM_SETSEL to the end, then EM_SCROLLCARET).
    static ShowEnd(edit) {
        length := StrLen(edit.Value)
        SendMessage(0xB1, length, length, edit)
        SendMessage(0xB7, 0, 0, edit)
    }

    ; Grey placeholder text shown while an Edit is empty (EM_SETCUEBANNER).
    static SetPlaceholder(edit, text) {
        SendMessage(0x1501, true, StrPtr(text), edit)
    }
}
