import "game/grid"

BubbleState = {}

function BubbleState:new()
    local instance = {
        grid = nil,
        shotsRemaining = 10,
        level = 1,
        -- Transition state variables
        transitionState = "playing", -- "starting", "playing", "waitingAfterLand", "despawning", "waitingAfterDespawn", "ready"
        transitionFrames = 0,
        mergedBallData = {}, -- Store positions and types of merged balls for tower phase
        showNewBubbles = true -- Controls whether new basic bubbles are visible
    }
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function BubbleState:enter(gameData)
    self.grid = Grid:new()
    self.shotsRemaining = gameData.shotsPerLevel or 10
    self.level = gameData.level or 1
    
    -- Setup level with potential pre-existing merged balls
    if gameData.survivingMergedBalls then
        -- Start with transition state to show merged balls first, then new ones
        self.transitionState = "starting"
        self.transitionFrames = 0
        self.showNewBubbles = false
        self.grid:setupLevelWithMergedBalls(self.level, gameData.survivingMergedBalls)
    else
        -- Fresh start - show everything immediately
        self.transitionState = "playing"
        self.transitionFrames = 0
        self.showNewBubbles = true
        self.grid:setupLevel(self.level)
    end
    
    self.mergedBallData = {}
end

function BubbleState:exit()
end

function BubbleState:update()
    if self.grid:checkGameOver() then
        return "gameOver"
    end
    
    -- Handle starting transition (showing new bubbles after delay)
    if self.transitionState == "starting" then
        self.transitionFrames += 1
        if self.transitionFrames >= 20 then
            self.transitionState = "playing"
            self.showNewBubbles = true
            print("=== New basic bubbles now visible ===")
        end
        return "bubble"
    end
    
    -- Handle transition sequence when shots are exhausted
    if self.shotsRemaining <= 0 then
        return self:handleTransitionSequence()
    end
    
    -- Normal gameplay
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if self.grid:shootBubble() then
            self.shotsRemaining -= 1
        end
    end
    
    self.grid:update()
    return "bubble"
end

function BubbleState:handleTransitionSequence()
    if self.transitionState == "playing" then
        -- Check if projectile is still in flight
        if self.grid.projectile then
            self.grid:update()
            return "bubble"
        else
            -- Final ball has landed, start first wait period
            self.transitionState = "waitingAfterLand"
            self.transitionFrames = 0
        end
    elseif self.transitionState == "waitingAfterLand" then
        self.transitionFrames += 1
        if self.transitionFrames >= 20 then
            -- Wait period complete, start despawning non-merged balls
            self.transitionState = "despawning"
            self.transitionFrames = 0
            self:despawnNonMergedBalls()
        end
    elseif self.transitionState == "despawning" then
        -- Instant despawn, move to second wait
        self.transitionState = "waitingAfterDespawn"
        self.transitionFrames = 0
    elseif self.transitionState == "waitingAfterDespawn" then
        self.transitionFrames += 1
        if self.transitionFrames >= 20 then
            -- Second wait complete, ready to transition
            self.transitionState = "ready"
        end
    elseif self.transitionState == "ready" then
        -- Transition to tower defense
        return "tower"
    end
    
    return "bubble"
end

function BubbleState:despawnNonMergedBalls()
    print("=== Despawning non-merged balls ===")
    self.mergedBallData = {}
    
    -- Scan grid and keep only merged balls (type > 5)
    for x = 1, self.grid.width do
        for y = 1, self.grid.height do
            local bubble = self.grid.cells[x][y]
            if bubble then
                if bubble.type > 5 or bubble.isTier1 then
                    -- This is a merged ball (elite or Tier 1), keep it and log it
                    local screenX, screenY = self.grid:gridToScreen(x, y)
                    table.insert(self.mergedBallData, {
                        x = x,
                        y = y,
                        type = bubble.type,
                        screenX = screenX,
                        screenY = screenY,
                        isTier1 = bubble.isTier1 or false,
                        tier1Config = bubble.tier1Config
                    })
                    print("Keeping merged ball: Type " .. bubble.type .. " (Tier1: " .. tostring(bubble.isTier1) .. ") at grid (" .. x .. "," .. y .. ") screen (" .. screenX .. "," .. screenY .. ")")
                else
                    -- This is a basic ball, remove it
                    print("Despawning basic ball: Type " .. bubble.type .. " at grid (" .. x .. "," .. y .. ")")
                    self.grid.cells[x][y] = nil
                end
            end
        end
    end
    
    print("=== Despawn complete. " .. #self.mergedBallData .. " merged balls remaining ===")
end

function BubbleState:draw()
    local gfx = playdate.graphics
    gfx.clear()
    
    self.grid:draw(self.showNewBubbles, self.transitionState, self.shotsRemaining)
end

function BubbleState:getGameData()
    return {
        grid = self.grid,
        level = self.level,
        mergedBallData = self.mergedBallData
    }
end

