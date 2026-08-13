#Requires AutoHotkey v2.0
#Include ../UIAValue.ahk
#Include TestRunner.ahk

/**
 * Stands in for a UIA element.
 *
 * A real element with no ValuePattern cannot be used here: touching .Value on one is
 * exactly the thing under test, and it raises an error from a destructor that no try
 * can catch, which would take the suite down with it. The stub reports the same
 * properties a real element would and records whether .Value was touched.
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

    ; Issue #32: the Sticky Notes field has no ValuePattern, and writing to .Value
    ; anyway produced an uncatchable destructor error. The write must be refused
    ; before it touches .Value at all.
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
