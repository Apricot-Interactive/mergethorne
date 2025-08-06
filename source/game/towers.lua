import "utils/constants"

Towers = {}

function Towers:new()
    local instance = {
        towers = {},
        projectiles = {},
        bubbleSprites = {}, -- Will store references to bubble sprites
        tier1Sprites = {} -- Will store references to Tier 1 sprites
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
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
            x = ballData.screenX,
            y = ballData.screenY,
            type = towerType,
            range = Constants and Constants.TOWER_RANGE or 80,
            damage = damage,
            fireRate = Constants and Constants.TOWER_FIRE_RATE or 20,
            lastShot = 0,
            originalBallType = ballData.type, -- Store original for sprite rendering
            isTier1 = ballData.isTier1 or false,
            tier1Config = ballData.tier1Config,
            gridX = ballData.x, -- Store original grid coordinates
            gridY = ballData.y
        })
        print("Created tower: Type " .. towerType .. " (Tier1: " .. tostring(ballData.isTier1) .. ") at screen (" .. ballData.screenX .. "," .. ballData.screenY .. ") grid (" .. ballData.x .. "," .. ballData.y .. ")")
    end
    print("=== Tower conversion complete. " .. #self.towers .. " towers created ===")
end

function Towers:update(creeps)
    for _, tower in ipairs(self.towers) do
        tower.lastShot += 1
        
        if tower.lastShot >= tower.fireRate then
            local target = self:findTarget(tower, creeps.creeps)
            if target then
                self:shootAt(tower, target)
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

function Towers:findTarget(tower, creeps)
    local closest = nil
    local closestDist = tower.range
    
    for _, creep in ipairs(creeps) do
        if creep.hp > 0 then
            local dist = math.sqrt((tower.x - creep.x)^2 + (tower.y - creep.y)^2)
            if dist < closestDist then
                closest = creep
                closestDist = dist
            end
        end
    end
    
    return closest
end

function Towers:shootAt(tower, target)
    local dx = target.x - tower.x
    local dy = target.y - tower.y
    local dist = math.sqrt(dx^2 + dy^2)
    
    table.insert(self.projectiles, {
        x = tower.x,
        y = tower.y,
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
    local gfx = playdate.graphics
    
    for _, tower in ipairs(self.towers) do
        if tower.isTier1 and tower.tier1Config then
            -- Draw Tier 1 tower using appropriate sprite  
            local spriteIndex = Constants.TIER1_SPRITE_INDICES[tower.tier1Config][tower.originalBallType]
            if spriteIndex and self.tier1Sprites[spriteIndex] then
                -- Position sprite to align with bubble radius
                local spriteX = tower.x - 7.5  -- Half of bubble radius (15px / 2)
                local spriteY = tower.y - 7.5  -- Half of bubble radius
                self.tier1Sprites[spriteIndex]:draw(spriteX, spriteY)
            else
                -- Fallback for Tier 1
                gfx.fillRect(tower.x - 15, tower.y - 13.5, 30, 27)
            end
        elseif tower.originalBallType and self.bubbleSprites[tower.originalBallType] then
            -- Draw using the bubble sprite from the original merged ball
            self.bubbleSprites[tower.originalBallType]:drawCentered(tower.x, tower.y)
        else
            -- Fallback to rectangle if no sprite available
            gfx.drawRect(tower.x - 8, tower.y - 8, 16, 16)
        end
    end
    
    for _, proj in ipairs(self.projectiles) do
        gfx.fillCircleAtPoint(proj.x, proj.y, 2)
    end
end

