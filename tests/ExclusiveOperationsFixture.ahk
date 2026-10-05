#Requires AutoHotkey v2.0
#Include ../ExclusiveOperations.ahk

; Releases every flag ExclusiveOperations consults, including the clinical and
; settings flags it reads from PACSCommands and Settings, so a test starts with no
; lease held. Restore puts the values ReleaseAll saved back.
class ExclusiveOperationsFixture {
    ; [owner, property, released value]
    static fields := [
        [PACSCommands, "clinicalCommandActive", false],
        [PACSCommands, "activeClinicalCommand", ""],
        [ExclusiveOperations, "captureActive", false],
        [ExclusiveOperations, "captureRestartRequired", false],
        [ExclusiveOperations, "profileMutationActive", false],
        [ExclusiveOperations, "profileMutationAction", ""],
        [Settings, "writeTransactionActive", false],
        [ExclusiveOperations, "uiPresentationActive", false],
        [ExclusiveOperations, "uiPresentationAction", ""],
        [ExclusiveOperations, "shutdownActive", false],
        [ExclusiveOperations, "shutdownAction", ""]
    ]

    static ReleaseAll() {
        saved := []
        for field in this.fields {
            saved.Push(field[1].%field[2]%)
            field[1].%field[2]% := field[3]
        }
        return saved
    }

    static Restore(saved) {
        for index, field in this.fields
            field[1].%field[2]% := saved[index]
    }
}
