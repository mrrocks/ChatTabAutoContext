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

local chatTypeSendRequirements = {
    GUILD = function()
        return IsInGuild()
    end,
    OFFICER = function()
        return IsInGuild()
    end,
    RAID_WARNING = function()
        return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
    end
}

local function HasValue(value)
    return value ~= nil and value ~= ""
end

local function IsChatTypeSendable(chatType)
    local canSend = chatTypeSendRequirements[chatType]
    return not canSend or canSend()
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
        if availableTypes[messageType] and IsChatTypeSendable(messageType) then
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

local function ApplyFrameTarget(frame, editBox)
    local target = addon.GetDefaultTarget(frame)
    if not target then
        return false
    end

    return ApplyTarget(editBox, target)
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

    return ApplyFrameTarget(frame, editBox)
end

local function GetChatTab(frame)
    if type(frame.GetName) ~= "function" then
        return nil
    end

    local frameName = frame:GetName()
    if not frameName then
        return nil
    end
    return _G[frameName .. "Tab"]
end

local function IsCyclableChatFrame(frame)
    if not frame or not frame.editBox then
        return false
    end

    local tab = GetChatTab(frame)
    if not tab or type(tab.IsShown) ~= "function" or not tab:IsShown() then
        return false
    end

    return addon.GetDefaultTarget(frame) ~= nil
end

local function GetCyclableChatFrames()
    local frames = {}
    if not GENERAL_CHAT_DOCK or type(FCFDock_GetChatFrames) ~= "function" then
        return frames
    end

    local dockedFrames = FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)
    if type(dockedFrames) ~= "table" then
        return frames
    end

    for _, frame in ipairs(dockedFrames) do
        if IsCyclableChatFrame(frame) then
            frames[#frames + 1] = frame
        end
    end

    return frames
end

local function SelectChatTab(frame)
    local tab = GetChatTab(frame)
    if not tab or type(FCF_Tab_OnClick) ~= "function" then
        return false
    end

    FCF_Tab_OnClick(tab)
    return true
end

local function FocusFrameInput(editBox, frame)
    local frameEditBox = GetEditBoxForSend(frame)
    if not frameEditBox or frameEditBox == editBox then
        return editBox
    end

    local pendingText = type(editBox.GetText) == "function" and editBox:GetText() or nil
    if ChatFrameUtil and type(ChatFrameUtil.ActivateChat) == "function" then
        ChatFrameUtil.ActivateChat(frameEditBox)
    end
    if HasValue(pendingText) and type(frameEditBox.SetText) == "function" then
        frameEditBox:SetText(pendingText)
    end

    return frameEditBox
end

function addon.CycleChatTab(editBox, step)
    local frames = GetCyclableChatFrames()
    if #frames < 2 then
        return false
    end

    local currentFrame = addon.GetActiveChatFrame()
    local currentIndex
    for index, frame in ipairs(frames) do
        if frame == currentFrame then
            currentIndex = index
            break
        end
    end

    local nextIndex
    if currentIndex then
        nextIndex = (currentIndex - 1 + step) % #frames + 1
    else
        nextIndex = step > 0 and 1 or #frames
    end

    local nextFrame = frames[nextIndex]
    if nextFrame == currentFrame or not SelectChatTab(nextFrame) then
        return false
    end

    ApplyFrameTarget(nextFrame, FocusFrameInput(editBox, nextFrame))
    return true
end

local function IsWritingCommand(editBox)
    if type(editBox.GetText) ~= "function" then
        return false
    end

    local text = editBox:GetText()
    return type(text) == "string" and text:sub(1, 1) == "/"
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

local previousCustomTabPressed

local function IsWhisperFrame(frame)
    return frame ~= nil and whisperChatTypes[frame.chatType] ~= nil
end

local function OnCustomTabPressed(editBox)
    if previousCustomTabPressed and previousCustomTabPressed(editBox) then
        return true
    end

    if not editBox or IsWritingCommand(editBox) then
        return false
    end

    if HasExplicitWhisperTarget(editBox) and not IsWhisperFrame(addon.GetActiveChatFrame()) then
        return false
    end

    return addon.CycleChatTab(editBox, IsShiftKeyDown() and -1 or 1)
end

local openChatHooked = false
local customTabPressedInstalled = false

local function InstallHooks()
    if not openChatHooked and ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        hooksecurefunc(ChatFrameUtil, "OpenChat", OnOpenChat)
        openChatHooked = true
    end

    if not customTabPressedInstalled and type(ChatEdit_CustomTabPressed) == "function" then
        previousCustomTabPressed = ChatEdit_CustomTabPressed
        ChatEdit_CustomTabPressed = OnCustomTabPressed
        customTabPressedInstalled = true
    end

    return openChatHooked and customTabPressedInstalled
end

if not InstallHooks() then
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self)
        if InstallHooks() then
            self:UnregisterAllEvents()
        end
    end)
end
