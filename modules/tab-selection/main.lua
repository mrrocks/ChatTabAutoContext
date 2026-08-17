local _, addon = ...

local issecretvalue = _G.issecretvalue

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

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
        local isLeader = UnitIsGroupLeader("player")
        if IsSecret(isLeader) then
            return false
        end
        if isLeader then
            return true
        end

        local isAssistant = UnitIsGroupAssistant("player")
        return not IsSecret(isAssistant) and isAssistant
    end
}

local sessionOverrides = {}

local chatInputRestrictionTypes = {}
if Enum and Enum.AddOnRestrictionType then
    local restrictionTypeNames = {
        "Encounter",
        "ChallengeMode",
        "PvPMatch",
        "Chat"
    }
    for _, name in ipairs(restrictionTypeNames) do
        local restrictionType = Enum.AddOnRestrictionType[name]
        if restrictionType ~= nil then
            chatInputRestrictionTypes[#chatInputRestrictionTypes + 1] = restrictionType
        end
    end
end

local function HasValue(value)
    return value ~= nil and value ~= ""
end

local function IsChatInputRestricted()
    if not C_RestrictedActions
        or type(C_RestrictedActions.GetAddOnRestrictionState) ~= "function"
        or not Enum
        or not Enum.AddOnRestrictionState
    then
        return false
    end

    local inactiveState = Enum.AddOnRestrictionState.Inactive
    if inactiveState == nil then
        return false
    end

    for _, restrictionType in ipairs(chatInputRestrictionTypes) do
        local state = C_RestrictedActions.GetAddOnRestrictionState(restrictionType)
        if IsSecret(state) or state ~= inactiveState then
            return true
        end
    end

    return false
end

local function NormalizeTargetName(value)
    if IsSecret(value) or not HasValue(value) then
        return nil
    end

    return tostring(value):lower():gsub("[%s%p]", "")
end

local function NormalizeChannelName(value)
    if IsSecret(value) or not HasValue(value) then
        return nil
    end

    local name = tostring(value)
        :gsub("^%s*%d+%s*[%.:%-]?%s*", "")
        :gsub("%s+%-%s+.*$", "")
    return NormalizeTargetName(name)
end

local function IsChatTypeSendable(chatType)
    local canSend = chatTypeSendRequirements[chatType]
    if not canSend then
        return true
    end

    local canSendResult = canSend()
    return not IsSecret(canSendResult) and canSendResult == true
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

local function ResolveChannelInfo(candidate)
    if IsSecret(candidate) or candidate == nil or type(GetChannelName) ~= "function" then
        return nil
    end

    local channelId, channelName = GetChannelName(candidate)
    if IsSecret(channelId) or IsSecret(channelName) then
        return nil
    end
    if channelId and channelId > 0 and HasValue(channelName) then
        return channelId, channelName
    end
    return nil
end

local function ResolveChannel(candidate)
    return ResolveChannelInfo(candidate)
end

local function GetMatchingChannelFromNames(channelNames, normalizedWindowName)
    if type(channelNames) ~= "table" or not normalizedWindowName then
        return nil
    end

    for _, key in ipairs(GetSortedNumericKeys(channelNames)) do
        local candidate = channelNames[key]
        local channelId, channelName = ResolveChannelInfo(candidate)
        if channelId
            and (NormalizeChannelName(candidate) == normalizedWindowName
                or NormalizeChannelName(channelName) == normalizedWindowName)
        then
            return channelId
        end
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

local function GetMatchingChannel(frame, frameId, windowName)
    local normalizedWindowName = NormalizeTargetName(windowName)
    local channelId = GetMatchingChannelFromNames(frame.channelList, normalizedWindowName)
    if channelId then
        return channelId
    end

    if not frameId or type(GetChatWindowChannels) ~= "function" then
        return nil
    end

    local configuredChannels = { GetChatWindowChannels(frameId) }
    for index = 1, #configuredChannels, 2 do
        local candidate = configuredChannels[index]
        local channelName
        channelId, channelName = ResolveChannelInfo(candidate)
        if channelId
            and (NormalizeChannelName(candidate) == normalizedWindowName
                or NormalizeChannelName(channelName) == normalizedWindowName)
        then
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
    if IsSecret(messageType) or type(messageType) ~= "string" then
        return nil
    end
    return sendableChatTypes[messageType] or whisperChatTypes[messageType]
end

local function IsStickyNonWhisperChatType(chatType)
    if whisperChatTypes[chatType] then
        return false
    end

    local chatTypeInfo = ChatTypeInfo and ChatTypeInfo[chatType]
    return chatTypeInfo and chatTypeInfo.sticky == 1
end

local function GetTargetChannelId(target)
    if not target or target.chatType ~= "CHANNEL" then
        return nil
    end

    return ResolveChannel(target.channelName or target.channelId)
end

local function TargetsMatch(firstTarget, secondTarget)
    if not firstTarget or not secondTarget or firstTarget.chatType ~= secondTarget.chatType then
        return false
    end

    if whisperChatTypes[firstTarget.chatType] then
        local firstName = NormalizeTargetName(firstTarget.tellTarget)
        local secondName = NormalizeTargetName(secondTarget.tellTarget)
        return firstName ~= nil and firstName == secondName
    end

    if firstTarget.chatType ~= "CHANNEL" then
        return true
    end

    local firstChannelId = GetTargetChannelId(firstTarget)
    local secondChannelId = GetTargetChannelId(secondTarget)
    return firstChannelId ~= nil and firstChannelId == secondChannelId
end

local function GetEditBoxTarget(editBox)
    if not editBox or type(editBox.GetChatType) ~= "function" then
        return nil
    end

    local chatType = editBox:GetChatType()
    if IsSecret(chatType) then
        return nil
    end
    if whisperChatTypes[chatType] then
        if type(editBox.GetTellTarget) ~= "function" then
            return nil
        end

        local tellTarget = editBox:GetTellTarget()
        if IsSecret(tellTarget) or not HasValue(tellTarget) then
            return nil
        end

        return {
            chatType = chatType,
            tellTarget = tellTarget
        }
    end
    if chatType ~= "CHANNEL" then
        return HasValue(chatType) and { chatType = chatType } or nil
    end

    if type(editBox.GetChannelTarget) ~= "function" or type(GetChannelName) ~= "function" then
        return nil
    end

    local channelTarget = editBox:GetChannelTarget()
    if IsSecret(channelTarget) then
        return nil
    end

    local channelId, channelName = GetChannelName(channelTarget)
    if IsSecret(channelId) or IsSecret(channelName) then
        return nil
    end
    if not channelId or channelId <= 0 or not HasValue(channelName) then
        return nil
    end

    return {
        chatType = "CHANNEL",
        channelName = channelName
    }
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

local function GetMatchingMessageType(availableTypes, windowName)
    local normalizedWindowName = NormalizeTargetName(windowName)
    if not normalizedWindowName then
        return nil
    end

    for _, messageType in ipairs(fallbackMessageTypeOrder) do
        local localizedName = _G[messageType]
        if availableTypes[messageType]
            and IsChatTypeSendable(messageType)
            and (NormalizeTargetName(localizedName) == normalizedWindowName
                or NormalizeTargetName(messageType) == normalizedWindowName)
        then
            return messageType
        end
    end

    return nil
end

local function GetFrameWindowName(frameId)
    if not frameId or type(GetChatWindowInfo) ~= "function" then
        return nil
    end

    local windowName = GetChatWindowInfo(frameId)
    return not IsSecret(windowName) and HasValue(windowName) and windowName or nil
end

local function GetWhisperTarget(frame, chatType)
    local tellTarget = frame.chatTarget
    if IsSecret(tellTarget) then
        return nil
    end
    if not HasValue(tellTarget) and frame.editBox and type(frame.editBox.GetTellTarget) == "function" then
        tellTarget = frame.editBox:GetTellTarget()
    end
    if IsSecret(tellTarget) then
        return nil
    end
    if not HasValue(tellTarget) then
        tellTarget = frame.name
    end
    if IsSecret(tellTarget) or not HasValue(tellTarget) then
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

    local succeeded, tellTarget, messageType = pcall(ChatFrameUtil.GetLastTellTarget)
    if not succeeded or IsSecret(tellTarget) or IsSecret(messageType) or not HasValue(tellTarget) then
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

    local frameChatType = frame.chatType
    if IsSecret(frameChatType) then
        return nil
    end

    local whisperChatType = whisperChatTypes[frameChatType]
    if whisperChatType then
        return GetWhisperTarget(frame, whisperChatType)
    end

    local frameId = type(frame.GetID) == "function" and frame:GetID() or nil
    local windowName = GetFrameWindowName(frameId)
    local availableMessageTypes = GetAvailableMessageTypes(frame, frameId)

    local chatType = GetMatchingMessageType(availableMessageTypes, windowName)
    if chatType then
        return {
            chatType = chatType
        }
    end

    local channelId = GetMatchingChannel(frame, frameId, windowName)
        or GetFirstChannel(frame, frameId)
    if channelId then
        return {
            chatType = "CHANNEL",
            channelId = channelId
        }
    end

    chatType = GetFirstMessageType(availableMessageTypes)
    if chatType then
        return {
            chatType = chatType
        }
    end

    return GetLatestWhisperTarget(availableMessageTypes)
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

local function GetSessionOverrideTarget(frame)
    local override = sessionOverrides[frame]
    if not override then
        return nil
    end

    if override.chatType ~= "CHANNEL" then
        return override
    end

    local channelId = ResolveChannel(override.channelName)
    if not channelId then
        sessionOverrides[frame] = nil
        return nil
    end

    return {
        chatType = "CHANNEL",
        channelId = channelId
    }
end

local function RememberSelectedTarget(frame, selectedTarget)
    if not frame
        or not selectedTarget
        or not (IsStickyNonWhisperChatType(selectedTarget.chatType) or whisperChatTypes[selectedTarget.chatType])
    then
        return
    end

    if not whisperChatTypes[selectedTarget.chatType] or whisperChatTypes[frame.chatType] then
        local defaultTarget = addon.GetDefaultTarget(frame)
        if defaultTarget and TargetsMatch(selectedTarget, defaultTarget) then
            sessionOverrides[frame] = nil
            return
        end
    end

    if not TargetsMatch(selectedTarget, GetSessionOverrideTarget(frame)) then
        sessionOverrides[frame] = selectedTarget
    end
end

local function HasWhisperTellTarget(editBox)
    if not editBox or type(editBox.GetChatType) ~= "function" or type(editBox.GetStickyType) ~= "function" then
        return false
    end

    local chatType = editBox:GetChatType()
    if IsSecret(chatType) then
        return true
    end

    local stickyType = editBox:GetStickyType()
    if IsSecret(stickyType) then
        return true
    end
    if not whisperChatTypes[chatType] or chatType == stickyType then
        return false
    end

    if type(editBox.GetTellTarget) ~= "function" then
        return false
    end

    local tellTarget = editBox:GetTellTarget()
    return IsSecret(tellTarget) or HasValue(tellTarget)
end

local function HasExplicitWhisperTarget(editBox)
    if not HasWhisperTellTarget(editBox) then
        return false
    end

    local selectedTarget = GetEditBoxTarget(editBox)
    if not selectedTarget then
        return true
    end

    local frame = addon.GetActiveChatFrame() or GetFrameForEditBox(editBox)
    return not TargetsMatch(GetSessionOverrideTarget(frame), selectedTarget)
end

local function GetFrameTarget(frame)
    return GetSessionOverrideTarget(frame) or addon.GetDefaultTarget(frame)
end

local function ApplyFrameTarget(frame, editBox)
    local target = GetFrameTarget(frame)
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
    if not editBox or HasWhisperTellTarget(editBox) then
        return false
    end

    return ApplyFrameTarget(frame, editBox)
end

function addon.GetChatTab(frame)
    if type(frame.GetName) ~= "function" then
        return nil
    end

    local frameName = frame:GetName()
    if not frameName then
        return nil
    end
    return _G[frameName .. "Tab"]
end

local GetChatTab = addon.GetChatTab

function addon.GetDockedChatFrames()
    if not GENERAL_CHAT_DOCK or type(FCFDock_GetChatFrames) ~= "function" then
        return nil
    end

    local dockedFrames = FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)
    if type(dockedFrames) ~= "table" then
        return nil
    end

    return dockedFrames
