local _, ns = ...

local eventFrame = ns.eventFrame
local whisperEvents = ns.whisperEvents
local keyboardPropagationPending = false

local function EnsureKeyboardPropagation()
    if InCombatLockdown() then
        keyboardPropagationPending = true
        return
    end
    eventFrame:SetPropagateKeyboardInput(true)
    keyboardPropagationPending = false
end

local function HandleEditBoxTabPressed(editBox)
    if not editBox then
        return false
    end

    local sourceFrame = editBox:GetParent()
    if not ns.IsValidChatFrame(sourceFrame) then
        sourceFrame = ns.GetSelectedChatFrame()
    end

    local direction = IsShiftKeyDown() and -1 or 1
    local nextFrame = ns.SelectAdjacentChatFrame(sourceFrame, direction)
    if not nextFrame then
        return false
    end

    if ns.IsWhisperType(nextFrame.chatType) then
        ns.DebugTab(sourceFrame, nextFrame, "WHISPER", nil)
        ns.SetWhisperTarget(nextFrame, true)
        return true
    end

    local chatType, channelTarget = ns.GetFrameDefaultChatTarget(nextFrame)
    ns.DebugTab(sourceFrame, nextFrame, chatType, channelTarget)
    ns.OpenFrameContext(nextFrame)
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

local function InstallTabHooks()
    if not ChatFrame1 or not ChatFrame1.editBox then
        return false
    end
    HookAllEditBoxTabs()

    hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
        HookEditBoxTab(editBox)
    end)

    return true
end

if not InstallTabHooks() then
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        if InstallTabHooks() then
            self:UnregisterAllEvents()
        end
    end)
end

local function OnWindowTypeChanged(frame, chatType, chatTarget)
    if not ns.IsWhisperType(chatType) then
        return
    end

    if frame and chatTarget and chatTarget ~= "" then
        frame.chatTarget = chatTarget
    end

    ns.UpdateWhisperState(frame, chatType, chatTarget)
    ns.ScheduleWhisperTarget(frame, false)
end

local function OnKeyDown(_, key)
    if key ~= "ENTER" then
        return
    end

    local selectedFrame = ns.GetSelectedChatFrame()
    if not selectedFrame or not selectedFrame.editBox then
        return
    end

    if selectedFrame.editBox:HasFocus() then
        return
    end

    ns.SetLastSelectedChatFrame(selectedFrame)

    ns.RunOutOfCombat(function()
        if not selectedFrame or not selectedFrame.editBox then
            return
        end
        if ns.IsWhisperType(selectedFrame.chatType) then
            ns.DebugEnter(selectedFrame, "WHISPER", nil)
            ns.SetWhisperTarget(selectedFrame, true)
            return
        end
        local chatType, channelTarget = ns.GetFrameDefaultChatTarget(selectedFrame)
        ns.DebugEnter(selectedFrame, chatType, channelTarget)
        ns.OpenFrameContext(selectedFrame)
    end)
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

for eventName in pairs(whisperEvents) do
    eventFrame:RegisterEvent(eventName)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if keyboardPropagationPending then
            EnsureKeyboardPropagation()
        end
        ns.HandleCombatDeferEvent(event)
        return
    end
    if not whisperEvents[event] then
        return
    end

    ns.TrackWhisperEvent(event, ...)
    ns.ScheduleWhisperTarget(nil, false)
end)

ns.HookSecure("FCF_Tab_OnClick", function(chatFrame)
    local actualChatFrame = ns.GetChatFrameFromTab(chatFrame)
    if actualChatFrame then
        ns.SetLastSelectedChatFrame(actualChatFrame)
    end
    ns.ScheduleWhisperTarget(actualChatFrame, false)
end)

eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnKeyDown", OnKeyDown)

ns.RunOutOfCombat(function()
    eventFrame:EnableKeyboard(true)
    EnsureKeyboardPropagation()
end)
