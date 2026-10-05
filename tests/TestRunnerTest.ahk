#Requires AutoHotkey v2.0

class TestRunnerTest {
    static tests := [
        "ThrowsRejectsAFunctionThatReturnsNormally",
        "EqualRejectsCaseOnlyAndTypeOnlyDifferences",
        "NotEqualAcceptsCaseOnlyAndTypeOnlyDifferences",
        "FailedAssertionNamesTheTestLineAndShowsObjects",
        "TemporaryPathsAreUniqueAndProcessScoped",
        "StorageIsIsolatedFromTheScriptFolder",
        "SetupFailureIsCountedAndDoesNotStopTheClass",
        "TeardownRunsAfterSetupFailure",
        "TeardownFailureCountsAsTheTestFailure",
        "TeardownRunsAfterABodyFailure",
        "NonErrorThrowIsCountedAsAFailure",
        "FalsyThrowsFromConstructorAndTeardownAreFailures",
        "UnlistedTestMethodIsAFailure",
        "ClassWithoutTestListIsAFailure",
        "ThrowsAcceptsAFalsyThrownValue",
        "DialogsAreRecordedPerTest"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "RunProbe"
    ]

    ThrowsRejectsAFunctionThatReturnsNormally() {
        didThrow := false
        try Assert.Throws(() => 42)
        catch Error {
            didThrow := true
        }

        Assert.True(didThrow, "Assert.Throws must fail when the callback returns normally")
    }

    EqualRejectsCaseOnlyAndTypeOnlyDifferences() {
        caseDifferenceRejected := false
        try Assert.Equal("PACS", "pacs")
        catch Error
            caseDifferenceRejected := true

        typeDifferenceRejected := false
        try Assert.Equal(1, "1")
        catch Error
            typeDifferenceRejected := true

        Assert.True(caseDifferenceRejected, "Assert.Equal must compare string case exactly")
        Assert.True(typeDifferenceRejected, "Assert.Equal must reject values of different types")
    }

    FailedAssertionNamesTheTestLineAndShowsObjects() {
        failures := []
        lines := []
        lines.Push(A_LineNumber + 1)
        try Assert.Equal(0, {})
        catch Error as err
            failures.Push(err)
        lines.Push(A_LineNumber + 1)
        try Assert.True(false)
        catch Error as err
            failures.Push(err)
        lines.Push(A_LineNumber + 1)
        try Assert.Throws(() => 0)
        catch Error as err
            failures.Push(err)

        Assert.Equal(3, failures.Length)
        Assert.Equal("Expected '0' but got '<Object>'", failures[1].Message)
        for failure in failures {
            Assert.Equal(A_LineFile, failure.File)
            Assert.Equal(lines[A_Index], failure.Line)
        }
    }

    NotEqualAcceptsCaseOnlyAndTypeOnlyDifferences() {
        caseDifferenceAccepted := true
        try Assert.NotEqual("PACS", "pacs")
        catch Error
            caseDifferenceAccepted := false

        typeDifferenceAccepted := true
        try Assert.NotEqual(1, "1")
        catch Error
            typeDifferenceAccepted := false

        Assert.True(caseDifferenceAccepted, "Assert.NotEqual must distinguish string case")
        Assert.True(typeDifferenceAccepted, "Assert.NotEqual must distinguish value types")
    }

    TemporaryPathsAreUniqueAndProcessScoped() {
        first := TestTempPath("pacs-fixture", ".ini")
        second := TestTempPath("pacs-fixture", ".ini")
        processId := DllCall("GetCurrentProcessId")

        Assert.NotEqual(first, second)
        Assert.True(
            InStr(first, A_Temp "\pacs-fixture-" processId "-") = 1,
            "Temporary paths must remain under the process-scoped system temp prefix"
        )
        Assert.True(
            SubStr(first, StrLen(first) - 3) == ".ini",
            "Temporary paths must preserve the requested extension"
        )
    }

    ; RunTests.ahk must isolate storage before Settings and ProfileManager initialize;
    ; isolating any later leaves both pointing at the files beside the scripts.
    StorageIsIsolatedFromTheScriptFolder() {
        root := AppStorage.DataRoot()

        Assert.NotEqual(A_ScriptDir, root)
        Assert.True(InStr(root, A_Temp "\pacs-assistant-unit-tests-") = 1, root)
        Assert.Equal(root "\settings.ini", Settings.settingsFile)
        Assert.Equal(root "\config.ini", ProfileManager.configPath)
        Assert.Equal(root "\profiles", ProfileManager.profilesPath)
    }

    SetupFailureIsCountedAndDoesNotStopTheClass() {
        SetupFailureProbe.Reset()
        result := this.RunProbe(SetupFailureProbe)

        Assert.Equal(1, result.successes)
        Assert.Equal(1, result.failures)
        Assert.Equal(1, SetupFailureProbe.bodyCalls)
    }

    TeardownRunsAfterSetupFailure() {
        PartialSetupFailureProbe.Reset()
        result := this.RunProbe(PartialSetupFailureProbe)

        Assert.Equal(0, result.successes)
        Assert.Equal(1, result.failures)
        Assert.Equal(1, PartialSetupFailureProbe.teardownCalls)
        Assert.False(PartialSetupFailureProbe.dirty)
    }

    TeardownFailureCountsAsTheTestFailure() {
        TeardownFailureProbe.Reset()
        result := this.RunProbe(TeardownFailureProbe)

        Assert.Equal(0, result.successes)
        Assert.Equal(1, result.failures)
    }

