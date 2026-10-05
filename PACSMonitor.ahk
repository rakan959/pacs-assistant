; = CONTENTS
;   + Preamble
;   + NativePACSMonitorDriver / NativePACSMonitorTimerDriver (portal UIA & timer primitives)
;   + PACSMonitor class (background study-list refresh, new-study detection & alerts)

#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include AppControl.ahk
#Include UIAElementIdentity.ahk
#Include ErrorText.ahk
#Include AppLog.ahk

class NativePACSMonitorDriver {
    ResolvePortalSession() {
        return AppControl.ResolveUniqueExactWindowStatus(AppControl.ExplorerPortalWindowSpec())
    }

    SessionIsLive(session) {
        return AppControl.ExactSessionIsUniqueAndLive(session)
    }

    IsActive(session) {
        try return WinActive(session.target) != 0
        return false
    }

    RootForSession(session) {
        return UIA.ElementFromHandle(session.target)
    }

    WaitForRefresh() {
        Sleep(1000)
    }
}

class NativePACSMonitorTimerDriver {
    Start(callback, interval) {
        SetTimer(callback, interval)
    }

    Stop(callback) {
        SetTimer(callback, 0)
    }
}

class PACSMonitor {
    ; Only these leading modality tokens may enter a desktop notification. Parsing
    ; arbitrary uppercase row text risks treating a patient-name column as the study.
    static studyModalityPattern := "\b(?:CTA|MRA|MRI|PET|CT|MR|XR|US|NM|DX|MG|FL)\b"
    ; No stable live Explorer Portal refresh AutomationId has been captured yet.
    ; Keep the click path closed instead of accepting any label containing "refresh".
    static approvedRefreshAutomationIds := []
    ; Accessions already alerted on, held as a set: every accession of every row is
    ; looked up in a list that only grows. Measured, 400 lookups (10 refresh passes
    ; over 40 rows) in a linear Array take 0 ms at 50 known, 15 ms at 250, 62 ms at
    ; 1000 and 188 ms at 3000, against 0 ms for Map.Has at every size.
    static knownAccessions := Map()
    static refreshTimer := 0

    static driver := NativePACSMonitorDriver()
    static timerDriver := NativePACSMonitorTimerDriver()
    static automationAcquire := (*) => {status: "acquired", busyCommand: ""}
    static automationRelease := (*) => 0

    ; The list has no recorded stable semantic identity, so its exact positional
    ; path is retained behind same-window/type validation. Refresh controls require
    ; a live-approved exact AutomationId and uniqueness; none is approved by default.
    static studyListPath := "Y/YYY/YqYYYVRxrTR"

    ; The portal is scanned whether or not refresh works, so new studies can still
    ; alert while nothing refreshes. Count refresh failures and speak up once.
    static consecutiveRefreshFailures := 0
    static refreshFailureThreshold := 3
    static refreshFailureNotified := false
    ; With no approved refresh control, refresh is unavailable rather than failing;
    ; that is said once per run.
    static refreshUnavailableNoted := false
    static consecutiveScanFailures := 0
    static scanFailureThreshold := 3
    static scanFailureNotified := false
    static lastError := ""
    static notifier := (text, title, options) => TrayTip(text, title, options)

    static Start() {
        this.knownAccessions := Map()
        this.StartMonitoring()
    }

    ; Restarts the refresh timer from the current settings, with an immediate
    ; first refresh; without auto-refresh it only stops the timer.
    static StartMonitoring() {
        this.StopMonitoring()
        if !Settings.Get("AutoRefreshPACS")
            return

        interval := Settings.Get("RefreshInterval") * 1000  ; Convert to milliseconds
        this.refreshTimer := ObjBindMethod(this, "RefreshAndCheck")
        this.timerDriver.Start(this.refreshTimer, interval)
        this.RefreshAndCheck()
    }

    static StopMonitoring() {
        if this.refreshTimer {
            this.timerDriver.Stop(this.refreshTimer)
            this.refreshTimer := 0
        }
    }

