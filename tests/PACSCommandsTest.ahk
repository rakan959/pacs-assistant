#Requires AutoHotkey v2.0
#Include ../PACSCommands.ahk
#Include ../PowerScribe.ahk
#Include TestRunner.ahk

class PACSCommandsTest {
    static Tests := [
        "TestBuiltInCommandsExist",
        "TestCreateCustomKeybindStoresConfig",
        "TestModalityClassification",
        "TestModalityNamesCoverEveryRule",
        "TestLooksLikeReport",
        "TestPowerScribeToggleUsesExactTarget"
    ]

    TestBuiltInCommandsExist() {
        required := [
            "Toggle Dictation",
            "Select Next Field",
            "Select Previous Field",
            "Delete Previous Word",
            "Delete Next Word",
            "Draft Report",
            "Sign Report",
            "Open/Force Restart PACS",
            "Paste Wet Read",
            "Toggle PowerScribe Window",
            "Toggle EPIC Window",
            "Set PowerScribe Microphone"
        ]
        
        for name in required {
            Assert.True(PACSCommands.commands.Has(name), "Missing command: " name)
            Assert.True(IsObject(PACSCommands.commands[name]), "Command not callable: " name)
        }
    }
    
    TestCreateCustomKeybindStoresConfig() {
        func := PACSCommands.CreateCustomKeybind("^c")
        Assert.Equal("^c", func.keys)
        Assert.Equal("", func.window)
        
        func2 := PACSCommands.CreateCustomKeybind("^v", "TargetWindow")
        Assert.Equal("^v", func2.keys)
        Assert.Equal("TargetWindow", func2.window)
    }

    TestModalityClassification() {
        Assert.Equal("Body", ReportModality.Classify("EXAMINATION: CT ABDOMEN AND PELVIS"))
        Assert.Equal("Body", ReportModality.Classify("EXAMINATION: XR ABDOMEN"))
        Assert.Equal("Chest", ReportModality.Classify("EXAMINATION: CT CHEST"))
        Assert.Equal("Chest", ReportModality.Classify("EXAMINATION: CT CHEST WITH CONTRAST"))
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: MRI BRAIN"))
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: CT HEAD WITHOUT CONTRAST"))
        Assert.Equal("Nucs", ReportModality.Classify("EXAMINATION: NM BONE SCAN"))
        ; The Peds rules are ultrasounds, so they must beat the catch-all US rule
        Assert.Equal("Peds", ReportModality.Classify("EXAMINATION: US RIGHT LOWER QUADRANT"))
        Assert.Equal("Peds", ReportModality.Classify("EXAMINATION: US NEUROSONOGRAPHY"))
        Assert.Equal("Ultrasound", ReportModality.Classify("EXAMINATION: US RENAL"))
        ; Known musculoskeletal examinations route explicitly.
        Assert.Equal("MSK", ReportModality.Classify("EXAMINATION: XR KNEE"))
        Assert.Equal("MSK", ReportModality.Classify("EXAMINATION: MRI SHOULDER"))
        ; Malformed and newly named examinations fail closed instead of silently
        ; assigning the MSK attending.
        Assert.Equal("Unknown", ReportModality.Classify("EXAMINATION: PET UNKNOWN PROTOCOL"))
        Assert.Equal("Unknown", ReportModality.Classify(""))
        ; Matching is case insensitive
        Assert.Equal("Chest", ReportModality.Classify("examination: ct chest"))
    }

    ; Every modality the classifier can return has to be assignable in the GUI,
    ; otherwise a study routes to a modality with no attending field
    TestModalityNamesCoverEveryRule() {
        for rule in ReportModality.rules {
            found := false
            for name in ReportModality.names {
                if (name == rule.name)
                    found := true
            }
            Assert.True(found, "Modality not listed in names: " rule.name)
        }

        Assert.Equal("Unknown", ReportModality.fallback)
    }

    ; Picks the report body out of the other text fields in the PowerScribe window,
    ; so the report no longer has to be found by a fixed positional path (issue #28)
    TestLooksLikeReport() {
        Assert.True(PowerScribe.LooksLikeReport("EXAMINATION: CT CHEST`n`nFINDINGS: ..."))
        Assert.True(PowerScribe.LooksLikeReport("examination: mri brain"))
        Assert.False(PowerScribe.LooksLikeReport(""))
        Assert.False(PowerScribe.LooksLikeReport("Smith, John"))
        Assert.False(PowerScribe.LooksLikeReport("Search"))
    }

    TestPowerScribeToggleUsesExactTarget() {
        Assert.Equal(PowerScribe.windowTitle, PACSCommands.PowerScribeToggleTarget())
    }
}
