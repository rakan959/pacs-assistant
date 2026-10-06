; = CONTENTS
;   + Preamble
;   + UpdateVerificationTest class (artifact checks, release metadata, download URL,
;       metadata request, streaming and worker ownership)
;   + Test doubles (metadata process and streaming worker)

#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include TestRunner.ahk

/**
 * The trust boundary of self-update: release-metadata parsing, the download URL
 * allowlist, downloaded-artifact verification, and the transports' local guards.
 * Nothing here touches the network.
 */
class UpdateVerificationTest {
    static tests := [
        "ArtifactValidationAcceptsMatchingExecutable",
        "ArtifactValidationRejectsEachMismatch",
        "ArtifactValidationRejectsNonExecutable",
        "ArtifactValidationRejectsMzWithoutPeSignature",
        "ArtifactChecksReadALeadingByteOrderMark",
        "Sha256KnownVector",
        "ReleaseParserKeepsAssetMetadataTogether",
        "ReleaseParserAcceptsArrayResponse",
        "ReleaseParserRejectsMalformedMetadata",
        "ReleaseParserRejectsInvalidAssetFields",
        "ReleaseParserRejectsOversizedAsset",
        "ReleaseStatusDistinguishesExpectedAbsenceFromFailure",
        "DownloadUrlMustBelongToThisRepository",
        "DownloadUrlRejectsQueryFragmentAndDotSegments",
        "DownloadRejectsUntrustedArgumentsBeforeConnecting",
        "MetadataRequestRejectsInvalidConstruction",
        "MetadataRequestTimesOutOnlyPastItsBudget",
        "MetadataDeadlineClosesPendingWorkerAndReportsOnce",
        "MetadataRequestReportsWorkerErrors",
        "MetadataStartFailureCleansUpAndReportsOnce",
        "MetadataCleanupFailureKeepsTheOutcomeAndRetainsExitCleanup",
        "CancelledRequestWithAFailedReapStaysSilent",
        "AbandonedRequestDirectoriesAreSweptByNameAndAge",
        "SourceRunStartsTheWorkerScriptBesideTheRequest",
        "PendingMetadataWorkerLeavesTheScriptResponsive",
        "MetadataCompletionDeliversUtf8BodyOnce",
        "MetadataHeadersEnforceSizeAndStatusBeforeReading",
        "MetadataResponsesAreStreamBoundedBeforeParsing",
        "AsyncRequestCancelBreaksCallbackOwnership",
        "CancelledMetadataWorkerCannotDeliverLateCompletion",
        "WorkerResponseRejectsInvalidSizeAndStatus",
        "NativeWorkerCancellationReapsOnlyItsOwnedProcess",
        "NativeWorkerScriptRefusesAnUnsupportedUrl"
    ]

    ; Non-test methods the tests share (see TestRunner.UnlistedMethods).
    static helpers := [
        "CopyRunningInterpreter",
        "NewMetadataRequest",
        "Repeat",
        "TrackTemp",
        "WriteRawFile"
    ]

    Setup() {
        this.tempPaths := []
    }

    Teardown() {
        for path in this.tempPaths {
            if FileExist(path)
                FileDelete(path)
        }
    }

    ArtifactValidationAcceptsMatchingExecutable() {
        artifact := this.CopyRunningInterpreter()

        Assert.True(UpdateChecker.ValidateDownloadedArtifact(
            artifact.path,
            artifact.size,
            artifact.sha256,
            artifact.version
        ))
    }

