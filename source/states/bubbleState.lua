-- Bubble State: Core game state with refactored merge and placement systems
-- Now uses modular systems for better code organization

import "CoreLibs/graphics"
import "game/mergeSystem"
import "game/placementSystem"
import "game/cascadeSystem"

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
    
    -- Initialize modular systems
    state.mergeSystem = MergeSystem:new()
    state.placementSystem = PlacementSystem:new()
    state.cascadeSystem = CascadeSystem:new()
    
    -- Shooter system
    state.shooterX = SCREEN_CONSTANTS.WIDTH - SHOOTER_CONSTANTS.X_OFFSET
    state.shooterY = SHOOTER_CONSTANTS.Y_POSITION
    state.shootingAngle = SHOOTER_CONSTANTS.DEFAULT_ANGLE
    state.currentProjectile = nil
    
    -- Game state
    state.gameOver = false
    state.debugMode = false  -- Debug visualization toggle
    
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
    
    -- Group 1: 4x BasicA in 1,1 1,2 2,1 2,2
    local group1Positions = {{1,1}, {1,2}, {2,1}, {2,2}}
    for _, pos in ipairs(group1Positions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
    end
    
    -- Group 2: 4x BasicB in 4,1 4,2 5,1 5,2
    local group2Positions = {{4,1}, {4,2}, {5,1}, {5,2}}
    for _, pos in ipairs(group2Positions) do
        local asset = self:placeAssetDirect("basic", basicB, pos[1], pos[2])
    end
    
    -- Group 3: 5x BasicC in 7,1 7,2 8,1 9,1 9,2
    local group3Positions = {{7,1}, {7,2}, {8,1}, {9,1}, {9,2}}
    for _, pos in ipairs(group3Positions) do
        local asset = self:placeAssetDirect("basic", basicC, pos[1], pos[2])
    end
    
    -- Group 4: 4x BasicD in 11,1 11,2 12,1 12,2
    local group4Positions = {{11,1}, {11,2}, {12,1}, {12,2}}
    for _, pos in ipairs(group4Positions) do
        local asset = self:placeAssetDirect("basic", basicD, pos[1], pos[2])
    end
    
    -- Group 5: 4x BasicE in 14,1 14,2 15,1 15,2
    local group5Positions = {{14,1}, {14,2}, {15,1}, {15,2}}
    for _, pos in ipairs(group5Positions) do
        local asset = self:placeAssetDirect("basic", basicE, pos[1], pos[2])
    end
    
    -- Middle row: BasicA in 8,2 8,3 and BasicE in 8,6 8,7
    local middleAPositions = {{8,2}, {8,3}}
    for _, pos in ipairs(middleAPositions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
    end
    
    local middleEPositions = {{8,6}, {8,7}}
    for _, pos in ipairs(middleEPositions) do
        local asset = self:placeAssetDirect("basic", basicE, pos[1], pos[2])
    end
    
    -- Additional placements: Basic E at 3,1 3,2
    local additionalEPositions = {{3,1}, {3,2}}
    for _, pos in ipairs(additionalEPositions) do
        local asset = self:placeAssetDirect("basic", basicE, pos[1], pos[2])
    end
    
    -- Additional placements: Basic A at 13,1 13,2
    local additionalAPositions = {{13,1}, {13,2}}
    for _, pos in ipairs(additionalAPositions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
    end
    
    -- Additional placements: Basic B at 10,1 10,2
    local additionalBPositions = {{10,1}, {10,2}}
    for _, pos in ipairs(additionalBPositions) do
        local asset = self:placeAssetDirect("basic", basicB, pos[1], pos[2])
    end
    
    -- Additional placements: Basic D at 6,1 6,2
    local additionalDPositions = {{6,1}, {6,2}}
    for _, pos in ipairs(additionalDPositions) do
        local asset = self:placeAssetDirect("basic", basicD, pos[1], pos[2])
    end
    
    -- Additional placements: Basic A at 7,3 7,4 9,3 9,4
    local moreAPositions = {{7,3}, {7,4}, {9,3}, {9,4}}
    for _, pos in ipairs(moreAPositions) do
        local asset = self:placeAssetDirect("basic", basicA, pos[1], pos[2])
    end
    
    -- Center cluster: Basic C at 7,5 7,6 8,4 8,5 9,5 9,6
    local centerCPositions = {{7,5}, {7,6}, {8,4}, {8,5}, {9,5}, {9,6}}
    for _, pos in ipairs(centerCPositions) do
        local asset = self:placeAssetDirect("basic", basicC, pos[1], pos[2])
    end
    
    -- Corner groups removed per user request
    
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

function BubbleState:getCellOccupant(row, col)
    local cellIndex = self:getCellIndex(row, col)
    if not cellIndex then return nil end
    return self.occupiedBy[cellIndex]
end

function BubbleState:clearCellOccupation(row, col)
    local cellIndex = self:getCellIndex(row, col)
    if cellIndex then
        self.occupiedBy[cellIndex] = nil
    end
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
            -- Debug: show which cell is blocking placement
            local occupantId = self:getCellOccupant(cellInfo.row, cellInfo.col)
            local occupant = occupantId and self.assets[occupantId]
            if occupant then
                print("DEBUG: Cell", cellInfo.row, cellInfo.col, "is occupied by asset", occupantId, "type", occupant.type, occupant.bubbleType)
            else
                print("DEBUG: Cell", cellInfo.row, cellInfo.col, "is marked occupied but no asset found")
            end
            return false
        end
    end
    
    return true
end

function BubbleState:placeAssetDirect(assetType, bubbleType, row, col, checkMerges)
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
    
    -- Check for merges only if requested (e.g., from projectile placement, not level init)
    if checkMerges then
        print("DEBUG: Checking for merges on newly placed", asset.type, "type", asset.bubbleType, "at", asset.anchorRow, asset.anchorCol)
        local mergeInfo = self.mergeSystem:checkForMerges(asset, self, self.cascadeSystem)
        if mergeInfo then
            print("DEBUG: Merge detected! Executing merge...")
            local newAsset = self.mergeSystem:executeMerge(mergeInfo, self, self.placementSystem)
            if newAsset then
                self.cascadeSystem:scheduleCascadeMerge(newAsset)
            end
        end
    end
    
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
-- Merge Detection System
function BubbleState:findAdjacentBubbles(startRow, startCol, targetBubbleType)
    local adjacent = {}
    local visited = {}
    local queue = {{row = startRow, col = startCol}}
    
    print("DEBUG: Finding connected bubbles of type", targetBubbleType, "from", startRow, startCol)
    
    -- Get all adjacent cells using proper hex grid directions
    local function getHexNeighbors(row, col)
        local neighbors = {}
        
        -- In a hex grid, adjacency depends on whether the row is staggered (odd/even)
        local stagger = ((row - 1) % 2)  -- 0 for even rows (1-indexed), 1 for odd rows
        local directions
        
        if stagger == 0 then
            -- Even rows: left column is aligned
            directions = {
                {-1, -1}, {-1, 0},  -- Above row (left-up, right-up)
                {0, -1},  {0, 1},   -- Same row (left, right)
                {1, -1},  {1, 0}    -- Below row (left-down, right-down)
            }
        else
            -- Odd rows: right column is aligned  
            directions = {
                {-1, 0}, {-1, 1},   -- Above row (left-up, right-up)
                {0, -1}, {0, 1},    -- Same row (left, right)
                {1, 0},  {1, 1}     -- Below row (left-down, right-down)
            }
        end
        
        for _, dir in ipairs(directions) do
            local checkRow = row + dir[1]
            local checkCol = col + dir[2]
            if self:isValidCell(checkRow, checkCol) then
                table.insert(neighbors, {row = checkRow, col = checkCol})
            end
        end
        return neighbors
    end
    
    -- Breadth-first search for connected bubbles of same type (only through same-type bubbles)
    while #queue > 0 do
        local current = table.remove(queue, 1)
        local key = current.row .. "," .. current.col
        
        if visited[key] then
            goto continue
        end
        visited[key] = true
        
        -- Check what's in this cell
        local occupant = self:getCellOccupant(current.row, current.col)
        if occupant then
            local asset = self.assets[occupant]
            -- Only match basic bubbles with same bubble type (not Tier 1+ bubbles)
            if asset and asset.type == "basic" and asset.bubbleType == targetBubbleType then
                -- Found a matching basic bubble - add it to results
                table.insert(adjacent, {
                    row = current.row,
                    col = current.col,
                    asset = asset
                })
                
                -- Only continue search through neighboring cells that contain same basic type bubbles
                -- DO NOT traverse through empty cells - this prevents long-distance connections
                local neighbors = getHexNeighbors(current.row, current.col)
                for _, neighbor in ipairs(neighbors) do
                    local neighborKey = neighbor.row .. "," .. neighbor.col
                    if not visited[neighborKey] then
                        local neighborOccupant = self:getCellOccupant(neighbor.row, neighbor.col)
                        if neighborOccupant then
                            local neighborAsset = self.assets[neighborOccupant]
                            -- Only add to queue if neighbor is same basic type (no Tier 1+)
                            if neighborAsset and neighborAsset.type == "basic" and neighborAsset.bubbleType == targetBubbleType then
                                table.insert(queue, neighbor)
                            end
                        end
                        -- Skip empty cells - no traversal through them
                    end
                end
            end
            -- If different type or not basic, stop here - don't traverse through
        end
        -- If empty cell, stop here - don't traverse through
        
        ::continue::
    end
    
    print("DEBUG: Found", #adjacent, "directly connected basic bubbles of type", targetBubbleType)
    if #adjacent > 0 then
        local idList = {}
        for i, bubble in ipairs(adjacent) do
            table.insert(idList, bubble.asset.id)
            if i >= 5 then -- Limit to first 5 for readability
                table.insert(idList, "...")
                break
            end
        end
        print("DEBUG: Connected bubble IDs:", table.concat(idList, ", "))
    end
    
    return adjacent
end


function BubbleState:checkForBasicMerges(placedAsset)
    if not placedAsset or placedAsset.type ~= "basic" then return nil end
    
    -- Find all connected bubbles of the same type as the placed bubble
    local connectedBubbles = self:findAdjacentBubbles(
        placedAsset.anchorRow, 
        placedAsset.anchorCol, 
        placedAsset.bubbleType
    )
    
    -- Verify that the placed bubble is actually in the connected group
    local placedBubbleIncluded = false
    for _, bubble in ipairs(connectedBubbles) do
        if bubble.asset.id == placedAsset.id then
            placedBubbleIncluded = true
            break
        end
    end
    
    if not placedBubbleIncluded then
        print("DEBUG: ERROR - placed bubble", placedAsset.id, "not found in connected group! This shouldn't happen.")
        return nil
    end
    
    print("DEBUG: Placed bubble", placedAsset.id, "is included in connected group of", #connectedBubbles, "bubbles")
    
    -- Need at least 3 bubbles for a merge
    if #connectedBubbles >= 3 then
        -- Determine the target Tier 1 bubble type based on basic type
        local tierOneBubbleType = self:getResultingBubbleType(placedAsset.bubbleType, 3)
        if tierOneBubbleType then
            -- Create proper bubble data structure for the placed bubble
            local placedBubbleData = {
                row = placedAsset.anchorRow,
                col = placedAsset.anchorCol,
                asset = placedAsset,
                distanceFromShot = 0  -- The shot bubble has 0 distance from itself
            }
            
            return {
                bubblesToRemove = connectedBubbles,
                newBubbleType = tierOneBubbleType,
                placedBubble = placedBubbleData,
                resultTier = "tierOne"
            }
        end
    end
    
    return nil
end

-- Check for Tier 2 merges (e.g., Flame + Rain = Steam)
function BubbleState:checkForTierTwoMerges(placedAsset)
    if not placedAsset or placedAsset.type ~= "tierOne" then return nil end
    
    print("DEBUG: Checking for Tier 2 merges with placed", placedAsset.type, "type", placedAsset.bubbleType, "at", placedAsset.anchorRow, placedAsset.anchorCol)
    
    -- Find all adjacent tier 1 bubbles that can combine with this one
    local adjacentTierOnes = self:findAdjacentTierOneBubbles(placedAsset.anchorRow, placedAsset.anchorCol)
    
    -- ALSO find adjacent tier 2 bubbles for potential Tier 3 combinations
    local adjacentTierTwos = self:findAdjacentTierTwoBubbles(placedAsset.anchorRow, placedAsset.anchorCol)
    
    -- Check each adjacent Tier 1 bubble for valid Tier 2 combinations
    for _, adjacentBubble in ipairs(adjacentTierOnes) do
        print("DEBUG: Testing Tier 2 combination:", placedAsset.bubbleType, "+", adjacentBubble.asset.bubbleType)
        local resultType = self:getTierTwoCombination(placedAsset.bubbleType, adjacentBubble.asset.bubbleType)
        if resultType then
            print("DEBUG: Found Tier 2 combination:", placedAsset.bubbleType, "+", adjacentBubble.asset.bubbleType, "=", resultType)
            
            -- Create merge info for the two bubbles
            local placedBubbleData = {
                row = placedAsset.anchorRow,
                col = placedAsset.anchorCol,
                asset = placedAsset,
                distanceFromShot = 0
            }
            
            return {
                bubblesToRemove = {placedBubbleData, adjacentBubble},
                newBubbleType = resultType,
                placedBubble = placedBubbleData,
                resultTier = "tierTwo"
            }
        else
            print("DEBUG: No Tier 2 combination found for", placedAsset.bubbleType, "+", adjacentBubble.asset.bubbleType)
        end
    end
    
    -- Check each adjacent Tier 2 bubble for valid Tier 3 combinations
    for _, adjacentBubble in ipairs(adjacentTierTwos) do
        print("DEBUG: Testing Tier 3 combination:", adjacentBubble.asset.bubbleType, "+", placedAsset.bubbleType)
        local resultType = self:getTierThreeCombination(adjacentBubble.asset.bubbleType, placedAsset.bubbleType)
        if resultType then
            print("DEBUG: Found Tier 3 combination:", adjacentBubble.asset.bubbleType, "+", placedAsset.bubbleType, "=", resultType)
            
            -- Create merge info for the two bubbles
            local placedBubbleData = {
                row = placedAsset.anchorRow,
                col = placedAsset.anchorCol,
                asset = placedAsset,
                distanceFromShot = 0
            }
            
            return {
                bubblesToRemove = {placedBubbleData, adjacentBubble},
                newBubbleType = resultType,
                placedBubble = placedBubbleData,
                resultTier = "tierThree"
            }
        else
            print("DEBUG: No Tier 3 combination found for", adjacentBubble.asset.bubbleType, "+", placedAsset.bubbleType)
        end
    end
    
    print("DEBUG: No Tier 2 merges found")
    return nil
end

-- Check for Tier 3 merges (e.g., Steam + Tremor = Geyser)
function BubbleState:checkForTierThreeMerges(placedAsset)
    if not placedAsset or placedAsset.type ~= "tierTwo" then return nil end
    
    print("DEBUG: Checking for Tier 3 merges with placed", placedAsset.type, "type", placedAsset.bubbleType)
    
    -- Find all adjacent tier 1 bubbles that can combine with this tier 2
    local adjacentTierOnes = self:findAdjacentTierOneBubbles(placedAsset.anchorRow, placedAsset.anchorCol)
    
    -- Check each adjacent bubble for valid Tier 3 combinations
    for _, adjacentBubble in ipairs(adjacentTierOnes) do
        local resultType = self:getTierThreeCombination(placedAsset.bubbleType, adjacentBubble.asset.bubbleType)
        if resultType then
            print("DEBUG: Found Tier 3 combination:", placedAsset.bubbleType, "+", adjacentBubble.asset.bubbleType, "=", resultType)
            
            local placedBubbleData = {
                row = placedAsset.anchorRow,
                col = placedAsset.anchorCol,
                asset = placedAsset,
                distanceFromShot = 0
            }
            
            return {
                bubblesToRemove = {placedBubbleData, adjacentBubble},
                newBubbleType = resultType,
                placedBubble = placedBubbleData,
                resultTier = "tierThree"
            }
        end
    end
    
    return nil
end

-- Find adjacent Tier 1 bubbles for higher-tier merging
function BubbleState:findAdjacentTierOneBubbles(centerRow, centerCol)
    local adjacentBubbles = {}
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    print("DEBUG: Looking for adjacent Tier 1 bubbles around", centerRow, centerCol)
    
    -- Get all cells occupied by the center asset (multi-cell tier 1s)
    local centerAssetId = self:getCellOccupant(centerRow, centerCol)
    local centerAsset = centerAssetId and self.assets[centerAssetId]
    
    print("DEBUG: Center asset lookup at", centerRow, centerCol, "->", centerAssetId and ("asset " .. centerAssetId) or "nil")
    
    if not centerAsset then
        print("DEBUG: No center asset found at", centerRow, centerCol)
        -- Let's debug what assets exist around this area
        print("DEBUG: Existing assets:")
        for id, asset in pairs(self.assets) do
            if asset.type == "tierOne" then
                print("DEBUG:  - Asset", id, asset.type, "bubbleType", asset.bubbleType, "at", asset.anchorRow, asset.anchorCol)
            end
        end
        return adjacentBubbles
    end
    
    -- Check all cells that the center asset occupies
    local centerCells = centerAsset.patternCells or {{row = centerRow, col = centerCol}}
    
    for _, centerCell in ipairs(centerCells) do
        for _, dir in ipairs(directions) do
            local checkRow = centerCell.row + dir[1]
            local checkCol = centerCell.col + dir[2]
            
            if self:isValidCell(checkRow, checkCol) then
                local occupantId = self:getCellOccupant(checkRow, checkCol)
                if occupantId and occupantId ~= centerAssetId then
                    local asset = self.assets[occupantId]
                    if asset and asset.type == "tierOne" then
                        -- Check if we already have this asset (avoid duplicates)
                        local alreadyAdded = false
                        for _, existing in ipairs(adjacentBubbles) do
                            if existing.asset.id == asset.id then
                                alreadyAdded = true
                                break
                            end
                        end
                        
                        if not alreadyAdded then
                            print("DEBUG: Found adjacent Tier 1:", asset.type, "bubbleType", asset.bubbleType, "at", asset.anchorRow, asset.anchorCol)
                            table.insert(adjacentBubbles, {
                                row = asset.anchorRow,
                                col = asset.anchorCol,
                                asset = asset,
                                distanceFromShot = 1
                            })
                        end
                    end
                end
            end
        end
    end
    
    print("DEBUG: Found", #adjacentBubbles, "adjacent Tier 1 bubbles")
    return adjacentBubbles
end

-- Find adjacent Tier 2 bubbles for potential Tier 3 combinations
function BubbleState:findAdjacentTierTwoBubbles(centerRow, centerCol)
    local adjacentBubbles = {}
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    print("DEBUG: Looking for adjacent Tier 2 bubbles around", centerRow, centerCol)
    
    -- Get all cells occupied by the center asset (multi-cell tier 1s)
    local centerAssetId = self:getCellOccupant(centerRow, centerCol)
    local centerAsset = centerAssetId and self.assets[centerAssetId]
    
    if not centerAsset then
        print("DEBUG: No center asset found at", centerRow, centerCol, "for Tier 2 search")
        return adjacentBubbles
    end
    
    -- Check all cells that the center asset occupies
    local centerCells = centerAsset.patternCells or {{row = centerRow, col = centerCol}}
    
    for _, centerCell in ipairs(centerCells) do
        for _, dir in ipairs(directions) do
            local checkRow = centerCell.row + dir[1]
            local checkCol = centerCell.col + dir[2]
            
            if self:isValidCell(checkRow, checkCol) then
                local occupantId = self:getCellOccupant(checkRow, checkCol)
                if occupantId and occupantId ~= centerAssetId then
                    local asset = self.assets[occupantId]
                    if asset and asset.type == "tierTwo" then
                        -- Check if we already have this asset (avoid duplicates)
                        local alreadyAdded = false
                        for _, existing in ipairs(adjacentBubbles) do
                            if existing.asset.id == asset.id then
                                alreadyAdded = true
                                break
                            end
                        end
                        
                        if not alreadyAdded then
                            table.insert(adjacentBubbles, {
                                row = asset.anchorRow,
                                col = asset.anchorCol,
                                asset = asset,
                                distanceFromShot = math.abs(asset.anchorRow - centerRow) + math.abs(asset.anchorCol - centerCol)
                            })
                            print("DEBUG: Found adjacent Tier 2 bubble:", asset.bubbleType, "at", asset.anchorRow, asset.anchorCol)
                        end
                    end
                end
            end
        end
    end
    
    print("DEBUG: Found", #adjacentBubbles, "adjacent Tier 2 bubbles")
    return adjacentBubbles
end

-- Get Tier 2 combination result from two Tier 1 types
function BubbleState:getTierTwoCombination(type1, type2)
    -- Check all possible combinations from constants
    local combinations = {
        ["6-7"] = 11,   -- Flame + Rain = Steam
        ["7-6"] = 11,   -- Rain + Flame = Steam (order doesn't matter)
        ["6-8"] = 12,   -- Flame + Tremor = Magma
        ["8-6"] = 12,   -- Tremor + Flame = Magma
        ["7-8"] = 13,   -- Rain + Tremor = Quicksand
        ["8-7"] = 13,   -- Tremor + Rain = Quicksand
        ["7-9"] = 14,   -- Rain + Gust = Downpour
        ["9-7"] = 14,   -- Gust + Rain = Downpour
        ["8-9"] = 15,   -- Tremor + Gust = Sandstorm
        ["9-8"] = 15,   -- Gust + Tremor = Sandstorm
        ["8-10"] = 16,  -- Tremor + Shock = Crystal
        ["10-8"] = 16,  -- Shock + Tremor = Crystal
        ["9-6"] = 17,   -- Gust + Flame = Wild Fire
        ["6-9"] = 17,   -- Flame + Gust = Wild Fire
        ["9-10"] = 18,  -- Gust + Shock = Thunderstorm
        ["10-9"] = 18,  -- Shock + Gust = Thunderstorm
        ["10-6"] = 19,  -- Shock + Flame = Explosion
        ["6-10"] = 19,  -- Flame + Shock = Explosion
        ["10-7"] = 20,  -- Shock + Rain = Chain Lightning
        ["7-10"] = 20   -- Rain + Shock = Chain Lightning
    }
    
    local key = type1 .. "-" .. type2
    return combinations[key]
end

-- Get Tier 3 combination result from Tier 2 + Tier 1
function BubbleState:getTierThreeCombination(tier2Type, tier1Type)
    -- Check combinations from constants (Tier 2 + Tier 1 = Tier 3)
    local combinations = {
        ["11-8"] = 21,  -- Steam + Tremor = Geyser
        ["12-9"] = 22,  -- Magma + Gust = Volcano
        ["13-10"] = 23, -- Quicksand + Shock = Sinkhole
        ["14-8"] = 24,  -- Downpour + Tremor = Flood
        ["15-7"] = 25,  -- Sandstorm + Rain = Landslide
        ["16-7"] = 26,  -- Crystal + Rain = Blizzard
        ["17-10"] = 27, -- Wild Fire + Shock = Phoenix
        ["18-6"] = 28,  -- Thunderstorm + Flame = Hellfire
        ["19-9"] = 29,  -- Explosion + Gust = Meteor
        ["20-6"] = 30   -- Chain Lightning + Flame = Plasma
    }
    
    local key = tier2Type .. "-" .. tier1Type
    return combinations[key]
end

-- Get asset type and sprite index from bubble type and tier
function BubbleState:getAssetTypeAndIndex(bubbleType, resultTier)
    local assetType, spriteIndex
    
    if resultTier == "tierOne" then
        assetType = "tierOne"
        spriteIndex = bubbleType - 5  -- Convert type 6-10 to sprite index 1-5
    elseif resultTier == "tierTwo" then
        assetType = "tierTwo"
        spriteIndex = bubbleType - 10  -- Convert type 11-20 to sprite index 1-10
    elseif resultTier == "tierThree" then
        assetType = "tierThree"
        spriteIndex = bubbleType - 20  -- Convert type 21-30 to sprite index 1-10
    else
        print("DEBUG: Unknown result tier:", resultTier)
        assetType = "tierOne"
        spriteIndex = 1
    end
    
    return assetType, spriteIndex
end

-- Schedule a cascade merge check after 8 frames
function BubbleState:scheduleCascadeMerge(placedAsset)
    if not placedAsset then return end
    
    print("DEBUG: Scheduling cascade merge check for asset", placedAsset.id, "in 8 frames")
    
    -- Initialize cascade system if needed
    if not self.cascadeQueue then
        self.cascadeQueue = {}
    end
    
    -- Add to cascade queue with 8-frame delay
    table.insert(self.cascadeQueue, {
        asset = placedAsset,
        framesRemaining = 8
    })
end

-- Process cascade merges (call this in update loop)
function BubbleState:processCascadeMerges()
    if not self.cascadeQueue or #self.cascadeQueue == 0 then
        return
    end
    
    -- Process each queued cascade merge
    for i = #self.cascadeQueue, 1, -1 do
        local cascadeItem = self.cascadeQueue[i]
        cascadeItem.framesRemaining = cascadeItem.framesRemaining - 1
        
        if cascadeItem.framesRemaining <= 0 then
            -- Time to check for cascade merge
            print("DEBUG: Checking cascade merge for asset", cascadeItem.asset.id)
            local mergeInfo = self:checkForMerges(cascadeItem.asset)
            
            if mergeInfo then
                print("DEBUG: Cascade merge detected! Executing...")
                self:executeMerge(mergeInfo)
            else
                print("DEBUG: No cascade merge found")
            end
            
            -- Remove from queue
            table.remove(self.cascadeQueue, i)
        end
    end
end

function BubbleState:selectBubblesForMerge(candidateBubbles, shotBubble)
    if #candidateBubbles < 3 then
        return nil
    end
    
    -- Always include the shot bubble
    local selected = {shotBubble}
    local remaining = {}
    
    -- Separate shot bubble from candidates
    for _, bubble in ipairs(candidateBubbles) do
        if bubble.asset.id ~= shotBubble.asset.id then
            table.insert(remaining, bubble)
        end
    end
    
    -- Calculate distances from shot bubble and sort
    local shotCell = self:getCellAtRowCol(shotBubble.row, shotBubble.col)
    for _, bubble in ipairs(remaining) do
        local bubbleCell = self:getCellAtRowCol(bubble.row, bubble.col)
        if shotCell and bubbleCell then
            bubble.distanceFromShot = distanceSquared(
                shotCell.x, shotCell.y, bubbleCell.x, bubbleCell.y
            )
        else
            bubble.distanceFromShot = math.huge
        end
    end
    
    -- Sort by distance (closest first)
    table.sort(remaining, function(a, b)
        return a.distanceFromShot < b.distanceFromShot
    end)
    
    -- Select the 2 closest bubbles
    for i = 1, math.min(2, #remaining) do
        table.insert(selected, remaining[i])
    end
    
    print("DEBUG: Selected", #selected, "bubbles for merge:", selected[1] and selected[1].asset.id or "nil", selected[2] and selected[2].asset.id or "nil", selected[3] and selected[3].asset.id or "nil")
    return selected
end

function BubbleState:getResultingBubbleType(basicType, requiredCount)
    -- Map basic bubble types to their Tier 1 equivalents
    local basicToTierOne = {
        [1] = 6,  -- Fire -> Flame
        [2] = 7,  -- Water -> Rain
        [3] = 8,  -- Earth -> Tremor
        [4] = 10, -- Lightning -> Shock
        [5] = 9   -- Wind -> Gust
    }
    
    if requiredCount == 3 and basicToTierOne[basicType] then
        return basicToTierOne[basicType]
    end
    
    return nil
end

function BubbleState:areBubblesAdjacent(row1, col1, row2, col2)
    -- Check if two bubbles are adjacent in hex grid
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    for _, dir in ipairs(directions) do
        local checkRow = row1 + dir[1]
        local checkCol = col1 + dir[2]
        if checkRow == row2 and checkCol == col2 then
            return true
        end
    end
    
    return false
end

function BubbleState:adjustAnchorForFrontPlacement(assetType, targetFrontRow, targetFrontCol)
    -- For multi-cell assets, adjust anchor position so the front of the asset appears at target
    if assetType == "basic" then
        -- Basic bubbles are single-cell, no adjustment needed
        return targetFrontRow, targetFrontCol
    elseif assetType == "tierOne" then
        -- For Tier 1 bubbles, try to place the anchor directly at the target position first
        -- This reduces the 1-cell gap issue by keeping merged bubbles closer to their origin
        return targetFrontRow, targetFrontCol
    elseif assetType == "tierTwo" then
        -- Tier 2 bubbles: front is at deltaRow -1 from anchor  
        return targetFrontRow + 1, targetFrontCol
    elseif assetType == "tierThree" then
        -- Tier 3 bubbles: front is at deltaRow -2 from anchor
        return targetFrontRow + 2, targetFrontCol
    end
    
    -- Default: no adjustment
    return targetFrontRow, targetFrontCol
end

function BubbleState:executeMerge(mergeInfo)
    if not mergeInfo or not mergeInfo.bubblesToRemove then
        return false
    end
    
    -- Handle different merge types
    local selectedBubbles = {}
    if mergeInfo.resultTier == "tierOne" then
        -- Basic bubbles: select 3 bubbles (shot + 2 closest)
        if #mergeInfo.bubblesToRemove < 3 then
            print("DEBUG: Not enough bubbles for Tier 1 merge")
            return false
        end
        selectedBubbles = self:selectBubblesForMerge(
            mergeInfo.bubblesToRemove, 
            mergeInfo.placedBubble
        )
        if not selectedBubbles or #selectedBubbles ~= 3 then
            print("DEBUG: Could not select 3 bubbles for Tier 1 merge")
            return false
        end
    else
        -- Higher tier merges: use exactly the 2 bubbles found
        if #mergeInfo.bubblesToRemove ~= 2 then
            print("DEBUG: Invalid bubble count for higher tier merge:", #mergeInfo.bubblesToRemove)
            return false
        end
        selectedBubbles = mergeInfo.bubblesToRemove
    end
    
    -- Find placement position from ALL connected bubbles, not just the 3 selected ones
    -- This ensures we can place at the true furthest forward position in the cluster
    local shotBubble = mergeInfo.placedBubble
    local allConnectedBubbles = mergeInfo.bubblesToRemove
    
    -- Calculate distances for all connected bubbles from shot position
    local shotCell = self:getCellAtRowCol(shotBubble.row, shotBubble.col)
    for _, bubble in ipairs(allConnectedBubbles) do
        local bubbleCell = self:getCellAtRowCol(bubble.row, bubble.col)
        if shotCell and bubbleCell then
            bubble.distanceFromShot = distanceSquared(
                shotCell.x, shotCell.y, bubbleCell.x, bubbleCell.y
            )
        else
            bubble.distanceFromShot = math.huge
        end
    end
    
    -- Filter to only bubbles adjacent to the shot bubble
    local adjacentToShot = {}
    for _, bubble in ipairs(allConnectedBubbles) do
        if self:areBubblesAdjacent(shotBubble.row, shotBubble.col, bubble.row, bubble.col) then
            table.insert(adjacentToShot, bubble)
        end
    end
    
    -- If no adjacent bubbles found, fall back to all connected
    if #adjacentToShot == 0 then
        adjacentToShot = allConnectedBubbles
        print("DEBUG: Warning - no adjacent bubbles found, using all connected")
    end
    
    -- Find the furthest forward among adjacent bubbles
    local targetRow, targetCol = nil, nil
    local lowestRow = math.huge
    local closestToShot = math.huge
    
    for _, bubble in ipairs(adjacentToShot) do
        if bubble.row < lowestRow then
            lowestRow = bubble.row
            targetRow = bubble.row
            targetCol = bubble.col
            closestToShot = bubble.distanceFromShot or 0
        elseif bubble.row == lowestRow then
            -- Tie-breaker: use closest to shot bubble
            local distance = bubble.distanceFromShot or math.huge
            if distance < closestToShot then
                targetRow = bubble.row
                targetCol = bubble.col
                closestToShot = distance
            end
        end
    end
    
    -- Adjust anchor position for multi-cell assets so their front appears at target position
    local assetTypeForAdjustment = mergeInfo.resultTier or "tierOne"
    local adjustedRow, adjustedCol = self:adjustAnchorForFrontPlacement(
        assetTypeForAdjustment, targetRow, targetCol
    )
    
    print("DEBUG: Target front position at", targetRow, targetCol, "-> anchor at", adjustedRow, adjustedCol, "for new bubble type", mergeInfo.newBubbleType)
    
    -- Remove the selected bubbles first
    for _, bubble in ipairs(selectedBubbles) do
        self:removeAsset(bubble.asset.id)
    end
    
    -- Determine the asset type and sprite index for the new bubble
    local newAssetType, newBubbleIndex = self:getAssetTypeAndIndex(mergeInfo.newBubbleType, mergeInfo.resultTier)
    
    -- Try to place the new bubble with nudge system
    -- IMPORTANT: Use the actual bubble type, not the sprite index!
    local shotRow = mergeInfo.placedBubble and mergeInfo.placedBubble.row or nil
    local shotCol = mergeInfo.placedBubble and mergeInfo.placedBubble.col or nil
    print("DEBUG: Shot location for placement:", shotRow or "none", shotCol or "none")
    if mergeInfo.placedBubble then
        print("DEBUG: placedBubble data:", mergeInfo.placedBubble.row, mergeInfo.placedBubble.col, "asset:", mergeInfo.placedBubble.asset and mergeInfo.placedBubble.asset.id or "none")
    end
    local placedAsset = self.placementSystem:placeAssetWithNudge(
        newAssetType, 
        mergeInfo.newBubbleType,  -- Use the full bubble type (6-10, 11-20, 21-30)
        adjustedRow, 
        adjustedCol, 
        3,  -- Maximum nudge distance
        shotRow,  -- shot location for better placement priority
        shotCol,
        self  -- Pass bubbleState for asset creation
    )
    
    if not placedAsset then
        print("DEBUG: Failed to place merged bubble, despawning")
        return false
    else
        print("DEBUG: Successfully merged bubbles into", newAssetType, "bubbleType", mergeInfo.newBubbleType, "spriteIndex", newBubbleIndex)
        
        -- Schedule cascade merge check after 8 frames
        self:scheduleCascadeMerge(placedAsset)
        return true
    end
end

function BubbleState:removeAsset(assetId)
    local asset = self.assets[assetId]
    if not asset then return end
    
    print("DEBUG: Removing asset", assetId, "-", asset.type, "type", asset.bubbleType, "at", asset.anchorRow, asset.anchorCol)
    
    -- Clear all cells this asset occupied
    if asset.patternCells then
        for _, cell in ipairs(asset.patternCells) do
            self:clearCellOccupation(cell.row, cell.col)
        end
    end
    
    -- Remove from assets table
    self.assets[assetId] = nil
end

function BubbleState:placeAssetWithNudge(assetType, bubbleType, preferredRow, preferredCol, maxNudgeDistance, shotRow, shotCol)
    -- Determine actual nudge distance based on asset type
    local actualNudgeDistance = self:getMaxNudgeDistance(assetType)
    local searchDistance = math.min(maxNudgeDistance, actualNudgeDistance)
    
    print("DEBUG: Nudging", assetType, "with max distance", searchDistance)
    
    -- First try the preferred position
    if self:canPlaceAsset(assetType, preferredRow, preferredCol) then
        print("DEBUG: Preferred position", preferredRow, preferredCol, "is available, using it directly")
        return self:placeAssetDirect(assetType, bubbleType, preferredRow, preferredCol, false)
    else
        print("DEBUG: Preferred position", preferredRow, preferredCol, "is NOT available, searching alternatives")
    end
    
    -- Collect all positions within nudge range
    local candidatePositions = {}
    for distance = 1, searchDistance do
        local positions = self:getPositionsAtDistance(preferredRow, preferredCol, distance)
        
        -- For Tier 1, sort positions to prefer downward/same row over upward
        if assetType == "tierOne" then
            table.sort(positions, function(a, b)
                -- Prefer positions that don't jump upward (higher deltaRow values)
                if a.deltaRow ~= b.deltaRow then
                    return a.deltaRow > b.deltaRow  -- 0 or positive deltaRow preferred over negative
                end
                -- If same row delta, prefer smaller column delta (closer horizontally)
                return math.abs(a.deltaCol) < math.abs(b.deltaCol)
            end)
        end
        
        for _, pos in ipairs(positions) do
            if self:isValidCell(pos.row, pos.col) then
                table.insert(candidatePositions, pos)
            end
        end
    end
    
    -- Find the best placement using stomping logic  
    local bestPlacement = self:findBestPlacementWithStomping(assetType, candidatePositions, preferredRow, preferredCol)
    
    if bestPlacement then
        
        -- Execute the stomping (remove conflicting assets)
        if bestPlacement.assetsToRemove and #bestPlacement.assetsToRemove > 0 then
            print("DEBUG: Stomping", #bestPlacement.assetsToRemove, "assets for placement")
            for _, assetId in ipairs(bestPlacement.assetsToRemove) do
                local stompedAsset = self.assets[assetId]
                if stompedAsset then
                    print("DEBUG: Stomping asset", assetId, "-", stompedAsset.type, "bubbleType", stompedAsset.bubbleType, "for", assetType, "placement")
                end
                self:removeAsset(assetId)
            end
        end
        
        -- Place the new asset
        print("DEBUG: Placing at", bestPlacement.row, bestPlacement.col, "after stomping")
        return self:placeAssetDirect(assetType, bubbleType, bestPlacement.row, bestPlacement.col, false)
    end
    
    print("DEBUG: Could not find valid placement with stomping within", searchDistance, "spaces")
    return nil
end

function BubbleState:getMaxNudgeDistance(assetType)
    local nudgeDistances = {
        basic = 0,
        tierOne = 2,  -- Increased from 1 to 2 to give more placement options
        tierTwo = 1, 
        tierThree = 2
    }
    return nudgeDistances[assetType] or 0
end

function BubbleState:findBestPlacementWithStomping(assetType, candidatePositions, targetRow, targetCol)
    local placements = {}
    
    -- Use the provided target position for distance calculations
    targetRow = targetRow or 0
    targetCol = targetCol or 0
    
    -- Analyze each candidate position
    for _, pos in ipairs(candidatePositions) do
        local analysis = self:analyzePlacement(assetType, pos.row, pos.col)
        if analysis then
            -- Check if this position could trigger a cascade merge
            analysis.cascadePotential = self:evaluateCascadePotential(assetType, pos.row, pos.col)
            
            -- Calculate distance from preferred target position
            analysis.distanceFromTarget = math.abs(pos.row - targetRow) + math.abs(pos.col - targetCol)
            
            -- Calculate distance from shot location (for tiebreaking)
            if shotRow and shotCol then
                analysis.distanceFromShot = math.abs(pos.row - shotRow) + math.abs(pos.col - shotCol)
                -- For Tier 1, heavily penalize positions that are far from shot location
                if assetType == "tierOne" and analysis.distanceFromShot > 1 then
                    analysis.distanceFromShot = analysis.distanceFromShot * 2  -- Double penalty for Tier 1
                end
            else
                analysis.distanceFromShot = analysis.distanceFromTarget  -- fallback to target distance
            end
            
            table.insert(placements, analysis)
        end
    end
    
    if #placements == 0 then
        return nil
    end
    
    -- Filter out unacceptable placements (those that stomp higher-tier bubbles unnecessarily)
    if assetType == "tierOne" or assetType == "tierTwo" then
        local acceptablePlacements = {}
        for _, placement in ipairs(placements) do
            local hasUnacceptableStomping = false
            if placement.assetsToRemove then
                for _, assetId in ipairs(placement.assetsToRemove) do
                    local targetAsset = self.assets[assetId]
                    if targetAsset then
                        -- Tier 1: Don't stomp Tier 1+
                        if assetType == "tierOne" and (targetAsset.type == "tierOne" or targetAsset.type == "tierTwo" or targetAsset.type == "tierThree") then
                            hasUnacceptableStomping = true
                            break
                        -- Tier 2: Don't stomp other Tier 2+ (but can stomp Tier 1 for higher cascades)
                        elseif assetType == "tierTwo" and (targetAsset.type == "tierTwo" or targetAsset.type == "tierThree") then
                            hasUnacceptableStomping = true  
                            break
                        end
                    end
                end
            end
            
            if not hasUnacceptableStomping then
                table.insert(acceptablePlacements, placement)
            end
        end
        
        print("DEBUG: Filtered", #placements, "placements down to", #acceptablePlacements, "acceptable ones for", assetType)
        placements = acceptablePlacements
    end
    
    if #placements == 0 then
        return nil
    end
    
    -- Sort by cascade potential tier, then distance, then exact cascade score, then shot distance, then stomping priority
    table.sort(placements, function(a, b)
        -- 1. Categorize cascade potential into tiers
        local aTier = 0
        local bTier = 0
        if a.cascadePotential >= 1000 then aTier = 3 -- Tier 3 combinations
        elseif a.cascadePotential >= 500 then aTier = 2 -- Tier 2 combinations  
        elseif a.cascadePotential > 0 then aTier = 1 -- Basic cascades
        end
        
        if b.cascadePotential >= 1000 then bTier = 3
        elseif b.cascadePotential >= 500 then bTier = 2
        elseif b.cascadePotential > 0 then bTier = 1
        end
        
        -- Prefer higher cascade tiers
        if aTier ~= bTier then
            return aTier > bTier
        end
        
        -- 2. Within same cascade tier, prefer exact target matches (distance 0) 
        local aExact = (a.distanceFromTarget == 0)
        local bExact = (b.distanceFromTarget == 0)
        if aExact ~= bExact then
            return aExact -- Prefer the exact match
        end
        
        -- 3. Within same tier, prefer positions closer to merge target
        if a.distanceFromTarget ~= b.distanceFromTarget then
            return a.distanceFromTarget < b.distanceFromTarget
        end
        
        -- 4. Among equal distances, prefer higher exact cascade scores
        if a.cascadePotential ~= b.cascadePotential then
            return a.cascadePotential > b.cascadePotential
        end
        
        -- 5. Among equal cascade scores, prefer positions closer to shot location
        -- For Tier 1, give extra weight to shot location proximity
        if assetType == "tierOne" and shotRow and shotCol then
            if a.distanceFromShot ~= b.distanceFromShot then
                return a.distanceFromShot < b.distanceFromShot
            end
        elseif a.distanceFromShot ~= b.distanceFromShot then
            return a.distanceFromShot < b.distanceFromShot
        end
        
        -- 6. Finally use stomping priority
        return self:comparePlacementPriority(a, b, assetType)
    end)
    
    -- Debug output to show top placement choices
    if assetType == "tierOne" and #placements > 1 then
        print("DEBUG: Top 3 Tier 1 placement options (target:", targetRow, targetCol, "shot:", shotRow or "?", shotCol or "?", "):")
        for i = 1, math.min(3, #placements) do
            local p = placements[i]
            local stompCount = p.assetsToRemove and #p.assetsToRemove or 0
            print("DEBUG:  ", i, "- Position", p.row, p.col, "targetDist", p.distanceFromTarget, "shotDist", p.distanceFromShot, "stomps", stompCount, "cascade", p.cascadePotential)
        end
    end
    
    return placements[1]
end

-- Evaluate the cascade potential of placing an asset at a specific position
function BubbleState:evaluateCascadePotential(assetType, row, col)
    -- Enhanced cascade evaluation that considers stomping-induced merges
    local potentialScore = 0
    
    -- First check if stomping basic bubbles here could create additional Tier 1s
    if assetType == "tierOne" then
        local analysis = self:analyzePlacement(assetType, row, col)
        if analysis and analysis.assetsToRemove then
            for _, assetId in ipairs(analysis.assetsToRemove) do
                local asset = self.assets[assetId]
                if asset and asset.type == "basic" then
                    -- Check if removing this basic bubble would trigger another merge
                    local mergeInfo = self:simulateBasicRemovalMerge(asset)
                    if mergeInfo and mergeInfo.resultTier == "tierOne" then
                        potentialScore = potentialScore + 10  -- High score for creating additional Tier 1s
                        print("DEBUG: Stomping basic at", asset.anchorRow, asset.anchorCol, "would create additional Tier 1 - score +10")
                    end
                end
            end
        end
    end
    
    -- Check all adjacent positions for compatible bubbles
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row  
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    -- Check all cells that would be occupied by the multi-cell asset
    local patternCells = self:findPatternCells(assetType, row, col)
    if not patternCells then
        return potentialScore
    end
    
    for _, patternCell in ipairs(patternCells) do
        for _, dir in ipairs(directions) do
            local checkRow = patternCell.row + dir[1]
            local checkCol = patternCell.col + dir[2]
            
            if self:isValidCell(checkRow, checkCol) then
                local occupantId = self:getCellOccupant(checkRow, checkCol)
                if occupantId then
                    local adjacentAsset = self.assets[occupantId]
                    if adjacentAsset and adjacentAsset.anchorRow == checkRow and adjacentAsset.anchorCol == checkCol then
                        -- Prioritize bigger merges: Tier 3 > Tier 2
                        if assetType == "tierOne" and adjacentAsset.type == "tierTwo" then
                            potentialScore = potentialScore + 1000  -- HIGHEST priority for Tier 3 cascades
                            print("DEBUG: CASCADE POTENTIAL +1000 for Tier 1 + Tier 2 = Tier 3 at", row, col, "with", adjacentAsset.type, "bubbleType", adjacentAsset.bubbleType)
                        elseif assetType == "tierTwo" and adjacentAsset.type == "tierOne" then
                            potentialScore = potentialScore + 1000  -- HIGHEST priority for Tier 3 cascades (reverse)
                            print("DEBUG: CASCADE POTENTIAL +1000 for Tier 2 + Tier 1 = Tier 3 at", row, col, "with", adjacentAsset.type, "bubbleType", adjacentAsset.bubbleType)
                        elseif assetType == "tierOne" and adjacentAsset.type == "tierOne" then
                            potentialScore = potentialScore + 500  -- High score for Tier 2 cascades  
                            print("DEBUG: CASCADE POTENTIAL +500 for Tier 1 + Tier 1 = Tier 2 at", row, col, "with", adjacentAsset.type, "bubbleType", adjacentAsset.bubbleType)
                        end
                    end
                end
            end
        end
    end
    
    return potentialScore
end

-- Simulate what would happen if we removed a basic bubble (for cascade evaluation)
function BubbleState:simulateBasicRemovalMerge(basicAsset)
    if not basicAsset or basicAsset.type ~= "basic" then
        return nil
    end
    
    -- Find all connected basic bubbles of the same type around this asset's neighbors
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    -- Check each neighboring position for potential merges
    for _, dir in ipairs(directions) do
        local checkRow = basicAsset.anchorRow + dir[1]
        local checkCol = basicAsset.anchorCol + dir[2]
        
        if self:isValidCell(checkRow, checkCol) then
            local neighborId = self:getCellOccupant(checkRow, checkCol)
            if neighborId and neighborId ~= basicAsset.id then
                local neighbor = self.assets[neighborId]
                if neighbor and neighbor.type == "basic" and neighbor.bubbleType == basicAsset.bubbleType then
                    -- Found a same-type neighbor, check if removing basicAsset would enable a merge
                    -- Simplified check: count same-type neighbors excluding the asset being stomped
                    local sameTypeCount = self:countSameTypeNeighbors(neighbor.bubbleType, checkRow, checkCol, basicAsset.id)
                    
                    if sameTypeCount >= 2 then  -- neighbor + 2 more = 3 total for merge
                        -- Would create a merge! Return merge info
                        return {
                            bubblesToRemove = {},  -- Don't need exact list for scoring
                            newBubbleType = basicAsset.bubbleType + 5,  -- Basic -> Tier 1 mapping
                            resultTier = "tierOne"
                        }
                    end
                end
            end
        end
    end
    
    return nil
end

-- Count connected same-type neighbors (for cascade evaluation)
function BubbleState:countSameTypeNeighbors(bubbleType, startRow, startCol, excludeAssetId)
    local visited = {}
    local queue = {{row = startRow, col = startCol}}
    local count = 0
    
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    while #queue > 0 do
        local current = table.remove(queue, 1)
        local key = current.row .. "," .. current.col
        
        if not visited[key] then
            visited[key] = true
            
            local occupantId = self:getCellOccupant(current.row, current.col)
            if occupantId and occupantId ~= excludeAssetId then
                local asset = self.assets[occupantId]
                if asset and asset.type == "basic" and asset.bubbleType == bubbleType then
                    count = count + 1
                    
                    -- Add neighbors to queue
                    for _, dir in ipairs(directions) do
                        local checkRow = current.row + dir[1]
                        local checkCol = current.col + dir[2]
                        local checkKey = checkRow .. "," .. checkCol
                        
                        if self:isValidCell(checkRow, checkCol) and not visited[checkKey] then
                            table.insert(queue, {row = checkRow, col = checkCol})
                        end
                    end
                end
            end
        end
    end
    
    return count
end

function BubbleState:analyzePlacement(assetType, row, col)
    -- Get all cells this asset would occupy
    local patternCells = self:findPatternCells(assetType, row, col)
    if not patternCells or #patternCells == 0 then
        return nil
    end
    
    -- Check if all pattern cells are within the grid
    local definition = ASSET_DEFINITIONS[assetType]
    if not definition or #patternCells ~= definition.cellCount then
        return nil
    end
    
    -- Categorize conflicts
    local conflicts = {
        basic = {},
        tierOne = {},
        tierTwo = {},
        tierThree = {}
    }
    local totalConflicts = 0
    
    for _, cellInfo in ipairs(patternCells) do
        local occupant = self:getCellOccupant(cellInfo.row, cellInfo.col)
        if occupant then
            local asset = self.assets[occupant]
            if asset then
                local conflictType = self:getAssetTier(asset.type)
                table.insert(conflicts[conflictType], asset.id)
                totalConflicts = totalConflicts + 1
            end
        end
    end
    
    return {
        row = row,
        col = col,
        patternCells = patternCells,
        conflicts = conflicts,
        totalConflicts = totalConflicts,
        assetsToRemove = self:getAllConflictingAssets(conflicts)
    }
end

function BubbleState:getAssetTier(assetType)
    local tierMap = {
        basic = "basic",
        tierOne = "tierOne",
        tierTwo = "tierTwo", 
        tierThree = "tierThree"
    }
    return tierMap[assetType] or "basic"
end

function BubbleState:getAllConflictingAssets(conflicts)
    local allAssets = {}
    for tierType, assetIds in pairs(conflicts) do
        for _, assetId in ipairs(assetIds) do
            table.insert(allAssets, assetId)
        end
    end
    return allAssets
end

function BubbleState:comparePlacementPriority(a, b, placingAssetType)
    -- Priority order: (a) empty > (b) basic only > (c) tier1+ for tier2+ only > (d) prevent tier1 vs tier1 stomping
    
    -- (a) Empty configurations first
    if a.totalConflicts == 0 and b.totalConflicts > 0 then
        return true
    elseif b.totalConflicts == 0 and a.totalConflicts > 0 then
        return false
    elseif a.totalConflicts == 0 and b.totalConflicts == 0 then
        -- Both empty - for Tier 1, prefer positions that don't jump upward
        if placingAssetType == "tierOne" then
            -- Prefer positions with higher row numbers (closer to merge origin, less jumping)
            if a.row ~= b.row then
                return a.row > b.row  -- Higher row number = lower on screen = less jumping
            end
            -- If same row, prefer closer to left (lower col)
            return a.col < b.col
        else
            -- For other tiers, use original logic
            return (a.row + a.col) < (b.row + b.col)
        end
    end
    
    -- (b) Tier 1 placement priority: basic-only stomping > empty > reject Tier 1 stomping
    if placingAssetType == "tierOne" then
        local aTier1Conflicts = #a.conflicts.tierOne > 0
        local bTier1Conflicts = #b.conflicts.tierOne > 0
        local aBasicOnlyStomping = #a.conflicts.basic > 0 and #a.conflicts.tierOne == 0 and #a.conflicts.tierTwo == 0 and #a.conflicts.tierThree == 0
        local bBasicOnlyStomping = #b.conflicts.basic > 0 and #b.conflicts.tierOne == 0 and #b.conflicts.tierTwo == 0 and #b.conflicts.tierThree == 0
        
        -- Absolutely refuse any placement that would stomp Tier 1+ bubbles
        if aTier1Conflicts or (#a.conflicts.tierTwo > 0) or (#a.conflicts.tierThree > 0) then
            return false  -- 'a' is unacceptable
        end
        if bTier1Conflicts or (#b.conflicts.tierTwo > 0) or (#b.conflicts.tierThree > 0) then
            return false  -- 'b' is unacceptable  
        end
        
        -- Prefer basic-only stomping over empty spaces for Tier 1 (fills gaps better)
        if aBasicOnlyStomping and (b.totalConflicts == 0) then
            print("DEBUG: Tier 1 placement prefers stomping", #a.conflicts.basic, "basic bubbles over empty space")
            return true  -- 'a' stomps basics, 'b' is empty -> prefer 'a'
        end
        if bBasicOnlyStomping and (a.totalConflicts == 0) then
            print("DEBUG: Tier 1 placement prefers stomping", #b.conflicts.basic, "basic bubbles over empty space")
            return false  -- 'b' stomps basics, 'a' is empty -> prefer 'b'
        end
        
        -- If both stomp basics or both are empty, continue with normal priority
    end
    
    -- Final tie-breaker: prefer positions closer to origin (lower row + col sum)
    if a.totalConflicts == b.totalConflicts then
        return (a.row + a.col) < (b.row + b.col)
    end
    
    -- (c) Basic-only stomping preferred
    local aBasicOnly = #a.conflicts.basic > 0 and #a.conflicts.tierOne == 0 and #a.conflicts.tierTwo == 0 and #a.conflicts.tierThree == 0
    local bBasicOnly = #b.conflicts.basic > 0 and #b.conflicts.tierOne == 0 and #b.conflicts.tierTwo == 0 and #b.conflicts.tierThree == 0
    
    if aBasicOnly and not bBasicOnly then
        return true
    elseif bBasicOnly and not aBasicOnly then
        return false
    elseif aBasicOnly and bBasicOnly then
        -- Both basic-only, choose the one that stomps fewer
        return #a.conflicts.basic < #b.conflicts.basic
    end
    
    -- (d) For Tier 2 and 3, allow stomping Tier 1
    if placingAssetType == "tierTwo" or placingAssetType == "tierThree" then
        local aTier1Only = #a.conflicts.tierOne > 0 and #a.conflicts.tierTwo == 0 and #a.conflicts.tierThree == 0
        local bTier1Only = #b.conflicts.tierOne > 0 and #b.conflicts.tierTwo == 0 and #b.conflicts.tierThree == 0
        
        if aTier1Only and not bTier1Only then
            return true
        elseif bTier1Only and not aTier1Only then
            return false
        elseif aTier1Only and bTier1Only then
            -- Both tier1-only, choose fewer stomps
            return #a.conflicts.tierOne < #b.conflicts.tierOne
        end
    end
    
    -- (d) For Tier 3 only, allow stomping Tier 2
    if placingAssetType == "tierThree" then
        local aTier2Only = #a.conflicts.tierTwo > 0 and #a.conflicts.tierThree == 0
        local bTier2Only = #b.conflicts.tierTwo > 0 and #b.conflicts.tierThree == 0
        
        if aTier2Only and not bTier2Only then
            return true
        elseif bTier2Only and not aTier2Only then
            return false
        elseif aTier2Only and bTier2Only then
            return #a.conflicts.tierTwo < #b.conflicts.tierTwo
        end
    end
    
    -- If all else is equal, choose the one with fewer total conflicts
    return a.totalConflicts < b.totalConflicts
end

function BubbleState:getPositionsAtDistance(centerRow, centerCol, distance)
    local positions = {}
    
    -- Generate all positions at exactly this distance
    for dRow = -distance, distance do
        for dCol = -distance, distance do
            -- Skip positions that are closer than the target distance
            local actualDistance = math.abs(dRow) + math.abs(dCol)
            if actualDistance == distance then
                table.insert(positions, {
                    row = centerRow + dRow,
                    col = centerCol + dCol,
                    deltaRow = dRow,  -- Store offset for Tier 1 preference sorting
                    deltaCol = dCol
                })
            end
        end
    end
    
    return positions
end

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
            print("DEBUG: ===== Shot Fired =====")
            projectile.x = placement.x
            projectile.y = placement.y
            projectile.targetRow = placement.row
            projectile.targetCol = placement.col
            self:placeAssetDirect(projectile.type, projectile.bubbleType, 
                                placement.row, placement.col, true)
            self:generateNewProjectile()
            return
        end
    end
    
    -- Check for back edge collision (left side)
    if nextX <= SCREEN_CONSTANTS.LEFT_PADDING + BOUNDARY_CONSTANTS.LEFT_BOUND_MARGIN then
        local placement = self:findNearestValidPlacement(nextX, nextY)
        if placement then
            print("DEBUG: ===== Shot Fired =====")
            projectile.x = placement.x
            projectile.y = placement.y
            projectile.targetRow = placement.row
            projectile.targetCol = placement.col
            self:placeAssetDirect(projectile.type, projectile.bubbleType, 
                                placement.row, placement.col, true)
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
    
    -- Calculate the correct sprite index based on asset type and bubble type
    local spriteIndex = asset.bubbleType
    if asset.type == "tierOne" then
        -- Tier 1: bubbleType 6-10 -> sprite index 1-5
        spriteIndex = asset.bubbleType - 5
    elseif asset.type == "tierTwo" then
        -- Tier 2: bubbleType 11-20 -> sprite index 1-10
        spriteIndex = asset.bubbleType - 10
    elseif asset.type == "tierThree" then
        -- Tier 3: bubbleType 21-30 -> sprite index 1-10
        spriteIndex = asset.bubbleType - 20
    end
    -- Basic bubbles use bubbleType directly (1-5)
    
    if spriteIndex < 1 or spriteIndex > sprite.count then
        print("DEBUG: Invalid sprite index", spriteIndex, "for", asset.type, "bubbleType", asset.bubbleType, "max", sprite.count)
        return
    end
    
    local sourceX = (spriteIndex - 1) * sprite.width
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
    
    -- Reset modular systems
    if self.cascadeSystem then
        self.cascadeSystem:reset()
    end
    
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
    
    -- Debug mode toggle
    if pd.buttonJustPressed(pd.kButtonB) then
        self.debugMode = not self.debugMode
        print("DEBUG: Debug visualization", self.debugMode and "ON" or "OFF")
    end
    
    if self.currentProjectile and self.currentProjectile.moving then
        self:updateProjectileMovement()
    end
    
    -- Process cascade merges
    self.cascadeSystem:processCascadeMerges(self.mergeSystem, self)
    
    return nil
end

function BubbleState:draw()
    gfx.clear()
    
    if self.gameOver then
        self:drawGameOver()
        return
    end
    
    self:drawBoundaries()
    
    if self.debugMode then
        -- Debug mode: show grid structure and occupation
        self:drawDebugVisualization()
    else
        -- Normal mode: show asset sprites
        for _, asset in pairs(self.assets) do
            self:drawAsset(asset)
        end
    end
    
    if self.currentProjectile then
        self:drawAimingLine()
        if self.debugMode then
            self:drawDebugProjectile()
        else
            self:drawProjectile()
        end
    end
end

function BubbleState:drawDebugVisualization()
    gfx.setColor(gfx.kColorBlack)
    
    -- Draw all grid circles
    for _, cell in ipairs(self.gridCells) do
        gfx.drawCircleAtPoint(cell.x, cell.y, GRID_CONSTANTS.CIRCLE_SIZE/2)
    end
    
    -- Draw occupation markers
    for _, asset in pairs(self.assets) do
        self:drawDebugAsset(asset)
    end
end

function BubbleState:drawDebugAsset(asset)
    if not asset or not asset.patternCells then return end
    
    gfx.setColor(gfx.kColorBlack)
    
    -- Draw + for anchor cell
    local anchorCell = self:getCellAtRowCol(asset.anchorRow, asset.anchorCol)
    if anchorCell then
        -- Draw a cross (+) for the anchor
        local size = 4
        gfx.drawLine(anchorCell.x - size, anchorCell.y, anchorCell.x + size, anchorCell.y)
        gfx.drawLine(anchorCell.x, anchorCell.y - size, anchorCell.x, anchorCell.y + size)
    end
    
    -- Draw dots for occupied cells (but not anchor cells to avoid redundancy)
    for _, cellInfo in ipairs(asset.patternCells) do
        -- Skip the anchor cell since it already has a + marker
        if cellInfo.row ~= asset.anchorRow or cellInfo.col ~= asset.anchorCol then
            local cell = self:getCellAtRowCol(cellInfo.row, cellInfo.col)
            if cell then
                gfx.fillCircleAtPoint(cell.x, cell.y, 2)
            end
        end
    end
end

function BubbleState:drawDebugProjectile()
    if not self.currentProjectile then return end
    
    gfx.setColor(gfx.kColorBlack)
    
    -- Draw projectile as a filled circle
    gfx.fillCircleAtPoint(self.currentProjectile.x, self.currentProjectile.y, 3)
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