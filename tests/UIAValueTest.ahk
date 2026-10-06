#Requires AutoHotkey v2.0
#Include ../UIAValue.ahk
#Include TestRunner.ahk

/**
 * Stands in for a UIA element. A real element with no ValuePattern cannot be used
 * in a deterministic unit test, so the stub reports the same value and capability
 * properties.
 */
class FakeElement {
    __New(value := "", legacyValue := "", hasValuePattern := true, hasLegacyPattern := false) {
        this.storedValue := value
        this.legacyValue := legacyValue
        this.hasValuePattern := hasValuePattern
        this.hasLegacyPattern := hasLegacyPattern
    }

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return this.storedValue
            case UIA.Property.LegacyIAccessibleValue: return this.legacyValue
            case UIA.Property.IsValuePatternAvailable: return this.hasValuePattern
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return this.hasLegacyPattern
        }
        return ""
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
        "TestFailedLegacyReadIsNotConvertedToSupportedBlank"
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

    ; The Sticky Notes path: no ValuePattern, so the legacy read decides.
    TestFailedLegacyReadIsNotConvertedToSupportedBlank() {
        result := UIAValue.TryRead(FailingLegacyReadElement())

        Assert.False(result.supported)
        Assert.Equal("", result.value)
    }
}

class FailingLegacyReadElement {
    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.LegacyIAccessibleValue: throw Error("legacy read failed")
            case UIA.Property.IsValuePatternAvailable: return false
            case UIA.Property.IsLegacyIAccessiblePatternAvailable: return true
        }
        return ""
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