    static OnSettingsChanged() {
        ; Reset failure state so a fixed setup is not still complaining
        this.consecutiveRefreshFailures := 0
        this.refreshFailureNotified := false
        this.RecordScanSuccess()

        ; Restart monitoring with new settings
        this.StartMonitoring()
    }

    /**
     * Resolves the portal's refresh button with explicit absence, ambiguity, and
     * provider-error states. All buttons are enumerated in one query so a failed
     * secondary lookup cannot make an incomplete result appear unique.
     */
    static ResolveRefreshButton(root) {
        ; With nothing approved no button can match. Skipping the enumeration keeps a
        ; full-tree UIA search from holding the clinical lease every refresh cycle.
        if (this.approvedRefreshAutomationIds.Length = 0)
            return {status: "absent", button: 0, error: ""}
        matches := []
        try {
            elements := root.FindElements({Type: "Button"})
            if !IsObject(elements)
                throw Error("Refresh-button enumeration returned no collection")

            for candidate in elements {
                if (this.InspectRefreshButton(root, candidate)
                    && !UIAElementIdentity.Contains(matches, candidate))
                    matches.Push(candidate)
            }
        } catch as err {
            return {status: "error", button: 0, error: err.Message}
        }

        if (matches.Length = 0)
            return {status: "absent", button: 0, error: ""}
        if (matches.Length > 1)
            return {status: "ambiguous", button: 0, error: ""}
        return {status: "found", button: matches[1], error: ""}
    }

    static InspectRefreshButton(root, candidate) {
        if !root || !candidate
            throw Error("Refresh-button identity is unavailable")

        rootProcess := root.ProcessId
        rootWindow := root.WinId
        if (rootProcess <= 0 || rootWindow <= 0)
            throw Error("Portal root identity is unavailable")
        if (candidate.ProcessId != rootProcess || candidate.WinId != rootWindow)
            return false
        if (candidate.Type != UIA.Type.Button)
            return false

        automationId := candidate.AutomationId
        approved := false
        for expectedId in this.approvedRefreshAutomationIds {
            if (automationId == expectedId) {
                approved := true
                break
            }
        }
        if !approved
            return false
        return candidate.IsInvokePatternAvailable
            || candidate.IsLegacyIAccessiblePatternAvailable
    }

    /**
     * Locates the study list through its recorded portal path. The portal exposes no
     * stable Name/AutomationId for this control, so a generic first Table/DataGrid/
     * List fallback could silently bind to an unrelated same-window collection.
     * @returns the list element, or 0 if the exact path cannot be verified
     */
    static FindStudyList(root) {
        try {
            candidate := root.ElementFromPath(this.studyListPath)
            if this.IsExpectedStudyList(root, candidate)
                return candidate
        }

        return 0
    }

    static IsExpectedStudyList(root, candidate) {
        if !this.IsSameWindowContext(root, candidate)
            return false

        try {
            controlType := candidate.Type
            return controlType = UIA.Type.Table
                || controlType = UIA.Type.DataGrid
                || controlType = UIA.Type.List
        } catch {
            return false
        }
    }

    static IsSameWindowContext(root, candidate) {
        if !root || !candidate
            return false

        try {
            rootProcess := root.ProcessId
            rootWindow := root.WinId
            return rootProcess > 0
                && candidate.ProcessId = rootProcess
                && rootWindow > 0
                && candidate.WinId = rootWindow
        } catch {
            return false
        }
    }

    static IsExpectedPortalRoot(session, root) {
        if !session || !root
            return false
        try return session.hwnd > 0
            && session.processId > 0
            && root.WinId = session.hwnd
            && root.ProcessId = session.processId
        return false
    }

