local _, addon = ...

local syncQueued = false
local syncGeneration = 0

local function GetEllesmereModule()
    local ellesmereUI = _G.EllesmereUI
    local moduleNamespaces = ellesmereUI and ellesmereUI._ModuleNS
    return moduleNamespaces and moduleNamespaces.EllesmereUIChat
end

local function SyncOwnedTabs()
    local moduleNamespace = GetEllesmereModule()
    local chat = moduleNamespace and moduleNamespace.ECHAT
    if chat and type(chat.TabsRefreshNow) == "function" then
        chat.TabsRefreshNow()
    end
end

local function SyncOwnedPanels()
    local ellesmereUI = _G.EllesmereUI
    local getFrameData = ellesmereUI and ellesmereUI._chatCFD
    if type(getFrameData) ~= "function"
        or not GENERAL_CHAT_DOCK
        or type(FCFDock_GetSelectedWindow) ~= "function"
    then
        return
    end

    local selectedFrame = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    if not selectedFrame then
        return
    end

    -- A newly-created whisper can be selected before EllesmereUI has built
    -- its corresponding panel. Never hide the current body until the
    -- destination body exists; the settled retry below will switch it later.
    local selectedFrameData = getFrameData(selectedFrame)
    local selectedPanel = selectedFrameData and selectedFrameData.bg
    local moduleNamespace = GetEllesmereModule()
    if not selectedPanel or (moduleNamespace and moduleNamespace._chatStackHidden) then
        return
    end

    -- EllesmereUI's message frames are children of its UIParent-owned panel,
    -- not of the Blizzard chat frame. Mirror the dock selection directly
    -- instead of waiting for Blizzard's deferred show/hide pass.
    for index = 1, 20 do
        local chatFrame = _G["ChatFrame" .. index]
        local frameData = chatFrame and getFrameData(chatFrame)
        local panel = frameData and frameData.bg
        if chatFrame and chatFrame.isDocked and panel then
            panel:SetShown(chatFrame == selectedFrame)
        end
    end
end

local function SyncChat()
    syncQueued = false
    local generation = syncGeneration

    SyncOwnedPanels()
    SyncOwnedTabs()

    -- EllesmereUI and Blizzard both coalesce their own zero-delay passes. A
    -- final generation-gated sync converges the body once the burst ends.
    -- Only touch EllesmereUI-owned presentation frames here: calling its
    -- broader refresh entry points from our execution chain can taint Blizzard
    -- chat state.
    C_Timer.After(0.10, function()
        if generation == syncGeneration then
            SyncOwnedPanels()
            SyncOwnedTabs()
        end
    end)
    C_Timer.After(0.40, function()
        if generation == syncGeneration then
            SyncOwnedPanels()
            SyncOwnedTabs()
        end
    end)
end

function addon.QueueEllesmereUIChatSync()
    local ellesmereUI = _G.EllesmereUI
    if not ellesmereUI or type(ellesmereUI._chatCFD) ~= "function" then
        return
    end

    syncGeneration = syncGeneration + 1

    -- Existing panels can follow the secured Blizzard selection immediately.
    -- Keep the queued passes below only for EllesmereUI work that settles on a
    -- later frame, such as integrating a newly-created whisper window.
    SyncOwnedPanels()
    SyncOwnedTabs()

    if syncQueued then
        return
    end

    syncQueued = true
    C_Timer.After(0, SyncChat)
end
