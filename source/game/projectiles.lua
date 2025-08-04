Projectiles = {}

function Projectiles:new()
    local instance = {
        projectiles = {}
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function Projectiles:add(x, y, vx, vy, damage, owner)
    table.insert(self.projectiles, {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        damage = damage or 10,
        owner = owner or "unknown",
        active = true
    })
end

function Projectiles:update()
    for i = #self.projectiles, 1, -1 do
        local proj = self.projectiles[i]
        
        if proj.active then
            proj.x += proj.vx
            proj.y += proj.vy
            
            if self:isOutOfBounds(proj) then
                table.remove(self.projectiles, i)
            end
        else
            table.remove(self.projectiles, i)
        end
    end
end

function Projectiles:isOutOfBounds(projectile)
    return projectile.x < -10 or projectile.x > 410 or 
           projectile.y < -10 or projectile.y > 250
end

function Projectiles:checkCollisions(targets, collisionRadius)
    collisionRadius = collisionRadius or 5
    local hits = {}
    
    for i = #self.projectiles, 1, -1 do
        local proj = self.projectiles[i]
        
        if proj.active then
            for j, target in ipairs(targets) do
                if target.active ~= false then
                    local dx = proj.x - target.x
                    local dy = proj.y - target.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    
                    if dist <= collisionRadius then
                        table.insert(hits, {
                            projectile = proj,
                            target = target,
                            damage = proj.damage
                        })
                        proj.active = false
                        break
                    end
                end
            end
        end
    end
    
    return hits
end

function Projectiles:removeInactive()
    for i = #self.projectiles, 1, -1 do
        if not self.projectiles[i].active then
            table.remove(self.projectiles, i)
        end
    end
end

function Projectiles:clear()
    self.projectiles = {}
end

function Projectiles:draw()
    local gfx = playdate.graphics
    
    for _, proj in ipairs(self.projectiles) do
        if proj.active then
            gfx.fillCircleAtPoint(proj.x, proj.y, 2)
        end
    end
end

function Projectiles:getCount()
    return #self.projectiles
end

