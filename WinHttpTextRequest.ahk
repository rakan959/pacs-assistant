#Requires AutoHotkey v2.0
#Include WinHttpTransport.ahk
#Include AppLog.ahk

/**
 * One bounded asynchronous WinHTTP GET for GitHub release metadata. The response
 * body is streamed into a fixed-size buffer and the request has an overall deadline.
 */
class WinHttpTextRequest {
    ; WinHTTP invokes one process-lifetime callback on worker threads. Context and
    ; handle maps keep each operation alive until HANDLE_CLOSING, the documented
    ; final notification for a request. This avoids freeing callback state while a
    ; worker can still reach it and avoids a per-hour callback allocation leak.
    ; WINHTTP_CALLBACK_STATUS_* values (winhttp.h). Each status's notification
    ; flag has the same bit value, so callbackFlags subscribes to exactly these.
    static WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING := 0x00000800
    static WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE := 0x00020000
    static WINHTTP_CALLBACK_STATUS_READ_COMPLETE := 0x00080000
    static WINHTTP_CALLBACK_STATUS_REQUEST_ERROR := 0x00200000
    static WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE := 0x00400000
    static operationsByContext := Map()
    static operationsByHandle := Map()
    static contextSequence := 0
    static statusCallback := 0
    static callbackFlags := this.WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING
        | this.WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE
        | this.WINHTTP_CALLBACK_STATUS_READ_COMPLETE
        | this.WINHTTP_CALLBACK_STATUS_REQUEST_ERROR
        | this.WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE

    __New(url, onComplete, onError, maximumSize) {
        if (Type(url) != "String"
            || !RegExMatch(url, "i)^https://api\.github\.com(/.*)$", &urlMatch))
            throw ValueError("Update metadata URL is not a supported GitHub API URL")
        if (!(maximumSize is Integer) || maximumSize <= 0)
            throw ValueError("A positive metadata response limit is required")

        this.path := urlMatch[1]
        this.onComplete := onComplete
        this.onError := onError
        this.maximumSize := maximumSize
        this.bodyBuffer := Buffer(maximumSize)
        this.readBuffer := Buffer(64 * 1024)
        this.totalBytes := 0
        this.session := 0
        this.connection := 0
        this.request := 0
        this.context := 0
        this.timeoutTimer := 0
        this.startedAt := 0
        this.state := "created"
        this.terminalKind := ""
        this.terminalValue := 0
    }

    Start() {
        try {
            this.state := "starting"
            this.startedAt := this.NowMilliseconds()
            this.session := DllCall(
                "winhttp\WinHttpOpen",
                "WStr", "PACS-Assistant-Update-Checker",
                "UInt", WinHttpTransport.WINHTTP_ACCESS_TYPE_NO_PROXY,
                "Ptr", 0,
                "Ptr", 0,
                "UInt", WinHttpTransport.WINHTTP_FLAG_ASYNC,
                "Ptr"
            )
            if !this.session
                throw OSError(A_LastError, "WinHttpOpen")
            this.connection := DllCall(
                "winhttp\WinHttpConnect",
                "Ptr", this.session,
                "WStr", "api.github.com",
                "UShort", WinHttpTransport.INTERNET_DEFAULT_HTTPS_PORT,
                "UInt", 0,
                "Ptr"
            )
            if !this.connection
                throw OSError(A_LastError, "WinHttpConnect")
            this.request := DllCall(
                "winhttp\WinHttpOpenRequest",
                "Ptr", this.connection,
                "WStr", "GET",
                "WStr", this.path,
                "Ptr", 0,
                "Ptr", 0,
                "Ptr", 0,
                "UInt", WinHttpTransport.WINHTTP_FLAG_SECURE,
                "Ptr"
            )
            if !this.request
                throw OSError(A_LastError, "WinHttpOpenRequest")
            if !DllCall(
                "winhttp\WinHttpSetTimeouts",
                "Ptr", this.request,
                "Int", WinHttpTransport.resolveTimeoutMs,
                "Int", WinHttpTransport.connectTimeoutMs,
                "Int", WinHttpTransport.sendTimeoutMs,
                "Int", WinHttpTransport.receiveTimeoutMs
            )
                throw OSError(A_LastError, "WinHttpSetTimeouts")

            callback := WinHttpTextRequest.CallbackPointer()
            previous := DllCall(
                "winhttp\WinHttpSetStatusCallback",
                "Ptr", this.request,
                "Ptr", callback,
                "UInt", WinHttpTextRequest.callbackFlags,
                "Ptr", 0,
                "Ptr"
            )
            if (previous = -1)
                throw OSError(A_LastError, "WinHttpSetStatusCallback")

            this.context := WinHttpTextRequest.NextContext()
            WinHttpTextRequest.operationsByContext[this.context] := this
            WinHttpTextRequest.operationsByHandle[this.request] := this
            this.timeoutTimer := ObjBindMethod(this, "CheckTimeout")
            SetTimer(this.timeoutTimer, 250)
            this.state := "sending"
            sent := DllCall(
                "winhttp\WinHttpSendRequest",
                "Ptr", this.request,
                "WStr", "User-Agent: PACS-Assistant-Update-Checker`r`n"
                    . "Accept: application/vnd.github+json`r`n",
                "UInt", -1,
                "Ptr", 0,
                "UInt", 0,
                "UInt", 0,
                "UPtr", this.context
            )
            sendError := A_LastError
            if (!sent && sendError != WinHttpTransport.ERROR_IO_PENDING)
                throw OSError(sendError, "WinHttpSendRequest")
            return this
        } catch as err {
            callback := this.onError
            this.CleanupStartFailure()
            try callback.Call(err)
            catch Any as callbackError
                AppLog.WriteError(callbackError)
            return 0
        }
    }

