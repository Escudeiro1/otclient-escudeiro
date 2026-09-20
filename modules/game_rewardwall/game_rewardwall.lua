rewardWallController = Controller:new()
-- /*=============================================
-- =            To-do                  =
-- =============================================*/
-- - otui -> html/css (g_ui.displayUI)
-- - Improve Ids footerGold2 , footerGold1, "test", "displayGeneralBox3"

local ServerPackets = {
    ShowDialog = 0xED,
    DailyRewardCollectionState = 0xDE,
    OpenRewardWall = 0xE2,
    CloseRewardWall = 0xE3,
    DailyRewardBasic = 0xE4,
    DailyRewardHistory = 0xE5
    -- RestingAreaState = 0xA9
}

local ClientPackets = {
    OpenRewardWall = 0xD8,
    OpenRewardHistory = 0xD9,
    SelectReward = 0xDA,
    CollectionResource = 0x14,
    JokerResource = 0x15
}

-- @ widget
local ButtonRewardWall = nil
local windowsPickWindow = nil
local generalBox = nil
-- @ array
local bonuses = {}
local actualUsed = {}
-- @ variable
local bonusShrine = 0
-- @ const
local COLORS = {
    BASE_1 = "#484848",
    BASE_2 = "#414141"
}
local ZONE = {
    LAST_KEY = nil,
    RESTING_AREA_ZONE = 1,
    ICON_ID = "condition_Rewards" -- maps to PlayerStates.Rewards (30) via Icons[30].id in gamelib/player.lua
}

local bundleType = {
    ITEMS = 1,
    PREY = 2,
    XPBOOST = 3
}

local STATUS = {
    COLLECTED = 1,
    ACTIVE = 2,
    LOCKED = 3
}

local OPEN_WINDOWS = {
    BUTTON_WIDGET = 0,
    SHRINE = 1 -- itemClientId = 25802
}

local DailyRewardStatus = { -- sendDailyRewardCollectionState 0xDE ?
    DAILY_REWARD_COLLECTED = 0,
    DAILY_REWARD_NOTCOLLECTED = 1,
    DAILY_REWARD_NOTAVAILABLE = 2
}

local CONST_WINDOWS_BOX = {
    ALREADY = 1,
    RELEASE = 2,
    CONFIRMATION_IRA = 3, -- IRA = Instant Reward Access
    NO_IRA = 4,
    CONFIRMATION_SHRINE = 5
}

local BOX_CONFIGS = {
    [CONST_WINDOWS_BOX.ALREADY] = {
        title = "Warning",
        content = "Sorry, you have already taken your daily reward or you are unable to collect it"
    },
    [CONST_WINDOWS_BOX.CONFIRMATION_IRA] = {
        title = "Confirmation of using Instant Reward Access",
        content = "Remember! You can always collect your daily reward for free by visiting a reward shrine!\n\nYou Currently own 3x Instant Reward Access. Do you really want to use one to claim your daily reward now?",
        okCallback = function()
            g_game.requestGetRewardDaily(bonusShrine, actualUsed)
            if windowsPickWindow then
                windowsPickWindow:destroy()
                windowsPickWindow = nil
            end
            if generalBox then
                generalBox:destroy()
                generalBox = nil
            end
            show()
        end
    },
    [CONST_WINDOWS_BOX.NO_IRA] = {
        title = "Warning: No Sufficient Instant Reward Access",
        content = "Remember! you can always collect your daily reward for free by visiting a reward shrine!\nyou do not have an Instant Reward Access.\nVisit the store to buy more!"
    },
    [CONST_WINDOWS_BOX.CONFIRMATION_SHRINE] = {
        title = "Collect Daily Reward",
        content = "Do you want to collect your daily reward at this shrine?",
        okCallback = function()
            g_game.requestGetRewardDaily(bonusShrine, actualUsed)
            if windowsPickWindow then
                windowsPickWindow:destroy()
                windowsPickWindow = nil
            end
            if generalBox then
                generalBox:destroy()
                generalBox = nil
            end
            show()
        end
    }
}

-- /*=============================================
-- =            Local function                  =
-- =============================================*/
local function destroyWindows(windows)
    if type(windows) == "table" then
        for _, window in pairs(windows) do
            if window and not window:isDestroyed() then
                window:destroy()
            end
        end
    else
        if windows and not windows:isDestroyed() then
            windows:destroy()
        end
    end
    return nil
end

local function premiumStatusWindwos(isPremium)
    rewardWallController.ui.premiumStatus.premiumMessage:setText(isPremium and
                                                                     "Great! You benefit from the best possible rewards and bonuses due to your premium status." or
                                                                     "With a Premium account, you would benefit from even better rewards and bonuses.")
    rewardWallController.ui.premiumStatus.premiumButton:setOn(not isPremium)
    rewardWallController.ui.infoPanel.free:setColor(isPremium and "#909090" or "#FFFFFF")
    rewardWallController.ui.infoPanel.premium:setColor(isPremium and "#FFFFFF" or "#909090")
end

