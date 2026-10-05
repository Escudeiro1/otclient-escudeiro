local iconTopMenu = nil
-- @ Minimap
local minimapWidget = nil -- bot fix
local otmm = true
local oldPos = nil
local fullscreenWidget
-- The minimap's frame (with the Minimap widget inside). Kept as a direct reference
-- because "large map" mode moves it out of mapController.ui into largeMapPanel.
local minimapBorderWidget = nil
local largeMapPanel = nil
local largeMapActive = false
local virtualFloor = 7
local currentDayTime = {
    h = 12,
    m = 0
}

local function refreshVirtualFloors()
    mapController.ui.layersPanel.layersMark:setMarginTop(((virtualFloor + 1) * 4) - 3)
    mapController.ui.layersPanel.automapLayers:setImageClip((virtualFloor * 14) .. ' 0 14 67')
    -- Every floor change (walking, floor buttons, reset) passes here; keep the large
    -- map's Surface View / full map in sync with the floor being shown.
    updateMinimapViewMode()
end

local function onPositionChange()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local pos = player:getPosition()
    if not pos then
        return
    end

    local minimapWidget = minimapBorderWidget.minimap
    if not (minimapWidget) or minimapWidget:isDragging() then
        return
    end

    if not minimapWidget.fullMapView then
        minimapWidget:setCameraPosition(pos)
    end

    minimapWidget:setCrossPosition(pos)
    virtualFloor = pos.z
    refreshVirtualFloors()
end

mapController = Controller:new()
mapController:setUI('minimap', modules.game_interface.getMainRightPanel())

function onChangeWorldTime(hour, minute)
--[[ 

check 
tfs c++ (old) : void ProtocolGame::sendWorldTime()
tfs lua (new) : function Player.sendWorldTime(self, time)
Canary: void ProtocolGame::sendTibiaTime(int32_t time)
 ]]

    currentDayTime = {
        h = hour % 24,
        m = minute
    }

    mapController:scheduleEvent(function()
        local nextH = currentDayTime.h
        local nextM = currentDayTime.m + 12
        if nextM >= 60 then
            nextH = nextH + 1
            nextM = nextM - 60
        end

        onChangeWorldTime(nextH, nextM)
    end, 30000, 'dayTime')

    local position = math.floor((124 / (24 * 60)) * ((hour * 60) + minute))
    local mainWidth = 31
    local secondaryWidth = 0

    if (position + 31) >= 124 then
        secondaryWidth = ((position + 31) - 124) + 1
        mainWidth = 31 - secondaryWidth
    end

    mapController.ui.rosePanel.ambients.main:setWidth(mainWidth)
    mapController.ui.rosePanel.ambients.secondary:setWidth(secondaryWidth)

    if secondaryWidth == 0 then
        mapController.ui.rosePanel.ambients.secondary:hide()
    else
        mapController.ui.rosePanel.ambients.secondary:setImageClip('0 0 ' .. secondaryWidth .. ' 31')
        mapController.ui.rosePanel.ambients.secondary:show()
    end

    if mainWidth == 0 then
        mapController.ui.rosePanel.ambients.main:hide()
    else
        mapController.ui.rosePanel.ambients.main:setImageClip(position .. ' 0 ' .. mainWidth .. ' 31')
        mapController.ui.rosePanel.ambients.main:show()
    end
end

function mapController:onInit()
    minimapBorderWidget = self.ui.minimapBorder
    minimapBorderWidget.minimap:getChildById('floorUpButton'):hide()
    minimapBorderWidget.minimap:getChildById('floorDownButton'):hide()
    minimapBorderWidget.minimap:getChildById('zoomInButton'):hide()
    minimapBorderWidget.minimap:getChildById('zoomOutButton'):hide()
    minimapBorderWidget.minimap:getChildById('resetButton'):hide()
end

function mapController:onGameStart()
    mapController:registerEvents(g_game, {
        onChangeWorldTime = onChangeWorldTime
    })

    mapController:registerEvents(LocalPlayer, {
        onPositionChange = onPositionChange
    }):execute()

    -- Load Map
    g_minimap.clean()

    local minimapFile = '/minimap'
    local loadFnc = nil

    if otmm then
        minimapFile = minimapFile .. '.otmm'
        loadFnc = g_minimap.loadOtmm
    else
        minimapFile = minimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'
        loadFnc = g_map.loadOtcm
    end

    if g_resources.fileExists(minimapFile) then
        loadFnc(minimapFile)
    end

    minimapBorderWidget.minimap:load()
    updateLargeMap()
