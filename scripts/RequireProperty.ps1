# Shared by the release validators. A GitHub API object that lacks a property the
# validator relies on fails here with the object's context, rather than later as a
# less specific StrictMode error.
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
