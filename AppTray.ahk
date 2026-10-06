; = CONTENTS
;   + Preamble
;   + AppTray class (notification-area menu: open the window, settings, updates,
;       suspend keybinds, exit)

#Requires AutoHotkey v2.0

#Include Settings.ahk
#Include UpdateChecker.ahk

/**
 * The notification-area icon's menu. Double-clicking the icon brings the PACS
 * Assistant window forward.
 *
 * It replaces AutoHotkey's standard items. Of those, a compiled build offered only
 * Suspend Hotkeys, Pause Script and Exit: Suspend is kept under the app's own name,
 * and Pause is left out because a paused script stops new-study monitoring and the
 * microphone service without saying so.
 */
class AppTray {
    static openItem := "&Open PACS Assistant"
    static suspendItem := "&Suspend Keybinds"
    static app := 0

    /**
     * @param app the main window's owner: ShowMainWindow() brings it forward and
     *     RefreshMainView() redraws its status after a suspend.
     */
    static Install(app) {
        this.app := app
        tray := A_TrayMenu
        tray.Delete()
        tray.Add(this.openItem, (*) => app.ShowMainWindow())
        tray.Add()
        tray.Add("Se&ttings...", (*) => Settings.ShowDialog())
        tray.Add("Check for &Updates...", (*) => UpdateChecker.ShowUpdateDialog())
        tray.Add()
        tray.Add(this.suspendItem, (*) => this.ToggleSuspend())
        tray.Add()
        ; ExitApp runs the same shutdown gate as closing the window (main.ahk OnExit).
        tray.Add("E&xit", (*) => ExitApp())
        tray.Default := this.openItem
    }

    ; Suspending turns every keybind off until it is resumed; key capture and the
    ; background services are unaffected.
    static ToggleSuspend() {
        Suspend(-1)
        if A_IsSuspended
            A_TrayMenu.Check(this.suspendItem)
        else
            A_TrayMenu.Uncheck(this.suspendItem)
        if IsObject(this.app)
            this.app.RefreshMainView()
    }
}
