#!/bin/bash
# Update this fork from upstream: show what's new, then merge, build, install and relaunch.
# `--rebuild` builds and installs what is committed on the branch, without fetching upstream.
# `--rollback` swaps the installed app back to the copy the last update replaced.
# A merge conflict or a build the merge broke goes to a headless Claude Code session in the scratch
# worktree; `TINYCAST_UPDATE_CLAUDE=0` turns that off and stops at the conflict instead.
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
BUILD_LOG="$REPO/build/update-build.log"
USE_CLAUDE="${TINYCAST_UPDATE_CLAUDE:-1}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

mkdir -p build
# Launched from Tinycast, stderr is a pipe into the app we are about to quit.
if [ -t 1 ]; then exec > >(tee -a "$LOG") 2>&1; else exec >>"$LOG" 2>&1; fi
trap '' HUP PIPE
echo "── $(date '+%Y-%m-%d %H:%M:%S') ──"

NOTIFIER="$REPO/build/Tinycast Update.app"
NOTIFIER_SOURCE="$REPO/Scripts/update-notifier.swift"

# A tiny bundle of our own, because `display notification` always wears Script Editor's icon.
notifier_ready() {
    local binary="$NOTIFIER/Contents/MacOS/notify"
    [ -x "$binary" ] && [ "$binary" -nt "$NOTIFIER_SOURCE" ] && return 0
    local icon=/Applications/Tinycast.app/Contents/Resources/tinycast.icns
    [ -f "$icon" ] || [ -f "$NOTIFIER/Contents/Resources/tinycast.icns" ] || return 1
    mkdir -p "$NOTIFIER/Contents/MacOS" "$NOTIFIER/Contents/Resources"
    [ -f "$icon" ] && cp "$icon" "$NOTIFIER/Contents/Resources/"
    cat >"$NOTIFIER/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tinycast.app.personal.update</string>
    <key>CFBundleName</key><string>Tinycast Update</string>
    <key>CFBundleDisplayName</key><string>Tinycast Update</string>
    <key>CFBundleExecutable</key><string>notify</string>
    <key>CFBundleIconFile</key><string>tinycast</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
    xcrun swiftc -O -swift-version 5 -o "$binary" "$NOTIFIER_SOURCE" >/dev/null 2>&1 || return 1
    codesign --force --sign "Tinycast Self-Signed" "$NOTIFIER" >/dev/null 2>&1 \
        || codesign --force --sign - "$NOTIFIER" >/dev/null 2>&1
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$NOTIFIER" >/dev/null 2>&1
    return 0
}

notify() {
    echo "$1"
    notifier_ready && "$NOTIFIER/Contents/MacOS/notify" "$1" >/dev/null 2>&1 && return 0
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

OLD="$(git rev-parse "$BRANCH")" || fail "No '$BRANCH' branch."
REBUILD=false
[ "${1:-}" = "--rebuild" ] && REBUILD=true

confirm_upstream() {
    echo "▸ Fetching upstream…"
    git fetch -q upstream --tags || fail "Couldn't fetch from upstream."
    COUNT="$(git rev-list --count "$BRANCH..$UPSTREAM")"
    if [ "$COUNT" = 0 ]; then
        notify "Already up to date."
        exit 0
    fi
    VERSION="$(git describe --tags --abbrev=0 "$UPSTREAM" | sed 's/^v//')"

    local summary shown compare choice
    summary="$(git log --no-merges --format='• %s' "$BRANCH..$UPSTREAM" | head -15)"
    shown="$(printf '%s\n' "$summary" | wc -l | tr -d ' ')"
    [ "$COUNT" -gt "$shown" ] && summary="$summary"$'\n'"…and $((COUNT - shown)) more"
    compare="https://github.com/$UPSTREAM_SLUG/compare/$(git merge-base "$BRANCH" "$UPSTREAM")...$(git rev-parse "$UPSTREAM")"
    while :; do
        choice="$(osascript - "$COUNT new upstream commits (v$VERSION):"$'\n\n'"$summary" 2>/dev/null <<'EOF'
on run argv
    set r to display dialog (item 1 of argv) with title "Update Tinycast" ¬
        buttons {"Cancel", "View on GitHub", "Update"} default button "Update" cancel button "Cancel"
    return button returned of r
end run
EOF
        )"
        case "$choice" in
            Update) return ;;
            "View on GitHub") open "$compare" ;;
            *) echo "Cancelled."; exit 0 ;;
        esac
    done
}

