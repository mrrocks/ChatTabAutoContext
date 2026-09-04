-- Run from the repository root with Lua or fengari.
-- These mocks check targeting behavior; WoW must validate actual taint safety.
local secret = {}
issecretvalue = function(value) return value == secret end
canaccessvalue = function(value) return value ~= secret end
securecallfunction = function(fn, ...) return fn(...) end

local frames, timers = {}, {}
function CreateFrame()
    local frame = { scripts = {} }
    function frame:SetScript(event, fn) self.scripts[event] = fn end
    function frame:RegisterEvent() end
    frames[#frames + 1] = frame
    return frame
end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flushTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end

local function chatFrame(id, chatType, target)
    local frame = {
        chatType = chatType, chatTarget = target, isTemporary = id > 10,
        messageTypeList = { "SAY" }, channelList = {}
    }
    function frame:GetID() return id end
    function frame:IsShown() return self.hidden ~= true end
    local box = {
        chatFrame = frame, chatType = "SAY", stickyType = "SAY",
        text = "", scripts = {}, writes = 0
    }
    function box:GetChatType() return self.chatType end
    function box:GetParent() return self.chatFrame end
    function box:GetStickyType() return self.stickyType end
    function box:GetTellTarget()
        assert(self.chatType ~= "BN_WHISPER", "Read a Battle.net recipient")
        return self.tellTarget
    end
    function box:SetChatType(value) self.chatType = value; self.writes = self.writes + 1 end
    function box:SetStickyType(value) self.stickyType = value; self.writes = self.writes + 1 end
    function box:SetTellTarget(value) self.tellTarget = value; self.writes = self.writes + 1 end
    function box:UpdateHeader() self.writes = self.writes + 1 end
    function box:GetText() return self.text end
    function box:HasFocus() return self.focused end
    function box:HookScript(event, fn) self.scripts[event] = fn end
    frame.editBox = box
    return frame
end

ChatFrame1 = chatFrame(1)
local alice = chatFrame(11, "WHISPER", "Alice-Realm")
local bob = chatFrame(12, "WHISPER", "Bob-Realm")
local bnet = chatFrame(13, "BN_WHISPER", secret)
CHAT_FRAMES = { ChatFrame1, alice, bob, bnet }
SELECTED_CHAT_FRAME = ChatFrame1
ChatTypeInfo = { SAY = { sticky = 1 } }
local classic = true
local lastNativeEditBox
ChatFrameUtil = {
    ChooseBoxForSend = function(frame)
        -- Model Blizzard's routing for ordinary chat (no voice transcription).
        if classic then return ChatFrame1.editBox end
        if frame and frame:IsShown() then return frame.editBox end
        if lastNativeEditBox and lastNativeEditBox:GetParent():IsShown() then
            return lastNativeEditBox
        end
        return ChatFrame1.editBox
    end,
    GetLastActiveWindow = function() return lastNativeEditBox end
}
local addon = {}
assert(loadfile("modules/tab-selection/main.lua"))("Test", addon)
local watcher = assert(frames[1].scripts.OnUpdate)
local box = ChatFrame1.editBox
local function selectTab(frame)
    -- Simulate the result of a hardware tab click; never call Blizzard's
    -- selection functions from the addon itself.
    SELECTED_CHAT_FRAME = frame
    if not classic then lastNativeEditBox = frame.editBox end
    watcher()
end
local function expectTarget(chatType, recipient)
    assert(box.chatType == chatType, "Unexpected chat type: " .. tostring(box.chatType))
    if recipient then assert(box.tellTarget == recipient, "Unexpected recipient") end
end

selectTab(alice)
expectTarget("WHISPER", "Alice-Realm")
selectTab(bob)
expectTarget("WHISPER", "Bob-Realm")
selectTab(ChatFrame1)
expectTarget("SAY")
print("PASS: character tabs restore recipients and release the shared input")

selectTab(alice)
box.focused = true
box.scripts.OnEditFocusGained(box)
flushTimers()
box.text = "Hello"
box.scripts.OnTextChanged(box, true)
box.text = ""
box.chatType = box.stickyType -- Blizzard resets the type before the post-script hook.
box.scripts.OnTextChanged(box, false)
box.scripts.OnEnterPressed(box)
box.scripts.OnEditFocusGained(box)
flushTimers()
expectTarget("WHISPER", "Alice-Realm")
print("PASS: reopening after a send restores the character tab")

box.chatType, box.tellTarget = "WHISPER", "Manual-Realm"
assert(not addon.ApplyActiveTabContext(alice))
expectTarget("WHISPER", "Manual-Realm")
box.chatType, box.tellTarget = "BN_WHISPER", secret
local writes = box.writes
assert(not addon.ApplyActiveTabContext(alice))
assert(box.writes == writes)
print("PASS: explicit character and Battle.net whispers are preserved")

box.chatType = "SAY"
writes = box.writes
for _, target in ipairs({ bnet, chatFrame(14, "WHISPER", secret),
    chatFrame(15, secret, "Hidden-Realm"), chatFrame(16, "WHISPER", ""),
    chatFrame(17, "WHISPER"), chatFrame(18, "SAY") }) do
    assert(not addon.ApplyActiveTabContext(target))
end
assert(box.writes == writes)
assert(next(alice.editBox.scripts) == nil and next(bnet.editBox.scripts) == nil)
print("PASS: private, missing, and Battle.net targets are excluded; temporary boxes stay unhooked")

assert(addon.ApplyActiveTabContext(alice))
alice.chatTarget = "Reused-Realm"
assert(addon.ApplyActiveTabContext(alice))
expectTarget("WHISPER", "Reused-Realm")
alice.chatType, alice.chatTarget = "BN_WHISPER", secret
writes = box.writes
assert(not addon.ApplyActiveTabContext(alice))
assert(box.writes == writes)
print("PASS: pooled conversation windows use the current recipient and reject Battle.net reuse")

classic = false
box = bob.editBox
box.chatType, box.stickyType, box.tellTarget = "WHISPER", "WHISPER", "Bob-Realm"
assert(addon.ApplyActiveTabContext(bob))
expectTarget("WHISPER", "Bob-Realm")
box.tellTarget = "Manual-Realm"
assert(not addon.ApplyActiveTabContext(bob))
expectTarget("WHISPER", "Manual-Realm")
print("PASS: character targeting also works with a dedicated IM edit box")

classic = true
box = ChatFrame1.editBox
box.chatType, box.stickyType = "SAY", "SAY"
selectTab(ChatFrame1)
box.scripts.OnEditFocusGained(box)
flushTimers()
box.chatType, box.tellTarget, box.text = "WHISPER", "Override-Realm", "Hello"
box.scripts.OnTextChanged(box, true)
box.chatType, box.text = "SAY", ""
box.scripts.OnTextChanged(box, false)
box.scripts.OnEnterPressed(box)
assert(addon.ApplyActiveTabContext(ChatFrame1))
expectTarget("WHISPER", "Override-Realm")
print("PASS: ordinary tabs still remember character whisper overrides after sends")

-- Native-recipient investigation: the addon must leave IM conversation boxes
-- alone. Throw on private-state queries so that checking only writes is not
-- enough to pass. This does not simulate WoW's actual taint propagation.
classic = false
local privateCharacter = chatFrame(19, "WHISPER", secret)
local function rejectPrivateQuery() error("Queried a native private edit box") end
for _, frame in ipairs({ bnet, privateCharacter }) do
    local nativeBox = frame.editBox
    nativeBox.chatType, nativeBox.stickyType = frame.chatType, frame.chatType
    nativeBox.tellTarget = secret -- Fixture for Blizzard-owned recipient state.
    nativeBox.GetTellTarget = rejectPrivateQuery
    nativeBox.GetChatType = rejectPrivateQuery
    nativeBox.GetStickyType = rejectPrivateQuery
    nativeBox.HasFocus = rejectPrivateQuery
    nativeBox.GetText = rejectPrivateQuery
    local nativeWrites = nativeBox.writes

    selectTab(ChatFrame1)
    -- A delayed callback from the previous input must not disturb the newly
    -- selected native conversation.
    ChatFrame1.editBox.scripts.OnEditFocusGained(ChatFrame1.editBox)
    selectTab(frame)
    flushTimers()
    assert(ChatFrameUtil.ChooseBoxForSend() == nativeBox)
    assert(not addon.ApplyActiveTabContext(frame))
    frames[2].scripts.OnEvent() -- Group/world refresh while on this tab.
    flushTimers()
    selectTab(ChatFrame1)
    assert(ChatFrameUtil.ChooseBoxForSend() == ChatFrame1.editBox)
    selectTab(frame)
    assert(ChatFrameUtil.ChooseBoxForSend() == nativeBox)
    assert(nativeBox.writes == nativeWrites)
    assert(nativeBox.tellTarget == secret and nativeBox.chatType == frame.chatType)
    assert(next(nativeBox.scripts) == nil)
end
print("PASS: IM routing preserves native Battle.net/private boxes across tab switches and deferred refreshes")

classic = true
selectTab(ChatFrame1)
selectTab(bnet)
assert(ChatFrameUtil.ChooseBoxForSend(bnet) == ChatFrame1.editBox)
assert(bnet.editBox.tellTarget == secret)
print("PASS: Classic mode still routes through General despite the conversation's native recipient")
