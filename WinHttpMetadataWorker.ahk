; = CONTENTS
;   + Preamble
;   + WinHttpMetadataWorker class (bounded synchronous GET and worker entry point)

#Requires AutoHotkey v2.0

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
            session := DllCall("winhttp\WinHttpOpen", "WStr", "PACS-Assistant-Update-Checker",
                "UInt", 1, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr") ; NO_PROXY
            if !session
                throw OSError(A_LastError, "WinHttpOpen")
            connection := DllCall("winhttp\WinHttpConnect", "Ptr", session,
                "WStr", "api.github.com", "UShort", 443, "UInt", 0, "Ptr")
            if !connection
                throw OSError(A_LastError, "WinHttpConnect")
            this.request := DllCall("winhttp\WinHttpOpenRequest", "Ptr", connection,
                "WStr", "GET", "WStr", match[1], "Ptr", 0, "Ptr", 0, "Ptr", 0,
                "UInt", 0x00800000, "Ptr") ; WINHTTP_FLAG_SECURE
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
        status := this.QueryHeaderNumber(19).value ; WINHTTP_QUERY_STATUS_CODE
        length := this.QueryHeaderNumber(5, true) ; WINHTTP_QUERY_CONTENT_LENGTH
        return {status: status, hasContentLength: length.found, contentLength: length.value}
    }

    QueryHeaderNumber(header, optional := false) {
        value := 0
        size := 4
        found := DllCall("winhttp\WinHttpQueryHeaders", "Ptr", this.request,
            "UInt", header | 0x20000000, "Ptr", 0, "UInt*", &value,
            "UInt*", &size, "Ptr", 0) ; WINHTTP_QUERY_FLAG_NUMBER
        errorCode := A_LastError
        if (!found && !(optional && errorCode = 12150))
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

    static Main() {
        try {
            config := A_ScriptDir "\request.ini"
            maximumSize := Integer(IniRead(config, "Request", "MaximumSize"))
            timeouts := []
            for name in ["Resolve", "Connect", "Send", "Receive"] {
                value := Integer(IniRead(config, "Timeouts", name))
                if (value <= 0 || value > 60000)
                    throw ValueError("Invalid metadata timeout")
                timeouts.Push(value)
            }
            worker := this(maximumSize, timeouts)
            response := worker.Get(IniRead(config, "Request", "Url"))
            output := FileOpen(A_ScriptDir "\response.bin", "w", "UTF-8-RAW")
            try {
                output.WriteUInt(response.status)
                if (response.status = 200 && worker.totalBytes)
                    output.RawWrite(worker.bodyBuffer, worker.totalBytes)
            } finally output.Close()
            ExitApp(0)
        } catch as err {
            try FileAppend(SubStr(err.Message, 1, 2048), A_ScriptDir "\error.txt", "UTF-8")
            ExitApp(10)
        }
    }
}