if $REBUILD; then
    VERSION="$(git describe --tags --abbrev=0 "$BRANCH" | sed 's/^v//')"
else
    confirm_upstream
fi

CLAUDE_TIMEOUT="${TINYCAST_UPDATE_CLAUDE_TIMEOUT:-1800}"
CLAUDE_MAX_TURNS="${TINYCAST_UPDATE_CLAUDE_MAX_TURNS:-150}"
# Why the last session stopped, for the failure notification; empty after a success.
CLAUDE_FAILURE=""

# Prints `resolved`, `sign-in: <line>` or `failed: <reason>`, and the session's reply on stderr.
# Its own function: bash 3.2 misparses a quoted heredoc inside `$(…)` once the heredoc has a quote.
classify_transcript() {
    python3 -I - "$1" <<'EOF'
import json, re, sys

text = open(sys.argv[1], errors="replace").read()
result = None
for line in reversed(text.splitlines()):
    if line.lstrip().startswith("{"):
        try:
            result = json.loads(line)
            break
        except ValueError:
            pass
reply = (result or {}).get("result") or ""
# Only the CLI's own messages, never a reply that merely discusses the app's own OAuth code.
errors = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("{"))
if result is None or result.get("is_error"):
    errors += "\n" + reply
if reply:
    print(reply.strip(), file=sys.stderr)
lines = reply.strip().splitlines()
if result and not result.get("is_error") and lines and lines[-1].startswith("RESULT: resolved"):
    print("resolved")
    sys.exit()
# A login the session can't use: an expired one, or a future `-p` default that skips it.
sign_in = re.search(
    r"authentication_failed|not logged in|please run /login|login expired|invalid api key"
    r"|oauth|apikeyhelper|anthropic_api_key|unauthori[sz]ed|\b401\b",
    errors, re.IGNORECASE)
if sign_in:
    line = next((l for l in errors.splitlines() if sign_in.group(0).lower() in l.lower()), sign_in.group(0))
    print("sign-in: " + line.strip()[:200])
elif lines and lines[-1].startswith("RESULT: failed"):
    print("failed: " + lines[-1][len("RESULT: failed"):].lstrip(" :-—")[:200])
elif result:
    print("failed: it ended without saying it resolved anything (" + str(result.get("subtype", "no subtype")) + ")")
else:
    first = next((l for l in errors.splitlines() if l.strip()), "no output")
    print("failed: Claude Code didn't run: " + first.strip()[:200])
EOF
}

# `--restricted` confines the file tools to the worktree and ignores every settings file and the
# repo's hooks and MCP servers, so merged-in code can't widen what the session may do. Bash is
# limited to the named commands: allowing `git *` would also allow `git -c`, which runs anything.
# Nothing it does reaches `personal` or the installed app until the checks below pass.
ask_claude() {
    local label=$1
    local task=$2
    local transcript="$REPO/build/update-claude-${label// /-}.json"
    CLAUDE_FAILURE=""
    [ "$USE_CLAUDE" = 1 ] || { CLAUDE_FAILURE="it is turned off"; return 1; }
    command -v claude >/dev/null || { CLAUDE_FAILURE="claude isn't on PATH"; return 1; }
    notify "Claude Code is fixing the $label (this can take a few minutes)…"
    echo "▸ Claude Code: fixing the $label; transcript in $transcript"
    # Job control gives the session its own process group, so the timeout also stops its builds.
    set -m
    printf '%s' "$task" | claude -p --output-format json --no-session-persistence \
        --restricted --strict-mcp-config --permission-mode dontAsk --max-turns "$CLAUDE_MAX_TURNS" \
        --tools Read Edit Write Glob Grep Bash \
        --allowedTools Read Edit Write Glob Grep \
        "Bash(git status)" "Bash(git status *)" "Bash(git diff)" "Bash(git diff *)" \
        "Bash(git log *)" "Bash(git show *)" "Bash(git blame *)" "Bash(git grep *)" \
        "Bash(git ls-files *)" "Bash(git merge-base *)" "Bash(git rev-parse *)" "Bash(git cat-file *)" \
        "Bash(git add *)" "Bash(git rm *)" "Bash(git mv *)" "Bash(git restore *)" \
        "Bash(git checkout --ours *)" "Bash(git checkout --theirs *)" "Bash(git commit *)" \
        "Bash(xcodegen generate)" "Bash(xcodegen generate *)" "Bash(xcodebuild *)" \
        "Bash(./Scripts/run-tests.sh)" "Bash(./Scripts/run-tests.sh *)" "Bash(./Scripts/lint.sh)" \
        "Bash(./Scripts/format.sh)" "Bash(node Scripts/check-localizations.js)" \
        "Bash(node Scripts/check-settings-search.js)" \
        "Bash(ls *)" "Bash(grep *)" "Bash(head *)" "Bash(tail *)" "Bash(wc *)" \
        --disallowedTools "Bash(git push*)" "Bash(git *--output*)" \
        >"$transcript" 2>&1 &
    local session=$!
    set +m
    local group
    group="$(ps -o pgid= -p "$session" | tr -d ' ')"
    ( sleep "$CLAUDE_TIMEOUT"; kill -TERM -- "-${group:-$session}" 2>/dev/null ) &
    local watchdog=$!
    wait "$session"
    local exit_code=$?
    pkill -P "$watchdog" 2>/dev/null
    kill "$watchdog" 2>/dev/null
    if [ "$exit_code" = 143 ]; then
        CLAUDE_FAILURE="it was stopped after $((CLAUDE_TIMEOUT / 60)) minutes"
        return 1
    fi
    local verdict
    verdict="$(classify_transcript "$transcript")"
    case "$verdict" in
        resolved) return 0 ;;
        sign-in:*) CLAUDE_FAILURE="Claude Code couldn't sign in (${verdict#sign-in: })"; return 2 ;;
        *) CLAUDE_FAILURE="${verdict#failed: }"; return 1 ;;
    esac
}

