# Manual QA

1. Enable only ChatTabAutoContext and EllesmereUIChat 8.8.4 or newer.
2. Create at least two docked tabs with different channel or message filters.
3. Focus chat, type unsent text, press Tab and Shift+Tab, and verify the selected EllesmereUI tab, visible message history, header target, and unsent text all move together.
4. Repeat with EllesmereUI chat visibility set to always, fade, and hidden-in-combat modes.
5. Open character and Battle.net whisper tabs, then verify Enter and Tab do not produce secret-value, `UpdateHeader`, `isLocked`, or `privateMessageList` errors.
6. Repeat the tab cycle in combat with `/console taintLog 2`, then inspect the taint log for ChatTabAutoContext.
7. Disable EllesmereUIChat and verify stock Blizzard tab cycling and automatic context still behave identically.
8. Click a character name in chat, close the edit box, press Enter, and verify the input stays whispered to that player until you send on the tab's default channel. Repeat with EllesmereUIChat enabled, including Tab cycling away and back.
