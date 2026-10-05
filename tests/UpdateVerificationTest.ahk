#Requires AutoHotkey v2.0
#Include ../UpdateChecker.ahk
#Include TestRunner.ahk

/**
 * The trust boundary of self-update: release-metadata parsing, the download URL
 * allowlist, downloaded-artifact verification, and the transport's local guards.
 * Nothing here touches the network.
 */
class UpdateVerificationTest {
    static tests := [
        "ArtifactValidationAcceptsMatchingExecutable",
        "ArtifactValidationRejectsEachMismatch",
        "ArtifactValidationRejectsMzWithoutPeSignature",
        "ReleaseParserRejectsMalformedMetadata",
        "ReleaseParserRejectsInvalidAssetFields",
        "DownloadUrlRejectsQueryFragmentAndDotSegments",
        "DownloadRejectsUntrustedArgumentsBeforeConnecting",
        "MetadataRequestRejectsInvalidConstruction",
        "MetadataRequestTimesOutOnlyPastItsBudget",
        "MetadataRequestReportsAsyncWinHttpErrors"
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
        wrongVersion := "v" parsed.major "." parsed.minor "." (parsed.patch + 1)

        cases := [
            {label: "size", size: artifact.size + 1, digest: artifact.sha256, version: artifact.version},
            {label: "zero size", size: 0, digest: artifact.sha256, version: artifact.version},
            {label: "digest", size: artifact.size, digest: wrongDigest, version: artifact.version},
            {label: "prefixed digest", size: artifact.size, digest: "sha256:" artifact.sha256, version: artifact.version},
            {label: "short digest", size: artifact.size, digest: SubStr(artifact.sha256, 2), version: artifact.version},
            {label: "version", size: artifact.size, digest: artifact.sha256, version: wrongVersion}
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
            fileHandle := FileOpen(path, "w")
            fileHandle.RawWrite(image)
            fileHandle.Close()

            Assert.False(UpdateChecker.IsPortableExecutable(path), "MZ image with e_lfanew " peOffset " was accepted")
        }
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
        budget := WinHttpTransport.resolveTimeoutMs
            + WinHttpTransport.connectTimeoutMs
            + WinHttpTransport.sendTimeoutMs
            + WinHttpTransport.receiveTimeoutMs
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

    MetadataRequestReportsAsyncWinHttpErrors() {
        request := RecordingMetadataRequest()
        request.state := "receiving"
        asyncResult := Buffer(A_PtrSize + 4, 0)
        NumPut("UInt", 12002, asyncResult, A_PtrSize)

        request.HandleNativeStatus(0, 0x00200000, asyncResult.Ptr, asyncResult.Size)
        request.HandleNativeStatus(0, 0x00200000, 0, 0)

        Assert.Equal(2, request.scheduled.Length)
        Assert.Equal("Fail", request.scheduled[1].method)
        Assert.True(request.scheduled[1].params[1] is OSError, "A WinHTTP error code must surface as OSError")
        Assert.Equal(12002, request.scheduled[1].params[1].Number)
        Assert.Equal("Fail", request.scheduled[2].method)
        Assert.True(InStr(request.scheduled[2].params[1].Message, "asynchronous request failed"))
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
        this.scheduled := []
    }

    NowMilliseconds() {
        return this.now
    }

    Fail(err) {
        this.failures.Push(err)
    }

    Schedule(methodName, params*) {
        this.scheduled.Push({method: methodName, params: params})
    }
}
