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
#Include AppLog.ahk
#Include AppTray.ahk

; The app icon: compiled into the EXE (which then also uses it for the tray and its
; windows), and set at startup for source runs, before any window is created.
;@Ahk2Exe-SetMainIcon pacs-assistant.ico
if !A_IsCompiled
    TraySetIcon(A_ScriptDir "\pacs-assistant.ico")
A_IconTip := "PACS Assistant"

; Production error record: append every uncaught runtime error, with its type,
; location and call stack, to error.log in the app's data folder (AppLog). The
; callback returns nothing, so the default error dialog still shows (additive).
OnError(OnError_Log)

OnError_Log(E, mode) {
    AppLog.WriteError(E)
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
PACSMonitor.automationAcquire := ObjBindMethod(PACSCommands, "AcquireClinicalAutomation")
PACSMonitor.automationRelease := ObjBindMethod(PACSCommands, "ReleaseClinicalAutomation")
MicrophoneManager.automationAcquire := ObjBindMethod(PACSCommands, "AcquireClinicalAutomation")
MicrophoneManager.automationRelease := ObjBindMethod(PACSCommands, "ReleaseClinicalAutomation")

; Initialize the GUI when the script starts
kbGUI := KeybindGUI()
UpdateChecker.shutdownCoordinator := kbGUI
OnExit((exitReason, exitCode) => kbGUI.HandleProcessExit(exitReason, exitCode))
AppTray.Install(kbGUI)

; Start background clinical services only after the shared automation and
; configuration gates are fully composed.
PACSMonitor.Start()
MicrophoneManager.Start()

; Start bounded asynchronous network checks only after clinical services, the GUI,
; and profile hotkeys are available.
UpdateChecker.Start()
