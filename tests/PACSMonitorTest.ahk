#Requires AutoHotkey v2.0
#Include ../PACSMonitor.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class PACSMonitorTest {
    static Tests := [
        "TestHasAccession",
        "TestProcessRowsFindsNewStudies",
        "TestMonitoringUsesTestMode",
        "TestOnSettingsChangedRespectsAutoRefresh"
    ]
    
    Setup() {
        this.originalSettings := Settings.settingsFile
        this.tempSettings := A_Temp "\pacs_monitor_settings_" A_TickCount ".ini"
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()
        
        PACSMonitor.testMode := true
        PACSMonitor.knownAccessions := []
        PACSMonitor.testStudyRows := []
        PACSMonitor.testRefreshCalls := 0
        PACSMonitor.testLastNewStudies := []
        PACSMonitor.refreshTimer := 0
    }
    
    TestHasAccession() {
        Assert.False(PACSMonitor.HasAccession("12345678"))
        PACSMonitor.knownAccessions.Push("12345678")
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
        PACSMonitor.knownAccessions := []
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}
