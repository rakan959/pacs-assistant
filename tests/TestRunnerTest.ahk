#Requires AutoHotkey v2.0

class TestRunnerTest {
    static Tests := [
        "ThrowsRejectsAFunctionThatReturnsNormally",
        "EqualRejectsCaseOnlyAndTypeOnlyDifferences",
        "NotEqualAcceptsCaseOnlyAndTypeOnlyDifferences",
        "TemporaryPathsAreUniqueAndProcessScoped",
        "SetupFailureIsCountedAndDoesNotStopTheClass",
        "TeardownRunsAfterSetupFailure",
        "TeardownFailureCountsAsTheTestFailure",
        "TeardownRunsAfterABodyFailure"
    ]

    ThrowsRejectsAFunctionThatReturnsNormally() {
        didThrow := false
        try Assert.Throws(() => 42)
        catch {
            didThrow := true
        }

        Assert.True(didThrow, "Assert.Throws must fail when the callback returns normally")
    }

    EqualRejectsCaseOnlyAndTypeOnlyDifferences() {
        caseDifferenceRejected := false
        try Assert.Equal("PACS", "pacs")
        catch
            caseDifferenceRejected := true

        typeDifferenceRejected := false
        try Assert.Equal(1, "1")
        catch
            typeDifferenceRejected := true

        Assert.True(caseDifferenceRejected, "Assert.Equal must compare string case exactly")
        Assert.True(typeDifferenceRejected, "Assert.Equal must reject values of different types")
    }

    NotEqualAcceptsCaseOnlyAndTypeOnlyDifferences() {
        caseDifferenceAccepted := true
        try Assert.NotEqual("PACS", "pacs")
        catch
            caseDifferenceAccepted := false

        typeDifferenceAccepted := true
        try Assert.NotEqual(1, "1")
        catch
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

    RunProbe(testClass) {
        priorSuccesses := TestRunner.successes
        priorFailures := TestRunner.failures
        TestRunner.successes := 0
        TestRunner.failures := 0

        try {
            TestRunner.RunTestClass(testClass, false)
            result := {
                successes: TestRunner.successes,
                failures: TestRunner.failures
            }
        } catch as err {
            TestRunner.successes := priorSuccesses
            TestRunner.failures := priorFailures
            throw err
        }

        TestRunner.successes := priorSuccesses
        TestRunner.failures := priorFailures
        return result
    }
}

class SetupFailureProbe {
    static Tests := ["First", "Second"]
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
    static Tests := ["Passes"]

    static Reset() {
    }

    Passes() {
    }

    Teardown() {
        throw Error("teardown failed")
    }
}

class PartialSetupFailureProbe {
    static Tests := ["NeverRuns"]
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
    static Tests := ["Fails"]
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
