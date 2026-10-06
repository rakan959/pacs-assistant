; = CONTENTS
;   + Preamble (update-metadata worker process entry point)

; A compiled build embeds this script as the WINHTTPMETADATAWORKER resource
; (WinHttpTextRequest.ahk) and runs it with /script *WINHTTPMETADATAWORKER, so no
; script file is written at run time; a source run starts this file directly. Its
; one argument is the request directory that holds request.ini.

#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#ErrorStdOut
#Warn All, StdOut
FileEncoding "UTF-8"
OnError((*) => ExitApp(10))

#Include WinHttpMetadataWorker.ahk

WinHttpMetadataWorker.Main(A_Args)
