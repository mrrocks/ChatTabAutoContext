local _, ns = ...

local PREFIX = "|cff00ccff[CTAC]|r "

local function Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    print(PREFIX .. table.concat(parts, " "))
end

local function FrameName(frame)
    if not frame then return "nil" end
    return frame.GetName and frame:GetName() or "?"
end

local function FormatChatResult(chatType, channelTarget)
    if chatType == "CHANNEL" and channelTarget then
        return "CH/" .. tostring(channelTarget)
    end
    return chatType or "?"
end

function ns.DebugTab(source, target, chatType, channelTarget)
    Print("TAB", FrameName(source), "->", FrameName(target), "=", FormatChatResult(chatType, channelTarget))
end

function ns.DebugEnter(frame, chatType, channelTarget)
    Print("ENTER", FrameName(frame), "=", FormatChatResult(chatType, channelTarget))
end

function ns.DebugCycle(orderedNames)
    Print("CYCLE [" .. table.concat(orderedNames, " > ") .. "]")
end
