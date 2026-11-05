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

# An upload that fails leaves a good archive behind, and rebuilding it costs
# the tests, the build number and five minutes of archiving to produce a file
# that is already on disk. Most upload failures are a wrong credential, which
# is fixed in seconds and should be retried in seconds.
UPLOAD_ONLY=no
[ "${1:-}" = "--upload-only" ] && UPLOAD_ONLY=yes

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

# Checked for shape, not just for being set.
#
# A placeholder left in appstore.env is a non empty string, so every check
# that only asked whether the value exists was satisfied by the words
# PASTE_ISSUER_ID_HERE, and the first thing that noticed was App Store Connect
# refusing the upload, fifteen minutes and one spent build number later.
case "$ASC_KEY_ID" in
  *XXXX*|*PASTE*|*HERE*|"") die "ASC_KEY_ID in scripts/appstore.env is still a placeholder." ;;
esac
case "$ASC_ISSUER_ID" in
  *XXXX*|*PASTE*|*HERE*|"") die "ASC_ISSUER_ID in scripts/appstore.env is still a placeholder. It is the UUID above the table on the App Store Connect API keys page." ;;
esac
# The issuer is always a uuid. Saying so here beats finding out from a web
# service that answers "Unauthenticated" and names nothing.
printf '%s' "$ASC_ISSUER_ID" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' \
  || die "ASC_ISSUER_ID does not look like a uuid: $ASC_ISSUER_ID"

[ -f "$ROOT/Mise/Resources/supabase.json" ] \
  || say "Note: no supabase.json, so this build will have sharing switched off."

# --- Check it works before shipping it --------------------------------------

if [ "$UPLOAD_ONLY" = yes ]; then
  [ -d "$ARCHIVE" ] || die "No archive at $ARCHIVE to upload. Run without --upload-only."
  say "Skipping the tests and the archive: uploading what is already built"
fi

# Everything from here to the matching fi is the expensive half, and
# --upload-only skips all of it.
if [ "$UPLOAD_ONLY" = no ]; then

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
# From the project file rather than from agvtool, which answers nothing here:
# MARKETING_VERSION is a build setting in this project and agvtool only reads
# it out of an Info.plist. Every line this script printed said "Mise  (2)".
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Mise.xcodeproj/project.pbxproj | head -1)
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
fi

BUILD="${BUILD:-$(agvtool what-version -terse)}"
VERSION="${VERSION:-$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Mise.xcodeproj/project.pbxproj | head -1)}"

# --- Upload -----------------------------------------------------------------

say "Uploading to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
  -exportPath "$ROOT/build/export" \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -allowProvisioningUpdates \
  || die "The upload failed. The archive is kept, so fix the cause and retry with:

    ./scripts/release.sh --upload-only

which skips the tests and the archive."

say "Sent. Mise $VERSION ($BUILD)"

# Committed here rather than left for somebody to remember.
#
# The number lives in project.pbxproj, which is also the file Xcode rewrites
# constantly and which update.sh parks and discards for exactly that reason.
# So an uncommitted bump is thrown away by the next pull, the project goes
# back to the number before the one already uploaded, and the next release is
# rejected by Apple for reusing it. Build 2 went out and the project said 1.
if [ "$UPLOAD_ONLY" = no ] && ! git diff --quiet -- Mise.xcodeproj/project.pbxproj; then
  git add Mise.xcodeproj/project.pbxproj
  git commit -q -m "Build $BUILD" && say "Committed the build number. Push it when you next push."
fi
cat <<'NEXT'

Apple takes ten to twenty minutes to process it. Then, at
https://appstoreconnect.apple.com under TestFlight, it appears under iOS
builds and goes out to your internal testers on its own.

An external group needs its first build reviewed, usually within a day. After
that one, later builds go out without review.

NEXT
