#Requires AutoHotkey v2.0
#Include ../UIAValue.ahk
#Include TestRunner.ahk

/**
 * Stands in for a UIA element.
 *
 * A real element with no ValuePattern cannot be used in a deterministic unit test.
 * The stub reports the same capability properties and records whether .Value was
 * touched, which verifies that the adapter checks support before invoking a pattern.
 */
class FakeElement {
    __New(value := "", legacyValue := "", hasValuePattern := true) {
        this.storedValue := value
        this.legacyValue := legacyValue
        this.hasValuePattern := hasValuePattern
        this.valueWasWritten := false
    }

    GetPropertyValue(propertyId) {
        switch propertyId {
            case UIA.Property.ValueValue: return this.storedValue
            case UIA.Property.LegacyIAccessibleValue: return this.legacyValue
            case UIA.Property.IsValuePatternAvailable: return this.hasValuePattern
        }
        return ""
    }

    Value {
        get => this.storedValue
        set => (this.valueWasWritten := true, this.storedValue := value)
    }
}

class UIAValueTest {
    static Tests := [
        "TestReadPrefersValueProperty",
        "TestReadFallsBackToLegacyValue",
        "TestReadReturnsBlankWhenNothingExposed",
        "TestCanWriteReflectsPatternAvailability",
        "TestWriteRefusesWhenPatternMissing",
        "TestWriteSucceedsWhenPatternPresent"
    ]

    TestReadPrefersValueProperty() {
        Assert.Equal("report text", UIAValue.Read(FakeElement("report text", "legacy")))
    }

    TestReadFallsBackToLegacyValue() {
        Assert.Equal("legacy", UIAValue.Read(FakeElement("", "legacy")))
    }

    TestReadReturnsBlankWhenNothingExposed() {
        Assert.Equal("", UIAValue.Read(FakeElement("", "")))
        ; An object that raises on every property must not propagate
        Assert.Equal("", UIAValue.Read({}))
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
}
