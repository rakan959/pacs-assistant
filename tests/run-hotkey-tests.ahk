#Requires AutoHotkey v2.0
#SingleInstance Off
#ErrorStdOut
#Warn All, StdOut
FileEncoding "UTF-8"

; Functional tests for hotkey registration. Unlike the unit suite in RunTests.ahk,
; these actually register hotkeys and synthesise keystrokes, so they exercise
; AutoHotkey's real enable/disable and HotIf behaviour rather than our model of it.
; That needs a real desktop, which is why CI does not run this one.
;
; The binds use keys a normal keyboard lacks: Ctrl+F13 for single hotkeys and F23/F24
; in combinations, so a registered bind swallows them before any window sees them.
; The alias check also needs a real prefix key, Esc & F24; it sends Esc only while
; that combination is registered, so Esc never reaches the active window.
;
; Run it with Invoke-AutoHotkeyChecked (README, "Tests"): AutoHotkey is a GUI-subsystem
; program, so a plain launch neither waits for the run nor reports its exit code.

#Include HarnessErrors.ahk
OnError(OnError_StdErr)

; Before execution reaches the class definitions included below (IsolatedStorage.ahk).
#Include IsolatedStorage.ahk
UseIsolatedDataRoot("pacs-assistant-hotkey-tests")

#Include ../HotkeyManager.ahk
#Include DesktopChecks.ahk

global fired := 0
global aliasFirstFired := 0
global aliasSecondFired := 0

Out(text) => DesktopChecks.Out(text)

; Same argument order as the unit suite's Assert.Equal.
AssertEqual(expected, actual, label) {
    return DesktopChecks.Record(actual == expected, label, "expected '" expected "', got '" actual "'")
}

Bump(*) {
    global fired
    fired++
}

BumpAliasFirst(*) {
    global aliasFirstFired
    aliasFirstFired++
}

BumpAliasSecond(*) {
    global aliasSecondFired
    aliasSecondFired++
}

; Sends a custom combination and reports how many times each alias callback ran
PressCombo(keys) {
    global aliasFirstFired, aliasSecondFired
    firstBefore := aliasFirstFired
    secondBefore := aliasSecondFired
    SendEvent(keys)
    loop 40 {
        Sleep(25)
        if (aliasFirstFired != firstBefore || aliasSecondFired != secondBefore)
            break
    }
    return {
        first: aliasFirstFired - firstBefore,
        second: aliasSecondFired - secondBefore
    }
}

; Sends Ctrl+F13 and reports how many times the bound action ran
Press() {
    global fired
    before := fired
    SendEvent("^{F13}")

    ; Hotkeys run on their own thread; give it a chance before concluding it did not fire
    loop 40 {
        Sleep(25)
        if (fired != before)
            break
    }
    return fired - before
}

Main() {
    ; Artificial keystrokes only trigger the script's own hotkeys above input level 0
    SendLevel(1)

    Out("PACS Assistant hotkey tests")
    Out("")

    ; A registered bind fires
    HotkeyManager.Register("Test", "^F13", Bump)
    AssertEqual(1, Press(), "a registered bind fires")

    ; ... and stops firing once disabled
    HotkeyManager.DisableAllHotkeys()
    AssertEqual(0, Press(), "a disabled bind does not fire")

    ; Issue #22. ApplyBinds disables everything and re-registers it on every profile
    ; load and keybind edit. Hotkey() updates an existing variant's action but leaves
    ; it disabled, so re-registration must pass "On" or the bind stays dead.
    HotkeyManager.Register("Test", "^F13", Bump)
    AssertEqual(1, Press(), "a bind re-registered after being disabled fires again")

    ; Repeated apply cycles, as happens when editing several keybinds in a row
    loop 3 {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.Register("Test", "^F13", Bump)
    }
    AssertEqual(1, Press(), "a bind survives repeated disable/re-register cycles")

    ; A scoped bind must not fire when its window is not active. Nothing in this test
    ; environment is PACS, so the predicate is false.
    HotkeyManager.Register("Test", "^F13", Bump, "PACS")
    AssertEqual(0, Press(), "a PACS-scoped bind does not fire outside PACS")

    ; ... and going back to an unscoped bind has to work, which means the scoped
    ; variant was torn down in the HotIf context it was created in
    HotkeyManager.Register("Test", "^F13", Bump, "Any")
    AssertEqual(1, Press(), "an unscoped bind fires again after being scoped")

    ; Unassigning clears the bind
    HotkeyManager.Register("Test", "", Bump)
    AssertEqual(0, Press(), "an unassigned bind does not fire")

    ; A rejected replacement must leave the known-good binding both tracked and live.
    HotkeyManager.Register("Test", "^F13", Bump)
    AssertEqual(
        false,
        HotkeyManager.Register("Test", "DefinitelyNotARealKeyName", Bump),
        "an invalid reassignment is rejected"
    )
    AssertEqual(1, Press(), "a rejected reassignment leaves the old bind active")

    ; Key aliases inside a custom combination are the same native variant. The
    ; second logical owner must be rejected instead of silently replacing the first.
    HotkeyManager.DisableAllHotkeys()
    aliasRegistered := AssertEqual(
        true,
        HotkeyManager.Register("AliasOne", "Esc & F24", BumpAliasFirst),
        "a custom combination with an aliased key registers"
    )
    AssertEqual(
        false,
        HotkeyManager.Register("AliasTwo", "Escape & F24", BumpAliasSecond),
        "an equivalent custom-combination alias is rejected"
    )
    ; Unregistered, Esc would reach whatever window is in front.
    if aliasRegistered {
        aliasResult := PressCombo("{Esc down}{F24}{Esc up}")
        AssertEqual(1, aliasResult.first, "the original aliased custom combination remains live")
        AssertEqual(0, aliasResult.second, "the rejected alias callback never replaces it")
    }

    ; Tilde/dollar on either side of a custom combination update the same native
    ; behavior variant; they cannot create a second logical owner.
    HotkeyManager.DisableAllHotkeys()
    AssertEqual(
        true,
        HotkeyManager.Register("BehaviorOne", "F23 & F24", BumpAliasFirst),
        "a custom combination registers before suffix behavior normalization"
    )
    AssertEqual(
        false,
        HotkeyManager.Register("BehaviorTwo", "F23 & ~F24", BumpAliasSecond),
        "a suffix-tilde equivalent combination is rejected"
    )
    behaviorResult := PressCombo("{F23 down}{F24}{F23 up}")
    AssertEqual(1, behaviorResult.first, "the original behavior combination remains live")
    AssertEqual(0, behaviorResult.second, "suffix tilde cannot replace its callback")

    HotkeyManager.DisableAllHotkeys()
    ExitApp(DesktopChecks.Finish("assertions"))
}

Main()
