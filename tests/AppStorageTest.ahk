#Requires AutoHotkey v2.0
#Include ../AppStorage.ahk
#Include TestRunner.ahk

class AppStorageTest {
    static Tests := [
        "TestInstalledDataMigrationPreservesLegacyAndDoesNotOverwriteDestination",
        "TestCompletedMigrationDoesNotResurrectDeletedProfile",
        "TestPartialMigrationRetriesBeforeWritingMarker",
        "TestFailedCopyCannotPublishAPartialDestination"
    ]

    Setup() {
        this.originalDataRoot := AppStorage.dataRootOverride
        this.originalLegacyRoot := AppStorage.legacyRootOverride
        this.originalCopyFile := AppStorage.copyFile
        this.tempRoot := A_Temp "\pacs_storage_" A_TickCount "_" Random(1000, 9999)
        this.legacyRoot := this.tempRoot "\legacy"
        this.dataRoot := this.tempRoot "\data"
        DirCreate(this.legacyRoot "\profiles")
        FileAppend("legacy settings", this.legacyRoot "\settings.ini")
        FileAppend("legacy config", this.legacyRoot "\config.ini")
        FileAppend("legacy profile", this.legacyRoot "\profiles\Night.ini")
        AppStorage.dataRootOverride := this.dataRoot
        AppStorage.legacyRootOverride := this.legacyRoot
    }

    TestInstalledDataMigrationPreservesLegacyAndDoesNotOverwriteDestination() {
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