end

function mapController:onGameEnd()
    -- Save Map
    if otmm then
        g_minimap.saveOtmm('/minimap.otmm')
    else
        g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
    end

    minimapBorderWidget.minimap:save()
end

function mapController:onTerminate()
    setLargeMap(false)
    if largeMapPanel then
        largeMapPanel:destroy()
        largeMapPanel = nil
    end
    if iconTopMenu then
        iconTopMenu:destroy()
        iconTopMenu = nil
    end
end

function zoomIn()
    minimapBorderWidget.minimap:zoomIn()
end

function zoomOut()
    minimapBorderWidget.minimap:zoomOut()
end

function openCyclopediaMap()
    if g_game.getClientVersion() >= 1310 then
        modules.game_cyclopedia.toggle('map')
    else
        return fullscreen()
    end
end

function fullscreen()
    local minimapWidget = minimapBorderWidget.minimap
    if not minimapWidget then
        minimapWidget = fullscreenWidget
    end
    local zoom;

    if not minimapWidget then
        return
    end

    if minimapWidget.fullMapView then
        fullscreenWidget = nil
        minimapWidget:setParent(minimapBorderWidget)
        minimapWidget:fill('parent')
        mapController.ui:show()
        zoom = minimapWidget.zoomMinimap
        g_keyboard.unbindKeyDown('Escape')
        minimapWidget.fullMapView = false
    else
        fullscreenWidget = minimapWidget
        mapController.ui:hide(true)
        minimapWidget:setParent(modules.game_interface.getRootPanel())
        minimapWidget:fill('parent')
        zoom = minimapWidget.zoomFullmap
        g_keyboard.bindKeyDown('Escape', fullscreen)
        minimapWidget.fullMapView = true
    end

    local pos = oldPos or minimapWidget:getCameraPosition()
    oldPos = minimapWidget:getCameraPosition()
    minimapWidget:setZoom(zoom)
    minimapWidget:setCameraPosition(pos)
end

function upLayer()
    if virtualFloor == 0 then
        return
    end

    minimapBorderWidget.minimap:floorUp(1)
    virtualFloor = virtualFloor - 1
    refreshVirtualFloors()
end

function downLayer()
    if virtualFloor == 15 then
        return
    end

    minimapBorderWidget.minimap:floorDown(1)
    virtualFloor = virtualFloor + 1
    refreshVirtualFloors()
end

function onClickRoseButton(dir)
    if dir == 'north' then
        minimapBorderWidget.minimap:move(0, 1)
    elseif dir == 'north-east' then
        minimapBorderWidget.minimap:move(-1, 1)
    elseif dir == 'east' then
        minimapBorderWidget.minimap:move(-1, 0)
    elseif dir == 'south-east' then
        minimapBorderWidget.minimap:move(-1, -1)
    elseif dir == 'south' then
        minimapBorderWidget.minimap:move(0, -1)
    elseif dir == 'south-west' then
        minimapBorderWidget.minimap:move(1, -1)
    elseif dir == 'west' then
        minimapBorderWidget.minimap:move(1, 0)
    elseif dir == 'north-west' then
        minimapBorderWidget.minimap:move(1, 1)
    end
end

function resetMap()
    minimapBorderWidget.minimap:reset()
    local player = g_game.getLocalPlayer()
    if player then
        virtualFloor = player:getPosition().z
        refreshVirtualFloors()
    end
end

function getMiniMapUi()
    return minimapBorderWidget.minimap
end

function extendedView(extendedView)
    if extendedView then
        if not iconTopMenu then
            iconTopMenu = modules.client_topmenu.addTopRightToggleButton('miniMap', tr('Show miniMap'),
                '/images/topbuttons/minimap', toggle)
            iconTopMenu:setOn(mapController.ui:isVisible())
            mapController.ui:setBorderColor('black')
            mapController.ui:setBorderWidth(2)
        end
    else
        if iconTopMenu then
            iconTopMenu:destroy()
            iconTopMenu = nil
        end
        mapController.ui:setBorderColor('alpha')
        mapController.ui:setBorderWidth(0)
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if not mainRightPanel:hasChild(mapController.ui) then
            mainRightPanel:insertChild(1, mapController.ui)
        end
        mapController.ui:show()

    end
    mapController.ui.moveOnlyToMain = not extendedView
