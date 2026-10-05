; = CONTENTS
;   + Preamble
;   + PACSMonitorTest class (study-list refresh, accession detection, alerts, portal targeting)
;   + Test doubles (timer/portal drivers, study & refresh roots, action buttons, notification fakes)

#Requires AutoHotkey v2.0
#Include ../PACSMonitor.ahk
#Include ../PACSCommands.ahk
#Include ../Settings.ahk
#Include TestRunner.ahk
#Include LogCapture.ahk

class PACSMonitorTest {
    static tests := [
        "TestHasAccession",
        "TestNoApprovedRefreshIdSkipsTheButtonSearch",
        "TestProcessRowsFindsNewStudies",
        "TestProcessRowsPreservesLongModalityPrefix",
        "TestStudyNotificationDropsPatientNamePrefix",
        "TestAmbiguousFlattenedRowDoesNotNotify",
        "TestProcessRowsRequiresAnExactEightDigitAccession",
        "TestAmbiguousNumericColumnsDoNotBecomeAccessions",
        "TestRepeatedAccessionAlertsOnce",
        "TestDisabledAlertsDoNotConsumeFutureStudyNotification",
        "TestInterruptedScanDoesNotConsumeUnalertedAccessions",
        "TestMonitoringUsesInjectedTimer",
        "TestRefreshButtonRequiresSemanticIdentity",
        "TestRefreshButtonMustBeUniqueWithinThePortal",
        "TestRefreshButtonEnumerationErrorFailsClosed",
        "TestDuplicateRefreshAppearingBeforeClickDoesNotInvoke",
        "TestPortalActivationBeforeClickDoesNotInvokeRefresh",
        "TestActiveClinicalLeaseSkipsBackgroundMonitor",
        "TestRefreshWaitDoesNotHoldClinicalLease",
        "TestRefreshAndScanUseOneCapturedPortalSession",
        "TestAmbiguousPortalWindowsAreReportedAsScanFailure",
        "TestStudyListFallbackRequiresExpectedTypeAndProcess",
        "TestStudyListDoesNotUseGenericFirstMatch",
        "TestOnSettingsChangedRespectsAutoRefresh",
        "TestRefreshFailureNotificationUsesTextThenTitle",
        "TestScanFailuresNotifyOnceAndReset",
        "TestUnapprovedRefreshIsReportedOnceAsUnavailable",
        "TestNoAlertKindSkipsTheWorklistScan",
        "TestNewStudyNotificationUsesTextThenTitle",
        "TestFailedAlertDoesNotConsumeAccession",
        "TestCompactDateRecognitionHonorsCalendarRules"
    ]

    Setup() {
        this.originalSettings := Settings.settingsFile
        this.originalNotifier := PACSMonitor.notifier
        this.originalApprovedRefreshIds := PACSMonitor.approvedRefreshAutomationIds
        this.originalAutomationAcquire := PACSMonitor.automationAcquire
        this.originalAutomationRelease := PACSMonitor.automationRelease
        this.originalDriver := PACSMonitor.driver
        this.originalTimerDriver := PACSMonitor.timerDriver
        this.tempSettings := TestTempPath("pacs-monitor-settings", ".ini")
        Settings.settingsFile := this.tempSettings
        Settings.SaveAllSettings()

        PACSMonitor.driver := CountingPortalResolutionDriver()
        PACSMonitor.timerDriver := FakePACSTimerDriver()
        PACSMonitor.knownAccessions := Map()
        PACSMonitor.refreshTimer := 0
        PACSMonitor.consecutiveRefreshFailures := 0
        PACSMonitor.refreshFailureNotified := false
        PACSMonitor.refreshUnavailableNoted := false
        PACSMonitor.consecutiveScanFailures := 0
        PACSMonitor.scanFailureNotified := false
        PACSMonitor.lastError := ""
        this.notifications := []
        PACSMonitor.notifier := (text, title, options) => this.notifications.Push({
            text: text,
            title: title,
            options: options
        })
        PACSMonitor.approvedRefreshAutomationIds := [
            "refreshButton",
            "refreshPrimary",
            "refreshSecondary"
        ]
    }

    TestCompactDateRecognitionHonorsCalendarRules() {
        for value in ["20240229", "20000229", "19991231", "20250131", "20240430"]
            Assert.True(PACSMonitor.LooksLikeCompactDate(value), value " is a real calendar date")
        for value in ["19000229", "20230229", "20241301", "20240100", "20240431", "18991231", "21000101", "12345678"]
            Assert.False(PACSMonitor.LooksLikeCompactDate(value), value " is not a compact calendar date")
    }

