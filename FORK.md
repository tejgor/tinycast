# This fork

A personal fork of [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast), built and installed
locally on one Mac. Everything in `AGENTS.md` still applies; this file only adds what is different here.

## Branches and remotes

- `origin` is `tejgor/tinycast`, `upstream` is `abue-ammar/tinycast`.
- `personal` is the working branch: every fork change is committed there. `main` stays a plain copy
  of upstream and is never committed to.
- See what the fork changes: `git log --oneline upstream/main..personal`.

## Building, installing, updating

`Scripts/update-fork.sh` is the only install path. It merges and builds in `build/update-worktree`
(a scratch git worktree), so a failure never touches `personal` or the installed app.

| Command | Does |
| --- | --- |
| `Scripts/update-fork.sh` | Fetches upstream, shows the new commits in a dialog, and on confirm merges into `personal`, builds Release, installs to `/Applications/Tinycast.app` and relaunches |
| `Scripts/update-fork.sh --rebuild` | Builds and installs what is **committed** on `personal`, without fetching. Use after committing a fork change |
| `Scripts/update-fork.sh --rollback` | Swaps the installed app with the previous build (`build/Tinycast-previous.app`) |

- Logs go to `build/update.log`.
- Notifications come from `build/Tinycast Update.app`, a helper the script builds from
  `Scripts/update-notifier.swift` on first use (and rebuilds when that file changes) so they carry
  Tinycast's icon; clicking one opens the log. It falls back to AppleScript's notification if the
  helper can't post.
- A conflict only in `Tinycast.xcodeproj/project.pbxproj` resolves itself by regenerating it with
  XcodeGen.
- Any other conflict, and a Release build the merge broke, go to a headless Claude Code session
  (`claude -p`) running in the scratch worktree, on the user's own subscription login:
  - `--restricted` confines its file tools to the worktree and ignores every settings file, so the
    merged code's hooks, MCP servers or permission rules never apply; `--strict-mcp-config` too.
  - Bash is limited to named commands: specific git subcommands (no `git *`, which would allow
    `git -c` and so anything), XcodeGen, `xcodebuild`, and the repo's test, lint and check scripts.
    `git push` and git's `--output` are denied outright.
  - It is capped at `TINYCAST_UPDATE_CLAUDE_MAX_TURNS` turns (150) and stopped, with everything it
    started, after `TINYCAST_UPDATE_CLAUDE_TIMEOUT` seconds (1800).
  - It must end with `RESULT: resolved`, and the script then checks for itself that the merge is
    committed, no conflict markers remain, the tree is clean and the build passes. Anything less
    stops with nothing installed, the reason in the notification, and the attempt left in
    `build/update-worktree`. Transcripts are `build/update-claude-*.json`.
  - A session that can't sign in gets its own message, and how to authenticate is the user's call.
    An expired login is fixed by `/login` again or a long-lived token from `claude setup-token`.
    A future Claude Code that makes `--bare` the `-p` default is different: bare mode reads only
    `ANTHROPIC_API_KEY` or an `apiKeyHelper` from `--settings`, never the subscription login or its
    tokens, so it would need an API key, which bills at API rates.
  - `TINYCAST_UPDATE_CLAUDE=0` turns all of this off.
- If you are that session: you are resolving an upstream merge, so the instructions in your prompt
  and the rules in this file and `AGENTS.md` are the whole job. Keep upstream's change and re-apply
  the fork's intent on top of it.
- Each successful run pushes `personal` to `origin`.

## Identity

- Release builds use bundle id `com.tinycast.app.personal` (set in `project.yml`). Any id other than
  upstream's stable or beta one resolves to `ReleaseChannel.development`, which is what keeps the
  built-in updater from replacing this fork with an upstream release. Do not change it back.
- Signed with the self-signed `Tinycast Self-Signed` identity in the login keychain (`docs/signing.md`).
  Keeping the identity and bundle id fixed keeps macOS permissions across rebuilds.
- Data lives under `~/Library/Application Support/com.tinycast.app.personal/` (notes in `Notes/`),
  and the settings file is `~/.config/tinycast-personal/settings.json`.

## Fork changes so far

- Personal bundle id and `Scripts/update-fork.sh`.
- ⌘↑ / ⌘↓ jump between sections in ⌘K action menus (`RootPaletteView.moveMenuSection`).
- Markdown tables in Notes render as a grid (`NoteMarkdown.Table`, `NoteTableGrid`, notes docs).
- A Table button in the Notes formatting bar inserts an empty three-column table
  (`NoteEditAction.insertTable`); the minimum note window grew from 440 to 470 points to fit it.
- Notes behaves more like Raycast Notes (see `docs/features/notes.md`):
  - a hand-sized window keeps its size (`NotesLocalState.autoSizesWindow`), and planned edits such as
    Return in a list scroll the caret into view;
  - ⌘L link, ⇧⌘S strikethrough, ⌘↵ checkbox, ⌘[ / ⌘] history (`NoteHistory`), ⌘+ / ⌘− / ⌘0 zoom,
    a character/word count toggle, Duplicate Note, Delete All Notes;
  - Settings → Notes → Escape Key Loses Focus and Show Notes Button in Menu Bar (fork-only, not in backups).
  - pins (⇧⌘P, ⌘1–⌘9), a browser with Pinned/Notes sections and "Opened … • N characters" rows, and a
    ⌘K action panel (`NoteActionsWindowController`) with copy/export as Markdown, HTML or plain text
    (`NoteExport`), deeplinks (`NoteDeepLink`, `tinycast://notes/open?id=…`), duplicate and delete all.
  - Device-local Notes state lives in `NotesLocalState` (one `AppCore` line), not in `AppSettings`.
- Settings → General → Transparency thins the launcher's scrim over its glass
  (`AppSettings.paletteTransparency`, `appearance.transparency` in `settings.json`; not in backups).

## Adding a feature without making merges painful

Upstream ships almost daily, so every edit to a shared file is a future merge conflict.

- Prefer new code in its own feature folder, and keep edits to shared files (`AppCore`, `AppIndex`,
  `CommandCatalog`, settings panes) to a few added lines.
- `Scripts/run-tests.sh` lists harness sources file by file. A new file a harness needs means editing
  that list, so prefer putting harness-compiled code in files already on it.
- Never commit a re-sort or reformat of an upstream file. `Scripts/sync-strings.sh` re-sorts all of
  `Localizable.xcstrings`; restore the file and insert only the new entries (translated into every
  language the catalog has) as text in the existing order.
- A new setting can go in `SettingsBackupCoverage.deliberatelyExcluded` instead of `SettingsBackup`
  when it is fork-only, which keeps it out of upstream's backup code.
- Docs and tests follow `AGENTS.md`: update the feature doc, run `./Scripts/run-tests.sh`,
  `./Scripts/lint.sh`, and build Debug with no new warnings before committing.

## Known quirks

- `icon-cache-test` can fail under the full parallel suite and passes alone; it is not a regression.
- The machine has Xcode 27 while upstream documents Xcode 26; builds are fine.
- To check drawing changes without the app, compile a small program against the same sources as
  `notes-editor-test` (the list in `Scripts/run-tests.sh`) and save the view with `cacheDisplay` to
  a PNG.
