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

- Logs go to `build/update.log`. A merge conflict or failed build stops and notifies; nothing is changed.
- A conflict only in `Tinycast.xcodeproj/project.pbxproj` resolves itself by regenerating it with
  XcodeGen. Any other conflict needs resolving by hand in a normal `git merge upstream/main`.
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
