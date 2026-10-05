#Requires AutoHotkey v2.0

/**
 * Text renderings of thrown values. AutoHotkey v2 can throw any value, so code that
 * reports a failure must not assume an Error object with a Message property.
 */
class ErrorText {
    /**
     * The human-readable message of a thrown value.
     * @param thrown Any value caught by `catch Any`, an Error object in the usual case
     * @returns The Message property when present, otherwise the value's string form,
     * otherwise its type name (an object without ToString cannot be converted)
     */
    static Message(thrown) {
        if (IsObject(thrown) && HasProp(thrown, "Message"))
            return String(thrown.Message)
        try return String(thrown)
        return Type(thrown)
    }

    /**
     * One diagnostic line: type, message, and where the error was raised.
     * @param thrown Any caught value
     * @returns For example "TypeError: Expected a Number (in Foo) at C:\app\x.ahk:12"
     */
    static Describe(thrown) {
        text := Type(thrown) ": " this.Message(thrown)
        if !IsObject(thrown)
            return text
        if (HasProp(thrown, "What") && thrown.What != "")
            text .= " (in " thrown.What ")"
        if (HasProp(thrown, "File") && HasProp(thrown, "Line"))
            text .= " at " thrown.File ":" thrown.Line
        return text
    }
}
