#!/usr/bin/env bash
#
# Pull the latest Mise, getting past the thing that keeps stopping it.
#
#   ./scripts/update.sh
#
# Xcode rewrites Mise.xcodeproj/project.pbxproj whenever files change on disk,
# which is every time a pull brings new ones. Git then refuses the next pull
# because that file has local changes, and prints a message that scrolls past
# in a build log. The result is a rebuild of code that did not change and ten
# minutes of confusion, which has now happened three times.
#
# So: park Xcode's edits, pull, and say plainly what happened.

set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }

BEFORE=$(git rev-parse HEAD)
STASHED=no

if ! git diff --quiet || ! git diff --cached --quiet; then
  say "Parking local changes"
  git stash push --quiet --message "update.sh: before pull" || true
  STASHED=yes
  git --no-pager stash show --stat "stash@{0}" 2>/dev/null || true
fi

say "Pulling"
git pull --quiet

AFTER=$(git rev-parse HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
  say "Already up to date"
else
  say "Updated. What came in:"
  git --no-pager log --oneline "$BEFORE..$AFTER"
fi

if [ "$STASHED" = yes ]; then
  cat <<'NOTE'

Your local changes are parked in the stash. They are almost certainly just
Xcode's own edits to the project file, in which case there is nothing to do:
they will be stashed again next time and can be forgotten.

To look:    git stash show -p stash@{0}
To restore: git stash pop
To discard: git stash drop
NOTE
fi

say "Now rebuild in Xcode: Cmd+R"
