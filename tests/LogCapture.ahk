#Requires AutoHotkey v2.0
#Include ../AppLog.ahk
#Include TestRunner.ahk

; Points AppLog at a fresh folder so a test can assert what was logged. Only
; AppLog resolves the data root per write; Settings and ProfileManager keep the
; paths they fixed at initialization. Call Restore in Teardown or finally.
class LogCapture {
    __New() {
        this.originalDataRoot := AppStorage.dataRootOverride
        this.root := TestTempPath("pacs-log-capture")
        AppStorage.dataRootOverride := this.root
    }

    Text() {
        path := this.root "\" AppLog.fileName
        return FileExist(path) ? FileRead(path) : ""
    }

    ; Logged entries whose text contains needle.
    Count(needle) {
        count := 0
        for line in StrSplit(this.Text(), "`n") {
            if InStr(line, needle)
                count++
        }
        return count
    }

    Restore() {
        AppStorage.dataRootOverride := this.originalDataRoot
        try DirDelete(this.root, true)
    }
}
