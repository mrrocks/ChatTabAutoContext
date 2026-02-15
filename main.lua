local _, ns = ...

local existingFrame = _G.ChatContext
if existingFrame and existingFrame.GetObjectType and existingFrame:GetObjectType() == "Frame" then
    ns.eventFrame = existingFrame
else
    ns.eventFrame = CreateFrame("Frame", "ChatContext", UIParent)
end
