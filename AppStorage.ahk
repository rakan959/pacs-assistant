#Requires AutoHotkey v2.0

/**
 * Owns mutable application data independently of the executable location.
 * Compiled installs use the per-user roaming AppData directory; source runs remain
 * portable beside the script for contributor compatibility.
 */
class AppStorage {
    static dataRootOverride := ""
    static legacyRootOverride := ""
    static migrationMarkerName := ".migration-v1-complete"
    static copyFile := (source, destination) => FileCopy(source, destination, false)
    static copySequence := 0

    static DataRoot() {
        if (this.dataRootOverride != "")
            return this.dataRootOverride
        return A_IsCompiled ? A_AppData "\PACS Assistant" : A_ScriptDir
    }

    static LegacyRoot() {
        return this.legacyRootOverride != ""
            ? this.legacyRootOverride
            : A_ScriptDir
    }

    static Ensure() {
        root := this.DataRoot()
        legacyRoot := this.LegacyRoot()
        DirCreate(root)
        DirCreate(root "\profiles")

        if (StrCompare(root, legacyRoot, false) = 0)
            return root
        marker := root "\" this.migrationMarkerName
        if FileExist(marker)
            return root

        ; A failed copy leaves no marker, so the next startup resumes by copying only
        ; destinations that are still absent. Once marked, legacy files are never
        ; consulted again; deleting a migrated profile must not resurrect it.
        this.CopyIfMissing(legacyRoot "\settings.ini", root "\settings.ini")
        this.CopyIfMissing(legacyRoot "\config.ini", root "\config.ini")
        legacyProfiles := legacyRoot "\profiles"
        if DirExist(legacyProfiles) {
            Loop Files, legacyProfiles "\*.ini", "F"
                this.CopyIfMissing(A_LoopFileFullPath, root "\profiles\" A_LoopFileName)
        }
        this.WriteMigrationMarker(marker)
        return root
    }

    static CopyIfMissing(source, destination) {
        if !FileExist(source) || FileExist(destination)
            return false
        this.copySequence++
        temporary := destination ".migration-copy-"
            . DllCall("GetCurrentProcessId") "-"
            . DllCall("GetTickCount64", "UInt64") "-"
            . this.copySequence
        if FileExist(temporary)
            throw Error("Migration temporary path already exists")

        try {
            this.copyFile.Call(source, temporary)
            if !FileExist(temporary)
                throw Error("Migration copy did not create its temporary file")
            ; Never overwrite a destination that appeared after the initial check.
            ; Failing here leaves the migration unmarked for a later safe retry.
            FileMove(temporary, destination, false)
            return true
        } finally {
            try FileDelete(temporary)
        }
    }

    static WriteMigrationMarker(marker) {
        temporary := marker ".tmp-" DllCall("GetCurrentProcessId") "-"
            . DllCall("GetTickCount64", "UInt64")
        try {
            FileAppend("migration-v1`n", temporary, "UTF-8")
            FileMove(temporary, marker, true)
        } finally {
            try FileDelete(temporary)
        }
    }
}
