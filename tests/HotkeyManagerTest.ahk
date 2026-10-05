; = CONTENTS
;   + Preamble
;   + HotkeyManagerTest class (registration, reassignment, rollback, scopes, teardown)
;   + Test doubles (hotkey driver)

#Requires AutoHotkey v2.0
#Include ../HotkeyManager.ahk
#Include TestRunner.ahk
#Include FakeWindowList.ahk

class HotkeyManagerTest {
    static tests := [
        "TestRegistersAndStoresHotkeys",
        "TestReassignUpdatesBinding",
        "TestUnassignClearsBinding",
        "TestUnregisterFailureKeepsLiveRegistrationTracked",
        "TestDisableAllReportsAndRetainsFailedRegistration",
        "TestReplacementRollbackFailureTracksEveryPossiblyLiveVariant",
        "TestRejectsMissingFunction",
        "TestDisableAllHotkeys",
        "TestRegistersWithScope",
        "TestUnknownScopeIsRejectedWithoutReplacingRegistration",
        "TestScopedBindCanBeTurnedOffAgain",
        "TestPowerScribeScopeRequiresExactReportingWindow",
        "TestPowerScribeScopeRejectsWrongTitleAndDuplicateWindows",
        "TestPacsScopeRejectsWrongTitleAndDuplicateWindows",
        "TestRestrictedCallbackRechecksScopeBeforeInvocation",
        "TestDuplicateHotkeyIsRejectedWithoutReplacingOwner",
        "TestEquivalentModifierOrderIsRejected",
        "TestEquivalentCustomCombinationPrefixesAreRejected",
        "TestMissingCallbackReassignmentPreservesExistingRegistration",
        "TestInvalidHotkeyReassignmentPreservesExistingRegistration",
        "TestNonCanonicalScopeIsNotRegistered"
    ]

    Setup() {
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.activeHotkeys.Clear()
        this.originalHotkeyDriver := HotkeyManager.hotkeyDriver
        this.originalWindowDriver := AppControl.windowDriver
        this.originalHotkeyFunctions := HotkeyManager.hotkeyFunctions
        ; Unit tests model registration through a recording driver so the suite never
        ; grabs a key the user might press. The two tests that need AutoHotkey itself
        ; switch to the native driver with Ctrl+F13/Ctrl+F22, which have no physical
        ; key; run-hotkey-tests.ahk covers the rest of the native behavior.
        HotkeyManager.hotkeyDriver := FakeHotkeyDriver()

        this.func1Calls := 0
        this.func2Calls := 0
        this.func1 := (*) => (this.func1Calls++, 0)
        this.func2 := (*) => (this.func2Calls++, 0)

        HotkeyManager.hotkeyFunctions := Map(
            "ActionOne", this.func1,
            "ActionTwo", this.func2
        )
    }

