-- Option "Use tooltip to look at items in your inventory": resting the mouse on an item
-- in an equipment slot or any container window for HOVER_DELAY sends a normal look
-- request, and the server's "You see..." reply is shown as a tooltip instead of in the
-- console/status bar. Items in the game window itself, and empty slots, are ignored.

local HOVER_DELAY = 1000     -- ms the mouse must rest on the item before looking
local REPLY_TIMEOUT = 3000   -- ms after the request a look reply is still taken as ours
local MAX_LINE_LENGTH = 60   -- the tooltip label doesn't wrap, so wrap the text here
local INVENTORY_X = 0xffff   -- item positions with this x are equipment slots or containers

local hoveredWidget = nil    -- item widget the mouse is resting on
local hoverEvent = nil       -- pending HOVER_DELAY timer
local pendingLook = nil      -- { widget, time } of the look request awaiting its reply
local showingTooltip = false -- whether this module is currently showing g_tooltip

local function isEnabled()
    return modules.client_options and modules.client_options.getOption('lookTooltipInInventory') == true
end

-- Real items shown in an equipment slot or container window. Map items aren't UIItem
-- widgets; store/market/trade/analyser previews are virtual or have no inventory position.
local function isInterfaceItem(widget)
    if widget:isVirtual() or widget:isDestroyed() then
        return false
    end
    local item = widget:getItem()
    if not item then
        return false -- empty slot
    end
    local pos = item:getPosition()
    return pos ~= nil and pos.x == INVENTORY_X
end

local function wrapText(text)
    local wrapped = {}
    for paragraph in (text .. '\n'):gmatch('(.-)\n') do
        local line = ''
        for word in paragraph:gmatch('%S+') do
            if line ~= '' and #line + 1 + #word > MAX_LINE_LENGTH then
                table.insert(wrapped, line)
                line = word
            else
                line = (line == '') and word or (line .. ' ' .. word)
            end
        end
        table.insert(wrapped, line)
    end
    return table.concat(wrapped, '\n')
end

local function hideTooltip()
    if showingTooltip then
        g_tooltip.hide()
        showingTooltip = false
    end
end

local function cancelHover()
    if hoverEvent then
        removeEvent(hoverEvent)
        hoverEvent = nil
    end
    hoveredWidget = nil
    hideTooltip()
end

local function requestLook()
    hoverEvent = nil
    local widget = hoveredWidget
    if not widget or not isEnabled() or g_mouse.isPressed() or not widget:isHovered()
        or not isInterfaceItem(widget) then
        return
    end
    pendingLook = { widget = widget, time = g_clock.millis() }
    g_game.look(widget:getItem())
end

local function onItemHoverChange(widget, hovered)
    if hovered then
        if not isEnabled() or g_mouse.isPressed() or not isInterfaceItem(widget) then
            return
        end
        cancelHover()
        hoveredWidget = widget
        hoverEvent = scheduleEvent(requestLook, HOVER_DELAY)
    elseif widget == hoveredWidget then
        cancelHover()
    end
end

-- Claims the look reply to our own request so it doesn't reach the console/status bar.
local function onTextMessage(mode, text)
    if mode ~= MessageModes.Look or not pendingLook then
        return false
    end

    local look = pendingLook
    pendingLook = nil
    if g_clock.millis() - look.time > REPLY_TIMEOUT then
        return false -- too old to be ours; let it through normally
    end

    -- Still resting on that item: show it. Otherwise just drop it silently.
    local widget = look.widget
    if widget == hoveredWidget and not widget:isDestroyed() and widget:isHovered() then
        g_tooltip.display(wrapText(text))
        showingTooltip = true
    end
    return true
end

local function onGameEnd()
    cancelHover()
    pendingLook = nil
end

function init()
    connect(UIItem, { onHoverChange = onItemHoverChange })
    connect(g_game, { onGameEnd = onGameEnd })
    registerMessageInterceptor(onTextMessage)
end

function terminate()
    disconnect(UIItem, { onHoverChange = onItemHoverChange })
    disconnect(g_game, { onGameEnd = onGameEnd })
    unregisterMessageInterceptor(onTextMessage)
    cancelHover()
    pendingLook = nil
end
