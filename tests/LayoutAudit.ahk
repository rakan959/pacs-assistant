#Requires AutoHotkey v2.0

/**
 * Geometry checks for a built window, run by run-ui-audit.ahk.
 *
 * A layout that looks right at one display scaling can break at another: text is
 * measured in the font's own pixels, so a label that fits at 125% can wrap or clip
 * at 150%, and a fixed-height area can then push a control onto the buttons (as in
 * the Settings window of issue #13). Problems() checks a window's controls at every
 * scaling in `dpis`, measuring each label with the control's real font at that size.
 */
class LayoutAudit {
    static dpis := [96, 120, 144, 168, 192]

    /**
     * Every layout problem in a shown window: a control outside the client area,
     * two controls overlapping, a label that does not fit its control at one of
     * the scalings, or two controls or menus with the same access key.
     * @returns Array of descriptions, empty when the layout is sound
     */
    static Problems(window) {
        problems := []
        window.GetClientPos(,, &clientWidth, &clientHeight)
        items := []
        for ctrl in window {
            if !ctrl.Visible
                continue
            ctrl.GetPos(&x, &y, &w, &h)
            items.Push({ctrl: ctrl, x: x, y: y, w: w, h: h})
        }

        for item in items {
            ; One logical unit of slack: positions are rounded at non-100% scaling.
            if (item.x < 0 || item.y < 0
                || item.x + item.w > clientWidth + 1 || item.y + item.h > clientHeight + 1)
                problems.Push(this.Name(item) " extends outside the window ("
                    . item.x "," item.y " " item.w "x" item.h " in " clientWidth "x" clientHeight ")")
        }

        for index, first in items {
            loop items.Length - index {
                second := items[index + A_Index]
                overlapWidth := Min(first.x + first.w, second.x + second.w) - Max(first.x, second.x)
                overlapHeight := Min(first.y + first.h, second.y + second.h) - Max(first.y, second.y)
                if (overlapWidth > 1 && overlapHeight > 1)
                    problems.Push(this.Name(first) " overlaps " this.Name(second))
            }
        }

        for item in items {
            problem := this.TextProblem(item)
            if (problem != "")
                problems.Push(problem)
            ; A list's columns are sized to fit it (UITheme.FillColumns); a sideways
            ; scrollbar means they do not.
            if (item.ctrl.Type = "ListView" && ControlGetStyle(item.ctrl) & 0x100000)  ; WS_HSCROLL
                problems.Push(this.Name(item) " scrolls sideways: its columns are wider than the list")
            ; An Edit given text longer than its width, without r1, is built as a
            ; wrapping multi-line box a few lines tall: a one-line field that turns
            ; into a scrolling block once its value is long. The app's only
            ; intended multi-line box, the release notes, is ten lines.
            if (item.ctrl.Type = "Edit" && ControlGetStyle(item.ctrl) & 0x4) {  ; ES_MULTILINE
                line := this.Measure("Ag", this.FontOf(item.ctrl), A_ScreenDPI).h
                if (item.h * A_ScreenDPI / 96 < line * 5)
                    problems.Push(this.Name(item) " is a multi-line box under five lines tall; a one-line field needs r1")
            }
        }
        for problem in this.AccessKeyProblems(window, items)
            problems.Push(problem)
        return problems
    }

    /**
     * Access keys used twice in one window: Alt with the key reaches only the
     * first control or menu that has it. The menu bar's menus count too. "&&" is
     * a literal ampersand, not an access key.
     */
    static AccessKeyProblems(window, items) {
        labels := []
        for name in this.MenuBarNames(window)
            labels.Push({name: "menu '" name "'", text: name})
        for item in items {
            if (item.ctrl.Type ~= "i)^(Button|CheckBox|Radio|Text|GroupBox)$")
                labels.Push({name: this.Name(item), text: item.ctrl.Text})
        }
        problems := []
        owners := Map()
        for label in labels {
            if !RegExMatch(StrReplace(label.text, "&&"), "&(.)", &match)
                continue
            key := StrLower(match[1])
            if owners.Has(key)
                problems.Push(label.name " and " owners[key] " both use Alt+" StrUpper(key))
            else
                owners[key] := label.name
        }
        return problems
    }

    ; The menu bar's top-level names, as Windows holds them (with their &).
    static MenuBarNames(window) {
        names := []
        menuHandle := DllCall("GetMenu", "Ptr", window.Hwnd, "Ptr")
        if !menuHandle
            return names
        loop DllCall("GetMenuItemCount", "Ptr", menuHandle, "Int") {
            text := Buffer(256 * 2, 0)
            DllCall("GetMenuStringW", "Ptr", menuHandle, "UInt", A_Index - 1, "Ptr", text, "Int", 256, "UInt", 0x400)  ; MF_BYPOSITION
            names.Push(StrGet(text, "UTF-16"))
        }
        return names
    }

