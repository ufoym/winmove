# WinMove

A lightweight macOS menu-bar utility for snapping and moving the focused window with a hold-and-tap keyboard trigger.

Hold the trigger chord (default: ⌃⌥⌘) and tap an arrow, Space, or Return to resize/reposition the frontmost window. Repeated taps cycle between halves, thirds, and two-thirds.

## Features

- Halves, thirds, two-thirds, and quarter tilings
- Maximize and center
- Arrow-combo quarters (e.g. ⬆ + ⬅ for top-left)
- Live preview overlay while the trigger is held
- Custom keybinds and configurable trigger key
- JSON import/export of settings
- Runs as a menu-bar app (no Dock icon)

## Default Keybinds

Hold **⌃⌥⌘** and tap:

| Key          | Action                                              |
|--------------|-----------------------------------------------------|
| Space        | Maximize                                            |
| Return       | Center                                              |
| ←            | Left — cycles 1/2 · 1/3 · 2/3                        |
| →            | Right — cycles 1/2 · 1/3 · 2/3                       |
| ↑            | Top — cycles 1/2 · 1/3 · 2/3                         |
| ↓            | Bottom — cycles 1/2 · 1/3 · 2/3                      |
| ↑ + ←        | Top-left quarter                                    |
| ↑ + →        | Top-right quarter                                   |
| ↓ + ←        | Bottom-left quarter                                 |
| ↓ + →        | Bottom-right quarter                                |

All keybinds and the trigger chord can be customized in Settings.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ toolchain (to build from source)

## Build

```sh
./build.sh          # Debug build
./build.sh release  # Release build
```

The resulting bundle is written to `./build/winmove.app`.

## Install & Run

1. `open ./build/winmove.app`
2. Grant **Accessibility** permission when prompted
   (System Settings → Privacy & Security → Accessibility).
3. Hold ⌃⌥⌘ and tap ← / → / ↑ / ↓ / Space / Return.

Open the menu-bar icon for Settings, or to quit.

## Project Layout

```
Package.swift          SwiftPM manifest
build.sh               Builds the .app bundle
Resources/             Info.plist, icons
Sources/winmove/       Swift sources
```

## License

Copyright © 2026 ufoym. All rights reserved.
