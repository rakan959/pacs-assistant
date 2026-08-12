#Requires AutoHotkey v2.0
#Include ../PACSCommands.ahk
#Include TestRunner.ahk

class PACSCommandsTest {
    static Tests := [
        "TestBuiltInCommandsExist",
        "TestCreateCustomKeybindStoresConfig",
        "TestModalityClassification",
        "TestLooksLikeReport"
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
        Assert.Equal("Chest", ReportModality.Classify("EXAMINATION: CT CHEST"))
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: MRI BRAIN"))
        Assert.Equal("Nucs", ReportModality.Classify("EXAMINATION: NM BONE SCAN"))
        ; The Peds rules are ultrasounds, so they must beat the catch-all US rule
        Assert.Equal("Peds", ReportModality.Classify("EXAMINATION: US RIGHT LOWER QUADRANT"))
        Assert.Equal("Ultrasound", ReportModality.Classify("EXAMINATION: US RENAL"))
        ; Anything unmatched falls through to MSK
        Assert.Equal("MSK", ReportModality.Classify("EXAMINATION: XR KNEE"))
    }

    ; Picks the report body out of the other text fields in the PowerScribe window,
    ; so the report no longer has to be found by a fixed positional path (issue #28)
    TestLooksLikeReport() {
        Assert.True(PACSCommands.LooksLikeReport("EXAMINATION: CT CHEST`n`nFINDINGS: ..."))
        Assert.True(PACSCommands.LooksLikeReport("examination: mri brain"))
        Assert.False(PACSCommands.LooksLikeReport(""))
        Assert.False(PACSCommands.LooksLikeReport("Smith, John"))
        Assert.False(PACSCommands.LooksLikeReport("Search"))
    }
}
