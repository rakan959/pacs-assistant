# PACS Assistant

PACS Assistant makes your radiology workflow faster with keyboard shortcuts, smart monitoring, and profile-based customization for PowerScribe and PACS.

## Features

### Quick commands (bind to any key)
- Toggle Dictation, Draft Report, Sign Report
- Select Next/Previous Field, Delete Previous/Next Word
- Open/Force Restart PACS (asks PowerScribe to save first, answering the save prompt)
- Paste Wet Read (optional LF→CRLF conversion; choose Ctrl+V, UIA Value, or ControlSetText paste)
- Toggle PowerScribe / EPIC windows, Next/Previous Series
- Set PowerScribe Microphone

### Profiles & custom binds
- Multiple profiles with default selection
- Custom keybind creator (send keys to any window)
- GUI to add/change/remove binds and set a default profile
- Per-bind scope: limit a shortcut to PACS, PowerScribe, or both. Outside its scope the
  key is passed through to whatever app is focused rather than being swallowed
- Per-modality attending assignment, used when routing a wet read

### Monitoring & notifications
- Auto-refresh PACS (interval configurable)
- New study detection with tray notifications and optional sounds
- Alert sounds are backed by distinct files, so the options are audibly different
- Warns if the refresh button can't be found instead of failing silently

### Updates
- Optional auto-check for updates
- Skip beta versions
- Background failures emit debugger diagnostics without interrupting the clinical workflow

## Getting started

1) **Download**
- Tagged releases publish `pacs-assistant.exe` with the applicable license notices.
- Untagged pushes upload a `pacs-assistant-build` artifact from CI.
- Place the EXE anywhere; profiles/settings live alongside it.

2) **Initial setup**
- Launch, create a profile, assign keybinds, and set notification/update preferences.

3) **Wet read workflow**
- Copy your wet read text to clipboard.
- Use the wet read hotkey; if prompted, pick a paste method (Ctrl+V/UIA Value/ControlSetText).
- Enable "Convert clipboard line endings" in Settings to normalize LF→CRLF before pasting.

4) **Keybind scope**
- Select a bind and click **Set Scope**.
- Tick PACS and/or PowerScribe to fire only when one of them is in front; leave both
  unticked for a bind that works everywhere.

5) **Modality attendings**
- Click **Modality Attendings** to assign an attending per modality for the current profile.
- Wet reads route to the attending assigned to the study's modality.
- Leave a modality blank to keep whatever default attending PowerScribe already has.
- Assignments are per profile, so a call shift assigned by modality can be its own profile.

## Settings
- Auto refresh PACS + interval
- Convert clipboard line endings (LF→CRLF) for wet reads
- PowerScribe: set microphone on login, and the name to match (part of the name is
  enough — `PowerMic` matches `PowerMic III`)
- Notifications: sound on/off, message popups, choose alert sound, custom sound file
- Updates: auto-check toggle, skip betas

Hotkey scope is set per bind from the main window, not here.

## Development setup

Development and CI target Windows with PowerShell 7, AutoHotkey v2.0.26, and UIA-v2
v1.1.3. Ahk2Exe v1.1.37.02a2 is also required to build the release executable.

Clone the repository and initialize its pinned submodule:

```powershell
git clone --recurse-submodules https://github.com/rakan959/pacs-assistant.git
Set-Location pacs-assistant
```

For an existing clone:

```powershell
git submodule sync --recursive
git submodule update --init --recursive
```

CI downloads the official tool archives and verifies them before execution:

