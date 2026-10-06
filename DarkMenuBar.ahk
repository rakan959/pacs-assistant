; = CONTENTS
;   + Preamble
;   + DarkMenuBar class (draws a window's menu bar in dark colors)

#Requires AutoHotkey v2.0

/**
 * Draws a window's menu bar in dark colors. Windows draws menu bars light even in
 * dark mode; like Notepad++ and other Win32 apps, this paints the bar and its items
 * through the undocumented WM_UAHDRAWMENU (0x91) and WM_UAHDRAWMENUITEM (0x92)
 * messages, and covers the light line Windows leaves under the bar on WM_NCPAINT
 * and WM_NCACTIVATE. The drop-down menus are dark through UITheme.UseDarkMenus.
 * Where the messages never arrive, the bar simply stays light.
 */
class DarkMenuBar {
    static windows := Map()  ; hwnd -> true
    static installed := false
    ; COLORREF (0xBBGGRR) values from UITheme's dark palette.
    static barColor := 0x202020
    static hotColor := 0x3B3B3B
    static textColor := 0xE6E6E6
    static disabledTextColor := 0x8A8A8A

    static Attach(hwnd) {
        ; Forget windows that are gone, so a reused handle starts unattached.
        for attached in [this.windows*] {
            if !DllCall("IsWindow", "Ptr", attached)
                this.windows.Delete(attached)
        }
        this.windows[hwnd] := true
        if !this.installed {
            this.installed := true
            OnMessage(0x91, ObjBindMethod(this, "OnDrawMenu"))
            OnMessage(0x92, ObjBindMethod(this, "OnDrawMenuItem"))
            OnMessage(0x85, ObjBindMethod(this, "OnNcPaint"))  ; WM_NCPAINT
            OnMessage(0x86, ObjBindMethod(this, "OnNcPaint"))  ; WM_NCACTIVATE
        }
        DllCall("DrawMenuBar", "Ptr", hwnd)
    }

    static Detach(hwnd) {
        if this.windows.Has(hwnd)
            this.windows.Delete(hwnd)
    }

    static Brush(color) {
        static brushes := Map()
        if !brushes.Has(color)
            brushes[color] := DllCall("CreateSolidBrush", "UInt", color, "Ptr")
        return brushes[color]
    }

    ; The menu bar's rectangle in window coordinates (MENUBARINFO.rcBar), or 0.
    static BarRect(hwnd) {
        info := Buffer(A_PtrSize = 8 ? 48 : 32, 0)  ; MENUBARINFO
        NumPut("UInt", info.Size, info, 0)
        if !DllCall("GetMenuBarInfo", "Ptr", hwnd, "Int", -3, "Int", 0, "Ptr", info)  ; OBJID_MENU
            return 0
        window := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", window)
        left := NumGet(window, 0, "Int"), top := NumGet(window, 4, "Int")
        rect := Buffer(16, 0)
        NumPut("Int", NumGet(info, 4, "Int") - left, "Int", NumGet(info, 8, "Int") - top,
            "Int", NumGet(info, 12, "Int") - left, "Int", NumGet(info, 16, "Int") - top, rect)
        return rect
    }

    static OnDrawMenu(wParam, lParam, msg, hwnd) {
        if !this.windows.Has(hwnd)
            return
        rect := this.BarRect(hwnd)
        if !rect
            return
        hdc := NumGet(lParam, A_PtrSize, "Ptr")  ; UAHMENU: hmenu, hdc, dwFlags
        DllCall("FillRect", "Ptr", hdc, "Ptr", rect, "Ptr", this.Brush(this.barColor))
        return 1
    }

    static OnDrawMenuItem(wParam, lParam, msg, hwnd) {
        if !this.windows.Has(hwnd)
            return
        ; UAHDRAWMENUITEM: a DRAWITEMSTRUCT, then UAHMENU {hmenu, hdc, dwFlags},
        ; then UAHMENUITEM, whose first field is the item's position.
        x64 := A_PtrSize = 8
        state := NumGet(lParam, 16, "UInt")
        hdc := NumGet(lParam, x64 ? 32 : 24, "Ptr")
        rectOffset := x64 ? 40 : 28
        menuHandle := NumGet(lParam, x64 ? 64 : 48, "Ptr")
        position := NumGet(lParam, x64 ? 88 : 60, "Int")
        rect := Buffer(16, 0)
        DllCall("RtlMoveMemory", "Ptr", rect, "Ptr", lParam + rectOffset, "Ptr", 16)

        ; ODS_SELECTED 0x1, ODS_GRAYED 0x2, ODS_DISABLED 0x4, ODS_HOTLIGHT 0x40,
        ; ODS_NOACCEL 0x100
        hot := state & (0x1 | 0x40)
        disabled := state & (0x2 | 0x4)
        DllCall("FillRect", "Ptr", hdc, "Ptr", rect, "Ptr", this.Brush(hot ? this.hotColor : this.barColor))

        length := DllCall("GetMenuStringW", "Ptr", menuHandle, "UInt", position, "Ptr", 0, "Int", 0, "UInt", 0x400, "Int")
        text := Buffer((length + 1) * 2, 0)
        DllCall("GetMenuStringW", "Ptr", menuHandle, "UInt", position, "Ptr", text, "Int", length + 1, "UInt", 0x400)
        DllCall("SetBkMode", "Ptr", hdc, "Int", 1)  ; TRANSPARENT
        DllCall("SetTextColor", "Ptr", hdc, "UInt", disabled ? this.disabledTextColor : this.textColor)
        ; DT_CENTER | DT_VCENTER | DT_SINGLELINE, and DT_HIDEPREFIX until Alt shows
        ; the mnemonics.
        flags := 0x1 | 0x4 | 0x20 | (state & 0x100 ? 0x100000 : 0)
        DllCall("DrawTextW", "Ptr", hdc, "Ptr", text, "Int", -1, "Ptr", rect, "UInt", flags)
        return 1
    }

    ; After Windows paints the frame, covers the light line it leaves under the bar.
    static OnNcPaint(wParam, lParam, msg, hwnd) {
        if !this.windows.Has(hwnd)
            return
        result := DllCall("DefWindowProcW", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr")
        rect := this.BarRect(hwnd)
        if rect {
            hdc := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
            line := Buffer(16, 0)
            NumPut("Int", NumGet(rect, 0, "Int"), "Int", NumGet(rect, 12, "Int"),
                "Int", NumGet(rect, 8, "Int"), "Int", NumGet(rect, 12, "Int") + 1, line)
            DllCall("FillRect", "Ptr", hdc, "Ptr", line, "Ptr", this.Brush(this.barColor))
            DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)
        }
        return result
    }
}
