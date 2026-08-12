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
    if candidate == "General" then
        return 1, "General"
    end
    return 0, nil
end

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
        activeEditBox = frame.editBox
        activeEditBox.text = text
        activeEditBox.cursorPosition = cursorPosition
        return activeEditBox
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
