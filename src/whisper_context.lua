local _, ns = ...

local whisperTypes = {
    BN_WHISPER = true,
    BN_WHISPER_INFORM = true,
    WHISPER = true,
    WHISPER_INFORM = true
}

local whisperEvents = {
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true
}

local whisperEventToType = {
    CHAT_MSG_BN_WHISPER = "BN_WHISPER",
    CHAT_MSG_BN_WHISPER_INFORM = "BN_WHISPER",
    CHAT_MSG_WHISPER = "WHISPER",
    CHAT_MSG_WHISPER_INFORM = "WHISPER"
}

local whisperUpdateDelaySeconds = 0.1
local frameWhisperState = setmetatable({}, { __mode = "k" })
local lastWhisperTargetByType = {}

ns.whisperEvents = whisperEvents

function ns.NormalizeWhisperType(chatType)
    if chatType == "BN_WHISPER" or chatType == "BN_WHISPER_INFORM" then
        return "BN_WHISPER"
    end
    if chatType == "WHISPER" or chatType == "WHISPER_INFORM" then
        return "WHISPER"
    end
    return nil
end

function ns.IsWhisperType(chatType)
    return ns.NormalizeWhisperType(chatType) ~= nil and whisperTypes[chatType] == true
end

function ns.UpdateWhisperState(frame, chatType, target)
    local whisperType = ns.NormalizeWhisperType(chatType)
    if not whisperType then
        return
    end

    local resolvedTarget = target
    if (not resolvedTarget or resolvedTarget == "") and frame and frame.chatTarget and frame.chatTarget ~= "" then
        resolvedTarget = frame.chatTarget
    end
    if not resolvedTarget or resolvedTarget == "" then
        return
    end

    if frame then
        frameWhisperState[frame] = {
            chatType = whisperType,
            target = resolvedTarget
        }
    end
    lastWhisperTargetByType[whisperType] = resolvedTarget
end

function ns.GetLastTellTargetForType(whisperType)
    if type(ChatEdit_GetLastTellTarget) ~= "function" then
        return nil
    end
    local target, chatType = ChatEdit_GetLastTellTarget()
    if not target then
        return nil
    end
    if ns.NormalizeWhisperType(chatType) ~= whisperType then
        return nil
    end
    return target
end

function ns.ResolveWhisperContext(frame)
    local selectedFrame = frame or ns.GetSelectedChatFrame()
    if not selectedFrame or not selectedFrame.editBox then
        return nil
    end

    local whisperType = ns.NormalizeWhisperType(selectedFrame.chatType)
    if not whisperType then
        return nil
    end

    local editBox = selectedFrame.editBox
    local target = selectedFrame.chatTarget

    if not target or target == "" then
        local frameState = frameWhisperState[selectedFrame]
        if frameState and frameState.chatType == whisperType then
            target = frameState.target
        end
    end
    if not target or target == "" then
        local editTarget = editBox:GetAttribute("tellTarget")
        if editTarget and editTarget ~= "" then
            target = editTarget
        end
    end
    if (not target or target == "") and whisperType == "WHISPER" then
        local frameName = selectedFrame.name
        if frameName and frameName ~= "" then
            target = frameName
        end
    end
    if not target or target == "" then
        target = lastWhisperTargetByType[whisperType]
    end
    if not target or target == "" then
        target = ns.GetLastTellTargetForType(whisperType)
    end

    return selectedFrame, editBox, whisperType, target
end

function ns.SetWhisperTarget(frame, activateChat, pendingText)
    local selectedFrame, editBox, whisperType, target = ns.ResolveWhisperContext(frame)
    if not selectedFrame or not editBox or not whisperType then
        return
    end

    if target and target ~= "" then
        editBox:SetAttribute("chatType", whisperType)
        editBox:SetAttribute("tellTarget", target)
        selectedFrame.chatTarget = target
        ns.UpdateWhisperState(selectedFrame, whisperType, target)
        ns.UpdateEditBoxHeader(editBox)
    end

    if activateChat then
        local chatText = pendingText or ""
        if not ns.OpenChat(chatText, selectedFrame) then
            ChatEdit_ActivateChat(editBox)
            if pendingText then
                editBox:SetText(pendingText)
            end
        end
    end
end

function ns.ScheduleWhisperTarget(frame, activateChat)
    C_Timer.After(whisperUpdateDelaySeconds, function()
        ns.SetWhisperTarget(frame, activateChat)
    end)
end

function ns.TrackWhisperEvent(event, ...)
    local whisperType = whisperEventToType[event]
    if not whisperType then
        return
    end
    local target = select(2, ...)
    if not target or target == "" then
        return
    end
    lastWhisperTargetByType[whisperType] = target
end
