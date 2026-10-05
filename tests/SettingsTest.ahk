#Requires AutoHotkey v2.0
#Include ../Settings.ahk
#Include TestRunner.ahk

class SettingsTest {
    static tests := [
        "TestDefaultSettingsLoaded",
        "TestSaveAndGetValues",
        "TestMutationGuardRejectsSettingsWrite",
        "TestPresentationLeaseRejectsSettingsWindowBeforeCreation",
        "TestMalformedPersistedSettingsUseDefaults",
        "TestExcessivePersistedRefreshIntervalUsesDefault",
        "TestSavingRejectsNonWholeRefreshInterval",
        "TestSavingRejectsExcessiveRefreshInterval",
        "TestAlertSoundsAreDistinct",
        "TestLegacyAliasesAreSelectable",
        "TestLegacySoundNamesMigrate",
        "TestFindSoundIndexFallback",
        "TestFailedBatchPreservesOriginalFile",
        "TestConcurrentSettingsWriteCannotBeLostByBatchReplace",
        "TestBatchPreservesUnmanagedSettings",
        "TestSavingSettingsNotifiesListeners",
        "TestStaleSettingsDialogCannotOverwriteNewerSave",
        "TestSettingsDialogCannotOverwriteAWriteDuringValidation",
        "TestSavingSettingsReportsListenerFailures",
        "TestChangeListenersAllRun",
        "TestChangeListenerFailureDoesNotBlockLaterListeners",
        "TestSettingsLayoutFitsScaled768p",
        "TestSavingRejectsRefreshIntervalOutsideBounds",
        "TestSavingAcceptsRefreshIntervalBounds",
        "TestPersistedRefreshIntervalBounds",
        "TestSavingRequiresMicrophoneNameWhenSwapEnabled",
        "TestSaveFailureKeepsDialogOpenAndFileUnchanged",
        "TestChangeListenerMustBeCallable"
    ]

    Setup() {
        this.originalFile := Settings.settingsFile
        this.originalListeners := Settings.changeListeners
        this.originalRevision := Settings.revision
        this.originalMutationGuard := Settings.mutationGuard
        this.originalDialogAcquire := Settings.HasOwnProp("dialogAcquire")
            ? Settings.dialogAcquire
            : 0
        this.originalDialogRelease := Settings.HasOwnProp("dialogRelease")
            ? Settings.dialogRelease
            : 0
        this.originalDialogUnavailableNotifier := Settings.HasOwnProp("dialogUnavailableNotifier")
            ? Settings.dialogUnavailableNotifier
            : 0
        this.originalWriteTransactionActive := Settings.writeTransactionActive
        this.tempFile := TestTempPath("settings-test", ".ini")
        Settings.settingsFile := this.tempFile
        Settings.changeListeners := []
        Settings.mutationGuard := (*) => true
        Settings.dialogAcquire := (*) => true
        Settings.dialogRelease := (*) => 0
        Settings.dialogUnavailableNotifier := (*) => 0
        Settings.writeTransactionActive := false
        Settings.SaveAllSettings()
    }
    
    TestDefaultSettingsLoaded() {
        Assert.True(Settings.Get("AutoUpdate"))
        Assert.True(Settings.Get("SkipBetaVersions"))
        Assert.Equal("", Settings.Get("SkippedUpdateVersion"))
        Assert.False(Settings.Get("AutoRefreshPACS"))
        Assert.Equal(60, Settings.Get("RefreshInterval"))
        Assert.False(Settings.Get("AudioAlertNewCase"))
        Assert.False(Settings.Get("MessageBoxNewCase"))
        Assert.True(Settings.Get("AutoConvertWetReadLineEndings"))
        Assert.True(Settings.Get("RestrictHotkeysByActiveWindow"))
        Assert.Equal("Default Beep", Settings.Get("AlertSound"))
        Assert.Equal("", Settings.Get("CustomSoundFile"))
        Assert.False(Settings.Get("SwapMicrophoneOnLogin"))
        Assert.Equal("", Settings.Get("MicrophoneName"))
    }
    
