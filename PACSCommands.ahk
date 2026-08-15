#Requires AutoHotkey v2.0
#Include MicrophoneManager.ahk
#Include PowerScribe.ahk
#Include AppControl.ahk
#Include WetRead.ahk

class PACSCommands {
    static commands := Map(
        "Toggle Dictation", (*) => sendPs("{F4}"),
        "Select Next Field", (*) => PowerScribe.SendKeys("{Tab}"),
        "Select Previous Field", (*) => PowerScribe.SendKeys("+{Tab}"),
        "Delete Previous Word", (*) => PowerScribe.SendKeys("^{Backspace}"),
        "Delete Next Word", (*) => PowerScribe.SendKeys("^{Delete}"),
        "Draft Report", (*) => sendPs("{F9}"),
        "Sign Report", (*) => sendPs("{F12}"),
        "Open/Force Restart PACS", (*) => restartPACS(),
        "Paste Wet Read", (*) => wetRead(),
        "Toggle PowerScribe Window", (*) => toggleWindow(PACSCommands.PowerScribeToggleTarget()),
        "Toggle EPIC Window", (*) => toggleWindow("Hyperspace"),
        "Next Series", (*) => AppControl.SendKeysToWindow("Vue PACS Client ahk_exe mp.exe", "{Right}"),
        "Previous Series", (*) => AppControl.SendKeysToWindow("Vue PACS Client ahk_exe mp.exe", "{Left}"),
        "Set PowerScribe Microphone", (*) => MicrophoneManager.ApplyNow()
    )

    static PowerScribeToggleTarget() {
        return PowerScribe.windowTitle
    }

    static CreateCustomKeybind(keys, targetWindow := "") {
        ; Create a function that stores its configuration
        func := targetWindow != "" ?
            (*) => AppControl.SendKeysToWindow(targetWindow, keys) :
            (*) => Send(keys)

        ; Store the configuration
        func.keys := keys
        func.window := targetWindow
        return func
    }
}
