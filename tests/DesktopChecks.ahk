#Requires AutoHotkey v2.0

; Pass/fail counting and output for the desktop runners. They cannot use TestRunner:
; its MsgBox override would hide the dialogs and windows they exist to exercise.
class DesktopChecks {
    static run := 0
    static failed := 0

    static Out(text) {
        FileAppend(text "`n", "*")
    }

    static Record(passed, label, detail := "") {
        this.run++
        if passed {
            this.Out("  ok   " label)
            return true
        }
        this.failed++
        this.Out("  FAIL " label (detail != "" ? " -- " detail : ""))
        return false
    }

    ; Prints the summary line and returns the process exit code.
    static Finish(unit) {
        this.Out("")
        this.Out(this.failed = 0
            ? "PASS - " this.run " " unit
            : "FAIL - " this.failed " of " this.run " " unit " failed")
        return this.failed = 0 ? 0 : 1
    }
}