-- Bonus icon i (1..6) represents streak day (i+1) - day 1 has no bonus. Lights
-- based on the actual (server-reset-on-expiry) streak level, not premium status;
-- mirrors canary's Player.getActiveDailyRewardBonusesName/getDailyRewardBonusesCount
-- (data/libs/functions/player.lua), which cap the same loop at streak day 7.
local function updateBonusIcons(dayStreakLevel)
    local streak = math.min(dayStreakLevel, 7)
    for i, widget in ipairs(rewardWallController.ui.restingAreaPanel.bonusIcons:getChildren()) do
        local active = streak >= i + 1
        widget:setOn(active)
        -- game_rewardwall.html declares these as <imgBonuses> tags (not a CSS
        -- class on a <div>), so the style's nested ditherpattern overlay child
        -- is actually instantiated (see UIManager::createWidgetFromOTML) and
        -- reachable here, same as RewardButton3's ditherpattern is used above
        -- for the daily-reward-row locks.
        widget.ditherpattern:setVisible(not active)
    end
end

local function convert_timestamp(timestamp)
    return os.date("%Y-%m-%d, %H:%M:%S", timestamp)
end

local function formatTimeLeft(timeLeft)
    if timeLeft == 0 then return "Expired" end
    if timeLeft == 90001 then return "< 1 min" end
    if timeLeft > 1000000000 then
        local remaining = timeLeft - os.time()
        if remaining <= 0 then return "Expired" end
        if remaining < 60 then return "< 1 min" end
        local hours = math.floor(remaining / 3600)
        local minutes = math.floor((remaining % 3600) / 60)
        return string.format("%02d:%02d", hours, minutes)
    end
    return timeLeft
end

local function getBonusStrings(bonuses)
    local result = {}
    for _, bonus in ipairs(bonuses) do
        table.insert(result, bonus["name"])
    end
    return table.concat(result, ", ")
end

local function visibleHistory(bool)
    for i, widget in ipairs(rewardWallController.ui:getChildren()) do
        if widget:getId() == "historyPanel" then
            widget:setVisible(bool)
        else
            widget:setVisible(not bool)
        end
        if i == 5 then -- foot
            break
        end
    end
end

-- Third argument (nextRewardTime) is only non-zero once today's reward has
-- already been collected: it's the timestamp the *next* reward opens up, and
-- drives a countdown under the current slot. The fourth (daysMissed) is only
-- non-zero once the current reward's grace period has elapsed uncollected,
-- and switches that same slot to a joker-cost badge instead. Neither applies
-- while the current reward is still collectible within its grace period, so
-- the slot shows no label at all in that case.
local function updateDailyRewards(dayStreakDay, wasDailyRewardTaken, nextRewardTime, daysMissed)
    local dailyRewardsPanel = rewardWallController.ui.dailyRewardsPanel
    for i = 1, dayStreakDay do
        local rewardWidget = dailyRewardsPanel:getChildById("reward" .. i)
        local rewardArrow = dailyRewardsPanel:getChildById("arrow" .. i)
        if rewardWidget then
            local test = g_ui.createWidget("RewardButton", rewardWidget:getChildById("rewardGold" .. i))
            test:setOn(true)
            test:fill("parent")
            test:setPhantom(true)
            rewardArrow:setImageClip("5 0 5 7")
            rewardWidget:getChildById("rewardButton" .. i):setOn(true)
            rewardWidget:getChildById("rewardButton" .. i).ditherpattern:setVisible(true)
            rewardWidget:getChildById("rewardGold" .. i).status = 1
        end
    end

    local currentReward = dailyRewardsPanel:getChildById("reward" .. dayStreakDay + 1)
    if currentReward then
        local rewardGoldWidget = currentReward:getChildById("rewardGold" .. dayStreakDay + 1)
        rewardGoldWidget:destroyChildren()
        if nextRewardTime and nextRewardTime > 0 then
            local test = g_ui.createWidget("GoldLabel2", rewardGoldWidget)
            test:setOn(true)
            test:fill("parent")
            test:setPhantom(true)
            test.gold:setVisible(false)
            test.text:setText(formatTimeLeft(nextRewardTime))
            test.text:setColor("white")
        else
            -- Always shown while the current reward hasn't been collected yet, even
            -- at 0 (not expired yet -- this previews what it would currently cost to
            -- keep the streak if it did expire right now).
            local missed = daysMissed or 0
            local test = g_ui.createWidget("GoldLabel2", rewardGoldWidget)
            test:setOn(true)
            test:fill("parent")
            test:setPhantom(true)
            test.gold:setImageSource("/game_rewardwall/images/icon-daily-reward-joker")
            test.gold:setImageSize("12 12")
            test.gold:setImageOffset("-20 0")
            test.text:setText(missed >= 4 and ">3" or tostring(missed))
            test.text:setColor(missed > 0 and "red" or "white")
        end
        rewardGoldWidget.status = 2
        currentReward:setOn(false)
        currentReward:getChildById("rewardButton" .. dayStreakDay + 1).ditherpattern:setVisible(false)
        currentReward:getChildById("rewardButton" .. dayStreakDay + 1):setOn(false)
    end

    for i = dayStreakDay + 2, 7 do
        local rewardWidget = dailyRewardsPanel:getChildById("reward" .. i)
        if rewardWidget then
            local test = g_ui.createWidget("RewardButton", rewardWidget:getChildById("rewardGold" .. i))
            test:setOn(false)
            test:fill("parent")
            test:setPhantom(true)
            rewardWidget:getChildById("rewardButton" .. i):setOn(true)
            rewardWidget:getChildById("rewardButton" .. i).ditherpattern:setVisible(true)
            rewardWidget:getChildById("rewardGold" .. i).status = 3
        end
    end
