# Manual QA

| Scenario | Steps | Expected |
| --- | --- | --- |
| Active tab | Select a chat tab, press `Enter`, and send a message. | The edit box opens on the selected tab and sends to that tab's channel. |
| Multiple channels | Configure a tab with at least two joined channels, select it, and press `Enter`. | The edit box targets the first channel listed for that tab. |
| Chat type fallback | Select a tab configured for Guild, Party, Raid, or Say without a joined channel and press `Enter`. | The edit box targets the first sendable chat type configured for the tab. |
| Whisper tab | Select a character or Battle.net whisper tab and press `Enter`. | The edit box opens on that tab with the same whisper recipient. |
| Incoming whisper | Receive a whisper, select a tab that displays whispers, and press `Enter`. | The edit box targets the person who sent the latest whisper. |
| Explicit command | Use a slash-chat or reply binding. | The explicit command and target remain unchanged. |
| Unsupported tab | Select a tab with no sendable channel, such as a system-only tab, and press `Enter`. | Blizzard's existing chat target remains unchanged. |
| Combat | Enter combat, select a normal chat tab, and press `Enter`. | Chat opens on the tab's target without a protected-action error. |
