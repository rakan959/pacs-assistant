; = CONTENTS
;   + Preamble
;   + KeybindCard class (Help > Keybind Card as text to copy and as a page to
;       print)

#Requires AutoHotkey v2.0

#Include Version.ahk

/**
 * A profile's set keybinds as a reference card. Rows are {group, name, keybind,
 * activeIn}, in the main list's order (KeybindGUI.KeybindCardRows).
 */
class KeybindCard {
    ; Plain text for the clipboard: one line per keybind under its group.
    static Text(profileName, rows) {
        text := profileName " keybinds"
        group := ""
        for row in rows {
            if !(row.group == group) {
                group := row.group
                text .= "`r`n`r`n" group
            }
            text .= "`r`n  " row.keybind "  " row.name this.ScopeSuffix(row)
        }
        if !rows.Length
            text .= "`r`n`r`nNo keybinds are set."
        return text
    }

    ; A page to print: the groups as tables, keybinds first.
    static Html(profileName, rows) {
        title := this.Escape(profileName) " keybinds"
        html := "<!doctype html>`n<html lang=`"en`"><head><meta charset=`"utf-8`"><title>" title "</title>`n<style>"
            . "body{font-family:'Segoe UI',Arial,sans-serif;font-size:11pt;color:#1b1b1b;margin:2em auto;max-width:44em}"
            . "h1{font-size:18pt;font-weight:600;margin:0 0 .2em}p.note{color:#5e5e5e;margin:0 0 1.2em}"
            . "h2{font-size:12pt;font-weight:600;margin:1.2em 0 .3em;border-bottom:1px solid #e1e1e1}"
            . "table{border-collapse:collapse;width:100%}td{padding:.25em .5em .25em 0;vertical-align:top}"
            . "td.key{white-space:nowrap;font-weight:600;width:14em}td.scope{color:#5e5e5e;white-space:nowrap;text-align:right}"
            . "@media print{body{margin:0}}</style></head><body>`n"
            . "<h1>" title "</h1><p class=`"note`">PACS Assistant " this.Escape(AppVersion.current)
            . ", printed " FormatTime(, "MMMM d, yyyy") "</p>`n"
        group := ""
        open := false
        for row in rows {
            if !(row.group == group) {
                if open
                    html .= "</table>`n"
                group := row.group
                html .= "<h2>" this.Escape(group) "</h2><table>`n"
                open := true
            }
            html .= "<tr><td class=`"key`">" this.Escape(row.keybind) "</td><td>" this.Escape(row.name)
                . "</td><td class=`"scope`">" this.Escape(row.activeIn == "Any window" ? "" : row.activeIn) "</td></tr>`n"
        }
        if open
            html .= "</table>`n"
        if !rows.Length
            html .= "<p>No keybinds are set.</p>`n"
        return html "</body></html>`n"
    }

    /**
     * Writes the printable page to the temp folder and opens it in the default
     * browser, where it can be printed.
     * @returns the page's path
     */
    static OpenPrintable(profileName, rows) {
        path := A_Temp "\PACS Assistant keybinds - " profileName ".html"
        stream := FileOpen(path, "w", "UTF-8")
        try stream.Write(this.Html(profileName, rows))
        finally stream.Close()
        Run('"' path '"')
        return path
    }

    static ScopeSuffix(row) => row.activeIn == "Any window" ? "" : "  (" row.activeIn ")"

    static Escape(text) {
        text := StrReplace(text, "&", "&amp;")
        text := StrReplace(text, "<", "&lt;")
        text := StrReplace(text, ">", "&gt;")
        return StrReplace(text, '"', "&quot;")
    }
}
