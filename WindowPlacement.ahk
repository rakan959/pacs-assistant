; = CONTENTS
;   + Preamble
;   + WindowPlacement class (where the main window was, kept between runs)

#Requires AutoHotkey v2.0

#Include AppStorage.ahk
#Include AppLog.ahk
#Include ErrorText.ahk

/**
 * The main window's last position, size and maximized state, in window.ini in the
 * data folder. It is window state, not a setting: it is written whenever the
 * window is moved, outside the settings transaction, and losing it only means the
 * window opens centred.
 *
 * Coordinates are screen pixels of the outer window, as WinGetPos reports them.
 */
class WindowPlacement {
    static fileName := "window.ini"
    static section := "MainWindow"

    static Path() => AppStorage.DataRoot() "\" this.fileName

    /**
     * The saved placement, or 0 when there is none or it is unreadable.
     * @returns {x, y, w, h, maximized}
     */
    static Load() {
        try {
            path := this.Path()
            if !FileExist(path)
                return 0
            values := []
            for key in ["X", "Y", "Width", "Height"] {
                value := IniRead(path, this.section, key, "")
                if !RegExMatch(value, "^-?\d+$")
                    return 0
                values.Push(Integer(value))
            }
            return {
                x: values[1], y: values[2], w: values[3], h: values[4],
                maximized: IniRead(path, this.section, "Maximized", "0") = "1"
            }
        }
        return 0
    }

    static SaveRect(x, y, w, h) {
        try {
            path := this.Path()
            IniWrite(x, path, this.section, "X")
            IniWrite(y, path, this.section, "Y")
            IniWrite(w, path, this.section, "Width")
            IniWrite(h, path, this.section, "Height")
        } catch Any as err
            AppLog.Write("The window position could not be saved: " ErrorText.Describe(err))
    }

    static SaveMaximized(maximized) {
        try IniWrite(maximized ? "1" : "0", this.Path(), this.section, "Maximized")
        catch Any as err
            AppLog.Write("The window position could not be saved: " ErrorText.Describe(err))
    }

    /**
     * Whether a saved placement can be used with these monitor work areas: its
     * title bar must lie mostly on one of them, so the window can be seen and
     * moved. A monitor that has since been removed or rearranged fails this, and
     * the window then opens centred.
     * @param workAreas Array of {left, top, right, bottom}
     */
    static IsReachable(saved, workAreas) {
        if (!IsObject(saved) || saved.w < 200 || saved.h < 150)
            return false
        titleTop := saved.y
        titleBottom := saved.y + 30
        for area in workAreas {
            visibleWidth := Min(saved.x + saved.w, area.right) - Max(saved.x, area.left)
            visibleHeight := Min(titleBottom, area.bottom) - Max(titleTop, area.top)
            if (visibleWidth >= Min(saved.w, 200) && visibleHeight >= 20)
                return true
        }
        return false
    }

    ; The work area of every monitor, for IsReachable.
    static WorkAreas() {
        areas := []
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            areas.Push({left: left, top: top, right: right, bottom: bottom})
        }
        return areas
    }
}