    TestHasAccession() {
        Assert.False(PACSMonitor.HasAccession("12345678"))
        PACSMonitor.MarkAccessionSeen("12345678")
        Assert.True(PACSMonitor.HasAccession("12345678"))
    }

    TestProcessRowsFindsNewStudies() {
        studies := PACSMonitor.ProcessRows([
            {name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {name: "CT ABDOMEN 87654321"},
            {name: "XR CHEST 2 VIEW 99887766"}
        ], (*) => true)

        Assert.True(PACSMonitor.HasAccession("12345678"))
        Assert.True(PACSMonitor.HasAccession("87654321"))
        Assert.True(PACSMonitor.HasAccession("99887766"))
        Assert.Equal(3, studies.Length)
    }

    TestProcessRowsPreservesLongModalityPrefix() {
        studies := PACSMonitor.ProcessRows([
            {name: "MRI BRAIN WITHOUT CONTRAST 12345678"},
            {name: "CTA HEAD AND NECK 87654321"}
        ], (*) => true)

        Assert.Equal("MRI", studies[1].studyType)
        Assert.Equal("CTA", studies[2].studyType)
    }

    TestStudyNotificationDropsPatientNamePrefix() {
        studies := PACSMonitor.ProcessRows([
            {name: "DOE JOHN CT CHEST 12345678"}
        ], (*) => true)

        Assert.Equal(1, studies.Length)
        Assert.Equal("CT", studies[1].studyType)
        Assert.False(InStr(studies[1].studyType, "DOE") > 0)
        Assert.False(InStr(studies[1].studyType, "JOHN") > 0)

        PACSMonitor.knownAccessions := Map()
        studies := PACSMonitor.ProcessRows([
            {name: "CT CHEST DOE JOHN 87654321"}
        ], (*) => true)
        Assert.Equal("CT", studies[1].studyType)
        Assert.False(InStr(studies[1].studyType, "DOE") > 0)
    }

    TestAmbiguousFlattenedRowDoesNotNotify() {
        studies := PACSMonitor.ProcessRows([
            {name: "DOE CT JOHN MRI BRAIN 12345678"},
            {name: "12345678 DOE JOHN CT CHEST"}
        ], (*) => true)

        Assert.Equal(0, studies.Length)
        Assert.False(PACSMonitor.HasAccession("12345678"))
    }

    TestProcessRowsRequiresAnExactEightDigitAccession() {
        studies := PACSMonitor.ProcessRows([
            {name: "CT HEAD 1234567"},
            {name: "CT HEAD 123456789"},
            {name: "CT HEAD 87654321"}
        ], (*) => true)

        Assert.Equal(1, studies.Length)
        Assert.Equal("87654321", studies[1].accession)
        Assert.False(PACSMonitor.HasAccession("12345678"))
    }

    TestAmbiguousNumericColumnsDoNotBecomeAccessions() {
        studies := PACSMonitor.ProcessRows([
            {name: "DOE JOHN 19800101 CT CHEST 12345678"},
            {name: "CT CHEST 20260815"}
        ], (*) => true)

        Assert.Equal(0, studies.Length)
        Assert.False(PACSMonitor.HasAccession("19800101"))
        Assert.False(PACSMonitor.HasAccession("12345678"))
        Assert.False(PACSMonitor.HasAccession("20260815"))
    }

    ; An accession can appear in more than one row of a single refresh. It must be
    ; reported once, not once per row.
    TestRepeatedAccessionAlertsOnce() {
        rows := [
            {name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {name: "XR CHEST 2 VIEW 99887766"}
        ]

        studies := PACSMonitor.ProcessRows(rows, (*) => true)
        Assert.Equal(2, studies.Length)
        Assert.True(PACSMonitor.HasAccession("12345678"))
        Assert.True(PACSMonitor.HasAccession("99887766"))
        Assert.Equal(2, PACSMonitor.knownAccessions.Count)

        ; A later pass over the same rows reports nothing new
        studies := PACSMonitor.ProcessRows(rows, (*) => true)
        Assert.Equal(0, studies.Length)
    }

    TestDisabledAlertsDoNotConsumeFutureStudyNotification() {
        SetTestSetting("AudioAlertNewCase", false)
        SetTestSetting("MessageBoxNewCase", false)
        rows := [{name: "CT CHEST 12345678"}]

        PACSMonitor.ProcessRows(rows)
        unseenWhileDisabled := !PACSMonitor.HasAccession("12345678")

        SetTestSetting("MessageBoxNewCase", true)
        PACSMonitor.ProcessRows(rows)

        Assert.True(unseenWhileDisabled)
        Assert.True(PACSMonitor.HasAccession("12345678"))
        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("CT", this.notifications[1].text)
    }

    TestRefreshButtonRequiresSemanticIdentity() {
        root := FakePACSTargetElement(UIA.Type.Window, 42)
        valid := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh studies", "refreshButton", true)
        wrongType := FakePACSTargetElement(UIA.Type.Edit, 42, "Refresh", "refreshButton", true)
        wrongMeaning := FakePACSTargetElement(UIA.Type.Button, 42, "Delete", "deleteButton", true)
        wrongRefreshMeaning := FakePACSTargetElement(UIA.Type.Button, 42, "Auto Refresh", "autoRefresh", true)
        wrongProcess := FakePACSTargetElement(UIA.Type.Button, 99, "Refresh", "refreshButton", true)
        wrongWindow := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh", "refreshButton", true, 200)

        Assert.True(PACSMonitor.InspectRefreshButton(root, valid))
        Assert.False(PACSMonitor.InspectRefreshButton(root, wrongType))
        Assert.False(PACSMonitor.InspectRefreshButton(root, wrongMeaning))
        Assert.False(PACSMonitor.InspectRefreshButton(root, wrongRefreshMeaning))
        Assert.False(PACSMonitor.InspectRefreshButton(root, wrongProcess))
        Assert.False(PACSMonitor.InspectRefreshButton(root, wrongWindow))
    }

    TestRefreshButtonMustBeUniqueWithinThePortal() {
        first := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh studies", "refreshPrimary", true)
        second := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh panel", "refreshSecondary", true)
        root := FakePACSRefreshRoot(42, 100, [first, second])

        result := PACSMonitor.ResolveRefreshButton(root)
        Assert.Equal("ambiguous", result.status)
        Assert.Equal(0, result.button)
    }

    TestNoApprovedRefreshIdSkipsTheButtonSearch() {
        PACSMonitor.approvedRefreshAutomationIds := []
        candidate := FakePACSTargetElement(UIA.Type.Button, 42, "Refresh studies", "refreshPrimary", true)

        ; A throwing root proves the search never ran.
        result := PACSMonitor.ResolveRefreshButton(ThrowingPACSRefreshRoot(42, 100))

        Assert.Equal("absent", result.status)
        Assert.Equal(0, result.button)
        Assert.False(PACSMonitor.InspectRefreshButton(FakePACSRefreshRoot(42, 100, [candidate]), candidate))
    }

    TestRefreshButtonEnumerationErrorFailsClosed() {
        result := PACSMonitor.ResolveRefreshButton(
            ThrowingPACSRefreshRoot(42, 100)
        )

        Assert.Equal("error", result.status)
        Assert.Equal(0, result.button)
    }

    TestDuplicateRefreshAppearingBeforeClickDoesNotInvoke() {
        session := {
            hwnd: 100,
            target: "ahk_id 100",
            processId: 42,
            title: "Explorer Portal",
            exe: "msedge.exe"
        }
        saved := FakePACSActionButton(42, 100, "Refresh", "refreshPrimary")
        duplicate := FakePACSActionButton(42, 100, "Refresh panel", "refreshSecondary")
        root := ChangingPACSRefreshRoot(
            42,
            100,
            [saved],
            [saved, duplicate]
        )

        PACSMonitor.driver := FixedPortalSessionDriver(session)
        result := PACSMonitor.ClickRefresh(root, session)

        Assert.False(result)
        Assert.Equal(2, root.findCalls)
        Assert.Equal(0, saved.clickCalls)
        Assert.Equal(0, duplicate.clickCalls)
    }

    TestPortalActivationBeforeClickDoesNotInvokeRefresh() {
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
        driver := ActivationChangingPortalDriver(session, button, studyList)

        PACSMonitor.driver := driver
        PACSMonitor.RefreshAndCheck()

        Assert.True(driver.activeChecks >= 2)
        Assert.Equal(0, button.clickCalls)
    }

    TestActiveClinicalLeaseSkipsBackgroundMonitor() {
        originalClinicalActive := PACSCommands.clinicalCommandActive
        originalClinicalName := PACSCommands.activeClinicalCommand
        driver := CountingPortalResolutionDriver()

        try {
            PACSMonitor.driver := driver
            PACSMonitor.automationAcquire := ObjBindMethod(
                PACSCommands,
                "AcquireClinicalAutomation"
            )
            PACSMonitor.automationRelease := ObjBindMethod(
                PACSCommands,
                "ReleaseClinicalAutomation"
            )
            PACSCommands.clinicalCommandActive := true
            PACSCommands.activeClinicalCommand := "Paste Wet Read"

            result := PACSMonitor.RefreshAndCheck()
        } finally {
            PACSCommands.clinicalCommandActive := originalClinicalActive
            PACSCommands.activeClinicalCommand := originalClinicalName
        }

        Assert.False(result)
        Assert.Equal(0, driver.resolveCalls)
    }

    TestRefreshWaitDoesNotHoldClinicalLease() {
        originalClinicalActive := PACSCommands.clinicalCommandActive
        originalClinicalName := PACSCommands.activeClinicalCommand
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
        driver := LeaseObservingPortalDriver(session, button, studyList)

        try {
            PACSMonitor.driver := driver
            PACSMonitor.automationAcquire := ObjBindMethod(
                PACSCommands,
                "AcquireClinicalAutomation"
            )
            PACSMonitor.automationRelease := ObjBindMethod(
                PACSCommands,
                "ReleaseClinicalAutomation"
            )
            PACSCommands.clinicalCommandActive := false
            PACSCommands.activeClinicalCommand := ""

            PACSMonitor.RefreshAndCheck()
        } finally {
            PACSCommands.clinicalCommandActive := originalClinicalActive
            PACSCommands.activeClinicalCommand := originalClinicalName
        }

        Assert.Equal("acquired", driver.waitLeaseStatus)
        Assert.False(PACSCommands.clinicalCommandActive)
    }

    TestRefreshAndScanUseOneCapturedPortalSession() {
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

        PACSMonitor.driver := driver
        PACSMonitor.knownAccessions := Map()
        SetTestSetting("MessageBoxNewCase", true)
        PACSMonitor.RefreshAndCheck()
        marked := PACSMonitor.HasAccession("12345678")

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

    TestAmbiguousPortalWindowsAreReportedAsScanFailure() {
        driver := AmbiguousPortalMonitorDriver()

        PACSMonitor.driver := driver
        loop PACSMonitor.scanFailureThreshold
            PACSMonitor.RefreshAndCheck()
        failures := PACSMonitor.consecutiveScanFailures
        lastError := PACSMonitor.lastError

        Assert.Equal(PACSMonitor.scanFailureThreshold, failures)
        Assert.True(InStr(lastError, "multiple exact Explorer Portal windows") > 0)
        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("PACS Background Monitoring Failed", this.notifications[1].title)
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
            {name: "CT HEAD WITHOUT CONTRAST 12345678"},
            {}  ; reading Name raises, simulating a stale UIA row
        ]

        Assert.Throws(() => PACSMonitor.ProcessRows(rows, (*) => true))
        Assert.False(PACSMonitor.HasAccession("12345678"))

        studies := PACSMonitor.ProcessRows(
            [{name: "CT HEAD WITHOUT CONTRAST 12345678"}],
            (*) => true
        )
        Assert.Equal(1, studies.Length)
        Assert.True(PACSMonitor.HasAccession("12345678"))
    }

    TestMonitoringUsesInjectedTimer() {
        SetTestSetting("AutoRefreshPACS", true)
        SetTestSetting("RefreshInterval", 10)
        timerDriver := PACSMonitor.timerDriver
        portalDriver := PACSMonitor.driver

        PACSMonitor.StartMonitoring()
        Assert.True(IsObject(PACSMonitor.refreshTimer))
        Assert.Equal(1, timerDriver.startCalls)
        Assert.Equal(10000, timerDriver.interval)
        Assert.True(portalDriver.resolveCalls >= 1)

        PACSMonitor.StopMonitoring()
        Assert.Equal(0, PACSMonitor.refreshTimer)
        Assert.Equal(1, timerDriver.stopCalls)
    }

    TestOnSettingsChangedRespectsAutoRefresh() {
        SetTestSetting("AutoRefreshPACS", true)
        PACSMonitor.StartMonitoring()
        SetTestSetting("AutoRefreshPACS", false)
        PACSMonitor.OnSettingsChanged()
        Assert.Equal(0, PACSMonitor.refreshTimer)
    }

    TestRefreshFailureNotificationUsesTextThenTitle() {
        capturedLog := LogCapture()
        try {
            loop PACSMonitor.refreshFailureThreshold + 2
                PACSMonitor.RecordRefreshResult(false)
            PACSMonitor.RecordRefreshResult(true)
            PACSMonitor.RecordRefreshResult(true)
        } finally {
            logged := capturedLog.Count("PACS auto-refresh is not working: ")
            recovered := capturedLog.Count("PACS auto-refresh is working again")
            capturedLog.Restore()
        }
        Assert.Equal(1, logged)
        Assert.Equal(1, recovered)

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "Monitoring may be stale") > 0)
        Assert.True(InStr(this.notifications[1].text, "manually") > 0)
        Assert.Equal("PACS Auto-Refresh Not Working", this.notifications[1].title)
    }

