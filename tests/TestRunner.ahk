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
    
    static RunTestClass(testClass) {
        instance := testClass()
        if (HasProp(testClass, "Tests")) {
            for methodName in testClass.Tests {
                if (HasMethod(instance, "Setup"))
                    instance.Setup()
                this.RunTest(instance, methodName)
                if (HasMethod(instance, "Teardown"))
                    instance.Teardown()
            }
        }
    }
    
    static RunTest(instance, methodName) {
        try {
            instance.%methodName%()
            this.successes++
            FileAppend(Format("PASS {1}.{2}`n", instance.__Class, methodName), "*")
        } catch as err {
            this.failures++
            FileAppend(Format("FAIL {1}.{2}: {3}`n", instance.__Class, methodName, err.Message), "*")
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
        if (expected != actual)
            throw Error(message ? message : Format("Expected '{1}' but got '{2}'", expected, actual))
    }
    
    static NotEqual(expected, actual, message := "") {
        if (expected = actual)
            throw Error(message ? message : Format("Expected value different from '{1}'", expected))
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
        try {
            func()
            throw Error(message ? message : "Expected function to throw an error")
        } catch as err {
            if (expectedError && !InStr(err.Message, expectedError))
                throw Error(message ? message : Format("Expected error containing '{1}' but got '{2}'", expectedError, err.Message))
        }
    }
}