    static CallbackPointer() {
        if !this.statusCallback
            this.statusCallback := CallbackCreate(
                ObjBindMethod(this, "DispatchStatus"),,
                5
            )
        return this.statusCallback
    }

    static NextContext() {
        this.contextSequence++
        if !this.contextSequence
            this.contextSequence := 1
        return this.contextSequence
    }

    static DispatchStatus(handle, context, status, information, length) {
        Critical("On")
        ; CallbackCreate receives machine-word integers. WinHTTP supplies these two
        ; fields as DWORDs, so ignore undefined upper bits on x64 before dispatch.
        status &= 0xFFFFFFFF
        length &= 0xFFFFFFFF
        operation := 0
        if context {
            if !this.operationsByContext.Has(context)
                return
            operation := this.operationsByContext[context]
        } else if (handle && this.operationsByHandle.Has(handle))
            operation := this.operationsByHandle[handle]
        if !operation
            return

        try {
            operation.HandleNativeStatus(handle, status, information, length)
        } catch as err {
            operation.Schedule("Fail", err)
        }
    }

    HandleNativeStatus(handle, status, information, length) {
        if (status = WinHttpTextRequest.WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING) {
            if (this.state = "closing" && handle = this.request)
                this.Schedule("Finalize")
            return
        }
        if (this.state = "closing" || this.state = "closed")
            return

        if (status = WinHttpTextRequest.WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE) {
            this.Schedule("ReceiveResponse")
        } else if (status = WinHttpTextRequest.WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE) {
            this.Schedule("HandleHeaders")
        } else if (status = WinHttpTextRequest.WINHTTP_CALLBACK_STATUS_READ_COMPLETE) {
            if !length
                this.Schedule("CompleteRead")
            else {
                this.ConsumeReadChunk(information, length)
                this.Schedule("ReadNext")
            }
        } else if (status = WinHttpTextRequest.WINHTTP_CALLBACK_STATUS_REQUEST_ERROR) {
            errorCode := information ? NumGet(information, A_PtrSize, "UInt") : 0
            this.Schedule(
                "Fail",
                errorCode
                    ? OSError(errorCode, "WinHTTP asynchronous request")
                    : Error("WinHTTP asynchronous request failed")
            )
        }
    }

    Schedule(methodName, params*) {
        SetTimer(ObjBindMethod(this, methodName, params*), -1)
    }

    ReceiveResponse() {
        if (this.state != "sending")
            return
        this.state := "receiving"
        received := DllCall(
            "winhttp\WinHttpReceiveResponse",
            "Ptr", this.request,
            "Ptr", 0
        )
        receiveError := A_LastError
        if (!received && receiveError != WinHttpTransport.ERROR_IO_PENDING)
            this.Fail(OSError(receiveError, "WinHttpReceiveResponse"))
    }

    HandleHeaders() {
        if (this.state != "receiving")
            return
        try {
            status := 0
            statusSize := 4
            if !DllCall(
                "winhttp\WinHttpQueryHeaders",
                "Ptr", this.request,
                "UInt", WinHttpTransport.WINHTTP_QUERY_STATUS_CODE | WinHttpTransport.WINHTTP_QUERY_FLAG_NUMBER,
                "Ptr", 0,
                "UInt*", &status,
                "UInt*", &statusSize,
                "Ptr", 0
            )
                throw OSError(A_LastError, "WinHttpQueryHeaders(status)")

            contentLength := 0
            contentLengthSize := 4
            hasContentLength := DllCall(
                "winhttp\WinHttpQueryHeaders",
                "Ptr", this.request,
                "UInt", WinHttpTransport.WINHTTP_QUERY_CONTENT_LENGTH | WinHttpTransport.WINHTTP_QUERY_FLAG_NUMBER,
                "Ptr", 0,
                "UInt*", &contentLength,
                "UInt*", &contentLengthSize,
                "Ptr", 0
            )
            headerError := A_LastError
            if (!hasContentLength && headerError != WinHttpTransport.ERROR_WINHTTP_HEADER_NOT_FOUND)
                throw OSError(headerError, "WinHttpQueryHeaders(Content-Length)")
            if (hasContentLength && contentLength > this.maximumSize)
                throw Error("Update metadata response exceeded its byte limit")

            if (status != 200) {
                this.Succeed({status: status, body: ""})
                return
            }

            this.responseStatus := status
            this.state := "reading"
            this.ReadNext()
        } catch as err {
            this.Fail(err)
        }
    }

