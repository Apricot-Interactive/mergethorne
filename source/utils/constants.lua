Constants = {}

-- Grid configuration (hex grid) - precise touching circles
Constants.GRID_WIDTH = 26  -- Main play area width  
Constants.GRID_HEIGHT = 17  -- 17 rows total
Constants.BUBBLE_RADIUS = 7.5  -- Bubble size (15px diameter)
Constants.BUBBLE_DIAMETER = Constants.BUBBLE_RADIUS * 2
Constants.HEX_SPACING_X = Constants.BUBBLE_DIAMETER  -- Horizontal spacing: exactly one diameter for touching
Constants.HEX_SPACING_Y = Constants.BUBBLE_RADIUS * 1.732  -- Vertical spacing: √3 * radius for perfect hex
Constants.HEX_OFFSET_X = Constants.BUBBLE_RADIUS  -- Offset: exactly one radius for stagger

-- Bubble physics
Constants.BUBBLE_SPEED = 8

-- Bubble types (1-5 basic, 6-10 elite, 11-15 Tier 1)
Constants.BUBBLE_TYPES = {
    BASIC_RED = 1,       -- Fire
    BASIC_BLUE = 2,      -- Air
    BASIC_GREEN = 3,     -- Earth
    BASIC_YELLOW = 4,    -- Lightning
    BASIC_PURPLE = 5,    -- Water
    ELITE_RED = 6,
    ELITE_BLUE = 7,
    ELITE_GREEN = 8,
    ELITE_YELLOW = 9,
    ELITE_PURPLE = 10,
    TIER1_FIRE = 11,     -- Fire Tier 1
    TIER1_WATER = 12,    -- Water Tier 1 
    TIER1_EARTH = 13,    -- Earth Tier 1
    TIER1_AIR = 14,      -- Air Tier 1
    TIER1_LIGHTNING = 15, -- Lightning Tier 1
    TIER2_UNIFIED = 16   -- Tier 2 (unified type for all merges)
}

-- Element mapping from basic to Tier 1
Constants.BASIC_TO_TIER1 = {
    [1] = 11, -- Fire -> Fire Tier 1
    [2] = 14, -- Air -> Air Tier 1
    [3] = 13, -- Earth -> Earth Tier 1
    [4] = 15, -- Lightning -> Lightning Tier 1
    [5] = 12  -- Water -> Water Tier 1
}

-- Element mapping from Tier 1 to Tier 2 (all merge to unified Tier 2)
Constants.TIER1_TO_TIER2 = {
    [11] = 16, -- Fire Tier 1 -> Tier 2
    [12] = 16, -- Water Tier 1 -> Tier 2
    [13] = 16, -- Earth Tier 1 -> Tier 2
    [14] = 16, -- Air Tier 1 -> Tier 2
    [15] = 16  -- Lightning Tier 1 -> Tier 2
}

-- Tier 1 configurations - each takes 3 horizontal cells
-- Configuration A (leftmost 5 in sprite sheet): leftmost bubble position
-- Configuration B (rightmost 5 in sprite sheet): rightmost bubble position
Constants.TIER1_CONFIGS = {
    A = { -- Configuration A positions (relative to leftmost)
        {0, 0}, {1, 0}, {2, 0} -- 3 cells horizontally
    },
    B = { -- Configuration B positions (relative to leftmost) 
        {0, 0}, {1, 0}, {2, 0} -- 3 cells horizontally
    }
}

-- Tier 2 configuration - diamond pattern (7 cells)
-- Pattern: center at (0,0), diamond shape
Constants.TIER2_CONFIG = {
    {0, -2},        -- Top
    {-1, -1}, {1, -1},  -- Second row (2 cells)
    {0, 0},         -- Center
    {-1, 1}, {1, 1},  -- Fourth row (2 cells)
    {0, 2}          -- Bottom
}

-- Tier 1 sprite indices matching actual sprite sheet orientation
Constants.TIER1_SPRITE_INDICES = {
    UP = { -- Up-facing triangles (sprites 6-10, right half of sheet)
        [11] = 6,  -- Fire Tier 1 UP
        [12] = 7,  -- Water Tier 1 UP
        [13] = 8,  -- Earth Tier 1 UP
        [14] = 9,  -- Air Tier 1 UP
        [15] = 10  -- Lightning Tier 1 UP
    },
    DOWN = { -- Down-facing triangles (sprites 1-5, left half of sheet)
        [11] = 1,  -- Fire Tier 1 DOWN
        [12] = 2,  -- Water Tier 1 DOWN
        [13] = 3,  -- Earth Tier 1 DOWN
        [14] = 4,  -- Air Tier 1 DOWN
        [15] = 5   -- Lightning Tier 1 DOWN
    }
}

-- Tower configuration
Constants.TOWER_RANGE = 80
Constants.TOWER_FIRE_RATE = 20
Constants.TOWER_DAMAGE = {
    [1] = 10,  -- Red tower
    [2] = 15,  -- Blue tower
    [3] = 20,  -- Green tower
    [4] = 25,  -- Yellow tower
    [5] = 30   -- Purple tower
}

-- Projectile configuration
Constants.PROJECTILE_SPEED = 6

-- Creep configuration
Constants.CREEP_HP = 50
Constants.CREEP_SPEED = 1.5
Constants.CREEP_DAMAGE = 10

-- Game configuration
Constants.SHOTS_PER_LEVEL = 10
Constants.BASE_HP = 100
Constants.MAX_LEVELS = 3

-- Screen dimensions
Constants.SCREEN_WIDTH = 400
Constants.SCREEN_HEIGHT = 240

-- Game boundaries - matching prototype layout
Constants.PLAY_AREA_WIDTH = Constants.GRID_WIDTH * Constants.HEX_SPACING_X + Constants.BUBBLE_RADIUS
Constants.BOUNDARY_X = Constants.PLAY_AREA_WIDTH + 10  -- Dashed line position close to play area
Constants.SHOOTER_X = Constants.BOUNDARY_X + 25  -- Shooter beyond boundary
Constants.SHOOTER_Y = 120  -- Vertical center

-- Colors (for basic graphics)
Constants.COLORS = {
    WHITE = playdate.graphics.kColorWhite,
    BLACK = playdate.graphics.kColorBlack
}

-- Input configuration
Constants.AIM_SPEED = 2
Constants.MIN_AIM_ANGLE = 135
Constants.MAX_AIM_ANGLE = 225

