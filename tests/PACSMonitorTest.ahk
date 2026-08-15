#Requires AutoHotkey v2.0
#Include ../PACSMonitor.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk

class PACSMonitorTest {
    static Tests := [
        "TestHasAccession",
        "TestProcessRowsFindsNewStudies",
        "TestProcessRowsPreservesLongModalityPrefix",
        "TestRepeatedAccessionAlertsOnce",
        "TestInterruptedScanDoesNotConsumeUnalertedAccessions",
        "TestMonitoringUsesTestMode",
        "TestRefreshButtonRequiresSemanticIdentity",
        "TestRefreshButtonMustBeUniqueWithinThePortal",
        "TestRefreshAndScanUseOneCapturedPortalSession",
        "TestStudyListFallbackRequiresExpectedTypeAndProcess",
        "TestStudyListDoesNotUseGenericFirstMatch",
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

    TestProcessRowsPreservesLongModalityPrefix() {
        PACSMonitor.ProcessRows([
            {Name: "MRI BRAIN WITHOUT CONTRAST 12345678"},
            {Name: "CTA HEAD AND NECK 87654321"}
        ], true)

        Assert.Equal("MRI BRAIN WITHOUT CONTRAST", PACSMonitor.testLastNewStudies[1].studyType)
        Assert.Equal("CTA HEAD AND NECK", PACSMonitor.testLastNewStudies[2].studyType)
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

    TestRefreshButtonRequiresSemanticIdentity() {
        root := FakePACSTargetElement(UIA.Type.Window, 42)
        valid := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh studies", "refreshButton", true)
        wrongType := FakePACSTargetElement(UIA.Type.Edit, 42, "Refresh", "refreshButton", true)
        wrongMeaning := FakePACSTargetElement(UIA.Type.Button, 42, "Delete", "deleteButton", true)
        wrongProcess := FakePACSTargetElement(UIA.Type.Button, 99, "Refresh", "refreshButton", true)
        wrongWindow := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh", "refreshButton", true, 200)

        Assert.True(PACSMonitor.IsExpectedRefreshButton(root, valid))
        Assert.False(PACSMonitor.IsExpectedRefreshButton(root, wrongType))
        Assert.False(PACSMonitor.IsExpectedRefreshButton(root, wrongMeaning))
        Assert.False(PACSMonitor.IsExpectedRefreshButton(root, wrongProcess))
        Assert.False(PACSMonitor.IsExpectedRefreshButton(root, wrongWindow))
    }

    TestRefreshButtonMustBeUniqueWithinThePortal() {
        first := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh studies", "refreshPrimary", true)
        second := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh panel", "refreshSecondary", true)
        root := FakePACSRefreshRoot(42, 100, [first, second])

        Assert.Equal(0, PACSMonitor.FindRefreshButton(root))
    }

    TestRefreshAndScanUseOneCapturedPortalSession() {
        originalTestMode := PACSMonitor.testMode
        originalDriver := PACSMonitor.driver
        session := {
            hwnd: 100,
            target: "ahk_id 100",
            processId: 42,
            title: "Explorer Portal",
            exe: "msedge.exe"
        }
        button := FakePACSActionButton(42, 100, "Refresh", "refreshPrimary")
        studyList := FakePACSStudyList(
            42,
            100,
            {Name: "CT HEAD WITHOUT CONTRAST 12345678"}
        )
        driver := PinnedPortalMonitorDriver(session, button, studyList)

        try {
            PACSMonitor.testMode := false
            PACSMonitor.driver := driver
            PACSMonitor.knownAccessions := Map()
            PACSMonitor.RefreshAndCheck()
            marked := PACSMonitor.HasAccession("12345678")
        } finally {
            PACSMonitor.driver := originalDriver
            PACSMonitor.testMode := originalTestMode
        }

        Assert.True(marked)
        Assert.Equal(1, driver.resolveCalls)
        Assert.Equal(2, driver.rootTargets.Length)
        Assert.Equal("ahk_id 100", driver.rootTargets[1])
        Assert.Equal("ahk_id 100", driver.rootTargets[2])
        Assert.True(driver.liveChecks >= 2)
        Assert.Equal(0, driver.restoreCalls)
        Assert.Equal(1, button.clickCalls)
        Assert.Equal(0, button.controlClickCalls)
    }

    TestStudyListFallbackRequiresExpectedTypeAndProcess() {
        root := FakePACSTargetElement(UIA.Type.Window, 42)

        Assert.True(PACSMonitor.IsExpectedStudyList(
            root,
            FakePACSTargetElement(UIA.Type.DataGrid, 42)
        ))
        Assert.False(PACSMonitor.IsExpectedStudyList(
            root,
            FakePACSTargetElement(UIA.Type.Button, 42)
        ))
        Assert.False(PACSMonitor.IsExpectedStudyList(
            root,
            FakePACSTargetElement(UIA.Type.List, 99)
        ))
        Assert.False(PACSMonitor.IsExpectedStudyList(
            root,
            FakePACSTargetElement(UIA.Type.List, 42, "", "", false, 200)
        ))
    }

    TestStudyListDoesNotUseGenericFirstMatch() {
        genericList := FakePACSTargetElement(UIA.Type.DataGrid, 42)
        root := FakePACSStudyRoot(42, 100, 0, genericList)

        Assert.Equal(0, PACSMonitor.FindStudyList(root))
        Assert.Equal(0, root.genericFindCalls)
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

class FakePACSTargetElement {
    __New(type, processId, name := "", automationId := "", invoke := false, windowId := 100) {
        this.Type := type
        this.ProcessId := processId
        this.WinId := windowId
        this.Name := name
        this.AutomationId := automationId
        this.IsInvokePatternAvailable := invoke
        this.IsLegacyIAccessiblePatternAvailable := false
        this.NativeWindowHandle := 0
    }
}

class FakePACSStudyRoot {
    __New(processId, windowId, pathResult, genericResult) {
        this.ProcessId := processId
        this.WinId := windowId
        this.pathResult := pathResult
        this.genericResult := genericResult
        this.genericFindCalls := 0
    }

    ElementFromPath(*) {
        return this.pathResult
    }

    FindElement(*) {
        this.genericFindCalls++
        return this.genericResult
    }
}

class FakePACSRefreshRoot extends FakePACSTargetElement {
    __New(processId, windowId, candidates) {
        super.__New(UIA.Type.Window, processId, "", "", false, windowId)
        this.candidates := candidates
    }

    FindElements(*) {
        return this.candidates.Clone()
    }
}

class FakePACSActionButton extends FakePACSTargetElement {
    __New(processId, windowId, name, automationId) {
        super.__New(UIA.Type.Button, processId, name, automationId, true, windowId)
        this.clickCalls := 0
        this.controlClickCalls := 0
    }

    Click(*) {
        this.clickCalls++
        return true
    }

    ControlClick(*) {
        this.controlClickCalls++
        return true
    }
}

class FakePACSStudyList extends Array {
    __New(processId, windowId, rows*) {
        this.ProcessId := processId
        this.WinId := windowId
        this.Type := UIA.Type.DataGrid
        for row in rows
            this.Push(row)
    }
}

class PinnedPortalMonitorDriver {
    __New(session, button, studyList) {
        this.session := session
        this.button := button
        this.studyList := studyList
        this.resolveCalls := 0
        this.liveChecks := 0
        this.rootTargets := []
        this.rootCalls := 0
        this.restoreCalls := 0
    }

    ResolvePortalSession() {
        this.resolveCalls++
        return this.session
    }

    SessionIsLive(session) {
        this.liveChecks++
        return session.hwnd = this.session.hwnd
            && session.processId = this.session.processId
    }

    IsActive(*) {
        return false
    }

    GetActiveWindow() {
        return 0
    }

    RestoreActiveWindow(*) {
        this.restoreCalls++
    }

    RootForSession(session) {
        this.rootTargets.Push(session.target)
        this.rootCalls++
        if (this.rootCalls = 1)
            return FakePACSRefreshRoot(session.processId, session.hwnd, [this.button])
        return FakePACSStudyRoot(session.processId, session.hwnd, this.studyList, 0)
    }

    WaitForRefresh() {
    }
}

FailPACSNotification(*) {
    throw Error("simulated notification failure")
}
