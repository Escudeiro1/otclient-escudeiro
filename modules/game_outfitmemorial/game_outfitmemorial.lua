-- Outfit Memorial: shown when using the memorial shrine. The server sends who owns
-- each stage of the golden and royal outfits (protocol 12.15+, opcode 0xB0, parsed in
-- ProtocolGame::parseOutfitMemorial) and this window lists them with their prices.

local STAGES = {
    golden = { tr('Golden Outfit'), tr('With Golden Helmet'), tr('Full Golden Outfit') },
    royal = { tr('Royal Costume'), tr('With First Addon'), tr('Full Royal Costume') },
}

local memorialWindow = nil
local columns = {}
local data = nil      -- last memorial data received from the server
local currentTab = 'golden'

local function formatNumber(n)
    local s = tostring(n)
    local formatted = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (formatted:gsub('^,', ''))
end

local function fillColumn(column, title, priceText, owners)
    column.title:setText(title)
    column.price:setText(priceText)

    local list = column.owners
    list:destroyChildren()
    if not owners or #owners == 0 then
        local label = g_ui.createWidget('MemorialOwnerLabel', list)
        label:setText(tr('No one yet.'))
        label:setColor('#808080')
        return
    end

    local sorted = table.copy(owners)
    table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
    for _, name in ipairs(sorted) do
        local label = g_ui.createWidget('MemorialOwnerLabel', list)
        label:setText(name)
    end
end

local function refresh()
    if not memorialWindow or not data then
        return
    end

    -- TabButton marks the selected tab with the 'on' state.
    memorialWindow.goldenTab:setOn(currentTab == 'golden')
    memorialWindow.royalTab:setOn(currentTab == 'royal')

    for i = 1, 3 do
        local priceText
        local owners
        if currentTab == 'golden' then
            priceText = formatNumber(data.goldenPrices[i] or 0) .. ' ' .. tr('gold')
            owners = data.goldenOwners[i]
        else
            priceText = string.format('%s %s / %s %s',
                formatNumber(data.royalSilverPrices[i] or 0), tr('silver'),
                formatNumber(data.royalGoldenPrices[i] or 0), tr('golden tokens'))
            owners = data.royalOwners[i]
        end
        fillColumn(columns[i], STAGES[currentTab][i], priceText, owners)
    end
end

function showTab(tab)
    currentTab = tab
    refresh()
end

function hide()
    if memorialWindow then
        memorialWindow:hide()
    end
end

local function onOutfitMemorial(goldenPrices, goldenOwners, royalSilverPrices, royalGoldenPrices, royalOwners)
    data = {
        goldenPrices = goldenPrices or {},
        goldenOwners = goldenOwners or {},
        royalSilverPrices = royalSilverPrices or {},
        royalGoldenPrices = royalGoldenPrices or {},
        royalOwners = royalOwners or {},
    }
    refresh()
    memorialWindow:show()
    memorialWindow:raise()
    memorialWindow:focus()
end

function init()
    memorialWindow = g_ui.displayUI('game_outfitmemorial')
    memorialWindow:hide()

    -- Three side-by-side columns filling the panel's height (anchored rather than a
    -- box layout, which wouldn't stretch their height).
    local panel = memorialWindow.columns
    for i = 1, 3 do
        local column = g_ui.createWidget('MemorialColumn', panel)
        column:addAnchor(AnchorTop, 'parent', AnchorTop)
        column:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        if i == 1 then
            column:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        else
            column:addAnchor(AnchorLeft, 'prev', AnchorRight)
            column:setMarginLeft(12)
        end
        columns[i] = column
    end

    connect(g_game, {
        onOutfitMemorial = onOutfitMemorial,
        onGameEnd = hide
    })
end

function terminate()
    disconnect(g_game, {
        onOutfitMemorial = onOutfitMemorial,
        onGameEnd = hide
    })
    if memorialWindow then
        memorialWindow:destroy()
        memorialWindow = nil
    end
    columns = {}
    data = nil
end
