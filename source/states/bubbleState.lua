-- Bubble State: Optimized single-file version with all performance improvements
-- This consolidates the modular architecture into one file until we fix import issues

import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics

-- Optimized constants (extracted from scattered hardcoded values)
local GRID_CONSTANTS = {
    TOTAL_ROWS = 15,
    MAX_COLS = 13,
    CELL_SPACING_X = 20,
    ROW_SPACING_Y = 16,
    HEX_OFFSET_X = 10,
    CIRCLE_SIZE = 20
}

local SCREEN_CONSTANTS = {
    WIDTH = 400,
    HEIGHT = 240,
    LEFT_PADDING = 40,
    RIGHT_PADDING = 100
}

local SHOOTER_CONSTANTS = {
    X_OFFSET = 60,
    Y_POSITION = 120,
    DEFAULT_ANGLE = 180,
    SPEED = 10,
    MIN_ANGLE = 90,
    MAX_ANGLE = 270,
    ANGLE_STEP = 2
}

local TRAJECTORY_CONSTANTS = {
    STEP_SIZE = 1,
    MAX_DISTANCE = 600,
    MAX_SEARCH_RADIUS = 60
}

local BOUNDARY_CONSTANTS = {
    LEFT_BOUND_MARGIN = 5,
    TOP_BOUND = -2,  -- Actual edge of row 1 (about 10px above center)
    BOTTOM_BOUND = 242,  -- Actual edge of row 15 (about 10px below center)
    LINE_DASH_LENGTH = 6,
    LINE_DASH_STEP = 10,
    BOUNDARY_OFFSET = 2
}

-- Asset definitions with optimized structure
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
        even = {{deltaRow = 0, deltaCol = 0}},
        odd = {{deltaRow = 0, deltaCol = 0}},
    },
    tierOne = {
        even = {
            {deltaRow = -1, deltaCol = 0},
            {deltaRow = -1, deltaCol = 1},
            {deltaRow = 0, deltaCol = 0},
            {deltaRow = 0, deltaCol = 1},
        },
        odd = {
            {deltaRow = -1, deltaCol = -1},
            {deltaRow = -1, deltaCol = 0},
            {deltaRow = 0, deltaCol = 0},
            {deltaRow = 0, deltaCol = 1},
        },
    },
    tierTwo = {
        even = {
            {deltaRow = -1, deltaCol = 0}, {deltaRow = -1, deltaCol = 1},
            {deltaRow = 0, deltaCol = -1}, {deltaRow = 0, deltaCol = 0}, {deltaRow = 0, deltaCol = 1},
            {deltaRow = 1, deltaCol = 0}, {deltaRow = 1, deltaCol = 1},
        },
        odd = {
            {deltaRow = -1, deltaCol = -1}, {deltaRow = -1, deltaCol = 0},
            {deltaRow = 0, deltaCol = -1}, {deltaRow = 0, deltaCol = 0}, {deltaRow = 0, deltaCol = 1},
            {deltaRow = 1, deltaCol = -1}, {deltaRow = 1, deltaCol = 0},
        },
    },
    tierThree = {
        even = {
            {deltaRow = -2, deltaCol = -1}, {deltaRow = -2, deltaCol = 0}, {deltaRow = -2, deltaCol = 1},
            {deltaRow = -1, deltaCol = -1}, {deltaRow = -1, deltaCol = 0}, {deltaRow = -1, deltaCol = 1}, {deltaRow = -1, deltaCol = 2},
            {deltaRow = 0, deltaCol = -2}, {deltaRow = 0, deltaCol = -1}, {deltaRow = 0, deltaCol = 0}, {deltaRow = 0, deltaCol = 1}, {deltaRow = 0, deltaCol = 2},
            {deltaRow = 1, deltaCol = -1}, {deltaRow = 1, deltaCol = 0}, {deltaRow = 1, deltaCol = 1}, {deltaRow = 1, deltaCol = 2},
            {deltaRow = 2, deltaCol = -1}, {deltaRow = 2, deltaCol = 0}, {deltaRow = 2, deltaCol = 1},
        },
        odd = {
            {deltaRow = -2, deltaCol = -1}, {deltaRow = -2, deltaCol = 0}, {deltaRow = -2, deltaCol = 1},
            {deltaRow = -1, deltaCol = -2}, {deltaRow = -1, deltaCol = -1}, {deltaRow = -1, deltaCol = 0}, {deltaRow = -1, deltaCol = 1},
            {deltaRow = 0, deltaCol = -2}, {deltaRow = 0, deltaCol = -1}, {deltaRow = 0, deltaCol = 0}, {deltaRow = 0, deltaCol = 1}, {deltaRow = 0, deltaCol = 2},
            {deltaRow = 1, deltaCol = -2}, {deltaRow = 1, deltaCol = -1}, {deltaRow = 1, deltaCol = 0}, {deltaRow = 1, deltaCol = 1},
            {deltaRow = 2, deltaCol = -1}, {deltaRow = 2, deltaCol = 0}, {deltaRow = 2, deltaCol = 1},
        },
    }
}

