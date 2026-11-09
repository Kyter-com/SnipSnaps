#!/usr/bin/env bash
# Orchestrates a full screenshot capture run for one simulator.
#
#   capture.sh <device-id> <raw-output-dir> [inner|outer]
#
# For iPhone Duo, the third argument picks the display to shoot. Folding and
# unfolding is a Device Hub control with no command-line equivalent, so before
# running the UI test the script waits until that display is the active one.
#
# Steps:
#   1. Boot the sim and wait for it.
#   2. Wipe the photo library and reseed from copies of seed-photos/ (fresh
#      EXIF dates); the tracked seed photos stay unchanged.
#   3. Pre-grant Photos full access via TCC.db so the test starts logged-in.
#      The UI test also has a fallback that walks the permission dialog if
#      the TCC hack ever stops working.
#   4. Run the XCUITest that drives the app through every marketing screen.
#   5. Extract the named screenshot attachments into the raw/ dir.
#
# The companion `generate.py` then composites the marketing layouts.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: capture.sh <device-id> <raw-output-dir> [inner|outer]" >&2
  exit 2
fi

DEVICE="$1"
RAW_DIR="$2"
DUO_DISPLAY="${3:-}"

case "$DUO_DISPLAY" in
  "") ;;
  inner) WANT_DISPLAY="LCD-1"; POSTURE="unfold it flat" ;;
  outer) WANT_DISPLAY="LCD"; POSTURE="fold it closed" ;;
  *) echo "error: the display must be inner or outer" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="com.kyter.SnipSnaps"
SIM_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE/data"
PYTHON_BIN="${SNIPSNAPS_SCREENSHOT_PYTHON:-python3}"

# The name of the device's active display ("LCD" or "LCD-1" on iPhone Duo).
active_display() {
  local json
  json="$(mktemp)"
  xcrun devicectl device info displays --device "$DEVICE" --json-output "$json" >/dev/null 2>&1 || true
  "$PYTHON_BIN" -c '
import json, sys
try:
    displays = json.load(open(sys.argv[1]))["result"]["displays"]
except Exception:
    displays = []
print(next((d["name"] for d in displays if d.get("active")), ""))' "$json"
  rm -f "$json"
}

# Refresh dates on copies so the tracked seed photos never change.
SEED_DIR="$(mktemp -d)"
trap 'rm -rf "$SEED_DIR"' EXIT
cp "$ROOT"/seed-photos/*.jpg "$SEED_DIR"/

echo "==> Refreshing EXIF dates so seed photos count as Today/On This Day"
"$PYTHON_BIN" "$ROOT/refresh-seed-dates.py" "$SEED_DIR"

echo "==> Stamping GPS on seed photos so the details Location map renders"
"$PYTHON_BIN" "$ROOT/seed-locations.py" "$SEED_DIR"

echo "==> Resetting sim photo library: $DEVICE"
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
sleep 1
rm -rf "$SIM_DATA/Media/DCIM" "$SIM_DATA/Media/PhotoData"

echo "==> Booting"
xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "==> Overriding the status bar (clean Apple 9:41, full battery/signal)"
# Bakes a tidy marketing status bar into every capture so shots don't show the
# sim's live clock / weak signal. Persists on the booted sim through the test.
xcrun simctl status_bar "$DEVICE" override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState discharging --batteryLevel 100 2>/dev/null || true

echo "==> Resetting Photos permission to not-determined (test grants via dialog)"
# iOS 26.4 note: the old TCC pre-grant no longer works and actively breaks the
# capture. `simctl privacy grant photos` lands as auth_value=2 (limited), which
# the modern Photos stack treats as denied; a direct sqlite write to
# auth_value=4 does land on disk but tccd keeps serving its cached value, so the
# app still sees denied. Either way the permission is *determined*, which
# suppresses the system prompt and drops the app on its "Photo access denied"
# screen (the test then bounces into Settings — that was the broken run).
#
# Fix: just reset to not-determined. On launch the app shows "Enable Photo
# Access"; the UI test taps it and walks the "Allow Full Access" dialog, which
# grants full access through tccd correctly.
xcrun simctl privacy "$DEVICE" reset all "$BUNDLE" 2>/dev/null || true

echo "==> Seeding $(ls "$SEED_DIR"/*.jpg | wc -l | tr -d ' ') photos"
for img in "$SEED_DIR"/*.jpg; do
  xcrun simctl addmedia "$DEVICE" "$img"
done

XCRESULT="$ROOT/.capture-runs/$DEVICE.xcresult"
mkdir -p "$ROOT/.capture-runs"
rm -rf "$XCRESULT"

if [[ -n "$DUO_DISPLAY" ]]; then
  # After booting, iPhone Duo can report either display for a while before it
  # settles, so wait until the right one is active for three checks in a row.
  steady=0
  wrong=0
  while (( steady < 3 )); do
    if [[ "$(active_display)" == "$WANT_DISPLAY" ]]; then
      steady=$((steady + 1))
    else
      steady=0
      wrong=$((wrong + 1))
      if (( wrong == 3 )); then
        echo "==> Waiting for the $DUO_DISPLAY display: in Device Hub, $POSTURE with the buttons under the device"
      fi
    fi
    sleep 2
  done
fi

echo "==> Running UI test"
cd "$ROOT/../.."
# With parallel testing, xcodebuild ran the test on simulator clones and
# retried transient "Busy" launch failures, so it could print "** TEST FAILED **"
# for a dead clone yet still pass on a retry — and exit non-zero regardless.
# Don't let a non-zero exit abort the script before we extract;
# `extract-shots.py` below is the real success check. Parallel testing is now
# off so the test runs on the device itself, since a clone has its own iPhone
# Duo fold state.
set +o pipefail
xcodebuild -project SnipSnaps.xcodeproj -scheme SnipSnaps \
  -destination "id=$DEVICE" -parallel-testing-enabled NO \
  -only-testing:SnipSnapsUITests/ScreenshotCaptureTests/testCaptureAllScreens \
  -resultBundlePath "$XCRESULT" \
  test 2>&1 | grep -E "(Test Case .* (passed|failed)|TEST (SUCCEEDED|FAILED)|error:)" | tail -8 || true
set -o pipefail

echo "==> Extracting captures into $RAW_DIR"
mkdir -p "$RAW_DIR"
"$PYTHON_BIN" "$ROOT/extract-shots.py" "$XCRESULT" "$RAW_DIR"

echo "==> Done for $DEVICE"
