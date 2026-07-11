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
    -- Clean up cursor if it was pushed
    if self.cursorPushed then
        if modules.client_options and modules.client_options.getOption('nativeCursor') then
            g_window.restoreMouseCursor()
        else
            g_mouse.popCursor('pointerbutton')
        end
        self.cursorPushed = false
    end
end

function UIButton:onHoverChange(hovered)
    if not modules.client_options then
        UIWidget.onHoverChange(self, hovered)
        return
    end
    
    local nativeCursor = modules.client_options.getOption('nativeCursor')
    local animatedCursor = modules.client_options.getOption('showAnimatedCursor')
    
    if animatedCursor and not nativeCursor then
        if hovered then
            if not self.cursorPushed then
                g_mouse.pushCursor('default')
                self.cursorPushed = true
            end
        else
            if self.cursorPushed then
                g_mouse.popCursor('default')
                self.cursorPushed = false
            end
        end
    elseif nativeCursor then
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
