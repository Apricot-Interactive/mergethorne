import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics

BubbleState = {}

function BubbleState:new()
    local state = {}
    setmetatable(state, self)
    self.__index = self
    
    state.leftPadding = 40
    state.rightPadding = 100
    state.gameWidth = 400 - state.leftPadding - state.rightPadding
    state.circleSize = 20
    state.gridCells = {}
    state.assets = {}
    state.occupiedBy = {}
    state.nextAssetId = 1
    
    -- Placement queue system for delayed placement
    state.placementQueue = {}
    state.placementFrameCounter = 0
    state.placementDelay = 2
    
    -- Verification system for occupied cells
    state.verificationPhase = false
    state.verificationFrameCounter = 0
    state.verificationDelay = 180  -- 3 seconds at 60fps
    state.verificationDots = {}
    
    state:setupHexGrid()
    state:setupAssetDefinitions()
    state:loadBubbleSprites()
    state:populateTestAssets()
    
    return state
end

function BubbleState:setupHexGrid()
    self.gridCells = {}
    self.gridLookup = {}
    self.rowLengths = {}
    
    local totalRows = 15
    local cellSpacingX = 20
    local rowSpacingY = 16
    local offsetX = 10
    local gridHeight = (totalRows - 1) * rowSpacingY + self.circleSize
    local startY = (240 - gridHeight) / 2 + self.circleSize/2
    
    local cellIndex = 1
    
    for row = 1, totalRows do
        local cellsInRow = 13 - ((row - 1) % 2)
        local hexOffset = ((row - 1) % 2) * offsetX
        
        self.gridLookup[row] = {}
        self.rowLengths[row] = cellsInRow
        
        for col = 1, cellsInRow do
            local x = self.leftPadding + hexOffset + (col - 1) * cellSpacingX + self.circleSize/2
            local y = startY + ((row - 1) * rowSpacingY)
            
            if x - self.circleSize/2 >= self.leftPadding and x + self.circleSize/2 <= 400 - self.rightPadding then
                table.insert(self.gridCells, {x = x, y = y, row = row, col = col})
                self.gridLookup[row][col] = cellIndex
                cellIndex = cellIndex + 1
            end
        end
    end
    
    self.totalRows = totalRows
    self.maxCols = 13
end