end

local function getDayStreakIcon(dayStreakLevel)
    local IconConsecutiveDays = {
        [24] = "icon-rewardstreak-default",
        [49] = "icon-rewardstreak-bronze",
        [99] = "icon-rewardstreak-silver",
        [100] = "icon-rewardstreak-gold"
    }
    if dayStreakLevel <= 24 then
        return IconConsecutiveDays[24]
    elseif dayStreakLevel <= 49 then
        return IconConsecutiveDays[49]
    elseif dayStreakLevel <= 99 then
        return IconConsecutiveDays[99]
    else
        return IconConsecutiveDays[100]
    end
end

local function getBonusDescription(bonusName, streakCount, activeBonuses)
    local isPremium = g_game.getLocalPlayer():isPremium()

    return string.format(
        "Allow [color=#909090]%s[/color]%s\nThis bonus is active because you are [color=%s]Premium[/color] and reached a reward streak of at least [color=#44AD25]%d[/color].%s",
        bonusName, isPremium and "" or "[color=#ff0000](Locked)[/color]", isPremium and "#44AD25" or "#ff0000",
        streakCount, isPremium and ("\n\nActive bonuses: [color=#909090]%s[/color]."):format(activeBonuses) or "")
end

local function checkRewards(data)
    local premium = g_game.getLocalPlayer():isPremium()
    local rewardType = premium and data.premiumRewards or data.freeRewards
    local altType = premium and data.freeRewards or data.premiumRewards

    for index = 1, #rewardType do
        local reward = rewardType[index]
        local altReward = altType[index]

        local hasSelectableItems = reward.selectableItems and next(reward.selectableItems) ~= nil
        local rewardButton = rewardWallController.ui.dailyRewardsPanel:getChildById("reward" .. index):getChildById(
            "rewardButton" .. index)
        local iconWidget = rewardWallController.ui.dailyRewardsPanel:getChildById("reward" .. index):getChildByIndex(1)

        if hasSelectableItems then
            iconWidget:setIcon("game_rewardwall/images/icon-reward-pickitems")
            rewardButton.bundleType = bundleType.ITEMS
            rewardButton.rewardItem = reward.selectableItems
            rewardButton.itemsToSelect = {reward.itemsToSelect or 0, altReward and altReward.itemsToSelect or 0}
        elseif reward.bundleItems[1] and reward.bundleItems[1].bundleType == bundleType.XPBOOST then
            iconWidget:setIcon("game_rewardwall/images/icon-reward-xpboost")
            rewardButton.bundleType = bundleType.XPBOOST
            rewardButton.itemsToSelect = {reward.bundleItems[1].itemId or 0,
                                          altReward and altReward.bundleItems[1].itemId or 0}
        else
            iconWidget:setIcon("game_rewardwall/images/icon-reward-fixeditems")
            rewardButton.bundleType = bundleType.PREY
            rewardButton.itemsToSelect = {reward.bundleItems[1].count or 0,
                                          altReward and altReward.bundleItems[1].count or 0}
        end
    end
end
-- /*=============================================
-- =            onParse                  =
-- =============================================*/

local function onRestingAreaState(zone, state, message)
    -- Dedup on the full (zone, state, message) tuple, not zone alone: a bonus can
    -- activate/deactivate (state/message change) while the player never leaves the
    -- resting area (zone stays 1 the whole time), and that update must not be dropped.
    local key = zone .. "|" .. state .. "|" .. message
    if ZONE.LAST_KEY == key then
        return
    end
    ZONE.LAST_KEY = key
    local gameInterface = modules.game_interface
    if zone == ZONE.RESTING_AREA_ZONE then
        -- Same string ICON_ID used here and in the destroy branch below, so the
        -- lookup actually finds the existing widget instead of always falling
        -- through to the createIfMissing path (widget ids are always strings).
        gameInterface.processIcon(ZONE.ICON_ID, function(icon)
            icon:setTooltip(message)
        end, true)
    else
        gameInterface.processIcon(ZONE.ICON_ID, function(icon)
            icon:destroy()
        end)
    end
end

local function onDailyReward(data)
    bonuses = data.bonuses
    checkRewards(data)
end

local function onServerError(code, error)
    generalBox = destroyWindows(generalBox)
    local cancelCallback = function()
        generalBox = destroyWindows(generalBox)
        rewardWallController.ui:show()
        rewardWallController.ui:raise()
        rewardWallController.ui:focus()
    end

    local standardButtons = {{
        text = "ok",
        callback = cancelCallback
    }}

    generalBox = displayGeneralBox3(rewardWallController.ui:getText(), error, standardButtons)
end

local function connectOnServerError()
    connect(g_game, {
        onServerError = onServerError
    })
