# ChatTabAutoContext

WoW addon that opens chat on the active tab's channel or whisper target and remembers per-tab session overrides.

## Layout

- `modules/tab-selection/` — separately toggleable targeting and session overrides
- `modules/notifications/` — separately toggleable unread-message addon, including EllesmereUI glow replacement
- `Scripts/Generate-Release-Changelog.ps1` — builds the current release notes from commit subjects
- `.pkgmeta` — CurseForge packager config
- `CHANGELOG.md` — generated current release notes only

## Taint safety

Do not select or click Blizzard chat tabs programmatically. Calls to `FCF_Tab_OnClick`, `FCFDock_SelectWindow`, and `Button:Click()` taint the selected-frame and active-edit-box globals even through `securecallfunction`, which can later break whisper history when private values are processed. Leave tab selection to native hardware clicks.

## Releases

CurseForge automatic packaging is already configured via a GitHub webhook. A GitHub Release is not required and does not trigger packaging.

The CurseForge project is configured to package **tagged commits only**. Untagged pushes to `main` do not create packages, so development commits can be pushed freely. A **release** is created only when the webhook sees a tagged commit. Do not enable **Package all commits**, which would turn ordinary branch pushes into alpha packages.

Unless otherwise specified, create the next release by incrementing the patch version only (for example, `1.3.2` becomes `1.3.3`).

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

5. Push the tag (this also pushes the commit object and lets CurseForge see the release tag):

   `git push origin 1.3.0`

6. Confirm that CurseForge created the tagged release.
7. Keep `origin/main` synchronized, then push `main` if needed:

   `git push origin main`

GitHub sends branch and tag updates as separate push events, even when both refs are supplied to one `git push` command. With tagged-commits-only packaging, the branch event is ignored and the tag event creates the release. If the CurseForge setting is ever changed back to **Package all commits**, restore tag-only packaging before pushing to avoid unwanted alpha packages.