end

function toggle()
    if iconTopMenu:isOn() then
        mapController.ui:hide()
        iconTopMenu:setOn(false)
    else
        mapController.ui:show()
        iconTopMenu:setOn(true)
    end
end

-- ---------------------------------------------------------------------------
-- "Use large map when there is available space" (Options -> Interface).
-- With both right columns open, the minimap moves into largeMapPanel spanning
-- the top of both columns, and its tools (compass, zoom, full map, floors) are
-- laid out in a row in the shorter top-right panel. Otherwise the normal layout.
-- ---------------------------------------------------------------------------
local NORMAL_PANEL_HEIGHT = 116  -- mainmappanel height in the normal layout (otui)
local LARGE_TOOLS_HEIGHT = 54    -- mainmappanel height holding only the tools row (compass 43 + margins)
local LARGE_MAP_HEIGHT = 245     -- height of the minimap frame in large mode
local LARGE_PANEL_PADDING = 5    -- space between largeMapPanel's border and the map

local function setAnchors(widget, anchors, margins)
    widget:breakAnchors()
    for _, a in ipairs(anchors) do
        widget:addAnchor(a[1], a[2], a[3])
    end
    widget:setMarginTop(margins.top or 0)
    widget:setMarginRight(margins.right or 0)
    widget:setMarginBottom(margins.bottom or 0)
    widget:setMarginLeft(margins.left or 0)
end

-- In large mode the floor bar (layersPanel, 20x68) is drawn rotated so it lies
-- horizontally next to the full map button: clockwise, the top floor ends up on the
-- right and the marker below the bar, pointing up. Rotation only affects drawing,
-- so the panel is made click-through and two flat click areas replace its buttons.
local LAYERS_ROTATION = 90
local LAYERS_W, LAYERS_H = 20, 68 -- layersPanel's real (unrotated) size
local LAYERS_TOP = 16             -- top of the horizontal bar inside mainmappanel
local LAYERS_RIGHT = 5            -- gap between the horizontal bar and the panel's right edge
local layerClickUp = nil
local layerClickDown = nil

-- Normal mode: the panel and its parts take clicks as in minimap.otui.
-- Large (rotated) mode: all of them are click-through.
local function setLayersPanelClickable(clickable)
    local layersPanel = mapController.ui.layersPanel
    layersPanel:setPhantom(not clickable)
    for _, child in ipairs(layersPanel:getChildren()) do
        child:setPhantom(not clickable)
    end
end

local function getLayerClickAreas()
    if not layerClickUp then
        local ui = mapController.ui
        local half = LAYERS_H / 2
        -- Clockwise (+90) puts the bar's top half (floor up) on the right; -90 on the left.
        local upOnRight = LAYERS_ROTATION > 0
        local function createClickArea(onRight, callback)
            local area = g_ui.createWidget('UIWidget', ui)
            area:setSize({ width = half, height = LAYERS_W })
            area:addAnchor(AnchorTop, 'parent', AnchorTop)
            area:addAnchor(AnchorRight, 'parent', AnchorRight)
            area:setMarginTop(LAYERS_TOP)
            area:setMarginRight(onRight and LAYERS_RIGHT or (LAYERS_RIGHT + half))
            area.onClick = callback
            return area
        end
        layerClickUp = createClickArea(upOnRight, function() upLayer() end)
        layerClickDown = createClickArea(not upOnRight, function() downLayer() end)
    end
    return layerClickUp, layerClickDown
end

local function setLayersHorizontal(horizontal)
    local layersPanel = mapController.ui.layersPanel
    local up, down = getLayerClickAreas()
    if horizontal then
        -- The rotated drawing is centred on the real rect: place the real rect so its
        -- centre is the centre of the wanted horizontal band (LAYERS_H x LAYERS_W).
        setAnchors(layersPanel, { { AnchorTop, 'parent', AnchorTop }, { AnchorRight, 'parent', AnchorRight } },
            { top = LAYERS_TOP + LAYERS_W / 2 - LAYERS_H / 2,
              right = LAYERS_RIGHT + LAYERS_H / 2 - LAYERS_W / 2 })
        layersPanel:setRotation(LAYERS_ROTATION)
        setLayersPanelClickable(false)
        up:show()
        down:show()
    else
        setAnchors(layersPanel, { { AnchorBottom, 'parent', AnchorBottom }, { AnchorRight, 'parent', AnchorRight } },
            { right = 7 })
        layersPanel:setRotation(0)
        setLayersPanelClickable(true)
        up:hide()
        down:hide()
    end
