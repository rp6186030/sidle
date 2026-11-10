#!/bin/zsh
# Builds Sidle.app into ./dist.
# Usage: ./build.sh [debug|release] [--zip]
#   --zip  also writes dist/Sidle-<version>.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"
CONFIG="release"; ZIP=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --zip) ZIP=1 ;;
    *) echo "unknown argument: $arg"; exit 2 ;;
  esac
done
# Keep every cache inside .build so the build works where ~/Library is read-only.
mkdir -p .build/module-cache .build/spm-cache .build/spm-config .build/spm-security
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build -c "$CONFIG" \
  --cache-path .build/spm-cache --config-path .build/spm-config --security-path .build/spm-security \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache" \
  -Xcc -fmodules-cache-path="$PWD/.build/module-cache" 2>&1 | grep -v '^\[' || true
BIN=".build/$CONFIG/Sidle"
[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }
APP="dist/Sidle.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sidle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc sign with a fixed identifier so the Accessibility grant survives rebuilds.
codesign --force --sign - --identifier com.rajpatel.sidle "$APP" >/dev/null
echo "Built $APP"
if (( ZIP )); then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
  OUT="dist/Sidle-$VERSION.zip"
  rm -f "$OUT"
  ditto -c -k --keepParent "$APP" "$OUT"
  echo "Zipped $OUT ($(shasum -a 256 "$OUT" | cut -d' ' -f1))"
fi
