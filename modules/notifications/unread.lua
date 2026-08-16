local _, addon = ...

local relevantChatEvents = {
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_YELL = true
}

local unreadFrames = {}
local tabBullets = {}
local hookedFrames = {}
local unreadWatcher = CreateFrame("Frame")
local discoveryQueued = false

local function IsChatFrameSelected(frame)
    if frame.isDocked
        and GENERAL_CHAT_DOCK
        and type(FCFDock_GetSelectedWindow) == "function"
    then
        return FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) == frame
    end

    return frame:IsShown()
end

local function GetChatTab(frame)
    if type(frame.GetName) ~= "function" then
        return nil
    end

    local frameName = frame:GetName()
    if not frameName then
        return nil
    end
    return _G[frameName .. "Tab"]
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
    local tab = GetChatTab(frame)
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
        RefreshTabBullet(frame)
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

local function OnChatFrameMessage(frame, _, _, _, _, _, _, _, event)
    if relevantChatEvents[event] then
        MarkUnread(frame)
    end
end

local function HookChatFrame(frame)
    if not frame or hookedFrames[frame] or type(frame.AddMessage) ~= "function" then
        return
    end

    hooksecurefunc(frame, "AddMessage", OnChatFrameMessage)
    hookedFrames[frame] = true

    local tab = GetChatTab(frame)
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

local function QueueChatFrameDiscovery()
    if discoveryQueued or not C_Timer then
        return
    end

    discoveryQueued = true
    C_Timer.After(0, function()
        DiscoverChatFrames()
        C_Timer.After(0, function()
            discoveryQueued = false
            DiscoverChatFrames()
        end)
    end)
end

local function OnEvent(_, event)
    DiscoverChatFrames()
    addon.QueueEllesmereUIChatGlowHooks()

    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        QueueChatFrameDiscovery()
    end
end

if type(FCF_OpenTemporaryWindow) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", DiscoverChatFrames)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("UPDATE_CHAT_WINDOWS")
loader:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
loader:RegisterEvent("CHAT_MSG_WHISPER")
loader:RegisterEvent("CHAT_MSG_BN_WHISPER")
loader:SetScript("OnEvent", OnEvent)
