; = CONTENTS
;   + Preamble
;   + CommandFeedback class (a brief tooltip naming the command a keybind ran)

#Requires AutoHotkey v2.0

#Include Settings.ahk

/**
 * "Show the command's name by the pointer when a keybind runs". A tooltip window
 * never takes focus, so it cannot pull PACS or PowerScribe out of the user's
 * hands; it disappears after durationMs. Off unless Settings turns it on.
 */
class CommandFeedback {
    static toolTipNumber := 19
    static durationMs := 1200
    static enabledProbe := (*) => Settings.Get("ShowCommandFeedback")
    static hide := (*) => ToolTip(,,, CommandFeedback.toolTipNumber)

    ; PACSCommands calls this as each command starts.
    static Show(commandName) {
        if !this.enabledProbe.Call()
            return false
        CoordMode("Mouse", "Screen")
        CoordMode("ToolTip", "Screen")
        MouseGetPos(&x, &y)
        ToolTip(commandName, x + 16, y + 20, this.toolTipNumber)
        ; A newer command restarts the clock rather than being hidden early.
        SetTimer(this.hide, -this.durationMs)
        return true
    }
}
