#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off

; Functional tests for hotkey registration. Unlike the unit suite in RunTests.ahk,
; these actually register hotkeys and synthesise keystrokes, so they exercise
; AutoHotkey's real enable/disable and HotIf behaviour rather than our model of it.
; That needs a real desktop, which is why CI does not run this one.
;
; Ctrl+F13 is used throughout: there is no physical F13 on a normal keyboard, and
; while the hotkey is registered AutoHotkey swallows it, so nothing reaches the
; active window.
;
; Run with:
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" tests\run-hotkey-tests.ahk

#Include ../HotkeyManager.ahk

global Fired := 0
global TestsRun := 0
global TestsFailed := 0

Out(text) {
    FileAppend(text "`n", "*")
}

AssertEqual(actual, expected, label) {
    global TestsRun, TestsFailed
    TestsRun++
    if (actual == expected) {
        Out("  ok   " label)
        return
    }
    TestsFailed++
    Out("  FAIL " label " -- expected '" expected "', got '" actual "'")
}

Bump(*) {
    global Fired
    Fired++
}

; Sends Ctrl+F13 and reports how many times the bound action ran
Press() {
    global Fired
    before := Fired
    SendEvent("^{F13}")

    ; Hotkeys run on their own thread; give it a chance before concluding it did not fire
    Loop 40 {
        Sleep(25)
        if (Fired != before)
            break
    }
    return Fired - before
}

Main() {
    global TestsRun, TestsFailed

    ; Artificial keystrokes only trigger the script's own hotkeys above input level 0
    SendLevel(1)

    Out("PACS Assistant hotkey tests")
    Out("")

    ; A registered bind fires
    HotkeyManager.Register("Test", "^F13", Bump)
    AssertEqual(Press(), 1, "a registered bind fires")

    ; ... and stops firing once disabled
    HotkeyManager.DisableAllHotkeys()
    AssertEqual(Press(), 0, "a disabled bind does not fire")

    ; Regression for issue #22. ApplyBinds disables everything and re-registers it,
    ; which happens on every profile load and every keybind edit. Hotkey() updates an
    ; existing variant's action but leaves it disabled, so without the explicit "On"
    ; the re-registered bind stayed dead and binds "broke" for no visible reason.
    HotkeyManager.Register("Test", "^F13", Bump)
    AssertEqual(Press(), 1, "a bind re-registered after being disabled fires again")

    ; Repeated apply cycles, as happens when editing several keybinds in a row
    Loop 3 {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.Register("Test", "^F13", Bump)
    }
    AssertEqual(Press(), 1, "a bind survives repeated disable/re-register cycles")

    ; A scoped bind must not fire when its window is not active. Nothing in this test
    ; environment is PACS, so the predicate is false.
    HotkeyManager.Register("Test", "^F13", Bump, "PACS")
    AssertEqual(Press(), 0, "a PACS-scoped bind does not fire outside PACS")

    ; ... and going back to an unscoped bind has to work, which means the scoped
    ; variant was torn down in the HotIf context it was created in
    HotkeyManager.Register("Test", "^F13", Bump, "Any")
    AssertEqual(Press(), 1, "an unscoped bind fires again after being scoped")

    ; Unassigning clears the bind
    HotkeyManager.Register("Test", "", Bump)
    AssertEqual(Press(), 0, "an unassigned bind does not fire")

    ; A rejected replacement must leave the known-good binding both tracked and live.
    HotkeyManager.Register("Test", "^F13", Bump)
    AssertEqual(
        HotkeyManager.Register("Test", "DefinitelyNotARealKeyName", Bump),
        false,
        "an invalid reassignment is rejected"
    )
    AssertEqual(Press(), 1, "a rejected reassignment leaves the old bind active")

    HotkeyManager.DisableAllHotkeys()

    ; Settings writes its ini next to the running script on load
    try FileDelete(A_ScriptDir "\settings.ini")

    Out("")
    Out(TestsFailed = 0
        ? "PASS - " TestsRun " assertions"
        : "FAIL - " TestsFailed " of " TestsRun " assertions failed")

    ExitApp(TestsFailed = 0 ? 0 : 1)
}

Main()