    /**
     * Clicks refresh in the portal.
     * @returns true if the button was found and actioned
     */
    static ClickRefresh(root, session) {
        try {
            if (!this.driver.SessionIsLive(session)
                || !this.IsExpectedPortalRoot(session, root))
                return false
        } catch {
            return false
        }

        initial := this.ResolveRefreshButton(root)
        if (initial.status != "found")
            return false

        ; Click() with no arguments uses only UIA semantic patterns; it does not move
        ; focus or the mouse. A coordinate/control fallback is deliberately omitted
        ; so the background timer cannot steal focus from the user's current app.
        try {
            current := this.ResolveRefreshButton(root)
            if (current.status != "found"
                || !UIAElementIdentity.Same(initial.button, current.button)
                || !this.driver.SessionIsLive(session)
                || this.driver.IsActive(session))
                return false
            return !!current.button.Click()
        }
        return false
    }

    static RecordRefreshResult(succeeded) {
        if succeeded {
            if this.refreshFailureNotified
                AppLog.Write("PACS auto-refresh is working again")
            this.consecutiveRefreshFailures := 0
            this.refreshFailureNotified := false
            return
        }

        this.consecutiveRefreshFailures++
        if (this.consecutiveRefreshFailures >= this.refreshFailureThreshold && !this.refreshFailureNotified) {
            this.refreshFailureNotified := true
            ; Logged once per failure episode, with the notice.
            AppLog.Write("PACS auto-refresh is not working: " this.consecutiveRefreshFailures " consecutive refreshes failed")
            this.Notify(
                "Explorer Portal could not be refreshed safely. Monitoring may be stale; refresh and check the worklist manually.",
                "PACS Auto-Refresh Not Working",
                "Icon!"
            )
        }
    }

    static NoteRefreshUnavailable() {
        if this.refreshUnavailableNoted
            return
        this.refreshUnavailableNoted := true
        AppLog.Write("PACS auto-refresh is unavailable: no Explorer Portal refresh control is approved")
        this.Notify(
            "PACS Assistant cannot refresh Explorer Portal yet, so it checks the worklist only as Explorer Portal shows it. Refresh the worklist yourself to see new studies.",
            "PACS Auto-Refresh Unavailable",
            "Icon!"
        )
    }

    static Notify(text, title, options := "") {
        try {
            this.notifier.Call(text, title, options)
            return true
        }
        catch Any as err {
            AppLog.Write("PACS notification failed: " ErrorText.Describe(err))
            return false
        }
    }

    static RecordScanFailure(err) {
        message := ErrorText.Message(err)
        this.lastError := message
        this.consecutiveScanFailures++
        OutputDebug("PACS background monitoring failed: " message)

        if (this.consecutiveScanFailures >= this.scanFailureThreshold && !this.scanFailureNotified) {
            this.scanFailureNotified := true
            notice := "Explorer Portal could not be read after " this.consecutiveScanFailures " attempts. Last error: " message
            ; Logged once per failure episode, with the notice, rather than once per poll.
            AppLog.Write("PACS background monitoring failed: " notice)
            this.Notify(notice, "PACS Background Monitoring Failed", "Icon!")
        }
    }

    static RecordScanSuccess() {
        this.consecutiveScanFailures := 0
        this.scanFailureNotified := false
        this.lastError := ""
    }