    ; With no approved refresh control nothing can be clicked. That is a property of
    ; the build, not a failing refresh, so it is said once instead of as a recurring
    ; failure episode.
    TestUnapprovedRefreshIsReportedOnceAsUnavailable() {
        PACSMonitor.approvedRefreshAutomationIds := []
        session := {
            hwnd: 100,
            target: "ahk_id 100",
            processId: 42,
            title: "Explorer Portal",
            exe: "msedge.exe"
        }
        capturedLog := LogCapture()
        try {
            loop PACSMonitor.refreshFailureThreshold + 2 {
                PACSMonitor.driver := PinnedPortalMonitorDriver(
                    session,
                    FakePACSActionButton(42, 100, "Refresh", "refreshPrimary"),
                    FakePACSStudyList(42, 100)
                )
                PACSMonitor.RefreshAndCheck()
            }
            loggedUnavailable := capturedLog.Count("PACS auto-refresh is unavailable")
            loggedFailures := capturedLog.Count("PACS auto-refresh is not working")
        } finally capturedLog.Restore()

        titles := []
        for notification in this.notifications
            titles.Push(notification.title)
        Assert.Equal(1, loggedUnavailable)
        Assert.Equal(0, loggedFailures)
        Assert.Equal(0, PACSMonitor.consecutiveRefreshFailures)
        Assert.Equal(1, titles.Length)
        Assert.Equal("PACS Auto-Refresh Unavailable", titles[1])
        Assert.True(InStr(this.notifications[1].text, "yourself"), this.notifications[1].text)
    }

