local _, addon = ...

local syncQueued = false

local function SyncChat()
    syncQueued = false

    local refreshAll = _G._ECHAT_RefreshAll
    if type(refreshAll) == "function" then
        refreshAll()
    end
end

function addon.QueueEllesmereUIChatSync()
    if syncQueued or type(_G._ECHAT_RefreshAll) ~= "function" then
        return
    end

    syncQueued = true
    C_Timer.After(0, SyncChat)
end
