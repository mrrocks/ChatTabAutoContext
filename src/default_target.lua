local _, ns = ...

local lastUsedChannelByFrame = setmetatable({}, { __mode = "k" })
local lastUsedChannelByFrameId = {}
local lastUsedChannelTarget
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
        local localId, localName = GetChannelName(numericCandidate)
        if localId and localId > 0 and localName and localName ~= "" then
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

function ns.GetFrameWindowName(frame)
    if not frame then
        return nil
    end
    local frameId = frame.GetID and frame:GetID()
    if frameId and frameId > 0 then
        return GetChatWindowInfo(frameId)
    end
    return nil
end

function ns.GetFrameDefaultChatTarget(frame)
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

    local windowName = ns.GetFrameWindowName(frame)
    local normalizedWindowName = windowName and strlower(windowName:gsub("%s+", ""))
    local mappedType = normalizedWindowName and frameWindowTypeToChatType[normalizedWindowName]
    if mappedType then
        return mappedType, nil
    end

    return nil, nil
end

function ns.OpenFrameContext(selectedFrame, pendingText)
    if not selectedFrame or not selectedFrame.editBox then
        return
    end

    ns.SetLastSelectedChatFrame(selectedFrame)
    local chatType, channelTarget = ns.GetFrameDefaultChatTarget(selectedFrame)
    if not chatType then
        return
    end

    local editBox = selectedFrame.editBox
    editBox:SetAttribute("chatType", chatType)
    editBox:SetAttribute("stickyType", chatType)
    if chatType == "CHANNEL" then
        editBox:SetAttribute("channelTarget", channelTarget)
    end
    ns.UpdateEditBoxHeader(editBox)

    if chatType == "CHANNEL" and channelTarget then
        local channelCommand = "/" .. channelTarget .. " "
        local fullText = pendingText and (channelCommand .. pendingText) or channelCommand
        if not ns.OpenChat(fullText, selectedFrame) then
            ChatEdit_ActivateChat(editBox)
            editBox:SetText(fullText)
        end
        if type(ChatEdit_ParseText) == "function" then
            ChatEdit_ParseText(editBox, 0, true)
        end
        return
    end

    ChatEdit_ActivateChat(editBox)
    if pendingText then
        editBox:SetText(pendingText)
    end
end

function ns.TrackChannelSend(channelTarget, sourceFrame)
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
    local selectedChannelFrame = ns.GetSelectedChatFrame()
    if selectedChannelFrame and selectedChannelFrame.editBox then
        lastUsedChannelByFrame[selectedChannelFrame] = resolvedChannelTarget
        local selectedChannelFrameId = selectedChannelFrame.GetID and selectedChannelFrame:GetID()
        if selectedChannelFrameId and selectedChannelFrameId > 0 then
            lastUsedChannelByFrameId[selectedChannelFrameId] = resolvedChannelTarget
        end
    end
end
