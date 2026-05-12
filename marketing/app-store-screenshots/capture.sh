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
TCC_DB="$SIM_DATA/Library/TCC/TCC.db"

echo "==> Refreshing EXIF dates so seed photos count as Today/On This Day"
python3 "$ROOT/refresh-seed-dates.py" "$SEED_DIR"

echo "==> Resetting sim photo library: $DEVICE"
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
sleep 1
rm -rf "$SIM_DATA/Media/DCIM" "$SIM_DATA/Media/PhotoData"

echo "==> Booting"
xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null

echo "==> Pre-granting Photos full access (TCC.db, auth_value=4)"
# Wipe any stale entries the previous run may have left so we don't end up
# with a stuck .denied state from a bad legacy auth_value.
xcrun simctl privacy "$DEVICE" reset all "$BUNDLE" 2>/dev/null || true
if [[ -f "$TCC_DB" ]]; then
  # auth_value: 0=denied, 2=legacy/limited-allowed, 3=limited, 4=full.
  # iOS 26 needs 4 for Photos read+write.
  sqlite3 "$TCC_DB" "INSERT OR REPLACE INTO access (service, client, client_type, auth_value, auth_reason, auth_version) VALUES ('kTCCServicePhotos', '$BUNDLE', 0, 4, 4, 1);" 2>/dev/null || true
fi
xcrun simctl privacy "$DEVICE" grant photos "$BUNDLE" 2>/dev/null || true

echo "==> Seeding $(ls "$SEED_DIR"/*.jpg | wc -l | tr -d ' ') photos"
for img in "$SEED_DIR"/*.jpg; do
  xcrun simctl addmedia "$DEVICE" "$img"
done

XCRESULT="$ROOT/.capture-runs/$DEVICE.xcresult"
mkdir -p "$ROOT/.capture-runs"
rm -rf "$XCRESULT"

echo "==> Running UI test"
cd "$ROOT/../.."
xcodebuild -project SnipSnaps.xcodeproj -scheme SnipSnaps \
  -destination "id=$DEVICE" \
  -only-testing:SnipSnapsUITests/ScreenshotCaptureTests/testCaptureAllScreens \
  -resultBundlePath "$XCRESULT" \
  test 2>&1 | grep -E "(TEST|passed|failed)" | tail -5

echo "==> Extracting captures into $RAW_DIR"
mkdir -p "$RAW_DIR"
python3 "$ROOT/extract-shots.py" "$XCRESULT" "$RAW_DIR"

echo "==> Done for $DEVICE"
