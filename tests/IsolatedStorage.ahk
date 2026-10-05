#Requires AutoHotkey v2.0
#Include ../AppStorage.ahk

/**
 * Points application storage at a new private folder under A_Temp for the rest of
 * the run and removes the folder on exit, so a harness never reads or writes the
 * settings and profiles beside the scripts.
 *
 * Call it before execution reaches the Settings or ProfileManager class definitions:
 * both fix their file paths when the class initializes, which happens as execution
 * passes each definition.
 *
 * Args:
 *   prefix: Folder-name prefix that identifies the harness.
 *
 * Returns:
 *   The folder path, "<A_Temp>\<prefix>-<pid>-<tick>".
 */
UseIsolatedDataRoot(prefix) {
    root := A_Temp "\" prefix "-" DllCall("GetCurrentProcessId") "-" DllCall("GetTickCount64", "UInt64")
    DirCreate(root)
    ; The legacy root matches the data root, so AppStorage.Ensure has nothing to
    ; migrate from the script folder.
    AppStorage.dataRootOverride := root
    AppStorage.legacyRootOverride := root
    OnExit(RemoveIsolatedDataRoot)
    return root

    RemoveIsolatedDataRoot(*) {
        try DirDelete(root, true)
        return 0
    }
}
