[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Matches {
    param(
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $Pattern,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Value -notmatch $Pattern) {
        $failures.Add($Message)
    }
}

function Assert-NotMatches {
    param(
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $Pattern,

        [Parameter(Mandatory)]
        [string] $Message
    )

    if ($Value -match $Pattern) {
        $failures.Add($Message)
    }
}

# YAML lets a key or a value be quoted and a mapping be written inline as
# { key: value }. The workflow checks below parse only the plain block form, so
# they count every form of a key or value and require each to be the plain one.
function Get-YamlKeyCount {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $Key
    )

    $anyKey = "(?:$Key|""$Key""|'$Key')"
    return [regex]::Matches($Text, "(?m)(?:^|[{,])\s*(?:-\s+)?$anyKey\s*:").Count
}

# Every value "write", in any form, for any key: only a permission takes it.
function Get-WriteValueCount {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    return [regex]::Matches($Text, '(?m):\s*["'']?write["'']?\s*(?:$|[,}])').Count
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflow = Get-Content -Raw (Join-Path $repoRoot '.github/workflows/ahk2exe.yml')
# The workflow without comments, for checks that a trailing "# ..." must not defeat.
$workflowCode = $workflow -replace '(?m)\s+#.*$', ''
$jobsSection = [regex]::Match($workflowCode, '(?ms)^jobs:\s*$.*').Value
$jobs = [regex]::Matches($jobsSection, '(?ms)^  (?<name>[A-Za-z0-9_-]+):\s*$(?<body>.*?)(?=^  [A-Za-z0-9_-]+:\s*$|\z)')
$gitmodules = Get-Content -Raw (Join-Path $repoRoot '.gitmodules')
$readme = Get-Content -Raw (Join-Path $repoRoot 'README.md')
$issueTemplate = Get-Content -Raw (Join-Path $repoRoot '.github/ISSUE_TEMPLATE/bug_report.md')
$featureTemplate = Get-Content -Raw (Join-Path $repoRoot '.github/ISSUE_TEMPLATE/feature_request.md')
$versionGeneratorPath = Join-Path $repoRoot 'scripts/GenerateVersion.ps1'
$releaseValidatorPath = Join-Path $repoRoot 'scripts/ValidateExistingRelease.ps1'
$releaseTagCommitValidatorPath = Join-Path $repoRoot 'scripts/AssertReleaseTagCommit.ps1'
$releaseFinderPath = Join-Path $repoRoot 'scripts/FindReleaseByTag.ps1'
$ownedDraftValidatorPath = Join-Path $repoRoot 'scripts/ValidateOwnedDraftRelease.ps1'
$publishFailureClassifierPath = Join-Path $repoRoot 'scripts/ClassifyReleaseAfterPublishFailure.ps1'
$releaseValidator = if (Test-Path -LiteralPath $releaseValidatorPath -PathType Leaf) {
    Get-Content -Raw -LiteralPath $releaseValidatorPath
} else {
    ''
}
$main = Get-Content -Raw (Join-Path $repoRoot 'main.ahk')
$profileManager = Get-Content -Raw (Join-Path $repoRoot 'ProfileManager.ahk')
$powerScribe = Get-Content -Raw (Join-Path $repoRoot 'PowerScribe.ahk')
$wetRead = Get-Content -Raw (Join-Path $repoRoot 'WetRead.ahk')
$pacsMonitor = Get-Content -Raw (Join-Path $repoRoot 'PACSMonitor.ahk')
$updateChecker = Get-Content -Raw (Join-Path $repoRoot 'UpdateChecker.ahk')
$winHttpTransport = Get-Content -Raw (Join-Path $repoRoot 'WinHttpTransport.ahk')
$winHttpTextRequest = Get-Content -Raw (Join-Path $repoRoot 'WinHttpTextRequest.ahk')
$winHttpMetadataWorker = Get-Content -Raw (Join-Path $repoRoot 'WinHttpMetadataWorker.ahk')
$winHttpWorkerProcess = Get-Content -Raw (Join-Path $repoRoot 'WinHttpWorkerProcess.ahk')
$winHttpMetadataWorkerMain = Get-Content -Raw (Join-Path $repoRoot 'WinHttpMetadataWorkerMain.ahk')
$updateNetworking = $updateChecker + $winHttpTransport + $winHttpTextRequest + $winHttpMetadataWorker + $winHttpMetadataWorkerMain
$appControl = Get-Content -Raw (Join-Path $repoRoot 'AppControl.ahk')
$keybindGui = Get-Content -Raw (Join-Path $repoRoot 'KeybindGUI.ahk')
$appTray = Get-Content -Raw (Join-Path $repoRoot 'AppTray.ahk')
$exclusiveOperations = Get-Content -Raw (Join-Path $repoRoot 'ExclusiveOperations.ahk')
$guiSmoke = Get-Content -Raw (Join-Path $repoRoot 'tests/run-gui-smoke.ahk')
$runTests = Get-Content -Raw (Join-Path $repoRoot 'tests/RunTests.ahk')
$testRunner = Get-Content -Raw (Join-Path $repoRoot 'tests/TestRunner.ahk')
$noticesPath = Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md'
$autoHotkeyLicensePath = Join-Path $repoRoot 'licenses/AutoHotkey-v2.0.26.txt'

Assert-Matches $gitmodules '(?m)^\s*url\s*=\s*https://github\.com/Descolada/UIA-v2\.git\s*$' 'UIA-v2 must use a public HTTPS submodule URL.'

$uiaPinnedCommit = '9f5a181c5d56d0cbc04e0a709fb875ab0059f762'
$uiaPath = Join-Path $repoRoot 'UIA-v2'
$uiaTreeEntry = [string] (& git -C $repoRoot ls-tree HEAD -- UIA-v2 2>$null)
if ($uiaTreeEntry -notmatch "^160000 commit $uiaPinnedCommit\tUIA-v2$") {
    $failures.Add("UIA-v2 must be pinned to v1.1.3 in the repository tree (found '$uiaTreeEntry').")
}
# Without its own .git entry, git -C UIA-v2 would silently report the parent
# repository's HEAD instead of the submodule's.
if (-not (Test-Path -LiteralPath (Join-Path $uiaPath '.git'))) {
    $failures.Add('UIA-v2 must be initialized before repository checks run (git submodule update --init).')
} else {
    $uiaCommit = [string] (& git -C $uiaPath rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or $uiaCommit.Trim() -ne $uiaPinnedCommit) {
        $failures.Add("The UIA-v2 checkout must be at the pinned v1.1.3 commit (found '$($uiaCommit.Trim())').")
    }
}

Assert-Matches $workflow '(?m)^\s*AUTOHOTKEY_VERSION:\s*2\.0\.26\s*$' 'CI must pin AutoHotkey v2.0.26.'
Assert-Matches $workflow '(?m)^\s*AUTOHOTKEY_SHA256:\s*43522aa3122a57784ac5db30abf85c2244475c36acd7796e2c993355f9e926ae\s*$' 'CI must verify the official AutoHotkey v2.0.26 ZIP digest.'
Assert-Matches $workflow '(?m)^\s*AUTOHOTKEY_SOURCE_SHA256:\s*765ada5ae0a543f470bcd30371a7b95438e59351b0a20508c516df76a4f73ca4\s*$' 'CI must verify the exact AutoHotkey v2.0.26 source archive digest.'
Assert-Matches $workflow '(?m)^\s*AHK2EXE_VERSION:\s*1\.1\.37\.02a2\s*$' 'CI must pin Ahk2Exe v1.1.37.02a2.'
Assert-Matches $workflow '(?m)^\s*AHK2EXE_SHA256:\s*c29b8c3a5124850d79fc9e66e2ca79677c377d7f31631ad3022ba159c5d9e3be\s*$' 'CI must verify the official Ahk2Exe v1.1.37.02a2 ZIP digest.'
Assert-Matches $workflow '(?m)^\s*pull_request:\s*$' 'Pull requests must run the non-release build and validation job.'
if ($jobs.Count -lt 2) {
    $failures.Add('The workflow must define its build and release jobs.')
}
foreach ($job in $jobs) {
    if ($job.Groups['body'].Value -notmatch '(?m)^\s{4}timeout-minutes:\s*\d+\s*$') {
        $failures.Add("CI job '$($job.Groups['name'].Value)' must define a bounded timeout-minutes value.")
    }
}
Assert-Matches $workflow '(?m)^\s*- name: Run unit tests\s*\r?\n\s+timeout-minutes:\s*\d+\s*$' 'The unit-test step must have its own timeout so a blocked harness fails fast.'
$unitStep = [regex]::Match($workflow, '(?ms)^\s*- name: Run unit tests\s*$.*?(?=^\s*- name:|\z)').Value
Assert-Matches $unitStep "'tests\\RunTests\.ahk'" 'The unit-test step must run tests\RunTests.ahk.'
Assert-Matches $unitStep '(?s)if \(\$process\.ExitCode -ne 0\)\s*\{\s*throw' 'The unit-test step must fail when the suite exits non-zero.'
$syntaxStep = [regex]::Match($workflow, '(?ms)^\s*- name: Validate syntax\s*$.*?(?=^\s*- name:|\z)').Value
foreach ($validatedScript in @("'main.ahk'", "'WinHttpMetadataWorkerMain\.ahk'", "'tests\\run-hotkey-tests\.ahk'", "'tests\\run-gui-smoke\.ahk'", "'tests\\run-ui-audit\.ahk'")) {
    Assert-Matches $syntaxStep $validatedScript "CI must /validate $validatedScript."
}
Assert-Matches $runTests 'ExitApp\(TestRunner\.failures > 0 \? 1 : 0\)' 'RunTests.ahk must exit non-zero when any test fails.'
Assert-Matches $testRunner 'OnExit\(ObjBindMethod\(this, "RequireCompletedRun"\)\)' 'TestRunner must fail a run that exits before every test finished.'
# README: add a test by writing a class and registering it in RunTests.ahk. Every
# *Test.ahk file must therefore be both included and registered, or it never runs.
foreach ($testFile in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*Test.ahk') {
    $testClass = [IO.Path]::GetFileNameWithoutExtension($testFile.Name)
    if ($runTests -notmatch ('(?m)^#Include\s+' + [regex]::Escape($testFile.Name) + '\s*$')) {
        $failures.Add("tests/RunTests.ahk does not include $($testFile.Name).")
    }
    if ($runTests -notmatch ('(?m)^TestRunner\.AddTest\(' + [regex]::Escape($testClass) + '\)\s*$')) {
        $failures.Add("tests/RunTests.ahk does not register $testClass.")
    }
}
# main.ahk and the test runners set FileEncoding "UTF-8", under which FileOpen puts
# a byte-order mark at the start of every file it creates. A binary write such as
# the update download needs a -RAW encoding, so every writing FileOpen names one.
$ahkSources = Get-ChildItem -LiteralPath $repoRoot -Filter '*.ahk' -Recurse |
    Where-Object { $_.FullName -notmatch '[\\/]UIA-v2[\\/]' }
foreach ($ahkSource in $ahkSources) {
    $text = Get-Content -Raw -LiteralPath $ahkSource.FullName
    foreach ($call in [regex]::Matches($text, 'FileOpen\(\s*[^,()]+,\s*"[^"]*[wa][^"]*"\s*\)')) {
        $failures.Add("$($ahkSource.Name) opens a file for writing without naming its encoding: $($call.Value)")
    }
    # Timeouts and deadlines use GetTickCount64. A_TickCount and the GetTickCount
    # export are 32-bit and wrap after 49.7 days, which a clinical workstation
    # can exceed; the tests replace every clock, so only this check can see one.
    if ($text -match '\bA_TickCount\b|"GetTickCount"') {
        $failures.Add("$($ahkSource.Name) reads a 32-bit tick count; use DllCall(""GetTickCount64"", ""UInt64"").")
    }
}

Assert-Matches $workflowCode '(?m)^permissions:\s*\r?\n  contents:\s*read\s*$' 'The top-level workflow token permission must be contents: read.'
Assert-NotMatches $workflowCode '(?m)^\s*permissions:[ \t]*\S' 'Workflow token permissions must be block mappings that name each scope, not an inline value such as write-all or { ... }.'
if ((Get-YamlKeyCount $workflowCode 'permissions') -ne [regex]::Matches($workflowCode, '(?m)^\s*permissions:\s*$').Count) {
    $failures.Add('Every workflow permissions key must be a plain, unquoted block mapping key.')
}
Assert-NotMatches $workflowCode '\b(?:read|write)-all\b' 'Workflow token permissions must name each scope, not read-all or write-all.'
Assert-Matches $workflowCode '(?ms)^\s{2}release:\s.*?^\s{4}permissions:\s*\r?\n\s{6}contents:\s*write\s*$' 'Only the release job may request contents: write.'
# Any scope (contents, actions, id-token, ...) and any form (quoted, inline)
# counts: the release job's contents: write is the only write permission.
if ((Get-WriteValueCount $workflowCode) -ne 1) {
    $failures.Add('Exactly one write permission, the release job''s contents: write, may appear in the workflow.')
}
Assert-Matches $workflow '(?m)^\s*runs-on:\s*windows-2025\s*$' 'The build job must use a versioned Windows runner image.'
Assert-Matches $workflow '(?m)^\s*runs-on:\s*ubuntu-24\.04\s*$' 'The release job must use a versioned Ubuntu runner image.'
Assert-NotMatches $workflowCode '(?m)^\s*runs-on:\s*\S+-latest\b' 'Workflow runner labels must not float on -latest.'
Assert-Matches $workflow '(?m)^\s*& tests/RepositoryContract\.ps1\s*$' 'CI must run the repository contract check.'
# #Warn leaves AutoHotkey's exit code at 0, so both AutoHotkey steps scan the output.
if ([regex]::Matches($workflow, 'Select-String -LiteralPath \$stdout, \$stderr -SimpleMatch ''==> Warning:'' -Quiet').Count -ne 2) {
    $failures.Add('Syntax validation and the unit tests must each fail CI on an AutoHotkey warning.')
}
Assert-Matches $workflow '(?m)^\s*& scripts/GenerateVersion\.ps1\b' 'CI must generate Version.ahk through the tested version script.'
Assert-Matches $workflow '(?m)^\s*licenses/AutoHotkey-v2\.0\.26\.txt\s*$' 'Release artifacts must include the AutoHotkey runtime license.'
Assert-Matches $workflow 'https://github\.com/AutoHotkey/AutoHotkey/archive/refs/tags/v\$\(\$env:AUTOHOTKEY_VERSION\)\.zip' 'CI must download source from the exact AutoHotkey version tag.'
Assert-Matches $workflow '(?m)^\s*AutoHotkey-v2\.0\.26-source\.zip\s*$' 'Build artifacts must include the AutoHotkey corresponding-source archive.'
Assert-Matches $workflow "Join-Path \`$PWD 'release/AutoHotkey-v2\.0\.26-source\.zip'" 'Tagged releases must publish the AutoHotkey corresponding-source archive.'
Assert-NotMatches $workflow '\$env:RELEASE_TAG\.Contains\(''-''\)' 'Release publication must not classify build-metadata hyphens as prerelease markers.'
$prereleaseMatch = [regex]::Match($workflow, "\`$expectedPrerelease\s*=\s*\`$env:RELEASE_TAG\s+-match\s+'(?<pattern>[^']+)'")
if (-not $prereleaseMatch.Success) {
    $failures.Add('Release publication must classify prereleases with one -match expression on RELEASE_TAG.')
} else {
    # Evaluate the workflow's own expression: only a hyphen directly after the
    # numeric core marks a prerelease, and only ASCII digits form that core.
    $prereleasePattern = $prereleaseMatch.Groups['pattern'].Value
    $classifications = [ordered]@{
        'v2.1.0-beta.1' = $true
        'v2.1.0-rc.1+build.5' = $true
        'v2.1.0' = $false
        'v2.1.0+build-5' = $false
        ('v2.1.1' + [char]0x0663 + '-beta.1') = $false
    }
    foreach ($tag in $classifications.Keys) {
        if (($tag -match $prereleasePattern) -ne $classifications[$tag]) {
            $failures.Add("Release prerelease classification is wrong for tag '$tag'.")
        }
    }
}
Assert-NotMatches $workflow '--clobber' 'Published release assets must never be replaced in place.'
Assert-Matches $releaseValidator 'Get-FileHash\s+-LiteralPath\s+\$localFile\.FullName\s+-Algorithm\s+SHA256' 'Existing releases must compare each local asset SHA-256.'
Assert-Matches $releaseValidator '\$remoteAsset\.digest' 'Existing releases must compare the API-provided asset digest.'
Assert-Matches $releaseValidator '\$remoteAsset\.size\s+-ne\s+\$localFile\.Length' 'Existing releases must compare asset sizes before becoming a no-op.'
Assert-Matches $workflow '& scripts/ValidateExistingRelease\.ps1' 'Existing releases must pass the complete release object through the tested validator.'
$existingReleaseCalls = [regex]::Matches($workflow, '& scripts/ValidateExistingRelease\.ps1(?<arguments>(?:[ \t]*`\r?\n[ \t]*-[^\r\n`]*)+)')
if ($existingReleaseCalls.Count -lt 2) {
    $failures.Add('Both existing-release and uploaded-draft validation must call scripts/ValidateExistingRelease.ps1.')
}
foreach ($call in $existingReleaseCalls) {
    $arguments = $call.Groups['arguments'].Value
    if ($arguments -notmatch '-ExpectedCommitSha \$env:EXPECTED_COMMIT' -or $arguments -notmatch '-ActualTagCommitSha \$actualTagCommit') {
        $failures.Add('Every existing-release validation must bind the resolved tag commit to the workflow commit.')
    }
}
if ([regex]::Matches($workflow, '& scripts/AssertReleaseTagCommit\.ps1').Count -lt 2) {
    $failures.Add('Release publication must verify the tag commit both before release handling and immediately before publishing a new draft.')
}
Assert-Matches $workflow '(?ms)Resolve-ReleaseTagCommit.*?AssertReleaseTagCommit\.ps1.*?\$release\s*=\s*Find-ReleaseByTag' 'Release handling must reject a moved tag before either the existing- or new-release branch.'
Assert-Matches $workflow '(?s)\$createdDraft = Invoke-GitHubJson -Method POST.*?draft = \$true.*?uploads\.github\.com.*?Resolve-ReleaseTagCommit.*?AssertReleaseTagCommit\.ps1.*?Invoke-GitHubJson -Method PATCH' 'New releases must remain drafts through asset upload and a second exact tag-commit check.'
Assert-Matches $workflow '(?s)\$uploadedDraft\s*=\s*Invoke-GitHubJson.*?ValidateExistingRelease\.ps1.*?-ExpectedDraft \$true.*?draft = \$false' 'Uploaded draft bytes and metadata must be revalidated before publication.'
Assert-NotMatches $workflow "'release',\s*'(?:upload|edit)'" 'Release uploads and publication must never rediscover their target by tag.'
Assert-Matches $workflow '\$latestPolicy = if \(\$expectedPrerelease\) \{ ''false'' \} else \{ ''legacy'' \}' 'Publication must explicitly preserve stable semantic latest-selection and exclude prereleases.'
Assert-Matches $workflow '(?s)--paginate.*?--slurp.*?releases\?per_page=100.*?FindReleaseByTag\.ps1' 'Release discovery must include authenticated draft releases across every API page.'
Assert-Matches $workflow '(?ms)^concurrency:\s*\r?\n\s+group:\s*\$\{\{\s*github\.workflow\s*\}\}-\$\{\{\s*github\.ref\s*\}\}\s*\r?\n\s+cancel-in-progress:\s*false' 'Workflow runs for the same ref must be serialized so one rerun cannot delete another active draft.'
Assert-Matches $workflow '(?s)if \(\$release -and \$release\.draft\).*?ValidateOwnedDraftRelease\.ps1.*?--method DELETE' 'A rerun must validate and remove only its own interrupted draft before recreating it.'
Assert-Matches $workflow '(?s)catch\s*\{.*?\$createdDraftId.*?--method DELETE.*?throw' 'A failed publication attempt must best-effort remove the draft created by that run.'

if (-not (Test-Path -LiteralPath $releaseFinderPath -PathType Leaf)) {
    $failures.Add('Release discovery must be implemented by scripts/FindReleaseByTag.ps1.')
} else {
    $releasePagesJson = @'
[[{"id":11,"tag_name":"v1.0.0","draft":false}],[{"id":22,"tag_name":"v2.0.0","draft":true}]]
'@
    $draft = & $releaseFinderPath -ReleaseJson $releasePagesJson -ReleaseTag 'v2.0.0'
    if ($draft -isnot [pscustomobject] -or $draft.PSObject.Properties.Name -cnotcontains 'draft') {
        $failures.Add('Release discovery must return the release object itself, so validators see its own JSON properties.')
    }
    if ($draft.id -ne 22 -or -not $draft.draft) {
        $failures.Add('Release discovery did not recover an interrupted draft by exact tag.')
    }
    $missing = @(& $releaseFinderPath -ReleaseJson $releasePagesJson -ReleaseTag 'v9.0.0')
    if ($missing.Count -ne 0) {
        $failures.Add('Release discovery must return no object for an absent tag.')
    }
    try {
        & $releaseFinderPath `
            -ReleaseJson '[[{"id":1,"tag_name":"v2.0.0"},{"id":2,"tag_name":"v2.0.0"}]]' `
            -ReleaseTag 'v2.0.0'
        $failures.Add('Release discovery must reject duplicate releases for one exact tag.')
    } catch {
        if ($_.Exception.Message -notmatch 'multiple') {
            $failures.Add('Duplicate release discovery failed for the wrong reason.')
        }
    }
}

if (-not (Test-Path -LiteralPath $ownedDraftValidatorPath -PathType Leaf)) {
    $failures.Add('Workflow drafts must be ownership-checked by scripts/ValidateOwnedDraftRelease.ps1.')
} else {
    $ownedDraft = [pscustomobject]@{
        id = 22
        draft = $true
        prerelease = $false
        tag_name = 'v2.0.0'
        name = 'v2.0.0'
        author = [pscustomobject]@{ login = 'github-actions[bot]' }
    }
    & $ownedDraftValidatorPath `
        -Release $ownedDraft `
        -ReleaseTag 'v2.0.0' `
        -ExpectedPrerelease $false
    foreach ($invalidId in @($true, 1.5, '22', 0, -1)) {
        $invalidDraft = $ownedDraft.PSObject.Copy()
        $invalidDraft.id = $invalidId
        try {
            & $ownedDraftValidatorPath -Release $invalidDraft -ReleaseTag 'v2.0.0' -ExpectedPrerelease $false
            $failures.Add("Draft reconciliation must reject the release ID '$invalidId'.")
        } catch {
            if ($_.Exception.Message -notmatch 'invalid database ID') {
                $failures.Add("Release ID '$invalidId' was rejected for the wrong reason: $($_.Exception.Message)")
            }
        }
    }
    $foreignDraft = $ownedDraft.PSObject.Copy()
    $foreignDraft.author = [pscustomobject]@{ login = 'human-maintainer' }
    try {
        & $ownedDraftValidatorPath `
            -Release $foreignDraft `
            -ReleaseTag 'v2.0.0' `
            -ExpectedPrerelease $false
        $failures.Add('Draft reconciliation must reject a draft not created by GitHub Actions.')
    } catch {
        if ($_.Exception.Message -notmatch 'author') {
            $failures.Add('Foreign draft validation failed for the wrong reason.')
        }
    }
    # Every other property that authorises the DELETE, changed one at a time (or
    # removed), with the reason its rejection must give.
    $invalidDraftCases = @(
        @{ Property = 'draft'; Value = $false; Reason = 'not an unpublished draft' },
        @{ Property = 'draft'; Value = 'true'; Reason = 'not an unpublished draft' },
        @{ Property = 'prerelease'; Value = $true; Reason = 'wrong prerelease classification' },
        @{ Property = 'prerelease'; Value = 'false'; Reason = 'wrong prerelease classification' },
        @{ Property = 'tag_name'; Value = 'V2.0.0'; Reason = 'tag does not exactly match' },
        @{ Property = 'name'; Value = 'Release v2.0.0'; Reason = 'exact title' },
        @{ Property = 'author'; Value = $null; Reason = 'no author identity' },
        @{ Property = 'author'; Value = [pscustomobject]@{ name = 'github-actions[bot]' }; Reason = "missing required property 'login'" },
        @{ Property = 'name'; Remove = $true; Reason = "missing required property 'name'" }
    )
    foreach ($case in $invalidDraftCases) {
        $invalidDraft = $ownedDraft.PSObject.Copy()
        if ($case.ContainsKey('Remove')) {
            $invalidDraft.PSObject.Properties.Remove($case.Property)
            $label = "without $($case.Property)"
        } else {
            $invalidDraft.($case.Property) = $case.Value
            $label = "with $($case.Property) = '$($case.Value)'"
        }
        try {
            & $ownedDraftValidatorPath -Release $invalidDraft -ReleaseTag 'v2.0.0' -ExpectedPrerelease $false
            $failures.Add("Draft reconciliation must reject a draft $label.")
        } catch {
            if ($_.Exception.Message -notmatch [regex]::Escape($case.Reason)) {
                $failures.Add("A draft $label was rejected for the wrong reason: $($_.Exception.Message)")
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $publishFailureClassifierPath -PathType Leaf)) {
    $failures.Add('Publish response-loss recovery must be implemented by scripts/ClassifyReleaseAfterPublishFailure.ps1.')
} else {
    $workflowDraft = [pscustomobject]@{
        id = 44
        draft = $true
        prerelease = $false
        tag_name = 'v2.0.0'
        name = 'v2.0.0'
        author = [pscustomobject]@{ login = 'github-actions[bot]' }
    }
    $publishedRelease = $workflowDraft.PSObject.Copy()
    $publishedRelease.draft = $false

    $draftDisposition = & $publishFailureClassifierPath `
        -Release $workflowDraft `
        -CreatedDraftId 44 `
        -ReleaseTag 'v2.0.0' `
        -ExpectedPrerelease $false
    if ($draftDisposition -cne 'cleanup-draft') {
        $failures.Add('A re-read workflow-owned draft must be the only publish-failure state eligible for deletion.')
    }

    $publishedDisposition = & $publishFailureClassifierPath `
        -Release $publishedRelease `
        -CreatedDraftId 44 `
        -ReleaseTag 'v2.0.0' `
        -ExpectedPrerelease $false
    if ($publishedDisposition -cne 'published') {
        $failures.Add('A response-loss re-read must preserve a release that GitHub already published.')
    }

    $differentDisposition = & $publishFailureClassifierPath `
        -Release $workflowDraft `
        -CreatedDraftId 45 `
        -ReleaseTag 'v2.0.0' `
        -ExpectedPrerelease $false
    if ($differentDisposition -cne 'leave') {
        $failures.Add('Publish-failure recovery must never mutate a different release database ID.')
    }

    $absentDisposition = & $publishFailureClassifierPath `
        -Release $null `
        -CreatedDraftId 44 `
        -ReleaseTag 'v2.0.0' `
        -ExpectedPrerelease $false
    if ($absentDisposition -cne 'leave') {
        $failures.Add('An absent release after publication failure must be left for a resumable rerun.')
    }

    $foreignWorkflowDraft = $workflowDraft.PSObject.Copy()
    $foreignWorkflowDraft.author = [pscustomobject]@{ login = 'human-maintainer' }
    try {
        & $publishFailureClassifierPath `
            -Release $foreignWorkflowDraft `
            -CreatedDraftId 44 `
            -ReleaseTag 'v2.0.0' `
            -ExpectedPrerelease $false
        $failures.Add('Publish-failure cleanup must reject a same-ID draft not owned by GitHub Actions.')
    } catch {
        if ($_.Exception.Message -notmatch 'author') {
            $failures.Add('Foreign publish-failure draft classification failed for the wrong reason.')
        }
    }
}

Assert-Matches $workflow 'scripts/ClassifyReleaseAfterPublishFailure\.ps1' 'Release publication failures must re-read and classify server state before cleanup.'
Assert-Matches $readme '(?i)immutable releases' 'Release documentation must require GitHub release immutability.'
Assert-Matches $readme '(?i)tag ruleset.*restrict.*updates.*deletions' 'Release documentation must require protected release tags because ref comparison and publication are not atomic.'
Assert-NotMatches ($appControl + $keybindGui) '``n``n' 'User-facing diagnostics must use real AHK newline escapes, not render literal backtick-n text.'

$actionReferencePattern = '(?m)^\s*(?:-\s+)?uses:\s*(?<reference>\S+?)(?:\s+#.*)?\s*$'
# Quoted and inline uses keys count too, so a step the pattern cannot parse fails.
$usesLineCount = Get-YamlKeyCount $workflowCode 'uses'
$validatedActionCount = 0
foreach ($match in [regex]::Matches($workflow, $actionReferencePattern)) {
    $validatedActionCount++
    $reference = $match.Groups['reference'].Value
    if ($reference -notmatch '@[0-9a-f]{40}$') {
        $failures.Add("GitHub Action is not pinned to an immutable commit: $reference")
    }
    $action = $reference.Split('@')[0]
    if ($action -notin @('actions/checkout', 'actions/upload-artifact', 'actions/download-artifact')) {
        $failures.Add("GitHub Action is not on the reviewed first-party allowlist: $action")
    }
}
if ($validatedActionCount -ne $usesLineCount) {
    $failures.Add("Every workflow uses entry must be validated (found $usesLineCount, validated $validatedActionCount).")
}

# Keep the parser honest for both forms used by contributors. Each fixture is
# intentionally floating and must be extracted as the same invalid reference even
# when an inline human-readable version comment follows it.
foreach ($fixture in @(
    'uses: actions/checkout@v4',
    'uses: actions/checkout@v4 # v4',
    '      - uses: actions/checkout@v4'
)) {
    $fixtureMatches = [regex]::Matches($fixture, $actionReferencePattern)
    if ($fixtureMatches.Count -ne 1 -or $fixtureMatches[0].Groups['reference'].Value -ne 'actions/checkout@v4') {
        $failures.Add("The action-reference parser did not cover negative fixture: $fixture")
    } elseif ($fixtureMatches[0].Groups['reference'].Value -match '@[0-9a-f]{40}$') {
        $failures.Add("A floating action negative fixture was incorrectly accepted: $fixture")
    }
}

$checkoutCount = [regex]::Matches($workflowCode, '(?m)^\s*(?:-\s+)?uses:\s*actions/checkout@').Count
$credentialsOff = [regex]::Matches($workflowCode, '(?m)^\s*persist-credentials:\s*false\s*$').Count
if ($checkoutCount -lt 1 -or $credentialsOff -ne $checkoutCount -or (Get-YamlKeyCount $workflowCode 'persist-credentials') -ne $credentialsOff) {
    $failures.Add('Every checkout must set persist-credentials: false, as a plain block line; the build job runs downloaded tools.')
}

# The counters must see the forms the plain-line patterns cannot parse.
foreach ($fixture in @(
    @{ Text = '      - { uses: actions/checkout@v4 }'; Key = 'uses' },
    @{ Text = '      - "uses": actions/checkout@v4'; Key = 'uses' },
    @{ Text = "        'uses': actions/checkout@v4"; Key = 'uses' },
    @{ Text = '        with: { persist-credentials: true }'; Key = 'persist-credentials' },
    @{ Text = '    "permissions": { contents: read }'; Key = 'permissions' }
)) {
    if ((Get-YamlKeyCount $fixture.Text $fixture.Key) -ne 1) {
        $failures.Add("The YAML key counter did not cover negative fixture: $($fixture.Text)")
    }
}
foreach ($fixture in @(
    '      contents: "write"',
    "      'id-token': 'write'",
    '    permissions: { contents: write, actions: read }',
    '    permissions: { actions: read, contents: write }'
)) {
    if ((Get-WriteValueCount $fixture) -ne 1) {
        $failures.Add("The write permission counter did not cover negative fixture: $fixture")
    }
}
Assert-NotMatches $workflow '(?i)benmusson/ahk2exe-action|softprops/action-gh-release' 'Build and release must not delegate downloaded binaries or release authority to third-party actions.'
Assert-NotMatches $workflow 'Ahk2Exe-SetCopyright\s+MIT' 'Executable copyright metadata must not mislabel the GPL-3.0 project as MIT.'

Assert-NotMatches $profileManager '(?m)^#Include\s+PACSCommands\.ahk\s*$' 'Profile persistence must not depend on the clinical command graph.'
Assert-NotMatches $powerScribe '\bProfileManager\b' 'PowerScribe automation must not reach profile state through an implicit global.'
Assert-Matches $wetRead '(?m)^#Include\s+ProfileManager\.ahk\s*$' 'The wet-read composition layer must declare its profile dependency.'
Assert-NotMatches $pacsMonitor '\btest(?:Mode|StudyRows|RefreshCalls|LastNewStudies)\b' 'Production PACS monitoring must use injected boundaries rather than compiled test-mode state.'
Assert-NotMatches $updateNetworking '\.\s*Response(?:Text|Body)\b' 'Update responses must be streamed through explicit byte caps rather than materialized by a COM response property.'
Assert-Matches $winHttpMetadataWorker 'WinHttpReadData' 'Update response bodies must use a bounded streaming WinHTTP read path.'
Assert-NotMatches ($winHttpTextRequest + $winHttpMetadataWorker) 'CallbackCreate|WinHttpSetStatusCallback' 'Metadata requests must never execute AutoHotkey on native WinHTTP worker threads.'
Assert-Matches $main '(?m)^#SingleInstance\s+Ignore\s*$' 'A second launch must never force-terminate a dirty or in-flight clinical instance.'
Assert-NotMatches $main '(?m)^#SingleInstance\s+Force\s*$' 'Force replacement bypasses shutdown and clinical transaction gates.'
Assert-Matches $main 'OnExit\(\(exitReason, exitCode\) => kbGUI\.HandleProcessExit\(exitReason, exitCode\)\)' 'Tray and external exits must use the authoritative shutdown coordinator.'
Assert-Matches $main 'UpdateChecker\.shutdownCoordinator\s*:=\s*kbGUI' 'Self-update must use the same shutdown coordinator as normal exit.'
Assert-Matches $main '(?s)OnExit\(\(exitReason, exitCode\) => kbGUI\.HandleProcessExit\(exitReason, exitCode\)\).*AppTray\.Install\(kbGUI\)' 'The tray menu must be installed after the shutdown coordinator, so its Exit passes the same gate.'
Assert-NotMatches $appTray 'AddStandard' 'The tray menu must not restore AutoHotkey''s standard items: Pause Script would silently stop monitoring.'
Assert-Matches $main '(?m)^;@Ahk2Exe-SetMainIcon pacs-assistant\.ico\s*$' 'Compiled builds must carry the app icon.'
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'pacs-assistant.ico') -PathType Leaf)) {
    $failures.Add('pacs-assistant.ico must exist: main.ahk compiles it in and sets it for source runs.')
}
Assert-Matches $main 'PACSCommands\.commandAvailabilityProbe\s*:=\s*\(\*\)\s*=>\s*ExclusiveOperations\.Active\("clinical"\)\s*=\s*""' 'Clinical commands must be gated by every other exclusive operation through the shared classifier.'
Assert-Matches $main 'UpdateChecker\.clinicalActivityProbe\s*:=\s*\(\*\)\s*=>\s*PACSCommands\.clinicalCommandActive' 'Self-update must see an active clinical command.'
Assert-Matches $main 'Settings\.mutationGuard\s*:=\s*\(\*\)\s*=>\s*ExclusiveOperations\.Active\("settingsWrite"\)\s*=\s*""' 'Settings writes must be gated by every other exclusive operation through the shared classifier.'
Assert-Matches $exclusiveOperations '(?s)static kinds := \[\s*"clinical",\s*"capture",\s*"profileMutation",\s*"settingsWrite",\s*"uiPresentation",\s*"shutdown"\s*\]' 'The exclusive-operation classifier must cover clinical, capture, profile, settings, dialog presentation and shutdown leases.'
Assert-NotMatches $guiSmoke '\{\s*base:\s*KeybindGUI\.Prototype' 'The GUI smoke test must construct a real KeybindGUI instance so instance-property initialization is exercised.'
Assert-Matches $guiSmoke '(?s)ExitApp\(RunSmoke\(\)\).*?RunSmoke\(\)\s*\{.*?try\s+exitCode\s*:=\s*Main\(\).*?catch Any as err\s*\{.*?return exitCode' 'The GUI smoke test must convert fatal harness errors into a nonzero process exit.'
Assert-Matches $main 'Settings\.dialogAcquire\s*:=\s*ObjBindMethod\(ExclusiveOperations,\s*"TryBegin",\s*"uiPresentation"\)' 'Settings presentation must acquire the shared UI transaction.'
Assert-Matches $main 'Settings\.dialogRelease\s*:=\s*ObjBindMethod\(ExclusiveOperations,\s*"End",\s*"uiPresentation"\)' 'Settings presentation must release the shared UI transaction.'
Assert-Matches $main 'UpdateChecker\.dialogAcquire\s*:=\s*ObjBindMethod\(ExclusiveOperations,\s*"TryBegin",\s*"uiPresentation"\)' 'Update presentation must acquire the shared UI transaction.'
Assert-Matches $main 'UpdateChecker\.dialogRelease\s*:=\s*ObjBindMethod\(ExclusiveOperations,\s*"End",\s*"uiPresentation"\)' 'Update presentation must release the shared UI transaction.'
Assert-Matches $updateChecker 'manualResultNotifier\s*:=\s*\(text, title, options\) => TrayTip' 'Asynchronous update results must use a nonactivating notification by default.'

