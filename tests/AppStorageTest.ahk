#Requires AutoHotkey v2.0
#Include ../AppStorage.ahk
#Include TestRunner.ahk

class AppStorageTest {
    static tests := [
        "TestInstalledDataMigrationCopiesOnceAndPreservesLegacy",
        "TestResumedMigrationKeepsADestinationWrittenSinceTheFailedAttempt",
        "TestMigrationNeverReplacesADestinationThatAppearsDuringTheCopy",
        "TestCompletedMigrationDoesNotResurrectDeletedProfile",
        "TestPartialMigrationRetriesBeforeWritingMarker",
        "TestFailedCopyCannotPublishAPartialDestination",
        "TestPortableRootSkipsMigration",
        "TestUniqueSiblingPathSkipsExistingFiles"
    ]

    Setup() {
        this.originalDataRoot := AppStorage.dataRootOverride
        this.originalLegacyRoot := AppStorage.legacyRootOverride
        this.originalCopyFile := AppStorage.copyFile
        this.tempRoot := TestTempPath("pacs-storage")
        this.legacyRoot := this.tempRoot "\legacy"
        this.dataRoot := this.tempRoot "\data"
        DirCreate(this.legacyRoot "\profiles")
        FileAppend("legacy settings", this.legacyRoot "\settings.ini")
        FileAppend("legacy config", this.legacyRoot "\config.ini")
        FileAppend("legacy profile", this.legacyRoot "\profiles\Night.ini")
        AppStorage.dataRootOverride := this.dataRoot
        AppStorage.legacyRootOverride := this.legacyRoot
    }

