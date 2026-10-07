; = CONTENTS
;   + Preamble
;   + StatusPanel class (Tools > Status: whether PACS Assistant's parts are
;       working, refreshed while open)

#Requires AutoHotkey v2.0

#Include AppControl.ahk
#Include PACSMonitor.ahk
#Include MicrophoneManager.ahk
#Include Settings.ahk
#Include UpdateChecker.ahk
#Include UITheme.ahk

/**
 * Answers "is it working?" in one place. It only reads state the services keep
 * and the windows that are open; it never clicks, reads a report or changes
 * anything. Each row is {label, value, tone}, tone being "ok", "warn" or "off".
 */
class StatusPanel {
    static refreshMs := 2000

    ; Rows for the window. keybindText is the main window's keybind state.
    static Rows(keybindText) {
        return [
            this.KeybindState(keybindText),
            this.WindowRow("PowerScribe", AppControl.PowerScribeWindowSpec()),
            this.PacsRow(),
            this.WindowRow("Explorer Portal", AppControl.ExplorerPortalWindowSpec()),
            this.ScanState(
                Settings.Get("AutoRefreshPACS"),
                PACSMonitor.NewCaseAlertsEnabled(),
                Settings.Get("RefreshInterval"),
                PACSMonitor.lastScanTime,
                PACSMonitor.consecutiveScanFailures,
                PACSMonitor.lastError
            ),
            this.MicrophoneState(
                Settings.Get("SwapMicrophoneOnLogin"),
                Trim(Settings.Get("MicrophoneName")),
                MicrophoneManager.lastSelection,
                MicrophoneManager.lastError
            ),
            this.UpdateState(
                UpdateChecker.updateCheckEligibleProbe.Call(),
                Settings.Get("AutoUpdate"),
                UpdateChecker.pendingUpdateInfo,
                UpdateChecker.lastCheckTime,
                UpdateChecker.lastCheckError
            )
        ]
    }

    ; keybindText as the main window's status line words it (KeybindStatusText).
    static KeybindState(keybindText) {
        tone := InStr(keybindText, " of ") || InStr(keybindText, "suspended") ? "warn"
            : InStr(keybindText, "No keybinds") ? "off" : "ok"
        return {label: "Keybinds", value: keybindText, tone: tone}
    }

    static WindowRow(label, spec) {
        try count := AppControl.ResolveExactWindows(spec).Length
        catch
            return {label: label, value: "Could not be checked", tone: "warn"}
        return this.WindowState(label, count)
    }

    ; Vue PACS as PACS keybinds see it: one window across the Vue PACS shell and
    ; its Vue PACS Client viewer (HotkeyManager.PACSIsActive).
    static PacsRow() {
        try {
            shellCount := AppControl.ResolveExactWindows(AppControl.VuePacsWindowSpec()).Length
            clientCount := AppControl.ResolveExactWindows(AppControl.VuePacsClientWindowSpec()).Length
        } catch
            return {label: "Vue PACS", value: "Could not be checked", tone: "warn"}
        return this.PacsState(shellCount, clientCount)
    }

    ; PACS-scoped keybinds need exactly one of the two windows; Next and Previous
    ; Series send to the viewer.
    static PacsState(shellCount, clientCount) {
        row := {label: "Vue PACS"}
        total := shellCount + clientCount
        if (total = 0)
            return (row.value := "Not open", row.tone := "off", row)
        if (total > 1)
            return (row.value := total " windows open (Vue PACS and its viewer count together); PACS keybinds need exactly one", row.tone := "warn", row)
        if clientCount
            return (row.value := "Open: the Vue PACS Client viewer", row.tone := "ok", row)
        return (row.value := "Open, but not the Vue PACS Client viewer that Next and Previous Series use", row.tone := "warn", row)
    }

    static WindowState(label, count) {
        if (count = 0)
            return {label: label, value: "Not open", tone: "off"}
        if (count = 1)
            return {label: label, value: "Open", tone: "ok"}
        return {label: label, value: count " windows open; its commands need exactly one", tone: "warn"}
    }

    static ScanState(enabled, alertsOn, intervalSeconds, lastScanTime, failures, lastError) {
        row := {label: "New-study scanning"}
        if !enabled
            return (row.value := "Off", row.tone := "off", row)
        if !alertsOn
            return (row.value := "On, but it waits for a sound or notification to be turned on", row.tone := "warn", row)
        value := "Every " intervalSeconds " seconds; "
            . (lastScanTime = "" ? "no scan yet" : "last read at " FormatTime(lastScanTime, "h:mm:ss tt"))
        if (failures > 0)
            return (row.value := value ". The last attempt failed: " lastError, row.tone := "warn", row)
        return (row.value := value, row.tone := "ok", row)
    }

