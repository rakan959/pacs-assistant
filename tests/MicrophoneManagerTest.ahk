#Requires AutoHotkey v2.0
#Include ../MicrophoneManager.ahk
#Include TestRunner.ahk

class MicrophoneManagerTest {
    static Tests := [
        "WaitForSelectionRequiresTheRequestedValue",
        "FinalSelectionFailureNotifiesOnce",
        "OperationalErrorIsRecorded"
    ]

    Setup() {
        this.originalNotifier := MicrophoneManager.notifier
        this.notifications := []
        MicrophoneManager.notifier := (text, title, options) => this.notifications.Push({
            text: text,
            title: title,
            options: options
        })
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
    }

    WaitForSelectionRequiresTheRequestedValue() {
        matching := FakeMicrophoneCombo("PowerMic III")
        other := FakeMicrophoneCombo("Internal Microphone")

        Assert.True(MicrophoneManager.WaitForSelection(matching, "PowerMic", 0))
        Assert.False(MicrophoneManager.WaitForSelection(other, "PowerMic", 0))
    }

    FinalSelectionFailureNotifiesOnce() {
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.RecordSelectionFailure("PowerMic")
        MicrophoneManager.RecordSelectionFailure("PowerMic")

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "PowerMic") > 0)
        Assert.Equal("PowerScribe microphone was not changed", this.notifications[1].title)
    }

    OperationalErrorIsRecorded() {
        MicrophoneManager.RecordOperationalError(Error("UIA unavailable"))

        Assert.Equal("UIA unavailable", MicrophoneManager.lastError)
    }

    Teardown() {
        MicrophoneManager.notifier := this.originalNotifier
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
    }
}

class FakeMicrophoneCombo {
    __New(value) {
        this.value := value
    }

    GetPropertyValue(propertyId) {
        if (propertyId = UIA.Property.ValueValue)
            return this.value
        return ""
    }
}