    ArtifactValidationRejectsEachMismatch() {
        artifact := this.CopyRunningInterpreter()
        wrongDigest := (SubStr(artifact.sha256, 1, 1) = "0" ? "1" : "0") SubStr(artifact.sha256, 2)
        parsed := UpdateChecker.ParseVersion(artifact.version)
        wrongMajor := "v" (parsed.major + 1) "." parsed.minor "." parsed.patch
        wrongMinor := "v" parsed.major "." (parsed.minor + 1) "." parsed.patch
        wrongPatch := "v" parsed.major "." parsed.minor "." (parsed.patch + 1)

        cases := [
            {label: "size", size: artifact.size + 1, digest: artifact.sha256, version: artifact.version},
            {label: "zero size", size: 0, digest: artifact.sha256, version: artifact.version},
            {label: "digest", size: artifact.size, digest: wrongDigest, version: artifact.version},
            {label: "prefixed digest", size: artifact.size, digest: "sha256:" artifact.sha256, version: artifact.version},
            {label: "short digest", size: artifact.size, digest: SubStr(artifact.sha256, 2), version: artifact.version},
            {label: "major version", size: artifact.size, digest: artifact.sha256, version: wrongMajor},
            {label: "minor version", size: artifact.size, digest: artifact.sha256, version: wrongMinor},
            {label: "patch version", size: artifact.size, digest: artifact.sha256, version: wrongPatch}
        ]
        for testCase in cases {
            Assert.False(
                UpdateChecker.ValidateDownloadedArtifact(artifact.path, testCase.size, testCase.digest, testCase.version),
                "Artifact with a mismatched " testCase.label " was accepted"
            )
        }
        Assert.False(UpdateChecker.ValidateDownloadedArtifact(
            artifact.path "-missing",
            artifact.size,
            artifact.sha256,
            artifact.version
        ))
    }

    ArtifactValidationRejectsMzWithoutPeSignature() {
        ; A 128-byte file with an MZ header whose e_lfanew points at bytes that are
        ; not "PE\0\0", and a second whose e_lfanew points past the end of the file.
        for peOffset in [64, 4096] {
            image := Buffer(128, 0)
            NumPut("UShort", 0x5A4D, image, 0)
            NumPut("UInt", peOffset, image, 0x3C)
            path := this.TrackTemp(TestTempPath("pacs-mz-only", ".exe"))
            this.WriteRawFile(path, image)

            Assert.False(UpdateChecker.IsPortableExecutable(path), "MZ image with e_lfanew " peOffset " was accepted")
        }
    }

    ArtifactChecksReadALeadingByteOrderMark() {
        ; FileOpen skips a leading UTF-8 byte-order mark when reading. The digest
        ; must cover it, and a file that starts with one is not an executable even
        ; when the bytes after it are laid out as one at their absolute offsets.
        bom := Buffer(4)
        NumPut("UChar", 0xEF, "UChar", 0xBB, "UChar", 0xBF, "UChar", 0x41, bom)
        path := this.TrackTemp(TestTempPath("pacs-bom", ".bin"))
        this.WriteRawFile(path, bom)
        Assert.Equal(
            "4d91bc408f19af2e9483a216ae71673e0ee456ece7a12998dd207e504f4f19a6",
            UpdateChecker.HashFileSha256(path)
        )

        image := Buffer(128, 0)
        NumPut("UChar", 0xEF, "UChar", 0xBB, "UChar", 0xBF, image, 0)
        NumPut("UShort", 0x5A4D, image, 3)
        NumPut("UInt", 68, image, 0x3C)
        NumPut("UInt", 0x00004550, image, 68)
        path := this.TrackTemp(TestTempPath("pacs-bom-mz", ".exe"))
        this.WriteRawFile(path, image)
        Assert.False(UpdateChecker.IsPortableExecutable(path))
    }

    ReleaseParserRejectsMalformedMetadata() {
        validAsset := '{"name":"pacs-assistant.exe","size":1550000,'
            . '"digest":"sha256:' this.Repeat("b", 64) '",'
            . '"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v9.0.0/pacs-assistant.exe"}'
        cases := [
            {json: "[]", error: "empty release list"},
            {json: '{"prerelease":false,"assets":[' validAsset ']}', error: "missing tag_name"},
            {json: '{"tag_name":7,"prerelease":false,"assets":[' validAsset ']}', error: "missing tag_name"},
            {json: '{"tag_name":"v9.0.0","assets":[' validAsset ']}', error: "prerelease flag"},
            {json: '{"tag_name":"v9.0.0","prerelease":null,"assets":[' validAsset ']}', error: "prerelease flag"},
            {json: '{"tag_name":"v9.0.0","prerelease":2,"assets":[' validAsset ']}', error: "prerelease flag"},
            {json: '{"tag_name":"v9.0.0","prerelease":false}', error: "missing assets"},
            {json: '{"tag_name":"v9.0.0","prerelease":false,"assets":{}}', error: "missing assets"},
            {json: '{"tag_name":"v9.0.0","prerelease":false,"assets":[{"name":"notes.txt"}]}', error: "does not contain pacs-assistant.exe"}
        ]
        for testCase in cases {
            Assert.Throws(
                ObjBindMethod(UpdateChecker, "ParseReleaseResponse", testCase.json),
                testCase.error,
                "Malformed release metadata was not rejected: " testCase.json
            )
        }
    }

