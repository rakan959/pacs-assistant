#Requires AutoHotkey v2.0
#SingleInstance Ignore
#Warn All, StdOut
FileEncoding "UTF-8"

#Include KeybindGUI.ahk
#Include Settings.ahk
#Include UpdateChecker.ahk
#Include PACSMonitor.ahk
#Include MicrophoneManager.ahk

; Production error record: append every uncaught runtime error to a timestamped
; log in the app's data folder so field failures leave a persistent record. The
; callback returns nothing, so the default error dialog still shows (additive).
OnError(OnError_Log)

OnError_Log(E, mode) {
    try {
        root := AppStorage.DataRoot()
        DirCreate(root)
        FileAppend(Format("{1} {2} line {3}: {4}`n", FormatTime(), A_MSec, E.Line, E.Message), root "\error.log")
    } catch {
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
PACSCommands.commandAvailabilityProbe := (*) => !KeybindGUI.shutdownTransactionActive
    && !KeybindGUI.captureTransactionActive
    && !KeybindGUI.profileMutationTransactionActive
    && !KeybindGUI.uiPresentationTransactionActive
    && !Settings.writeTransactionActive
Settings.mutationGuard := (*) => !PACSCommands.clinicalCommandActive
    && !KeybindGUI.shutdownTransactionActive
    && !KeybindGUI.captureTransactionActive
    && !KeybindGUI.profileMutationTransactionActive
    && !KeybindGUI.uiPresentationTransactionActive
Settings.dialogGuard := (*) => !PACSCommands.clinicalCommandActive
    && !KeybindGUI.shutdownTransactionActive
    && !KeybindGUI.captureTransactionActive
    && !KeybindGUI.profileMutationTransactionActive
    && !KeybindGUI.uiPresentationTransactionActive
    && !Settings.writeTransactionActive
Settings.dialogAcquire := ObjBindMethod(KeybindGUI, "TryBeginUiPresentation")
Settings.dialogRelease := ObjBindMethod(KeybindGUI, "EndUiPresentation")
UpdateChecker.dialogAcquire := ObjBindMethod(KeybindGUI, "TryBeginUiPresentation")
UpdateChecker.dialogRelease := ObjBindMethod(KeybindGUI, "EndUiPresentation")

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
