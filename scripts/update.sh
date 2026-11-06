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

# The one file Xcode rewrites by itself. Anything else that has changed is
# something a person wrote, and the difference decides whether this script may
# throw the parked changes away afterwards.
GENERATED="Mise.xcodeproj/project.pbxproj"

BEFORE=$(git rev-parse HEAD)
STASHED=no
ONLY_GENERATED=yes

if ! git diff --quiet || ! git diff --cached --quiet; then
  while IFS= read -r file; do
    [ "$file" = "$GENERATED" ] || ONLY_GENERATED=no
  done < <(git diff --name-only HEAD)

  # One thing in that generated file is not Xcode's: the build number. It is
  # raised by release.sh, it is the one number Apple refuses to see twice, and
  # discarding it sends the project back to a number already uploaded. If the
  # parked change touches it, the change is a person's work and is kept.
  if git diff -- "$GENERATED" | grep -qE '^[-+].*(CURRENT_PROJECT_VERSION|MARKETING_VERSION)'; then
    ONLY_GENERATED=no
  fi

  say "Parking local changes"
  git stash push --quiet --message "update.sh: before pull" || true
  STASHED=yes
  git --no-pager stash show --stat "stash@{0}" 2>/dev/null || true
fi

say "Pulling"
# --rebase, stated here rather than left to whatever git is configured to do.
#
# release.sh commits the build number, so this repository does have local
# commits, and the moment one of them meets a commit from elsewhere git stops
# with "divergent branches" and a hint listing three options rather than
# picking one. Rebase is the right one here: the local commits are small and
# nobody else is building on them, and the history stays a line.
git pull --rebase --quiet

AFTER=$(git rev-parse HEAD)

if [ "$BEFORE" = "$AFTER" ]; then
  say "Already up to date"
else
  say "Updated. What came in:"
  git --no-pager log --oneline "$BEFORE..$AFTER"
fi

if [ "$STASHED" = yes ]; then
  if [ "$ONLY_GENERATED" = yes ]; then
    # Xcode regenerates this file from the folder on disk, so a copy of it from
    # before the pull is worth nothing and keeping it is worse than nothing.
    # The first version of this script said so in a note and left the stash
    # behind anyway, which is how seven of them piled up in a week.
    git stash drop --quiet "stash@{0}"
    say "Discarded Xcode's own edits to the project file. Nothing of yours was touched."
  else
    cat <<'NOTE'

You had changes to more than Xcode's project file, so they are parked rather
than discarded.

To look:    git stash show -p stash@{0}
To restore: git stash pop
To discard: git stash drop
NOTE
  fi
fi

# Older parkings, from the version of this script that left them behind.
#
# Any stash whose only file is the generated project file is worth nothing,
# whoever made it and whatever its message says, because Xcode rebuilds that
# file from the folder on disk. Dropping shifts the remaining indexes, so this
# finds one at a time rather than collecting a list and working through it.
TIDIED=0
while true; do
  STALE=""
  while IFS= read -r ref; do
    if [ "$(git stash show --name-only "$ref" 2>/dev/null)" = "$GENERATED" ]; then
      STALE="$ref"
      break
    fi
  done < <(git stash list | cut -d: -f1)

  [ -n "$STALE" ] || break
  git stash drop --quiet "$STALE"
  TIDIED=$((TIDIED + 1))
done

if [ "$TIDIED" -gt 0 ]; then
  say "Cleared $TIDIED older parked copy of the project file."
fi

REMAINING=$(git stash list | wc -l | tr -d ' ')
if [ "$REMAINING" != "0" ]; then
  say "$REMAINING parked change(s) left, holding more than the project file:"
  git stash list | cut -d: -f1 | while read -r ref; do
    printf "  %s  %s\n" "$ref" "$(git stash show --name-only "$ref" | tr '\n' ' ')"
  done
  echo
  echo "  To look:    git stash show -p stash@{0}"
  echo "  To restore: git stash pop"
fi

say "Now rebuild in Xcode: Cmd+R"
