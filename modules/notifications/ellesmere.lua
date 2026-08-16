local _, addon = ...

local ghostCache = {}
local hookedGhosts = {}
local replacingGlow = {}
local glowHookScanQueued = false

local function GetEllesmereUIChatTabStrip()
    local ellesmereUI = _G.EllesmereUI
    local moduleNamespaces = ellesmereUI and ellesmereUI._ModuleNS
    local chatNamespace = moduleNamespaces and moduleNamespaces.EllesmereUIChat
    return chatNamespace and chatNamespace._chatTabStrip
end

local function GetEllesmereUIChatGhostFrame(ghost)
    local state = ghost and ghost.state
    if ghost and ghost._flasher and ghost._fs and state then
        return state.cf
    end
    return nil
end

local function ScanEllesmereUIChatGhosts(visitor)
    local strip = GetEllesmereUIChatTabStrip()
    if not strip then
        return
    end

    local containers = { strip }
    local stripChildren = { strip:GetChildren() }
    for _, child in ipairs(stripChildren) do
        containers[#containers + 1] = child
    end

    for _, container in ipairs(containers) do
        for _, candidate in ipairs({ container:GetChildren() }) do
            local frame = GetEllesmereUIChatGhostFrame(candidate)
            if frame then
                ghostCache[frame] = candidate
                if visitor then
                    visitor(candidate)
                end
            end
        end
    end
end

local function GetEllesmereUIChatGhost(frame)
    local cached = ghostCache[frame]
    if GetEllesmereUIChatGhostFrame(cached) == frame then
        return cached
    end

    ScanEllesmereUIChatGhosts()
    local ghost = ghostCache[frame]
    if GetEllesmereUIChatGhostFrame(ghost) == frame then
        return ghost
    end

    ghostCache[frame] = nil
    return nil
end

function addon.GetEllesmereUIChatTabAnchor(frame)
    return GetEllesmereUIChatGhost(frame)
end

local function ReplaceEllesmereUIChatGlow(ghost)
    if replacingGlow[ghost] then
        return
    end

    local state = ghost.state
    local frame = state and state.cf
    if not frame then
        return
    end

    replacingGlow[ghost] = true
    if type(ghost.StopFlash) == "function" then
        ghost:StopFlash()
    end
    if type(addon.MarkChatFrameUnread) == "function" then
        addon.MarkChatFrameUnread(frame)
    end
    replacingGlow[ghost] = nil
end

local function HookEllesmereUIChatGhost(ghost)
    if type(ghost.StartFlash) ~= "function" then
        return
    end

    if not hookedGhosts[ghost] then
        hookedGhosts[ghost] = true
        hooksecurefunc(ghost, "StartFlash", ReplaceEllesmereUIChatGlow)
    end
    if type(ghost._flasher.IsPlaying) == "function" and ghost._flasher:IsPlaying() then
        ReplaceEllesmereUIChatGlow(ghost)
    end
end

function addon.SuppressEllesmereUIChatGlow(frame)
    if not GetEllesmereUIChatTabStrip() then
        return
    end

    local ghost = GetEllesmereUIChatGhost(frame)
    if not ghost then
        addon.QueueEllesmereUIChatGlowHooks()
        return
    end

    HookEllesmereUIChatGhost(ghost)
    if type(ghost.StopFlash) == "function" then
        ghost:StopFlash()
    end
end

local function HookEllesmereUIChatGhosts()
    ScanEllesmereUIChatGhosts(HookEllesmereUIChatGhost)
end

function addon.QueueEllesmereUIChatGlowHooks()
    if glowHookScanQueued or not GetEllesmereUIChatTabStrip() then
        return
    end

    HookEllesmereUIChatGhosts()
    if not C_Timer then
        return
    end

    glowHookScanQueued = true
    C_Timer.After(0, function()
        HookEllesmereUIChatGhosts()
        C_Timer.After(0, function()
            glowHookScanQueued = false
            HookEllesmereUIChatGhosts()
        end)
    end)
end
