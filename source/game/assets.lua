-- Asset management: sprite loading, asset creation, and rendering
-- Extracted from bubbleState.lua for better maintainability

import "CoreLibs/graphics"

-- Temporarily inline constants until we fix the import system
local constants = {
    ASSET_DEFINITIONS = {
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
    },
    SPRITE_FILES = {
        basic = "bubbles-basic",
        tierOne = "bubbles-tier-one", 
        tierTwo = "bubbles-tier-two",
        tierThree = "bubbles-tier-three"
    },
    COLLISION = {
        CLIPPING_TOLERANCE = 3,
        BASIC_RADIUS_REDUCTION = 5
    }
}

-- Temporarily inline helpers
local helpers = {
    getHexStagger = function(row)
        return ((row - 1) % 2)
    end,
    tableCount = function(table)
        local count = 0
        for _, _ in pairs(table) do
            count = count + 1
        end
        return count
    end,
    randomChoice = function(array)
        if #array == 0 then return nil end
        return array[math.random(#array)]
    end,
    randomRange = function(min, max)
        return math.random(min, max)
    end,
    isWithinDistance = function(x1, y1, x2, y2, maxDistance)
        local maxDistanceSquared = maxDistance * maxDistance
        return ((x2 - x1)^2 + (y2 - y1)^2) <= maxDistanceSquared
    end
}

local gfx <const> = playdate.graphics

local AssetManager = {}

function AssetManager:new()
    local manager = {}
    setmetatable(manager, self)
    self.__index = self
    
    manager.spriteSheets = {}
    manager.assets = {}
    manager.nextAssetId = 1
    
    -- Load sprite sheets on initialization
    manager:loadBubbleSprites()
    
    return manager
end

function AssetManager:loadBubbleSprites()
    self.spriteSheets = {}
    
    -- Try to load each sprite sheet individually with error handling
    for assetType, fileName in pairs(constants.SPRITE_FILES) do
        local sheetPath = "assets/sprites/" .. fileName .. ".png"
        
        local success, sheet = pcall(gfx.image.new, sheetPath)
        
        if success and sheet then
            self.spriteSheets[assetType] = sheet
        else
            self.spriteSheets[assetType] = nil
        end
    end
end

function AssetManager:createAsset(assetType, bubbleType, row, col, grid)
    local definition = constants.ASSET_DEFINITIONS[assetType]
    if not definition then return nil end
    
    -- Calculate center position for the asset
    local anchorCell = grid:getCellAtRowCol(row, col)
    if not anchorCell then return nil end
    
    local centerX, centerY = self:calculateAssetCenter(assetType, row, col, grid)
    if not centerX then return nil end
    
    local assetId = self.nextAssetId
    self.nextAssetId = self.nextAssetId + 1
    
    local asset = {
        id = assetId,
        type = assetType,
        bubbleType = bubbleType,
        x = centerX,
        y = centerY,
        anchorRow = row,
        anchorCol = col,
    }
    
    return asset
end

function AssetManager:calculateAssetCenter(assetType, row, col, grid)
    local anchorCell = grid:getCellAtRowCol(row, col)
    if not anchorCell then 
        return 0, 0 
    end
    
    if assetType == "basic" then
        -- Basic: center sprite on single cell
        return anchorCell.x, anchorCell.y
    end
    
    if assetType == "tierTwo" or assetType == "tierThree" then
        -- Tier 2 & 3: center sprite on center cell (anchor is center cell)
        return anchorCell.x, anchorCell.y
    end
    
    if assetType == "tierOne" then
        -- Tier 1: use the actual top-left cell of the pattern for positioning
        local anchorStagger = helpers.getHexStagger(row)
        local topLeftCell
        
        if anchorStagger == 0 then
            -- Odd row: top-left is at (row-1, col-1)
            topLeftCell = grid:getCellAtRowCol(row - 1, col - 1)
        else
            -- Even row: top-left is at (row-1, col+0)  
            topLeftCell = grid:getCellAtRowCol(row - 1, col)
        end
        
        if not topLeftCell then 
            return anchorCell.x, anchorCell.y  -- Fallback to anchor
        end
        
        -- Use top-left cell for sprite positioning
        -- Grid cells are 20px wide, 16px tall
        local anchorTopLeftX = topLeftCell.x - 10
        local anchorTopLeftY = topLeftCell.y - 8
        
        -- 50x36px sprite: center is at top-left + (25px, 16px)
        local spriteCenterX = anchorTopLeftX + 25
        local spriteCenterY = anchorTopLeftY + 16
        
        return spriteCenterX, spriteCenterY
    end
    
    -- Fallback: use anchor cell center
    return anchorCell.x, anchorCell.y
end

function AssetManager:placeAssetDirect(assetType, bubbleType, row, col, grid)
    -- Get pattern cells for this placement
    local patternCells = grid:findPatternCells(assetType, row, col)
    if not patternCells or #patternCells == 0 then
        return nil
    end
    
    -- Create the asset
    local asset = self:createAsset(assetType, bubbleType, row, col, grid)
    if not asset then
        return nil
    end
    
    -- Mark ALL pattern cells as occupied by this asset
    for _, cellInfo in ipairs(patternCells) do
        grid:markCellOccupied(cellInfo.row, cellInfo.col, asset.id)
    end
    
    -- Store the pattern cells with the asset
    asset.patternCells = patternCells
    
    -- Add to assets table
    self.assets[asset.id] = asset
    
    return asset
end

function AssetManager:placeAssetDirectForced(assetType, bubbleType, row, col, grid)
    -- Forced placement for losing shots - bypasses all collision checks
    local asset = self:createAsset(assetType, bubbleType, row, col, grid)
    if not asset then
        return nil
    end
    
    -- Get pattern cells but don't check if they're occupied
    local patternCells = grid:findPatternCells(assetType, row, col)
    if patternCells then
        -- Force mark ALL pattern cells as occupied, even if they overlap
        for _, cellInfo in ipairs(patternCells) do
            grid:markCellOccupied(cellInfo.row, cellInfo.col, asset.id)
        end
        asset.patternCells = patternCells
    end
    
    -- Add to assets table
    self.assets[asset.id] = asset
    
    return asset
end

function AssetManager:getBubbleCollisionRadius(bubbleType)
    -- Return collision radius for each bubble type (max radius - reduction)
    local definition = constants.ASSET_DEFINITIONS[bubbleType]
    if definition and definition.collisionRadius then
        return definition.collisionRadius - constants.COLLISION.BASIC_RADIUS_REDUCTION
    end
    
    -- Fallback for unknown types
    return 15
end

function AssetManager:wouldProjectileCollide(testX, testY, projectileType, assets)
    -- Shape-aware collision detection with consistent clipping tolerance
    
    -- Get projectile's collision radius based on type
    local projectileRadius = self:getBubbleCollisionRadius(projectileType)
    
    -- Check distance to all existing bubble centers using optimized squared distance
    for _, asset in pairs(assets) do
        local existingRadius = self:getBubbleCollisionRadius(asset.type)
        local requiredDistance = projectileRadius + existingRadius + constants.COLLISION.CLIPPING_TOLERANCE
        
        -- Use optimized distance comparison to avoid sqrt calculation
        if helpers.isWithinDistance(testX, testY, asset.x, asset.y, requiredDistance) then
            return true  -- Too close to existing bubble
        end
    end
    
    return false  -- No collision
end

function AssetManager:drawAsset(asset)
    local definition = constants.ASSET_DEFINITIONS[asset.type]
    local spriteSheet = self.spriteSheets[asset.type]
    
    -- Only proceed if we have valid definition and sprite sheet
    if not definition or not spriteSheet then
        return
    end
    
    local sprite = definition.sprite
    
    -- Validate bubble type is within range
    if asset.bubbleType < 1 or asset.bubbleType > sprite.count then
        return
    end
    
    local sourceX = (asset.bubbleType - 1) * sprite.width
    
    -- Calculate draw position (center the sprite on the asset position)
    local drawX = math.floor(asset.x - sprite.width / 2)
    local drawY = math.floor(asset.y - sprite.height / 2)
    
    -- Use clipping to draw the correct sprite from the sheet
    gfx.setClipRect(drawX, drawY, sprite.width, sprite.height)
    spriteSheet:draw(drawX - sourceX, drawY)
    gfx.clearClipRect()
end

function AssetManager:drawAllAssets()
    -- Draw all placed assets
    for _, asset in pairs(self.assets) do
        self:drawAsset(asset)
    end
end

function AssetManager:resetAssets()
    self.assets = {}
    self.nextAssetId = 1
end

function AssetManager:getAssetCount()
    return helpers.tableCount(self.assets)
end

function AssetManager:generateRandomProjectile()
    -- Randomly select projectile type and bubble type
    local projectileTypes = {"basic", "tierOne", "tierTwo", "tierThree"}
    local projectileType = helpers.randomChoice(projectileTypes)
    
    local bubbleType
    if projectileType == "basic" or projectileType == "tierOne" then
        bubbleType = helpers.randomRange(1, 5)  -- 5 basic types
    else
        bubbleType = helpers.randomRange(1, 10) -- 10 advanced types  
    end
    
    return projectileType, bubbleType
end

return AssetManager