| Tool | Official archive | SHA-256 |
|---|---|---|
| AutoHotkey v2.0.26 | [AutoHotkey_2.0.26.zip](https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip) | `43522aa3122a57784ac5db30abf85c2244475c36acd7796e2c993355f9e926ae` |
| AutoHotkey v2.0.26 source | [v2.0.26.zip](https://github.com/AutoHotkey/AutoHotkey/archive/refs/tags/v2.0.26.zip) | `765ada5ae0a543f470bcd30371a7b95438e59351b0a20508c516df76a4f73ca4` |
| Ahk2Exe v1.1.37.02a2 | [Ahk2Exe1.1.37.02a2.zip](https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.02a2/Ahk2Exe1.1.37.02a2.zip) | `c29b8c3a5124850d79fc9e66e2ca79677c377d7f31631ad3022ba159c5d9e3be` |

Verify a downloaded archive before extracting it:

```powershell
$archive = 'C:\path\to\download.zip'
(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
```

## Tests

All suites exit non-zero on failure.

```powershell
$ahk = "$Env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"

function Invoke-AutoHotkeyChecked {
  param([Parameter(Mandatory)][string[]] $ArgumentList)

  # AutoHotkey is a GUI-subsystem executable. Start-Process is required here so
  # PowerShell waits for completion and observes the suite's real exit code.
  $process = Start-Process -FilePath $ahk -ArgumentList $ArgumentList -NoNewWindow -Wait -PassThru
  if ($process.ExitCode -ne 0) {
    throw "AutoHotkey failed with exit code $($process.ExitCode): $($ArgumentList -join ' ')"
  }
}

# Syntax and deterministic unit tests; both run in CI.
Invoke-AutoHotkeyChecked @('/validate', '/ErrorStdOut', 'main.ahk')
Invoke-AutoHotkeyChecked @('/ErrorStdOut', 'tests/RunTests.ahk')

# Desktop integration checks; these register hotkeys and open real windows, so run locally.
Invoke-AutoHotkeyChecked @('/ErrorStdOut', 'tests/run-hotkey-tests.ahk')
Invoke-AutoHotkeyChecked @('/ErrorStdOut', 'tests/run-gui-smoke.ahk')

# CI, dependency, documentation, and distribution invariants.
& tests/RepositoryContract.ps1
```

The unit runner suppresses MsgBoxes and writes results to stdout. Add a new test by
writing a class with a `static Tests` list and registering it in `tests/RunTests.ahk`.

To reproduce the uncompressed release build with the verified archives:

```powershell
$compiler = 'C:\path\to\Ahk2Exe.exe'
$ahkBase = 'C:\path\to\AutoHotkey64.exe'
$process = Start-Process -FilePath $compiler -ArgumentList @(
  '/in', 'main.ahk',
  '/out', 'pacs-assistant.exe',
  '/base', $ahkBase,
  '/compress', '0',
  '/silent', 'verbose'
) -NoNewWindow -Wait -PassThru
if ($process.ExitCode -ne 0) {
  throw "Compilation failed (exit $($process.ExitCode))"
}
```

## Layout

| File | Holds |
|---|---|
| `main.ahk` | Startup: update check, PACS monitor, microphone watcher, GUI |
| `PACSCommands.ahk` | The command registry — what can be bound to a key |
| `PowerScribe.ahk` | Report reading, modality classification, attending routing |
| `AppControl.ahk` | Restarting PACS, the save-changes prompt, window toggles |
| `WetRead.ahk` | The wet-read workflow |
| `PACSMonitor.ahk` | Worklist polling and new-study alerts |
| `MicrophoneManager.ahk` | Microphone selection on the PowerScribe login screen |
| `KeybindGUI.ahk` | Main window and its dialogs |
| `HotkeyManager.ahk` | Hotkey registration and window scoping |
| `HotkeyContract.ahk` | Shared persisted/runtime hotkey contract and identity |
| `ProfileManager.ahk` | Profile load/save |
| `Settings.ahk` | Settings storage and the settings dialog |
| `UpdateChecker.ahk` | Release checks and self-update |
| `Version.ahk` | Generated by CI from the git tag |

## CI / builds

GitHub Actions validates the repository contract and syntax, runs the unit suite, and
builds on every push using a GitHub-hosted Windows runner. Build tools and actions are
pinned and verified; the build job has read-only repository permission. Tagged builds
hand the verified artifact to a separate release job with narrowly scoped write access.

- Tagged pushes publish `pacs-assistant.exe`, `LICENSE`,
  `THIRD_PARTY_NOTICES.md`, the AutoHotkey runtime license, and the exact
  `AutoHotkey-v2.0.26-source.zip` corresponding-source archive.
- Other pushes upload the same files as the `pacs-assistant-build` artifact.

## Versioning and releases

Versions follow [SemVer](https://semver.org): `vMAJOR.MINOR.PATCH`, with an optional
prerelease suffix such as `v2.1.0-beta.1`.

**The git tag is the only place a version is stated.** CI generates `Version.ahk` from
the tag before compiling, and the app reads `AppVersion.current` from it. Nothing is
hand-edited to bump a release — hand-syncing a constant to a tag is what previously let
the shipped build report `v2.0b4` while `v2.0b7` was published.

To cut a release:

```
git tag v2.1.0
git push origin v2.1.0
```

That's the whole process. CI compiles, stamps the EXE's file properties, generates
release notes from the commits, and publishes `pacs-assistant.exe`.

**Prereleases.** A tag containing a hyphen (`v2.1.0-beta.1`) is published as a GitHub
prerelease. The update checker uses that flag rather than reading the tag name:

| `Skip beta versions` | Endpoint | Sees |
|---|---|---|
| on (default) | `/releases/latest` | stable releases only — GitHub excludes prereleases |
| off | `/releases?per_page=1` | the newest release, prerelease or not |

Name betas with a hyphen, or users on default settings won't be offered them — and
don't name a stable release with one.

Untagged and uncompiled builds report `v0.0.0-dev` and skip update checks entirely, so
running from source never offers to overwrite `main.ahk` with an EXE.

## License

PACS Assistant is licensed under [GPL-3.0](LICENSE). The compiled executable also
contains the AutoHotkey runtime and the MIT-licensed UIA-v2 library. Their attribution,
license, and corresponding-source details are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Need help?
- Ensure PACS Assistant is running (tray icon).
- Make sure PowerScribe and PACS are open.
- Try restarting PACS Assistant.
