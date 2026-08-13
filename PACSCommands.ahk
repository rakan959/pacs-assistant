#Requires AutoHotkey v2.0
#Include MicrophoneManager.ahk
#Include PowerScribe.ahk
#Include AppControl.ahk
#Include WetRead.ahk

class PACSCommands {
    static commands := Map(
        "Toggle Dictation", (*) => sendPs("{F4}"),
        "Select Next Field", (*) => (WinActivate("PowerScribe"), Send("{Tab}")),
        "Select Previous Field", (*) => (WinActivate("PowerScribe"), Send("+{Tab}")),
        "Delete Previous Word", (*) => (WinActivate("PowerScribe"), Send("^{Backspace}")),
        "Delete Next Word", (*) => (WinActivate("PowerScribe"), Send("^{Delete}")),
        "Draft Report", (*) => sendPs("{F9}"),
        "Sign Report", (*) => sendPs("{F12}"),
        "Open/Force Restart PACS", (*) => restartPACS(),
        "Paste Wet Read", (*) => wetRead(),
        "Toggle PowerScribe Window", (*) => toggleWindow("PowerScribe"),
        "Toggle EPIC Window", (*) => toggleWindow("Hyperspace"),
        "Next Series", (*) => (WinActivate("Vue PACS Client"), Send("{Right}")),
        "Previous Series", (*) => (WinActivate("Vue PACS Client"), Send("{Left}")),
        "Set PowerScribe Microphone", (*) => MicrophoneManager.ApplyNow()
    )

    static CreateCustomKeybind(keys, targetWindow := "") {
        ; Create a function that stores its configuration
        func := targetWindow != "" ?
            (*) => (WinActivate(targetWindow), Send(keys)) :
            (*) => Send(keys)

        ; Store the configuration
        func.keys := keys
        func.window := targetWindow
        return func
    }
}