# The self-update script runs under Windows PowerShell after the app has exited:
# if it did not parse, nothing would be installed, relaunched or logged.
$updaterMatch = [regex]::Match($updateChecker, '(?ms)static BuildUpdaterScript\(\) \{\s*script := "\s*\r?\n\s*\(\r?\n(?<body>.*?)\r?\n\s*\)"')
if (-not $updaterMatch.Success) {
    $failures.Add('The updater script continuation section in UpdateChecker.BuildUpdaterScript was not found.')
} else {
    $updaterScript = $updaterMatch.Groups['body'].Value
    # Without double quotes or backticks the section's text is exactly the string
    # AutoHotkey builds, so this parses the script that runs.
    if ($updaterScript -match '[`"]') {
        $failures.Add('The updater script must not use double quotes or backticks, so this check reads the exact script that runs.')
    }
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($updaterScript, [ref]$null, [ref]$parseErrors)
    foreach ($parseError in $parseErrors) {
        $failures.Add("The updater script does not parse: $($parseError.Message) (line $($parseError.Extent.StartLineNumber))")
    }
    # The installed updater runs under Windows PowerShell 5.1, whose grammar is
    # narrower than this engine's; check it there too where it exists (CI).
    $windowsPowerShell = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' } else { '' }
    if ($windowsPowerShell -and (Test-Path -LiteralPath $windowsPowerShell)) {
        $scriptFile = Join-Path ([IO.Path]::GetTempPath()) "pacs-assistant-updater-parse-$PID.ps1"
        try {
            [IO.File]::WriteAllText($scriptFile, $updaterScript)
            & $windowsPowerShell -NoProfile -NonInteractive -Command "`$e = `$null; [void][Management.Automation.Language.Parser]::ParseFile('$scriptFile', [ref]`$null, [ref]`$e); exit `$e.Count"
            if ($LASTEXITCODE -ne 0) {
                $failures.Add("The updater script does not parse under Windows PowerShell 5.1 ($LASTEXITCODE errors).")
            }
        } finally {
            Remove-Item -LiteralPath $scriptFile -ErrorAction SilentlyContinue
        }
    }
}
foreach ($subscriber in @('UpdateChecker', 'PACSMonitor', 'MicrophoneManager')) {
    Assert-Matches $main ("Settings\.AddChangeListener\(ObjBindMethod\(" + $subscriber) ("main.ahk must explicitly subscribe " + $subscriber + " to settings changes.")
}
Assert-Matches $winHttpTextRequest '(?s)this\.worker\.Start.*?SetTimer\(this\.timeoutTimer, 50\)' 'Automatic metadata requests must run outside the UI process with nonblocking completion polling.'
Assert-Matches $winHttpWorkerProcess '(?s)JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE.*?PROC_THREAD_ATTRIBUTE_JOB_LIST.*?CreateProcessW' 'Metadata workers must be created inside their kill-on-close job, and end with their parent process.'
# A suspended self-launch followed by ResumeThread is an injection-shaped pattern to
# behavior-monitoring antivirus, which the hospital deployment cannot afford.
Assert-NotMatches $winHttpWorkerProcess 'ResumeThread|AssignProcessToJobObject|0x0800000[4-7]\b|CREATE_SUSPENDED' 'Metadata workers must never start suspended.'
Assert-Matches $winHttpTextRequest '(?m)^;@Ahk2Exe-AddResource WinHttpMetadataWorkerMain\.ahk, WINHTTPMETADATAWORKER\s*$' 'Compiled builds must embed the metadata worker script.'
Assert-Matches $winHttpTextRequest 'workerResourceName := "WINHTTPMETADATAWORKER"' 'The embedded worker must be launched by the resource name it is compiled under.'
Assert-NotMatches $winHttpTextRequest '\b(?:FileInstall|FileCopy|FileAppend)\b' 'Metadata requests must never write a script file to run.'
Assert-Matches $winHttpMetadataWorkerMain '(?m)^#NoTrayIcon\s*$' 'The metadata worker must not show a second tray icon.'
Assert-Matches $workflow '(?s)- name: Compile.*?- name: Smoke-test the embedded metadata worker.*?\*WINHTTPMETADATAWORKER' 'CI must run the metadata worker embedded in the compiled executable.'
Assert-Matches $main '(?s)PACSMonitor\.automationAcquire\s*:=.*MicrophoneManager\.automationAcquire\s*:=.*kbGUI\s*:=\s*KeybindGUI\(\).*PACSMonitor\.Start\(\).*MicrophoneManager\.Start\(\).*UpdateChecker\.Start\(\)' 'Every lease, the background automation gates included, must be wired before the GUI is shown, the GUI before clinical timers, and clinical timers before automatic network checks.'