    TestSaveAndGetValues() {
        SetTestSetting("RefreshInterval", 45)
        Assert.Equal(45, Settings.Get("RefreshInterval"))
        
        SetTestSetting("AutoUpdate", false)
        Assert.False(Settings.Get("AutoUpdate"))

        SetTestSetting("AutoConvertWetReadLineEndings", false)
        Assert.False(Settings.Get("AutoConvertWetReadLineEndings"))

        SetTestSetting("RestrictHotkeysByActiveWindow", false)
        Assert.False(Settings.Get("RestrictHotkeysByActiveWindow"))
        
        SetTestSetting("AlertSound", "Asterisk")
        Assert.Equal("Asterisk", Settings.Get("AlertSound"))
    }

    TestMutationGuardRejectsSettingsWrite() {
        Settings.mutationGuard := (*) => false

        Assert.Throws(
            (*) => SetTestSetting("AutoUpdate", false),
            "Settings cannot be changed"
        )
        Assert.True(Settings.Get("AutoUpdate"))
    }

    TestPresentationLeaseRejectsSettingsWindowBeforeCreation() {
        lease := FakeSettingsPresentationLease(false)
        Settings.dialogAcquire := ObjBindMethod(lease, "Acquire")
        Settings.dialogRelease := ObjBindMethod(lease, "Release")
        Settings.dialogUnavailableNotifier := ObjBindMethod(lease, "Notify")

        result := Settings.ShowDialog()
        if IsObject(result)
            try result.Destroy()

        Assert.False(result)
        Assert.Equal(1, lease.acquireCalls)
        Assert.Equal(0, lease.releaseCalls)
        Assert.Equal(1, lease.notificationCalls)
    }

    TestMalformedPersistedSettingsUseDefaults() {
        IniWrite("-1", Settings.settingsFile, "Settings", "RefreshInterval")
        IniWrite("not-a-boolean", Settings.settingsFile, "Settings", "AutoUpdate")

        Assert.Equal(Settings.defaultSettings["RefreshInterval"], Settings.Get("RefreshInterval"))
        Assert.Equal(Settings.defaultSettings["AutoUpdate"], Settings.Get("AutoUpdate"))

        for invalidInterval in ["10.5", "1e2", "+10"] {
            IniWrite(invalidInterval, Settings.settingsFile, "Settings", "RefreshInterval")
            Assert.Equal(
                Settings.defaultSettings["RefreshInterval"],
                Settings.Get("RefreshInterval")
            )
        }
    }

    TestExcessivePersistedRefreshIntervalUsesDefault() {
        IniWrite("4294968", Settings.settingsFile, "Settings", "RefreshInterval")

        Assert.Equal(
            Settings.defaultSettings["RefreshInterval"],
            Settings.Get("RefreshInterval")
        )
    }

    TestSavingRejectsNonWholeRefreshInterval() {
        controls := this.SettingsControls(false, "10.5")
        dialog := FakeSettingsDialog()

        result := Settings.SaveSettings(controls, dialog)

        Assert.False(result)
        Assert.False(dialog.destroyed)
        Assert.Equal(60, Settings.Get("RefreshInterval"))
    }

    TestSavingRejectsExcessiveRefreshInterval() {
        controls := this.SettingsControls(false, 86401)
        dialog := FakeSettingsDialog()

        result := Settings.SaveSettings(controls, dialog)

        Assert.False(result)
        Assert.False(dialog.destroyed)
        Assert.Equal(60, Settings.Get("RefreshInterval"))
    }
    
    ; The catalogue is a repository contract. Optional Windows Media files are a
    ; runtime capability and production deliberately falls back when one is absent.
    TestAlertSoundsAreDistinct() {
        seen := Map()
        for name, soundFile in Settings.soundFiles {
            key := StrLower(Trim(soundFile))
            Assert.True(key != "", "No filename configured for alert sound: " name)
            Assert.False(seen.Has(key), "Alert sound reuses another sound's file: " name)
            seen[key] := name
        }
        Assert.Equal(Settings.soundFiles.Count, seen.Count)

        ; These two are handled without a file
        Assert.Equal("", Settings.ResolveSoundFile("Default Beep"))
        Assert.Equal("", Settings.ResolveSoundFile("Custom File"))
    }

