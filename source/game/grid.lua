-- ============================================================================
-- MERGETHORNE GRID SYSTEM - COMPLETE IMPLEMENTATION
-- ============================================================================
--
-- 🤖 AI DEVELOPMENT GUIDE:
-- This file contains the complete game logic for a bubble shooter with tier progression
-- and combat systems. When making changes, follow these guidelines:
--
-- 🎯 KEY PRINCIPLES:
-- • Animation-driven: Most game state changes happen via animation completion
-- • State consistency: Always check self.isAnimating before major state changes  
-- • Coordinate systems: Grid uses indices (1-300), visual uses pixel coordinates
-- • Rally points: Troops always have assigned rally points, movement is gentle/smooth
-- • Tier progression: Each tier has specific placement rules and troop spawning behavior
--
-- 🔧 COMMON MODIFICATIONS:
-- • Adding new tier combinations: Update MergeConstants.lua + magnetic detection logic
-- • Changing troop behavior: Focus on rally point assignment and movement states
-- • Adjusting balance: Look for constants at top of file and in MergeConstants
-- • New animations: Add to updateAnimations() and drawAnimations() functions
-- • Debug features: Use self.debugView flag for conditional rendering
--
-- ⚠️ CRITICAL AREAS (Modify carefully):
-- • Collision detection (visual + physics)
-- • Animation state management (prevents corrupted game state)
-- • Rally point assignment (troops must always have valid targets)
-- • Grid boundary logic (cutout areas and permanent boundaries)
--
-- ARCHITECTURE OVERVIEW:
-- ┌─────────────────┬─────────────────┬─────────────────────────────────────┐
-- │ CORE SYSTEMS    │ COMBAT SYSTEMS  │ PROGRESSION SYSTEMS                 │
-- ├─────────────────┼─────────────────┼─────────────────────────────────────┤
-- │ • Grid & Input  │ • Enemy Creeps  │ • Basic → Tier 1 (3-merge)         │
-- │ • Ball Physics  │ • Allied Troops │ • Tier 1 → Tier 2 (magnetic)       │
-- │ • Collision     │ • Rally Points  │ • Tier 2 → Tier 3 (magnetic)       │
-- │ • Rendering     │ • March Cycles  │ • Tier 3 → Despawn (after troop)   │
-- └─────────────────┴─────────────────┴─────────────────────────────────────┘
--
-- DATA STRUCTURES:
-- • cells[idx] = {ballType, occupied, permanent, tier} - Single unified cell system
-- • positions[idx] = {x, y} - 20px hex grid coordinates
-- • tierOnePositions[idx] = {centerX, centerY, ballType, triangle} - Tier 1 bubbles
-- • tierTwoPositions[idx] = {centerX, centerY, sprite, pattern} - Tier 2 bubbles  
-- • troops[] = {x, y, targetX, targetY, tier, size, marching, rallied, rallyPoint}
-- • creeps[] = {x, y, targetX, targetY, tier, size, staging}
-- • animations[] = {type, frame, ...} - All visual animations
--
-- GAME FLOW:
-- 1. Input → Aim → Shoot → Ball Physics → Collision → Grid Snap
-- 2. Merge Detection → Animation → Tier Progression → Troop Spawning
-- 3. Combat Cycles → Rally → March → Battle
--
-- PERFORMANCE: 60fps stable, ~2800 lines with full feature set
-- DESIGN PRINCIPLE: Clean separation of concerns, boundary-aware positioning

local MergeConstants = import("game/mergeConstants")
local CombatConstants = import("game/combatConstants")

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Core constants
local BALL_SPEED <const> = 9
local COLLISION_RADIUS <const> = 18  -- 2px smaller for easier attachment
local FLYING_BALL_RADIUS <const> = 15  -- 5px smaller for easier passage
local AIM_LINE_LENGTH <const> = 50
-- Shooter system constants - now free-floating on vertical line
local SHOOTER_X <const> = 320  -- Vertical line bisecting even row cell 16 midpoints
local SHOOTER_Y_MIN <const> = 8    -- Top of grid (row 1)
local SHOOTER_Y_MAX <const> = 200  -- Bottom of row 13  
local SHOOTER_Y_INITIAL <const> = 104  -- Midpoint of movement range
local CRANK_TO_MOVEMENT <const> = 96/360  -- 360° crank = 96px (half range)
local TOP_BOUNDARY <const> = 8
local BOTTOM_BOUNDARY <const> = 200
local LEFT_BOUNDARY <const> = 10
local MERGE_ANIMATION_FRAMES <const> = 8
local GAME_OVER_FLASHES <const> = 3

-- Creep system constants
local CREEP_STAGING_POSITIONS <const> = {
    (3-1) * 20 + 18,   -- 3,18
    (5-1) * 20 + 18,   -- 5,18  
    (7-1) * 20 + 18,   -- 7,18
    (9-1) * 20 + 18,   -- 9,18
    (11-1) * 20 + 18   -- 11,18
}
local CREEP_SPAWN_OFFSET <const> = 100  -- Pixels to right of staging spot
local CREEP_MOVE_SPEED <const> = 2
local CREEP_SIZE <const> = 3  -- 4px sprite with 1px transparent edge
local CREEP_SIZE_TIER3 <const> = 24  -- 25px sprite with 1px transparent edge

-- Troop system constants
-- Multiple rally points to reduce clustering and jitter
local TROOP_RALLY_POINTS <const> = {
    (6-1) * 20 + 1,  -- 6,1 position
    (7-1) * 20 + 1,  -- 7,1 position  
    (7-1) * 20 + 2,  -- 7,2 position
    (8-1) * 20 + 1   -- 8,1 position
}
local TROOP_MOVE_SPEED <const> = 2
local TROOP_SIZE_BASIC <const> = 3   -- 4px sprite with 1px transparent buffer
local TROOP_SIZE_TIER1 <const> = 4   -- 5px sprite with 1px transparent buffer  
local TROOP_SIZE_TIER2 <const> = 8   -- 9px sprite with 1px transparent buffer
local TROOP_SIZE_TIER3 <const> = 24  -- 25px sprite with 1px transparent buffer
local TROOP_MARCH_SPEED <const> = 2

local Grid = {}

-- ============================================================================
-- SPRITE LOADING & INITIALIZATION
-- ============================================================================
--
-- PURPOSE: Load all sprite sheets and split them into individual sprites
-- DEPENDENCIES: Playdate graphics system, asset files in assets/sprites/
-- CROSS-REFS: Used by Grid:init(), referenced in all draw functions
--
-- AI_NOTE: Sprite loading is synchronous and happens once at startup.
-- All sprites are stored in self.bubbleSprites for efficient access during rendering.

-- Sprite loading (Basic + Tier + Creep + Troop systems)
local function loadBubbleSprites()
    local sprites = {basic = {}, tier1 = {}, tier2 = {}, tier3 = {}, creeps = {}, troops = {}}
    
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
    
    -- Load tier 3 sprites
    local tier3Sheet = gfx.image.new("assets/sprites/bubbles-tier-three")
    local tier3Width, tier3Height = tier3Sheet:getSize()
    for i = 1, 10 do
        local spriteWidth = tier3Width / 10
        sprites.tier3[i] = gfx.image.new(spriteWidth, tier3Height)
        gfx.pushContext(sprites.tier3[i])
        tier3Sheet:draw(-(i-1) * spriteWidth, 0)
        gfx.popContext()
    end
    
    -- Load creep sprites
    sprites.creeps.basic = gfx.image.new("assets/sprites/creeps-basic")
    sprites.creeps.tier1 = gfx.image.new("assets/sprites/creeps-tier-one")
    sprites.creeps.tier2 = gfx.image.new("assets/sprites/creeps-tier-two")
    sprites.creeps.tier3 = gfx.image.new("assets/sprites/creeps-tier-three")
    
    -- Load troop sprites
    sprites.troops.basic = gfx.image.new("assets/sprites/troops-basic")
    sprites.troops.tier1 = gfx.image.new("assets/sprites/troops-tier-one")
    sprites.troops.tier2 = gfx.image.new("assets/sprites/troops-tier-two")
    sprites.troops.tier3 = gfx.image.new("assets/sprites/troops-tier-three")
    
    return sprites
end

-- ============================================================================
-- CORE GAME SYSTEMS  
-- ============================================================================
--
-- PURPOSE: Grid initialization, boundary setup, input handling, ball physics
-- BEHAVIOR: Handles the main game loop: input → physics → collision → merge detection
-- CROSS-REFS: Calls tier progression (lines 925+), triggers troop spawning (lines 2224+)
--
-- AI_NOTE: This section contains the fundamental game mechanics. Ball physics uses
-- visual collision detection with immediate grid snapping rather than complex physics.
-- Input is processed every frame, but ball physics only when a ball is in flight.

-- Initialize grid system
-- PURPOSE: Set up all game systems and load resources
-- PARAMS: None
-- RETURNS: None  
-- SIDE_EFFECTS: Loads sprites, creates grid, sets up boundaries, initializes game state
-- AI_NOTE: This is the main entry point. Must be called before any other Grid functions.
function Grid:init()
    self.bubbleSprites = loadBubbleSprites()
    self:createGrid()
    self:setupBoundaries()
    self:initializeStartingGrid()
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
                tier = nil,  -- Phase 2: "basic", "tier1", "tier2"
                health = nil,     -- Current health (nil for empty cells)
                maxHealth = nil   -- Maximum health (nil for empty cells)
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
    
    -- Cell 13,16 (former shooter position) is now a legal playable space
end

