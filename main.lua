local _, addon = ...

local applyingContext = false
local latestIncomingWhisper

local sendableChatTypes = {
    BATTLEGROUND = "BATTLEGROUND",
    EMOTE = "EMOTE",
    GUILD = "GUILD",
    INSTANCE_CHAT = "INSTANCE_CHAT",
    INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    OFFICER = "OFFICER",
    PARTY = "PARTY",
    PARTY_LEADER = "PARTY",
    RAID = "RAID",
    RAID_LEADER = "RAID",
    RAID_WARNING = "RAID_WARNING",
    SAY = "SAY",
    YELL = "YELL"
}

local fallbackMessageTypeOrder = {
    "INSTANCE_CHAT",
    "PARTY",
    "RAID",
    "RAID_WARNING",
    "OFFICER",
    "GUILD",
    "BATTLEGROUND",
    "SAY",
    "YELL",
    "EMOTE"
}

local whisperChatTypes = {
    BN_WHISPER = "BN_WHISPER",
    BN_WHISPER_INFORM = "BN_WHISPER",
    WHISPER = "WHISPER",
    WHISPER_INFORM = "WHISPER"
}

local incomingWhisperEvents = {
    CHAT_MSG_BN_WHISPER = {
        chatType = "BN_WHISPER",
        targetIndex = 13
    },
    CHAT_MSG_WHISPER = {
        chatType = "WHISPER",
        targetIndex = 2
    }
}

local function IsUsableChatFrame(frame)
    if not frame or not frame.editBox then
        return false
    end
    return type(frame.IsShown) ~= "function" or frame:IsShown()
end

local function GetFrameForEditBox(editBox)
    if not editBox then
        return nil
    end
    if editBox.chatFrame then
        return editBox.chatFrame
    end
    if type(editBox.GetParent) == "function" then
        return editBox:GetParent()
    end
    return nil
end

local function GetActiveEditBox()
    if ChatFrameUtil and type(ChatFrameUtil.GetActiveWindow) == "function" then
        local editBox = ChatFrameUtil.GetActiveWindow()
        if editBox then
            return editBox
        end
    end
    if type(ChatEdit_GetActiveWindow) == "function" then
        return ChatEdit_GetActiveWindow()
    end
    return nil
end

function addon.GetActiveChatFrame()
    if IsUsableChatFrame(SELECTED_CHAT_FRAME) then
        return SELECTED_CHAT_FRAME
    end

    if GENERAL_CHAT_DOCK and type(FCFDock_GetSelectedWindow) == "function" then
        local selectedFrame = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
        if IsUsableChatFrame(selectedFrame) then
            return selectedFrame
        end
    end

    if IsUsableChatFrame(SELECTED_DOCK_FRAME) then
        return SELECTED_DOCK_FRAME
    end

    local activeFrame = GetFrameForEditBox(GetActiveEditBox())
    if IsUsableChatFrame(activeFrame) then
        return activeFrame
    end

    local lastActiveEditBox
    if ChatFrameUtil and type(ChatFrameUtil.GetLastActiveWindow) == "function" then
        lastActiveEditBox = ChatFrameUtil.GetLastActiveWindow()
    elseif type(ChatEdit_GetLastActiveWindow) == "function" then
        lastActiveEditBox = ChatEdit_GetLastActiveWindow()
    end

    if lastActiveEditBox then
        local lastActiveFrame = GetFrameForEditBox(lastActiveEditBox)
        if IsUsableChatFrame(lastActiveFrame) then
            return lastActiveFrame
        end
    end

    return nil
end

local function ResolveChannel(candidate)
    if candidate == nil or type(GetChannelName) ~= "function" then
        return nil
    end

    local channelId, channelName = GetChannelName(candidate)
    if channelId and channelId > 0 and channelName and channelName ~= "" then
        return channelId
    end
    return nil
end

local function GetFirstChannelFromValues(...)
    for index = 1, select("#", ...) do
        local channelId = ResolveChannel(select(index, ...))
        if channelId then
            return channelId
        end
    end
    return nil
end

