; = CONTENTS
;   + Preamble
;   + WinHttpTextRequest class (request files, polling, completion and cleanup)

#Requires AutoHotkey v2.0
#Include WinHttpConstants.ahk
#Include WinHttpMetadataWorker.ahk
#Include WinHttpWorkerProcess.ahk
#Include AppLog.ahk

; Compiled builds carry the worker as an embedded script (see WorkerArguments).
;@Ahk2Exe-AddResource WinHttpMetadataWorkerMain.ahk, WINHTTPMETADATAWORKER

/**
 * Asynchronous metadata request for the UI process. A separate owned interpreter
 * performs synchronous, bounded WinHTTP reads. Only the script timer invokes the
 * completion callbacks; WinHTTP worker threads never enter AutoHotkey callbacks.
 */
class WinHttpTextRequest {
    static workerResourceName := "WINHTTPMETADATAWORKER"
    static requestFileNames := ["request.ini", "response.bin", "error.txt"]
    static abandonedSweepDone := false

    __New(url, onComplete, onError, maximumSize) {
        if (Type(url) != "String"
            || !RegExMatch(url, "i)^https://api\.github\.com(/.*)$")
            || RegExMatch(url, '[\x00-\x20"]'))
            throw ValueError("Update metadata URL is not a supported GitHub API URL")
        if (!(maximumSize is Integer) || maximumSize <= 0 || maximumSize > 16 * 1024 * 1024)
            throw ValueError("A positive metadata response limit of at most 16 MiB is required")
        this.url := url
        this.onComplete := onComplete
        this.onError := onError
        this.maximumSize := maximumSize
        this.worker := WinHttpWorkerProcess()
        this.directory := ""
        this.timeoutTimer := 0
        this.exitCallback := 0
        this.startedAt := 0
        this.state := "created"
        this.terminalKind := ""
        this.terminalValue := 0
    }

    Start() {
        if (this.state != "created")
            throw Error("A metadata request can be started only once")
        try {
            this.state := "starting"
            this.startedAt := this.NowMilliseconds()
            this.CreateRequestFiles()
            this.exitCallback := ObjBindMethod(this, "Cancel")
            OnExit(this.exitCallback)
            this.worker.Start(this.WorkerArguments(), this.directory)
            this.state := "sending"
            this.timeoutTimer := ObjBindMethod(this, "Poll")
            SetTimer(this.timeoutTimer, 50)
            return this
        } catch as err {
            this.Fail(err)
            return 0
        }
    }

    CreateRequestFiles() {
        if !WinHttpTextRequest.abandonedSweepDone {
            WinHttpTextRequest.abandonedSweepDone := true
            WinHttpTextRequest.SweepAbandonedDirectories(A_Temp)
        }
        guid := Buffer(16)
        if DllCall("ole32\CoCreateGuid", "Ptr", guid, "Int")
            throw Error("Could not allocate a metadata request identity")
        name := ""
        loop 4
            name .= Format("{:08x}", NumGet(guid, (A_Index - 1) * 4, "UInt"))
        directory := A_Temp "\pacs-metadata-" name
        if DirExist(directory)
            throw Error("Metadata request directory already exists")
        DirCreate(directory)
        this.directory := directory
        config := directory "\request.ini"
        IniWrite(this.url, config, "Request", "Url")
        IniWrite(this.maximumSize, config, "Request", "MaximumSize")
    }

    ; The worker is the program already running: a compiled build runs its embedded
    ; worker script, so it never writes or executes a script file; a source run
    ; starts the worker file beside this one. Its argument is the request directory.
    WorkerArguments() {
        if A_IsCompiled
            script := "*" WinHttpTextRequest.workerResourceName
        else {
            SplitPath(A_LineFile, , &sourceDirectory)
            script := '"' sourceDirectory '\WinHttpMetadataWorkerMain.ahk"'
        }
        return '/script /ErrorStdOut ' script ' "' this.directory '"'
    }

