-- Mergethorne Grid System - Phase 1: Simplified Core
-- 
-- Architecture Overview:
-- - Single unified cell system: {ballType, occupied, permanent}
-- - 20px hex grid, visual collision detection with immediate snapping
-- - Simple merge detection via flood-fill, animated ball convergence
-- - Extensible structure ready for Phase 2 tier/magnetism systems
--
-- Performance targets: 60fps stable, <400 lines total
-- Design principle: Each function <20 lines, minimal nesting

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Core constants
local BALL_SPEED <const> = 9
local COLLISION_RADIUS <const> = 20
local AIM_LINE_LENGTH <const> = 50
local SHOOTER_IDX <const> = 12 * 20 + 16  -- Bottom center
local TOP_BOUNDARY <const> = 8
local BOTTOM_BOUNDARY <const> = 200
local LEFT_BOUNDARY <const> = 10
local MERGE_ANIMATION_FRAMES <const> = 8
local GAME_OVER_FLASHES <const> = 3

local Grid = {}

-- Sprite loading (Phase 2: Basic + Tier systems)
local function loadBubbleSprites()
    local sprites = {basic = {}, tier1 = {}, tier2 = {}}
    
    -- Load basic sprites
    local basicSheet = gfx.image.new("assets/sprites/bubbles-basic")
    local basicWidth, basicHeight = basicSheet:getSize()
    for i = 1, 5 do
        local spriteWidth = basicWidth / 5
        sprites.basic[i] = gfx.image.new(spriteWidth, basicHeight)
        gfx.pushContext(sprites.basic[i])
        basicSheet:draw(-(i-1) * spriteWidth, 0)
        gfx.popContext()
    end
    
    -- Load tier 1 sprites  
    local tier1Sheet = gfx.image.new("assets/sprites/bubbles-tier-one")
    local tier1Width, tier1Height = tier1Sheet:getSize()
    for i = 1, 5 do
        local spriteWidth = tier1Width / 5
        sprites.tier1[i] = gfx.image.new(spriteWidth, tier1Height)
        gfx.pushContext(sprites.tier1[i])
        tier1Sheet:draw(-(i-1) * spriteWidth, 0)
        gfx.popContext()
    end
    
    -- Load tier 2 sprites
    local tier2Sheet = gfx.image.new("assets/sprites/bubbles-tier-two")
    local tier2Width, tier2Height = tier2Sheet:getSize()
    for i = 1, 10 do
        local spriteWidth = tier2Width / 10
        sprites.tier2[i] = gfx.image.new(spriteWidth, tier2Height)
        gfx.pushContext(sprites.tier2[i])
        tier2Sheet:draw(-(i-1) * spriteWidth, 0)
        gfx.popContext()
    end
    
    return sprites
end

-- Initialize grid system
function Grid:init()
    self.bubbleSprites = loadBubbleSprites()
    self:createGrid()
    self:setupBoundaries()
    self:setupGameState()
end

-- Create hex grid positions and cell structure
function Grid:createGrid()
    self.cells = {}
    self.positions = {}
    
    for row = 1, 15 do
        local cols = (row % 2 == 1) and 20 or 19
        local rowY = (row - 1) * 16 + 8
        local rowX = (row % 2 == 0) and 10 or 0
        
        for col = 1, cols do
            local idx = (row - 1) * 20 + col
            self.positions[idx] = {
                x = rowX + (col - 1) * 20 + 10,
                y = rowY,
                row = row,
                col = col
            }
            self.cells[idx] = {
                ballType = nil,
                occupied = false,
                permanent = false,
                tier = nil  -- Phase 2: "basic", "tier1", "tier2"
            }
        end
    end
end

