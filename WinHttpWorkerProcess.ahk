; = CONTENTS
;   + Preamble
;   + WinHttpWorkerProcess class (job ownership, launch and bounded cancellation)

#Requires AutoHotkey v2.0

/** Owns the exact worker process handle and a kill-on-close Windows job. */
class WinHttpWorkerProcess {
    ; Win32 constants from winnt.h, winbase.h and processthreadsapi.h, in their
    ; native spelling.
    static JobObjectExtendedLimitInformation := 9
    static JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE := 0x2000
    static PROC_THREAD_ATTRIBUTE_JOB_LIST := 0x0002000D
    static EXTENDED_STARTUPINFO_PRESENT := 0x00080000
    static CREATE_NO_WINDOW := 0x08000000

    process := 0
    job := 0

    /**
     * Runs the current program (AutoHotkey, or this compiled build) with arguments.
     * The process is created inside a kill-on-close job, so it never runs unowned
     * and never has to start suspended. Requires Windows 10 or later.
     */
    Start(arguments, directory) {
        attributes := 0
        attributesInitialized := false
        threadHandle := 0
        try {
            this.job := DllCall("CreateJobObjectW", "Ptr", 0, "Ptr", 0, "Ptr")
            if !this.job
                throw OSError(A_LastError, "CreateJobObject")
            ; JOBOBJECT_EXTENDED_LIMIT_INFORMATION, native Win32 layout. The
            ; LimitFlags field is at byte 16 on both architectures.
            limits := Buffer(A_PtrSize = 8 ? 144 : 112, 0)
            NumPut("UInt", WinHttpWorkerProcess.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, limits, 16)
            if !DllCall("SetInformationJobObject", "Ptr", this.job,
                "Int", WinHttpWorkerProcess.JobObjectExtendedLimitInformation,
                "Ptr", limits, "UInt", limits.Size)
                throw OSError(A_LastError, "SetInformationJobObject")

            ; The first call only reports the list's size, so its failure is expected.
            attributesSize := 0
            DllCall("InitializeProcThreadAttributeList", "Ptr", 0, "UInt", 1, "UInt", 0,
                "UPtr*", &attributesSize)
            attributes := Buffer(attributesSize, 0)
            if !DllCall("InitializeProcThreadAttributeList", "Ptr", attributes, "UInt", 1,
                "UInt", 0, "UPtr*", &attributesSize)
                throw OSError(A_LastError, "InitializeProcThreadAttributeList")
            attributesInitialized := true
            ; The handle list must outlive the attribute list, deleted in finally.
            jobList := Buffer(A_PtrSize, 0)
            NumPut("Ptr", this.job, jobList)
            if !DllCall("UpdateProcThreadAttribute", "Ptr", attributes, "UInt", 0,
                "UPtr", WinHttpWorkerProcess.PROC_THREAD_ATTRIBUTE_JOB_LIST,
                "Ptr", jobList, "UPtr", jobList.Size, "Ptr", 0, "Ptr", 0)
                throw OSError(A_LastError, "UpdateProcThreadAttribute")

            command := '"' A_AhkPath '" ' arguments
            commandBuffer := Buffer(StrPut(command, "UTF-16") * 2)
            StrPut(command, commandBuffer, "UTF-16")
            ; STARTUPINFOEXW: STARTUPINFOW followed by the attribute-list pointer.
            startupInfoSize := A_PtrSize = 8 ? 104 : 68
            startup := Buffer(startupInfoSize + A_PtrSize, 0)
            NumPut("UInt", startup.Size, startup)
            NumPut("Ptr", attributes.Ptr, startup, startupInfoSize)
            information := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            ; No handles are inherited.
            if !DllCall("CreateProcessW", "WStr", A_AhkPath, "Ptr", commandBuffer,
                "Ptr", 0, "Ptr", 0, "Int", false,
                "UInt", WinHttpWorkerProcess.CREATE_NO_WINDOW
                    | WinHttpWorkerProcess.EXTENDED_STARTUPINFO_PRESENT,
                "Ptr", 0, "WStr", directory, "Ptr", startup, "Ptr", information)
                throw OSError(A_LastError, "CreateProcess")
            this.process := NumGet(information, 0, "Ptr")
            threadHandle := NumGet(information, A_PtrSize, "Ptr")
        } catch {
            this.Close()
            throw
        } finally {
            if threadHandle
                DllCall("CloseHandle", "Ptr", threadHandle)
            if attributesInitialized
                DllCall("DeleteProcThreadAttributeList", "Ptr", attributes)
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
        ; Closing the kill-on-close job ends a running worker; the process never
        ; exists outside it. Keep the process handle until reaping succeeds so
        ; exit can retry. The handle pins process identity, so a retry cannot
        ; wait on a recycled PID or another AutoHotkey session.
        if this.job {
            if !DllCall("CloseHandle", "Ptr", this.job)
                throw OSError(A_LastError, "CloseHandle(job)")
            this.job := 0
        }
        if this.process {
            if (!this.IsFinished()
                && DllCall("WaitForSingleObject", "Ptr", this.process, "UInt", 1000, "UInt") != 0)
                throw Error("The metadata worker did not stop within one second")
            if !DllCall("CloseHandle", "Ptr", this.process)
                throw OSError(A_LastError, "CloseHandle(process)")
            this.process := 0
        }
    }
}
