#Requires AutoHotkey v2.0
#Include ../ErrorText.ahk

/**
 * OnError callback shared by the headless test runners (style guide s11). An
 * uncaught runtime error is written to stderr and ends the run with exit code 10,
 * because the default error dialog would wait forever on a CI runner. Code 1 stays
 * the unit suite's "tests failed" result and 2 is AutoHotkey's load-failure code.
 */
OnError_StdErr(E, mode) {
    report := "UNCAUGHT " ErrorText.Describe(E) "`n"
    if (IsObject(E) && HasProp(E, "Stack") && E.Stack != "")
        report .= E.Stack "`n"
    try FileAppend(report, "**", "UTF-8")
    ExitApp(10)
}