Assert-Matches $readme 'git clone --recurse-submodules' 'README must document cloning with submodules.'
Assert-Matches $readme 'AutoHotkey v2\.0\.26' 'README must state the AutoHotkey version used by CI.'
Assert-Matches $readme 'Ahk2Exe v1\.1\.37\.02a2' 'README must state the Ahk2Exe version used by CI.'
Assert-Matches $readme 'THIRD_PARTY_NOTICES\.md' 'README must link the bundled dependency notices.'
Assert-Matches $readme 'AutoHotkey-v2\.0\.26-source\.zip' 'README must identify the corresponding-source release asset.'
Assert-Matches $readme 'GPL-3\.0' 'README must identify the project license.'
Assert-Matches $readme 'Start-Process\s+-FilePath\s+\$ahk.*-Wait\s+-PassThru' 'Local AutoHotkey test commands must wait for the GUI-subsystem process.'
Assert-Matches $readme '\$process\.ExitCode\s+-ne\s+0' 'Local AutoHotkey test commands must propagate the process exit code.'
Assert-Matches $readme '& scripts/GenerateVersion\.ps1' 'The documented local release build must generate version metadata before compiling.'

Assert-NotMatches $issueTemplate '(?i)\bsmartphone\b|\bbrowser\b|\biOS\b' 'The bug template must not ask irrelevant browser or smartphone questions.'
Assert-Matches $issueTemplate 'PowerScribe' 'The bug template must request PowerScribe context.'
Assert-Matches $issueTemplate '\bPACS\b' 'The bug template must request PACS context.'
Assert-Matches $featureTemplate '(?i)protected health information|\bPHI\b' 'The feature template must prohibit protected health information.'
Assert-Matches $featureTemplate '(?i)redact.+screenshots|screenshots.+redact' 'The feature template must tell reporters to redact screenshots.'

