import "game/grid"

BubbleState = {}

function BubbleState:new()
    local instance = {
        grid = nil,
        shotsRemaining = 10,
        level = 1
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function BubbleState:enter(gameData)
    self.grid = Grid:new()
    self.shotsRemaining = gameData.shotsPerLevel or 10
    self.level = gameData.level or 1
    self.grid:setupLevel(self.level)
end

function BubbleState:exit()
end

function BubbleState:update()
    if self.shotsRemaining <= 0 and not self.grid.projectile then
        return "tower"
    end
    
    if self.grid:checkGameOver() then
        return "gameOver"
    end
    
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if self.grid:shootBubble() then
            self.shotsRemaining -= 1
        end
    end
    
    self.grid:update()
    return "bubble"
end

function BubbleState:draw()
    local gfx = playdate.graphics
    gfx.clear()
    
    self.grid:draw()
end

function BubbleState:getGameData()
    return {
        grid = self.grid,
        level = self.level
    }
end

