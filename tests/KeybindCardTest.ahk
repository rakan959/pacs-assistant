#Requires AutoHotkey v2.0
#Include ../KeybindCard.ahk
#Include ../RecentErrors.ahk
#Include TestRunner.ahk

class KeybindCardTest {
    static tests := [
        "TestCardTextGroupsKeybindsAndNamesNarrowScopes",
        "TestCardPageEscapesNamesAndGroupsTables",
        "TestEmptyCardSaysSo",
        "TestLogTailKeepsWholeNewestLines",
        "TestMissingLogHasNoTail",
        "TestBugReportNamesTheVersion"
    ]

    static Rows() => [
        {group: "PowerScribe", name: "Sign Report", keybind: "Ctrl + F13", activeIn: "Any window"},
        {group: "PowerScribe", name: "Draft Report", keybind: "Ctrl + F14", activeIn: "PowerScribe"},
        {group: "Custom", name: "Custom: <b>Tom & Jerry</b>", keybind: "Ctrl + Alt + F14", activeIn: "PACS"}
    ]

    TestCardTextGroupsKeybindsAndNamesNarrowScopes() {
        expected := "Night keybinds`r`n`r`nPowerScribe`r`n  Ctrl + F13  Sign Report"
            . "`r`n  Ctrl + F14  Draft Report  (PowerScribe)`r`n`r`nCustom"
            . "`r`n  Ctrl + Alt + F14  Custom: <b>Tom & Jerry</b>  (PACS)"
        Assert.Equal(expected, KeybindCard.Text("Night", KeybindCardTest.Rows()))
    }

    TestCardPageEscapesNamesAndGroupsTables() {
        html := KeybindCard.Html("Night & Day", KeybindCardTest.Rows())
        Assert.True(InStr(html, "<title>Night &amp; Day keybinds</title>") > 0)
        Assert.True(InStr(html, "Custom: &lt;b&gt;Tom &amp; Jerry&lt;/b&gt;") > 0)
        Assert.False(InStr(html, "<b>Tom"))
        ; One table per group, every one closed.
        StrReplace(html, "<table>", "<table>", true, &opened)
        StrReplace(html, "</table>", "</table>", true, &closed)
        Assert.Equal(2, opened)
        Assert.Equal(2, closed)
    }

    TestEmptyCardSaysSo() {
        Assert.True(InStr(KeybindCard.Text("Night", []), "No keybinds are set.") > 0)
        Assert.True(InStr(KeybindCard.Html("Night", []), "No keybinds are set.") > 0)
    }

    TestLogTailKeepsWholeNewestLines() {
        path := A_Temp "\pacs-log-tail-" DllCall("GetCurrentProcessId") ".log"
        try {
            text := ""
            loop 50
                text .= "2026-10-06 03:00:00.000 entry " Format("{:03}", A_Index) "`n"
            FileOpen(path, "w", "UTF-8-RAW").Write(text)
            whole := RecentErrors.Tail(path, 100000)
            Assert.True(InStr(whole, "entry 001") = 25)
            tail := RecentErrors.Tail(path, 200)
            Assert.True(InStr(tail, "entry 050") > 0)
            Assert.False(InStr(tail, "entry 001"))
            ; Starts at a whole line, never mid-entry.
            Assert.Equal(1, InStr(tail, "2026-10-06"))
        } finally {
            try FileDelete(path)
        }
    }

    TestMissingLogHasNoTail() {
        Assert.Equal("", RecentErrors.Tail(A_Temp "\pacs-no-such-log-" DllCall("GetCurrentProcessId") ".log"))
    }

    TestBugReportNamesTheVersion() {
        report := RecentErrors.BugReportText("2026-10-06 03:00:00.000 something failed")
        Assert.Equal(1, InStr(report, "PACS Assistant " AppVersion.current " on Windows "))
        Assert.True(InStr(report, "something failed") > 0)
        Assert.True(InStr(RecentErrors.BugReportText(""), "error.log is empty.") > 0)
    }
}