foreach ($generatedArtifact in @(
    'pacs-assistant.exe',
    'pacs-assistant.new.exe',
    'pacs-assistant.backup.exe',
    'AutoHotkey-v2.0.26-source.zip'
)) {
    & git -C $repoRoot check-ignore --quiet -- $generatedArtifact
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Generated root artifact is not ignored: $generatedArtifact")
    }
}

foreach ($privateSettingsArtifact in @(
    'settings.ini.tmp-123-456',
    'tests/settings.ini.tmp-123-456',
    'tests/settings.ini',
    'tests/profiles/Night.ini',
    'profiles/Night.ini',
    'error.log'
)) {
    & git -C $repoRoot check-ignore --quiet -- $privateSettingsArtifact
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("Private settings transaction artifact is not ignored: $privateSettingsArtifact")
    }
}

if (-not (Test-Path -LiteralPath $releaseValidatorPath -PathType Leaf)) {
    $failures.Add('scripts/ValidateExistingRelease.ps1 must validate immutable release no-op state.')
} else {
    function Invoke-ReleaseValidationFixture {
        param([string] $Case = 'valid')

        $caseRoot = Join-Path ([IO.Path]::GetTempPath()) ("pacs-release-contract-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $caseRoot)
        try {
            $assetPaths = @()
            $remoteAssets = @()
            foreach ($name in @('pacs-assistant.exe', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'AutoHotkey-v2.0.26.txt', 'AutoHotkey-v2.0.26-source.zip')) {
                $path = Join-Path $caseRoot $name
                [IO.File]::WriteAllText($path, "fixture:$name")
                $assetPaths += $path
                $remoteAssets += [pscustomobject]@{
                    name = $name
                    size = (Get-Item -LiteralPath $path).Length
                    digest = 'sha256:' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }

            $release = [pscustomobject]@{
                draft = $false
                prerelease = $false
                tag_name = 'v2.3.4'
                name = 'v2.3.4'
                assets = $remoteAssets
            }
            $expectedCommit = '0123456789abcdef0123456789abcdef01234567'
            $actualCommit = $expectedCommit
            $expectedDraft = $false
            switch ($Case) {
                'draft' { $release.draft = $true }
                'valid-draft' {
                    $release.draft = $true
                    $expectedDraft = $true
                }
                'wrong-prerelease' { $release.prerelease = $true }
                # Each compares equal to $false in PowerShell, but is not a JSON boolean.
                'string-draft' { $release.draft = 'false' }
                'zero-prerelease' { $release.prerelease = 0 }
                'wrong-tag' { $release.tag_name = 'v9.9.9' }
                'wrong-name' { $release.name = 'Unexpected title' }
                'wrong-commit' { $actualCommit = 'ffffffffffffffffffffffffffffffffffffffff' }
                'extra-asset' {
                    $release.assets += [pscustomobject]@{
                        name = 'unexpected.bin'
                        size = 1
                        digest = 'sha256:' + ('0' * 64)
                    }
                }
                'missing-asset' { $release.assets = @($remoteAssets | Select-Object -Skip 1) }
                'renamed-asset' { $remoteAssets[0].name = 'pacs-assistant-renamed.exe' }
                'size-mismatch' { $remoteAssets[0].size = $remoteAssets[0].size + 1 }
                'digest-mismatch' { $remoteAssets[0].digest = 'sha256:' + ('0' * 64) }
                'null-digest' { $remoteAssets[0].digest = $null }
            }

            try {
                & $releaseValidatorPath `
                    -Release $release `
                    -ReleaseTag 'v2.3.4' `
                    -ExpectedPrerelease $false `
                    -ExpectedDraft $expectedDraft `
                    -ExpectedCommitSha $expectedCommit `
                    -ActualTagCommitSha $actualCommit `
                    -Assets $assetPaths
                return ''
            } catch {
                return $_.Exception.Message
            }
        } finally {
            Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $validMessage = Invoke-ReleaseValidationFixture
    if ($validMessage -ne '') {
        $failures.Add("The matching release fixture must be accepted as an immutable no-op: $validMessage")
    }
    $validDraftMessage = Invoke-ReleaseValidationFixture -Case 'valid-draft'
    if ($validDraftMessage -ne '') {
        $failures.Add("The matching uploaded draft fixture must be accepted before publication: $validDraftMessage")
    }
    # Each invalid fixture must fail, and for its own reason: a validator that
    # failed early for an unrelated cause would otherwise hide a removed check.
    $expectedRejections = [ordered]@{
        'draft' = 'must be published'
        'wrong-prerelease' = 'wrong prerelease classification'
        'string-draft' = 'must be published'
        'zero-prerelease' = 'wrong prerelease classification'
        'wrong-tag' = 'does not exactly match'
        'wrong-name' = 'exact title'
        'wrong-commit' = 'not workflow commit'
        'extra-asset' = 'exactly the approved asset set'
        'missing-asset' = 'exactly the approved asset set'
        'renamed-asset' = 'missing approved asset'
        'size-mismatch' = 'different bytes'
        'digest-mismatch' = 'different bytes'
        'null-digest' = 'different bytes'
    }
    foreach ($invalidCase in $expectedRejections.Keys) {
        $message = Invoke-ReleaseValidationFixture -Case $invalidCase
        if ($message -eq '') {
            $failures.Add("Invalid existing-release fixture was accepted: $invalidCase")
        } elseif ($message -notmatch [regex]::Escape($expectedRejections[$invalidCase])) {
            $failures.Add("Existing-release fixture '$invalidCase' failed for the wrong reason: $message")
        }
    }
}

if (-not (Test-Path -LiteralPath $releaseTagCommitValidatorPath -PathType Leaf)) {
    $failures.Add('scripts/AssertReleaseTagCommit.ps1 must own the release tag-to-artifact commit assertion.')
} else {
    $expectedCommit = '0123456789abcdef0123456789abcdef01234567'
    try {
        & $releaseTagCommitValidatorPath `
            -ExpectedCommitSha $expectedCommit `
            -ActualTagCommitSha $expectedCommit
    } catch {
        $failures.Add('The release tag-commit assertion must accept an exact commit match.')
    }

    $mismatchAccepted = $true
    try {
        & $releaseTagCommitValidatorPath `
            -ExpectedCommitSha $expectedCommit `
            -ActualTagCommitSha 'ffffffffffffffffffffffffffffffffffffffff'
    } catch {
        $mismatchAccepted = $false
    }
    if ($mismatchAccepted) {
        $failures.Add('The release tag-commit assertion must reject a moved tag before new publication.')
    }
}

if (-not (Test-Path -LiteralPath $versionGeneratorPath -PathType Leaf)) {
    $failures.Add('scripts/GenerateVersion.ps1 must own and validate release version generation.')
} else {
    function Invoke-VersionGenerator {
        param(
            [string] $RefType,
            [string] $RefName,
            [string] $CommitSha = '0123456789abcdef0123456789abcdef01234567'
        )

        $caseRoot = Join-Path ([IO.Path]::GetTempPath()) ("pacs-version-contract-" + [guid]::NewGuid().ToString('N'))
        $outputPath = Join-Path $caseRoot 'Version.ahk'
        [void](New-Item -ItemType Directory -Path $caseRoot)
        try {
            try {
                $messages = @(& $versionGeneratorPath -RefType $RefType -RefName $RefName -CommitSha $CommitSha -OutputPath $outputPath 2>&1)
                return [pscustomobject]@{
                    Succeeded = $true
                    Content = Get-Content -Raw -LiteralPath $outputPath
                    Message = $messages -join [Environment]::NewLine
                }
            } catch {
                return [pscustomobject]@{
                    Succeeded = $false
                    Content = ''
                    Message = $_.Exception.Message
                }
            }
        } finally {
            Remove-Item -LiteralPath $caseRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $tagResult = Invoke-VersionGenerator -RefType tag -RefName 'v2.3.4-beta.1+build.5'
    if (-not $tagResult.Succeeded) {
        $failures.Add("Valid SemVer tag generation failed: $($tagResult.Message)")
    } else {
        Assert-Matches $tagResult.Content 'static current := "v2\.3\.4-beta\.1\+build\.5"' 'Generated AppVersion must retain the exact valid release tag.'
        Assert-Matches $tagResult.Content 'Ahk2Exe-SetVersion 2\.3\.4\.0' 'Generated file metadata must use the numeric SemVer core.'
        Assert-Matches $tagResult.Content 'static isDevBuild := false' 'Tagged builds must not be marked as development builds.'
    }

    $devResult = Invoke-VersionGenerator -RefType branch -RefName 'main'
    if (-not $devResult.Succeeded) {
        $failures.Add("Development version generation failed: $($devResult.Message)")
    } else {
        Assert-Matches $devResult.Content 'static current := "v0\.0\.0-dev\+0123456"' 'Development builds must include the short commit identity.'
        Assert-Matches $devResult.Content 'static isDevBuild := true' 'Branch builds must be marked as development builds.'
    }

    foreach ($invalidTag in @(
        'v01.2.3',
        'v1.02.3',
        'v1.2.03',
        'v1.2.3-alpha..1',
        'v1.2.3-01',
        'v1.2.3+',
        'v1.2.3-alpha_1',
        'v65536.0.0',
        ('v1.2.' + [char]0x0663)
    )) {
        $invalidResult = Invoke-VersionGenerator -RefType tag -RefName $invalidTag
        if ($invalidResult.Succeeded) {
            $failures.Add("Invalid release tag was accepted: $invalidTag")
        }
    }
}

if (-not (Test-Path -LiteralPath $noticesPath -PathType Leaf)) {
    $failures.Add('THIRD_PARTY_NOTICES.md must accompany the bundled UIA-v2 dependency.')
} else {
    $notices = Get-Content -Raw $noticesPath
    Assert-Matches $notices 'UIA-v2' 'Third-party notices must name UIA-v2.'
    Assert-Matches $notices 'AutoHotkey v2\.0\.26' 'Third-party notices must name the embedded AutoHotkey runtime.'
    Assert-Matches $notices '\[repository license copy\]\(licenses/AutoHotkey-v2\.0\.26\.txt\)' 'Third-party notices must link the license at its real repository path.'
    Assert-Matches $notices 'Published release asset:\s*`AutoHotkey-v2\.0\.26\.txt`' 'Third-party notices must also identify the flat published license asset.'
    Assert-Matches $notices 'AutoHotkey-v2\.0\.26-source\.zip' 'Third-party notices must identify the runtime corresponding-source release asset.'
    Assert-Matches $notices 'MIT License' 'Third-party notices must include the UIA-v2 MIT license.'
    Assert-Matches $notices 'Copyright \(c\) 2023 Descolada' 'Third-party notices must preserve the UIA-v2 copyright notice.'
}

if (-not (Test-Path -LiteralPath $autoHotkeyLicensePath -PathType Leaf)) {
    $failures.Add('The AutoHotkey runtime license must accompany release builds.')
} else {
    $autoHotkeyLicense = Get-Content -Raw $autoHotkeyLicensePath
    Assert-Matches $autoHotkeyLicense 'GNU GENERAL PUBLIC LICENSE\s+Version 2' 'The AutoHotkey license copy must include GPL version 2.'
    Assert-Matches $autoHotkeyLicense 'PCRE LICENCE' 'The AutoHotkey license copy must retain the bundled PCRE notice.'
}

try {
    & (Join-Path $PSScriptRoot 'ReleaseWorkflowTest.ps1')
} catch {
    $failures.Add("The release workflow regression fixtures failed: $($_.Exception.Message)")
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Repository contract checks passed.'
