local _, addon = ...

local unreadFrames = {}
local tabBullets = {}
local hookedFrames = {}
local unreadWatcher = CreateFrame("Frame")

local function IsChatFrameSelected(frame)
    if frame.isDocked
        and GENERAL_CHAT_DOCK
        and type(FCFDock_GetSelectedWindow) == "function"
    then
        return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) == frame
    end

    return frame:IsShown()
end

local function GetTabBullet(frame)
    local bullet = tabBullets[frame]
    if bullet then
        return bullet
    end

    bullet = CreateFrame("Frame", nil, UIParent)
    bullet:SetFrameStrata("MEDIUM")
    bullet:SetFrameLevel(110)
    bullet:EnableMouse(false)

    local dot = bullet:CreateTexture(nil, "OVERLAY")
    dot:SetAllPoints()
    dot:SetColorTexture(1, 0.82, 0, 1)
    local mask = bullet:CreateMaskTexture()
    mask:SetAllPoints(dot)
    mask:SetTexture(
        "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    dot:AddMaskTexture(mask)

    tabBullets[frame] = bullet
    return bullet
end

local function RefreshTabBullet(frame)
    local bullet = tabBullets[frame]
    local tab = addon.GetChatTab(frame)
    if not unreadFrames[frame] or not tab or not tab:IsVisible() then
        if bullet then
            bullet:Hide()
        end
        return
    end

    bullet = bullet or GetTabBullet(frame)
    local tabAnchor = addon.GetEllesmereUIChatTabAnchor(frame)
    local topInset = -6
    if not tabAnchor then
        local tabName = tab:GetName()
        tabAnchor = tab.Left or tab.leftTexture or (tabName and _G[tabName .. "Left"]) or tab
        topInset = -22
    end
    bullet:ClearAllPoints()
    bullet:SetPoint("CENTER", tabAnchor, "TOPLEFT", 6, topInset)
    bullet:SetSize(4, 4)
    bullet:Show()
end

local function RefreshTabBullets()
    for frame in pairs(tabBullets) do
        RefreshTabBullet(frame)
    end
end

local function ClearUnread(frame)
    if not unreadFrames[frame] then
        return
    end

    unreadFrames[frame] = nil
    RefreshTabBullet(frame)
    if not next(unreadFrames) then
        unreadWatcher:SetScript("OnUpdate", nil)
    end
end

local function WatchUnreadFrames()
    for frame in pairs(unreadFrames) do
        if IsChatFrameSelected(frame) then
            ClearUnread(frame)
        end
    end
end

local function MarkUnread(frame, force)
    if frame == _G.ChatFrame2 or (not force and IsChatFrameSelected(frame)) then
        return
    end
    if unreadFrames[frame] then
        return
    end

    unreadFrames[frame] = true
    addon.SuppressEllesmereUIChatGlow(frame)
    RefreshTabBullet(frame)
    unreadWatcher:SetScript("OnUpdate", WatchUnreadFrames)
end

function addon.MarkChatFrameUnread(frame)
    MarkUnread(frame, true)
end

local function HookChatFrame(frame)
    if not frame or hookedFrames[frame] or type(frame.AddMessage) ~= "function" then
        return
    end

    hooksecurefunc(frame, "AddMessage", function()
        MarkUnread(frame)
    end)
    hookedFrames[frame] = true

    local tab = addon.GetChatTab(frame)
    if tab and tab.alerting then
        MarkUnread(frame)
    end
end

local function DiscoverChatFrames()
    if type(CHAT_FRAMES) == "table" then
        for _, frameName in ipairs(CHAT_FRAMES) do
            HookChatFrame(_G[frameName])
        end
    end
    RefreshTabBullets()
end

local function OnEvent(_, event)
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        addon.QueueEllesmereUIChatGlowHooks()
        return
    end

    DiscoverChatFrames()
    addon.QueueEllesmereUIChatGlowHooks()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("UPDATE_CHAT_WINDOWS")
loader:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
loader:RegisterEvent("CHAT_MSG_WHISPER")
loader:RegisterEvent("CHAT_MSG_BN_WHISPER")
loader:SetScript("OnEvent", OnEvent)
