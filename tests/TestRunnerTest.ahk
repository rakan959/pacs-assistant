#Requires AutoHotkey v2.0

class TestRunnerTest {
    static Tests := [
        "ThrowsRejectsAFunctionThatReturnsNormally",
        "SetupFailureIsCountedAndDoesNotStopTheClass",
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

    SetupFailureIsCountedAndDoesNotStopTheClass() {
        SetupFailureProbe.Reset()
        result := this.RunProbe(SetupFailureProbe)

        Assert.Equal(1, result.successes)
        Assert.Equal(1, result.failures)
        Assert.Equal(1, SetupFailureProbe.bodyCalls)
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