    ; Every legacy name must land on a sound that is actually selectable, or an old
    ; settings.ini would resolve to an option no longer in the list
    TestLegacyAliasesAreSelectable() {
        for legacy, current in Settings.legacySoundAliases {
            found := false
            for name in Settings.alertSounds {
                if (name == current)
                    found := true
            }
            Assert.True(found, "Legacy sound '" legacy "' maps to '" current "', which is not selectable")
        }
    }

    TestLegacySoundNamesMigrate() {
        Assert.Equal("Default Beep", Settings.NormalizeSoundName("Default"))
        Assert.Equal("Notification", Settings.NormalizeSoundName("Asterisk"))
        Assert.Equal("Chime", Settings.NormalizeSoundName("Exclamation"))
        Assert.Equal("Chord", Settings.NormalizeSoundName("Hand"))
        Assert.Equal("Ding", Settings.NormalizeSoundName("Question"))
        Assert.Equal("Tada", Settings.NormalizeSoundName("Tada"))
        Assert.Equal("Default Beep", Settings.NormalizeSoundName("NotRealSound"))
    }

    TestFindSoundIndexFallback() {
        Assert.Equal("Default Beep", Settings.alertSounds[Settings.FindSoundIndex("Default")])
        Assert.Equal("Notification", Settings.alertSounds[Settings.FindSoundIndex("Asterisk")])
        Assert.Equal("Default Beep", Settings.alertSounds[Settings.FindSoundIndex("NotRealSound")])
    }

    TestFailedBatchPreservesOriginalFile() {
        SetTestSetting("AutoUpdate", true)
        IniWrite("keep me", Settings.settingsFile, "Extension", "UnknownKey")
        before := FileRead(Settings.settingsFile)
        values := Map("AutoUpdate", false, "RefreshInterval", 45)

        Assert.Throws(
            () => Settings.SaveValues(values, FailSettingsReplace),
            "simulated settings replace failure"
        )

        Assert.Equal(before, FileRead(Settings.settingsFile))
        Assert.True(Settings.Get("AutoUpdate"))
        Assert.Equal(60, Settings.Get("RefreshInterval"))
    }

    TestConcurrentSettingsWriteCannotBeLostByBatchReplace() {
        originalRevision := Settings.revision

        Assert.Throws(
            (*) => Settings.SaveValues(
                Map("AutoUpdate", false),
                ReentrantSettingsReplace
            ),
            "Another settings write is already in progress"
        )

        Assert.True(Settings.Get("AutoUpdate"))
        Assert.Equal("", Settings.Get("SkippedUpdateVersion"))
        Assert.Equal(originalRevision, Settings.revision)
        Assert.False(Settings.writeTransactionActive)
    }

    TestBatchPreservesUnmanagedSettings() {
        SetTestSetting("SkippedUpdateVersion", "v9.9.9")
        IniWrite("keep me", Settings.settingsFile, "Extension", "UnknownKey")

        Settings.SaveValues(Map("AutoUpdate", false, "RefreshInterval", 45))

        Assert.False(Settings.Get("AutoUpdate"))
        Assert.Equal(45, Settings.Get("RefreshInterval"))
        Assert.Equal("v9.9.9", Settings.Get("SkippedUpdateVersion"))
        Assert.Equal("keep me", IniRead(Settings.settingsFile, "Extension", "UnknownKey"))
    }

    TestSavingSettingsNotifiesListeners() {
        calls := []
        Settings.AddChangeListener((*) => calls.Push("changed"))
        controls := this.SettingsControls(false, 45)
        dialog := FakeSettingsDialog()

        Settings.SaveSettings(controls, dialog)

        Assert.True(dialog.destroyed)
        Assert.Equal(1, calls.Length)
        Assert.False(Settings.Get("AutoUpdate"))
        Assert.Equal(45, Settings.Get("RefreshInterval"))
    }

