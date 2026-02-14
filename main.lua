local existingFrame = _G.ChatContext
local eventFrame
if existingFrame and existingFrame.GetObjectType and existingFrame:GetObjectType() == "Frame" then
    eventFrame = existingFrame
else
    eventFrame = CreateFrame("Frame", "ChatContext", UIParent)
end

local whisperTypes = {
    BN_WHISPER = true,
    BN_WHISPER_INFORM = true,
    WHISPER = true,
    WHISPER_INFORM = true
}

local whisperEvents = {
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true
}

local whisperEventToType = {
    CHAT_MSG_BN_WHISPER = "BN_WHISPER",
    CHAT_MSG_BN_WHISPER_INFORM = "BN_WHISPER",
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_WHISPER_INFORM = "WHISPER"
}

local whisperUpdateDelaySeconds = 0.1
local frameWhisperState = setmetatable({}, { __mode = "k" })
local lastWhisperTargetByType = {}
local lastUsedChannelByFrame = setmetatable({}, { __mode = "k" })
local lastUsedChannelTarget
local lastSelectedChatFrame
local frameWindowTypeToChatType = {
    battleground = "BATTLEGROUND",
    guild = "GUILD",
    instance = "INSTANCE_CHAT",
    officer = "OFFICER",
    party = "PARTY",
    raid = "RAID",
    raidwarning = "RAID_WARNING",
    say = "SAY",
    yell = "YELL"
}

local function NormalizeWhisperType(chatType)
    if chatType == "BN_WHISPER" or chatType == "BN_WHISPER_INFORM" then
        return "BN_WHISPER"
    end
    if chatType == "WHISPER" or chatType == "WHISPER_INFORM" then
        return "WHISPER"
    end
    return nil
end

local function IsWhisperType(chatType)
    return NormalizeWhisperType(chatType) ~= nil and whisperTypes[chatType] == true
end

local function GetSelectedChatFrame()
    if lastSelectedChatFrame and lastSelectedChatFrame.editBox and lastSelectedChatFrame:IsShown() then
        return lastSelectedChatFrame
    end
    if type(FCFDock_GetSelectedWindow) == "function" and GENERAL_CHAT_DOCK then
        local dockWindow = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
        if dockWindow and dockWindow.editBox then
            lastSelectedChatFrame = dockWindow
            return dockWindow
        end
    end
    if SELECTED_DOCK_FRAME and SELECTED_DOCK_FRAME.editBox then
        lastSelectedChatFrame = SELECTED_DOCK_FRAME
        return SELECTED_DOCK_FRAME
    end
    if type(ChatEdit_GetLastActiveWindow) == "function" then
        local activeEditBox = ChatEdit_GetLastActiveWindow()
        local activeFrame = activeEditBox and activeEditBox:GetParent()
        if activeFrame and activeFrame.editBox then
            lastSelectedChatFrame = activeFrame
            return activeFrame
        end
    end
    return nil
end

local function OpenChat(text, frame)
    if type(ChatFrame_OpenChat) == "function" then
        ChatFrame_OpenChat(text, frame)
        return true
    end
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        ChatFrameUtil.OpenChat(text, frame)
        return true
    end
    return false
end

local function UpdateEditBoxHeader(editBox)
    if not editBox then
        return
    end
    if type(ChatEdit_UpdateHeader) == "function" then
        ChatEdit_UpdateHeader(editBox)
        return
    end
    if ChatFrameEditBoxMixin and type(ChatFrameEditBoxMixin.UpdateHeader) == "function" then
        ChatFrameEditBoxMixin.UpdateHeader(editBox)
    end
end

local function UpdateWhisperState(frame, chatType, target)
    local whisperType = NormalizeWhisperType(chatType)
    if not whisperType then
        return
    end

    local resolvedTarget = target
    if (not resolvedTarget or resolvedTarget == "") and frame and frame.chatTarget and frame.chatTarget ~= "" then
        resolvedTarget = frame.chatTarget
    end

    if not resolvedTarget or resolvedTarget == "" then
        return
    end

    if frame then
        frameWhisperState[frame] = {
            chatType = whisperType,
            target = resolvedTarget
        }
    end

    lastWhisperTargetByType[whisperType] = resolvedTarget
