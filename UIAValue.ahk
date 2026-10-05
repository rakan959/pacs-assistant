#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Safe access to a UIA element's value.
 *
 * UIA-v2's `element.Value` accessor tries ValuePattern, then RangeValuePattern, then
 * the legacy accessibility pattern, and on a failed write replaces the error with a
 * generic one. Pattern support is a capability boundary rather than an application
 * failure: the Sticky Notes field, for example, does not support ValuePattern.
 *
 * Reads therefore go through plain property lookups. A write is gated on
 * ValuePattern being available and calls ValuePattern.SetValue directly: one write
 * through the pattern the caller chose, and that pattern's own error if it fails.
 */
class UIAValue {
    /**
     * Reads an element's value without instantiating a pattern and reports whether
     * an empty value is supported or merely UIA's default for an absent pattern.
     * Falls back to the legacy accessibility value. Unlike UIA-v2's Value getter it
     * uses property lookups only and does not try RangeValuePattern.
     * @returns {supported, value}
     */
    static TryRead(element) {
        valueRead := false
        text := ""
        try {
            text := element.GetPropertyValue(UIA.Property.ValueValue)
            valueRead := true
            if (text != "")
                return {supported: true, value: text}
        }

        valueSupported := false
        try valueSupported := element.GetPropertyValue(UIA.Property.IsValuePatternAvailable) ? true : false
        if (valueRead && valueSupported)
            return {supported: true, value: ""}

        legacyRead := false
        text := ""
        try {
            text := element.GetPropertyValue(UIA.Property.LegacyIAccessibleValue)
            legacyRead := true
            if (text != "")
                return {supported: true, value: text}
        }

        ; An empty value is valid, but the property APIs also return an empty default
        ; for unsupported patterns. Capability flags are the only safe way to tell
        ; those states apart before a direct-write transaction.
        legacySupported := false
        try legacySupported := element.GetPropertyValue(UIA.Property.IsLegacyIAccessiblePatternAvailable) ? true : false

        return {supported: legacyRead && legacySupported, value: ""}
    }

    ; Whether this element can be written through ValuePattern
    static CanWrite(element) {
        try {
            return element.GetPropertyValue(UIA.Property.IsValuePatternAvailable) ? true : false
        }
        return false
    }

    /**
     * Writes a value through ValuePattern only, when the element supports it.
     * @returns true if the write was attempted and did not throw; false when the
     * element has no ValuePattern, so the caller can pick another strategy instead
     * of retrying something that cannot work.
     */
    static Write(element, text) {
        if !this.CanWrite(element)
            return false

        element.ValuePattern.SetValue(text)
        return true
    }
}
