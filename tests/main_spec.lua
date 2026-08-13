local secretValue = {}
local selectedFrame
local activeEditBox
local dockedFrames = {}
local timers = {}
local refreshCount = 0
local frameData = {}

issecretvalue = function(value)
    return rawequal(value, secretValue)
end

IsInGuild = function()
    return true
end

UnitIsGroupLeader = function()
    return false
end

UnitIsGroupAssistant = function()
    return false
end

IsShiftKeyDown = function()
    return false
end

local messagesByFrame = {
    [1] = { "CHANNEL", "SAY" },
    [2] = { "GUILD", "SAY" },
    [3] = { "WHISPER" }
}

local unpackValues = unpack or table.unpack

local function Unpack(values)
    return unpackValues(values)
end

local function CreateEditBox(frame)
    local editBox = {
        chatFrame = frame,
        chatType = "SAY",
        stickyType = "SAY",
        text = ""
    }

    function editBox:GetParent()
        return self.chatFrame
    end

    function editBox:GetChatType()
        return self.chatType
    end

    function editBox:GetStickyType()
        return self.stickyType
    end

    function editBox:SetChatType(chatType)
        self.chatType = chatType
    end

    function editBox:GetTellTarget()
        return self.tellTarget
    end

    function editBox:SetTellTarget(tellTarget)
        self.tellTarget = tellTarget
    end

    function editBox:GetChannelTarget()
        return self.channelId
    end

    function editBox:SetChannelTarget(channelId)
        self.channelId = channelId
    end

    function editBox:UpdateHeader()
        self.headerUpdated = true
    end

    function editBox:GetText()
        return self.text
    end

    function editBox:GetCursorPosition()
        return self.cursorPosition
    end

    return editBox
end

local function CreateChatFrame(id, shown)
    local frame = {
        id = id,
        name = "ChatFrame" .. id,
        shown = shown
    }

    function frame:GetID()
        return self.id
    end

    function frame:GetName()
        return self.name
    end

    function frame:IsShown()
        return self.shown
    end

    frame.editBox = CreateEditBox(frame)

    local tab = {
        frame = frame,
        shown = false
    }

    function tab:IsShown()
        return self.shown
    end

    _G[frame.name .. "Tab"] = tab
    frameData[frame] = {
        bg = {
            shown = shown,
            IsShown = function(self)
                return self.shown
            end,
            SetShown = function(self, value)
                self.shown = value
            end
        }
    }

    return frame
end

local channelFrame = CreateChatFrame(1, true)
channelFrame.channelList = { "General" }
local guildFrame = CreateChatFrame(2, false)
local whisperListFrame = CreateChatFrame(3, false)
local secretWhisperFrame = CreateChatFrame(4, false)
secretWhisperFrame.chatType = "WHISPER"
secretWhisperFrame.chatTarget = secretValue

dockedFrames = { channelFrame, guildFrame, whisperListFrame }
selectedFrame = channelFrame
activeEditBox = channelFrame.editBox
GENERAL_CHAT_DOCK = {}
SELECTED_CHAT_FRAME = channelFrame
SELECTED_DOCK_FRAME = channelFrame

FCFDock_GetChatFrames = function()
    return dockedFrames
end

FCFDock_GetSelectedWindow = function()
    return selectedFrame
end

FCF_Tab_OnClick = function(tab)
    activeEditBox.text = ""
    activeEditBox.cursorPosition = 0
    selectedFrame = tab.frame
    SELECTED_CHAT_FRAME = selectedFrame
    SELECTED_DOCK_FRAME = selectedFrame
    for _, frame in ipairs(dockedFrames) do
        frame.shown = frame == selectedFrame
    end
end

GetChatWindowChannels = function()
    return nil
end

GetChatWindowMessages = function(frameId)
    return Unpack(messagesByFrame[frameId] or {})
end

GetChannelName = function(candidate)
    if candidate == "General" or candidate == 1 then
        return 1, "General"
    end
    return 0, nil
end

ChatTypeInfo = {
    CHANNEL = { sticky = 1 },
    GUILD = { sticky = 1 },
    SAY = { sticky = 1 },
    WHISPER = { sticky = 0 },
    BN_WHISPER = { sticky = 0 }
}

local eventCallbacks = {}