function BubbleState:setupAssetDefinitions()
    self.ASSET_DEFINITIONS = {
        basic = {
            cellCount = 1,
            sprite = {width = 20, height = 20, count = 5, sheet = "bubbles-basic"}
        },
        
        tierOne = {
            cellCount = 4,
            sprite = {width = 50, height = 36, count = 5, sheet = "bubbles-tier-one"}
        },
        
        tierTwo = {
            cellCount = 7,
            sprite = {width = 60, height = 52, count = 10, sheet = "bubbles-tier-two"}
        },
        
        tierThree = {
            cellCount = 19,
            sprite = {width = 100, height = 84, count = 10, sheet = "bubbles-tier-three"}
        }
    }
    
    -- Pattern templates: separate templates for even vs odd anchor rows
    self.PATTERN_TEMPLATES = {
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
    
end


function BubbleState:getHexStagger(row)
    -- Standardized hex stagger calculation matching grid setup
    -- Returns 1 if row has hex offset, 0 if not
    return ((row - 1) % 2)
end

function BubbleState:loadBubbleSprites()
    self.spriteSheets = {}
    
    -- Try to load each sprite sheet individually with error handling
    local spriteFiles = {
        basic = "bubbles-basic",
        tierOne = "bubbles-tier-one", 
        tierTwo = "bubbles-tier-two",
        tierThree = "bubbles-tier-three"
    }
    
    for assetType, fileName in pairs(spriteFiles) do
        local sheetPath = "assets/sprites/" .. fileName .. ".png"
        print("Loading " .. assetType .. " from: " .. sheetPath)
        
        local success, sheet = pcall(gfx.image.new, sheetPath)
        
        if success and sheet then
            self.spriteSheets[assetType] = sheet
            print("SUCCESS: " .. assetType .. " loaded")
        else
            print("FAILED: " .. assetType .. " could not load from " .. sheetPath)
            self.spriteSheets[assetType] = nil
        end
    end
    
    -- Report what loaded successfully
    print("=== Sprite Loading Summary ===")
    for assetType, sheet in pairs(self.spriteSheets) do
        if sheet then
            print("✓ " .. assetType .. " ready")
        else
            print("✗ " .. assetType .. " missing")
        end
    end
end

function BubbleState:populateTestAssets()
    self:generateRandomPlacements()
end

function BubbleState:generateRandomPlacements()
    self:despawnAllAssets()
    
    -- Reset verification system
    self.verificationPhase = false
    self.verificationFrameCounter = 0
    self.verificationDots = {}
    
    -- Create placement list with desired quantities
    local placements = {}
    
    -- Add 1 Tier Three bubble
    table.insert(placements, {type = "tierThree", bubbleType = math.random(1, 10)})
    
    -- Add 2 Tier Two bubbles
    for i = 1, 2 do
        table.insert(placements, {type = "tierTwo", bubbleType = math.random(1, 10)})
    end
    
    -- Add 3 Tier One bubbles
    for i = 1, 3 do
        table.insert(placements, {type = "tierOne", bubbleType = math.random(1, 5)})
    end
    
    -- Add 6 Basic bubbles
    for i = 1, 6 do
        table.insert(placements, {type = "basic", bubbleType = math.random(1, 5)})
    end
    
    -- Shuffle the placement order
    for i = #placements, 2, -1 do
        local j = math.random(i)
        placements[i], placements[j] = placements[j], placements[i]
    end
    
    -- Queue all placements with random coordinates
    self.placementQueue = {}
    for _, placement in ipairs(placements) do
        local row = math.random(1, self.totalRows)
        local maxColForRow = self.rowLengths[row] or 13
        local col = math.random(1, maxColForRow)
        
        table.insert(self.placementQueue, {
            type = placement.type,
            bubbleType = placement.bubbleType,
            row = row,
            col = col
        })
    end
    
    -- Reset frame counter to start placement process
    self.placementFrameCounter = 0
    
    print("=== Queued " .. #self.placementQueue .. " assets for random placement ===")
end

function BubbleState:placeAssetWithDebug(assetType, bubbleType, preferredRow, preferredCol)
    -- Direct placement only - no nudging
    local asset = self:placeAssetDirect(assetType, bubbleType, preferredRow, preferredCol)
    if not asset then
        print("PLACEMENT FAILED: " .. assetType .. " at (" .. preferredRow .. "," .. preferredCol .. ") - DESPAWNED")
    end
    return asset
end

function BubbleState:despawnAllAssets()
    -- Clear all occupation tracking
    self.occupiedBy = {}
    
    -- Clear all assets
    self.assets = {}
    
    -- Reset asset ID counter
    self.nextAssetId = 1
    
    -- Clear placement queue
    self.placementQueue = {}
    self.placementFrameCounter = 0
    
    print("All assets despawned")
end

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

function BubbleState:canPlaceAsset(assetType, row, col)
    -- Simplified - just check if we can generate the pattern cells
    local patternCells = self:findPatternCells(assetType, row, col)
    local definition = self.ASSET_DEFINITIONS[assetType]
    
    return patternCells and #patternCells == definition.cellCount
end

function BubbleState:findPatternCells(assetType, anchorRow, anchorCol)
    -- Simple template lookup: choose even or odd template based on anchor row
    local templates = self.PATTERN_TEMPLATES[assetType]
    if not templates then return {} end
    
    -- Choose template based on anchor row parity
    local anchorStagger = self:getHexStagger(anchorRow)
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


function BubbleState:createAsset(assetType, bubbleType, row, col)
    local definition = self.ASSET_DEFINITIONS[assetType]
    if not definition then return nil end
    
    -- Calculate center position for the asset
    local anchorCell = self:getCellAtRowCol(row, col)
    if not anchorCell then return nil end
    
    local centerX, centerY = self:calculateAssetCenter(assetType, row, col)
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

function BubbleState:calculateAssetCenter(assetType, row, col)
    local anchorCell = self:getCellAtRowCol(row, col)
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
        local anchorStagger = self:getHexStagger(row)
        local topLeftCell
        
        if anchorStagger == 0 then
            -- Odd row: top-left is at (row-1, col-1)
            topLeftCell = self:getCellAtRowCol(row - 1, col - 1)
        else
            -- Even row: top-left is at (row-1, col+0)  
            topLeftCell = self:getCellAtRowCol(row - 1, col)
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


function BubbleState:placeAssetDirect(assetType, bubbleType, row, col)
    -- Get pattern cells for this placement
    local patternCells = self:findPatternCells(assetType, row, col)
    if #patternCells == 0 then
        return nil
    end
    
    -- Create the asset
    local asset = self:createAsset(assetType, bubbleType, row, col)
    if not asset then
        return nil
    end
    
    -- Mark pattern cells as occupied (allows overlapping for now)
    for _, cellInfo in ipairs(patternCells) do
        self:markCellOccupied(cellInfo.row, cellInfo.col, asset.id)
    end
    
    -- Store the pattern cells with the asset
    asset.patternCells = patternCells
    
    -- Add to assets table
    self.assets[asset.id] = asset
    
    return asset
end

function BubbleState:createVerificationDots()
    -- Create black dots for all occupied cells, plus symbols for anchors
    self.verificationDots = {}
    
    -- First, identify anchor positions for each asset
    local anchorPositions = {}
    for _, asset in pairs(self.assets) do
        if asset.anchorRow and asset.anchorCol then
            local cellIndex = self:getCellIndex(asset.anchorRow, asset.anchorCol)
            if cellIndex then
                anchorPositions[cellIndex] = true
            end
        end
    end
    
    -- Create dots, marking anchors specially
    for cellIndex, assetId in pairs(self.occupiedBy) do
        local cell = self.gridCells[cellIndex]
        if cell then
            table.insert(self.verificationDots, {
                x = cell.x,
                y = cell.y,
                cellIndex = cellIndex,
                originalAssetId = assetId,
                isAnchor = anchorPositions[cellIndex] or false
            })
        end
    end
    
    print("Created " .. #self.verificationDots .. " verification dots")
end

function BubbleState:despawnAssetsKeepDots()
    -- Clear all assets but keep occupation and dots
    self.assets = {}
    print("Despawned all assets, kept verification dots and occupation data")
end

function BubbleState:drawAsset(asset)
    local definition = self.ASSET_DEFINITIONS[asset.type]
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

function BubbleState:enter()
    
end

function BubbleState:exit()
    
end

function BubbleState:update()
    if pd.buttonJustPressed(pd.kButtonB) then
        print("=== B Button Pressed - Regenerating Assets ===")
        self:generateRandomPlacements()
    end
    
    -- Process delayed placement queue
    if #self.placementQueue > 0 then
        self.placementFrameCounter = self.placementFrameCounter + 1
        
        if self.placementFrameCounter >= self.placementDelay then
            -- Place next asset in queue
            local nextPlacement = table.remove(self.placementQueue, 1)
            self:placeAssetWithDebug(nextPlacement.type, nextPlacement.bubbleType, nextPlacement.row, nextPlacement.col)
            
            -- Reset frame counter for next placement
            self.placementFrameCounter = 0
            
            -- Check if we're done placing assets
            if #self.placementQueue == 0 then
                print("=== Delayed Placement Complete - Starting Verification Phase ===")
                self.verificationPhase = true
                self.verificationFrameCounter = 0
            end
        end
    end
    
    -- Process verification phase
    if self.verificationPhase then
        self.verificationFrameCounter = self.verificationFrameCounter + 1
        
        if self.verificationFrameCounter >= self.verificationDelay then
            print("=== Creating Verification Dots ===")
            self:createVerificationDots()
            self:despawnAssetsKeepDots()
            self.verificationPhase = false
            print("=== Verification Phase Complete ===")
        end
    end
    
    return nil
end

function BubbleState:draw()
    gfx.clear()
    
    -- Draw dashed boundary lines manually (6px on, 4px off)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    
    local leftLineX = self.leftPadding - 2
    local rightLineX = 400 - self.rightPadding + 2
    
    -- Draw left boundary dashed line
    for y = 0, 240, 10 do
        gfx.drawLine(leftLineX, y, leftLineX, math.min(y + 6, 240))
    end
    
    -- Draw right boundary dashed line  
    for y = 0, 240, 10 do
        gfx.drawLine(rightLineX, y, rightLineX, math.min(y + 6, 240))
    end
    
    -- Debug: render all grid circles
    for _, cell in ipairs(self.gridCells) do
        gfx.drawCircleAtPoint(cell.x, cell.y, self.circleSize/2)
    end
    
    
    -- Draw all assets using unified rendering system
    for _, asset in pairs(self.assets) do
        self:drawAsset(asset)
    end
    
    -- Draw verification dots if they exist
    if #self.verificationDots > 0 then
        gfx.setColor(gfx.kColorBlack)
        for _, dot in ipairs(self.verificationDots) do
            if dot.isAnchor then
                -- Draw plus symbol for anchor
                gfx.drawLine(dot.x - 4, dot.y, dot.x + 4, dot.y)  -- Horizontal line
                gfx.drawLine(dot.x, dot.y - 4, dot.x, dot.y + 4)  -- Vertical line
            else
                -- Draw regular dot for non-anchor cells
                gfx.fillCircleAtPoint(dot.x, dot.y, 3)
            end
        end
    end
end