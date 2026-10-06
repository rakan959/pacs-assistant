#Requires AutoHotkey v2.0

/**
 * The result dialogs of clinical commands. A command runs under the clinical lease,
 * which refuses every other clinical command and pauses background monitoring, so a
 * dialog left open under it would block both until the user dismissed it. While
 * PACSCommands.RunClinicalCommand holds the lease, notices are queued and shown in
 * order once it has released the lease; at any other time they show at once.
 *
 * A prompt whose answer the command needs is not a notice and stays modal under
 * the lease.
 */
class ClinicalNotices {
    static deferring := false
    static deferred := []
    static presenter := (text, title, options) => MsgBox(text, title, options)

    static Show(text, title, options := "") {
        if this.deferring
            this.deferred.Push({text: text, title: title, options: options})
        else
            this.presenter.Call(text, title, options)
    }

    ; Queues notices from now on; RunClinicalCommand calls this once it holds the lease.
    static Defer() {
        this.deferring := true
    }

    ; Stops queueing and shows the queued notices; RunClinicalCommand calls this
    ; after releasing the lease.
    static ShowDeferred() {
        this.deferring := false
        notices := this.deferred
        this.deferred := []
        for notice in notices
            this.presenter.Call(notice.text, notice.title, notice.options)
    }
}