    ReleaseParserRejectsInvalidAssetFields() {
        url := '"https://github.com/rakan959/pacs-assistant/releases/download/v9.0.0/pacs-assistant.exe"'
        digest := '"sha256:' this.Repeat("b", 64) '"'
        cases := [
            {asset: '"size":1,"digest":' digest, error: "missing browser_download_url"},
            {asset: '"size":1,"browser_download_url":' url, error: "missing digest"},
            {asset: '"digest":' digest ',"browser_download_url":' url, error: "missing size"},
            {asset: '"size":1,"digest":"sha512:' this.Repeat("b", 128) '","browser_download_url":' url, error: "SHA-256 digest"},
            {asset: '"size":1,"digest":"sha256:' this.Repeat("g", 64) '","browser_download_url":' url, error: "SHA-256 digest"},
            {asset: '"size":0,"digest":' digest ',"browser_download_url":' url, error: "invalid size"},
            {asset: '"size":1.5,"digest":' digest ',"browser_download_url":' url, error: "invalid size"},
            {asset: '"size":"1","digest":' digest ',"browser_download_url":' url, error: "invalid size"},
            {asset: '"size":1,"digest":' digest ',"browser_download_url":"https://example.com/pacs-assistant.exe"', error: "untrusted download URL"}
        ]
        for testCase in cases {
            json := '{"tag_name":"v9.0.0","prerelease":false,"assets":[{"name":"pacs-assistant.exe",' testCase.asset '}]}'
            Assert.Throws(
                ObjBindMethod(UpdateChecker, "ParseReleaseResponse", json),
                testCase.error,
                "Invalid asset was not rejected: " testCase.asset
            )
        }
    }

    DownloadUrlRejectsQueryFragmentAndDotSegments() {
        prefix := "https://github.com/rakan959/pacs-assistant/releases/download/"
        Assert.True(UpdateChecker.IsTrustedDownloadUrl(prefix "v2.2.0-beta.1%2Bbuild.5/pacs-assistant.exe"))
        for rejected in [
            prefix "v2.2.0/pacs-assistant.exe?x=1",
            prefix "v2.2.0/pacs-assistant.exe#fragment",
            prefix "../pacs-assistant.exe",
            prefix "./pacs-assistant.exe",
            prefix "%2e%2e/pacs-assistant.exe",
            prefix "v2.2.0/extra/pacs-assistant.exe",
            prefix "/pacs-assistant.exe",
            "https://github.com.evil.example/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe",
            42
        ] {
            Assert.False(UpdateChecker.IsTrustedDownloadUrl(rejected), "Untrusted download URL accepted: " String(rejected))
        }
    }

    DownloadRejectsUntrustedArgumentsBeforeConnecting() {
        transport := WinHttpTransport()
        destination := this.TrackTemp(TestTempPath("pacs-download-guard", ".exe"))
        url := "https://github.com/rakan959/pacs-assistant/releases/download/v9.0.0/pacs-assistant.exe"
        for expectedSize in [0, -1, 1.5, "10", 101] {
            Assert.Throws(
                ObjBindMethod(transport, "Download", url, destination, expectedSize, 100),
                "outside the allowed range"
            )
        }
        Assert.Throws(
            ObjBindMethod(transport, "Download", "https://example.com/pacs-assistant.exe", destination, 10, 100),
            "not a supported HTTPS GitHub URL"
        )
        Assert.Throws(
            ObjBindMethod(transport, "Download", "http://github.com/x", destination, 10, 100),
            "not a supported HTTPS GitHub URL"
        )
        Assert.False(FileExist(destination), "A rejected download must not create its destination")
    }

