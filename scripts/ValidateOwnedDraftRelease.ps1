[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [psobject] $Release,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseTag,

    [Parameter(Mandatory)]
    [bool] $ExpectedPrerelease,

    [ValidateNotNullOrEmpty()]
    [string] $ExpectedAuthorLogin = 'github-actions[bot]'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'RequireProperty.ps1')

foreach ($property in @('id', 'draft', 'prerelease', 'tag_name', 'name', 'author')) {
    Require-Property -Object $Release -Name $property -Context 'Draft release'
}
# ConvertFrom-Json yields Int64 for JSON integers; accept only integral IDs.
if (-not ($Release.id -is [long] -or $Release.id -is [int]) -or $Release.id -le 0) {
    throw "Draft release '$ReleaseTag' has an invalid database ID."
}
if ($Release.draft -isnot [bool] -or -not $Release.draft) {
    throw "Release '$ReleaseTag' is not an unpublished draft."
}
if ($Release.prerelease -isnot [bool] -or $Release.prerelease -ne $ExpectedPrerelease) {
    throw "Draft release '$ReleaseTag' has the wrong prerelease classification."
}
if ([string] $Release.tag_name -cne $ReleaseTag) {
    throw "Draft release tag does not exactly match '$ReleaseTag'."
}
if ([string] $Release.name -cne $ReleaseTag) {
    throw "Draft release '$ReleaseTag' does not use the tag as its exact title."
}
if ($null -eq $Release.author) {
    throw "Draft release '$ReleaseTag' has no author identity."
}
Require-Property -Object $Release.author -Name 'login' -Context 'Draft release author'
if ([string] $Release.author.login -cne $ExpectedAuthorLogin) {
    throw "Draft release '$ReleaseTag' has unexpected author '$($Release.author.login)'."
}

Write-Host "Draft release '$ReleaseTag' is owned by the release workflow."