end

local function canUseLargeMap()
    local extraPanel = modules.game_interface.getRightExtraPanel()
    return modules.client_options.getOption('largeMapWhenSpace') == true
        and g_game.isOnline()
        and extraPanel and extraPanel:isOn() and extraPanel:isVisible()
        and mapController.ui:getParent() == modules.game_interface.getMainRightPanel()
        and not (minimapBorderWidget.minimap and minimapBorderWidget.minimap.fullMapView)
end

local function getLargeMapPanel()
    if not largeMapPanel then
        largeMapPanel = g_ui.createWidget('UIWidget', modules.game_interface.getRootPanel())
        largeMapPanel:setId('largeMinimapPanel')
        largeMapPanel:setImageSource('/images/ui/2pixel_up_frame_borderimage')
        largeMapPanel:setImageBorder(4)
        largeMapPanel:setFocusable(false)
        largeMapPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
        largeMapPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    end
    return largeMapPanel
end

function setLargeMap(large)
    if large == largeMapActive or not minimapBorderWidget then
        return
    end
    largeMapActive = large

    local ui = mapController.ui
    local mainRightPanel = modules.game_interface.getMainRightPanel()
    local rightExtraPanel = modules.game_interface.getRightExtraPanel()

    if large then
        -- Both right columns plus the 1px gap between them.
        local panel = getLargeMapPanel()
        panel:setSize({
            width = modules.game_interface.getRightPanel():getWidth() + 1 + rightExtraPanel:getWidth(),
            height = LARGE_MAP_HEIGHT + 2 * LARGE_PANEL_PADDING
        })
        panel:show()

        minimapBorderWidget:setParent(panel)
        setAnchors(minimapBorderWidget, {
            { AnchorTop, 'parent', AnchorTop }, { AnchorBottom, 'parent', AnchorBottom },
            { AnchorLeft, 'parent', AnchorLeft }, { AnchorRight, 'parent', AnchorRight }
        }, { top = LARGE_PANEL_PADDING, right = LARGE_PANEL_PADDING, bottom = LARGE_PANEL_PADDING,
             left = LARGE_PANEL_PADDING })

        -- Tools in a row: compass, zoom out/in stacked, full map; floor bar stays right.
        setAnchors(ui.rosePanel, { { AnchorTop, 'parent', AnchorTop }, { AnchorLeft, 'parent', AnchorLeft } },
            { top = 5, left = 8 })
        setAnchors(ui.zoomOut, { { AnchorTop, 'rosePanel', AnchorTop }, { AnchorLeft, 'rosePanel', AnchorRight } },
            { left = 6 })
        setAnchors(ui.zoomIn, { { AnchorTop, 'zoomOut', AnchorBottom }, { AnchorLeft, 'zoomOut', AnchorLeft } },
            { top = 2 })
        setAnchors(ui.fullMap, { { AnchorTop, 'zoomOut', AnchorTop }, { AnchorLeft, 'zoomOut', AnchorRight } },
            { left = 4 })

        setLayersHorizontal(true)
        -- HD toggle under the full map button, on the zoom in row.
        setAnchors(ui.hdButton, { { AnchorTop, 'zoomIn', AnchorTop }, { AnchorLeft, 'fullMap', AnchorLeft } }, {})
        ui.hdButton:show()
        updateHdButtonGlow()

        mainRightPanel:addAnchor(AnchorTop, 'largeMinimapPanel', AnchorBottom)
        rightExtraPanel:addAnchor(AnchorTop, 'largeMinimapPanel', AnchorBottom)
        ui.panelHeight = LARGE_TOOLS_HEIGHT
    else
        -- Back to the layout from minimap.otui.
        minimapBorderWidget:setParent(ui)
        -- Back to its place in minimap.otui: right before layersPanel. Not index 1 --
        -- the PhantomMiniWindow style's own children (its 60% background image, top
        -- bar, close button) come first, and the background would cover the map.
        ui:moveChildToIndex(minimapBorderWidget, ui:getChildIndex(ui.layersPanel))
        setAnchors(minimapBorderWidget, { { AnchorTop, 'parent', AnchorTop }, { AnchorLeft, 'parent', AnchorLeft } },
            { top = 5, left = 8 })
        minimapBorderWidget:setSize({ width = 115, height = 111 })

        setAnchors(ui.rosePanel, { { AnchorTop, 'minimapBorder', AnchorTop }, { AnchorRight, 'layersPanel', AnchorRight } }, {})
        setAnchors(ui.fullMap, { { AnchorRight, 'layersPanel', AnchorLeft }, { AnchorBottom, 'minimapBorder', AnchorBottom } },
            { right = 4 })
        setAnchors(ui.zoomIn, { { AnchorRight, 'fullMap', AnchorRight }, { AnchorBottom, 'fullMap', AnchorTop } },
            { bottom = 2 })
        setAnchors(ui.zoomOut, { { AnchorRight, 'fullMap', AnchorRight }, { AnchorBottom, 'zoomIn', AnchorTop } },
            { bottom = 2 })
        setLayersHorizontal(false)
        ui.hdButton:hide()

        mainRightPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
        rightExtraPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
        if largeMapPanel then
            largeMapPanel:hide()
        end
        ui.panelHeight = NORMAL_PANEL_HEIGHT
    end

    -- Large map: full static map + Surface View (see updateMinimapViewMode).
    local minimap = minimapBorderWidget.minimap
    if minimap then
        minimap:setUseStaticMinimap(large and isHdMinimap())
        minimap:setFloorSeparatorOpacity(1.0)
    end
    updateMinimapViewMode()

    if modules.game_mainpanel and modules.game_mainpanel.reloadMainPanelSizes then
        modules.game_mainpanel.reloadMainPanelSizes()
    end
