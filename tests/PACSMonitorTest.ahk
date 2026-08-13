#Requires AutoHotkey v2.0
#Include ../PACSMonitor.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class PACSMonitorTest {
    static Tests := [
        "TestHasAccession",
        "TestProcessRowsFindsNewStudies",
        "TestRepeatedAccessionAlertsOnce",
        "TestMonitoringUsesTestMode",
        "TestOnSettingsChangedRespectsAutoRefresh"
    ]
    
    Setup() {
        this.originalSettings := Settings.settingsFile
        this.tempSettings := A_Temp "\pacs_monitor_settings_" A_TickCount ".ini"
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()
        
        PACSMonitor.testMode := true
        PACSMonitor.knownAccessions := Map()
        PACSMonitor.testStudyRows := []
        PACSMonitor.testRefreshCalls := 0
        PACSMonitor.testLastNewStudies := []
        PACSMonitor.refreshTimer := 0
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
    
    Teardown() {
        PACSMonitor.StopMonitoring()
        PACSMonitor.testMode := false
        PACSMonitor.testStudyRows := []
        PACSMonitor.testLastNewStudies := []
        PACSMonitor.knownAccessions := Map()
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}
