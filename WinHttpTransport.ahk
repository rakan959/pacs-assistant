#Requires AutoHotkey v2.0

/** Bounded WinHTTP transport for asynchronous checks and interactive downloads. */
class WinHttpTransport {
    ; Win32 constants from winhttp.h and winerror.h, in their native spelling.
    ; Requests bypass any configured proxy (NO_PROXY), as they always have.
    static WINHTTP_ACCESS_TYPE_NO_PROXY := 1
    static WINHTTP_FLAG_SECURE := 0x00800000
    static WINHTTP_QUERY_CONTENT_LENGTH := 5
    static WINHTTP_QUERY_STATUS_CODE := 19
    static WINHTTP_QUERY_FLAG_NUMBER := 0x20000000
    static INTERNET_DEFAULT_HTTPS_PORT := 443
    static ERROR_WINHTTP_HEADER_NOT_FOUND := 12150

    static resolveTimeoutMs := 2000
    static connectTimeoutMs := 3000
    static sendTimeoutMs := 5000
    static receiveTimeoutMs := 10000

    GetTextAsync(url, onComplete, onError, maximumSize) {
        operation := WinHttpTextRequest(url, onComplete, onError, maximumSize)
        return operation.Start()
    }

    Download(url, destination, expectedSize, maximumSize) {
        if (!(expectedSize is Integer)
            || expectedSize <= 0
            || expectedSize > maximumSize)
            throw Error("Update download size is outside the allowed range")
        if !RegExMatch(url, "i)^https://github\.com(/.*)$", &match)
            throw Error("Update download URL is not a supported HTTPS GitHub URL")

        session := 0
        connection := 0
        request := 0
        output := 0
        completed := false
        try {
            session := DllCall(
                "winhttp\WinHttpOpen",
                "WStr", "PACS-Assistant-Update-Checker",
                "UInt", WinHttpTransport.WINHTTP_ACCESS_TYPE_NO_PROXY,
                "Ptr", 0,
                "Ptr", 0,
                "UInt", 0,
                "Ptr"
            )
            if !session
                throw OSError(A_LastError, "WinHttpOpen")
            connection := DllCall(
                "winhttp\WinHttpConnect",
                "Ptr", session,
                "WStr", "github.com",
                "UShort", WinHttpTransport.INTERNET_DEFAULT_HTTPS_PORT,
                "UInt", 0,
                "Ptr"
            )
            if !connection
                throw OSError(A_LastError, "WinHttpConnect")
            request := DllCall(
                "winhttp\WinHttpOpenRequest",
                "Ptr", connection,
                "WStr", "GET",
                "WStr", match[1],
                "Ptr", 0,
                "Ptr", 0,
                "Ptr", 0,
                "UInt", WinHttpTransport.WINHTTP_FLAG_SECURE,
                "Ptr"
            )
            if !request
                throw OSError(A_LastError, "WinHttpOpenRequest")
            if !DllCall(
                "winhttp\WinHttpSetTimeouts",
                "Ptr", request,
                "Int", WinHttpTransport.resolveTimeoutMs,
                "Int", WinHttpTransport.connectTimeoutMs,
                "Int", WinHttpTransport.sendTimeoutMs,
                "Int", WinHttpTransport.receiveTimeoutMs
            )
                throw OSError(A_LastError, "WinHttpSetTimeouts")
            if !DllCall(
                "winhttp\WinHttpSendRequest",
                "Ptr", request,
                "WStr", "Accept: application/octet-stream`r`n",
                "UInt", -1,
                "Ptr", 0,
                "UInt", 0,
                "UInt", 0,
                "UPtr", 0
            )
                throw OSError(A_LastError, "WinHttpSendRequest")
            if !DllCall("winhttp\WinHttpReceiveResponse", "Ptr", request, "Ptr", 0)
                throw OSError(A_LastError, "WinHttpReceiveResponse")

            status := 0
            statusSize := 4
            if !DllCall(
                "winhttp\WinHttpQueryHeaders",
                "Ptr", request,
                "UInt", WinHttpTransport.WINHTTP_QUERY_STATUS_CODE | WinHttpTransport.WINHTTP_QUERY_FLAG_NUMBER,
                "Ptr", 0,
                "UInt*", &status,
                "UInt*", &statusSize,
                "Ptr", 0
            )
                throw OSError(A_LastError, "WinHttpQueryHeaders(status)")
            if (status != 200)
                throw Error("Update download returned HTTP " status)

            contentLength := 0
            contentLengthSize := 4
            if !DllCall(
                "winhttp\WinHttpQueryHeaders",
                "Ptr", request,
                "UInt", WinHttpTransport.WINHTTP_QUERY_CONTENT_LENGTH | WinHttpTransport.WINHTTP_QUERY_FLAG_NUMBER,
                "Ptr", 0,
                "UInt*", &contentLength,
                "UInt*", &contentLengthSize,
                "Ptr", 0
            )
                throw Error("Update download did not provide a valid Content-Length")
            if (contentLength != expectedSize || contentLength > maximumSize)
                throw Error("Update download Content-Length does not match trusted metadata")

            ; -RAW: under the script's FileEncoding "UTF-8", FileOpen would otherwise
            ; put a byte-order mark before the downloaded bytes.
            output := FileOpen(destination, "w", "UTF-8-RAW")
            total := 0
            downloadBuffer := Buffer(64 * 1024)
            loop {
                available := 0
                if !DllCall(
                    "winhttp\WinHttpQueryDataAvailable",
                    "Ptr", request,
                    "UInt*", &available
                )
                    throw OSError(A_LastError, "WinHttpQueryDataAvailable")
                if !available
                    break
                readSize := Min(available, downloadBuffer.Size)
                bytesRead := 0
                if !DllCall(
                    "winhttp\WinHttpReadData",
                    "Ptr", request,
                    "Ptr", downloadBuffer.Ptr,
                    "UInt", readSize,
                    "UInt*", &bytesRead
                )
                    throw OSError(A_LastError, "WinHttpReadData")
                if !bytesRead
                    throw Error("Update download ended before its declared byte count")
                total += bytesRead
                if (total > expectedSize || total > maximumSize)
                    throw Error("Update download exceeded its trusted byte limit")
                if (output.RawWrite(downloadBuffer, bytesRead) != bytesRead)
                    throw Error("Update download could not be written completely")
            }
            output.Close()
            output := 0
            if (total != expectedSize)
                throw Error("Update download byte count does not match trusted metadata")
            completed := true
        } finally {
            if IsObject(output)
                try output.Close()
            for handle in [request, connection, session] {
                if handle
                    DllCall("winhttp\WinHttpCloseHandle", "Ptr", handle)
            }
            if !completed
                try FileDelete(destination)
        }
    }
}