    TeardownRunsAfterABodyFailure() {
        BodyFailureProbe.Reset()
        result := this.RunProbe(BodyFailureProbe)

        Assert.Equal(0, result.successes)
        Assert.Equal(1, result.failures)
        Assert.Equal(1, BodyFailureProbe.teardownCalls)
    }

    NonErrorThrowIsCountedAsAFailure() {
        result := this.RunProbe(NonErrorThrowProbe)

        Assert.Equal(0, result.successes)
        Assert.Equal(NonErrorThrowProbe.tests.Length, result.failures)
    }

    ; A falsy thrown value from a constructor or teardown is still a failure.
    FalsyThrowsFromConstructorAndTeardownAreFailures() {
        Assert.Equal(1, this.RunProbe(FalsyConstructorProbe).failures)
        result := this.RunProbe(FalsyTeardownProbe)
        Assert.Equal(0, result.successes)
        Assert.Equal(1, result.failures)
    }

    UnlistedTestMethodIsAFailure() {
        result := this.RunProbe(UnlistedMethodProbe)

        ; The listed test and the declared helper are fine; the forgotten test fails
        ; the class's test list.
        Assert.Equal(1, result.successes)
        Assert.Equal(1, result.failures)
    }

    ClassWithoutTestListIsAFailure() {
        result := this.RunProbe(MissingTestListProbe)

        Assert.Equal(0, result.successes)
        Assert.Equal(1, result.failures)
    }

    ThrowsAcceptsAFalsyThrownValue() {
        Assert.Throws(ObjBindMethod(NonErrorThrowProbe, "ThrowValue", 0))
        Assert.Throws(ObjBindMethod(NonErrorThrowProbe, "ThrowValue", "plain text"), "plain text")
    }

    DialogsAreRecordedPerTest() {
        priorDialogs := TestRunner.dialogs
        try {
            result := this.RunProbe(DialogProbe)
            Assert.Equal(2, result.successes)
            Assert.Equal(1, DialogProbe.observed[1], "A MsgBox call must be recorded")
            Assert.Equal(0, DialogProbe.observed[2], "Each test must start with an empty dialog record")
        } finally TestRunner.dialogs := priorDialogs
    }

    RunProbe(testClass) {
        priorSuccesses := TestRunner.successes
        priorFailures := TestRunner.failures
        TestRunner.successes := 0
        TestRunner.failures := 0

        try {
            TestRunner.RunTestClass(testClass, false)
            return {
                successes: TestRunner.successes,
                failures: TestRunner.failures
            }
        } finally {
            TestRunner.successes := priorSuccesses
            TestRunner.failures := priorFailures
        }
    }
}

class SetupFailureProbe {
    static tests := ["First", "Second"]
    static setupCalls := 0
    static bodyCalls := 0

    static Reset() {
        this.setupCalls := 0
        this.bodyCalls := 0
    }

    Setup() {
        SetupFailureProbe.setupCalls++
        if (SetupFailureProbe.setupCalls = 1)
            throw Error("setup failed")
    }

    First() {
        SetupFailureProbe.bodyCalls++
    }

    Second() {
        SetupFailureProbe.bodyCalls++
    }
}

class TeardownFailureProbe {
    static tests := ["Passes"]

    static Reset() {
    }

    Passes() {
    }

    Teardown() {
        throw Error("teardown failed")
    }
}

class PartialSetupFailureProbe {
    static tests := ["NeverRuns"]
    static dirty := false
    static teardownCalls := 0

    static Reset() {
        this.dirty := false
        this.teardownCalls := 0
    }

    Setup() {
        PartialSetupFailureProbe.dirty := true
        throw Error("setup failed after mutation")
    }

    NeverRuns() {
        throw Error("test body must not run")
    }

    Teardown() {
        PartialSetupFailureProbe.teardownCalls++
        PartialSetupFailureProbe.dirty := false
    }
}

class BodyFailureProbe {
    static tests := ["Fails"]
    static teardownCalls := 0

    static Reset() {
        this.teardownCalls := 0
    }

    Fails() {
        throw Error("body failed")
    }

    Teardown() {
        BodyFailureProbe.teardownCalls++
    }
}

class NonErrorThrowProbe {
    static tests := ["ThrowsAString", "ThrowsZero", "ThrowsAnEmptyString"]

    static ThrowValue(value) {
        throw value
    }

    ThrowsAString() {
        throw "not an Error object"
    }

    ThrowsZero() {
        throw 0
    }

    ThrowsAnEmptyString() {
        throw ""
    }
}

class UnlistedMethodProbe {
    static tests := ["Listed"]
    static helpers := ["Helper"]

    Listed() {
        this.Helper()
    }

    Forgotten() {
    }

    Helper() {
    }
}

class FalsyConstructorProbe {
    static tests := ["Body"]

    __New() {
        throw 0
    }

    Body() {
    }
}

class FalsyTeardownProbe {
    static tests := ["Body"]

    Body() {
    }

    Teardown() {
        throw ""
    }
}

class MissingTestListProbe {
}

class DialogProbe {
    static tests := ["ShowsOne", "SeesNone"]
    static observed := []

    ShowsOne() {
        MsgBox("probe dialog", "Probe", "Iconi")
        DialogProbe.observed := [TestRunner.dialogs.Length]
    }

    SeesNone() {
        DialogProbe.observed.Push(TestRunner.dialogs.Length)
    }
}
