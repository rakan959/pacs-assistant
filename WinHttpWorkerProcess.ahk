; = CONTENTS
;   + Preamble
;   + WinHttpWorkerProcess class (job ownership, launch and bounded cancellation)

#Requires AutoHotkey v2.0

/** Owns the exact worker process handle and a kill-on-close Windows job. */
class WinHttpWorkerProcess {
    process := 0
    job := 0
    jobAssigned := false

    Start(scriptPath, directory) {
        threadHandle := 0
        try {
            this.job := DllCall("CreateJobObjectW", "Ptr", 0, "Ptr", 0, "Ptr")
            if !this.job
                throw OSError(A_LastError, "CreateJobObject")
            ; JOBOBJECT_EXTENDED_LIMIT_INFORMATION, native Win32 layout. The
            ; LimitFlags field is at byte 16 on both architectures.
            limits := Buffer(A_PtrSize = 8 ? 144 : 112, 0)
            NumPut("UInt", 0x2000, limits, 16) ; JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if !DllCall("SetInformationJobObject", "Ptr", this.job, "Int", 9,
                "Ptr", limits, "UInt", limits.Size)
                throw OSError(A_LastError, "SetInformationJobObject")
            command := '"' A_AhkPath '" /script /ErrorStdOut "' scriptPath '"'
            commandBuffer := Buffer(StrPut(command, "UTF-16") * 2)
            StrPut(command, commandBuffer, "UTF-16")
            startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
            NumPut("UInt", startup.Size, startup)
            information := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            ; Suspend before job assignment, so even an immediate parent exit
            ; cannot leave an unowned network worker behind. No handles inherited.
            if !DllCall("CreateProcessW", "WStr", A_AhkPath, "Ptr", commandBuffer,
                "Ptr", 0, "Ptr", 0, "Int", false, "UInt", 0x08000004,
                "Ptr", 0, "WStr", directory, "Ptr", startup, "Ptr", information)
                throw OSError(A_LastError, "CreateProcess")
            this.process := NumGet(information, 0, "Ptr")
            threadHandle := NumGet(information, A_PtrSize, "Ptr")
            if !DllCall("AssignProcessToJobObject", "Ptr", this.job, "Ptr", this.process)
                throw OSError(A_LastError, "AssignProcessToJobObject")
            this.jobAssigned := true
            if (DllCall("ResumeThread", "Ptr", threadHandle, "UInt") = 0xFFFFFFFF)
                throw OSError(A_LastError, "ResumeThread")
        } catch {
            this.Close()
            throw
        } finally {
            if threadHandle
                DllCall("CloseHandle", "Ptr", threadHandle)
        }
    }

    IsFinished() {
        if !this.process
            return true
        result := DllCall("WaitForSingleObject", "Ptr", this.process, "UInt", 0, "UInt")
        if (result = 0xFFFFFFFF)
            throw OSError(A_LastError, "WaitForSingleObject")
        return result = 0
    }

    ExitCode() {
        code := 0
        if !DllCall("GetExitCodeProcess", "Ptr", this.process, "UInt*", &code)
            throw OSError(A_LastError, "GetExitCodeProcess")
        return code
    }

    Close() {
        ; Closing the job also stops an assigned worker if termination or waiting
        ; fails. Keep the process handle until reaping succeeds so exit can retry.
        if this.job {
            if !DllCall("CloseHandle", "Ptr", this.job)
                throw OSError(A_LastError, "CloseHandle(job)")
            this.job := 0
        }
        if this.process {
            if !this.IsFinished() {
                ; The handle pins process identity; cancellation cannot target a
                ; recycled PID or another AutoHotkey session.
                if (!this.jobAssigned && !DllCall("TerminateProcess", "Ptr", this.process, "UInt", 10)) {
                    errorCode := A_LastError
                    ; The job may have completed termination between these calls.
                    if !this.IsFinished()
                        throw OSError(errorCode, "TerminateProcess")
                }
                if (DllCall("WaitForSingleObject", "Ptr", this.process, "UInt", 1000, "UInt") != 0)
                    throw Error("The metadata worker did not stop within one second")
            }
            if !DllCall("CloseHandle", "Ptr", this.process)
                throw OSError(A_LastError, "CloseHandle(process)")
            this.process := 0
            this.jobAssigned := false
        }
    }
}