    TestStaleSettingsDialogCannotOverwriteNewerSave() {
        staleControls := this.SettingsControls(true, 90)
        newerControls := this.SettingsControls(false, 45)
        staleDialog := FakeSettingsDialog()
        newerDialog := FakeSettingsDialog()

        Assert.True(Settings.SaveSettings(newerControls, newerDialog))
        Assert.False(Settings.SaveSettings(staleControls, staleDialog))

        Assert.False(Settings.Get("AutoUpdate"))
        Assert.Equal(45, Settings.Get("RefreshInterval"))
        Assert.True(staleDialog.destroyed)
    }

    TestSettingsDialogCannotOverwriteAWriteDuringValidation() {
        controls := this.SettingsControls(true, 90)
        controls.micName := ReentrantSettingsValueControl(
            "PowerMic",
            (*) => SetTestSetting("SkippedUpdateVersion", "v9.9.9")
        )
        dialog := FakeSettingsDialog()

        result := Settings.SaveSettings(controls, dialog)

        Assert.False(result)
        Assert.True(dialog.destroyed)
        Assert.Equal("v9.9.9", Settings.Get("SkippedUpdateVersion"))
        Assert.Equal(60, Settings.Get("RefreshInterval"))
    }

    SettingsControls(autoUpdate, interval, swapMicrophone := false, micName := "") {
        return {
            checkboxes: Map(
                "AutoUpdate", {Value: autoUpdate},
                "SwapMicrophoneOnLogin", {Value: swapMicrophone}
            ),
            refreshInterval: {Value: interval},
            micName: {Value: micName},
            soundDropDown: {Text: "Ding"},
            customSound: {Text: ""}
        }
    }

    TestSavingRejectsRefreshIntervalOutsideBounds() {
        for interval in [9, 0, 86401] {
            dialog := FakeSettingsDialog()
            result := Settings.SaveSettings(this.SettingsControls(false, interval), dialog)

            Assert.Equal(false, result, "Interval " interval " must be rejected with false")
            Assert.False(dialog.destroyed)
            Assert.Equal("Invalid Setting", TestRunner.dialogs[TestRunner.dialogs.Length].title)
        }
        Assert.Equal(60, Settings.Get("RefreshInterval"))
    }

    TestSavingAcceptsRefreshIntervalBounds() {
        for interval in [10, 86400] {
            Assert.True(Settings.SaveSettings(this.SettingsControls(false, interval), FakeSettingsDialog()))
            Assert.Equal(interval, Settings.Get("RefreshInterval"))
        }
    }

    TestPersistedRefreshIntervalBounds() {
        expectations := Map("9", 60, "10", 10, "86400", 86400, "86401", 60, "-10", 60, "1e2", 60)
        for persisted, expected in expectations {
            IniWrite(persisted, Settings.settingsFile, "Settings", "RefreshInterval")
            Assert.Equal(expected, Settings.Get("RefreshInterval"), "Persisted interval '" persisted "'")
        }
    }

    TestSavingRequiresMicrophoneNameWhenSwapEnabled() {
        dialog := FakeSettingsDialog()

        result := Settings.SaveSettings(this.SettingsControls(false, 60, true, "   "), dialog)

        Assert.Equal(false, result)
        Assert.False(dialog.destroyed)
        Assert.Equal("Invalid Setting", TestRunner.dialogs[1].title)
        Assert.False(Settings.Get("SwapMicrophoneOnLogin"))

        Assert.True(Settings.SaveSettings(this.SettingsControls(false, 60, true, " PowerMic "), FakeSettingsDialog()))
        Assert.Equal("PowerMic", Settings.Get("MicrophoneName"))
    }

    TestSaveFailureKeepsDialogOpenAndFileUnchanged() {
        Settings.mutationGuard := (*) => false
        dialog := FakeSettingsDialog()

        result := Settings.SaveSettings(this.SettingsControls(false, 45), dialog)

        Assert.Equal(false, result)
        Assert.False(dialog.destroyed)
        Assert.Equal("Save Failed", TestRunner.dialogs[1].title)
        Assert.Equal(60, Settings.Get("RefreshInterval"))
    }