end

local function disconnectOnServerError()
    disconnect(g_game, {
        onServerError = onServerError
    })
end

local function onOpenRewardWall(bonusShrines, nextRewardTime, dayStreakDay, wasDailyRewardTaken, errorMessage, tokens,
    timeLeft, dayStreakLevel, daysMissed)
    if bonusShrines == OPEN_WINDOWS.SHRINE then
        rewardWallController.ui:show()
        rewardWallController.ui:raise()
        rewardWallController.ui:focus()
    end
    bonusShrine = bonusShrines
    updateDailyRewards(dayStreakDay, wasDailyRewardTaken, nextRewardTime, daysMissed)
    rewardWallController.ui.restingAreaPanel.restingAreaInfo.rewardStreakIcon:setText(dayStreakLevel)
    updateBonusIcons(dayStreakLevel)

    local restingAreaInfo = rewardWallController.ui.restingAreaPanel.restingAreaInfo
    local streakWarning = rewardWallController.ui.restingAreaPanel.streakWarning
    local rewardTaken = wasDailyRewardTaken ~= 0
    local expired = not rewardTaken and (daysMissed or 0) > 0

    -- Three top-left slot states:
    --   (a) just collected            -> green checkmark
    --   (b) collected, grace running  -> live countdown of hours remaining
    --   (c) grace elapsed, uncollected -> "Expired" + joker-cost message (daysMissed 1-3,
    --       or 4 meaning ">3"/unrecoverable since jokers cap at 3)
    -- When the reward is already taken, the server sends no timeLeft field at all (see
    -- sendOpenRewardWall), so timeLeft stays at its C++ default of 0 -- which formatTimeLeft
    -- treats as a "no data" sentinel and renders as "Expired". Show the collected checkmark
    -- instead of calling formatTimeLeft in that case, rather than misreading 0 as expired.
    restingAreaInfo.timeLeft.timeLeftDone:setVisible(rewardTaken)
    restingAreaInfo.timeLeft:setText(rewardTaken and "" or (expired and "expired" or formatTimeLeft(timeLeft)))

    if streakWarning then
        streakWarning:setVisible(true)
        if rewardTaken then
            if dayStreakLevel >= 7 then
                streakWarning:parseColoredText("Great! You benefit from the best possible rewards and bonuses",
                    "#c0c0c0")
            else
                streakWarning:parseColoredText("You already claimed your daily reward.", "#c0c0c0")
            end
        elseif expired then
            local jokerMessage = daysMissed >= 4 and "Too bad, you do not have enough Daily Reward Jokers." or
                                      ("Spend " .. daysMissed .. " Daily Reward Joker(s) to keep your streak.")
            streakWarning:parseColoredText(
                "You did not claim your daily reward in time.\n" .. jokerMessage, "#c0c0c0")
        else
            streakWarning:parseColoredText("Hurry up! collect your daily reward and keep your streak.", "#c0c0c0")
        end
    end

    -- Below the top-left slot this badge normally shows the player's current joker
    -- balance, but once expired it switches to the joker cost to recover the streak
    -- (same 0-3 / ">3" range as the streakWarning message above).
    rewardWallController.ui.restingAreaPanel.restingAreaInfo.restingAreaGold.text:setText(
        expired and (daysMissed >= 4 and ">3" or tostring(daysMissed)) or tokens)
    rewardWallController.ui.footerPanel.footerGold1.text:setText(tokens)
    rewardWallController.ui.restingAreaPanel.restingAreaInfo.rewardStreakIcon:setImageSource(
        "/game_rewardwall/images/" .. getDayStreakIcon(dayStreakLevel))

    rewardWallController.ui.footerPanel.footerGold2.text:setText(
        g_game.getLocalPlayer():getResourceBalance(ResourceTypes.DAILYREWARD_STREAK))
end

local function onRewardHistory(rewardHistory)
    local transferHistory = rewardWallController.ui.historyPanel.historyList.List
    transferHistory:destroyChildren()

    local headerRow = g_ui.createWidget("historyData2", transferHistory)
    headerRow:setBackgroundColor("#363636")
    headerRow:setBorderColor("#00000077")
    headerRow:setBorderWidth(1)
    headerRow.date:setText("Date")
    headerRow.Balance:setText("Streak")
    headerRow.Description:setText("Event")

    for i, data in ipairs(rewardHistory) do
        local row = g_ui.createWidget("historyData2", transferHistory)
        row:setHeight(30)
        row.date:setText(convert_timestamp(data[1]))
        row.Balance:setText(data[4])
        row.Description:setText(data[3])
        row.Description:setTextWrap(true)
        row:setBackgroundColor(i % 2 == 0 and "#ffffff12" or "#00000012")
    end
end

-- /*=============================================
-- =            Windows                  =
-- =============================================*/
function show()
    if not rewardWallController.ui then
        return
    end
    g_game.sendOpenRewardWall()
    rewardWallController.ui:show()
    rewardWallController.ui:raise()
    rewardWallController.ui:focus()
    if ButtonRewardWall then
        ButtonRewardWall:setOn(true)
    end
    connectOnServerError()
    premiumStatusWindwos(g_game.getLocalPlayer():isPremium())