# A sign-in failure is its own message: how the session should authenticate is the user's call.
claude_stopped() {
    case "$CLAUDE_FAILURE" in
        "Claude Code couldn't sign in"*)
            fail "$CLAUDE_FAILURE. Nothing was installed; it needs a login it can use from a script (see FORK.md)." ;;
        "")
            fail "Claude Code's attempt to $1 didn't pass the update's checks. See build/update.log; the attempt is kept in build/update-worktree, and nothing was installed." ;;
        *)
            fail "Claude Code couldn't $1: $CLAUDE_FAILURE. See build/update.log; nothing was installed." ;;
    esac
}

# What a finished merge looks like, checked here rather than taken from the session's own word.
merge_is_complete() {
    [ -z "$(git diff --name-only --diff-filter=U)" ] \
        && ! git rev-parse -q --verify MERGE_HEAD >/dev/null \
        && git merge-base --is-ancestor "$UPSTREAM" HEAD \
        && [ -z "$(git status --porcelain)" ] \
        && ! git grep -qE '^(<<<<<<<|>>>>>>>)( |$)' HEAD
}

AFTERWORD="
Read AGENTS.md and FORK.md first and follow them, and fix any doc the change made wrong. Only the
commands you need are permitted; if one is refused, find another way with the ones that work rather
than stopping. Verify before committing:
the Debug build (\`xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug
-derivedDataPath build/DebugDerivedData ARCHS=arm64 build\`) succeeds with no new warnings,
\`./Scripts/lint.sh\` is clean, and \`./Scripts/run-tests.sh <harness>\` passes for every area you
touched (icon-cache-test is known to be flaky under the full suite and passes alone).
Leave the working tree clean. Never push, create or move branches, or change anything outside this
directory. End your reply with exactly one line: \`RESULT: resolved\` once everything is committed and
verified, or \`RESULT: failed: <reason>\`."

conflict_task() {
    cat <<EOF
You are completing an update of this personal fork of Tinycast. This directory is a scratch git
worktree in the middle of merging upstream/main (v$VERSION, MERGE_HEAD) into the fork (HEAD), and
these files conflict:

$1

\`git log --oneline MERGE_HEAD..HEAD\` lists the fork's own commits and FORK.md says what each one is
for; \`git log --oneline HEAD..MERGE_HEAD\` lists upstream's new ones. For every conflicted file, read
both sides and the commits behind them, keep upstream's change, and re-apply the fork's intent on
top of it so neither side's behaviour is lost. Tinycast.xcodeproj/project.pbxproj is generated: take
upstream's (\`git checkout --theirs\`) and run \`xcodegen generate\`. Localizable.xcstrings keeps
upstream's order; re-insert only the fork's entries, never re-sort it. Then \`git add\` the resolved
files and \`git commit --no-edit\` to conclude the merge.
$AFTERWORD
EOF
}

build_task() {
    cat <<EOF
You are completing an update of this personal fork of Tinycast. This directory is a scratch git
worktree where upstream v$VERSION is already merged into the fork and committed, but the Release
build fails. Its errors:

$1

\`git log --oneline HEAD^2..HEAD^1\` lists the fork's own commits and FORK.md says what each one is
for. Keep upstream's behaviour and adapt the fork's code to it until it builds, then commit with a
message starting "Fix the fork after merging upstream v$VERSION".
$AFTERWORD
EOF
}

build_release() {
    xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
        -derivedDataPath "$DERIVED" -quiet \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Tinycast Self-Signed" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
        MARKETING_VERSION="$VERSION" \
        build 2>&1 | tee "$BUILD_LOG"
    return "${PIPESTATUS[0]}"
}

FIXED_BY_CLAUDE=""

echo "▸ Preparing a copy of ${BRANCH}…"
if [ -d "$WORKTREE" ]; then
    git -C "$WORKTREE" merge --abort >/dev/null 2>&1
    git -C "$WORKTREE" reset -q --hard && git -C "$WORKTREE" checkout -q --detach "$OLD" \
        || fail "Couldn't reset $WORKTREE."
else
    git worktree add -q --detach "$WORKTREE" "$OLD" || fail "Couldn't create $WORKTREE."
fi
cd "$WORKTREE" || exit 1
if ! $REBUILD && ! git merge -q --no-edit -m "Merge upstream v$VERSION" "$UPSTREAM"; then
    CONFLICTS="$(git diff --name-only --diff-filter=U)"
    FILES="$(echo "$CONFLICTS" | tr '\n' ' ')"
    # The project file is generated from project.yml, so regenerating it is the resolution.
    if [ "$CONFLICTS" = "Tinycast.xcodeproj/project.pbxproj" ]; then
        git checkout -q --theirs -- "$CONFLICTS" && xcodegen generate --quiet \
            && git add "$CONFLICTS" && git commit -q --no-edit \
            || fail "Couldn't regenerate the conflicting project file."
    elif [ "$USE_CLAUDE" = 1 ]; then
        ask_claude "merge conflict" "$(conflict_task "$CONFLICTS")" && merge_is_complete \
            || claude_stopped "resolve the conflict in ${FILES% }"
        FIXED_BY_CLAUDE="resolved the conflict in ${FILES}"
    else
        git merge --abort
        fail "Merge conflict in: ${FILES}— nothing was changed."
    fi
fi
xcodegen generate --quiet || fail "xcodegen failed."
if ! git diff --quiet; then
    git commit -q -am "Regenerate Tinycast.xcodeproj" || fail "Couldn't commit the regenerated project."
fi

echo "▸ Building v$VERSION (Release)…"
if ! build_release; then
    ERRORS="$(grep -E 'error:' "$BUILD_LOG" | sort -u | head -40)"
    $REBUILD || [ "$USE_CLAUDE" != 1 ] \
        && fail "Build failed, see build/update.log. The merge is kept in build/update-worktree."
    ask_claude "build" "$(build_task "${ERRORS:-$(tail -60 "$BUILD_LOG")}")" && merge_is_complete && build_release \
        || claude_stopped "fix the build"
    FIXED_BY_CLAUDE="${FIXED_BY_CLAUDE:+$FIXED_BY_CLAUDE and }fixed the build"
fi
MERGED="$(git rev-parse HEAD)"
APP="$DERIVED/Build/Products/Release/Tinycast.app"
codesign --verify --deep --strict "$APP" || fail "The new build's signature doesn't verify."
cd "$REPO" || exit 1

if $REBUILD && [ "$MERGED" = "$OLD" ]; then
    :
elif [ "$(git branch --show-current)" = "$BRANCH" ]; then
    echo "▸ Moving $BRANCH to the merge…"
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
if $REBUILD; then
    notify "✓ Rebuilt and installed $BRANCH ($(git rev-parse --short "$BRANCH"))."
else
    notify "✓ Updated to v$VERSION ($COUNT upstream commits)${FIXED_BY_CLAUDE:+. Claude Code $FIXED_BY_CLAUDE}."
fi
