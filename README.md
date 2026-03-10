# Five Minute Note

A macOS menubar scratchpad that self-destructs. Open it, dump text, walk away — it disappears on its own.

## How It Works

- **`Cmd+Option+Control+Space`** summons the window from anywhere
- Type whatever you need — every keystroke resets the 5-minute timer
- Stop typing and the countdown begins
- When the timer hits zero, the window closes and your text is gone. No file saved, no trace.
- The app stays in the menubar, ready for the next note

## Controls

| Action | What it does |
|---|---|
| `Cmd+Option+Control+Space` | Toggle the window |
| `Escape` | Hide the window (text survives) |
| `+5m` button | Extend the timer by 5 minutes |
| Trash button | Destroy the note immediately |
| Click menubar icon | Toggle the window |

## Timer

- Displays in the bottom-right corner as `M:SS`
- Gray when plenty of time remains
- **Amber** under 60 seconds
- **Red** under 15 seconds
- The menubar icon becomes a draining pie chart in the final 60 seconds

## Building

Requires Xcode 15+ and macOS 13 (Ventura) or later.

```bash
# Generate the Xcode project
brew install xcodegen
xcodegen generate

# Build
xcodebuild -project FiveMinuteNote.xcodeproj -scheme FiveMinuteNote -configuration Debug build

# Or open in Xcode
open FiveMinuteNote.xcodeproj
```

## Installing

Copy the built app to `/Applications`:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/FiveMinuteNote-*/Build/Products/Debug/FiveMinuteNote.app "/Applications/Five Minute Note.app"
```

On first launch, macOS will prompt for **Accessibility** permissions (needed for the global hotkey). Grant access in **System Settings → Privacy & Security → Accessibility**.

## Testing

```bash
# Run all tests
xcodebuild test -project FiveMinuteNote.xcodeproj -scheme FiveMinuteNote -configuration Debug
```

73 unit tests across three suites:

| Suite | Tests | Covers |
|---|---|---|
| `NoteStateTests` | 38 | Timer lifecycle, countdown, expiry notification, adaptive interval, keystroke reset, +5m extension, 24h cap, note destruction, date-based accuracy, singleton |
| `TimerViewTests` | 23 | `M:SS` formatting, ceil rounding, negative clamping, color thresholds (gray → amber → red) |
| `NoteTextEditorCoordinatorTests` | 12 | 100K character limit, paste rejection, deletion at limit, UTF-16 counting, coordinator flag |

## Configuration

Edit the top of `FiveMinuteNote/FiveMinuteNoteApp.swift`:

```swift
let defaultTimerMinutes: Int = 5
let hotkeyModifiers: CGEventFlags = [.maskCommand, .maskOption, .maskControl]
let hotkeyKeyCode: Int64 = Int64(kVK_Space)
```

## Known Quirks

- From Chromium-based apps (Chrome, VS Code), the hotkey may require a double-tap if the chosen shortcut conflicts with the app's built-in bindings. The default `Cmd+Option+Control+Space` avoids most conflicts.
