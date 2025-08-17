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
-- - Post-attack tower compacting system with recursive merge detection
--
-- Performance: 60fps stable, ~1900 lines with full feature set
-- Design principle: Clean separation of concerns, boundary-aware positioning
--
-- ============================================================================
-- POST-ATTACK TOWER COMPACTING SYSTEM (COMPLETED & FUNCTIONAL)
-- ============================================================================
--
-- End-of-level sequence that processes surviving towers through a systematic
-- compacting and merging pipeline. Ensures optimal tower positioning while
-- maintaining tier progression unlocks and animation continuity.
--
-- SYSTEM FLOW:
-- 1. handleLevelCompletion() → convertBasicBubblesToCreeps() → finale battle
-- 2. checkForDefeat() → advanceToNextLevel() → startPostAttackSequence()
-- 3. collectLivingTowers() → gathers all surviving towers with metadata
-- 4. checkPostCompactMerges() → looks for immediate merge opportunities
-- 5. If merges found: process ONE merge → recursive back to step 4
-- 6. If no merges: startTowerCompacting() → animate leftward movement
-- 7. Tower compacting completes → continuePostMergeSequence() → back to step 4
-- 8. Repeat until no more moves/merges → finishLevelAdvancement()
--
-- SMART TOWER COMPACTING MECHANICS:
-- - Uses hex grid triangle system for Tier 1 positioning (Tier 2/3 stay in place)
-- - Prioritizes: 1) Leftward gain, 2) Same Y-level, 3) Minimal movement distance
-- - Maintains minimum spacing: TOWER_SPACING_BUFFER (10px between edges)
-- - Processes towers left-to-right to ensure correct collision order
-- - Properly updates both tower positions AND occupied hex cells
--
-- MERGE DETECTION RULES:
-- - Level-based unlocks: Tier 1 merges after level 1, Tier 2 after level 2
-- - Tier 1 + Tier 1 (different types) → Tier 2: TIER1_MERGE_DISTANCE (36px)
-- - Tier 2 + Tier 2 (compatible types) → Tier 3: TIER2_MERGE_DISTANCE (52px)
-- - Only ONE merge processed per cycle to maintain animation sequence integrity
-- - ALL animation types (tier2_magnetism, tier2_snap, tier3_magnetism) continue sequence
--
-- HEX GRID INTEGRATION:
-- - Tower positions calculated using existing triangle center logic
-- - Coordinates rounded like original tower placement (math.floor(center + 0.5))
-- - Occupied cells properly cleared from old positions and marked at new positions
-- - Basic ball spawning respects compacted tower positions
--
-- ANIMATION INTEGRATION:
-- - Uses existing animation system with "tower_compacting" type
-- - Smooth interpolation from current position to calculated target position
-- - Updates tower tracking tables AND hex cell states when animation completes
-- - Ensures animations complete before next sequence step begins
--
-- This system ensures optimal tower positioning for strategic gameplay while
-- maintaining visual polish through smooth animations and proper state management.

local MergeConstants = import("game/mergeConstants")

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Core constants
local BALL_SPEED <const> = 9
local COLLISION_RADIUS <const> = 20
local FLYING_BALL_RADIUS <const> = 17  -- Slightly reduced for better skill shots, but not too small
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
-- POST-ATTACK TOWER COMPACTING CONSTANTS
-- ============================================================================
-- Tower spacing and boundary calculations for end-of-level compacting

local TOWER_SPACING_BUFFER <const> = 2         -- Minimum px between tower edges during compacting
local CUTOUT_CLEARANCE_BASE <const> = 80       -- Base clearance for cutout boundary area
local CUTOUT_SAFETY_BUFFER <const> = 10        -- Additional safety buffer for cutout boundary
local BASIC_BOUNDARY_BUFFER <const> = 5        -- Safety buffer from left screen edge

-- Merge detection distances for post-attack combinations
local TIER1_MERGE_DISTANCE <const> = 36        -- Touching distance for Tier 1 towers (18+18 radii)
local TIER2_MERGE_DISTANCE <const> = 52        -- Touching distance for Tier 2 towers (26+26 radii)
local MAGNETIC_TIER1_DISTANCE <const> = 45     -- Tier 1 to Tier 2 magnetic combination range
local MAGNETIC_TIER2_DISTANCE <const> = 50     -- Tier 2 to Tier 2 magnetic combination range

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
local AVATAR_HP <const> = 1200                 -- Avatar hitpoints (Tier 2 tower + 50%)
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
local RAIN_DOTS_PER_FRAME <const> = 2          -- Number of dots spawned each frame (reduced for performance)
local RAIN_DOT_LIFETIME <const> = 6            -- Frames each dot lasts (reduced for performance)
local RAIN_DOT_DAMAGE <const> = 2              -- Damage per dot collision
local RAIN_INNER_RADIUS <const> = 10           -- Inner radius (tower radius)
local RAIN_OUTER_RADIUS <const> = 50           -- Outer radius (tower radius + 40px) - increased by 10px

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
local LIGHTNING_TOWER_RANGE <const> = 160       -- Legacy detection range (not used for targeting to avoid out-of-range locks)
local LIGHTNING_TOWER_COOLDOWN <const> = 8      -- Cooldown between sequences (was 6, slightly slower)
local LIGHTNING_BOLT_RANGE <const> = 75         -- Lightning bolt range AND targeting range (was 70, slightly longer)
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
        range = LIGHTNING_BOLT_RANGE, -- Use bolt range for consistency with targeting
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
    -- Simple ammo system: array of balls (15 per level)
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
    self.pendingPostCompactMergeCheck = false
    self.pendingContinuePostMerge = false
    self.gameOverFlashCount = 0
    self.flashTimer = 0
    
    -- Phase 2: Tier tracking systems
    self.tierOnePositions = {}  -- {idx -> {centerX, centerY, ballType, triangle}}
    self.tierTwoPositions = {}  -- {idx -> {centerX, centerY, sprite, pattern}}
    self.tierThreePositions = {} -- {idx -> {centerX, centerY, sprite, pattern}}
    self.avatars = {} -- {id -> {x, y, sprite, hitpoints, targetX, targetY, attackCooldown, state}}
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

