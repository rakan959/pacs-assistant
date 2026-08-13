#Requires AutoHotkey v2.0
#Include UIA-v2/Lib/UIA.ahk

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
    WinActivate("PowerScribe")
    Send x
}

setAttending(x) {
    WinActivate("PowerScribe")
    Send "{Alt down}ta{Alt up}"
    Sleep(100)
    Send x
    Sleep(100)
    Send "{tab}{space}{tab}{Enter}"
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

    ; The report editor presents as a Document, but has been seen as a plain Edit
    best := ""
    for condition in [{Type: "Document"}, {Type: "Edit"}] {
        elements := ""
        try {
            elements := root.FindElements(condition)
        } catch {
            continue
        }

        for el in elements {
            text := ""
            try text := el.Value
            if (text = "")
                continue

            ; A real report names the study, so prefer that over any other text field
            if PowerScribe.LooksLikeReport(text)
                return text

            if (StrLen(text) > StrLen(best))
                best := text
        }
    }

    if (best != "")
        return best

    ; Positional fallback for the case where nothing matched by type
    try {
        return root.ElementFromPath(PowerScribe.reportPath).Value
    }

    return ""
}

/**
 * Assigns the report to the attending configured for its modality.
 * A modality configured with a blank attending is left alone so the report keeps
 * PowerScribe's own default attending.
 *
 * ProfileManager is resolved through main.ahk's include graph rather than included
 * here: ProfileManager pulls in PACSCommands, which pulls in this file, and the
 * resulting order would run ProfileManager's static initialiser before
 * PACSCommands.commands exists.
 *
 * @returns the modality the report was classified as
 */
checkAttending(haystack) {
    modality := ReportModality.Classify(haystack)
    attending := ProfileManager.GetModalityAttending(modality)

    if (attending != "")
        setAttending(attending)

    return modality
}
