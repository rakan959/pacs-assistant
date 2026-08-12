#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off

; Headless tests for the parts of PACS Assistant that do not need PACS, PowerScribe
; or a GUI. Run with:
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" tests\run-tests.ahk
; Exits 0 if everything passed, 1 otherwise.

#Include ../PACSCommands.ahk
#Include ../ProfileManager.ahk
#Include ../HotkeyManager.ahk
#Include ../Settings.ahk

global TestsRun := 0
global TestsFailed := 0
global TempDir := A_Temp "\pacs-assistant-tests"

Out(text) {
    FileAppend(text "`n", "*")
}

Assert(condition, label) {
    global TestsRun, TestsFailed
    TestsRun++
    if condition {
        Out("  ok   " label)
        return
    }
    TestsFailed++
    Out("  FAIL " label)
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

Section(name) {
    Out("")
    Out(name)
}

; ---------------------------------------------------------------------------
; ReportModality: which reading section a report belongs to (issue #25)
; ---------------------------------------------------------------------------
TestReportModality() {
    Section("ReportModality.Classify")

    AssertEqual(ReportModality.Classify("EXAMINATION: CT ABDOMEN AND PELVIS"), "Body", "CT abdomen/pelvis is Body")
    AssertEqual(ReportModality.Classify("EXAMINATION: XR ABDOMEN"), "Body", "XR abdomen is Body")
    AssertEqual(ReportModality.Classify("EXAMINATION: CT CHEST WITH CONTRAST"), "Chest", "CT chest is Chest")
    AssertEqual(ReportModality.Classify("EXAMINATION: MRI BRAIN"), "Neuro", "MRI brain is Neuro")
    AssertEqual(ReportModality.Classify("EXAMINATION: CT HEAD WITHOUT CONTRAST"), "Neuro", "CT head is Neuro")
    AssertEqual(ReportModality.Classify("EXAMINATION: NM BONE SCAN"), "Nucs", "NM is Nucs")

    ; Order matters: the Peds rules are ultrasound studies, so they have to be
    ; evaluated before the catch-all ultrasound rule
    AssertEqual(ReportModality.Classify("EXAMINATION: US RIGHT LOWER QUADRANT"), "Peds", "US RLQ is Peds, not Ultrasound")
    AssertEqual(ReportModality.Classify("EXAMINATION: US NEUROSONOGRAPHY"), "Peds", "US neurosonography is Peds")
    AssertEqual(ReportModality.Classify("EXAMINATION: US RENAL"), "Ultrasound", "other US is Ultrasound")

    ; Anything unmatched falls through to MSK, as it did before assignments existed
    AssertEqual(ReportModality.Classify("EXAMINATION: XR KNEE"), "MSK", "unmatched study is MSK")
    AssertEqual(ReportModality.Classify(""), "MSK", "empty report is MSK")

    ; Case insensitivity
    AssertEqual(ReportModality.Classify("examination: ct chest"), "Chest", "classification is case insensitive")

    ; Every modality the classifier can return must be assignable in the GUI
    for rule in ReportModality.rules {
        found := false
        for name in ReportModality.names {
            if (name == rule.name)
                found := true
        }
        Assert(found, "modality '" rule.name "' is listed in ReportModality.names")
    }
    fallbackListed := false
    for name in ReportModality.names {
        if (name == ReportModality.fallback)
            fallbackListed := true
    }
    Assert(fallbackListed, "fallback modality is listed in ReportModality.names")
}

; ---------------------------------------------------------------------------
; Alert sounds (issue #16)
; ---------------------------------------------------------------------------
TestAlertSounds() {
    Section("Settings alert sounds")

    ; Sound names written by older versions keep working
    AssertEqual(Settings.NormalizeSoundName("Default"), "Default Beep", "legacy 'Default' maps forward")
    AssertEqual(Settings.NormalizeSoundName("Asterisk"), "Notification", "legacy 'Asterisk' maps forward")
    AssertEqual(Settings.NormalizeSoundName("Exclamation"), "Chime", "legacy 'Exclamation' maps forward")
    AssertEqual(Settings.NormalizeSoundName("Hand"), "Chord", "legacy 'Hand' maps forward")
    AssertEqual(Settings.NormalizeSoundName("Question"), "Ding", "legacy 'Question' maps forward")

    AssertEqual(Settings.NormalizeSoundName("Chime"), "Chime", "current name passes through")
    AssertEqual(Settings.NormalizeSoundName("nonsense"), "Default Beep", "unknown name falls back")

    ; The legacy names have to land on entries that actually exist
    for legacy, current in Settings.legacySoundAliases {
        found := false
        for name in Settings.alertSounds {
            if (name == current)
                found := true
        }
        Assert(found, "legacy '" legacy "' maps to a selectable sound")
    }

    ; The regression itself: every named sound has to resolve to its own distinct
    ; file. The old implementation routed five names through MessageBeep, where the
    ; stock Windows scheme collapsed them onto two files and one silence.
    seen := Map()
    for name, file in Settings.soundFiles {
        path := Settings.ResolveSoundFile(name)
        Assert(path != "", "'" name "' resolves to a file (" file ")")
        if (path != "") {
            Assert(!seen.Has(path), "'" name "' resolves to a file no other sound uses")
            seen[path] := name
        }
    }
    AssertEqual(seen.Count, Settings.soundFiles.Count, "every alert sound is audibly distinct")

    ; "Default Beep" and "Custom File" are handled separately and have no file
    AssertEqual(Settings.ResolveSoundFile("Default Beep"), "", "'Default Beep' has no backing file")
    AssertEqual(Settings.ResolveSoundFile("Custom File"), "", "'Custom File' has no backing file")

    ; The dropdown selects the right row for a stored legacy value
    AssertEqual(Settings.alertSounds[Settings.FindSoundIndex("Asterisk")], "Notification", "legacy value selects its replacement")
    AssertEqual(Settings.alertSounds[Settings.FindSoundIndex("Tada")], "Tada", "current value selects itself")
    AssertEqual(Settings.alertSounds[Settings.FindSoundIndex("nonsense")], "Default Beep", "unknown value selects the default")
}

; ---------------------------------------------------------------------------
; Keybind scopes (issue #19)
; ---------------------------------------------------------------------------
TestScopes() {
    Section("HotkeyManager scopes")

    AssertEqual(HotkeyManager.ScopeFromFlags(false, false), "Any", "neither box checked is Any")
    AssertEqual(HotkeyManager.ScopeFromFlags(true, false), "PACS", "PACS box only")
    AssertEqual(HotkeyManager.ScopeFromFlags(false, true), "PowerScribe", "PowerScribe box only")
    AssertEqual(HotkeyManager.ScopeFromFlags(true, true), "PACS or PowerScribe", "both boxes checked")

    ; Checkbox state and stored scope have to agree in both directions, or the
    ; scope dialog would silently rewrite a scope just by being opened
    for scope in HotkeyManager.scopes {
        flags := HotkeyManager.FlagsFromScope(scope)
        AssertEqual(HotkeyManager.ScopeFromFlags(flags.requirePACS, flags.requirePowerScribe), scope, "'" scope "' round-trips through the checkboxes")
    }

    AssertEqual(HotkeyManager.NormalizeScope("nonsense"), "Any", "unknown scope falls back to Any")
    AssertEqual(HotkeyManager.NormalizeScope(""), "Any", "blank scope falls back to Any")
    AssertEqual(HotkeyManager.NormalizeScope("PACS"), "PACS", "known scope passes through")

    ; Every scope except Any needs a predicate, otherwise it would register globally
    for scope in HotkeyManager.scopes {
        if (scope == "Any") {
            Assert(!HotkeyManager.scopePredicates.Has(scope), "'Any' has no predicate")
            continue
        }
        Assert(HotkeyManager.scopePredicates.Has(scope), "'" scope "' has a HotIf predicate")
    }

    ; The predicates must be stable objects: AutoHotkey identifies a hotkey variant
    ; by the exact function object, so a fresh closure per call would leak variants
    for scope, predicate in HotkeyManager.scopePredicates {
        Assert(predicate == HotkeyManager.scopePredicates[scope], "'" scope "' predicate is a stable object")
    }
}

; ---------------------------------------------------------------------------
; Profile persistence (issues #19 and #25)
; ---------------------------------------------------------------------------
TestProfilePersistence() {
    global TempDir
    Section("ProfileManager persistence")

    profile := ProfileManager.NewProfile()
    profile.binds["Sign Report"] := "^s"
    profile.scopes["Sign Report"] := "PowerScribe"
    profile.binds["Next Series"] := "^n"
    profile.scopes["Next Series"] := "PACS or PowerScribe"
    profile.binds["Draft Report"] := "^d"
    ; Deliberately no scope for Draft Report - it must default to Any
    profile.modalityAttendings["Neuro"] := "Smith"
    profile.modalityAttendings["Chest"] := ""  ; configured as "leave the default"

    ProfileManager.SaveProfile("RoundTrip", profile)
    reloaded := ProfileManager.LoadProfile(TempDir "\profiles\RoundTrip.ini")

    AssertEqual(reloaded.binds["Sign Report"], "^s", "bind survives a save/load round trip")
    AssertEqual(reloaded.scopes["Sign Report"], "PowerScribe", "scope survives a save/load round trip")
    AssertEqual(reloaded.scopes["Next Series"], "PACS or PowerScribe", "multi-window scope survives")
    AssertEqual(reloaded.scopes["Draft Report"], "Any", "a bind saved without a scope reloads as Any")

    AssertEqual(reloaded.modalityAttendings["Neuro"], "Smith", "modality attending survives")
    Assert(reloaded.modalityAttendings.Has("Chest"), "a blank attending stays configured rather than vanishing")
    AssertEqual(reloaded.modalityAttendings["Chest"], "", "a blank attending reloads blank")
    Assert(!reloaded.modalityAttendings.Has("Body"), "an unconfigured modality is not invented")

    ; Attending lookup semantics
    ProfileManager.profiles["RoundTrip"] := reloaded
    ProfileManager.currentProfile := "RoundTrip"
    AssertEqual(ProfileManager.GetModalityAttending("Neuro"), "Smith", "configured modality returns its attending")
    AssertEqual(ProfileManager.GetModalityAttending("Chest"), "", "modality configured blank returns blank (keep PowerScribe default)")
    AssertEqual(ProfileManager.GetModalityAttending("Body"), "Body", "unconfigured modality falls back to the modality name")

    AssertEqual(ProfileManager.GetScope("Sign Report"), "PowerScribe", "GetScope reads the current profile")
    AssertEqual(ProfileManager.GetScope("Not Bound"), "Any", "GetScope defaults to Any")
}

; ---------------------------------------------------------------------------
; A profile written by an older version has no [Scopes] or [ModalityAttendings]
; ---------------------------------------------------------------------------
TestLegacyProfile() {
    global TempDir
    Section("Legacy profile compatibility")

    path := TempDir "\legacy.ini"
    try FileDelete(path)
    IniWrite("Sign Report|Custom: Yell|", path, "Functions", "Order")
    IniWrite("^s", path, "Keybinds", "Sign Report")
    IniWrite("!y", path, "Keybinds", "Custom: Yell")
    IniWrite("HELLO", path, "CustomFunctions", "Custom: Yell_keys")
    IniWrite("", path, "CustomFunctions", "Custom: Yell_window")

    legacy := ProfileManager.LoadProfile(path)

    AssertEqual(legacy.binds["Sign Report"], "^s", "legacy bind loads")
    AssertEqual(legacy.scopes["Sign Report"], "Any", "legacy bind defaults to Any scope")
    AssertEqual(legacy.binds["Custom: Yell"], "!y", "legacy custom bind loads")
    Assert(legacy.customFuncs.Has("Custom: Yell"), "legacy custom function is rebuilt")
    AssertEqual(legacy.customFuncs["Custom: Yell"].keys, "HELLO", "legacy custom keys survive")
    AssertEqual(legacy.modalityAttendings.Count, 0, "legacy profile has no modality assignments")

    ; And re-saving a legacy profile must not lose anything
    ProfileManager.SaveProfile("LegacyResaved", legacy)
    resaved := ProfileManager.LoadProfile(TempDir "\profiles\LegacyResaved.ini")
    AssertEqual(resaved.binds["Sign Report"], "^s", "bind survives re-save")
    AssertEqual(resaved.scopes["Sign Report"], "Any", "scope is written on re-save")
    AssertEqual(resaved.customFuncs["Custom: Yell"].keys, "HELLO", "custom function survives re-save")
}

; ---------------------------------------------------------------------------

Main() {
    global TestsRun, TestsFailed, TempDir

    ; Profiles are written relative to the working directory
    try DirDelete(TempDir, true)
    DirCreate(TempDir)
    SetWorkingDir(TempDir)

    Out("PACS Assistant tests")

    TestReportModality()
    TestAlertSounds()
    TestScopes()
    TestProfilePersistence()
    TestLegacyProfile()

    SetWorkingDir(A_ScriptDir)
    try DirDelete(TempDir, true)
    ; Settings creates its ini next to the running script on load
    try FileDelete(A_ScriptDir "\settings.ini")

    Out("")
    Out(TestsFailed = 0
        ? "PASS - " TestsRun " assertions"
        : "FAIL - " TestsFailed " of " TestsRun " assertions failed")

    ExitApp(TestsFailed = 0 ? 0 : 1)
}

Main()
