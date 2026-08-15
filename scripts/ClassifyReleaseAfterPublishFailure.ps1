[CmdletBinding()]
param(
    [AllowNull()]
    [psobject] $Release,

    [Parameter(Mandatory)]
    [ValidateRange(1, [long]::MaxValue)]
    [long] $CreatedDraftId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseTag,

    [Parameter(Mandatory)]
    [bool] $ExpectedPrerelease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($null -eq $Release) {
    return 'leave'
}
if ($Release.PSObject.Properties.Name -cnotcontains 'id') {
    throw "Release state after publishing '$ReleaseTag' has no database ID."
}

try {
    $releaseId = [long] $Release.id
} catch {
    throw "Release state after publishing '$ReleaseTag' has an invalid database ID."
}
if ($releaseId -ne $CreatedDraftId) {
    return 'leave'
}
if ($Release.PSObject.Properties.Name -cnotcontains 'draft' -or $Release.draft -isnot [bool]) {
    throw "Release state after publishing '$ReleaseTag' has no valid draft state."
}

if (-not $Release.draft) {
    return 'published'
}

& (Join-Path $PSScriptRoot 'ValidateOwnedDraftRelease.ps1') `
    -Release $Release `
    -ReleaseTag $ReleaseTag `
    -ExpectedPrerelease $ExpectedPrerelease
return 'cleanup-draft'
