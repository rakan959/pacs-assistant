#Requires AutoHotkey v2.0
#Include ../UITheme.ahk

; Saves and restores UITheme's mode and the probes UpdateMode reads, so a test can
; choose the Theme setting and Windows' state without touching the machine's.
class UIThemeFixture {
    static Save() => {
        mode: UITheme.mode,
        themeSetting: UITheme.themeSetting,
        highContrastProbe: UITheme.highContrastProbe,
        windowsDarkProbe: UITheme.windowsDarkProbe
    }

    static Restore(saved) {
        UITheme.themeSetting := saved.themeSetting
        UITheme.highContrastProbe := saved.highContrastProbe
        UITheme.windowsDarkProbe := saved.windowsDarkProbe
        if (UITheme.mode != saved.mode) {
            UITheme.mode := saved.mode
            UITheme.UseDarkMenus(saved.mode = "dark")
        }
    }

    ; The Theme setting and Windows' state that UpdateMode will read.
    static Use(setting, windowsDark, highContrast) {
        UITheme.themeSetting := (*) => setting
        UITheme.windowsDarkProbe := (*) => windowsDark
        UITheme.highContrastProbe := (*) => highContrast
    }
}
