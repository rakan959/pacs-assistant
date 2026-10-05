#Requires AutoHotkey v2.0
#Include AppStorage.ahk
#Include ErrorText.ahk

/**
 * The persistent diagnostic record: timestamped lines appended to error.log in the
 * app's data folder. A dialog or OutputDebug line leaves nothing behind on a
 * clinical workstation, so failures worth diagnosing later are written here.
 * Background pollers log once per failure episode, not per poll.
 */
class AppLog {
    static fileName := "error.log"

    ; Where entries are written; the updater appends its own failures here too.
    static Path() {
        return AppStorage.DataRoot() "\" this.fileName
    }

    /**
     * Appends "<yyyy-MM-dd HH:mm:ss.mmm> <text>". Never throws: a logging failure
     * must not mask or replace the failure being logged.
     * @returns true when the entry was written
     */
    static Write(text) {
        try {
            root := AppStorage.DataRoot()
            DirCreate(root)
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "." A_MSec " " text "`n", root "\" this.fileName)
            return true
        } catch Any {
            return false
        }
    }

    ; Logs a thrown value with its type, location and call stack.
    static WriteError(thrown) {
        entry := ErrorText.Describe(thrown)
        if (IsObject(thrown) && HasProp(thrown, "Stack") && thrown.Stack != "")
            entry .= "`n" RTrim(thrown.Stack, "`r`n")
        return this.Write(entry)
    }
}