end

function hide(bool)
    if not rewardWallController.ui then
        return
    end
    rewardWallController.ui:hide()
    if ButtonRewardWall then
        ButtonRewardWall:setOn(false)
    end
    if bool then
        disconnectOnServerError()
    end
end

function toggle()
    if not rewardWallController.ui then
        return
    end
    if rewardWallController.ui:isVisible() then
        return hide(true)
    end
    show()
end

local function fixCssIncompatibility() -- temp
    rewardWallController.ui.historyPanel.historyList:fill('parent')

    -- note: I don't know how to edit children in css
    local restingAreaGold = rewardWallController.ui.restingAreaPanel.restingAreaInfo.restingAreaGold
    restingAreaGold.gold:setImageSource("/game_rewardwall/images/icon-daily-reward-joker")
    restingAreaGold.gold:setImageSize("12 12")
    restingAreaGold.gold:setImageOffset("-22 0")

    local footerGold1 = rewardWallController.ui.footerPanel.footerGold1
    footerGold1.gold:setImageSource("/game_rewardwall/images/icon-daily-reward-joker")
    footerGold1.gold:setImageSize("11 11")
    footerGold1.gold:setImageOffset("-3 0")
    footerGold1.text:setTextAlign(AlignRightCenter)

    local footerGold2 = rewardWallController.ui.footerPanel.footerGold2
    footerGold2.gold:setImageSource("/game_rewardwall/images/instant-reward-access-icon")
    footerGold2.gold:setImageSize("12 12")
    footerGold2.gold:setImageOffset("-5 0")
end
-- /*=============================================
-- =            Controller                  =
-- =============================================*/
-- closeButton/historyButton are created here as plain OTUI widgets instead
-- of in the HTML, and anchored/positioned via Lua -- widgets parsed from
-- game_rewardwall.html get an html node attached (isOnHtml() == true), which
-- silently skips the otui "size:" property and pulls in a chain of
-- html-specific auto-sizing/stretch behavior that never let these two
-- buttons render at their declared size. Plain g_ui.createWidget() avoids
-- all of that, matching how game_cyclopedia's CloseButton/BackButton (which
-- render correctly) are built.
local function createFooterButtons()
    local footerPanel = rewardWallController.ui.footerPanel

    local closeButton = g_ui.createWidget('RewardWallButton', footerPanel)
    closeButton:setId('closeButton')
    closeButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    closeButton:addAnchor(AnchorRight, 'parent', AnchorRight)
    closeButton:setText('Close')
    closeButton.onClick = function()
        rewardWallController:onClickToggle()
    end

    local historyButton = g_ui.createWidget('RewardWallButton', footerPanel)
    historyButton:setId('historyButton')
    historyButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    historyButton:addAnchor(AnchorRight, 'closeButton', AnchorLeft)
    historyButton:setMarginRight(10)
    historyButton:setText('History')
    historyButton.onClick = function()
        rewardWallController:onClickshowHistory()
    end
end

function rewardWallController:onInit()
    g_ui.importStyle("styles/style.otui")
    rewardWallController:loadHtml('game_rewardwall.html')
    rewardWallController.ui:hide()
    createFooterButtons()

    rewardWallController:registerEvents(g_game, {
        onOpenRewardWall = onOpenRewardWall,
        onDailyReward = onDailyReward,
        onRewardHistory = onRewardHistory,
        onRestingAreaState = onRestingAreaState
    })
    fixCssIncompatibility()
end

function rewardWallController:onTerminate()
    generalBox, windowsPickWindow, ButtonRewardWall = destroyWindows({generalBox, windowsPickWindow, ButtonRewardWall})
end

function rewardWallController:onGameStart()
    if g_game.getClientVersion() > 1140 then -- Summer Update 2017
        if not ButtonRewardWall then
            ButtonRewardWall = modules.game_mainpanel.addToggleButton("rewardWall", tr("Open rewardWall"),
                "/images/options/rewardwall", toggle, false, 21)
        end
    else
        scheduleEvent(function()
            g_modules.getModule("game_rewardwall"):unload()
        end, 100)
    end
end

function rewardWallController:onGameEnd()
    if rewardWallController.ui:isVisible() then
        rewardWallController.ui:hide()
        ButtonRewardWall:setOn(false)
    end
    generalBox, windowsPickWindow = destroyWindows({generalBox, windowsPickWindow})
end
-- /*=============================================
-- =            Call css onClick                =
-- =============================================*/
function rewardWallController:onClickshowHistory()
    visibleHistory(not rewardWallController.ui.historyPanel:isVisible())
    if rewardWallController.ui.historyPanel:isVisible() then
        g_game.requestOpenRewardHistory()
    end
    rewardWallController.ui.footerPanel.historyButton:setText(
    rewardWallController.ui.historyPanel:isVisible() and "Back" or "History")
end

function rewardWallController:onClickToggle()
    toggle()
end

function rewardWallController:onClickSendStoreRewardWall()
    modules.game_store.toggle()
    g_game.sendRequestStorePremiumBoost()
end

