#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Safe access to a UIA element's value.
 *
 * Reading or writing `element.Value` goes through UIA-v2's ValuePattern accessor,
 * which throws when an element does not support the pattern. UIA-v2 v1.1.3 fixed
 * the destructor failure that originally made this unsafe (issue #32), but pattern
 * support is still a capability boundary rather than an exceptional application
 * failure. The Sticky Notes field, for example, does not support ValuePattern.
 *
 * Reads therefore go through plain property lookups, and writes are gated on the
 * pattern actually being available. This also keeps the clinical adapter stable if
 * UIA-v2 changes its unsupported-pattern error behavior again.
 */
class UIAValue {
    /**
     * Reads an element's value without instantiating a pattern and reports whether
     * an empty value is supported or merely UIA's default for an absent pattern.
     * Falls back to the legacy accessibility value, mirroring what UIA-v2's own
     * Value getter tries, minus the unsafe pattern construction.
     * @returns {supported, value}
     */
    static TryRead(element) {
        try {
            text := element.GetPropertyValue(UIA.Property.ValueValue)
            if (text != "")
                return {supported: true, value: text}
        }

        try {
            text := element.GetPropertyValue(UIA.Property.LegacyIAccessibleValue)
            if (text != "")
                return {supported: true, value: text}
        }

        ; An empty value is valid, but the property APIs also return an empty default
        ; for unsupported patterns. Capability flags are the only safe way to tell
        ; those states apart before a destructive replace-and-rollback transaction.
        valueSupported := false
        legacySupported := false
        try valueSupported := element.GetPropertyValue(UIA.Property.IsValuePatternAvailable) ? true : false
        try legacySupported := element.GetPropertyValue(UIA.Property.IsLegacyIAccessiblePatternAvailable) ? true : false

        return {supported: valueSupported || legacySupported, value: ""}
    }

    static Read(element) {
        return this.TryRead(element).value
    }

    ; Whether this element can be written through ValuePattern
    static CanWrite(element) {
        try {
            return element.GetPropertyValue(UIA.Property.IsValuePatternAvailable) ? true : false
        }
        return false
    }

    /**
     * Writes a value only when the element supports it.
     * @returns true if the write was attempted and did not throw; false when the
     * element has no ValuePattern, so the caller can pick another strategy instead
     * of retrying something that cannot work.
     */
    static Write(element, text) {
        if !this.CanWrite(element)
            return false

        try {
            element.Value := text
            return true
        }

        return false
    }
}
