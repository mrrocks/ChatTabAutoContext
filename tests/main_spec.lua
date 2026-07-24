local selectedFrame
local activeEditBox
local openCalls = {}
local whisperEventHandler

local channelsByFrame = {
    [1] = { 7, 5 },
    [2] = {},
    [3] = {}
}

local messagesByFrame = {
    [1] = { "CHANNEL", "SAY" },
    [2] = { "SYSTEM", "GUILD", "SAY" },
    [3] = { "SYSTEM", "LOOT" },
    [7] = { "SAY", "PARTY" },
    [8] = { "WHISPER" }
}

local channelNames = {
    [5] = "Trade",
    [7] = "General"
}

local unpackValues = unpack or table.unpack

local function Unpack(values)
    return unpackValues(values)
end

local function CreateFrameStub(id)
    local frame = {
        id = id,
        shown = true
    }

    frame.GetID = function(self)
        return self.id
    end
    frame.IsShown = function(self)
        return self.shown
    end
    frame.editBox = {
        chatFrame = frame,
        text = ""
    }
    frame.editBox.GetParent = function(self)
        return self.chatFrame
    end
    frame.editBox.SetChatType = function(self, chatType)
        self.chatType = chatType
    end
    frame.editBox.SetChannelTarget = function(self, channelId)
        self.channelId = channelId
    end
    frame.editBox.GetTellTarget = function(self)
        return self.tellTarget
    end
    frame.editBox.SetTellTarget = function(self, tellTarget)
        self.tellTarget = tellTarget
    end
    frame.editBox.GetAttribute = function(self, attribute)
        return self[attribute]
    end
    frame.editBox.SetAttribute = function(self, attribute, value)
        self[attribute] = value
    end
    frame.editBox.UpdateHeader = function(self)
        self.headerUpdated = true
    end

    return frame
end

local selectedChannelFrame = CreateFrameStub(1)
local guildFrame = CreateFrameStub(2)
local noTargetFrame = CreateFrameStub(3)
local originalFrame = CreateFrameStub(4)

selectedChannelFrame.channelList = { "Trade", "General" }
local whisperFrame = CreateFrameStub(5)
whisperFrame.chatType = "WHISPER"
whisperFrame.chatTarget = "Alice"
local battleNetWhisperFrame = CreateFrameStub(6)
battleNetWhisperFrame.chatType = "BN_WHISPER_INFORM"
battleNetWhisperFrame.chatTarget = 42
local partyFrame = CreateFrameStub(7)
local incomingWhisperFrame = CreateFrameStub(8)

GENERAL_CHAT_DOCK = {}

FCFDock_GetSelectedWindow = function()
    return selectedFrame
end

GetChatWindowChannels = function(frameId)
    return Unpack(channelsByFrame[frameId] or {})
end

GetChatWindowMessages = function(frameId)
    return Unpack(messagesByFrame[frameId] or {})
end

GetChannelName = function(candidate)
    if candidate == "Trade" then
        return 5, "Trade"
    end
    if candidate == "General" then
        return 7, "General"
    end
    local channelId = tonumber(candidate)
    return channelId or 0, channelNames[channelId]
end

ChatFrameUtil = {
    GetActiveWindow = function()
        return activeEditBox
    end,
    OpenChat = function(text, frame)
        openCalls[#openCalls + 1] = {
            text = text,
            frame = frame
        }
        activeEditBox = frame and frame.editBox or activeEditBox
        if activeEditBox then
            activeEditBox.text = text
        end
        return activeEditBox
    end
}

hooksecurefunc = function(target, method, callback)
    local original = target[method]
    target[method] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end

CreateFrame = function()
    return {
        RegisterEvent = function()
        end,
        SetScript = function(_, scriptName, handler)
            if scriptName == "OnEvent" then
                whisperEventHandler = handler
            end
        end
    }
end

local addon = {}
assert(loadfile("main.lua"))("ChatTabAutoContext", addon)

local function AssertEqual(actual, expected)
    if actual ~= expected then
        error(("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
    end
end

local function ResetOpenCalls()
    openCalls = {}
end

selectedFrame = selectedChannelFrame
AssertEqual(addon.GetActiveChatFrame(), selectedChannelFrame)

SELECTED_CHAT_FRAME = guildFrame
AssertEqual(addon.GetActiveChatFrame(), guildFrame)
SELECTED_CHAT_FRAME = nil

local channelTarget = addon.GetDefaultTarget(selectedChannelFrame)
AssertEqual(channelTarget.chatType, "CHANNEL")
AssertEqual(channelTarget.channelId, 5)

local guildTarget = addon.GetDefaultTarget(guildFrame)
AssertEqual(guildTarget.chatType, "GUILD")
AssertEqual(guildTarget.channelId, nil)

local partyTarget = addon.GetDefaultTarget(partyFrame)
AssertEqual(partyTarget.chatType, "PARTY")
AssertEqual(partyTarget.channelId, nil)

whisperEventHandler(nil, "CHAT_MSG_WHISPER", "Hello", "Bob")
local incomingWhisperTarget = addon.GetDefaultTarget(incomingWhisperFrame)
AssertEqual(incomingWhisperTarget.chatType, "WHISPER")
AssertEqual(incomingWhisperTarget.tellTarget, "Bob")

AssertEqual(addon.GetDefaultTarget(noTargetFrame), nil)

local whisperTarget = addon.GetDefaultTarget(whisperFrame)
AssertEqual(whisperTarget.chatType, "WHISPER")
AssertEqual(whisperTarget.tellTarget, "Alice")

local battleNetWhisperTarget = addon.GetDefaultTarget(battleNetWhisperFrame)
AssertEqual(battleNetWhisperTarget.chatType, "BN_WHISPER")
AssertEqual(battleNetWhisperTarget.tellTarget, 42)

ResetOpenCalls()
activeEditBox = originalFrame.editBox
selectedFrame = selectedChannelFrame
ChatFrameUtil.OpenChat("", originalFrame)
AssertEqual(#openCalls, 2)
AssertEqual(openCalls[1].frame, originalFrame)
AssertEqual(openCalls[2].frame, selectedChannelFrame)
AssertEqual(openCalls[2].text, "")
AssertEqual(selectedChannelFrame.editBox.chatType, "CHANNEL")
AssertEqual(selectedChannelFrame.editBox.channelId, 5)
AssertEqual(selectedChannelFrame.editBox.headerUpdated, true)

ResetOpenCalls()
selectedFrame = guildFrame
ChatFrameUtil.OpenChat("", originalFrame)
AssertEqual(#openCalls, 2)
AssertEqual(openCalls[2].frame, guildFrame)
AssertEqual(openCalls[2].text, "")
AssertEqual(guildFrame.editBox.chatType, "GUILD")
AssertEqual(guildFrame.editBox.headerUpdated, true)

ResetOpenCalls()
selectedFrame = whisperFrame
ChatFrameUtil.OpenChat("", originalFrame)
AssertEqual(#openCalls, 2)
AssertEqual(openCalls[2].frame, whisperFrame)
AssertEqual(whisperFrame.editBox.chatType, "WHISPER")
AssertEqual(whisperFrame.editBox.tellTarget, "Alice")
AssertEqual(whisperFrame.editBox.headerUpdated, true)

ResetOpenCalls()
selectedFrame = selectedChannelFrame
ChatFrameUtil.OpenChat("/reply ", originalFrame)
AssertEqual(#openCalls, 1)

ResetOpenCalls()
selectedFrame = noTargetFrame
ChatFrameUtil.OpenChat("", originalFrame)
AssertEqual(#openCalls, 1)
