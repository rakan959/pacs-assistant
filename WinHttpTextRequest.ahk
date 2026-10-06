; = CONTENTS
;   + Preamble
;   + WinHttpTextRequest class (worker files, polling, completion and cleanup)

#Requires AutoHotkey v2.0
#Include WinHttpTransport.ahk
#Include WinHttpMetadataWorker.ahk
#Include WinHttpWorkerProcess.ahk
#Include AppLog.ahk

/**
 * Asynchronous metadata request for the UI process. A separate owned interpreter
 * performs synchronous, bounded WinHTTP reads. Only the script timer invokes the
 * completion callbacks; WinHTTP worker threads never enter AutoHotkey callbacks.
 */
class WinHttpTextRequest {
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
            this.CreateWorkerFiles()
            this.exitCallback := ObjBindMethod(this, "Cancel")
            OnExit(this.exitCallback)
            this.worker.Start(this.directory "\worker.ahk", this.directory)
            this.state := "sending"
            this.timeoutTimer := ObjBindMethod(this, "Poll")
            SetTimer(this.timeoutTimer, 50)
            return this
        } catch as err {
            this.Fail(err)
            return 0
        }
    }

    CreateWorkerFiles() {
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
        destination := directory "\WinHttpMetadataWorker.ahk"
        if A_IsCompiled
            FileInstall("WinHttpMetadataWorker.ahk", destination)
        else {
            SplitPath(A_LineFile, , &sourceDirectory)
            FileCopy(sourceDirectory "\WinHttpMetadataWorker.ahk", destination)
        }
        FileAppend(this.WorkerScript(), directory "\worker.ahk", "UTF-8")
        config := directory "\request.ini"
        IniWrite(this.url, config, "Request", "Url")
        IniWrite(this.maximumSize, config, "Request", "MaximumSize")
        for entry in [
            ["Resolve", WinHttpTransport.resolveTimeoutMs],
            ["Connect", WinHttpTransport.connectTimeoutMs],
            ["Send", WinHttpTransport.sendTimeoutMs],
            ["Receive", WinHttpTransport.receiveTimeoutMs]
        ]
            IniWrite(entry[2], config, "Timeouts", entry[1])
    }

    WorkerScript() {
        return '#Requires AutoHotkey v2.0`n'
            . '#SingleInstance Off`n'
            . '#ErrorStdOut`n'
            . '#Warn All, StdOut`n'
            . 'FileEncoding "UTF-8"`n'
            . 'OnError((*) => ExitApp(10))`n'
            . '#Include WinHttpMetadataWorker.ahk`n'
            . 'WinHttpMetadataWorker.Main()`n'
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
        cleanupError := 0
        try this.worker.Close()
        catch as err {
            cleanupError := err
            AppLog.Write("Metadata worker cleanup failed: " ErrorText.Describe(err))
        }
        if (this.exitCallback && !cleanupError) {
            OnExit(this.exitCallback, 0)
            this.exitCallback := 0
        }
        if !cleanupError
            this.CleanupFiles()
        this.state := "closed"
        kind := cleanupError ? "error" : this.terminalKind
        value := cleanupError ? Error("Metadata worker cleanup failed: " cleanupError.Message) : this.terminalValue
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
            for name in ["worker.ahk", "WinHttpMetadataWorker.ahk", "request.ini", "response.bin", "error.txt"] {
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

    CheckTimeout() {
        if (this.state = "closing" || this.state = "closed")
            return
        maxDuration := WinHttpTransport.resolveTimeoutMs
            + WinHttpTransport.connectTimeoutMs
            + WinHttpTransport.sendTimeoutMs
            + WinHttpTransport.receiveTimeoutMs
            + 2000
        if (this.NowMilliseconds() - this.startedAt > maxDuration)
            this.Fail(Error("WinHTTP asynchronous request timed out"))
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
