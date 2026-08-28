local _, addon = ...

local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue
local securecallfunction = _G.securecallfunction

local function IsSecret(value)
    return (canaccessvalue ~= nil and not canaccessvalue(value))
        or (issecretvalue ~= nil and issecretvalue(value))
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

-- Battle.net whisper targets are private tokenized values. Reading one from a
-- Blizzard frame and writing it back through addon execution can taint the
-- shared chat state, causing ChatHistory_GetAccessID to fail when the next
-- BN_WHISPER arrives. Native Blizzard code still owns those temporary windows;
-- only ordinary character whispers are safe for addon-managed targeting.
local managedWhisperChatTypes = {
    WHISPER = true
}

local chatTypeSendRequirements = {
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
        return IsInGroup(LE_PARTY_CATEGORY_HOME)
    end,
    RAID = function()
        return IsInRaid(LE_PARTY_CATEGORY_HOME)
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

local function HasValue(value)
    return value ~= nil and value ~= ""
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

local function GetSelectedDockedChatFrame()
    if GENERAL_CHAT_DOCK and type(FCFDock_GetSelectedWindow) == "function" then
        return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    end
    return nil
end

function addon.GetActiveChatFrame()
    if IsUsableChatFrame(SELECTED_CHAT_FRAME) then
        return SELECTED_CHAT_FRAME
    end

    local selectedFrame = GetSelectedDockedChatFrame()
    if IsUsableChatFrame(selectedFrame) then
        return selectedFrame
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
        if not managedWhisperChatTypes[chatType] then
            return nil
        end
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
    if not managedWhisperChatTypes[chatType] then
        return nil
    end

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
    if not managedWhisperChatTypes[chatType] or not availableTypes[chatType] then
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
        or (whisperChatTypes[target.chatType] and not managedWhisperChatTypes[target.chatType])
        or type(editBox.SetChatType) ~= "function"
        or type(editBox.UpdateHeader) ~= "function"
    then
        return false
    end

    local function ApplyStickyType()
        if not whisperChatTypes[target.chatType]
            and type(editBox.SetStickyType) == "function"
        then
            securecallfunction(editBox.SetStickyType, editBox, target.chatType)
        end
    end

    -- Temporary whisper windows already carry Blizzard's native target. Avoid
    -- rewriting the edit-box attributes when the requested context is already
    -- active, particularly for private whisper values. Keep non-whisper sticky
    -- state synchronized even on a match: Blizzard resets to it after Escape
    -- and after sending.
    if TargetsMatch(GetEditBoxTarget(editBox), target) then
        ApplyStickyType()
        return true
    end

    if target.chatType == "CHANNEL" then
        if type(editBox.SetChannelTarget) ~= "function" then
            return false
        end
        securecallfunction(editBox.SetChannelTarget, editBox, target.channelId)
    elseif whisperChatTypes[target.chatType] then
        if type(editBox.SetTellTarget) ~= "function" then
            return false
        end
        securecallfunction(editBox.SetTellTarget, editBox, target.tellTarget)
    end

    -- These fields are later consumed by Blizzard's event, temporary-window,
    -- and chat-configuration paths. Keep the writes in native execution so a
    -- harmless target change cannot leave those later paths tainted.
    securecallfunction(editBox.SetChatType, editBox, target.chatType)
    ApplyStickyType()
    securecallfunction(editBox.UpdateHeader, editBox)
    return true
end

local function GetSessionOverrideTarget(frame)
    local override = sessionOverrides[frame]
    if not override then
        return nil
    end

    if override.chatType ~= "CHANNEL" then
        if not IsChatTypeSendable(override.chatType) then
            sessionOverrides[frame] = nil
            return nil
        end
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

local function RememberSelectedTarget(frame, selectedTarget, wasManuallySelected)
    if not frame
        or not selectedTarget
        or not IsChatTypeSendable(selectedTarget.chatType)
        or not (IsStickyNonWhisperChatType(selectedTarget.chatType)
            or managedWhisperChatTypes[selectedTarget.chatType])
    then
        return
    end

    if not whisperChatTypes[selectedTarget.chatType] or whisperChatTypes[frame.chatType] then
        local defaultTarget = addon.GetDefaultTarget(frame)
        if defaultTarget and TargetsMatch(selectedTarget, defaultTarget) then
            sessionOverrides[frame] = nil
            return
        end
        if not defaultTarget and not wasManuallySelected then
            -- SAY can be Blizzard's automatic fallback while a Party, Raid,
            -- or Instance target is unavailable. Do not let that fallback
            -- become a tab override that survives after the player joins.
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

local function GetFrameTarget(frame)
    if frame and not IsSecret(frame.chatType) and whisperChatTypes[frame.chatType] then
        -- Temporary conversation windows already carry Blizzard's native
        -- target. Never reapply it from addon execution: private whisper
        -- values can become inaccessible in protected instances.
        return nil
    end

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

local function RememberEditBoxTarget(editBox, selectedTarget, wasManuallySelected)
    if not editBox then
        return
    end

    local frame = addon.GetActiveChatFrame() or GetFrameForEditBox(editBox)
    if not frame then
        return
    end

    RememberSelectedTarget(frame, selectedTarget, wasManuallySelected)
end

local hookedSendEditBoxes = setmetatable({}, { __mode = "k" })
local pendingSendText = setmetatable({}, { __mode = "k" })
local pendingSendTargets = setmetatable({}, { __mode = "k" })
local activationTargets = setmetatable({}, { __mode = "k" })
local contextApplyQueued = setmetatable({}, { __mode = "k" })
local sendScriptsHooked = false

local function OnEditBoxFocusGained(editBox)
    activationTargets[editBox] = GetEditBoxTarget(editBox)
    if contextApplyQueued[editBox] or not C_Timer then
        return
    end

    contextApplyQueued[editBox] = true
    -- IM-style chat keeps its edit box shown after Escape, so OnShow does not
    -- run on the next Enter. Focus gain occurs for every activation. Defer the
    -- work until Blizzard's complete OpenChat caller has returned so this hook
    -- cannot taint state written later in that call.
    C_Timer.After(0, function()
        contextApplyQueued[editBox] = nil
        if type(editBox.HasFocus) == "function" and not editBox:HasFocus() then
            return
        end
        if CHAT_FOCUS_OVERRIDE then
            return
        end

        local text = type(editBox.GetText) == "function" and editBox:GetText() or nil
        if IsSecret(text) or HasValue(text) then
            return
        end
        if editBox.setText == 1 then
            local pending = editBox.text
            if IsSecret(pending) or HasValue(pending) then
                return
            end
        end

        addon.ApplyActiveTabContext()
        activationTargets[editBox] = GetEditBoxTarget(editBox)
    end)
end

local function OnEditBoxTextChanged(editBox, userInput)
    if not editBox or type(editBox.GetText) ~= "function" then
        return
    end

    local text = editBox:GetText()
    if IsSecret(text) then
        pendingSendText[editBox] = nil
        pendingSendTargets[editBox] = nil
        return
    end

    -- Blizzard clears the text programmatically before the OnEnterPressed
    -- hook runs. Preserve the pending flag across that clear, while still
    -- honoring a user who deletes all text before pressing Enter.
    if text == "" and not userInput then
        return
    end

    local hasText = HasValue(text)
    pendingSendText[editBox] = hasText or nil
    pendingSendTargets[editBox] = hasText and GetEditBoxTarget(editBox) or nil
end

local function OnEditBoxEnterPressed(editBox)
    local hadText = pendingSendText[editBox]
    local selectedTarget = pendingSendTargets[editBox]
    local activationTarget = activationTargets[editBox]
    pendingSendText[editBox] = nil
    pendingSendTargets[editBox] = nil
    activationTargets[editBox] = nil
    if hadText and selectedTarget then
        -- Blizzard's native OnEnterPressed has already cleared the input and
        -- reset its chat type before HookScript invokes us. Remember the target
        -- captured while the draft still existed instead of that reset value.
        local wasManuallySelected = not activationTarget
            or not TargetsMatch(selectedTarget, activationTarget)
        RememberEditBoxTarget(editBox, selectedTarget, wasManuallySelected)
    end
end

local function HookEditBoxSend(editBox)
    if not editBox
        or hookedSendEditBoxes[editBox]
        or type(editBox.HookScript) ~= "function"
    then
        return false
    end

    local frame = GetFrameForEditBox(editBox)
    local frameId = frame and type(frame.GetID) == "function" and frame:GetID() or nil
    if (frame and frame.isTemporary) or type(frameId) ~= "number" or frameId > 10 then
        return false
    end

    -- Never use hooksecurefunc(editBox, "SendText", ...). Object-method hooks
    -- install a wrapper field directly on the Blizzard edit box. A temporary
    -- whisper creation can later read that tainted object while processing a
    -- secret target and poison ChatHistory for the rest of the session.
    -- C-side script hooks do not write method fields; permanent frames only
    -- are sufficient for remembering normal per-tab sends.
    editBox:HookScript("OnEditFocusGained", OnEditBoxFocusGained)
    editBox:HookScript("OnTextChanged", OnEditBoxTextChanged)
    editBox:HookScript("OnEnterPressed", OnEditBoxEnterPressed)
    hookedSendEditBoxes[editBox] = true
    sendScriptsHooked = true
    return true
end

local function HookKnownEditBoxes()
    for index = 1, 10 do
        local frame = _G["ChatFrame" .. index]
        if frame then
            HookEditBoxSend(frame.editBox)
        end
    end

    if type(CHAT_FRAMES) == "table" then
        for _, frameName in ipairs(CHAT_FRAMES) do
            local frame = type(frameName) == "string" and _G[frameName] or frameName
            if frame then
                HookEditBoxSend(frame.editBox)
            end
        end
    end

    HookEditBoxSend(GetActiveEditBox())
end

local function InstallHooks()
    -- OnEditBoxPreSendText fires inline immediately before Blizzard calls
    -- SendChatMessage. Entering addon code there taints the rest of the send.
    -- C-side post-script hooks capture the completed send after Blizzard's
    -- handler and avoid placing an addon wrapper on any edit-box method.
    HookKnownEditBoxes()

    return sendScriptsHooked
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

local lastObservedChatFrame
local function PrimeFrameContext(frame, preserveActiveInput)
    if not frame then
        return
    end

    local editBox = GetEditBoxForSend(frame)
    if not editBox or HasWhisperTellTarget(editBox) then
        return
    end
    if preserveActiveInput
        and type(editBox.HasFocus) == "function"
        and editBox:HasFocus()
    then
        return
    end

    ApplyFrameTarget(frame, editBox)
    activationTargets[editBox] = GetEditBoxTarget(editBox)
end

local selectionWatcher = CreateFrame("Frame")
selectionWatcher:SetScript("OnUpdate", function()
    local frame = addon.GetActiveChatFrame()
    if frame == lastObservedChatFrame then
        return
    end

    lastObservedChatFrame = frame
    if not frame then
        return
    end

    -- Observe native selection from our own update pass, completely outside
    -- Blizzard's hardware-click execution. Prime the shared input while it is
    -- still closed so EllesmereUI never renders SAY before the focus fallback
    -- corrects it. This never clicks or selects a chat tab.
    PrimeFrameContext(frame, false)
end)

local contextRefreshQueued = false
local contextEventFrame = CreateFrame("Frame")
contextEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
contextEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
contextEventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
contextEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
contextEventFrame:SetScript("OnEvent", function()
    if contextRefreshQueued or not C_Timer then
        return
    end

    contextRefreshQueued = true
    -- Group and instance availability can change without selecting another
    -- tab. Refresh after the event dispatch, but never replace a target while
    -- the player is already composing a message.
    C_Timer.After(0, function()
        contextRefreshQueued = false
        local frame = addon.GetActiveChatFrame()
        lastObservedChatFrame = frame
        PrimeFrameContext(frame, true)
    end)
end)
