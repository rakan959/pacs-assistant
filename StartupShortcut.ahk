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

    /**
     * Whether the shortcut starts this build. One left by a copy that has since
     * moved does not count: the option then shows off, and turning it on replaces
     * the shortcut.
     */
    static IsEnabled() {
        if !FileExist(this.Path())
            return false
        try FileGetShortcut(this.Path(), &target,, &arguments)
        catch
            return false
        expected := this.Expected()
        return target = expected.target && arguments = expected.arguments
    }

    ; What starts this build: the EXE, or for a source run the interpreter with
    ; this script.
    static Expected() => A_IsCompiled
        ? {target: A_ScriptFullPath, arguments: ""}
        : {target: A_AhkPath, arguments: '"' A_ScriptFullPath '"'}

    static Enable() {
        expected := this.Expected()
        FileCreateShortcut(expected.target, this.Path(), A_ScriptDir, expected.arguments, "PACS Assistant")
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