    MetadataRequestRejectsInvalidConstruction() {
        Assert.Throws(
            () => WinHttpTextRequest("https://github.com/rakan959/pacs-assistant", (*) => 0, (*) => 0, 10),
            "not a supported GitHub API URL"
        )
        Assert.Throws(
            () => WinHttpTextRequest(42, (*) => 0, (*) => 0, 10),
            "not a supported GitHub API URL"
        )
        for maximumSize in [0, -5, 1.5, "10"] {
            Assert.Throws(
                ObjBindMethod(this, "NewMetadataRequest", maximumSize),
                "positive metadata response limit"
            )
        }
    }

    MetadataRequestTimesOutOnlyPastItsBudget() {
        budget := WinHttpConstants.resolveTimeoutMs
            + WinHttpConstants.connectTimeoutMs
            + WinHttpConstants.sendTimeoutMs
            + WinHttpConstants.receiveTimeoutMs
            + 2000
        request := RecordingMetadataRequest()
        request.state := "sending"
        request.startedAt := 1000

        request.now := 1000 + budget
        request.CheckTimeout()
        Assert.Equal(0, request.failures.Length, "A request at exactly its budget must not time out")

        request.now := 1000 + budget + 1
        request.CheckTimeout()
        Assert.Equal(1, request.failures.Length)
        Assert.True(InStr(request.failures[1].Message, "timed out"), request.failures[1].Message)

        request.state := "closing"
        request.CheckTimeout()
        Assert.Equal(1, request.failures.Length, "A closing request must not fail again")
    }

    MetadataRequestReportsWorkerErrors() {
        failed := []
        request := WinHttpTextRequest("https://api.github.com/test", (*) => ThrowError("unexpected success"), (err) => failed.Push(err), 16)
        request.worker := FakeMetadataWorkerProcess(200, "", 10)
        Assert.True(IsObject(request.Start()))
        request.Poll()
        Assert.Equal(1, failed.Length)
        Assert.True(InStr(failed[1].Message, "simulated worker failure"))
        Assert.Equal("closed", request.state)
        Assert.True(request.worker.closed)
    }

    MetadataStartFailureCleansUpAndReportsOnce() {
        failures := []
        request := WinHttpTextRequest("https://api.github.com/test", (*) => ThrowError("unexpected success"), (err) => failures.Push(err), 16)
        request.worker := FailingStartMetadataProcess()
        Assert.False(request.Start())
        Assert.Equal(1, failures.Length)
        Assert.Equal("closed", request.state)
        Assert.Equal("", request.directory)
        Assert.Equal(0, request.exitCallback)
        Assert.True(request.worker.closed)
    }

    ; A failed reap is a resource fault, retried at exit. It must not turn a
    ; delivered response into a failure.
    MetadataCleanupFailureKeepsTheOutcomeAndRetainsExitCleanup() {
        received := []
        failures := []
        request := WinHttpTextRequest("https://api.github.com/test", (response) => received.Push(response), (err) => failures.Push(err), 16)
        request.worker := FailingCloseMetadataProcess(200, "{}")
        capturedLog := LogCapture()
        try {
            Assert.True(IsObject(request.Start()))
            request.Poll()
            Assert.Equal(1, received.Length)
            Assert.Equal("{}", received[1].body)
            Assert.Equal(0, failures.Length)
            Assert.Equal(1, capturedLog.Count("Metadata worker cleanup failed"))
            Assert.Equal("closed", request.state)
            Assert.True(IsObject(request.exitCallback))
            Assert.True(DirExist(request.directory))
        } finally {
            request.Cancel()
            capturedLog.Restore()
        }
        Assert.True(request.worker.closed)
        Assert.Equal("", request.directory)
        Assert.Equal(0, request.exitCallback)
    }

    CancelledRequestWithAFailedReapStaysSilent() {
        received := []
        failures := []
        request := WinHttpTextRequest("https://api.github.com/test", (response) => received.Push(response), (err) => failures.Push(err), 16)
        request.worker := FailingCloseMetadataProcess()
        request.worker.finished := false
        capturedLog := LogCapture()
        try {
            Assert.True(IsObject(request.Start()))
            request.Cancel()
            Assert.Equal("closed", request.state)
            Assert.Equal(0, received.Length)
            Assert.Equal(0, failures.Length, "A cancelled request must never call back")
            Assert.True(IsObject(request.exitCallback), "The failed reap must be retried at exit")
        } finally {
            request.Cancel()
            capturedLog.Restore()
        }
        Assert.True(request.worker.closed)
        Assert.Equal(0, request.exitCallback)
        Assert.Equal(0, failures.Length)
    }

