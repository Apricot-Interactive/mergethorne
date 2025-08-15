-- Mergethorne Grid System - Complete Implementation
-- 
-- Architecture Overview:
-- - Single unified cell system: {ballType, occupied, permanent, tier}
-- - 20px hex grid, visual collision detection with immediate snapping
-- - Merge detection via flood-fill, animated ball convergence and tier progression
-- - Complete tier progression: Basic → Tier 1 → Tier 2 → Tier 3
-- - Enemy creep spawning system with staging positions and march cycles
-- - Allied troop spawning system with rally point clustering and march coordination
-- - Unified collision system respecting 1px sprite buffers across all unit types
--
-- Performance: 60fps stable, ~1900 lines with full feature set
-- Design principle: Clean separation of concerns, boundary-aware positioning

local MergeConstants = import("game/mergeConstants")

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Core constants
local BALL_SPEED <const> = 9
local COLLISION_RADIUS <const> = 20
local FLYING_BALL_RADIUS <const> = 18  -- 2px smaller for tighter gaps
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

-- ============================================================================
-- ENEMY CREEP SYSTEM CONSTANTS
-- ============================================================================
-- Creeps spawn in cycles, move to staging positions, then march toward towers

-- Creep spawn and movement
local CREEP_STAGING_POSITIONS <const> = {
    (3-1) * 20 + 18,   -- Row 3, Col 18 (grid index 58)
    (5-1) * 20 + 18,   -- Row 5, Col 18 (grid index 98)  
    (7-1) * 20 + 18,   -- Row 7, Col 18 (grid index 138)
    (9-1) * 20 + 18,   -- Row 9, Col 18 (grid index 178)
    (11-1) * 20 + 18   -- Row 11, Col 18 (grid index 218)
}
local CREEP_SPAWN_OFFSET <const> = 100  -- Pixels to right of staging spot
local CREEP_MOVE_SPEED <const> = 3      -- Pixels per frame movement speed (increased by 50%)
local CREEP_MARCH_SPEED <const> = 0.75  -- Pixels per frame when marching toward towers (1.5x faster)
local CREEP_SIZE <const> = 3            -- Collision radius (4px sprite with 1px transparent edge)
local CREEP_RALLY_LINE_X <const> = 330  -- X coordinate of dashed line where creeps queue

-- REBALANCED: Creep hitpoints for strategic combat (playtesting balance)
local CREEP_HP_BASIC <const> = 30   -- Basic creeps: 10 hits from flame, 2.5 from tremor
local CREEP_HP_TIER1 <const> = 90   -- Tier 1 creeps: 30 hits from flame, 7.5 from tremor
local CREEP_HP_TIER2 <const> = 200  -- Tier 2 creeps: 67 hits from flame, 17 from tremor

-- REBALANCED: Creep combat capabilities (Basic suicide, Tier 1+2 ranged)
local CREEP_ATTACK_RANGE <const> = 30   -- Range for basic creep suicide attacks
local CREEP_BASIC_DAMAGE <const> = 15   -- Basic creep suicide damage
local CREEP_ATTACK_COOLDOWN <const> = 25 -- Frames between basic creep attacks

-- Basic creep charge system (activate within 20px of target)
local CREEP_CHARGE_RANGE <const> = 20   -- Range to activate charge (outer edge collision)
local CREEP_CHARGE_SPEED <const> = 6    -- 200% of normal speed (3 * 2 = 6)

-- Zone-based targeting system (3 vertical slices of the battlefield)
local ZONE_1_MIN_X <const> = 266        -- Zone 1: closest to creep rally (rightmost)
local ZONE_2_MIN_X <const> = 133        -- Zone 2: middle zone
-- Zone 3 is everything below ZONE_2_MIN_X (leftmost, furthest from creep rally)

-- Fixed rally positions for each creep tier
local BASIC_RALLY_ROWS <const> = {3, 5, 7, 9, 11}     -- Basic creeps rally to rows 3,5,7,9,11 at col 18
local TIER1_RALLY_ROWS <const> = {4, 6, 8, 10, 12}    -- Tier 1 creeps rally to rows 4,6,8,10,12 at col 18  
local TIER2_RALLY_ROWS <const> = {3, 5, 7, 9, 11}     -- Tier 2 creeps rally to rows 3,5,7,9,11 at col 19

-- Convert row numbers to grid indices for each tier
local BASIC_RALLY_POSITIONS <const> = {
    (3-1) * 20 + 18,   -- Row 3, Col 18
    (5-1) * 20 + 18,   -- Row 5, Col 18
    (7-1) * 20 + 18,   -- Row 7, Col 18
    (9-1) * 20 + 18,   -- Row 9, Col 18
    (11-1) * 20 + 18   -- Row 11, Col 18
}
local TIER1_RALLY_POSITIONS <const> = {
    (4-1) * 20 + 18,   -- Row 4, Col 18
    (6-1) * 20 + 18,   -- Row 6, Col 18
    (8-1) * 20 + 18,   -- Row 8, Col 18
    (10-1) * 20 + 18,  -- Row 10, Col 18
    (12-1) * 20 + 18   -- Row 12, Col 18
}
local TIER2_RALLY_POSITIONS <const> = {
    (3-1) * 20 + 19,   -- Row 3, Col 19
    (5-1) * 20 + 19,   -- Row 5, Col 19
    (7-1) * 20 + 19,   -- Row 7, Col 19
    (9-1) * 20 + 19,   -- Row 9, Col 19
    (11-1) * 20 + 19   -- Row 11, Col 19
}

