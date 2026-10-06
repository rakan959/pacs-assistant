[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github/workflows/ahk2exe.yml') -Raw -Encoding utf8
$publishStep = $workflow.Substring($workflow.IndexOf('      - name: Publish release'))
$runStart = $publishStep.IndexOf("        run: |")
if ($runStart -lt 0) { throw 'The release workflow has no publication script.' }
$code = ($publishStep.Substring($runStart) -split "`n", 2)[1] -replace '(?m)^          ', ''
$publication = [scriptblock]::Create($code)

function Assert-ReleaseFixture {
    param([bool] $Condition, [string] $Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-ReleaseFixture {
    param([string] $Case)

    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('pacs-release-workflow-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $fixture)
    $oldEnvironment = @{}
    foreach ($key in @('GITHUB_REPOSITORY', 'RELEASE_TAG', 'EXPECTED_COMMIT')) {
        $oldEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
    }
    $fixtureState = @{
        Case = $Case
        Calls = [Collections.Generic.List[object]]::new()
        TagReads = 0
        ListReads = 0
        Published = $false
        Deleted = $false
        RequestFiles = [Collections.Generic.List[string]]::new()
    }
    try {
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts') -Destination (Join-Path $fixture 'scripts') -Recurse
        $assetRoot = Join-Path $fixture 'release'
        [void](New-Item -ItemType Directory -Path (Join-Path $assetRoot 'licenses'))
        $remoteAssets = @()
        foreach ($name in @('pacs-assistant.exe', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'licenses/AutoHotkey-v2.0.26.txt', 'AutoHotkey-v2.0.26-source.zip')) {
            $path = Join-Path $assetRoot $name
            [IO.File]::WriteAllBytes($path, [byte[]]@(0, 128, 255, 13, 10))
            $remoteAssets += [pscustomobject]@{
                name = [IO.Path]::GetFileName($path)
                size = (Get-Item -LiteralPath $path).Length
                digest = 'sha256:' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        $env:GITHUB_REPOSITORY = 'fixture/pacs-assistant'
        $env:RELEASE_TAG = if ($Case -eq 'prerelease') { 'v2.3.4-beta.1' } else { 'v2.3.4' }
        $env:EXPECTED_COMMIT = '0123456789abcdef0123456789abcdef01234567'
        $releaseObject = [pscustomobject]@{
            id = 321
            draft = $true
            prerelease = ($Case -eq 'prerelease')
            tag_name = $env:RELEASE_TAG
            name = $env:RELEASE_TAG
            author = [pscustomobject]@{ login = 'github-actions[bot]' }
            assets = @()
        }

        # Only the external CLI boundary is substituted. The workflow and all
        # release validators execute unchanged against synthetic binary assets.
        function gh {
            $arguments = @($args)
            if ($arguments[0] -ne 'api') { throw 'Release mutations must use the ID-addressed API.' }
            $methodIndex = [array]::IndexOf($arguments, '--method')
            $method = $arguments[$methodIndex + 1]
            $endpoint = @($arguments | Where-Object { $_ -match '^(?:https://uploads\.github\.com/)?repos/' })[0]
            $inputIndex = [array]::IndexOf($arguments, '--input')
            $body = $null
            $inputPath = ''
            if ($inputIndex -ge 0) {
                $inputPath = $arguments[$inputIndex + 1]
                if ($arguments -contains 'Content-Type: application/json') {
                    $body = Get-Content -LiteralPath $inputPath -Raw -Encoding utf8 | ConvertFrom-Json
                    $fixtureState.RequestFiles.Add($inputPath)
                } else {
                    Assert-ReleaseFixture ($arguments -contains 'Content-Type: application/octet-stream') 'Uploads must name the binary content type.'
                    Assert-ReleaseFixture ([Convert]::ToHexString([IO.File]::ReadAllBytes($inputPath)) -eq '0080FF0D0A') 'Upload input must preserve the exact binary bytes.'
                }
            }
            $fixtureState.Calls.Add([pscustomobject]@{ Method = $method; Endpoint = $endpoint; Body = $body; InputPath = $inputPath })
            $global:LASTEXITCODE = 0
            if ($endpoint -match '/git/ref/tags/') {
                $fixtureState.TagReads++
                $sha = if ($Case -eq 'moved-tag' -and $fixtureState.TagReads -gt 1) { 'ffffffffffffffffffffffffffffffffffffffff' } else { $env:EXPECTED_COMMIT }
                return (@{ object = @{ type = 'commit'; sha = $sha } } | ConvertTo-Json -Depth 5 -Compress)
            }
            if ($method -eq 'GET' -and $endpoint -match '/releases\?per_page=100$') {
                $fixtureState.ListReads++
                if ($Case -eq 'existing') {
                    $releaseObject.draft = $false
                    $releaseObject.assets = $remoteAssets
                    return '[[' + ($releaseObject | ConvertTo-Json -Depth 5 -Compress) + ']]'
                }
                # A second tag lookup would pick an unrelated same-tag object.
                if ($fixtureState.ListReads -gt 1) { throw 'The workflow rediscovered a created release by tag.' }
                return '[[]]'
            }
            if ($method -eq 'POST' -and $endpoint -eq 'repos/fixture/pacs-assistant/releases') {
                Assert-ReleaseFixture ($body.draft -is [bool] -and $body.draft) 'Creation must remain a draft.'
                Assert-ReleaseFixture ($body.prerelease -is [bool] -and $body.prerelease -eq $releaseObject.prerelease) 'Creation must use the expected prerelease flag.'
                Assert-ReleaseFixture ($body.target_commitish -eq $env:EXPECTED_COMMIT) 'Creation must bind the workflow commit.'
                Assert-ReleaseFixture ($body.make_latest -ceq 'false' -and $body.generate_release_notes) 'Draft creation must retain generated notes without making it latest.'
                return ($releaseObject | ConvertTo-Json -Depth 5 -Compress)
            }
            if ($method -eq 'POST' -and $endpoint -match '^https://uploads\.github\.com/repos/fixture/pacs-assistant/releases/321/assets\?name=') {
                if ($Case -eq 'upload-failure') { $global:LASTEXITCODE = 1; return 'simulated upload failure' }
                $name = [Uri]::UnescapeDataString(($endpoint -split '\?name=', 2)[1])
                $releaseObject.assets += @($remoteAssets | Where-Object name -CEQ $name)
                return '{}'
            }
            if ($method -eq 'GET' -and $endpoint -eq 'repos/fixture/pacs-assistant/releases/321') {
                if ($Case -eq 'reconcile-failure' -and $fixtureState.Published) { $global:LASTEXITCODE = 1; return 'simulated unavailable state' }
                return ($releaseObject | ConvertTo-Json -Depth 5 -Compress)
            }
            if ($method -eq 'PATCH' -and $endpoint -eq 'repos/fixture/pacs-assistant/releases/321') {
                Assert-ReleaseFixture ($body.draft -is [bool] -and -not $body.draft) 'Publication must send JSON draft=false.'
                $policy = if ($Case -eq 'prerelease') { 'false' } else { 'legacy' }
                Assert-ReleaseFixture ($body.make_latest -ceq $policy) 'Publication must explicitly select the correct latest policy.'
                if ($Case -eq 'publish-failure') { $global:LASTEXITCODE = 1; return 'simulated publish failure' }
                $releaseObject.draft = $false
                $fixtureState.Published = $true
                if ($Case -in @('response-loss', 'reconcile-failure')) { $global:LASTEXITCODE = 1; return 'simulated lost response' }
                return ($releaseObject | ConvertTo-Json -Depth 5 -Compress)
            }
            if ($method -eq 'DELETE' -and $endpoint -eq 'repos/fixture/pacs-assistant/releases/321') {
                Assert-ReleaseFixture $releaseObject.draft 'A published release must never be deleted.'
                $fixtureState.Deleted = $true
                return ''
            }
            throw "Unexpected API call: $method $endpoint"
        }

        $failed = $false
        $failureMessage = ''
        Push-Location $fixture
        try {
            try { & $publication } catch { $failed = $true; $failureMessage = $_.Exception.Message }
        } finally { Pop-Location }
        $shouldFail = $Case -in @('upload-failure', 'publish-failure', 'moved-tag', 'reconcile-failure')
        Assert-ReleaseFixture ($failed -eq $shouldFail) "Fixture '$Case' had the wrong success state: $failureMessage"
        if ($shouldFail) {
            $expectedError = switch ($Case) {
                'upload-failure' { 'simulated upload failure' }
                'publish-failure' { 'simulated publish failure' }
                'moved-tag' { 'not workflow commit' }
                'reconcile-failure' { 'simulated lost response' }
            }
            Assert-ReleaseFixture ($failureMessage -match [regex]::Escape($expectedError)) "Fixture '$Case' failed for the wrong reason: $failureMessage"
        }
        $shouldDelete = $Case -in @('upload-failure', 'publish-failure', 'moved-tag')
        Assert-ReleaseFixture ($fixtureState.Deleted -eq $shouldDelete) "Fixture '$Case' had the wrong cleanup state."
        $patches = @($fixtureState.Calls | Where-Object Method -EQ 'PATCH')
        Assert-ReleaseFixture ($patches.Count -eq $(if ($Case -in @('upload-failure', 'moved-tag', 'existing')) { 0 } else { 1 })) "Fixture '$Case' had the wrong publication count."
        if (-not $shouldFail -and $Case -ne 'existing') {
            Assert-ReleaseFixture ($releaseObject.assets.Count -eq 5 -and $fixtureState.Published) 'Success requires all five assets on the created release.'
        }
        foreach ($requestFile in $fixtureState.RequestFiles) {
            Assert-ReleaseFixture (-not (Test-Path -LiteralPath $requestFile)) 'JSON request files must be removed after every request.'
        }
        Write-Host "PASS release workflow $Case"
    } finally {
        foreach ($key in $oldEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $oldEnvironment[$key]) }
        $resolved = [IO.Path]::GetFullPath($fixture)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped the temp directory.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

foreach ($case in @('stable', 'prerelease', 'response-loss', 'upload-failure', 'publish-failure', 'reconcile-failure', 'moved-tag', 'existing')) {
    Invoke-ReleaseFixture -Case $case
}
Write-Host 'Release workflow: 8 fixtures passed.'
