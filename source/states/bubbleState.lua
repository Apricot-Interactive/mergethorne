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
    self.level = gameData.level or 1
    
    -- Setup shot queue with basic shots + flyoff towers
    self:setupShotQueue(gameData.flyoffTowers or {})
    
    -- Total shots = queue length + 1 (setupNextShots consumed one during init)
    self.shotsRemaining = #self.shotQueue + 1
    
    -- Setup level with potential pre-existing merged balls
    if gameData.survivingMergedBalls and #gameData.survivingMergedBalls > 0 then
        -- Start with transition state to show merged balls first, then new ones
        self.transitionState = "starting"
        self.transitionFrames = 0
        self.showNewBubbles = false
        self.grid:setupLevelWithMergedBalls(self.level, gameData.survivingMergedBalls)
    else
        -- Fresh start - show everything immediately (no surviving merged balls)
        self.transitionState = "playing"
        self.transitionFrames = 0
        self.showNewBubbles = true
        self.grid:setupLevel(self.level)
    end
    
    self.mergedBallData = {}
end

function BubbleState:setupShotQueue(flyoffTowers)
    -- Create DEBUG shot queue: 1 Tier 2 + 6 Tier 1 + 3 basic for level 1
    self.shotQueue = {}
    
    if self.level == 1 then
        -- DEBUG MODE: Custom sequence for level 1
        -- 1 Tier 2 shot first
        table.insert(self.shotQueue, {
            type = "tier2",
            bubbleType = 16,  -- Tier 2 unified type
            isTier1 = false,
            isTier2 = true,
            tier1Config = nil
        })
        
        -- 6 Tier 1 shots (random types 11-15)
        for i = 1, 6 do
            table.insert(self.shotQueue, {
                type = "tier1",
                bubbleType = math.random(11, 15),
                isTier1 = true,
                isTier2 = false,
                tier1Config = "UP"  -- Use UP configuration for debug mode
            })
        end
        
        -- 3 basic shots (types 1-5)
        for i = 1, 3 do
            table.insert(self.shotQueue, {
                type = "basic",
                bubbleType = math.random(1, 5),
                isTier1 = false,
                isTier2 = false,
                tier1Config = nil
            })
        end
        
    else
        -- Normal mode for other levels: 10 basic shots + flyoff towers in random order
        for i = 1, 10 do
            table.insert(self.shotQueue, {
                type = "basic",
                bubbleType = math.random(1, 5)
            })
        end
        
        -- Add flyoff towers
        for _, tower in ipairs(flyoffTowers) do
            table.insert(self.shotQueue, {
                type = "tower",
                bubbleType = tower.bubbleType,
                isTier1 = tower.isTier1,
                tier1Config = tower.tier1Config
            })
        end
        
        -- Shuffle the entire queue for non-debug levels
        for i = #self.shotQueue, 2, -1 do
            local j = math.random(i)
            self.shotQueue[i], self.shotQueue[j] = self.shotQueue[j], self.shotQueue[i]
        end
    end
    
    -- Record original shot count before setupNextShots consumes one
    local originalShotCount = #self.shotQueue
    
    -- Set initial shots
    self:setupNextShots()
    
end

function BubbleState:setupNextShots()
    if #self.shotQueue > 0 then
        local currentShot = table.remove(self.shotQueue, 1)
        self.grid.nextBubbleType = currentShot.bubbleType
        self.grid.nextBubbleIsTier1 = currentShot.isTier1 or false
        self.grid.nextBubbleTier1Config = currentShot.tier1Config
        
        -- Handle Tier 2 bubbles (type 16)
        if currentShot.bubbleType == 16 or currentShot.isTier2 then
            self.grid.nextBubbleIsTier2 = true
        else
            self.grid.nextBubbleIsTier2 = false
        end
    else
        self.grid.nextBubbleType = math.random(1, 5)
        self.grid.nextBubbleIsTier1 = false
        self.grid.nextBubbleIsTier2 = false
        self.grid.nextBubbleTier1Config = nil
    end
    
    if #self.shotQueue > 0 then
        local previewShot = self.shotQueue[1]  -- Don't remove, just peek
        self.grid.previewBubbleType = previewShot.bubbleType
        self.grid.previewBubbleIsTier1 = previewShot.isTier1 or false
        self.grid.previewBubbleIsTier2 = previewShot.isTier2 or false
        self.grid.previewBubbleTier1Config = previewShot.tier1Config
    else
        self.grid.previewBubbleType = math.random(1, 5)
        self.grid.previewBubbleIsTier1 = false
        self.grid.previewBubbleIsTier2 = false
        self.grid.previewBubbleTier1Config = nil
    end
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
            -- Setup next shot from queue
            self:setupNextShots()
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
                else
                    -- This is a basic ball, remove it
                    self.grid.cells[x][y] = nil
                end
            end
        end
    end
    
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

