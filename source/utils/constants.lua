Constants = {}

-- Grid configuration (hex grid) - precise touching circles
Constants.GRID_WIDTH = 11  -- Main play area width
Constants.GRID_HEIGHT = 9  -- 9 rows total
Constants.BUBBLE_RADIUS = 15  -- Bubble size
Constants.BUBBLE_DIAMETER = Constants.BUBBLE_RADIUS * 2
Constants.HEX_SPACING_X = Constants.BUBBLE_DIAMETER  -- Horizontal spacing: exactly one diameter for touching
Constants.HEX_SPACING_Y = Constants.BUBBLE_RADIUS * 1.732  -- Vertical spacing: √3 * radius for perfect hex
Constants.HEX_OFFSET_X = Constants.BUBBLE_RADIUS  -- Offset: exactly one radius for stagger

-- Bubble physics
Constants.BUBBLE_SPEED = 8

-- Bubble types (1-5 basic, 6-10 elite)
Constants.BUBBLE_TYPES = {
    BASIC_RED = 1,
    BASIC_BLUE = 2,
    BASIC_GREEN = 3,
    BASIC_YELLOW = 4,
    BASIC_PURPLE = 5,
    ELITE_RED = 6,
    ELITE_BLUE = 7,
    ELITE_GREEN = 8,
    ELITE_YELLOW = 9,
    ELITE_PURPLE = 10
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

