#Requires AutoHotkey v2.0
#Include ../AppLog.ahk
#Include TestRunner.ahk
#Include LogCapture.ahk

class AppLogTest {
    static tests := [
        "WriteAppendsTimestampedLines",
        "WriteErrorRecordsTypeLocationAndStack",
        "WriteNeverThrows"
    ]

    Setup() {
        this.capturedLog := LogCapture()
    }

    Teardown() {
        this.capturedLog.Restore()
    }

    WriteAppendsTimestampedLines() {
        Assert.True(AppLog.Write("first"))
        Assert.True(AppLog.Write("second"))

        lines := StrSplit(RTrim(this.capturedLog.Text(), "`n"), "`n")
        Assert.Equal(2, lines.Length)
        Assert.True(lines[1] ~= "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} first$", lines[1])
        Assert.True(lines[2] ~= " second$", lines[2])
    }

    WriteErrorRecordsTypeLocationAndStack() {
        try
            throw ValueError("bad interval", "SaveSettings")
        catch Any as err
            thrown := err

        Assert.True(AppLog.WriteError(thrown))
        Assert.True(AppLog.WriteError("plain text"))
        Assert.True(AppLog.WriteError(thrown, "Saving settings"))

        text := this.capturedLog.Text()
        Assert.True(InStr(text, " ValueError: bad interval (in SaveSettings) at "), text)
        Assert.True(InStr(text, "`n" RTrim(thrown.Stack, "`r`n") "`n"), "The call stack follows the entry")
        Assert.True(InStr(text, " String: plain text`n"), text)
        Assert.True(InStr(text, " Saving settings: ValueError: bad interval (in SaveSettings) at "), text)
    }

    WriteNeverThrows() {
        ; A data root that is a file cannot hold the log.
        blocker := this.capturedLog.root ".blocker"
        FileAppend("", blocker)
        AppStorage.dataRootOverride := blocker
        try {
            Assert.False(AppLog.Write("lost"))
            Assert.False(AppLog.WriteError(Error("lost")))
        } finally FileDelete(blocker)
    }
}
