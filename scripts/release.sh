#!/usr/bin/env bash
#
# Build Mise and send it to TestFlight.
#
#   ./scripts/release.sh
#
# One command, because the alternative is eight steps in Xcode's Organizer and
# the one that gets forgotten is raising the build number, which Apple rejects
# after the archive has already taken four minutes.
#
# Needs a one time setup. See RELEASE.md.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ARCHIVE="$ROOT/build/Mise.xcarchive"
SECRETS="$ROOT/scripts/appstore.env"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
die() { printf "\n\033[31m%s\033[0m\n" "$*" >&2; exit 1; }

# --- What it needs before it starts -----------------------------------------

[ -f "$SECRETS" ] || die "Missing $SECRETS. See the TestFlight section of RELEASE.md."
# shellcheck disable=SC1090
source "$SECRETS"

: "${ASC_KEY_ID:?ASC_KEY_ID is not set in scripts/appstore.env}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set in scripts/appstore.env}"
: "${ASC_KEY_PATH:?ASC_KEY_PATH is not set in scripts/appstore.env}"

KEY_PATH="${ASC_KEY_PATH/#\~/$HOME}"
[ -f "$KEY_PATH" ] || die "No App Store Connect key at $KEY_PATH"

[ -f "$ROOT/Mise/Resources/supabase.json" ] \
  || say "Note: no supabase.json, so this build will have sharing switched off."

# --- Check it works before shipping it --------------------------------------

say "Running the tests"
xcodebuild test \
  -scheme Mise \
  -destination 'platform=iOS Simulator,name=iPhone 17e' \
  -quiet \
  || die "Tests failed. Not shipping."

# --- Raise the build number -------------------------------------------------
#
# Apple rejects an upload that reuses one, and finding that out after the
# archive is the most annoying way to find it out.

say "Raising the build number"
agvtool next-version -all >/dev/null
BUILD=$(agvtool what-version -terse)
VERSION=$(agvtool what-marketing-version -terse1)
say "Building Mise $VERSION ($BUILD)"

# --- Archive ----------------------------------------------------------------

rm -rf "$ARCHIVE"
say "Archiving, which takes a few minutes"
xcodebuild archive \
  -scheme Mise \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -quiet \
  || die "The archive failed."

# --- Upload -----------------------------------------------------------------

say "Uploading to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
  -exportPath "$ROOT/build/export" \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  || die "The upload failed. The archive is kept at $ARCHIVE, so this can be retried without rebuilding."

say "Sent. Mise $VERSION ($BUILD)"
cat <<'NEXT'

Apple takes ten to twenty minutes to process it. Then, at
https://appstoreconnect.apple.com under TestFlight, it appears under iOS
builds and goes out to your internal testers on its own.

An external group needs its first build reviewed, usually within a day. After
that one, later builds go out without review.

The build number was raised, so commit it:

    git commit -am "Build $(cd "$(dirname "$0")/.." && agvtool what-version -terse)"

NEXT
