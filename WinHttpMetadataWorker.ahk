; = CONTENTS
;   + Preamble
;   + WinHttpMetadataWorker class (bounded synchronous GET and worker entry point)

#Requires AutoHotkey v2.0
#Include WinHttpConstants.ahk

/** Synchronous, stream-bounded metadata GET, executed in an owned child process. */
class WinHttpMetadataWorker {
    __New(maximumSize, timeouts) {
        if (!(maximumSize is Integer) || maximumSize <= 0 || maximumSize > 16 * 1024 * 1024)
            throw ValueError("A bounded metadata response limit is required")
        this.maximumSize := maximumSize
        this.timeouts := timeouts
        this.bodyBuffer := Buffer(maximumSize)
        this.readBuffer := Buffer(64 * 1024)
        this.totalBytes := 0
        this.request := 0
    }

    Get(url) {
        if !RegExMatch(url, "i)^https://api\.github\.com(/.*)$", &match)
            throw ValueError("Unsupported update metadata URL")
        session := 0
        connection := 0
        try {
            ; Synchronous WinHTTP: no native callback ever enters the interpreter.
            session := DllCall("winhttp\WinHttpOpen", "WStr", WinHttpConstants.userAgent,
                "UInt", WinHttpConstants.WINHTTP_ACCESS_TYPE_NO_PROXY,
                "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr")
            if !session
                throw OSError(A_LastError, "WinHttpOpen")
            connection := DllCall("winhttp\WinHttpConnect", "Ptr", session,
                "WStr", "api.github.com", "UShort", WinHttpConstants.INTERNET_DEFAULT_HTTPS_PORT,
                "UInt", 0, "Ptr")
            if !connection
                throw OSError(A_LastError, "WinHttpConnect")
            this.request := DllCall("winhttp\WinHttpOpenRequest", "Ptr", connection,
                "WStr", "GET", "WStr", match[1], "Ptr", 0, "Ptr", 0, "Ptr", 0,
                "UInt", WinHttpConstants.WINHTTP_FLAG_SECURE, "Ptr")
            if !this.request
                throw OSError(A_LastError, "WinHttpOpenRequest")
            if !DllCall("winhttp\WinHttpSetTimeouts", "Ptr", this.request,
                "Int", this.timeouts[1], "Int", this.timeouts[2],
                "Int", this.timeouts[3], "Int", this.timeouts[4])
                throw OSError(A_LastError, "WinHttpSetTimeouts")
            if !DllCall("winhttp\WinHttpSendRequest", "Ptr", this.request,
                "WStr", "Accept: application/vnd.github+json`r`n", "UInt", -1,
                "Ptr", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
                throw OSError(A_LastError, "WinHttpSendRequest")
            if !DllCall("winhttp\WinHttpReceiveResponse", "Ptr", this.request, "Ptr", 0)
                throw OSError(A_LastError, "WinHttpReceiveResponse")
            return this.ReadResponse()
        } finally {
            if this.request
                DllCall("winhttp\WinHttpCloseHandle", "Ptr", this.request)
            this.request := 0
            if connection
                DllCall("winhttp\WinHttpCloseHandle", "Ptr", connection)
            if session
                DllCall("winhttp\WinHttpCloseHandle", "Ptr", session)
        }
    }

    ReadResponseHeaders() {
        status := this.QueryHeaderNumber(WinHttpConstants.WINHTTP_QUERY_STATUS_CODE).value
        length := this.QueryHeaderNumber(WinHttpConstants.WINHTTP_QUERY_CONTENT_LENGTH, true)
        return {status: status, hasContentLength: length.found, contentLength: length.value}
    }

    QueryHeaderNumber(header, optional := false) {
        value := 0
        size := 4
        found := DllCall("winhttp\WinHttpQueryHeaders", "Ptr", this.request,
            "UInt", header | WinHttpConstants.WINHTTP_QUERY_FLAG_NUMBER, "Ptr", 0,
            "UInt*", &value, "UInt*", &size, "Ptr", 0)
        errorCode := A_LastError
        if (!found && !(optional && errorCode = WinHttpConstants.ERROR_WINHTTP_HEADER_NOT_FOUND))
            throw OSError(errorCode, "WinHttpQueryHeaders")
        return {found: !!found, value: value}
    }

    ReadResponse() {
        headers := this.ReadResponseHeaders()
        if (headers.hasContentLength && headers.contentLength > this.maximumSize)
            throw Error("Update metadata response exceeded its byte limit")
        if (headers.status != 200)
            return {status: headers.status, body: ""}
        loop {
            length := this.ReadChunk()
            if !length
                break
            this.ConsumeReadChunk(this.readBuffer.Ptr, length)
        }
        return {status: headers.status, body: this.totalBytes
            ? StrGet(this.bodyBuffer.Ptr, this.totalBytes, "UTF-8") : ""}
    }

    ReadChunk() {
        length := 0
        if !DllCall("winhttp\WinHttpReadData", "Ptr", this.request,
            "Ptr", this.readBuffer.Ptr, "UInt", this.readBuffer.Size, "UInt*", &length)
            throw OSError(A_LastError, "WinHttpReadData")
        return length
    }

    ConsumeReadChunk(source, length) {
        if (!(length is Integer) || length < 0 || length > this.readBuffer.Size)
            throw ValueError("WinHTTP returned an invalid metadata byte count")
        if (this.totalBytes + length > this.maximumSize)
            throw Error("Update metadata response exceeded its byte limit")
        if length {
            DllCall("ntdll\RtlMoveMemory", "Ptr", this.bodyBuffer.Ptr + this.totalBytes,
                "Ptr", source, "UPtr", length)
            this.totalBytes += length
        }
        return this.totalBytes
    }

    ; Runs the request described by request.ini in the directory named by the only
    ; argument, and writes response.bin (or error.txt) back into that directory.
    static Main(args) {
        directory := ""
        try {
            if (args.Length != 1
                || !RegExMatch(args[1], "i)\\pacs-metadata-[0-9a-f]{32}$")
                || !DirExist(args[1]))
                throw ValueError("The metadata worker needs its request directory")
            directory := args[1]
            config := directory "\request.ini"
            worker := this(Integer(IniRead(config, "Request", "MaximumSize")), [
                WinHttpConstants.resolveTimeoutMs,
                WinHttpConstants.connectTimeoutMs,
                WinHttpConstants.sendTimeoutMs,
                WinHttpConstants.receiveTimeoutMs
            ])
            response := worker.Get(IniRead(config, "Request", "Url"))
            output := FileOpen(directory "\response.bin", "w", "UTF-8-RAW")
            try {
                output.WriteUInt(response.status)
                if (response.status = 200 && worker.totalBytes)
                    output.RawWrite(worker.bodyBuffer, worker.totalBytes)
            } finally output.Close()
            ExitApp(0)
        } catch as err {
            ; Without a request directory there is nowhere to report; the parent
            ; then reports the exit code alone.
            if (directory != "")
                try FileAppend(SubStr(err.Message, 1, 2048), directory "\error.txt", "UTF-8")
            ExitApp(10)
        }
    }
}