    AbandonedRequestDirectoriesAreSweptByNameAndAge() {
        root := TestTempPath("pacs-metadata-sweep")
        stale := root "\pacs-metadata-" this.Repeat("a", 32)
        fresh := root "\pacs-metadata-" this.Repeat("b", 32)
        withUnknownFile := root "\pacs-metadata-" this.Repeat("c", 32)
        otherName := root "\pacs-metadata-notarequest"
        capturedLog := LogCapture()
        try {
            for directory in [stale, fresh, withUnknownFile, otherName] {
                DirCreate(directory)
                IniWrite(16, directory "\request.ini", "Request", "MaximumSize")
            }
            FileAppend("partial", stale "\response.bin", "UTF-8-RAW")
            FileAppend("not a request file", withUnknownFile "\notes.txt", "UTF-8")
            twoHoursAgo := DateAdd(A_Now, -2, "Hours")
            for directory in [stale, withUnknownFile, otherName]
                FileSetTime(twoHoursAgo, directory, "M", "D")

            WinHttpTextRequest.SweepAbandonedDirectories(root)

            Assert.False(DirExist(stale), "An hour-old request directory must be removed")
            Assert.True(DirExist(fresh), "A recent request directory may belong to a live request")
            Assert.True(DirExist(withUnknownFile), "A directory holding other files must be kept")
            Assert.True(FileExist(withUnknownFile "\notes.txt") != "")
            Assert.True(DirExist(otherName), "Only request-shaped names are swept")
            Assert.Equal(1, capturedLog.Count("abandoned metadata request directory could not be removed"))
        } finally {
            capturedLog.Restore()
            DirDelete(root, true)
        }
    }

    SourceRunStartsTheWorkerScriptBesideTheRequest() {
        request := WinHttpTextRequest("https://api.github.com/test", (*) => 0, (*) => 0, 16)
        request.directory := A_Temp "\pacs-metadata-" this.Repeat("d", 32)
        arguments := request.WorkerArguments()
        Assert.True(RegExMatch(arguments, '^/script /ErrorStdOut "([^"]+)" "([^"]+)"$', &parts), arguments)
        SplitPath(parts[1], &scriptName)
        Assert.Equal("WinHttpMetadataWorkerMain.ahk", scriptName)
        Assert.True(FileExist(parts[1]) != "", parts[1])
        Assert.Equal(request.directory, parts[2])
    }

    PendingMetadataWorkerLeavesTheScriptResponsive() {
        request := WinHttpTextRequest("https://api.github.com/test", (*) => ThrowError("unexpected completion"), (*) => ThrowError("unexpected failure"), 16)
        request.worker := FakeMetadataWorkerProcess()
        request.worker.finished := false
        Assert.True(IsObject(request.Start()))
        try {
            request.Poll()
            Assert.Equal("sending", request.state)
            Assert.False(request.worker.closed)
        } finally request.Cancel()
        Assert.True(request.worker.closed)
        Assert.Equal("closed", request.state)
    }

    MetadataDeadlineClosesPendingWorkerAndReportsOnce() {
        failures := []
        request := ClockMetadataRequest("https://api.github.com/test", (*) => ThrowError("unexpected completion"), (err) => failures.Push(err), 16)
        request.worker := FakeMetadataWorkerProcess()
        request.worker.finished := false
        Assert.True(IsObject(request.Start()))
        try {
            request.now := WinHttpConstants.resolveTimeoutMs + WinHttpConstants.connectTimeoutMs
                + WinHttpConstants.sendTimeoutMs + WinHttpConstants.receiveTimeoutMs + 2000
            request.Poll()
            Assert.Equal("sending", request.state)
            Assert.False(request.worker.closed)
            request.now++
            request.Poll()
            request.Poll()
            Assert.Equal(1, failures.Length)
            Assert.True(InStr(failures[1].Message, "timed out"))
            Assert.Equal("closed", request.state)
            Assert.True(request.worker.closed)
            Assert.Equal("", request.directory)
            Assert.Equal(0, request.exitCallback)
            Assert.Equal(0, request.timeoutTimer)
        } finally request.Cancel()
    }

