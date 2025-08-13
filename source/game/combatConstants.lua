-- ============================================================================
-- MERGETHORNE COMBAT CONSTANTS - BALANCE CONFIGURATION
-- ============================================================================
--
-- 🎯 COMBAT BALANCE OVERVIEW:
-- This file contains all combat-related balance values that can be easily
-- adjusted without diving into the main game logic. All damage, health,
-- attack timing, and behavior parameters are centralized here.
--
-- ⚖️ BALANCE PHILOSOPHY:
-- • Basic units: Aggressive rushers, high speed/damage but fragile
-- • Tier 1: Heavy assault, tactical suicide bombers with reach  
-- • Tier 2: Rapid fire support, mobile ranged units
-- • Tier 3: Heavy artillery, devastating burst damage dealers
--
-- 🔧 TUNING GUIDE:
-- • Increase HITPOINTS for longer battles (Basic: 6, T1: 15, T2: 35, T3: 80)
-- • Increase DAMAGE for faster kills (Basic: 2, T1: 4, T2: 2, T3: 8)
-- • Adjust ATTACK_RANGE for engagement zones (Basic: 25, T1: 30, T2: 120, T3: 100)
-- • Modify ATTACK_COOLDOWN for DPS (Suicide: 0, T2: 8 frames, T3: 12 frames)
-- • Change PROJECTILE_SPEED for threat level (T2: 6px/frame, T3: 5px/frame)
-- • Adjust MOVE_SPEED for positioning (Basic: 2.5, T1: 2, T2/T3: 2)

local CombatConstants = {}

-- ============================================================================
-- UNIT COMBAT STATS
-- ============================================================================

CombatConstants.UNIT_STATS = {
    basic = {
        HITPOINTS = 6,      -- Fragile but fast - high risk/reward
        DAMAGE = 2,         -- Meaningful damage for successful charges
        ATTACK_TYPE = "suicide_crash",
        ATTACK_RANGE = 25,  -- Better engagement window vs ranged
        BLAST_RADIUS = 15,  -- Precise blast for tactical positioning
        MOVE_SPEED = 2.5,   -- Fast enough to close distance effectively
        ATTACK_COOLDOWN = 0  -- Instant on contact
    },
    
    tier1 = {
        HITPOINTS = 15,     -- Tougher than basic but not overpowered
        DAMAGE = 4,         -- Meaningful blast damage for tactical play
        ATTACK_TYPE = "suicide_crash",
        ATTACK_RANGE = 30,  -- Better reach against ranged enemies
        BLAST_RADIUS = 18,  -- Wider blast for area control
        MOVE_SPEED = 2,     -- Faster than basic, tactical advance
        ATTACK_COOLDOWN = 0  -- Instant on contact
    },
    
    tier2 = {
        HITPOINTS = 35,     -- Durable but killable by focused assault
        DAMAGE = 6,         -- Effective damage for destroying bubble towers
        ATTACK_TYPE = "projectile",
        ATTACK_RANGE = 120, -- Closer combat, positioning matters more
        BLAST_RADIUS = 0,   -- No area damage
        MOVE_SPEED = 2,     -- Mobile for repositioning
        ATTACK_COOLDOWN = 5, -- Faster firing for bubble destruction
        PROJECTILE_SIZE = 2,  -- 2px square
        PROJECTILE_SPEED = 6,  -- Threatening projectiles, harder to dodge
        PROJECTILE_LIFETIME = 100  -- Balanced range for positioning play
    },
    
    tier3 = {
        HITPOINTS = 80,     -- Tanky but not immortal, can be overwhelmed
        DAMAGE = 15,        -- Devastating damage for destroying fortified towers
        ATTACK_TYPE = "short_projectile",
        ATTACK_RANGE = 100, -- Short-range powerhouse, must get close
        BLAST_RADIUS = 0,   -- No area damage
        MOVE_SPEED = 2,     -- Deliberate movement for positioning
        ATTACK_COOLDOWN = 8,  -- Faster burst intervals for tower destruction
        PROJECTILE_SIZE = 4,  -- 4x4 square
        PROJECTILE_SPEED = 5,  -- Threatening projectiles that demand respect
        PROJECTILE_LIFETIME = 20   -- Short range forces tactical positioning
    }
}

-- ============================================================================
-- BUBBLE/TOWER HEALTH CONSTANTS
-- ============================================================================

CombatConstants.BUBBLE_HEALTH = {
    basic = 8,      -- Basic bubbles - fragile towers
    tier1 = 20,     -- Tier 1 - moderate durability  
    tier2 = 30,     -- Tier 2 - tough but destroyable (5 hits at 6 damage)
    tier3 = 60      -- Tier 3 - heavily fortified (4 hits at 15 damage)
}

-- ============================================================================
-- COMBAT BEHAVIOR CONSTANTS
-- ============================================================================

-- Battle engagement rules - FIGHT TO THE DEATH!
CombatConstants.BATTLE_ENGAGEMENT_RANGE = 500  -- Much larger detection range
CombatConstants.MAX_TARGETING_RANGE = 800      -- Maximum range for finding targets
CombatConstants.IDLE_TARGET_OVERRIDE = true    -- Idle units can target any enemy if close
CombatConstants.COMBAT_COMMITMENT = true       -- Once in combat, fight until death!

-- Targeting priorities (higher = more preferred)
CombatConstants.TARGET_PRIORITIES = {
    tier3 = 4,
    tier2 = 3,
    tier1 = 2,
    basic = 1
}

-- Projectile physics
CombatConstants.PROJECTILE_COLLISION_BUFFER = 1  -- Buffer for collision detection

-- Visual effects
CombatConstants.DEATH_ANIMATION_FRAMES = 8
CombatConstants.EXPLOSION_FRAMES = 6
CombatConstants.MUZZLE_FLASH_FRAMES = 3

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get combat stats for a unit tier
function CombatConstants.getUnitStats(tier)
    return CombatConstants.UNIT_STATS[tier] or CombatConstants.UNIT_STATS.basic
end

-- Calculate blast damage for area attacks
function CombatConstants.getBlastDamage(attackerTier, distance, blastRadius)
    local stats = CombatConstants.getUnitStats(attackerTier)
    if distance > blastRadius then
        return 0
    end
    -- Full damage within blast radius (could add falloff later)
    return stats.DAMAGE
end

-- Check if unit should engage target based on range and behavior
function CombatConstants.shouldEngage(unitTier, distanceToTarget)
    local stats = CombatConstants.getUnitStats(unitTier)
    
    -- Different engagement logic per attack type
    if stats.ATTACK_TYPE == "suicide_crash" then
        return distanceToTarget <= stats.ATTACK_RANGE + 5 -- Small buffer for contact
    elseif stats.ATTACK_TYPE == "projectile" then
        return distanceToTarget <= stats.ATTACK_RANGE + 10 -- Stop and fire
    elseif stats.ATTACK_TYPE == "short_projectile" then
        return distanceToTarget <= stats.ATTACK_RANGE + 5  -- Get close and fire
    end
    
    return false
end

-- Get target priority score for unit selection
function CombatConstants.getTargetPriority(tier)
    return CombatConstants.TARGET_PRIORITIES[tier] or 1
end

-- Get bubble health for a tier
function CombatConstants.getBubbleHealth(tier)
    return CombatConstants.BUBBLE_HEALTH[tier] or CombatConstants.BUBBLE_HEALTH.basic
end

return CombatConstants