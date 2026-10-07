#Requires AutoHotkey v2.0
#Include ../StatusPanel.ahk
#Include TestRunner.ahk

class StatusPanelTest {
    static tests := [
        "TestKeybindRowWarnsWhenSomeAreNotLive",
        "TestWindowRowsNeedExactlyOneWindow",
        "TestScanningSaysWhyItIsNotRunning",
        "TestScanningReportsTheLastReadAndFailures",
        "TestMicrophoneRowReportsTheLastSelectionOrError",
        "TestUpdateRowNamesAnAvailableVersion",
        "TestUpdateRowNeedsASuccessfulCheck"
    ]

    TestKeybindRowWarnsWhenSomeAreNotLive() {
        Assert.Equal("ok", StatusPanel.KeybindState("9 keybinds active").tone)
        Assert.Equal("warn", StatusPanel.KeybindState("8 of 9 keybinds active").tone)
        Assert.Equal("warn", StatusPanel.KeybindState("Keybinds suspended").tone)
        Assert.Equal("off", StatusPanel.KeybindState("No keybinds set").tone)
    }

    TestWindowRowsNeedExactlyOneWindow() {
        Assert.Equal("Not open", StatusPanel.WindowState("PowerScribe", 0).value)
        Assert.Equal("ok", StatusPanel.WindowState("PowerScribe", 1).tone)
        two := StatusPanel.WindowState("PowerScribe", 2)
        Assert.Equal("warn", two.tone)
        Assert.True(InStr(two.value, "exactly one") > 0)
    }

    TestScanningSaysWhyItIsNotRunning() {
        Assert.Equal("Off", StatusPanel.ScanState(false, true, 60, "", 0, "").value)
        waiting := StatusPanel.ScanState(true, false, 60, "", 0, "")
        Assert.Equal("warn", waiting.tone)
        Assert.True(InStr(waiting.value, "sound or notification") > 0)
    }

    TestScanningReportsTheLastReadAndFailures() {
        fresh := StatusPanel.ScanState(true, true, 60, "", 0, "")
        Assert.Equal("Every 60 seconds; no scan yet", fresh.value)
        read := StatusPanel.ScanState(true, true, 30, "20261006143005", 0, "")
        Assert.Equal("Every 30 seconds; last read at 2:30:05 PM", read.value)
        Assert.Equal("ok", read.tone)
        failing := StatusPanel.ScanState(true, true, 30, "20261006143005", 2, "Explorer Portal is not open")
        Assert.Equal("warn", failing.tone)
        Assert.True(InStr(failing.value, "The last attempt failed: Explorer Portal is not open") > 0)
    }

    TestMicrophoneRowReportsTheLastSelectionOrError() {
        Assert.Equal("off", StatusPanel.MicrophoneState(false, "PowerMic", 0, "").tone)
        Assert.Equal("off", StatusPanel.MicrophoneState(true, "", 0, "").tone)
        pending := StatusPanel.MicrophoneState(true, "PowerMic", 0, "")
        Assert.True(InStr(pending.value, "next PowerScribe login") > 0)
        done := StatusPanel.MicrophoneState(true, "PowerMic", {name: "Nuance PowerMic III", time: "20261006071500"}, "")
        Assert.Equal("'Nuance PowerMic III' selected at 7:15 AM", done.value)
        failed := StatusPanel.MicrophoneState(true, "PowerMic", 0, "the microphone list changed")
        Assert.Equal("warn", failed.tone)
    }

    TestUpdateRowNamesAnAvailableVersion() {
        Assert.Equal("off", StatusPanel.UpdateState(false, true, 0).tone)
        Assert.Equal("Automatic checks are off", StatusPanel.UpdateState(true, false, 0).value)
        available := StatusPanel.UpdateState(true, true, {hasUpdate: true, latestVersion: "v2.1.0"})
        Assert.Equal("warn", available.tone)
        Assert.True(InStr(available.value, "v2.1.0 is available") = 1)
    }

    ; Up to date only once a check has succeeded; a failure says so.
    TestUpdateRowNeedsASuccessfulCheck() {
        waiting := StatusPanel.UpdateState(true, true, 0)
        Assert.Equal("off", waiting.tone)
        Assert.Equal("Checked automatically; no check has finished yet", waiting.value)
        today := SubStr(A_Now, 1, 8) "141500"
        checked := StatusPanel.UpdateState(true, true, 0, today)
        Assert.Equal("ok", checked.tone)
        Assert.Equal("Up to date as of 2:15 PM; checked automatically", checked.value)
        earlier := StatusPanel.UpdateState(true, false, 0, "20261001090500")
        Assert.Equal("Up to date as of Oct 1, 9:05 AM; automatic checks are off", earlier.value)
        failed := StatusPanel.UpdateState(true, true, 0, today, "The server could not be reached")
        Assert.Equal("warn", failed.tone)
        Assert.Equal("The last check failed: The server could not be reached", failed.value)
    }
}
