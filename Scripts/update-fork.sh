#!/bin/bash
# Update this fork from upstream: show what's new, then merge, build, install and relaunch.
# `--rollback` swaps the installed app back to the copy the last update replaced.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

BRANCH=personal
UPSTREAM=upstream/main
UPSTREAM_SLUG=abue-ammar/tinycast
BUNDLE_ID=com.tinycast.app.personal
INSTALLED=/Applications/Tinycast.app
WORKTREE="$REPO/build/update-worktree"
DERIVED="$REPO/build/UpdateDerivedData"
BACKUP="$REPO/build/Tinycast-previous.app"
LOG="$REPO/build/update.log"
LOCK="$REPO/build/update.lock"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

mkdir -p build
# Launched from Tinycast, stderr is a pipe into the app we are about to quit.
if [ -t 1 ]; then exec > >(tee -a "$LOG") 2>&1; else exec >>"$LOG" 2>&1; fi
trap '' HUP PIPE
echo "── $(date '+%Y-%m-%d %H:%M:%S') ──"

notify() {
    echo "$1"
    osascript - "$1" >/dev/null 2>&1 <<'EOF' || true
on run argv
    display notification (item 1 of argv) with title "Tinycast update"
end run
EOF
}

fail() {
    notify "✗ $1"
    exit 1
}

mkdir "$LOCK" 2>/dev/null || fail "An update is already running."
trap 'rmdir "$LOCK"' EXIT

quit_tinycast() {
    pgrep -f "$INSTALLED/Contents/MacOS/" >/dev/null || return 0
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1
    for _ in $(seq 30); do
        pgrep -f "$INSTALLED/Contents/MacOS/" >/dev/null || return 0
        sleep 0.5
    done
    return 1
}

if [ "${1:-}" = "--rollback" ]; then
    [ -d "$BACKUP" ] || fail "No previous build to roll back to."
    quit_tinycast || fail "Tinycast didn't quit, so nothing was changed."
    mv "$INSTALLED" "$INSTALLED.swap" && mv "$BACKUP" "$INSTALLED" && mv "$INSTALLED.swap" "$BACKUP" \
        || fail "Rollback failed, check $INSTALLED and $BACKUP."
    open "$INSTALLED"
    notify "✓ Rolled back to the previous build."
    exit 0
fi

echo "▸ Fetching upstream…"
git fetch -q upstream --tags || fail "Couldn't fetch from upstream."
OLD="$(git rev-parse "$BRANCH")" || fail "No '$BRANCH' branch."
COUNT="$(git rev-list --count "$BRANCH..$UPSTREAM")"
if [ "$COUNT" = 0 ]; then
    notify "Already up to date."
    exit 0
fi
VERSION="$(git describe --tags --abbrev=0 "$UPSTREAM" | sed 's/^v//')"

SUMMARY="$(git log --no-merges --format='• %s' "$BRANCH..$UPSTREAM" | head -15)"
SHOWN="$(printf '%s\n' "$SUMMARY" | wc -l | tr -d ' ')"
[ "$COUNT" -gt "$SHOWN" ] && SUMMARY="$SUMMARY"$'\n'"…and $((COUNT - SHOWN)) more"
COMPARE="https://github.com/$UPSTREAM_SLUG/compare/$(git merge-base "$BRANCH" "$UPSTREAM")...$(git rev-parse "$UPSTREAM")"
while :; do
    CHOICE="$(osascript - "$COUNT new upstream commits (v$VERSION):"$'\n\n'"$SUMMARY" 2>/dev/null <<'EOF'
on run argv
    set r to display dialog (item 1 of argv) with title "Update Tinycast" ¬
        buttons {"Cancel", "View on GitHub", "Update"} default button "Update" cancel button "Cancel"
    return button returned of r
end run
EOF
    )"
    case "$CHOICE" in
        Update) break ;;
        "View on GitHub") open "$COMPARE" ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
done

echo "▸ Merging $UPSTREAM into a copy of $BRANCH…"
if [ -d "$WORKTREE" ]; then
    git -C "$WORKTREE" merge --abort >/dev/null 2>&1
    git -C "$WORKTREE" reset -q --hard && git -C "$WORKTREE" checkout -q --detach "$OLD" \
        || fail "Couldn't reset $WORKTREE."
else
    git worktree add -q --detach "$WORKTREE" "$OLD" || fail "Couldn't create $WORKTREE."
fi
cd "$WORKTREE" || exit 1
if ! git merge -q --no-edit -m "Merge upstream v$VERSION" "$UPSTREAM"; then
    CONFLICTS="$(git diff --name-only --diff-filter=U)"
    # The project file is generated from project.yml, so regenerating it is the resolution.
    if [ "$CONFLICTS" = "Tinycast.xcodeproj/project.pbxproj" ]; then
        git checkout -q --theirs -- "$CONFLICTS" && xcodegen generate --quiet \
            && git add "$CONFLICTS" && git commit -q --no-edit \
            || fail "Couldn't regenerate the conflicting project file."
    else
        git merge --abort
        fail "Merge conflict in: $(echo "$CONFLICTS" | tr '\n' ' ')— nothing was changed."
    fi
fi
xcodegen generate --quiet || fail "xcodegen failed."
if ! git diff --quiet; then
    git commit -q -am "Regenerate Tinycast.xcodeproj" || fail "Couldn't commit the regenerated project."
fi
MERGED="$(git rev-parse HEAD)"

echo "▸ Building v$VERSION (Release)…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" -quiet \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Tinycast Self-Signed" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    MARKETING_VERSION="$VERSION" \
    build || fail "Build failed, see build/update.log. The merge is kept in build/update-worktree."
APP="$DERIVED/Build/Products/Release/Tinycast.app"
codesign --verify --deep --strict "$APP" || fail "The new build's signature doesn't verify."
cd "$REPO" || exit 1

echo "▸ Moving $BRANCH to the merge…"
if [ "$(git branch --show-current)" = "$BRANCH" ]; then
    git merge -q --ff-only "$MERGED" \
        || echo "! Your checkout has changes in the way; run 'git merge --ff-only $MERGED' later."
else
    git update-ref "refs/heads/$BRANCH" "$MERGED" "$OLD"
fi
git push -q origin "$BRANCH" || echo "! Couldn't push $BRANCH to origin."

echo "▸ Installing…"
quit_tinycast || fail "Tinycast didn't quit, so the new build wasn't installed."
rm -rf "$BACKUP"
[ -d "$INSTALLED" ] && { mv "$INSTALLED" "$BACKUP" || fail "Couldn't move the current app aside."; }
if ! ditto "$APP" "$INSTALLED"; then
    [ -d "$BACKUP" ] && mv "$BACKUP" "$INSTALLED"
    open "$INSTALLED"
    fail "Couldn't copy the new build; the previous one is back in place."
fi
open "$INSTALLED"
notify "✓ Updated to v$VERSION ($COUNT upstream commits)."
