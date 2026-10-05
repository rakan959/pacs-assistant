#Requires AutoHotkey v2.0
#Include ../ErrorText.ahk

TestTempPath(prefix, extension := "") {
    static sequence := 0
    sequence++
    return A_Temp "\" prefix "-"
        . DllCall("GetCurrentProcessId") "-"
        . DllCall("GetTickCount64", "UInt64") "-"
        . sequence extension
}

SetTestSetting(settingName, value) {
    return Settings.SaveValues(Map(settingName, value))
}

class TestRunner {
    static tests := []
    static successes := 0
    static failures := 0
    ; Dialogs raised through the MsgBox override below during the current test, so a
    ; test can assert which message a failure path showed rather than only its result.
    static dialogs := []

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
        className := testClass.Prototype.__Class
        ; A registered class without a test list would otherwise contribute nothing
        ; and still leave the suite green.
        if !HasProp(testClass, "tests") {
            this.RecordResult(className, "(test list)", Error("Test class has no static tests list"), report)
            return
        }

        try instance := testClass()
        catch Any as err {
            for methodName in testClass.tests
                this.RecordResult(className, methodName, err, report)
            return
        }

        for methodName in testClass.tests {
            this.RunTest(instance, methodName, report)
        }
    }

    static RunTest(instance, methodName, report := true) {
        failure := false
        this.dialogs := []

        ; catch Any: AutoHotkey can throw non-Error values, and one that escaped here
        ; would reach the OnError handler and end the whole run.
        try {
            if (HasMethod(instance, "Setup"))
                instance.Setup()
            instance.%methodName%()
        } catch Any as err {
            failure := err
        }

        ; Setup can mutate globals or fixtures before it raises. Teardown is the only
        ; reliable cleanup boundary, so invoke it after every attempted test even
        ; when setup itself failed.
        if HasMethod(instance, "Teardown") {
            try instance.Teardown()
            catch Any as teardownError {
                if (failure) {
                    failure := Error(Format(
                        "{1}; teardown failed: {2}",
                        ErrorText.Describe(failure),
                        ErrorText.Describe(teardownError)
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
                FileAppend(Format("FAIL {1}.{2}: {3}`n", className, methodName, ErrorText.Describe(failure)), "*")
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
    
    static Throws(callback, expectedError := "", message := "") {
        ; Track the throw separately: a thrown 0 or "" is falsy but still a throw.
        threw := false
        try {
            callback()
        } catch Any as err {
            threw := true
            if (expectedError && !InStr(ErrorText.Message(err), expectedError))
                throw Error(message ? message : Format("Expected error containing '{1}' but got '{2}'", expectedError, ErrorText.Message(err)))
        }

        if !threw
            throw Error(message ? message : "Expected function to throw an error")
    }
}

; Suppress pop-up dialogs during tests by overriding MsgBox. Each call is recorded
; in TestRunner.dialogs and echoed to stdout.
MsgBox(text := "", title := "", options := "") {
    TestRunner.dialogs.Push({text: text, title: title, options: options})
    FileAppend(Format("MSGBOX [{1}] {2}`n", title, text), "*")
    ; Return a sensible default for Yes/No prompts
    if InStr(options, "YesNo")
        return "Yes"
    return "OK"
}