    ; The scan only feeds the alerts. With both kinds off, its result would be
    ; thrown away, so the study list is not read and no second lease is taken.
    TestNoAlertKindSkipsTheWorklistScan() {
        SetTestSetting("AudioAlertNewCase", false)
        SetTestSetting("MessageBoxNewCase", false)
        leases := []
        PACSMonitor.automationAcquire := (name) => (
            leases.Push(name),
            {status: "acquired", busyCommand: ""}
        )
        session := {
            hwnd: 100,
            target: "ahk_id 100",
            processId: 42,
            title: "Explorer Portal",
            exe: "msedge.exe"
        }
        driver := PinnedPortalMonitorDriver(
            session,
            FakePACSActionButton(42, 100, "Refresh", "refreshPrimary"),
            FakePACSStudyList(42, 100, {Name: "CT HEAD WITHOUT CONTRAST 12345678"})
        )
        PACSMonitor.driver := driver

        PACSMonitor.RefreshAndCheck()

        Assert.Equal(1, leases.Length)
        Assert.Equal("PACS worklist refresh", leases[1])
        Assert.Equal(1, driver.rootCalls)
        Assert.Equal(0, PACSMonitor.knownAccessions.Count)
    }

    TestScanFailuresNotifyOnceAndReset() {
        capturedLog := LogCapture()
        try {
            loop PACSMonitor.scanFailureThreshold + 2
                PACSMonitor.RecordScanFailure("study list unavailable")
        } finally {
            logged := capturedLog.Count("PACS background monitoring failed: ")
            capturedLog.Restore()
        }
        ; One log entry per failure episode, with the notice, not one per poll.
        Assert.Equal(1, logged)

        Assert.Equal(1, this.notifications.Length)
        Assert.True(InStr(this.notifications[1].text, "study list unavailable") > 0)
        Assert.Equal("PACS Background Monitoring Failed", this.notifications[1].title)
        Assert.Equal("study list unavailable", PACSMonitor.lastError)

        PACSMonitor.RecordScanSuccess()
        Assert.Equal(0, PACSMonitor.consecutiveScanFailures)
        Assert.False(PACSMonitor.scanFailureNotified)
    }

