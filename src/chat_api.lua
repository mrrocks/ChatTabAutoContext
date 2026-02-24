local _, ns = ...

function ns.OpenChat(text, frame)
    if type(ChatFrame_OpenChat) == "function" then
        ChatFrame_OpenChat(text, frame)
        return true
    end
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        ChatFrameUtil.OpenChat(text, frame)
        return true
    end
    return false
end

function ns.UpdateEditBoxHeader(editBox)
    if not editBox then
        return
    end
    if type(ChatEdit_UpdateHeader) == "function" then
        ChatEdit_UpdateHeader(editBox)
        return
    end
    if ChatFrameEditBoxMixin and type(ChatFrameEditBoxMixin.UpdateHeader) == "function" then
        ChatFrameEditBoxMixin.UpdateHeader(editBox)
    end
end

function ns.HookSecure(functionName, callback)
    if type(_G[functionName]) ~= "function" then
        return false
    end
    hooksecurefunc(functionName, callback)
    return true
end