-- Get level-specific starting grid pattern (shared between all setup functions)
function Grid:getLevelStartingPattern(level)
    local prePlacedCells = {}
    
    -- Progressive starting grids based on level (cumulative additions)
    if level == 1 then
        -- Level 1: Base grid
        prePlacedCells = {
            {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"}, {{3,1}, "A"}, {{3,2}, "A"}, {{3,3}, "A"},
            {{4,1}, "B"}, {{4,2}, "B"}, {{4,3}, "B"}, {{5,3}, "B"}, {{5,4}, "B"},
            {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"}, {{11,1}, "E"}, {{11,2}, "E"}, {{11,3}, "E"},
            {{10,1}, "D"}, {{10,2}, "D"}, {{10,3}, "D"}, {{9,3}, "D"}, {{9,4}, "D"},
            {{6,3}, "A"}, {{6,4}, "A"}, {{7,4}, "A"}, {{7,5}, "A"}, {{8,3}, "A"}, {{8,4}, "A"},
            {{6,5}, "E"}, {{6,6}, "E"}, {{7,6}, "E"}, {{7,7}, "E"}, {{8,5}, "E"}, {{8,6}, "E"},
        }
    elseif level == 2 then
        -- Level 2: Base grid + additional groups
        prePlacedCells = {
            -- Level 1 base
            {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"}, {{3,1}, "A"}, {{3,2}, "A"}, {{3,3}, "A"},
            {{4,1}, "B"}, {{4,2}, "B"}, {{4,3}, "B"}, {{5,3}, "B"}, {{5,4}, "B"},
            {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"}, {{11,1}, "E"}, {{11,2}, "E"}, {{11,3}, "E"},
            {{10,1}, "D"}, {{10,2}, "D"}, {{10,3}, "D"}, {{9,3}, "D"}, {{9,4}, "D"},
            {{6,3}, "A"}, {{6,4}, "A"}, {{7,4}, "A"}, {{7,5}, "A"}, {{8,3}, "A"}, {{8,4}, "A"},
            {{6,5}, "E"}, {{6,6}, "E"}, {{7,6}, "E"}, {{7,7}, "E"}, {{8,5}, "E"}, {{8,6}, "E"},
            -- Level 2 additions
            {{1,3}, "E"}, {{1,4}, "E"}, {{2,3}, "E"}, {{2,4}, "E"},
            {{3,4}, "D"}, {{3,5}, "D"}, {{4,4}, "D"}, {{4,5}, "D"}, {{5,5}, "D"}, {{5,6}, "D"},
            {{13,3}, "A"}, {{13,4}, "A"}, {{12,3}, "A"}, {{12,4}, "A"},
            {{11,4}, "B"}, {{11,5}, "B"}, {{10,4}, "B"}, {{10,5}, "B"}, {{9,5}, "B"}, {{9,6}, "B"},
        }
    elseif level == 3 then
        -- Level 3: Levels 1-2 + new additions
        prePlacedCells = {
            -- Levels 1-2 base
            {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"}, {{3,1}, "A"}, {{3,2}, "A"}, {{3,3}, "A"},
            {{4,1}, "B"}, {{4,2}, "B"}, {{4,3}, "B"}, {{5,3}, "B"}, {{5,4}, "B"},
            {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"}, {{11,1}, "E"}, {{11,2}, "E"}, {{11,3}, "E"},
            {{10,1}, "D"}, {{10,2}, "D"}, {{10,3}, "D"}, {{9,3}, "D"}, {{9,4}, "D"},
            {{6,3}, "A"}, {{6,4}, "A"}, {{7,4}, "A"}, {{7,5}, "A"}, {{8,3}, "A"}, {{8,4}, "A"},
            {{6,5}, "E"}, {{6,6}, "E"}, {{7,6}, "E"}, {{7,7}, "E"}, {{8,5}, "E"}, {{8,6}, "E"},
            {{1,3}, "E"}, {{1,4}, "E"}, {{2,3}, "E"}, {{2,4}, "E"},
            {{3,4}, "D"}, {{3,5}, "D"}, {{4,4}, "D"}, {{4,5}, "D"}, {{5,5}, "D"}, {{5,6}, "D"},
            {{13,3}, "A"}, {{13,4}, "A"}, {{12,3}, "A"}, {{12,4}, "A"},
            {{11,4}, "B"}, {{11,5}, "B"}, {{10,4}, "B"}, {{10,5}, "B"}, {{9,5}, "B"}, {{9,6}, "B"},
            -- Level 3 additions
            {{6,9}, "C"}, {{6,10}, "C"}, {{7,10}, "C"}, {{7,11}, "C"}, {{8,9}, "C"}, {{8,10}, "C"},
            {{6,7}, "C"}, {{6,8}, "C"}, {{7,8}, "C"}, {{7,9}, "C"}, {{10,7}, "C"}, {{10,8}, "C"},
        }
    elseif level == 4 then
        -- Level 4: Levels 1-3 + new additions
        prePlacedCells = {
            -- Levels 1-3 base
            {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"}, {{3,1}, "A"}, {{3,2}, "A"}, {{3,3}, "A"},
            {{4,1}, "B"}, {{4,2}, "B"}, {{4,3}, "B"}, {{5,3}, "B"}, {{5,4}, "B"},
            {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"}, {{11,1}, "E"}, {{11,2}, "E"}, {{11,3}, "E"},
            {{10,1}, "D"}, {{10,2}, "D"}, {{10,3}, "D"}, {{9,3}, "D"}, {{9,4}, "D"},
            {{6,3}, "A"}, {{6,4}, "A"}, {{7,4}, "A"}, {{7,5}, "A"}, {{8,3}, "A"}, {{8,4}, "A"},
            {{6,5}, "E"}, {{6,6}, "E"}, {{7,6}, "E"}, {{7,7}, "E"}, {{8,5}, "E"}, {{8,6}, "E"},
            {{1,3}, "E"}, {{1,4}, "E"}, {{2,3}, "E"}, {{2,4}, "E"},
            {{3,4}, "D"}, {{3,5}, "D"}, {{4,4}, "D"}, {{4,5}, "D"}, {{5,5}, "D"}, {{5,6}, "D"},
            {{13,3}, "A"}, {{13,4}, "A"}, {{12,3}, "A"}, {{12,4}, "A"},
            {{11,4}, "B"}, {{11,5}, "B"}, {{10,4}, "B"}, {{10,5}, "B"}, {{9,5}, "B"}, {{9,6}, "B"},
            {{6,9}, "C"}, {{6,10}, "C"}, {{7,10}, "C"}, {{7,11}, "C"}, {{8,9}, "C"}, {{8,10}, "C"},
            {{6,7}, "C"}, {{6,8}, "C"}, {{7,8}, "C"}, {{7,9}, "C"}, {{10,7}, "C"}, {{10,8}, "C"},
            -- Level 4 additions
            {{1,9}, "C"}, {{1,10}, "C"}, {{1,11}, "C"}, {{2,9}, "C"}, {{2,10}, "C"},
            {{13,9}, "C"}, {{13,10}, "C"}, {{13,11}, "C"}, {{12,9}, "C"}, {{12,10}, "C"},
        }
    else
        -- Level 5+: Levels 1-4 + final additions
        prePlacedCells = {
            -- Levels 1-4 base
            {{1,1}, "A"}, {{1,2}, "A"}, {{2,1}, "A"}, {{2,2}, "A"}, {{3,1}, "A"}, {{3,2}, "A"}, {{3,3}, "A"},
            {{4,1}, "B"}, {{4,2}, "B"}, {{4,3}, "B"}, {{5,3}, "B"}, {{5,4}, "B"},
            {{13,1}, "E"}, {{13,2}, "E"}, {{12,1}, "E"}, {{12,2}, "E"}, {{11,1}, "E"}, {{11,2}, "E"}, {{11,3}, "E"},
            {{10,1}, "D"}, {{10,2}, "D"}, {{10,3}, "D"}, {{9,3}, "D"}, {{9,4}, "D"},
            {{6,3}, "A"}, {{6,4}, "A"}, {{7,4}, "A"}, {{7,5}, "A"}, {{8,3}, "A"}, {{8,4}, "A"},
            {{6,5}, "E"}, {{6,6}, "E"}, {{7,6}, "E"}, {{7,7}, "E"}, {{8,5}, "E"}, {{8,6}, "E"},
            {{1,3}, "E"}, {{1,4}, "E"}, {{2,3}, "E"}, {{2,4}, "E"},
            {{3,4}, "D"}, {{3,5}, "D"}, {{4,4}, "D"}, {{4,5}, "D"}, {{5,5}, "D"}, {{5,6}, "D"},
            {{13,3}, "A"}, {{13,4}, "A"}, {{12,3}, "A"}, {{12,4}, "A"},
            {{11,4}, "B"}, {{11,5}, "B"}, {{10,4}, "B"}, {{10,5}, "B"}, {{9,5}, "B"}, {{9,6}, "B"},
            {{6,9}, "C"}, {{6,10}, "C"}, {{7,10}, "C"}, {{7,11}, "C"}, {{8,9}, "C"}, {{8,10}, "C"},
            {{6,7}, "C"}, {{6,8}, "C"}, {{7,8}, "C"}, {{7,9}, "C"}, {{10,7}, "C"}, {{10,8}, "C"},
            {{1,9}, "C"}, {{1,10}, "C"}, {{1,11}, "C"}, {{2,9}, "C"}, {{2,10}, "C"},
            {{13,9}, "C"}, {{13,10}, "C"}, {{13,11}, "C"}, {{12,9}, "C"}, {{12,10}, "C"},
            -- Level 5+ additions
            {{4,6}, "A"}, {{4,7}, "A"}, {{5,7}, "A"}, {{5,8}, "A"},
            {{9,7}, "A"}, {{9,8}, "A"}, {{10,6}, "A"}, {{10,7}, "A"},
        }
    end
    
    return prePlacedCells
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
    
    -- Get level-specific pattern from shared function (eliminates code duplication)
    local prePlacedCells = self:getLevelStartingPattern(self.currentLevel)
    
    -- Place all bubble types on the grid based on the pattern
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
--]]

-- Initialize starting grid with pre-placed bubbles that respects preserved towers
function Grid:setupStartingBallsWithTowerPreservation()
    print("DEBUG: Setting up basic bubbles for level " .. self.currentLevel)
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
    
    -- Get level-specific pattern from shared function (eliminates code duplication)
    local prePlacedCells = self:getLevelStartingPattern(self.currentLevel)
    
    -- Place all bubble types on the grid based on the pattern, but skip if towers exist
    for _, cellData in ipairs(prePlacedCells) do
        local pos = cellData[1]
        local letter = cellData[2]
        local row, col = pos[1], pos[2]
        
        if self:isValidGridPosition(row, col) then
            local idx = (row - 1) * 20 + col
            if self.cells[idx] and not self.cells[idx].permanent then
                -- Check if a tower already occupies this position - if so, skip
                local hasTower = false
                for _, tower in pairs(self.tierOnePositions) do
                    if tower.triangle then
                        for _, triangleIdx in ipairs(tower.triangle) do
                            if triangleIdx == idx then
                                hasTower = true
                                break
                            end
                        end
                    end
                end
                
                for _, tower in pairs(self.tierTwoPositions) do
                    if tower.pattern then
                        for _, patternIdx in ipairs(tower.pattern) do
                            if patternIdx == idx then
                                hasTower = true
                                break
                            end
                        end
                    end
                end
                
                -- Also check if cell is already occupied
                if self.cells[idx].occupied then
                    hasTower = true
                end
                
                if not hasTower then
                    self.cells[idx].ballType = letterTypes[letter]
                    self.cells[idx].occupied = true
                    self.cells[idx].tier = "basic"
                end
            end
        end
    end
    print("DEBUG: Basic bubble setup complete for level " .. self.currentLevel)
end

-- DUPLICATE FUNCTION REMOVED

-- Simple ammo system helpers
function Grid:getCurrentShooterBall()
    if self.currentShotIndex <= #self.ammo then
        return self.ammo[self.currentShotIndex]
    end
    return nil
end

function Grid:getOnDeckBall()
    if self.currentShotIndex < #self.ammo then
        return self.ammo[self.currentShotIndex + 1]
    end
    return nil
end

function Grid:getShotsRemaining()
    return math.max(0, #self.ammo - self.currentShotIndex + 1)
end

-- Handle level completion: trigger finale for all levels
function Grid:handleLevelCompletion()
    -- Always trigger finale sequence (conversion and battle) for all levels
    self:convertBasicBubblesToCreeps()
end

-- Advance to next level with tower preservation and grid overlay
function Grid:advanceToNextLevel()
    print("DEBUG: advanceToNextLevel() called - advancing from level " .. self.currentLevel .. " to " .. (self.currentLevel + 1))
    self.currentLevel = self.currentLevel + 1
    
    -- Add 15 shots to the counter
    for i = 1, 15 do
        self.ammo[#self.ammo + 1] = math.random(1, 5)
    end
    -- Note: currentShotIndex stays the same to continue from current position
    
    -- NEW: Start the post-attack compacting sequence instead of immediate preservation
    print("DEBUG: Starting post-attack sequence for level " .. self.currentLevel)
    self:startPostAttackSequence()
end

-- NEW: Start the complete post-attack sequence: compact → settle → merge → repeat
-- Post-Attack Tower Compacting System
-- Initiates the end-of-level sequence where towers move left until hitting boundaries
-- or other towers, settle into position, then check for merges recursively
-- @return void - Continues asynchronously through animation system
function Grid:startPostAttackSequence()
    print("DEBUG: startPostAttackSequence() called for level " .. self.currentLevel)
    -- Set flag to indicate we're in post-attack sequence
    print("DEBUG: Setting isPostAttackSequence = true")
    self.isPostAttackSequence = true
    
    -- Store living towers for compacting
    local livingTowers = self:collectLivingTowers()
    print("DEBUG: Found " .. #livingTowers .. " living towers to compact")
    
    if #livingTowers == 0 then
        -- No towers to compact, proceed directly to level setup
        print("DEBUG: No towers to compact, proceeding directly to finishLevelAdvancement()")
        print("DEBUG: Setting isPostAttackSequence = false")
        self.isPostAttackSequence = false -- Clear the flag
        self:finishLevelAdvancement()
        return
    end
    
    -- First check for immediate merges with newly unlocked abilities
    self:checkPostCompactMerges()
end

-- Tower Collection for Post-Attack Processing
-- Scans all tier positions and builds a unified list of living towers with metadata
-- @return table - Array of tower objects with type, idx, data, centerX, centerY fields
function Grid:collectLivingTowers()
    local towers = {}
    
    -- Collect Tier 1 towers
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then
            towers[#towers + 1] = {
                type = "tier1",
                idx = idx,
                data = tower,
                centerX = tower.centerX,
                centerY = tower.centerY
            }
        end
    end
    
    -- Collect Tier 2 towers
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then
            towers[#towers + 1] = {
                type = "tier2", 
                idx = idx,
                data = tower,
                centerX = tower.centerX,
                centerY = tower.centerY
            }
        end
    end
    
    -- Collect Tier 3 towers
    for idx, tower in pairs(self.tierThreePositions) do
        if tower.hitpoints > 0 then
            towers[#towers + 1] = {
                type = "tier3",
                idx = idx, 
                data = tower,
                centerX = tower.centerX,
                centerY = tower.centerY
            }
        end
    end
    
    return towers
end

-- Start tower compacting animation: shift all towers left until they hit edge or another tower
-- Tower Compacting Animation System
-- Initiates leftward movement animations for all towers until they hit boundaries or each other
-- Processes towers left-to-right to ensure proper collision detection order
-- @param towers table - Array of tower objects from collectLivingTowers()
-- @return void - Sets up animations that complete asynchronously
function Grid:startTowerCompacting(towers)
    print("DEBUG: startTowerCompacting() called with " .. #towers .. " towers")
    if self.isAnimating then 
        print("DEBUG: Still animating, deferring tower compacting")
        return 
    end
    
    -- Sort towers by X position (leftmost first) to compact from left to right
    table.sort(towers, function(a, b) return a.centerX < b.centerX end)
    
    local compactingTowers = {}
    local compactedPositions = {} -- Track new positions for collision checking
    
    for i, tower in ipairs(towers) do
        -- Calculate new compacted position (shift left until hitting boundary or another tower)
        local newX, newY, newTriangle = self:calculateCompactedPosition(tower, towers, i, compactedPositions)
        compactedPositions[i] = {x = newX, y = newY} -- Store new position for subsequent towers
        
        local moveDist = math.sqrt((newX - tower.centerX)^2 + (newY - tower.centerY)^2)
        if moveDist > 1 then -- Only animate if significant movement
            compactingTowers[#compactingTowers + 1] = {
                tower = tower,
                startX = tower.centerX,
                startY = tower.centerY,
                endX = newX,
                endY = newY, -- Allow Y movement for hex grid repositioning
                newTriangle = newTriangle, -- Store new triangle for cell updates
                frame = 0
            }
        end
    end
    
    if #compactingTowers > 0 then
        self.animations[#self.animations + 1] = {
            type = "tower_compacting",
            towers = compactingTowers,
            frame = 0
        }
        print("DEBUG: Starting tower compacting animations for " .. #compactingTowers .. " towers")
        self.isAnimating = true
    else
        -- No compacting needed, finish the post-attack sequence
        print("DEBUG: No compacting needed, finishing post-attack sequence immediately")
        print("DEBUG: Setting isPostAttackSequence = false")
        self.isPostAttackSequence = false
        self:finishLevelAdvancement()
    end
end

-- Calculate the leftmost valid position for a tower during compacting
-- Tower Position Collision Calculator
-- Determines the leftmost safe position for a tower considering boundaries and other towers
-- Respects both the cutout boundary and maintains minimum spacing between towers
-- @param tower table - Tower object with centerX, centerY, type fields
-- @param allTowers table - Complete array of towers being processed
-- @param currentIndex number - Index of current tower in the sorted array
-- @param compactedPositions table - Previously calculated positions for towers 1..currentIndex-1
-- @return number - New X coordinate for the tower's center position
function Grid:calculateCompactedPosition(tower, allTowers, currentIndex, compactedPositions)
    
    -- Find the leftmost valid position for this tower type
    local bestPosition = self:findLeftmostValidTowerPosition(tower, allTowers, currentIndex, compactedPositions)
    
    if bestPosition then
        -- Only move if the new position is to the left (less X) than current position
        if bestPosition.x < tower.centerX then
            return bestPosition.x, bestPosition.y, bestPosition.triangle
        else
            return tower.centerX, tower.centerY, nil
        end
    else
        return tower.centerX, tower.centerY, nil
    end
end

-- Find the best leftward position for a tower that minimizes movement
function Grid:findLeftmostValidTowerPosition(tower, allTowers, currentIndex, compactedPositions)
    -- Get all valid positions for this tower type
    local validPositions = {}
    
    if tower.type == "tier1" then
        validPositions = self:findValidTier1Positions()
    elseif tower.type == "tier2" then
        validPositions = self:findValidTier2Positions()
    elseif tower.type == "tier3" then
        validPositions = self:findValidTier3Positions()
    end
    
    -- Filter positions that are to the left and don't collide with other towers
    local validLeftwardPositions = {}
    for _, pos in ipairs(validPositions) do
        -- Only consider positions to the left of current position
        if pos.x < tower.centerX then
            local canPlace = true
            
            -- Check collision with other towers (using their compacted positions)
            for i = 1, currentIndex - 1 do
                local otherTower = allTowers[i]
                local otherX, otherY
                if compactedPositions[i] then
                    otherX = compactedPositions[i].x
                    otherY = compactedPositions[i].y
                else
                    otherX = otherTower.centerX
                    otherY = otherTower.centerY
                end
                
                local distance = self:getDistance(pos.x, pos.y, otherX, otherY)
                local requiredDistance = self:getTowerRadius(tower.type) + self:getTowerRadius(otherTower.type) + TOWER_SPACING_BUFFER
                
                if distance < requiredDistance then
                    canPlace = false
                    break
                end
            end
            
            if canPlace then
                -- Calculate movement distance and leftward benefit
                local movementDistance = self:getDistance(pos.x, pos.y, tower.centerX, tower.centerY)
                local leftwardGain = tower.centerX - pos.x
                
                validLeftwardPositions[#validLeftwardPositions + 1] = {
                    x = pos.x,
                    y = pos.y,
                    triangle = pos.triangle,
                    movementDistance = movementDistance,
                    leftwardGain = leftwardGain,
                    -- Prefer positions at same Y level
                    sameLevelPenalty = math.abs(pos.y - tower.centerY)
                }
            end
        end
    end
    
    if #validLeftwardPositions == 0 then
        return nil
    end
    
    -- Sort by priorities: 
    -- 1. Maximize leftward gain (more important)
    -- 2. Minimize Y level change (prefer horizontal movement)  
    -- 3. Minimize total movement distance
    table.sort(validLeftwardPositions, function(a, b)
        -- First priority: leftward gain (bigger is better)
        if math.abs(a.leftwardGain - b.leftwardGain) > 5 then
            return a.leftwardGain > b.leftwardGain
        end
        
        -- Second priority: same Y level (smaller penalty is better)
        if math.abs(a.sameLevelPenalty - b.sameLevelPenalty) > 10 then
            return a.sameLevelPenalty < b.sameLevelPenalty
        end
        
        -- Third priority: minimize movement distance
        return a.movementDistance < b.movementDistance
    end)
    
    return validLeftwardPositions[1]
end

-- Get the safe minimum X position for a tower at given Y, respecting cutout boundary
-- Boundary-Aware Minimum Position Calculator
-- Calculates the leftmost safe X coordinate considering both screen edge and cutout areas
-- Different Y ranges require different clearances due to the hex grid's cutout shape
-- @param centerY number - Y coordinate of tower center
-- @param towerRadius number - Radius of the tower sprite (half of sprite width)
-- @return number - Minimum safe X coordinate for tower placement
function Grid:getSafeMinimumX(centerY, towerRadius)
    local basicMinX = LEFT_BOUNDARY + towerRadius + BASIC_BOUNDARY_BUFFER
    
    -- Check if Y position intersects with cutout area 
    -- Cutout cells: rows 5-9 (Y ~80-160), columns 1-3 (X ~30-70)
    -- Only apply cutout clearance to the actual cutout Y range
    if centerY >= 80 and centerY <= 160 then
        -- This Y level intersects the cutout, need more clearance
        -- Cutout extends to column 3 (~X=70), plus tower radius, plus safety buffer
        local cutoutClearance = CUTOUT_CLEARANCE_BASE + towerRadius + CUTOUT_SAFETY_BUFFER
        return math.max(basicMinX, cutoutClearance)
    end
    
    return basicMinX
end

-- Find all valid Tier 1 positions (triangle centers) in the hex grid
function Grid:findValidTier1Positions()
    local validPositions = {}
    
    -- Scan all hex cells to find valid triangle formations
    for idx, cell in pairs(self.cells) do
        if not cell.occupied and not cell.permanent then
            local neighbors = self:getNeighbors(idx)
            if #neighbors >= 6 then
                -- Define all 6 possible pie slice triangles (same as original placement logic)
                local pieSlices = {
                    {idx, neighbors[2], neighbors[4]}, -- 0° right
                    {idx, neighbors[1], neighbors[2]}, -- 60° up-right  
                    {idx, neighbors[3], neighbors[1]}, -- 120° up-left
                    {idx, neighbors[5], neighbors[3]}, -- 180° left
                    {idx, neighbors[6], neighbors[5]}, -- 240° down-left
                    {idx, neighbors[4], neighbors[6]}  -- 300° down-right
                }
                
                -- Test each triangle for validity
                for _, triangle in ipairs(pieSlices) do
                    local isValid = true
                    for _, triangleIdx in ipairs(triangle) do
                        if self.cells[triangleIdx] and (self.cells[triangleIdx].occupied or self.cells[triangleIdx].permanent) then
                            isValid = false
                            break
                        end
                    end
                    
                    if isValid then
                        -- Calculate triangle center (same as getTriangleCenter)
                        local center = self:getTriangleCenter(triangle)
                        -- Round coordinates like original tower placement does
                        local roundedX = math.floor(center.x + 0.5)
                        local roundedY = math.floor(center.y + 0.5)
                        validPositions[#validPositions + 1] = {x = roundedX, y = roundedY, triangle = triangle}
                    end
                end
            end
        end
    end
    
    return validPositions
end

-- Find all valid Tier 2 positions (2-3-2 pattern centers) in the hex grid
function Grid:findValidTier2Positions()
    -- Tier 2 compacting not yet implemented - towers stay in current position
    return {}
end

-- Find all valid Tier 3 positions in the hex grid  
function Grid:findValidTier3Positions()
    -- Tier 3 compacting not yet implemented - towers stay in current position
    return {}
end

-- Get tower radius for collision detection
function Grid:getTowerRadius(towerType)
    if towerType == "tier1" then
        return 16 -- Slightly less than 36px/2 for tighter packing
    elseif towerType == "tier2" then
        return 24 -- Slightly less than 52px/2 for tighter packing
    elseif towerType == "tier3" then
        return 40 -- Slightly less than 84px/2 for tighter packing
    end
    return 10 -- fallback
end

-- Check for merges after compacting: Tier 1s first, then Tier 2s
-- Post-Attack Merge Detection and Processing
-- Checks for valid tower merges after compacting, respecting level-based unlocks
-- Processes one merge at a time to maintain animation sequence integrity
-- @return void - Either triggers merge animation or continues to tower compacting
function Grid:checkPostCompactMerges()
    if self.isAnimating then 
        return 
    end
    
    -- Tier 1 merges are unlocked after level 1
    if self.currentLevel > 1 then
        local tier1Merge = self:findPostCompactTier1Merge()
        if tier1Merge then
            print("DEBUG: Found Tier 1 merge, starting magnetism")
            self:startTierTwoMagnetism(tier1Merge.t1, tier1Merge.t2)
            return -- Process one merge at a time
        end
    end
    
    -- Tier 2 merges are unlocked after level 2
    if self.currentLevel > 2 then
        local tier2Merge = self:findPostCompactTier2Merge()
        if tier2Merge then
            print("DEBUG: Found Tier 2 merge, starting magnetism")
            self:startTierThreeMagnetism(tier2Merge.t2a, tier2Merge.t2b, tier2Merge.sprite)
            return -- Process one merge at a time
        end
    end
    -- No immediate merges found, proceed to compacting
    local livingTowers = self:collectLivingTowers()
    if #livingTowers > 0 then
        self:startTowerCompacting(livingTowers)
    else
        -- No towers left, finish level advancement
        print("DEBUG: Finishing level advancement")
        self.isPostAttackSequence = false -- Clear the flag
        self:finishLevelAdvancement()
    end
end

-- Find first valid Tier 1 merge after compacting
function Grid:findPostCompactTier1Merge()
    local tierOnes = {}
    
    -- Collect all Tier 1 towers
    for idx, tierOneData in pairs(self.tierOnePositions) do
        tierOnes[#tierOnes + 1] = {
            idx = idx,
            ballType = tierOneData.ballType,
            centerX = tierOneData.centerX,
            centerY = tierOneData.centerY,
            triangle = tierOneData.triangle
        }
    end
    
    -- Check for magnetic combinations (touching distance)
    for i = 1, #tierOnes do
        for j = i + 1, #tierOnes do
            local t1, t2 = tierOnes[i], tierOnes[j]
            if t1.ballType ~= t2.ballType then -- Different types required for Tier 2
                local distance = self:getDistance(t1.centerX, t1.centerY, t2.centerX, t2.centerY)
                if distance <= TIER1_MERGE_DISTANCE then -- Touching distance for Tier 1 towers
                    return {t1 = t1, t2 = t2}
                end
            end
        end
    end
    
    return nil
end

-- Find first valid Tier 2 merge after compacting
function Grid:findPostCompactTier2Merge()
    local tierTwos = {}
    
    -- Collect all Tier 2 towers
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        tierTwos[#tierTwos + 1] = {
            idx = idx,
            sprite = tierTwoData.sprite,
            centerX = tierTwoData.centerX,
            centerY = tierTwoData.centerY,
            pattern = tierTwoData.pattern
        }
    end
    
    -- Check for Tier 3 combinations (touching distance)
    for i = 1, #tierTwos do
        for j = i + 1, #tierTwos do
            local t2a, t2b = tierTwos[i], tierTwos[j]
            local tier3Sprite = MergeConstants.getTierThreeSprite(t2a.sprite, t2b.sprite)
            
            if tier3Sprite then
                local distance = self:getDistance(t2a.centerX, t2a.centerY, t2b.centerX, t2b.centerY)
                if distance <= TIER2_MERGE_DISTANCE then -- Touching distance for Tier 2 towers
                    return {t2a = t2a, t2b = t2b, sprite = tier3Sprite}
                end
            end
        end
    end
    
    return nil
end

-- Override the normal magnetic checking after merges to continue compacting sequence
function Grid:continuePostMergeSequence()
    print("DEBUG: continuePostMergeSequence() called")
    
    -- If still animating, defer this call until animations complete
    if self.isAnimating then
        print("DEBUG: Still animating, setting flag to continue post-merge sequence when ready")
        self.pendingContinuePostMerge = true
        return
    end
    
    -- After a merge completes, restart the compacting sequence
    local livingTowers = self:collectLivingTowers()
    print("DEBUG: Found " .. #livingTowers .. " living towers after merge")
    
    if #livingTowers > 0 then
        -- Compact again after the merge
        print("DEBUG: Restarting tower compacting after merge")
        self:startTowerCompacting(livingTowers)
    else
        -- No towers left, finish level advancement
        print("DEBUG: No towers left after merge, finishing level advancement")
        print("DEBUG: Setting isPostAttackSequence = false")
        self.isPostAttackSequence = false -- Clear the flag
        self:finishLevelAdvancement()
    end
end

-- Original level advancement logic, now called after compacting sequence completes
function Grid:finishLevelAdvancement()
    print("DEBUG: finishLevelAdvancement() called for level " .. self.currentLevel)
    -- Store current tower positions for preservation
    local preservedTierOnePositions = {}
    local preservedTierTwoPositions = {}
    local preservedTierThreePositions = {}
    
    -- Copy living towers to preserved tables
    for idx, tower in pairs(self.tierOnePositions) do
        if tower.hitpoints > 0 then
            preservedTierOnePositions[idx] = tower
        end
    end
    for idx, tower in pairs(self.tierTwoPositions) do
        if tower.hitpoints > 0 then
            preservedTierTwoPositions[idx] = tower
        end
    end
    for idx, tower in pairs(self.tierThreePositions) do
        if tower.hitpoints > 0 then
            preservedTierThreePositions[idx] = tower
        end
    end
    
    -- Count preserved towers
    local t1Count, t2Count, t3Count = 0, 0, 0
    for _ in pairs(preservedTierOnePositions) do t1Count = t1Count + 1 end
    for _ in pairs(preservedTierTwoPositions) do t2Count = t2Count + 1 end
    for _ in pairs(preservedTierThreePositions) do t3Count = t3Count + 1 end
    print("DEBUG: Preserved " .. t1Count .. " T1, " .. t2Count .. " T2, " .. t3Count .. " T3 towers")
    
    -- Clear existing grid (except permanent boundaries and preserved towers)
    for idx, cell in pairs(self.cells) do
        if not cell.permanent then
            -- Check if this cell is occupied by a preserved tower
            local isPreservedTower = false
            
            -- Check tier one towers
            if preservedTierOnePositions[idx] then
                isPreservedTower = true
            end
            
            -- Check tier two tower patterns
            for towerIdx, tower in pairs(preservedTierTwoPositions) do
                if tower.pattern then
                    for _, patternIdx in ipairs(tower.pattern) do
                        if patternIdx == idx then
                            isPreservedTower = true
                            break
                        end
                    end
                end
            end
            
            -- Check tier three tower patterns
            for towerIdx, tower in pairs(preservedTierThreePositions) do
                if tower.pattern then
                    for _, patternIdx in ipairs(tower.pattern) do
                        if patternIdx == idx then
                            isPreservedTower = true
                            break
                        end
                    end
                end
            end
            
            -- Only clear cells that don't have preserved towers
            if not isPreservedTower then
                cell.occupied = false
                cell.ballType = nil
                cell.tier = nil
            end
        end
    end
    
    -- Restore preserved towers
    self.tierOnePositions = preservedTierOnePositions
    self.tierTwoPositions = preservedTierTwoPositions
    self.tierThreePositions = preservedTierThreePositions
    
    -- Clear units and combat systems for fresh start
    self.creeps = {}
    self.troops = {}
    self.avatars = {}
    self.projectiles = {}
    self.rainDots = {}
    self.lightningEffects = {}
    self.stagingOccupied = {}
    self.rallyPointOccupied = {}
    
    -- Reset combat systems
    self.finalAttackTriggered = false
    self.finalAttackDelay = nil
    self.finaleTriggered = false
    self.finaleCountdown = nil
    self.troopShotCounter = 0
    self.troopMarchActive = false
    
    -- Setup new starting grid that respects preserved towers
    print("DEBUG: Calling setupStartingBallsWithTowerPreservation() for level " .. self.currentLevel)
    self:setupStartingBallsWithTowerPreservation()
    print("DEBUG: finishLevelAdvancement() complete for level " .. self.currentLevel)
end

-- Check for victory condition or level advancement after all creeps defeated
function Grid:checkForVictory()
    local creepCount = #self.creeps
    local finalAttack = self.finalAttackTriggered
    local hasConverted = self:hasConvertedCreeps()
    
    
    if creepCount == 0 then
        -- Two victory paths:
        -- Path A: Regular combat creeps defeated (no converted creeps exist)
        -- Path B: Finale converted creeps defeated (finalAttackTriggered required)
        
        local shouldAdvance = false
        
        if not hasConverted then
            -- Path A: Regular combat victory - no converted creeps, advance immediately
            shouldAdvance = true
        elseif finalAttack then
            -- Path B: Finale victory - all converted creeps defeated after final attack
            shouldAdvance = true
        else
            -- Converted creeps exist but final attack not triggered yet - wait
        end
        
        if shouldAdvance then
            if self.currentLevel == 5 then
                -- Final victory on level 5
                print("DEBUG: Victory on level 5 - setting gameState to victory")
                self.gameState = "victory"
            elseif self.currentLevel == 1 then
                -- Level 1 completed - unlock Tier 2 towers
                print("DEBUG: Level 1 completed - setting gameState to tier2_unlock")
                self.gameState = "tier2_unlock"
                -- NOTE: Level advancement deferred until unlock screen confirmation
            elseif self.currentLevel == 2 then
                -- Level 2 completed - unlock Tier 3 towers
                print("DEBUG: Level 2 completed - setting gameState to tier3_unlock")
                self.gameState = "tier3_unlock"
                -- NOTE: Level advancement deferred until unlock screen confirmation
            else
                -- Regular level advancement (levels 3-4)
                print("DEBUG: Regular level advancement for level " .. self.currentLevel)
                self:advanceToNextLevel()
            end
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
    elseif self.gameState == "tier2_unlock" or self.gameState == "tier3_unlock" then
        if pd.buttonJustPressed(pd.kButtonA) then
            -- Continue to next level after unlock message
            print("DEBUG: A pressed during unlock screen, calling advanceToNextLevel()")
            self:advanceToNextLevel()
            print("DEBUG: Setting gameState to playing after unlock")
            self.gameState = "playing"
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
    
    -- DEBUG: Periodic status updates (reduced frequency)
    self.debugFrameCounter = (self.debugFrameCounter or 0) + 1
    if self.debugFrameCounter % 300 == 0 then  -- Every 5 seconds instead of 2
        print("DEBUG: Level " .. self.currentLevel .. ", Shot " .. self.currentShotIndex .. "/" .. #self.ammo .. 
              ", Creeps: " .. #self.creeps .. ", gameState: " .. self.gameState)
    end
    
    self:updateAnimations()
    self:updateCreeps()
    self:checkForFinalAttack()  -- Check if converted creeps are staged and ready for final attack
    self:updateTroops()
    self:updateAvatars()
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
                if distSq <= ((FLYING_BALL_RADIUS - 3) * (FLYING_BALL_RADIUS - 3)) then
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
        local tier1Radius = 25 -- 36/2 + 7 for reasonable collision
        if distSq <= (tier1Radius * tier1Radius) then
            return true
        end
    end
    
    -- Check tier 2 bubbles (collision with center point, 52x52 sprite)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        local dx = self.ball.x - tierTwoData.centerX
        local dy = self.ball.y - tierTwoData.centerY
        local distSq = dx * dx + dy * dy
        local tier2Radius = 33 -- 52/2 + 7 for reasonable collision
        if distSq <= (tier2Radius * tier2Radius) then
            return true
        end
    end
    
    -- Check tier 3 bubbles (collision with center point, 84x84 sprite)
    for idx, tierThreeData in pairs(self.tierThreePositions) do
        local dx = self.ball.x - tierThreeData.centerX
        local dy = self.ball.y - tierThreeData.centerY
        local distSq = dx * dx + dy * dy
        local tier3Radius = 49 -- 84/2 + 7 for reasonable collision
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
        
        -- Check if this was the final ball landing (all ammo used)
        if self.currentShotIndex > #self.ammo then
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
    local queueHead = 1
    
    while queueHead <= #queue do
        local idx = queue[queueHead]
        queueHead = queueHead + 1
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
                -- Note: No longer spawn troops when towers form - towers are the defensive units
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
                
                -- Check if this is part of post-attack sequence
                if self.isPostAttackSequence then
                    self:continuePostMergeSequence()
                end
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
                
                -- Note: No longer spawn troops when towers form - towers are the defensive units
                
                -- Check if this is part of post-attack sequence
                if self.isPostAttackSequence then
                    self:continuePostMergeSequence()
                end
                
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tier3_magnetism" then
            if progress >= 1.0 then
                -- Complete tier 3 magnetism - remove both tier 2 bubbles, create tier 3
                self:clearTierTwo(anim.tierTwoA)
                self:clearTierTwo(anim.tierTwoB)
                self:placeTierThree(anim.endX, anim.endY, anim.sprite)
                
                -- Check if this is part of post-attack sequence
                if self.isPostAttackSequence then
                    self:continuePostMergeSequence()
                end
                -- Don't keep this animation
            else
                activeAnimations[#activeAnimations + 1] = anim
            end
        elseif anim.type == "tower_compacting" then
            if progress >= 1.0 then
                -- Complete tower compacting - update tower positions to final locations
                for _, compactingTower in ipairs(anim.towers) do
                    local tower = compactingTower.tower
                    
                    -- Clear old cells that this tower was occupying
                    if tower.type == "tier1" and self.tierOnePositions[tower.idx] and self.tierOnePositions[tower.idx].triangle then
                        for _, idx in ipairs(self.tierOnePositions[tower.idx].triangle) do
                            if self.cells[idx] then
                                self.cells[idx].occupied = false
                                self.cells[idx].ballType = nil
                                self.cells[idx].tier = nil
                            end
                        end
                    end
                    -- TODO: Add similar logic for tier2 and tier3 when implemented
                    
                    -- Update tower position in appropriate tracking table
                    if tower.type == "tier1" then
                        self.tierOnePositions[tower.idx].centerX = compactingTower.endX
                        self.tierOnePositions[tower.idx].centerY = compactingTower.endY
                        
                        -- Update triangle cells if we have the new triangle from compacting
                        if compactingTower.newTriangle then
                            self.tierOnePositions[tower.idx].triangle = compactingTower.newTriangle
                            -- Mark new triangle cells as occupied
                            for _, triangleIdx in ipairs(compactingTower.newTriangle) do
                                if self.cells[triangleIdx] then
                                    self.cells[triangleIdx].occupied = true
                                    self.cells[triangleIdx].ballType = self.tierOnePositions[tower.idx].ballType
                                    self.cells[triangleIdx].tier = "tier1"
                                end
                            end
                        end
                    elseif tower.type == "tier2" then
                        self.tierTwoPositions[tower.idx].centerX = compactingTower.endX
                        self.tierTwoPositions[tower.idx].centerY = compactingTower.endY
                    elseif tower.type == "tier3" then
                        self.tierThreePositions[tower.idx].centerX = compactingTower.endX
                        self.tierThreePositions[tower.idx].centerY = compactingTower.endY
                    end
                end
                -- Set flag to check merges on next frame (after isAnimating is cleared)
                print("DEBUG: Tower compacting animation completed, setting pendingPostCompactMergeCheck = true")
                self.pendingPostCompactMergeCheck = true
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
                -- Create Avatar at tower position (waits for attack mode)
                local avatarId = #self.avatars + 1
                self.avatars[avatarId] = {
                    x = anim.centerX,
                    y = anim.centerY,
                    sprite = anim.sprite,
                    hitpoints = AVATAR_HP,
                    targetX = nil,
                    targetY = nil,
                    attackCooldown = 0,
                    state = "waiting", -- "waiting", "moving", "attacking"
                    lastShotTime = 0
                }
                
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
        
        -- Check for pending post-compact merge check
        if self.pendingPostCompactMergeCheck then
            print("DEBUG: Processing pendingPostCompactMergeCheck")
            self.pendingPostCompactMergeCheck = false
            self:checkPostCompactMerges()
        end
        
        -- Check for pending continue post-merge sequence
        if self.pendingContinuePostMerge then
            print("DEBUG: Processing pendingContinuePostMerge")
            self.pendingContinuePostMerge = false
            self:continuePostMergeSequence()
        end
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

-- Find best triangle for tier 1 placement (generous approach)
function Grid:findBestTriangleForTierOne(centerX, centerY)
    -- Find multiple candidate cells near the merge center - much wider search
    local candidates = self:findNearestValidCells(centerX, centerY, 15)
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
            
            -- Test each pie slice for validity (GENEROUS: allow stomping basic bubbles)
            for _, slice in ipairs(pieSlices) do
                local isValid = true
                local blockingTowers = {}
                
                for _, idx in ipairs(slice.triangle) do
                    if not self.positions[idx] or self.cells[idx].permanent then
                        isValid = false
                        break
                    end
                    -- Check for blocking towers (Tier 1+)
                    if self.cells[idx].occupied and (self.cells[idx].tier == "tier1" or self.cells[idx].tier == "tier2" or self.cells[idx].tier == "tier3") then
                        blockingTowers[#blockingTowers + 1] = idx
                    end
                end
                
                if isValid then
                    -- Calculate triangle center and distance to merge center
                    local triangleCenter = self:getTriangleCenter(slice.triangle)
                    local dx = centerX - triangleCenter.x
                    local dy = centerY - triangleCenter.y
                    local dist = dx * dx + dy * dy
                    
                    -- Penalty for displacing existing towers (prefer clean placement)
                    local penalty = 0
                    for _, blockingIdx in ipairs(blockingTowers) do
                        if self.cells[blockingIdx].tier == "tier3" then
                            penalty = penalty + 4000  -- Heavy penalty for Tier 3
                        elseif self.cells[blockingIdx].tier == "tier2" then
                            penalty = penalty + 2000  -- Medium penalty for Tier 2
                        elseif self.cells[blockingIdx].tier == "tier1" then
                            penalty = penalty + 800   -- Light penalty for same-tier
                        end
                    end
                    
                    allValidTriangles[#allValidTriangles + 1] = {
                        triangle = slice.triangle,
                        center = triangleCenter,
                        dist = dist + penalty,
                        candidateIdx = candidateIdx,
                        blockingTowers = blockingTowers
                    }
                end
            end
        end
    end
    
    -- Choose triangle with center closest to merge center (with penalties)
    local bestTriangle = nil
    if #allValidTriangles > 0 then
        table.sort(allValidTriangles, function(a, b) return a.dist < b.dist end)
        bestTriangle = allValidTriangles[1].triangle
        
        -- Clear any blocking towers before placement
        local bestOption = allValidTriangles[1]
        if #bestOption.blockingTowers > 0 then
            self:clearBlockingTowers(bestOption.blockingTowers)
        end
    end
    
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

-- Phase 2: Check for touching tier 1 combinations
function Grid:checkMagneticCombinations()
    if self.isAnimating then return end
    
    -- Level restrictions: Tier 2 towers only available from level 2+
    if self.currentLevel < 2 then return end
    
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
    
    -- Check for touching pairs (different types that are adjacent)
    for i = 1, #tierOnes do
        for j = i + 1, #tierOnes do
            local t1, t2 = tierOnes[i], tierOnes[j]
            if t1.ballType ~= t2.ballType then
                local distance = self:getDistance(t1.centerX, t1.centerY, t2.centerX, t2.centerY)
                if distance <= MAGNETIC_TIER1_DISTANCE then -- Tier 1 to Tier 2 magnetic combination range
                    self:startTierTwoMagnetism(t1, t2)
                    return -- Only one combination at a time
                end
            end
        end
    end
end

-- Phase 3: Check for touching tier 3 combinations (Tier 2 + Tier 2)
function Grid:checkMagneticTierThree()
    if self.isAnimating then return end
    
    -- Level restrictions: Tier 3 towers only available from level 3+
    if self.currentLevel < 3 then
        -- If no Tier 3 possible, check for normal Tier 2 combinations
        self:checkMagneticCombinations()
        return
    end
    
    -- Find all tier 2 bubbles
    local tierTwos = {}
    
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        tierTwos[#tierTwos + 1] = {
            idx = idx,
            sprite = tierTwoData.sprite,
            centerX = tierTwoData.centerX,
            centerY = tierTwoData.centerY,
            pattern = tierTwoData.pattern
        }
    end
    
    -- Check for valid Tier 3 combinations (Tier 2 + Tier 2 touching)
    for i = 1, #tierTwos do
        for j = i + 1, #tierTwos do -- Only check each pair once
            local t2a, t2b = tierTwos[i], tierTwos[j]
            local tier3Sprite = MergeConstants.getTierThreeSprite(t2a.sprite, t2b.sprite)
            
            if tier3Sprite then
                local distance = self:getDistance(t2a.centerX, t2a.centerY, t2b.centerX, t2b.centerY)
                if distance <= MAGNETIC_TIER2_DISTANCE then -- Tier 2 to Tier 2 magnetic combination range
                    self:startTierThreeMagnetism(t2a, t2b, tier3Sprite)
                    return -- Only one combination at a time
                end
            end
        end
    end
    
    -- If no Tier 3 possible, check for normal Tier 2 combinations
    self:checkMagneticCombinations()
end

-- Start tier 3 magnetism animation (between two Tier 2 bubbles)
function Grid:startTierThreeMagnetism(tierTwoA, tierTwoB, sprite)
    local midpointX = (tierTwoA.centerX + tierTwoB.centerX) / 2
    local midpointY = (tierTwoA.centerY + tierTwoB.centerY) / 2
    
    self.animations[#self.animations + 1] = {
        type = "tier3_magnetism",
        tierTwoA = tierTwoA,
        tierTwoB = tierTwoB,
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
function Grid:getDistance(x1, y1, x2, y2)
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

-- Clear tier 3 bubble and its pattern cells
function Grid:clearTierThree(tierThree)
    for _, idx in ipairs(tierThree.pattern) do
        self.cells[idx].ballType = nil
        self.cells[idx].occupied = false
        self.cells[idx].tier = nil
    end
    self.tierThreePositions[tierThree.idx] = nil
end

-- Clear blocking towers when placing new ones (generous placement)
function Grid:clearBlockingTowers(towerIndices)
    for _, idx in ipairs(towerIndices) do
        local cell = self.cells[idx]
        if cell.tier == "tier1" then
            -- Find and remove from tierOnePositions
            for tier1Idx, tier1 in pairs(self.tierOnePositions) do
                for _, triangleIdx in ipairs(tier1.triangle) do
                    if triangleIdx == idx then
                        self:clearTierOne(tier1)
                        break
                    end
                end
            end
        elseif cell.tier == "tier2" then
            -- Find and remove from tierTwoPositions
            for tier2Idx, tier2 in pairs(self.tierTwoPositions) do
                for _, patternIdx in ipairs(tier2.pattern) do
                    if patternIdx == idx then
                        self:clearTierTwo(tier2)
                        break
                    end
                end
            end
        elseif cell.tier == "tier3" then
            -- Find and remove from tierThreePositions
            for tier3Idx, tier3 in pairs(self.tierThreePositions) do
                for _, patternIdx in ipairs(tier3.pattern) do
                    if patternIdx == idx then
                        self:clearTierThree(tier3)
                        break
                    end
                end
            end
        else
            -- Basic bubble - just clear it
            cell.ballType = nil
            cell.occupied = false
            cell.tier = nil
        end
    end
end

-- Find valid Tier 2 placement near given position (generous approach)
function Grid:findValidTierTwoPlacement(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 20) -- Wider search
    
    local bestOptions = {}
    
    for _, candidate in ipairs(candidates) do
        local centerIdx = candidate.idx
        local neighbors = self:getNeighbors(centerIdx)
        
        -- Check if we have enough valid neighbors for full 7-cell pattern
        if #neighbors >= 6 then
            local validPattern = {centerIdx}
            local blockingTowers = {}
            local canPlace = true
            
            -- Check center cell first
            if self.cells[centerIdx].permanent then
                canPlace = false
            elseif self.cells[centerIdx].occupied and self.cells[centerIdx].tier == "tier3" then
                blockingTowers[#blockingTowers + 1] = centerIdx
            elseif self.cells[centerIdx].occupied and self.cells[centerIdx].tier == "tier2" then
                -- Light penalty for same-tier displacement
                blockingTowers[#blockingTowers + 1] = centerIdx
            end
            
            -- Check all neighbors
            if canPlace then
                for _, neighborIdx in ipairs(neighbors) do
                    if self.cells[neighborIdx] and not self.cells[neighborIdx].permanent then
                        validPattern[#validPattern + 1] = neighborIdx
                        -- Allow stomping basic bubbles and Tier 1, track higher tier conflicts
                        if self.cells[neighborIdx].occupied and self.cells[neighborIdx].tier == "tier3" then
                            blockingTowers[#blockingTowers + 1] = neighborIdx
                        elseif self.cells[neighborIdx].occupied and self.cells[neighborIdx].tier == "tier2" then
                            -- Light penalty for same-tier displacement
                            blockingTowers[#blockingTowers + 1] = neighborIdx
                        end
                    else
                        canPlace = false
                        break
                    end
                end
            end
            
            if canPlace and #validPattern >= 7 then
                -- Calculate distance to preferred position
                local dx = centerX - candidate.pos.x
                local dy = centerY - candidate.pos.y
                local dist = dx * dx + dy * dy
                
                -- Calculate penalty for displacing towers (lighter for same-tier)
                local penalty = 0
                for _, blockingIdx in ipairs(blockingTowers) do
                    if self.cells[blockingIdx].tier == "tier3" then
                        penalty = penalty + 3000  -- Heavy penalty for Tier 3
                    elseif self.cells[blockingIdx].tier == "tier2" then
                        penalty = penalty + 500   -- Light penalty for same-tier
                    end
                end
                
                bestOptions[#bestOptions + 1] = {
                    centerIdx = centerIdx,
                    pattern = validPattern,
                    blockingTowers = blockingTowers,
                    dist = dist + penalty
                }
            end
        end
    end
    
    if #bestOptions > 0 then
        -- Sort by distance (with penalties) and pick best
        table.sort(bestOptions, function(a, b) return a.dist < b.dist end)
        local best = bestOptions[1]
        
        -- Clear any blocking towers
        if #best.blockingTowers > 0 then
            self:clearBlockingTowers(best.blockingTowers)
        end
        
        return best.centerIdx, best.pattern
    end
    
    return nil, nil
end

-- Find valid Tier 3 placement near given position (generous 19-cell pattern)
function Grid:findValidTierThreePlacement(centerX, centerY)
    local candidates = self:findNearestValidCells(centerX, centerY, 40) -- Even wider search
    
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
        print("WARNING: Could not place Tier 2 tower - finding emergency position")
        centerIdx, pattern = self:findEmergencyTierTwoPlacement(centerX, centerY)
        if not centerIdx then
            print("CRITICAL: Could not place Tier 2 tower at all - tower lost")
            return 
        end
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
    
end

-- Place tier 3 bubble with grid snapping animation  
function Grid:placeTierThree(centerX, centerY, sprite)
    -- Find valid position for full 19-cell pattern
    local centerIdx, pattern = self:findValidTierThreePlacement(centerX, centerY)
    if not centerIdx then 
        print("WARNING: Could not place Tier 3 tower - finding emergency position")
        centerIdx, pattern = self:findEmergencyTierThreePlacement(centerX, centerY)
        if not centerIdx then
            print("CRITICAL: Could not place Tier 3 tower at all - tower lost")
            return 
        end
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
    
end

-- Emergency placement for Tier 2 - finds ANY available position by clearing everything
function Grid:findEmergencyTierTwoPlacement(centerX, centerY)
    -- Find ANY valid cell, even if far away
    local allCandidates = self:findNearestValidCells(centerX, centerY, 100) -- Search entire valid area
    
    for _, candidate in ipairs(allCandidates) do
        local centerIdx = candidate.idx
        local neighbors = self:getNeighbors(centerIdx)
        
        if #neighbors >= 6 and not self.cells[centerIdx].permanent then
            local pattern = {centerIdx}
            local canPlace = true
            
            -- Check all neighbors - only skip permanent boundaries
            for _, neighborIdx in ipairs(neighbors) do
                if self.cells[neighborIdx] and not self.cells[neighborIdx].permanent then
                    pattern[#pattern + 1] = neighborIdx
                else
                    canPlace = false
                    break
                end
            end
            
            if canPlace and #pattern >= 7 then
                -- Clear EVERYTHING in the pattern (emergency mode)
                for _, idx in ipairs(pattern) do
                    if self.cells[idx].occupied then
                        self:clearAnyTowerAtIndex(idx)
                    end
                end
                return centerIdx, pattern
            end
        end
    end
    
    return nil, nil
end

-- Emergency placement for Tier 3 - finds ANY available position by clearing everything  
function Grid:findEmergencyTierThreePlacement(centerX, centerY)
    -- Find ANY valid cell, even if far away
    local allCandidates = self:findNearestValidCells(centerX, centerY, 100) -- Search entire valid area
    
    for _, candidate in ipairs(allCandidates) do
        local centerIdx = candidate.idx
        local neighbors1 = self:getNeighbors(centerIdx)
        
        if #neighbors1 >= 6 and not self.cells[centerIdx].permanent then
            local pattern = {centerIdx}
            local canPlace = true
            
            -- Add first ring - only skip permanent boundaries
            for _, n1 in ipairs(neighbors1) do
                if self.cells[n1] and not self.cells[n1].permanent then
                    pattern[#pattern + 1] = n1
                else
                    canPlace = false
                    break
                end
            end
            
            -- Add second ring if first ring worked
            if canPlace and #pattern == 7 then
                local secondRingCells = {}
                for _, firstRingIdx in ipairs(neighbors1) do
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
                        
                        if not alreadyInPattern and self.cells[secondRingIdx] and 
                           not self.cells[secondRingIdx].permanent then
                            secondRingCells[#secondRingCells + 1] = secondRingIdx
                        end
                    end
                end
                
                -- Add 12 second-ring cells
                for i = 1, math.min(12, #secondRingCells) do
                    pattern[#pattern + 1] = secondRingCells[i]
                end
                
                if #pattern >= 19 then
                    -- Clear EVERYTHING in the pattern (emergency mode)
                    for _, idx in ipairs(pattern) do
                        if self.cells[idx].occupied then
                            self:clearAnyTowerAtIndex(idx)
                        end
                    end
                    return centerIdx, pattern
                end
            end
        end
    end
    
    return nil, nil
end

-- Clear any tower at a specific index (helper for emergency placement)
function Grid:clearAnyTowerAtIndex(idx)
    local cell = self.cells[idx]
    if cell.tier == "tier1" then
        -- Find and remove from tierOnePositions
        for tier1Idx, tier1 in pairs(self.tierOnePositions) do
            for _, triangleIdx in ipairs(tier1.triangle) do
                if triangleIdx == idx then
                    self:clearTierOne(tier1)
                    return
                end
            end
        end
    elseif cell.tier == "tier2" then
        -- Find and remove from tierTwoPositions
        for tier2Idx, tier2 in pairs(self.tierTwoPositions) do
            for _, patternIdx in ipairs(tier2.pattern) do
                if patternIdx == idx then
                    self:clearTierTwo(tier2)
                    return
                end
            end
        end
    elseif cell.tier == "tier3" then
        -- Find and remove from tierThreePositions
        for tier3Idx, tier3 in pairs(self.tierThreePositions) do
            for _, patternIdx in ipairs(tier3.pattern) do
                if patternIdx == idx then
                    self:clearTierThree(tier3)
                    return
                end
            end
        end
    else
        -- Basic bubble - just clear it
        cell.ballType = nil
        cell.occupied = false
        cell.tier = nil
    end
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
        end
    elseif not self.finalAttackTriggered then
        local regularCreeps = 0
        for _, creep in ipairs(self.creeps) do
            if not creep.converted then
                regularCreeps = regularCreeps + 1
            end
        end
    end
    
    -- Handle final attack delay countdown
    if self.finalAttackTriggered and self.finalAttackDelay then
        self.finalAttackDelay = self.finalAttackDelay - 1
        
        if self.finalAttackDelay <= 0 then
            self.finalAttackDelay = nil
            self:startCreepMarch()
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
    
    -- Don't spawn creeps on the final ball launch (when all ammo is used)
    if shotNumber >= #self.ammo then
        -- Simple finale trigger when ammo is exhausted
        local ammoExhausted = (self.currentShotIndex > #self.ammo)
        
        if ammoExhausted and not self.finaleTriggered then
            print("DEBUG: Ammo exhausted, triggering finale")
            self.finaleTriggered = true
            self.finaleCountdown = 60  -- 2 second delay before marching starts
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
        -- Tier 1 ranged: Stop 15px from tower edge (tower radius + 15px)
        -- This keeps them within rain range (40px) while maintaining tactical distance
        return TOWER_SPRITE_RADIUS + 15  -- 18 + 15 = 33px (within rain range)
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
        
        -- Safety check: skip if creep is nil or if array was cleared during level transition
        if not creep or i > #self.creeps then
            -- Only remove if index is still valid
            if i <= #self.creeps then
                table.remove(self.creeps, i)
            end
            goto continue
        end
        
        -- Remove dead creeps (suicide attacks, damage from towers)
        if creep.hitpoints <= 0 or creep.dead then
            self:checkStagingAvailability(creep.stagingIdx)
            -- Bounds check before removal
            if i <= #self.creeps then
                table.remove(self.creeps, i)
                self:checkForVictory()
            end
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
                    -- Bounds check before removal
                    if i <= #self.creeps then
                        table.remove(self.creeps, i)
                        self:checkForVictory()  -- Check for victory after removing creep
                    end
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
    self:drawAvatars()
    self:drawProjectiles()
    self:drawLightningEffects()
    self:drawAnimations()
    self:drawUI()
    if self.gameState == "gameOver" then
        self:drawGameOverScreen()
    elseif self.gameState == "victory" then
        self:drawVictoryScreen()
    elseif self.gameState == "tier2_unlock" then
        self:drawTier2UnlockScreen()
    elseif self.gameState == "tier3_unlock" then
        self:drawTier3UnlockScreen()
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
        
        -- Draw HP bar above tower (only during combat phase)
        if self:isCreepMarchActive() then
            self:drawTowerHPBar(tierOneData)
        end
    end
    
    -- Tier 2 bubbles (render at stored center positions)
    for idx, tierTwoData in pairs(self.tierTwoPositions) do
        self.bubbleSprites.tier2[tierTwoData.sprite]:draw(
            tierTwoData.centerX - 26, tierTwoData.centerY - 26)
        
        -- Draw HP bar above tower (only during combat phase)
        if self:isCreepMarchActive() then
            self:drawTowerHPBar(tierTwoData)
        end
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
        
        -- Safety check: skip if troop is nil (can happen during level transitions)
        if not troop then
            table.remove(self.troops, i)
            goto continue
        end
        
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
                goto continue
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
        
        ::continue::
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

-- Update all Avatar behavior (mobile fire towers)
function Grid:updateAvatars()
    for i = #self.avatars, 1, -1 do
        local avatar = self.avatars[i]
        
        -- Safety check: skip if avatar is nil
        if not avatar then
            table.remove(self.avatars, i)
            goto continue
        end
        
        -- Only activate during creep march phase
        if self:isCreepMarchActive() and avatar.state == "waiting" then
            avatar.state = "moving"
        end
        
        if avatar.state == "moving" or avatar.state == "attacking" then
            -- Find nearest enemy
            local nearestCreep = nil
            local nearestDistance = math.huge
            
            for _, creep in ipairs(self.creeps) do
                local dx = creep.x - avatar.x
                local dy = creep.y - avatar.y
                local distance = math.sqrt(dx*dx + dy*dy)
                
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestCreep = creep
                end
            end
            
            -- Move towards nearest enemy or attack if in range
            if nearestCreep then
                local dx = nearestCreep.x - avatar.x
                local dy = nearestCreep.y - avatar.y
                local distance = math.sqrt(dx*dx + dy*dy)
                
                -- Fire tower range is FLAME_TOWER_RANGE (240px)
                if distance <= FLAME_TOWER_RANGE then
                    avatar.state = "attacking"
                    avatar.targetX = nearestCreep.x
                    avatar.targetY = nearestCreep.y
                    
                    -- Fire projectiles like a flame tower
                    if self.frameCounter - avatar.lastShotTime >= FLAME_TOWER_COOLDOWN then
                        self:fireAvatarProjectiles(avatar, nearestCreep.x, nearestCreep.y)
                        avatar.lastShotTime = self.frameCounter
                    end
                else
                    -- Move towards enemy (same speed as troop march)
                    avatar.state = "moving"
                    local moveDistance = TROOP_MARCH_SPEED
                    local moveX = (dx / distance) * moveDistance
                    local moveY = (dy / distance) * moveDistance
                    avatar.x = avatar.x + moveX
                    avatar.y = avatar.y + moveY
                end
            end
        end
        
        ::continue::
    end
end

-- Fire Avatar projectiles (flame tower style)
function Grid:fireAvatarProjectiles(avatar, targetX, targetY)
    local dx = targetX - avatar.x
    local dy = targetY - avatar.y
    local baseAngle = math.atan2(dy, dx)
    
    -- Fire projectiles in a cone like flame tower
    for i = 1, FLAME_PROJECTILES_PER_SHOT do
        local spreadAngle = (i - 2) * (FLAME_CONE_ANGLE * PI_OVER_180)  -- -15°, 0°, +15°
        local angle = baseAngle + spreadAngle
        
        self.projectiles[#self.projectiles + 1] = {
            x = avatar.x,
            y = avatar.y,
            velocityX = math.cos(angle) * FLAME_PROJECTILE_SPEED,
            velocityY = math.sin(angle) * FLAME_PROJECTILE_SPEED,
            damage = FLAME_PROJECTILE_DAMAGE,
            range = FLAME_PROJECTILE_RANGE,
            distanceTraveled = 0,
            towerType = "avatar"
        }
    end
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
        -- FIXED: Find priority target within actual bolt range to avoid targeting out-of-range enemies
        local target = self:findPriorityTargetForLightning(tower.centerX, tower.centerY, LIGHTNING_BOLT_RANGE)
        
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
        
        -- Note: No additional range check needed since we already found target within bolt range
        
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
                
                -- Check if tower is destroyed
                if target.hitpoints <= 0 then
                    -- Determine tower type and call appropriate destroy function
                    local foundInTier1 = false
                    for idx, towerData in pairs(self.tierOnePositions) do
                        if towerData == target then
                            self:destroyTower(target)
                            foundInTier1 = true
                            break
                        end
                    end
                    
                    if not foundInTier1 then
                        -- Must be a Tier 2 tower
                        for idx, towerData in pairs(self.tierTwoPositions) do
                            if towerData == target then
                                self:destroyTowerTier2(target, idx)
                                break
                            end
                        end
                    end
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
        -- All towers destroyed - creeps won this round, advance to next level
        if self.currentLevel == 5 then
            -- Final level - game over (creeps completely won)
            self:startGameOverSequence()
        else
            -- Advance to next level after defeat
            self:advanceToNextLevel()
        end
    end
end

-- Update all projectiles with optimized collision detection
-- Performance optimized: Screen boundary check first, range check second, collision last
-- Processes projectiles in reverse order to handle safe removal during iteration
function Grid:updateProjectiles()
    for i = #self.projectiles, 1, -1 do
        local projectile = self.projectiles[i]
        
        -- Safety check: skip if projectile is nil or if array was cleared during level transition
        if not projectile or i > #self.projectiles then
            -- Only remove if index is still valid
            if i <= #self.projectiles then
                table.remove(self.projectiles, i)
            end
            goto continue
        end
        
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
            -- Bounds check before removal
            if i <= #self.projectiles then
                table.remove(self.projectiles, i)
            end
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
            -- Bounds check before removal
            if i <= #self.projectiles then
                table.remove(self.projectiles, i)
            end
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
        
        -- Safety check: skip if dot is nil or if array was cleared during level transition
        if not dot or i > #self.rainDots then
            -- Only remove if index is still valid
            if i <= #self.rainDots then
                table.remove(self.rainDots, i)
            end
            goto continue
        end
        
        -- Check if dot has expired (5 frames)
        if (self.frameCounter - dot.spawnFrame) >= RAIN_DOT_LIFETIME then
            -- Bounds check before removal
            if i <= #self.rainDots then
                table.remove(self.rainDots, i)
            end
            goto continue
        end
        
        -- Check collision with all creeps (optimized: avoid sqrt, use squared distance)
        for j = #self.creeps, 1, -1 do
            local creep = self.creeps[j]
            
            -- Calculate squared distance between dot and creep (faster than sqrt)
            local dx = dot.x - creep.x
            local dy = dot.y - creep.y
            local distSquared = dx*dx + dy*dy
            local creepSizeSquared = creep.size * creep.size
            
            -- Check if creep is touching the dot (using squared distance comparison)
            if distSquared <= creepSizeSquared then
                -- Deal damage to creep
                creep.hitpoints = creep.hitpoints - dot.damage
                
                -- Remove the dot (it gets consumed on hit)
                -- Bounds check before removal
                if i <= #self.rainDots then
                    table.remove(self.rainDots, i)
                end
                
                -- Check if creep is dead
                if creep.hitpoints <= 0 then
                    -- Free up staging position if this was the last creep there
                    self:checkStagingAvailability(creep.stagingIdx)
                    -- Bounds check before removal
                    if j <= #self.creeps then
                        table.remove(self.creeps, j)
                        
                        -- Check for victory after removing creep
                        self:checkForVictory()
                    end
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
        
        -- Safety check: skip if effect is nil (can happen during level transitions)
        if not effect then
            table.remove(self.lightningEffects, i)
            goto continue
        end
        
        -- Decrease lifetime each frame
        effect.lifetime = effect.lifetime - 1
        
        -- Remove expired effects
        if effect.lifetime <= 0 then
            table.remove(self.lightningEffects, i)
        end
        
        ::continue::
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
                    -- Bounds check before removal
                    if projectileIndex <= #self.projectiles then
                        table.remove(self.projectiles, projectileIndex)
                    end
                end
                
                -- Check if creep is dead
                if creep.hitpoints <= 0 then
                    -- Free up staging position if this was the last creep there
                    self:checkStagingAvailability(creep.stagingIdx)
                    -- Bounds check before removal
                    if i <= #self.creeps then
                        table.remove(self.creeps, i)
                        
                        -- Check for victory after removing creep
                        self:checkForVictory()
                    end
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
                -- Bounds check before removal
                if projectileIndex <= #self.projectiles then
                    table.remove(self.projectiles, projectileIndex)
                end
                
                
                -- Check if tower is destroyed
                if tower.hitpoints <= 0 then
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
                -- Bounds check before removal
                if projectileIndex <= #self.projectiles then
                    table.remove(self.projectiles, projectileIndex)
                end
                
                
                -- Check if tower is destroyed
                if tower.hitpoints <= 0 then
                    self:destroyTowerTier2(tower, idx)
                end
                
                return  -- Projectile hit something, stop processing
            end
        end
    end
    
    -- Check all Avatars for collision
    for avatarIndex, avatar in ipairs(self.avatars) do
        -- Calculate distance between projectile and avatar center
        local dx = projectile.x - avatar.x
        local dy = projectile.y - avatar.y
        local distance = math.sqrt(dx*dx + dy*dy)
        
        -- Avatar collision radius (same as Tier 3 tower - 42px radius)
        local avatarRadius = 42
        
        -- Check if projectile hits the avatar
        if distance <= avatarRadius then
            -- Apply damage to avatar
            avatar.hitpoints = avatar.hitpoints - projectile.damage
            
            -- Remove the projectile
            if projectileIndex <= #self.projectiles then
                table.remove(self.projectiles, projectileIndex)
            end
            
            -- Check if avatar is destroyed
            if avatar.hitpoints <= 0 then
                table.remove(self.avatars, avatarIndex)
            end
            
            return  -- Projectile hit something, stop processing
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

-- Draw all Avatars
function Grid:drawAvatars()
    for _, avatar in ipairs(self.avatars) do
        -- Draw Avatar using tier 3 sprite (since that's where it came from)
        self.bubbleSprites.tier3[avatar.sprite]:draw(avatar.x - 42, avatar.y - 42)
        
        -- Draw health bar if in combat
        if self:isCreepMarchActive() and avatar.hitpoints < AVATAR_HP then
            self:drawAvatarHPBar(avatar)
        end
    end
end

-- Draw health bar for Avatar
function Grid:drawAvatarHPBar(avatar)
    local barWidth = 60
    local barHeight = 6
    local barX = avatar.x - barWidth / 2
    local barY = avatar.y - 50  -- Above the avatar
    
    -- Background
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(barX, barY, barWidth, barHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(barX, barY, barWidth, barHeight)
    
    -- Health bar
    local healthPercent = avatar.hitpoints / AVATAR_HP
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(barX + 1, barY + 1, (barWidth - 2) * healthPercent, barHeight - 2)
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
    local ammoExhausted = (self.currentShotIndex > #self.ammo)
    
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
        elseif anim.type == "tower_compacting" then
            local progress = math.min(anim.frame / MERGE_ANIMATION_FRAMES, 1.0)
            
            -- Draw each tower moving from start to end position
            for _, compactingTower in ipairs(anim.towers) do
                local tower = compactingTower.tower
                local currentX = compactingTower.startX + (compactingTower.endX - compactingTower.startX) * progress
                local currentY = compactingTower.startY + (compactingTower.endY - compactingTower.startY) * progress
                
                -- Draw based on tower type
                if tower.type == "tier1" then
                    self.bubbleSprites.tier1[tower.data.ballType]:draw(currentX - 18, currentY - 18)
                elseif tower.type == "tier2" then
                    self.bubbleSprites.tier2[tower.data.sprite]:draw(currentX - 26, currentY - 26)
                elseif tower.type == "tier3" then
                    self.bubbleSprites.tier3[tower.data.sprite]:draw(currentX - 42, currentY - 42)
                end
            end
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

-- Draw Tier 2 unlock screen
function Grid:drawTier2UnlockScreen()
    local boxWidth, boxHeight = 240, 100
    local boxX, boxY = 200 - boxWidth / 2, 120 - boxHeight / 2
    
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(boxX, boxY, boxWidth, boxHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(boxX, boxY, boxWidth, boxHeight)
    
    gfx.drawTextInRect("LEVEL 1 COMPLETE!", boxX, boxY + 5, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("ADVANCED TOWERS", boxX, boxY + 25, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("UNLOCKED!", boxX, boxY + 45, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("Press A to continue", boxX, boxY + 70, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
end

-- Draw Tier 3 unlock screen  
function Grid:drawTier3UnlockScreen()
    local boxWidth, boxHeight = 240, 100
    local boxX, boxY = 200 - boxWidth / 2, 120 - boxHeight / 2
    
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(boxX, boxY, boxWidth, boxHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(boxX, boxY, boxWidth, boxHeight)
    
    gfx.drawTextInRect("LEVEL 2 COMPLETE!", boxX, boxY + 5, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("AVATAR TOWERS", boxX, boxY + 25, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("UNLOCKED!", boxX, boxY + 45, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
    gfx.drawTextInRect("Press A to continue", boxX, boxY + 70, boxWidth, 20, 
                       nil, nil, kTextAlignment.center)
end

return Grid