end

local function GetLastTellTargetForType(whisperType)
    if type(ChatEdit_GetLastTellTarget) ~= "function" then
        return nil
    end

    local target, chatType = ChatEdit_GetLastTellTarget()
    if not target then
        return nil
    end

    if NormalizeWhisperType(chatType) ~= whisperType then
        return nil
    end

    return target
end

local function ResolveWhisperContext(frame)
    local selectedFrame = frame or GetSelectedChatFrame()
    if not selectedFrame or not selectedFrame.editBox then
        return nil
    end

    local whisperType = NormalizeWhisperType(selectedFrame.chatType)
    if not whisperType then
        return nil
    end

    local editBox = selectedFrame.editBox
    local target = selectedFrame.chatTarget

    if not target or target == "" then
        local frameState = frameWhisperState[selectedFrame]
        if frameState and frameState.chatType == whisperType then
            target = frameState.target
        end
    end

    if not target or target == "" then
        local editTarget = editBox:GetAttribute("tellTarget")
        if editTarget and editTarget ~= "" then
            target = editTarget
        end
    end

    if (not target or target == "") and whisperType == "WHISPER" then
        local frameName = selectedFrame.name
        if frameName and frameName ~= "" then
            target = frameName
        end
    end

    if not target or target == "" then
        target = lastWhisperTargetByType[whisperType]
    end

    if not target or target == "" then
        target = GetLastTellTargetForType(whisperType)
    end

    return selectedFrame, editBox, whisperType, target
end

local function GetFrameWindowName(frame)
    if not frame then
        return nil
    end

    local frameId = frame.GetID and frame:GetID()
    if frameId and frameId > 0 then
        return GetChatWindowInfo(frameId)
    end

    return nil
end

local function TableHasValues(values)
    if not values then
        return false
    end
    for key, value in pairs(values) do
        if (type(value) == "string" and value ~= "") or
            (type(value) == "number" and value > 0) or
            (type(key) == "string" and key ~= "" and value) then
            return true
        end
    end
    return false
end

local function VisitTableEntries(values, callback)
    if not values then
        return
    end

    local seenEntries = {}
    local function emit(entry)
        if entry == nil or entry == "" then
            return
        end
        local lookupKey = tostring(entry)
        if seenEntries[lookupKey] then
            return
        end
        seenEntries[lookupKey] = true
        callback(entry)
    end

    for key, value in pairs(values) do
        if type(value) == "string" or type(value) == "number" then
            emit(value)
        end
        if type(key) == "string" and value then
            emit(key)
        end
    end
end

local function ResolveChannelTarget(channelName)
    if not channelName or channelName == "" then
        return nil
    end

    if type(channelName) == "number" and channelName > 0 then
        return channelName
    end

    local numericTarget = tonumber(channelName)
    if numericTarget and numericTarget > 0 then
        return numericTarget
    end

    local prefixedNumericTarget = tonumber(tostring(channelName):match("^(%d+)%s*[%.:%-]"))
    if prefixedNumericTarget and prefixedNumericTarget > 0 then
        return prefixedNumericTarget
    end

    local channelId = GetChannelName(channelName)
    if channelId and channelId > 0 then
        return channelId
    end

    return nil
end

local function NormalizeMessageType(messageType)
    if type(messageType) ~= "string" or messageType == "" then
        return nil
    end

    local resolvedType = messageType
    if strsub(resolvedType, 1, 9) == "CHAT_MSG_" then
        resolvedType = strsub(resolvedType, 10)
    end
    if type(Chat_GetChatCategory) == "function" then
        resolvedType = Chat_GetChatCategory(resolvedType)
    end
    if resolvedType == "PARTY_LEADER" then
        resolvedType = "PARTY"
    elseif resolvedType == "INSTANCE_CHAT_LEADER" then
        resolvedType = "INSTANCE_CHAT"
    elseif resolvedType == "RAID_LEADER" or resolvedType == "RAID_WARNING" then
        resolvedType = "RAID"
    end
    return resolvedType
