; = CONTENTS
;   + Preamble
;   + UITheme class (shared fonts, colors, spacing and the building blocks every
;       window is made from: heading, note, section label, footer button row)

#Requires AutoHotkey v2.0

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

    ; Colors on the white window. Secondary text keeps at least 4.5:1 contrast
    ; against white (WCAG AA for body text); panelColor fills read-only areas.
    static windowColor := "FFFFFF"
    static textColor := "1B1B1B"
    static secondaryColor := "5E5E5E"
    ; Amber for advice that needs attention: 5.6:1 against white.
    static warningColor := "A35200"
    static separatorColor := "E1E1E1"
    static panelColor := "F5F5F5"

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
        ; DPI policy: default DPIScale ON - system-DPI-aware, auto-scaled.
        window := Gui(options, title)
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
        window.SetFont("s" (size ? size : this.headingSize) " norm c" this.textColor, this.headingFontName)
        try heading := window.Add("Text", options, text)
        finally this.UseBodyFont(window)
        return heading
    }

    ; Secondary explanatory text. Give it a width so long notes wrap.
    static AddNote(window, text, options := "") {
        window.SetFont("s" this.fontSize " norm c" this.secondaryColor, this.fontName)
        try note := window.Add("Text", options, text)
        finally this.UseBodyFont(window)
        return note
    }

    ; A label that opens a group of related settings.
    static AddSectionLabel(window, text, options := "") {
        window.SetFont("s" this.fontSize " norm c" this.textColor, this.headingFontName)
        try label := window.Add("Text", options, text)
        finally this.UseBodyFont(window)
        return label
    }

    ; A one-pixel rule: give it w1 or h1 in the options.
    static AddSeparator(window, options) {
        return window.Add("Text", options " Background" this.separatorColor)
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
            if (ctrl.Type = "StatusBar")
                continue
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
        window.Show(Trim((width ? "w" width " " : "") options))
        return window
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
