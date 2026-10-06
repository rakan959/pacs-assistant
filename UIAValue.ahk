#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Safe reads of a UIA element's value.
 *
 * UIA-v2's `element.Value` accessor tries ValuePattern, then RangeValuePattern, then
 * the legacy accessibility pattern. Pattern support is a capability boundary rather
 * than an application failure: the Sticky Notes field, for example, does not
 * support ValuePattern. Reads therefore go through plain property lookups.
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
        ; those states apart.
        legacySupported := false
        try legacySupported := element.GetPropertyValue(UIA.Property.IsLegacyIAccessiblePatternAvailable) ? true : false

        return {supported: legacyRead && legacySupported, value: ""}
    }
}
