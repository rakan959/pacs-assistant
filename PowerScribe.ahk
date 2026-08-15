#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk
#Include AppControl.ahk
#Include UIAValue.ahk

/**
 * The PowerScribe report itself: locating it, reading it, and routing it to an
 * attending. Split out of PACSCommands, which had become the command registry plus
 * every workflow's implementation in one file.
 */
class PowerScribe {
    static windowTitle := "PowerScribe 360 | Reporting ahk_exe Nuance.PowerScribe360.exe"

    ; Positional path to the report text. Brittle - kept only as a last resort behind
    ; a property-based lookup.
    static reportPath := "YYYYV"

    ; Whether a piece of text reads like a report body rather than some other field
    static LooksLikeReport(text) {
        return RegExMatch(text, "i)EXAMINATION:") > 0
    }

    /**
     * Chooses only report-shaped text. Returning an unrelated UI value is worse than
     * returning nothing because it silently falls through to the MSK routing rule.
     */
    static SelectReportText(candidates, fallbackText := "") {
        for text in candidates {
            if this.LooksLikeReport(text)
                return text
        }
        return this.LooksLikeReport(fallbackText) ? fallbackText : ""
    }

    static SendKeys(keys) {
        return AppControl.SendKeysToWindow(this.windowTitle, keys)
    }

    static SetAttending(attending) {
        if !AppControl.ActivateWindow(this.windowTitle)
            return false

        driver := AppControl.windowDriver
        try {
            if !AppControl.SendKeysToActiveWindow(this.windowTitle, "{Alt down}ta{Alt up}")
                return false
            driver.Pause(100)
            ; Attending names are data, not AutoHotkey Send syntax. SendText keeps
            ; characters such as +, ^ and braces literal.
            if !AppControl.SendTextToActiveWindow(this.windowTitle, attending)
                return false
            driver.Pause(100)
            return AppControl.SendKeysToActiveWindow(
                this.windowTitle,
                "{tab}{space}{tab}{Enter}"
            )
        } catch {
            return false
        }
    }
}

/**
 * Maps a report's EXAMINATION line onto a reading section.
 * The rules are evaluated in order and the first match wins, so narrower rules
 * (Peds ultrasound) must stay ahead of the broader ones (any ultrasound).
 */
class ReportModality {
    static rules := [
        {name: "Body",       pattern: "i)EXAMINATION:[\s]*((CT.*pelvis)|(XR.*abdomen)|(MRCP)|(MRI.*abdomen))"},
        {name: "Chest",      pattern: "i)EXAMINATION:[\s]*((CT.*chest)|(XR.*chest))"},
        {name: "Neuro",      pattern: "i)EXAMINATION:[\s]*((CT.*((facial)|(spine)|(head)|(escape)|(neck)))|(MRI.*((brain)|(spine)|(orbits)))|(MRA))"},
        {name: "Nucs",       pattern: "i)EXAMINATION:[\s]*NM"},
        {name: "Peds",       pattern: "i)EXAMINATION:[\s]*((US.*((right lower quadrant)|(neurosonography))))"},
        {name: "Ultrasound", pattern: "i)EXAMINATION:[\s]*US"}
    ]

    ; Used when nothing else matches
    static fallback := "MSK"

    ; Every modality that can be assigned an attending, in display order
    static names := ["Body", "Chest", "Neuro", "Nucs", "Peds", "Ultrasound", "MSK"]

    static Classify(reportText) {
        for rule in this.rules {
            if RegExMatch(reportText, rule.pattern)
                return rule.name
        }
        return this.fallback
    }
}

sendPs(x) {
    return PowerScribe.SendKeys(x)
}

/**
 * Pure attending-routing policy. Profile lookup and PowerScribe mutation are passed
 * in by the workflow layer so classification and failure behavior remain testable
 * without global profile state or a live clinical application.
 */
class AttendingRouting {
    static Route(reportText, attendingLookup, attendingWriter) {
        modality := ReportModality.Classify(reportText)
        attending := attendingLookup.Call(modality)

        if (attending != "" && !attendingWriter.Call(attending))
            throw Error("Attending could not be assigned because PACS Assistant could not safely control PowerScribe")

        return modality
    }
}

/**
 * Reads the text of the report currently open in PowerScribe.
 *
 * The report control used to be addressed by a fixed positional path. When
 * PowerScribe's element tree shifted, that path stopped resolving and threw, taking
 * the whole wet read down with it - the sticky note never got pasted either
 * (issue #28). Candidates are matched on their control type instead, and the one
 * whose text actually reads like a report wins; the positional path is only a last
 * resort.
 *
 * @returns the report text, or "" if it could not be read
 */
readReportText() {
    try {
        root := UIA.ElementFromHandle(PowerScribe.windowTitle)
    } catch {
        return ""
    }

    ; The report editor presents as a Document, but has been seen as a plain Edit.
    candidates := []
    for condition in [{Type: "Document"}, {Type: "Edit"}] {
        elements := ""
        try {
            elements := root.FindElements(condition)
        } catch {
            continue
        }

        for el in elements {
            text := ""
            try text := UIAValue.Read(el)
            if (text = "")
                continue
            candidates.Push(text)
        }
    }

    ; Positional fallback for the case where nothing matched by type
    fallbackText := ""
    try fallbackText := UIAValue.Read(root.ElementFromPath(PowerScribe.reportPath))

    return PowerScribe.SelectReportText(candidates, fallbackText)
}