    TestPortableRootSkipsMigration() {
        ; Source runs keep data beside the script, so data and legacy roots coincide
        ; and there is nothing to copy or mark.
        AppStorage.dataRootOverride := this.legacyRoot
        copies := []
        AppStorage.copyFile := (source, destination) => copies.Push(source)

        Assert.Equal(this.legacyRoot, AppStorage.Ensure())
        Assert.Equal(0, copies.Length)
        Assert.False(FileExist(this.legacyRoot "\" AppStorage.migrationMarkerName) != "")
        Assert.True(DirExist(this.legacyRoot "\profiles") != "")
    }

    TestInstalledDataMigrationCopiesOnceAndPreservesLegacy() {
        Assert.Equal(this.dataRoot, AppStorage.Ensure())
        Assert.Equal("legacy settings", FileRead(this.dataRoot "\settings.ini"))
        Assert.Equal("legacy config", FileRead(this.dataRoot "\config.ini"))
        Assert.Equal("legacy profile", FileRead(this.dataRoot "\profiles\Night.ini"))
        Assert.Equal("legacy settings", FileRead(this.legacyRoot "\settings.ini"))

        FileDelete(this.dataRoot "\settings.ini")
        FileAppend("new destination", this.dataRoot "\settings.ini")
        FileDelete(this.legacyRoot "\settings.ini")
        FileAppend("changed legacy", this.legacyRoot "\settings.ini")
        AppStorage.Ensure()

        Assert.Equal("new destination", FileRead(this.dataRoot "\settings.ini"))
    }

    ; A failed migration resumes at the next start. Settings the user changed in the
    ; meantime must not be replaced by the stale legacy copy.
    TestResumedMigrationKeepsADestinationWrittenSinceTheFailedAttempt() {
        AppStorage.copyFile := FailingMigrationCopy(this.dataRoot "\config.ini")
        Assert.Throws((*) => AppStorage.Ensure(), "simulated migration copy failure")
        FileDelete(this.dataRoot "\settings.ini")
        FileAppend("newer destination", this.dataRoot "\settings.ini")

        AppStorage.copyFile := this.originalCopyFile
        AppStorage.Ensure()

        Assert.Equal("newer destination", FileRead(this.dataRoot "\settings.ini"))
        Assert.Equal("legacy config", FileRead(this.dataRoot "\config.ini"))
    }

    ; The final move refuses to overwrite, so a destination that appears after the
    ; existence check survives and the migration stays unmarked for a later retry.
    TestMigrationNeverReplacesADestinationThatAppearsDuringTheCopy() {
        destination := this.dataRoot "\settings.ini"
        AppStorage.copyFile := (source, temporary) => (
            FileCopy(source, temporary),
            InStr(temporary, destination ".") = 1 && FileAppend("written meanwhile", destination)
        )

        Assert.Throws((*) => AppStorage.Ensure())

        Assert.Equal("written meanwhile", FileRead(destination))
        Assert.False(FileExist(this.dataRoot "\" AppStorage.migrationMarkerName))
    }

    TestCompletedMigrationDoesNotResurrectDeletedProfile() {
        AppStorage.Ensure()
        marker := this.dataRoot "\" AppStorage.migrationMarkerName
        Assert.True(FileExist(marker) != "")

        FileDelete(this.dataRoot "\profiles\Night.ini")
        AppStorage.Ensure()

        Assert.False(FileExist(this.dataRoot "\profiles\Night.ini") != "")
        Assert.Equal("legacy profile", FileRead(this.legacyRoot "\profiles\Night.ini"))
    }

    TestPartialMigrationRetriesBeforeWritingMarker() {
        AppStorage.copyFile := FailingMigrationCopy(this.dataRoot "\config.ini")
        Assert.Throws(
            (*) => AppStorage.Ensure(),
            "simulated migration copy failure"
        )
        marker := this.dataRoot "\" AppStorage.migrationMarkerName
        Assert.False(FileExist(marker) != "")
        Assert.Equal("legacy settings", FileRead(this.dataRoot "\settings.ini"))
        Assert.False(FileExist(this.dataRoot "\config.ini") != "")

        AppStorage.copyFile := this.originalCopyFile
        AppStorage.Ensure()

        Assert.True(FileExist(marker) != "")
        Assert.Equal("legacy config", FileRead(this.dataRoot "\config.ini"))
        Assert.Equal("legacy profile", FileRead(this.dataRoot "\profiles\Night.ini"))
    }

    TestFailedCopyCannotPublishAPartialDestination() {
        destination := this.dataRoot "\config.ini"
        AppStorage.copyFile := PartialMigrationCopy(destination)

        Assert.Throws(
            (*) => AppStorage.Ensure(),
            "simulated partial migration copy"
        )
        Assert.False(FileExist(destination) != "")

        AppStorage.copyFile := this.originalCopyFile
        AppStorage.Ensure()
        Assert.Equal("legacy config", FileRead(destination))
    }

    Teardown() {
        AppStorage.dataRootOverride := this.originalDataRoot
        AppStorage.legacyRootOverride := this.originalLegacyRoot
        AppStorage.copyFile := this.originalCopyFile
        try DirDelete(this.tempRoot, true)
    }

    ; The staging-name format is a recovery contract: ProfileManager finds an
    ; interrupted case-only rename by "<name>.ini.case-rename-<pid>-<n>".
    TestUniqueSiblingPathSkipsExistingFiles() {
        DirCreate(this.tempRoot)
        target := this.tempRoot "\Night.ini"
        first := AppStorage.UniqueSiblingPath(target, "case-rename")
        Assert.True(first ~= "^\Q" target "\E\.case-rename-" DllCall("GetCurrentProcessId") "-\d+$", first)

        FileAppend("taken", first)
        second := AppStorage.UniqueSiblingPath(target, "case-rename")
        Assert.NotEqual(first, second)
        Assert.False(FileExist(second))
    }
}

class FailingMigrationCopy {
    __New(failedDestination) {
        this.failedDestination := failedDestination
    }

    Call(source, destination) {
        if (InStr(destination, this.failedDestination) = 1)
            throw Error("simulated migration copy failure")
        FileCopy(source, destination, false)
    }
}

class PartialMigrationCopy {
    __New(destinationPrefix) {
        this.destinationPrefix := destinationPrefix
    }

    Call(source, destination) {
        if (InStr(destination, this.destinationPrefix) = 1) {
            FileAppend("partial", destination)
            throw Error("simulated partial migration copy")
        }
        FileCopy(source, destination, false)
    }
}
