; = CONTENTS
;   + Preamble
;   + StartupShortcut class (start PACS Assistant when the user signs in)

#Requires AutoHotkey v2.0

/**
 * "Start when I sign in to Windows" is a shortcut in the user's Startup folder.
 * The shortcut itself is the setting: there is nothing in settings.ini to drift
 * from it, and removing it by hand in Explorer turns the option off.
 */
class StartupShortcut {
    static folder := A_Startup
    static fileName := "PACS Assistant.lnk"

    static Path() => this.folder "\" this.fileName

    static IsEnabled() => !!FileExist(this.Path())

    ; Creates the shortcut to this build: the EXE, or for a source run the
    ; interpreter with this script.
    static Enable() {
        if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, this.Path(), A_ScriptDir,, "PACS Assistant")
        else
            FileCreateShortcut(A_AhkPath, this.Path(), A_ScriptDir, '"' A_ScriptFullPath '"', "PACS Assistant")
    }

    static Disable() {
        if FileExist(this.Path())
            FileDelete(this.Path())
    }

    static Set(enabled) {
        if enabled
            this.Enable()
        else
            this.Disable()
    }
}
