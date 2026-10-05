#Requires AutoHotkey v2.0
#Include ../ErrorText.ahk
#Include TestRunner.ahk

class ErrorTextTest {
    static tests := [
        "MessageHandlesEveryThrownValueKind",
        "DescribeNamesTypeFunctionAndLocation"
    ]

    MessageHandlesEveryThrownValueKind() {
        Assert.Equal("disk full", ErrorText.Message(Error("disk full")))
        Assert.True(InStr(ErrorText.Message(OSError(112)), "(112)"), "OSError messages carry the Win32 code")
        Assert.Equal("plain text", ErrorText.Message("plain text"))
        Assert.Equal("42", ErrorText.Message(42))
        ; An object without Message or ToString cannot be converted to text.
        Assert.Equal("Object", ErrorText.Message({}))
        Assert.Equal("Map", ErrorText.Message(Map()))
    }

    DescribeNamesTypeFunctionAndLocation() {
        try
            throw ValueError("bad interval", "SaveSettings")
        catch Any as err
            described := ErrorText.Describe(err)

        Assert.True(InStr(described, "ValueError: bad interval (in SaveSettings) at ") = 1, described)
        Assert.True(InStr(described, "ErrorTextTest.ahk:"), described)
        Assert.Equal("String: plain text", ErrorText.Describe("plain text"))
    }
}
