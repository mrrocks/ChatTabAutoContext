local _, ns = ...

local lastSelectedChatFrame

function ns.SetLastSelectedChatFrame(frame)
    lastSelectedChatFrame = frame
end

function ns.GetLastSelectedChatFrame()
    return lastSelectedChatFrame
end

function ns.GetSelectedChatFrame()
    if type(FCFDock_GetSelectedWindow) == "function" and GENERAL_CHAT_DOCK then
        local dockWindow = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
        if dockWindow and dockWindow.editBox and dockWindow:IsShown() then
            lastSelectedChatFrame = dockWindow
            return dockWindow
        end
    end
    if SELECTED_DOCK_FRAME and SELECTED_DOCK_FRAME.editBox and SELECTED_DOCK_FRAME:IsShown() then
        lastSelectedChatFrame = SELECTED_DOCK_FRAME
        return SELECTED_DOCK_FRAME
    end
    if lastSelectedChatFrame and lastSelectedChatFrame.editBox and lastSelectedChatFrame:IsShown() then
        return lastSelectedChatFrame
    end
    if type(ChatEdit_GetLastActiveWindow) == "function" then
        local activeEditBox = ChatEdit_GetLastActiveWindow()
        local activeFrame = activeEditBox and activeEditBox:GetParent()
        if activeFrame and activeFrame.editBox and activeFrame:IsShown() then
            lastSelectedChatFrame = activeFrame
            return activeFrame
        end
    end
    return nil
end

function ns.GetChatFrameFromTab(chatFrame)
    if not chatFrame then
        return nil
    end
    if chatFrame.editBox then
        return chatFrame
    end
    if chatFrame.chatFrame and chatFrame.chatFrame.editBox then
        return chatFrame.chatFrame
    end
    local frameName = chatFrame:GetName()
    if not frameName then
        return nil
    end
    local chatFrameNum = frameName:match("ChatFrame(%d+)Tab")
    if not chatFrameNum then
        return nil
    end
    return _G["ChatFrame" .. chatFrameNum]
end

function ns.IsValidChatFrame(frame)
    return frame and frame.editBox and type(frame.GetName) == "function"
end

function ns.IsCombatLogFrame(frame)
    if not ns.IsValidChatFrame(frame) then
        return false
    end
    if frame.isCombatLog then
        return true
    end
    local windowName = ns.GetFrameWindowName(frame)
    if windowName and COMBAT_LOG then
        local normalizedWindowName = strlower(windowName:gsub("%s+", ""))
        local normalizedCombatLogName = strlower(COMBAT_LOG:gsub("%s+", ""))
        if normalizedWindowName == normalizedCombatLogName then
            return true
        end
    end
    return false
end

function ns.IsSelectableChatFrame(frame)
    if not ns.IsValidChatFrame(frame) then
        return false
    end
    local tab = _G[frame:GetName() .. "Tab"]
    if not tab then
        return false
    end
    return tab:IsShown() or frame:IsShown()
end

function ns.GetOrderedChatFrames(includeUnselectable)
    local orderedFrames = {}
    local seenFrames = {}

    local function AddFrame(candidate)
        local frame = ns.GetChatFrameFromTab(candidate)
        if not ns.IsValidChatFrame(frame) or seenFrames[frame] then
            return
        end
        if ns.IsCombatLogFrame(frame) then
            return
        end
        if not includeUnselectable and not ns.IsSelectableChatFrame(frame) then
            return
        end
        seenFrames[frame] = true
        orderedFrames[#orderedFrames + 1] = frame
    end

    if GENERAL_CHAT_DOCK then
        if type(FCFDock_GetChatFrames) == "function" then
            local dockFrames = FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)
            if type(dockFrames) == "table" then
                for _, frame in ipairs(dockFrames) do
                    AddFrame(frame)
                end
            end
        end
        if type(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) == "table" then
            for _, frame in ipairs(GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES) do
                AddFrame(frame)
            end
        end
    end

    if type(CHAT_FRAMES) == "table" then
        for _, frameName in ipairs(CHAT_FRAMES) do
            AddFrame(_G[frameName])
        end
    end

    return orderedFrames
end

function ns.SelectAdjacentChatFrame(currentFrame, direction)
    local chatFrames = ns.GetOrderedChatFrames(false)
    if #chatFrames < 2 then
        return nil
    end
    local selectedFrame = ns.GetChatFrameFromTab(currentFrame) or ns.GetSelectedChatFrame()
    local selectedIndex
    for index, frame in ipairs(chatFrames) do
        if frame == selectedFrame then
            selectedIndex = index
            break
        end
    end

    local step = direction == -1 and -1 or 1
    local nextIndex
    if selectedIndex then
        nextIndex = ((selectedIndex - 1 + step) % #chatFrames) + 1
    elseif step == -1 then
        nextIndex = #chatFrames
    else
        nextIndex = 1
    end

    local nextFrame = chatFrames[nextIndex]
    if not nextFrame then
        return nil
    end
    local nextTab = _G[nextFrame:GetName() .. "Tab"]
    if not nextTab then
        return nil
    end
    if type(FCF_Tab_OnClick) == "function" then
        FCF_Tab_OnClick(nextTab)
    elseif type(nextTab.Click) == "function" then
        nextTab:Click()
    else
        return nil
    end

    lastSelectedChatFrame = nextFrame
    return nextFrame
end