function rewardWallController:onClickbuyInstantRewardAccess()
    modules.game_store.toggle()
    g_game.sendRequestUsefulThings(StoreConst.InstantRewardAccess)
end

function rewardWallController:onClickDisplayWindowsPickRewardWindow(event)
    if event.target:isOn() then
        return
    end

    if event.target.bundleType == bundleType.ITEMS then
        local isPremium = g_game.getLocalPlayer():isPremium()
        local itemsToSelect = event.target.itemsToSelect
        if not windowsPickWindow then
            if type(itemsToSelect) == "table" then
                itemsToSelect = isPremium and itemsToSelect[1] or itemsToSelect[2]
            else
                itemsToSelect = itemsToSelect or 1
            end
            windowsPickWindow = g_ui.displayUI('styles/pickreward')
            windowsPickWindow:show()
            windowsPickWindow:getChildById('capacity'):setText("Free capacity: " ..
                                                                   g_game:getLocalPlayer():getFreeCapacity() .. " oz")

            local text = string.format("You have selected [color=#D33C3C]0[/color] of %d reward items", itemsToSelect)
            windowsPickWindow:getChildById('rewardLabel'):parseColoredText(text, "#c0c0c0")

            for i, item in pairs(event.target.rewardItem) do
                local getItem = g_ui.createWidget('ItemReward', windowsPickWindow:getChildById('rewardList'))
                getItem:getChildById('item'):setItemId(item.itemId)
                getItem:getChildById('title'):setText(item.name)
                getItem:setBackgroundColor((i % 2 == 0) and COLORS.BASE_1 or COLORS.BASE_2)
                getItem.totalWeight = (item.weight or 100) / 100
                getItem.itemsToSelect = itemsToSelect

            end
            actualUsed = {}
            hide()
        else
            windowsPickWindow:show()
            windowsPickWindow:raise()
            windowsPickWindow:focus()
        end

    elseif event.target.bundleType == bundleType.XPBOOST or event.target.bundleType == bundleType.PREY then
        hide()
        actualUsed = {}
        local box = bonusShrine == OPEN_WINDOWS.SHRINE and CONST_WINDOWS_BOX.CONFIRMATION_SHRINE or CONST_WINDOWS_BOX.CONFIRMATION_IRA
        managerMessageBoxWindow(box)
    end
end

-- /*=============================================
-- =            Call onHover css                  =
-- =============================================*/

-- infoPanel's own text (used by the hover handlers below) and its free/premium
-- child labels (permanently showing "Reward for Free/Premium Accounts: ...")
-- occupy the same screen space. Hide the labels while a hover explanation is
-- showing, and restore them once the hover ends, so they don't overlap.
local function hideRewardAccountLabels()
    rewardWallController.ui.infoPanel.free:setVisible(false)
    rewardWallController.ui.infoPanel.premium:setVisible(false)
end

local function showRewardAccountLabels()
    rewardWallController.ui.infoPanel.free:setVisible(true)
    rewardWallController.ui.infoPanel.premium:setVisible(true)
end

function rewardWallController:onhoverBonus(event)
    if not event.value then
        rewardWallController.ui.infoPanel:setText("")
        showRewardAccountLabels()
        return
    end
    hideRewardAccountLabels()

    local id = event.target:getId()
    local index = tonumber(id:match("%d+"))
    local bonus = bonuses[index]

    if not bonus then
        rewardWallController.ui.infoPanel:setText("Unknown bonus.")
        return
    end

    local isPremium = g_game.getLocalPlayer():isPremium()
    local bonusText = string.format(
        "Allow [color=#909090]%s[/color]%s\nThis bonus is active because you are [color=%s]Premium[/color] and reached a reward streak of at least [color=#44AD25]%d[/color].%s",
        bonus.name, isPremium and "" or "[color=#ff0000](Locked)[/color]", isPremium and "#44AD25" or "#ff0000",
        bonus.id,
        isPremium and ("\n\nActive bonuses: [color=#909090]%s[/color]."):format(getBonusStrings(bonuses)) or "")

    rewardWallController.ui.infoPanel:parseColoredText(bonusText)
end

function rewardWallController:onhoverStatusPlayer(event)
    if not event.value then
        rewardWallController.ui.infoPanel:setText("")
        showRewardAccountLabels()
        return
    end
    hideRewardAccountLabels()

    local playerStatus = {
        rewardStreakIcon = "This explains the reward streak system. You need to claim your daily reward between regular server saves to maintain your streak. At a streak of 2+, your character gets resting area bonuses. Free accounts can reach a maximum bonus at streak level 3, while premium players can reach higher levels. Characters on the same account share the streak.",
        timeLeft = "This is an urgent notification to claim your daily reward within one minute (before the next server save) to raise your reward streak by 1. It mentions that 3 Daily Reward Jokers will be used to prevent resetting your streak. It also encourages raising your streak to benefit from bonuses in resting areas.",
        restingAreaGold = "This explains how Daily Reward Jokers work. They help you maintain your streak on days when you can't claim your daily reward. Each character receives one Daily Reward Joker on the first day of each month. The message recommends collecting rewards daily to stay safe."
    }

    local DEFAULT_MESSAGE = "Unknown bonus."

    local id = event.target:getId()
    local info = playerStatus[id]
    rewardWallController.ui.infoPanel:parseColoredText(info or DEFAULT_MESSAGE)