    static RefreshAndCheck() {
        session := 0
        refreshed := false
        skipScan := false
        phaseError := 0

        refreshLease := this.automationAcquire.Call("PACS worklist refresh")
        if (!IsObject(refreshLease)
            || !HasProp(refreshLease, "status")
            || refreshLease.status != "acquired")
            return false

        try {
            ; Resolve one exact portal session once. Every later root/action/read is
            ; pinned to its HWND/PID instead of resolving the title again.
            resolution := this.driver.ResolvePortalSession()
            if (!IsObject(resolution) || !HasProp(resolution, "status"))
                throw Error("portal window resolution returned an invalid result")
            if (resolution.status == "absent")
                skipScan := true
            else if (resolution.status == "ambiguous")
                throw Error("multiple exact Explorer Portal windows are open")
            if (resolution.status == "error") {
                detail := HasProp(resolution, "error") ? resolution.error : "unknown lookup error"
                throw Error("Explorer Portal lookup failed: " detail)
            }
            if (!skipScan
                && (!(resolution.status == "unique")
                    || !HasProp(resolution, "session")
                    || !resolution.session))
                throw Error("portal window resolution returned an invalid unique result")
            if !skipScan
                session := resolution.session

            ; While the user has Explorer Portal active, skip the whole cycle: refresh,
            ; scan and alerts.
            if (!skipScan && this.driver.IsActive(session))
                skipScan := true

            if !skipScan {
                root := this.driver.RootForSession(session)
                if !this.IsExpectedPortalRoot(session, root)
                    throw Error("portal root identity changed before refresh")
                refreshed := this.ClickRefresh(root, session)
            }
        } catch as err {
            phaseError := err
        } finally this.automationRelease.Call()

        if phaseError {
            this.RecordScanFailure(phaseError)
            return false
        }
        if skipScan
            return false

        ; Notification/error reporting and the portal's render delay do not hold the
        ; global clinical automation lease. A user command can run during the wait;
        ; the scan phase must then reacquire the lease and revalidate the pinned
        ; session before touching UIA again.
        if (this.approvedRefreshAutomationIds.Length = 0)
            this.NoteRefreshUnavailable()
        else
            this.RecordRefreshResult(refreshed)
        if refreshed {
            try this.driver.WaitForRefresh()
            catch as err {
                this.RecordScanFailure(err)
                return false
            }
        }

        ; The scan only feeds the new-study alerts. With both kinds off its result
        ; would be discarded, so it does not take the clinical lease at all.
        if !this.NewCaseAlertsEnabled()
            return false

        scanLease := this.automationAcquire.Call("PACS worklist scan")
        if (!IsObject(scanLease)
            || !HasProp(scanLease, "status")
            || scanLease.status != "acquired")
            return false

        rowSnapshots := 0
        phaseError := 0
        try {
            if !this.driver.SessionIsLive(session)
                throw Error("portal window changed during refresh")

            ; Reacquire the UIA root from the same exact HWND after the portal has
            ; refreshed; a cached root may be stale after Edge rerenders the page.
            root := this.driver.RootForSession(session)
            if !this.IsExpectedPortalRoot(session, root)
                throw Error("portal root identity changed before scan")
            studyList := this.FindStudyList(root)
            if !studyList
                throw Error("study list was not found")
            rowSnapshots := this.SnapshotStudyRows(studyList)
        } catch as err {
            phaseError := err
        } finally this.automationRelease.Call()

        if phaseError {
            this.RecordScanFailure(phaseError)
            return false
        }

        try {
            this.ProcessRows(rowSnapshots)
            this.RecordScanSuccess()
            return true
        } catch as err {
            this.RecordScanFailure(err)
            return false
        }
    }

    static SnapshotStudyRows(studyList) {
        rows := []
        for row in studyList {
            rowText := row.Name
            if (Type(rowText) != "String")
                throw Error("study row text is unavailable")
            rows.Push({name: rowText})
        }
        return rows
    }

    static HasAccession(accession) {
        return this.knownAccessions.Has(accession)
    }

    static MarkAccessionSeen(accession) {
        this.knownAccessions[accession] := true
    }

