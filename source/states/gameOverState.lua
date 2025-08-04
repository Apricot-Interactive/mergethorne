GameOverState = {}

function GameOverState:new()
    local instance = {
        isWin = false,
        message = "",
        restartTimer = 0
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function GameOverState:enter(gameData)
    self.isWin = gameData.isWin or false
    self.message = self.isWin and "YOU WIN!" or "GAME OVER"
    self.restartTimer = 120
end

function GameOverState:exit()
end

function GameOverState:update()
    self.restartTimer -= 1
    
    if self.restartTimer <= 0 or playdate.buttonJustPressed(playdate.kButtonA) then
        return "menu"
    end
    
    return "gameOver"
end

function GameOverState:draw()
    local gfx = playdate.graphics
    gfx.clear()
    
    gfx.drawTextAligned(self.message, 200, 100, kTextAlignment.center)
    
    if self.restartTimer > 60 then
        gfx.drawTextAligned("Press A to continue", 200, 140, kTextAlignment.center)
    elseif self.restartTimer > 0 then
        gfx.drawTextAligned("Returning to menu...", 200, 140, kTextAlignment.center)
    end
end