end

local function GetCyclableChatFrames()
    local frames = {}
    local targets = {}
    local dockedFrames = addon.GetDockedChatFrames()
    if not dockedFrames then
        return frames, targets
    end

    for _, frame in ipairs(dockedFrames) do
        local target = frame
            and frame.editBox
            and GetChatTab(frame)
            and GetFrameTarget(frame)
        if target then
            frames[#frames + 1] = frame
            targets[#targets + 1] = target
        end
    end

    return frames, targets
end

local function SelectChatTab(frame)
    local tab = GetChatTab(frame)
    if not tab or type(FCF_Tab_OnClick) ~= "function" then
        return false
    end

    FCF_Tab_OnClick(tab)
    if GENERAL_CHAT_DOCK
        and type(FCFDock_GetSelectedWindow) == "function"
        and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) ~= frame
    then
        return false
    end

    addon.QueueEllesmereUIChatSync()
    return true
end

function addon.CycleChatTab(editBox, step)
    if IsChatInputRestricted() then
        return false
    end

    local frames, targets = GetCyclableChatFrames()
    if #frames < 2 then
        return false
    end

    local pendingText = type(editBox.GetText) == "function" and editBox:GetText() or nil
    if IsSecret(pendingText) then
        return false
    end

    local pendingCursorPosition = type(editBox.GetCursorPosition) == "function"
        and editBox:GetCursorPosition()
        or nil
    if IsSecret(pendingCursorPosition) then
        pendingCursorPosition = nil
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

    local frameEditBox = ChatFrameUtil.OpenChat(pendingText, nextFrame, pendingCursorPosition)
    ApplyTarget(frameEditBox, targets[nextIndex])
    return true
end

local function IsWritingCommand(editBox)
    if type(editBox.GetText) ~= "function" then
        return false
    end

    local text = editBox:GetText()
    if IsSecret(text) then
        return true
    end
    return type(text) == "string" and text:sub(1, 1) == "/"
end

local function OnOpenChat(text, chatFrame)
    if IsSecret(text) or HasValue(text) then
        return
    end
    if chatFrame == nil and CHAT_FOCUS_OVERRIDE then
        return
    end

    local editBox = GetEditBoxForSend(chatFrame)
    if editBox and editBox.setText == 1 then
        local pending = editBox.text
        if IsSecret(pending) or HasValue(pending) then
            return
        end
    end

    addon.ApplyActiveTabContext(chatFrame)
end

local function OnEditBoxPreSendText(_, editBox)
    if not editBox or type(editBox.GetText) ~= "function" then
        return
    end

    local text = editBox:GetText()
    if IsSecret(text) or not HasValue(text) then
        return
    end

    local frame = addon.GetActiveChatFrame() or GetFrameForEditBox(editBox)
    if not frame then
        return
    end

    RememberSelectedTarget(frame, GetEditBoxTarget(editBox))
end

local function RememberWhisperFromTell(chatType, tellTarget, chatFrame)
    if IsSecret(tellTarget) or not HasValue(tellTarget) then
        return
    end

    local editBox = GetEditBoxForSend(chatFrame)
    RememberSelectedTarget(addon.GetActiveChatFrame() or GetFrameForEditBox(editBox), {
        chatType = chatType,
        tellTarget = tellTarget
    })
end

local previousCustomTabPressed

local function IsWhisperFrame(frame)
    return frame ~= nil and (IsSecret(frame.chatType) or whisperChatTypes[frame.chatType] ~= nil)
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
local preSendHooked = false

local function InstallHooks()
    if not openChatHooked and ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        hooksecurefunc(ChatFrameUtil, "OpenChat", OnOpenChat)
        if type(ChatFrameUtil.SendTellWithMessage) == "function" then
            hooksecurefunc(ChatFrameUtil, "SendTellWithMessage", function(name, _, chatFrame)
                RememberWhisperFromTell("WHISPER", name, chatFrame)
            end)
        end
        if type(ChatFrameUtil.SendBNetTell) == "function" then
            hooksecurefunc(ChatFrameUtil, "SendBNetTell", function(tokenizedName)
                RememberWhisperFromTell("BN_WHISPER", tokenizedName)
            end)
        end
        openChatHooked = true
    end

    if not customTabPressedInstalled and type(ChatEdit_CustomTabPressed) == "function" then
        previousCustomTabPressed = ChatEdit_CustomTabPressed
        ChatEdit_CustomTabPressed = OnCustomTabPressed
        customTabPressedInstalled = true
    end

    if not preSendHooked and EventRegistry and type(EventRegistry.RegisterCallback) == "function" then
        EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", OnEditBoxPreSendText, addon)
        preSendHooked = true
    end

    return openChatHooked and customTabPressedInstalled and preSendHooked
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
