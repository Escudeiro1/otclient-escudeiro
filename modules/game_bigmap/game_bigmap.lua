-- Floating big map: a Cyclopedia-sized map that keeps following the player.
-- Uses the Cyclopedia's look: Surface View (satellite images) on surface floors
-- and the full static map (whole world, not only explored tiles) underground.

local HOTKEY = 'Ctrl+Alt+M'
local KEYBIND_NAME = 'show/hide Big Map'
local SURFACE_FLOOR = 7 -- Surface View exists for floors 0-7 only

local bigMapWindow = nil
local minimap = nil
local currentFloor = nil

local function getAssetsDir()
    return string.format('/data/things/%d', g_game.getClientVersion())
end

-- Make sure the satellite/static map images for this floor are loaded.
-- g_satelliteMap is shared with the Cyclopedia (which clears it when its map tab
-- opens), so check what's actually loaded instead of remembering it. Both checks
-- are cheap lookups, and loadFloors skips anything already loaded.
local function ensureFloorLoaded(floor)
    local needsSurface = floor <= SURFACE_FLOOR and not g_satelliteMap.hasChunksForView(floor)
    local needsStatic = not g_satelliteMap.hasMinimapChunksForFloor(floor)
    if needsSurface or needsStatic then
        -- Surface View composites [floor, 7]; underground only needs the floor itself.
        g_satelliteMap.loadFloors(getAssetsDir(), floor, math.max(floor, SURFACE_FLOOR))
    end
end

-- Surface View where satellite images exist, full static map everywhere else.
local function updateViewMode(floor)
    minimap:setSatelliteMode(floor <= SURFACE_FLOOR and g_satelliteMap.hasChunksForView(floor))
end

local function followPlayer()
    if not bigMapWindow or not bigMapWindow:isVisible() then
        return
    end

    local player = g_game.getLocalPlayer()
    local pos = player and player:getPosition()
    if not pos then
        return
    end

    ensureFloorLoaded(pos.z)
    if pos.z ~= currentFloor then
        currentFloor = pos.z
        updateViewMode(pos.z)
    end

    -- While the player is dragging the map around, don't yank it back.
    if not minimap:isDragging() then
        minimap:setCameraPosition(pos)
    end
    minimap:setCrossPosition(pos)
end

function show()
    if not bigMapWindow or not g_game.isOnline() then
        return
    end
    bigMapWindow:show()
    bigMapWindow:raise() -- no focus(): keyboard input stays with the game
    currentFloor = nil -- re-evaluate the view mode on open
    followPlayer()
end

function hide()
    if bigMapWindow then
        bigMapWindow:hide()
    end
end

function toggle()
    if bigMapWindow and bigMapWindow:isVisible() then
        hide()
    else
        show()
    end
end

function init()
    bigMapWindow = g_ui.displayUI('game_bigmap')
    bigMapWindow:hide()
    minimap = bigMapWindow:recursiveGetChildById('minimap')
    minimap:setUseStaticMinimap(true)
    minimap:setFloorSeparatorOpacity(1.0)

    connect(LocalPlayer, { onPositionChange = followPlayer })
    connect(g_game, { onGameEnd = hide })

    Keybind.new('Windows', KEYBIND_NAME, HOTKEY, '')
    Keybind.bind('Windows', KEYBIND_NAME, {
        {
            type = KEY_DOWN,
            callback = toggle,
        }
    })
end

function terminate()
    Keybind.delete('Windows', KEYBIND_NAME)
    disconnect(LocalPlayer, { onPositionChange = followPlayer })
    disconnect(g_game, { onGameEnd = hide })

    if bigMapWindow then
        bigMapWindow:destroy()
        bigMapWindow = nil
    end
    minimap = nil
    currentFloor = nil
end
