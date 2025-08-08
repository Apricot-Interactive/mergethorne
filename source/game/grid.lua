-- Grid system: hex grid calculations, collision detection, and placement logic
-- Extracted from bubbleState.lua for better maintainability

import "CoreLibs/graphics"

-- Temporarily inline constants until we fix the import system
local constants = {
    GRID = {
        TOTAL_ROWS = 15,
        MAX_COLS = 13,
        CELL_SPACING_X = 20,
        ROW_SPACING_Y = 16,
        HEX_OFFSET_X = 10,
        CIRCLE_SIZE = 20
    },
    SCREEN = {
        WIDTH = 400,
        HEIGHT = 240,
        LEFT_PADDING = 40,
        RIGHT_PADDING = 100,
    },
    PATTERN_TEMPLATES = {
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
        }
    }
}

-- Temporarily inline helpers
local helpers = {
    getHexStagger = function(row)
        return ((row - 1) % 2)
    end,
    hasElements = function(table)
        for _, _ in pairs(table) do
            return true
        end
        return false
    end,
    distanceSquared = function(x1, y1, x2, y2)
        return (x2 - x1)^2 + (y2 - y1)^2
    end,
    distance = function(x1, y1, x2, y2)
        return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
    end
}

local Grid = {}

function Grid:new()
    local grid = {}
    setmetatable(grid, self)
    self.__index = self
    
    -- Grid state
    grid.gridCells = {}
    grid.gridLookup = {}
    grid.rowLengths = {}
    grid.occupiedBy = {}
    
    -- Initialize the hex grid
    grid:setupHexGrid()
    
    return grid
end

function Grid:setupHexGrid()
    self.gridCells = {}
    self.gridLookup = {}
    self.rowLengths = {}
    
    local totalRows = constants.GRID.TOTAL_ROWS
    local cellSpacingX = constants.GRID.CELL_SPACING_X
    local rowSpacingY = constants.GRID.ROW_SPACING_Y
    local offsetX = constants.GRID.HEX_OFFSET_X
    local circleSize = constants.GRID.CIRCLE_SIZE
    
    local gridHeight = (totalRows - 1) * rowSpacingY + circleSize
    local startY = (constants.SCREEN.HEIGHT - gridHeight) / 2 + circleSize/2
    
    local cellIndex = 1
    
    for row = 1, totalRows do
        local cellsInRow = constants.GRID.MAX_COLS - ((row - 1) % 2)
        local hexOffset = ((row - 1) % 2) * offsetX
        
        self.gridLookup[row] = {}
        self.rowLengths[row] = cellsInRow
        
        for col = 1, cellsInRow do
            local x = constants.SCREEN.LEFT_PADDING + hexOffset + (col - 1) * cellSpacingX + circleSize/2
            local y = startY + ((row - 1) * rowSpacingY)
            
            if x - circleSize/2 >= constants.SCREEN.LEFT_PADDING and 
               x + circleSize/2 <= constants.SCREEN.WIDTH - constants.SCREEN.RIGHT_PADDING then
                table.insert(self.gridCells, {x = x, y = y, row = row, col = col})
                self.gridLookup[row][col] = cellIndex
                cellIndex = cellIndex + 1
            end
        end
    end
    
    self.totalRows = totalRows
    self.maxCols = constants.GRID.MAX_COLS
end

function Grid:getCellAtRowCol(row, col)
    if not self.gridLookup[row] or not self.gridLookup[row][col] then
        return nil
    end
    
    local index = self.gridLookup[row][col]
    return self.gridCells[index]
end

function Grid:getCellIndex(row, col)
    if not self.gridLookup[row] or not self.gridLookup[row][col] then
        return nil
    end
    return self.gridLookup[row][col]
end

function Grid:isValidCell(row, col)
    return row >= 1 and row <= self.totalRows and 
           col >= 1 and col <= self.rowLengths[row] and
           self.gridLookup[row] and self.gridLookup[row][col]
end

function Grid:markCellOccupied(row, col, assetId)
    local cellIndex = self:getCellIndex(row, col)
    if cellIndex then
        self.occupiedBy[cellIndex] = assetId
    end
end

