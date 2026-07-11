-- @docclass
UIButton = extends(UIWidget, 'UIButton')

function UIButton.create()
    local button = UIButton.internalCreate()
    button:setFocusable(false)
    button.cursorPushed = false
    return button
end

function UIButton:onMouseRelease(pos, button)
    return self:isPressed()
end

function UIButton:onDestroy()
    if self.cursorPushed then
        g_window.restoreMouseCursor()
        self.cursorPushed = false
    end
end

function UIButton:onHoverChange(hovered)
    if not modules.client_options then
        UIWidget.onHoverChange(self, hovered)
        return
    end

    local nativeCursor = modules.client_options.getOption('nativeCursor')

    if nativeCursor then
        if hovered then
            if not self.cursorPushed then
                g_window.setSystemCursor('arrow')
                self.cursorPushed = true
            end
        else
            if self.cursorPushed then
                g_window.restoreMouseCursor()
                self.cursorPushed = false
            end
        end
    end
    UIWidget.onHoverChange(self, hovered)
end
