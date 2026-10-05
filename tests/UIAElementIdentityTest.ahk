#Requires AutoHotkey v2.0
#Include ../UIAElementIdentity.ahk
#Include TestRunner.ahk

; The fakes carry no COM pointer, so the provider comparison always fails and the
; property comparison decides, as it does when CompareElements misses a match.
class UIAElementIdentityTest {
    static tests := [
        "TestTheSameWrapperIsTheSameElement",
        "TestIndistinguishableElementsCompareEqual",
        "TestAnyDifferingPropertySeparatesElements",
        "TestUnreadablePropertiesFailClosedOrPropagate",
        "TestContainsDeduplicatesIndistinguishableElements"
    ]

    TestTheSameWrapperIsTheSameElement() {
        element := FakeIdentityElement()
        Assert.True(UIAElementIdentity.Same(element, element))
        Assert.True(UIAElementIdentity.SameStrict(element, element))
        Assert.False(UIAElementIdentity.Same(element, 0))
        Assert.False(UIAElementIdentity.SameStrict(0, element))
    }

    TestIndistinguishableElementsCompareEqual() {
        Assert.True(UIAElementIdentity.Same(FakeIdentityElement(), FakeIdentityElement()))
        Assert.True(UIAElementIdentity.SameStrict(FakeIdentityElement(), FakeIdentityElement()))
        ; Names compare without regard to case.
        Assert.True(UIAElementIdentity.Same(FakeIdentityElement(), FakeIdentityElement({Name: "POWERMIC III"})))
    }

    TestAnyDifferingPropertySeparatesElements() {
        for changed in [
            {Type: 50000},
            {Name: "PowerMic II"},
            {ClassName: "Button"},
            {AutomationId: "other"},
            {BoundingRectangle: {l: 0, t: 20, r: 100, b: 40}}
        ] {
            Assert.False(UIAElementIdentity.Same(FakeIdentityElement(), FakeIdentityElement(changed)))
        }
    }

    TestUnreadablePropertiesFailClosedOrPropagate() {
        unreadable := FakeIdentityElement({throwOnName: true})

        Assert.False(UIAElementIdentity.Same(FakeIdentityElement(), unreadable))
        Assert.Throws(ObjBindMethod(UIAElementIdentity, "SameStrict", FakeIdentityElement(), unreadable), "simulated property failure")
    }

    TestContainsDeduplicatesIndistinguishableElements() {
        list := [FakeIdentityElement()]
        Assert.True(UIAElementIdentity.Contains(list, FakeIdentityElement()))
        Assert.False(UIAElementIdentity.Contains(list, FakeIdentityElement({Name: "PowerMic II"})))
    }
}

class FakeIdentityElement {
    __New(overrides := 0) {
        this.values := {
            Type: 50007,
            Name: "PowerMic III",
            ClassName: "ListBoxItem",
            AutomationId: "",
            BoundingRectangle: {l: 0, t: 0, r: 100, b: 20},
            throwOnName: false
        }
        if IsObject(overrides) {
            for name, value in overrides.OwnProps()
                this.values.%name% := value
        }
    }

    Type => this.values.Type
    ClassName => this.values.ClassName
    AutomationId => this.values.AutomationId
    BoundingRectangle => this.values.BoundingRectangle

    Name {
        get {
            if this.values.throwOnName
                throw Error("simulated property failure")
            return this.values.Name
        }
    }
}
