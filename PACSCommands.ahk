#Requires AutoHotkey v2.0
#Include MicrophoneManager.ahk
#Include PowerScribe.ahk
#Include AppControl.ahk
#Include WetRead.ahk

class PACSCommands {
    static clinicalCommandActive := false
    static activeClinicalCommand := ""
    static busyNotifier := (text, title, options) => TrayTip(text, title, options)

    static commands := Map(
        "Toggle Dictation", (*) => PACSCommands.RunClinicalCommand("Toggle Dictation", (*) => sendPs("{F4}")),
        "Select Next Field", (*) => PACSCommands.RunClinicalCommand("Select Next Field", (*) => PowerScribe.SendKeys("{Tab}")),
        "Select Previous Field", (*) => PACSCommands.RunClinicalCommand("Select Previous Field", (*) => PowerScribe.SendKeys("+{Tab}")),
        "Delete Previous Word", (*) => PACSCommands.RunClinicalCommand("Delete Previous Word", (*) => PowerScribe.SendKeys("^{Backspace}")),
        "Delete Next Word", (*) => PACSCommands.RunClinicalCommand("Delete Next Word", (*) => PowerScribe.SendKeys("^{Delete}")),
        "Draft Report", (*) => PACSCommands.RunClinicalCommand("Draft Report", (*) => sendPs("{F9}")),
        "Sign Report", (*) => PACSCommands.RunClinicalCommand("Sign Report", (*) => sendPs("{F12}")),
        "Open/Force Restart PACS", (*) => PACSCommands.RunClinicalCommand("Open/Force Restart PACS", (*) => restartPACS()),
        "Paste Wet Read", (*) => PACSCommands.RunClinicalCommand("Paste Wet Read", (*) => wetRead()),
        "Toggle PowerScribe Window", (*) => PACSCommands.RunClinicalCommand("Toggle PowerScribe Window", (*) => AppControl.ToggleExactWindow(PACSCommands.PowerScribeToggleTarget())),
        "Toggle EPIC Window", (*) => PACSCommands.RunClinicalCommand("Toggle EPIC Window", (*) => toggleWindow("Hyperspace")),
        "Next Series", (*) => PACSCommands.RunClinicalCommand("Next Series", (*) => AppControl.SendKeysToExactWindow(AppControl.VuePacsClientWindowSpec(), "{Right}")),
        "Previous Series", (*) => PACSCommands.RunClinicalCommand("Previous Series", (*) => AppControl.SendKeysToExactWindow(AppControl.VuePacsClientWindowSpec(), "{Left}")),
        "Set PowerScribe Microphone", (*) => PACSCommands.RunClinicalCommand("Set PowerScribe Microphone", (*) => MicrophoneManager.ApplyNow())
    )

    static PowerScribeToggleTarget() {
        return AppControl.PowerScribeWindowSpec()
    }

    static RunClinicalCommand(name, callback) {
        if this.clinicalCommandActive {
            try this.busyNotifier.Call(
                "'" this.activeClinicalCommand "' is still running. '" name "' was not started.",
                "Clinical command already in progress",
                "Icon!"
            )
            return false
        }
        if !IsObject(callback)
            throw TypeError("Clinical command callback must be callable")

        this.clinicalCommandActive := true
        this.activeClinicalCommand := name
        try return callback.Call()
        finally {
            this.activeClinicalCommand := ""
            this.clinicalCommandActive := false
        }
    }

    static CreateCustomKeybind(keys, targetWindow := "") {
        ; Create a function that stores its configuration
        action := targetWindow != "" ?
            (*) => AppControl.SendKeysToWindow(targetWindow, keys) :
            (*) => Send(keys)
        func := (*) => PACSCommands.RunClinicalCommand("Custom keybind", action)

        ; Store the configuration
        func.keys := keys
        func.window := targetWindow
        return func
    }
}