    TestChangeListenerMustBeCallable() {
        Assert.Throws(ObjBindMethod(Settings, "AddChangeListener", "not callable"), "must be callable")
        Assert.Throws(ObjBindMethod(Settings, "AddChangeListener", {}), "must be callable")
        Assert.Equal(0, Settings.changeListeners.Length)
    }

    TestSavingSettingsReportsListenerFailures() {
        Settings.AddChangeListener(ThrowSettingsListener)
        controls := this.SettingsControls(false, 45)
        dialog := FakeSettingsDialog()
        reports := []

        savedAndApplied := Settings.SaveSettings(
            controls,
            dialog,
            (message, errors) => reports.Push({message: message, errors: errors})
        )

        Assert.False(savedAndApplied)
        Assert.True(dialog.destroyed)
        Assert.False(Settings.Get("AutoUpdate"))
        Assert.Equal(1, reports.Length)
        Assert.Equal(1, reports[1].errors.Length)
        Assert.True(InStr(reports[1].message, "restart") > 0)
    }

    TestChangeListenersAllRun() {
        calls := []
        Settings.AddChangeListener((*) => calls.Push("updater"))
        Settings.AddChangeListener((*) => calls.Push("monitor"))

        errors := Settings.NotifyChanged()

        Assert.Equal(2, calls.Length)
        Assert.Equal("updater", calls[1])
        Assert.Equal("monitor", calls[2])
        Assert.Equal(0, errors.Length)
    }

    TestChangeListenerFailureDoesNotBlockLaterListeners() {
        calls := []
        Settings.AddChangeListener(ThrowSettingsListener)
        Settings.AddChangeListener((*) => calls.Push("after failure"))

        errors := Settings.NotifyChanged()

        Assert.Equal(1, calls.Length)
        Assert.Equal("after failure", calls[1])
        Assert.Equal(1, errors.Length)
        Assert.True(InStr(errors[1], "listener failed") > 0)
    }

    TestSettingsLayoutFitsScaled768p() {
        ; Allow 60 physical pixels for title bar/borders at 150% scaling.
        Assert.True(Settings.dialogLogicalWidth * 1.5 <= 1366)
        Assert.True(Settings.dialogLogicalHeight * 1.5 + 60 <= 768)
    }
    
    Teardown() {
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalFile
        Settings.changeListeners := this.originalListeners
        Settings.revision := this.originalRevision
        Settings.mutationGuard := this.originalMutationGuard
        if this.originalDialogAcquire
            Settings.dialogAcquire := this.originalDialogAcquire
        else
            try Settings.DeleteProp("dialogAcquire")
        if this.originalDialogRelease
            Settings.dialogRelease := this.originalDialogRelease
        else
            try Settings.DeleteProp("dialogRelease")
        if this.originalDialogUnavailableNotifier
            Settings.dialogUnavailableNotifier := this.originalDialogUnavailableNotifier
        else
            try Settings.DeleteProp("dialogUnavailableNotifier")
        Settings.writeTransactionActive := this.originalWriteTransactionActive
    }
}

ThrowSettingsListener(*) {
    throw Error("listener failed")
}

FailSettingsReplace(*) {
    throw Error("simulated settings replace failure")
}

ReentrantSettingsReplace(*) {
    SetTestSetting("SkippedUpdateVersion", "v9.9.9")
}

class FakeSettingsPresentationLease {
    __New(acquireResult := true) {
        this.acquireResult := acquireResult
        this.acquireCalls := 0
        this.releaseCalls := 0
        this.notificationCalls := 0
    }

    Acquire(*) {
        this.acquireCalls++
        return this.acquireResult
    }

    Release(*) {
        this.releaseCalls++
    }

    Notify(*) {
        this.notificationCalls++
    }
}

class FakeSettingsDialog {
    __New() {
        this.destroyed := false
        this.settingsRevision := Settings.revision
    }

    Destroy() {
        this.destroyed := true
    }
}

class ReentrantSettingsValueControl {
    __New(value, callback) {
        this.storedValue := value
        this.callback := callback
        this.triggered := false
    }

    Value {
        get {
            if !this.triggered {
                this.triggered := true
                this.callback.Call()
            }
            return this.storedValue
        }
    }
}