-- Setup boundary cells (cutouts and walls)
function Grid:setupBoundaries()
    -- Left cutout (center of left edge)
    local leftCutout = {
        {5,1}, {5,2}, {6,1}, {6,2}, {7,1}, {7,2}, {7,3}, {8,1}, {8,2}, {9,1}, {9,2}
    }
    
    -- Bottom boundary
    local bottomBoundary = {}
    for col = 1, 16 do
        bottomBoundary[#bottomBoundary + 1] = {14, col}
        bottomBoundary[#bottomBoundary + 1] = {15, col}
    end
    
    -- Right boundary  
    local rightBoundary = {}
    for row = 1, 15 do
        rightBoundary[#rightBoundary + 1] = {row, 17}
    end
    
    -- Mark all boundary cells as permanent
    for _, boundaries in ipairs({leftCutout, bottomBoundary, rightBoundary}) do
        for _, cell in ipairs(boundaries) do
            local row, col = cell[1], cell[2]
            if self:isValidGridPosition(row, col) then
                local idx = (row - 1) * 20 + col
                self.cells[idx].permanent = true
            end
        end
    end
    
    -- Shooter position is permanent but special
    self.cells[SHOOTER_IDX].permanent = true
end

-- Initialize game state variables
function Grid:setupGameState()
    self.angle = 45
    self.ball = nil
    self.shooterBallType = math.random(1, 5)
    self.onDeckBallType = math.random(1, 5)
    self.shotCounter = 15
    self.gameState = "playing"
    self.showDebug = false
    
    -- Animation system (extensible for Phase 2)
    self.animations = {}
    self.isAnimating = false
    self.gameOverFlashCount = 0
    self.flashTimer = 0
    
    -- Phase 2: Tier tracking systems
    self.tierOnePositions = {}  -- {idx -> {centerX, centerY, ballType, triangle}}
    self.tierTwoPositions = {}  -- {idx -> {centerX, centerY, sprite, pattern}}
    
    -- Precompute aim direction
    self:updateAimDirection()
    
    -- Add starting balls
    self:setupStartingBalls()
end

-- Add initial ball layout
function Grid:setupStartingBalls()
    local startingBalls = {
        -- Basic A (type 1)
        {1, 1, 1}, {1, 2, 1}, {2, 1, 1}, {2, 2, 1},
        {6, 3, 1}, {7, 4, 1}, {8, 3, 1},
        {12, 1, 1}, {12, 2, 1}, {13, 1, 1}, {13, 2, 1},
        -- Basic B (type 2)
        {3, 1, 2}, {3, 2, 2}, {4, 1, 2},
        -- Basic C (type 3)
        {4, 2, 3}, {5, 3, 3},
        -- Basic D (type 4)
        {9, 3, 4}, {10, 2, 4},
        -- Basic E (type 5)
        {10, 1, 5}, {11, 1, 5}, {11, 2, 5}
    }
    
    for _, ball in ipairs(startingBalls) do
        local row, col, ballType = ball[1], ball[2], ball[3]
        if self:isValidGridPosition(row, col) then
            local idx = (row - 1) * 20 + col
            self.cells[idx].ballType = ballType
            self.cells[idx].occupied = true
            self.cells[idx].tier = "basic"
        end
    end
end

-- Validate grid position bounds
function Grid:isValidGridPosition(row, col)
    if row < 1 or row > 15 then return false end
    local maxCol = (row % 2 == 1) and 20 or 19
    return col >= 1 and col <= maxCol
end

-- Update aim direction cache
function Grid:updateAimDirection()
    local radians = math.rad(self.angle)
    self.aimCos = math.cos(radians)
    self.aimSin = math.sin(radians)
end

-- Main game input handling
function Grid:handleInput()
    if self.gameState == "gameOver" then
        if pd.buttonJustPressed(pd.kButtonA) then
            self:init() -- Restart game
        end
        return
    end
    
    -- Aim adjustment
    if pd.buttonIsPressed(pd.kButtonUp) and self.angle < 86 then
        self.angle = self.angle + 2
        self:updateAimDirection()
    elseif pd.buttonIsPressed(pd.kButtonDown) and self.angle > 1 then
        self.angle = self.angle - 2
        self:updateAimDirection()
    elseif pd.buttonJustPressed(pd.kButtonLeft) then
        self.showDebug = not self.showDebug
    elseif pd.buttonJustPressed(pd.kButtonB) then
        self:init() -- Reset level to starting state
    elseif pd.buttonJustPressed(pd.kButtonA) and not self.ball and 
           self.shotCounter > 0 and self.shooterBallType and not self.isAnimating then
        self:shootBall()
    end
end

-- Fire a ball from shooter position  
function Grid:shootBall()
    local shooterPos = self.positions[SHOOTER_IDX]
    self.ball = {
        x = shooterPos.x,
        y = shooterPos.y,
        vx = -self.aimCos * BALL_SPEED,
        vy = -self.aimSin * BALL_SPEED,
        ballType = self.shooterBallType
    }
end

-- Main update loop
function Grid:update()
    if self.gameState == "gameOver" then
        self:updateGameOverFlash()
        return
    end
    
    self:updateAnimations()
    self:updateBall()
end

-- Update ball physics and collision
function Grid:updateBall()
    if not self.ball then return end
    
    -- Move ball
    self.ball.x = self.ball.x + self.ball.vx  
    self.ball.y = self.ball.y + self.ball.vy
    
    -- Check boundaries
    if self.ball.y <= TOP_BOUNDARY or self.ball.y >= BOTTOM_BOUNDARY then
        self.ball.vy = -self.ball.vy
    end
    
    -- Left boundary, cutout boundary, or ball collision
    if self.ball.x <= LEFT_BOUNDARY or self:checkCutoutCollision() or self:checkBallCollision() then
        self:handleBallLanding()
    end
end

-- Check if ball collides with cutout boundary cells
function Grid:checkCutoutCollision()
    -- Check collision with the cutout boundary cells (permanent cells in the cutout area)
    local cutoutCells = {
        {5,1}, {5,2}, {6,1}, {6,2}, {7,1}, {7,2}, {7,3}, {8,1}, {8,2}, {9,1}, {9,2}
    }
    
    for _, cellPos in ipairs(cutoutCells) do
        local row, col = cellPos[1], cellPos[2]
        if self:isValidGridPosition(row, col) then
            local idx = (row - 1) * 20 + col
            local pos = self.positions[idx]
            if pos then
                local dx = self.ball.x - pos.x
                local dy = self.ball.y - pos.y
                local distSq = dx * dx + dy * dy
                -- Use slightly tighter collision for boundary cells
                if distSq <= (15 * 15) then
                    return true
                end
            end
        end
    end
    return false
end

-- Check if ball collides with placed balls (including tier bubbles)
function Grid:checkBallCollision()
    -- Check basic tier balls
    for idx, cell in pairs(self.cells) do
        if cell.occupied and not cell.permanent and cell.tier == "basic" then
            local pos = self.positions[idx]
            if pos then
                local dx = self.ball.x - pos.x
                local dy = self.ball.y - pos.y
                local distSq = dx * dx + dy * dy
                if distSq <= (COLLISION_RADIUS * COLLISION_RADIUS) then
                    return true
                end
            end
        end
    end
    
    -- Check tier 1 bubbles (collision with center point)
    for idx, tierOneData in pairs(self.tierOnePositions) do
        local dx = self.ball.x - tierOneData.centerX
        local dy = self.ball.y - tierOneData.centerY
        local distSq = dx * dx + dy * dy
        if distSq <= (COLLISION_RADIUS * COLLISION_RADIUS) then
            return true
        end
    end
    
    -- Check tier 2 bubbles (collision with center point)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        local dx = self.ball.x - tierTwoData.centerX
        local dy = self.ball.y - tierTwoData.centerY
        local distSq = dx * dx + dy * dy
        if distSq <= (COLLISION_RADIUS * COLLISION_RADIUS) then
            return true
        end
    end
    
    return false
end

-- Handle ball landing after collision
function Grid:handleBallLanding()
    local landingIdx = self:findNearestEmptyCell(self.ball.x, self.ball.y)
    
    if landingIdx and self:isLegalPlacement(landingIdx) then
        -- Place ball successfully
        self.cells[landingIdx].ballType = self.ball.ballType
        self.cells[landingIdx].occupied = true
        self.cells[landingIdx].tier = "basic"  -- Phase 2: New balls are basic tier
        self.ball = nil
        self.shotCounter = self.shotCounter - 1
        
        -- Advance to next ball
        if self.shotCounter > 0 then
            self.shooterBallType = self.onDeckBallType
            if self.shotCounter > 1 then
                self.onDeckBallType = math.random(1, 5)
            end
        else
            -- No more shots - empty the shooter
            self.shooterBallType = nil
        end
        
        -- Check for merges
        self:checkForMerges(landingIdx)
    else
        -- Failed placement - trigger game over sequence
        self:startGameOverSequence()
    end
end

-- Find nearest empty cell to given position
function Grid:findNearestEmptyCell(x, y)
    local minDist = math.huge
    local nearestIdx = nil
    
    for idx, cell in pairs(self.cells) do
        if not cell.occupied and not cell.permanent and idx ~= SHOOTER_IDX then
            local pos = self.positions[idx]
            if pos then
                local dx = x - pos.x
                local dy = y - pos.y
                local dist = dx * dx + dy * dy
                if dist < minDist then
                    minDist = dist
                    nearestIdx = idx
                end
            end
        end
    end
    
    return nearestIdx
end

-- Check if placement is legal (within 1 cell of collision)
function Grid:isLegalPlacement(landingIdx)
    local pos = self.positions[landingIdx]
    if not pos then return false end
    
    local dx = self.ball.x - pos.x
    local dy = self.ball.y - pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    
    return dist <= COLLISION_RADIUS
end

-- Check for merges starting from placed ball
function Grid:checkForMerges(startIdx)
    if self.isAnimating then return end
    
    local chain = self:findMergeChain(startIdx)
    if #chain >= 3 then
        self:startMergeAnimation(chain)
    end
end

-- Find chain of connected same-type basic balls (flood fill)
function Grid:findMergeChain(startIdx)
    local cell = self.cells[startIdx]
    if not cell or not cell.occupied or cell.tier ~= "basic" then return {} end
    
    local ballType = cell.ballType
    local visited = {}
    local chain = {}
    local queue = {startIdx}
    
    while #queue > 0 do
        local idx = table.remove(queue, 1)
        if not visited[idx] then
            visited[idx] = true
            chain[#chain + 1] = idx
            
            -- Check neighbors (only basic tier balls can merge)
            for _, neighborIdx in ipairs(self:getNeighbors(idx)) do
                local neighbor = self.cells[neighborIdx]
                if not visited[neighborIdx] and neighbor and 
                   neighbor.occupied and neighbor.ballType == ballType and 
                   neighbor.tier == "basic" then
                    queue[#queue + 1] = neighborIdx
                end
            end
        end
    end
    
    return chain
end

-- Get neighboring cell indices for hex grid
function Grid:getNeighbors(idx)
    local pos = self.positions[idx]
    if not pos then return {} end
    
    local row, col = pos.row, pos.col
    local neighbors = {}
    
    local offsets = (row % 2 == 1) and {
        {-1, -1}, {-1, 0}, {0, -1}, {0, 1}, {1, -1}, {1, 0}
    } or {
        {-1, 0}, {-1, 1}, {0, -1}, {0, 1}, {1, 0}, {1, 1}
    }
    
    for _, offset in ipairs(offsets) do
        local newRow = row + offset[1]
        local newCol = col + offset[2]
        if self:isValidGridPosition(newRow, newCol) then
            neighbors[#neighbors + 1] = (newRow - 1) * 20 + newCol
        end
    end
    
    return neighbors
end

-- Start merge animation (balls fly to center, then disappear)
function Grid:startMergeAnimation(chain)
    local centerX, centerY = 0, 0
    for _, idx in ipairs(chain) do
        local pos = self.positions[idx]
        centerX = centerX + pos.x
        centerY = centerY + pos.y
    end
    centerX = centerX / #chain
    centerY = centerY / #chain
    
    -- Mark balls as animating (hide from normal rendering)
    for _, idx in ipairs(chain) do
        self.cells[idx].animating = true
    end
    
    self.animations[#self.animations + 1] = {
        type = "merge",
        chain = chain,
        centerX = centerX,
        centerY = centerY,
        ballType = self.cells[chain[1]].ballType,
        frame = 0
    }
    self.isAnimating = true
end

-- Update all active animations
function Grid:updateAnimations()
    if not self.isAnimating then return end
    
    local allComplete = true
    
    for i, anim in ipairs(self.animations) do
        anim.frame = anim.frame + 1
        local progress = math.min(anim.frame / MERGE_ANIMATION_FRAMES, 1.0)
        
        if anim.type == "merge" then
            if progress >= 1.0 then
                -- Complete animation - remove balls and create tier 1
                for _, idx in ipairs(anim.chain) do
                    self.cells[idx].ballType = nil
                    self.cells[idx].occupied = false
                    self.cells[idx].animating = nil
                    self.cells[idx].tier = nil
                end
                -- Phase 2: Create tier 1 bubble after merge
                self:createTierOne(anim.centerX, anim.centerY, anim.ballType)
            else
                allComplete = false
            end
        end
    end
    
    if allComplete then
        self.animations = {}
        self.isAnimating = false
    end
end

-- Phase 2: Create Tier 1 bubble after basic merge
function Grid:createTierOne(centerX, centerY, ballType)
    local bestTriangle = self:findBestTriangleForTierOne(centerX, centerY)
    if bestTriangle then
        self:placeTierOne(bestTriangle, ballType, centerX, centerY)
        -- Check for magnetic combinations after placing tier 1
        self:checkMagneticCombinations()
    end
end

-- Find best triangle of empty cells near merge center
function Grid:findBestTriangleForTierOne(centerX, centerY)
    local nearestIdx = self:findNearestEmptyCell(centerX, centerY)
    if not nearestIdx then return nil end
    
    local triangles = self:getTriangleCombinations(nearestIdx)
    local bestTriangle = nil
    local minDist = math.huge
    
    for _, triangle in ipairs(triangles) do
        local triangleCenter = self:getTriangleCenter(triangle)
        local dx = centerX - triangleCenter.x
        local dy = centerY - triangleCenter.y
        local dist = dx * dx + dy * dy
        if dist < minDist then
            minDist = dist
            bestTriangle = triangle
        end
    end
    
    return bestTriangle
end

-- Get all valid triangle combinations around a center cell
function Grid:getTriangleCombinations(centerIdx)
    local neighbors = self:getNeighbors(centerIdx)
    local triangles = {}
    
    -- Try all pairs of neighbors to form triangles with center
    for i = 1, #neighbors do
        for j = i + 1, #neighbors do
            local triangle = {centerIdx, neighbors[i], neighbors[j]}
            if self:isValidTriangleForTierOne(triangle) then
                triangles[#triangles + 1] = triangle
            end
        end
    end
    
    return triangles
end

-- Check if triangle cells are available for tier 1 placement
function Grid:isValidTriangleForTierOne(triangle)
    for _, idx in ipairs(triangle) do
        local cell = self.cells[idx]
        if not cell or cell.occupied or cell.permanent or idx == SHOOTER_IDX then
            return false
        end
    end
    return true
end

-- Calculate center point of triangle
function Grid:getTriangleCenter(triangle)
    local centerX, centerY = 0, 0
    for _, idx in ipairs(triangle) do
        local pos = self.positions[idx]
        centerX = centerX + pos.x
        centerY = centerY + pos.y
    end
    return {x = centerX / 3, y = centerY / 3}
end

-- Place tier 1 bubble in triangle formation
function Grid:placeTierOne(triangle, ballType, centerX, centerY)
    -- Mark all triangle cells as tier 1
    for _, idx in ipairs(triangle) do
        self.cells[idx].ballType = ballType
        self.cells[idx].occupied = true
        self.cells[idx].tier = "tier1"
    end
    
    -- Store rendering info for the first cell in triangle
    local renderIdx = triangle[1]
    self.tierOnePositions[renderIdx] = {
        centerX = centerX,
        centerY = centerY,
        ballType = ballType,
        triangle = triangle
    }
end

-- Phase 2: Check for magnetic tier 1 combinations
function Grid:checkMagneticCombinations()
    if self.isAnimating then return end
    
    -- Find all tier 1 bubbles
    local tierOnes = {}
    for idx, tierOneData in pairs(self.tierOnePositions) do
        tierOnes[#tierOnes + 1] = {
            idx = idx,
            ballType = tierOneData.ballType,
            centerX = tierOneData.centerX,
            centerY = tierOneData.centerY,
            triangle = tierOneData.triangle
        }
    end
    
    -- Check for magnetic pairs (different types within range)
    for i = 1, #tierOnes do
        for j = i + 1, #tierOnes do
            local t1, t2 = tierOnes[i], tierOnes[j]
            if t1.ballType ~= t2.ballType then
                local distance = self:getMagneticDistance(t1.centerX, t1.centerY, t2.centerX, t2.centerY)
                if distance <= 60 then -- Magnetic range (about 3 cells)
                    self:createTierTwoCombination(t1, t2)
                    return -- Only one combination at a time
                end
            end
        end
    end
end

-- Calculate distance between two points
function Grid:getMagneticDistance(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

-- Create tier 2 combination from two tier 1 bubbles
function Grid:createTierTwoCombination(tierOne1, tierOne2)
    -- Remove tier 1 bubbles
    self:clearTierOne(tierOne1)
    self:clearTierOne(tierOne2)
    
    -- Create tier 2 bubble at midpoint
    local centerX = (tierOne1.centerX + tierOne2.centerX) / 2
    local centerY = (tierOne1.centerY + tierOne2.centerY) / 2
    local sprite = self:getTierTwoSprite(tierOne1.ballType, tierOne2.ballType)
    
    self:placeTierTwo(centerX, centerY, sprite)
end

-- Get tier 2 sprite index from ball type combination
function Grid:getTierTwoSprite(type1, type2)
    -- Based on original tier 2 combination mapping
    local combinations = {
        [1] = {[2] = 1, [3] = 2, [4] = 9, [5] = 7}, -- Fire combinations
        [2] = {[1] = 1, [3] = 3, [4] = 10, [5] = 4}, -- Water combinations
        [3] = {[1] = 2, [2] = 3, [4] = 6, [5] = 5},  -- Earth combinations
        [4] = {[1] = 9, [2] = 10, [3] = 6, [5] = 8}, -- Lightning combinations
        [5] = {[1] = 7, [2] = 4, [3] = 5, [4] = 8}   -- Wind combinations
    }
    return combinations[type1] and combinations[type1][type2] or 1
end

-- Clear tier 1 bubble and its triangle cells
function Grid:clearTierOne(tierOne)
    for _, idx in ipairs(tierOne.triangle) do
        self.cells[idx].ballType = nil
        self.cells[idx].occupied = false
        self.cells[idx].tier = nil
    end
    self.tierOnePositions[tierOne.idx] = nil
end

-- Place tier 2 bubble (occupies 2-3-2 pattern)
function Grid:placeTierTwo(centerX, centerY, sprite)
    local centerIdx = self:findNearestEmptyCell(centerX, centerY)
    if not centerIdx then return end
    
    -- 2-3-2 pattern around center
    local pattern = {centerIdx}
    local neighbors = self:getNeighbors(centerIdx)
    for i = 1, math.min(6, #neighbors) do
        pattern[#pattern + 1] = neighbors[i]
    end
    
    -- Mark pattern cells as tier 2
    for _, idx in ipairs(pattern) do
        if self.cells[idx] and not self.cells[idx].occupied then
            self.cells[idx].ballType = sprite
            self.cells[idx].occupied = true
            self.cells[idx].tier = "tier2"
        end
    end
    
    -- Store rendering info
    self.tierTwoPositions[centerIdx] = {
        centerX = centerX,
        centerY = centerY,
        sprite = sprite,
        pattern = pattern
    }
end

-- Start game over sequence (3 flashes then game over)
function Grid:startGameOverSequence()
    self.gameState = "flashing"
    self.gameOverFlashCount = 0
    self.flashTimer = 0
end

-- Update game over flash sequence
function Grid:updateGameOverFlash()
    if self.gameState ~= "flashing" then return end
    
    self.flashTimer = self.flashTimer + 1
    if self.flashTimer >= 20 then -- Flash every 20 frames
        self.flashTimer = 0
        self.gameOverFlashCount = self.gameOverFlashCount + 1
        if self.gameOverFlashCount >= GAME_OVER_FLASHES * 2 then -- *2 for on/off cycles
            self.gameState = "gameOver"
            self.ball = nil
        end
    end
end

-- Draw the complete game state
function Grid:draw()
    self:drawGrid()
    self:drawBoundaries()
    self:drawBalls()
    self:drawAnimations()
    self:drawUI()
    if self.gameState == "gameOver" then
        self:drawGameOverScreen()
    end
end

-- Draw grid cells (debug mode)
function Grid:drawGrid()
    if not self.showDebug then return end
    
    for idx, cell in pairs(self.cells) do
        local pos = self.positions[idx]
        if pos and idx ~= SHOOTER_IDX then
            if cell.permanent then
                gfx.fillCircleAtPoint(pos.x, pos.y, 2)
            else
                gfx.drawCircleAtPoint(pos.x, pos.y, 10)
            end
        end
    end
end

-- Draw boundary lines (simplified from curves)
function Grid:drawBoundaries()
    local function drawDashedLine(x1, y1, x2, y2)
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local steps = math.floor(len / 10)
        local stepX, stepY = dx / steps, dy / steps
        
        for i = 0, steps - 1 do
            if i % 2 == 0 then
                local startX, startY = x1 + i * stepX, y1 + i * stepY
                local endX, endY = x1 + (i + 1) * stepX, y1 + (i + 1) * stepY
                gfx.drawLine(startX, startY, endX, endY)
            end
        end
    end
    
    -- Bottom boundary (10px below bottom row)
    drawDashedLine(0, BOTTOM_BOUNDARY + 10, 400, BOTTOM_BOUNDARY + 10)
    
    -- Right boundary (10px right of rightmost cells)
    local rightX = self.positions[20 + 16].x + 10
    drawDashedLine(rightX, 0, rightX, BOTTOM_BOUNDARY + 10)
    
    -- Left cutout - elegant line connecting specific circle points
    local cutoutPoints = {
        -- (a) topmost point of 5,1 circle (nudged down 4px)
        {self.positions[(5-1)*20 + 1].x, self.positions[(5-1)*20 + 1].y - 10 + 4},
        -- (b) topmost point of 5,2 circle (nudged down 4px)
        {self.positions[(5-1)*20 + 2].x, self.positions[(5-1)*20 + 2].y - 10 + 4},
        -- (c) rightmost point of 5,2 circle (nudged left 4px)
        {self.positions[(5-1)*20 + 2].x + 10 - 2, self.positions[(5-1)*20 + 4].y},
        -- (d) rightmost point of 7,3 circle (nudged left 4px)
        {self.positions[(7-1)*20 + 3].x + 10 - 2, self.positions[(7-1)*20 + 3].y},
        -- (e) rightmost point of 9,2 circle (nudged left 4px)
        {self.positions[(9-1)*20 + 2].x + 10 - 2, self.positions[(9-1)*20 + 4].y},
        -- (f) bottommost point of 9,2 circle (nudged up 4px)
        {self.positions[(9-1)*20 + 2].x, self.positions[(9-1)*20 + 2].y + 10 - 4},
        -- (g) bottommost point of 9,1 circle (nudged up 4px)
        {self.positions[(9-1)*20 + 1].x, self.positions[(9-1)*20 + 1].y + 10 - 4}
    }
    
    for i = 1, #cutoutPoints - 1 do
        local p1, p2 = cutoutPoints[i], cutoutPoints[i+1]
        gfx.drawLine(p1[1], p1[2], p2[1], p2[2])
    end
end

-- Draw placed balls
function Grid:drawBalls()
    -- Basic tier balls (only render non-tier1/tier2 occupied cells)
    for idx, cell in pairs(self.cells) do
        if cell.occupied and not cell.permanent and not cell.animating and 
           cell.tier == "basic" and idx ~= SHOOTER_IDX then
            local pos = self.positions[idx]
            if pos then
                self.bubbleSprites.basic[cell.ballType]:draw(pos.x - 10, pos.y - 10)
            end
        end
    end
    
    -- Tier 1 bubbles (render at stored center positions)
    for idx, tierOneData in pairs(self.tierOnePositions) do
        self.bubbleSprites.tier1[tierOneData.ballType]:draw(
            tierOneData.centerX - 10, tierOneData.centerY - 10)
    end
    
    -- Tier 2 bubbles (render at stored center positions)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        self.bubbleSprites.tier2[tierTwoData.sprite]:draw(
            tierTwoData.centerX - 10, tierTwoData.centerY - 10)
    end
    
    -- Shooter ball (with flashing for game over)
    if not self.ball and self.shooterBallType then
        local shouldDraw = true
        if self.gameState == "flashing" then
            shouldDraw = (math.floor(self.flashTimer / 10) % 2) == 0
        end
        
        if shouldDraw then
            local shooterPos = self.positions[SHOOTER_IDX]
            self.bubbleSprites.basic[self.shooterBallType]:draw(shooterPos.x - 10, shooterPos.y - 10)
            
            -- Aim line (only show if shooter ball exists)
            local endX = shooterPos.x - self.aimCos * AIM_LINE_LENGTH
            local endY = shooterPos.y - self.aimSin * AIM_LINE_LENGTH
            gfx.drawLine(shooterPos.x, shooterPos.y, endX, endY)
        end
    end
    
    -- Flying ball
    if self.ball then
        self.bubbleSprites.basic[self.ball.ballType]:draw(self.ball.x - 10, self.ball.y - 10)
    end
end

-- Draw active animations
function Grid:drawAnimations()
    for _, anim in ipairs(self.animations) do
        if anim.type == "merge" then
            local progress = math.min(anim.frame / MERGE_ANIMATION_FRAMES, 1.0)
            
            -- Draw balls moving toward center
            for _, idx in ipairs(anim.chain) do
                local pos = self.positions[idx]
                local currentX = pos.x + (anim.centerX - pos.x) * progress
                local currentY = pos.y + (anim.centerY - pos.y) * progress
                self.bubbleSprites.basic[anim.ballType]:draw(currentX - 10, currentY - 10)
            end
        end
    end
end

-- Draw UI elements
function Grid:drawUI()
    -- On-deck ball
    if self.shotCounter > 1 then
        local onDeckPos = self.positions[(15 - 1) * 20 + 17]
        if onDeckPos then
            self.bubbleSprites.basic[self.onDeckBallType]:draw(onDeckPos.x - 10, onDeckPos.y - 10)
        end
    end
    
    -- Shot counter
    if self.shotCounter > 0 then
        local onDeckPos = self.positions[(15 - 1) * 20 + 17]
        if onDeckPos then
            gfx.drawText(self.shotCounter, onDeckPos.x + 25, onDeckPos.y - 8)
        end
    end
end

-- Draw game over screen
function Grid:drawGameOverScreen()
    local boxWidth, boxHeight = 200, 80
    local boxX, boxY = 200 - boxWidth / 2, 120 - boxHeight / 2
    
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(boxX, boxY, boxWidth, boxHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(boxX, boxY, boxWidth, boxHeight)
    
    gfx.drawTextInRect("GAME OVER", boxX, boxY + 15, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("Press A to restart", boxX, boxY + 45, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
end

return Grid