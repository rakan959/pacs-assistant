#Requires AutoHotkey v2.0
#SingleInstance Off
#ErrorStdOut
#Warn All, StdOut
FileEncoding "UTF-8"

; Headless CI runner: load errors and warnings go to stdout/stderr, and an uncaught
; runtime error exits with code 10 instead of opening a dialog (HarnessErrors.ahk).
#Include HarnessErrors.ahk
OnError(OnError_StdErr)

; Before execution reaches the class definitions included below (IsolatedStorage.ahk).
#Include IsolatedStorage.ahk
UseIsolatedDataRoot("pacs-assistant-unit-tests")

#Include TestRunner.ahk
#Include TestRunnerTest.ahk
#Include AppStorageTest.ahk
#Include AppLogTest.ahk
#Include ErrorTextTest.ahk
#Include JsonParserTest.ahk
#Include UpdateCheckerTest.ahk
#Include UpdateVerificationTest.ahk
#Include SettingsTest.ahk
#Include PACSMonitorTest.ahk
#Include MicrophoneManagerTest.ahk
#Include HotkeyContractTest.ahk
#Include HotkeyManagerTest.ahk
#Include ProfileManagerTest.ahk
#Include PACSCommandsTest.ahk
#Include ClinicalAutomationTest.ahk
#Include ExclusiveOperationsTest.ahk
#Include WetReadTest.ahk
#Include KeybindGUITest.ahk
#Include UIAValueTest.ahk
#Include UIAElementIdentityTest.ahk

TestRunner.AddTest(TestRunnerTest)
TestRunner.AddTest(AppStorageTest)
TestRunner.AddTest(AppLogTest)
TestRunner.AddTest(ErrorTextTest)
TestRunner.AddTest(JsonParserTest)
TestRunner.AddTest(UpdateCheckerTest)
TestRunner.AddTest(UpdateVerificationTest)
TestRunner.AddTest(SettingsTest)
TestRunner.AddTest(PACSMonitorTest)
TestRunner.AddTest(MicrophoneManagerTest)
TestRunner.AddTest(HotkeyContractTest)
TestRunner.AddTest(HotkeyManagerTest)
TestRunner.AddTest(ProfileManagerTest)
TestRunner.AddTest(PACSCommandsTest)
TestRunner.AddTest(ClinicalAutomationTest)
TestRunner.AddTest(ExclusiveOperationsTest)
TestRunner.AddTest(WetReadTest)
TestRunner.AddTest(KeybindGUITest)
TestRunner.AddTest(UIAValueTest)
TestRunner.AddTest(UIAElementIdentityTest)

TestRunner.RunAll()

; Exit non-zero on failure: CI reads the exit code, and a bare ExitApp reports
; success.
ExitApp(TestRunner.failures > 0 ? 1 : 0)
