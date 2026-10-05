#Requires AutoHotkey v2.0
#Include ../PACSCommands.ahk
#Include ../PowerScribe.ahk
#Include TestRunner.ahk

class PACSCommandsTest {
    static tests := [
        "TestBuiltInCommandsExist",
        "TestEachBuiltInCommandRunsUnderItsOwnName",
        "TestCreateCustomKeybindStoresConfig",
        "TestModalityClassification",
        "TestModalityNamesCoverEveryRule",
        "TestLooksLikeReport",
        "TestEpicToggleFailsClosedWithoutCapturedIdentity"
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
            "Next Series",
            "Previous Series",
            "Set PowerScribe Microphone"
        ]

        for name in required {
            Assert.True(PACSCommands.commands.Has(name), "Missing command: " name)
            Assert.True(HasMethod(PACSCommands.commands[name], "Call"), "Command not callable: " name)
        }
        ; Profiles persist these names, so an unlisted addition must be deliberate.
        Assert.Equal(required.Length, PACSCommands.commands.Count)
    }

    ; Driven while another command holds the lease: the refusal names the command
    ; that was not started, without running any action.
    TestEachBuiltInCommandRunsUnderItsOwnName() {
        originalActive := PACSCommands.clinicalCommandActive
        originalActiveName := PACSCommands.activeClinicalCommand
        originalNotifier := PACSCommands.busyNotifier
        notices := []
        PACSCommands.busyNotifier := (text, *) => notices.Push(text)
        PACSCommands.clinicalCommandActive := true
        PACSCommands.activeClinicalCommand := "Other Command"
        try {
            for name, command in PACSCommands.commands {
                Assert.False(command.Call())
                Assert.Equal("'Other Command' is still running. '" name "' was not started.", notices[notices.Length])
            }
        } finally {
            PACSCommands.clinicalCommandActive := originalActive
            PACSCommands.activeClinicalCommand := originalActiveName
            PACSCommands.busyNotifier := originalNotifier
        }
        Assert.Equal(PACSCommands.commands.Count, notices.Length)
    }

    TestCreateCustomKeybindStoresConfig() {
        callback := PACSCommands.CreateCustomKeybind("^c")
        Assert.Equal("^c", callback.keys)
        Assert.Equal("", callback.window)

        targetedCallback := PACSCommands.CreateCustomKeybind("^v", "TargetWindow")
        Assert.Equal("^v", targetedCallback.keys)
        Assert.Equal("TargetWindow", targetedCallback.window)
    }

    TestModalityClassification() {
        Assert.Equal("Body", ReportModality.Classify("EXAMINATION: CT ABDOMEN AND PELVIS"))
        Assert.Equal("Body", ReportModality.Classify("EXAMINATION: XR ABDOMEN"))
        Assert.Equal("Chest", ReportModality.Classify("EXAMINATION: CT CHEST"))
        Assert.Equal("Chest", ReportModality.Classify("EXAMINATION: CT CHEST WITH CONTRAST"))
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: MRI BRAIN"))
        ; MR and MRI name the same modality, as in the MSK rule.
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: MR BRAIN WITHOUT CONTRAST"))
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: MR CERVICAL SPINE"))
        Assert.Equal("Body", ReportModality.Classify("EXAMINATION: MR ABDOMEN"))
        Assert.Equal("Body", ReportModality.Classify("EXAMINATION: MRCP"))
        Assert.Equal("Neuro", ReportModality.Classify("EXAMINATION: MRA HEAD"))
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
    ; so the fixed positional path is only a fallback (issue #28)
    TestLooksLikeReport() {
        Assert.True(PowerScribe.LooksLikeReport("EXAMINATION: CT CHEST`n`nFINDINGS: ..."))
        Assert.True(PowerScribe.LooksLikeReport("examination: mri brain"))
        Assert.False(PowerScribe.LooksLikeReport(""))
        Assert.False(PowerScribe.LooksLikeReport("Smith, John"))
        Assert.False(PowerScribe.LooksLikeReport("Search"))
    }

    TestEpicToggleFailsClosedWithoutCapturedIdentity() {
        originalNotifier := PACSCommands.unavailableNotifier
        notifications := []
        PACSCommands.unavailableNotifier := RecordNotification.Bind(notifications)
        try result := PACSCommands.ToggleEpicWindow()
        finally PACSCommands.unavailableNotifier := originalNotifier

        Assert.False(result)
        Assert.Equal(1, notifications.Length)
        Assert.True(InStr(notifications[1].text, "manually") > 0)
    }
}