    MetadataCompletionDeliversUtf8BodyOnce() {
        received := []
        failed := []
        text := '{"body":"' Chr(0x2192) '"}'
        request := WinHttpTextRequest("https://api.github.com/test", (response) => received.Push(response), (err) => failed.Push(err), 64)
        request.worker := FakeMetadataWorkerProcess(200, text)
        Assert.True(IsObject(request.Start()))
        request.Poll()
        request.Poll()
        request.Finalize()
        Assert.Equal(0, failed.Length)
        Assert.Equal(1, received.Length)
        Assert.Equal(200, received[1].status)
        Assert.Equal(text, received[1].body)
        Assert.Equal("closed", request.state)
        Assert.Equal("", request.directory)
        Assert.True(request.worker.closed)
        Assert.Equal(0, request.onComplete)
        Assert.Equal(0, request.onError)
    }

    MetadataHeadersEnforceSizeAndStatusBeforeReading() {
        for testCase in [
            {status: 200, length: 16, hasLength: true, reads: 1, fails: false},
            {status: 200, length: 17, hasLength: true, reads: 0, fails: true},
            {status: 200, length: 99, hasLength: false, reads: 1, fails: false},
            {status: 404, length: 0, hasLength: true, reads: 0, fails: false}
        ] {
            worker := HeaderMetadataWorker(testCase)
            if testCase.fails
                Assert.Throws(() => worker.ReadResponse(), "exceeded its byte limit")
            else {
                response := worker.ReadResponse()
                Assert.Equal(testCase.status, response.status)
                Assert.Equal("", response.body)
            }
            Assert.Equal(testCase.reads, worker.reads)
        }
    }

    NativeWorkerCancellationReapsOnlyItsOwnedProcess() {
        script := this.TrackTemp(TestTempPath("pacs-worker-cancel", ".ahk"))
        FileAppend("#Requires AutoHotkey v2.0`n#SingleInstance Off`n#ErrorStdOut`nSleep(30000)`nExitApp()`n", script, "UTF-8")
        worker := WinHttpWorkerProcess()
        try {
            worker.Start('/script /ErrorStdOut "' script '"', A_Temp)
            Assert.False(worker.IsFinished())
        } finally worker.Close()
        Assert.Equal(0, worker.process)
        Assert.Equal(0, worker.job)
        Assert.True(worker.IsFinished())
    }

    ; Runs the real worker script in its own process, network-free: the URL is
    ; refused before any connection, and the refusal comes back through error.txt.
    NativeWorkerScriptRefusesAnUnsupportedUrl() {
        name := ""
        loop 32
            name .= Format("{:x}", Random(0, 15))
        directory := A_Temp "\pacs-metadata-" name
        DirCreate(directory)
        worker := WinHttpWorkerProcess()
        try {
            IniWrite("https://example.invalid/", directory "\request.ini", "Request", "Url")
            IniWrite(16, directory "\request.ini", "Request", "MaximumSize")
            request := WinHttpTextRequest("https://api.github.com/test", (*) => 0, (*) => 0, 16)
            request.directory := directory
            worker.Start(request.WorkerArguments(), directory)
            Assert.Equal(0, DllCall("WaitForSingleObject", "Ptr", worker.process, "UInt", 15000, "UInt"),
                "The worker must exit on its own")
            Assert.Equal(10, worker.ExitCode())
            Assert.True(InStr(FileRead(directory "\error.txt", "UTF-8"), "Unsupported update metadata URL"))
            Assert.False(FileExist(directory "\response.bin"))
        } finally {
            worker.Close()
            DirDelete(directory, true)
        }
    }

    ReleaseParserKeepsAssetMetadataTogether() {
        json := '{"tag_name":"v2.2.0","prerelease":false,"body":"Line 1\nLine 2","assets":['
            . '{"name":"notes.txt","size":12,"digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/notes.txt"},'
            . '{"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe","digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","size":1550000,"name":"pacs-assistant.exe"}'
            . ']}'

        release := UpdateChecker.ParseReleaseResponse(json)

        Assert.Equal("v2.2.0", release.version)
        Assert.Equal("Line 1`nLine 2", release.notes)
        Assert.Equal(1550000, release.assetSize)
        Assert.Equal("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", release.assetSha256)
        Assert.True(InStr(release.downloadUrl, "/pacs-assistant.exe") > 0)
    }

