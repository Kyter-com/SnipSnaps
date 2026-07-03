#!/usr/bin/env bash
#
# Guards against SnipSnaps' recurring release gotcha: shipping a build whose
# MARKETING_VERSION still points at an App Store version that is already
# released. Once a version is READY_FOR_SALE its release train is closed, so
# every Xcode Cloud build gets rejected at upload with:
#   ITMS-90186  (train closed for new build submissions)
#   ITMS-90062  (CFBundleShortVersionString not higher than approved)
#
# Exit 0 = OK to push. Exit 1 = train closed, block the push.
# It SOFT-PASSES (exit 0 + warning) whenever it can't be sure — asc missing,
# not authed, network down, no matching version — so it never blocks on infra.
# Override with:  SKIP_VERSION_CHECK=1 git push
#
# Run manually any time:  ./scripts/check-marketing-version.sh
set -euo pipefail

APP_ID="6746975535"   # SnipSnaps (com.kyter.SnipSnaps)
PROFILE="snipsnaps"

if [[ "${SKIP_VERSION_CHECK:-}" == "1" ]]; then
  echo "check-marketing-version: skipped (SKIP_VERSION_CHECK=1)"
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
pbxproj="$repo_root/SnipSnaps.xcodeproj/project.pbxproj"

soft_pass() { echo "check-marketing-version: $1 — skipping check." >&2; exit 0; }

[[ -f "$pbxproj" ]] || soft_pass "project.pbxproj not found"

version=$(grep -m1 -E 'MARKETING_VERSION = ' "$pbxproj" \
  | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' ')
[[ -n "$version" ]] || soft_pass "could not read MARKETING_VERSION"

command -v asc >/dev/null 2>&1 || soft_pass "'asc' not installed (MARKETING_VERSION=$version)"
command -v jq  >/dev/null 2>&1 || soft_pass "'jq' not installed (MARKETING_VERSION=$version)"

state=$(asc --profile "$PROFILE" versions list --app "$APP_ID" --output json 2>/dev/null \
  | jq -r --arg v "$version" \
      '.data[]? | select(.attributes.versionString==$v and .attributes.platform=="IOS") | .attributes.appStoreState' \
  | head -n1 || true)

if [[ -z "$state" ]]; then
  soft_pass "MARKETING_VERSION=$version has no released iOS version on ASC (or asc unavailable) — treating train as open"
fi

case "$state" in
  READY_FOR_SALE|PENDING_APPLE_RELEASE|REPLACED_WITH_NEW_VERSION|REMOVED_FROM_SALE)
    cat >&2 <<EOF

✗ BLOCKED: MARKETING_VERSION $version is already $state on the App Store.
  That release train is closed — Xcode Cloud will reject the build with
  ITMS-90186 (train closed) and ITMS-90062 (version not higher than approved).

  Fix — bump MARKETING_VERSION in SnipSnaps.xcodeproj (all build configs), then:
    asc versions create --app $APP_ID --version <NEW> --copy-metadata-from $version --exclude-fields whatsNew

  Intentional? Push anyway with:  SKIP_VERSION_CHECK=1 git push
EOF
    exit 1
    ;;
  *)
    echo "check-marketing-version: MARKETING_VERSION=$version is $state (train open) — OK." >&2
    exit 0
    ;;
esac
