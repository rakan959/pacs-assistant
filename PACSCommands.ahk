#Requires AutoHotkey v2.0
#Include MicrophoneManager.ahk
#Include PowerScribe.ahk
#Include AppControl.ahk
#Include WetRead.ahk

class PACSCommands {
    static clinicalCommandActive := false
    static activeClinicalCommand := ""
    static busyNotifier := (text, title, options) => TrayTip(text, title, options)
    static unavailableNotifier := (text, title, options) => TrayTip(text, title, options)
    static commandAvailabilityProbe := (*) => true

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
        "Toggle EPIC Window", (*) => PACSCommands.RunClinicalCommand("Toggle EPIC Window", (*) => PACSCommands.ToggleEpicWindow()),
        "Next Series", (*) => PACSCommands.RunClinicalCommand("Next Series", (*) => AppControl.SendKeysToExactWindow(AppControl.VuePacsClientWindowSpec(), "{Right}")),
        "Previous Series", (*) => PACSCommands.RunClinicalCommand("Previous Series", (*) => AppControl.SendKeysToExactWindow(AppControl.VuePacsClientWindowSpec(), "{Left}")),
        "Set PowerScribe Microphone", (*) => PACSCommands.RunClinicalCommand("Set PowerScribe Microphone", (*) => MicrophoneManager.ApplyNow())
    )

    static PowerScribeToggleTarget() {
        return AppControl.PowerScribeWindowSpec()
    }

    static ToggleEpicWindow() {
        ; No exact Hyperspace title/executable contract has been captured from a live
        ; workstation. A title-prefix toggle can affect unrelated clinical or user
        ; windows, so preserve the profile command but perform no window action.
        try this.unavailableNotifier.Call(
            "EPIC window identity has not been safely configured. Toggle EPIC manually.",
            "Toggle EPIC unavailable",
            "Icon!"
        )
        return false
    }

    static RunClinicalCommand(name, callback) {
        if !IsObject(callback)
            throw TypeError("Clinical command callback must be callable")

        lease := this.AcquireClinicalAutomation(name)
        if lease.status == "unavailable" {
            try this.busyNotifier.Call(
                "PACS Assistant is shutting down or changing configuration. '" name "' was not started.",
                "Clinical command unavailable",
                "Icon!"
            )
            return false
        }
        if lease.status != "acquired" {
            try this.busyNotifier.Call(
                "'" lease.busyCommand "' is still running. '" name "' was not started.",
                "Clinical command already in progress",
                "Icon!"
            )
            return false
        }

        try return callback.Call()
        finally this.ReleaseClinicalAutomation()
    }

    static AcquireClinicalAutomation(name) {
        unavailable := false
        busyCommand := ""
        acquired := false
        ; A timer/GUI callback can interrupt between a point-in-time availability
        ; check and publication. Acquire the shared boundary atomically with every
        ; profile/settings/capture transaction's corresponding guarded acquisition.
        Critical("On")
        try {
            if !this.commandAvailabilityProbe.Call()
                unavailable := true
            else if this.clinicalCommandActive
                busyCommand := this.activeClinicalCommand
            else {
                this.clinicalCommandActive := true
                this.activeClinicalCommand := name
                acquired := true
            }
        } finally Critical("Off")

        if acquired
            return {status: "acquired", busyCommand: ""}
        return {
            status: unavailable ? "unavailable" : "busy",
            busyCommand: busyCommand
        }
    }

    static ReleaseClinicalAutomation() {
        Critical("On")
        try {
            this.activeClinicalCommand := ""
            this.clinicalCommandActive := false
        } finally Critical("Off")
    }

    static CreateCustomKeybind(keys, targetWindow := "") {
        ; Create a function that stores its configuration
        action := targetWindow != "" ?
            (*) => AppControl.SendKeysToWindow(targetWindow, keys) :
            (*) => Send(keys)
        commandCallback := (*) => PACSCommands.RunClinicalCommand("Custom keybind", action)

        ; Store the configuration
        commandCallback.keys := keys
        commandCallback.window := targetWindow
        return commandCallback
    }
}