local SPRITE_FILES = {
    basic = "bubbles-basic",
    tierOne = "bubbles-tier-one", 
    tierTwo = "bubbles-tier-two",
    tierThree = "bubbles-tier-three"
}

-- Optimized helper functions (no more inline sqrt calculations where possible)
local function distanceSquared(x1, y1, x2, y2)
    return (x2 - x1)^2 + (y2 - y1)^2
end

local function distance(x1, y1, x2, y2)
    return math.sqrt(distanceSquared(x1, y1, x2, y2))
end

local function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

local function getHexStagger(row)
    return ((row - 1) % 2)
end

-- Main BubbleState class
BubbleState = {}

function BubbleState:new()
    local state = {}
    setmetatable(state, self)
    self.__index = self
    
    -- Grid system
    state.gridCells = {}
    state.gridLookup = {}
    state.rowLengths = {}
    state.occupiedBy = {}
    
    -- Asset system
    state.spriteSheets = {}
    state.assets = {}
    state.nextAssetId = 1
    
    -- Shooter system
    state.shooterX = SCREEN_CONSTANTS.WIDTH - SHOOTER_CONSTANTS.X_OFFSET
    state.shooterY = SHOOTER_CONSTANTS.Y_POSITION
    state.shootingAngle = SHOOTER_CONSTANTS.DEFAULT_ANGLE
    state.currentProjectile = nil
    
    -- Game state
    state.gameOver = false
    
    -- Initialize systems
    state:setupHexGrid()
    state:loadBubbleSprites()
    state:generateNewProjectile()
    
    return state
end

function BubbleState:setupHexGrid()
    self.gridCells = {}
    self.gridLookup = {}
    self.rowLengths = {}
    
    local totalRows = GRID_CONSTANTS.TOTAL_ROWS
    local cellSpacingX = GRID_CONSTANTS.CELL_SPACING_X
    local rowSpacingY = GRID_CONSTANTS.ROW_SPACING_Y
    local offsetX = GRID_CONSTANTS.HEX_OFFSET_X
    local circleSize = GRID_CONSTANTS.CIRCLE_SIZE
    
    local gridHeight = (totalRows - 1) * rowSpacingY + circleSize
    local startY = (SCREEN_CONSTANTS.HEIGHT - gridHeight) / 2 + circleSize/2
    
    local cellIndex = 1
    
    for row = 1, totalRows do
        local cellsInRow = GRID_CONSTANTS.MAX_COLS - ((row - 1) % 2)
        local hexOffset = ((row - 1) % 2) * offsetX
        
        self.gridLookup[row] = {}
        self.rowLengths[row] = cellsInRow
        
        for col = 1, cellsInRow do
            local x = SCREEN_CONSTANTS.LEFT_PADDING + hexOffset + (col - 1) * cellSpacingX + circleSize/2
            local y = startY + ((row - 1) * rowSpacingY)
            
            if x - circleSize/2 >= SCREEN_CONSTANTS.LEFT_PADDING and 
               x + circleSize/2 <= SCREEN_CONSTANTS.WIDTH - SCREEN_CONSTANTS.RIGHT_PADDING then
                table.insert(self.gridCells, {x = x, y = y, row = row, col = col})
                self.gridLookup[row][col] = cellIndex
                cellIndex = cellIndex + 1
            end
        end
    end
    
    self.totalRows = totalRows
    self.maxCols = GRID_CONSTANTS.MAX_COLS
