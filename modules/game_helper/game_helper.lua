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
        { itemId = 0, itemName = '', isMana = false, threshold = 25 },
        { itemId = 0, itemName = '', isMana = false, threshold = 50 },
        { itemId = 0, itemName = '', isMana = false, threshold = 50 },
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
    local spellSections = {
        { prefix = 'sh',  list = helperData.spellHealing,  count = 3 },
        { prefix = 'sio', list = helperData.sioFriends,    count = 2 },
        { prefix = 'gsio',list = helperData.granSioFriends,count = 2 },
    }
    for _, sec in ipairs(spellSections) do
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
    for row = 1, 3 do
        local d = helperData.potionHealing and helperData.potionHealing[row]
        if d then
            self:updateValDisplay('ph', row, d.threshold or 25)
            self:updatePotionDisplay('ph', row, d)
        end
    end
    self:updateStatusDisplay()
end

-- ── Heal spell cache — sorted by threshold asc, rebuilt on data change ───────

function HelperController:rebuildHealCache()
    local spells = {}
    for _, s in ipairs(helperData.spellHealing or {}) do
        if s.spellWords and s.spellWords ~= '' then
            table.insert(spells, s)
        end
    end
    table.sort(spells, function(a, b) return a.threshold < b.threshold end)
    self._sortedHealSpells = spells
end

-- ── Potion cache — sorted hp/mana lists, rebuilt on data change ──────────────

function HelperController:rebuildPotionCache()
    local hp, mp = {}, {}
    for _, s in ipairs(helperData.potionHealing or {}) do
        if s.itemId and s.itemId > 0 then
            table.insert(s.isMana and mp or hp, s)
        end
    end
    table.sort(hp, function(a, b) return a.threshold < b.threshold end)
    table.sort(mp, function(a, b) return a.threshold < b.threshold end)
    self._sortedHpPotions   = hp
    self._sortedManaPotions = mp
end

-- ── Potion slot item picker — mouseGrabber pattern ────────────────────────────

function HelperController:onPotionSlotClick(section, row)
    self._pendingPotionSection = section
    self._pendingPotionRow     = row
    self._mouseGrabber.onMouseRelease = function(_, pos, _btn)
        self._mouseGrabber:ungrabMouse()
        g_mouse.popCursor('target')
        self:_onPotionItemPicked(pos)
    end
    self._mouseGrabber:grabMouse()
    g_mouse.pushCursor('target')
end

function HelperController:_onPotionItemPicked(pos)
    local root = modules.game_interface.getRootPanel()
    local w = root:recursiveGetChildByPos(pos, false)
    local item = nil
    if w then
        local cls = w:getClassName()
        if cls == 'UIItem' and not w:isVirtual() then
            item = w:getItem()
        elseif cls == 'UIGameMap' then
            local tile = w:getTile(pos)
            if tile then item = tile:getTopMoveThing() end
        end
    end
    if not item or not item:isItem() or not item:isStackable() then return end

    local d = getSectionData(self._pendingPotionSection, self._pendingPotionRow)
    if not d then return end
    d.itemId   = item:getId()
    d.itemName = item:getName() or ''
    d.isMana   = (item:getName() or ''):lower():find('mana') ~= nil
    saveData()
    self:updatePotionDisplay(self._pendingPotionSection, self._pendingPotionRow, d)
    self:rebuildPotionCache()
end

function HelperController:updatePotionDisplay(section, row, data)
    if not self.ui or not data then return end
    local slot = self.ui:recursiveGetChildById(section .. '_slot_' .. row)
    if not slot then return end
    local icon = slot:getChildById('_potionItem')
    if not icon then
        icon = g_ui.createWidget('UIItem', slot)
        icon:setId('_potionItem')
        icon:setVirtual(true)
        icon:fill('parent')
    end
    if data.itemId and data.itemId > 0 then
        icon:setItemId(data.itemId)
        icon:show()
    else
        icon:hide()
    end
end

-- ── Mana change — fire mana potions ──────────────────────────────────────────

