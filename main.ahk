#Requires AutoHotkey v2.0
#SingleInstance Ignore
#Warn All, Off

#Include KeybindGUI.ahk
#Include Settings.ahk
#Include UpdateChecker.ahk
#Include PACSMonitor.ahk
#Include MicrophoneManager.ahk

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
    && !Settings.writeTransactionActive
Settings.mutationGuard := (*) => !PACSCommands.clinicalCommandActive
    && !KeybindGUI.shutdownTransactionActive
    && !KeybindGUI.captureTransactionActive
    && !KeybindGUI.profileMutationTransactionActive
Settings.dialogGuard := (*) => !PACSCommands.clinicalCommandActive
    && !KeybindGUI.shutdownTransactionActive
    && !KeybindGUI.captureTransactionActive
    && !KeybindGUI.profileMutationTransactionActive
    && !Settings.writeTransactionActive

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