end

function BubbleState:loadBubbleSprites()
    self.spriteSheets = {}
    
    for assetType, fileName in pairs(SPRITE_FILES) do
        local sheetPath = "assets/sprites/" .. fileName .. ".png"
        local success, sheet = pcall(gfx.image.new, sheetPath)
        
        if success and sheet then
            self.spriteSheets[assetType] = sheet
        else
            self.spriteSheets[assetType] = nil
        end
    end
end

function BubbleState:generateNewProjectile()
    -- Only generate basic bubbles for shooting
    local projectileType = "basic"
    local bubbleType = math.random(1, 5)
    
    self.currentProjectile = {
        type = projectileType,
        bubbleType = bubbleType,
        x = self.shooterX,
        y = self.shooterY,
        moving = false
    }
end

function BubbleState:generateInitialBubbles()
    print("DEBUG: Generating initial bubbles with new merge layout")
    
    -- Randomly assign basic types 1-5 to groups A-E
    local basicTypes = {1, 2, 3, 4, 5}
    local shuffledTypes = {}
    
    -- Shuffle the types
    for i = 1, 5 do
        local randomIndex = math.random(#basicTypes)
        table.insert(shuffledTypes, basicTypes[randomIndex])
        table.remove(basicTypes, randomIndex)
    end
    
    local basicA, basicB, basicC, basicD, basicE = shuffledTypes[1], shuffledTypes[2], shuffledTypes[3], shuffledTypes[4], shuffledTypes[5]
    print("DEBUG: Assigned types - A:", basicA, "B:", basicB, "C:", basicC, "D:", basicD, "E:", basicE)
    
    -- Group 1: 4x BasicA in 1,1 1,2 2,1 2,2
    local group1Positions = {{1,1}, {1,2}, {2,1}, {2,2}}
    for _, pos in ipairs(group1Positions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed BasicA", basicA, "at", pos[1], pos[2])
        end
    end
    
    -- Group 2: 4x BasicB in 4,1 4,2 5,1 5,2
    local group2Positions = {{4,1}, {4,2}, {5,1}, {5,2}}
    for _, pos in ipairs(group2Positions) do
        local asset = self:placeAssetDirect("basic", basicB, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed BasicB", basicB, "at", pos[1], pos[2])
        end
    end
    
    -- Group 3: 5x BasicC in 7,1 7,2 8,1 9,1 9,2
    local group3Positions = {{7,1}, {7,2}, {8,1}, {9,1}, {9,2}}
    for _, pos in ipairs(group3Positions) do
        local asset = self:placeAssetDirect("basic", basicC, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed BasicC", basicC, "at", pos[1], pos[2])
        end
    end
    
    -- Group 4: 4x BasicD in 11,1 11,2 12,1 12,2
    local group4Positions = {{11,1}, {11,2}, {12,1}, {12,2}}
    for _, pos in ipairs(group4Positions) do
        local asset = self:placeAssetDirect("basic", basicD, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed BasicD", basicD, "at", pos[1], pos[2])
        end
    end
    
    -- Group 5: 4x BasicE in 14,1 14,2 15,1 15,2
    local group5Positions = {{14,1}, {14,2}, {15,1}, {15,2}}
    for _, pos in ipairs(group5Positions) do
        local asset = self:placeAssetDirect("basic", basicE, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed BasicE", basicE, "at", pos[1], pos[2])
        end
    end
    
    -- Middle row: BasicA in 8,2 8,3 and BasicE in 8,6 8,7
    local middleAPositions = {{8,2}, {8,3}}
    for _, pos in ipairs(middleAPositions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed middle BasicA", basicA, "at", pos[1], pos[2])
        end
    end
    
    local middleEPositions = {{8,6}, {8,7}}
    for _, pos in ipairs(middleEPositions) do
        local asset = self:placeAssetDirect("basic", basicE, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed middle BasicE", basicE, "at", pos[1], pos[2])
        end
    end
    
    -- Additional placements: Basic E at 3,1 3,2
    local additionalEPositions = {{3,1}, {3,2}}
    for _, pos in ipairs(additionalEPositions) do
        local asset = self:placeAssetDirect("basic", basicE, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed additional BasicE", basicE, "at", pos[1], pos[2])
        end
    end
    
    -- Additional placements: Basic A at 13,1 13,2
    local additionalAPositions = {{13,1}, {13,2}}
    for _, pos in ipairs(additionalAPositions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed additional BasicA", basicA, "at", pos[1], pos[2])
        end
    end
    
    -- Additional placements: Basic B at 10,1 10,2
    local additionalBPositions = {{10,1}, {10,2}}
    for _, pos in ipairs(additionalBPositions) do
        local asset = self:placeAssetDirect("basic", basicB, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed additional BasicB", basicB, "at", pos[1], pos[2])
        end
    end
    
    -- Additional placements: Basic D at 6,1 6,2
    local additionalDPositions = {{6,1}, {6,2}}
    for _, pos in ipairs(additionalDPositions) do
        local asset = self:placeAssetDirect("basic", basicD, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed additional BasicD", basicD, "at", pos[1], pos[2])
        end
    end
    
    -- Additional placements: Basic A at 7,3 7,4 9,3 9,4
    local moreAPositions = {{7,3}, {7,4}, {9,3}, {9,4}}
    for _, pos in ipairs(moreAPositions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed more BasicA", basicA, "at", pos[1], pos[2])
        end
    end
    
    -- Center cluster: Basic C at 7,5 7,6 8,4 8,5 9,5 9,6
    local centerCPositions = {{7,5}, {7,6}, {8,4}, {8,5}, {9,5}, {9,6}}
    for _, pos in ipairs(centerCPositions) do
        local asset = self:placeAssetDirect("basic", basicC, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed center BasicC", basicC, "at", pos[1], pos[2])
        end
    end
    
    -- Corner groups: BasicD in 1,7 1,8 2,7 and BasicB in 15,7 15,8 14,7 (removed 2,6 and 14,6)
    local cornerDPositions = {{1,7}, {1,8}, {2,7}}
    for _, pos in ipairs(cornerDPositions) do
        local asset = self:placeAssetDirect("basic", basicD, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed corner BasicD", basicD, "at", pos[1], pos[2])
        end
    end
    
    local cornerBPositions = {{15,7}, {15,8}, {14,7}}
    for _, pos in ipairs(cornerBPositions) do
        local asset = self:placeAssetDirect("basic", basicB, pos[1], pos[2])
        if asset then
            print("DEBUG: Placed corner BasicB", basicB, "at", pos[1], pos[2])
        end
    end
    
    local assetCount = 0
    for _ in pairs(self.assets) do
        assetCount = assetCount + 1
    end
    print("DEBUG: Total assets after new merge layout:", assetCount)
end

-- Grid helper functions
function BubbleState:getCellAtRowCol(row, col)
    if not self.gridLookup[row] or not self.gridLookup[row][col] then
        return nil
    end
    local index = self.gridLookup[row][col]
    return self.gridCells[index]
end

function BubbleState:getCellIndex(row, col)
    if not self.gridLookup[row] or not self.gridLookup[row][col] then
        return nil
    end
    return self.gridLookup[row][col]
end

function BubbleState:isValidCell(row, col)
    return row >= 1 and row <= self.totalRows and 
           col >= 1 and col <= self.rowLengths[row] and
           self.gridLookup[row] and self.gridLookup[row][col]
end

function BubbleState:markCellOccupied(row, col, assetId)
    local cellIndex = self:getCellIndex(row, col)
    if cellIndex then
        self.occupiedBy[cellIndex] = assetId
    end
end

function BubbleState:isCellOccupied(row, col)
    local cellIndex = self:getCellIndex(row, col)
    if not cellIndex then return true end
    return self.occupiedBy[cellIndex] ~= nil
end

function BubbleState:findPatternCells(assetType, anchorRow, anchorCol)
    local templates = PATTERN_TEMPLATES[assetType]
    if not templates then return {} end
    
    local anchorStagger = getHexStagger(anchorRow)
    local template = (anchorStagger == 0) and templates.odd or templates.even
    
    local result = {}
    
    for _, delta in ipairs(template) do
        local targetRow = anchorRow + delta.deltaRow
        local targetCol = anchorCol + delta.deltaCol
        
        if self:isValidCell(targetRow, targetCol) then
            table.insert(result, {
                row = targetRow,
                col = targetCol,
                index = self:getCellIndex(targetRow, targetCol)
            })
        end
    end
    
    return result
end

function BubbleState:canPlaceAsset(assetType, row, col)
    local patternCells = self:findPatternCells(assetType, row, col)
    local definition = ASSET_DEFINITIONS[assetType]
    
    if not patternCells or #patternCells ~= definition.cellCount then
        return false
    end
    
    for _, cellInfo in ipairs(patternCells) do
        if self:isCellOccupied(cellInfo.row, cellInfo.col) then
            return false
        end
    end
    
    return true
end

function BubbleState:placeAssetDirect(assetType, bubbleType, row, col)
    local patternCells = self:findPatternCells(assetType, row, col)
    if not patternCells or #patternCells == 0 then
        return nil
    end
    
    local asset = self:createAsset(assetType, bubbleType, row, col)
    if not asset then
        return nil
    end
    
    for _, cellInfo in ipairs(patternCells) do
        self:markCellOccupied(cellInfo.row, cellInfo.col, asset.id)
    end
    
    asset.patternCells = patternCells
    self.assets[asset.id] = asset
    
    return asset
end

function BubbleState:createAsset(assetType, bubbleType, row, col)
    local definition = ASSET_DEFINITIONS[assetType]
    if not definition then return nil end
    
    local anchorCell = self:getCellAtRowCol(row, col)
    if not anchorCell then return nil end
    
    local centerX, centerY = self:calculateAssetCenter(assetType, row, col)
    if not centerX then return nil end
    
    local assetId = self.nextAssetId
    self.nextAssetId = self.nextAssetId + 1
    
    return {
        id = assetId,
        type = assetType,
        bubbleType = bubbleType,
        x = centerX,
        y = centerY,
        anchorRow = row,
        anchorCol = col,
    }
end

function BubbleState:calculateAssetCenter(assetType, row, col)
    local anchorCell = self:getCellAtRowCol(row, col)
    if not anchorCell then return 0, 0 end
    
    if assetType == "basic" then
        return anchorCell.x, anchorCell.y
    elseif assetType == "tierTwo" or assetType == "tierThree" then
        return anchorCell.x, anchorCell.y
    elseif assetType == "tierOne" then
        local anchorStagger = getHexStagger(row)
        local topLeftCell
        
        if anchorStagger == 0 then
            topLeftCell = self:getCellAtRowCol(row - 1, col - 1)
        else
            topLeftCell = self:getCellAtRowCol(row - 1, col)
        end
        
        if not topLeftCell then 
            return anchorCell.x, anchorCell.y
        end
        
        local anchorTopLeftX = topLeftCell.x - 10
        local anchorTopLeftY = topLeftCell.y - 8
        local spriteCenterX = anchorTopLeftX + 25
        local spriteCenterY = anchorTopLeftY + 16
        
        return spriteCenterX, spriteCenterY
    end
    
    return anchorCell.x, anchorCell.y
end

-- Optimized collision detection using squared distance
function BubbleState:getBubbleCollisionRadius(bubbleType)
    local definition = ASSET_DEFINITIONS[bubbleType]
    if definition and definition.collisionRadius then
        return definition.collisionRadius - 5  -- 5px reduction for all types
    end
    return 15
end

function BubbleState:wouldProjectileCollide(testX, testY)
    local projectileRadius = self:getBubbleCollisionRadius(self.currentProjectile.type)
    
    for _, asset in pairs(self.assets) do
        local existingRadius = self:getBubbleCollisionRadius(asset.type)
        
        -- Use reduced tolerance for Tier 1 projectiles only
        local tolerance = (self.currentProjectile.bubbleType >= 11 and self.currentProjectile.bubbleType <= 15) and 1 or 3
        local requiredDistance = projectileRadius + existingRadius + tolerance
        local requiredDistanceSquared = requiredDistance * requiredDistance
        
        -- Use optimized squared distance comparison
        if distanceSquared(testX, testY, asset.x, asset.y) < requiredDistanceSquared then
            return true
        end
    end
    
    return false
end

-- Shooting system
function BubbleState:fireProjectile()
    if not self.currentProjectile or self.currentProjectile.moving then
        return
    end
    
    local radians = math.rad(self.shootingAngle)
    local dx = math.cos(radians)
    local dy = math.sin(radians)
    
    local placement = self:findPlacementAlongTrajectory(dx, dy)
    
    if placement and placement.gameOver then
        self.currentProjectile.moving = true
        self.currentProjectile.targetX = placement.x
        self.currentProjectile.targetY = placement.y
        self.currentProjectile.gameOverShot = true
        self.currentProjectile.stopOnly = placement.losingShotStop
    elseif placement then
        self.currentProjectile.moving = true
        self.currentProjectile.targetX = placement.x
        self.currentProjectile.targetY = placement.y
        self.currentProjectile.targetRow = placement.row
        self.currentProjectile.targetCol = placement.col
    end
end

function BubbleState:findPlacementAlongTrajectory(dx, dy)
    local startX = self.shooterX
    local startY = self.shooterY
    local stepSize = TRAJECTORY_CONSTANTS.STEP_SIZE
    local maxDistance = TRAJECTORY_CONSTANTS.MAX_DISTANCE
    local lastValidPosition = nil
    
    for distance = stepSize, maxDistance, stepSize do
        local testX = startX + dx * distance  
        local testY = startY + dy * distance
        
        -- Screen bounds check
        if testX < -20 or testX > SCREEN_CONSTANTS.WIDTH + 20 or 
           testY < -20 or testY > SCREEN_CONSTANTS.HEIGHT + 20 then
            break
        end
        
        -- Back edge (left) - stick to it
        if testX <= SCREEN_CONSTANTS.LEFT_PADDING + BOUNDARY_CONSTANTS.LEFT_BOUND_MARGIN then
            return self:findNearestValidPlacement(testX, testY)
        end
        
        -- Top/bottom edges - just check for collision, don't bounce in trajectory calculation
        -- The actual bouncing will be handled in the projectile movement
        if testY <= BOUNDARY_CONSTANTS.TOP_BOUND or testY >= BOUNDARY_CONSTANTS.BOTTOM_BOUND then
            -- For now, just continue the trajectory - bouncing is complex to calculate here
            -- We'll handle this in the actual projectile movement
        end
        
        -- Bubble collision check
        if testX >= SCREEN_CONSTANTS.LEFT_PADDING and testX <= SCREEN_CONSTANTS.WIDTH - SCREEN_CONSTANTS.RIGHT_PADDING then
            if self:wouldProjectileCollide(testX, testY) then
                if lastValidPosition then
                    return self:findNearestValidPlacement(lastValidPosition.x, lastValidPosition.y)
                else
                    return self:findNearestValidPlacement(testX, testY)
                end
            else
                lastValidPosition = {x = testX, y = testY}
            end
        end
    end
    
    if lastValidPosition then
        local placement = self:findNearestValidPlacement(lastValidPosition.x, lastValidPosition.y)
        if placement then
            return placement
        else
            return {
                gameOver = true, 
                losingShotStop = true,
                x = lastValidPosition.x,
                y = lastValidPosition.y
            }
        end
    end
    
    return {gameOver = true, losingShotStop = true, x = startX + dx * 100, y = startY + dy * 100}
end

-- Optimized placement search using squared distance
function BubbleState:findNearestValidPlacement(collisionX, collisionY)
    local bestPlacement = nil
    local bestDistanceSquared = math.huge
    local maxSearchRadius = TRAJECTORY_CONSTANTS.MAX_SEARCH_RADIUS
    local maxSearchRadiusSquared = maxSearchRadius * maxSearchRadius
    
    for _, cell in ipairs(self.gridCells) do
        local distSquared = distanceSquared(cell.x, cell.y, collisionX, collisionY)
        
        if distSquared <= maxSearchRadiusSquared then
            local isValid = self:canPlaceAsset(self.currentProjectile.type, cell.row, cell.col)
            
            if isValid and distSquared < bestDistanceSquared then
                bestDistanceSquared = distSquared
                bestPlacement = {
                    x = cell.x,
                    y = cell.y,
                    row = cell.row,
                    col = cell.col
                }
            end
        end
    end
    
    return bestPlacement
end

function BubbleState:updateProjectileMovement()
    local projectile = self.currentProjectile
    if not projectile or not projectile.moving then
        return
    end
    
    -- Initialize velocity if not set
    if not projectile.velocityX then
        local dx = projectile.targetX - projectile.x
        local dy = projectile.targetY - projectile.y
        local dist = distance(projectile.x, projectile.y, projectile.targetX, projectile.targetY)
        projectile.velocityX = (dx / dist) * SHOOTER_CONSTANTS.SPEED
        projectile.velocityY = (dy / dist) * SHOOTER_CONSTANTS.SPEED
    end
    
    -- Calculate next position
    local nextX = projectile.x + projectile.velocityX
    local nextY = projectile.y + projectile.velocityY
    
    -- Check for bubble collision FIRST (before boundary checks)
    if self:wouldProjectileCollide(nextX, nextY) then
        local placement = self:findNearestValidPlacement(projectile.x, projectile.y)
        if placement then
            projectile.x = placement.x
            projectile.y = placement.y
            projectile.targetRow = placement.row
            projectile.targetCol = placement.col
            self:placeAssetDirect(projectile.type, projectile.bubbleType, 
                                placement.row, placement.col)
            self:generateNewProjectile()
            return
        end
    end
    
    -- Check for back edge collision (left side)
    if nextX <= SCREEN_CONSTANTS.LEFT_PADDING + BOUNDARY_CONSTANTS.LEFT_BOUND_MARGIN then
        local placement = self:findNearestValidPlacement(nextX, nextY)
        if placement then
            projectile.x = placement.x
            projectile.y = placement.y
            projectile.targetRow = placement.row
            projectile.targetCol = placement.col
            self:placeAssetDirect(projectile.type, projectile.bubbleType, 
                                placement.row, placement.col)
            self:generateNewProjectile()
            return
        end
    end
    
    -- Check for bouncing off top/bottom boundaries LAST
    -- Use hard screen edges for bouncing (0 and SCREEN_HEIGHT)
    local projectileRadius = self:getBubbleCollisionRadius(self.currentProjectile.type)
    local hardTopEdge = projectileRadius
    local hardBottomEdge = SCREEN_CONSTANTS.HEIGHT - projectileRadius
    
    if nextY <= hardTopEdge then
        nextY = hardTopEdge + (hardTopEdge - nextY)
        projectile.velocityY = -projectile.velocityY  -- Reverse Y velocity
    elseif nextY >= hardBottomEdge then
        nextY = hardBottomEdge - (nextY - hardBottomEdge)
        projectile.velocityY = -projectile.velocityY  -- Reverse Y velocity
    end
    
    -- Update position
    projectile.x = nextX
    projectile.y = nextY
end

function BubbleState:drawAsset(asset)
    local definition = ASSET_DEFINITIONS[asset.type]
    local spriteSheet = self.spriteSheets[asset.type]
    
    if not definition or not spriteSheet then
        return
    end
    
    local sprite = definition.sprite
    
    if asset.bubbleType < 1 or asset.bubbleType > sprite.count then
        return
    end
    
    local sourceX = (asset.bubbleType - 1) * sprite.width
    local drawX = math.floor(asset.x - sprite.width / 2)
    local drawY = math.floor(asset.y - sprite.height / 2)
    
    gfx.setClipRect(drawX, drawY, sprite.width, sprite.height)
    spriteSheet:draw(drawX - sourceX, drawY)
    gfx.clearClipRect()
end

function BubbleState:resetGame()
    self.gameOver = false
    self.assets = {}
    self.occupiedBy = {}
    self.nextAssetId = 1
    self.shootingAngle = SHOOTER_CONSTANTS.DEFAULT_ANGLE
    
    -- Pre-place random basic bubbles
    self:generateInitialBubbles()
    self:generateNewProjectile()
end

function BubbleState:enter()
    self:resetGame()
end

function BubbleState:exit()
end

function BubbleState:update()
    if self.gameOver then
        if pd.buttonJustPressed(pd.kButtonA) then
            self:resetGame()
            return "menu"
        end
        return nil
    end
    
    -- Optimized input handling with constants
    if pd.buttonIsPressed(pd.kButtonUp) then
        self.shootingAngle = clamp(self.shootingAngle + SHOOTER_CONSTANTS.ANGLE_STEP, 
                                  SHOOTER_CONSTANTS.MIN_ANGLE, SHOOTER_CONSTANTS.MAX_ANGLE)
    end
    if pd.buttonIsPressed(pd.kButtonDown) then
        self.shootingAngle = clamp(self.shootingAngle - SHOOTER_CONSTANTS.ANGLE_STEP, 
                                  SHOOTER_CONSTANTS.MIN_ANGLE, SHOOTER_CONSTANTS.MAX_ANGLE)
    end
    
    if pd.buttonJustPressed(pd.kButtonA) then
        self:fireProjectile()
    end
    
    if self.currentProjectile and self.currentProjectile.moving then
        self:updateProjectileMovement()
    end
    
    return nil
end

function BubbleState:draw()
    gfx.clear()
    
    if self.gameOver then
        self:drawGameOver()
        return
    end
    
    self:drawBoundaries()
    
    -- Debug: render all grid circles (hidden for now)
    -- for _, cell in ipairs(self.gridCells) do
    --     gfx.drawCircleAtPoint(cell.x, cell.y, GRID_CONSTANTS.CIRCLE_SIZE/2)
    -- end
    
    -- Draw all placed assets
    for _, asset in pairs(self.assets) do
        self:drawAsset(asset)
    end
    
    if self.currentProjectile then
        self:drawAimingLine()
        self:drawProjectile()
    end
end

function BubbleState:drawBoundaries()
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    
    local leftLineX = SCREEN_CONSTANTS.LEFT_PADDING - BOUNDARY_CONSTANTS.BOUNDARY_OFFSET
    local rightLineX = SCREEN_CONSTANTS.WIDTH - SCREEN_CONSTANTS.RIGHT_PADDING + BOUNDARY_CONSTANTS.BOUNDARY_OFFSET
    
    for y = 0, SCREEN_CONSTANTS.HEIGHT, BOUNDARY_CONSTANTS.LINE_DASH_STEP do
        gfx.drawLine(leftLineX, y, leftLineX, math.min(y + BOUNDARY_CONSTANTS.LINE_DASH_LENGTH, SCREEN_CONSTANTS.HEIGHT))
    end
    
    for y = 0, SCREEN_CONSTANTS.HEIGHT, BOUNDARY_CONSTANTS.LINE_DASH_STEP do
        gfx.drawLine(rightLineX, y, rightLineX, math.min(y + BOUNDARY_CONSTANTS.LINE_DASH_LENGTH, SCREEN_CONSTANTS.HEIGHT))
    end
end

function BubbleState:drawGameOver()
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(50, 80, 300, 80)
    gfx.setColor(gfx.kColorWhite)
    gfx.drawRect(50, 80, 300, 80)
    
    gfx.setFont(gfx.getSystemFont(gfx.kFontVariantBold))
    gfx.drawTextAligned("Game Over!", 200, 100, kTextAlignment.center)
    
    gfx.setFont(gfx.getSystemFont(gfx.kFontVariantNormal))
    gfx.drawTextAligned("Press A to return to menu", 200, 130, kTextAlignment.center)
end

function BubbleState:drawAimingLine()
    local radians = math.rad(self.shootingAngle)
    local projectileRadius = self:getBubbleCollisionRadius(self.currentProjectile.type)
    local lineLength = 40 + projectileRadius
    local endX = self.shooterX + math.cos(radians) * lineLength
    local endY = self.shooterY + math.sin(radians) * lineLength
    
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(self.shooterX, self.shooterY, endX, endY)
end

function BubbleState:drawProjectile()
    if not self.currentProjectile then return end
    
    local tempAsset = {
        type = self.currentProjectile.type,
        bubbleType = self.currentProjectile.bubbleType,
        x = self.currentProjectile.x,
        y = self.currentProjectile.y
    }
    
    self:drawAsset(tempAsset)
end