EventRegistry = {
    RegisterCallback = function(_, event, callback, owner)
        eventCallbacks[event] = { callback = callback, owner = owner }
    end
}

ChatFrameUtil = {
    GetActiveWindow = function()
        return activeEditBox
    end,
    GetLastActiveWindow = function()
        return activeEditBox
    end,
    ChooseBoxForSend = function(frame)
        return frame and frame.editBox or activeEditBox
    end,
    GetLastTellTarget = function()
        error("secret tell target")
    end,
    OpenChat = function(text, frame, cursorPosition)
        local editBox = frame and frame.editBox or activeEditBox
        activeEditBox = editBox
        if text then
            editBox.text = text
            editBox.setText = 1
        end
        editBox.cursorPosition = cursorPosition
        return editBox
    end,
    SendTell = function(name, chatFrame)
        ChatFrameUtil.SendTellWithMessage(name, "", chatFrame)
    end,
    SendTellWithMessage = function(name, text, chatFrame)
        local editBox = ChatFrameUtil.OpenChat(
            (name and "/w " .. tostring(name) .. " " or ""),
            chatFrame
        )
        editBox.chatType = "WHISPER"
        editBox.tellTarget = name
        editBox.text = text
        activeEditBox = editBox
    end,
    SendBNetTell = function(tokenizedName)
        activeEditBox.chatType = "BN_WHISPER"
        activeEditBox.tellTarget = tokenizedName
    end
}

hooksecurefunc = function(target, method, callback)
    local original = target[method]
    target[method] = function(...)
        local results = { original(...) }
        callback(...)
        return Unpack(results)
    end
end

ChatEdit_CustomTabPressed = function()
    return false
end

CreateFrame = function()
    return {
        RegisterEvent = function()
        end,
        SetScript = function()
        end,
        UnregisterAllEvents = function()
        end
    }
end

