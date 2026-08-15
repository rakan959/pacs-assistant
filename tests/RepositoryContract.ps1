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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflow = Get-Content -Raw (Join-Path $repoRoot '.github/workflows/ahk2exe.yml')
$gitmodules = Get-Content -Raw (Join-Path $repoRoot '.gitmodules')
$readme = Get-Content -Raw (Join-Path $repoRoot 'README.md')
$issueTemplate = Get-Content -Raw (Join-Path $repoRoot '.github/ISSUE_TEMPLATE/bug_report.md')
$main = Get-Content -Raw (Join-Path $repoRoot 'main.ahk')
$profileManager = Get-Content -Raw (Join-Path $repoRoot 'ProfileManager.ahk')
$powerScribe = Get-Content -Raw (Join-Path $repoRoot 'PowerScribe.ahk')
$wetRead = Get-Content -Raw (Join-Path $repoRoot 'WetRead.ahk')
$noticesPath = Join-Path $repoRoot 'THIRD_PARTY_NOTICES.md'
$autoHotkeyLicensePath = Join-Path $repoRoot 'licenses/AutoHotkey-v2.0.26.txt'

Assert-Matches $gitmodules '(?m)^\s*url\s*=\s*https://github\.com/Descolada/UIA-v2\.git\s*$' 'UIA-v2 must use a public HTTPS submodule URL.'

$uiaCommit = (& git -C (Join-Path $repoRoot 'UIA-v2') rev-parse HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0) {
    $failures.Add('UIA-v2 must be initialized before repository checks run.')
} elseif ($uiaCommit -ne '9f5a181c5d56d0cbc04e0a709fb875ab0059f762') {
    $failures.Add("UIA-v2 must be pinned to v1.1.3 (found $uiaCommit).")
}

Assert-Matches $workflow '(?m)^\s*AUTOHOTKEY_VERSION:\s*2\.0\.26\s*$' 'CI must pin AutoHotkey v2.0.26.'
Assert-Matches $workflow '(?m)^\s*AUTOHOTKEY_SHA256:\s*43522aa3122a57784ac5db30abf85c2244475c36acd7796e2c993355f9e926ae\s*$' 'CI must verify the official AutoHotkey v2.0.26 ZIP digest.'
Assert-Matches $workflow '(?m)^\s*AHK2EXE_VERSION:\s*1\.1\.37\.02a2\s*$' 'CI must pin Ahk2Exe v1.1.37.02a2.'
Assert-Matches $workflow '(?m)^\s*AHK2EXE_SHA256:\s*c29b8c3a5124850d79fc9e66e2ca79677c377d7f31631ad3022ba159c5d9e3be\s*$' 'CI must verify the official Ahk2Exe v1.1.37.02a2 ZIP digest.'
Assert-Matches $workflow '(?m)^\s*contents:\s*read\s*$' 'The default workflow token permission must be contents: read.'
Assert-Matches $workflow '(?ms)^\s{2}release:\s.*?^\s{4}permissions:\s*\r?\n\s{6}contents:\s*write\s*$' 'Only the release job may request contents: write.'
if ([regex]::Matches($workflow, '(?m)^\s*contents:\s*write\s*$').Count -ne 1) {
    $failures.Add('Exactly one job, the release job, may request contents: write.')
}
Assert-Matches $workflow '(?m)^\s*runs-on:\s*windows-2025\s*$' 'The build job must use a versioned Windows runner image.'
Assert-Matches $workflow '(?m)^\s*runs-on:\s*ubuntu-24\.04\s*$' 'The release job must use a versioned Ubuntu runner image.'
Assert-NotMatches $workflow '(?m)^\s*runs-on:\s*\S+-latest\s*$' 'Workflow runner labels must not float on -latest.'
Assert-Matches $workflow '(?m)^\s*& tests/RepositoryContract\.ps1\s*$' 'CI must run the repository contract check.'
Assert-Matches $workflow '(?m)^\s*licenses/AutoHotkey-v2\.0\.26\.txt\s*$' 'Release artifacts must include the AutoHotkey runtime license.'

foreach ($match in [regex]::Matches($workflow, '(?m)^\s*uses:\s*(?<reference>\S+)\s*$')) {
    $reference = $match.Groups['reference'].Value
    if ($reference -notmatch '@[0-9a-f]{40}$') {
        $failures.Add("GitHub Action is not pinned to an immutable commit: $reference")
    }
    $action = $reference.Split('@')[0]
    if ($action -notin @('actions/checkout', 'actions/upload-artifact', 'actions/download-artifact')) {
        $failures.Add("GitHub Action is not on the reviewed first-party allowlist: $action")
    }
}

Assert-NotMatches $workflow '(?m)^\s*packages:\s*write\s*$' 'The workflow must not request unused packages: write permission.'
Assert-NotMatches $workflow '(?i)benmusson/ahk2exe-action|softprops/action-gh-release' 'Build and release must not delegate downloaded binaries or release authority to third-party actions.'
Assert-NotMatches $workflow 'Ahk2Exe-SetCopyright\s+MIT' 'Executable copyright metadata must not mislabel the GPL-3.0 project as MIT.'

Assert-NotMatches $profileManager '(?m)^#Include\s+PACSCommands\.ahk\s*$' 'Profile persistence must not depend on the clinical command graph.'
Assert-NotMatches $powerScribe '\bProfileManager\b' 'PowerScribe automation must not reach profile state through an implicit global.'
Assert-Matches $wetRead '(?m)^#Include\s+ProfileManager\.ahk\s*$' 'The wet-read composition layer must declare its profile dependency.'
foreach ($subscriber in @('UpdateChecker', 'PACSMonitor', 'MicrophoneManager')) {
    Assert-Matches $main ("Settings\.AddChangeListener\(ObjBindMethod\(" + $subscriber) ("main.ahk must explicitly subscribe " + $subscriber + " to settings changes.")
}

Assert-Matches $readme 'git clone --recurse-submodules' 'README must document cloning with submodules.'
Assert-Matches $readme 'AutoHotkey v2\.0\.26' 'README must state the AutoHotkey version used by CI.'
Assert-Matches $readme 'Ahk2Exe v1\.1\.37\.02a2' 'README must state the Ahk2Exe version used by CI.'
Assert-Matches $readme 'THIRD_PARTY_NOTICES\.md' 'README must link the bundled dependency notices.'
Assert-Matches $readme 'GPL-3\.0' 'README must identify the project license.'

Assert-NotMatches $issueTemplate '(?i)\bsmartphone\b|\bbrowser\b|\biOS\b' 'The bug template must not ask irrelevant browser or smartphone questions.'
Assert-Matches $issueTemplate 'PowerScribe' 'The bug template must request PowerScribe context.'
Assert-Matches $issueTemplate '\bPACS\b' 'The bug template must request PACS context.'

if (-not (Test-Path -LiteralPath $noticesPath -PathType Leaf)) {
    $failures.Add('THIRD_PARTY_NOTICES.md must accompany the bundled UIA-v2 dependency.')
} else {
    $notices = Get-Content -Raw $noticesPath
    Assert-Matches $notices 'UIA-v2' 'Third-party notices must name UIA-v2.'
    Assert-Matches $notices 'AutoHotkey v2\.0\.26' 'Third-party notices must name the embedded AutoHotkey runtime.'
    Assert-Matches $notices 'licenses/AutoHotkey-v2\.0\.26\.txt' 'Third-party notices must link the AutoHotkey runtime license.'
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

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }
    exit 1
}

Write-Host 'Repository contract checks passed.'
