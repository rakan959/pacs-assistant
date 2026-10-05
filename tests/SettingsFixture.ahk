#Requires AutoHotkey v2.0
#Include ../Settings.ahk
#Include TestRunner.ahk

; Writes one setting through the real save path, as the Settings dialog stores it.
; Callers point Settings at an isolated file first (UseTestSettings).
SetTestSetting(settingName, value) {
    return Settings.SaveValues(Map(settingName, value))
}

; Points Settings at a fresh temporary file, for a test that saves settings.
; @returns the file and revision that RestoreTestSettings puts back
UseTestSettings(prefix) {
    saved := {settingsFile: Settings.settingsFile, revision: Settings.revision}
    Settings.settingsFile := TestTempPath(prefix, ".ini")
    return saved
}

; Deletes the temporary settings file and restores what UseTestSettings replaced.
RestoreTestSettings(saved) {
    try FileDelete(Settings.settingsFile)
    Settings.settingsFile := saved.settingsFile
    Settings.revision := saved.revision
}