local function GetFirstChannelFromTable(channels)
    if type(channels) ~= "table" then
        return nil
    end

    for _, candidate in ipairs(channels) do
        local channelId = ResolveChannel(candidate)
        if channelId then
            return channelId
        end
    end

    local numericKeys = {}
    for key, enabled in pairs(channels) do
        if type(key) == "number" and enabled then
            numericKeys[#numericKeys + 1] = key
        end
    end
    table.sort(numericKeys)

    for _, candidate in ipairs(numericKeys) do
        local channelId = ResolveChannel(candidate)
        if channelId then
            return channelId
        end
    end

    return nil
end

local function GetFirstChannel(frame, frameId)
    local channelId = GetFirstChannelFromTable(frame.channelList)
        or GetFirstChannelFromTable(frame.zoneChannelList)
        or ResolveChannel(frame.channelName)
    if channelId then
        return channelId
    end

    if frameId and type(GetChatWindowChannels) == "function" then
        return GetFirstChannelFromValues(GetChatWindowChannels(frameId))
    end

    return nil
end

local function NormalizeMessageType(messageType)
    if type(messageType) ~= "string" then
        return nil
    end
    return sendableChatTypes[messageType]
end

local function GetWhisperTarget(frame)
    local chatType = whisperChatTypes[frame.chatType]
    if not chatType then
        return nil
    end

    local tellTarget = frame.chatTarget
    if tellTarget == nil or tellTarget == "" then
        if frame.editBox and type(frame.editBox.GetTellTarget) == "function" then
            tellTarget = frame.editBox:GetTellTarget()
        elseif frame.editBox and type(frame.editBox.GetAttribute) == "function" then
            tellTarget = frame.editBox:GetAttribute("tellTarget")
        end
    end
    if (tellTarget == nil or tellTarget == "") and chatType == "WHISPER" then
        tellTarget = frame.name
    end
    if tellTarget == nil or tellTarget == "" then
        return nil
    end

    return {
        chatType = chatType,
        tellTarget = tellTarget
    }
end

local function AddAvailableMessageTypes(availableTypes, messageTypes)
    for _, messageType in ipairs(messageTypes) do
        local normalizedType = NormalizeMessageType(messageType) or whisperChatTypes[messageType]
        if normalizedType then
            availableTypes[normalizedType] = true
        end
    end

    for messageType, enabled in pairs(messageTypes) do
        if type(messageType) == "string" and enabled then
            local normalizedType = NormalizeMessageType(messageType) or whisperChatTypes[messageType]
            if normalizedType then
                availableTypes[normalizedType] = true
            end
        end
    end
end

local function GetAvailableMessageTypes(frame, frameId)
    local availableTypes = {}
    if type(frame.messageTypeList) == "table" then
        AddAvailableMessageTypes(availableTypes, frame.messageTypeList)
    end
    if frameId and type(GetChatWindowMessages) == "function" then
        AddAvailableMessageTypes(availableTypes, { GetChatWindowMessages(frameId) })
    end
    return availableTypes
end

local function GetFirstMessageType(availableTypes)
    for _, messageType in ipairs(fallbackMessageTypeOrder) do
        if availableTypes[messageType] then
            return messageType
        end
    end

    return nil
end

function addon.GetDefaultTarget(frame)
    if not frame then
        return nil
    end

    local whisperTarget = GetWhisperTarget(frame)
    if whisperTarget then
        return whisperTarget
    end

    local frameId = type(frame.GetID) == "function" and frame:GetID() or nil
    local availableMessageTypes = GetAvailableMessageTypes(frame, frameId)
    if latestIncomingWhisper and availableMessageTypes[latestIncomingWhisper.chatType] then
        return {
            chatType = latestIncomingWhisper.chatType,
            tellTarget = latestIncomingWhisper.tellTarget
        }
    end

    local channelId = GetFirstChannel(frame, frameId)
    if channelId then
        return {
            chatType = "CHANNEL",
            channelId = channelId
        }
    end

    local chatType = GetFirstMessageType(availableMessageTypes)
    if chatType then
        return {
            chatType = chatType
        }
    end

    return nil
end

local function OpenChat(text, frame)
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        return ChatFrameUtil.OpenChat(text, frame)
    end
    if type(ChatFrame_OpenChat) == "function" then
        return ChatFrame_OpenChat(text, frame)
    end
    return nil
end

local function ApplyTarget(editBox, target)
    if not editBox
        or type(editBox.SetChatType) ~= "function"
        or type(editBox.UpdateHeader) ~= "function"
    then
        return false
    end

    if target.chatType == "CHANNEL" then
        if type(editBox.SetChannelTarget) ~= "function" then
            return false
        end
        editBox:SetChannelTarget(target.channelId)
    elseif whisperChatTypes[target.chatType] then
        if type(editBox.SetTellTarget) ~= "function" then
            return false
        end
        editBox:SetTellTarget(target.tellTarget)
    end

    editBox:SetChatType(target.chatType)
    editBox:UpdateHeader()
    return true
end

function addon.ApplyActiveTabContext()
    local frame = addon.GetActiveChatFrame()
    local target = addon.GetDefaultTarget(frame)
    if not target then
        return false
    end

    applyingContext = true
    local opened, editBox = pcall(OpenChat, "", frame)
    applyingContext = false
    if not opened then
        error(editBox, 0)
    end
    editBox = editBox or GetActiveEditBox()

    return ApplyTarget(editBox, target)
end

local function OnOpenChat(text)
    if applyingContext or (text ~= nil and text ~= "") then
        return
    end
    addon.ApplyActiveTabContext()
end

local function InstallHook()
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        hooksecurefunc(ChatFrameUtil, "OpenChat", OnOpenChat)
        return true
    end
    if type(ChatFrame_OpenChat) == "function" then
        hooksecurefunc("ChatFrame_OpenChat", OnOpenChat)
        return true
    end
    return false
end

local whisperTracker = CreateFrame("Frame")
for eventName in pairs(incomingWhisperEvents) do
    whisperTracker:RegisterEvent(eventName)
end
whisperTracker:SetScript("OnEvent", function(_, eventName, ...)
    local whisperEvent = incomingWhisperEvents[eventName]
    local tellTarget = whisperEvent and select(whisperEvent.targetIndex, ...)
    if tellTarget ~= nil and tellTarget ~= "" then
        latestIncomingWhisper = {
            chatType = whisperEvent.chatType,
            tellTarget = tellTarget
        }
    end
end)

if not InstallHook() then
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self)
        if InstallHook() then
            self:UnregisterAllEvents()
        end
    end)
end
