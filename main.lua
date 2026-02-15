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
local lastUsedChannelByFrameId = {}
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
    if type(FCFDock_GetSelectedWindow) == "function" and GENERAL_CHAT_DOCK then
        local dockWindow = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
        if dockWindow and dockWindow.editBox and dockWindow:IsShown() then
            lastSelectedChatFrame = dockWindow
            return dockWindow
        end
    end
    if SELECTED_DOCK_FRAME and SELECTED_DOCK_FRAME.editBox and SELECTED_DOCK_FRAME:IsShown() then
        lastSelectedChatFrame = SELECTED_DOCK_FRAME
        return SELECTED_DOCK_FRAME
    end
    if lastSelectedChatFrame and lastSelectedChatFrame.editBox and lastSelectedChatFrame:IsShown() then
        return lastSelectedChatFrame
    end
    if type(ChatEdit_GetLastActiveWindow) == "function" then
        local activeEditBox = ChatEdit_GetLastActiveWindow()
        local activeFrame = activeEditBox and activeEditBox:GetParent()
        if activeFrame and activeFrame.editBox and activeFrame:IsShown() then
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

    local function ResolveNumericChannelTarget(candidate)
        local numericCandidate = tonumber(candidate)
        if not numericCandidate or numericCandidate <= 0 then
            return nil
        end
        local localId = GetChannelName(numericCandidate)
        if localId and localId > 0 then
            return localId
        end
        return nil
    end

    if type(channelName) == "number" then
        return ResolveNumericChannelTarget(channelName)
    end

    local channelNameString = tostring(channelName)
    local directNumericTarget = ResolveNumericChannelTarget(channelNameString)
    if directNumericTarget then
        return directNumericTarget
    end

    local prefixedNumericTarget = ResolveNumericChannelTarget(channelNameString:match("^%s*(%d+)%s*[%.:%-]"))
    if prefixedNumericTarget then
        return prefixedNumericTarget
    end

    local bracketedNumericTarget = ResolveNumericChannelTarget(channelNameString:match("%[(%d+)[^%]]*%]"))
    if bracketedNumericTarget then
        return bracketedNumericTarget
    end

    local candidates = {
        channelNameString,
        channelNameString:gsub("^%s*%d+%s*[%.:%-]?%s*", ""),
        channelNameString:gsub("%s*%-%s*.*$", "")
    }

    local seenCandidates = {}
    for _, candidate in ipairs(candidates) do
        if candidate and candidate ~= "" and not seenCandidates[candidate] then
            seenCandidates[candidate] = true
            local channelId = GetChannelName(candidate)
            if channelId and channelId > 0 then
                return channelId
            end
        end
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
    for key, value in pairs(channelList) do
        local candidates = {}
        if type(value) == "string" and value ~= "" then
            candidates[#candidates + 1] = value
        elseif type(value) == "number" then
            if type(key) == "number" and key > 0 and value == 1 then
                candidates[#candidates + 1] = key
            else
                candidates[#candidates + 1] = value
            end
        elseif type(value) == "boolean" and value and type(key) == "number" and key > 0 then
            candidates[#candidates + 1] = key
        end

        if type(key) == "string" and value then
            candidates[#candidates + 1] = key
        end

        for _, candidate in ipairs(candidates) do
            local resolvedTarget = ResolveChannelTarget(candidate)
            if resolvedTarget and not seenTargets[resolvedTarget] then
                channelTargets[#channelTargets + 1] = resolvedTarget
                seenTargets[resolvedTarget] = true
            end
        end
    end
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

local function GetPreferredChannelTarget(frame, channelTargets)
    if #channelTargets == 0 then
        return nil
    end

    local validTargets = {}
    for _, target in ipairs(channelTargets) do
        validTargets[target] = true
    end

    local frameChannelTarget = frame and lastUsedChannelByFrame[frame]
    local frameId = frame and frame.GetID and frame:GetID()
    local frameIdChannelTarget = frameId and lastUsedChannelByFrameId[frameId] or nil
    local editBoxChannelTarget = frame and frame.editBox and frame.editBox:GetAttribute("channelTarget")
    local candidates = {
        frameChannelTarget,
        frameIdChannelTarget,
        lastUsedChannelTarget,
        editBoxChannelTarget
    }

    for _, candidate in ipairs(candidates) do
        local resolvedCandidate = ResolveChannelTarget(candidate)
        if resolvedCandidate and validTargets[resolvedCandidate] then
            return resolvedCandidate
        end
    end

    if #channelTargets == 1 then
        return channelTargets[1]
    end

    return nil
end

local function GetMessageTypePresence(...)
    local presentTypes = {}

    local lists = { ... }
    for _, messageTypeList in ipairs(lists) do
        VisitTableEntries(messageTypeList, function(value)
            local normalizedType = NormalizeMessageType(value)
            if normalizedType and normalizedType ~= "" then
                presentTypes[normalizedType] = true
            end
        end)
    end
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
    local apiChannelList
    if frameId and frameId > 0 and type(GetChatWindowChannels) == "function" then
        apiChannelList = { GetChatWindowChannels(frameId) }
    end

    local messageTypeList = frame and frame.messageTypeList
    local apiMessageTypeList
    if frameId and frameId > 0 and type(GetChatWindowMessages) == "function" then
        apiMessageTypeList = { GetChatWindowMessages(frameId) }
    end

    local presentTypes = GetMessageTypePresence(messageTypeList, apiMessageTypeList)
    local channelTargets = MergeChannelTargets(
        MergeChannelTargets(GetChannelTargets(channelList), GetChannelTargets(zoneChannelList)),
        GetChannelTargets(apiChannelList)
    )
    local configuredChannelCount = #channelTargets
    if #channelTargets == 0 and frame and frame.channelName then
        local resolvedChannelTarget = ResolveChannelTarget(frame.channelName)
        if resolvedChannelTarget then
            channelTargets = { resolvedChannelTarget }
        end
    end

    local stickyChannelTarget
    if frame and frame.editBox and frame.editBox:GetAttribute("stickyType") == "CHANNEL" then
        local stickyTarget = frame.editBox:GetAttribute("channelTarget")
        if type(ChatEdit_GetChannelTarget) == "function" then
            stickyTarget = ChatEdit_GetChannelTarget(frame.editBox)
        end
        stickyChannelTarget = ResolveChannelTarget(stickyTarget)
    end
    if stickyChannelTarget then
        if #channelTargets == 0 then
            return "CHANNEL", stickyChannelTarget
        end
        for _, target in ipairs(channelTargets) do
            if target == stickyChannelTarget then
                return "CHANNEL", stickyChannelTarget
            end
        end
    end

    if presentTypes.CHANNEL then
        local rememberedChannelTarget = frame and ResolveChannelTarget(lastUsedChannelByFrame[frame]) or nil
        if not rememberedChannelTarget then
            local frameId = frame and frame.GetID and frame:GetID()
            rememberedChannelTarget = frameId and ResolveChannelTarget(lastUsedChannelByFrameId[frameId]) or nil
        end
        if not rememberedChannelTarget then
            rememberedChannelTarget = ResolveChannelTarget(lastUsedChannelTarget)
        end
        local rememberedChannelLocalId = rememberedChannelTarget and GetChannelName(rememberedChannelTarget) or 0
        if rememberedChannelLocalId and rememberedChannelLocalId > 0 then
            if #channelTargets == 0 then
                return "CHANNEL", rememberedChannelLocalId
            end
            for _, target in ipairs(channelTargets) do
                if target == rememberedChannelLocalId then
                    return "CHANNEL", rememberedChannelLocalId
                end
            end
        end
    end

    if #channelTargets > 0 and (presentTypes.CHANNEL or not next(presentTypes)) then
        local preferredChannelTarget = GetPreferredChannelTarget(frame, channelTargets)
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
        local preferredChannelTarget = GetPreferredChannelTarget(frame, channelTargets)
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
        return nil, nil, nil
    end

    local chatType, channelTarget = GetFrameDefaultChatTarget(selectedFrame)
    if not chatType then
        return nil, nil, nil
    end

    local editBox = selectedFrame.editBox
    editBox:SetAttribute("chatType", chatType)
    editBox:SetAttribute("stickyType", chatType)
    if chatType == "CHANNEL" then
        editBox:SetAttribute("channelTarget", channelTarget)
    end
    UpdateEditBoxHeader(editBox)
    return editBox, chatType, channelTarget
end

local function OpenFrameContext(selectedFrame)
    if not selectedFrame or not selectedFrame.editBox then
        return
    end

    lastSelectedChatFrame = selectedFrame
    local editBox, chatType, channelTarget = ApplyDefaultFrameContext(selectedFrame)
    if not editBox then
        return
    end

    if chatType == "CHANNEL" and channelTarget then
        local channelCommand = "/" .. channelTarget .. " "
        if OpenChat(channelCommand, selectedFrame) then
            if type(ChatEdit_ParseText) == "function" then
                ChatEdit_ParseText(editBox, 0, true)
            end
            return
        end

        ChatEdit_ActivateChat(editBox)
        editBox:SetText(channelCommand)
        if type(ChatEdit_ParseText) == "function" then
            ChatEdit_ParseText(editBox, 0, true)
        end
        return
    end

    ChatEdit_ActivateChat(editBox)
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

local function TrackChannelSend(channelTarget, sourceFrame)
    local resolvedChannelTarget = ResolveChannelTarget(channelTarget)
    if not resolvedChannelTarget then
        return
    end

    lastUsedChannelTarget = resolvedChannelTarget
    local channelFrame = sourceFrame
    if channelFrame and channelFrame.editBox then
        lastUsedChannelByFrame[channelFrame] = resolvedChannelTarget
        local channelFrameId = channelFrame.GetID and channelFrame:GetID()
        if channelFrameId and channelFrameId > 0 then
            lastUsedChannelByFrameId[channelFrameId] = resolvedChannelTarget
        end
    end
    local selectedChannelFrame = GetSelectedChatFrame()
    if selectedChannelFrame and selectedChannelFrame.editBox then
        lastUsedChannelByFrame[selectedChannelFrame] = resolvedChannelTarget
        local selectedChannelFrameId = selectedChannelFrame.GetID and selectedChannelFrame:GetID()
        if selectedChannelFrameId and selectedChannelFrameId > 0 then
            lastUsedChannelByFrameId[selectedChannelFrameId] = resolvedChannelTarget
        end
    end
end

HookSecure("SendChatMessage", function(_, chatType, _, channelTarget)
    if chatType ~= "CHANNEL" then
        return
    end

    local sourceFrame
    if type(ChatEdit_GetActiveWindow) == "function" then
        local activeEditBox = ChatEdit_GetActiveWindow()
        local activeFrame = activeEditBox and activeEditBox:GetParent()
        if activeFrame and activeFrame.editBox then
            sourceFrame = activeFrame
        end
    end
    if not sourceFrame then
        sourceFrame = GetSelectedChatFrame()
    end

    TrackChannelSend(channelTarget, sourceFrame)
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
