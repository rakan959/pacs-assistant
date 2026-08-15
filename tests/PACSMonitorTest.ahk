#Requires AutoHotkey v2.0
#Include ../PACSMonitor.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class PACSMonitorTest {
    static Tests := [
        "TestHasAccession",
        "TestProcessRowsFindsNewStudies",
        "TestRepeatedAccessionAlertsOnce",
        "TestInterruptedScanDoesNotConsumeUnalertedAccessions",
        "TestMonitoringUsesTestMode",
        "TestOnSettingsChangedRespectsAutoRefresh",
        "TestRefreshFailureNotificationUsesTextThenTitle",
        "TestScanFailuresNotifyOnceAndReset",
        "TestNewStudyNotificationUsesTextThenTitle",
        "TestFailedAlertDoesNotConsumeAccession"
    ]
    
    Setup() {
        this.originalSettings := Settings.settingsFile
        this.originalNotifier := PACSMonitor.notifier
        this.tempSettings := A_Temp "\pacs_monitor_settings_" A_TickCount ".ini"
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()
        
        PACSMonitor.testMode := true
        PACSMonitor.knownAccessions := Map()
        PACSMonitor.testStudyRows := []
        PACSMonitor.testRefreshCalls := 0
        PACSMonitor.testLastNewStudies := []
        PACSMonitor.refreshTimer := 0
        PACSMonitor.consecutiveRefreshFailures := 0
        PACSMonitor.refreshFailureNotified := false
        PACSMonitor.consecutiveScanFailures := 0
        PACSMonitor.scanFailureNotified := false
        PACSMonitor.lastError := ""
        this.notifications := []
        PACSMonitor.notifier := (text, title, options) => this.notifications.Push({
            text: text,
            title: title,
            options: options
        })
    }
    
    TestHasAccession() {
        Assert.False(PACSMonitor.HasAccession("12345678"))
        PACSMonitor.MarkAccessionSeen("12345678")
        Assert.True(PACSMonitor.HasAccession("12345678"))
    }
    
    TestProcessRowsFindsNewStudies() {
        PACSMonitor.testStudyRows := [
            {Name: "CT HEAD WITHOUT CONTRAST 12345678 87654321"},
            {Name: "XR CHEST 2 VIEW 99887766"}
        ]
        
        PACSMonitor.RefreshAndCheck()
        Assert.Equal(1, PACSMonitor.testRefreshCalls)
        Assert.True(PACSMonitor.HasAccession("12345678"))
        Assert.True(PACSMonitor.HasAccession("87654321"))
        Assert.True(PACSMonitor.HasAccession("99887766"))
        Assert.Equal(3, PACSMonitor.testLastNewStudies.Length)
    }
    
    ; An accession can appear in more than one row of a single refresh. It must be
    ; reported once, not once per row.
    TestRepeatedAccessionAlertsOnce() {
        PACSMonitor.testStudyRows := [
            {Name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {Name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {Name: "XR CHEST 2 VIEW 99887766"}
        ]

        PACSMonitor.RefreshAndCheck()
        Assert.Equal(2, PACSMonitor.testLastNewStudies.Length)
        Assert.True(PACSMonitor.HasAccession("12345678"))
        Assert.True(PACSMonitor.HasAccession("99887766"))
        Assert.Equal(2, PACSMonitor.knownAccessions.Count)

        ; A later pass over the same rows reports nothing new
        PACSMonitor.testLastNewStudies := []
        PACSMonitor.RefreshAndCheck()
        Assert.Equal(0, PACSMonitor.testLastNewStudies.Length)
    }

    ; UIA enumeration can fail after some rows have already been read. Accessions from
    ; that partial pass must remain eligible for the next successful scan.
    TestInterruptedScanDoesNotConsumeUnalertedAccessions() {
        rows := [
            {Name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {}  ; reading Name raises, simulating a stale UIA row
        ]

        Assert.Throws(() => PACSMonitor.ProcessRows(rows, true))
        Assert.False(PACSMonitor.HasAccession("12345678"))

        PACSMonitor.testLastNewStudies := []
        PACSMonitor.ProcessRows([{Name: "CT HEAD WITHOUT CONTRAST 12345678"}], true)
        Assert.Equal(1, PACSMonitor.testLastNewStudies.Length)
        Assert.True(PACSMonitor.HasAccession("12345678"))
    }

    TestMonitoringUsesTestMode() {
        Settings.Set("AutoRefreshPACS", true)
        Settings.Set("RefreshInterval", 1)
        PACSMonitor.StartMonitoring()
        Assert.Equal(-1, PACSMonitor.refreshTimer)
        Assert.True(PACSMonitor.testRefreshCalls >= 1)
        PACSMonitor.StopMonitoring()
        Assert.Equal(0, PACSMonitor.refreshTimer)
    }
    
    TestOnSettingsChangedRespectsAutoRefresh() {
        Settings.Set("AutoRefreshPACS", true)
        PACSMonitor.StartMonitoring()
        Settings.Set("AutoRefreshPACS", false)
        PACSMonitor.OnSettingsChanged()
        Assert.Equal(0, PACSMonitor.refreshTimer)
    }

    TestRefreshFailureNotificationUsesTextThenTitle() {
        loop PACSMonitor.refreshFailureThreshold
            PACSMonitor.RecordRefreshResult(false)

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "refresh button") > 0)
        Assert.Equal("PACS auto-refresh is not working", this.notifications[1].title)
    }

    TestScanFailuresNotifyOnceAndReset() {
        loop PACSMonitor.scanFailureThreshold + 2
            PACSMonitor.RecordScanFailure("study list unavailable")

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "study list unavailable") > 0)
        Assert.Equal("PACS background monitoring failed", this.notifications[1].title)
        Assert.Equal("study list unavailable", PACSMonitor.lastError)

        PACSMonitor.RecordScanSuccess()
        Assert.Equal(0, PACSMonitor.consecutiveScanFailures)
        Assert.False(PACSMonitor.scanFailureNotified)
    }

    TestNewStudyNotificationUsesTextThenTitle() {
        Settings.Set("MessageBoxNewCase", true)
        Settings.Set("AudioAlertNewCase", false)
        PACSMonitor.testMode := false

        PACSMonitor.AlertNewCases([{studyType: "CT HEAD", accession: "12345678"}])

        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("CT HEAD", this.notifications[1].text)
        Assert.Equal("New Study Available", this.notifications[1].title)
    }

    TestFailedAlertDoesNotConsumeAccession() {
        Settings.Set("MessageBoxNewCase", true)
        Settings.Set("AudioAlertNewCase", false)
        PACSMonitor.testMode := false
        PACSMonitor.notifier := FailPACSNotification

        Assert.Throws(
            () => PACSMonitor.ProcessRows([{Name: "CT HEAD WITHOUT CONTRAST 12345678"}]),
            "notifications could not be delivered"
        )
        Assert.False(PACSMonitor.HasAccession("12345678"))
    }
    
    Teardown() {
        PACSMonitor.StopMonitoring()
        PACSMonitor.testMode := false
        PACSMonitor.testStudyRows := []
        PACSMonitor.testLastNewStudies := []
        PACSMonitor.knownAccessions := Map()
        PACSMonitor.notifier := this.originalNotifier
        PACSMonitor.consecutiveScanFailures := 0
        PACSMonitor.scanFailureNotified := false
        PACSMonitor.lastError := ""
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}

FailPACSNotification(*) {
    throw Error("simulated notification failure")
}