    ; A request directory outlives its request only when the process was killed
    ; mid-check, so OnExit never ran, or its cleanup failed. Remove those once per
    ; run; the age limit keeps the sweep clear of any live request.
    static SweepAbandonedDirectories(root, minimumAgeMinutes := 60) {
        loop files root "\pacs-metadata-*", "D" {
            if (!RegExMatch(A_LoopFileName, "^pacs-metadata-[0-9a-f]{32}$")
                || DateDiff(A_Now, A_LoopFileTimeModified, "Minutes") < minimumAgeMinutes)
                continue
            directory := A_LoopFileFullPath
            try {
                for name in this.requestFileNames {
                    if FileExist(directory "\" name)
                        FileDelete(directory "\" name)
                }
                DirDelete(directory)
            } catch as err {
                AppLog.Write("An abandoned metadata request directory could not be removed: "
                    . ErrorText.Describe(err))
            }
        }
    }

    Poll() {
        if (this.state != "sending")
            return
        this.CheckTimeout()
        if (this.state != "sending")
            return
        try {
            if !this.worker.IsFinished()
                return
            if this.worker.ExitCode() {
                errorPath := this.directory "\error.txt"
                message := FileExist(errorPath) && FileGetSize(errorPath) <= 8192
                    ? FileRead(errorPath, "UTF-8") : "The metadata worker failed before returning a response"
                throw Error(message)
            }
            this.Succeed(this.ReadWorkerResponse())
        } catch as err {
            this.Fail(err)
        }
    }

    ReadWorkerResponse() {
        input := FileOpen(this.directory "\response.bin", "r", "UTF-8-RAW")
        try {
            if (input.Length < 4 || input.Length > this.maximumSize + 4)
                throw Error("Update metadata response exceeded its byte limit or was truncated")
            status := input.ReadUInt()
            if (status < 100 || status > 599)
                throw Error("The metadata worker returned an invalid HTTP status")
            length := input.Length - 4
            if (status != 200 && length)
                throw Error("The metadata worker returned an unexpected error body")
            body := ""
            if length {
                bodyBytes := Buffer(length)
                if (input.RawRead(bodyBytes, length) != length)
                    throw Error("The metadata worker response was truncated")
                body := StrGet(bodyBytes.Ptr, length, "UTF-8")
            }
            return {status: status, body: body}
        } finally input.Close()
    }

    Succeed(response) {
        this.BeginClose("complete", response)
    }

    Fail(err) {
        this.BeginClose("error", err)
    }

    BeginClose(kind, value) {
        if (this.state = "closing" || this.state = "closed")
            return
        this.state := "closing"
        this.terminalKind := kind
        this.terminalValue := value
        this.StopTimeoutTimer()
        this.Finalize()
    }

    Finalize() {
        if (this.state = "closed")
            return
        ; A callback may immediately start another check. Reap this worker and
        ; release its timers/files before publishing completion to that caller.
        ; A failed reap keeps the exact handle, files and exit cleanup for a retry
        ; at exit; it does not change the outcome, and a cancel never calls back.
        reaped := false
        try {
            this.worker.Close()
            reaped := true
        } catch as err {
            AppLog.Write("Metadata worker cleanup failed: " ErrorText.Describe(err))
        }
        if reaped {
            if this.exitCallback {
                OnExit(this.exitCallback, 0)
                this.exitCallback := 0
            }
            this.CleanupFiles()
        }
        this.state := "closed"
        kind := this.terminalKind
        value := this.terminalValue
        completeCallback := this.onComplete
        errorCallback := this.onError
        this.onComplete := 0
        this.onError := 0
        this.terminalValue := 0
        try {
            if (kind = "complete")
                completeCallback.Call(value)
            else if (kind = "error")
                errorCallback.Call(value)
        } catch Any as err {
            AppLog.WriteError(err)
        }
    }

    CleanupFiles() {
        if (this.directory = "")
            return
        try {
            for name in WinHttpTextRequest.requestFileNames {
                path := this.directory "\" name
                if FileExist(path)
                    FileDelete(path)
            }
            DirDelete(this.directory)
            this.directory := ""
        } catch as err {
            AppLog.Write("Metadata temporary files could not be removed: " ErrorText.Describe(err))
        }
    }

    Cancel(*) {
        if (this.state = "closed" && this.exitCallback) {
            ; A failed reap retains its exact handle and exit cleanup. Retry it
            ; without permitting an OnExit callback to prevent shutdown.
            try {
                this.worker.Close()
                this.CleanupFiles()
                OnExit(this.exitCallback, 0)
                this.exitCallback := 0
            } catch as err {
                AppLog.Write("Metadata worker exit cleanup failed: " ErrorText.Describe(err))
            }
            return 0
        }
        this.BeginClose("cancel", 0)
        return 0 ; OnExit must never veto the application's exit.
    }

    ; The deadline covers starting the worker as well as its request.
    CheckTimeout() {
        if (this.state = "closing" || this.state = "closed")
            return
        maxDuration := WinHttpConstants.resolveTimeoutMs
            + WinHttpConstants.connectTimeoutMs
            + WinHttpConstants.sendTimeoutMs
            + WinHttpConstants.receiveTimeoutMs
            + 2000
        if (this.NowMilliseconds() - this.startedAt > maxDuration)
            this.Fail(Error("The update metadata request timed out"))
    }

    StopTimeoutTimer() {
        if this.timeoutTimer {
            SetTimer(this.timeoutTimer, 0)
            this.timeoutTimer := 0
        }
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }
}