    TestNewStudyNotificationUsesTextThenTitle() {
        SetTestSetting("MessageBoxNewCase", true)
        SetTestSetting("AudioAlertNewCase", false)

        PACSMonitor.AlertNewCases([{studyType: "CT HEAD", accession: "12345678"}])

        Assert.Equal(1, this.notifications.Length)
        Assert.Equal("CT HEAD", this.notifications[1].text)
        Assert.Equal("New Study Available", this.notifications[1].title)
    }

    TestFailedAlertDoesNotConsumeAccession() {
        SetTestSetting("MessageBoxNewCase", true)
        SetTestSetting("AudioAlertNewCase", false)
        PACSMonitor.notifier := FailPACSNotification

        Assert.Throws(
            () => PACSMonitor.ProcessRows([{name: "CT HEAD WITHOUT CONTRAST 12345678"}]),
            "notifications could not be delivered"
        )
        Assert.False(PACSMonitor.HasAccession("12345678"))
    }

    Teardown() {
        PACSMonitor.StopMonitoring()
        PACSMonitor.knownAccessions := Map()
        PACSMonitor.driver := this.originalDriver
        PACSMonitor.timerDriver := this.originalTimerDriver
        PACSMonitor.notifier := this.originalNotifier
        PACSMonitor.approvedRefreshAutomationIds := this.originalApprovedRefreshIds
        PACSMonitor.automationAcquire := this.originalAutomationAcquire
        PACSMonitor.automationRelease := this.originalAutomationRelease
        PACSMonitor.consecutiveRefreshFailures := 0
        PACSMonitor.refreshFailureNotified := false
        PACSMonitor.consecutiveScanFailures := 0
        PACSMonitor.scanFailureNotified := false
        PACSMonitor.refreshUnavailableNoted := false
        PACSMonitor.lastError := ""
        try FileDelete(Settings.settingsFile)
        Settings.settingsFile := this.originalSettings
    }
}

