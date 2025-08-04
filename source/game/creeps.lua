import "utils/constants"

Creeps = {}

function Creeps:new()
    local instance = {
        creeps = {},
        spawnTimer = 0,
        creepsToSpawn = 0,
        spawnDelay = 30,
        waveComplete = false
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function Creeps:startWave(level)
    self.creeps = {}
    self.creepsToSpawn = 5 + level * 2
    self.spawnTimer = 0
    self.waveComplete = false
    self.spawnDelay = math.max(15, 30 - level * 3)
end

function Creeps:update()
    if self.creepsToSpawn > 0 then
        self.spawnTimer += 1
        if self.spawnTimer >= self.spawnDelay then
            self:spawnCreep()
            self.spawnTimer = 0
            self.creepsToSpawn -= 1
        end
    end
    
    for i = #self.creeps, 1, -1 do
        local creep = self.creeps[i]
        
        if creep.hp <= 0 then
            table.remove(self.creeps, i)
        else
            creep.x += creep.speed
            
            if creep.x >= 400 then
                creep.reachedBase = true
            end
        end
    end
    
    if self.creepsToSpawn <= 0 and #self.creeps == 0 then
        self.waveComplete = true
    end
end

function Creeps:spawnCreep()
    table.insert(self.creeps, {
        x = 0,
        y = 120 + math.random(-40, 40),
        hp = Constants and Constants.CREEP_HP or 50,
        maxHp = Constants and Constants.CREEP_HP or 50,
        speed = Constants and Constants.CREEP_SPEED or 1.5,
        reachedBase = false
    })
end

function Creeps:checkBaseDamage()
    local damage = 0
    for i = #self.creeps, 1, -1 do
        local creep = self.creeps[i]
        if creep.reachedBase then
            damage += (Constants and Constants.CREEP_DAMAGE or 10)
            table.remove(self.creeps, i)
        end
    end
    return damage
end

function Creeps:isWaveComplete()
    return self.waveComplete
end

function Creeps:draw()
    local gfx = playdate.graphics
    
    for _, creep in ipairs(self.creeps) do
        if creep.hp > 0 then
            gfx.fillCircleAtPoint(creep.x, creep.y, 6)
            
            local barWidth = 20
            local barHeight = 3
            local barX = creep.x - barWidth / 2
            local barY = creep.y - 12
            
            gfx.drawRect(barX, barY, barWidth, barHeight)
            local hpWidth = (creep.hp / creep.maxHp) * (barWidth - 2)
            if hpWidth > 0 then
                gfx.fillRect(barX + 1, barY + 1, hpWidth, barHeight - 2)
            end
        end
    end
    
    if self.creepsToSpawn > 0 then
        gfx.drawTextAligned("Enemies: " .. self.creepsToSpawn, 200, 220, kTextAlignment.center)
    end
end

