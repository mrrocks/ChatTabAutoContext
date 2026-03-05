local _, ns = ...

local eventFrame = ns.eventFrame
local whisperEvents = ns.whisperEvents

local function GetEditBoxMessageText(editBox)
    if not editBox then
        return nil
    end
    local text = editBox:GetText()
    if not text or text == "" then
        return nil
    end
    if text:match("^/%S+%s*$") then
        return nil
    end
    local body = text:match("^/%d+%s+(.+)$") or text:match("^/%S+%s+(.+)$")
    return body or text
end

local function FindCurrentTargetIndex(editBox, targets)
    local currentType = editBox:GetAttribute("chatType")
    local currentChannel = editBox:GetAttribute("channelTarget")
    for i, target in ipairs(targets) do
        if target.chatType == currentType then
            if currentType ~= "CHANNEL" or target.channelTarget == tonumber(currentChannel) then
                return i
            end
        end
    end
    return nil
end

local function ApplyFrameTarget(frame, targets, targetIndex, pendingText)
    local target = targets[targetIndex]
    if not target then
        ns.OpenFrameContext(frame, pendingText)
        return
    end
    ns.SetFrameChatTarget(frame, target.chatType, target.channelTarget, pendingText)
end

local function HandleEditBoxTabPressed(editBox)
    if not editBox then
        return false
    end

    local sourceFrame = editBox:GetParent()
    if not ns.IsValidChatFrame(sourceFrame) then
        sourceFrame = ns.GetSelectedChatFrame()
    end

    local pendingText = GetEditBoxMessageText(editBox)
    local direction = IsShiftKeyDown() and -1 or 1

    local targets = ns.GetFrameChatTargets(sourceFrame)
    if #targets > 1 then
        local currentIndex = FindCurrentTargetIndex(editBox, targets)
        if currentIndex then
            local nextIndex = currentIndex + direction
            if nextIndex >= 1 and nextIndex <= #targets then
                ApplyFrameTarget(sourceFrame, targets, nextIndex, pendingText)
                return true
            end
        elseif direction == 1 then
            ApplyFrameTarget(sourceFrame, targets, 1, pendingText)
            return true
        end
    end

    local nextFrame = ns.SelectAdjacentChatFrame(sourceFrame, direction)
    if not nextFrame then
        return false
    end

    if ns.IsWhisperType(nextFrame.chatType) then
        ns.SetWhisperTarget(nextFrame, true, pendingText)
        return true
    end

    local nextTargets = ns.GetFrameChatTargets(nextFrame)
    if #nextTargets > 0 then
        local entryIndex = direction == 1 and 1 or #nextTargets
        ApplyFrameTarget(nextFrame, nextTargets, entryIndex, pendingText)
    else
        ns.OpenFrameContext(nextFrame, pendingText)
    end
    return true
end

local ctacTabHandler = {}

local function MakeTabWrapper(orig)
    local wrapper = function(self, ...)
        if HandleEditBoxTabPressed(self) then
            if type(AutoComplete_HideIfAttachedTo) == "function" then
                AutoComplete_HideIfAttachedTo(self)
            end
            return
        end
        if type(orig) == "function" then
            orig(self, ...)
        end
    end
    return wrapper
end

local function HookEditBoxTab(editBox)
    if not editBox then
        return
    end
    local current = editBox:GetScript("OnTabPressed")
    if current and ctacTabHandler[current] then
        return
    end
    local wrapper = MakeTabWrapper(current)
    ctacTabHandler[wrapper] = true
    editBox:SetScript("OnTabPressed", wrapper)
end

local function HookAllEditBoxTabs()
    for i = 1, NUM_CHAT_WINDOWS or 20 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.editBox then
            HookEditBoxTab(frame.editBox)
        end
    end
end

local function InstallHooks()
    if not ChatFrame1 or not ChatFrame1.editBox then
        return false
    end

    HookAllEditBoxTabs()

    hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
        HookEditBoxTab(editBox)
    end)

    return true
end

if not InstallHooks() then
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        if InstallHooks() then
            self:UnregisterAllEvents()
        end
    end)
end

local function OnWindowTypeChanged(frame, chatType, chatTarget)
    if frame and frame.editBox then
        HookEditBoxTab(frame.editBox)
    end

    if not ns.IsWhisperType(chatType) then
        return
    end

    if frame and chatTarget and chatTarget ~= "" then
        frame.chatTarget = chatTarget
    end

    ns.UpdateWhisperState(frame, chatType, chatTarget)
    ns.ScheduleWhisperTarget(frame, false)
end

local function OnKeyDown(self, key)
    self:SetPropagateKeyboardInput(key ~= "ENTER")
    if key ~= "ENTER" then
        return
    end

    local selectedFrame = ns.GetSelectedChatFrame()
    if not selectedFrame or not selectedFrame.editBox then
        self:SetPropagateKeyboardInput(true)
        return
    end

    if selectedFrame.editBox:HasFocus() then
        self:SetPropagateKeyboardInput(true)
        return
    end

    ns.SetLastSelectedChatFrame(selectedFrame)

    if ns.IsWhisperType(selectedFrame.chatType) then
        ns.SetWhisperTarget(selectedFrame, true)
        return
    end

    local recentTarget = ns.GetFrameRecentTarget(selectedFrame)
    if recentTarget then
        ns.SetFrameChatTarget(
            selectedFrame,
            recentTarget.chatType,
            recentTarget.channelTarget
        )
    else
        ns.OpenFrameContext(selectedFrame)
    end
end

ns.HookSecure("SendChatMessage", function(_, chatType, _, channelTarget)
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
        sourceFrame = ns.GetSelectedChatFrame()
    end

    ns.TrackChannelSend(channelTarget, sourceFrame)
end)

if not ns.HookSecure("FCF_SetTemporaryWindowType", OnWindowTypeChanged) then
    ns.HookSecure("FCF_SetWindowType", OnWindowTypeChanged)
end

ns.HookSecure("FCF_Tab_OnClick", function(chatFrame)
    local actualChatFrame = ns.GetChatFrameFromTab(chatFrame)
    if actualChatFrame then
        ns.SetLastSelectedChatFrame(actualChatFrame)
        if actualChatFrame.editBox then
            HookEditBoxTab(actualChatFrame.editBox)
        end
    end
    ns.ScheduleWhisperTarget(actualChatFrame, false)
end)

ns.HookSecure("FCF_OpenTemporaryWindow", function()
    HookAllEditBoxTabs()
end)

for eventName in pairs(whisperEvents) do
    eventFrame:RegisterEvent(eventName)
end
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

local chatMsgEvents = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_CHANNEL",
}
for _, eventName in ipairs(chatMsgEvents) do
    pcall(eventFrame.RegisterEvent, eventFrame, eventName)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        eventFrame:EnableKeyboard(false)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        eventFrame:EnableKeyboard(true)
        eventFrame:SetPropagateKeyboardInput(true)
        return
    end
    if whisperEvents[event] then
        ns.TrackWhisperEvent(event, ...)
        ns.ScheduleWhisperTarget(nil, false)
        return
    end
    if strsub(event, 1, 9) == "CHAT_MSG_" then
        ns.TrackReceivedMessage(event, ...)
        return
    end
end)

eventFrame:SetScript("OnKeyDown", OnKeyDown)
eventFrame:EnableKeyboard(true)
eventFrame:SetPropagateKeyboardInput(true)
