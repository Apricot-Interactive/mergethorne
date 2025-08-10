-- Merge Constants for Towers of Mergethorne
-- All bubble types, combinations, and tier progression rules

local MergeConstants = {}

-- Basic bubble types (elemental)
MergeConstants.BASIC_TYPES = {
    FIRE = 1,
    WATER = 2, 
    EARTH = 3,
    LIGHTNING = 4,
    WIND = 5
}

-- Basic type names for debugging
MergeConstants.BASIC_NAMES = {
    [1] = "Fire",
    [2] = "Water", 
    [3] = "Earth",
    [4] = "Lightning",
    [5] = "Wind"
}

-- Tier 1 formation: 3+ connected basic bubbles of same type
-- Tier 1 uses same type numbers (1-5) but different sprites

-- Tier 2 combinations: Two different Tier 1 types → Tier 2 sprite
MergeConstants.TIER_2_COMBINATIONS = {
    -- Fire combinations
    [1] = {[2] = 1, [3] = 2, [4] = 9, [5] = 7}, -- Fire + Water/Earth/Lightning/Wind
    -- Water combinations  
    [2] = {[1] = 1, [3] = 3, [4] = 10, [5] = 4}, -- Water + Fire/Earth/Lightning/Wind
    -- Earth combinations
    [3] = {[1] = 2, [2] = 3, [4] = 6, [5] = 5},  -- Earth + Fire/Water/Lightning/Wind
    -- Lightning combinations
    [4] = {[1] = 9, [2] = 10, [3] = 6, [5] = 8}, -- Lightning + Fire/Water/Earth/Wind
    -- Wind combinations
    [5] = {[1] = 7, [2] = 4, [3] = 5, [4] = 8}   -- Wind + Fire/Water/Earth/Lightning
}

-- Tier 2 result names
MergeConstants.TIER_2_NAMES = {
    [1] = "Steam",        -- Fire + Water
    [2] = "Magma",        -- Fire + Earth  
    [3] = "Quicksand",    -- Water + Earth
    [4] = "Downpour",     -- Water + Wind
    [5] = "Sandstorm",    -- Earth + Wind
    [6] = "Crystal",      -- Earth + Lightning
    [7] = "Wild Fire",    -- Fire + Wind
    [8] = "Thunderstorm", -- Wind + Lightning
    [9] = "Explosion",    -- Fire + Lightning
    [10] = "Chain Lightning" -- Water + Lightning
}

-- Tier 3 combinations: Tier 2 + Tier 1 → Tier 3
-- Format: [tier2_sprite][tier1_type] = tier3_sprite
MergeConstants.TIER_3_COMBINATIONS = {
    [1] = {[3] = 1},  -- Steam + Tremor (Earth) = Geyser
    [2] = {[5] = 2},  -- Magma + Gust (Wind) = Volcano  
    [3] = {[4] = 3},  -- Quicksand + Shock (Lightning) = Sinkhole
    [4] = {[3] = 4},  -- Downpour + Tremor (Earth) = Flood
    [5] = {[2] = 5},  -- Sandstorm + Rain (Water) = Landslide
    [6] = {[2] = 6},  -- Crystal + Rain (Water) = Blizzard
    [7] = {[4] = 7},  -- Wild Fire + Shock (Lightning) = Phoenix
    [8] = {[1] = 8},  -- Thunderstorm + Flame (Fire) = Hellfire
    [9] = {[5] = 9},  -- Explosion + Gust (Wind) = Meteor
    [10] = {[1] = 10} -- Chain Lightning + Flame (Fire) = Plasma
}

-- Tier 3 result names
MergeConstants.TIER_3_NAMES = {
    [1] = "Geyser",      -- Steam + Earth
    [2] = "Volcano",     -- Magma + Wind
    [3] = "Sinkhole",    -- Quicksand + Lightning  
    [4] = "Flood",       -- Downpour + Earth
    [5] = "Landslide",   -- Sandstorm + Water
    [6] = "Blizzard",    -- Crystal + Water
    [7] = "Phoenix",     -- Wild Fire + Lightning
    [8] = "Hellfire",    -- Thunderstorm + Fire
    [9] = "Meteor",      -- Explosion + Wind
    [10] = "Plasma"      -- Chain Lightning + Fire
}

-- Helper function to get Tier 2 sprite from two Tier 1 types
function MergeConstants.getTierTwoSprite(type1, type2)
    return MergeConstants.TIER_2_COMBINATIONS[type1] and MergeConstants.TIER_2_COMBINATIONS[type1][type2] or nil
end

-- Sprite positioning constants
MergeConstants.SPRITE_INFO = {
    basic = {
        size = 20,
        offset = -10  -- Half of size for centering
    },
    tier1 = {
        size = 36, 
        offset = -18  -- Half of size for centering
    },
    tier2 = {
        size = 52,
        offset = -26  -- Half of size for centering  
    },
    tier3 = {
        size = 84,    -- Confirmed 84x84px sprites
        offset = -42  -- Half of size for centering
    }
}

-- Helper function to get Tier 3 sprite from Tier 2 sprite + Tier 1 type  
function MergeConstants.getTierThreeSprite(tier2Sprite, tier1Type)
    return MergeConstants.TIER_3_COMBINATIONS[tier2Sprite] and MergeConstants.TIER_3_COMBINATIONS[tier2Sprite][tier1Type] or nil
end

-- Helper function to get sprite offset for tier
function MergeConstants.getSpriteOffset(tier)
    local info = MergeConstants.SPRITE_INFO[tier]
    return info and info.offset or -10
end

return MergeConstants