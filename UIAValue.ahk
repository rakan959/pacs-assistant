#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Safe access to a UIA element's value.
 *
 * Reading or writing `element.Value` goes through UIA-v2's ValuePattern accessor,
 * and that accessor is unsafe on an element that does not support the pattern:
 *
 *     GetPattern()  ComCall(16, ...) succeeds but yields a null pattern pointer
 *     __New(0)      throws ValueError before it defines this.ptr
 *     __Delete()    later calls Release(), which reads the ptr that was never set
 *
 * The ValueError is catchable, but the destructor error is not - AutoHotkey reports
 * it separately ("__Delete will now return"), so a surrounding try does nothing and
 * an error dialog lands in the middle of a clinical workflow. That is issue #32,
 * hit on the Sticky Notes field, which does not support ValuePattern.
 *
 * Reads therefore go through plain property lookups, which never build a pattern
 * object, and writes are gated on the pattern actually being available.
 */
class UIAValue {
    /**
     * Reads an element's value without instantiating a pattern.
     * Falls back to the legacy accessibility value, mirroring what UIA-v2's own
     * Value getter tries, minus the unsafe pattern construction.
     * @returns the value, or "" if the element exposes none
     */
    static Read(element) {
        try {
            text := element.GetPropertyValue(UIA.Property.ValueValue)
            if (text != "")
                return text
        }

        try {
            text := element.GetPropertyValue(UIA.Property.LegacyIAccessibleValue)
            if (text != "")
                return text
        }

        return ""
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
