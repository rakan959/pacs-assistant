#Requires AutoHotkey v2.0
#Include TestRunner.ahk
#Include UpdateCheckerTest.ahk
#Include SettingsTest.ahk
#Include PACSMonitorTest.ahk
#Include HotkeyManagerTest.ahk
#Include ProfileManagerTest.ahk
#Include PACSCommandsTest.ahk

TestRunner.AddTest(UpdateCheckerTest)
TestRunner.AddTest(SettingsTest)
TestRunner.AddTest(PACSMonitorTest)
TestRunner.AddTest(HotkeyManagerTest)
TestRunner.AddTest(ProfileManagerTest)
TestRunner.AddTest(PACSCommandsTest)

TestRunner.RunAll()
ExitApp
