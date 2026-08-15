[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseJson,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $pages = ConvertFrom-Json -InputObject $ReleaseJson -NoEnumerate
} catch {
    throw "Release listing was not valid JSON: $($_.Exception.Message)"
}

$matches = [Collections.Generic.List[psobject]]::new()
foreach ($page in @($pages)) {
    foreach ($release in @($page)) {
        if ($null -eq $release -or $release.PSObject.Properties.Name -cnotcontains 'tag_name') {
            throw 'Release listing contained an object without tag_name.'
        }
        if ([string] $release.tag_name -ceq $ReleaseTag) {
            $matches.Add($release)
        }
    }
}

if ($matches.Count -gt 1) {
    throw "GitHub returned multiple releases for exact tag '$ReleaseTag'."
}
if ($matches.Count -eq 1) {
    Write-Output -NoEnumerate $matches[0]
}
