#Requires AutoHotkey v2.0
#Include ../MicrophoneManager.ahk
#Include TestRunner.ahk

class MicrophoneManagerTest {
    static Tests := [
        "WaitForSelectionRequiresTheRequestedValue",
        "FinalSelectionFailureNotifiesOnce",
        "OperationalErrorIsRecorded",
        "PickerReappearanceStartsANewLoginSession"
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
        MicrophoneManager.pickerPresent := false
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

    PickerReappearanceStartsANewLoginSession() {
        MicrophoneManager.pickerPresent := true
        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.failureNotified := true
        MicrophoneManager.lastError := "old failure"

        MicrophoneManager.RecordPickerPresence(false)
        Assert.False(MicrophoneManager.pickerPresent)
        Assert.Equal(0, MicrophoneManager.attempts)
        Assert.False(MicrophoneManager.failureNotified)
        Assert.Equal("", MicrophoneManager.lastError)

        MicrophoneManager.attempts := MicrophoneManager.maxAttempts
        MicrophoneManager.RecordPickerPresence(true)
        Assert.True(MicrophoneManager.pickerPresent)
        Assert.Equal(0, MicrophoneManager.attempts)
    }

    Teardown() {
        MicrophoneManager.notifier := this.originalNotifier
        MicrophoneManager.attempts := 0
        MicrophoneManager.failureNotified := false
        MicrophoneManager.lastError := ""
        MicrophoneManager.pickerPresent := false
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
