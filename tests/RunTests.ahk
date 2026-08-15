#Requires AutoHotkey v2.0
#Include TestRunner.ahk
#Include TestRunnerTest.ahk
#Include UpdateCheckerTest.ahk
#Include SettingsTest.ahk
#Include PACSMonitorTest.ahk
#Include HotkeyManagerTest.ahk
#Include ProfileManagerTest.ahk
#Include PACSCommandsTest.ahk
#Include ClinicalAutomationTest.ahk
#Include WetReadTest.ahk
#Include KeybindGUITest.ahk
#Include UIAValueTest.ahk

TestRunner.AddTest(TestRunnerTest)
TestRunner.AddTest(UpdateCheckerTest)
TestRunner.AddTest(SettingsTest)
TestRunner.AddTest(PACSMonitorTest)
TestRunner.AddTest(HotkeyManagerTest)
TestRunner.AddTest(ProfileManagerTest)
TestRunner.AddTest(PACSCommandsTest)
TestRunner.AddTest(ClinicalAutomationTest)
TestRunner.AddTest(WetReadTest)
TestRunner.AddTest(KeybindGUITest)
TestRunner.AddTest(UIAValueTest)

TestRunner.RunAll()

; Exit non-zero on failure. A bare ExitApp always reported success, so any caller
; trusting the exit code - CI included - would read a failing suite as green.
ExitApp(TestRunner.failures > 0 ? 1 : 0)
