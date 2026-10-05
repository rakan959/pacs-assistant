#Requires AutoHotkey v2.0
#Include ../UIAValue.ahk
#Include TestRunner.ahk

/**
 * Stands in for a UIA element.
 *
 * A real element with no ValuePattern cannot be used in a deterministic unit test.
 * The stub reports the same capability properties, exposes ValuePattern and the
 * legacy pattern, and models UIA-v2's combined Value setter, which falls back to
 * the legacy pattern when the ValuePattern write fails. writeAttempts records each
 * pattern written through.
 */
class FakeElement {
    __New(value := "", legacyValue := "", hasValuePattern := true, hasLegacyPattern := false, writeErrorAfterMutation := "") {
        this.storedValue := value
        this.legacyValue := legacyValue
        this.hasValuePattern := hasValuePattern
        this.hasLegacyPattern := hasLegacyPattern
        this.valueWasWritten := false
        this.writeErrorAfterMutation := writeErrorAfterMutation
        this.writeAttempts := []
    }

    ValuePattern => FakeValuePattern(this)
    LegacyIAccessiblePattern => FakeLegacyPattern(this)

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return this.storedValue
            case UIA.Property.LegacyIAccessibleValue: return this.legacyValue
            case UIA.Property.IsValuePatternAvailable: return this.hasValuePattern
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return this.hasLegacyPattern
        }
        return ""
    }

    Value {
        get => this.storedValue
        set {
            try return this.ValuePattern.SetValue(value)
            try return this.LegacyIAccessiblePattern.SetValue(value)
            throw Error("Setting the value failed! Is ValuePattern, RangeValuePattern or LegacyIAccessiblePattern supported?")
        }
    }
}

class FakeValuePattern {
    __New(element) {
        this.element := element
    }

    SetValue(text) {
        this.element.writeAttempts.Push("Value")
        this.element.valueWasWritten := true
        this.element.storedValue := text
        if (this.element.writeErrorAfterMutation != "")
            throw Error(this.element.writeErrorAfterMutation)
    }
}

class FakeLegacyPattern {
    __New(element) {
        this.element := element
    }

    SetValue(text) {
        this.element.writeAttempts.Push("Legacy")
        this.element.storedValue := text
    }
}

class UIAValueTest {
    static tests := [
        "TestReadPrefersValueProperty",
        "TestReadFallsBackToLegacyValue",
        "TestReadReturnsBlankWhenNothingExposed",
        "TestTryReadPreservesSupportedBlank",
        "TestSupportedBlankDoesNotFallThroughToLegacy",
        "TestFailedReadIsNotConvertedToSupportedBlank",
        "TestCanWriteReflectsPatternAvailability",
        "TestWriteRefusesWhenPatternMissing",
        "TestWriteSucceedsWhenPatternPresent",
        "TestWritePropagatesPostMutationError"
    ]

    TestReadPrefersValueProperty() {
        result := UIAValue.TryRead(FakeElement("report text", "legacy"))
        Assert.True(result.supported)
        Assert.Equal("report text", result.value)
    }

    TestReadFallsBackToLegacyValue() {
        result := UIAValue.TryRead(FakeElement("", "legacy", false, true))
        Assert.True(result.supported)
        Assert.Equal("legacy", result.value)
    }

    TestReadReturnsBlankWhenNothingExposed() {
        emptyResult := UIAValue.TryRead(FakeElement("", "", false, false))
        Assert.False(emptyResult.supported)
        Assert.Equal("", emptyResult.value)
        ; An object that raises on every property must not propagate
        missingResult := UIAValue.TryRead({})
        Assert.False(missingResult.supported)
        Assert.Equal("", missingResult.value)
    }

    TestTryReadPreservesSupportedBlank() {
        result := UIAValue.TryRead(FakeElement("", "", true, false))

        Assert.True(result.supported)
        Assert.Equal("", result.value)
    }

    TestSupportedBlankDoesNotFallThroughToLegacy() {
        result := UIAValue.TryRead(FakeElement("", "stale legacy value", true, true))

        Assert.True(result.supported)
        Assert.Equal("", result.value)
    }

    TestFailedReadIsNotConvertedToSupportedBlank() {
        result := UIAValue.TryRead(FailingValueReadElement())

        Assert.False(result.supported)
        Assert.Equal("", result.value)
    }

    TestCanWriteReflectsPatternAvailability() {
        Assert.True(UIAValue.CanWrite(FakeElement("", "", true)))
        Assert.False(UIAValue.CanWrite(FakeElement("", "", false)))
        Assert.False(UIAValue.CanWrite({}))
    }

    ; The Sticky Notes field has no ValuePattern. Refuse the unsupported operation
    ; before touching .Value, independent of how UIA-v2 reports that condition.
    TestWriteRefusesWhenPatternMissing() {
        el := FakeElement("", "", false)
        Assert.False(UIAValue.Write(el, "wet read"))
        Assert.False(el.valueWasWritten, "Write must not touch .Value when the pattern is unavailable")
        Assert.Equal("", el.storedValue)
    }

    TestWriteSucceedsWhenPatternPresent() {
        el := FakeElement("", "", true)
        Assert.True(UIAValue.Write(el, "wet read"))
        Assert.True(el.valueWasWritten)
        Assert.Equal("wet read", el.storedValue)
    }

    ; One write through ValuePattern and its own error: UIA-v2's combined setter would
    ; write again through another pattern and replace the error.
    TestWritePropagatesPostMutationError() {
        el := FakeElement("existing", "", true, true, "provider failed after mutation")

        Assert.Throws(
            () => UIAValue.Write(el, "wet read"),
            "provider failed after mutation"
        )
        Assert.Equal("wet read", el.storedValue)
        Assert.Equal(1, el.writeAttempts.Length)
        Assert.Equal("Value", el.writeAttempts[1])
    }
}

class FailingValueReadElement {
    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: throw Error("value read failed")
            case UIA.Property.IsValuePatternAvailable: return true
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return false
        }
        return ""
    }
}