end

function rewardWallController:onhoverRewardType(event)
    if not event.value then
        rewardWallController.ui.infoPanel.free:setText("")
        rewardWallController.ui.infoPanel.premium:setText("")
        return
    end

    local itemsToSelect = event.target.itemsToSelect or {1, 1}
    local freeAmount = 0
    local premiumAmount = 0

    if type(itemsToSelect) == "table" then
        freeAmount = itemsToSelect[2] or 0
        premiumAmount = itemsToSelect[1] or 0
    else
        freeAmount = itemsToSelect
        premiumAmount = itemsToSelect
    end

    local rewardType = event.target.bundleType
    local rewardTexts = {}

    if rewardType == bundleType.ITEMS then
        rewardTexts = {
            free = string.format(
                "Reward for Free Accounts:\nPick %d items from the list. Among\nother items it contains: health\npotion, a fire bomb rune, a\nthundestorm rune.",
                freeAmount),
            premium = string.format(
                "Reward for Premium Accounts:\nPick %d items from the list. Among\nother items it contains: health\npotion, a fire bomb rune, a\nthundestorm rune.",
                premiumAmount)
        }
    elseif rewardType == bundleType.PREY then
        rewardTexts = {
            free = string.format("Reward for Free Accounts:\n * %d x Prey Wildcard", freeAmount),
            premium = string.format("Reward for Premium Accounts:\n * %d x Prey Wildcard", premiumAmount)
        }
    elseif rewardType == bundleType.XPBOOST then
        rewardTexts = {
            free = string.format("Reward for Free Accounts:\n * %d minutes 50%% XP Boost", freeAmount),
            premium = string.format("Reward for Premium Accounts:\n * %d minutes 50%% XP Boost", premiumAmount)
        }
    else
        print("WARNING: Unknown rewardType:", rewardType)
        return
    end

    rewardWallController.ui.infoPanel.free:setText(rewardTexts.free)
    rewardWallController.ui.infoPanel.premium:setText(rewardTexts.premium)
end

function rewardWallController:onhoverStatusReward(event)
    local statusReward = {
        [STATUS.COLLECTED] = "You have already collected this daily reward.\nThe daily rewards follow a specific cycle where each day you claim it, you get another reward. The cycle repeats after 7 claimed rewards. You will be able to claim this daily reward again as soon as you have reached this postion in the next cycle.",
        [STATUS.ACTIVE] = "The daily reward can be claimed now.\nIf you claim this reward now, it will cost you one Instant Reward Access.\nGet your daily reward for free by visiting a reward shrine.\nYou did not claim your daily reward in time.\nToo bad, you do not have enough Daily Reward Jokers.",
        [STATUS.LOCKED] = "This daily reward is still locked.\nFirst collect the previous daily rewards of this cycle."
    }
    if not event.value then
        rewardWallController.ui.infoPanel:setText("")
        showRewardAccountLabels()
        return
    end
    hideRewardAccountLabels()
    rewardWallController.ui.infoPanel:setText(statusReward[event.target.status])
end

-- /*=============================================
-- =            Auxiliar Windows pickReward      =
-- =============================================*/

function onClickBtnOk()
    if table.empty(actualUsed) then
        return
    end
    local box = bonusShrine == OPEN_WINDOWS.SHRINE and CONST_WINDOWS_BOX.CONFIRMATION_SHRINE or CONST_WINDOWS_BOX.CONFIRMATION_IRA
    managerMessageBoxWindow(box)
end

function destroyPickReward(bool)
    windowsPickWindow = destroyWindows(windowsPickWindow)

    if bool then
        rewardWallController.ui:show()
        rewardWallController.ui:raise()
        rewardWallController.ui:focus()
    end
end

function onTextChangeChangeNumber(getPanel)
    if not getPanel.itemsToSelect then
        return
    end

    local alreadyUsed = 0
    local itemId = getPanel:getChildById('item'):getItemId()
    local thisPanelUsed = actualUsed[itemId] or 0

    for _, count in pairs(actualUsed) do
        alreadyUsed = alreadyUsed + (count or 0)
    end

    local numberField = getPanel:getChildById('number')
    local currentValue = tonumber(numberField:getText()) or 0
    local maxAllowed = getPanel.itemsToSelect - (alreadyUsed - thisPanelUsed)

    if currentValue > maxAllowed then
        numberField:setText(maxAllowed)
    end
    actualUsed[itemId] = tonumber(numberField:getText()) or 0
    alreadyUsed = 0
    for _, count in pairs(actualUsed) do
        alreadyUsed = alreadyUsed + (count or 0)
    end
    local color = alreadyUsed == 0 and "#D33C3C" or "#00FF00"
    windowsPickWindow:getChildById('btnOk'):setEnabled(alreadyUsed > 0)

    local text = string.format("You have selected [color=%s]%d[/color] of %d reward items", color, alreadyUsed,
        getPanel.itemsToSelect)
    windowsPickWindow:getChildById('rewardLabel'):parseColoredText(text)
    getPanel:getChildById('weight'):setText(string.format("%.2f oz", actualUsed[itemId] * getPanel.totalWeight))
    local totalWeight = 0
    for i, widget in pairs(getPanel:getParent():getChildren()) do
        local weightLabel = widget:getChildById('weight')
        if weightLabel then
            local weightText = weightLabel:getText()
            local weightValue = tonumber(weightText:match("([%d%.]+)"))
            if weightValue then
                totalWeight = totalWeight + weightValue
            end
        end
    end
    windowsPickWindow:getChildById("weight"):setText(string.format("Total weight: %.2f oz", totalWeight))
    windowsPickWindow:getChildById("weight"):resizeToText()
