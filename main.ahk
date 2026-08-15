#Requires AutoHotkey v2.0
#SingleInstance Force
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

; Start PACS monitoring
PACSMonitor.Start()

; Watch for the PowerScribe login screen to set the microphone
MicrophoneManager.Start()

; Initialize the GUI when the script starts
kbGUI := KeybindGUI()

; Start bounded asynchronous network checks only after clinical services, the GUI,
; and profile hotkeys are available.
UpdateChecker.Start()