-- Tier 1 ranged combat system (aggressive, close-range, balanced vs old suicide)
local CREEP_TIER1_RANGE <const> = 80    -- Tier 1 shooting range (reduced to fire just before stopping)
local CREEP_TIER1_DAMAGE <const> = 20   -- Tier 1 ranged damage per shot (balanced for sustained DPS)
local CREEP_TIER1_COOLDOWN <const> = 90 -- Tier 1 shot cooldown (1.5 seconds vs Tier 2's 1 sec)
local CREEP_TIER1_MIN_DISTANCE <const> = 20 -- Tier 1s get twice as close (was 40 for Tier 2)

-- Tier 2 ranged combat system (cautious, long-range)
local CREEP_TIER2_RANGE <const> = 110   -- Tier 2 shooting range (reduced to fire just before stopping)
local CREEP_TIER2_DAMAGE <const> = 25   -- Tier 2 ranged damage per shot
local CREEP_TIER2_COOLDOWN <const> = 60 -- Tier 2 shot cooldown (1 shot/second)
local CREEP_TIER2_MIN_DISTANCE <const> = 40 -- Minimum distance Tier 2s maintain from targets

-- Creep projectile constants
local CREEP_TIER1_PROJECTILE_SPEED <const> = 4.0 -- Tier 1 projectile speed (increased for visibility)
local CREEP_TIER2_PROJECTILE_SPEED <const> = 3.5 -- Tier 2 projectile speed (increased for visibility)

-- Lightning tower smart targeting weights (priority system)
local LIGHTNING_TARGET_WEIGHT_TIER2 <const> = 100  -- Highest priority: Tier 2 creeps
local LIGHTNING_TARGET_WEIGHT_TIER1 <const> = 50   -- Medium priority: Tier 1 creeps
local LIGHTNING_TARGET_WEIGHT_BASIC <const> = 10   -- Lowest priority: Basic creeps

-- ============================================================================
-- ALLIED TROOP SYSTEM CONSTANTS  
-- ============================================================================
-- Troops spawn from tier bubbles and rally at multiple points to reduce clustering

local TROOP_RALLY_POINTS <const> = {
    (6-1) * 20 + 1,  -- Row 6, Col 1 (grid index 101)
    (7-1) * 20 + 1,  -- Row 7, Col 1 (grid index 121)  
    (7-1) * 20 + 2,  -- Row 7, Col 2 (grid index 122)
    (8-1) * 20 + 1   -- Row 8, Col 1 (grid index 141)
}
local TROOP_MOVE_SPEED <const> = 2      -- Pixels per frame movement speed
local TROOP_MARCH_SPEED <const> = 2     -- Speed when marching off-screen

-- Troop collision sizes by tier (sprite size + 1px transparent buffer)
local TROOP_SIZE_BASIC <const> = 3   -- 4px sprite with 1px buffer
local TROOP_SIZE_TIER1 <const> = 4   -- 5px sprite with 1px buffer  
local TROOP_SIZE_TIER2 <const> = 8   -- 9px sprite with 1px buffer
local TROOP_SIZE_TIER3 <const> = 8   -- 9px sprite with 1px buffer

-- ============================================================================
-- TOWER COMBAT SYSTEM CONSTANTS
-- ============================================================================
-- TOWER DESIGN PHILOSOPHY:
-- Each tower type fills a unique tactical role with distinct strengths/weaknesses:
--
-- 1. FLAME TOWER (Fire) - Anti-swarm specialist
--    Role: Fast, continuous damage with cone spread
--    Strengths: High DPS, good vs basic creeps, fast reaction
--    Weaknesses: Low damage per hit, shorter range
--    Best against: Large groups of weak enemies
--
-- 2. RAIN TOWER (Water) - Area denial 
--    Role: Constant area damage around tower position
--    Strengths: No aim required, continuous damage, can't miss
--    Weaknesses: Fixed position, limited range, predictable
--    Best against: Enemies forced through chokepoints
--
-- 3. TREMOR TOWER (Earth) - Line formation breaker
--    Role: Piercing arc shots that hit multiple enemies  
--    Strengths: Pierces through enemies, good burst damage
--    Weaknesses: Slower attack rate, requires good positioning
--    Best against: Lined up enemies, medium-tier threats
--
-- 4. LIGHTNING TOWER (Lightning) - Single target assassin
--    Role: Instant high damage to priority targets
--    Strengths: Highest single-hit damage, instant delivery
--    Weaknesses: Very short range, limited targets per attack
--    Best against: High-value single targets, tier 2 creeps
--
-- 5. WIND TOWER (Wind) - Crowd control specialist  
--    Role: Wide area spirograph patterns for area coverage
--    Strengths: Longest range, unpredictable patterns
--    Weaknesses: Complex timing, moderate damage
--    Best against: Spread out enemies, area control
--
-- Tower types: 1=Flame (Fire), 2=Rain (Water), 3=Tremor (Earth), 4=Lightning, 5=Wind

-- General tower properties
local TOWER_HP <const> = 800                   -- Hitpoints for all towers (survivable vs creep rush)
local TOWER_ATTACK_COOLDOWN <const> = 20       -- Default frames between attacks (3/sec at 60fps)
local TOWER_SPRITE_RADIUS <const> = 18         -- Tier 1 tower sprite radius for collision
local PROJECTILE_FIRE_RANGE_MULTIPLIER <const> = 2.5  -- Towers fire at 250% of projectile range

-- OPTIMIZATION: Pre-computed constants for performance (avoid repeated calculations)
local HALF_PI <const> = math.pi * 0.5          -- π/2 for perpendicular angles
local TWO_PI <const> = math.pi * 2              -- 2π for angle normalization  
local PI_OVER_180 <const> = math.pi / 180      -- Degrees to radians conversion
local SQRT_EPSILON <const> = 0.000001          -- Epsilon for sqrt comparisons

-- Flame Tower (ballType 1) - Rapid fire cone attacks
local FLAME_TOWER_RANGE <const> = 240          -- Detection/targeting range
local FLAME_PROJECTILE_SPEED <const> = 1.25    -- Projectile velocity (pixels/frame)
local FLAME_PROJECTILE_RANGE <const> = 60      -- Distance projectiles travel before despawning
local FLAME_CONE_ANGLE <const> = 15            -- ±15 degrees cone spread from aim direction
local FLAME_PROJECTILE_DAMAGE <const> = 1      -- Damage per projectile (low but rapid)
local FLAME_PROJECTILES_PER_SHOT <const> = 3   -- Number of projectiles per attack
local FLAME_TOWER_COOLDOWN <const> = 2         -- Frames between attacks (very rapid)
local FLAME_ROTATION_SPEED <const> = math.pi / 12  -- 90° per 6 frames rotation speed

-- Tremor Tower (ballType 3) - Precise arc shockwaves  
local TREMOR_TOWER_RANGE <const> = 240         -- Detection/targeting range (same as flame)
local TREMOR_PROJECTILE_SPEED <const> = 3.0    -- Projectile velocity (faster than flame)
local TREMOR_PROJECTILE_RANGE <const> = 60     -- Distance projectiles travel (same as flame)
local TREMOR_ARC_ANGLE <const> = 45            -- Total arc span in degrees (45° spread)
local TREMOR_PROJECTILES_PER_SHOT <const> = 15 -- 15 projectiles in precise formation
local TREMOR_TOWER_COOLDOWN <const> = 25       -- Frames between attacks (slower than flame)
local TREMOR_ROTATION_SPEED <const> = math.pi / 12  -- Same rotation speed as flame
local TREMOR_PROJECTILE_DAMAGE <const> = 3     -- Higher damage per projectile (pierces targets)

-- Rain Tower (ballType 2) - Stationary damage dots
local RAIN_DOTS_PER_FRAME <const> = 4          -- Number of dots spawned each frame
local RAIN_DOT_LIFETIME <const> = 10           -- Frames each dot lasts (2x longer)
local RAIN_DOT_DAMAGE <const> = 2              -- Damage per dot collision
local RAIN_INNER_RADIUS <const> = 10           -- Inner radius (tower radius)
local RAIN_OUTER_RADIUS <const> = 40           -- Outer radius (tower radius + 30px)

-- Wind Tower (ballType 5) - Spirograph burst patterns
local WIND_TOWER_RANGE <const> = 240           -- Detection/targeting range (same as others)
local WIND_PROJECTILE_SPEED <const> = 2.0      -- Base speed of wind projectiles
local WIND_PROJECTILE_RANGE <const> = 60       -- Distance projectiles travel (same as others)
local WIND_PROJECTILES_PER_BURST <const> = 10  -- 10 projectiles fired over 10 frames (1 per frame)
local WIND_BURST_DURATION <const> = 10         -- Frames to fire all projectiles (1 per frame)
local WIND_TOWER_COOLDOWN <const> = 34         -- 24 frame cooldown after burst (10 + 24 = 34 total)
local WIND_ROTATION_SPEED <const> = math.pi / 12  -- Same rotation speed as other towers
local WIND_PROJECTILE_DAMAGE <const> = 2       -- Moderate damage per projectile
local WIND_SPIRAL_RADIUS <const> = 15          -- Radius of spirograph circle (pixels)

-- ENHANCED: Wind tower pushback system - smooth animation with 3x distance
local WIND_PUSHBACK_DISTANCE <const> = 27      -- Total pushback distance (3x original 9px)
local WIND_PUSHBACK_DURATION <const> = 9       -- Frames to complete pushback animation (50% slower)
local WIND_PUSHBACK_COOLDOWN <const> = 15      -- Frames between pushback applications

-- BALANCED: Lightning Tower (ballType 4) - High burst damage, short range
local LIGHTNING_TOWER_RANGE <const> = 160       -- Detection range (was 180, shorter for balance)
local LIGHTNING_TOWER_COOLDOWN <const> = 8      -- Cooldown between sequences (was 6, slightly slower)
local LIGHTNING_BOLT_RANGE <const> = 75         -- Lightning bolt max range (was 70, slightly longer)
local LIGHTNING_BOLT_DAMAGE <const> = 35        -- Damage per bolt hit (was 12, massive increase!)
local LIGHTNING_BOLTS_PER_SEQUENCE <const> = 2  -- Number of bolts fired in sequence
local LIGHTNING_SEQUENCE_DURATION <const> = 8   -- Frames for entire sequence (bolts at frame 1 and 5)
local LIGHTNING_BOLT_LIFETIME <const> = 3       -- Frames each bolt remains visible
local LIGHTNING_SEGMENTS_MIN <const> = 3        -- Minimum jagged line segments (more branches)
local LIGHTNING_SEGMENTS_MAX <const> = 6        -- Maximum jagged line segments (up to 6 branches)
local LIGHTNING_JITTER_RANGE <const> = 15       -- Pixels of random jitter for jagged effect

-- ============================================================================
-- COLLISION AND BOUNDARY CONSTANTS
-- ============================================================================

-- Screen and collision boundaries
local SCREEN_WIDTH <const> = 400               -- Game screen width
local SCREEN_HEIGHT <const> = 240              -- Game screen height
local PROJECTILE_HIDE_DISTANCE <const> = 20    -- Hide projectiles within this distance of tower

-- ============================================================================
-- TOWER TYPE CONFIGURATION TABLE
-- ============================================================================
-- Extensible configuration for all tower types - makes adding new towers easy

local TOWER_CONFIGS <const> = {
    [1] = { -- Flame Tower (Fire)
        name = "Flame",
        range = FLAME_TOWER_RANGE,
        projectileSpeed = FLAME_PROJECTILE_SPEED,
        projectileRange = FLAME_PROJECTILE_RANGE,
        projectileDamage = FLAME_PROJECTILE_DAMAGE,
        projectilesPerShot = FLAME_PROJECTILES_PER_SHOT,
        cooldown = FLAME_TOWER_COOLDOWN,
        rotationSpeed = FLAME_ROTATION_SPEED,
        special = {
            coneAngle = FLAME_CONE_ANGLE,
            variableRange = true,  -- 90-110% range variation
            piercing = false       -- Projectiles despawn on hit
        }
    },
    [2] = { -- Rain Tower (Water)
        name = "Rain",
        range = 0,  -- No attack range - always active
        projectileSpeed = 0,  -- Stationary dots
        projectileRange = 0,  -- Dots don't move
        projectileDamage = RAIN_DOT_DAMAGE,
        projectilesPerShot = RAIN_DOTS_PER_FRAME,
        cooldown = 1,  -- Spawn every frame
        rotationSpeed = 0,  -- No rotation needed
        special = {
            dotLifetime = RAIN_DOT_LIFETIME,
            innerRadius = RAIN_INNER_RADIUS,
            outerRadius = RAIN_OUTER_RADIUS,
            variableRange = false, -- Fixed area
            piercing = false       -- Dots despawn on hit
        }
    },
    [3] = { -- Tremor Tower (Earth)
        name = "Tremor",
        range = TREMOR_TOWER_RANGE,
        projectileSpeed = TREMOR_PROJECTILE_SPEED,
        projectileRange = TREMOR_PROJECTILE_RANGE,
        projectileDamage = TREMOR_PROJECTILE_DAMAGE,
        projectilesPerShot = TREMOR_PROJECTILES_PER_SHOT,
        cooldown = TREMOR_TOWER_COOLDOWN,
        rotationSpeed = TREMOR_ROTATION_SPEED,
        special = {
            arcAngle = TREMOR_ARC_ANGLE,
            variableRange = false, -- Fixed range
            piercing = true        -- Projectiles continue after hit
        }
    },
    [4] = { -- Lightning Tower (Lightning)
        name = "Lightning",
        range = LIGHTNING_TOWER_RANGE,
        projectileSpeed = 0, -- Instant bolts
        projectileRange = LIGHTNING_BOLT_RANGE,
        projectileDamage = LIGHTNING_BOLT_DAMAGE,
        projectilesPerShot = LIGHTNING_BOLTS_PER_SEQUENCE,
        cooldown = LIGHTNING_TOWER_COOLDOWN,
        rotationSpeed = WIND_ROTATION_SPEED, -- Same as wind tower
        special = {
            sequenceDuration = LIGHTNING_SEQUENCE_DURATION,
            boltLifetime = LIGHTNING_BOLT_LIFETIME,
            segmentsMin = LIGHTNING_SEGMENTS_MIN,
            segmentsMax = LIGHTNING_SEGMENTS_MAX,
            jitterRange = LIGHTNING_JITTER_RANGE,
            variableRange = false, -- Fixed range
            piercing = false       -- Bolts hit once
        }
    },
    [5] = { -- Wind Tower (Wind)
        name = "Wind",
        range = WIND_TOWER_RANGE,
        projectileSpeed = WIND_PROJECTILE_SPEED,
        projectileRange = WIND_PROJECTILE_RANGE,
        projectileDamage = WIND_PROJECTILE_DAMAGE,
        projectilesPerShot = WIND_PROJECTILES_PER_BURST,
        cooldown = WIND_TOWER_COOLDOWN,
        rotationSpeed = WIND_ROTATION_SPEED,
        special = {
            burstDuration = WIND_BURST_DURATION,
            spiralRadius = WIND_SPIRAL_RADIUS,
            variableRange = false, -- Fixed range
            piercing = false       -- Projectiles despawn on hit
        }
    }
    -- Future tower types: [2] = Water
}

local Grid = {}

-- ============================================================================
-- SPRITE LOADING & INITIALIZATION
-- ============================================================================

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
    
    -- Cell 13,16 (former shooter position) is now a legal playable space
end

-- Initialize game state variables
function Grid:setupGameState()
    self.angle = 0
    self.ball = nil
    -- Simple ammo system: array of balls
    self.ammo = {}
    for i = 1, 15 do
        self.ammo[i] = math.random(1, 5)
    end
    self.currentShotIndex = 1  -- Which shot we're on (1-15)
    self.currentLevel = 1      -- Which level we're on (1-5)
    self.gameState = "playing"
    self.showDebug = false
    self.frameCounter = 0      -- Global frame counter for knockback cooldown
    
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
    self.creeps = {}  -- {x, y, targetX, targetY, animating, staged, tier, size, marching}
    self.stagingOccupied = {}  -- Track which staging positions are occupied
    -- Creep spawning is now random based on dice rolls per shot
    self.finalAttackTriggered = false  -- Track if final attack sequence has begun
    self.finalAttackDelay = nil  -- Countdown timer before final march
    self.finaleTriggered = false  -- Simple finale trigger when ammo exhausted
    self.finaleCountdown = nil  -- Simple countdown to start marching
    
    -- Troop system
    self.troops = {}  -- {x, y, targetX, targetY, tier, size, marching, rallied}
    self.troopShotCounter = 0  -- Independent shot counter for troop cycles
    self.rallyPointOccupied = {}  -- Track positions around rally point
    self.troopMarchActive = false  -- Track when troops are in march mode
    
    -- Tower combat system
    self.projectiles = {}  -- {x, y, vx, vy, damage, towerType, lifespan, range}
    self.rainDots = {}     -- {x, y, damage, lifetime, spawFrame, underTower} - stationary damage dots
    self.lightningEffects = {}  -- {path, lifetime, damage, targetCreep} - instant lightning bolts
    
    -- Precompute aim direction
    self:updateAimDirection()
    
    -- Add starting balls
    self:setupStartingBalls()
end

-- Initialize starting grid with pre-placed bubbles based on level
function Grid:setupStartingBalls()
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
    
    local prePlacedCells = {}
    
    -- Different starting grids based on level
    if self.currentLevel <= 2 then
        -- Simpler grid for levels 1-2
        prePlacedCells = {
            {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"}, {{3,1}, "A"}, {{3,2}, "A"}, {{3,3}, "A"},
            {{4,1}, "B"}, {{4,2}, "B"}, {{4,3}, "B"}, {{5,3}, "B"}, {{5,4}, "B"},
            {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"}, {{11,1}, "E"}, {{11,2}, "E"}, {{11,3}, "E"},
            {{10,1}, "D"}, {{10,2}, "D"}, {{10,3}, "D"}, {{9,3}, "D"}, {{9,4}, "D"},
            {{6,3}, "A"}, {{6,4}, "A"}, {{7,4}, "A"}, {{7,5}, "A"}, {{8,3}, "A"}, {{8,4}, "A"},
            {{6,5}, "E"}, {{6,6}, "E"}, {{7,6}, "E"}, {{7,7}, "E"}, {{8,5}, "E"}, {{8,6}, "E"},
            {{6,7}, "C"}, {{6,8}, "C"}, {{7,8}, "C"}, {{7,9}, "C"}, {{8,7}, "C"}, {{8,8}, "C"}
        }
    else
        -- Complex grid for levels 3-5
        prePlacedCells = {
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
    end
    
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
            end
        end
    end
end

-- Simple ammo system helpers
function Grid:getCurrentShooterBall()
    if self.currentShotIndex <= 15 then
        return self.ammo[self.currentShotIndex]
    end
    return nil
end

function Grid:getOnDeckBall()
    if self.currentShotIndex < 15 then
        return self.ammo[self.currentShotIndex + 1]
    end
    return nil
end

function Grid:getShotsRemaining()
    return math.max(0, 15 - self.currentShotIndex + 1)
end

-- Handle level completion: trigger finale for all levels
function Grid:handleLevelCompletion()
    -- Always trigger finale sequence (conversion and battle) for all levels
    self:convertBasicBubblesToCreeps()
end

-- Advance to next level with new ammo and grid
function Grid:advanceToNextLevel()
    self.currentLevel = self.currentLevel + 1
    
    -- Reset ammo for new level
    self.ammo = {}
    for i = 1, 15 do
        self.ammo[i] = math.random(1, 5)
    end
    self.currentShotIndex = 1
    
    -- Clear existing grid (except permanent boundaries)
    for idx, cell in pairs(self.cells) do
        if not cell.permanent then
            cell.occupied = false
            cell.ballType = nil
            cell.tier = nil
        end
    end
    
    -- Clear tier tracking
    self.tierOnePositions = {}
    self.tierTwoPositions = {}
    self.tierThreePositions = {}
    
    -- Clear units
    self.creeps = {}
    self.troops = {}
    self.projectiles = {}
    self.stagingOccupied = {}
    self.rallyPointOccupied = {}
    
    -- Reset systems
    self.finalAttackTriggered = false
    self.finalAttackDelay = nil
    self.finaleTriggered = false
    self.finaleCountdown = nil
    self.troopShotCounter = 0
    self.troopMarchActive = false
    
    -- Setup new starting grid based on new level
    self:setupStartingBalls()
end

-- Check for victory condition or level advancement after all creeps defeated
function Grid:checkForVictory()
    if #self.creeps == 0 and self.finalAttackTriggered then
        if self.currentLevel == 5 then
            -- Final victory on level 5
            self.gameState = "victory"
        else
            -- Advance to next level (levels 1-4)
            self:advanceToNextLevel()
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
    if self.gameState == "gameOver" or self.gameState == "victory" then
        if pd.buttonJustPressed(pd.kButtonA) then
            self:init() -- Restart game
        end
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
           self:getCurrentShooterBall() and not self.isAnimating then
        self:shootBall()
    end
end

-- Fire a ball from shooter position  
function Grid:shootBall()
    local currentBall = self:getCurrentShooterBall()
    if not currentBall then
        return  -- No ammo left
    end
    
    self.ball = {
        x = self.shooterX,
        y = self.shooterY,
        vx = -self.aimCos * BALL_SPEED,
        vy = -self.aimSin * BALL_SPEED,
        ballType = currentBall,
        bounces = 0  -- Track bounce count (max 3)
    }
    
    -- Simple: just advance to next shot
    self.currentShotIndex = self.currentShotIndex + 1
    
    -- Handle creep spawning cycles
    self:handleCreepCycle()
end

-- Main update loop
function Grid:update()
    if self.gameState == "gameOver" then
        self:updateGameOverFlash()
        return
    end
    
    -- Increment global frame counter for knockback cooldown tracking
    self.frameCounter = self.frameCounter + 1
    
    self:updateAnimations()
    self:updateCreeps()
    self:updateTroops()
    self:updateTowerCombat()
    self:updateProjectiles()
    self:updateRainDots()
    self:updateLightningEffects()
    
    -- Handle finale countdown (runs every frame)
    if self.finaleTriggered and self.finaleCountdown then
        self.finaleCountdown = self.finaleCountdown - 1
        if self.finaleCountdown <= 0 then
            self.finaleCountdown = nil
            self:startCreepMarch()
            print("FINALE: Creeps marching to attack!")
        end
    end
    
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
                if distSq <= ((FLYING_BALL_RADIUS - 4) * (FLYING_BALL_RADIUS - 4)) then
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
        local tier1Radius = 27 -- 36/2 + 9 for flying ball radius
        if distSq <= (tier1Radius * tier1Radius) then
            return true
        end
    end
    
    -- Check tier 2 bubbles (collision with center point, 52x52 sprite)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        local dx = self.ball.x - tierTwoData.centerX
        local dy = self.ball.y - tierTwoData.centerY
        local distSq = dx * dx + dy * dy
        local tier2Radius = 35 -- 52/2 + 9 for flying ball radius
        if distSq <= (tier2Radius * tier2Radius) then
            return true
        end
    end
    
    -- Check tier 3 bubbles (collision with center point, 84x84 sprite)
    for idx, tierThreeData in pairs(self.tierThreePositions) do
        local dx = self.ball.x - tierThreeData.centerX
        local dy = self.ball.y - tierThreeData.centerY
        local distSq = dx * dx + dy * dy
        local tier3Radius = 51 -- 84/2 + 9 for flying ball radius
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
        -- Place ball successfully
        self.cells[landingIdx].ballType = self.ball.ballType
        self.cells[landingIdx].occupied = true
        self.cells[landingIdx].tier = "basic"  -- Phase 2: New balls are basic tier
        self.ball = nil
        
        -- Advance to next ball (infinite shots)
        self.shooterBallType = self.onDeckBallType
        self.onDeckBallType = math.random(1, 5)
        
        -- Check for merges
        self:checkForMerges(landingIdx)
        
        -- Check if this was the final ball landing (shot 15) 
        if self.currentShotIndex > 15 then
            self:handleLevelCompletion()
        end
        
        -- Handle troop spawning and shot counting (happens on every shot)
        self:handleTroopShotCounting()
        self:spawnTroopsForShot()
        
    else
        -- Failed placement - trigger game over sequence
        self:startGameOverSequence()
    end
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
                local rallyPos = self:getRandomRallyPoint()
                self:spawnTroop(anim.endX, anim.endY, "tier1", TROOP_SIZE_TIER1, rallyPos)
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier2_magnetism" then
            if progress >= 1.0 then
                -- Complete magnetism - remove both tier 1s and create tier 2
                self:clearTierOne(anim.tierOne1)
                self:clearTierOne(anim.tierOne2)
                self:placeTierTwo(anim.endX, anim.endY, anim.sprite)
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier2_snap" then
            if progress >= 1.0 then
                -- Complete grid snapping - mark all pattern cells as tier 2
                for _, idx in ipairs(anim.pattern) do
                    self.cells[idx].ballType = anim.sprite
                    self.cells[idx].occupied = true
                    self.cells[idx].tier = "tier2"
                end
                
                -- Store at exact grid position
                self.tierTwoPositions[anim.centerIdx] = {
                    centerX = anim.endX,
                    centerY = anim.endY,
                    sprite = anim.sprite,
                    pattern = anim.pattern,
                    ballType = 4,  -- All Tier 2 towers are Lightning towers
                    hitpoints = TOWER_HP,
                    maxHitpoints = TOWER_HP,
                    lastAttackTime = 0,
                    -- Lightning tower specific properties
                    lightningSequenceActive = false,
                    lightningSequenceProgress = 0,
                    lightningBoltsFired = 0,
                    -- Rotation properties for tower targeting
                    currentAngle = 0,
                    targetAngle = 0,
                    currentTarget = nil
                }
                
                -- Spawn troop from newly created tier 2
                local rallyPos = self:getRandomRallyPoint()
                self:spawnTroop(anim.endX, anim.endY, "tier2", TROOP_SIZE_TIER2, rallyPos)
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_magnetism" then
            if progress >= 1.0 then
                -- Complete tier 3 magnetism - remove tier 1 and tier 2, create tier 3
                self:clearTierOne(anim.tierOne)
                self:clearTierTwo(anim.tierTwo)
                self:placeTierThree(anim.endX, anim.endY, anim.sprite)
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_snap" then
            if progress >= 1.0 then
                -- Clear any stomped tier bubbles from tracking tables before placing tier 3
                for _, idx in ipairs(anim.pattern) do
                    -- Remove from tier 1 positions if stomped
                    if self.tierOnePositions[idx] then
                        self.tierOnePositions[idx] = nil
                    end
                    
                    -- Remove from tier 2 positions if stomped (check all patterns)
                    for tierIdx, tierData in pairs(self.tierTwoPositions) do
                        for _, patternIdx in ipairs(tierData.pattern) do
                            if patternIdx == idx then
                                self.tierTwoPositions[tierIdx] = nil
                                break
                            end
                        end
                    end
                end
                
                -- Complete grid snapping - mark all pattern cells as tier 3
                for _, idx in ipairs(anim.pattern) do
                    self.cells[idx].ballType = anim.sprite
                    self.cells[idx].occupied = true
                    self.cells[idx].tier = "tier3"
                end
                
                -- Store at exact grid position
                self.tierThreePositions[anim.centerIdx] = {
                    centerX = anim.endX,
                    centerY = anim.endY,
                    sprite = anim.sprite,
                    pattern = anim.pattern
                }
                
                -- Start flashing animation (3 flashes over 1 second = 60 frames)
                self.animations[#self.animations + 1] = {
                    type = "tier3_flash",
                    centerIdx = anim.centerIdx,
                    centerX = anim.endX,
                    centerY = anim.endY,
                    sprite = anim.sprite,
                    pattern = anim.pattern,
                    frame = 0,
                    flashCount = 0  -- Track number of flashes completed
                }
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_flash" then
            anim.frame = anim.frame + 1
            
            -- Flash every 10 frames (6 times per second)
            if anim.frame % 10 == 0 then
                anim.flashCount = anim.flashCount + 1
            end
            
            -- After 80 frames and 8 flashes (3 visible appearances + final off)
            if anim.frame >= 80 and anim.flashCount >= 8 then
                -- Spawn single tier 3 troop
                local rallyPos = self:getRandomRallyPoint()
                self:spawnTroop(anim.centerX, anim.centerY, "tier3", TROOP_SIZE_TIER3, rallyPos)
                
                -- Despawn the tier 3 bubble - clear from grid and tracking
                for _, idx in ipairs(anim.pattern) do
                    self.cells[idx].occupied = false
                    self.cells[idx].ballType = nil
                    self.cells[idx].tier = "basic"
                end
                self.tierThreePositions[anim.centerIdx] = nil
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        end
    end
    
    self.animations = activeAnimations
    
    if #self.animations == 0 then
        self.isAnimating = false
    end
end

-- ============================================================================
-- TIER PROGRESSION SYSTEMS
-- ============================================================================

-- Phase 2: Create Tier 1 bubble after basic merge
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
        if not cell.permanent and not cell.occupied then
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

-- Place tier 1 bubble in triangle formation
function Grid:placeTierOne(triangle, ballType, centerX, centerY)
    -- Clear any existing bubbles in triangle positions
    for _, idx in ipairs(triangle) do
        self:clearCell(idx)
    end
    
    -- Mark all triangle cells as tier 1
    for _, idx in ipairs(triangle) do
        self.cells[idx].ballType = ballType
        self.cells[idx].occupied = true
        self.cells[idx].tier = "tier1"
    end
    
    -- Use the provided coordinates directly (already rounded from animation)
    local renderIdx = triangle[1]
    self.tierOnePositions[renderIdx] = {
        centerX = centerX,
        centerY = centerY,
        ballType = ballType,
        triangle = triangle,
        hitpoints = TOWER_HP,
        maxHitpoints = TOWER_HP,
        lastAttackTime = 0,
        -- Flame tower tracking data
        currentTarget = nil,
        currentAngle = 0,
        targetAngle = 0
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

-- Convert all basic bubbles to creeps when final ball lands
function Grid:convertBasicBubblesToCreeps()
    local basicBubbles = {}
    
    -- Find all basic bubbles on the grid
    for idx, cell in pairs(self.cells) do
        if cell.occupied and cell.tier == "basic" then
            local pos = self.positions[idx]
            if pos then
                basicBubbles[#basicBubbles + 1] = {
                    idx = idx,
                    x = pos.x,
                    y = pos.y,
                    ballType = cell.ballType
                }
            end
        end
    end
    
    -- Convert each basic bubble to a creep
    for _, bubble in ipairs(basicBubbles) do
        -- Clear the bubble from the grid
        self.cells[bubble.idx].occupied = false
        self.cells[bubble.idx].ballType = nil
        self.cells[bubble.idx].tier = "basic"
        
        -- Find a staging position for this creep (prefer spreading them out)
        local stagingIdx = self:findStagingForConvertedCreep()
        local stagingPos = self.positions[stagingIdx]
        
        if stagingPos then
            -- Create arc path with variance for chaotic movement
            local arcParams = self:calculateArcPath(bubble.x, bubble.y, stagingPos.x, stagingPos.y)
            
            -- Add converted creep with arc movement
            self.creeps[#self.creeps + 1] = {
                x = bubble.x,
                y = bubble.y,
                targetX = stagingPos.x,
                targetY = stagingPos.y,
                animating = true,
                staged = false,
                stagingIdx = stagingIdx,
                tier = "basic",
                size = 3,
                marching = false,
                converted = true,  -- Mark as converted from bubble
                hitpoints = CREEP_HP_BASIC,
                maxHitpoints = CREEP_HP_BASIC,
                lastAttackTime = 0,
                -- Simple collision avoidance
                lastDirection = 0,  -- -1 = up, 1 = down, 0 = none
                -- Arc movement parameters
                arcStartX = bubble.x,
                arcStartY = bubble.y,
                arcEndX = stagingPos.x,
                arcEndY = stagingPos.y,
                arcMidX = arcParams.midX,
                arcMidY = arcParams.midY,
                arcProgress = 0  -- 0 to 1 for arc progression
            }
            
            -- Mark staging position as having creeps
            self.stagingOccupied[stagingIdx] = true
        end
    end
    
    print("FINAL CONVERSION: Converted " .. #basicBubbles .. " basic bubbles to creeps!")
end

-- Find staging position for converted creeps (distribute across all positions)
function Grid:findStagingForConvertedCreep()
    -- Count creeps at each staging position
    local stagingCounts = {}
    for _, idx in ipairs(CREEP_STAGING_POSITIONS) do
        stagingCounts[idx] = 0
    end
    
    -- Count all creeps (including converted ones)
    for _, creep in ipairs(self.creeps) do
        if not creep.marching and stagingCounts[creep.stagingIdx] then
            stagingCounts[creep.stagingIdx] = stagingCounts[creep.stagingIdx] + 1
        end
    end
    
    -- Find position with fewest creeps
    local minCount = math.huge
    local bestPositions = {}
    for idx, count in pairs(stagingCounts) do
        if count < minCount then
            minCount = count
            bestPositions = {idx}
        elseif count == minCount then
            bestPositions[#bestPositions + 1] = idx
        end
    end
    
    -- Return random position from those with minimum count
    return bestPositions[math.random(1, #bestPositions)]
end

-- Calculate arc path parameters for chaotic movement
function Grid:calculateArcPath(startX, startY, endX, endY)
    local midX = (startX + endX) / 2
    local midY = (startY + endY) / 2
    
    -- Add variance to create chaotic arcing
    local variance = 80 + math.random(-30, 30)  -- Arc height with randomness
    local direction = math.random() > 0.5 and 1 or -1  -- Random arc direction
    
    -- Calculate perpendicular offset for arc
    local dx = endX - startX
    local dy = endY - startY
    local dist = math.sqrt(dx*dx + dy*dy)
    
    if dist > 0 then
        -- Normalize and rotate 90 degrees for perpendicular
        local perpX = -dy / dist
        local perpY = dx / dist
        
        -- Apply variance
        midX = midX + perpX * variance * direction
        midY = midY + perpY * variance * direction
    end
    
    return {
        midX = midX,
        midY = midY
    }
end

-- Check if all converted creeps are staged and trigger final attack
function Grid:checkForFinalAttack()
    -- Only check if we have converted creeps and haven't already triggered final attack
    if not self.finalAttackTriggered and self:hasConvertedCreeps() then
        local allConverted = self:areAllConvertedCreepsStaged()
        
        if allConverted then
            self.finalAttackTriggered = true
            self.finalAttackDelay = 30  -- 30-frame delay before final march
            print("FINAL ATTACK: All converted creeps staged! Attack launching in 30 frames...")
        end
    end
    
    -- Handle final attack delay countdown
    if self.finalAttackTriggered and self.finalAttackDelay then
        self.finalAttackDelay = self.finalAttackDelay - 1
        
        if self.finalAttackDelay <= 0 then
            self.finalAttackDelay = nil
            self:startCreepMarch()
            print("FINAL ATTACK: All creeps marching!")
        end
    end
end

-- Check if there are any converted creeps
function Grid:hasConvertedCreeps()
    for _, creep in ipairs(self.creeps) do
        if creep.converted then
            return true
        end
    end
    return false
end

-- Check if all converted creeps have reached their staging positions
function Grid:areAllConvertedCreepsStaged()
    for _, creep in ipairs(self.creeps) do
        if creep.converted and not creep.staged then
            return false
        end
    end
    return true
end

-- Check if there are basic bubbles on the grid that could be converted
function Grid:hasBasicBubblesToConvert()
    for idx, cell in pairs(self.cells) do
        if cell.occupied and cell.tier == "basic" then
            return true
        end
    end
    return false
end

-- Find collision-free staging position near target, respecting rally line boundary
function Grid:findCreepStagingPosition(targetX, targetY, creepSize, exemptCreep)
    local searchRadius = 5
    local maxRadius = 50
    local rallyLineX = CREEP_RALLY_LINE_X  -- Correct x-coordinate of rally dashed line
    
    -- Start at exact target and spiral outward
    for radius = 0, maxRadius, searchRadius do
        local positions = {}
        
        if radius == 0 then
            -- Check exact position first
            positions[1] = {x = targetX, y = targetY}
        else
            -- Generate positions in a circle around target
            local numPositions = math.max(8, radius * 2)  -- More positions for larger radius
            for i = 1, numPositions do
                local angle = (i - 1) * (2 * math.pi / numPositions)
                local x = targetX + radius * math.cos(angle)
                local y = targetY + radius * math.sin(angle)
                
                -- Prefer positions that go backward (away from rally line) rather than forward
                if x >= rallyLineX then  -- Don't cross in front of rally line
                    positions[#positions + 1] = {x = x, y = y}
                end
            end
            
            -- If no positions behind rally line, try positions exactly on the line
            if #positions == 0 then
                for i = 1, numPositions do
                    local angle = (i - 1) * (2 * math.pi / numPositions)
                    local x = targetX + radius * math.cos(angle)
                    local y = targetY + radius * math.sin(angle)
                    
                    if x >= rallyLineX - 5 then  -- Allow slight buffer at rally line
                        positions[#positions + 1] = {x = x, y = y}
                    end
                end
            end
        end
        
        -- Test each position for collisions
        for _, pos in ipairs(positions) do
            if self:isCreepPositionFree(pos.x, pos.y, creepSize, exemptCreep) then
                return pos
            end
        end
    end
    
    -- Fallback: return target position even if it causes collision
    return {x = targetX, y = targetY}
end

-- Check if a position is free of collisions with other creeps
function Grid:isCreepPositionFree(x, y, size, exemptCreep)
    local buffer = 2  -- Minimum spacing between creeps
    
    for _, otherCreep in ipairs(self.creeps) do
        if otherCreep.staged or not otherCreep.animating then
            local dx = x - otherCreep.x
            local dy = y - otherCreep.y
            local dist = math.sqrt(dx*dx + dy*dy)
            local minDist = (size + otherCreep.size) / 2 + buffer
            
            if dist < minDist then
                -- Check if collision can be exempted
                local canPassThrough = false
                if exemptCreep and exemptCreep.collisionExempt then
                    local tierPriority = {basic = 1, tier1 = 2, tier2 = 3}
                    local exemptPriority = tierPriority[exemptCreep.tier] or 1
                    local otherPriority = tierPriority[otherCreep.tier] or 1
                    
                    -- Allow smaller tier to pass through larger tier during spawn movement
                    if exemptPriority < otherPriority then
                        canPassThrough = true  -- Exempt creep can pass through higher tier
                    end
                end
                
                if not canPassThrough then
                    return false  -- Too close to another creep
                end
            end
        end
    end
    
    -- Also check screen boundaries
    if x < 10 or x > 410 or y < 10 or y > 230 then
        return false
    end
    
    return true
end

-- Find queue position for creep - simple collision-based spacing

function Grid:handleCreepCycle()
    local shotNumber = self.currentShotIndex
    
    -- Don't spawn creeps on the final ball launch (shot 15)
    if shotNumber >= 15 then
        -- Simple finale trigger when ammo is exhausted
        local ammoExhausted = (self.currentShotIndex > 15)
        
        if ammoExhausted and not self.finaleTriggered then
            self.finaleTriggered = true
            self.finaleCountdown = 60  -- 2 second delay before marching starts
            print("FINALE: Ammo exhausted! Creeps will march in 2 seconds...")
        end
        return
    end
    
    
    -- Random creep spawning based on shot number and dice roll
    local roll = math.random(1, 100)
    
    -- Limit roll range based on shot number
    if shotNumber == 1 then
        roll = math.min(roll, 30)  -- Cannot roll above 30 on shot 1
    elseif shotNumber == 2 then
        roll = math.min(roll, 60)  -- Cannot roll above 60 on shot 2
    end
    -- Shot 3+: all rolls are valid (1-100)
    
    -- Determine spawning based on roll
    if roll >= 1 and roll <= 10 then
        self:spawnCreeps(1, "basic", 3)
    elseif roll >= 11 and roll <= 20 then
        self:spawnCreeps(2, "basic", 3)
    elseif roll >= 21 and roll <= 30 then
        self:spawnCreeps(3, "basic", 3)
    elseif roll >= 31 and roll <= 40 then
        self:spawnCreeps(1, "tier1", 4)
    elseif roll >= 41 and roll <= 50 then
        self:spawnCreeps(2, "tier1", 4)
    elseif roll >= 51 and roll <= 60 then
        self:spawnCreeps(5, "basic", 3)
    elseif roll >= 61 and roll <= 70 then
        self:spawnCreeps(8, "basic", 3)
    elseif roll >= 71 and roll <= 80 then
        self:spawnCreeps(3, "tier1", 4)
    elseif roll >= 81 and roll <= 90 then
        self:spawnCreeps(1, "tier2", 8)
    elseif roll >= 91 and roll <= 100 then
        self:spawnCreeps(2, "tier2", 8)
    end
end

-- Spawn creeps with tier and size
function Grid:spawnCreeps(count, tier, size)
    local stagingIdx = self:findAvailableStaging(tier)
    if not stagingIdx then 
        return 
    end  -- Should never happen with new logic
    
    local stagingPos = self.positions[stagingIdx]
    self.stagingOccupied[stagingIdx] = true  -- Mark as occupied (multiple creeps can share)
    
    -- Spawn all creeps to the same rally point with random spawn offsets
    -- Keep staging target at least 20px away from dashed line
    local safeTargetX = math.max(stagingPos.x, CREEP_RALLY_LINE_X + PROJECTILE_HIDE_DISTANCE)
    
    -- Get hitpoints based on tier
    local hitpoints = CREEP_HP_BASIC
    if tier == "tier1" then
        hitpoints = CREEP_HP_TIER1
    elseif tier == "tier2" then
        hitpoints = CREEP_HP_TIER2
    end

    for i = 1, count do
        self.creeps[#self.creeps + 1] = {
            x = stagingPos.x + CREEP_SPAWN_OFFSET + math.random(-10, 10),
            y = stagingPos.y + math.random(-10, 10),
            targetX = safeTargetX,
            targetY = stagingPos.y,
            animating = true,
            staged = false,
            stagingIdx = stagingIdx,
            tier = tier or "basic",
            size = size or 3,
            marching = false,
            hitpoints = hitpoints,
            maxHitpoints = hitpoints,
            lastAttackTime = 0,
            stunFrames = 0,  -- Earthquake wave stun counter
            lastKnockbackFrame = 0,  -- Wind knockback cooldown tracker
            -- ENHANCED: Wind pushback animation system
            pushbackActive = false,    -- Is currently being pushed back
            pushbackStartX = 0,        -- Starting position for pushback
            pushbackStartY = 0, 
            pushbackTargetX = 0,       -- Target position for pushback
            pushbackTargetY = 0,
            pushbackProgress = 0,      -- Animation progress (0-1)
            pushbackFrames = 0,        -- Frames elapsed in pushback
            -- Simple collision avoidance
            lastDirection = 0,         -- -1 = up, 1 = down, 0 = none
            -- Collision exemption system
            collisionExempt = true,    -- Can pass through higher tier creeps during spawn movement
            hasReachedRally = false    -- Track when creep reaches rally position
        }
    end
end

-- Find available staging position - prefer empty, or choose position with fewest creeps of same tier
function Grid:findAvailableStaging(tier)
    -- Get tier-specific rally positions
    local rallyPositions = self:getRallyPositionsForTier(tier)
    
    -- First try: find completely empty staging positions for this tier
    local available = {}
    for _, idx in ipairs(rallyPositions) do
        if not self.stagingOccupied[idx] then
            available[#available + 1] = idx
        end
    end
    
    if #available > 0 then
        return available[math.random(1, #available)]
    end
    
    -- Second try: all staging positions occupied, find one with fewest creeps of this tier
    local stagingCounts = {}
    for _, idx in ipairs(rallyPositions) do
        stagingCounts[idx] = 0
    end
    
    -- Count creeps of this tier at each staging position
    for _, creep in ipairs(self.creeps) do
        if creep.tier == tier and not creep.marching and stagingCounts[creep.stagingIdx] then
            stagingCounts[creep.stagingIdx] = stagingCounts[creep.stagingIdx] + 1
        end
    end
    
    -- Find minimum count and positions with that count
    local minCount = math.huge
    local bestPositions = {}
    for idx, count in pairs(stagingCounts) do
        if count < minCount then
            minCount = count
            bestPositions = {idx}
        elseif count == minCount then
            bestPositions[#bestPositions + 1] = idx
        end
    end
    
    -- Choose randomly among tied positions
    if #bestPositions > 0 then
        return bestPositions[math.random(1, #bestPositions)]
    end
    
    -- Fallback: return first position for this tier
    return rallyPositions[1]
end

-- Start marching all creeps with staggered delays to prevent bunching
function Grid:startCreepMarch()
    print("MARCH: " .. #self.creeps .. " creeps starting march with staggered delays")
    for i, creep in ipairs(self.creeps) do
        creep.marching = true
        creep.animating = false
        creep.marchDelay = math.random(0, 60)  -- Random 0-2 second delay before attacking
    end
end

-- ============================================================================
-- CREEP MOVEMENT HELPER FUNCTIONS  
-- ============================================================================


-- Simplified creep movement: wait for delay, then move toward nearest tower and attack
function Grid:updateCreepMovement(creep)
    if not creep.marching then return end
    
    -- Update stun counter - creeps can't move while stunned
    if creep.stunFrames and creep.stunFrames > 0 then
        creep.stunFrames = creep.stunFrames - 1
        return  -- Skip movement while stunned
    end
    
    -- Update wind pushback animation (takes priority over normal movement)
    if creep.pushbackActive then
        creep.pushbackFrames = creep.pushbackFrames + 1
        creep.pushbackProgress = creep.pushbackFrames / WIND_PUSHBACK_DURATION
        
        if creep.pushbackProgress >= 1.0 then
            -- Animation complete - snap to final position
            creep.x = creep.pushbackTargetX
            creep.y = creep.pushbackTargetY
            creep.pushbackActive = false
        else
            -- Smooth interpolation with easing (ease-out for natural feel)
            local t = creep.pushbackProgress
            local easedT = 1 - (1 - t) * (1 - t)  -- Quadratic ease-out
            
            creep.x = creep.pushbackStartX + (creep.pushbackTargetX - creep.pushbackStartX) * easedT
            creep.y = creep.pushbackStartY + (creep.pushbackTargetY - creep.pushbackStartY) * easedT
        end
        return  -- Skip normal movement while being pushed back
    end
    
    -- Wait for march delay before starting to attack
    if creep.marchDelay > 0 then
        creep.marchDelay = creep.marchDelay - 1
        if creep.marchDelay == 0 then
            print("ATTACK: " .. creep.tier .. " creep delay expired, engaging towers at (" .. math.floor(creep.x) .. "," .. math.floor(creep.y) .. ")")
        end
        return  -- Wait at staging position
    end
    
    -- Direct tower targeting: move toward nearest tower and attack
    self:updateStandAndFightMovement(creep)
    self:updateCreepSimpleCollision(creep)
    self:updateCreepAttacks(creep)
end

-- ENHANCED: "Stand and Fight" movement - creeps target towers using zone-based system
-- Creeps must destroy all towers before they can exit the battlefield
function Grid:updateStandAndFightMovement(creep)
    
    -- ZONE-BASED TARGETING: Use zone priority system instead of closest tower
    local target = creep.standAndFightTarget
    if not target or target.hitpoints <= 0 then
        target = self:findZoneBasedTarget(creep)
        creep.standAndFightTarget = target
        if target then
            local zone = self:getTowerZone(target.centerX)
            print("TARGET: " .. creep.tier .. " creep locked onto tower in zone " .. zone .. " at (" .. math.floor(target.centerX) .. "," .. math.floor(target.centerY) .. ")")
        end
    end
    
    if target then
        -- Move toward the locked target tower
        local dx = target.centerX - creep.x
        local dy = target.centerY - creep.y
        local dist = math.sqrt(dx*dx + dy*dy)
        
        -- Only move if not in attack range (varies by creep type)
        local attackRange = self:getCreepAttackRange(creep)
        
        if dist > attackRange then
            -- Calculate movement speed (basic creeps move twice as fast)
            local moveSpeed = CREEP_MARCH_SPEED
            
            -- BASIC CREEP SPEED: Basic creeps move twice as fast as other tiers
            if creep.tier == "basic" then
                moveSpeed = CREEP_MARCH_SPEED * 2  -- Double speed for basic creeps
                
                -- CHARGE SYSTEM: Additional speed boost when within 20px (outer edge collision)
                local distToEdge = dist - TOWER_SPRITE_RADIUS
                if distToEdge <= CREEP_CHARGE_RANGE then
                    -- Activate charge mode! (even faster than base double speed)
                    moveSpeed = CREEP_CHARGE_SPEED
                    if not creep.charging then
                        creep.charging = true
                        print("CHARGE: Basic creep activating charge mode!")
                    end
                else
                    creep.charging = false
                end
            end
            
            -- Normalize movement direction
            local moveX = (dx / dist) * moveSpeed
            local moveY = (dy / dist) * moveSpeed
            
            -- Check for tower collisions before applying movement
            local newX = creep.x + moveX
            local newY = creep.y + moveY
            local collision, blockingTower = self:checkTowerCollision(creep, newX, newY)
            
            if collision == "clear" then
                -- Safe to move normally
                creep.x = newX
                creep.y = newY
            elseif collision == "hard_collision" and blockingTower then
                -- Blocked by tower - find path around it
                local avoidanceMovement = self:findGuaranteedMovement(creep, blockingTower)
                if avoidanceMovement then
                    creep.x = creep.x + avoidanceMovement[1]
                    creep.y = creep.y + avoidanceMovement[2]
                end
            else
                -- Apply movement anyway for other collision types
                creep.x = newX
                creep.y = newY
            end
        else
            -- In attack range - add debug output
            if math.random(1, 60) == 1 then  -- Occasional debug to avoid spam
                print("RANGE: " .. creep.tier .. " creep in attack range (dist=" .. math.floor(dist) .. ", range=" .. attackRange .. ")")
            end
        end
        -- If in range, stop and fight (attack system handles the combat)
    else
        -- No towers left - exit left side of screen
        creep.x = creep.x - CREEP_MARCH_SPEED
        
        -- Remove creep when it exits screen
        if creep.x < -20 then
            -- Find and remove this creep
            for i = #self.creeps, 1, -1 do
                if self.creeps[i] == creep then
                    table.remove(self.creeps, i)
                    break
                end
            end
        end
    end
end

-- ENHANCED: Get attack range for different creep types (ensures creeps get within tower range)
function Grid:getCreepAttackRange(creep)
    if creep.tier == "tier1" then
        -- Tier 1 ranged: Stop 10px from tower edge (tower radius + 10px)
        -- This keeps them within rain range (40px) while maintaining tactical distance
        return TOWER_SPRITE_RADIUS + 10  -- 18 + 10 = 28px (within rain range)
    elseif creep.tier == "tier2" then
        -- Tier 2 ranged: Stop 25px from tower edge (tower radius + 25px) 
        -- More cautious positioning while still within rain range
        return TOWER_SPRITE_RADIUS + 25  -- 18 + 25 = 43px (just within rain range)
    else
        -- Basic creeps: Must get very close for suicide attacks (tower radius + small buffer)
        return TOWER_SPRITE_RADIUS + 5  -- 18 + 5 = 23px (much closer than 30px)
    end
end

-- Get which zone a tower is in (1 = closest to creep rally, 2 = middle, 3 = furthest)
function Grid:getTowerZone(towerX)
    if towerX >= ZONE_1_MIN_X then
        return 1  -- Zone 1: closest to creep rally (rightmost)
    elseif towerX >= ZONE_2_MIN_X then
        return 2  -- Zone 2: middle zone
    else
        return 3  -- Zone 3: furthest from creep rally (leftmost)
    end
end

-- Find target tower using zone-based priority system
function Grid:findZoneBasedTarget(creep)
    -- Group towers by zone
    local zoneTargets = {[1] = {}, [2] = {}, [3] = {}}
    
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then  -- Only consider living towers
            local zone = self:getTowerZone(tower.centerX)
            table.insert(zoneTargets[zone], tower)
        end
    end
    
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then  -- Only consider living towers
            local zone = self:getTowerZone(tower.centerX)
            table.insert(zoneTargets[zone], tower)
        end
    end
    
    -- If creep has current target in same zone, continue targeting that zone
    local currentZone = nil
    if creep.standAndFightTarget and creep.standAndFightTarget.hitpoints > 0 then
        currentZone = self:getTowerZone(creep.standAndFightTarget.centerX)
        if #zoneTargets[currentZone] > 0 then
            -- Find closest tower in current zone
            return self:findClosestTowerInZone(creep, zoneTargets[currentZone])
        end
    end
    
    -- Priority: Zone 1 (front) -> Zone 2 (middle) -> Zone 3 (back)
    for zone = 1, 3 do
        if #zoneTargets[zone] > 0 then
            if not creep.hasSelectedZoneTarget then
                -- First time selecting in this zone - choose random tower
                local randomIndex = math.random(1, #zoneTargets[zone])
                creep.hasSelectedZoneTarget = true
                return zoneTargets[zone][randomIndex]
            else
                -- Find closest tower in this zone
                return self:findClosestTowerInZone(creep, zoneTargets[zone])
            end
        end
    end
    
    return nil  -- No towers left
end

-- Find closest tower within a specific zone
function Grid:findClosestTowerInZone(creep, zoneTowers)
    local closestTower = nil
    local closestDist = math.huge
    
    for _, tower in ipairs(zoneTowers) do
        local dx = tower.centerX - creep.x
        local dy = tower.centerY - creep.y
        local dist = math.sqrt(dx*dx + dy*dy)
        
        if dist < closestDist then
            closestTower = tower
            closestDist = dist
        end
    end
    
    return closestTower
end

-- Legacy function for compatibility (redirects to zone-based system)
function Grid:findClosestLivingTower(creepX, creepY)
    -- Create temporary creep object for zone targeting
    local tempCreep = {x = creepX, y = creepY}
    return self:findZoneBasedTarget(tempCreep)
end

-- Get rally positions for a specific tier
function Grid:getRallyPositionsForTier(tier)
    if tier == "tier1" then
        return TIER1_RALLY_POSITIONS
    elseif tier == "tier2" then
        return TIER2_RALLY_POSITIONS
    else
        return BASIC_RALLY_POSITIONS  -- Default to basic positions
    end
end


-- Main creep update function - coordinates all creep behavior
-- Performance: Processes all creeps each frame with optimized sub-functions
function Grid:updateCreeps()
    -- Update all individual creep movements and behaviors
    for i = #self.creeps, 1, -1 do
        local creep = self.creeps[i]
        
        -- Remove dead creeps (suicide attacks, damage from towers)
        if creep.hitpoints <= 0 or creep.dead then
            self:checkStagingAvailability(creep.stagingIdx)
            table.remove(self.creeps, i)
            self:checkForVictory()
            goto continue
        end
        
        if creep.marching then
            -- Handle marching creep movement and combat
            self:updateCreepMovement(creep)
            
            -- ENHANCED: Only remove creeps that exit left AFTER all towers are destroyed
            if creep.x < -30 then  -- 30px buffer to prevent visual pop
                -- Check if any towers remain - only allow exit if none remain
                local towersRemain = self:findClosestLivingTower(0, 0) ~= nil
                if not towersRemain then
                    -- No towers left - allow creep to exit (victory for creeps)
                    self:checkStagingAvailability(creep.stagingIdx)
                    table.remove(self.creeps, i)
                    self:checkForVictory()  -- Check for victory after removing creep
                else
                    -- Towers still exist - creep shouldn't be leaving! Move them back to fight
                    creep.x = 0  -- Reset position to edge of screen to continue fighting
                end
            end
        elseif creep.animating then
            -- Handle creep spawn and conversion animations
            self:updateCreepAnimation(creep)
        end
        
        ::continue::
    end
end

-- Handle creep spawn and conversion animations
-- Manages both arc movement for converted creeps and linear spawn movement
-- @param creep: Creep object with animating=true and animation properties
function Grid:updateCreepAnimation(creep)
    -- Update stun counter - creeps can't move while stunned (even during animation)
    if creep.stunFrames and creep.stunFrames > 0 then
        creep.stunFrames = creep.stunFrames - 1
        return  -- Skip movement while stunned
    end
    
    if creep.converted and creep.arcProgress ~= nil then
        -- Arc movement for converted creeps (twice as fast)
        creep.arcProgress = creep.arcProgress + (CREEP_MOVE_SPEED * 2 / 200)  -- Double speed for converted creeps
        
        if creep.arcProgress >= 1.0 then
            -- Find collision-free position near target
            local finalPos = self:findCreepStagingPosition(creep.targetX, creep.targetY, creep.size, creep)
            creep.x = finalPos.x
            creep.y = finalPos.y
            creep.animating = false
            creep.staged = true
            creep.arcProgress = nil  -- Clean up arc data
            -- Remove collision exemption when reaching rally position
            creep.collisionExempt = false
            creep.hasReachedRally = true
        else
            -- Calculate position along quadratic bezier curve
            local t = creep.arcProgress
            local oneMinusT = 1 - t
            
            -- Quadratic bezier: P(t) = (1-t)²P₀ + 2(1-t)tP₁ + t²P₂
            creep.x = oneMinusT * oneMinusT * creep.arcStartX + 
                     2 * oneMinusT * t * creep.arcMidX + 
                     t * t * creep.arcEndX
                     
            creep.y = oneMinusT * oneMinusT * creep.arcStartY + 
                     2 * oneMinusT * t * creep.arcMidY + 
                     t * t * creep.arcEndY
        end
    else
        -- Normal linear movement for regular creeps
        local dx = creep.targetX - creep.x
        local dy = creep.targetY - creep.y
        local dist = math.sqrt(dx*dx + dy*dy)
        
        -- Normal spawn movement speed for all creep tiers
        local spawnMoveSpeed = CREEP_MOVE_SPEED
        
        if dist <= spawnMoveSpeed then
            -- Find collision-free position near target
            local finalPos = self:findCreepStagingPosition(creep.targetX, creep.targetY, creep.size, creep)
            creep.x = finalPos.x
            creep.y = finalPos.y
            creep.animating = false
            creep.staged = true
            -- Remove collision exemption when reaching rally position
            creep.collisionExempt = false
            creep.hasReachedRally = true
        else
            -- Move toward target with tower collision checking
            local moveX = (dx/dist) * spawnMoveSpeed
            local moveY = (dy/dist) * spawnMoveSpeed
            local newX = creep.x + moveX
            local newY = creep.y + moveY
            
            -- Check for tower collisions during spawn movement
            local collision, blockingTower = self:checkTowerCollision(creep, newX, newY)
            
            if collision == "clear" then
                -- Safe to move normally
                creep.x = newX
                creep.y = newY
            elseif collision == "hard_collision" and blockingTower then
                -- Blocked by tower - try to navigate around it
                local avoidanceMovement = self:findGuaranteedMovement(creep, blockingTower)
                if avoidanceMovement then
                    creep.x = creep.x + avoidanceMovement[1]
                    creep.y = creep.y + avoidanceMovement[2]
                end
            else
                -- Apply movement anyway for other collision types
                creep.x = newX
                creep.y = newY
            end
        end
    end
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

-- Simple two-barrier collision detection for towers
function Grid:checkTowerCollision(creep, testX, testY)
    -- First check screen boundaries - simple and permissive
    if testX < -10 or testX > 430 or testY < 0 or testY > SCREEN_HEIGHT then
        return "hard_collision", nil  -- Screen edge
    end
    
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then  -- Only check living towers
            local dx = tower.centerX - testX
            local dy = tower.centerY - testY
            local dist = math.sqrt(dx*dx + dy*dy)
            local towerRadius = TOWER_SPRITE_RADIUS
            local creepRadius = creep.size / 2
            
            -- Check barriers
            if dist <= towerRadius + creepRadius + 2 then
                return "hard_collision", tower  -- 2px hard barrier
            elseif dist <= towerRadius + creepRadius + 10 then
                return "wake_up", tower  -- 10px wake-up barrier
            end
        end
    end
    
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then  -- Only check living towers
            local dx = tower.centerX - testX
            local dy = tower.centerY - testY
            local dist = math.sqrt(dx*dx + dy*dy)
            local towerRadius = TOWER_SPRITE_RADIUS + 8  -- Larger footprint for Tier 2
            local creepRadius = creep.size / 2
            
            -- Check barriers
            if dist <= towerRadius + creepRadius + 2 then
                return "hard_collision", tower  -- 2px hard barrier
            elseif dist <= towerRadius + creepRadius + 10 then
                return "wake_up", tower  -- 10px wake-up barrier
            end
        end
    end
    return "clear", nil
end

-- Tower-aware collision avoidance - respects stand and fight targeting
function Grid:updateCreepSimpleCollision(creep)
    if not creep.marching then return end
    
    -- REMOVED: Legacy "move left toward screen edge" behavior
    -- NEW: Only handle collision avoidance, don't override tower targeting movement
    
    -- Simple boundary check - keep creeps on screen
    creep.x = math.max(-30, math.min(450, creep.x))
    creep.y = math.max(0, math.min(240, creep.y))
    
    -- Light collision avoidance with other creeps (optional, minimal)
    -- This preserves the stand-and-fight movement set by updateStandAndFightMovement
end

-- Find guaranteed movement around obstacles - NEVER returns original position
function Grid:findGuaranteedMovement(creep, blockingTower)
    -- Movement options in order of preference
    local movements = {
        {-CREEP_MOVE_SPEED, 0},                    -- Left (preferred)
        {-CREEP_MOVE_SPEED, -CREEP_MOVE_SPEED},    -- Left-up diagonal
        {-CREEP_MOVE_SPEED, CREEP_MOVE_SPEED},     -- Left-down diagonal
        {0, -CREEP_MOVE_SPEED},                    -- Pure up
        {0, CREEP_MOVE_SPEED},                     -- Pure down
        {-CREEP_MOVE_SPEED * 0.5, -CREEP_MOVE_SPEED}, -- Slower left-up
        {-CREEP_MOVE_SPEED * 0.5, CREEP_MOVE_SPEED},  -- Slower left-down
        {CREEP_MOVE_SPEED * 0.5, -CREEP_MOVE_SPEED},  -- Emergency right-up
        {CREEP_MOVE_SPEED * 0.5, CREEP_MOVE_SPEED},   -- Emergency right-down
        {0, -CREEP_MOVE_SPEED * 2},                -- Double up
        {0, CREEP_MOVE_SPEED * 2}                  -- Double down
    }
    
    -- Bias toward previous direction to prevent jittering
    if creep.lastDirection == -1 then
        -- Prefer upward movements - reorder array
        movements = {
            {-CREEP_MOVE_SPEED, -CREEP_MOVE_SPEED},    -- Left-up
            {0, -CREEP_MOVE_SPEED},                    -- Pure up
            {-CREEP_MOVE_SPEED, 0},                    -- Left
            {-CREEP_MOVE_SPEED * 0.5, -CREEP_MOVE_SPEED}, -- Slower left-up
            {-CREEP_MOVE_SPEED, CREEP_MOVE_SPEED},     -- Left-down
            {0, CREEP_MOVE_SPEED},                     -- Pure down
            {-CREEP_MOVE_SPEED * 0.5, CREEP_MOVE_SPEED}, -- Slower left-down
            {0, -CREEP_MOVE_SPEED * 2},                -- Double up
            {CREEP_MOVE_SPEED * 0.5, -CREEP_MOVE_SPEED}, -- Emergency right-up
            {CREEP_MOVE_SPEED * 0.5, CREEP_MOVE_SPEED},  -- Emergency right-down
            {0, CREEP_MOVE_SPEED * 2}                  -- Double down
        }
    elseif creep.lastDirection == 1 then
        -- Prefer downward movements
        movements = {
            {-CREEP_MOVE_SPEED, CREEP_MOVE_SPEED},     -- Left-down
            {0, CREEP_MOVE_SPEED},                     -- Pure down
            {-CREEP_MOVE_SPEED, 0},                    -- Left
            {-CREEP_MOVE_SPEED * 0.5, CREEP_MOVE_SPEED}, -- Slower left-down
            {-CREEP_MOVE_SPEED, -CREEP_MOVE_SPEED},    -- Left-up
            {0, -CREEP_MOVE_SPEED},                    -- Pure up
            {-CREEP_MOVE_SPEED * 0.5, -CREEP_MOVE_SPEED}, -- Slower left-up
            {0, CREEP_MOVE_SPEED * 2},                 -- Double down
            {CREEP_MOVE_SPEED * 0.5, CREEP_MOVE_SPEED}, -- Emergency right-down
            {CREEP_MOVE_SPEED * 0.5, -CREEP_MOVE_SPEED}, -- Emergency right-up
            {0, -CREEP_MOVE_SPEED * 2}                 -- Double up
        }
    end
    
    -- Try each movement until we find one that works
    for _, movement in ipairs(movements) do
        local testX = creep.x + movement[1]
        local testY = creep.y + movement[2]
        
        -- Use relaxed collision checking for guaranteed movement
        local collision = self:checkTowerCollisionRelaxed(creep, testX, testY)
        
        if collision == "clear" then
            -- Update direction memory
            if movement[2] < 0 then
                creep.lastDirection = -1  -- Moving up
            elseif movement[2] > 0 then
                creep.lastDirection = 1   -- Moving down
            else
                creep.lastDirection = 0   -- No vertical movement
            end
            
            return {movement[1], movement[2]}
        end
    end
    
    -- Absolute fallback: move in any direction away from current position
    return {-CREEP_MOVE_SPEED * 0.5, creep.lastDirection * CREEP_MOVE_SPEED}
end

-- Relaxed collision checking for guaranteed movement
function Grid:checkTowerCollisionRelaxed(creep, testX, testY)
    -- Very permissive screen boundaries for guaranteed movement
    if testX < -50 or testX > 470 or testY < -10 or testY > 250 then
        return "hard_collision"  -- Only block at extreme edges
    end
    
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then  -- Only check living towers
            local dx = tower.centerX - testX
            local dy = tower.centerY - testY
            local dist = math.sqrt(dx*dx + dy*dy)
            local towerRadius = TOWER_SPRITE_RADIUS
            local creepRadius = creep.size / 2
            
            -- Only block at 1px hard barrier (no wake-up zone in relaxed mode)
            if dist <= towerRadius + creepRadius + 1 then
                return "hard_collision"
            end
        end
    end
    
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then  -- Only check living towers
            local dx = tower.centerX - testX
            local dy = tower.centerY - testY
            local dist = math.sqrt(dx*dx + dy*dy)
            local towerRadius = TOWER_SPRITE_RADIUS + 8  -- Larger footprint for Tier 2
            local creepRadius = creep.size / 2
            
            -- Only block at 1px hard barrier (no wake-up zone in relaxed mode)
            if dist <= towerRadius + creepRadius + 1 then
                return "hard_collision"
            end
        end
    end
    return "clear"
end

-- Prevent creeps from overlapping
-- Old creep collision function removed - now handled by resolveAllUnitCollisions()

-- ============================================================================
-- RENDERING SYSTEMS
-- ============================================================================

-- Draw the complete game state
function Grid:draw()
    self:drawGrid()
    self:drawBoundaries()
    self:drawBalls()
    self:drawRainDots()
    self:drawCreeps()
    self:drawTroops()
    self:drawProjectiles()
    self:drawLightningEffects()
    self:drawAnimations()
    self:drawUI()
    if self.gameState == "gameOver" then
        self:drawGameOverScreen()
    elseif self.gameState == "victory" then
        self:drawVictoryScreen()
    end
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
    drawDashedLine(0, BOTTOM_BOUNDARY + 10, SCREEN_WIDTH, BOTTOM_BOUNDARY + 10)
    
    -- Right boundary (rally dashed line) - only show in debug mode
    if self.showDebug then
        local rightX = self.positions[20 + 16].x + 10
        drawDashedLine(rightX, 0, rightX, BOTTOM_BOUNDARY + 10)
    end
    
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
        
        -- Draw HP bar above tower
        self:drawTowerHPBar(tierOneData)
    end
    
    -- Tier 2 bubbles (render at stored center positions)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        self.bubbleSprites.tier2[tierTwoData.sprite]:draw(
            tierTwoData.centerX - 26, tierTwoData.centerY - 26)
        
        -- Draw HP bar above tower
        self:drawTowerHPBar(tierTwoData)
    end
    
    -- Tier 3 bubbles (render at stored center positions, skip if currently flashing)
    for idx, tierThreeData in pairs(self.tierThreePositions) do
        -- Check if this tier 3 bubble is currently flashing
        local isFlashing = false
        for _, anim in ipairs(self.animations) do
            if anim.type == "tier3_flash" and anim.centerIdx == idx then
                isFlashing = true
                break
            end
        end
        
        -- Only draw if not flashing (flashing is handled in drawAnimations)
        if not isFlashing then
            self.bubbleSprites.tier3[tierThreeData.sprite]:draw(
                tierThreeData.centerX - 42, tierThreeData.centerY - 42)
        end
    end
    
    -- Shooter ball (with flashing for game over)
    local currentShooterBall = self:getCurrentShooterBall()
    if not self.ball and currentShooterBall then
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
            self.bubbleSprites.basic[currentShooterBall]:draw(self.shooterX - 10, self.shooterY - 10)
        end
    end
    
    -- Flying ball
    if self.ball then
        self.bubbleSprites.basic[self.ball.ballType]:draw(self.ball.x - 10, self.ball.y - 10)
    end
end

-- Draw all rain dots (towers will render over them)
function Grid:drawRainDots()
    for _, dot in ipairs(self.rainDots) do
        -- Draw all rain dots as 1px black dots (towers render over them)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(dot.x, dot.y, 1)
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
    end
end
-- ============================================================================
-- ALLIED TROOP SYSTEMS  
-- ============================================================================

-- Get a random rally point position
function Grid:getRandomRallyPoint()
    local rallyIdx = TROOP_RALLY_POINTS[math.random(#TROOP_RALLY_POINTS)]
    return self.positions[rallyIdx]
end

-- Spawn troops from all tier bubbles after shot landing
function Grid:spawnTroopsFromBubbles()
    -- Only spawn from Tier 3 bubbles (Tier 1 and Tier 2 no longer spawn troops)
    for idx, tierData in pairs(self.tierThreePositions) do
        local rallyPos = self:getRandomRallyPoint()
        self:spawnTroop(tierData.centerX, tierData.centerY, "tier3", TROOP_SIZE_TIER3, rallyPos)
    end
end
-- Spawn basic troops from 1/3 of basic bubbles (shots 2, 6, 10, etc.)
function Grid:spawnBasicTroops()
    local basicBubbles = {}
    for idx, cell in pairs(self.cells) do
        if cell.occupied and cell.tier == "basic" then
            basicBubbles[#basicBubbles + 1] = idx
        end
    end
    
    -- Spawn from 1/3 of basic bubbles
    local spawnCount = math.max(1, math.floor(#basicBubbles / 3))
    for i = 1, spawnCount do
        local idx = basicBubbles[math.random(#basicBubbles)]
        local pos = self.positions[idx]
        if pos then
            local rallyPos = self:getRandomRallyPoint()
            self:spawnTroop(pos.x, pos.y, "basic", TROOP_SIZE_BASIC, rallyPos)
        end
    end
end
-- Spawn individual troop at specified location
function Grid:spawnTroop(spawnX, spawnY, tier, size, rallyPos)
    if not rallyPos then return end
    
    -- Check if we're in a march state (Turn 4 or any troops marching)
    local shouldMarch = self:shouldNewTroopsMarch()
    
    self.troops[#self.troops + 1] = {
        x = spawnX,
        y = spawnY,
        targetX = rallyPos.x,
        targetY = rallyPos.y,
        tier = tier,
        size = size,
        marching = shouldMarch,
        rallied = false,
        rallyPoint = rallyPos  -- Store assigned rally point
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
        
        if troop.marching then
            -- March right until offscreen
            troop.x = troop.x + TROOP_MARCH_SPEED
            
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
            -- Find target: use troop's assigned rally point  
            local clusterCenter = self:findTroopClusterCenter(troop)
            local targetX = clusterCenter.x
            local targetY = clusterCenter.y
            
            -- Move toward cluster center
            local dx = targetX - troop.x
            local dy = targetY - troop.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= TROOP_MOVE_SPEED * 4 then  -- Even larger threshold for looser rally clusters
                -- Reached cluster area, join and trigger shuffle
                troop.rallied = true
                self:shuffleTroops(troop)
            else
                -- Move toward cluster center, but clamp to valid area
                local newX = troop.x + (dx/dist) * TROOP_MOVE_SPEED
                local newY = troop.y + (dy/dist) * TROOP_MOVE_SPEED
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
            rallied = false,  -- Creeps don't rally
            tier = creep.tier,
            collisionExempt = creep.collisionExempt or false
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
                -- Check collision exemption rules
                local shouldSkipCollision = false
                
                if u1.type == "creep" and u2.type == "creep" then
                    -- Collision exemption system for creeps
                    local tierPriority = {basic = 1, tier1 = 2, tier2 = 3}
                    local u1Priority = tierPriority[u1.tier] or 1
                    local u2Priority = tierPriority[u2.tier] or 1
                    
                    -- Lower tier creeps can pass through higher tier creeps when exempted
                    if u1.collisionExempt and u1Priority < u2Priority then
                        shouldSkipCollision = true  -- u1 (lower tier) can pass through u2 (higher tier)
                    elseif u2.collisionExempt and u2Priority < u1Priority then
                        shouldSkipCollision = true  -- u2 (lower tier) can pass through u1 (higher tier)
                    end
                end
                
                if not shouldSkipCollision then
                    -- Calculate push force
                    local pushDist = (minDist - dist) / 2
                    local pushX = (dx/dist) * pushDist
                    local pushY = (dy/dist) * pushDist
                    
                    -- Special case: if one unit is collision exempt, only push the non-exempt unit
                    if u1.type == "creep" and u1.collisionExempt and u2.type == "creep" and not u2.collisionExempt then
                        -- Only push u2 (non-exempt)
                        u2.unit.x = u2.unit.x + pushX * 2
                        u2.unit.y = u2.unit.y + pushY * 2
                        u2.x = u2.unit.x
                        u2.y = u2.unit.y
                    elseif u2.type == "creep" and u2.collisionExempt and u1.type == "creep" and not u1.collisionExempt then
                        -- Only push u1 (non-exempt)
                        u1.unit.x = u1.unit.x - pushX * 2
                        u1.unit.y = u1.unit.y - pushY * 2
                        u1.x = u1.unit.x
                        u1.y = u1.unit.y
                    else
                        -- Normal collision: push both units
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
    end
end

-- ============================================================================
-- TOWER COMBAT SYSTEM
-- ============================================================================

-- Update tower combat systems (only during creep march phase)
function Grid:updateTowerCombat()
    
    -- Update attack cooldowns and process attacks for all Tier 1 towers
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then  -- Only attack if tower is alive
            -- Update attack cooldown
            tower.lastAttackTime = tower.lastAttackTime + 1
            
            -- Check if tower can attack (different cooldowns per tower type)
            local towerConfig = TOWER_CONFIGS[tower.ballType]
            local cooldown = towerConfig and towerConfig.cooldown or TOWER_ATTACK_COOLDOWN
            
            -- Special case handling for towers with unique cooldown systems
            local shouldFire = false
            if tower.ballType == 4 then  -- Lightning tower - variable cooldown
                if tower.lightningSequenceActive then
                    shouldFire = true  -- Always fire during sequence
                else
                    -- Use variable cooldown if set, otherwise use base cooldown
                    local effectiveCooldown = tower.variableCooldown or cooldown
                    if tower.lastAttackTime >= effectiveCooldown then
                        shouldFire = true  -- Start new sequence after variable cooldown
                        tower.lastAttackTime = 0  -- Reset cooldown
                        tower.variableCooldown = nil  -- Clear variable cooldown for next cycle
                    end
                end
            elseif tower.ballType == 5 then  -- Wind tower
                if tower.burstActive then
                    shouldFire = true  -- Always fire during burst
                elseif tower.lastAttackTime >= cooldown then
                    shouldFire = true  -- Start new burst after cooldown
                    tower.lastAttackTime = 0  -- Reset cooldown
                end
            else
                -- Standard tower firing
                if tower.lastAttackTime >= cooldown then
                    shouldFire = true
                    tower.lastAttackTime = 0  -- Reset cooldown
                end
            end
            
            if shouldFire then
                self:processTowerAttack(tower)
            end
        end
    end
    
    -- Update attack cooldowns and process attacks for all Tier 2 towers (all lightning)
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then  -- Only attack if tower is alive
            -- Update attack cooldown
            tower.lastAttackTime = tower.lastAttackTime + 1
            
            -- All Tier 2 towers are Lightning towers (ballType 4)
            local cooldown = LIGHTNING_TOWER_COOLDOWN
            
            -- Lightning tower with variable cooldown system
            local shouldFire = false
            if tower.lightningSequenceActive then
                shouldFire = true  -- Always fire during sequence
            else
                -- Use variable cooldown if set, otherwise use base cooldown
                local effectiveCooldown = tower.variableCooldown or cooldown
                if tower.lastAttackTime >= effectiveCooldown then
                    shouldFire = true  -- Start new sequence after variable cooldown
                    tower.lastAttackTime = 0  -- Reset cooldown
                    tower.variableCooldown = nil  -- Clear variable cooldown for next cycle
                end
            end
            
            if shouldFire then
                self:lightningCreateProjectiles(tower)  -- Use lightning attack system
            end
        end
    end
end

-- Check if creeps are currently marching (combat phase active)
function Grid:isCreepMarchActive()
    for _, creep in ipairs(self.creeps) do
        if creep.marching then
            return true
        end
    end
    return false
end

-- ============================================================================
-- SHARED TOWER BEHAVIOR HELPER FUNCTIONS
-- ============================================================================

-- Calculate distance between tower and target
-- @param tower: Tower object with centerX, centerY properties
-- @param target: Target object with x, y properties  
-- @return distance: Distance between tower and target
-- @return dx, dy: X and Y components of distance vector
function Grid:calculateTargetDistance(tower, target)
    local dx = target.x - tower.centerX
    local dy = target.y - tower.centerY
    return math.sqrt(dx*dx + dy*dy), dx, dy
end

-- Update tower rotation toward target angle at specified speed
-- Handles angle normalization and smooth rotation with speed limiting
-- @param tower: Tower object with currentAngle, targetAngle properties
-- @param targetAngle: Desired angle in radians (optional if tower.targetAngle set)
-- @param rotationSpeed: Maximum rotation per frame in radians
function Grid:updateTowerRotation(tower, targetAngle, rotationSpeed)
    -- Calculate target angle if not provided
    if not tower.targetAngle then
        tower.targetAngle = targetAngle
    end
    
    -- Normalize angle difference to [-π, π] 
    local angleDiff = tower.targetAngle - tower.currentAngle
    while angleDiff > math.pi do angleDiff = angleDiff - 2*math.pi end
    while angleDiff < -math.pi do angleDiff = angleDiff + 2*math.pi end
    
    -- Rotate at fixed speed toward target
    if math.abs(angleDiff) > rotationSpeed then
        tower.currentAngle = tower.currentAngle + math.sign(angleDiff) * rotationSpeed
    else
        tower.currentAngle = tower.targetAngle  -- Snap when close enough
    end
end

-- Check if target is within firing range (250% of projectile range)
-- Towers fire when targets are within 2.5x their projectile range
-- @param distToTarget: Distance to target in pixels
-- @param projectileRange: Base range of tower's projectiles
-- @return boolean: True if target is within firing range
function Grid:isTargetInFiringRange(distToTarget, projectileRange)
    local maxFireRange = projectileRange * PROJECTILE_FIRE_RANGE_MULTIPLIER
    return distToTarget <= maxFireRange
end

-- Generate jagged lightning bolt path from tower to target
-- Creates 2-3 line segments with random jitter to simulate forked lightning
-- Path is limited to LIGHTNING_PROJECTILE_RANGE regardless of target distance
-- @param startX, startY: Tower center position
-- @param targetX, targetY: Target position
-- @return pathPoints: Array of {x, y} points defining the lightning path
function Grid:generateLightningPath(startX, startY, targetX, targetY)
    local pathPoints = {{x = startX, y = startY}}
    
    -- Determine number of segments (2-3 randomly)
    local numSegments = math.random(LIGHTNING_SEGMENTS_MIN, LIGHTNING_SEGMENTS_MAX)
    
    -- Calculate direction to target
    local dirX = targetX - startX
    local dirY = targetY - startY
    local targetDistance = math.sqrt(dirX * dirX + dirY * dirY)
    
    -- Normalize direction and limit to bolt range
    local normalizedDx = dirX / targetDistance
    local normalizedDy = dirY / targetDistance
    local actualRange = math.min(targetDistance, LIGHTNING_BOLT_RANGE)
    
    -- Calculate actual end point (limited by range)
    local endX = startX + normalizedDx * actualRange
    local endY = startY + normalizedDy * actualRange
    
    -- Use limited range for path generation
    local totalDx = endX - startX
    local totalDy = endY - startY
    
    -- Create intermediate points with jitter
    for i = 1, numSegments - 1 do
        local progress = i / numSegments
        
        -- Base position along straight line
        local baseX = startX + totalDx * progress
        local baseY = startY + totalDy * progress
        
        -- Add random jitter perpendicular to the main direction
        local perpAngle = math.atan2(totalDy, totalDx) + math.pi / 2
        local jitterAmount = (math.random() - 0.5) * LIGHTNING_JITTER_RANGE
        local jitterX = math.cos(perpAngle) * jitterAmount
        local jitterY = math.sin(perpAngle) * jitterAmount
        
        pathPoints[#pathPoints + 1] = {
            x = baseX + jitterX,
            y = baseY + jitterY
        }
    end
    
    -- Final point is the range-limited end point
    pathPoints[#pathPoints + 1] = {x = endX, y = endY}
    
    return pathPoints
end

-- Process attack for a specific tower
function Grid:processTowerAttack(tower)
    if tower.ballType == 1 then  -- Flame tower
        self:flameCreateProjectiles(tower)
    elseif tower.ballType == 2 then  -- Rain tower (Water)
        self:rainCreateDots(tower)
    elseif tower.ballType == 3 then  -- Tremor tower (Earth)
        self:tremorCreateProjectiles(tower)
    elseif tower.ballType == 4 then  -- Lightning tower
        self:lightningCreateProjectiles(tower)
    elseif tower.ballType == 5 then  -- Wind tower
        self:windCreateProjectiles(tower)
    end
end

-- Create flame tower projectiles with rotation tracking
function Grid:flameCreateProjectiles(tower)
    -- Only flame towers use this system
    if tower.ballType ~= 1 then return end
    
    -- Find nearest creep within range (always check for new targets)
    local target = self:findNearestCreepInRange(tower.centerX, tower.centerY, FLAME_TOWER_RANGE)
    if not target then 
        tower.currentTarget = nil
        return 
    end
    
    -- Always update to newest target (rotation speed will limit switching)
    if tower.currentTarget ~= target then
        tower.currentTarget = target
        -- Calculate new target angle
        local dx = target.x - tower.centerX
        local dy = target.y - tower.centerY
        tower.targetAngle = math.atan2(dy, dx)
    end
    
    -- Calculate distance to target using shared helper
    local distToTarget = self:calculateTargetDistance(tower, target)
    
    -- Only fire if target is within firing range using shared helper
    if not self:isTargetInFiringRange(distToTarget, FLAME_PROJECTILE_RANGE) then
        return  -- Don't fire if creep is too far away
    end
    
    -- Update tower rotation using shared helper
    self:updateTowerRotation(tower, tower.targetAngle, FLAME_ROTATION_SPEED)
    
    -- Fire continuously while creep is in range (even while adjusting aim)
    
    -- Create multiple projectiles with random angles in cone around current angle
    for i = 1, FLAME_PROJECTILES_PER_SHOT do
        -- Random angle within ±FLAME_CONE_ANGLE degrees of current aim
        local spreadAngle = (math.random() - 0.5) * 2 * math.rad(FLAME_CONE_ANGLE)
        local projectileAngle = tower.currentAngle + spreadAngle
        
        -- Calculate projectile velocity
        local vx = math.cos(projectileAngle) * FLAME_PROJECTILE_SPEED
        local vy = math.sin(projectileAngle) * FLAME_PROJECTILE_SPEED
        
        -- Variable range: 90-110% of base range for more organic flame behavior
        local rangeMultiplier = 0.9 + (math.random() * 0.2)  -- 0.9 to 1.1
        local projectileRange = FLAME_PROJECTILE_RANGE * rangeMultiplier
        
        -- Create projectile
        self.projectiles[#self.projectiles + 1] = {
            x = tower.centerX,
            y = tower.centerY,
            vx = vx,
            vy = vy,
            damage = FLAME_PROJECTILE_DAMAGE,
            towerType = 1,  -- Flame tower
            maxRange = projectileRange,  -- Variable range instead of fixed lifespan
            startX = tower.centerX,
            startY = tower.centerY
        }
    end
end

-- Create rain tower damage dots in random positions around tower
function Grid:rainCreateDots(tower)
    -- Only rain towers use this system
    if tower.ballType ~= 2 then return end
    
    -- Rain towers always spawn dots - no range or target checking needed
    for i = 1, RAIN_DOTS_PER_FRAME do
        -- Generate random position within the ring (between inner and outer radius)
        local angle = math.random() * 2 * math.pi
        -- For ring distribution: distance between inner and outer radius
        local ringWidth = RAIN_OUTER_RADIUS - RAIN_INNER_RADIUS
        local distance = RAIN_INNER_RADIUS + math.sqrt(math.random()) * ringWidth
        
        local dotX = tower.centerX + math.cos(angle) * distance
        local dotY = tower.centerY + math.sin(angle) * distance
        
        -- Create rain dot
        self.rainDots[#self.rainDots + 1] = {
            x = dotX,
            y = dotY,
            damage = RAIN_DOT_DAMAGE,
            lifetime = RAIN_DOT_LIFETIME,
            spawnFrame = self.frameCounter
        }
    end
end


-- Create tremor tower projectiles with precise arc pattern
function Grid:tremorCreateProjectiles(tower)
    -- Only tremor towers use this system
    if tower.ballType ~= 3 then return end
    
    -- Find nearest creep within range (always check for new targets)
    local target = self:findNearestCreepInRange(tower.centerX, tower.centerY, TREMOR_TOWER_RANGE)
    if not target then 
        tower.currentTarget = nil
        return 
    end
    
    -- Always update to newest target (rotation speed will limit switching)
    if tower.currentTarget ~= target then
        tower.currentTarget = target
        -- Calculate new target angle
        local dx = target.x - tower.centerX
        local dy = target.y - tower.centerY
        tower.targetAngle = math.atan2(dy, dx)
    end
    
    -- Calculate distance to target using shared helper
    local distToTarget = self:calculateTargetDistance(tower, target)
    
    -- Only fire if target is within firing range using shared helper
    if not self:isTargetInFiringRange(distToTarget, TREMOR_PROJECTILE_RANGE) then
        return  -- Don't fire if creep is too far away
    end
    
    -- Update tower rotation using shared helper
    self:updateTowerRotation(tower, tower.targetAngle, TREMOR_ROTATION_SPEED)
    
    -- Create 15 projectiles in precise arc pattern
    local arcRadians = math.rad(TREMOR_ARC_ANGLE)  -- Convert 45° to radians
    local angleStep = arcRadians / (TREMOR_PROJECTILES_PER_SHOT - 1)  -- 14 steps for 15 shots
    local startAngle = tower.currentAngle - (arcRadians / 2)  -- Start at left edge of arc
    
    for i = 0, TREMOR_PROJECTILES_PER_SHOT - 1 do
        -- Calculate precise angle for this projectile
        local projectileAngle = startAngle + (i * angleStep)
        
        -- Calculate projectile velocity
        local vx = math.cos(projectileAngle) * TREMOR_PROJECTILE_SPEED
        local vy = math.sin(projectileAngle) * TREMOR_PROJECTILE_SPEED
        
        -- Create projectile
        self.projectiles[#self.projectiles + 1] = {
            x = tower.centerX,
            y = tower.centerY,
            vx = vx,
            vy = vy,
            damage = TREMOR_PROJECTILE_DAMAGE,
            towerType = 3,  -- Tremor tower
            maxRange = TREMOR_PROJECTILE_RANGE,
            startX = tower.centerX,
            startY = tower.centerY
        }
    end
end

-- Create wind tower projectiles with spirograph burst pattern
function Grid:windCreateProjectiles(tower)
    -- Only wind towers use this system
    if tower.ballType ~= 5 then return end
    
    -- Initialize burst state if not already set
    if not tower.burstProgress then
        tower.burstProgress = 0
        tower.burstActive = false
    end
    
    -- Check if we should start a new burst
    if not tower.burstActive then
        -- Find nearest creep within range to start burst
        local target = self:findNearestCreepInRange(tower.centerX, tower.centerY, WIND_TOWER_RANGE)
        
        if not target then 
            tower.currentTarget = nil
            return  -- Don't fire if no target in range
        end
        
        -- Always update to newest target
        if tower.currentTarget ~= target then
            tower.currentTarget = target
            -- Calculate new target angle
            local dx = target.x - tower.centerX
            local dy = target.y - tower.centerY
            tower.targetAngle = math.atan2(dy, dx)
        end
        
        -- Calculate distance to target using shared helper
        local distToTarget = self:calculateTargetDistance(tower, target)
        
        -- Only start burst if target is within firing range
        if not self:isTargetInFiringRange(distToTarget, WIND_PROJECTILE_RANGE) then
            return  -- Don't fire if creep is too far away
        end
        
        -- Update tower rotation using shared helper
        self:updateTowerRotation(tower, tower.targetAngle, WIND_ROTATION_SPEED)
        
        -- Start new burst
        tower.burstActive = true
        tower.burstProgress = 0
        tower.burstStartAngle = tower.currentAngle  -- Lock in angle for entire burst
    end
    
    -- Continue burst if active
    if tower.burstActive then
        tower.burstProgress = tower.burstProgress + 1
        
        -- Fire one projectile this frame
        local burstRatio = tower.burstProgress / WIND_BURST_DURATION  -- 0 to 1
        
        -- Each projectile gets its own position in the spirograph pattern
        local spiralAngle = burstRatio * 2 * math.pi  -- One rotation per burst
        
        -- Base direction toward target
        local baseVx = math.cos(tower.burstStartAngle) * WIND_PROJECTILE_SPEED
        local baseVy = math.sin(tower.burstStartAngle) * WIND_PROJECTILE_SPEED
        
        -- Create projectile with spirograph motion data
        self.projectiles[#self.projectiles + 1] = {
            x = tower.centerX,
            y = tower.centerY,
            vx = baseVx,
            vy = baseVy,
            damage = WIND_PROJECTILE_DAMAGE,
            towerType = 5,  -- Wind tower
            maxRange = WIND_PROJECTILE_RANGE,
            startX = tower.centerX,
            startY = tower.centerY,
            -- Spirograph motion data
            spiralCenterVx = baseVx,  -- Direction the spiral center moves
            spiralCenterVy = baseVy,
            spiralRadius = WIND_SPIRAL_RADIUS,
            spiralAngle = spiralAngle,  -- Starting angle in the circle
            spiralSpeed = 0.3,  -- Speed of rotation around the circle (radians per frame)
            spiralCenterX = tower.centerX,  -- Current center position
            spiralCenterY = tower.centerY
        }
        
        -- End burst when all projectiles fired
        if tower.burstProgress >= WIND_BURST_DURATION then
            tower.burstActive = false
            tower.burstProgress = 0
            tower.lastAttackTime = 0  -- Reset cooldown timer for 24-frame pause
        end
    end
end

-- Create instant lightning bolt effects
function Grid:lightningCreateProjectiles(tower)
    -- Only lightning towers use this system
    if tower.ballType ~= 4 then return end
    
    -- Initialize lightning state if not already set
    if not tower.lightningSequenceActive then
        tower.lightningSequenceActive = false
        tower.lightningSequenceProgress = 0
        tower.lightningBoltsFired = 0
    end
    
    -- Check if we should start a new lightning sequence
    if not tower.lightningSequenceActive then
        -- ENHANCED: Find priority target (Tier 2 > Tier 1 > Basic) within range
        local target = self:findPriorityTargetForLightning(tower.centerX, tower.centerY, LIGHTNING_TOWER_RANGE)
        
        if not target then 
            tower.currentTarget = nil
            return  -- Don't fire if no target in range
        end
        
        -- Always update to newest target
        if tower.currentTarget ~= target then
            tower.currentTarget = target
            -- Calculate new target angle
            local dx = target.x - tower.centerX
            local dy = target.y - tower.centerY
            tower.targetAngle = math.atan2(dy, dx)
        end
        
        -- Calculate distance to target using shared helper
        local distToTarget = self:calculateTargetDistance(tower, target)
        
        -- Only fire if target is within actual bolt range (not the multiplied firing range)
        if distToTarget > LIGHTNING_BOLT_RANGE then
            return  -- Don't fire if target is beyond bolt reach
        end
        
        -- Update tower rotation using shared helper
        self:updateTowerRotation(tower, tower.targetAngle, WIND_ROTATION_SPEED)
        
        -- Start new lightning sequence
        tower.lightningSequenceActive = true
        tower.lightningSequenceProgress = 0
        tower.lightningBoltsFired = 0
        tower.currentTarget = target  -- Lock target for entire sequence
    end
    
    -- Continue lightning sequence if active
    if tower.lightningSequenceActive then
        tower.lightningSequenceProgress = tower.lightningSequenceProgress + 1
        
        -- Fire bolts at intervals during sequence (frames 1 and 5, 4 frames apart)
        local boltFrame = tower.lightningSequenceProgress
        if (boltFrame == 1 or boltFrame == 5) and tower.lightningBoltsFired < LIGHTNING_BOLTS_PER_SEQUENCE then
            tower.lightningBoltsFired = tower.lightningBoltsFired + 1
            
            -- Generate new jagged path for this bolt
            local lightningPath = self:generateLightningPath(tower.centerX, tower.centerY, tower.currentTarget.x, tower.currentTarget.y)
            
            -- Create instant lightning effect
            self.lightningEffects[#self.lightningEffects + 1] = {
                path = lightningPath,
                lifetime = LIGHTNING_BOLT_LIFETIME,
                damage = LIGHTNING_BOLT_DAMAGE,
                targetCreep = tower.currentTarget,
                towerX = tower.centerX,
                towerY = tower.centerY
            }
            
            -- Apply instant damage along bolt path
            self:applyLightningDamage(lightningPath, LIGHTNING_BOLT_DAMAGE)
        end
        
        -- End lightning sequence after duration (8 frames total)
        if tower.lightningSequenceProgress >= LIGHTNING_SEQUENCE_DURATION then  
            tower.lightningSequenceActive = false
            tower.lightningSequenceProgress = 0
            tower.lightningBoltsFired = 0
            tower.currentTarget = nil
            
            -- Variable cooldown: 50% to 150% of base cooldown (3 to 9 frames)
            local minCooldown = math.ceil(LIGHTNING_TOWER_COOLDOWN * 0.5)   -- 50% = 3 frames
            local maxCooldown = math.ceil(LIGHTNING_TOWER_COOLDOWN * 1.5)   -- 150% = 9 frames
            local randomCooldown = math.random(minCooldown, maxCooldown)
            
            tower.lastAttackTime = 0  -- Reset cooldown timer
            tower.variableCooldown = randomCooldown  -- Store the random cooldown for this cycle
        end
    end
end

-- Apply instant damage along lightning bolt path
-- Checks for creep collisions along the entire jagged lightning path
function Grid:applyLightningDamage(lightningPath, damage)
    if #lightningPath < 2 then return end
    
    -- Check each line segment of the lightning path
    for i = 1, #lightningPath - 1 do
        local startPoint = lightningPath[i]
        local endPoint = lightningPath[i + 1]
        
        -- Check collision with each creep along this line segment
        for _, creep in ipairs(self.creeps) do
            if creep.marching then  -- Only hit marching creeps
                -- Calculate distance from creep to line segment
                local distToSegment = self:pointToLineDistance(
                    creep.x, creep.y,
                    startPoint.x, startPoint.y,
                    endPoint.x, endPoint.y
                )
                
                -- Check if creep is close enough to be hit by lightning
                local creepSize = creep.tier == "basic" and CREEP_SIZE or 
                                 creep.tier == "tier1" and CREEP_SIZE + 1 or 
                                 creep.tier == "tier2" and CREEP_SIZE + 5 or CREEP_SIZE
                
                if distToSegment <= creepSize + 2 then  -- 2px lightning width
                    -- Apply damage to creep
                    creep.hitpoints = creep.hitpoints - damage
                    
                    -- Remove dead creeps
                    if creep.hitpoints <= 0 then
                        -- Mark for removal (will be cleaned up in update cycle)
                        creep.dead = true
                    end
                    
                    -- Lightning hits only one creep per bolt (break after first hit)
                    return
                end
            end
        end
    end
end

-- Calculate distance from point to line segment
-- Returns the shortest distance from point (px, py) to line segment (x1,y1)-(x2,y2)
function Grid:pointToLineDistance(px, py, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local lengthSquared = dx * dx + dy * dy
    
    if lengthSquared == 0 then
        -- Line segment is a point
        local dpx = px - x1
        local dpy = py - y1
        return math.sqrt(dpx * dpx + dpy * dpy)
    end
    
    -- Calculate projection of point onto line
    local t = ((px - x1) * dx + (py - y1) * dy) / lengthSquared
    t = math.max(0, math.min(1, t))  -- Clamp to line segment
    
    -- Find closest point on line segment
    local closestX = x1 + t * dx
    local closestY = y1 + t * dy
    
    -- Return distance to closest point
    local dpx = px - closestX
    local dpy = py - closestY
    return math.sqrt(dpx * dpx + dpy * dpy)
end

-- Find nearest creep within range of tower
function Grid:findNearestCreepInRange(towerX, towerY, range)
    local nearestCreep = nil
    local nearestDist = math.huge
    
    for _, creep in ipairs(self.creeps) do
        if creep.marching then  -- Only target marching creeps
            local dx = creep.x - towerX
            local dy = creep.y - towerY
            local dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= range and dist < nearestDist then
                nearestCreep = creep
                nearestDist = dist
            end
        end
    end
    
    return nearestCreep
end

-- ENHANCED: Lightning tower smart targeting with priority weights
-- Prioritizes Tier 2 > Tier 1 > Basic creeps, then by distance within same tier
-- @param towerX, towerY: Tower center position
-- @param range: Detection range for targeting
-- @return bestTarget: Highest priority creep in range, or nil if none found
function Grid:findPriorityTargetForLightning(towerX, towerY, range)
    local bestTarget = nil
    local bestScore = -1
    
    for _, creep in ipairs(self.creeps) do
        if creep.marching then  -- Only target marching creeps
            local dx = creep.x - towerX
            local dy = creep.y - towerY
            local dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= range then
                -- Calculate priority weight based on creep tier
                local weight = LIGHTNING_TARGET_WEIGHT_BASIC  -- Default to basic
                if creep.tier == "tier1" then
                    weight = LIGHTNING_TARGET_WEIGHT_TIER1
                elseif creep.tier == "tier2" then
                    weight = LIGHTNING_TARGET_WEIGHT_TIER2
                end
                
                -- Score = weight - distance (higher weight + closer = better score)
                -- Distance normalized to 0-1 range so weight dominates
                local normalizedDist = dist / range
                local score = weight - normalizedDist
                
                if score > bestScore then
                    bestTarget = creep
                    bestScore = score
                end
            end
        end
    end
    
    return bestTarget
end

-- Predict where a creep will be based on its movement
function Grid:predictCreepPosition(creep)
    -- Simple prediction: assume creep continues current movement
    local futureFrames = 10  -- Predict 10 frames ahead
    local predictedX = creep.x
    local predictedY = creep.y
    
    if creep.marching then
        -- Simplified: if not waiting for delay, predict movement toward towers
        if creep.marchDelay <= 0 then
            -- Creep is moving toward towers at CREEP_MARCH_SPEED
            predictedX = creep.x - (CREEP_MARCH_SPEED * futureFrames)
        end
        -- If still waiting (marchDelay > 0), stay at current position
    end
    
    return predictedX, predictedY
end

-- ENHANCED: Update creep attacks on towers (supports Tier 1+2 ranged combat)
function Grid:updateCreepAttacks(creep)
    if creep.tier == "tier1" then
        -- TIER 1: Aggressive close-range shooting
        self:updateTier1RangedCombat(creep)
    elseif creep.tier == "tier2" then
        -- TIER 2: Cautious long-range shooting
        self:updateTier2RangedCombat(creep)
    else
        -- BASIC: Traditional suicide attacks
        self:updateBasicCreepAttacks(creep)
    end
end

-- Traditional suicide attacks for Basic creeps only
function Grid:updateBasicCreepAttacks(creep)
    -- Update attack cooldown
    creep.lastAttackTime = creep.lastAttackTime + 1
    
    -- Check if creep can attack
    if creep.lastAttackTime >= CREEP_ATTACK_COOLDOWN then
        -- Use the locked stand-and-fight target instead of finding a new one
        local target = creep.standAndFightTarget
        if target and target.hitpoints > 0 then
            -- Check if target is in attack range
            local dx = target.centerX - creep.x
            local dy = target.centerY - creep.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= CREEP_ATTACK_RANGE then
                -- Attack the locked tower
                target.hitpoints = target.hitpoints - CREEP_BASIC_DAMAGE
                creep.lastAttackTime = 0  -- Reset cooldown
                print("SUICIDE: Basic creep attacked tower! Damage=" .. CREEP_BASIC_DAMAGE .. ", HP left=" .. target.hitpoints)
                
                -- Check if tower is destroyed
                if target.hitpoints <= 0 then
                    print("DESTROY: Tower destroyed by basic creep!")
                    self:destroyTower(target)
                end
                
                -- SUICIDE: Remove the creep after attack (suicide behavior)
                creep.hitpoints = 0  -- Mark for removal by main update loop
            end
        end
    end
end

-- ENHANCED: Tier 1 ranged combat (aggressive, close-range, balanced vs old suicide)
function Grid:updateTier1RangedCombat(creep)
    -- Initialize ranged combat properties if needed
    if not creep.lastRangedAttack then
        creep.lastRangedAttack = 0
        creep.kiteTarget = nil
        creep.kiteDirection = 0  -- -1 = move away, 0 = maintain, 1 = move closer
    end
    
    -- Update ranged attack cooldown
    creep.lastRangedAttack = creep.lastRangedAttack + 1
    
    -- ENHANCED: Use "stand and fight" target, or find closest if none set
    local target = creep.standAndFightTarget
    if not target or target.hitpoints <= 0 then
        target = self:findClosestLivingTower(creep.x, creep.y)
    end
    
    -- Only shoot if target is in range (account for tower radius)
    if target then
        local dx = target.centerX - creep.x
        local dy = target.centerY - creep.y
        local distToTarget = math.sqrt(dx*dx + dy*dy)
        -- Effective range: shooting range minus tower radius (edge-to-center distance)
        local effectiveRange = CREEP_TIER1_RANGE - TOWER_SPRITE_RADIUS
        if distToTarget > effectiveRange then
            target = nil  -- Out of range, can't shoot
        end
    end
    
    if target then
        -- STAND AND FIGHT: No kiting, just shoot when in range and ready
        if creep.lastRangedAttack >= CREEP_TIER1_COOLDOWN then
            -- Calculate projectile direction toward tower
            local dx = target.centerX - creep.x
            local dy = target.centerY - creep.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            -- Create projectile toward tower
            local vx = (dx / dist) * CREEP_TIER1_PROJECTILE_SPEED
            local vy = (dy / dist) * CREEP_TIER1_PROJECTILE_SPEED
            
            self.projectiles[#self.projectiles + 1] = {
                x = creep.x,
                y = creep.y,
                vx = vx,
                vy = vy,
                damage = CREEP_TIER1_DAMAGE,
                creepType = "tier1",  -- Mark as creep projectile
                maxRange = CREEP_TIER1_RANGE,
                startX = creep.x,
                startY = creep.y
            }
            
            creep.lastRangedAttack = 0  -- Reset cooldown
            print("SHOOT: Tier1 creep fired projectile at tower")
        end
    end
end

-- ENHANCED: Tier 2 ranged combat with "stand and fight" behavior
function Grid:updateTier2RangedCombat(creep)
    -- Initialize ranged combat properties if needed
    if not creep.lastRangedAttack then
        creep.lastRangedAttack = 0
    end
    
    -- Update ranged attack cooldown
    creep.lastRangedAttack = creep.lastRangedAttack + 1
    
    -- ENHANCED: Use "stand and fight" target, or find closest if none set
    local target = creep.standAndFightTarget
    if not target or target.hitpoints <= 0 then
        target = self:findClosestLivingTower(creep.x, creep.y)
    end
    
    -- Only shoot if target is in range (account for tower radius)
    if target then
        local dx = target.centerX - creep.x
        local dy = target.centerY - creep.y
        local distToTarget = math.sqrt(dx*dx + dy*dy)
        -- Effective range: shooting range minus tower radius (edge-to-center distance)
        local effectiveRange = CREEP_TIER2_RANGE - TOWER_SPRITE_RADIUS
        if distToTarget > effectiveRange then
            target = nil  -- Out of range, can't shoot
        end
    end
    
    if target then
        -- STAND AND FIGHT: No kiting, just shoot when in range and ready
        if creep.lastRangedAttack >= CREEP_TIER2_COOLDOWN then
            -- Calculate projectile direction toward tower
            local dx = target.centerX - creep.x
            local dy = target.centerY - creep.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            -- Create projectile toward tower
            local vx = (dx / dist) * CREEP_TIER2_PROJECTILE_SPEED
            local vy = (dy / dist) * CREEP_TIER2_PROJECTILE_SPEED
            
            self.projectiles[#self.projectiles + 1] = {
                x = creep.x,
                y = creep.y,
                vx = vx,
                vy = vy,
                damage = CREEP_TIER2_DAMAGE,
                creepType = "tier2",  -- Mark as creep projectile
                maxRange = CREEP_TIER2_RANGE,
                startX = creep.x,
                startY = creep.y
            }
            
            creep.lastRangedAttack = 0  -- Reset cooldown
            print("SHOOT: Tier2 creep fired projectile at tower")
        end
    end
end

-- Find nearest tower within range of creep
function Grid:findNearestTowerInRange(creepX, creepY, range)
    local nearestTower = nil
    local nearestDist = math.huge
    
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then  -- Only attack living towers
            local dx = tower.centerX - creepX
            local dy = tower.centerY - creepY
            local dist = math.sqrt(dx*dx + dy*dy)
            
            if dist <= range and dist < nearestDist then
                nearestTower = tower
                nearestDist = dist
            end
        end
    end
    
    return nearestTower
end

-- Destroy a tower when its HP reaches 0
function Grid:destroyTower(tower)
    -- Find and remove the tower from tierOnePositions
    for idx, towerData in pairs(self.tierOnePositions) do
        if towerData == tower then
            -- Clear the triangle cells
            for _, cellIdx in ipairs(tower.triangle) do
                self.cells[cellIdx].ballType = nil
                self.cells[cellIdx].occupied = false
                self.cells[cellIdx].tier = nil
            end
            
            -- Remove from tierOnePositions
            self.tierOnePositions[idx] = nil
            break
        end
    end
    
    -- Check for game over (no more towers)
    self:checkForDefeat()
end

-- Destroy a Tier 2 tower when its hitpoints reach 0
function Grid:destroyTowerTier2(tower, towerIdx)
    -- Clear the pattern cells
    for _, cellIdx in ipairs(tower.pattern) do
        self.cells[cellIdx].ballType = nil
        self.cells[cellIdx].occupied = false
        self.cells[cellIdx].tier = nil
    end
    
    -- Remove from tierTwoPositions
    self.tierTwoPositions[towerIdx] = nil
    
    -- Check for game over (no more towers)
    self:checkForDefeat()
end

-- Check if player has lost (no more towers)
function Grid:checkForDefeat()
    local hasTowers = false
    for _, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then
            hasTowers = true
            break
        end
    end
    
    -- Also check if there are any Tier 2 or Tier 3 towers
    if not hasTowers then
        for _, _ in pairs(self.tierTwoPositions) do
            hasTowers = true
            break
        end
    end
    
    if not hasTowers then
        for _, _ in pairs(self.tierThreePositions) do
            hasTowers = true
            break
        end
    end
    
    if not hasTowers then
        -- Player has lost - start game over sequence
        self:startGameOverSequence()
    end
end

-- Update all projectiles with optimized collision detection
-- Performance optimized: Screen boundary check first, range check second, collision last
-- Processes projectiles in reverse order to handle safe removal during iteration
function Grid:updateProjectiles()
    for i = #self.projectiles, 1, -1 do
        local projectile = self.projectiles[i]
        
        -- Move projectile
        if projectile.towerType == 5 and projectile.spiralCenterVx then
            -- Wind tower spirograph motion
            -- Move the spiral center forward
            projectile.spiralCenterX = projectile.spiralCenterX + projectile.spiralCenterVx
            projectile.spiralCenterY = projectile.spiralCenterY + projectile.spiralCenterVy
            
            -- Rotate around the spiral center
            projectile.spiralAngle = projectile.spiralAngle + projectile.spiralSpeed
            
            -- Calculate position: moving center + rotating offset
            local spiralOffsetX = math.cos(projectile.spiralAngle) * projectile.spiralRadius
            local spiralOffsetY = math.sin(projectile.spiralAngle) * projectile.spiralRadius
            
            projectile.x = projectile.spiralCenterX + spiralOffsetX
            projectile.y = projectile.spiralCenterY + spiralOffsetY
        else
            -- Standard linear motion for other projectiles
            projectile.x = projectile.x + projectile.vx
            projectile.y = projectile.y + projectile.vy
        end
        
        -- Early exit: check screen boundaries first (fastest check)
        if projectile.x < 0 or projectile.x > SCREEN_WIDTH or 
           projectile.y < 0 or projectile.y > SCREEN_HEIGHT then
            table.remove(self.projectiles, i)
            goto continue
        end
        
        -- Check range limit
        local distTraveled
        if projectile.towerType == 5 and projectile.spiralCenterX then
            -- For wind projectiles, use spiral center distance
            local dx = projectile.spiralCenterX - projectile.startX
            local dy = projectile.spiralCenterY - projectile.startY
            distTraveled = math.sqrt(dx*dx + dy*dy)
        else
            -- Standard distance calculation
            local dx = projectile.x - projectile.startX
            local dy = projectile.y - projectile.startY
            distTraveled = math.sqrt(dx*dx + dy*dy)
        end
        
        -- Use variable range if available, otherwise fall back to default
        local maxRange = projectile.maxRange or FLAME_PROJECTILE_RANGE
        
        -- Remove if traveled max range
        if distTraveled >= maxRange then
            table.remove(self.projectiles, i)
        else
            -- Check collision based on projectile type
            if projectile.creepType then
                -- Creep projectile - check collision with towers
                self:checkCreepProjectileTowerCollision(projectile, i)
            else
                -- Tower projectile - check collision with creeps
                self:checkProjectileCreepCollision(projectile, i)
            end
        end
        
        ::continue::
    end
end

-- Update rain dots: handle lifetime, collision detection, and cleanup
function Grid:updateRainDots()
    for i = #self.rainDots, 1, -1 do
        local dot = self.rainDots[i]
        
        -- Check if dot has expired (5 frames)
        if (self.frameCounter - dot.spawnFrame) >= RAIN_DOT_LIFETIME then
            table.remove(self.rainDots, i)
            goto continue
        end
        
        -- Check collision with all creeps
        for j = #self.creeps, 1, -1 do
            local creep = self.creeps[j]
            
            -- Calculate distance between dot and creep
            local dx = dot.x - creep.x
            local dy = dot.y - creep.y
            local distance = math.sqrt(dx*dx + dy*dy)
            
            -- Check if creep is touching the dot (use creep size for collision radius)
            if distance <= creep.size then
                -- Deal damage to creep
                creep.hitpoints = creep.hitpoints - dot.damage
                
                -- Remove the dot (it gets consumed on hit)
                table.remove(self.rainDots, i)
                
                -- Check if creep is dead
                if creep.hitpoints <= 0 then
                    -- Free up staging position if this was the last creep there
                    self:checkStagingAvailability(creep.stagingIdx)
                    table.remove(self.creeps, j)
                    
                    -- Check for victory after removing creep
                    self:checkForVictory()
                end
                
                goto continue  -- Dot is consumed, move to next dot
            end
        end
        
        ::continue::
    end
end

-- Update lightning effects: handle lifetime and cleanup
function Grid:updateLightningEffects()
    for i = #self.lightningEffects, 1, -1 do
        local effect = self.lightningEffects[i]
        
        -- Decrease lifetime each frame
        effect.lifetime = effect.lifetime - 1
        
        -- Remove expired effects
        if effect.lifetime <= 0 then
            table.remove(self.lightningEffects, i)
        end
    end
end

-- Check if projectile collides with any creep (optimized with tower config)
-- Uses tower configuration to determine piercing behavior
-- @param projectile: Projectile object with towerType, damage, position
-- @param projectileIndex: Index in projectiles array for removal
function Grid:checkProjectileCreepCollision(projectile, projectileIndex)
    -- Get tower configuration for piercing behavior
    local towerConfig = TOWER_CONFIGS[projectile.towerType]
    local isPiercing = towerConfig and towerConfig.special.piercing or false
    
    for i, creep in ipairs(self.creeps) do
        if creep.marching then  -- Only hit marching creeps
            local dx = projectile.x - creep.x
            local dy = projectile.y - creep.y
            local dist = math.sqrt(dx*dx + dy*dy)
            
            -- Hit if projectile is within creep's collision radius
            if dist <= creep.size then
                -- Deal damage to creep
                creep.hitpoints = creep.hitpoints - projectile.damage
                
                -- Apply special effects based on projectile type
                if projectile.towerType == 3 then  -- Tremor tower - earthquake wave stun
                    creep.stunFrames = 12  -- 12 frames of movement disable
                elseif projectile.towerType == 5 then  -- Wind tower - ENHANCED pushback
                    -- Check if pushback is on cooldown and not already being pushed
                    if not creep.pushbackActive and 
                       (not creep.lastKnockbackFrame or (self.frameCounter - creep.lastKnockbackFrame) >= WIND_PUSHBACK_COOLDOWN) then
                        
                        -- Calculate movement direction for pushback
                        local movementDx, movementDy = 0, 0
                        
                        if creep.marching and creep.marchDelay <= 0 then
                            -- Active marching creeps move toward towers (left)
                            movementDx = -1
                            movementDy = 0
                        elseif creep.marching and creep.marchDelay > 0 then
                            -- Waiting creeps stay in place
                            movementDx = 0
                            movementDy = 0
                        elseif creep.animating and not creep.converted then
                            -- Spawning creeps move toward target
                            local dx = creep.targetX - creep.x
                            local dy = creep.targetY - creep.y
                            local dist = math.sqrt(dx*dx + dy*dy)
                            if dist > 0 then
                                movementDx = dx / dist
                                movementDy = dy / dist
                            end
                        end
                        
                        -- Start pushback animation with 3x distance (27px total)
                        if movementDx ~= 0 or movementDy ~= 0 then
                            -- Calculate target position with boundary checking
                            local targetX = creep.x - movementDx * WIND_PUSHBACK_DISTANCE
                            local targetY = creep.y - movementDy * WIND_PUSHBACK_DISTANCE
                            
                            -- Clamp to screen boundaries to prevent units going off-screen
                            targetX = math.max(10, math.min(SCREEN_WIDTH - 10, targetX))
                            targetY = math.max(10, math.min(SCREEN_HEIGHT - 10, targetY))
                            
                            creep.pushbackActive = true
                            creep.pushbackStartX = creep.x
                            creep.pushbackStartY = creep.y
                            creep.pushbackTargetX = targetX
                            creep.pushbackTargetY = targetY
                            creep.pushbackProgress = 0
                            creep.pushbackFrames = 0
                            creep.lastKnockbackFrame = self.frameCounter
                        end
                    end
                else
                    -- Initialize properties for existing creeps if not present
                    if not creep.stunFrames then
                        creep.stunFrames = 0
                    end
                    if not creep.lastKnockbackFrame then
                        creep.lastKnockbackFrame = 0
                    end
                    -- ENHANCED: Initialize pushback animation properties
                    if creep.pushbackActive == nil then
                        creep.pushbackActive = false
                        creep.pushbackStartX = 0
                        creep.pushbackStartY = 0
                        creep.pushbackTargetX = 0
                        creep.pushbackTargetY = 0
                        creep.pushbackProgress = 0
                        creep.pushbackFrames = 0
                    end
                end
                
                -- Remove projectile if it's not piercing
                if not isPiercing then
                    table.remove(self.projectiles, projectileIndex)
                end
                
                -- Check if creep is dead
                if creep.hitpoints <= 0 then
                    -- Free up staging position if this was the last creep there
                    self:checkStagingAvailability(creep.stagingIdx)
                    table.remove(self.creeps, i)
                    
                    -- Check for victory after removing creep
                    self:checkForVictory()
                end
                
                -- For piercing projectiles, continue processing other creeps
                -- For non-piercing projectiles, stop processing
                if not isPiercing then
                    return  -- Non-piercing projectile hit something, stop processing
                end
            end
        end
    end
end

-- Check collision between creep projectiles and towers
function Grid:checkCreepProjectileTowerCollision(projectile, projectileIndex)
    -- Check all tier 1 towers for collision
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then  -- Only check living towers
            -- Calculate distance between projectile and tower center
            local dx = projectile.x - tower.centerX
            local dy = projectile.y - tower.centerY
            local distance = math.sqrt(dx*dx + dy*dy)
            
            -- Tower collision radius (use sprite radius)
            local towerRadius = TOWER_SPRITE_RADIUS
            
            -- Check if projectile hits the tower
            if distance <= towerRadius then
                -- Apply damage to tower
                tower.hitpoints = tower.hitpoints - projectile.damage
                
                -- Remove the projectile
                table.remove(self.projectiles, projectileIndex)
                
                print("HIT: Tower hit by " .. projectile.creepType .. " projectile! Damage=" .. projectile.damage .. ", HP left=" .. tower.hitpoints)
                
                -- Check if tower is destroyed
                if tower.hitpoints <= 0 then
                    print("DESTROY: Tower destroyed by creep projectile!")
                    self:destroyTower(tower)
                end
                
                return  -- Projectile hit something, stop processing
            end
        end
    end
    
    -- Check all tier 2 towers for collision
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then  -- Only check living towers
            -- Calculate distance between projectile and tower center
            local dx = projectile.x - tower.centerX
            local dy = projectile.y - tower.centerY
            local distance = math.sqrt(dx*dx + dy*dy)
            
            -- Tower collision radius (larger for tier 2)
            local towerRadius = TOWER_SPRITE_RADIUS + 8
            
            -- Check if projectile hits the tower
            if distance <= towerRadius then
                -- Apply damage to tower
                tower.hitpoints = tower.hitpoints - projectile.damage
                
                -- Remove the projectile
                table.remove(self.projectiles, projectileIndex)
                
                print("HIT: Tier 2 Tower hit by " .. projectile.creepType .. " projectile! Damage=" .. projectile.damage .. ", HP left=" .. tower.hitpoints)
                
                -- Check if tower is destroyed
                if tower.hitpoints <= 0 then
                    print("DESTROY: Tier 2 Tower destroyed by creep projectile!")
                    self:destroyTowerTier2(tower, idx)
                end
                
                return  -- Projectile hit something, stop processing
            end
        end
    end
end

-- Check if all towers are destroyed (game over condition)
function Grid:checkForGameOver()
    -- Count remaining towers
    local towerCount = 0
    for idx = 1, #self.cells do
        local cell = self.cells[idx]
        if cell and cell.occupied and cell.ballType and cell.ballType >= 1 and cell.ballType <= 5 then
            towerCount = towerCount + 1
        end
    end
    
    -- If no towers remain, trigger game over
    if towerCount == 0 then
        print("GAME OVER: All towers destroyed!")
        -- Could add game over state here
        -- For now, just print message
    end
end

-- Draw HP bar above a tower
function Grid:drawTowerHPBar(tower)
    -- Only draw HP bar if tower is damaged
    if tower.hitpoints >= tower.maxHitpoints then return end
    
    local barWidth = 20
    local barHeight = 3
    local barX = tower.centerX - barWidth/2
    local barY = tower.centerY - 25  -- Above the tower sprite
    
    -- Calculate HP percentage
    local hpPercent = tower.hitpoints / tower.maxHitpoints
    local fillWidth = barWidth * hpPercent
    
    -- Draw background (black border)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(barX-1, barY-1, barWidth+2, barHeight+2)
    
    -- Draw empty bar (white background)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(barX, barY, barWidth, barHeight)
    
    -- Draw filled portion (black fill)
    if fillWidth > 0 then
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(barX, barY, fillWidth, barHeight)
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
        end
        
        sprite:draw(troop.x - offset, troop.y - offset)
    end
end

-- Draw all projectiles
function Grid:drawProjectiles()
    gfx.setColor(gfx.kColorBlack)
    for _, projectile in ipairs(self.projectiles) do
        local shouldDraw = true
        
        -- Hide flame projectiles when they're close to their source tower
        if projectile.towerType == 1 then  -- Flame tower
            local dx = projectile.x - projectile.startX
            local dy = projectile.y - projectile.startY
            local distFromTower = math.sqrt(dx*dx + dy*dy)
            
            -- Hide projectiles within distance of the tower (behind/under tower)
            if distFromTower <= PROJECTILE_HIDE_DISTANCE then
                shouldDraw = false
            end
        end
        
        if shouldDraw then
            if projectile.towerType == 1 then  -- Flame tower
                gfx.fillCircleAtPoint(projectile.x, projectile.y, 1)
            elseif projectile.towerType == 3 then  -- Tremor tower
                gfx.fillCircleAtPoint(projectile.x, projectile.y, 2)  -- Larger projectiles
            elseif projectile.towerType == 5 then  -- Wind tower
                gfx.fillCircleAtPoint(projectile.x, projectile.y, 1)  -- Same size as flame
            elseif projectile.creepType == "tier1" then  -- Tier 1 creep projectile
                gfx.fillCircleAtPoint(projectile.x, projectile.y, 1)  -- 1px diameter
            elseif projectile.creepType == "tier2" then  -- Tier 2 creep projectile
                gfx.fillCircleAtPoint(projectile.x, projectile.y, 2)  -- 2px diameter
            end
        end
    end
end

-- Draw lightning bolt effects as jagged lines
function Grid:drawLightningEffects()
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)  -- Slightly thick lines for visibility
    
    for _, effect in ipairs(self.lightningEffects) do
        local path = effect.path
        
        -- Draw each line segment of the jagged lightning path
        for i = 1, #path - 1 do
            local startPoint = path[i]
            local endPoint = path[i + 1]
            
            gfx.drawLine(
                startPoint.x, startPoint.y,
                endPoint.x, endPoint.y
            )
        end
    end
    
    gfx.setLineWidth(1)  -- Reset line width
end

-- Handle troop shot counting and cycle management
function Grid:handleTroopShotCounting()
    self.troopShotCounter = self.troopShotCounter + 1
    
    -- Check if ammo is exhausted (no more shots available)
    local ammoExhausted = (self.currentShotIndex > 15)
    
    -- Shot 4: march all troops off screen and reset cycle, but only if ammo is exhausted
    if self.troopShotCounter == 4 and ammoExhausted then
        self:marchTroopsOffscreen()
        self.troopShotCounter = 0  -- Reset for next cycle
    elseif self.troopShotCounter >= 4 and not ammoExhausted then
        -- Keep counting but don't march until ammo runs out
        -- troopShotCounter will keep incrementing beyond 4
    end
end
-- Spawn troops when merges/tiers complete (called from animation completions)
function Grid:spawnTroopsForShot()
    -- Only spawn from Tier 3 bubbles (with new flashing behavior)
    -- Note: Tier 3 spawning is now handled by the flashing animation system
    -- No immediate spawning - Tier 3 bubbles will flash then spawn and despawn
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
            -- Flash on/off every 10 frames (visible on frames 0-9, 20-29, 40-49)
            local flashCycle = math.floor(anim.frame / 10) % 2
            if flashCycle == 0 then  -- Show on even cycles (0, 2, 4)
                self.bubbleSprites.tier3[anim.sprite]:draw(anim.centerX - 42, anim.centerY - 42)
            end
            -- Don't draw on odd cycles (1, 3, 5) to create flashing effect
        end
    end
end

-- Draw UI elements
function Grid:drawUI()
    local shotsRemaining = self:getShotsRemaining()
    local currentShooter = self:getCurrentShooterBall()
    local onDeckBall = self:getOnDeckBall()
    
    
    -- On-deck ball (only show if exists AND more than 1 shot remains)
    if onDeckBall and shotsRemaining > 1 then
        local onDeckPos = self.positions[(15 - 1) * 20 + 17]
        if onDeckPos then
            self.bubbleSprites.basic[onDeckBall]:draw(onDeckPos.x - 10, onDeckPos.y - 10)
        end
    end
    
    -- Shot count (only show if shots remaining > 0)
    if shotsRemaining > 0 then
        local onDeckPos = self.positions[(15 - 1) * 20 + 17]
        if onDeckPos then
            gfx.setColor(gfx.kColorBlack)
            local countText = tostring(shotsRemaining)
            local textWidth, textHeight = gfx.getTextSize(countText)
            gfx.drawText(countText, onDeckPos.x + 15, onDeckPos.y - textHeight / 2)
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

-- Draw victory screen
function Grid:drawVictoryScreen()
    local boxWidth, boxHeight = 200, 80
    local boxX, boxY = 200 - boxWidth / 2, 120 - boxHeight / 2
    
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(boxX, boxY, boxWidth, boxHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(boxX, boxY, boxWidth, boxHeight)
    
    gfx.drawTextInRect("VICTORY!", boxX, boxY + 10, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("All 5 levels complete!", boxX, boxY + 30, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("Press A to restart", boxX, boxY + 50, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
end

return Grid