-- Game constants and configuration values
-- Extracted from bubbleState.lua for better maintainability

-- Grid configuration
local GRID = {
    TOTAL_ROWS = 15,
    MAX_COLS = 13,
    CELL_SPACING_X = 20,
    ROW_SPACING_Y = 16,
    HEX_OFFSET_X = 10,
    CIRCLE_SIZE = 20
}

-- Screen layout
local SCREEN = {
    WIDTH = 400,
    HEIGHT = 240,
    LEFT_PADDING = 40,
    RIGHT_PADDING = 100,
}

-- Shooter configuration  
local SHOOTER = {
    X_OFFSET = 60,  -- from right edge
    Y_POSITION = 120,
    DEFAULT_ANGLE = 180,  -- degrees
    SPEED = 5,
    MIN_ANGLE = 90,
    MAX_ANGLE = 270,
    ANGLE_STEP = 2
}

-- Game rules
local GAME = {
    BASE_HP = 100,
    MAX_LEVELS = 3,
    SHOTS_PER_LEVEL = 10
}

-- Collision detection
local COLLISION = {
    CLIPPING_TOLERANCE = 3,  -- pixels
    BASIC_RADIUS_REDUCTION = 5,
    TIER_ONE_RADIUS_REDUCTION = 5,
    TIER_TWO_RADIUS_REDUCTION = 5,
    TIER_THREE_RADIUS_REDUCTION = 5
}

-- Trajectory calculation
local TRAJECTORY = {
    STEP_SIZE = 1,
    MAX_DISTANCE = 600,
    MAX_SEARCH_RADIUS = 60,
    ATTACHMENT_SEARCH_RADIUS = 80,
    ANGLE_STEPS = 12  -- for radial search
}

-- Boundaries
local BOUNDARIES = {
    LEFT_BOUND_MARGIN = 5,
    TOP_BOUND = 25,
    BOTTOM_BOUND = 215,
    LINE_DASH_LENGTH = 6,
    LINE_GAP_LENGTH = 4,
    LINE_DASH_STEP = 10,
    BOUNDARY_OFFSET = 2
}

-- Asset definitions - moved from bubbleState.lua
local ASSET_DEFINITIONS = {
    basic = {
        cellCount = 1,
        sprite = {width = 20, height = 20, count = 5, sheet = "bubbles-basic"},
        collisionRadius = 10
    },
    
    tierOne = {
        cellCount = 4,
        sprite = {width = 50, height = 36, count = 5, sheet = "bubbles-tier-one"},
        collisionRadius = 18
    },
    
    tierTwo = {
        cellCount = 7,
        sprite = {width = 60, height = 52, count = 10, sheet = "bubbles-tier-two"},
        collisionRadius = 30
    },
    
    tierThree = {
        cellCount = 19,
        sprite = {width = 100, height = 84, count = 10, sheet = "bubbles-tier-three"},
        collisionRadius = 42
    }
}

