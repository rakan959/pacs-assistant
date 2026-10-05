#Requires AutoHotkey v2.0

/**
 * Small standards-compliant JSON parser used for GitHub release metadata. It keeps
 * asset fields in their owning object and decodes escapes in one pass, avoiding the
 * field-order and double-unescape failures of regular-expression extraction.
 */
class JsonParser {
    static nullValue := {isJsonNull: true}
    ; \G anchors each scan at the current position, so no suffix copy is needed.
    static plainRunPattern := '\G[^"\\\x00-\x1F]+'
    static numberPattern := "\G-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"
    static whitespacePattern := "\G[ \t\r\n]+"

    static Parse(text) {
        parser := JsonParser(text)
        value := parser.ParseValue()
        parser.SkipWhitespace()
        if (parser.position <= parser.length)
            throw ValueError("Unexpected content after JSON value", , parser.position)
        return value
    }

    __New(text) {
        if !(Type(text) == "String")
            throw TypeError("JSON input must be a string")
        this.text := text
        this.length := StrLen(text)
        this.position := 1
    }

    ParseValue() {
        this.SkipWhitespace()
        if (this.position > this.length)
            throw ValueError("Unexpected end of JSON input")

        char := this.Peek()
        switch char {
            case "{": return this.ParseObject()
            case "[": return this.ParseArray()
        }
        if (char == Chr(34))
            return this.ParseString()
        if (SubStr(this.text, this.position, 4) == "true") {
            this.position += 4
            return true
        }
        if (SubStr(this.text, this.position, 5) == "false") {
            this.position += 5
            return false
        }
        if (SubStr(this.text, this.position, 4) == "null") {
            this.position += 4
            return JsonParser.nullValue
        }
        return this.ParseNumber()
    }

    ParseObject() {
        result := Map()
        this.Expect("{")
        this.SkipWhitespace()
        if (this.Peek() == "}") {
            this.position++
            return result
        }

        loop {
            this.SkipWhitespace()
            if !(this.Peek() == Chr(34))
                throw ValueError("Expected a JSON object key", , this.position)
            key := this.ParseString()
            this.SkipWhitespace()
            this.Expect(":")
            if result.Has(key)
                throw ValueError("Duplicate key in JSON object: " key, , this.position)
            result[key] := this.ParseValue()
            this.SkipWhitespace()
            separator := this.Take()
            if (separator == "}")
                return result
            if !(separator == ",")
                throw ValueError("Expected ',' or '}' in JSON object", , this.position - 1)
        }
    }

    ParseArray() {
        result := []
        this.Expect("[")
        this.SkipWhitespace()
        if (this.Peek() == "]") {
            this.position++
            return result
        }

        loop {
            result.Push(this.ParseValue())
            this.SkipWhitespace()
            separator := this.Take()
            if (separator == "]")
                return result
            if !(separator == ",")
                throw ValueError("Expected ',' or ']' in JSON array", , this.position - 1)
        }
    }

    ParseString() {
        this.Expect(Chr(34))
        result := ""
        slash := Chr(92)
        quote := Chr(34)

        loop {
            ; Copy each run of ordinary characters in one step. Character-at-a-time
            ; appends made long release notes the dominant parse cost.
            if RegExMatch(this.text, JsonParser.plainRunPattern, &plainRun, this.position) {
                result .= plainRun[0]
                this.position += plainRun.Len[0]
            }
            if (this.position > this.length)
                throw ValueError("Unterminated JSON string")

            char := this.Take()
            if (char == quote)
                return result
            if !(char == slash)
                throw ValueError("Unescaped control character in JSON string", , this.position - 1)

            if (this.position > this.length)
                throw ValueError("Unterminated JSON escape sequence")
            escaped := this.Take()
            if (escaped == quote || escaped == slash || escaped == "/") {
                result .= escaped
            } else if (escaped == "b") {
                result .= Chr(8)
            } else if (escaped == "f") {
                result .= Chr(12)
            } else if (escaped == "n") {
                result .= "`n"
            } else if (escaped == "r") {
                result .= "`r"
            } else if (escaped == "t") {
                result .= "`t"
            } else if (escaped == "u") {
                result .= this.ParseUnicodeEscape()
            } else {
                throw ValueError("Invalid JSON escape sequence", , this.position - 1)
            }
        }
    }

    ParseUnicodeEscape() {
        high := this.ParseHexCodeUnit()
        if (high >= 0xD800 && high <= 0xDBFF) {
            if !(SubStr(this.text, this.position, 2) == "\u")
                throw ValueError("High surrogate is missing its low surrogate", , this.position)
            this.position += 2
            low := this.ParseHexCodeUnit()
            if (low < 0xDC00 || low > 0xDFFF)
                throw ValueError("Invalid low surrogate in JSON string", , this.position - 4)
            codePoint := 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
            return Chr(codePoint)
        }
        if (high >= 0xDC00 && high <= 0xDFFF)
            throw ValueError("Unexpected low surrogate in JSON string", , this.position - 4)
        return Chr(high)
    }

    ParseHexCodeUnit() {
        if (this.position + 3 > this.length)
            throw ValueError("Incomplete Unicode escape in JSON string")
        hex := SubStr(this.text, this.position, 4)
        if !RegExMatch(hex, "i)^[0-9a-f]{4}$")
            throw ValueError("Invalid Unicode escape in JSON string", , this.position)
        this.position += 4
        return Integer("0x" hex)
    }

    ParseNumber() {
        start := this.position
        if !RegExMatch(this.text, JsonParser.numberPattern, &match, start)
            throw ValueError("Expected a JSON value", , start)
        token := match[0]
        this.position += StrLen(token)
        ; Integer() wraps past the 64-bit range and Float() overflows to infinity;
        ; either would silently become a different number.
        if RegExMatch(token, "[.eE]") {
            value := Float(token)
            if !(Abs(value) <= 1.7976931348623157e308)
                throw ValueError("JSON number is outside the floating-point range", , start)
            return value
        }
        value := Integer(token)
        if (String(value) != token && token != "-0")
            throw ValueError("JSON number is outside the 64-bit integer range", , start)
        return value
    }

    SkipWhitespace() {
        if RegExMatch(this.text, JsonParser.whitespacePattern, &whitespace, this.position)
            this.position += whitespace.Len[0]
    }

    Peek() {
        return this.position <= this.length ? SubStr(this.text, this.position, 1) : ""
    }

    Take() {
        if (this.position > this.length)
            throw ValueError("Unexpected end of JSON input")
        char := SubStr(this.text, this.position, 1)
        this.position++
        return char
    }

    Expect(expected) {
        actual := this.Take()
        if !(actual == expected)
            throw ValueError("Expected '" expected "' but found '" actual "'", , this.position - 1)
    }
}
