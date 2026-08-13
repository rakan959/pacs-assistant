#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

#Include KeybindGUI.ahk
#Include UpdateChecker.ahk
#Include PACSMonitor.ahk
#Include MicrophoneManager.ahk

; Initialize the update checker
UpdateChecker.Start()

; Start PACS monitoring
PACSMonitor.Start()

; Watch for the PowerScribe login screen to set the microphone
MicrophoneManager.Start()

; Initialize the GUI when the script starts
kbGUI := KeybindGUI() 