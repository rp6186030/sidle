# Contributing to Sidle

Thanks for helping. Bug reports about gesture feel are as valuable as code.

## Build

```bash
./build.sh            # dist/Sidle.app
./build.sh debug
./build.sh --zip      # also dist/Sidle-<version>.zip
```

Run the bundle, not the bare binary: `open dist/Sidle.app`. Rebuilding keeps your Accessibility grant because the ad-hoc signature uses a fixed identifier.

## Debugging touches

```bash
dist/Sidle.app/Contents/MacOS/Sidle --dump-touches
```

Prints raw frames for six seconds: finger id, state, normalized position, millimetre position and contact size. Please paste a few lines of this in gesture bug reports, along with your Mac model and macOS version.

## Where things live

- `Sources/MTBridge`: C shim that `dlopen`s the private MultitouchSupport framework. Do not reorder the `MTTouch` struct fields.
- `Sources/Sidle/GestureEngine.swift`: decides whether a click starts a gesture and tracks the slide.
- `Sources/Sidle/EventTap.swift`: the `CGEventTap` that swallows gesture clicks. Keep its handlers fast.
- `Sources/Sidle/Actions.swift`: everything a gesture can trigger.
- `Sources/Sidle/Settings.swift`: one `Codable` struct. New options need a default so saved settings still decode.

## Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, add a `CHANGELOG.md` entry, then push a tag like `v1.0.1`. The release workflow builds the zip and attaches it to a GitHub Release. Update `version` in the Homebrew cask afterwards.
