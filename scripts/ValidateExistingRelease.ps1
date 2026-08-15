[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [psobject] $Release,

    [Parameter(Mandatory)]
    [string] $ReleaseTag,

    [Parameter(Mandatory)]
    [bool] $ExpectedPrerelease,

    [bool] $ExpectedDraft = $false,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $ExpectedCommitSha,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $ActualTagCommitSha,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Assets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Property {
    param(
        [Parameter(Mandatory)] [psobject] $Object,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Context
    )

    if ($Object.PSObject.Properties.Name -cnotcontains $Name) {
        throw "$Context is missing required property '$Name'."
    }
}

foreach ($property in @('draft', 'prerelease', 'tag_name', 'name', 'assets')) {
    Require-Property -Object $Release -Name $property -Context 'Existing release'
}
if ($Release.draft -isnot [bool] -or $Release.draft -ne $ExpectedDraft) {
    $expectedState = $ExpectedDraft ? 'an unpublished draft' : 'published (draft=false)'
    throw "Existing release '$ReleaseTag' must be $expectedState."
}
if ($Release.prerelease -isnot [bool] -or $Release.prerelease -ne $ExpectedPrerelease) {
    throw "Existing release '$ReleaseTag' has the wrong prerelease classification."
}
if ([string] $Release.tag_name -cne $ReleaseTag) {
    throw "Existing release tag does not exactly match '$ReleaseTag'."
}
if ([string] $Release.name -cne $ReleaseTag) {
    throw "Existing release '$ReleaseTag' must use the tag as its exact title."
}
if ($ActualTagCommitSha -ine $ExpectedCommitSha) {
    throw "Release tag '$ReleaseTag' resolves to $ActualTagCommitSha, not workflow commit $ExpectedCommitSha."
}

$localByName = [Collections.Generic.Dictionary[string, IO.FileInfo]]::new(
    [StringComparer]::Ordinal
)
foreach ($assetPath in $Assets) {
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        throw "Release asset is missing: $assetPath"
    }
    $localFile = Get-Item -LiteralPath $assetPath
    if (-not $localByName.TryAdd($localFile.Name, $localFile)) {
        throw "Local release assets contain duplicate basename '$($localFile.Name)'."
    }
}

$remoteAssets = @($Release.assets)
if ($remoteAssets.Count -ne $localByName.Count) {
    throw "Existing release '$ReleaseTag' must contain exactly the approved asset set."
}
$remoteByName = [Collections.Generic.Dictionary[string, psobject]]::new(
    [StringComparer]::Ordinal
)
foreach ($remoteAsset in $remoteAssets) {
    foreach ($property in @('name', 'size', 'digest')) {
        Require-Property -Object $remoteAsset -Name $property -Context 'Existing release asset'
    }
    $assetName = [string] $remoteAsset.name
    if (-not $remoteByName.TryAdd($assetName, $remoteAsset)) {
        throw "Existing release '$ReleaseTag' contains duplicate asset '$assetName'."
    }
}

foreach ($entry in $localByName.GetEnumerator()) {
    $assetName = $entry.Key
    $localFile = $entry.Value
    $remoteAsset = $null
    if (-not $remoteByName.TryGetValue($assetName, [ref] $remoteAsset)) {
        throw "Existing release '$ReleaseTag' is missing approved asset '$assetName'."
    }
    $localDigest = 'sha256:' + (Get-FileHash -LiteralPath $localFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteDigest = [string] $remoteAsset.digest
    if ($remoteAsset.size -ne $localFile.Length -or $remoteDigest.ToLowerInvariant() -cne $localDigest) {
        throw "Existing release '$ReleaseTag' has different bytes for '$assetName'; published assets are immutable."
    }
}

$state = $ExpectedDraft ? 'draft upload' : 'immutable publication'
Write-Host "Existing release '$ReleaseTag' exactly matches the $state contract."