end

-- Called on game start and whenever the option, the second right column or the
-- view mode changes.
function updateLargeMap()
    if not mapController.ui or not minimapBorderWidget then
        return
    end
    setLargeMap(canUseLargeMap())
end

-- Large map look, as in the Cyclopedia / big map (Ctrl+Alt+M): Surface View
-- (satellite images) on floors 0-7 and the full static map (whole world, not only
-- explored tiles) elsewhere. The normal small minimap keeps the explored map.
local SURFACE_FLOOR = 7

-- g_satelliteMap is shared with the Cyclopedia and the big map (the Cyclopedia
-- clears it when its map tab opens), so check what's loaded instead of remembering
-- it. Both checks are cheap lookups, and loadFloors skips anything already loaded.
local function ensureSatelliteFloor(floor)
    local needsSurface = floor <= SURFACE_FLOOR and not g_satelliteMap.hasChunksForView(floor)
    local needsStatic = not g_satelliteMap.hasMinimapChunksForFloor(floor)
    if needsSurface or needsStatic then
        local assetsDir = string.format('/data/things/%d', g_game.getClientVersion())
        g_satelliteMap.loadFloors(assetsDir, floor, math.max(floor, SURFACE_FLOOR))
    end
end

function updateMinimapViewMode()
    local minimap = minimapBorderWidget and minimapBorderWidget.minimap
    if not minimap then
        return
    end

    if largeMapActive and isHdMinimap() then
        ensureSatelliteFloor(virtualFloor)
        minimap:setSatelliteMode(virtualFloor <= SURFACE_FLOOR and g_satelliteMap.hasChunksForView(virtualFloor))
    else
        minimap:setSatelliteMode(false)
    end
end

-- HD toggle for the large map: HD = Surface View + full static map, otherwise the
-- standard explored map. Saved per client; on by default.
local HD_SETTING = 'largeMinimapHD'

function isHdMinimap()
    local value = g_settings.get(HD_SETTING)
    return value == '' or g_settings.getBoolean(HD_SETTING)
end

function updateHdButtonGlow()
    local button = mapController.ui and mapController.ui.hdButton
    if button then
        local hd = isHdMinimap()
        button.brightButton:setVisible(hd)
        button.highlight:setVisible(hd)
    end
end

function toggleHdMinimap()
    g_settings.set(HD_SETTING, not isHdMinimap())
    local minimap = minimapBorderWidget and minimapBorderWidget.minimap
    if minimap then
        minimap:setUseStaticMinimap(largeMapActive and isHdMinimap())
    end
    updateMinimapViewMode()
    updateHdButtonGlow()
end
