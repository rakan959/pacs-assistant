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

; A notifier double that records each call in notifications, for example
; PACSMonitor.notifier := RecordNotification.Bind(list).
RecordNotification(notifications, text, title, options := "") {
    notifications.Push({text: text, title: title, options: options})
}

class TestRunner {
    static tests := []
    static successes := 0
    static failures := 0
    static completed := false
    ; Dialogs raised through the MsgBox override below during the current test, so a
    ; test can assert which message a failure path showed rather than only its result.
    static dialogs := []

    static AddTest(testClass) {
        this.tests.Push(testClass)
    }

    static RunAll() {
        this.successes := 0
        this.failures := 0
        this.completed := false
        ; Production code under test can reach ExitApp. Without this guard such a
        ; test would end the run with exit code 0, no summary, and every later test
        ; silently skipped.
        OnExit(ObjBindMethod(this, "RequireCompletedRun"))

        for testClass in this.tests {
            this.RunTestClass(testClass)
        }

        this.ReportResults()
        this.completed := true
    }

    ; OnExit callback: turns an otherwise "successful" exit into exit code 11 when
    ; RunAll did not finish or ran no tests. Failure exit codes pass through.
    static RequireCompletedRun(exitReason, exitCode) {
        if (exitCode != 0 || (this.completed && this.successes + this.failures > 0))
            return 0
        try FileAppend("INCOMPLETE test run: the process exited (" exitReason ") before every test finished or no test ran.`n", "**")
        ExitApp(11)
    }

    static RunTestClass(testClass, report := true) {
        className := testClass.Prototype.__Class
        ; A registered class without a test list would otherwise contribute nothing
        ; and still leave the suite green.
        if !HasProp(testClass, "tests") {
            this.RecordFailure(className, "(test list)", Error("Test class has no static tests list"), report)
            return
        }

        ; A test missing from the list would otherwise never run, silently.
        unlisted := this.UnlistedMethods(testClass)
        if unlisted.Length {
            names := ""
            for name in unlisted
                names .= (names = "" ? "" : ", ") name
            this.RecordFailure(className, "(test list)", Error("Methods in neither the tests nor the helpers list: " names), report)
        }

        try instance := testClass()
        catch Any as err {
            for methodName in testClass.tests
                this.RecordFailure(className, methodName, err, report)
            return
        }

        for methodName in testClass.tests {
            this.RunTest(instance, methodName, report)
        }
    }

    ; Instance methods that are neither listed tests, declared helpers (an optional
    ; static helpers list) nor fixture hooks.
    static UnlistedMethods(testClass) {
        known := Map()
        known.CaseSense := false
        for name in ["__Init", "__New", "__Delete", "Setup", "Teardown"]
            known[name] := true
        for name in testClass.tests
            known[name] := true
        if HasProp(testClass, "helpers") {
            for name in testClass.helpers
                known[name] := true
        }
        unlisted := []
        for name in testClass.Prototype.OwnProps() {
            if (!known.Has(name) && HasMethod(testClass.Prototype, name))
                unlisted.Push(name)
        }
        return unlisted
    }

    static RunTest(instance, methodName, report := true) {
        ; Track failure separately from the thrown value: a test that throws 0 or ""
        ; still failed.
        failed := false
        failure := ""
        this.dialogs := []

        ; catch Any: AutoHotkey can throw non-Error values, and one that escaped here
        ; would reach the OnError handler and end the whole run.
        try {
            if (HasMethod(instance, "Setup"))
                instance.Setup()
            instance.%methodName%()
        } catch Any as err {
            failed := true
            failure := err
        }

        ; Setup can mutate globals or fixtures before it raises. Teardown is the only
        ; reliable cleanup boundary, so invoke it after every attempted test even
        ; when setup itself failed.
        if HasMethod(instance, "Teardown") {
            try instance.Teardown()
            catch Any as teardownError {
                failure := failed
                    ? Error(Format(
                        "{1}; teardown failed: {2}",
                        ErrorText.Describe(failure),
                        ErrorText.Describe(teardownError)
                    ))
                    : teardownError
                failed := true
            }
        }

        if failed
            this.RecordFailure(instance.__Class, methodName, failure, report)
        else
            this.RecordPass(instance.__Class, methodName, report)
    }

    static RecordPass(className, methodName, report := true) {
        this.successes++
        if (report)
            FileAppend(Format("PASS {1}.{2}`n", className, methodName), "*")
    }

    ; thrown is whatever was thrown, which may be falsy (0 or "").
    static RecordFailure(className, methodName, thrown, report := true) {
        this.failures++
        if (report)
            FileAppend(Format("FAIL {1}.{2}: {3}`n", className, methodName, ErrorText.Describe(thrown)), "*")
    }

    static ReportResults() {
        total := this.successes + this.failures
        FileAppend(Format("`nTest Results:`n============`nTotal: {1}`nPassed: {2}`nFailed: {3}`n",
            total, this.successes, this.failures), "*")
    }
}

; A failed assertion is reported at the test line that made it (Error's -1 frame),
; not inside this class.
class Assert {
    static Equal(expected, actual, message := "") {
        if !this.ExactlyEqual(expected, actual)
            throw Error(this.Failure(message, Format(
                "expected '{1}' but got '{2}'",
                this.Show(expected),
                this.Show(actual)
            )), -1)
    }

    static NotEqual(expected, actual, message := "") {
        if this.ExactlyEqual(expected, actual)
            throw Error(this.Failure(message, Format(
                "expected a value different from '{1}'",
                this.Show(expected)
            )), -1)
    }

    static ExactlyEqual(expected, actual) {
        return Type(expected) == Type(actual) && expected == actual
    }

    ; Format cannot render an object, so name its type instead.
    static Show(value) {
        return IsObject(value) ? "<" Type(value) ">" : value
    }

    ; A caller's message leads and the computed detail follows in parentheses, so
    ; the failure still says what actually happened.
    static Failure(message, detail) {
        return message = ""
            ? StrUpper(SubStr(detail, 1, 1)) SubStr(detail, 2)
            : message " (" detail ")"
    }

    static True(value, message := "") {
        if (!value)
            throw Error(this.Failure(message, "expected true but got false"), -1)
    }

    static False(value, message := "") {
        if (value)
            throw Error(this.Failure(message, "expected false but got true"), -1)
    }

    static Throws(callback, expectedError := "", message := "") {
        ; Track the throw separately: a thrown 0 or "" is falsy but still a throw.
        threw := false
        try {
            callback()
        } catch Any as err {
            threw := true
            if (expectedError && !InStr(ErrorText.Message(err), expectedError))
                throw Error(this.Failure(message, Format(
                    "expected an error containing '{1}' but got '{2}'",
                    expectedError,
                    ErrorText.Message(err)
                )), -1)
        }

        if !threw
            throw Error(this.Failure(message, "expected the function to throw an error"), -1)
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