class FakePACSTimerDriver {
    __New() {
        this.startCalls := 0
        this.stopCalls := 0
        this.callback := 0
        this.interval := 0
    }

    Start(callback, interval) {
        this.startCalls++
        this.callback := callback
        this.interval := interval
    }

    Stop(callback) {
        this.stopCalls++
        this.callback := callback
    }
}

class FakePACSTargetElement {
    __New(elementType, processId, name := "", automationId := "", invoke := false, windowId := 100) {
        this.Type := elementType
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

class ThrowingPACSRefreshRoot extends FakePACSTargetElement {
    __New(processId, windowId) {
        super.__New(UIA.Type.Window, processId, "", "", false, windowId)
    }

    FindElements(*) {
        throw Error("simulated UIA enumeration failure")
    }
}

class ChangingPACSRefreshRoot extends FakePACSTargetElement {
    __New(processId, windowId, firstCandidates, laterCandidates) {
        super.__New(UIA.Type.Window, processId, "", "", false, windowId)
        this.firstCandidates := firstCandidates
        this.laterCandidates := laterCandidates
        this.findCalls := 0
    }

    FindElements(*) {
        this.findCalls++
        return this.findCalls = 1
            ? this.firstCandidates.Clone()
            : this.laterCandidates.Clone()
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
        return {status: "unique", session: this.session}
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

class ActivationChangingPortalDriver extends PinnedPortalMonitorDriver {
    __New(session, button, studyList) {
        super.__New(session, button, studyList)
        this.activeChecks := 0
    }

    IsActive(*) {
        this.activeChecks++
        return this.activeChecks > 1
    }
}

class LeaseObservingPortalDriver extends PinnedPortalMonitorDriver {
    __New(session, button, studyList) {
        super.__New(session, button, studyList)
        this.waitLeaseStatus := ""
    }

    WaitForRefresh() {
        lease := PACSCommands.AcquireClinicalAutomation("interrupting clinical command")
        this.waitLeaseStatus := lease.status
        if (lease.status = "acquired")
            PACSCommands.ReleaseClinicalAutomation()
    }
}

class FixedPortalSessionDriver {
    __New(session) {
        this.session := session
    }

    SessionIsLive(session) {
        return session.hwnd = this.session.hwnd
            && session.processId = this.session.processId
    }
}

class AmbiguousPortalMonitorDriver {
    ResolvePortalSession() {
        return {status: "ambiguous", session: 0}
    }
}

class CountingPortalResolutionDriver {
    __New() {
        this.resolveCalls := 0
    }

    ResolvePortalSession() {
        this.resolveCalls++
        return {status: "absent", session: 0}
    }
}

FailPACSNotification(*) {
    throw Error("simulated notification failure")
}
