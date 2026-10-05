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

    ; Built-in commands by persisted name. Profiles store these names, so renaming
    ; one orphans existing binds.
    static commands := PACSCommands.ClinicalCommands([
        ["Toggle Dictation", (*) => PowerScribe.SendKeys("{F4}")],
        ["Select Next Field", (*) => PowerScribe.SendKeys("{Tab}")],
        ["Select Previous Field", (*) => PowerScribe.SendKeys("+{Tab}")],
        ["Delete Previous Word", (*) => PowerScribe.SendKeys("^{Backspace}")],
        ["Delete Next Word", (*) => PowerScribe.SendKeys("^{Delete}")],
        ["Draft Report", (*) => PowerScribe.SendKeys("{F9}")],
        ["Sign Report", (*) => PowerScribe.SendKeys("{F12}")],
        ["Open/Force Restart PACS", (*) => RestartPACS()],
        ["Paste Wet Read", (*) => WetRead()],
        ["Toggle PowerScribe Window", (*) => AppControl.ToggleExactWindow(PACSCommands.PowerScribeToggleTarget())],
        ["Toggle EPIC Window", (*) => PACSCommands.ToggleEpicWindow()],
        ["Next Series", (*) => AppControl.SendKeysToExactWindow(AppControl.VuePacsClientWindowSpec(), "{Right}")],
        ["Previous Series", (*) => AppControl.SendKeysToExactWindow(AppControl.VuePacsClientWindowSpec(), "{Left}")],
        ["Set PowerScribe Microphone", (*) => MicrophoneManager.ApplyNow()]
    ])

    ; Wraps each [name, action] pair so the action runs under the clinical lease in
    ; that command's name.
    static ClinicalCommands(definitions) {
        commands := Map()
        for definition in definitions
            commands[definition[1]] := this.ClinicalCommand(definition[1], definition[2])
        return commands
    }

    ; A separate function, not a closure built in the loop above: a closure captures
    ; the variable itself, and a for loop restores its variables when it ends, so a
    ; closure made in the loop would find them unset when the hotkey fires.
    static ClinicalCommand(name, action) {
        return (*) => PACSCommands.RunClinicalCommand(name, action)
    }

    static PowerScribeToggleTarget() {
        return AppControl.PowerScribeWindowSpec()
    }

    static ToggleEpicWindow() {
        ; No exact Hyperspace title/executable contract has been captured from a live
        ; workstation. A title-prefix toggle can affect unrelated clinical or user
        ; windows, so preserve the profile command but perform no window action.
        try this.unavailableNotifier.Call(
            "EPIC window identity has not been safely configured. Toggle EPIC manually.",
            "Toggle EPIC Unavailable",
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
                "Clinical Command Unavailable",
                "Icon!"
            )
            return false
        }
        if lease.status != "acquired" {
            try this.busyNotifier.Call(
                "'" lease.busyCommand "' is still running. '" name "' was not started.",
                "Clinical Command In Progress",
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

        ; Exposed so the configuration can be checked without sending keys.
        commandCallback.keys := keys
        commandCallback.window := targetWindow
        return commandCallback
    }
}