    ReadNext() {
        if (this.state != "reading")
            return
        readStarted := DllCall(
            "winhttp\WinHttpReadData",
            "Ptr", this.request,
            "Ptr", this.readBuffer.Ptr,
            "UInt", this.readBuffer.Size,
            "Ptr", 0
        )
        readError := A_LastError
        if (!readStarted && readError != WinHttpTransport.ERROR_IO_PENDING)
            this.Fail(OSError(readError, "WinHttpReadData"))
    }

    ConsumeReadChunk(source, length) {
        if (!(length is Integer) || length < 0)
            throw ValueError("WinHTTP returned an invalid metadata byte count")
        if (this.totalBytes + length > this.maximumSize)
            throw Error("Update metadata response exceeded its byte limit")
        if length {
            DllCall(
                "ntdll\RtlMoveMemory",
                "Ptr", this.bodyBuffer.Ptr + this.totalBytes,
                "Ptr", source,
                "UPtr", length
            )
            this.totalBytes += length
        }
        return this.totalBytes
    }

    CompleteRead() {
        if (this.state != "reading")
            return
        try {
            body := this.totalBytes
                ? StrGet(this.bodyBuffer.Ptr, this.totalBytes, "UTF-8")
                : ""
            this.Succeed({status: this.responseStatus, body: body})
        } catch as err {
            this.Fail(err)
        }
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
        if (this.state = "created") {
            this.terminalKind := kind
            this.terminalValue := value
            this.Finalize()
            return
        }

        this.state := "closing"
        this.terminalKind := kind
        this.terminalValue := value
        this.StopTimeoutTimer()

        request := this.request
        closePending := false
        if request
            closePending := DllCall("winhttp\WinHttpCloseHandle", "Ptr", request)
        if this.connection {
            DllCall("winhttp\WinHttpCloseHandle", "Ptr", this.connection)
            this.connection := 0
        }
        if this.session {
            DllCall("winhttp\WinHttpCloseHandle", "Ptr", this.session)
            this.session := 0
        }
        if !closePending
            this.Schedule("Finalize")
    }

    Finalize() {
        if (this.state = "closed")
            return

        this.StopTimeoutTimer()
        this.Unregister()
        this.request := 0
        this.connection := 0
        this.session := 0
        this.state := "closed"

        kind := this.terminalKind
        value := this.terminalValue
        completeCallback := this.onComplete
        errorCallback := this.onError
        this.onComplete := 0
        this.onError := 0
        this.bodyBuffer := 0
        this.readBuffer := 0
        this.terminalValue := 0

        if (kind = "complete") {
            ; The callbacks handle their own failures; reaching these is a bug.
            try completeCallback.Call(value)
            catch Any as err
                AppLog.WriteError(err)
        } else if (kind = "error") {
            try errorCallback.Call(value)
            catch Any as err
                AppLog.WriteError(err)
        }
    }

    Cancel() {
        this.BeginClose("cancel", 0)
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

    CleanupStartFailure() {
        this.StopTimeoutTimer()
        if this.request {
            DllCall(
                "winhttp\WinHttpSetStatusCallback",
                "Ptr", this.request,
                "Ptr", 0,
                "UInt", WinHttpTextRequest.callbackFlags,
                "Ptr", 0,
                "Ptr"
            )
        }
        this.Unregister()
        for propertyName in ["request", "connection", "session"] {
            handle := this.%propertyName%
            if handle
                DllCall("winhttp\WinHttpCloseHandle", "Ptr", handle)
            this.%propertyName% := 0
        }
        this.state := "closed"
        this.onComplete := 0
        this.onError := 0
        this.bodyBuffer := 0
        this.readBuffer := 0
    }

    Unregister() {
        if (this.context && WinHttpTextRequest.operationsByContext.Has(this.context))
            WinHttpTextRequest.operationsByContext.Delete(this.context)
        if (this.request && WinHttpTextRequest.operationsByHandle.Has(this.request))
            WinHttpTextRequest.operationsByHandle.Delete(this.request)
        this.context := 0
    }

    NowMilliseconds() {
        return DllCall("GetTickCount64", "UInt64")
    }
}
