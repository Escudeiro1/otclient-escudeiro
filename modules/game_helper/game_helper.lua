HelperController = Controller:new()

HelperButton = nil

function HelperController:onInit()
end

function HelperController:onGameStart()
    if not HelperButton then
        HelperButton = modules.game_mainpanel.addToggleButton(
            "helperButton",
            tr("Helper"),
            "/images/options/button_helper",
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
    if not self.ui then
        self:loadHtml('template/html/main_helper.html')
    end
    self.ui:show()
    self.ui:raise()
    self.ui:focus()
    if HelperButton then
        HelperButton:setOn(true)
    end
end

function HelperController:hide()
    if self.ui then
        self:unloadHtml()
    end
    if HelperButton then
        HelperButton:setOn(false)
    end
end

function HelperController:toggle()
    if self.ui and self.ui:isVisible() then
        self:hide()
    else
        self:show()
    end
end
