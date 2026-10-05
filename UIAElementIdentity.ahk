#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

/**
 * Identity comparison for UIA element wrappers. Two wrappers can represent the same
 * provider element, so callers that revalidate a target before acting compare
 * through UIA rather than by object identity alone.
 *
 * The comparison is UIA-v2's CompareElementsEx: elements are the same when the
 * provider says so, or otherwise when their type, name (ignoring case), class
 * name, AutomationId and on-screen rectangle are all equal. CompareElements misses
 * true matches on some providers, which is why the library adds the property
 * check. Two distinct elements pass it only when they show the same role and name
 * in the same place, such as two identically named items of one collapsed list.
 */
class UIAElementIdentity {
    /**
     * Whether two wrappers are the same element. An element whose properties
     * cannot be read counts as "not the same", which makes revalidation fail closed.
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
     * As Same, but a property-read failure propagates so the caller can treat it as
     * an unknown state rather than a mismatch.
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