-- Pattern templates for multi-cell bubbles
local PATTERN_TEMPLATES = {
    basic = {
        even = {{deltaRow = 0, deltaCol = 0}}, -- Just the anchor cell
        odd = {{deltaRow = 0, deltaCol = 0}},  -- Same for both
    },
    
    tierOne = {
        -- Even anchor example: (14,2) → pattern: 13,2  13,3  14,2  14,3
        even = {
            {deltaRow = -1, deltaCol = 0},  -- (13,2) = (14,2) + (-1,0)
            {deltaRow = -1, deltaCol = 1},  -- (13,3) = (14,2) + (-1,1)
            {deltaRow = 0, deltaCol = 0},   -- (14,2) = (14,2) + (0,0) [anchor]
            {deltaRow = 0, deltaCol = 1},   -- (14,3) = (14,2) + (0,1)
        },
        
        -- Odd anchor example: (5,2) → pattern: 4,1  4,2  5,2  5,3  
        odd = {
            {deltaRow = -1, deltaCol = -1}, -- (4,1) = (5,2) + (-1,-1)
            {deltaRow = -1, deltaCol = 0},  -- (4,2) = (5,2) + (-1,0)
            {deltaRow = 0, deltaCol = 0},   -- (5,2) = (5,2) + (0,0) [anchor]
            {deltaRow = 0, deltaCol = 1},   -- (5,3) = (5,2) + (0,1)
        },
    },
    
    tierTwo = {
        -- Even anchor example: anchor at center of 7-cell hex
        even = {
            {deltaRow = -1, deltaCol = 0}, -- Top-left
            {deltaRow = -1, deltaCol = 1},  -- Top-right
            {deltaRow = 0, deltaCol = -1},  -- Center-left
            {deltaRow = 0, deltaCol = 0},   -- Anchor (center)
            {deltaRow = 0, deltaCol = 1},   -- Center-right
            {deltaRow = 1, deltaCol = 0},  -- Bottom-left
            {deltaRow = 1, deltaCol = 1},   -- Bottom-right
        },
        
        -- Odd anchor example: anchor at center of 7-cell hex
        odd = {
            {deltaRow = -1, deltaCol = -1},  -- Top-left (shifted due to stagger)
            {deltaRow = -1, deltaCol = 0},  -- Top-right
            {deltaRow = 0, deltaCol = -1},  -- Center-left
            {deltaRow = 0, deltaCol = 0},   -- Anchor (center)
            {deltaRow = 0, deltaCol = 1},   -- Center-right
            {deltaRow = 1, deltaCol = -1},   -- Bottom-left (shifted due to stagger)
            {deltaRow = 1, deltaCol = 0},   -- Bottom-right
        },
    },
    
    tierThree = {
        -- Even anchor example: (4,3) → known pattern
        even = {
            {deltaRow = -2, deltaCol = -1}, {deltaRow = -2, deltaCol = 0}, {deltaRow = -2, deltaCol = 1},
            {deltaRow = -1, deltaCol = -1}, {deltaRow = -1, deltaCol = 0}, {deltaRow = -1, deltaCol = 1}, {deltaRow = -1, deltaCol = 2},
            {deltaRow = 0, deltaCol = -2}, {deltaRow = 0, deltaCol = -1}, {deltaRow = 0, deltaCol = 0}, {deltaRow = 0, deltaCol = 1}, {deltaRow = 0, deltaCol = 2},
            {deltaRow = 1, deltaCol = -1}, {deltaRow = 1, deltaCol = 0}, {deltaRow = 1, deltaCol = 1}, {deltaRow = 1, deltaCol = 2},
            {deltaRow = 2, deltaCol = -1}, {deltaRow = 2, deltaCol = 0}, {deltaRow = 2, deltaCol = 1},
        },
        
        -- Odd anchor example: adjusted for hex stagger
        odd = {
            {deltaRow = -2, deltaCol = -1}, {deltaRow = -2, deltaCol = 0}, {deltaRow = -2, deltaCol = 1},
            {deltaRow = -1, deltaCol = -2}, {deltaRow = -1, deltaCol = -1}, {deltaRow = -1, deltaCol = 0}, {deltaRow = -1, deltaCol = 1},
            {deltaRow = 0, deltaCol = -2}, {deltaRow = 0, deltaCol = -1}, {deltaRow = 0, deltaCol = 0}, {deltaRow = 0, deltaCol = 1}, {deltaRow = 0, deltaCol = 2},
            {deltaRow = 1, deltaCol = -2}, {deltaRow = 1, deltaCol = -1}, {deltaRow = 1, deltaCol = 0}, {deltaRow = 1, deltaCol = 1},
            {deltaRow = 2, deltaCol = -1}, {deltaRow = 2, deltaCol = 0}, {deltaRow = 2, deltaCol = 1},
        },
    }
}

-- Sprite files configuration
local SPRITE_FILES = {
    basic = "bubbles-basic",
    tierOne = "bubbles-tier-one", 
    tierTwo = "bubbles-tier-two",
    tierThree = "bubbles-tier-three"
}