    static MicrophoneState(enabled, name, lastSelection, lastError) {
        row := {label: "Microphone"}
        if (!enabled || name = "")
            return (row.value := "Not set at login", row.tone := "off", row)
        if (lastError != "")
            return (row.value := "'" name "' was not selected: " lastError, row.tone := "warn", row)
        if IsObject(lastSelection)
            return (row.value := "'" lastSelection.name "' selected at " FormatTime(lastSelection.time, "h:mm tt"), row.tone := "ok", row)
        return (row.value := "'" name "' is selected at the next PowerScribe login", row.tone := "ok", row)
    }

    ; "Up to date" only once a check has succeeded: the first automatic check is
    ; still running at startup, and an offline workstation never completes one.
    static UpdateState(eligible, autoUpdate, pendingUpdateInfo, lastCheckTime := "", lastCheckError := "") {
        row := {label: "Updates"}
        if !eligible
            return (row.value := "Not checked by this build (development build)", row.tone := "off", row)
        if (IsObject(pendingUpdateInfo) && HasProp(pendingUpdateInfo, "hasUpdate") && pendingUpdateInfo.hasUpdate)
            return (row.value := pendingUpdateInfo.latestVersion " is available: Help > Check for Updates", row.tone := "warn", row)
        if (lastCheckError != "")
            return (row.value := "The last check failed: " lastCheckError, row.tone := "warn", row)
        schedule := autoUpdate ? "checked automatically" : "automatic checks are off"
        if (lastCheckTime != "")
            return (row.value := "Up to date as of " this.When(lastCheckTime) "; " schedule, row.tone := autoUpdate ? "ok" : "off", row)
        return (row.value := autoUpdate ? "Checked automatically; no check has finished yet" : "Automatic checks are off", row.tone := "off", row)
    }

    ; A timestamp as a time today, or with its date on another day.
    static When(timestamp) => FormatTime(timestamp, SubStr(timestamp, 1, 8) = SubStr(A_Now, 1, 8) ? "h:mm tt" : "MMM d, h:mm tt")

    static ToneColor(tone) => tone = "ok" ? UITheme.okColor : tone = "warn" ? UITheme.warningColor : UITheme.secondaryColor

    /**
     * Shows the window, refreshed every refreshMs while it is open. keybindText is
     * a function returning the main window's keybind state.
     */
    static Show(keybindText, ownerGui := 0) {
        window := UITheme.NewWindow("PACS Assistant - Status", IsObject(ownerGui) ? "+Owner" ownerGui.Hwnd : "")
        width := 560
        labelWidth := 150
        UITheme.AddHeading(window, "Status", "xm ym w" width)
        UITheme.AddNote(window, "What PACS Assistant can see right now. This window updates every two seconds.", "xm y+4 w" width)
        values := []
        for index, row in this.Rows(keybindText.Call()) {
            UITheme.AddSectionLabel(window, row.label, "xm y+" (index = 1 ? 16 : 8) " w" labelWidth)
            ; Two lines tall, so a longer value later still fits.
            value := window.Add("Text", "x+" UITheme.gap " yp w" (width - labelWidth - UITheme.gap) " r2", "")
            ; Colored by its state (Fill), not by the theme.
            value.themed := true
            values.Push(value)
        }
        ; The timer stops itself once the window is gone, however it went.
        tick := (*) => this.Fill(window, values, keybindText) ? 0 : SetTimer(tick, 0)
        close := (*) => (SetTimer(tick, 0), window.Destroy())
        footer := UITheme.AddFooter(window, width, [{text: "Close", default: true, action: close}])
        window.OnEvent("Close", close)
        window.OnEvent("Escape", close)
        this.Fill(window, values, keybindText)
        UITheme.ShowDialog(window)
        footer["Close"].Focus()
        SetTimer(tick, this.refreshMs)
        return window
    }

    ; Writes the current state into the value controls.
    ; @returns false once the window is gone
    static Fill(window, values, keybindText) {
        try {
            if !DllCall("IsWindow", "Ptr", window.Hwnd)
                return false
            for index, row in this.Rows(keybindText.Call()) {
                control := values[index]
                control.SetFont("c" this.ToneColor(row.tone))
                if !(control.Value == row.value)
                    control.Value := row.value
            }
            return true
        } catch
            return false
    }
}
