# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Sidle is a free, open-source macOS menu bar app (Swift, SwiftPM, macOS 14+, Apple silicon) that adds trackpad edge gestures in the style of MacEdge: click-and-slide on the right edge for volume, left edge for brightness, bottom edge to seek media, and 1–4 clicks on the top corners for configurable actions. There are no tests.

## Commands

```bash
./build.sh                  # release build -> dist/Sidle.app (ad-hoc signed, bundle id com.rajpatel.sidle)
./build.sh debug            # same, from .build/debug
./build.sh --zip            # also dist/Sidle-<version>.zip, the GitHub release artifact
open dist/Sidle.app         # run; first launch prompts for Accessibility
dist/Sidle.app/Contents/MacOS/Sidle --dump-touches   # print raw trackpad frames for 6 s, then exit
```

`build.sh` is the only supported way to build. It redirects every SwiftPM/clang cache into `.build/` because the default caches under `~/Library` and `/var/folders` are unwritable in sandboxed sessions. Even so, `swift build` under the Claude Code Bash sandbox fails with EPERM writing its build manifests, so run `./build.sh` with the sandbox disabled. Do not add `--build-system native` or `--disable-sandbox`; both were tried and do not help.

The app must be run as a bundle (`dist/Sidle.app`), not the bare binary, for `LSUIElement` (no Dock icon) and a stable Accessibility grant. The ad-hoc signature with a fixed identifier is what keeps the Accessibility grant valid across rebuilds.

## Architecture

Two SwiftPM targets:

- `Sources/MTBridge` (C): loads the private `MultitouchSupport.framework` with `dlopen` at runtime (never linked directly) and exposes `MTBridgeStart/Stop`, surface size in mm, and the `MTTouch` struct. The struct layout in `MTBridge.h` was verified against real frames on macOS 27 (normalized 0..1 coords, origin bottom-left; `state` 3–5 means the finger is down). Do not reorder its fields.
- `Sources/Sidle` (Swift): the app.

Data flow for a gesture:

1. `TouchReader` receives frames on a MultitouchSupport background thread, converts them to `Touch` values with both normalized and millimetre coordinates, and forwards them to `GestureEngine.ingest`, which caches the latest frame per device under a lock.
2. `EventTap` is a HID-level `CGEventTap` (needs Accessibility). On `leftMouseDown` it asks `GestureEngine.mouseDown`, which looks at the cached frames: exactly one finger down, resting in a strip or corner, else the click passes through. Multi-finger or two-trackpad situations are deliberately ignored.
3. If a gesture starts, the engine swallows the down/drag/up events, freezes the pointer with `CGAssociateMouseAndMouseCursorPosition(0)`, and then tracks that finger ID in subsequent frames on the main thread. Slide distance is measured in millimetres (`stepMillimetres`), so it feels the same on a Magic Trackpad. Leaving the strip cancels but keeps swallowing until the mouse-up.
4. Effects go through `Actions`: volume/brightness/mute are posted as `NX_SYSDEFINED` media-key events (so macOS shows its own bezel; ⇧⌥ gives quarter steps natively), seek sends ←/→ key presses to the frontmost app on release, corner actions open apps/links, run `shortcuts run`, or replay a recorded shortcut.

Corner clicks are counted in `GestureEngine.registerCornerClick` with a 0.35 s timer, firing early once the highest configured click count is reached.

Settings are one `Codable` `Settings` struct persisted as JSON in `UserDefaults` via `SettingsStore.shared` (key `SidleSettings.v1`); the SwiftUI `SettingsView` binds straight to it, and the engine reads `SettingsStore.shared.settings` live, so no restart is needed after changes. Add new options to the struct with a default value so old saved JSON still decodes.

`App.swift` is the entry (`@main` struct, `-parse-as-library`): it builds the `NSStatusItem`, starts `GestureEngine` only once Accessibility is granted (polling every second until then), and hosts the settings window. `SeekHUD` is the floating "+15 s" panel shown while scrubbing.

## Distribution

There is no Apple Developer account, so the app is ad-hoc signed and not notarized; do not add Sparkle or notarization steps. Releases are cut by pushing a `v<version>` tag that matches `CFBundleShortVersionString` in `Resources/Info.plist`; `.github/workflows/release.yml` builds the zip and publishes the GitHub Release. `UpdateChecker` (in `Support.swift`) polls that repo's latest release once a day and only links to the release page. All outward URLs (repo, issues, Buy Me a Coffee) come from `Links` in `Support.swift`; the same handles appear in `README.md`, `docs/index.html` (the GitHub Pages landing page), `packaging/homebrew/sidle.rb` and `marketing/`, so change them together. The app icon is generated from `Resources/icon/AppIcon.svg` with `rsvg-convert` + `iconutil` into `Resources/AppIcon.icns`.

## Gotchas

- Private-API callbacks are C function pointers: `TouchReader.handleFrame` must stay a non-capturing closure and reach state through the singleton.
- `EventTap` runs its callback on the main run loop; keep the mouse handlers fast, since a slow tap gets disabled by the system (the code re-enables on `tapDisabledByTimeout`).
- Brightness is refused when no built-in display is active (`Display.hasBuiltInDisplay`), matching the reference app.
