#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk
#Include AppControl.ahk

class NativePACSMonitorDriver {
    ResolvePortalSession() {
        try sessions := AppControl.ResolveExactWindows(
            AppControl.ExplorerPortalWindowSpec()
        )
        catch as err
            return {status: "error", session: 0, error: err.Message}
        if !sessions.Length
            return {status: "absent", session: 0}
        if sessions.Length > 1
            return {status: "ambiguous", session: 0}
        return {status: "unique", session: sessions[1]}
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

class PACSMonitor {
    ; Accessions already alerted on, held as a set. This was an Array scanned
    ; linearly on every accession of every row, over a list that only ever grows.
    ; Measured, 400 lookups (10 refresh passes over 40 rows): 0 ms at 50 known,
    ; 15 ms at 250, 62 ms at 1000, 188 ms at 3000 - against 0 ms for Map.Has at
    ; every size.
    static knownAccessions := Map()
    static refreshTimer := 0

    static testMode := false          ; When true, avoid UI automation and use test data
    static testStudyRows := []        ; Rows to process in test mode
    static testRefreshCalls := 0      ; Counter for RefreshAndCheck invocations in test mode
    static testLastNewStudies := []   ; Captured new studies in test mode

    static driver := NativePACSMonitorDriver()

    ; The list has no recorded stable semantic identity, so its exact positional
    ; path is retained behind same-window/type validation. Refresh controls do have
    ; semantic labels and are required to be unique instead of using a path fallback.
    static studyListPath := "Y/YYY/YqYYYVRxrTR"

    ; Refresh failures used to be swallowed entirely: the portal kept being scraped,
    ; so new studies still alerted, while nothing was actually being refreshed and
    ; nothing said so. Count them and speak up once instead.
    static consecutiveRefreshFailures := 0
    static refreshFailureThreshold := 3
    static refreshFailureNotified := false
    static consecutiveScanFailures := 0
    static scanFailureThreshold := 3
    static scanFailureNotified := false
    static lastError := ""
    static notifier := (text, title, options) => TrayTip(text, title, options)

    static Start() {
        ; Clear known accessions
        this.knownAccessions := Map()

        ; Start monitoring if enabled
        if Settings.Get("AutoRefreshPACS") {
            this.StartMonitoring()
        }
    }

    static StartMonitoring() {
        ; Clear any existing timer
        if this.refreshTimer {
            if (this.refreshTimer != -1) {
                SetTimer(this.refreshTimer, 0)
            }
            this.refreshTimer := 0
        }

        ; Set up new timer if auto-refresh is enabled
        if Settings.Get("AutoRefreshPACS") {
            ; In tests, skip real timers and just run once
            if (this.testMode) {
                this.refreshTimer := -1  ; Sentinel to show monitoring is active in tests
                this.RefreshAndCheck()
            } else {
                interval := Settings.Get("RefreshInterval") * 1000  ; Convert to milliseconds
                this.refreshTimer := ObjBindMethod(this, "RefreshAndCheck")
                SetTimer(this.refreshTimer, interval)

                ; Do an initial refresh
                this.RefreshAndCheck()
            }
        }
    }

    static StopMonitoring() {
        if this.refreshTimer {
            if (this.refreshTimer != -1) {
                SetTimer(this.refreshTimer, 0)
            }
            this.refreshTimer := 0
        }
        if (this.testMode) {
            this.testStudyRows := []
            this.testLastNewStudies := []
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
     * Locates the portal's refresh button.
     * Every semantic match is enumerated and deduplicated. Ambiguity is a failure:
     * clicking the first of multiple refresh-labelled controls can refresh an
     * unrelated portal panel while the worklist remains stale.
     * @returns the button element, or 0 if it cannot be found
     */
    static FindRefreshButton(root) {
        matches := []
        conditions := [
            {Type: "Button", Name: "Refresh", mm: "SubString", cs: false},
            {Type: "Button", AutomationId: "refresh", mm: "SubString", cs: false}
        ]
        for condition in conditions {
            try {
                for candidate in root.FindElements(condition) {
                    if (this.IsExpectedRefreshButton(root, candidate)
                        && !this.ContainsSameElement(matches, candidate))
                        matches.Push(candidate)
                }
            }
        }
        return matches.Length = 1 ? matches[1] : 0
    }

    static ContainsSameElement(elements, candidate) {
        for existing in elements {
            if (ObjPtr(existing) = ObjPtr(candidate))
                return true
            try {
                if UIA.CompareElementsEx(existing, candidate)
                    return true
            }
        }
        return false
    }

    /**
     * A positional path is only a locator hint, never proof of target identity.
     * Require a refresh-labelled, actionable button in the same process before a
     * caller is allowed to click it.
     */
    static IsExpectedRefreshButton(root, candidate) {
        if !this.IsSameWindowContext(root, candidate)
            return false

        try {
            if (candidate.Type != UIA.Type.Button)
                return false
            label := candidate.Name " " candidate.AutomationId
            if !InStr(StrLower(label), "refresh")
                return false
            return candidate.IsInvokePatternAvailable
                || candidate.IsLegacyIAccessiblePatternAvailable
        } catch {
            return false
        }
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
            type := candidate.Type
            return type = UIA.Type.Table
                || type = UIA.Type.DataGrid
                || type = UIA.Type.List
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

        button := this.FindRefreshButton(root)
        if !button
            return false

        ; Click() with no arguments uses only UIA semantic patterns; it does not move
        ; focus or the mouse. A coordinate/control fallback is deliberately omitted
        ; so the background timer cannot steal focus from the user's current app.
        try {
            if (!this.driver.SessionIsLive(session)
                || !this.IsExpectedRefreshButton(root, button))
                return false
            return !!button.Click()
        }
        return false
    }

    static RecordRefreshResult(succeeded) {
        if succeeded {
            this.consecutiveRefreshFailures := 0
            this.refreshFailureNotified := false
            return
        }

        this.consecutiveRefreshFailures++
        if (this.consecutiveRefreshFailures >= this.refreshFailureThreshold && !this.refreshFailureNotified) {
            this.refreshFailureNotified := true
            this.Notify(
                "The refresh button could not be found in Explorer Portal. New study alerts still work, but the list is not being refreshed.",
                "PACS auto-refresh is not working",
                "Icon!"
            )
        }
    }

    static Notify(text, title, options := "") {
        try {
            this.notifier.Call(text, title, options)
            return true
        }
        catch as err {
            OutputDebug("PACS notification failed: " err.Message)
            return false
        }
    }

    static RecordScanFailure(error) {
        message := IsObject(error) && HasProp(error, "Message") ? error.Message : String(error)
        this.lastError := message
        this.consecutiveScanFailures++
        OutputDebug("PACS background monitoring failed: " message)

        if (this.consecutiveScanFailures >= this.scanFailureThreshold && !this.scanFailureNotified) {
            this.scanFailureNotified := true
            this.Notify(
                "Explorer Portal could not be read after " this.consecutiveScanFailures " attempts. Last error: " message,
                "PACS background monitoring failed",
                "Icon!"
            )
        }
    }

    static RecordScanSuccess() {
        this.consecutiveScanFailures := 0
        this.scanFailureNotified := false
        this.lastError := ""
    }

    static RefreshAndCheck() {
        if (this.testMode) {
            this.testRefreshCalls++
            return this.ProcessRows(this.testStudyRows, true)
        }

        try {
            ; Resolve one exact portal session once. Every later root/action/read is
            ; pinned to its HWND/PID instead of resolving the title again.
            resolution := this.driver.ResolvePortalSession()
            if (!IsObject(resolution) || !HasProp(resolution, "status")) {
                this.RecordScanFailure("portal window resolution returned an invalid result")
                return
            }
            if (resolution.status == "absent")
                return
            if (resolution.status == "ambiguous") {
                this.RecordScanFailure("multiple exact Explorer Portal windows are open")
                return
            }
            if (resolution.status == "error") {
                detail := HasProp(resolution, "error") ? resolution.error : "unknown lookup error"
                this.RecordScanFailure("Explorer Portal lookup failed: " detail)
                return
            }
            if (!(resolution.status == "unique")
                || !HasProp(resolution, "session")
                || !resolution.session) {
                this.RecordScanFailure("portal window resolution returned an invalid unique result")
                return
            }
            session := resolution.session

            ; Skip refresh if Explorer Portal is the active window
            if this.driver.IsActive(session)
                return

            root := this.driver.RootForSession(session)
            if !this.IsExpectedPortalRoot(session, root) {
                this.RecordScanFailure("portal root identity changed before refresh")
                return
            }
            refreshed := this.ClickRefresh(root, session)

            this.RecordRefreshResult(refreshed)

            ; Wait a moment for the refresh to complete
            this.driver.WaitForRefresh()

            if !this.driver.SessionIsLive(session) {
                this.RecordScanFailure("portal window changed during refresh")
                return
            }

            ; Reacquire the UIA root from the same exact HWND after the portal has
            ; refreshed; a cached root may be stale after Edge rerenders the page.
            root := this.driver.RootForSession(session)
            if !this.IsExpectedPortalRoot(session, root) {
                this.RecordScanFailure("portal root identity changed before scan")
                return
            }
            studyList := this.FindStudyList(root)
            if !studyList {
                this.RecordScanFailure("study list was not found")
                return
            }

            this.ProcessRows(studyList)
            this.RecordScanSuccess()

        } catch as err {
            this.RecordScanFailure(err)
        }
    }

    static HasAccession(accession) {
        return this.knownAccessions.Has(accession)
    }

    static MarkAccessionSeen(accession) {
        this.knownAccessions[accession] := true
    }

    static ProcessRows(rows, isTest := false) {
        newStudies := []
        pendingAccessions := Map()

        for row in rows {
            rowText := row.Name
            ; Find any accession numbers
            accessions := []
            pos := 1
            while (pos := RegExMatch(rowText, "\d{8}", &accMatch, pos)) {
                accessions.Push(accMatch[0])
                pos += StrLen(accMatch[0])
            }

            ; Start at a complete 2+-letter modality token. Without the word
            ; boundary, the engine could start on the second character of MRI/CTA
            ; and label alerts as "RI ..." or "TA ...".
            if RegExMatch(rowText, "\b[A-Z]{2,}\s[A-Z\s]+?(?=\s+\d|$)", &studyMatch) {
                studyType := Trim(studyMatch[0])

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
        if newStudies.Length > 0 {
            if (isTest || this.testMode) {
                this.testLastNewStudies := newStudies
            } else {
                this.AlertNewCases(newStudies)
            }
        }

        ; Commit only after the complete traversal and alert path succeed. Retrying a
        ; failed pass may duplicate a notification; committing early can lose it
        ; forever, which is the unsafe direction for a clinical worklist alert.
        for accession, _ in pendingAccessions
            this.MarkAccessionSeen(accession)

        return newStudies
    }

    static AlertNewCases(newStudies) {
        if (this.testMode) {
            this.testLastNewStudies := newStudies
            return
        }
        if Settings.Get("AudioAlertNewCase") {
            Settings.PlayAlertSound(Settings.Get("AlertSound"))
        }

        deliveryFailed := false
        if Settings.Get("MessageBoxNewCase") {
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
    }
}
