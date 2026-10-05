#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Identity comparison for UIA element wrappers. Two wrappers can represent the same
 * provider element, so callers that revalidate a target before acting compare
 * through UIA rather than by object identity alone.
 */
class UIAElementIdentity {
    /**
     * Whether two wrappers are the same element. A provider comparison failure
     * counts as "not the same", which makes revalidation fail closed.
     */
    static Same(left, right) {
        if (!left || !right)
            return false
        if (ObjPtr(left) = ObjPtr(right))
            return true
        try return UIA.CompareElementsEx(left, right)
        return false
    }

    /**
     * As Same, but a provider comparison failure propagates so the caller can
     * treat it as an unknown state rather than a mismatch.
     */
    static SameStrict(left, right) {
        if (!left || !right)
            return false
        if (ObjPtr(left) = ObjPtr(right))
            return true
        return UIA.CompareElementsEx(left, right)
    }

    ; Whether a list already holds the same element as candidate.
    static Contains(elements, candidate) {
        for existing in elements {
            if this.Same(existing, candidate)
                return true
        }
        return false
    }
}