    TestRegistersAndStoresHotkeys() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal("Any", HotkeyManager.activeHotkeys["ActionOne"].scope)
    }

    TestReassignUpdatesBinding() {
        HotkeyManager.RegisterHotkey("ActionOne", "^a")
        HotkeyManager.RegisterHotkey("ActionOne", "^b")
        Assert.Equal("^b", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
    }

    TestUnassignClearsBinding() {
        HotkeyManager.RegisterHotkey("ActionTwo", "^c")
        HotkeyManager.RegisterHotkey("ActionTwo", "")
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
    }

    TestRejectsMissingFunction() {
        Assert.False(HotkeyManager.RegisterHotkey("MissingAction", "^d"))
        Assert.False(HotkeyManager.activeHotkeys.Has("MissingAction"))
        ; Failure is reported by return value plus lastError, not a dialog, so
        ; ApplyBinds can collect every failure into one message
        Assert.True(HotkeyManager.lastError != "")
    }

    TestDisableAllHotkeys() {
        HotkeyManager.RegisterHotkey("ActionOne", "^a")
        HotkeyManager.RegisterHotkey("ActionTwo", "^b")
        HotkeyManager.DisableAllHotkeys()
        Assert.Equal(0, HotkeyManager.activeHotkeys.Count)
    }

    TestRegistersWithScope() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "PowerScribe"))
        Assert.Equal("PowerScribe", HotkeyManager.activeHotkeys["ActionOne"].scope)

        ; Re-registering under a different scope must replace, not accumulate. The
        ; PowerScribe variant is a separate AutoHotkey hotkey, so it is turned off.
        driver := HotkeyManager.hotkeyDriver
        Assert.Equal(0, driver.disabled.Length)
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "PACS"))
        Assert.Equal("PACS", HotkeyManager.activeHotkeys["ActionOne"].scope)
        Assert.Equal(1, HotkeyManager.activeHotkeys.Count)
        Assert.Equal(1, driver.disabled.Length)
        Assert.Equal("^a", driver.disabled[1])
    }

    TestUnknownScopeIsRejectedWithoutReplacingRegistration() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a", "PACS"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "^b", "nonsense"))
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal("PACS", HotkeyManager.activeHotkeys["ActionOne"].scope)
    }

    ; HotkeyContractTest covers the scope names themselves.
    TestNonCanonicalScopeIsNotRegistered() {
        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "^F22", "pacs"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionOne"))
    }

    ; AutoHotkey identifies a hotkey variant by the exact function object handed to
    ; HotIf, so a fresh closure per registration would leave each scoped bind
    ; registered and unreachable: turning it off would fail with "Nonexistent hotkey
    ; variant". Registers natively; Ctrl+F22 has no physical key.
    TestScopedBindCanBeTurnedOffAgain() {
        for scope in HotkeyContract.scopes {
            if (scope == "Any") {
                Assert.False(HotkeyManager.scopePredicates.Has(scope), "'Any' must register globally, with no predicate")
                continue
            }
            Assert.True(HotkeyManager.scopePredicates.Has(scope), "No HotIf predicate for scope: " scope)
        }

        HotkeyManager.hotkeyDriver := this.originalHotkeyDriver
        for scope in ["PACS", "PowerScribe", "PACS or PowerScribe"] {
            Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^F22", scope), HotkeyManager.lastError)
            Assert.True(HotkeyManager.Unregister("ActionOne"), scope ": " HotkeyManager.lastError)
            Assert.False(HotkeyManager.activeHotkeys.Has("ActionOne"))
        }
    }

    TestPowerScribeScopeRequiresExactReportingWindow() {
        requestedSpecs := []

        active := HotkeyManager.PowerScribeIsActive(
            (specs) => (requestedSpecs.Push(specs), true)
        )

        Assert.True(active)
        Assert.Equal(1, requestedSpecs.Length)
        Assert.Equal(1, requestedSpecs[1].Length)
        Assert.Equal(
            AppControl.powerScribeReportingTitle,
            requestedSpecs[1][1].title
        )
        Assert.Equal(
            AppControl.powerScribeExecutable,
            requestedSpecs[1][1].exe
        )
    }

    TestPacsScopeRejectsWrongTitleAndDuplicateWindows() {
        AppControl.windowDriver := FakeWindowList([{
            hwnd: 100,
            title: "Unrelated mp.exe dialog",
            exe: AppControl.vuePacsExecutable,
            pid: 42,
            active: true
        }])
        Assert.False(HotkeyManager.PACSIsActive())

        AppControl.windowDriver := FakeWindowList([
            {
                hwnd: 101,
                title: AppControl.vuePacsTitle,
                exe: AppControl.vuePacsExecutable,
                pid: 42,
                active: true
            },
            {
                hwnd: 102,
                title: AppControl.vuePacsClientTitle,
                exe: AppControl.vuePacsExecutable,
                pid: 42,
                active: false
            }
        ])
        Assert.False(HotkeyManager.PACSIsActive())

        AppControl.windowDriver := FakeWindowList([{
            hwnd: 103,
            title: AppControl.vuePacsTitle,
            exe: AppControl.vuePacsExecutable,
            pid: 42,
            active: true
        }])
        Assert.True(HotkeyManager.PACSIsActive())
    }

    TestPowerScribeScopeRejectsWrongTitleAndDuplicateWindows() {
        AppControl.windowDriver := FakeWindowList([{
            hwnd: 200,
            title: "PowerScribe Login",
            exe: AppControl.powerScribeExecutable,
            pid: 52,
            active: true
        }])
        Assert.False(HotkeyManager.PowerScribeIsActive())

        AppControl.windowDriver := FakeWindowList([
            {
                hwnd: 201,
                title: AppControl.powerScribeReportingTitle,
                exe: AppControl.powerScribeExecutable,
                pid: 52,
                active: true
            },
            {
                hwnd: 202,
                title: AppControl.powerScribeReportingTitle,
                exe: AppControl.powerScribeExecutable,
                pid: 52,
                active: false
            }
        ])
        Assert.False(HotkeyManager.PowerScribeIsActive())

        AppControl.windowDriver := FakeWindowList([{
            hwnd: 203,
            title: AppControl.powerScribeReportingTitle,
            exe: AppControl.powerScribeExecutable,
            pid: 52,
            active: true
        }])
        Assert.True(HotkeyManager.PowerScribeIsActive())
    }

    TestRestrictedCallbackRechecksScopeBeforeInvocation() {
        driver := FakeHotkeyDriver()
        HotkeyManager.hotkeyDriver := driver
        AppControl.windowDriver := FakeWindowList([{
            hwnd: 301,
            title: AppControl.vuePacsTitle,
            exe: AppControl.vuePacsExecutable,
            pid: 62,
            active: false
        }])

        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^F22", "PACS"))
        ; HotIf may have accepted the physical key while PACS was active. The
        ; registered callback must independently reject a later focus change.
        driver.enabled["^F22"].Call("^F22")
        Assert.Equal(0, this.func1Calls)

        AppControl.windowDriver.windows[1].active := true
        driver.enabled["^F22"].Call("^F22")
        Assert.Equal(1, this.func1Calls)
    }

    TestDuplicateHotkeyIsRejectedWithoutReplacingOwner() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionTwo", "^A"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
        Assert.True(InStr(HotkeyManager.lastError, "ActionOne") > 0)
    }

    TestEquivalentModifierOrderIsRejected() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^!a"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionTwo", "!^A"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
    }

    TestEquivalentCustomCombinationPrefixesAreRejected() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "a & b"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionTwo", "~a & b"))
        Assert.Equal(
            HotkeyContract.BindingIdentity("a & b"),
            HotkeyContract.BindingIdentity("a & ~b")
        )
        Assert.Equal(
            HotkeyContract.BindingIdentity("a & b"),
            HotkeyContract.BindingIdentity("a & $b")
        )
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))
        Assert.True(InStr(HotkeyManager.lastError, "ActionOne") > 0)
    }

    TestUnregisterFailureKeepsLiveRegistrationTracked() {
        HotkeyManager.hotkeyDriver := FakeHotkeyDriver("^F23")
        HotkeyManager.activeHotkeys["ActionOne"] := {
            hotkey: "^F23",
            scope: "Any"
        }

        Assert.False(HotkeyManager.Unregister("ActionOne"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.True(InStr(HotkeyManager.lastError, "disable") > 0)

        HotkeyManager.activeHotkeys.Delete("ActionOne")
    }

    TestDisableAllReportsAndRetainsFailedRegistration() {
        HotkeyManager.hotkeyDriver := FakeHotkeyDriver("^F23")
        HotkeyManager.activeHotkeys["ActionOne"] := {
            hotkey: "^F23",
            scope: "Any"
        }
        HotkeyManager.activeHotkeys["ActionTwo"] := {hotkey: "^F24", scope: "Any"}

        ; Each failed function is named with the native reason, which is all a
        ; later diagnosis of a "restart required" notice has to go on.
        Assert.Throws(
            () => HotkeyManager.DisableAllHotkeys(),
            "These hotkeys could not be disabled: ActionOne (^F23: simulated native Off failure)"
        )
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.False(HotkeyManager.activeHotkeys.Has("ActionTwo"))

        HotkeyManager.activeHotkeys.Delete("ActionOne")
    }

    TestReplacementRollbackFailureTracksEveryPossiblyLiveVariant() {
        driver := FakeHotkeyDriver(["^F23", "^F24"])
        HotkeyManager.hotkeyDriver := driver
        HotkeyManager.activeHotkeys["ActionOne"] := {
            hotkey: "^F23",
            scope: "Any"
        }

        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "^F24"))
        Assert.Equal("^F23", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal(1, HotkeyManager.additionalActiveHotkeys.Count)
        for _, entry in HotkeyManager.additionalActiveHotkeys {
            Assert.Equal("ActionOne", entry.funcName)
            Assert.Equal("^F24", entry.hotkey)
        }

        Assert.Throws(
            () => HotkeyManager.DisableAllHotkeys(),
            "could not be disabled"
        )
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal(1, HotkeyManager.additionalActiveHotkeys.Count)

        driver.failingHotkeys.Clear()
        Assert.True(HotkeyManager.DisableAllHotkeys())
        Assert.Equal(0, HotkeyManager.activeHotkeys.Count)
        Assert.Equal(0, HotkeyManager.additionalActiveHotkeys.Count)
    }

    TestMissingCallbackReassignmentPreservesExistingRegistration() {
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^a"))

        Assert.False(HotkeyManager.Register("ActionOne", "^b", 0))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal("^a", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
    }

    TestInvalidHotkeyReassignmentPreservesExistingRegistration() {
        ; AutoHotkey itself is the key-name authority, so this test registers through
        ; the native driver. Ctrl+F13 has no physical key on a standard keyboard.
        HotkeyManager.hotkeyDriver := this.originalHotkeyDriver
        Assert.True(HotkeyManager.RegisterHotkey("ActionOne", "^F13"))

        Assert.False(HotkeyManager.RegisterHotkey("ActionOne", "DefinitelyNotARealKeyName"))
        Assert.True(HotkeyManager.activeHotkeys.Has("ActionOne"))
        Assert.Equal("^F13", HotkeyManager.activeHotkeys["ActionOne"].hotkey)
        Assert.Equal("Any", HotkeyManager.activeHotkeys["ActionOne"].scope)
        Assert.True(InStr(HotkeyManager.lastError, "Invalid key name") > 0)
    }

    Teardown() {
        if !(HotkeyManager.hotkeyDriver == this.originalHotkeyDriver)
            HotkeyManager.activeHotkeys.Clear()
        HotkeyManager.additionalActiveHotkeys.Clear()
        HotkeyManager.hotkeyDriver := this.originalHotkeyDriver
        AppControl.windowDriver := this.originalWindowDriver
        HotkeyManager.DisableAllHotkeys()
        HotkeyManager.activeHotkeys.Clear()
        HotkeyManager.hotkeyFunctions := this.originalHotkeyFunctions
    }
}

class FakeHotkeyDriver {
    __New(failingHotkeys := "") {
        this.failingHotkeys := Map()
        if (Type(failingHotkeys) = "String") {
            if (failingHotkeys != "")
                this.failingHotkeys[failingHotkeys] := true
        } else {
            for hotkeyStr in failingHotkeys
                this.failingHotkeys[hotkeyStr] := true
        }
        this.disabled := []
        this.enabled := Map()
    }

    Enable(hotkeyStr, callback) {
        this.enabled[hotkeyStr] := callback
    }

    Disable(hotkeyStr) {
        this.disabled.Push(hotkeyStr)
        if this.failingHotkeys.Has(hotkeyStr)
            throw Error("simulated native Off failure")
    }
}