end

local function GetChannelTargets(channelList)
    local channelTargets = {}
    if not channelList then
        return channelTargets
    end

    local seenTargets = {}
    VisitTableEntries(channelList, function(value)
        local resolvedTarget = ResolveChannelTarget(value)
        if resolvedTarget and not seenTargets[resolvedTarget] then
            channelTargets[#channelTargets + 1] = resolvedTarget
            seenTargets[resolvedTarget] = true
        end
    end)
    return channelTargets
end

local function MergeChannelTargets(primaryTargets, secondaryTargets)
    local mergedTargets = {}
    local seenTargets = {}

    for _, target in ipairs(primaryTargets) do
        if not seenTargets[target] then
            seenTargets[target] = true
            mergedTargets[#mergedTargets + 1] = target
        end
    end
    for _, target in ipairs(secondaryTargets) do
        if not seenTargets[target] then
            seenTargets[target] = true
            mergedTargets[#mergedTargets + 1] = target
        end
    end
    return mergedTargets
end

local function CountChannelEntries(...)
    local lists = { ... }
    local seenEntries = {}
    local entryCount = 0

    for _, list in ipairs(lists) do
        VisitTableEntries(list, function(value)
            local entryKey = tostring(value)
            if not seenEntries[entryKey] then
                seenEntries[entryKey] = true
                entryCount = entryCount + 1
            end
        end)
    end
    return entryCount
end

local function GetPreferredChannelTarget(frame, channelTargets, allowRememberedOverride)
    if #channelTargets == 0 then
        return nil
    end

    local validTargets = {}
    for _, target in ipairs(channelTargets) do
        validTargets[target] = true
    end

    local frameChannelTarget = frame and lastUsedChannelByFrame[frame]
    local editBoxChannelTarget = frame and frame.editBox and frame.editBox:GetAttribute("channelTarget")
    local candidates = {
        frameChannelTarget,
        editBoxChannelTarget,
        lastUsedChannelTarget
    }

    for _, candidate in ipairs(candidates) do
        local resolvedCandidate = ResolveChannelTarget(candidate)
        if resolvedCandidate and validTargets[resolvedCandidate] then
            return resolvedCandidate
        end
    end

    if allowRememberedOverride then
        for _, candidate in ipairs(candidates) do
            local resolvedCandidate = ResolveChannelTarget(candidate)
            local localChannelId = resolvedCandidate and GetChannelName(resolvedCandidate) or 0
            if localChannelId and localChannelId > 0 then
                return localChannelId
            end
        end
    end

    if #channelTargets == 1 then
        return channelTargets[1]
    end

    return nil
end

local function GetMessageTypePresence(messageTypeList)
    local presentTypes = {}
    if not messageTypeList then
        return presentTypes
    end

    VisitTableEntries(messageTypeList, function(value)
        local normalizedType = NormalizeMessageType(value)
        if normalizedType and normalizedType ~= "" then
            presentTypes[normalizedType] = true
        end
    end)
    return presentTypes
end

local function GetFrameDefaultChatTarget(frame)
    if type(ChatFrame_GetDefaultChatTarget) == "function" then
        local chatType, channelTarget = ChatFrame_GetDefaultChatTarget(frame)
        if chatType then
            return chatType, channelTarget
        end
    end

    local frameId = frame and frame.GetID and frame:GetID()
    local channelList = frame and frame.channelList
    local zoneChannelList = frame and frame.zoneChannelList
    if not TableHasValues(channelList) and frameId and frameId > 0 and type(GetChatWindowChannels) == "function" then
        channelList = { GetChatWindowChannels(frameId) }
    end

    local messageTypeList = frame and frame.messageTypeList
    if not TableHasValues(messageTypeList) and frameId and frameId > 0 and type(GetChatWindowMessages) == "function" then
        messageTypeList = { GetChatWindowMessages(frameId) }
    end

    local presentTypes = GetMessageTypePresence(messageTypeList)
    local channelTargets = MergeChannelTargets(GetChannelTargets(channelList), GetChannelTargets(zoneChannelList))
    local configuredChannelCount = CountChannelEntries(channelList, zoneChannelList)
    if #channelTargets == 0 and presentTypes.CHANNEL and frameId and frameId > 0 and type(GetChatWindowChannels) == "function" then
        local apiChannels = { GetChatWindowChannels(frameId) }
        channelTargets = GetChannelTargets(apiChannels)
        configuredChannelCount = CountChannelEntries(apiChannels)
    end
    if #channelTargets == 0 and frame and frame.channelName then
        local resolvedChannelTarget = ResolveChannelTarget(frame.channelName)
        if resolvedChannelTarget then
            channelTargets = { resolvedChannelTarget }
        end
    end

    if #channelTargets > 0 and (presentTypes.CHANNEL or not next(presentTypes)) then
        local preferredChannelTarget = GetPreferredChannelTarget(frame, channelTargets, configuredChannelCount > 1)
        if preferredChannelTarget then
            return "CHANNEL", preferredChannelTarget
        end
        return "SAY", nil
    end
    if presentTypes.PARTY then
        return "PARTY", nil
    end
    if presentTypes.INSTANCE_CHAT then
        return "INSTANCE_CHAT", nil
    end
    if presentTypes.RAID then
        return "RAID", nil
    end
    if presentTypes.OFFICER then
        return "OFFICER", nil
    end
    if presentTypes.GUILD then
        return "GUILD", nil
    end
    if presentTypes.BATTLEGROUND then
        return "BATTLEGROUND", nil
    end
    if #channelTargets > 0 then
        local preferredChannelTarget = GetPreferredChannelTarget(frame, channelTargets, configuredChannelCount > 1)
        if preferredChannelTarget then
            return "CHANNEL", preferredChannelTarget
        end
        return "SAY", nil
    end
    if presentTypes.SAY then
        return "SAY", nil
    end

    local windowName = GetFrameWindowName(frame)
    local normalizedWindowName = windowName and strlower(windowName:gsub("%s+", ""))
    local mappedType = normalizedWindowName and frameWindowTypeToChatType[normalizedWindowName]
    if mappedType then
        return mappedType, nil
    end

    return nil, nil
end

local function ApplyDefaultFrameContext(selectedFrame)
    if not selectedFrame or not selectedFrame.editBox then
        return
    end

    local chatType, channelTarget = GetFrameDefaultChatTarget(selectedFrame)
    if not chatType then
        return
    end

    local editBox = selectedFrame.editBox
    editBox:SetAttribute("chatType", chatType)
    editBox:SetAttribute("stickyType", chatType)
    if chatType == "CHANNEL" then
        editBox:SetAttribute("channelTarget", channelTarget)
    end
    UpdateEditBoxHeader(editBox)
end

local function OpenFrameContext(selectedFrame)
    if not selectedFrame or not selectedFrame.editBox then
        return
    end

    lastSelectedChatFrame = selectedFrame
    ApplyDefaultFrameContext(selectedFrame)
    ChatEdit_ActivateChat(selectedFrame.editBox)
end

local function SetWhisperTarget(frame, activateChat)
    local selectedFrame, editBox, whisperType, target = ResolveWhisperContext(frame)
    if not selectedFrame or not editBox or not whisperType then
        return
    end

    if target and target ~= "" then
        editBox:SetAttribute("chatType", whisperType)
        editBox:SetAttribute("tellTarget", target)
        selectedFrame.chatTarget = target
        UpdateWhisperState(selectedFrame, whisperType, target)
        UpdateEditBoxHeader(editBox)
    end

    if activateChat then
        if not OpenChat("", selectedFrame) then
            ChatEdit_ActivateChat(editBox)
        end
    end
end

local function ScheduleWhisperTarget(frame, activateChat)
    C_Timer.After(whisperUpdateDelaySeconds, function()
        SetWhisperTarget(frame, activateChat)
    end)
end

local function GetChatFrameFromTab(chatFrame)
    if not chatFrame then
        return nil
    end

    if chatFrame.editBox then
        return chatFrame
    end

    if chatFrame.chatFrame and chatFrame.chatFrame.editBox then
        return chatFrame.chatFrame
    end

    local frameName = chatFrame:GetName()
    if not frameName then
        return nil
    end

    local chatFrameNum = frameName:match("ChatFrame(%d+)Tab")
    if not chatFrameNum then
        return nil
    end

    return _G["ChatFrame" .. chatFrameNum]
end

local function HookSecure(functionName, callback)
    if type(_G[functionName]) ~= "function" then
        return false
    end

    hooksecurefunc(functionName, callback)
    return true
end

local function TrackChannelSend(editBox)
    if not editBox then
        return
    end

    local chatType = editBox:GetAttribute("chatType")
    if chatType ~= "CHANNEL" then
        return
    end

    local channelTarget = editBox:GetAttribute("channelTarget")
    if type(ChatEdit_GetChannelTarget) == "function" then
        channelTarget = ChatEdit_GetChannelTarget(editBox)
    end
    local resolvedChannelTarget = ResolveChannelTarget(channelTarget)
    if not resolvedChannelTarget then
        return
    end

    lastUsedChannelTarget = resolvedChannelTarget
    local channelFrame = editBox:GetParent()
    if channelFrame and channelFrame.editBox then
        lastUsedChannelByFrame[channelFrame] = resolvedChannelTarget
    end
end

HookSecure("ChatEdit_SendText", function(editBox)
    TrackChannelSend(editBox)
end)

local function OnWindowTypeChanged(frame, chatType, chatTarget)
    if not IsWhisperType(chatType) then
        return
    end

    if frame and chatTarget and chatTarget ~= "" then
        frame.chatTarget = chatTarget
    end

    UpdateWhisperState(frame, chatType, chatTarget)
    ScheduleWhisperTarget(frame, false)
end

if not HookSecure("FCF_SetTemporaryWindowType", OnWindowTypeChanged) then
    HookSecure("FCF_SetWindowType", OnWindowTypeChanged)
end

for eventName in pairs(whisperEvents) do
    eventFrame:RegisterEvent(eventName)
end

local function TrackWhisperEvent(event, ...)
    local whisperType = whisperEventToType[event]
    if not whisperType then
        return
    end

    local target = select(2, ...)
    if not target or target == "" then
        return
    end

    lastWhisperTargetByType[whisperType] = target
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not whisperEvents[event] then
        return
    end

    TrackWhisperEvent(event, ...)
    ScheduleWhisperTarget(nil, false)
end)

HookSecure("FCF_Tab_OnClick", function(chatFrame)
    local actualChatFrame = GetChatFrameFromTab(chatFrame)
    if actualChatFrame then
        lastSelectedChatFrame = actualChatFrame
    end
    ScheduleWhisperTarget(actualChatFrame, false)
end)

local function OnKeyDown(_, key)
    if key ~= "ENTER" then
        eventFrame:SetPropagateKeyboardInput(true)
        return
    end

    local selectedFrame = GetSelectedChatFrame()
    if not selectedFrame or not selectedFrame.editBox then
        eventFrame:SetPropagateKeyboardInput(true)
        return
    end

    if selectedFrame.editBox:HasFocus() then
        eventFrame:SetPropagateKeyboardInput(true)
        return
    end

    eventFrame:SetPropagateKeyboardInput(false)
    lastSelectedChatFrame = selectedFrame
    if IsWhisperType(selectedFrame.chatType) then
        SetWhisperTarget(selectedFrame, true)
        return
    end

    OpenFrameContext(selectedFrame)
end

eventFrame:SetScript("OnKeyDown", OnKeyDown)
eventFrame:EnableKeyboard(true)
eventFrame:SetPropagateKeyboardInput(true)
