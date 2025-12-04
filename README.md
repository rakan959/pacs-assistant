# PACS Assistant

PACS Assistant makes your radiology workflow faster with keyboard shortcuts, smart monitoring, and profile-based customization for PowerScribe and PACS.

## Features

### Quick commands (bind to any key)
- Toggle Dictation, Draft Report, Sign Report
- Select Next/Previous Field, Delete Previous/Next Word
- Open/Force Restart PACS
- Paste Wet Read (optional LF→CRLF conversion; choose Ctrl+V, UIA Value, or ControlSetText paste)
- Toggle PowerScribe / EPIC windows, Next/Previous Series

### Profiles & custom binds
- Multiple profiles with default selection
- Custom keybind creator (send keys to any window)
- GUI to add/change/remove binds and set a default profile

### Monitoring & notifications
- Auto-refresh PACS (interval configurable)
- New study detection with tray notifications and optional sounds
- Per-setting controls for audio and message notifications

### Updates
- Optional auto-check for updates
- Skip beta versions
- Background-only error logging (no popups)

## Getting started

1) **Download**
- Tagged releases publish `pacs-assistant.exe`.
- Dev pushes upload a `pacs-assistant-dev` artifact from CI.
- Place the EXE anywhere; profiles/settings live alongside it.

2) **Initial setup**
- Launch, create a profile, assign keybinds, and set notification/update preferences.

3) **Wet read workflow**
- Copy your wet read text to clipboard.
- Use the wet read hotkey; if prompted, pick a paste method (Ctrl+V/UIA Value/ControlSetText).
- Enable “Convert clipboard line endings” in Settings to normalize LF→CRLF before pasting.

## Settings
- Auto refresh PACS + interval
- Convert clipboard line endings (LF→CRLF) for wet reads
- Notifications: sound on/off, message popups, choose system sound, custom sound file
- Updates: auto-check toggle, skip betas

## Tests
- Run all tests:\
  `& "$Env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tests/RunTests.ahk`
- Test runner suppresses MsgBoxes and writes results to stdout.

## CI / builds
- GitHub Actions builds on every push:\
  - Tagged pushes publish a release with `pacs-assistant.exe`.\
  - Other pushes upload a `pacs-assistant-dev` artifact for quick testing.

## Need help?
- Ensure PACS Assistant is running (tray icon).
- Make sure PowerScribe and PACS are open.
- Try restarting PACS Assistant.
