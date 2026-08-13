# ChatTabAutoContext

WoW addon that opens chat on the active tab's channel or whisper target, remembers per-tab session overrides, and cycles docked tabs with Tab / Shift+Tab.

## Layout

- `main.lua` — targeting, session overrides, OpenChat / Tab / SendTell hooks
- `compatibility/ellesmere.lua` — sync EllesmereUI Chat 8.8+ tab visuals after a programmatic tab change
- `.pkgmeta` — CurseForge packager config
- `CHANGELOG.md` — **current release notes only**. Delete older version sections before tagging so CurseForge publishes just this release.

## Code

- Modern Lua. No inline or block comments. Self-descriptive names.
- Treat `issecretvalue` results as opaque. Never compare, concatenate, or pass secret whisper names, channel names, or group-permission results into `SetTellTarget` / `UpdateHeader`.
- Do not overwrite an in-progress whisper (`HasWhisperTellTarget`) with the tab's channel default. Name clicks go through `ChatFrameUtil.SendTellWithMessage`.
- Session overrides live until reload. Sticky channel changes and clicked/typed whispers are remembered per tab. Sending on the tab's default target clears the override.
- EllesmereUI keeps Blizzard frames as the data plane (hyperlink hit-zones, edit box). After `FCF_Tab_OnClick`, call `addon.QueueEllesmereUIChatSync()`. Do not drive EllesmereUI private state.

## Releases

CurseForge automatic packaging is already configured via a GitHub webhook. A GitHub Release is not required and does not trigger packaging.

Untagged pushes to `main` package as **alpha**. A **release** is created only when the webhook sees a tagged commit.

1. Update `CHANGELOG.md` to the new version only.
2. Commit on `main`.
3. Create an annotated tag named like `1.3.0` (no `v` prefix, no `alpha`/`beta` in the name):

   `git tag -a 1.3.0 -m "ChatTabAutoContext 1.3.0"`

4. Push **the tag only** (this also pushes the commit):

   `git push origin 1.3.0`

Do not `git push origin main` first. That webhook fires on an untagged commit and publishes an alpha. If that happens, delete the remote tag and push the same tag again so CurseForge sees a tagged release.