    ReleaseParserAcceptsArrayResponse() {
        json := '[{"tag_name":"v2.2.0-beta.1","prerelease":true,"body":"Beta","assets":['
            . '{"name":"pacs-assistant.exe","size":42,"digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0-beta.1/pacs-assistant.exe"}'
            . ']}]'

        release := UpdateChecker.ParseReleaseResponse(json)
        Assert.Equal("v2.2.0-beta.1", release.version)
        Assert.Equal(42, release.assetSize)
    }

    ReleaseParserRejectsOversizedAsset() {
        size := UpdateChecker.maxUpdateSizeBytes + 1
        json := '{"tag_name":"v9.0.0","prerelease":false,"body":"Large","assets":['
            . '{"name":"pacs-assistant.exe","size":' size
            . ',"digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"'
            . ',"browser_download_url":"https://github.com/rakan959/pacs-assistant/releases/download/v9.0.0/pacs-assistant.exe"}'
            . ']}'

        Assert.Throws(
            (*) => UpdateChecker.ParseReleaseResponse(json),
            "invalid size"
        )
    }

    ReleaseStatusDistinguishesExpectedAbsenceFromFailure() {
        Assert.True(UpdateChecker.ReleaseResponseAvailable(200, true))
        Assert.False(UpdateChecker.ReleaseResponseAvailable(404, true))
        Assert.Throws(
            () => UpdateChecker.ReleaseResponseAvailable(403, true),
            "HTTP 403"
        )
        Assert.Throws(
            () => UpdateChecker.ReleaseResponseAvailable(503, false),
            "HTTP 503"
        )
        Assert.Throws(
            () => UpdateChecker.ReleaseResponseAvailable(404, false),
            "HTTP 404"
        )
    }

    DownloadUrlMustBelongToThisRepository() {
        Assert.True(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "http://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/attacker/pacs-assistant/releases/download/v2.2.0/pacs-assistant.exe"
        ))
        Assert.False(UpdateChecker.IsTrustedDownloadUrl(
            "https://github.com/rakan959/pacs-assistant/releases/download/v2.2.0/other.exe"
        ))
    }

    Sha256KnownVector() {
        path := TestTempPath("pacs-sha256", ".txt")
        FileAppend("abc", path, "UTF-8-RAW")
        try {
            Assert.Equal(
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                UpdateChecker.HashFileSha256(path)
            )
        } finally {
            try FileDelete(path)
        }
    }

    ArtifactValidationRejectsNonExecutable() {
        path := TestTempPath("pacs-bad-update", ".exe")
        FileAppend("not an executable", path, "UTF-8-RAW")
        try {
            digest := UpdateChecker.HashFileSha256(path)
            Assert.False(UpdateChecker.ValidateDownloadedArtifact(path, FileGetSize(path), digest, "v2.2.0"))
        } finally {
            try FileDelete(path)
        }
    }

    AsyncRequestCancelBreaksCallbackOwnership() {
        operation := WinHttpTextRequest(
            "https://api.github.com/test",
            (*) => 0,
            (*) => 0,
            UpdateChecker.maxMetadataSizeBytes
        )

        operation.Cancel()

        Assert.Equal("closed", operation.state)
        Assert.Equal(0, operation.onComplete)
        Assert.Equal(0, operation.onError)
    }

    CancelledMetadataWorkerCannotDeliverLateCompletion() {
        received := []
        failed := []
        request := WinHttpTextRequest("https://api.github.com/test", (value) => received.Push(value), (err) => failed.Push(err), 16)
        request.worker := FakeMetadataWorkerProcess(200, "late response")
        request.worker.finished := false
        Assert.True(IsObject(request.Start()))
        request.Cancel()
        request.worker.finished := true
        request.Poll()
        Assert.Equal(0, received.Length)
        Assert.Equal(0, failed.Length)
        Assert.True(request.worker.closed)
        Assert.Equal("", request.directory)
    }

    WorkerResponseRejectsInvalidSizeAndStatus() {
        for entry in [{status: 200, body: "too many response bytes"}, {status: 99, body: ""}, {status: 404, body: "unexpected"}] {
            failures := []
            request := WinHttpTextRequest("https://api.github.com/test", (*) => ThrowError("unexpected success"), (err) => failures.Push(err), 16)
            request.worker := FakeMetadataWorkerProcess(entry.status, entry.body)
            Assert.True(IsObject(request.Start()))
            request.Poll()
            Assert.Equal(1, failures.Length)
            Assert.Equal("closed", request.state)
            Assert.Equal("", request.directory)
        }
    }

    MetadataResponsesAreStreamBoundedBeforeParsing() {
        operation := WinHttpMetadataWorker(5, [2000, 3000, 5000, 10000])
        firstChunk := Buffer(4)
        NumPut("UInt", 0x64636261, firstChunk)
        operation.ConsumeReadChunk(firstChunk.Ptr, firstChunk.Size)

        Assert.Equal(4, operation.totalBytes)
        Assert.Equal(5, operation.bodyBuffer.Size)

        secondChunk := Buffer(2)
        Assert.Throws(
            () => operation.ConsumeReadChunk(secondChunk.Ptr, secondChunk.Size),
            "exceeded its byte limit"
        )
        Assert.Equal(4, operation.totalBytes)
    }

    NewMetadataRequest(maximumSize) {
        return WinHttpTextRequest("https://api.github.com/test", (*) => 0, (*) => 0, maximumSize)
    }

    ; A copy of the running interpreter is a real signed PE whose file version is
    ; known, which exercises the accept path without shipping a binary fixture.
    CopyRunningInterpreter() {
        path := this.TrackTemp(TestTempPath("pacs-valid-update", ".exe"))
        FileCopy(A_AhkPath, path)
        return {
            path: path,
            size: FileGetSize(path),
            sha256: UpdateChecker.HashFileSha256(path),
            version: "v" FileGetVersion(path)
        }
    }

    TrackTemp(path) {
        this.tempPaths.Push(path)
        return path
    }

    ; Writes the bytes exactly. Under the suite's FileEncoding "UTF-8", FileOpen
    ; without a -RAW encoding puts a byte-order mark before them.
    WriteRawFile(path, bytes) {
        fileHandle := FileOpen(path, "w", "UTF-8-RAW")
        fileHandle.RawWrite(bytes)
        fileHandle.Close()
    }

    Repeat(text, count) {
        result := ""
        loop count
            result .= text
        return result
    }
}

