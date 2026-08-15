#Requires AutoHotkey v2.0

class TestRunner {
    static tests := []
    static successes := 0
    static failures := 0
    
    static AddTest(testClass) {
        this.tests.Push(testClass)
    }
    
    static RunAll() {
        this.successes := 0
        this.failures := 0
        
        for testClass in this.tests {
            this.RunTestClass(testClass)
        }
        
        this.ReportResults()
    }
    
    static RunTestClass(testClass, report := true) {
        if (!HasProp(testClass, "Tests"))
            return

        try instance := testClass()
        catch as err {
            for methodName in testClass.Tests
                this.RecordResult(testClass.Prototype.__Class, methodName, err, report)
            return
        }

        for methodName in testClass.Tests {
            this.RunTest(instance, methodName, report)
        }
    }
    
    static RunTest(instance, methodName, report := true) {
        failure := false

        try {
            if (HasMethod(instance, "Setup"))
                instance.Setup()
            instance.%methodName%()
        } catch as err {
            failure := err
        }

        ; Setup can mutate globals or fixtures before it raises. Teardown is the only
        ; reliable cleanup boundary, so invoke it after every attempted test even
        ; when setup itself failed.
        if HasMethod(instance, "Teardown") {
            try instance.Teardown()
            catch as teardownError {
                if (failure) {
                    failure := Error(Format(
                        "{1}; teardown failed: {2}",
                        failure.Message,
                        teardownError.Message
                    ))
                } else {
                    failure := teardownError
                }
            }
        }

        this.RecordResult(instance.__Class, methodName, failure, report)
    }

    static RecordResult(className, methodName, failure := false, report := true) {
        if (failure) {
            this.failures++
            if (report)
                FileAppend(Format("FAIL {1}.{2}: {3}`n", className, methodName, failure.Message), "*")
        } else {
            this.successes++
            if (report)
                FileAppend(Format("PASS {1}.{2}`n", className, methodName), "*")
        }
    }
    
    static ReportResults() {
        total := this.successes + this.failures
        FileAppend(Format("`nTest Results:`n============`nTotal: {1}`nPassed: {2}`nFailed: {3}`n", 
            total, this.successes, this.failures), "*")
    }
}

class Assert {
    static Equal(expected, actual, message := "") {
        if !this.ExactlyEqual(expected, actual)
            throw Error(message ? message : Format("Expected '{1}' but got '{2}'", expected, actual))
    }
    
    static NotEqual(expected, actual, message := "") {
        if this.ExactlyEqual(expected, actual)
            throw Error(message ? message : Format("Expected value different from '{1}'", expected))
    }

    static ExactlyEqual(expected, actual) {
        return Type(expected) == Type(actual) && expected == actual
    }
    
    static True(value, message := "") {
        if (!value)
            throw Error(message ? message : "Expected true but got false")
    }
    
    static False(value, message := "") {
        if (value)
            throw Error(message ? message : "Expected false but got true")
    }
    
    static Throws(func, expectedError := "", message := "") {
        caughtError := false
        try {
            func()
        } catch as err {
            caughtError := err
            if (expectedError && !InStr(err.Message, expectedError))
                throw Error(message ? message : Format("Expected error containing '{1}' but got '{2}'", expectedError, err.Message))
        }

        if (!caughtError)
            throw Error(message ? message : "Expected function to throw an error")
    }
}

; Suppress pop-up dialogs during tests by overriding MsgBox
MsgBox(text := "", title := "", options := "") {
    FileAppend(Format("MSGBOX [{1}] {2}`n", title, text), "*")
    ; Return a sensible default for Yes/No prompts
    if InStr(options, "YesNo")
        return "Yes"
    return "OK"
}
