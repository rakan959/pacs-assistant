#Requires AutoHotkey v2.0
#SingleInstance Ignore
#Warn All, StdOut
FileEncoding "UTF-8"

#Include ExclusiveOperations.ahk
#Include KeybindGUI.ahk
#Include Settings.ahk
#Include UpdateChecker.ahk
#Include PACSMonitor.ahk
#Include MicrophoneManager.ahk
#Include ErrorText.ahk

; Production error record: append every uncaught runtime error to the app's data
; folder so field failures leave a persistent record. The callback returns nothing,
; so the default error dialog still shows (additive). Lines are ISO-timestamped and
; carry the error type, function and source location plus the call stack.
OnError(OnError_Log)

OnError_Log(E, mode) {
    try {
        entry := FormatTime(, "yyyy-MM-dd HH:mm:ss") "." A_MSec " " ErrorText.Describe(E) "`n"
        if (IsObject(E) && HasProp(E, "Stack") && E.Stack != "")
            entry .= E.Stack "`n"
        root := AppStorage.DataRoot()
        DirCreate(root)
        FileAppend(entry, root "\error.log")
    } catch Any {
        ; A logging failure must never mask the original error.
    }
}

; The composition root owns cross-module reactions to persisted settings. Settings
; itself remains independent of the services that consume it.
Settings.AddChangeListener(ObjBindMethod(UpdateChecker, "OnSettingsChanged"))
Settings.AddChangeListener(ObjBindMethod(PACSMonitor, "OnSettingsChanged"))
Settings.AddChangeListener(ObjBindMethod(MicrophoneManager, "OnSettingsChanged"))
UpdateChecker.clinicalActivityProbe := (*) => PACSCommands.clinicalCommandActive

; Compose every cross-module lease before showing the main window or registering
; callbacks, so even the first user action observes the same serialization policy.
; Each guard ignores only the lease its own module tracks and reports separately.
PACSCommands.commandAvailabilityProbe := (*) => ExclusiveOperations.Active("clinical") = ""
Settings.mutationGuard := (*) => ExclusiveOperations.Active("settingsWrite") = ""
Settings.dialogAcquire := ObjBindMethod(ExclusiveOperations, "TryBegin", "uiPresentation")
Settings.dialogRelease := ObjBindMethod(ExclusiveOperations, "End", "uiPresentation")
UpdateChecker.dialogAcquire := ObjBindMethod(ExclusiveOperations, "TryBegin", "uiPresentation")
UpdateChecker.dialogRelease := ObjBindMethod(ExclusiveOperations, "End", "uiPresentation")

; Initialize the GUI when the script starts
kbGUI := KeybindGUI()
UpdateChecker.shutdownCoordinator := kbGUI
OnExit((exitReason, exitCode) => kbGUI.HandleProcessExit(exitReason, exitCode))
PACSMonitor.automationAcquire := ObjBindMethod(PACSCommands, "AcquireClinicalAutomation")
PACSMonitor.automationRelease := ObjBindMethod(PACSCommands, "ReleaseClinicalAutomation")
MicrophoneManager.automationAcquire := ObjBindMethod(PACSCommands, "AcquireClinicalAutomation")
MicrophoneManager.automationRelease := ObjBindMethod(PACSCommands, "ReleaseClinicalAutomation")

; Start background clinical services only after the shared automation and
; configuration gates are fully composed.
PACSMonitor.Start()
MicrophoneManager.Start()

; Start bounded asynchronous network checks only after clinical services, the GUI,
; and profile hotkeys are available.
UpdateChecker.Start()