-- Initialize starting grid with pre-placed bubbles
function Grid:initializeStartingGrid()
    -- Randomly assign bubble types to letters A, B, C, D, E (types 1-5)
    local letterTypes = {}
    local availableTypes = {1, 2, 3, 4, 5}
    
    -- Shuffle and assign types to letters
    for i = #availableTypes, 2, -1 do
        local j = math.random(i)
        availableTypes[i], availableTypes[j] = availableTypes[j], availableTypes[i]
    end
    
    letterTypes.A = availableTypes[1]
    letterTypes.B = availableTypes[2]
    letterTypes.C = availableTypes[3]
    letterTypes.D = availableTypes[4]
    letterTypes.E = availableTypes[5]
    
    -- Define pre-placed cell positions with their letter assignments
    local prePlacedCells = {
        -- A cells: 1,1 1,2 2,1 2,2
        {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"},
        -- B cells: 3,1 3,2 3,3 4,1 4,2  
        {{3,1}, "B"}, {{3,2}, "B"}, {{3,3}, "B"}, {{4,1}, "B"}, {{4,2}, "B"},
        -- E cells: 13,1 13,2 12,1 12,2
        {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"},
        -- D cells: 11,1 11,2 11,3 10,1 10,2
        {{11,1}, "D"}, {{11,2}, "D"}, {{11,3}, "D"}, {{10,1}, "D"}, {{10,2}, "D"},
        -- E cells: 4,3 5,3 5,4 6,3
        {{4,3}, "E"}, {{5,3}, "E"}, {{5,4}, "E"}, {{6,3}, "E"},
        -- A cells: 10,3 9,3 9,4 8,3
        {{10,3}, "A"}, {{9,3}, "A"}, {{9,4}, "A"}, {{8,3}, "A"},
        -- C cells: 6,4 7,4 7,5 8,4
        {{6,4}, "C"}, {{7,4}, "C"}, {{7,5}, "C"}, {{8,4}, "C"},
        -- B cells: 6,5 7,6 8,5
        {{6,5}, "B"}, {{7,6}, "B"}, {{8,5}, "B"},
        -- D cells: 6,6 7,7 8,6
        {{6,6}, "D"}, {{7,7}, "D"}, {{8,6}, "D"},
        -- C cells: 6,7 7,8 7,9 8,7
        {{6,7}, "C"}, {{7,8}, "C"}, {{7,9}, "C"}, {{8,7}, "C"},
        -- C cells: 6,8 8,8 (changed to match 6,7 type)
        {{6,8}, "C"}, {{8,8}, "C"},
        -- B cells: 6,9 7,10 8,9
        {{6,9}, "B"}, {{7,10}, "B"}, {{8,9}, "B"},
        -- D cells: 6,10 7,11 8,10
        {{6,10}, "D"}, {{7,11}, "D"}, {{8,10}, "D"}
    }
    
    -- Place all pre-defined cells
    for _, cellData in ipairs(prePlacedCells) do
        local pos = cellData[1]
        local letter = cellData[2]
        local row, col = pos[1], pos[2]
        
        if self:isValidGridPosition(row, col) then
            local idx = (row - 1) * 20 + col
            if self.cells[idx] and not self.cells[idx].permanent then
                self.cells[idx].ballType = letterTypes[letter]
                self.cells[idx].occupied = true
                self.cells[idx].tier = "basic"
                self.cells[idx].maxHealth = CombatConstants.getBubbleHealth("basic")
                self.cells[idx].health = self.cells[idx].maxHealth
            end
        end
    end
end

-- Initialize game state variables
function Grid:setupGameState()
    self.angle = 0
    self.ball = nil
    self.shooterBallType = math.random(1, 5)
    self.onDeckBallType = math.random(1, 5)  -- Load normally at start
    self.shooterDelayTimer = 0  -- Timer for 2-second delay after shooting
    self.gameState = "playing"
    self.showDebug = false
    
    -- Free-floating shooter position
    self.shooterX = SHOOTER_X
    self.shooterY = SHOOTER_Y_INITIAL
    
    -- Animation system (extensible for Phase 2)
    self.animations = {}
    self.isAnimating = false
    self.gameOverFlashCount = 0
    self.flashTimer = 0
    
    -- Phase 2: Tier tracking systems
    self.tierOnePositions = {}  -- {idx -> {centerX, centerY, ballType, triangle}}
    self.tierTwoPositions = {}  -- {idx -> {centerX, centerY, sprite, pattern}}
    self.tierThreePositions = {} -- {idx -> {centerX, centerY, sprite, pattern}}
    self.magnetismDelayCounter = 0  -- 8-frame delay before checking magnetism
    
    -- Creep system
    self.creeps = {}  -- {x, y, targetX, targetY, animating, staged, tier, size, marching, hitpoints, maxHitpoints, damage, attackTimer, target}
    self.stagingOccupied = {}  -- Track which staging positions are occupied
    self.creepCycleCount = 0  -- Track shots for creep spawn cycles (1-5)
    
    -- Troop system
    self.troops = {}  -- {x, y, targetX, targetY, tier, size, marching, rallied, hitpoints, maxHitpoints, damage, attackTimer, target}
    self.troopShotCounter = 0  -- Independent shot counter for troop cycles
    self.rallyPointOccupied = {}  -- Track positions around rally point
    self.troopMarchActive = false  -- Track when troops are in march mode
    
    -- Combat system
    self.projectiles = {}  -- {x, y, velocityX, velocityY, damage, size, lifetime, owner}
    self.battleActive = false  -- True when units are engaged in combat
    self.unitsInCombat = {}  -- Track which units are currently fighting
    
    -- Battle and popup system
    self.battleState = "normal"  -- "normal", "waiting_for_merges", "show_popup", "battle"
    self.popup = {
        active = false,
        frame = 0,
        text = "",
        width = 180,
        height = 50
    }
    
    -- Precompute aim direction
    self:updateAimDirection()
    
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
-- PURPOSE: Process all player input and update game state accordingly  
-- PARAMS: None
-- RETURNS: None
-- SIDE_EFFECTS: Updates shooter position/angle, shoots ball, toggles debug, handles game over
-- AI_NOTE: Input is processed every frame. Handles game state transitions and input blocking.
-- Crank controls shooter Y position, D-pad controls aim angle (271°-89° range).
function Grid:handleInput()
    if self.gameState == "gameOver" then
        if pd.buttonJustPressed(pd.kButtonA) then
            self:init() -- Restart game
        end
        return
    end
    
    -- Block input during popup
    if self.popup.active then
        return
    end
    
    -- Shooter positioning via crank
    local crankChange = pd.getCrankChange()
    if math.abs(crankChange) > 0.1 then  -- Ignore tiny movements
        -- Crank up (positive) moves shooter up (decrease Y)
        -- Crank down (negative) moves shooter down (increase Y)
        self.shooterY = self.shooterY - (crankChange * CRANK_TO_MOVEMENT)
        self.shooterY = math.max(SHOOTER_Y_MIN, math.min(SHOOTER_Y_MAX, self.shooterY))
    end
    
    -- Aim adjustment via D-pad (271° to 89° range, prevents shooting right)
    if pd.buttonIsPressed(pd.kButtonUp) then
        self.angle = self.angle + 2
        -- Handle wrapping from 359° to 0° and continue to 89°
        if self.angle >= 360 then
            self.angle = self.angle - 360  -- 360° becomes 0°, 362° becomes 2°
        end
        -- Only clamp if we're in the valid low range and hit the upper limit
        if self.angle > 89 and self.angle < 271 then
            self.angle = 89  -- Clamp at upper limit
        end
        self:updateAimDirection()
    elseif pd.buttonIsPressed(pd.kButtonDown) then
        self.angle = self.angle - 2
        -- Handle wrapping from 0° to 359°
        if self.angle < 0 then
            self.angle = self.angle + 360  -- -2° becomes 358°
        end
        -- Only clamp if we're in the valid high range and hit the lower limit
        if self.angle < 271 and self.angle > 89 then
            self.angle = 271  -- Clamp at lower limit
        end
        self:updateAimDirection()
    end
    
    if pd.buttonJustPressed(pd.kButtonLeft) then
        self.showDebug = not self.showDebug
    elseif pd.buttonJustPressed(pd.kButtonB) then
        self:init() -- Reset level to starting state
    elseif pd.buttonJustPressed(pd.kButtonA) and not self.ball and 
           self.shooterBallType and not self.isAnimating and self.shooterDelayTimer <= 0 then
        self:shootBall()
    end
end

-- Fire a ball from shooter position  
function Grid:shootBall()
    self.ball = {
        x = self.shooterX,
        y = self.shooterY,
        vx = -self.aimCos * BALL_SPEED,
        vy = -self.aimSin * BALL_SPEED,
        ballType = self.shooterBallType,
        bounces = 0  -- Track bounce count (max 3)
    }
    
    -- Only apply 2-second delay on shot 4 (when troops march)
    if self.troopShotCounter == 4 then
        self.shooterDelayTimer = 120  -- 2 seconds at 60fps
        self.shooterBallType = nil  -- Clear current ball during delay
    end
    
    -- Handle creep spawning cycles
    self:handleCreepCycle()
end

-- Check if a position collides with any bubble (with 2px buffer)
function Grid:checkBubbleCollision(x, y, unitSize)
    unitSize = unitSize or 3  -- Default unit size
    local totalRadius = unitSize + 10 + 2  -- unit + bubble + buffer
    
    for idx, cell in pairs(self.cells) do
        if cell.occupied and cell.health and cell.health > 0 then
            local bubblePos = self.positions[idx]
            if bubblePos then
                local dx = x - bubblePos.x
                local dy = y - bubblePos.y
                local distance = math.sqrt(dx*dx + dy*dy)
                
                if distance < totalRadius then
                    return true  -- Collision detected
                end
            end
        end
    end
    return false  -- No collision
end

-- Find nearest open space from current position (escape path for troops)
function Grid:findNearestOpenSpace(x, y, unitSize)
    unitSize = unitSize or 3
    local bestPos = {x = x, y = y}
    local bestDistance = math.huge
    
    -- Search in expanding circles
    for radius = 5, 50, 5 do
        for angle = 0, 360, 15 do
            local radians = math.rad(angle)
            local testX = x + math.cos(radians) * radius
            local testY = y + math.sin(radians) * radius
            
            -- Keep within screen bounds
            if testX >= 20 and testX <= 380 and testY >= 20 and testY <= 220 then
                if not self:checkBubbleCollision(testX, testY, unitSize) then
                    local distance = radius
                    if distance < bestDistance then
                        bestDistance = distance
                        bestPos = {x = testX, y = testY}
                    end
                end
            end
        end
        
        -- Return first valid position found
        if bestDistance < math.huge then
            return bestPos
        end
    end
    
    return bestPos  -- Return original position if no open space found
end

-- Find path around bubble obstacles (improved avoidance with stuck prevention)
function Grid:findAvoidancePath(fromX, fromY, toX, toY, unitSize, allowThroughBubbles, preferDirect)
    unitSize = unitSize or 3
    allowThroughBubbles = allowThroughBubbles or false
    preferDirect = preferDirect or false  -- For combat units pursuing targets
    local dx = toX - fromX
    local dy = toY - fromY
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if distance == 0 then return fromX, fromY end
    
    local moveSpeed = 2  -- Default move speed
    local stepX = (dx / distance) * moveSpeed
    local stepY = (dy / distance) * moveSpeed
    
    -- Try the direct path first (unless specifically avoiding bubbles)
    local testX = fromX + stepX
    local testY = fromY + stepY
    
    if allowThroughBubbles or not self:checkBubbleCollision(testX, testY, unitSize) then
        return testX, testY  -- Direct path is clear or allowed
    end
    
    -- If preferDirect (combat units), do fewer avoidance attempts before forcing through
    local maxAvoidanceAttempts = preferDirect and 3 or 8
    
    -- Try larger avoidance maneuvers around bubbles
    local perpX = -stepY  -- Perpendicular to movement direction
    local perpY = stepX
    
    -- Try multiple avoidance angles and distances
    local avoidanceOptions = {
        -- Small side steps
        {stepX * 0.3 + perpX * 1.5, stepY * 0.3 + perpY * 1.5},
        {stepX * 0.3 - perpX * 1.5, stepY * 0.3 - perpY * 1.5},
        -- Medium side steps
        {stepX * 0.1 + perpX * 2.5, stepY * 0.1 + perpY * 2.5},
        {stepX * 0.1 - perpX * 2.5, stepY * 0.1 - perpY * 2.5},
        -- Large bypass moves
        {perpX * 3.0, perpY * 3.0},
        {-perpX * 3.0, -perpY * 3.0},
        -- Retreat and side-step
        {-stepX * 0.5 + perpX * 2.0, -stepY * 0.5 + perpY * 2.0},
        {-stepX * 0.5 - perpX * 2.0, -stepY * 0.5 - perpY * 2.0}
    }
    
    -- Try each avoidance option (limited attempts for combat units)
    for i, option in ipairs(avoidanceOptions) do
        if i > maxAvoidanceAttempts then break end
        
        local testX = fromX + option[1]
        local testY = fromY + option[2]
        
        -- Keep within screen bounds
        if testX >= 20 and testX <= 380 and testY >= 20 and testY <= 220 then
            if allowThroughBubbles or not self:checkBubbleCollision(testX, testY, unitSize) then
                return testX, testY
            end
        end
    end
    
    -- For combat units preferring direct movement, try forcing through bubbles sooner
    if preferDirect and allowThroughBubbles then
        local testX = fromX + stepX
        local testY = fromY + stepY
        
        -- Clamp to screen bounds
        testX = math.max(20, math.min(380, testX))
        testY = math.max(20, math.min(220, testY))
        
        return testX, testY  -- Force movement toward target
    end
    
    -- If all paths blocked, try moving away from nearest bubble
    local nearestBubbleX, nearestBubbleY = self:findNearestBubble(fromX, fromY)
    if nearestBubbleX then
        local awayX = fromX - (nearestBubbleX - fromX) * 0.3
        local awayY = fromY - (nearestBubbleY - fromY) * 0.3
        
        if awayX >= 20 and awayX <= 380 and awayY >= 20 and awayY <= 220 then
            if allowThroughBubbles or not self:checkBubbleCollision(awayX, awayY, unitSize) then
                return awayX, awayY
            end
        end
    end
    
    -- STUCK PREVENTION: If allowThroughBubbles is true, force movement toward target
    if allowThroughBubbles then
        local testX = fromX + stepX
        local testY = fromY + stepY
        
        -- Clamp to screen bounds
        testX = math.max(20, math.min(380, testX))
        testY = math.max(20, math.min(220, testY))
        
        return testX, testY  -- Force movement even through bubbles
    end
    
    -- Last resort: don't move (only when not allowing through bubbles)
    return fromX, fromY
end

-- Find nearest bubble position for avoidance calculations
function Grid:findNearestBubble(x, y)
    local nearestX, nearestY = nil, nil
    local nearestDistance = math.huge
    
    for idx, cell in pairs(self.cells) do
        if cell.occupied and cell.health and cell.health > 0 then
            local bubblePos = self.positions[idx]
            if bubblePos then
                local dx = x - bubblePos.x
                local dy = y - bubblePos.y
                local distance = math.sqrt(dx*dx + dy*dy)
                
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestX = bubblePos.x
                    nearestY = bubblePos.y
                end
            end
        end
    end
    
    return nearestX, nearestY
end

-- Check if a target is still valid (works for both units and bubbles)
function Grid:isTargetValid(target)
    if not target then return false end
    
    if target.type == "bubble" then
        -- Bubble target - check if cell is still occupied and has health
        return target.cell.occupied and target.cell.health and target.cell.health > 0
    else
        -- Unit target - check hitpoints
        return target.hitpoints and target.hitpoints > 0
    end
end

-- Update shooter delay timer and load next ball when ready
function Grid:updateShooterDelay()
    if self.shooterDelayTimer > 0 then
        self.shooterDelayTimer = self.shooterDelayTimer - 1
        
        -- Load next ball when delay expires
        if self.shooterDelayTimer <= 0 then
            self.shooterBallType = self.onDeckBallType or math.random(1, 5)
            self.onDeckBallType = math.random(1, 5)
        end
    end
end

-- Main update loop
function Grid:update()
    if self.gameState == "gameOver" then
        self:updateGameOverFlash()
        return
    end
    
    self:updateAnimations()
    self:updateCreeps()
    self:updateTroops()
    self:updateCombat()  -- Handle all combat interactions
    self:cleanupDeadUnits()  -- Remove dead units from arrays
    self:updateBattlePopup()
    self:updateShooterDelay()  -- Handle shooter delay timer
    
    -- Handle magnetism delay counter (check Tier 3 first, then Tier 2)
    if self.magnetismDelayCounter > 0 then
        self.magnetismDelayCounter = self.magnetismDelayCounter - 1
        if self.magnetismDelayCounter == 0 then
            self:checkMagneticTierThree()
        end
    end
    
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
        if self.ball.bounces >= 2 then
            -- Force landing on 3rd bounce (after 2 previous bounces)
            self:handleBallLanding()
            return
        end
        self.ball.bounces = self.ball.bounces + 1
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
                if distSq <= (FLYING_BALL_RADIUS * FLYING_BALL_RADIUS) then
                    return true
                end
            end
        end
    end
    
    -- Check tier 1 bubbles (collision with center point, 36x36 sprite)
    for idx, tierOneData in pairs(self.tierOnePositions) do
        local dx = self.ball.x - tierOneData.centerX
        local dy = self.ball.y - tierOneData.centerY
        local distSq = dx * dx + dy * dy
        local tier1Radius = 25 -- 36/2 + 7 for flying ball radius (2px smaller)
        if distSq <= (tier1Radius * tier1Radius) then
            return true
        end
    end
    
    -- Check tier 2 bubbles (collision with center point, 52x52 sprite)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        local dx = self.ball.x - tierTwoData.centerX
        local dy = self.ball.y - tierTwoData.centerY
        local distSq = dx * dx + dy * dy
        local tier2Radius = 33 -- 52/2 + 7 for flying ball radius (2px smaller)
        if distSq <= (tier2Radius * tier2Radius) then
            return true
        end
    end
    
    -- Check tier 3 bubbles (collision with center point, 84x84 sprite)
    for idx, tierThreeData in pairs(self.tierThreePositions) do
        local dx = self.ball.x - tierThreeData.centerX
        local dy = self.ball.y - tierThreeData.centerY
        local distSq = dx * dx + dy * dy
        local tier3Radius = 49 -- 84/2 + 7 for flying ball radius (2px smaller)
        if distSq <= (tier3Radius * tier3Radius) then
            return true
        end
    end
    
    return false
end

-- Handle ball landing after collision
function Grid:handleBallLanding()
    local landingIdx = self:findNearestValidCell(self.ball.x, self.ball.y)
    
    if landingIdx and self:isLegalPlacement(landingIdx) then
        -- Place ball (isLegalPlacement ensures cell is unoccupied)
        self.cells[landingIdx].ballType = self.ball.ballType
        self.cells[landingIdx].occupied = true
        self.cells[landingIdx].tier = "basic"  -- Phase 2: New balls are basic tier
        self.cells[landingIdx].maxHealth = CombatConstants.getBubbleHealth("basic")
        self.cells[landingIdx].health = self.cells[landingIdx].maxHealth
        self.ball = nil
        
        -- Advance to next ball immediately (unless in shot 4 delay)
        if self.shooterDelayTimer <= 0 then
            self.shooterBallType = self.onDeckBallType or math.random(1, 5)
            self.onDeckBallType = math.random(1, 5)
        end
        
        -- Check for merges
        self:checkForMerges(landingIdx)
        
        -- Handle troop spawning and shot counting (happens on every shot)
        self:handleTroopShotCounting()
        self:spawnTroopsForShot()
        
        -- Check if we should start battle popup immediately if no animations are running
        if self.battleState == "waiting_for_merges" and not self.isAnimating then
            self:startBattlePopup()
        end
    else
        -- Try nearby cells for legal placement (no displacement)
        local candidates = self:findNearestValidCells(self.ball.x, self.ball.y, 10)
        local placed = false
        
        for _, candidate in ipairs(candidates) do
            if self:isLegalPlacement(candidate.idx) then
                -- Place ball in unoccupied cell (no ripple displacement)
                self.cells[candidate.idx].ballType = self.ball.ballType
                self.cells[candidate.idx].occupied = true
                self.cells[candidate.idx].tier = "basic"
                self.cells[candidate.idx].maxHealth = CombatConstants.getBubbleHealth("basic")
                self.cells[candidate.idx].health = self.cells[candidate.idx].maxHealth
                self.ball = nil
                
                -- Advance to next ball immediately (unless in shot 4 delay)
                if self.shooterDelayTimer <= 0 then
                    self.shooterBallType = self.onDeckBallType or math.random(1, 5)
                    self.onDeckBallType = math.random(1, 5)
                end
                
                -- Check for merges
                self:checkForMerges(candidate.idx)
                
                -- Handle troop spawning
                self:handleTroopShotCounting()
                self:spawnTroopsForShot()
                
                -- Check if we should start battle popup immediately if no animations are running
                if self.battleState == "waiting_for_merges" and not self.isAnimating then
                    self:startBattlePopup()
                end
                
                placed = true
                break
            end
        end
        
        -- Last resort: clear ball if no valid placement found
        if not placed then
            self:startGameOverSequence()
        end
    end
end


-- Check if placement is legal (within 1 cell of collision)
function Grid:isLegalPlacement(landingIdx)
    local pos = self.positions[landingIdx]
    if not pos then return false end
    
    local dx = self.ball.x - pos.x
    local dy = self.ball.y - pos.y
    local dist = math.sqrt(dx * dx + dy * dy)
    
    -- Must be within collision distance AND cell must be unoccupied
    local cell = self.cells[landingIdx]
    return dist <= COLLISION_RADIUS and cell and not cell.occupied and not cell.permanent
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

-- Update all active animations and handle completion events
-- PURPOSE: Advance animation frames and trigger completion events
-- PARAMS: None
-- RETURNS: None
-- SIDE_EFFECTS: Updates animation frames, triggers tier progression, spawns troops
-- AI_NOTE: ANIMATION STATE MACHINE:
-- This function is critical for game state progression. Each animation type has specific
-- completion behaviors that trigger game events:
-- • merge → createTierOne() → troop spawning
-- • tier1_placement → placeTierOne() → troop spawning  
-- • tier2_magnetism → placeTierTwo() → troop transfer
-- • tier3_magnetism → placeTierThree() → troop transfer to center
-- • tier3_flash → spawn troop → despawn bubble → clear cells
-- Always ensure animations clean up properly to prevent state corruption.
function Grid:updateAnimations()
    if not self.isAnimating then return end
    
    local activeAnimations = {}
    
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
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier1_placement" then
            if progress >= 1.0 then
                -- Complete tier 1 placement - use the animation's end coordinates
                self:placeTierOne(anim.triangle, anim.ballType, anim.endX, anim.endY)
                -- Spawn troop from newly created tier 1
                local rallyPos = self:getBubbleRallyPoint(anim.endX, anim.endY, "tier1")
                self:spawnTroop(anim.endX, anim.endY, "tier1", TROOP_SIZE_TIER1, rallyPos)
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier2_magnetism" then
            if progress >= 1.0 then
                -- Complete magnetism - collect old rally points before clearing
                local oldRallyPoints = {
                    self:getBubbleRallyPoint(anim.tierOne1.centerX, anim.tierOne1.centerY, "tier1"),
                    self:getBubbleRallyPoint(anim.tierOne2.centerX, anim.tierOne2.centerY, "tier1")
                }
                
                -- Remove both tier 1s and create tier 2
                self:clearTierOne(anim.tierOne1)
                self:clearTierOne(anim.tierOne2)
                self:placeTierTwo(anim.endX, anim.endY, anim.sprite)
                
                -- Transfer troops to new tier 2 rally point
                local newRallyPos = self:getBubbleRallyPoint(anim.endX, anim.endY, "tier2")
                self:transferTroopsToNewRally(oldRallyPoints, newRallyPos)
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier2_snap" then
            if progress >= 1.0 then
                -- Use ripple displacement to make space for tier 2 pattern
                self:rippleDisplace(anim.pattern, 3)
                
                -- Complete grid snapping - mark all pattern cells as tier 2
                for _, idx in ipairs(anim.pattern) do
                    self.cells[idx].ballType = anim.sprite
                    self.cells[idx].occupied = true
                    self.cells[idx].tier = "tier2"
                    self.cells[idx].maxHealth = CombatConstants.getBubbleHealth("tier2")
                    self.cells[idx].health = self.cells[idx].maxHealth
                end
                
                -- Store at exact grid position
                self.tierTwoPositions[anim.centerIdx] = {
                    centerX = anim.endX,
                    centerY = anim.endY,
                    sprite = anim.sprite,
                    pattern = anim.pattern
                }
                
                -- Spawn troop from newly created tier 2
                local rallyPos = self:getBubbleRallyPoint(anim.endX, anim.endY, "tier2")
                self:spawnTroop(anim.endX, anim.endY, "tier2", TROOP_SIZE_TIER2, rallyPos)
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_magnetism" then
            if progress >= 1.0 then
                -- Complete tier 3 magnetism - collect old rally points before clearing
                local oldRallyPoints = {
                    self:getBubbleRallyPoint(anim.tierOne.centerX, anim.tierOne.centerY, "tier1"),
                    self:getBubbleRallyPoint(anim.tierTwo.centerX, anim.tierTwo.centerY, "tier2")
                }
                
                -- Remove tier 1 and tier 2, create tier 3
                self:clearTierOne(anim.tierOne)
                self:clearTierTwo(anim.tierTwo)
                self:placeTierThree(anim.endX, anim.endY, anim.sprite)
                
                -- Transfer troops to tier 3 center rally point (since tier 3 will despawn)
                local newRallyPos = {x = anim.endX, y = anim.endY}  -- Center of tier 3
                self:transferTroopsToNewRally(oldRallyPoints, newRallyPos)
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_snap" then
            if progress >= 1.0 then
                -- Use ripple displacement to make space for tier 3 pattern
                self:rippleDisplace(anim.pattern, 4)
                
                -- Complete grid snapping - mark all pattern cells as tier 3
                for _, idx in ipairs(anim.pattern) do
                    self.cells[idx].ballType = anim.sprite
                    self.cells[idx].occupied = true
                    self.cells[idx].tier = "tier3"
                    self.cells[idx].maxHealth = CombatConstants.getBubbleHealth("tier3")
                    self.cells[idx].health = self.cells[idx].maxHealth
                end
                
                -- Start tier3_flash animation instead of immediate troop spawn
                -- Don't add to tierThreePositions yet - wait for flash to complete
                activeAnimations[#activeAnimations + 1] = {
                    type = "tier3_flash",
                    frame = 0,
                    centerX = anim.endX,
                    centerY = anim.endY,
                    sprite = anim.sprite,
                    centerIdx = anim.centerIdx,
                    flashState = "hold", -- hold, flash1, off1, flash2, off2
                    holdFrames = 0,
                    pattern = anim.pattern -- Store pattern for later
                }
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_flash" then
            anim.frame = anim.frame + 1
            
            if anim.flashState == "hold" then
                anim.holdFrames = anim.holdFrames + 1
                if anim.holdFrames >= 20 then
                    anim.flashState = "flash1"
                    anim.frame = 0
                end
                activeAnimations[#activeAnimations + 1] = anim
            elseif anim.flashState == "flash1" then
                if anim.frame >= 12 then
                    anim.flashState = "off1"
                    anim.frame = 0
                end
                activeAnimations[#activeAnimations + 1] = anim
            elseif anim.flashState == "off1" then
                if anim.frame >= 12 then
                    anim.flashState = "flash2"
                    anim.frame = 0
                end
                activeAnimations[#activeAnimations + 1] = anim
            elseif anim.flashState == "flash2" then
                if anim.frame >= 12 then
                    anim.flashState = "off2"
                    anim.frame = 0
                end
                activeAnimations[#activeAnimations + 1] = anim
            elseif anim.flashState == "off2" then
                if anim.frame >= 12 then
                    anim.flashState = "flash3"
                    anim.frame = 0
                end
                activeAnimations[#activeAnimations + 1] = anim
            elseif anim.flashState == "flash3" then
                if anim.frame >= 12 then
                    anim.flashState = "off3"
                    anim.frame = 0
                end
                activeAnimations[#activeAnimations + 1] = anim
            elseif anim.flashState == "off3" then
                if anim.frame >= 12 then
                    -- Flash animation complete - spawn troop then despawn (don't add to tierThreePositions)
                    local rallyPos = {x = anim.centerX, y = anim.centerY} -- Rally to tier 3 center
                    self:spawnTroop(anim.centerX, anim.centerY, "tier3", TROOP_SIZE_TIER3, rallyPos)
                    
                    -- Clear the cells that were occupied by this tier 3
                    for _, cellIdx in ipairs(anim.pattern) do
                        self.cells[cellIdx] = {occupied = false, permanent = false}
                    end
                    
                    -- Don't keep this animation
                else
                    activeAnimations[#activeAnimations + 1] = anim
                end
            end
        end
    end
    
    self.animations = activeAnimations
    
    if #self.animations == 0 then
        self.isAnimating = false
        
        -- Check if we should transition from waiting_for_merges to show_popup
        if self.battleState == "waiting_for_merges" then
            self:startBattlePopup()
        end
    end
end

-- ============================================================================
-- TIER PROGRESSION SYSTEMS
-- ============================================================================
--
-- PURPOSE: Handle bubble evolution from Basic → Tier 1 → Tier 2 → Tier 3
-- BEHAVIOR: Manages merge detection, magnetic combinations, and tier placement
-- CROSS-REFS: Called from updateAnimations(), triggers troop spawning
--
-- TIER PROGRESSION FLOW:
-- ┌─────────────┐  3+ merge   ┌─────────────┐  magnetic   ┌─────────────┐
-- │ Basic       │ ──────────► │ Tier 1      │ ──────────► │ Tier 2      │
-- │ (single)    │             │ (triangle)  │             │ (7-cell)    │
-- └─────────────┘             └─────────────┘             └─────────────┘
--                                     │                           │
--                                     │     magnetic              │
--                                     └─────────────┐             │
--                                                   ▼             ▼
--                                             ┌─────────────┐     │
--                                             │ Tier 3      │◄────┘
--                                             │ (flash+despawn)
--                                             └─────────────┘
--
-- AI_NOTE: Tier progression is animation-driven. Each tier has specific placement
-- requirements and triggers troop spawning with bubble-specific rally points.
-- Tier 3 is special: flashes 3 times, spawns troop, then despawns completely.

-- Phase 2: Create Tier 1 bubble after basic merge
-- PURPOSE: Convert a basic bubble merge into a Tier 1 triangle formation
-- PARAMS: centerX, centerY (merge center), ballType (1-5 for different elements)
-- RETURNS: None
-- SIDE_EFFECTS: Starts tier1_placement animation, will trigger troop spawning when complete
-- AI_NOTE: This is called from merge animation completion. Finds best triangle near merge
-- center, then starts placement animation. If no valid triangle found, merge fails gracefully.
function Grid:createTierOne(centerX, centerY, ballType)
    local bestTriangle = self:findBestTriangleForTierOne(centerX, centerY)
    if bestTriangle then
        self:startTierOnePlacement(bestTriangle, ballType, centerX, centerY)
    else
        print("ERROR: No valid triangle found for tier 1 placement!")
    end
end

-- Start tier 1 placement animation
function Grid:startTierOnePlacement(triangle, ballType, mergeX, mergeY)
    local triangleCenter = self:getTriangleCenter(triangle)
    
    -- Use the same rounding as we do when storing the tier 1
    local endX = math.floor(triangleCenter.x + 0.5)
    local endY = math.floor(triangleCenter.y + 0.5)
    
    self.animations[#self.animations + 1] = {
        type = "tier1_placement",
        triangle = triangle,
        ballType = ballType,
        startX = mergeX,
        startY = mergeY,
        endX = endX,
        endY = endY,
        frame = 0
    }
    self.isAnimating = true
end

-- Find best triangle for tier 1 placement (expanded search approach)
function Grid:findBestTriangleForTierOne(centerX, centerY)
    -- Find multiple candidate cells near the merge center
    local candidates = self:findNearestValidCells(centerX, centerY, 5)
    if #candidates == 0 then return nil end
    
    -- Collect all valid triangles from all candidates
    local allValidTriangles = {}
    
    for _, candidate in ipairs(candidates) do
        local candidateIdx = candidate.idx
        local candidatePos = candidate.pos
        
        -- Get neighbors for this candidate
        local neighbors = self:getNeighbors(candidateIdx)
        if #neighbors >= 6 then
            -- Define all 6 possible pie slice triangles
            local pieSlices = {
                {angle = 0,   triangle = {candidateIdx, neighbors[2], neighbors[4]}}, -- 0° right
                {angle = 60,  triangle = {candidateIdx, neighbors[1], neighbors[2]}}, -- 60° up-right  
                {angle = 120, triangle = {candidateIdx, neighbors[3], neighbors[1]}}, -- 120° up-left
                {angle = 180, triangle = {candidateIdx, neighbors[5], neighbors[3]}}, -- 180° left
                {angle = 240, triangle = {candidateIdx, neighbors[6], neighbors[5]}}, -- 240° down-left
                {angle = 300, triangle = {candidateIdx, neighbors[4], neighbors[6]}}  -- 300° down-right
            }
            
            -- Test each pie slice for validity
            for _, slice in ipairs(pieSlices) do
                local isValid = true
                for _, idx in ipairs(slice.triangle) do
                    if not self.positions[idx] or self.cells[idx].permanent then
                        isValid = false
                        break
                    end
                end
                
                if isValid then
                    -- Calculate triangle center and distance to merge center
                    local triangleCenter = self:getTriangleCenter(slice.triangle)
                    local dx = centerX - triangleCenter.x
                    local dy = centerY - triangleCenter.y
                    local dist = dx * dx + dy * dy
                    
                    allValidTriangles[#allValidTriangles + 1] = {
                        triangle = slice.triangle,
                        center = triangleCenter,
                        dist = dist,
                        candidateIdx = candidateIdx
                    }
                end
            end
        end
    end
    
    -- Choose triangle with center closest to merge center
    local bestTriangle = nil
    if #allValidTriangles > 0 then
        table.sort(allValidTriangles, function(a, b) return a.dist < b.dist end)
        bestTriangle = allValidTriangles[1].triangle
    end
    
    -- Removed debug output for cleaner console
    
    return bestTriangle
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

-- Find nearest valid cell to given position (for ball placement)
function Grid:findNearestValidCell(x, y)
    local candidates = self:findNearestValidCells(x, y, 1)
    return candidates[1] and candidates[1].idx or nil
end

-- Find multiple nearest valid cells to given position
function Grid:findNearestValidCells(x, y, count)
    local candidates = {}
    
    for idx, cell in pairs(self.cells) do
        if not cell.permanent then
            local pos = self.positions[idx]
            if pos then
                local dx = x - pos.x
                local dy = y - pos.y
                local dist = dx * dx + dy * dy
                candidates[#candidates + 1] = {idx = idx, pos = pos, dist = dist}
            end
        end
    end
    
    -- Sort by distance and return top 'count' candidates
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    
    local result = {}
    for i = 1, math.min(count, #candidates) do
        result[i] = candidates[i]
    end
    
    return result
end

-- Ripple displacement: Push existing bubbles away to make space for new placement
function Grid:rippleDisplace(targetPositions, maxRippleRadius)
    if not targetPositions or #targetPositions == 0 then return true end
    
    -- Collect all bubbles that need to be displaced (including whole tier bubbles)
    local displacedBubbles = {}
    local processedTierBubbles = {}  -- Track which tier bubbles we've already processed
    
    for _, idx in ipairs(targetPositions) do
        local cell = self.cells[idx]
        if cell and cell.occupied and not cell.permanent then
            
            -- Check if this cell is part of a tier bubble pattern
            if cell.tier == "tier1" then
                -- Find the tier 1 bubble this cell belongs to
                for tierIdx, tierData in pairs(self.tierOnePositions) do
                    if not processedTierBubbles[tierIdx] and tierData.triangle then
                        for _, triangleIdx in ipairs(tierData.triangle) do
                            if triangleIdx == idx then
                                -- Store health info before displacement
                                local healthData = {}
                                for _, healthIdx in ipairs(tierData.triangle) do
                                    healthData[healthIdx] = {
                                        health = self.cells[healthIdx].health,
                                        maxHealth = self.cells[healthIdx].maxHealth
                                    }
                                end
                                
                                -- Displace entire tier 1 bubble
                                displacedBubbles[#displacedBubbles + 1] = {
                                    type = "tier1",
                                    tierIdx = tierIdx,
                                    tierData = tierData,
                                    originalPos = {x = tierData.centerX, y = tierData.centerY},
                                    healthData = healthData
                                }
                                -- Clear all triangle cells
                                for _, clearIdx in ipairs(tierData.triangle) do
                                    self.cells[clearIdx].occupied = false
                                    self.cells[clearIdx].ballType = nil
                                    self.cells[clearIdx].tier = nil
                                    self.cells[clearIdx].health = nil
                                    self.cells[clearIdx].maxHealth = nil
                                end
                                self.tierOnePositions[tierIdx] = nil
                                processedTierBubbles[tierIdx] = true
                                break
                            end
                        end
                    end
                end
                
            elseif cell.tier == "tier2" then
                -- Find the tier 2 bubble this cell belongs to
                for tierIdx, tierData in pairs(self.tierTwoPositions) do
                    if not processedTierBubbles[tierIdx] and tierData.pattern then
                        for _, patternIdx in ipairs(tierData.pattern) do
                            if patternIdx == idx then
                                -- Displace entire tier 2 bubble
                                displacedBubbles[#displacedBubbles + 1] = {
                                    type = "tier2", 
                                    tierIdx = tierIdx,
                                    tierData = tierData,
                                    originalPos = {x = tierData.centerX, y = tierData.centerY}
                                }
                                -- Clear all pattern cells
                                for _, clearIdx in ipairs(tierData.pattern) do
                                    self.cells[clearIdx].occupied = false
                                    self.cells[clearIdx].ballType = nil
                                    self.cells[clearIdx].tier = nil
                                end
                                self.tierTwoPositions[tierIdx] = nil
                                processedTierBubbles[tierIdx] = true
                                break
                            end
                        end
                    end
                end
                
            elseif cell.tier == "tier3" then
                -- Find the tier 3 bubble this cell belongs to
                for tierIdx, tierData in pairs(self.tierThreePositions) do
                    if not processedTierBubbles[tierIdx] and tierData.pattern then
                        for _, patternIdx in ipairs(tierData.pattern) do
                            if patternIdx == idx then
                                -- Displace entire tier 3 bubble
                                displacedBubbles[#displacedBubbles + 1] = {
                                    type = "tier3",
                                    tierIdx = tierIdx, 
                                    tierData = tierData,
                                    originalPos = {x = tierData.centerX, y = tierData.centerY}
                                }
                                -- Clear all pattern cells
                                for _, clearIdx in ipairs(tierData.pattern) do
                                    self.cells[clearIdx].occupied = false
                                    self.cells[clearIdx].ballType = nil
                                    self.cells[clearIdx].tier = nil
                                end
                                self.tierThreePositions[tierIdx] = nil
                                processedTierBubbles[tierIdx] = true
                                break
                            end
                        end
                    end
                end
                
            else
                -- Regular basic bubble displacement
                displacedBubbles[#displacedBubbles + 1] = {
                    type = "basic",
                    idx = idx,
                    ballType = cell.ballType,
                    tier = cell.tier,
                    originalPos = self.positions[idx]
                }
                -- Temporarily clear the cell
                cell.occupied = false
                cell.ballType = nil
                cell.tier = nil
            end
        end
    end
    
    -- Find new homes for displaced bubbles using expanding search
    local maxRadius = maxRippleRadius or 4
    for _, bubble in ipairs(displacedBubbles) do
        local foundHome = false
        
        -- Search outward in expanding rings from original position
        for radius = 1, maxRadius do
            if foundHome then break end
            
            local candidates = self:findNearestValidCells(bubble.originalPos.x, bubble.originalPos.y, radius * 6)
            for _, candidate in ipairs(candidates) do
                if bubble.type == "basic" then
                    -- Simple basic bubble placement
                    local candidateCell = self.cells[candidate.idx]
                    if candidateCell and not candidateCell.occupied and not candidateCell.permanent then
                        candidateCell.ballType = bubble.ballType
                        candidateCell.occupied = true
                        candidateCell.tier = bubble.tier
                        foundHome = true
                        break
                    end
                    
                elseif bubble.type == "tier1" then
                    -- Try to place tier 1 triangle near this candidate with flexible placement
                    local newTriangle = self:findFlexibleTriangleForTierOne(candidate.pos.x, candidate.pos.y)
                    if newTriangle then
                        -- Clear any existing bubbles in the new triangle (recursive ripple if needed)
                        for _, idx in ipairs(newTriangle) do
                            if self.cells[idx].occupied and not self.cells[idx].permanent then
                                self:rippleDisplace({idx}, 2) -- Smaller ripple to avoid infinite recursion
                            end
                        end
                        
                        -- Place the tier 1 bubble in new triangle formation
                        for _, idx in ipairs(newTriangle) do
                            self.cells[idx].ballType = bubble.tierData.ballType
                            self.cells[idx].occupied = true
                            self.cells[idx].tier = "tier1"
                        end
                        
                        -- Update tracking with new triangle
                        local newCenter = self:getTriangleCenter(newTriangle)
                        self.tierOnePositions[newTriangle[1]] = {
                            centerX = newCenter.x,
                            centerY = newCenter.y,
                            ballType = bubble.tierData.ballType,
                            triangle = newTriangle
                        }
                        foundHome = true
                        break
                    end
                    
                elseif bubble.type == "tier2" then
                    -- Try to place tier 2 pattern with flexible placement allowing basic bubble displacement
                    local centerIdx, newPattern = self:findFlexibleTierTwoPlacement(candidate.pos.x, candidate.pos.y)
                    if centerIdx and newPattern then
                        -- Clear any basic bubbles in the new pattern (avoid tier bubble conflicts)
                        for _, idx in ipairs(newPattern) do
                            if self.cells[idx].occupied and self.cells[idx].tier == "basic" then
                                self.cells[idx].occupied = false
                                self.cells[idx].ballType = nil
                                self.cells[idx].tier = nil
                            end
                        end
                        
                        -- Place the tier 2 bubble in new pattern
                        for _, idx in ipairs(newPattern) do
                            self.cells[idx].ballType = bubble.tierData.sprite
                            self.cells[idx].occupied = true
                            self.cells[idx].tier = "tier2"
                        end
                        
                        -- Update tracking with new pattern
                        local gridPos = self.positions[centerIdx]
                        self.tierTwoPositions[centerIdx] = {
                            centerX = gridPos.x,
                            centerY = gridPos.y,
                            sprite = bubble.tierData.sprite,
                            pattern = newPattern
                        }
                        foundHome = true
                        break
                    end
                    
                elseif bubble.type == "tier3" then
                    -- Try to place tier 3 pattern with flexible placement allowing basic bubble displacement
                    local centerIdx, newPattern = self:findFlexibleTierThreePlacement(candidate.pos.x, candidate.pos.y)
                    if centerIdx and newPattern then
                        -- Clear any basic bubbles in the new pattern (avoid tier bubble conflicts)
                        for _, idx in ipairs(newPattern) do
                            if self.cells[idx].occupied and self.cells[idx].tier == "basic" then
                                self.cells[idx].occupied = false
                                self.cells[idx].ballType = nil
                                self.cells[idx].tier = nil
                            end
                        end
                        
                        -- Place the tier 3 bubble in new pattern
                        for _, idx in ipairs(newPattern) do
                            self.cells[idx].ballType = bubble.tierData.sprite
                            self.cells[idx].occupied = true
                            self.cells[idx].tier = "tier3"
                        end
                        
                        -- Update tracking with new pattern
                        local gridPos = self.positions[centerIdx]
                        self.tierThreePositions[centerIdx] = {
                            centerX = gridPos.x,
                            centerY = gridPos.y,
                            sprite = bubble.tierData.sprite,
                            pattern = newPattern
                        }
                        foundHome = true
                        break
                    end
                end
            end
        end
        
        -- If no home found, restore bubble to original position (prevent deletion)
        if not foundHome then
            if bubble.type == "basic" then
                local originalCell = self.cells[bubble.idx]
                if originalCell and not originalCell.permanent then
                    originalCell.ballType = bubble.ballType
                    originalCell.occupied = true
                    originalCell.tier = bubble.tier
                end
            else
                -- Restore tier bubble to original position
                if bubble.type == "tier1" then
                    for _, idx in ipairs(bubble.tierData.triangle) do
                        self.cells[idx].ballType = bubble.tierData.ballType
                        self.cells[idx].occupied = true
                        self.cells[idx].tier = "tier1"
                    end
                    self.tierOnePositions[bubble.tierIdx] = bubble.tierData
                elseif bubble.type == "tier2" then
                    for _, idx in ipairs(bubble.tierData.pattern) do
                        self.cells[idx].ballType = bubble.tierData.sprite
                        self.cells[idx].occupied = true
                        self.cells[idx].tier = "tier2"
                    end
                    self.tierTwoPositions[bubble.tierIdx] = bubble.tierData
                elseif bubble.type == "tier3" then
                    for _, idx in ipairs(bubble.tierData.pattern) do
                        self.cells[idx].ballType = bubble.tierData.sprite
                        self.cells[idx].occupied = true
                        self.cells[idx].tier = "tier3"
                    end
                    self.tierThreePositions[bubble.tierIdx] = bubble.tierData
                end
            end
        end
    end
    
    return true  -- Always succeed - we preserve bubbles by restoring them if needed
end

-- Place tier 1 bubble in triangle formation
function Grid:placeTierOne(triangle, ballType, centerX, centerY)
    -- Use ripple displacement to make space for tier 1 formation
    self:rippleDisplace(triangle, 3)
    
    -- Mark all triangle cells as tier 1
    for _, idx in ipairs(triangle) do
        self.cells[idx].ballType = ballType
        self.cells[idx].occupied = true
        self.cells[idx].tier = "tier1"
        self.cells[idx].maxHealth = CombatConstants.getBubbleHealth("tier1")
        self.cells[idx].health = self.cells[idx].maxHealth
    end
    
    -- Use the provided coordinates directly (already rounded from animation)
    local renderIdx = triangle[1]
    self.tierOnePositions[renderIdx] = {
        centerX = centerX,
        centerY = centerY,
        ballType = ballType,
        triangle = triangle
    }
    
    -- Start 8-frame delay before checking magnetism
    self.magnetismDelayCounter = 8
end

-- Clear a cell of any bubble (basic or tier)
function Grid:clearCell(idx)
    local cell = self.cells[idx]
    if not cell then return end
    
    -- Clear basic bubble
    if cell.tier == "basic" and cell.occupied then
        cell.ballType = nil
        cell.occupied = false
        cell.tier = nil
    end
    
    -- Clear tier 1 bubble
    if cell.tier == "tier1" then
        -- Find and remove from tierOnePositions
        for tierIdx, tierData in pairs(self.tierOnePositions) do
            for _, triangleIdx in ipairs(tierData.triangle) do
                if triangleIdx == idx then
                    self.tierOnePositions[tierIdx] = nil
                    break
                end
            end
        end
        cell.ballType = nil
        cell.occupied = false
        cell.tier = nil
    end
    
    -- Clear tier 2 bubble
    if cell.tier == "tier2" then
        -- Find and remove from tierTwoPositions
        for tierIdx, tierData in pairs(self.tierTwoPositions) do
            for _, patternIdx in ipairs(tierData.pattern) do
                if patternIdx == idx then
                    self.tierTwoPositions[tierIdx] = nil
                    break
                end
            end
        end
        cell.ballType = nil
        cell.occupied = false
        cell.tier = nil
    end
end

-- Phase 2: Check for magnetic tier 1 combinations
-- PURPOSE: Detect when two different Tier 1 bubbles are close enough to combine into Tier 2
-- PARAMS: None
-- RETURNS: None  
-- SIDE_EFFECTS: Starts tier2_magnetism animation if valid pair found
-- AI_NOTE: DECISION TREE for magnetic combinations:
-- 1. Skip if any animation active (prevents conflicts)
-- 2. Collect all Tier 1 bubbles with their positions and types
-- 3. For each pair: Check if different types AND within 60px magnetic range
-- 4. If valid pair found: Start magnetism animation, remove bubbles, trigger Tier 2 creation
-- 5. Only process first valid pair found (prevents multiple simultaneous combinations)
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
                    self:startTierTwoMagnetism(t1, t2)
                    return -- Only one combination at a time
                end
            end
        end
    end
end

-- Phase 3: Check for magnetic tier 3 combinations (Tier 1 + Tier 2)
function Grid:checkMagneticTierThree()
    if self.isAnimating then return end
    
    -- Find all tier 1 and tier 2 bubbles
    local tierOnes = {}
    local tierTwos = {}
    
    for idx, tierOneData in pairs(self.tierOnePositions) do
        tierOnes[#tierOnes + 1] = {
            idx = idx,
            ballType = tierOneData.ballType,
            centerX = tierOneData.centerX,
            centerY = tierOneData.centerY,
            triangle = tierOneData.triangle
        }
    end
    
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        tierTwos[#tierTwos + 1] = {
            idx = idx,
            sprite = tierTwoData.sprite,
            centerX = tierTwoData.centerX,
            centerY = tierTwoData.centerY,
            pattern = tierTwoData.pattern
        }
    end
    
    -- Check for valid Tier 3 combinations (Tier 2 + Tier 1)
    for i = 1, #tierTwos do
        for j = 1, #tierOnes do
            local t2, t1 = tierTwos[i], tierOnes[j]
            local tier3Sprite = MergeConstants.getTierThreeSprite(t2.sprite, t1.ballType)
            
            if tier3Sprite then
                local distance = self:getMagneticDistance(t2.centerX, t2.centerY, t1.centerX, t1.centerY)
                if distance <= 62 then -- Magnetic range for Tier 3 (42 + 20)
                    self:startTierThreeMagnetism(t2, t1, tier3Sprite)
                    return -- Only one combination at a time
                end
            end
        end
    end
    
    -- If no Tier 3 possible, check for normal Tier 2 combinations
    self:checkMagneticCombinations()
end

-- Start tier 3 magnetism animation
function Grid:startTierThreeMagnetism(tierTwo, tierOne, sprite)
    local midpointX = (tierTwo.centerX + tierOne.centerX) / 2
    local midpointY = (tierTwo.centerY + tierOne.centerY) / 2
    
    self.animations[#self.animations + 1] = {
        type = "tier3_magnetism",
        tierTwo = tierTwo,
        tierOne = tierOne,
        endX = midpointX,
        endY = midpointY,
        sprite = sprite,
        frame = 0
    }
    self.isAnimating = true
end

-- Start tier 2 magnetism animation
function Grid:startTierTwoMagnetism(tierOne1, tierOne2)
    local midpointX = (tierOne1.centerX + tierOne2.centerX) / 2
    local midpointY = (tierOne1.centerY + tierOne2.centerY) / 2
    local sprite = self:getTierTwoSprite(tierOne1.ballType, tierOne2.ballType)
    
    self.animations[#self.animations + 1] = {
        type = "tier2_magnetism",
        tierOne1 = tierOne1,
        tierOne2 = tierOne2,
        endX = midpointX,
        endY = midpointY,
        sprite = sprite,
        frame = 0
    }
    self.isAnimating = true
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
    return MergeConstants.getTierTwoSprite(type1, type2) or 1
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

-- Clear tier 2 bubble and its pattern cells
function Grid:clearTierTwo(tierTwo)
    for _, idx in ipairs(tierTwo.pattern) do
        self.cells[idx].ballType = nil
        self.cells[idx].occupied = false
        self.cells[idx].tier = nil
    end
    self.tierTwoPositions[tierTwo.idx] = nil
end

-- Find valid Tier 2 placement near given position
function Grid:findValidTierTwoPlacement(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 10)
    
    for _, candidate in ipairs(candidates) do
        local centerIdx = candidate.idx
        local neighbors = self:getNeighbors(centerIdx)
        
        -- Check if we have enough valid neighbors for full 7-cell pattern
        if #neighbors >= 6 then
            local validPattern = {centerIdx}
            local allValid = true
            
            for _, neighborIdx in ipairs(neighbors) do
                if self.cells[neighborIdx] and not self.cells[neighborIdx].permanent and not self.cells[neighborIdx].occupied then
                    validPattern[#validPattern + 1] = neighborIdx
                else
                    allValid = false
                    break
                end
            end
            
            if allValid and #validPattern >= 7 then
                return centerIdx, validPattern
            end
        end
    end
    
    print("ERROR: No valid Tier 2 placement found after checking " .. #candidates .. " candidates!")
    return nil, nil
end

-- Find valid Tier 3 placement near given position (19-cell pattern)
function Grid:findValidTierThreePlacement(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 30)
    
    for _, candidate in ipairs(candidates) do
        local centerIdx = candidate.idx
        local neighbors = self:getNeighbors(centerIdx)
        
        -- Need full 2-ring neighbor pattern for 3-4-5-4-3 formation
        if #neighbors >= 6 then
            local pattern = {centerIdx} -- Start with center
            local allValid = true
            
            -- Check if center is valid (not permanent boundary, not shooter, not tier3)
            if self.cells[centerIdx].permanent or 
               (self.cells[centerIdx].occupied and self.cells[centerIdx].tier == "tier3") then
                allValid = false
            end
            
            -- Add first ring (6 neighbors) - allow stomping basic/tier1/tier2
            if allValid then
                for _, neighborIdx in ipairs(neighbors) do
                    if self.cells[neighborIdx] and not self.cells[neighborIdx].permanent and
                       not (self.cells[neighborIdx].occupied and self.cells[neighborIdx].tier == "tier3") then
                        pattern[#pattern + 1] = neighborIdx
                    else
                        allValid = false
                        break
                    end
                end
            end
            
            -- Add second ring (need 12 more for total of 19)
            if allValid and #pattern == 7 then -- center + 6 neighbors
                local secondRingCells = {}
                
                -- Collect all second-ring candidates - allow stomping basic/tier1/tier2
                for _, firstRingIdx in ipairs(neighbors) do
                    local secondRing = self:getNeighbors(firstRingIdx)
                    for _, secondRingIdx in ipairs(secondRing) do
                        -- Skip if already in pattern
                        local alreadyInPattern = false
                        for _, patternIdx in ipairs(pattern) do
                            if patternIdx == secondRingIdx then
                                alreadyInPattern = true
                                break
                            end
                        end
                        
                        -- Allow if not permanent, not shooter, not tier3
                        if not alreadyInPattern and self.cells[secondRingIdx] and 
                           not self.cells[secondRingIdx].permanent and
                           not (self.cells[secondRingIdx].occupied and self.cells[secondRingIdx].tier == "tier3") then
                            secondRingCells[#secondRingCells + 1] = secondRingIdx
                        end
                    end
                end
                
                -- Add exactly 12 second-ring cells (will stomp basic/tier1/tier2 if needed)
                for i = 1, math.min(12, #secondRingCells) do
                    pattern[#pattern + 1] = secondRingCells[i]
                end
                
                if #pattern >= 19 then
                    print("TIER 3 PLACEMENT: Found " .. #pattern .. "-cell pattern at grid " .. self.positions[centerIdx].x .. "," .. self.positions[centerIdx].y)
                    return centerIdx, pattern
                end
            end
        end
    end
    
    print("ERROR: No valid Tier 3 placement found after checking " .. #candidates .. " candidates!")
    return nil, nil
end

-- Flexible placement functions for ripple displacement (allow basic bubble displacement)

-- Find flexible tier 1 triangle placement (can displace basic bubbles)
function Grid:findFlexibleTriangleForTierOne(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 8)
    if #candidates == 0 then return nil end
    
    -- Try to find any valid triangle pattern
    for _, candidate in ipairs(candidates) do
        local candidateIdx = candidate.idx
        local neighbors = self:getNeighbors(candidateIdx)
        if #neighbors >= 6 then
            -- Try each pie slice triangle
            local pieSlices = {
                {candidateIdx, neighbors[2], neighbors[4]}, -- 0° right
                {candidateIdx, neighbors[1], neighbors[2]}, -- 60° up-right  
                {candidateIdx, neighbors[3], neighbors[1]}, -- 120° up-left
                {candidateIdx, neighbors[5], neighbors[3]}, -- 180° left
                {candidateIdx, neighbors[6], neighbors[5]}, -- 240° down-left
                {candidateIdx, neighbors[4], neighbors[6]}  -- 300° down-right
            }
            
            for _, triangle in ipairs(pieSlices) do
                local isValid = true
                for _, idx in ipairs(triangle) do
                    local cell = self.cells[idx]
                    if not self.positions[idx] or not cell or cell.permanent or 
                       (cell.occupied and cell.tier ~= "basic") then -- Allow displacing basic bubbles only
                        isValid = false
                        break
                    end
                end
                
                if isValid then
                    return triangle
                end
            end
        end
    end
    return nil
end

-- Find flexible tier 2 pattern placement (can displace basic bubbles)  
function Grid:findFlexibleTierTwoPlacement(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 15)
    
    for _, candidate in ipairs(candidates) do
        local centerIdx = candidate.idx
        local neighbors = self:getNeighbors(centerIdx)
        
        if #neighbors >= 6 then
            local validPattern = {centerIdx}
            local allValid = true
            
            -- Check center allows basic displacement
            local centerCell = self.cells[centerIdx]
            if centerCell.permanent or (centerCell.occupied and centerCell.tier ~= "basic") then
                allValid = false
            end
            
            -- Check neighbors (allow displacing basic bubbles)
            if allValid then
                for _, neighborIdx in ipairs(neighbors) do
                    local cell = self.cells[neighborIdx]
                    if cell and not cell.permanent and 
                       (not cell.occupied or cell.tier == "basic") then -- Allow basic displacement
                        validPattern[#validPattern + 1] = neighborIdx
                    else
                        allValid = false
                        break
                    end
                end
            end
            
            if allValid and #validPattern >= 7 then
                return centerIdx, validPattern
            end
        end
    end
    return nil, nil
end

-- Find flexible tier 3 pattern placement (can displace basic bubbles)
function Grid:findFlexibleTierThreePlacement(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 25)
    
    for _, candidate in ipairs(candidates) do
        local centerIdx = candidate.idx
        local neighbors = self:getNeighbors(centerIdx)
        
        if #neighbors >= 6 then
            local pattern = {centerIdx}
            local allValid = true
            
            -- Check center (allow basic displacement)
            local centerCell = self.cells[centerIdx]
            if centerCell.permanent or (centerCell.occupied and centerCell.tier ~= "basic") then
                allValid = false
            end
            
            -- Add first ring (allow basic displacement)
            if allValid then
                for _, neighborIdx in ipairs(neighbors) do
                    local cell = self.cells[neighborIdx]
                    if cell and not cell.permanent and 
                       (not cell.occupied or cell.tier == "basic") then -- Allow basic displacement
                        pattern[#pattern + 1] = neighborIdx
                    else
                        allValid = false
                        break
                    end
                end
            end
            
            -- Add second ring (allow basic displacement)
            if allValid then
                local secondRingCells = {}
                for _, firstRingIdx in ipairs(neighbors) do
                    local secondRing = self:getNeighbors(firstRingIdx)
                    for _, secondRingIdx in ipairs(secondRing) do
                        -- Skip if already in pattern
                        local alreadyInPattern = false
                        for _, patternIdx in ipairs(pattern) do
                            if patternIdx == secondRingIdx then
                                alreadyInPattern = true
                                break
                            end
                        end
                        
                        -- Allow if basic bubble or empty
                        if not alreadyInPattern then
                            local cell = self.cells[secondRingIdx]
                            if cell and not cell.permanent and 
                               (not cell.occupied or cell.tier == "basic") then -- Allow basic displacement
                                secondRingCells[#secondRingCells + 1] = secondRingIdx
                            end
                        end
                    end
                end
                
                -- Add up to 12 second-ring cells
                for i = 1, math.min(12, #secondRingCells) do
                    pattern[#pattern + 1] = secondRingCells[i]
                end
                
                if #pattern >= 19 then
                    return centerIdx, pattern
                end
            end
        end
    end
    return nil, nil
end

-- Place tier 2 bubble with grid snapping animation
function Grid:placeTierTwo(centerX, centerY, sprite)
    -- Find valid position for full 7-cell pattern
    local centerIdx, pattern = self:findValidTierTwoPlacement(centerX, centerY)
    if not centerIdx then 
        print("ERROR: No valid Tier 2 placement found!")
        return 
    end
    
    local gridPos = self.positions[centerIdx]
    
    -- Start grid snapping animation (like Tier 1 does)
    self.animations[#self.animations + 1] = {
        type = "tier2_snap",
        startX = centerX,           -- midpoint from magnetism
        startY = centerY,
        endX = gridPos.x,          -- target grid center
        endY = gridPos.y,
        centerIdx = centerIdx,
        pattern = pattern,          -- store the validated pattern
        sprite = sprite,
        frame = 0
    }
    self.isAnimating = true
    
    print("TIER 2 SNAP: From (" .. centerX .. "," .. centerY .. ") to valid grid (" .. gridPos.x .. "," .. gridPos.y .. ") with " .. #pattern .. " cells")
end

-- Place tier 3 bubble with grid snapping animation  
function Grid:placeTierThree(centerX, centerY, sprite)
    -- Find valid position for full 19-cell pattern
    local centerIdx, pattern = self:findValidTierThreePlacement(centerX, centerY)
    if not centerIdx then 
        print("ERROR: No valid Tier 3 placement found!")
        return 
    end
    
    local gridPos = self.positions[centerIdx]
    
    -- Start grid snapping animation (like Tier 2 does)
    self.animations[#self.animations + 1] = {
        type = "tier3_snap",
        startX = centerX,           -- midpoint from magnetism
        startY = centerY,
        endX = gridPos.x,          -- target grid center
        endY = gridPos.y,
        centerIdx = centerIdx,
        pattern = pattern,          -- store the validated 19-cell pattern
        sprite = sprite,
        frame = 0
    }
    self.isAnimating = true
    
    print("TIER 3 SNAP: From (" .. centerX .. "," .. centerY .. ") to valid grid (" .. gridPos.x .. "," .. gridPos.y .. ") with " .. #pattern .. " cells")
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

-- Handle creep spawning cycles based on shot count
-- ============================================================================
-- ENEMY CREEP SYSTEMS
-- ============================================================================
--
-- PURPOSE: Manage hostile units that spawn and march across the battlefield
-- BEHAVIOR: 4-shot cycles with staging positions and coordinated marches
-- CROSS-REFS: Collision detection with troops, rendered in drawCreeps()
--
-- CREEP CYCLE STATE MACHINE:
-- Shot 1: Spawn 5x Basic creeps → Stage at random positions (rows 3,5,7,9,11, col 18)
-- Shot 2: Spawn 3x Tier 1 creeps → Stage at available positions  
-- Shot 3: Spawn 2x Tier 2 creeps → Stage at available positions
-- Shot 4: ALL staged creeps march left off-screen, cycle resets
--
-- STAGING BEHAVIOR:
-- • Creeps spawn off-screen right (staging position + 100px)
-- • March to staging position and hold
-- • On Shot 4, march together in formation off-screen left
--
-- AI_NOTE: Creep cycles are independent of tier bubble progression.
-- Collision detection uses sprite size buffers for visual accuracy.

function Grid:handleCreepCycle()
    self.creepCycleCount = self.creepCycleCount + 1
    
    if self.creepCycleCount == 1 then
        -- Shot 1: 5x Basic creeps
        self:spawnCreeps(5, "basic", 3)
    elseif self.creepCycleCount == 2 then
        -- Shot 2: 3x Tier 1 creeps
        self:spawnCreeps(3, "tier1", 4)
    elseif self.creepCycleCount == 3 then
        -- Shot 3: 2x Tier 2 creeps
        self:spawnCreeps(2, "tier2", 8)
    elseif self.creepCycleCount == 4 then
        -- Shot 4: Creeps will march after battle popup completes
        -- Don't start march immediately - let popup system handle it
    elseif self.creepCycleCount >= 5 then
        -- Shot 5+: Reset cycle
        self.creepCycleCount = 1
        self:spawnCreeps(5, "basic", 3)
    end
end

-- Spawn creeps with tier and size
function Grid:spawnCreeps(count, tier, size)
    local stagingIdx = self:findAvailableStaging()
    if not stagingIdx then return end  -- No available staging positions
    
    local stagingPos = self.positions[stagingIdx]
    self.stagingOccupied[stagingIdx] = true
    
    -- Spawn all creeps to the same rally point with random spawn offsets
    for i = 1, count do
        local creepTier = tier or "basic"
        local stats = CombatConstants.getUnitStats(creepTier)
        
        local spawnX = stagingPos.x + CREEP_SPAWN_OFFSET + math.random(-10, 10)
        local spawnY = stagingPos.y + math.random(-10, 10)
        
        self.creeps[#self.creeps + 1] = {
            x = spawnX,
            y = spawnY,
            targetX = stagingPos.x,
            targetY = stagingPos.y,
            animating = true,
            staged = false,
            stagingIdx = stagingIdx,
            tier = creepTier,
            size = size or 3,
            marching = false,
            
            -- Stuck detection properties
            lastX = spawnX,
            lastY = spawnY,
            stuckCounter = 0,
            stuckThreshold = 60,  -- Frames before considering stuck (1 second at 60fps)
            
            -- Combat properties
            hitpoints = stats.HITPOINTS,
            maxHitpoints = stats.HITPOINTS,
            damage = stats.DAMAGE,
            attackTimer = 0,
            target = nil
        }
    end
end

-- Find available staging position (one with no creeps) - random selection
function Grid:findAvailableStaging()
    local available = {}
    for _, idx in ipairs(CREEP_STAGING_POSITIONS) do
        if not self.stagingOccupied[idx] then
            available[#available + 1] = idx
        end
    end
    
    if #available > 0 then
        return available[math.random(1, #available)]
    end
    return nil  -- All staging positions occupied
end

-- Start marching all creeps to the left
function Grid:startCreepMarch()
    for _, creep in ipairs(self.creeps) do
        creep.marching = true
        creep.animating = false
    end
end

-- Update all creeps movement and collision
function Grid:updateCreeps()
    for i = #self.creeps, 1, -1 do
        local creep = self.creeps[i]
        
        -- Check if creep is stuck (hasn't moved much recently)
        local moveDistance = math.sqrt((creep.x - creep.lastX)^2 + (creep.y - creep.lastY)^2)
        local isStuck = false
        
        if moveDistance < 0.5 then  -- Barely moved
            creep.stuckCounter = creep.stuckCounter + 1
            if creep.stuckCounter >= creep.stuckThreshold then
                isStuck = true
            end
        else
            creep.stuckCounter = 0  -- Reset stuck counter if moving normally
        end
        
        -- Update last position for next frame's stuck detection
        creep.lastX = creep.x
        creep.lastY = creep.y
        
        if creep.marching then
            -- Suicide units keep marching in combat for aggressive charges
            local stats = CombatConstants.getUnitStats(creep.tier)
            if not creep.inCombat or stats.ATTACK_TYPE == "suicide_crash" then
                -- Suicide units steer toward targets, others march in straight line
                if stats.ATTACK_TYPE == "suicide_crash" and creep.target and self:isTargetValid(creep.target) then
                    -- Steer toward target with improved bubble avoidance
                    local dx = creep.target.x - creep.x
                    local dy = creep.target.y - creep.y
                    local distance = math.sqrt(dx*dx + dy*dy)
                    if distance > 0 then
                        local newX = creep.x + (dx / distance) * CREEP_MOVE_SPEED
                        local newY = creep.y + (dy / distance) * CREEP_MOVE_SPEED
                        
                        -- Check for bubble collision and adjust path (allow through bubbles if stuck or in combat)
                        local allowThroughBubbles = isStuck or creep.inCombat or (creep.target and self:isTargetValid(creep.target))
                        local preferDirect = creep.target and self:isTargetValid(creep.target)
                        if self:checkBubbleCollision(newX, newY, creep.size) then
                            local avoidX, avoidY = self:findAvoidancePath(creep.x, creep.y, creep.target.x, creep.target.y, creep.size, allowThroughBubbles, preferDirect)
                            creep.x, creep.y = avoidX, avoidY
                        else
                            creep.x, creep.y = newX, newY
                        end
                    end
                else
                    -- March normally (straight line) with improved bubble avoidance
                    local newX = creep.x - CREEP_MOVE_SPEED
                    local newY = creep.y
                    
                    -- Check for bubble collision and adjust path (allow through bubbles if stuck or in combat)
                    local allowThroughBubbles = isStuck or creep.inCombat
                    if self:checkBubbleCollision(newX, newY, creep.size) then
                        -- For marching creeps, try to maintain general leftward movement
                        local avoidX, avoidY = self:findAvoidancePath(creep.x, creep.y, newX, newY, creep.size, allowThroughBubbles)
                        
                        -- Prefer paths that still move generally left (unless stuck or in combat)
                        if avoidX <= creep.x or allowThroughBubbles then
                            creep.x, creep.y = avoidX, avoidY
                        else
                            -- If forced to move right, try alternative paths
                            local altX, altY = self:findAvoidancePath(creep.x, creep.y, creep.x - CREEP_MOVE_SPEED * 2, creep.y, creep.size, allowThroughBubbles)
                            creep.x, creep.y = altX, altY
                        end
                    else
                        creep.x = newX
                    end
                end
            end
            -- Ranged units stop and fight when in combat
            
            -- Remove if offscreen (left edge)
            if creep.x < -20 then
                -- Free up staging position if this was the last creep there
                self:checkStagingAvailability(creep.stagingIdx)
                table.remove(self.creeps, i)
            end
        elseif creep.animating then
            -- Move toward target position
            local dx = creep.targetX - creep.x
            local dy = creep.targetY - creep.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= CREEP_MOVE_SPEED then
                -- Reached target
                creep.x = creep.targetX
                creep.y = creep.targetY
                creep.animating = false
                creep.staged = true
            else
                -- Move toward target
                creep.x = creep.x + (dx/dist) * CREEP_MOVE_SPEED
                creep.y = creep.y + (dy/dist) * CREEP_MOVE_SPEED
            end
        end
    end
    
    -- Handle all unit collisions (already called in updateTroops, avoid double calling)
    -- self:resolveAllUnitCollisions()
end

-- Check if staging position should be freed (no more creeps there)
function Grid:checkStagingAvailability(stagingIdx)
    local hasCreeps = false
    for _, creep in ipairs(self.creeps) do
        if creep.stagingIdx == stagingIdx and not creep.marching then
            hasCreeps = true
            break
        end
    end
    
    if not hasCreeps then
        self.stagingOccupied[stagingIdx] = nil
    end
end

-- Prevent creeps from overlapping
-- Old creep collision function removed - now handled by resolveAllUnitCollisions()

-- ============================================================================
-- COMBAT SYSTEMS
-- ============================================================================
--
-- PURPOSE: Handle all unit-to-unit combat interactions
-- BEHAVIOR: Engagement detection, targeting, attacks, damage, projectiles
-- INTEGRATION: Called from main update loop when units are within combat range
-- AI_NOTE: Combat phases: Detection → Targeting → Attack → Damage → Victory

-- Main combat update - called from Grid:update()
function Grid:updateCombat()
    if self.isAnimating then return end  -- Skip during animations
    
    -- Update attack timers for all units
    self:updateAttackTimers()
    
    -- Check for battle engagement
    self:checkBattleEngagement()
    
    -- Update projectiles
    self:updateProjectiles()
    
    -- Process combat if battle is active
    if self.battleActive then
        self:processCombat()
        self:checkBattleEnd()
    end
end

-- Update attack cooldown timers for all units
function Grid:updateAttackTimers()
    for _, troop in ipairs(self.troops) do
        if troop.attackTimer > 0 then
            troop.attackTimer = troop.attackTimer - 1
        end
    end
    
    for _, creep in ipairs(self.creeps) do
        if creep.attackTimer > 0 then
            creep.attackTimer = creep.attackTimer - 1
        end
    end
end

-- Check if any troops and creeps are close enough to engage in battle
function Grid:checkBattleEngagement()
    local troopsInRange = {}
    local creepsInRange = {}
    
    -- Find units within combat range of each other (only during march phase)
    for _, troop in ipairs(self.troops) do
        if troop.hitpoints > 0 and troop.marching then  -- Only marching, alive troops
            for _, creep in ipairs(self.creeps) do
                if creep.hitpoints > 0 and creep.marching then  -- Only marching, alive creeps
                    local dx = troop.x - creep.x
                    local dy = troop.y - creep.y
                    local distance = math.sqrt(dx*dx + dy*dy)
                    
                    if distance <= CombatConstants.BATTLE_ENGAGEMENT_RANGE then
                        troopsInRange[#troopsInRange + 1] = troop
                        creepsInRange[#creepsInRange + 1] = creep
                        break  -- This troop is in combat
                    end
                end
            end
        end
    end
    
    -- Set battle state based on engagement
    local wasActive = self.battleActive
    self.battleActive = #troopsInRange > 0 and #creepsInRange > 0
    
    -- Mark all units in combat and slow them down
    for _, troop in ipairs(self.troops) do
        troop.inCombat = false  -- Reset combat state
    end
    for _, creep in ipairs(self.creeps) do
        creep.inCombat = false  -- Reset combat state
    end
    
    if self.battleActive then
        for _, troop in ipairs(troopsInRange) do
            troop.inCombat = true  -- Mark as in combat - this will slow their march
        end
        for _, creep in ipairs(creepsInRange) do
            creep.inCombat = true  -- Mark as in combat - this will slow their march
        end
    end
end

-- Process all combat actions for engaged units
function Grid:processCombat()
    -- Update targeting for all units
    self:updateTargeting()
    
    -- Execute attacks for units that are ready
    local troopsAttacking = 0
    for _, troop in ipairs(self.troops) do
        if troop.hitpoints > 0 and troop.target and troop.attackTimer <= 0 then
            self:executeAttack(troop, "troop")
            troopsAttacking = troopsAttacking + 1
        end
    end
    
    local creepsAttacking = 0
    for _, creep in ipairs(self.creeps) do
        if creep.hitpoints > 0 and creep.target and creep.attackTimer <= 0 then
            self:executeAttack(creep, "creep")
            creepsAttacking = creepsAttacking + 1
        end
    end
    
    -- Debug output (only occasionally to avoid spam)
    if math.random(1, 60) == 1 then  -- 1/60 chance per frame
        local troopsTotal = #self.troops
        local creepsTotal = #self.creeps
        local troopsInCombat = 0
        local creepsInCombat = 0
        
        for _, troop in ipairs(self.troops) do
            if troop.inCombat then troopsInCombat = troopsInCombat + 1 end
        end
        for _, creep in ipairs(self.creeps) do
            if creep.inCombat then creepsInCombat = creepsInCombat + 1 end
        end
        
        print("COMBAT: " .. troopsAttacking .. "/" .. troopsInCombat .. "/" .. troopsTotal .. " troops, " .. 
              creepsAttacking .. "/" .. creepsInCombat .. "/" .. creepsTotal .. " creeps (attacking/inCombat/total)")
    end
end

-- Update targeting for all combat units
function Grid:updateTargeting()
    -- Troops target creeps (only during march phase)
    for _, troop in ipairs(self.troops) do
        if troop.hitpoints > 0 and troop.marching then
            troop.target = self:findTarget(troop, self.creeps)
        end
    end
    
    -- Creeps target both troops and bubbles based on tier rules
    for _, creep in ipairs(self.creeps) do
        if creep.hitpoints > 0 and creep.marching then
            creep.target = self:findCreepTarget(creep)
        end
    end
end

-- Find target for creeps using tier-based targeting rules
function Grid:findCreepTarget(creep)
    local troopTarget = self:findTarget(creep, self.troops)
    local bubbleTarget = self:findBubbleTarget(creep)
    
    -- Debug: Print targeting info
    if creep.tier == "tier2" or creep.tier == "tier3" then
        local troopStr = troopTarget and ("troop " .. troopTarget.tier) or "no troop"
        local bubbleStr = bubbleTarget and ("bubble " .. bubbleTarget.tier) or "no bubble"
        print("DEBUG: " .. creep.tier .. " creep targeting - " .. troopStr .. ", " .. bubbleStr)
    end
    
    -- Tier-based targeting rules
    if creep.tier == "basic" or creep.tier == "tier1" then
        -- Basic/Tier 1: Target first thing they can lock onto (troops or bubbles)
        if troopTarget and bubbleTarget then
            -- Return whichever is closer
            local troopDist = math.sqrt((creep.x - troopTarget.x)^2 + (creep.y - troopTarget.y)^2)
            local bubbleDist = math.sqrt((creep.x - bubbleTarget.x)^2 + (creep.y - bubbleTarget.y)^2)
            return troopDist <= bubbleDist and troopTarget or bubbleTarget
        else
            return troopTarget or bubbleTarget
        end
    elseif creep.tier == "tier2" or creep.tier == "tier3" then
        -- Tier 2/3: Prefer bubbles, but target Tier 2/3 troops if closer
        if bubbleTarget and troopTarget then
            local bubbleDist = math.sqrt((creep.x - bubbleTarget.x)^2 + (creep.y - bubbleTarget.y)^2)
            local troopDist = math.sqrt((creep.x - troopTarget.x)^2 + (creep.y - troopTarget.y)^2)
            
            -- Only target troops if they're Tier 2/3 AND closer than bubbles
            if (troopTarget.tier == "tier2" or troopTarget.tier == "tier3") and troopDist < bubbleDist then
                if creep.tier == "tier2" or creep.tier == "tier3" then
                    print("DEBUG: " .. creep.tier .. " chose high-tier troop over bubble")
                end
                return troopTarget
            else
                if creep.tier == "tier2" or creep.tier == "tier3" then
                    print("DEBUG: " .. creep.tier .. " chose bubble target")
                end
                return bubbleTarget
            end
        else
            local choice = bubbleTarget or troopTarget
            if choice and (creep.tier == "tier2" or creep.tier == "tier3") then
                print("DEBUG: " .. creep.tier .. " single target: " .. (choice.type or "troop"))
            end
            return choice
        end
    end
    
    -- Fallback
    local fallback = troopTarget or bubbleTarget
    if fallback and (creep.tier == "tier2" or creep.tier == "tier3") then
        print("DEBUG: " .. creep.tier .. " fallback target: " .. (fallback.type or "troop"))
    end
    return fallback
end

-- Find bubble targets within range for a unit
function Grid:findBubbleTarget(unit)
    local bestTarget = nil
    local bestDistance = math.huge
    local bestPriority = 0
    
    -- Search through all occupied cells for valid bubble targets
    for idx, cell in pairs(self.cells) do
        if cell.occupied and not cell.permanent and cell.health then
            local bubblePos = self.positions[idx]
            if bubblePos then
                local dx = unit.x - bubblePos.x
                local dy = unit.y - bubblePos.y
                local distance = math.sqrt(dx*dx + dy*dy)
                
                -- Get priority for bubble tier (use same priority as units)
                local priority = CombatConstants.getTargetPriority(cell.tier or "basic")
                
                -- Check if this is a better target
                local shouldTarget = false
                
                if priority > bestPriority then
                    -- Higher priority target
                    shouldTarget = true
                elseif priority == bestPriority and distance < bestDistance then
                    -- Same priority, closer target
                    shouldTarget = true
                elseif bestTarget == nil and distance <= CombatConstants.MAX_TARGETING_RANGE then
                    -- No target yet and within range
                    shouldTarget = true
                end
                
                if shouldTarget then
                    bestTarget = {
                        type = "bubble",
                        cell = cell,
                        x = bubblePos.x,
                        y = bubblePos.y,
                        tier = cell.tier or "basic"
                    }
                    bestDistance = distance
                    bestPriority = priority
                end
            end
        end
    end
    
    return bestTarget
end

-- Find the best target for a unit (nearest enemy with tier priority)
function Grid:findTarget(unit, enemies)
    local bestTarget = nil
    local bestDistance = math.huge
    local bestPriority = 0
    local unitStats = CombatConstants.getUnitStats(unit.tier)
    local isSuicideUnit = unitStats.ATTACK_TYPE == "suicide_crash"
    
    for _, enemy in ipairs(enemies) do
        if enemy.hitpoints > 0 and enemy.marching then  -- Only target marching enemies
            local dx = unit.x - enemy.x
            local dy = unit.y - enemy.y
            local distance = math.sqrt(dx*dx + dy*dy)
            local priority = CombatConstants.getTargetPriority(enemy.tier)
            
            -- Priority targeting: prefer higher tier units if within reasonable distance
            local shouldTarget = false
            
            if priority > bestPriority then
                -- Higher priority target
                shouldTarget = true
            elseif priority == bestPriority and distance < bestDistance then
                -- Same priority, closer target
                shouldTarget = true
            elseif bestTarget == nil then
                -- No target yet - suicide units can target ANY enemy, ranged units limited by range
                if isSuicideUnit or distance <= CombatConstants.MAX_TARGETING_RANGE then
                    shouldTarget = true
                end
            end
            
            if shouldTarget then
                bestTarget = enemy
                bestDistance = distance
                bestPriority = priority
            end
        end
    end
    
    return bestTarget
end

-- Execute an attack based on unit type and attack behavior
function Grid:executeAttack(attacker, attackerType)
    -- Check if current target is still valid
    local targetValid = false
    if attacker.target then
        if attacker.target.type == "bubble" then
            -- Bubble target - check if cell is still occupied and has health
            targetValid = attacker.target.cell.occupied and attacker.target.cell.health and attacker.target.cell.health > 0
        else
            -- Unit target - check hitpoints
            targetValid = attacker.target.hitpoints and attacker.target.hitpoints > 0
        end
    end
    
    if not targetValid then
        -- Find new target if current one is dead/destroyed
        if attackerType == "troop" then
            attacker.target = self:findTarget(attacker, self.creeps)
        else  -- creep
            attacker.target = self:findCreepTarget(attacker)
        end
        if not attacker.target then
            return  -- No valid targets available
        end
    end
    
    local stats = CombatConstants.getUnitStats(attacker.tier)
    local dx = attacker.target.x - attacker.x
    local dy = attacker.target.y - attacker.y
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if stats.ATTACK_TYPE == "suicide_crash" then
        -- CHARGE AT THE ENEMY! NO MERCY!
        local targetSize = attacker.target.size or 10  -- Bubbles default to size 10
        local attackRange = attacker.size + targetSize + 8
        
        -- Debug output for suicide attacks
        if attacker.target.type == "bubble" then
            print("DEBUG: " .. attacker.tier .. " suicide at distance " .. math.floor(distance) .. " (need <= " .. attackRange .. ")")
        end
        
        if distance <= attackRange then
            -- Close enough for suicide attack
            print("DEBUG: Executing suicide attack on " .. (attacker.target.type or "unit"))
            self:executeSuicideAttack(attacker, attacker.target)
        elseif distance <= 40 then
            -- Within 40px - accelerate for dramatic final approach!
            self:chargeAtTarget(attacker, attacker.target)
        end
        -- Beyond 40px: rely on normal marching speed
        
    elseif stats.ATTACK_TYPE == "projectile" then
        -- Force close-quarters combat - no long-range standoffs!
        local maxCombatRange = 40  -- Maximum 40px apart for intense battles
        
        if distance <= stats.ATTACK_RANGE then
            -- In range, fire projectile
            self:fireProjectile(attacker, attacker.target, false)
            attacker.attackTimer = stats.ATTACK_COOLDOWN
        end
        
        -- Force units to close distance for intense combat
        if distance > maxCombatRange then
            -- Too far! Get closer for intense firefight
            self:moveTowardsTarget(attacker, attacker.target)
        elseif distance < 25 then
            -- Too close! Back up slightly for breathing room
            self:kiteAwayFromTarget(attacker, attacker.target)
        end
        -- Sweet spot: 25-40px for intense projectile combat
        
    elseif stats.ATTACK_TYPE == "short_projectile" then
        -- Force close-quarters combat - even shorter range
        local maxCombatRange = 35  -- Even closer for short-range units
        
        if distance <= stats.ATTACK_RANGE then
            -- In range, fire projectile
            self:fireProjectile(attacker, attacker.target, false)
            attacker.attackTimer = stats.ATTACK_COOLDOWN
        end
        
        -- Force units into tight combat range
        if distance > maxCombatRange then
            -- Too far! Close the gap aggressively
            self:moveTowardsTarget(attacker, attacker.target)
        elseif distance < 20 then
            -- Too close! Small step back
            self:kiteAwayFromTarget(attacker, attacker.target)
        end
        -- Sweet spot: 20-35px for intense short-range combat
    end
end

-- Move unit towards its target
function Grid:moveTowardsTarget(unit, target)
    local dx = target.x - unit.x
    local dy = target.y - unit.y
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if distance > 0 then
        local moveSpeed = CombatConstants.getUnitStats(unit.tier).MOVE_SPEED or 2
        unit.x = unit.x + (dx / distance) * moveSpeed
        unit.y = unit.y + (dy / distance) * moveSpeed
    end
end

-- SLOW MENACING ADVANCE - Maximum tension buildup!
function Grid:chargeAtTarget(unit, target)
    local dx = target.x - unit.x
    local dy = target.y - unit.y
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if distance > 0 then
        local stats = CombatConstants.getUnitStats(unit.tier)
        local chargeSpeed = stats.MOVE_SPEED * 1.5  -- Slightly faster than normal for final approach
        unit.x = unit.x + (dx / distance) * chargeSpeed
        unit.y = unit.y + (dy / distance) * chargeSpeed
    end
end

-- Kite away from target - tactical retreat for ranged units
function Grid:kiteAwayFromTarget(unit, target)
    local dx = unit.x - target.x  -- Reverse direction to move away
    local dy = unit.y - target.y
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if distance > 0 then
        local stats = CombatConstants.getUnitStats(unit.tier)
        local kiteSpeed = stats.MOVE_SPEED * 0.8  -- Slower retreat for tactical positioning
        unit.x = unit.x + (dx / distance) * kiteSpeed
        unit.y = unit.y + (dy / distance) * kiteSpeed
    end
end

-- Execute suicide crash attack with blast damage
function Grid:executeSuicideAttack(attacker, target)
    local stats = CombatConstants.getUnitStats(attacker.tier)
    
    -- Apply damage to primary target
    print("DEBUG: Suicide attack applying " .. stats.DAMAGE .. " damage to " .. (target.type or "unit"))
    if target.type == "bubble" then
        -- For bubble targets, pass the cell directly to applyDamage
        self:applyDamage(target.cell, stats.DAMAGE)
    else
        -- For unit targets, pass the unit directly
        self:applyDamage(target, stats.DAMAGE)
    end
    
    -- Apply blast damage to nearby enemies (units and bubbles)
    local enemies = nil
    -- Determine which enemy list to use based on attacker type
    local attackerIsCreep = false
    for _, creep in ipairs(self.creeps) do
        if creep == attacker then
            attackerIsCreep = true
            break
        end
    end
    enemies = attackerIsCreep and self.troops or self.creeps
    
    -- Damage nearby enemy units
    for _, enemy in ipairs(enemies) do
        if enemy.hitpoints > 0 and enemy ~= target then
            local dx = enemy.x - attacker.x
            local dy = enemy.y - attacker.y
            local distance = math.sqrt(dx*dx + dy*dy)
            
            if distance <= stats.BLAST_RADIUS then
                local blastDamage = CombatConstants.getBlastDamage(attacker.tier, distance, stats.BLAST_RADIUS)
                if blastDamage > 0 then
                    self:applyDamage(enemy, blastDamage)
                end
            end
        end
    end
    
    -- Damage nearby bubbles (if attacker is a creep - creeps can damage bubbles)
    if attackerIsCreep then
        for idx, cell in pairs(self.cells) do
            if cell.occupied and cell.health and cell.health > 0 then
                local bubblePos = self.positions[idx]
                if bubblePos then
                    local dx = bubblePos.x - attacker.x
                    local dy = bubblePos.y - attacker.y
                    local distance = math.sqrt(dx*dx + dy*dy)
                    
                    if distance <= stats.BLAST_RADIUS then
                        local blastDamage = CombatConstants.getBlastDamage(attacker.tier, distance, stats.BLAST_RADIUS)
                        if blastDamage > 0 then
                            self:applyDamage(cell, blastDamage)
                        end
                    end
                end
            end
        end
    end
    
    -- Suicide attacker dies
    attacker.hitpoints = 0
end

-- Fire a projectile at target
function Grid:fireProjectile(attacker, target, predictive)
    local stats = CombatConstants.getUnitStats(attacker.tier)
    
    -- Calculate projectile direction
    local targetX, targetY = target.x, target.y
    
    -- TODO: Add predictive targeting for Tier 2 units later
    -- if predictive then
    --     -- Calculate where target will be
    -- end
    
    local dx = targetX - attacker.x
    local dy = targetY - attacker.y
    local distance = math.sqrt(dx*dx + dy*dy)
    
    if distance > 0 then
        local velocityX = (dx / distance) * stats.PROJECTILE_SPEED
        local velocityY = (dy / distance) * stats.PROJECTILE_SPEED
        
        self.projectiles[#self.projectiles + 1] = {
            x = attacker.x,
            y = attacker.y,
            velocityX = velocityX,
            velocityY = velocityY,
            damage = stats.DAMAGE,
            size = stats.PROJECTILE_SIZE,
            lifetime = stats.PROJECTILE_LIFETIME,
            owner = attacker
        }
    end
end

-- Update all active projectiles
function Grid:updateProjectiles()
    local activeProjectiles = {}
    
    for _, projectile in ipairs(self.projectiles) do
        -- Move projectile
        projectile.x = projectile.x + projectile.velocityX
        projectile.y = projectile.y + projectile.velocityY
        projectile.lifetime = projectile.lifetime - 1
        
        -- Check lifetime
        if projectile.lifetime <= 0 then
            goto continue  -- Projectile expired
        end
        
        -- Check collision with enemies
        local enemies = nil
        if projectile.owner and projectile.owner.tier then
            -- Determine which list to check based on owner type
            local ownerFound = false
            for _, troop in ipairs(self.troops) do
                if troop == projectile.owner then
                    enemies = self.creeps  -- Troop projectile hits creeps
                    ownerFound = true
                    break
                end
            end
            if not ownerFound then
                enemies = self.troops  -- Creep projectile hits troops
            end
        end
        
        if enemies then
            for _, enemy in ipairs(enemies) do
                if enemy.hitpoints > 0 then
                    local dx = projectile.x - enemy.x
                    local dy = projectile.y - enemy.y
                    local distance = math.sqrt(dx*dx + dy*dy)
                    
                    if distance <= projectile.size + enemy.size + 1 then
                        -- Hit!
                        self:applyDamage(enemy, projectile.damage)
                        goto continue  -- Projectile consumed
                    end
                end
            end
        end
        
        -- Check collision with bubbles (only for creep projectiles)
        if not ownerFound then  -- This means owner is a creep
            for idx, cell in pairs(self.cells) do
                if cell.occupied and cell.health and cell.health > 0 then
                    local bubblePos = self.positions[idx]
                    if bubblePos then
                        local dx = projectile.x - bubblePos.x
                        local dy = projectile.y - bubblePos.y
                        local distance = math.sqrt(dx*dx + dy*dy)
                        
                        if distance <= projectile.size + 10 + 1 then  -- 10 = bubble size
                            -- Hit bubble!
                            print("DEBUG: Projectile hit " .. (cell.tier or "basic") .. " bubble for " .. projectile.damage .. " damage")
                            self:applyDamage(cell, projectile.damage)
                            goto continue  -- Projectile consumed
                        end
                    end
                end
            end
        end
        
        -- Projectile survived, keep it
        activeProjectiles[#activeProjectiles + 1] = projectile
        ::continue::
    end
    
    self.projectiles = activeProjectiles
end

-- Apply damage to a unit
function Grid:applyDamage(target, damage)
    -- Handle both unit and bubble targets
    if target.hitpoints then
        -- Unit target
        target.hitpoints = target.hitpoints - damage
        if target.hitpoints < 0 then
            target.hitpoints = 0
        end
    elseif target.health then
        -- Bubble target (cell reference)
        local oldHealth = target.health
        target.health = target.health - damage
        print("DEBUG: Bubble " .. (target.tier or "basic") .. " took " .. damage .. " damage: " .. oldHealth .. " -> " .. target.health)
        if target.health <= 0 then
            print("DEBUG: Bubble " .. (target.tier or "basic") .. " destroyed!")
            -- Bubble destroyed - clear the cell
            self:destroyBubble(target)
        end
    end
end

-- Destroy a bubble and handle tier bubble cleanup
function Grid:destroyBubble(cell)
    if not cell or not cell.occupied then return end
    
    -- Handle tier bubble destruction
    if cell.tier == "tier1" then
        -- Find and remove from tierOnePositions
        for tierIdx, tierData in pairs(self.tierOnePositions) do
            for _, triangleIdx in ipairs(tierData.triangle or {}) do
                if self.cells[triangleIdx] == cell then
                    -- Clear entire tier 1 bubble
                    for _, clearIdx in ipairs(tierData.triangle) do
                        self.cells[clearIdx].occupied = false
                        self.cells[clearIdx].ballType = nil
                        self.cells[clearIdx].tier = nil
                        self.cells[clearIdx].health = nil
                        self.cells[clearIdx].maxHealth = nil
                    end
                    self.tierOnePositions[tierIdx] = nil
                    return
                end
            end
        end
    elseif cell.tier == "tier2" then
        -- Find and remove from tierTwoPositions
        for tierIdx, tierData in pairs(self.tierTwoPositions) do
            for _, patternIdx in ipairs(tierData.pattern or {}) do
                if self.cells[patternIdx] == cell then
                    -- Clear entire tier 2 bubble
                    for _, clearIdx in ipairs(tierData.pattern) do
                        self.cells[clearIdx].occupied = false
                        self.cells[clearIdx].ballType = nil
                        self.cells[clearIdx].tier = nil
                        self.cells[clearIdx].health = nil
                        self.cells[clearIdx].maxHealth = nil
                    end
                    self.tierTwoPositions[tierIdx] = nil
                    return
                end
            end
        end
    elseif cell.tier == "tier3" then
        -- Find and remove from tierThreePositions
        for tierIdx, tierData in pairs(self.tierThreePositions) do
            for _, patternIdx in ipairs(tierData.pattern or {}) do
                if self.cells[patternIdx] == cell then
                    -- Clear entire tier 3 bubble
                    for _, clearIdx in ipairs(tierData.pattern) do
                        self.cells[clearIdx].occupied = false
                        self.cells[clearIdx].ballType = nil
                        self.cells[clearIdx].tier = nil
                        self.cells[clearIdx].health = nil
                        self.cells[clearIdx].maxHealth = nil
                    end
                    self.tierThreePositions[tierIdx] = nil
                    return
                end
            end
        end
    else
        -- Basic bubble - just clear the cell
        cell.occupied = false
        cell.ballType = nil
        cell.tier = nil
        cell.health = nil
        cell.maxHealth = nil
    end
end

-- Check if battle has ended (one side eliminated)
function Grid:checkBattleEnd()
    local aliveTroops = 0
    local aliveCreeps = 0
    
    -- Count living units
    for _, troop in ipairs(self.troops) do
        if troop.hitpoints > 0 then
            aliveTroops = aliveTroops + 1
        end
    end
    
    for _, creep in ipairs(self.creeps) do
        if creep.hitpoints > 0 then
            aliveCreeps = aliveCreeps + 1
        end
    end
    
    -- Check for victory conditions - FIGHT TO THE BITTER END!
    if aliveTroops == 0 or aliveCreeps == 0 then
        self.battleActive = false
        
        -- Winning side continues march off-screen
        if aliveTroops > 0 then
            -- Troops won, continue march right
            for _, troop in ipairs(self.troops) do
                if troop.hitpoints > 0 then
                    troop.inCombat = false  -- Stop combat mode
                    troop.marching = true
                    troop.targetX = 500  -- March off-screen right
                end
            end
            print("🏆 TROOPS VICTORIOUS! " .. aliveTroops .. " survivors march on!")
        elseif aliveCreeps > 0 then
            -- Creeps won, continue march left  
            for _, creep in ipairs(self.creeps) do
                if creep.hitpoints > 0 then
                    creep.inCombat = false  -- Stop combat mode
                    creep.marching = true
                    creep.targetX = -100  -- March off-screen left
                end
            end
            print("💀 CREEPS VICTORIOUS! " .. aliveCreeps .. " survivors march on!")
        end
    end
end

-- Clean up dead units from arrays
function Grid:cleanupDeadUnits()
    -- Remove dead troops
    local aliveTroops = {}
    for _, troop in ipairs(self.troops) do
        if troop.hitpoints > 0 then
            aliveTroops[#aliveTroops + 1] = troop
        end
    end
    self.troops = aliveTroops
    
    -- Remove dead creeps  
    local aliveCreeps = {}
    for _, creep in ipairs(self.creeps) do
        if creep.hitpoints > 0 then
            aliveCreeps[#aliveCreeps + 1] = creep
        end
    end
    self.creeps = aliveCreeps
end

-- ============================================================================
-- RENDERING SYSTEMS
-- ============================================================================

-- Draw the complete game state
function Grid:draw()
    self:drawGrid()
    self:drawBoundaries()
    self:drawBalls()
    self:drawCreeps()
    self:drawTroops()
    self:drawProjectiles()  -- Draw combat projectiles
    self:drawAnimations()
    self:drawUI()
    self:drawPopup()
    if self.gameState == "gameOver" then
        self:drawGameOverScreen()
    end
end

-- Draw popup overlay
function Grid:drawPopup()
    if not self.popup.active then return end
    
    -- Calculate centered position (screen is 400x240)
    local screenWidth, screenHeight = 400, 240
    local popupX = (screenWidth - self.popup.width) / 2
    local popupY = (screenHeight - self.popup.height) / 2
    
    -- Draw white background
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(popupX, popupY, self.popup.width, self.popup.height)
    
    -- Draw border
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(popupX, popupY, self.popup.width, self.popup.height)
    
    -- Draw text centered in popup
    gfx.setColor(gfx.kColorBlack)
    local textWidth, textHeight = gfx.getTextSize(self.popup.text)
    local textX = popupX + (self.popup.width - textWidth) / 2
    local textY = popupY + (self.popup.height - textHeight) / 2
    gfx.drawText(self.popup.text, textX, textY)
end

-- Draw grid cells (debug mode)
function Grid:drawGrid()
    if not self.showDebug then return end
    
    for idx, cell in pairs(self.cells) do
        local pos = self.positions[idx]
        if pos then
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
           cell.tier == "basic" then
            local pos = self.positions[idx]
            if pos then
                self.bubbleSprites.basic[cell.ballType]:draw(pos.x - 10, pos.y - 10)
            end
        end
        
    end
    
    -- Tier 1 bubbles (render at stored center positions with CORRECT centering)
    for idx, tierOneData in pairs(self.tierOnePositions) do
        -- Draw the tier 1 bubble with correct 36x36 sprite centering
        self.bubbleSprites.tier1[tierOneData.ballType]:draw(
            tierOneData.centerX - 18, tierOneData.centerY - 18)
            
    end
    
    -- Tier 2 bubbles (render at stored center positions)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        self.bubbleSprites.tier2[tierTwoData.sprite]:draw(
            tierTwoData.centerX - 26, tierTwoData.centerY - 26)
    end
    
    -- Tier 3 bubbles (render at stored center positions)
    for idx, tierThreeData in pairs(self.tierThreePositions) do
        self.bubbleSprites.tier3[tierThreeData.sprite]:draw(
            tierThreeData.centerX - 42, tierThreeData.centerY - 42)
    end
    
    -- Shooter ball (with flashing for game over)
    if not self.ball and self.shooterBallType then
        local shouldDraw = true
        if self.gameState == "flashing" then
            shouldDraw = (math.floor(self.flashTimer / 10) % 2) == 0
        end
        
        if shouldDraw then
            -- Aim line (render behind shooter ball)
            local endX = self.shooterX - self.aimCos * AIM_LINE_LENGTH
            local endY = self.shooterY - self.aimSin * AIM_LINE_LENGTH
            gfx.drawLine(self.shooterX, self.shooterY, endX, endY)
            
            -- Shooter ball (renders on top of aim line)
            self.bubbleSprites.basic[self.shooterBallType]:draw(self.shooterX - 10, self.shooterY - 10)
        end
    end
    
    -- Flying ball
    if self.ball then
        self.bubbleSprites.basic[self.ball.ballType]:draw(self.ball.x - 10, self.ball.y - 10)
    end
end

-- Draw all creeps
function Grid:drawCreeps()
    for _, creep in ipairs(self.creeps) do
        local sprite = self.bubbleSprites.creeps.basic
        local offset = creep.size / 2
        
        if creep.tier == "tier1" then
            sprite = self.bubbleSprites.creeps.tier1 or sprite
        elseif creep.tier == "tier2" then
            sprite = self.bubbleSprites.creeps.tier2 or sprite
        end
        
        sprite:draw(creep.x - offset, creep.y - offset)
        
        -- Draw health bar if unit is damaged (debug mode only)
        if self.showDebug and creep.hitpoints < creep.maxHitpoints then
            self:drawHealthBar(creep.x, creep.y - offset - 8, creep.hitpoints, creep.maxHitpoints, 12)
        end
    end
end
-- ============================================================================
-- ALLIED TROOP SYSTEMS  
-- ============================================================================
--
-- PURPOSE: Manage friendly units spawned from bubbles that rally and march
-- BEHAVIOR: Spawn from tier bubbles → rally to specific points → march in formation
-- CROSS-REFS: Spawned from tier progression, collision with creeps, rendered in drawTroops()
--
-- TROOP SPAWNING RULES:
-- • Every shot: All tier bubbles (T1/T2/T3) spawn corresponding troops
-- • Every shot: 10% chance per basic bubble to spawn basic troop
-- • Troops inherit rally point from their spawning bubble or nearest available
--
-- RALLY POINT ASSIGNMENTS:
-- ┌─────────────┬─────────────────────────────────────────────────────────┐
-- │ Troop Type  │ Rally Point Location                                    │
-- ├─────────────┼─────────────────────────────────────────────────────────┤
-- │ Basic       │ Nearest available (bubble-specific or base cutout)     │
-- │ Tier 1      │ Bubble center, offset up 1/3 from center              │
-- │ Tier 2      │ Bubble center, offset up 1/3 from center              │
-- │ Tier 3      │ Exact bubble center (stays even after despawn)        │
-- └─────────────┴─────────────────────────────────────────────────────────┘
--
-- MOVEMENT STATES:
-- 1. Approaching: Moving from spawn → rally point
-- 2. Rallied: Clustered at rally point, gentle shuffling
-- 3. Marching: Moving right off-screen in formation (Shot 4 trigger)
--
-- AI_NOTE: Troop movement uses gentle physics with collision avoidance.
-- When bubbles merge, troops transfer to new bubble's rally point automatically.

-- Get a random rally point position
function Grid:getRandomRallyPoint()
    local rallyIdx = TROOP_RALLY_POINTS[math.random(#TROOP_RALLY_POINTS)]
    return self.positions[rallyIdx]
end

-- Calculate bubble-specific rally point based on tier and bubble position
function Grid:getBubbleRallyPoint(bubbleX, bubbleY, tier)
    local rallyX = bubbleX  -- Midpoint left/right
    local rallyY
    
    if tier == "tier1" then
        -- Top 1/3 of the bubble (assuming 20px height)
        rallyY = bubbleY - 7  -- 1/3 up from center
    elseif tier == "tier2" then
        -- Top 1/3 of the bubble (assuming 20px height)  
        rallyY = bubbleY - 7   -- 1/3 up from center
    else
        -- Default behavior for other tiers
        return self:getRandomRallyPoint()
    end
    
    return {x = rallyX, y = rallyY}
end

-- Transfer troops from merged bubbles to new bubble's rally point
-- PURPOSE: When bubbles merge, move their troops to the new bubble's rally point
-- PARAMS: oldRallyPositions (array of {x,y}), newRallyPos ({x,y})
-- RETURNS: None
-- SIDE_EFFECTS: Updates troop rallyPoint, targetX/Y, sets rallied=false to trigger movement
-- AI_NOTE: TROOP TRANSFER LOGIC:
-- 1. Only affect troops that aren't marching (preserve march state)
-- 2. Check each troop's current rally point against old rally positions
-- 3. If match found: Update rally point, set new target, mark as not-rallied
-- 4. Troops will automatically path to new position using existing movement logic
-- This ensures smooth transitions when Tier 1+2 → Tier 2+3 merges occur.
function Grid:transferTroopsToNewRally(oldRallyPositions, newRallyPos)
    if not newRallyPos then return end
    
    for _, troop in ipairs(self.troops) do
        if troop.rallyPoint and not troop.marching then
            -- Check if this troop was assigned to any of the old rally points
            for _, oldRally in ipairs(oldRallyPositions) do
                if troop.rallyPoint.x == oldRally.x and troop.rallyPoint.y == oldRally.y then
                    -- Reassign to new rally point and make them move there
                    troop.rallyPoint = newRallyPos
                    troop.targetX = newRallyPos.x
                    troop.targetY = newRallyPos.y
                    troop.rallied = false  -- Make them move to new position
                    break
                end
            end
        end
    end
end

-- Find nearest rally point (bubble-specific or base rally points)
function Grid:findNearestRallyPoint(spawnX, spawnY)
    local nearestRally = nil
    local nearestDistance = math.huge
    
    -- Check all tier 1 bubble rally points
    for idx, tierData in pairs(self.tierOnePositions) do
        local rallyPos = self:getBubbleRallyPoint(tierData.centerX, tierData.centerY, "tier1")
        local distance = math.sqrt((spawnX - rallyPos.x)^2 + (spawnY - rallyPos.y)^2)
        if distance < nearestDistance then
            nearestDistance = distance
            nearestRally = rallyPos
        end
    end
    
    -- Check all tier 2 bubble rally points
    for idx, tierData in pairs(self.tierTwoPositions) do
        local rallyPos = self:getBubbleRallyPoint(tierData.centerX, tierData.centerY, "tier2")
        local distance = math.sqrt((spawnX - rallyPos.x)^2 + (spawnY - rallyPos.y)^2)
        if distance < nearestDistance then
            nearestDistance = distance
            nearestRally = rallyPos
        end
    end
    
    -- Check base rally points (left edge cutout)
    for _, rallyIdx in ipairs(TROOP_RALLY_POINTS) do
        local rallyPos = self.positions[rallyIdx]
        if rallyPos then
            local distance = math.sqrt((spawnX - rallyPos.x)^2 + (spawnY - rallyPos.y)^2)
            if distance < nearestDistance then
                nearestDistance = distance
                nearestRally = rallyPos
            end
        end
    end
    
    return nearestRally or self:getRandomRallyPoint()
end

-- Spawn troops from all tier bubbles after shot landing
function Grid:spawnTroopsFromBubbles()
    
    -- Spawn from Tier 1 bubbles
    for idx, tierData in pairs(self.tierOnePositions) do
        local rallyPos = self:getBubbleRallyPoint(tierData.centerX, tierData.centerY, "tier1")
        self:spawnTroop(tierData.centerX, tierData.centerY, "tier1", TROOP_SIZE_TIER1, rallyPos)
    end
    
    -- Spawn from Tier 2 bubbles  
    for idx, tierData in pairs(self.tierTwoPositions) do
        local rallyPos = self:getBubbleRallyPoint(tierData.centerX, tierData.centerY, "tier2")
        self:spawnTroop(tierData.centerX, tierData.centerY, "tier2", TROOP_SIZE_TIER2, rallyPos)
    end
    
    -- Spawn from Tier 3 bubbles (rally to fixed point 7,3)
    for idx, tierData in pairs(self.tierThreePositions) do
        local rallyPos = {x = 7 * 20 + 10, y = 3 * 17.32 + 10} -- Rally point 7,3
        self:spawnTroop(tierData.centerX, tierData.centerY, "tier3", TROOP_SIZE_TIER3, rallyPos)
    end
end
-- Spawn basic troops (each basic bubble has 10% chance)
function Grid:spawnBasicTroops()
    for idx, cell in pairs(self.cells) do
        if cell.occupied and cell.tier == "basic" then
            -- 10% chance for each basic bubble to spawn a troop
            if math.random() < 0.1 then
                local pos = self.positions[idx]
                if pos then
                    -- Find nearest rally point (bubble or base)
                    local rallyPos = self:findNearestRallyPoint(pos.x, pos.y)
                    self:spawnTroop(pos.x, pos.y, "basic", TROOP_SIZE_BASIC, rallyPos)
                end
            end
        end
    end
end
-- Spawn individual troop at specified location
function Grid:spawnTroop(spawnX, spawnY, tier, size, rallyPos)
    if not rallyPos then return end
    
    -- Check if we're in a march state (Turn 4 or any troops marching)
    local shouldMarch = self:shouldNewTroopsMarch()
    
    local stats = CombatConstants.getUnitStats(tier)
    
    -- Check if spawning inside a bubble and need escape path
    local finalTargetX, finalTargetY = rallyPos.x, rallyPos.y
    local needsEscape = self:checkBubbleCollision(spawnX, spawnY, size)
    
    if needsEscape then
        -- Find nearest open space to escape to first
        local escapePos = self:findNearestOpenSpace(spawnX, spawnY, size)
        finalTargetX, finalTargetY = escapePos.x, escapePos.y
    end
    
    self.troops[#self.troops + 1] = {
        x = spawnX,
        y = spawnY,
        targetX = finalTargetX,
        targetY = finalTargetY,
        tier = tier,
        size = size,
        needsEscape = needsEscape,  -- Flag to track escape state
        originalRallyX = rallyPos.x,  -- Store original rally point
        originalRallyY = rallyPos.y,
        marching = shouldMarch,
        rallied = false,
        rallyPoint = rallyPos,  -- Store assigned rally point
        
        -- Stuck detection properties
        lastX = spawnX,
        lastY = spawnY,
        stuckCounter = 0,
        stuckThreshold = 60,  -- Frames before considering stuck (1 second at 60fps)
        
        -- Combat properties
        hitpoints = stats.HITPOINTS,
        maxHitpoints = stats.HITPOINTS,
        damage = stats.DAMAGE,
        attackTimer = 0,
        target = nil
    }
end
-- Determine if newly spawned troops should march immediately
function Grid:shouldNewTroopsMarch()
    -- Only march if we're actively in shot 4 cycle (troopShotCounter just reset to 0)
    -- This prevents shot 5+ troops from marching while shot 4 troops are still moving
    return self.troopMarchActive and self.troopShotCounter == 0
end
-- Update all troop movement
function Grid:updateTroops()
    for i = #self.troops, 1, -1 do
        local troop = self.troops[i]
        
        -- Check if troop is stuck (hasn't moved much recently)
        local moveDistance = math.sqrt((troop.x - troop.lastX)^2 + (troop.y - troop.lastY)^2)
        local isStuck = false
        
        if moveDistance < 0.5 then  -- Barely moved
            troop.stuckCounter = troop.stuckCounter + 1
            if troop.stuckCounter >= troop.stuckThreshold then
                isStuck = true
            end
        else
            troop.stuckCounter = 0  -- Reset stuck counter if moving normally
        end
        
        -- Update last position for next frame's stuck detection
        troop.lastX = troop.x
        troop.lastY = troop.y
        
        if troop.marching then
            -- Suicide units keep marching in combat for aggressive charges
            local stats = CombatConstants.getUnitStats(troop.tier)
            if not troop.inCombat or stats.ATTACK_TYPE == "suicide_crash" then
                -- Suicide units steer toward targets, others march in straight line
                if stats.ATTACK_TYPE == "suicide_crash" and troop.target and self:isTargetValid(troop.target) then
                    -- Steer toward target with bubble avoidance
                    local dx = troop.target.x - troop.x
                    local dy = troop.target.y - troop.y
                    local distance = math.sqrt(dx*dx + dy*dy)
                    if distance > 0 then
                        local newX = troop.x + (dx / distance) * TROOP_MARCH_SPEED
                        local newY = troop.y + (dy / distance) * TROOP_MARCH_SPEED
                        
                        -- Check for bubble collision and adjust path (allow through bubbles if stuck or in combat)
                        local allowThroughBubbles = isStuck or troop.inCombat or (troop.target and self:isTargetValid(troop.target))
                        local preferDirect = troop.target and self:isTargetValid(troop.target)
                        if self:checkBubbleCollision(newX, newY, troop.size) then
                            local avoidX, avoidY = self:findAvoidancePath(troop.x, troop.y, troop.target.x, troop.target.y, troop.size, allowThroughBubbles, preferDirect)
                            troop.x, troop.y = avoidX, avoidY
                        else
                            troop.x, troop.y = newX, newY
                        end
                    end
                else
                    -- March normally (straight line) with bubble avoidance
                    local newX = troop.x + TROOP_MARCH_SPEED
                    local newY = troop.y
                    
                    -- Check for bubble collision and adjust path (allow through bubbles if stuck or in combat)
                    local allowThroughBubbles = isStuck or troop.inCombat
                    if self:checkBubbleCollision(newX, newY, troop.size) then
                        -- For marching troops, try to maintain general rightward movement
                        local avoidX, avoidY = self:findAvoidancePath(troop.x, troop.y, newX, newY, troop.size, allowThroughBubbles)
                        
                        -- Prefer paths that still move generally right (unless stuck or in combat)
                        if avoidX >= troop.x or allowThroughBubbles then
                            troop.x, troop.y = avoidX, avoidY
                        else
                            -- If forced to move left, try alternative paths
                            local altX, altY = self:findAvoidancePath(troop.x, troop.y, troop.x + TROOP_MARCH_SPEED * 2, troop.y, troop.size, allowThroughBubbles)
                            troop.x, troop.y = altX, altY
                        end
                    else
                        troop.x = newX
                    end
                end
            end
            -- Ranged units stop and fight when in combat
            
            -- Fan out vertically during first 200px of march
            if not troop.fanOutStartX then
                troop.fanOutStartX = troop.x  -- Record starting position for fan-out
                -- Assign a stable march index for consistent spreading
                if not troop.marchIndex then
                    troop.marchIndex = self:assignMarchIndex(troop)
                end
                troop.fanOutTargetY = self:calculateFanOutY(troop, troop.marchIndex)
            end
            
            local marchDistance = troop.x - troop.fanOutStartX
            if marchDistance < 200 then
                -- Fan out phase: move toward assigned Y position
                local dy = troop.fanOutTargetY - troop.y
                if math.abs(dy) > 1 then
                    local newY = troop.y + math.sign(dy) * math.min(1, math.abs(dy))
                    local clampedPos = self:clampToValidArea(troop.x, newY, troop.size)
                    troop.y = clampedPos.y
                end
            end
            
            -- Remove if offscreen (right edge)
            if troop.x > 420 then  -- Screen width + margin
                table.remove(self.troops, i)
            end
        elseif not troop.rallied then
            -- Handle escape from bubbles first, then rally
            local targetX, targetY
            
            if troop.needsEscape then
                -- Check if we've escaped from the bubble
                if not self:checkBubbleCollision(troop.x, troop.y, troop.size) then
                    -- Escaped! Now head to original rally point
                    troop.needsEscape = false
                    troop.targetX = troop.originalRallyX
                    troop.targetY = troop.originalRallyY
                end
                -- Use current escape target
                targetX, targetY = troop.targetX, troop.targetY
            else
                -- Normal rally behavior
                local clusterCenter = self:findTroopClusterCenter(troop)
                targetX = clusterCenter.x
                targetY = clusterCenter.y
            end
            
            -- Move toward cluster center
            local dx = targetX - troop.x
            local dy = targetY - troop.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            -- More flexible rally threshold - accept rallying if close OR if path is blocked by bubbles
            local canRally = dist <= TROOP_MOVE_SPEED * 4
            local pathBlocked = self:checkBubbleCollision(troop.x + (dx/dist) * TROOP_MOVE_SPEED, troop.y + (dy/dist) * TROOP_MOVE_SPEED, troop.size)
            
            if canRally or (pathBlocked and dist <= TROOP_MOVE_SPEED * 8) or isStuck then
                -- Reached cluster area, blocked path, or stuck - join and trigger shuffle
                troop.rallied = true
                self:shuffleTroops(troop)
            else
                -- Move toward cluster center, avoiding bubble collisions
                local newX = troop.x + (dx/dist) * TROOP_MOVE_SPEED
                local newY = troop.y + (dy/dist) * TROOP_MOVE_SPEED
                
                -- Check for bubble collision and adjust path if needed (allow through bubbles if stuck, in combat, or has target)
                local allowThroughBubbles = isStuck or troop.inCombat or (troop.target and self:isTargetValid(troop.target))
                if self:checkBubbleCollision(newX, newY, troop.size) then
                    -- Try moving around the bubble (allow through if needed for combat)
                    local avoidanceX, avoidanceY = self:findAvoidancePath(troop.x, troop.y, targetX, targetY, troop.size, allowThroughBubbles)
                    newX, newY = avoidanceX, avoidanceY
                    
                    -- If still can't move much and not in combat situation, accept current position as "close enough"
                    local moveDistance = math.sqrt((newX - troop.x)^2 + (newY - troop.y)^2)
                    if moveDistance < TROOP_MOVE_SPEED * 0.3 and dist <= TROOP_MOVE_SPEED * 12 and not allowThroughBubbles then
                        troop.rallied = true
                        self:shuffleTroops(troop)
                        newX, newY = troop.x, troop.y  -- Don't move
                    end
                end
                
                local clampedPos = self:clampToValidArea(newX, newY, troop.size)
                troop.x = clampedPos.x
                troop.y = clampedPos.y
            end
        end
    end
    
    -- Handle all unit collisions (troops vs troops, troops vs creeps)
    self:resolveAllUnitCollisions()
    
    -- Check if march is complete (no more marching troops)
    if self.troopMarchActive then
        local hasMatchingTroops = false
        for _, troop in ipairs(self.troops) do
            if troop.marching then
                hasMatchingTroops = true
                break
            end
        end
        if not hasMatchingTroops then
            self.troopMarchActive = false  -- Clear march mode
        end
    end
end
-- Find the target for approaching troops (use their assigned rally point)
function Grid:findTroopClusterCenter(approachingTroop)
    -- Use the approaching troop's assigned rally point
    if approachingTroop and approachingTroop.rallyPoint then
        local clampedRally = self:clampToValidArea(approachingTroop.rallyPoint.x, approachingTroop.rallyPoint.y, TROOP_SIZE_BASIC)
        return {x = clampedRally.x, y = clampedRally.y}
    end
    
    -- Fallback to first rally point if no specific assignment
    local rallyPos = self:getRandomRallyPoint()
    if rallyPos then
        local clampedRally = self:clampToValidArea(rallyPos.x, rallyPos.y, TROOP_SIZE_BASIC)
        return {x = clampedRally.x, y = clampedRally.y}
    end
    
    return {x = 100, y = 100}  -- Final fallback
end
-- Shuffle troops at the same rally point when a new one arrives (gentler packing)
function Grid:shuffleTroops(newTroop)
    -- Only shuffle troops assigned to the same rally point as the new troop
    local sameRallyTroops = {}
    for _, troop in ipairs(self.troops) do
        if troop.rallied and not troop.marching and troop.rallyPoint then
            -- Check if troops share the same rally point
            if newTroop.rallyPoint and 
               troop.rallyPoint.x == newTroop.rallyPoint.x and 
               troop.rallyPoint.y == newTroop.rallyPoint.y then
                sameRallyTroops[#sameRallyTroops + 1] = troop
            end
        end
    end
    
    -- Use the new troop's assigned rally point as anchor
    local rallyAnchor = self:findTroopClusterCenter(newTroop)
    
    -- Pack troops around their specific rally anchor with gentler spacing
    for i, troop in ipairs(sameRallyTroops) do
        local targetPos = self:findTightPackPosition(rallyAnchor.x, rallyAnchor.y, troop.size, i)
        -- Gentle movement instead of instant snap
        self:moveTowardsGently(troop, targetPos.x, targetPos.y)
    end
end

-- Check if troop position would violate 1px gap around tier bubbles
function Grid:checkTroopTierBubbleGap(x, y, troopSize)
    local troopRadius = troopSize / 2
    
    -- Check against Tier 1 bubbles
    for idx, tierData in pairs(self.tierOnePositions) do
        local dx = tierData.centerX - x
        local dy = tierData.centerY - y
        local dist = math.sqrt(dx*dx + dy*dy)
        local minDist = troopRadius + 10 + 1  -- Tier 1 radius (10px) + troop radius + 1px gap
        if dist < minDist then
            return false  -- Too close to tier 1 bubble
        end
    end
    
    -- Check against Tier 2 bubbles  
    for idx, tierData in pairs(self.tierTwoPositions) do
        local dx = tierData.centerX - x
        local dy = tierData.centerY - y
        local dist = math.sqrt(dx*dx + dy*dy)
        local minDist = troopRadius + 15 + 1  -- Tier 2 radius (~15px) + troop radius + 1px gap
        if dist < minDist then
            return false  -- Too close to tier 2 bubble
        end
    end
    
    -- Check against Tier 3 bubbles
    for idx, tierData in pairs(self.tierThreePositions) do
        local dx = tierData.centerX - x
        local dy = tierData.centerY - y
        local dist = math.sqrt(dx*dx + dy*dy)
        local minDist = troopRadius + 20 + 1  -- Tier 3 radius (~20px) + troop radius + 1px gap
        if dist < minDist then
            return false  -- Too close to tier 3 bubble
        end
    end
    
    return true  -- Position is safe with 1px gap
end

-- Move troop gently towards target position to reduce jitter
function Grid:moveTowardsGently(troop, targetX, targetY)
    local dx = targetX - troop.x
    local dy = targetY - troop.y
    local dist = math.sqrt(dx*dx + dy*dy)
    
    -- Only move if we're more than 1 pixel away
    if dist > 1 then
        -- Move slowly towards target (1/4 the distance each frame)
        troop.x = troop.x + dx * 0.25
        troop.y = troop.y + dy * 0.25
    end
end

-- Find tightly packed position for a troop respecting boundaries
function Grid:findTightPackPosition(centerX, centerY, troopSize, troopIndex)
    -- Try center first
    if troopIndex == 1 then
        local clampedPos = self:clampToValidArea(centerX, centerY, troopSize)
        return {x = clampedPos.x, y = clampedPos.y}
    end
    
    -- Pack in concentric circles with better spacing to avoid tier bubbles
    local ring = math.ceil((troopIndex - 1) / 6)  -- 6 troops per ring max
    local posInRing = ((troopIndex - 2) % 6) + 1
    local ringRadius = ring * troopSize * 2.5  -- Increased spacing to maintain 1px gap from tier bubbles
    local angleStep = (math.pi * 2) / 6
    local angle = (posInRing - 1) * angleStep
    
    -- Add small random offset to prevent perfect alignment and oscillation
    angle = angle + (math.random() - 0.5) * 0.3
    
    local testX = centerX + math.cos(angle) * ringRadius
    local testY = centerY + math.sin(angle) * ringRadius
    
    -- Check if position respects 1px gap around tier bubbles
    if not self:checkTroopTierBubbleGap(testX, testY, troopSize) then
        -- If too close to tier bubbles, try wider spacing (crowded override)
        ringRadius = ringRadius * 1.5
        testX = centerX + math.cos(angle) * ringRadius
        testY = centerY + math.sin(angle) * ringRadius
        
        -- If still too close and really crowded, allow it but warn with wider spacing
        if not self:checkTroopTierBubbleGap(testX, testY, troopSize) then
            ringRadius = ringRadius * 1.3  -- Extra spacing for crowded situations
            testX = centerX + math.cos(angle) * ringRadius
            testY = centerY + math.sin(angle) * ringRadius
        end
    end
    
    -- Clamp to valid area (respect left edge and bottom boundary)
    local clampedPos = self:clampToValidArea(testX, testY, troopSize)
    return {x = clampedPos.x, y = clampedPos.y}
end
-- Clamp unit position to stay within valid screen area
function Grid:clampToValidArea(x, y, unitSize)
    local margin = unitSize / 2
    local minX = LEFT_BOUNDARY + margin  -- Don't go past left edge
    local maxX = 400 - margin  -- Right edge
    local minY = 8 + margin   -- Top of grid (row 1)
    local maxY = (13-1) * 16 + 8 + margin  -- Bottom of row 13 (avoid rows 14-15)
    
    return {
        x = math.max(minX, math.min(maxX, x)),
        y = math.max(minY, math.min(maxY, y))
    }
end
-- Calculate vertical spread target for marching troops (avoid rows 14-15)
function Grid:calculateFanOutY(troop, troopIndex)
    -- Define valid Y range for rows 1-13
    local row1Y = 8      -- Top of row 1
    local row13Y = (13-1) * 16 + 8  -- Top of row 13
    local validHeight = row13Y - row1Y
    
    -- Count how many troops are marching for even distribution
    local marchingTroops = {}
    for _, t in ipairs(self.troops) do
        if t.marching then
            marchingTroops[#marchingTroops + 1] = t
        end
    end
    local marchingCount = #marchingTroops
    
    if marchingCount <= 1 then
        return troop.y  -- No spreading needed for single troop
    end
    
    -- Distribute evenly across the valid Y range
    local spacing = validHeight / (marchingCount - 1)
    local targetY = row1Y + (troopIndex - 1) * spacing
    
    -- Clamp to ensure we stay within valid bounds
    local clampedPos = self:clampToValidArea(troop.x, targetY, troop.size)
    return clampedPos.y
end
-- Assign a stable march index for consistent troop spreading
function Grid:assignMarchIndex(targetTroop)
    local marchingTroops = {}
    for _, troop in ipairs(self.troops) do
        if troop.marching then
            marchingTroops[#marchingTroops + 1] = troop
        end
    end
    
    -- Find the position of our target troop in the list
    for i, troop in ipairs(marchingTroops) do
        if troop == targetTroop then
            return i
        end
    end
    
    return 1  -- Fallback
end
-- Math helper: sign function
function math.sign(x)
    if x > 0 then return 1
    elseif x < 0 then return -1
    else return 0 end
end
-- Find available position around rally point (concentric spreading)
function Grid:findSpreadPosition(centerX, centerY, troopSize)
    -- Try center first
    if not self:isTroopPositionOccupied(centerX, centerY, troopSize) then
        self:markTroopPosition(centerX, centerY, troopSize, true)
        return {x = centerX, y = centerY}
    end
    
    -- Spread concentrically in increasing rings
    for ring = 1, 5 do
        local ringRadius = ring * troopSize * 2
        for angle = 0, math.pi * 2 - 0.1, 0.3 do
            local testX = centerX + math.cos(angle) * ringRadius
            local testY = centerY + math.sin(angle) * ringRadius
            
            if not self:isTroopPositionOccupied(testX, testY, troopSize) then
                self:markTroopPosition(testX, testY, troopSize, true)
                return {x = testX, y = testY}
            end
        end
    end
    
    -- Fallback to original position if no space found
    return {x = centerX, y = centerY}
end
-- Check if position is occupied by another troop
function Grid:isTroopPositionOccupied(x, y, size)
    for _, troop in ipairs(self.troops) do
        if troop.rallied and not troop.marching then
            local dx = troop.x - x
            local dy = troop.y - y
            local dist = math.sqrt(dx*dx + dy*dy)
            if dist < (size + troop.size) then
                return true
            end
        end
    end
    return false
end
-- Mark position as occupied (for rally point management)
function Grid:markTroopPosition(x, y, size, occupied)
    -- This could be expanded for more sophisticated position tracking
    -- For now, collision detection handles overlap prevention
end
-- Start marching all rallied troops to the right
function Grid:marchTroopsOffscreen()
    self.troopMarchActive = true  -- Set march mode flag
    for _, troop in ipairs(self.troops) do
        if troop.rallied then
            troop.marching = true
        end
    end
end
-- Unified collision system for all units (troops vs troops, troops vs creeps, creeps vs creeps)
function Grid:resolveAllUnitCollisions()
    -- Create a unified list of all units with their properties
    local allUnits = {}
    
    -- Add all troops
    for _, troop in ipairs(self.troops) do
        allUnits[#allUnits + 1] = {
            x = troop.x,
            y = troop.y,
            size = troop.size,
            unit = troop,
            type = "troop",
            marching = troop.marching,
            rallied = troop.rallied or false
        }
    end
    
    -- Add all creeps
    for _, creep in ipairs(self.creeps) do
        allUnits[#allUnits + 1] = {
            x = creep.x,
            y = creep.y,
            size = creep.size,
            unit = creep,
            type = "creep",
            marching = creep.marching,
            rallied = false  -- Creeps don't rally
        }
    end
    
    -- Check all pairs for collision
    for i = 1, #allUnits do
        for j = i+1, #allUnits do
            local u1, u2 = allUnits[i], allUnits[j]
            local dx = u2.x - u1.x
            local dy = u2.y - u1.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            -- Calculate minimum distance respecting 1px buffers
            -- Each unit's size already accounts for the 1px buffer
            local minDist = u1.size + u2.size
            
            -- Special case: allow tighter packing for rallied troops only
            if u1.type == "troop" and u2.type == "troop" and u1.rallied and u2.rallied 
               and not u1.marching and not u2.marching then
                minDist = minDist * 0.8  -- Tighter rally formation
            end
            
            if dist < minDist and dist > 0 then
                -- Calculate push force
                local pushDist = (minDist - dist) / 2
                local pushX = (dx/dist) * pushDist
                local pushY = (dy/dist) * pushDist
                
                -- Apply push (update original unit positions)
                u1.unit.x = u1.unit.x - pushX
                u1.unit.y = u1.unit.y - pushY
                u2.unit.x = u2.unit.x + pushX
                u2.unit.y = u2.unit.y + pushY
                
                -- Update the working copies for this frame
                u1.x = u1.unit.x
                u1.y = u1.unit.y
                u2.x = u2.unit.x
                u2.y = u2.unit.y
            end
        end
    end
end
-- Draw all troops
function Grid:drawTroops()
    for _, troop in ipairs(self.troops) do
        local sprite = self.bubbleSprites.troops.basic
        local offset = troop.size / 2
        
        if troop.tier == "tier1" then
            sprite = self.bubbleSprites.troops.tier1 or sprite
        elseif troop.tier == "tier2" then
            sprite = self.bubbleSprites.troops.tier2 or sprite
        elseif troop.tier == "tier3" then
            sprite = self.bubbleSprites.troops.tier3 or sprite
            offset = 16  -- 32x32 sprite needs 16px offset for proper centering
        end
        
        sprite:draw(troop.x - offset, troop.y - offset)
        
        -- Draw health bar if unit is damaged (debug mode only)
        if self.showDebug and troop.hitpoints < troop.maxHitpoints then
            self:drawHealthBar(troop.x, troop.y - offset - 8, troop.hitpoints, troop.maxHitpoints, 12)
        end
    end
end

-- Draw all active projectiles
function Grid:drawProjectiles()
    gfx.setColor(gfx.kColorBlack)
    
    for _, projectile in ipairs(self.projectiles) do
        if projectile.size == 2 then
            -- 2px square projectile (Tier 2)
            gfx.fillRect(
                math.floor(projectile.x - 1), 
                math.floor(projectile.y - 1), 
                2, 2
            )
        elseif projectile.size == 4 then
            -- 4x4 square projectile (Tier 3)
            gfx.fillRect(
                math.floor(projectile.x - 2), 
                math.floor(projectile.y - 2), 
                4, 4
            )
        end
    end
end

-- Draw a health bar above a unit
function Grid:drawHealthBar(x, y, currentHealth, maxHealth, width)
    if currentHealth <= 0 or currentHealth >= maxHealth then return end
    
    local healthRatio = currentHealth / maxHealth
    local healthWidth = math.floor(width * healthRatio)
    
    -- Background (black)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(x - width/2, y, width, 2)
    
    -- Health bar (white)  
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - width/2, y, healthWidth, 2)
end

-- Handle troop shot counting and cycle management
function Grid:handleTroopShotCounting()
    self.troopShotCounter = self.troopShotCounter + 1
    
    -- Shot 4: enter battle preparation mode instead of immediate marching
    if self.troopShotCounter == 4 then
        self.battleState = "waiting_for_merges"
        self.troopShotCounter = 0  -- Reset for next cycle
    end
end

-- Battle popup system
function Grid:startBattlePopup()
    self.battleState = "show_popup"
    self.popup.active = true
    self.popup.frame = 0
    self.popup.text = "Attack!"
end

function Grid:updateBattlePopup()
    if self.popup.active then
        self.popup.frame = self.popup.frame + 1
        
        if self.popup.frame >= 63 then
            -- Popup duration complete - start the battle
            self.popup.active = false
            self.battleState = "normal"  -- Return to normal after battle starts
            
            -- Now start the actual battle actions
            self:marchTroopsOffscreen()
            self:startCreepMarch()
        end
    end
end

-- Spawn troops when merges/tiers complete (called from animation completions)
function Grid:spawnTroopsForShot()
    -- Always spawn from existing tier bubbles
    self:spawnTroopsFromBubbles()
    
    -- Spawn basic troops every turn (1/5 of basic bubbles)
    self:spawnBasicTroops()
end

-- Draw active animations
-- PURPOSE: Render all active animations with proper visual effects
-- PARAMS: None
-- RETURNS: None
-- SIDE_EFFECTS: Draws sprites to screen using animation interpolation
-- AI_NOTE: ANIMATION RENDERING PIPELINE:
-- 1. Iterate through all active animations in self.animations
-- 2. Calculate progress (frame / total_frames) for interpolation
-- 3. For each animation type, render appropriate visual effects:
--    • merge: Balls converging to center point
--    • tier1_placement: Tier 1 bubble moving to triangle center
--    • tier2_magnetism: Two Tier 1 bubbles moving to midpoint
--    • tier2_snap: Grid snapping effect for Tier 2 placement
--    • tier3_magnetism: Tier 1 + Tier 2 moving to midpoint
--    • tier3_snap: Grid snapping effect for Tier 3 placement
--    • tier3_flash: Flashing effect (hold → flash1 → off1 → flash2 → off2 → flash3 → off3)
-- 4. Use currentX/Y interpolation for smooth movement animations
-- 5. Respect flash states for tier3_flash (only draw during flash states, not off states)
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
        elseif anim.type == "tier1_placement" then
            local progress = math.min(anim.frame / MERGE_ANIMATION_FRAMES, 1.0)
            
            -- Draw tier 1 bubble moving from merge center to triangle center
            local currentX = anim.startX + (anim.endX - anim.startX) * progress
            local currentY = anim.startY + (anim.endY - anim.startY) * progress
            -- Debug disabled for minimal test case
            self.bubbleSprites.tier1[anim.ballType]:draw(currentX - 18, currentY - 18)
        elseif anim.type == "tier2_snap" then
            local progress = math.min(anim.frame / MERGE_ANIMATION_FRAMES, 1.0)
            
            -- Draw tier 2 bubble moving from midpoint to grid center
            local currentX = anim.startX + (anim.endX - anim.startX) * progress
            local currentY = anim.startY + (anim.endY - anim.startY) * progress
            self.bubbleSprites.tier2[anim.sprite]:draw(currentX - 26, currentY - 26)
        elseif anim.type == "tier3_snap" then
            local progress = math.min(anim.frame / MERGE_ANIMATION_FRAMES, 1.0)
            
            -- Draw tier 3 bubble moving from midpoint to grid center
            local currentX = anim.startX + (anim.endX - anim.startX) * progress
            local currentY = anim.startY + (anim.endY - anim.startY) * progress
            self.bubbleSprites.tier3[anim.sprite]:draw(currentX - 42, currentY - 42)
        elseif anim.type == "tier3_flash" then
            -- Only draw during hold and flash states, not during off states
            if anim.flashState == "hold" or anim.flashState == "flash1" or anim.flashState == "flash2" or anim.flashState == "flash3" then
                self.bubbleSprites.tier3[anim.sprite]:draw(anim.centerX - 42, anim.centerY - 42)
            end
        end
    end
end

-- Draw UI elements
function Grid:drawUI()
    -- On-deck ball (only show when loaded after delay)
    local onDeckPos = self.positions[(15 - 1) * 20 + 17]
    if onDeckPos and self.onDeckBallType then
        self.bubbleSprites.basic[self.onDeckBallType]:draw(onDeckPos.x - 10, onDeckPos.y - 10)
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