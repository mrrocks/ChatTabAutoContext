local _, addon = ...

local sendableChatTypes = {
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
    "SAY",
    "YELL",
    "EMOTE"
}

local whisperChatTypes = {
    BN_WHISPER = "BN_WHISPER",
    WHISPER = "WHISPER"
}

local chatTypeAvailability = {
    GUILD = function()
        return IsInGuild()
    end,
    INSTANCE_CHAT = function()
        return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    end,
    OFFICER = function()
        return IsInGuild()
    end,
    PARTY = function()
        return IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid(LE_PARTY_CATEGORY_HOME)
    end,
    RAID = function()
        return IsInRaid(LE_PARTY_CATEGORY_HOME)
    end,
    RAID_WARNING = function()
        return IsInRaid(LE_PARTY_CATEGORY_HOME)
            and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
    end
}

local function HasValue(value)
    return value ~= nil and value ~= ""
end

local function IsChatTypeUsable(chatType)
    local isAvailable = chatTypeAvailability[chatType]
    return not isAvailable or isAvailable()
end

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
        return ChatFrameUtil.GetActiveWindow()
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

    if ChatFrameUtil and type(ChatFrameUtil.GetLastActiveWindow) == "function" then
        local lastActiveFrame = GetFrameForEditBox(ChatFrameUtil.GetLastActiveWindow())
        if IsUsableChatFrame(lastActiveFrame) then
            return lastActiveFrame
        end
    end

    return nil
end

local function GetSortedNumericKeys(source)
    local keys = {}
    for key in pairs(source) do
        if type(key) == "number" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function ResolveChannel(candidate)
    if candidate == nil or type(GetChannelName) ~= "function" then
        return nil
    end

    local channelId, channelName = GetChannelName(candidate)
    if channelId and channelId > 0 and HasValue(channelName) then
        return channelId
    end
    return nil
end

local function GetFirstChannelFromNames(channelNames)
    if type(channelNames) ~= "table" then
        return nil
    end

    for _, key in ipairs(GetSortedNumericKeys(channelNames)) do
        local channelId = ResolveChannel(channelNames[key])
        if channelId then
            return channelId
        end
    end

    return nil
end

local function GetFirstChannel(frame, frameId)
    local channelId = GetFirstChannelFromNames(frame.channelList)
    if channelId then
        return channelId
    end

    if not frameId or type(GetChatWindowChannels) ~= "function" then
        return nil
    end

    local configuredChannels = { GetChatWindowChannels(frameId) }
    for index = 1, #configuredChannels, 2 do
        channelId = ResolveChannel(configuredChannels[index])
        if channelId then
            return channelId
        end
    end

    return nil
end

local function NormalizeMessageType(messageType)
    if type(messageType) ~= "string" then
        return nil
    end
    return sendableChatTypes[messageType] or whisperChatTypes[messageType]
end

local function AddAvailableMessageTypes(availableTypes, messageTypes)
    for _, key in ipairs(GetSortedNumericKeys(messageTypes)) do
        local chatType = NormalizeMessageType(messageTypes[key])
        if chatType then
            availableTypes[chatType] = true
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
        if availableTypes[messageType] and IsChatTypeUsable(messageType) then
            return messageType
        end
    end

    return nil
end

local function GetWhisperTarget(frame)
    local chatType = whisperChatTypes[frame.chatType]
    if not chatType then
        return nil
    end

    local tellTarget = frame.chatTarget
    if not HasValue(tellTarget) and frame.editBox and type(frame.editBox.GetTellTarget) == "function" then
        tellTarget = frame.editBox:GetTellTarget()
    end
    if not HasValue(tellTarget) then
        tellTarget = frame.name
    end
    if not HasValue(tellTarget) then
        return nil
    end

    return {
        chatType = chatType,
        tellTarget = tellTarget
    }
end

local function GetLatestWhisperTarget(availableTypes)
    if not ChatFrameUtil or type(ChatFrameUtil.GetLastTellTarget) ~= "function" then
        return nil
    end

    local tellTarget, messageType = ChatFrameUtil.GetLastTellTarget()
    if not HasValue(tellTarget) then
        return nil
    end

    local chatType = whisperChatTypes[messageType]
    if not chatType or not availableTypes[chatType] then
        return nil
    end

    return {
        chatType = chatType,
        tellTarget = tellTarget
    }
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

    local channelId = GetFirstChannel(frame, frameId)
    if channelId then
        return {
            chatType = "CHANNEL",
            channelId = channelId
        }
    end

    local availableMessageTypes = GetAvailableMessageTypes(frame, frameId)
    local chatType = GetFirstMessageType(availableMessageTypes)
    if chatType then
        return {
            chatType = chatType
        }
    end

    return GetLatestWhisperTarget(availableMessageTypes)
end

local function HasExplicitWhisperTarget(editBox)
    if type(editBox.GetChatType) ~= "function" or type(editBox.GetStickyType) ~= "function" then
        return false
    end

    local chatType = editBox:GetChatType()
    if not whisperChatTypes[chatType] or chatType == editBox:GetStickyType() then
        return false
    end

    return type(editBox.GetTellTarget) == "function" and HasValue(editBox:GetTellTarget())
end

local function GetEditBoxForSend(frame)
    if ChatFrameUtil and type(ChatFrameUtil.ChooseBoxForSend) == "function" then
        local editBox = ChatFrameUtil.ChooseBoxForSend(frame)
        if editBox then
            return editBox
        end
    end
    return GetActiveEditBox()
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

function addon.ApplyActiveTabContext(chatFrame)
    local frame = IsUsableChatFrame(chatFrame) and chatFrame or addon.GetActiveChatFrame()
    if not frame then
        return false
    end

    local editBox = GetEditBoxForSend(frame)
    if not editBox or HasExplicitWhisperTarget(editBox) then
        return false
    end

    local target = addon.GetDefaultTarget(frame)
    if not target then
        return false
    end

    return ApplyTarget(editBox, target)
end

local function OnOpenChat(text, chatFrame)
    if HasValue(text) then
        return
    end
    if chatFrame == nil and CHAT_FOCUS_OVERRIDE then
        return
    end
    addon.ApplyActiveTabContext(chatFrame)
end

local function InstallHook()
    if not ChatFrameUtil or type(ChatFrameUtil.OpenChat) ~= "function" then
        return false
    end
    hooksecurefunc(ChatFrameUtil, "OpenChat", OnOpenChat)
    return true
end

if not InstallHook() then
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self)
        if InstallHook() then
            self:UnregisterAllEvents()
        end
    end)
end