function Grid:isCellOccupied(row, col)
    local cellIndex = self:getCellIndex(row, col)
    if not cellIndex then return true end
    return self.occupiedBy[cellIndex] ~= nil
end

function Grid:getCellOccupant(row, col)
    local cellIndex = self:getCellIndex(row, col)
    if not cellIndex then return nil end
    return self.occupiedBy[cellIndex]
end

function Grid:clearCellOccupation(row, col)
    local cellIndex = self:getCellIndex(row, col)
    if cellIndex then
        self.occupiedBy[cellIndex] = nil
    end
end

function Grid:canPlaceAsset(assetType, row, col)
    -- Get all cells this asset would occupy
    local patternCells = self:findPatternCells(assetType, row, col)
    local definition = constants.ASSET_DEFINITIONS[assetType]
    
    -- Must have correct number of pattern cells
    if not patternCells or #patternCells ~= definition.cellCount then
        return false
    end
    
    -- All cells must be empty (not occupied by other assets)
    for _, cellInfo in ipairs(patternCells) do
        if self:isCellOccupied(cellInfo.row, cellInfo.col) then
            return false  -- Cell is already occupied
        end
    end
    
    return true
end

function Grid:findPatternCells(assetType, anchorRow, anchorCol)
    -- Simple template lookup: choose even or odd template based on anchor row
    local templates = constants.PATTERN_TEMPLATES[assetType]
    if not templates then return {} end
    
    -- Choose template based on anchor row parity
    local anchorStagger = helpers.getHexStagger(anchorRow)
    local template = (anchorStagger == 0) and templates.odd or templates.even
    
    local result = {}
    
    for _, delta in ipairs(template) do
        local targetRow = anchorRow + delta.deltaRow
        local targetCol = anchorCol + delta.deltaCol
        
        -- Only check if target cell is valid - allow overlapping for now
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

function Grid:findClosestGridCell(x, y)
    local closestDistanceSquared = math.huge
    local closestRow, closestCol = nil, nil
    
    -- Use squared distance to avoid expensive sqrt calculations
    for _, cell in ipairs(self.gridCells) do
        local distanceSquared = helpers.distanceSquared(x, y, cell.x, cell.y)
        if distanceSquared < closestDistanceSquared then
            closestDistanceSquared = distanceSquared
            closestRow = cell.row
            closestCol = cell.col
        end
    end
    
    return closestRow, closestCol
end

function Grid:isAdjacentToExistingBubbles(row, col, assets)
    -- If no bubbles exist yet, allow placement anywhere in grid
    if not helpers.hasElements(assets) then
        return true  -- First bubble can go anywhere
    end
    
    -- Check surrounding cells for existing bubbles
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    for _, dir in ipairs(directions) do
        local checkRow = row + dir[1]
        local checkCol = col + dir[2]
        
        if self:isValidCell(checkRow, checkCol) then
            if self:isCellOccupied(checkRow, checkCol) then
                return true  -- Adjacent to an existing bubble
            end
        end
    end
    
    return false  -- Not adjacent to any existing bubbles
end

function Grid:isTouchingGridEdges(assetType, row, col)
    -- Check if this position is at or near grid boundaries
    local patternCells = self:findPatternCells(assetType, row, col)
    if not patternCells then
        return false
    end
    
    for _, cellInfo in ipairs(patternCells) do
        local cellRow = cellInfo.row
        local cellCol = cellInfo.col
        
        -- Check if touching any grid boundary
        if cellRow == 1 or cellRow == self.totalRows or  -- Top or bottom edge
           cellCol == 1 or cellCol == self.rowLengths[cellRow] then  -- Left or right edge of this row
            return true
        end
    end
    
    return false
end

function Grid:clearAllOccupation()
    self.occupiedBy = {}
end

-- Draw the grid (for debugging purposes)
function Grid:draw()
    local gfx = playdate.graphics
    local circleSize = constants.GRID.CIRCLE_SIZE
    
    -- Draw all grid circles for debugging
    for _, cell in ipairs(self.gridCells) do
        gfx.drawCircleAtPoint(cell.x, cell.y, circleSize/2)
    end
end

return Grid