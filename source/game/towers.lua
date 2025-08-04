import "utils/constants"

Towers = {}

function Towers:new()
    local instance = {
        towers = {},
        projectiles = {}
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
            if bubble and bubble.type > 5 then
                local towerX, towerY = grid:gridToScreen(x, y)
                table.insert(self.towers, {
                    x = towerX,
                    y = towerY,
                    type = bubble.type - 5,
                    range = Constants and Constants.TOWER_RANGE or 80,
                    damage = (Constants and Constants.TOWER_DAMAGE and Constants.TOWER_DAMAGE[bubble.type - 5]) or 10,
                    fireRate = Constants and Constants.TOWER_FIRE_RATE or 20,
                    lastShot = 0
                })
            end
        end
    end
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
        gfx.drawRect(tower.x - 8, tower.y - 8, 16, 16)
    end
    
    for _, proj in ipairs(self.projectiles) do
        gfx.fillCircleAtPoint(proj.x, proj.y, 2)
    end
end

