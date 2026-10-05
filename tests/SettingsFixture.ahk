#Requires AutoHotkey v2.0
#Include ../Settings.ahk

; Writes one setting through the real save path, as the Settings dialog stores it.
; Callers point Settings.settingsFile at an isolated file first.
SetTestSetting(settingName, value) {
    return Settings.SaveValues(Map(settingName, value))
}
