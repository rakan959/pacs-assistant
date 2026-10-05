#Requires AutoHotkey v2.0

; Stands in for the UI-presentation lease that the settings and update dialogs bind
; through their dialogAcquire/dialogRelease (and, for settings, the unavailable
; notifier) seams. Counts each call; Acquire returns the configured result.
class FakePresentationLease {
    __New(acquireResult := true) {
        this.acquireResult := acquireResult
        this.acquireCalls := 0
        this.releaseCalls := 0
        this.notificationCalls := 0
    }

    Acquire(*) {
        this.acquireCalls++
        return this.acquireResult
    }

    Release(*) {
        this.releaseCalls++
    }

    Notify(*) {
        this.notificationCalls++
    }
}
