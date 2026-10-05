#Requires AutoHotkey v2.0
#Include ../ExclusiveOperations.ahk
#Include TestRunner.ahk
#Include ExclusiveOperationsFixture.ahk

class ExclusiveOperationsTest {
    static tests := [
        "TestActiveReportsTheFirstActiveKind",
        "TestTryBeginRefusesWhileAnotherOperationIsActive",
        "TestShutdownExemptionLetsAProfileSaveFinishShutdown",
        "TestEndReleasesTheLeaseAndItsAction",
        "TestOnlyOwnedLeasesCanBeTaken",
        "TestUiPresentationLeaseBlocksClinicalEntry"
    ]

    Setup() {
        this.originalLeases := ExclusiveOperationsFixture.ReleaseAll()
        this.originalCommandAvailabilityProbe := PACSCommands.commandAvailabilityProbe
    }

    Teardown() {
        ExclusiveOperationsFixture.Restore(this.originalLeases)
        PACSCommands.commandAvailabilityProbe := this.originalCommandAvailabilityProbe
    }

    TestActiveReportsTheFirstActiveKind() {
        flags := [
            {kind: "clinical", owner: PACSCommands, name: "clinicalCommandActive"},
            {kind: "capture", owner: ExclusiveOperations, name: "captureActive"},
            {kind: "profileMutation", owner: ExclusiveOperations, name: "profileMutationActive"},
            {kind: "settingsWrite", owner: Settings, name: "writeTransactionActive"},
            {kind: "uiPresentation", owner: ExclusiveOperations, name: "uiPresentationActive"},
            {kind: "shutdown", owner: ExclusiveOperations, name: "shutdownActive"}
        ]
        Assert.Equal("", ExclusiveOperations.Active())

        for flag in flags {
            flag.owner.%flag.name% := true
            Assert.Equal(flag.kind, ExclusiveOperations.Active())
            Assert.Equal("", ExclusiveOperations.Active(flag.kind), "Ignoring the only active kind")
            flag.owner.%flag.name% := false
        }

        ; With several active, the user hears about the highest-priority one, and an
        ; ignored kind does not hide the next one.
        PACSCommands.clinicalCommandActive := true
        ExclusiveOperations.shutdownActive := true
        Assert.Equal("clinical", ExclusiveOperations.Active())
        Assert.Equal("shutdown", ExclusiveOperations.Active("clinical"))
        Assert.Equal("", ExclusiveOperations.Active("clinical", "shutdown"))
        Assert.Throws(ObjBindMethod(ExclusiveOperations, "IsActive", "Clinical"), "Unknown exclusive operation kind")
    }

    TestTryBeginRefusesWhileAnotherOperationIsActive() {
        PACSCommands.clinicalCommandActive := true

        Assert.False(ExclusiveOperations.TryBegin("capture", "start key capture"))
        Assert.False(ExclusiveOperations.captureActive)

        PACSCommands.clinicalCommandActive := false
        Assert.True(ExclusiveOperations.TryBegin("capture", "start key capture"))
        Assert.True(ExclusiveOperations.captureActive)
        ; A held lease excludes a second taker of the same kind.
        Assert.False(ExclusiveOperations.TryBegin("capture", "start key capture"))
    }

    TestShutdownExemptionLetsAProfileSaveFinishShutdown() {
        Assert.True(ExclusiveOperations.TryBegin("shutdown", "close PACS Assistant"))

        Assert.False(ExclusiveOperations.TryBegin("profileMutation", "save the profile"))
        Assert.True(ExclusiveOperations.TryBegin(
            "profileMutation",
            "save the profile",
            ExclusiveOperations.ShutdownExemption(true)*
        ))
        Assert.Equal("save the profile", ExclusiveOperations.profileMutationAction)
        Assert.True(ExclusiveOperations.shutdownActive)
    }

    TestEndReleasesTheLeaseAndItsAction() {
        Assert.True(ExclusiveOperations.TryBegin("uiPresentation", "open Settings"))
        Assert.Equal("uiPresentation", ExclusiveOperations.Active())
        Assert.Equal("open Settings", ExclusiveOperations.uiPresentationAction)

        ExclusiveOperations.End("uiPresentation")

        Assert.Equal("", ExclusiveOperations.Active())
        Assert.Equal("", ExclusiveOperations.uiPresentationAction)
    }

    ; Clinical commands and settings writes are leased by PACSCommands and Settings.
    TestOnlyOwnedLeasesCanBeTaken() {
        for kind in ["clinical", "settingsWrite", "Capture"] {
            Assert.Throws(ObjBindMethod(ExclusiveOperations, "TryBegin", kind), "does not own")
            Assert.Throws(ObjBindMethod(ExclusiveOperations, "End", kind), "does not own")
        }
        Assert.False(PACSCommands.clinicalCommandActive)
        Assert.False(Settings.writeTransactionActive)
    }

    TestUiPresentationLeaseBlocksClinicalEntry() {
        callbackCalls := 0
        ; The same composition main.ahk uses for clinical entry.
        PACSCommands.commandAvailabilityProbe := (*) =>
            ExclusiveOperations.Active("clinical") = ""

        Assert.True(ExclusiveOperations.TryBegin("uiPresentation", "open Settings"))
        blocked := PACSCommands.RunClinicalCommand(
            "Sign Report",
            (*) => callbackCalls++
        )
        Assert.False(blocked)
        Assert.Equal(0, callbackCalls)

        ExclusiveOperations.End("uiPresentation")
        Assert.True(PACSCommands.RunClinicalCommand(
            "Sign Report",
            (*) => (callbackCalls++, true)
        ))
        Assert.Equal(1, callbackCalls)
    }
}
