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

foreach ($property in @('id', 'draft', 'prerelease', 'tag_name', 'name', 'author')) {
    Require-Property -Object $Release -Name $property -Context 'Interrupted release'
}
if ($Release.id -isnot [ValueType] -or [long] $Release.id -le 0) {
    throw "Interrupted release '$ReleaseTag' has an invalid database ID."
}
if ($Release.draft -isnot [bool] -or -not $Release.draft) {
    throw "Release '$ReleaseTag' is not an unpublished draft."
}
if ($Release.prerelease -isnot [bool] -or $Release.prerelease -ne $ExpectedPrerelease) {
    throw "Interrupted draft '$ReleaseTag' has the wrong prerelease classification."
}
if ([string] $Release.tag_name -cne $ReleaseTag) {
    throw "Interrupted draft tag does not exactly match '$ReleaseTag'."
}
if ([string] $Release.name -cne $ReleaseTag) {
    throw "Interrupted draft '$ReleaseTag' does not use the tag as its exact title."
}
if ($null -eq $Release.author) {
    throw "Interrupted draft '$ReleaseTag' has no author identity."
}
Require-Property -Object $Release.author -Name 'login' -Context 'Interrupted release author'
if ([string] $Release.author.login -cne $ExpectedAuthorLogin) {
    throw "Interrupted draft '$ReleaseTag' has unexpected author '$($Release.author.login)'."
}

Write-Host "Interrupted draft '$ReleaseTag' is owned by the release workflow and may be reconciled."
