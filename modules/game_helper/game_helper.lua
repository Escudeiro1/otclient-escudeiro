HelperController = Controller:new()

HelperButton = nil

-- ── Per-character data ────────────────────────────────────────────────────────

local helperData = {}

local DATA_DEFAULT = {
    statusEnabled = true,
    autoHaste     = { enabled = false, pzCast = false },
    autoEatFood   = true,
    spellHealing  = {
        { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 50 },
        { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 80 },
        { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 80 },
    },
    potionHealing = {
        { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 25 },
        { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 50 },
        { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 50 },
    },
    manaTraining  = { spellWords = '', spellName = '', spellId = 0, spellSource = '', spellClip = '', threshold = 90 },
    sioFriends    = {
        { name = '', enabled = false, threshold = 99 },
        { name = '', enabled = false, threshold = 99 },
    },
    granSioFriends = {
        { name = '', enabled = false, threshold = 99 },
        { name = '', enabled = false, threshold = 99 },
    },
}

local function deepCopy(t)
    if type(t) ~= 'table' then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepCopy(v) end
    return c
end

local function dataPath()
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    return '/characterdata/' .. player:getId() .. '/helper.json'
end

local function dataDir()
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    return '/characterdata/' .. player:getId()
end

local function loadData()
    helperData = deepCopy(DATA_DEFAULT)
    local path = dataPath()
    if not path or not g_resources.fileExists(path) then return end
    local ok, decoded = pcall(function()
        return json.decode(g_resources.readFileContents(path))
    end)
    if ok and type(decoded) == 'table' then
        helperData = decoded
    end
end

local function saveData()
    local path = dataPath()
    if not path then return end
    local dir = dataDir()
    if not g_resources.directoryExists(dir) then
        g_resources.makeDir(dir)
    end
    local ok, encoded = pcall(function() return json.encode(helperData) end)
    if ok then
        g_resources.writeFileContents(path, encoded)
    end
end

-- Returns the data table for a given section + row.
-- section: 'sh' (spell healing), 'ph' (potion healing), 'mh' (mana training),
--          'sio' (sio friends), 'gsio' (gran sio friends)
local function getSectionData(section, row)
    if section == 'sh'   then return helperData.spellHealing   and helperData.spellHealing[row]
    elseif section == 'ph'   then return helperData.potionHealing  and helperData.potionHealing[row]
    elseif section == 'mh'   then return helperData.manaTraining
    elseif section == 'sio'  then return helperData.sioFriends     and helperData.sioFriends[row]
    elseif section == 'gsio' then return helperData.granSioFriends and helperData.granSioFriends[row]
    end
end

-- ── UI helpers ────────────────────────────────────────────────────────────────

function HelperController:updateValDisplay(section, row, val)
    if not self.ui then return end
    local w = self.ui:recursiveGetChildById(section .. '_val_' .. row)
    if w then
        w:setText('')
        w:setText(val .. '%')
    end
end

function HelperController:updateSlotDisplay(section, row, data)
    if not self.ui or not data then return end
    local icon = self.ui:recursiveGetChildById(section .. '_icon_' .. row)
    if not icon then return end
    if data.spellSource and data.spellSource ~= '' then
        icon:setImageSource(data.spellSource)
        icon:setImageClip(data.spellClip or '')
        icon:show()
    else
        icon:hide()
    end
end

function HelperController:updateAllDisplays()
    if not self.ui then return end
    local sections = {
        { prefix = 'sh',  list = helperData.spellHealing,   count = 3 },
        { prefix = 'ph',  list = helperData.potionHealing,  count = 3 },
        { prefix = 'sio', list = helperData.sioFriends,     count = 2 },
        { prefix = 'gsio',list = helperData.granSioFriends, count = 2 },
    }
    for _, sec in ipairs(sections) do
        for row = 1, sec.count do
            local d = sec.list and sec.list[row]
            if d then
                self:updateValDisplay(sec.prefix, row, d.threshold or 50)
                self:updateSlotDisplay(sec.prefix, row, d)
            end
        end
    end
    if helperData.manaTraining then
        self:updateValDisplay('mh', 1, helperData.manaTraining.threshold or 90)
        self:updateSlotDisplay('mh', 1, helperData.manaTraining)
    end