C_Timer = {
    After = function(_, callback)
        timers[#timers + 1] = callback
    end
}

EllesmereUI = {
    _chatCFD = function(frame)
        return frameData[frame]
    end
}

_ECHAT_RefreshAll = function()
    refreshCount = refreshCount + 1
end

local addon = {}
assert(loadfile("compatibility/ellesmere.lua"))("ChatTabAutoContext", addon)
assert(loadfile("main.lua"))("ChatTabAutoContext", addon)

local function AssertEqual(actual, expected)
    if actual ~= expected then
        error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end

AssertEqual(addon.GetDefaultTarget(secretWhisperFrame), nil)
AssertEqual(addon.GetDefaultTarget(whisperListFrame), nil)

channelFrame.editBox.text = "draft"
channelFrame.editBox.cursorPosition = 3
AssertEqual(addon.CycleChatTab(channelFrame.editBox, 1), true)
AssertEqual(selectedFrame, guildFrame)
AssertEqual(guildFrame.editBox.text, "draft")
AssertEqual(guildFrame.editBox.cursorPosition, 3)
AssertEqual(guildFrame.editBox.chatType, "GUILD")
AssertEqual(#timers, 1)

timers[1]()
AssertEqual(refreshCount, 1)
AssertEqual(frameData[channelFrame].bg.shown, false)
AssertEqual(frameData[guildFrame].bg.shown, true)
AssertEqual(frameData[whisperListFrame].bg.shown, false)

addon.QueueEllesmereUIChatSync()
timers[2]()
AssertEqual(refreshCount, 1)

guildFrame.editBox.text = secretValue
AssertEqual(ChatEdit_CustomTabPressed(guildFrame.editBox), false)
AssertEqual(selectedFrame, guildFrame)

guildFrame.editBox.text = ""
FCF_Tab_OnClick(_G[channelFrame.name .. "Tab"])
AssertEqual(selectedFrame, channelFrame)

local function ResetEditBox(editBox, chatType)
    editBox.chatType = chatType
    editBox.stickyType = chatType
    editBox.tellTarget = nil
    editBox.channelId = nil
    editBox.headerUpdated = false
    editBox.text = ""
end

ChatFrameUtil.SendTell("PlayerName", channelFrame)
AssertEqual(addon.ApplyActiveTabContext(channelFrame), false)
AssertEqual(channelFrame.editBox.chatType, "WHISPER")
AssertEqual(channelFrame.editBox.tellTarget, "PlayerName")

ChatFrameUtil.OpenChat("", channelFrame)
AssertEqual(channelFrame.editBox.chatType, "WHISPER")
AssertEqual(channelFrame.editBox.tellTarget, "PlayerName")

ResetEditBox(channelFrame.editBox, "SAY")
AssertEqual(addon.ApplyActiveTabContext(channelFrame), true)
AssertEqual(channelFrame.editBox.chatType, "WHISPER")
AssertEqual(channelFrame.editBox.tellTarget, "PlayerName")
AssertEqual(channelFrame.editBox.headerUpdated, true)

channelFrame.editBox.text = "still whispering"
AssertEqual(ChatEdit_CustomTabPressed(channelFrame.editBox), true)
AssertEqual(selectedFrame, guildFrame)
AssertEqual(guildFrame.editBox.chatType, "GUILD")
AssertEqual(guildFrame.editBox.text, "still whispering")

guildFrame.editBox.text = "back to whisper"
AssertEqual(addon.CycleChatTab(guildFrame.editBox, -1), true)
AssertEqual(selectedFrame, channelFrame)
AssertEqual(channelFrame.editBox.chatType, "WHISPER")
AssertEqual(channelFrame.editBox.tellTarget, "PlayerName")

ResetEditBox(channelFrame.editBox, "SAY")
channelFrame.editBox.chatType = "CHANNEL"
channelFrame.editBox.channelId = 1
channelFrame.editBox.text = "back on general"
eventCallbacks["ChatFrame.OnEditBoxPreSendText"].callback(
    eventCallbacks["ChatFrame.OnEditBoxPreSendText"].owner,
    channelFrame.editBox
)
ResetEditBox(channelFrame.editBox, "SAY")
AssertEqual(addon.ApplyActiveTabContext(channelFrame), true)
AssertEqual(channelFrame.editBox.chatType, "CHANNEL")
AssertEqual(channelFrame.editBox.channelId, 1)

ChatFrameUtil.SendTellWithMessage(secretValue, "", channelFrame)
ResetEditBox(channelFrame.editBox, "SAY")
AssertEqual(addon.ApplyActiveTabContext(channelFrame), true)
AssertEqual(channelFrame.editBox.chatType, "CHANNEL")
AssertEqual(channelFrame.editBox.channelId, 1)

ResetEditBox(channelFrame.editBox, "SAY")
ChatFrameUtil.SendBNetTell("BNetFriend")
ResetEditBox(channelFrame.editBox, "SAY")
AssertEqual(addon.ApplyActiveTabContext(channelFrame), true)
AssertEqual(channelFrame.editBox.chatType, "BN_WHISPER")
AssertEqual(channelFrame.editBox.tellTarget, "BNetFriend")

ResetEditBox(channelFrame.editBox, "SAY")
channelFrame.editBox.chatType = "WHISPER"
channelFrame.editBox.tellTarget = "TypedName"
channelFrame.editBox.text = "typed whisper"
eventCallbacks["ChatFrame.OnEditBoxPreSendText"].callback(
    eventCallbacks["ChatFrame.OnEditBoxPreSendText"].owner,
    channelFrame.editBox
)
ResetEditBox(channelFrame.editBox, "SAY")
AssertEqual(addon.ApplyActiveTabContext(channelFrame), true)
AssertEqual(channelFrame.editBox.chatType, "WHISPER")
AssertEqual(channelFrame.editBox.tellTarget, "TypedName")

channelFrame.editBox.tellTarget = "OtherPlayer"
channelFrame.editBox.stickyType = "SAY"
channelFrame.editBox.text = "ad hoc whisper"
AssertEqual(ChatEdit_CustomTabPressed(channelFrame.editBox), false)
AssertEqual(selectedFrame, channelFrame)

ResetEditBox(channelFrame.editBox, "SAY")
channelFrame.editBox.chatType = "GUILD"
channelFrame.editBox.text = "manual guild"
eventCallbacks["ChatFrame.OnEditBoxPreSendText"].callback(
    eventCallbacks["ChatFrame.OnEditBoxPreSendText"].owner,
    channelFrame.editBox
)
ResetEditBox(channelFrame.editBox, "SAY")
AssertEqual(addon.ApplyActiveTabContext(channelFrame), true)
AssertEqual(channelFrame.editBox.chatType, "GUILD")
