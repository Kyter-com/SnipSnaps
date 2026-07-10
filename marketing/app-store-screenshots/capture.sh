#!/usr/bin/env bash
# Orchestrates a full screenshot capture run for one simulator.
#
#   capture.sh <device-id> <raw-output-dir>
#
# Steps:
#   1. Boot the sim and wait for it.
#   2. Wipe the photo library and reseed from seed-photos/ (fresh EXIF dates).
#   3. Pre-grant Photos full access via TCC.db so the test starts logged-in.
#      The UI test also has a fallback that walks the permission dialog if
#      the TCC hack ever stops working.
#   4. Run the XCUITest that drives the app through every marketing screen.
#   5. Extract the named screenshot attachments into the raw/ dir.
#
# The companion `generate.py` then composites the marketing layouts.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: capture.sh <device-id> <raw-output-dir>" >&2
  exit 2
fi

DEVICE="$1"
RAW_DIR="$2"

ROOT="$(cd "$(dirname "$0")" && pwd)"
SEED_DIR="$ROOT/seed-photos"
BUNDLE="com.kyter.SnipSnaps"
SIM_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE/data"

echo "==> Refreshing EXIF dates so seed photos count as Today/On This Day"
python3 "$ROOT/refresh-seed-dates.py" "$SEED_DIR"

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

echo "==> Running UI test"
cd "$ROOT/../.."
# xcodebuild spins up simulator clones and retries on transient "Busy" launch
# failures, so it can print "** TEST FAILED **" for a dead clone yet still pass
# on a retry — and exit non-zero regardless. Don't let that abort the script
# before we extract; `extract-shots.py` below is the real success check.
set +o pipefail
xcodebuild -project SnipSnaps.xcodeproj -scheme SnipSnaps \
  -destination "id=$DEVICE" \
  -only-testing:SnipSnapsUITests/ScreenshotCaptureTests/testCaptureAllScreens \
  -resultBundlePath "$XCRESULT" \
  test 2>&1 | grep -E "(Test Case .* (passed|failed)|TEST (SUCCEEDED|FAILED)|error:)" | tail -8 || true
set -o pipefail

echo "==> Extracting captures into $RAW_DIR"
mkdir -p "$RAW_DIR"
python3 "$ROOT/extract-shots.py" "$XCRESULT" "$RAW_DIR"

echo "==> Done for $DEVICE"
