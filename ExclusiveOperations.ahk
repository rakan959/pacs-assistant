#Requires AutoHotkey v2.0
#Include PACSCommands.ahk
#Include Settings.ahk

/**
 * The app-wide operations that must never overlap: a clinical command, key capture,
 * a profile mutation, a settings write, a dialog presentation and shutdown. Every
 * acquisition checks the others through Active, and main.ahk wires the same check
 * into PACSCommands, Settings and UpdateChecker, so the first user action already
 * observes one serialization policy.
 *
 * Clinical commands and settings writes keep their own flags (PACSCommands,
 * Settings); this class owns the other four leases.
 */
class ExclusiveOperations {
    ; In user-facing priority order: Active reports the first that is active.
    static kinds := [
        "clinical",
        "capture",
        "profileMutation",
        "settingsWrite",
        "uiPresentation",
        "shutdown"
    ]
    static captureActive := false
    ; Set when a capture could not be undone (its hook would not stop, or the prior
    ; shortcuts could not be restored). Its lease stays held so no clinical command
    ; runs on shortcuts that could not be verified, and its notice asks for a
    ; restart, which that lease must not refuse.
    static captureRestartRequired := false
    static profileMutationActive := false
    static profileMutationAction := ""
    static uiPresentationActive := false
    static uiPresentationAction := ""
    static shutdownActive := false
    static shutdownAction := ""

    /**
     * The first active exclusive operation, or "" when none is active.
     * @param ignoredKinds Kinds the caller tracks itself, such as its own lease
     * @returns One of kinds, or ""
     */
    static Active(ignoredKinds*) {
        for kind in this.kinds {
            ignored := false
            for ignoredKind in ignoredKinds {
                if (ignoredKind == kind) {
                    ignored := true
                    break
                }
            }
            if (!ignored && this.IsActive(kind))
                return kind
        }
        return ""
    }

    static IsActive(kind) {
        switch kind, true {
            case "clinical": return PACSCommands.clinicalCommandActive
            case "capture": return this.captureActive
            case "profileMutation": return this.profileMutationActive
            case "settingsWrite": return Settings.writeTransactionActive
            case "uiPresentation": return this.uiPresentationActive
            case "shutdown": return this.shutdownActive
        }
        throw ValueError("Unknown exclusive operation kind: " kind)
    }

    ; The leases shutdown itself may proceed past (see captureRestartRequired).
    static RestartExemption() {
        return this.captureRestartRequired ? ["capture"] : []
    }

    ; Profile saves during shutdown resolve dirty state on the way out, so they may
    ; ignore the shutdown lease, and whatever shutdown itself may proceed past.
    static ShutdownExemption(allowDuringShutdown) {
        if !allowDuringShutdown
            return []
        exemption := this.RestartExemption()
        exemption.Push("shutdown")
        return exemption
    }

    /**
     * Takes one of the leases this class owns, provided no exclusive operation
     * outside ignoredKinds is active. The check and the take are one Critical step.
     * @param kind "capture", "profileMutation", "uiPresentation" or "shutdown"
     * @param action What the holder is doing, for "wait for ..." messages
     * @returns true when the lease was taken
     */
    static TryBegin(kind, action := "", ignoredKinds*) {
        Critical("On")
        try {
            if (this.Active(ignoredKinds*) != "")
                return false
            this.SetLease(kind, true, action)
            return true
        } finally Critical("Off")
    }

    static End(kind) {
        Critical("On")
        try this.SetLease(kind, false, "")
        finally Critical("Off")
    }

    static SetLease(kind, active, action) {
        switch kind, true {
            case "capture":
                this.captureActive := active
            case "profileMutation":
                this.profileMutationAction := action
                this.profileMutationActive := active
            case "uiPresentation":
                this.uiPresentationAction := action
                this.uiPresentationActive := active
            case "shutdown":
                this.shutdownAction := action
                this.shutdownActive := active
            default:
                throw ValueError("ExclusiveOperations does not own the '" kind "' lease")
        }
    }
}
