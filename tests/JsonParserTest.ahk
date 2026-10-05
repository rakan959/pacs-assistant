#Requires AutoHotkey v2.0
#Include ../JsonParser.ahk
#Include TestRunner.ahk

class JsonParserTest {
    static tests := [
        "TestParsesNestedValuesAcrossWhitespace",
        "TestParsesNumberForms",
        "TestHandlesEscapesAndUnicode",
        "TestLongStringRoundTripsExactly",
        "TestRejectsUppercaseTokensAndEscapes",
        "TestRejectsMalformedStructure"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "AssertAllRejected"
    ]

    TestParsesNestedValuesAcrossWhitespace() {
        parsed := JsonParser.Parse(' `r`n`t{ "a" : [ 1 , { "b" : null } , true , false ] ,`n "c" : "" } `n')
        Assert.Equal(1, parsed["a"][1])
        Assert.True(parsed["a"][2]["b"] == JsonParser.nullValue, "null must parse to the shared null sentinel")
        Assert.Equal(true, parsed["a"][3])
        Assert.Equal(false, parsed["a"][4])
        Assert.Equal("", parsed["c"])
        Assert.Equal(0, JsonParser.Parse("{}").Count)
        Assert.Equal(0, JsonParser.Parse("[]").Length)
    }

    TestParsesNumberForms() {
        parsed := JsonParser.Parse("[0,-7,1550000,2.5,-0.25,1e3,6E-2,123456789012]")
        Assert.Equal(0, parsed[1])
        Assert.Equal(-7, parsed[2])
        Assert.Equal(1550000, parsed[3])
        Assert.Equal(2.5, parsed[4])
        Assert.Equal(-0.25, parsed[5])
        Assert.Equal(1000.0, parsed[6])
        Assert.Equal(0.06, parsed[7])
        Assert.Equal(123456789012, parsed[8])
    }

    TestHandlesEscapesAndUnicode() {
        ; Raw (unescaped) non-ASCII characters, built with Chr so this file stays ASCII.
        parsed := JsonParser.Parse('{"text":"line 1\nquote: \"ok\"; slash: \\n; solidus: \/; tab:\t; smile: '
            . Chr(0x263A) '; emoji: ' Chr(0x1F600) '"}')
        Assert.Equal(
            "line 1`nquote: `"ok`"; slash: \n; solidus: /; tab:`t; smile: " Chr(0x263A) "; emoji: " Chr(0x1F600),
            parsed["text"]
        )
    }

    TestLongStringRoundTripsExactly() {
        expected := ""
        loop 400
            expected .= "- fix(updater): line " A_Index " with `"quotes`", a \ slash and " Chr(0x263A) "`n"
        encoded := StrReplace(StrReplace(StrReplace(expected, "\", "\\"), '"', '\"'), "`n", "\n")
        parsed := JsonParser.Parse('{"body":"' encoded '","size":42}')
        Assert.Equal(expected, parsed["body"])
        Assert.Equal(42, parsed["size"])
    }

    TestRejectsUppercaseTokensAndEscapes() {
        invalidCases := [
            {input: "TRUE", error: "Expected a JSON value"},
            {input: "False", error: "Expected a JSON value"},
            {input: "NULL", error: "Expected a JSON value"},
            {input: '"\N"', error: "Invalid JSON escape sequence"},
            {input: '"\U263A"', error: "Invalid JSON escape sequence"}
        ]
        this.AssertAllRejected(invalidCases)
    }

    TestRejectsMalformedStructure() {
        invalidCases := [
            {input: '"unterminated', error: "Unterminated JSON string"},
            {input: '"ends in escape\', error: "Unterminated JSON escape sequence"},
            {input: '"tab`there"', error: "Unescaped control character"},
            {input: '"line`nbreak"', error: "Unescaped control character"},
            {input: '"\uD83D"', error: "High surrogate is missing its low surrogate"},
            {input: '"\uDE00"', error: "Unexpected low surrogate"},
            {input: '"\u26"', error: "Incomplete Unicode escape"},
            {input: "01", error: "Unexpected content after JSON value"},
            {input: "-", error: "Expected a JSON value"},
            {input: "1.", error: "Unexpected content after JSON value"},
            {input: '{"a":1,"a":2}', error: "Duplicate key"},
            {input: '{"a" 1}', error: "Expected ':'"},
            {input: '{"a":1,}', error: "Expected a JSON object key"},
            {input: "[1 2]", error: "Expected ',' or ']'"},
            {input: "[1,", error: "Unexpected end of JSON input"},
            {input: "", error: "Unexpected end of JSON input"},
            {input: "{} {}", error: "Unexpected content after JSON value"}
        ]
        this.AssertAllRejected(invalidCases)
    }

    AssertAllRejected(invalidCases) {
        for invalidCase in invalidCases {
            Assert.Throws(
                ObjBindMethod(JsonParser, "Parse", invalidCase.input),
                invalidCase.error,
                "Invalid JSON was not rejected as expected: " invalidCase.input
            )
        }
    }
}