end

-- ── Arrow click — adjust threshold ±1 ────────────────────────────────────────

function HelperController:onArrowClick(section, row, delta)
    local d = getSectionData(section, row)
    if not d then return end
    d.threshold = math.max(1, math.min(99, (d.threshold or 50) + delta))
    saveData()
    self:updateValDisplay(section, row, d.threshold)
end

-- ── Value button click — open percentage picker ───────────────────────────────

function HelperController:onValueClick(section, row)
    local d = getSectionData(section, row)
    if not d then return end
    self:showValuePicker(d.threshold or 50, function(newVal)
        d.threshold = newVal
        saveData()
        self:updateValDisplay(section, row, newVal)
    end)
end

function HelperController:showValuePicker(currentVal, callback)
    local picker = g_ui.createWidget('HelperValuePicker', g_ui.getRootWidget())
    picker:lock()

    local bar   = picker:getChildById('valueBar')
    local label = picker:getChildById('currentValueLabel')

    bar:setMinimum(1)
    bar:setMaximum(99)
    bar:setValue(currentVal)
    label:setText(currentVal .. '%')

    bar.onValueChange = function(_, val)
        label:setText(val .. '%')
    end

    -- Digit accumulator: each keypress appends a digit.
    -- Typing "8","4" → 84; typing "1","0","0" → 10 then caps at 99 and resets.
    local accumulated = ''
    local function handleDigit(d)
        local tentative = accumulated .. d
        local num = tonumber(tentative) or 0
        if num > 99 then
            bar:setValue(99)
            label:setText('99%')
            accumulated = ''
        else
            accumulated = tentative
            local clamped = math.max(1, num)
            bar:setValue(clamped)
            label:setText(clamped .. '%')
        end
    end

    local closed = false
    local function doOk()
        if closed then return end
        closed = true
        callback(bar:getValue())
        picker:unlock()
        picker:destroy()
    end

    local function doCancel()
        if closed then return end
        closed = true
        picker:unlock()
        picker:destroy()
    end

    -- onEscape owns the Escape key at the window level so it never
    -- reaches the helper window's onescape="self:hide()" handler.
    picker.onEscape = doCancel

    local function onKey(_, keyCode, _mods)
        if keyCode >= Key0 and keyCode <= Key9 then
            handleDigit(tostring(keyCode - Key0))
            return true
        elseif keyCode >= KeyNumpad0 and keyCode <= KeyNumpad9 then
            handleDigit(tostring(keyCode - KeyNumpad0))
            return true
        elseif keyCode == KeyReturn or keyCode == KeyEnter then
            doOk()
            return true
        elseif keyCode == KeyEscape then
            doCancel()
            return true
        end
        return false
    end

    picker.onKeyDown = onKey
    bar.onKeyDown    = onKey

    picker:getChildById('buttonOk').onClick     = doOk
    picker:getChildById('buttonCancel').onClick = doCancel
end

-- ── Slot click — open spell selector ─────────────────────────────────────────

