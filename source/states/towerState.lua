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
    
    -- Pass bubble and Tier 1 sprites from the grid to towers system
    if gameData.grid and gameData.grid.bubbleSprites then
        self.towers.bubbleSprites = gameData.grid.bubbleSprites
    end
    
    if gameData.grid and gameData.grid.tier1Sprites then
        self.towers.tier1Sprites = gameData.grid.tier1Sprites
    end
    
    if gameData.mergedBallData then
        self.towers:convertFromMergedBalls(gameData.mergedBallData)
    else
        -- Fallback to old method if no merged ball data available
        self.towers:convertFromGrid(gameData.grid)
    end
    
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
    
    -- UI elements hidden for cleaner tower defense experience
    -- gfx.drawTextAligned("HP: " .. self.baseHp, 50, 10, kTextAlignment.left)
    -- gfx.drawTextAligned("Level: " .. self.level, 350, 10, kTextAlignment.right)
end

function TowerState:getGameData()
    return {
        level = self.level + 1,
        survivingMergedBalls = self:getSurvivingMergedBalls()
    }
end

function TowerState:getSurvivingMergedBalls()
    -- Convert current tower positions back to merged ball data for next bubble phase
    local survivingBalls = {}
    
    print("=== Collecting surviving merged balls ===")
    for _, tower in ipairs(self.towers.towers) do
        if tower.originalBallType and tower.gridX and tower.gridY then
            -- Use the precise stored grid coordinates
            table.insert(survivingBalls, {
                x = tower.gridX,
                y = tower.gridY,
                type = tower.originalBallType,
                screenX = tower.x,
                screenY = tower.y,
                isTier1 = tower.isTier1,
                tier1Config = tower.tier1Config
            })
            print("Preserving merged ball: Type " .. tower.originalBallType .. " at grid (" .. tower.gridX .. "," .. tower.gridY .. ") screen (" .. tower.x .. "," .. tower.y .. ")")
        end
    end
    print("=== " .. #survivingBalls .. " merged balls will survive to next bubble phase ===")
    
    return survivingBalls
end


