local _, addon = ...

local syncQueued = false
local syncGeneration = 0

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

    -- EllesmereUI's message frames are children of its UIParent-owned panel,
    -- not of the Blizzard chat frame. Keep a deliberate full-hide intact, but
    -- otherwise mirror the dock selection directly instead of waiting for
    -- Blizzard's deferred show/hide pass.
    local hasVisiblePanel = false
    for index = 1, 20 do
        local chatFrame = _G["ChatFrame" .. index]
        local frameData = chatFrame and getFrameData(chatFrame)
        local panel = frameData and frameData.bg
        if chatFrame and chatFrame.isDocked and panel then
            hasVisiblePanel = hasVisiblePanel or panel:IsShown()
        end
    end

    if not hasVisiblePanel then
        return
    end

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

    -- EllesmereUI and Blizzard both coalesce their own zero-delay passes. A
    -- final generation-gated sync converges the body and repaints the ghost
    -- tabs once the burst ends, without rerunning its full layout on every
    -- intermediate selection.
    C_Timer.After(0.10, function()
        if generation == syncGeneration then
            SyncOwnedPanels()

            local refreshAll = _G._ECHAT_RefreshAll
            if type(refreshAll) == "function" then
                refreshAll()
            end
        end
    end)
end

function addon.QueueEllesmereUIChatSync()
    if type(_G._ECHAT_RefreshAll) ~= "function" then
        return
    end

    syncGeneration = syncGeneration + 1
    if syncQueued then
        return
    end

    syncQueued = true
    C_Timer.After(0, SyncChat)
end
