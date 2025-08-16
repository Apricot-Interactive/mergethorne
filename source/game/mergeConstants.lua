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

-- Tier 3 combinations: Tier 2 + Tier 2 → Tier 3 tower
-- Format: [tier2_sprite1][tier2_sprite2] = tier3_sprite (all return 1 - single sprite)
MergeConstants.TIER_3_COMBINATIONS = {
    -- Tempest: Thunderstorm + Downpour
    [8] = {[4] = 1}, [4] = {[8] = 1},
    -- Ember: Magma + Wild Fire  
    [2] = {[7] = 1}, [7] = {[2] = 1},
    -- Chronus: Sandstorm + Quicksand
    [5] = {[3] = 1}, [3] = {[5] = 1},
    -- Prism: Steam + Explosion
    [1] = {[9] = 1}, [9] = {[1] = 1},
    -- Catalyst: Crystal + Chain Lightning
    [6] = {[10] = 1}, [10] = {[6] = 1}
}

-- Tier 3 tower names (all use sprite 1)
MergeConstants.TIER_3_NAMES = {
    [1] = "Tempest",     -- Thunderstorm + Downpour
    [2] = "Ember",       -- Magma + Wild Fire
    [3] = "Chronus",     -- Sandstorm + Quicksand
    [4] = "Prism",       -- Steam + Explosion
    [5] = "Catalyst"     -- Crystal + Chain Lightning
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

-- Helper function to get Tier 3 sprite from two Tier 2 sprites
function MergeConstants.getTierThreeSprite(tier2Sprite1, tier2Sprite2)
    return MergeConstants.TIER_3_COMBINATIONS[tier2Sprite1] and MergeConstants.TIER_3_COMBINATIONS[tier2Sprite1][tier2Sprite2] or nil
end

-- Helper function to get Tier 3 tower name from two Tier 2 sprites
function MergeConstants.getTierThreeName(tier2Sprite1, tier2Sprite2)
    local sprite = MergeConstants.getTierThreeSprite(tier2Sprite1, tier2Sprite2)
    if sprite then
        -- Determine which combination this is
        if (tier2Sprite1 == 8 and tier2Sprite2 == 4) or (tier2Sprite1 == 4 and tier2Sprite2 == 8) then
            return "Tempest"
        elseif (tier2Sprite1 == 2 and tier2Sprite2 == 7) or (tier2Sprite1 == 7 and tier2Sprite2 == 2) then
            return "Ember"
        elseif (tier2Sprite1 == 5 and tier2Sprite2 == 3) or (tier2Sprite1 == 3 and tier2Sprite2 == 5) then
            return "Chronus"
        elseif (tier2Sprite1 == 1 and tier2Sprite2 == 9) or (tier2Sprite1 == 9 and tier2Sprite2 == 1) then
            return "Prism"
        elseif (tier2Sprite1 == 6 and tier2Sprite2 == 10) or (tier2Sprite1 == 10 and tier2Sprite2 == 6) then
            return "Catalyst"
        end
    end
    return nil
end

-- Helper function to get sprite offset for tier
function MergeConstants.getSpriteOffset(tier)
    local info = MergeConstants.SPRITE_INFO[tier]
    return info and info.offset or -10
end

return MergeConstants