# ChatTabAutoContext

WoW addon that opens chat on the active tab's channel or whisper target, remembers per-tab session overrides, and cycles docked tabs with Tab / Shift+Tab.

## Layout

- `modules/tab-selection/` — separately toggleable targeting, session overrides, OpenChat / Tab / SendTell hooks
- `modules/notifications/` — separately toggleable unread-message addon, including EllesmereUI glow replacement
- `Scripts/Generate-Release-Changelog.ps1` — builds the current release notes from commit subjects
- `.pkgmeta` — CurseForge packager config
- `CHANGELOG.md` — generated current release notes only

## Taint safety

Blizzard exposes `ChatEdit_CustomTabPressed` for addon hooks and invokes it through `securecall`. Calls from that hook into Blizzard tab-selection code must use `securecallfunction`; a direct `FCF_Tab_OnClick` / `FCFDock_SelectWindow` call taints the dock state and can break Battle.net whisper history when private values are processed.

## Releases

CurseForge automatic packaging is already configured via a GitHub webhook. A GitHub Release is not required and does not trigger packaging.

Untagged pushes to `main` package as **alpha**. A **release** is created only when the webhook sees a tagged commit.

Release changelogs are generated from commit subjects. Write subjects for players, describing the visible outcome in clear, concise language.

- Use an imperative, sentence-case summary without a conventional-commit prefix for user-visible changes.
- Prefer a specific outcome, such as `Keep chat targeting available during combat`, over an implementation detail such as `Refactor restriction checks`.
- Keep one user-facing outcome per commit where practical.
- Put implementation details in the commit body; only the subject is included in release notes.
- Add `[skip changelog]` to the subject or body for documentation, tests, CI, release tooling, formatting, or internal-only refactors.
- Do not skip fixes, performance improvements, or behavior changes that players should know about.

To publish a release:

1. Commit all release changes on `main`.
2. Generate `CHANGELOG.md`, replacing `1.3.0` with the new version:

   `./Scripts/Generate-Release-Changelog.ps1 -Version 1.3.0`

3. Commit the generated changelog with `[skip changelog]` in the commit message.
4. Create an annotated tag named like `1.3.0` (no `v` prefix, no `alpha`/`beta` in the name):

   `git tag -a 1.3.0 -m "ChatTabAutoContext 1.3.0"`

5. Push **the tag only** (this also pushes the commit):

   `git push origin 1.3.0`

Do not `git push origin main` first. That webhook fires on an untagged commit and publishes an alpha. If that happens, delete the remote tag and push the same tag again so CurseForge sees a tagged release.
