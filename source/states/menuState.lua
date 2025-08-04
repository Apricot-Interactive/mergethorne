MenuState = {}

function MenuState:new()
    local instance = {
        selectedOption = 1,
        options = {"Play"}
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function MenuState:enter()
    self.selectedOption = 1
end

function MenuState:exit()
end

function MenuState:update()
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if self.selectedOption == 1 then
            return "bubble"
        end
    end
    return "menu"
end

function MenuState:getGameData()
    -- Fresh start - clear all persisted game data including surviving merged balls
    print("=== Starting fresh game - clearing all persisted data ===")
    return {
        level = 1,
        shotsPerLevel = 10
        -- No survivingMergedBalls - fresh start
    }
end

function MenuState:draw()
    local gfx = playdate.graphics
    gfx.clear()
    
    gfx.drawTextAligned("TOWERS OF MERGETHORNE", 200, 60, kTextAlignment.center)
    
    local y = 120
    for i, option in ipairs(self.options) do
        local prefix = (i == self.selectedOption) and "• " or "  "
        gfx.drawTextAligned(prefix .. option, 200, y, kTextAlignment.center)
        y += 30
    end
end

