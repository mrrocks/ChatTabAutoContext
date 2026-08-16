local _, addon = ...

local syncQueued = false

local function SyncChat()
    syncQueued = false

    local refreshAll = _G._ECHAT_RefreshAll
    local ellesmereUI = _G.EllesmereUI
    local getFrameData = ellesmereUI and ellesmereUI._chatCFD
    local dockedFrames = addon.GetDockedChatFrames()
    if type(refreshAll) ~= "function" or type(getFrameData) ~= "function" or not dockedFrames then
        return
    end

    local hasDrift = false
    for _, frame in ipairs(dockedFrames) do
        local frameData = getFrameData(frame)
        local background = frameData and frameData.bg
        if background
            and type(background.IsShown) == "function"
            and type(background.SetShown) == "function"
            and type(frame.IsShown) == "function"
        then
            local shown = frame:IsShown()
            if background:IsShown() ~= shown then
                background:SetShown(shown)
                hasDrift = true
            end
        end
    end

    if hasDrift then
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
