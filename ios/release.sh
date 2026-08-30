#!/usr/bin/env bash
# Build and ship a TestFlight build from this Mac. No GitHub, no Xcode GUI.
#
# The CI workflow this replaces ran on a fresh runner every time, which minted a new
# development certificate per build and needed a pruning step to stay under Apple's
# cap. Building locally keeps one identity and skips all of that.
#
# One-time setup — App Store Connect > Users and Access > Integrations >
# App Store Connect API > generate a key with the "App Manager" role:
#
#   1. put the downloaded file at ~/private_keys/AuthKey_<KEYID>.p8   (chmod 600)
#   2. export ASC_KEY_ID=<KEYID>      # 10 chars, also in the filename
#      export ASC_ISSUER_ID=<UUID>    # shown above the key list
#      (or write them to ios/.asc-env, which is gitignored and sourced below)
#
# Then:  ./ios/release.sh
#
# The build number is the current time as yymmddHHMM: always increasing, never
# collides, and readable — 2608291359 is 13:59 on 29 Aug 2026. Apple only requires
# that it rise, and this cannot fail to.
set -euo pipefail

cd "$(dirname "$0")"
[ -f .asc-env ] && . ./.asc-env

: "${ASC_KEY_ID:?set ASC_KEY_ID (see the header of this script)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (see the header of this script)}"
KEY="$HOME/private_keys/AuthKey_${ASC_KEY_ID}.p8"
[ -f "$KEY" ] || { echo "missing $KEY" >&2; exit 1; }

BUILD="${BUILD_NUMBER:-$(date +%y%m%d%H%M)}"
ARCHIVE="build/TheSharpEdge.xcarchive"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Testing before shipping"
xcodebuild test -project TheSharpEdge.xcodeproj -scheme TheSharpEdge \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' -quiet

echo "==> Archiving build $BUILD"
xcodebuild -project TheSharpEdge.xcodeproj -scheme TheSharpEdge \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  archive

echo "==> Uploading to TestFlight"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist exportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "==> Build $BUILD uploaded. Processing takes a few minutes before it appears in TestFlight."
