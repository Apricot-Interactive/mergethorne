import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics

MenuState = {}

function MenuState:new()
    local state = {}
    setmetatable(state, self)
    self.__index = self
    
    state.selectedOption = 1
    state.options = {"Play"}
    
    return state
end

function MenuState:enter()
    
end

function MenuState:exit()
    
end

function MenuState:update()
    if pd.buttonJustPressed(pd.kButtonA) then
        if self.selectedOption == 1 then
            return "bubble"
        end
    end
    
    return nil
end

function MenuState:draw()
    gfx.clear()
    
    gfx.setFont(gfx.getSystemFont(gfx.kFontVariantBold))
    local titleText = "Towers of Mergethorne"
    local titleWidth = gfx.getTextSize(titleText)
    gfx.drawTextAligned(titleText, 200, 100, kTextAlignment.center)
    
    gfx.setFont(gfx.getSystemFont(gfx.kFontVariantNormal))
    local optionY = 160
    for i, option in ipairs(self.options) do
        local prefix = ""
        if i == self.selectedOption then
            prefix = "* "
        else
            prefix = "  "
        end
        gfx.drawText(prefix .. option, 180, optionY + (i-1) * 25)
    end
end