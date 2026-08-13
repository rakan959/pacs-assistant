#Requires AutoHotkey v2.0

/**
 * Application version.
 *
 * CI regenerates this file from the git tag before compiling - see
 * .github/workflows/ahk2exe.yml. The value committed here is the placeholder used for
 * local and untagged builds.
 *
 * Do not hand-edit this to bump a release. The tag is the source of truth. Hand-syncing
 * a version constant to a tag is exactly what let the shipped build report v2.0b4 while
 * v2.0b7 was the published release.
 */
class AppVersion {
    ; Full version string, matching the git tag on a tagged build
    static current := "v0.0.0-dev"

    ; True for anything not built from a tag. Update checks are skipped for these, so a
    ; dev build never offers to overwrite itself with a release.
    static isDevBuild := true
}
