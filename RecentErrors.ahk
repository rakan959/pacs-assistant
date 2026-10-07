; = CONTENTS
;   + Preamble
;   + RecentErrors class (Help > Recent Errors: the end of error.log, and a copy
;       of it for a bug report)

#Requires AutoHotkey v2.0

#Include AppLog.ahk
#Include AppStorage.ahk
#Include ErrorText.ahk
#Include UITheme.ahk
#Include Version.ahk

class RecentErrors {
    ; Shown and copied at most: the newest part of a long log.
    static maxBytes := 64 * 1024

    /**
     * The end of a log file: its last maxBytes, starting at a whole line. Returns
     * "" for a missing or empty file.
     */
    static Tail(path, maxBytes := 0) {
        if !FileExist(path)
            return ""
        maxBytes := maxBytes ? maxBytes : this.maxBytes
        stream := FileOpen(path, "r", "UTF-8")
        try {
            size := stream.Length
            if (size > maxBytes) {
                stream.Pos := size - maxBytes
                text := stream.Read()
                ; The first line read is probably cut; start after it.
                lineEnd := InStr(text, "`n")
                text := lineEnd ? SubStr(text, lineEnd + 1) : text
            } else
                text := stream.Read()
        } finally stream.Close()
        return RTrim(text, "`r`n")
    }

    ; What Copy for Bug Report puts on the clipboard.
    static BugReportText(logText) {
        return "PACS Assistant " AppVersion.current " on Windows " A_OSVersion
            . "`n`n" (logText = "" ? "error.log is empty." : logText)
    }

    static Show(ownerGui := 0) {
        logText := this.Tail(AppLog.Path())
        window := UITheme.NewWindow(
            "PACS Assistant - Recent Errors",
            IsObject(ownerGui) ? "+Owner" ownerGui.Hwnd : ""
        )
        width := 640
        UITheme.AddHeading(window, "Recent errors", "xm ym w" width)
        UITheme.AddNote(
            window,
            "The newest entries in error.log, kept in the data folder. Check a copy for anything private before you send it.",
            "xm y+4 w" width
        )
        window.SetFont("s9", "Consolas")
        logBox := window.Add("Edit", "xm y+12 w" width " r18 ReadOnly -Wrap +HScroll Background" UITheme.panelColor,
            logText = "" ? "No errors have been recorded." : logText)
        UITheme.UseBodyFont(window)

        close := (*) => window.Destroy()
        footer := UITheme.AddFooter(
            window,
            width,
            [{text: "Close", default: true, action: close}],
            [
                {text: "&Copy for Bug Report", width: 160, action: (*) => (
                    A_Clipboard := this.BugReportText(logText),
                    window.Opt("+OwnDialogs"),
                    MsgBox("Copied. Paste it into your bug report.", "Recent Errors", "Iconi")
                )},
                {text: "Open Data &Folder", width: 140, action: (*) => this.OpenFolder(window)}
            ]
        )
        window.OnEvent("Close", close)
        window.OnEvent("Escape", close)
        UITheme.ShowDialog(window)
        ; Start at the newest entry, scrolled to its beginning so the timestamps
        ; show; an Edit scrolls only once it is shown.
        lastLine := SendMessage(0xBA, 0, 0, logBox) - 1        ; EM_GETLINECOUNT
        start := SendMessage(0xBB, lastLine, 0, logBox)        ; EM_LINEINDEX
        SendMessage(0xB1, start, start, logBox)                ; EM_SETSEL
        SendMessage(0xB7, 0, 0, logBox)                        ; EM_SCROLLCARET
        footer["Close"].Focus()
        return window
    }

    static OpenFolder(window) {
        try Run('explorer.exe "' AppStorage.DataRoot() '"')
        catch Any as err {
            window.Opt("+OwnDialogs")
            MsgBox("The data folder could not be opened.`n`n" ErrorText.Message(err), "Data Folder Unavailable", "Icon!")
        }
    }
}