    static ProcessRows(rows, alertAction := 0) {
        newStudies := []
        pendingAccessions := Map()

        for row in rows {
            rowText := row.name
            ; Find any accession numbers
            accessions := []
            firstAccessionPosition := 0
            pos := 1
            while (pos := RegExMatch(rowText, "(?<!\d)\d{8}(?!\d)", &accMatch, pos)) {
                if !firstAccessionPosition
                    firstAccessionPosition := pos
                accessions.Push(accMatch[0])
                pos += StrLen(accMatch[0])
            }

            ; A flattened row gives no accession-column identity. Multiple numeric
            ; tokens are ambiguous, and compact calendar dates are never accessions.
            if (accessions.Length = 1 && !this.LooksLikeCompactDate(accessions[1])) {
                studyType := this.ExtractStudyType(rowText, firstAccessionPosition)
                if (studyType = "")
                    continue

                for acc in accessions {
                    ; Deduplicate within this pass without mutating durable scan state.
                    ; A later stale UIA row can still throw; committing here would make
                    ; earlier accessions look alerted before AlertNewCases has run.
                    if (this.HasAccession(acc) || pendingAccessions.Has(acc))
                        continue

                    pendingAccessions[acc] := true
                    newStudies.Push({
                        studyType: studyType,
                        accession: acc
                    })
                }
            }
        }

        ; Alert if new studies found
        delivered := false
        if newStudies.Length > 0 {
            if !alertAction
                alertAction := ObjBindMethod(this, "AlertNewCases")
            delivered := alertAction.Call(newStudies) ? true : false
        }

        ; Commit only after the complete traversal and alert path succeed. Retrying a
        ; failed pass may duplicate a notification; committing early can lose it
        ; forever, which is the unsafe direction for a clinical worklist alert.
        if delivered {
            for accession, _ in pendingAccessions
                this.MarkAccessionSeen(accession)
        }

        return newStudies
    }

    static ExtractStudyType(rowText, firstAccessionPosition) {
        if (firstAccessionPosition <= 1)
            return ""
        prefix := SubStr(rowText, 1, firstAccessionPosition - 1)
        matches := []
        pos := 1
        while (pos := RegExMatch(prefix, this.studyModalityPattern, &modality, pos)) {
            matches.Push({position: pos, value: modality[0]})
            pos += StrLen(modality[0])
        }
        ; More than one modality-shaped token means the flattened multi-column row
        ; cannot be attributed safely. Missing an alert is preferable to disclosing
        ; a patient-name prefix or announcing the wrong study.
        if matches.Length != 1
            return ""

        ; The flattened row provides no verified column boundary after the modality.
        ; Notify only the approved token; later uppercase words may be patient PHI.
        return matches[1].value
    }

    static LooksLikeCompactDate(value) {
        if !RegExMatch(value, "^(19|20)\d{6}$")
            return false
        year := Integer(SubStr(value, 1, 4))
        month := Integer(SubStr(value, 5, 2))
        day := Integer(SubStr(value, 7, 2))
        if (month < 1 || month > 12 || day < 1)
            return false
        days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if (month = 2 && (Mod(year, 400) = 0 || (Mod(year, 4) = 0 && Mod(year, 100) != 0)))
            days[2] := 29
        return day <= days[month]
    }

    static NewCaseAlertsEnabled() {
        return Settings.Get("AudioAlertNewCase") || Settings.Get("MessageBoxNewCase")
    }

    static AlertNewCases(newStudies) {
        audioEnabled := Settings.Get("AudioAlertNewCase")
        notificationEnabled := Settings.Get("MessageBoxNewCase")
        if (!audioEnabled && !notificationEnabled)
            return false
        if audioEnabled {
            Settings.PlayAlertSound(Settings.Get("AlertSound"))
        }

        deliveryFailed := false
        if notificationEnabled {
            ; Create a TrayTip for each new study
            for study in newStudies {
                if !this.Notify(study.studyType, "New Study Available", "Iconi")
                    deliveryFailed := true
            }

            ; If there are multiple studies, show a summary notification
            if newStudies.Length > 1 {
                Sleep(1000)  ; Wait a bit to not overlap notifications
                if !this.Notify(
                    newStudies.Length " new studies available",
                    "Multiple New Studies",
                    "Iconi"
                )
                    deliveryFailed := true
            }
        }

        ; ProcessRows commits accessions only after this method returns. A failed
        ; delivery must therefore escape so the next scan can retry rather than
        ; permanently treating an unseen clinical alert as consumed.
        if deliveryFailed
            throw Error("One or more new-study notifications could not be delivered")
        return true
    }
}