class RecordingMetadataRequest extends WinHttpTextRequest {
    __New() {
        super.__New("https://api.github.com/test", (*) => 0, (*) => 0, 16)
        this.now := 0
        this.failures := []
    }

    NowMilliseconds() {
        return this.now
    }

    Fail(err) {
        this.failures.Push(err)
    }

}

class ClockMetadataRequest extends WinHttpTextRequest {
    now := 0
    NowMilliseconds() => this.now
}

class FakeMetadataWorkerProcess {
    __New(status := 200, body := "", code := 0) {
        this.status := status
        this.body := body
        this.code := code
        this.finished := true
        this.closed := false
    }

    Start(arguments, directory) {
        if this.code {
            FileAppend("simulated worker failure", directory "\error.txt", "UTF-8")
            return
        }
        output := FileOpen(directory "\response.bin", "w", "UTF-8-RAW")
        try {
            output.WriteUInt(this.status)
            output.Write(this.body)
        } finally output.Close()
    }

    IsFinished() => this.finished
    ExitCode() => this.code
    Close() {
        this.closed := true
    }
}

class HeaderMetadataWorker extends WinHttpMetadataWorker {
    __New(headers) {
        super.__New(16, [2000, 3000, 5000, 10000])
        this.headers := headers
        this.reads := 0
    }

    ReadResponseHeaders() {
        return {status: this.headers.status, contentLength: this.headers.length, hasContentLength: this.headers.hasLength}
    }

    ReadChunk() {
        this.reads++
        return 0
    }
}

class FailingStartMetadataProcess extends FakeMetadataWorkerProcess {
    Start(*) {
        throw Error("simulated launch failure")
    }
}

class FailingCloseMetadataProcess extends FakeMetadataWorkerProcess {
    Close() {
        if !HasProp(this, "closeFailed") {
            this.closeFailed := true
            throw Error("simulated reap failure")
        }
        super.Close()
    }
}
