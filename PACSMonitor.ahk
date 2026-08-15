#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include Settings.ahk

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

    static portalTitle := "Explorer Portal ahk_exe msedge.exe"

    ; Positional UIA paths. These are brittle - they encode the portal's layout, so
    ; they break whenever it shifts - and are only used as a fallback behind a
    ; property-based lookup.
    static refreshButtonPath := "Y/YYY/YqYYYVRvrRK"
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
     * Properties are tried before the positional path so a layout change no longer
     * silently disables refreshing.
     * @returns the button element, or 0 if it cannot be found
     */
    static FindRefreshButton(root) {
        conditions := [
            {Type: "Button", Name: "Refresh", mm: "SubString", cs: false},
            {Type: "Button", AutomationId: "refresh", mm: "SubString", cs: false}
        ]
        for condition in conditions {
            try {
                return root.FindElement(condition)
            }
        }

        ; Positional fallback
        try {
            return root.ElementFromPath(this.refreshButtonPath)
        }

        return 0
    }

    /**
     * Locates the study list. The positional path is tried first here because it is
     * the one that has been working; the property lookups only cover it breaking.
     * @returns the list element, or 0 if it cannot be found
     */
    static FindStudyList(root) {
        try {
            return root.ElementFromPath(this.studyListPath)
        }

        for condition in [{Type: "Table"}, {Type: "DataGrid"}, {Type: "List"}] {
            try {
                return root.FindElement(condition)
            }
        }

        return 0
    }

    /**
     * Clicks refresh in the portal.
     * @returns true if the button was found and actioned
     */
    static ClickRefresh() {
        try {
            root := UIA.ElementFromHandle(this.portalTitle)
        } catch {
            return false
        }

        button := this.FindRefreshButton(root)
        if !button
            return false

        ; Invoke through the UIA pattern first. That works even when the portal is
        ; minimised or the button is scrolled out of view, which a positional click
        ; does not. Click() with no arguments returns the pattern it used, or 0 when
        ; the element exposes none.
        try {
            if button.Click()
                return true
        }

        ; Fall back to the positional click the previous implementation used
        try {
            button.ControlClick()
            return true
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
            ; Try to get the Explorer Portal window
            if !WinExist(this.portalTitle) {
                return  ; Portal not open, skip this check
            }

            ; Skip refresh if Explorer Portal is the active window
            if WinActive(this.portalTitle) {
                return  ; Don't refresh when user is actively using the portal
            }

            ; Store the currently active window
            previousWindow := WinExist("A")

            refreshed := this.ClickRefresh()

            ; Restore the previously active window
            if (previousWindow && WinExist("ahk_id " previousWindow)) {
                WinActivate("ahk_id " previousWindow)
            }

            this.RecordRefreshResult(refreshed)

            ; Wait a moment for the refresh to complete
            Sleep(1000)

            ; Get current accession numbers and study info
            root := UIA.ElementFromHandle(this.portalTitle)
            studyList := this.FindStudyList(root)
            if !studyList {
                this.RecordScanFailure("study list was not found")
                return
            }

            this.ProcessRows(studyList)
            this.RecordScanSuccess()

        } catch as err {
            this.RecordScanFailure(err)

            ; Still try to restore the active window if we have it
            if (IsSet(previousWindow) && previousWindow && WinExist("ahk_id " previousWindow)) {
                WinActivate("ahk_id " previousWindow)
            }
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

            ; Find study type (any uppercase string that starts with two letters)
            if RegExMatch(rowText, "[A-Z]{2}\s[A-Z\s]+?(?=\s+\d|$)", &studyMatch) {
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