function HelperController:onManaChange(player, mana, maxMana, oldMana, oldMaxMana)
    if not helperData.statusEnabled then return end
    if mana >= oldMana then return end
    if not self._sortedManaPotions or #self._sortedManaPotions == 0 then return end
    if g_clock.millis() - (self._lastPotionTime or 0) < 1000 then return end

    local manaPct = math.floor(mana / maxMana * 100)
    for _, pot in ipairs(self._sortedManaPotions) do
        if pot.threshold >= manaPct then
            g_game.useInventoryItemWith(pot.itemId, player)
            self._lastPotionTime = g_clock.millis()
            return
        end
    end
end

-- ── Status toggle ─────────────────────────────────────────────────────────────

function HelperController:onEnableHelper()
    helperData.statusEnabled = true
    saveData()
    self:updateStatusDisplay()
end

function HelperController:onDisableHelper()
    helperData.statusEnabled = false
    saveData()
    self:updateStatusDisplay()
end

function HelperController:updateStatusDisplay()
    if not self.ui then return end
    local label = self.ui:recursiveGetChildById('statusEnabledLabel')
    if not label then return end
    if helperData.statusEnabled then
        label:setText('Helper Status: Enabled')
        label:setColor('#44cc44ff')
    else
        label:setText('Helper Status: Disabled')
        label:setColor('#888888ff')
    end
end

-- ── Auto-heal handler — fires on every HP drop, no polling loop ───────────────

function HelperController:onHealthChange(player, health, maxHealth, oldHealth, oldMaxHealth)
    if not helperData.statusEnabled then return end
    if health >= oldHealth then return end

    local hpPct = math.floor(health / maxHealth * 100)

    -- healing spells first
    if self._sortedHealSpells and #self._sortedHealSpells > 0 then
        local cooldowns = modules.game_cooldown
        if not (cooldowns and cooldowns.isGroupCooldownIconActive(2)) then
            for _, spell in ipairs(self._sortedHealSpells) do
                if spell.threshold >= hpPct then
                    g_game.talk(spell.spellWords)
                    return
                end
            end
        end
    end

    -- HP potions if no spell fired or spell was on cooldown
    if self._sortedHpPotions and #self._sortedHpPotions > 0
    and g_clock.millis() - (self._lastPotionTime or 0) >= 1000 then
        for _, pot in ipairs(self._sortedHpPotions) do
            if pot.threshold >= hpPct then
                g_game.useInventoryItemWith(pot.itemId, player)
                self._lastPotionTime = g_clock.millis()
                return
            end
        end
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
    self._pickerOpen = true
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

    local function doOk()
        local val = bar:getValue()
        picker:unlock()
        picker:destroy()
        scheduleEvent(function() self._pickerOpen = false end, 0)
        callback(val)
    end

    local function doCancel()
        picker:unlock()
        picker:destroy()
        scheduleEvent(function() self._pickerOpen = false end, 0)
    end

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

    local ActionBarController = modules.game_actionbar.ActionBarController
    if not ActionBarController then return end

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
        local vocMatch      = showAll or table.contains(spellData.vocations, playerVocation)
        local groupOk       = section ~= 'sh' or Spells.getPrimaryGroup(spellData) == 2
        if vocMatch and groupOk then
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
                if section == 'sh' then self:rebuildHealCache() end
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
    self._mouseGrabber = g_ui.createWidget('UIWidget', g_ui.getRootWidget())
    self._mouseGrabber:setVisible(false)
    self._mouseGrabber:setFocusable(false)
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
    self:registerEvents(LocalPlayer, {
        onHealthChange = function(player, health, maxHealth, oldHealth, oldMaxHealth)
            self:onHealthChange(player, health, maxHealth, oldHealth, oldMaxHealth)
        end,
        onManaChange = function(player, mana, maxMana, oldMana, oldMaxMana)
            self:onManaChange(player, mana, maxMana, oldMana, oldMaxMana)
        end,
    })
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
    self:rebuildHealCache()
    self:rebuildPotionCache()
    if not self.ui then
        self:loadHtml('template/html/main_helper.html')
    end
    self:updateAllDisplays()
    self.ui:show()
    self.ui:raise()
    self.ui:focus()
    if HelperButton then HelperButton:setOn(true) end
end

function HelperController:doCloseWindow()
    if self._pickerOpen then return end
    self:hide()
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
