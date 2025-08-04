import "game/towers"
import "game/creeps"

TowerState = {}

function TowerState:new()
    local instance = {
        towers = nil,
        creeps = nil,
        baseHp = 100,
        level = 1
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function TowerState:enter(gameData)
    self.level = gameData.level or 1
    self.baseHp = 100
    
    self.towers = Towers:new()
    self.towers:convertFromGrid(gameData.grid)
    
    self.creeps = Creeps:new()
    self.creeps:startWave(self.level)
end

function TowerState:exit()
end

function TowerState:update()
    if self.baseHp <= 0 then
        return "gameOver"
    end
    
    self.creeps:update()
    self.towers:update(self.creeps)
    
    local damage = self.creeps:checkBaseDamage()
    self.baseHp -= damage
    
    if self.creeps:isWaveComplete() then
        if self.level >= 3 then
            return "win"
        else
            return "bubble"
        end
    end
    
    return "tower"
end

function TowerState:draw()
    local gfx = playdate.graphics
    gfx.clear()
    
    self.towers:draw()
    self.creeps:draw()
    
    gfx.drawTextAligned("HP: " .. self.baseHp, 50, 10, kTextAlignment.left)
    gfx.drawTextAligned("Level: " .. self.level, 350, 10, kTextAlignment.right)
end

function TowerState:getGameData()
    return {
        level = self.level + 1
    }
end

