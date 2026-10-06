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

    /**
     * @param app the main window's owner: ShowMainWindow() brings it forward, and
     *     ToggleSuspend() turns keybinds off or on and reports the change through
     *     its onSuspendChanged callback, which keeps this menu's checkmark in step.
     */
    static Install(app) {
        tray := A_TrayMenu
        tray.Delete()
        tray.Add(this.openItem, (*) => app.ShowMainWindow())
        tray.Add()
        tray.Add("Se&ttings...", (*) => Settings.ShowDialog())
        tray.Add("Check for &Updates...", (*) => UpdateChecker.ShowUpdateDialog())
        tray.Add()
        tray.Add(this.suspendItem, (*) => app.ToggleSuspend())
        tray.Add()
        ; ExitApp runs the same shutdown gate as closing the window (main.ahk OnExit).
        tray.Add("E&xit", (*) => ExitApp())
        tray.Default := this.openItem
        app.onSuspendChanged := ObjBindMethod(this, "SyncSuspend")
    }

    static SyncSuspend() {
        if A_IsSuspended
            A_TrayMenu.Check(this.suspendItem)
        else
            A_TrayMenu.Uncheck(this.suspendItem)
    }
}
