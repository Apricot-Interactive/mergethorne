import "utils/constants"

Towers = {}

function Towers:new()
    local instance = {
        towers = {},
        projectiles = {},
        bubbleSprites = {}, -- Will store references to bubble sprites
        tier1Sprites = {}, -- Will store references to Tier 1 sprites
        -- Grid constants for position calculation
        bubbleRadius = Constants and Constants.BUBBLE_RADIUS or 7.5,
        hexSpacingX = Constants and Constants.HEX_SPACING_X or 15,
        hexSpacingY = Constants and Constants.HEX_SPACING_Y or 13,
        hexOffsetX = Constants and Constants.HEX_OFFSET_X or 7.5,
        gridHeight = Constants and Constants.GRID_HEIGHT or 17
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

-- Convert grid coordinates to screen position (matching grid.lua exactly)
function Towers:gridToScreen(gridX, gridY)
    local screenX = (gridX - 1) * self.hexSpacingX
    local screenY = (gridY - 1) * self.hexSpacingY
    
    -- Offset even rows for hex pattern
    if gridY % 2 == 0 then  
        screenX = screenX + self.hexOffsetX
    end
    
    -- Match grid.lua positioning exactly
    local startX = 50  -- Fixed left margin
    local gridHeight = (self.gridHeight - 1) * self.hexSpacingY + 2 * self.bubbleRadius
    local startY = (240 - gridHeight) / 2
    
    return startX + screenX + self.bubbleRadius, startY + screenY + self.bubbleRadius
end

-- Set grid parameters from the actual grid instance to ensure exact positioning match
function Towers:setGridParameters(grid)
    self.bubbleRadius = grid.bubbleRadius
    self.hexSpacingX = grid.hexSpacingX
    self.hexSpacingY = grid.hexSpacingY
    self.hexOffsetX = grid.hexOffsetX
    self.gridHeight = grid.height
end

function Towers:convertFromGrid(grid)
    self.towers = {}
    
    for x = 1, grid.width do
        for y = 1, grid.height do
            local bubble = grid.cells[x][y]
            if bubble and (bubble.type > 5 or bubble.isTier1) then
                local towerX, towerY = grid:gridToScreen(x, y)
                local towerType, damage
                
                if bubble.isTier1 then
                    -- Tier 1 bubbles become more powerful towers
                    towerType = bubble.type - 10 -- Types 11-15 -> 1-5
                    damage = (Constants and Constants.TOWER_DAMAGE and Constants.TOWER_DAMAGE[towerType]) or 10
                    damage = damage * 2 -- Tier 1 towers do double damage
                else
                    -- Elite bubbles (6-10) become regular towers
                    towerType = bubble.type - 5
                    damage = (Constants and Constants.TOWER_DAMAGE and Constants.TOWER_DAMAGE[towerType]) or 10
                end
                
                table.insert(self.towers, {
                    x = towerX,
                    y = towerY,
                    type = towerType,
                    range = Constants and Constants.TOWER_RANGE or 80,
                    damage = damage,
                    fireRate = Constants and Constants.TOWER_FIRE_RATE or 20,
                    lastShot = 0,
                    originalBallType = bubble.type, -- Store original for sprite rendering
                    isTier1 = bubble.isTier1 or false,
                    tier1Config = bubble.tier1Config,
                    gridX = x, -- Store original grid coordinates
                    gridY = y
                })
            end
        end
    end
end

function Towers:convertFromMergedBalls(mergedBallData)
    self.towers = {}
    
    print("=== Converting merged balls to towers ===")
    for _, ballData in ipairs(mergedBallData) do
        local towerType, damage
        
        if ballData.isTier1 then
            -- Tier 1 bubbles become more powerful towers
            towerType = ballData.type - 10 -- Types 11-15 -> 1-5
            damage = (Constants and Constants.TOWER_DAMAGE and Constants.TOWER_DAMAGE[towerType]) or 10
            damage = damage * 2 -- Tier 1 towers do double damage
        else
            -- Elite bubbles (6-10) become regular towers
            towerType = ballData.type - 5
            damage = (Constants and Constants.TOWER_DAMAGE and Constants.TOWER_DAMAGE[towerType]) or 10
        end
        
        table.insert(self.towers, {
            type = towerType,
            range = Constants and Constants.TOWER_RANGE or 80,
            damage = damage,
            fireRate = Constants and Constants.TOWER_FIRE_RATE or 20,
            lastShot = 0,
            gridX = ballData.x, -- Store grid coordinates for targeting
            gridY = ballData.y
        })
        print("Created tower: Type " .. towerType .. " (Tier1: " .. tostring(ballData.isTier1) .. ") at grid (" .. ballData.x .. "," .. ballData.y .. ")")
    end
    print("=== Tower conversion complete. " .. #self.towers .. " towers created ===")
end

function Towers:update(creeps, grid)
    for _, tower in ipairs(self.towers) do
        tower.lastShot += 1
        
        if tower.lastShot >= tower.fireRate then
            local target = self:findTarget(tower, creeps.creeps, grid)
            if target then
                self:shootAt(tower, target, grid)
                tower.lastShot = 0
            end
        end
    end
    
    for i = #self.projectiles, 1, -1 do
        local proj = self.projectiles[i]
        proj.x += proj.vx
        proj.y += proj.vy
        
        if proj.x < 0 or proj.x > 400 or proj.y < 0 or proj.y > 240 then
            table.remove(self.projectiles, i)
        else
            local hit = self:checkProjectileHit(proj, creeps.creeps)
            if hit then
                table.remove(self.projectiles, i)
            end
        end
    end
end

function Towers:findTarget(tower, creeps, grid)
    local closest = nil
    local closestDist = tower.range
    
    -- Get tower position from grid
    local towerX, towerY = grid:gridToScreen(tower.gridX, tower.gridY)
    
    for _, creep in ipairs(creeps) do
        if creep.hp > 0 then
            local dist = math.sqrt((towerX - creep.x)^2 + (towerY - creep.y)^2)
            if dist < closestDist then
                closest = creep
                closestDist = dist
            end
        end
    end
    
    return closest
end

function Towers:shootAt(tower, target, grid)
    -- Get tower position from grid
    local towerX, towerY = grid:gridToScreen(tower.gridX, tower.gridY)
    
    local dx = target.x - towerX
    local dy = target.y - towerY
    local dist = math.sqrt(dx^2 + dy^2)
    
    table.insert(self.projectiles, {
        x = towerX,
        y = towerY,
        vx = (dx / dist) * (Constants and Constants.PROJECTILE_SPEED or 6),
        vy = (dy / dist) * (Constants and Constants.PROJECTILE_SPEED or 6),
        damage = tower.damage
    })
end

function Towers:checkProjectileHit(proj, creeps)
    for _, creep in ipairs(creeps) do
        if creep.hp > 0 then
            local dist = math.sqrt((proj.x - creep.x)^2 + (proj.y - creep.y)^2)
            if dist < 8 then
                creep.hp -= proj.damage
                return true
            end
        end
    end
    return false
end

function Towers:draw()
    -- This method is now unused - grid handles tower drawing for perfect positioning
    -- Keeping for backward compatibility
    self:drawProjectiles()
end

function Towers:drawProjectiles()
    local gfx = playdate.graphics
    
    for _, proj in ipairs(self.projectiles) do
        gfx.fillCircleAtPoint(proj.x, proj.y, 2)
    end
end

