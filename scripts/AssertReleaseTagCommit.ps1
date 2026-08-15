[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $ExpectedCommitSha,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string] $ActualTagCommitSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ActualTagCommitSha -ine $ExpectedCommitSha) {
    throw "Release tag resolves to $ActualTagCommitSha, not workflow commit $ExpectedCommitSha."
}

Write-Host "Release tag resolves to the workflow commit $ExpectedCommitSha."