end

-- /*=============================================
-- =            Auxiliar GeneralBox             =
-- =============================================*/
function displayGeneralBox3(title, message, buttons, onEnterCallback, onEscapeCallback)
    if generalBox then
        generalBox = destroyWindows(generalBox)
    end

    generalBox = g_ui.createWidget('MessageBoxWindow', rootWidget)
    if not generalBox then
        return nil
    end

    local titleWidget = generalBox:getChildById('title')
    if titleWidget then
        titleWidget:setText(title)
    end

    local holder = generalBox:getChildById('holder')
    if holder and buttons then
        for i = 1, #buttons do
            local button = g_ui.createWidget('Button', holder)
            local buttonId = buttons[i].text:lower():gsub(" ", "_")

            button:setId(buttonId)
            button:setText(buttons[i].text)
            button:setWidth(math.max(86, 10 + (string.len(buttons[i].text) * 8)))
            button:setHeight(20)
            button:setMarginTop(-5)

            if i == 1 then
                button:addAnchor(AnchorTop, 'parent', AnchorTop)
                button:addAnchor(AnchorRight, 'parent', AnchorRight)
            else
                button:addAnchor(AnchorTop, 'parent', AnchorTop)
                button:addAnchor(AnchorRight, 'prev', AnchorLeft)
                button:setMarginRight(5)
            end
            button.onClick = buttons[i].callback
        end
    end
    if onEnterCallback then
        generalBox.onEnter = onEnterCallback
    end
    if onEscapeCallback then
        generalBox.onEscape = onEscapeCallback
    end

    local content = generalBox:getChildById('content')
    if not content then
        generalBox = destroyWindows(generalBox)

        return nil
    end

    content:setText(message)
    content:resizeToText()

    local contentWidth = content:getWidth() + 32
    local contentHeight = content:getHeight() + 42 + (holder and holder:getHeight() or 0)
    generalBox:setWidth(math.min(916, math.max(300, contentWidth)))
    generalBox:setHeight(math.min(616, math.max(119, contentHeight)))

    generalBox.setContent = function(self, newMessage)
        local content = generalBox:getChildById('content')
        if not content then
            return
        end

        content:setText(newMessage)
        content:resizeToText()
        content:setTextWrap(false)
        content:setTextAutoResize(false)

        local holder = generalBox:getChildById('holder')
        if not holder then
            return
        end

        local contentWidth = content:getWidth() + 32
        local contentHeight = content:getHeight() + 50 + holder:getHeight()
        generalBox:setWidth(math.min(736, math.max(300, contentWidth)))
        generalBox:setHeight(math.min(300, math.max(89, contentHeight)))
    end

    generalBox.setTitle = function(self, newTitle)
        local titleWidget = generalBox:getChildById('title')
        if not titleWidget then
            return
        end

        titleWidget:setText(newTitle)
    end
    generalBox.modifyButton = function(self, buttonId, newText, newCallback)
        local holder = generalBox:getChildById('holder')
        if not holder then
            return nil
        end

        local button = holder:getChildById(buttonId)
        if button then
            if newText then
                button:setText(newText)
                button:setWidth(math.max(86, 10 + (string.len(newText) * 8)))
            end
            if newCallback then
                disconnect(button, {
                    onClick = button.onClick
                })
                connect(button, {
                    onClick = newCallback
                })
                button.onClick = newCallback
            end
        end
        return button
    end
    generalBox:show()
    generalBox:raise()
    generalBox:focus()
    return generalBox
end

function managerMessageBoxWindow(id)
    local config = BOX_CONFIGS[id]
    if not config then
        return
    end

    local cancelCallback = function()
        generalBox, windowsPickWindow = destroyWindows({generalBox, windowsPickWindow})
        rewardWallController.ui:show()
        rewardWallController.ui:raise()
        rewardWallController.ui:focus()
    end

    local okCallback = config.okCallback or function()
        generalBox, windowsPickWindow = destroyWindows({generalBox, windowsPickWindow})
        rewardWallController.ui:show()
        rewardWallController.ui:raise()
        rewardWallController.ui:focus()
    end

    local standardButtons = {{
        text = "cancel",
        callback = cancelCallback
    }, {
        text = "ok",
        callback = okCallback
    }}

    generalBox = displayGeneralBox3(config.title, config.content, standardButtons)

    rewardWallController.ui:hide()

    if windowsPickWindow then
        windowsPickWindow = destroyWindows(windowsPickWindow)
    end
end
