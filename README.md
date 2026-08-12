# PACS Assistant

PACS Assistant is a helpful tool designed to make your radiology workflow smoother and more efficient. It provides quick keyboard shortcuts and automated features to help you work faster with PowerScribe and PACS.

## 🌟 Features

### Quick Commands - can be assigned to any key!
- **Toggle Dictation** - Start or stop dictation
- **Select Next Field** - Move to the next field in PowerScribe
- **Select Previous Field** - Move to the previous field in PowerScribe
- **Delete Previous Word** - Quickly delete the word before the cursor
- **Delete Next Word** - Quickly delete the word after the cursor
- **Draft Report** - Draft your report
- **Sign Report** - Sign your report
- **Open/Force Restart PACS** - Restart PACS if it's frozen or not responding (asks PowerScribe to save first)
- **Paste Wet Read** - Copy your read and paste it as a PACS note
- **Toggle PowerScribe Window** - Quickly switch PowerScribe window to front/back
- **Toggle EPIC Window** - Quickly switch EPIC window to front/back
- **Set PowerScribe Microphone** - Pick your microphone on the PowerScribe login screen

### Smart Notifications
- Get notified when new studies arrive
- Choose from different notification sounds - each one is a different sound
- See study types at a glance
- Stay focused with non-intrusive alerts

### Customization
- Create custom keyboard shortcuts
- Limit any shortcut to PACS, PowerScribe, or both
- Assign an attending per modality
- Set up multiple profiles for different workflows
- Choose which notifications you want to receive
- Adjust refresh intervals for new study checks

## 🚀 Getting Started

1. **Download**
   - Download the latest version from the releases page
   - Place the file in your preferred directory (profiles will be stored here)
   - Run pacs-assistant.exe - no installation required!

2. **Initial Setup**
   - Create a profile when first launching
   - Set up your preferred keyboard shortcuts
   - Configure notification settings

3. **Basic Usage**
   - Use keyboard shortcuts to perform actions
   - Watch for notifications about new studies
   - Switch between profiles as needed

## ⚙️ Settings

### Notifications
- **Auto Refresh**: Choose if PACS should automatically check for new studies
- **Sound Alerts**: Pick from various notification sounds
- **Visual Alerts**: Enable/disable pop-up notifications
- **Refresh Interval**: Set how often to check for new studies

### PowerScribe
- **Set microphone on login**: Selects your microphone on the PowerScribe login screen
- **Microphone**: The name to pick, matched on part of the name (e.g. `PowerMic` matches `PowerMic III`). Leave blank to leave the selection alone

### Updates
- **Auto Update**: Choose to automatically check for new versions
- **Beta Versions**: Opt in/out of beta updates

## 🎯 Tips & Tricks

1. **Wet Reads**
   - Copy your wet read text
   - Use the wet read shortcut
   - The PACS note will be created automatically
   - The report will automatically be assigned to the appropriate section queue

2. **Multiple Profiles**
   - Create different profiles for different workflows
   - Switch between profiles easily
   - Each profile can have its own shortcuts

3. **Custom Shortcuts**
   - Create shortcuts for frequently used actions
   - Assign them to easy-to-remember key combinations
   - Target specific windows for certain actions

4. **Keybind Scope**
   - Select a keybind and click **Set Scope**
   - Tick PACS and/or PowerScribe to only fire that shortcut when one of them is in front
   - Leave both unticked and the shortcut works everywhere, which is how every existing keybind behaves

5. **Modality Attendings**
   - Click **Modality Attendings** to assign an attending per modality for the current profile
   - Wet reads are routed to the attending assigned to the study's modality
   - Leave a modality blank to keep whatever default attending PowerScribe already has
   - Each profile has its own assignments, so a call shift assigned by modality can be its own profile

## 🧪 Development

Tests run headlessly and need nothing but AutoHotkey v2:

```
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" tests\run-tests.ahk
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" tests\run-hotkey-tests.ahk
```

`run-tests.ahk` covers modality classification, alert sounds, scope handling and
profile persistence. `run-hotkey-tests.ahk` registers real hotkeys and synthesises
keystrokes to check that binds survive being disabled and re-applied. Both exit
non-zero on failure.

To check syntax without running:

```
"C:\Program Files\AutoHotkey\v2\AutoHotkey.exe" /validate /ErrorStdOut main.ahk
```

## 🆘 Need Help?

If you encounter any issues:
1. Check if PACS Assistant is running (look for the icon in your system tray)
2. Make sure PowerScribe and PACS are open
3. Try restarting PACS Assistant
4. If all else fails, text me