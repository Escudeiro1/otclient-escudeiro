local messageModeCallbacks = {}
-- Interceptors run before the normal callbacks; one returning true consumes the
-- message (e.g. game_looktooltip shows its own look replies as a tooltip instead
-- of in the console/status bar).
local messageInterceptors = {}

function g_game.onTextMessage(messageMode, message)
    for _, interceptor in ipairs(messageInterceptors) do
        if interceptor(messageMode, message) then
            return
        end
    end

    local callbacks = messageModeCallbacks[messageMode]
    if not callbacks or #callbacks == 0 then
        perror(string.format('Unhandled onTextMessage message mode %i: %s', messageMode, message))
        return
    end

    for _, callback in pairs(callbacks) do
        callback(messageMode, message)
    end
end

function registerMessageMode(messageMode, callback)
    if not messageModeCallbacks[messageMode] then
        messageModeCallbacks[messageMode] = {}
    end

    table.insert(messageModeCallbacks[messageMode], callback)
    return true
end

function registerMessageInterceptor(interceptor)
    if not table.find(messageInterceptors, interceptor) then
        table.insert(messageInterceptors, interceptor)
    end
end

function unregisterMessageInterceptor(interceptor)
    return table.removevalue(messageInterceptors, interceptor)
end

function unregisterMessageMode(messageMode, callback)
    if not messageModeCallbacks[messageMode] then
        return false
    end

    return table.removevalue(messageModeCallbacks[messageMode], callback)
end