    /**
     * How the control's label fails to fit, or "". At this screen's scaling the
     * label must fit exactly. At the other scalings, a few pixels of font-metric
     * rounding are allowed, since AutoHotkey sizes a control to its label when the
     * window is built; what must not happen is a clipped word or an extra line.
     * A label already sized to its text here is sized again at any other scaling,
     * so only its single-line height is compared there.
     */
    static TextProblem(item) {
        current := this.Needed(item, A_ScreenDPI, false)
        if !IsObject(current)
            return ""
        space := this.Space(item, A_ScreenDPI)
        if (current.w > space.w + 1 || current.h > space.h + 1)
            return this.Describe(item, A_ScreenDPI, current)
        sizedToText := current.w >= space.w - 2
        for dpi in this.dpis {
            if (dpi = A_ScreenDPI)
                continue
            needed := this.Needed(item, dpi, sizedToText)
            space := this.Space(item, dpi)
            if ((!sizedToText && needed.w > space.w * 1.03 + 1) || needed.h > space.h * 1.15 + 1)
                return this.Describe(item, dpi, needed)
        }
        return ""
    }

    static Space(item, dpi) => {w: Round(item.w * dpi / 96), h: Round(item.h * dpi / 96)}

    ; Whether a window, laid out in logical units, fits a 1366x768 screen at 150%
    ; with room for its title bar (and menu bar, when it has one).
    static FitsSmallScreen(logicalWidth, logicalHeight, hasMenu := false) {
        chrome := hasMenu ? 80 : 60
        return logicalWidth * 1.5 <= 1366 && logicalHeight * 1.5 + chrome <= 768
    }

    static Name(item) {
        text := ""
        try text := item.ctrl.Text
        text := StrReplace(StrReplace(text, "`r", " "), "`n", " ")
        return item.ctrl.Type (text != "" ? " '" SubStr(text, 1, 40) "'" : "")
    }

    /**
     * The pixels the control's label needs at dpi, with the control's own padding,
     * or 0 for a control whose content scrolls or that has no label. singleLine
     * measures without wrapping.
     */
    static Needed(item, dpi, singleLine) {
        ctrl := item.ctrl
        scale := dpi / 96
        space := this.Space(item, dpi)
        text := ""
        try text := ctrl.Text
        switch ctrl.Type, false {
            case "Text":
                ; Rules and colored panels (no text, or a hairline) have nothing to fit.
                if (text = "" || item.w <= 2 || item.h <= 2)
                    return 0
                font := this.FontOf(ctrl)
                ; SS_CENTERIMAGE draws one vertically centered line.
                if (singleLine || ControlGetStyle(ctrl) & 0x200)
                    return this.Measure(text, font, dpi)
                return this.Measure(text, font, dpi, space.w)
            case "Button":
                needed := this.Measure(text, this.FontOf(ctrl), dpi)
                return {w: needed.w + Round(12 * scale), h: needed.h + Round(4 * scale)}
            case "CheckBox", "Radio":
                font := this.FontOf(ctrl)
                box := Round(20 * scale)  ; the check glyph and its gap
                line := this.Measure("Ag", font, dpi).h
                if (singleLine || space.h < line * 1.6)
                    needed := this.Measure(text, font, dpi)
                else
                    needed := this.Measure(text, font, dpi, space.w - box)
                return {w: needed.w + box, h: needed.h}
            case "DDL":
                font := this.FontOf(ctrl)
                widest := 0
                for entry in ControlGetItems(ctrl)
                    widest := Max(widest, this.Measure(entry, font, dpi).w)
                return {w: widest + Round(30 * scale), h: 0}
        }
        return 0
    }

    static Describe(item, dpi, needed) {
        return this.Name(item) " does not fit at " Round(dpi / 96 * 100) "%: needs "
            . needed.w "x" needed.h " px, has " Round(item.w * dpi / 96) "x" Round(item.h * dpi / 96)
    }

    ; The control's font as point size, weight and face.
    static FontOf(ctrl) {
        handle := SendMessage(0x31, 0, 0, ctrl)  ; WM_GETFONT
        logFont := Buffer(92, 0)
        DllCall("GetObjectW", "Ptr", handle, "Int", logFont.Size, "Ptr", logFont)
        return {
            points: -NumGet(logFont, 0, "Int") * 72 / A_ScreenDPI,
            weight: NumGet(logFont, 16, "Int"),
            face: StrGet(logFont.Ptr + 28, 32, "UTF-16")
        }
    }

    /**
     * Pixel size of text drawn in font at dpi: one line, or wrapped at wrapWidth
     * pixels when it is given. & marks a mnemonic, as in the controls.
     */
    static Measure(text, font, dpi, wrapWidth := 0) {
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        handle := DllCall("CreateFontW",
            "Int", -Round(font.points * dpi / 72), "Int", 0, "Int", 0, "Int", 0,
            "Int", font.weight, "UInt", 0, "UInt", 0, "UInt", 0,
            "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 5, "UInt", 0,  ; DEFAULT_CHARSET, CLEARTYPE_QUALITY
            "Str", font.face, "Ptr")
        previous := DllCall("SelectObject", "Ptr", dc, "Ptr", handle, "Ptr")
        try {
            rect := Buffer(16, 0)
            NumPut("Int", wrapWidth ? wrapWidth : 100000, rect, 8)
            ; DT_CALCRECT, with DT_WORDBREAK or DT_SINGLELINE
            DllCall("DrawTextW", "Ptr", dc, "Str", text, "Int", -1, "Ptr", rect,
                "UInt", 0x400 | (wrapWidth ? 0x10 : 0x20))
            return {w: NumGet(rect, 8, "Int"), h: NumGet(rect, 12, "Int")}
        } finally {
            DllCall("SelectObject", "Ptr", dc, "Ptr", previous)
            DllCall("DeleteObject", "Ptr", handle)
            DllCall("DeleteDC", "Ptr", dc)
        }
    }
}
