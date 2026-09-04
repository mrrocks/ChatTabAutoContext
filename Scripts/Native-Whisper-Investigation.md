# Native whisper recipient preservation

Investigated on 2026-09-04 against Blizzard's published UI source mirror and the local EllesmereUI checkout.

## Finding

IM chat mode provides an existing native route for Battle.net and private character conversation tabs. No recipient-copying code is needed in ChatTabAutoContext for that route. Actual taint behavior still needs an in-game trial.

The user confirmed that their chat style was already IM and that the native Battle.net conversation test worked. Protected-content taint behavior has not yet been confirmed.

1. Blizzard initializes each temporary conversation's own edit box with its chat type, sticky type, and recipient in [FCF_SetTemporaryWindowType](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua#L561).
2. A native hardware tab click makes that edit box the last active input when the chat style is not Classic, in [FCF_Tab_OnClick](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/FloatingChatFrame.lua#L1397).
3. [ChooseBoxForSend](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua#L456) uses that input in IM mode. Classic mode instead chooses General's edit box for ordinary chat, even when passed a conversation frame explicitly.
4. After sending from a temporary window's own box, [OnEnterPressed](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua#L381) restores the window's chat type and recipient in Blizzard execution. Escape resets the sticky chat type; it does not separately restore a recipient changed during a draft.

The local EllesmereUI chat code does not override these routing functions or set `chatStyle`. Its tab overlays pass hardware clicks through to the native tabs (`EllesmereUIChat_Tabs.lua`). This supports trying the native IM route, but does not establish that the installed version or every addon combination is taint-free.

## What this supports

- Returning to an existing Battle.net/private conversation tab and opening its native input.
- Restoring that conversation's recipient after sends through its own input.
- Leaving all private recipient handling to Blizzard.

This does not add Battle.net overrides to ordinary channel tabs or copy private recipients into Classic mode's shared input. Calling `SendBNetTell` or `OpenChat` from addon code is not equivalent to preserving the native hardware path. `SendBNetTell` also accepts only the tokenized name in the inspected source; the extra frame argument supplied by EllesmereUI's minimap action does not constrain its routing.

## In-game trial

1. Record the current mode with `/dump GetCVar("chatStyle")`.
2. Switch with `/console chatStyle im`, then `/reload` for a fresh session.
3. Open two Battle.net conversation tabs through Blizzard's chat/friends UI. Keep the minimap action out of this initial test to isolate the native path.
4. Click each tab by hand, press Enter, and check the recipient in the header. Check returning from a normal channel tab, reopening after a send, and Escape/reopen with no recipient change.
5. Repeat with a private character conversation when available and in the protected-content conditions that previously produced errors.
6. If a failure occurs, compare with Tab Selection disabled, then with EllesmereUI Chat disabled. Reload between runs so an earlier tainted session does not contaminate the comparison.

To restore Classic mode, use `/console chatStyle classic` and `/reload`. IM is a global chat-style preference and changes focus/input behavior across all tabs. If the recorded original mode was already IM, no mode change is needed.

## Local verification

`Scripts/Test-TabContext.lua` now models Classic versus IM input routing. Its private edit-box fixtures throw if the addon queries recipient, chat type, sticky type, focus, or draft text. Checks cover tab switches, a pending focus callback from the previous tab, and deferred group/world refreshes. They verify that the native boxes remain unhooked and unmodified.

These mocks validate addon non-interference, not Blizzard's secure execution or real message delivery. No addon runtime changes were made for this investigation.
