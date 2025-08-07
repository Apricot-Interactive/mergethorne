import "game/towers"
import "game/creeps"
import "utils/constants"

TowerState = {}

function TowerState:new()
    local instance = {
        towers = nil,
        creeps = nil,
        baseHp = 100,
        level = 1,
        -- Flyoff animation state
        flyoffPhase = false,
        preFlyoffDelay = 0,  -- Delay before starting flyoff
        flyoffDelay = 0,
        flyoffTowers = {},
        completedTowers = {}  -- Towers that have flown off screen
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function TowerState:enter(gameData)
    self.level = gameData.level or 1
    self.baseHp = 100
    
    -- Keep the grid from the previous phase for consistent positioning
    self.grid = gameData.grid
    
    self.towers = Towers:new()
    
    -- Pass bubble and Tier 1 sprites from the grid to towers system
    if self.grid and self.grid.bubbleSprites then
        self.towers.bubbleSprites = self.grid.bubbleSprites
    end
    
    if self.grid and self.grid.tier1Sprites then
        self.towers.tier1Sprites = self.grid.tier1Sprites
    end
    
    if gameData.mergedBallData then
        self.towers:convertFromMergedBalls(gameData.mergedBallData)
    else
        -- Fallback to old method if no merged ball data available
        self.towers:convertFromGrid(self.grid)
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
    
    if not self.flyoffPhase then
        -- Normal tower defense phase
        self.creeps:update()
        self.towers:update(self.creeps, self.grid)
        
        local damage = self.creeps:checkBaseDamage()
        self.baseHp -= damage
        
        if self.creeps:isWaveComplete() then
            -- Start pre-flyoff delay
            if self.preFlyoffDelay == 0 then
                self.preFlyoffDelay = 1  -- Start counting delay
            else
                self.preFlyoffDelay += 1
                if self.preFlyoffDelay >= 20 then  -- 20 frame delay
                    self:startFlyoffPhase()
                end
            end
        end
    else
        -- Flyoff animation phase
        self:updateFlyoffPhase()
        
        -- Check if flyoff is complete
        if self:isFlyoffComplete() then
            if self.level >= 3 then
                return "win"
            else
                return "bubble"
            end
        end
    end
    
    return "tower"
end

function TowerState:draw()
    local gfx = playdate.graphics
    gfx.clear()
    
    if not self.flyoffPhase then
        -- Normal tower defense phase
        -- Draw the grid with only elite/Tier1 bubbles (the towers) - this ensures perfect positioning
        if self.grid then
            self.grid:draw(true, "tower", nil) -- Show all bubbles, tower mode, no shot counter
        end
        
        -- Draw tower projectiles and creeps on top
        self.towers:drawProjectiles()
        self.creeps:draw()
    else
        -- Flyoff phase - draw grid without towers, plus flying towers
        if self.grid then
            self.grid:draw(false, "tower", nil) -- Hide elite/Tier1 bubbles during flyoff
        end
        
        -- Draw flying towers
        for _, tower in ipairs(self.flyoffTowers) do
            local bubble = self.grid.cells[tower.originalData.gridX] and 
                          self.grid.cells[tower.originalData.gridX][tower.originalData.gridY]
            if bubble then
                if bubble.isTier1 then
                    -- Draw Tier 1 tower
                    local spriteIndex = Constants.TIER1_SPRITE_INDICES[bubble.tier1Config][bubble.type]
                    if spriteIndex and self.grid.tier1Sprites[spriteIndex] then
                        local spriteX = tower.x - 15
                        local spriteY = tower.y - 13.5
                        self.grid.tier1Sprites[spriteIndex]:draw(spriteX, spriteY)
                    else
                        gfx.fillRect(tower.x - 15, tower.y - 13.5, 30, 27)
                    end
                else
                    -- Draw regular tower
                    if self.grid.bubbleSprites[bubble.type] then
                        self.grid.bubbleSprites[bubble.type]:drawCentered(tower.x, tower.y)
                    else
                        gfx.drawRect(tower.x - 8, tower.y - 8, 16, 16)
                    end
                end
            end
        end
    end
    
    -- UI elements hidden for cleaner tower defense experience
    -- gfx.drawTextAligned("HP: " .. self.baseHp, 50, 10, kTextAlignment.left)
    -- gfx.drawTextAligned("Level: " .. self.level, 350, 10, kTextAlignment.right)
end


function TowerState:startFlyoffPhase()
    print("=== Starting tower flyoff phase ===")
    self.flyoffPhase = true
    self.flyoffDelay = 20  -- 20 frame delay before starting flyoff
    
    -- Capture exact current tower positions before any state changes
    self.flyoffTowers = {}
    for _, tower in ipairs(self.towers.towers) do
        -- Get the exact current position from grid - this should be stable
        local bubble = self.grid.cells[tower.gridX] and self.grid.cells[tower.gridX][tower.gridY]
        if bubble then
            local towerX, towerY = self.grid:gridToScreen(tower.gridX, tower.gridY)
            
            -- Create flyoff tower data with exact current positions
            table.insert(self.flyoffTowers, {
                x = towerX,
                y = towerY,
                targetY = 120, -- Screen center vertically
                vx = Constants and Constants.BUBBLE_SPEED or 8,
                vy = 0,
                -- Store original tower data for next level
                originalData = {
                    type = tower.type,
                    gridX = tower.gridX,
                    gridY = tower.gridY,
                    bubbleType = self:towerTypeToBubbleType(tower),
                    isTier1 = self:isTowerTier1(tower),
                    tier1Config = self:getTowerTier1Config(tower)
                }
            })
        end
    end
    
    print("Created " .. #self.flyoffTowers .. " flyoff towers from " .. #self.towers.towers .. " total towers")
end

function TowerState:updateFlyoffPhase()
    if self.flyoffDelay > 0 then
        self.flyoffDelay -= 1
        return
    end
    
    -- Update flyoff tower positions
    for i = #self.flyoffTowers, 1, -1 do
        local tower = self.flyoffTowers[i]
        
        -- Move toward target Y position first
        if math.abs(tower.y - tower.targetY) > 2 then
            if tower.y < tower.targetY then
                tower.vy = 2
            else
                tower.vy = -2
            end
        else
            tower.vy = 0
            tower.y = tower.targetY
        end
        
        -- Move horizontally
        tower.x += tower.vx
        tower.y += tower.vy
        
        -- Check if tower has flown off screen
        if tower.x > 400 + 30 then  -- Off right edge + some buffer
            table.insert(self.completedTowers, tower.originalData)
            table.remove(self.flyoffTowers, i)
            print("Tower completed flyoff: " .. tower.originalData.bubbleType .. " (" .. #self.completedTowers .. "/" .. (#self.completedTowers + #self.flyoffTowers) .. " total)")
        end
    end
end

function TowerState:isFlyoffComplete()
    return #self.flyoffTowers == 0 and self.flyoffDelay <= 0
end

function TowerState:towerTypeToBubbleType(tower)
    -- Get the original bubble data from the grid
    if tower.gridX and tower.gridY and self.grid.cells[tower.gridX] and self.grid.cells[tower.gridX][tower.gridY] then
        return self.grid.cells[tower.gridX][tower.gridY].type
    end
    return 6  -- Fallback to elite type 6
end

function TowerState:isTowerTier1(tower)
    -- Check if this tower came from a Tier 1 bubble
    if tower.gridX and tower.gridY and self.grid.cells[tower.gridX] and self.grid.cells[tower.gridX][tower.gridY] then
        local bubble = self.grid.cells[tower.gridX][tower.gridY]
        return bubble.isTier1 or false
    end
    return false
end

function TowerState:getTowerTier1Config(tower)
    -- Get the Tier 1 configuration if applicable
    if tower.gridX and tower.gridY and self.grid.cells[tower.gridX] and self.grid.cells[tower.gridX][tower.gridY] then
        local bubble = self.grid.cells[tower.gridX][tower.gridY]
        return bubble.tier1Config
    end
    return nil
end

function TowerState:getGameData()
    print("TowerState:getGameData() - level " .. self.level .. " passing " .. #(self.completedTowers or {}) .. " flyoff towers")
    return {
        level = self.level + 1,
        -- Pass the completed towers to the next bubble phase
        flyoffTowers = self.completedTowers or {}
    }
end