function HelperController:onSlotClick(section, row)
    local player = g_game.getLocalPlayer()
    if not player then return end

    -- Reuse ActionBarController's spell picker HTML so we don't duplicate the UI.
    if ActionBarController.ui then
        ActionBarController:unloadHtml()
    end

    local radio = UIRadioGroup.create()
    ActionBarController:loadHtml('html/spells.html')
    ActionBarController.ui:show()
    ActionBarController.ui:raise()
    ActionBarController.ui:setTitle('Select Spell')

    -- Hide action-bar-specific widgets.
    local paramLabel = ActionBarController:findWidget('#paramLabel')
    local paramText  = ActionBarController:findWidget('#paramText')
    local devBtn     = ActionBarController:findWidget('#dev')
    if paramLabel then paramLabel:hide() end
    if paramText  then paramText:hide()  end
    if devBtn     then devBtn:hide()     end

    local spellList     = ActionBarController:findWidget('#spellList')
    local previewWidget = ActionBarController:findWidget('#preview')
    local imageWidget   = ActionBarController:findWidget('#image')

    local playerVocation = translateVocation(player:getVocation())
    local playerLevel    = player:getLevel()
    local spells         = SpellInfo['Default']
    local iconFolder     = SpelllistSettings['Default'].iconFile
    local showAll        = (playerVocation == 0)

    for spellName, spellData in pairs(spells) do
        if showAll or table.contains(spellData.vocations, playerVocation) then
            local widget = g_ui.createWidget('SpellPreview', spellList)
            local spellId = spellData.clientId
            local clip    = Spells.getImageClip(spellId)
            radio:addWidget(widget)
            widget:setId(tostring(spellData.id))
            widget:setText(spellName .. '\n' .. spellData.words)
            widget.voc    = spellData.vocations
            widget.param  = spellData.parameter
            widget.source = iconFolder
            widget.clip   = clip
            widget.image:setImageSource(iconFolder)
            widget.image:setImageClip(clip)
            if spellData.level then
                widget.levelLabel:setVisible(true)
                widget.levelLabel:setText(string.format('Level: %d', spellData.level))
                widget.image.gray:setVisible(playerLevel < spellData.level)
            end
            local primaryGroup = Spells.getPrimaryGroup(spellData)
            if primaryGroup ~= -1 then
                local offSet = (primaryGroup == 2 and 20) or (primaryGroup == 3 and 40) or 0
                widget.imageGroup:setImageClip(offSet .. ' 0 20 20')
                widget.imageGroup:setVisible(true)
            end
        end
    end

    local widgets = spellList:getChildren()
    table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
    for i, w in ipairs(widgets) do spellList:moveChildToIndex(w, i) end
    if #widgets > 0 then radio:selectWidget(widgets[1]) end

    radio.onSelectionChange = function(_, selected)
        if selected then
            previewWidget:setText(selected:getText())
            imageWidget:setImageSource(selected.source)
            imageWidget:setImageClip(selected.clip)
        end
    end

    local function confirmSpell()
        local selected = radio:getSelectedWidget()
        if selected then
            local d = getSectionData(section, row)
            if d then
                d.spellName   = string.match(selected:getText(), '^(.+)\n') or ''
                d.spellWords  = string.match(selected:getText(), '\n(.*)') or ''
                d.spellId     = tonumber(selected:getId()) or 0
                d.spellSource = selected.source or ''
                d.spellClip   = selected.clip   or ''
                saveData()
                self:updateSlotDisplay(section, row, d)
            end
        end
        ActionBarController:unloadHtml()
    end

    ActionBarController:findWidget('#buttonOk').onClick    = confirmSpell
    ActionBarController:findWidget('#buttonApply').onClick = confirmSpell
    ActionBarController:findWidget('#buttonClose').onClick = function()
        ActionBarController:unloadHtml()
    end
end

-- ── Controller lifecycle ──────────────────────────────────────────────────────

function HelperController:onInit()
    g_ui.importStyle('/modules/game_helper/HelperValuePicker.otui')
end

function HelperController:onGameStart()
    if not HelperButton then
        HelperButton = modules.game_mainpanel.addToggleButton(
            'helperButton',
            tr('Helper'),
            '/images/options/button_helper',
            function() self:toggle() end,
            false,
            2000)
    end
end

function HelperController:onGameEnd()
    self:hide()
end

function HelperController:onTerminate()
    if HelperButton then
        HelperButton:destroy()
        HelperButton = nil
    end
    if self.ui then
        self:unloadHtml()
    end
end

function HelperController:show()
    loadData()
    if not self.ui then
        self:loadHtml('template/html/main_helper.html')
    end
    self:updateAllDisplays()
    self.ui:show()
    self.ui:raise()
    self.ui:focus()
    if HelperButton then HelperButton:setOn(true) end
end

function HelperController:hide()
    if self.ui then self:unloadHtml() end
    if HelperButton then HelperButton:setOn(false) end
end

function HelperController:toggle()
    if self.ui and self.ui:isVisible() then
        self:hide()
    else
        self:show()
    end
end
