#!/usr/bin/env bash
# Captures the macOS marketing screens end-to-end.
#
#   capture-mac.sh
#
# Unlike the iOS capture (which drives the real app in a seeded simulator via
# XCUITest), the Mac can't seed a Photos library or grant sandbox folders
# headlessly. So each screen is a curated static demo rendered inside the real
# Mac shell (see SnipSnaps/Views/Marketing/MacScreenshotDemoView.swift), selected
# by the SNIPSNAPS_SCREENSHOT_SCREEN env var. We launch the app once per screen,
# grab just its window with `screencapture`, and let generate.py composite the
# marketing frame. No XCUITest, no window-driving, no signing needed.
#
# Requirements:
#   - Run from a logged-in GUI session (the app must be able to open a window).
#   - Grant your terminal *Screen Recording* permission once
#     (System Settings ▸ Privacy & Security ▸ Screen Recording), or every capture
#     comes out as the desktop instead of the window.
#   - A Retina display for @2x captures (a 1x display still works, just lower res).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
RAW_DIR="$ROOT/raw/mac"
PROJECT="$ROOT/../../SnipSnaps.xcodeproj"
RUNS="$ROOT/.capture-runs"           # gitignored
SCREENS=(home review similar files)

mkdir -p "$RAW_DIR" "$RUNS"

# 1. Build the Mac app (Debug, signing off — same as the local compile-check).
echo "==> Building macOS app (Debug)"
DERIVED="$RUNS/mac-derived"
xcodebuild -project "$PROJECT" -scheme SnipSnaps \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build >/dev/null
APP="$DERIVED/Build/Products/Debug/SnipSnaps.app"
BIN="$APP/Contents/MacOS/SnipSnaps"
[ -x "$BIN" ] || { echo "!! app binary not found at $BIN" >&2; exit 1; }

# 2. Compile the window-id helper (rebuild if the source changed).
HELPER="$RUNS/windowid"
if [ ! -x "$HELPER" ] || [ "$ROOT/windowid.swift" -nt "$HELPER" ]; then
  echo "==> Compiling windowid helper"
  swiftc -O "$ROOT/windowid.swift" -o "$HELPER"
fi

# Clear any stale instance so window discovery can't pick the wrong one, and make
# sure the just-launched app is killed even if we're interrupted mid-capture.
killall SnipSnaps 2>/dev/null || true
sleep 0.5
PID=""
trap 'kill "${PID:-}" 2>/dev/null || true' EXIT INT TERM

# A real `-o` window grab has transparent rounded corners; a desktop grab (what
# screencapture returns when the terminal lacks Screen Recording permission) is
# fully opaque. Returns 0 for a good window grab, 1 for a desktop/garbage grab,
# and 0 if it can't check (PIL missing) so tooling gaps never block a real run.
is_window_capture() {
  python3 - "$1" <<'PY'
import sys
try:
    from PIL import Image
    alpha = Image.open(sys.argv[1]).convert("RGBA").getpixel((0, 0))[3]
except Exception:
    sys.exit(0)
sys.exit(1 if alpha >= 200 else 0)
PY
}

i=0
for screen in "${SCREENS[@]}"; do
  i=$((i + 1))
  n=$(printf "%02d" "$i")
  out="$RAW_DIR/$n-$screen.png"
  echo "==> [$n] $screen"

  # Launch a fresh instance with this demo screen selected. Running the bundle's
  # executable directly (not `open`) inherits the env var and gives us the PID.
  SNIPSNAPS_SCREENSHOT_SCREEN="$screen" "$BIN" >/dev/null 2>&1 &
  PID=$!

  # Poll for *this instance's* window (matched by PID, up to ~10s).
  WID=""
  for _ in $(seq 1 40); do
    WID="$("$HELPER" SnipSnaps "$PID" 2>/dev/null || true)"
    [ -n "$WID" ] && break
    sleep 0.25
  done

  if [ -z "$WID" ]; then
    echo "    !! window never appeared — need a GUI login session" >&2
    kill "$PID" 2>/dev/null || true
    continue
  fi

  # Let SwiftUI settle: async image decode + layout + first paint.
  sleep 2.5

  if ! screencapture -x -o -l "$WID" "$out"; then
    echo "    !! screencapture failed" >&2
    kill "$PID" 2>/dev/null || true
    continue
  fi

  if [ ! -s "$out" ]; then
    echo "    !! capture empty — grant your terminal Screen Recording permission" >&2
  elif ! is_window_capture "$out"; then
    echo "    !! capture is the desktop, not the window. Grant your terminal Screen" >&2
    echo "       Recording permission (System Settings ▸ Privacy & Security), then re-run." >&2
    rm -f "$out"
  else
    echo "    wrote $out ($(sips -g pixelWidth -g pixelHeight "$out" 2>/dev/null | grep pixel | tr -d ' \n' | sed 's/pixelWidth:/ /;s/pixelHeight:/x/'))"
  fi

  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  sleep 0.4
done
PID=""

echo "==> Raw captures in $RAW_DIR"
echo "==> Composite the marketing layouts: python3 $ROOT/generate.py"
