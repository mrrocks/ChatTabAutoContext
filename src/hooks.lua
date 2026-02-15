local _, ns = ...

local eventFrame = ns.eventFrame
local whisperEvents = ns.whisperEvents
local originalTabHandlerByEditBox = setmetatable({}, { __mode = "k" })
local keyboardPropagationPending = false

local function EnsureKeyboardPropagation()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        keyboardPropagationPending = true
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    eventFrame:SetPropagateKeyboardInput(true)
    if keyboardPropagationPending then
        keyboardPropagationPending = false
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
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
        ns.SetWhisperTarget(nextFrame, true)
        return true
    end

    ns.OpenFrameContext(nextFrame)
    return true
end

local function HookChatEditBoxTab(chatFrame)
    local actualChatFrame = ns.GetChatFrameFromTab(chatFrame)
    if not ns.IsValidChatFrame(actualChatFrame) then
        return
    end

    local editBox = actualChatFrame.editBox
    if originalTabHandlerByEditBox[editBox] ~= nil then
        return
    end

    local originalOnTabPressed = editBox:GetScript("OnTabPressed")
    originalTabHandlerByEditBox[editBox] = originalOnTabPressed or false
    editBox:SetScript("OnTabPressed", function(self, ...)
        if HandleEditBoxTabPressed(self) then
            return
        end

        local fallbackHandler = originalTabHandlerByEditBox[self]
        if type(fallbackHandler) == "function" then
            fallbackHandler(self, ...)
        end
    end)
end

local function HookAllChatEditBoxTabs()
    local chatFrames = ns.GetOrderedChatFrames(true)
    for _, chatFrame in ipairs(chatFrames) do
        HookChatEditBoxTab(chatFrame)
    end
end

local function OnWindowTypeChanged(frame, chatType, chatTarget)
    HookChatEditBoxTab(frame)

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
    if ns.IsWhisperType(selectedFrame.chatType) then
        ns.SetWhisperTarget(selectedFrame, true)
        return
    end

    ns.OpenFrameContext(selectedFrame)
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
        EnsureKeyboardPropagation()
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
        HookChatEditBoxTab(actualChatFrame)
    end
    ns.ScheduleWhisperTarget(actualChatFrame, false)
end)

ns.HookSecure("FCF_OpenTemporaryWindow", function()
    HookAllChatEditBoxTabs()
end)

eventFrame:SetScript("OnKeyDown", OnKeyDown)
eventFrame:EnableKeyboard(true)
EnsureKeyboardPropagation()

HookAllChatEditBoxTabs()
