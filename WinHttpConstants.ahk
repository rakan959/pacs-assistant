; = CONTENTS
;   + Preamble
;   + WinHttpConstants class (Win32 constants, user agent and timeouts)

#Requires AutoHotkey v2.0

/**
 * WinHTTP values shared by the UI-process transport and the metadata worker
 * process. It depends on nothing, so the worker can include it alone.
 */
class WinHttpConstants {
    ; Win32 constants from winhttp.h and winerror.h, in their native spelling.
    ; Requests bypass any configured proxy (NO_PROXY), as they always have.
    static WINHTTP_ACCESS_TYPE_NO_PROXY := 1
    static WINHTTP_FLAG_SECURE := 0x00800000
    static WINHTTP_QUERY_CONTENT_LENGTH := 5
    static WINHTTP_QUERY_STATUS_CODE := 19
    static WINHTTP_QUERY_FLAG_NUMBER := 0x20000000
    static INTERNET_DEFAULT_HTTPS_PORT := 443
    static ERROR_WINHTTP_HEADER_NOT_FOUND := 12150

    static userAgent := "PACS-Assistant-Update-Checker"
    static resolveTimeoutMs := 2000
    static connectTimeoutMs := 3000
    static sendTimeoutMs := 5000
    static receiveTimeoutMs := 10000
}