-- Comprehensive bubble definitions with merge rules
local BUBBLE_TYPES = {
    -- Basic bubbles (tier 0) - not formed by merging
    [1] = {
        name = "Fire",
        tier = 0,
        element = "fire",
        spriteIndex = 1,
        formation = nil -- Basic bubbles are not formed
    },
    [2] = {
        name = "Water", 
        tier = 0,
        element = "water",
        spriteIndex = 2,
        formation = nil
    },
    [3] = {
        name = "Earth",
        tier = 0,
        element = "earth", 
        spriteIndex = 3,
        formation = nil
    },
    [4] = {
        name = "Lightning",
        tier = 0,
        element = "lightning",
        spriteIndex = 4,
        formation = nil
    },
    [5] = {
        name = "Wind",
        tier = 0,
        element = "wind",
        spriteIndex = 5,
        formation = nil
    },
    
    -- Tier 1 bubbles - formed from 3 basic bubbles
    [6] = {
        name = "Flame",
        tier = 1,
        element = "fire",
        spriteIndex = 1,
        formation = {
            requiredBubbles = {1}, -- Fire
            requiredCount = 3,
            method = "merge"
        }
    },
    [7] = {
        name = "Rain",
        tier = 1,
        element = "water",
        spriteIndex = 2,
        formation = {
            requiredBubbles = {2}, -- Water
            requiredCount = 3,
            method = "merge"
        }
    },
    [8] = {
        name = "Tremor",
        tier = 1,
        element = "earth",
        spriteIndex = 3,
        formation = {
            requiredBubbles = {3}, -- Earth
            requiredCount = 3,
            method = "merge"
        }
    },
    [9] = {
        name = "Gust",
        tier = 1,
        element = "wind",
        spriteIndex = 4, -- Gust is position 4 on Tier 1 sheet
        formation = {
            requiredBubbles = {5}, -- Wind
            requiredCount = 3,
            method = "merge"
        }
    },
    [10] = {
        name = "Shock",
        tier = 1,
        element = "lightning",
        spriteIndex = 5, -- Shock is position 5 on Tier 1 sheet
        formation = {
            requiredBubbles = {4}, -- Lightning
            requiredCount = 3,
            method = "merge"
        }
    },
    
    -- Tier 2 bubbles (10 types) - formed from specific Tier 1 combinations
    [11] = {
        name = "Steam",
        tier = 2,
        element = "fire-water",
        spriteIndex = 1,
        formation = {
            requiredBubbles = {6, 7}, -- Flame + Rain
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [12] = {
        name = "Magma",
        tier = 2,
        element = "fire-earth",
        spriteIndex = 2,
        formation = {
            requiredBubbles = {6, 8}, -- Flame + Tremor
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [13] = {
        name = "Quicksand",
        tier = 2,
        element = "water-earth",
        spriteIndex = 3,
        formation = {
            requiredBubbles = {7, 8}, -- Rain + Tremor
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [14] = {
        name = "Downpour",
        tier = 2,
        element = "water-wind",
        spriteIndex = 4,
        formation = {
            requiredBubbles = {7, 9}, -- Rain + Gust
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [15] = {
        name = "Sandstorm",
        tier = 2,
        element = "earth-wind",
        spriteIndex = 5,
        formation = {
            requiredBubbles = {8, 9}, -- Tremor + Gust
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [16] = {
        name = "Crystal",
        tier = 2,
        element = "earth-lightning",
        spriteIndex = 6,
        formation = {
            requiredBubbles = {8, 10}, -- Tremor + Shock
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [17] = {
        name = "Wild Fire",
        tier = 2,
        element = "wind-fire",
        spriteIndex = 7,
        formation = {
            requiredBubbles = {9, 6}, -- Gust + Flame
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [18] = {
        name = "Thunderstorm",
        tier = 2,
        element = "wind-lightning",
        spriteIndex = 8,
        formation = {
            requiredBubbles = {9, 10}, -- Gust + Shock
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [19] = {
        name = "Explosion",
        tier = 2,
        element = "lightning-fire",
        spriteIndex = 9,
        formation = {
            requiredBubbles = {10, 6}, -- Shock + Flame
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    [20] = {
        name = "Chain Lightning",
        tier = 2,
        element = "lightning-water",
        spriteIndex = 10,
        formation = {
            requiredBubbles = {10, 7}, -- Shock + Rain
            requiredCount = 2,
            method = "combo_merge"
        }
    },
    
    -- Tier 3 bubbles (10 types) - formed from Tier 2 + Tier 1 combinations
    [21] = {
        name = "Geyser",
        tier = 3,
        element = "ultimate-steam",
        spriteIndex = 1,
        formation = {
            requiredBubbles = {11, 8}, -- Steam + Tremor
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [22] = {
        name = "Volcano",
        tier = 3,
        element = "ultimate-magma",
        spriteIndex = 2,
        formation = {
            requiredBubbles = {12, 9}, -- Magma + Gust
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [23] = {
        name = "Sinkhole",
        tier = 3,
        element = "ultimate-quicksand",
        spriteIndex = 3,
        formation = {
            requiredBubbles = {13, 10}, -- Quicksand + Shock
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [24] = {
        name = "Flood",
        tier = 3,
        element = "ultimate-downpour",
        spriteIndex = 4,
        formation = {
            requiredBubbles = {14, 8}, -- Downpour + Tremor
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [25] = {
        name = "Landslide",
        tier = 3,
        element = "ultimate-sandstorm",
        spriteIndex = 5,
        formation = {
            requiredBubbles = {15, 7}, -- Sandstorm + Rain
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [26] = {
        name = "Blizzard",
        tier = 3,
        element = "ultimate-crystal",
        spriteIndex = 6,
        formation = {
            requiredBubbles = {16, 7}, -- Crystal + Rain
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [27] = {
        name = "Phoenix",
        tier = 3,
        element = "ultimate-wildfire",
        spriteIndex = 7,
        formation = {
            requiredBubbles = {17, 10}, -- Wild Fire + Shock
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [28] = {
        name = "Hellfire",
        tier = 3,
        element = "ultimate-thunderstorm",
        spriteIndex = 8,
        formation = {
            requiredBubbles = {18, 6}, -- Thunderstorm + Flame
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [29] = {
        name = "Meteor",
        tier = 3,
        element = "ultimate-explosion",
        spriteIndex = 9,
        formation = {
            requiredBubbles = {19, 9}, -- Explosion + Gust
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    },
    [30] = {
        name = "Plasma",
        tier = 3,
        element = "ultimate-chain-lightning",
        spriteIndex = 10,
        formation = {
            requiredBubbles = {20, 6}, -- Chain Lightning + Flame
            requiredCount = 2,
            method = "tier_combo_merge"
        }
    }
}

-- Helper function to get bubble type by element and tier
local ELEMENT_TO_BUBBLE_TYPE = {
    [0] = {
        fire = 1, water = 2, earth = 3, lightning = 4, wind = 5
    },
    [1] = {
        fire = 6, water = 7, earth = 8, lightning = 10, wind = 9
    }
}

-- Reverse lookup: bubble type to formation requirements
local MERGE_RULES = {}
for bubbleType, data in pairs(BUBBLE_TYPES) do
    if data.formation then
        -- Create lookup by required bubble types
        local key = table.concat(data.formation.requiredBubbles, "-")
        if not MERGE_RULES[key] then
            MERGE_RULES[key] = {}
        end
        table.insert(MERGE_RULES[key], {
            resultType = bubbleType,
            requiredCount = data.formation.requiredCount,
            method = data.formation.method
        })
    end
end

-- Export the constants
return {
    GRID = GRID,
    SCREEN = SCREEN,
    SHOOTER = SHOOTER,
    GAME = GAME,
    COLLISION = COLLISION,
    TRAJECTORY = TRAJECTORY,
    BOUNDARIES = BOUNDARIES,
    ASSET_DEFINITIONS = ASSET_DEFINITIONS,
    PATTERN_TEMPLATES = PATTERN_TEMPLATES,
    SPRITE_FILES = SPRITE_FILES,
    BUBBLE_TYPES = BUBBLE_TYPES,
    ELEMENT_TO_BUBBLE_TYPE = ELEMENT_TO_BUBBLE_TYPE,
    MERGE_RULES = MERGE_RULES
}