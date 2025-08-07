import "utils/constants"
import "CoreLibs/graphics"

Grid = {}

function Grid:new()
    local instance = {
        cells = {},
        width = Constants and Constants.GRID_WIDTH or 10,
        height = Constants and Constants.GRID_HEIGHT or 8,
        bubbleRadius = Constants and Constants.BUBBLE_RADIUS or 12,
        hexSpacingX = Constants and Constants.HEX_SPACING_X or 24,
        hexSpacingY = Constants and Constants.HEX_SPACING_Y or 20,
        hexOffsetX = Constants and Constants.HEX_OFFSET_X or 12,
        shooterX = Constants and Constants.SHOOTER_X or 350,
        baseShooterY = Constants and Constants.SHOOTER_Y or 120,
        shooterY = Constants and Constants.SHOOTER_Y or 120,
        boundaryX = Constants and Constants.BOUNDARY_X or 300,
        -- Crank tracking
        crankTotal = 0,
        minShooterY = 20,
        maxShooterY = 220,
        aimAngle = 180,
        projectile = nil,
        gameOver = false,
        shotsRemaining = 10,
        nextBubbleType = math.random(1, 5),
        nextBubbleIsTier2 = false,
        previewBubbleType = math.random(1, 5),
        previewBubbleIsTier2 = false,
        bubbleSprites = {},
        tier1Sprites = {},
        tier2Sprites = {},
        -- Tier 1 performance cache
        tier1OccupiedCache = {}, -- Cache of all cells occupied by Tier 1 bubbles
        tier1CacheDirty = true,  -- Flag to rebuild cache when needed
        -- Animation state for preview ball
        previewScale = 1.0,
        previewAnimating = false,
        -- Flip state for UI elements when shooter is too low
        uiFlipped = false,
        -- Cached boundary calculations
        leftBoundaryX = 0,
        topBoundaryY = 0,
        bottomBoundaryY = 0,
        rightBoundaryX = 0
    }
    setmetatable(instance, self)
    self.__index = self
    
    instance:initGrid()
    instance:loadBubbleSprites()
    instance:loadTier1Sprites()
    instance:loadTier2Sprites()
    instance:updateBoundaryCache()
    return instance
end

function Grid:loadBubbleSprites()
    -- Load the bubble sprite sheet
    local spriteSheet = playdate.graphics.image.new("assets/sprites/bubbles-basic.png")
    
    if spriteSheet then
        local sheetWidth, sheetHeight = spriteSheet:getSize()
        
        -- Extract sprites from the sheet (handle both 5 and 10 sprite sheets)
        local numSprites = math.floor(sheetWidth / 15)
        for i = 1, numSprites do
            local x = (i - 1) * 15  -- Each sprite is 15 pixels wide
            
            -- Create a new 15x15 image and draw the specific region
            local sprite = playdate.graphics.image.new(15, 15)
            playdate.graphics.pushContext(sprite)
            -- Draw the sprite sheet at negative offset to show only the desired region
            spriteSheet:draw(-x, 0)
            playdate.graphics.popContext()
            
            local w, h = sprite:getSize()
            self.bubbleSprites[i] = sprite
        end
    else
        -- Fallback: create simple filled circles if sprite sheet not found
        for i = 1, 5 do
            local sprite = playdate.graphics.image.new(15, 15)
            playdate.graphics.pushContext(sprite)
            playdate.graphics.setColor(playdate.graphics.kColorBlack)
            playdate.graphics.fillCircleAtPoint(7.5, 7.5, 7)  -- Fill circle in center
            playdate.graphics.popContext()
            self.bubbleSprites[i] = sprite
        end
    end
end

function Grid:loadTier1Sprites()
    -- Load the Tier 1 bubble sprite sheet
    local spriteSheet = playdate.graphics.image.new("assets/sprites/bubbles-tier-one.png")
    
    if spriteSheet then
        local sheetWidth, sheetHeight = spriteSheet:getSize()
        
        -- Extract 10 Tier 1 sprites from the sheet - each is 30px wide by 27px tall
        for i = 1, 10 do
            local x = (i - 1) * 30  -- Each Tier 1 sprite is 30 pixels wide
            
            -- Create a new 30x27 image and draw the specific region
            local sprite = playdate.graphics.image.new(30, 27)
            playdate.graphics.pushContext(sprite)
            -- Draw the sprite sheet at negative offset to show only the desired region
            spriteSheet:draw(-x, 0)
            playdate.graphics.popContext()
            
            self.tier1Sprites[i] = sprite
        end
    else
        -- Fallback: create simple filled rectangles if sprite sheet not found
        for i = 1, 10 do
            local sprite = playdate.graphics.image.new(30, 27)
            playdate.graphics.pushContext(sprite)
            playdate.graphics.setColor(playdate.graphics.kColorBlack)
            playdate.graphics.fillRect(0, 0, 30, 27)
            playdate.graphics.popContext()
            self.tier1Sprites[i] = sprite
        end
    end
end

function Grid:loadTier2Sprites()
    -- Load the Tier 2 bubble sprite sheet
    local spriteSheet = playdate.graphics.image.new("assets/sprites/bubbles-tier-two.png")
    
    if spriteSheet then
        -- For now, just one Tier 2 sprite (unified type)
        self.tier2Sprites[1] = spriteSheet
    else
        -- Fallback: create simple filled rectangle if sprite sheet not found
        local sprite = playdate.graphics.image.new(45, 60)  -- Approximate size for 7-cell diamond
        playdate.graphics.pushContext(sprite)
        playdate.graphics.setColor(playdate.graphics.kColorBlack)
        playdate.graphics.fillRect(0, 0, 45, 60)
        playdate.graphics.popContext()
        self.tier2Sprites[1] = sprite
    end
end

function Grid:drawBubbleByType(x, y, bubbleType)
    if bubbleType and bubbleType >= 1 and bubbleType <= 10 and self.bubbleSprites[bubbleType] then
        -- Draw regular bubble sprite centered at x, y
        self.bubbleSprites[bubbleType]:drawCentered(x, y)
    elseif bubbleType and bubbleType >= 11 and bubbleType <= 15 then
        -- Draw Tier 1 bubble - need to determine sprite index and position
        self:drawTier1Bubble(x, y, bubbleType)
    elseif bubbleType and bubbleType == 16 then
        -- Draw Tier 2 bubble at screen coordinates
        self:drawTier2ProjectileAt(x, y, bubbleType)
    else
        -- Fallback to circle if sprite not available
        playdate.graphics.drawCircleAtPoint(x, y, self.bubbleRadius)
    end
end

function Grid:drawTier1Bubble(gridX, gridY, bubbleType)
    -- Get the bubble's configuration and sprite index
    local bubble = self.cells[gridX] and self.cells[gridX][gridY]
    if not bubble or not bubble.tier1Config then return end
    
    local config = bubble.tier1Config -- "UP" or "DOWN"
    local spriteIndex = Constants.TIER1_SPRITE_INDICES[config][bubbleType]
    
    if spriteIndex and self.tier1Sprites[spriteIndex] then
        local leftX, topY
        
        -- Calculate the draw position for perfect alignment
        leftX, topY = self:gridToScreen(gridX, gridY)
        
        -- For UP triangles, adjust positioning since gridX/gridY is the point, not the base
        if config == "UP" then
            -- UP triangles are anchored at the point but sprite should align to base
            -- Shift left by half a cell to align with the visual triangle center
            leftX = leftX - (self.hexSpacingX / 2)
        end
        
        -- Position sprite so the top edge aligns with the hex row
        -- The sprite should span from leftmost cell to rightmost cell horizontally
        local spriteX = leftX - self.bubbleRadius
        local spriteY = topY - self.bubbleRadius
        
        self.tier1Sprites[spriteIndex]:draw(spriteX, spriteY)
    end
end

function Grid:drawTier1Projectile(x, y, bubbleType, tier1Config)
    -- Draw a Tier 1 bubble as a projectile (moving)
    if not tier1Config then
        print("WARNING: drawTier1Projectile called with nil tier1Config for type " .. bubbleType)
        tier1Config = "UP"  -- Default to UP configuration as fallback
    end
    
    local spriteIndex = Constants.TIER1_SPRITE_INDICES[tier1Config][bubbleType]
    
    if spriteIndex and self.tier1Sprites[spriteIndex] then
        -- Center the sprite on the projectile position
        local spriteX = x - 15  -- Half sprite width (30px / 2)
        local spriteY = y - 13.5  -- Half sprite height (27px / 2)
        self.tier1Sprites[spriteIndex]:draw(spriteX, spriteY)
    else
        -- Fallback to rectangle
        playdate.graphics.fillRect(x - 15, y - 13.5, 30, 27)
    end
end

function Grid:drawTier2Bubble(gridX, gridY, bubbleType)
    -- Draw Tier 2 bubble (diamond pattern, 7 cells)
    if bubbleType == 16 and self.tier2Sprites[1] then
        -- Calculate position for the Tier 2 sprite
        local centerX, centerY = self:gridToScreen(gridX, gridY)
        
        -- Center the sprite on the middle cell of the diamond
        local spriteX = centerX - 22.5  -- Half sprite width
        local spriteY = centerY - 30    -- Half sprite height
        
        self.tier2Sprites[1]:draw(spriteX, spriteY)
    else
        -- Fallback - draw a large rectangle
        local centerX, centerY = self:gridToScreen(gridX, gridY)
        playdate.graphics.fillRect(centerX - 22, centerY - 30, 45, 60)
    end
end

function Grid:drawTier2Projectile(x, y, bubbleType)
    -- Draw a Tier 2 bubble as a projectile (moving)
    if bubbleType == 16 and self.tier2Sprites[1] then
        -- Center the sprite on the projectile position
        local spriteX = x - 22.5  -- Half sprite width
        local spriteY = y - 30    -- Half sprite height
        self.tier2Sprites[1]:draw(spriteX, spriteY)
    else
        -- Fallback to rectangle
        playdate.graphics.fillRect(x - 22, y - 30, 45, 60)
    end
end

function Grid:drawTier2ProjectileAt(x, y, bubbleType)
    -- Draw a Tier 2 bubble at screen coordinates (alias for drawTier2Projectile)
    self:drawTier2Projectile(x, y, bubbleType)
end

function Grid:drawScaledBubbleByType(x, y, bubbleType, scale)
    if bubbleType and bubbleType >= 1 and bubbleType <= 10 and self.bubbleSprites[bubbleType] then
        -- Draw sprite scaled and centered at x, y
        self.bubbleSprites[bubbleType]:drawScaled(x - 15 * scale, y - 15 * scale, scale)
    else
        -- Fallback to scaled circle if sprite not available
        playdate.graphics.drawCircleAtPoint(x, y, self.bubbleRadius * scale)
    end
end

function Grid:updateBoundaryCache()
    -- Calculate and cache all boundary positions
    local leftmostX, _ = self:gridToScreen(1, 1)
    local _, topmostY = self:gridToScreen(1, 1)
    local _, bottomRowY = self:gridToScreen(1, 17)
    local col20EvenRowX, _ = self:gridToScreen(20, 2)  -- Use column 20 as boundary for 26-column grid
    
    self.leftBoundaryX = leftmostX - self.bubbleRadius - 2 - 2  -- Additional 2px space before boundary
    self.topBoundaryY = topmostY - self.bubbleRadius - 2
    self.bottomBoundaryY = bottomRowY + self.bubbleRadius + 2
    self.rightBoundaryX = col20EvenRowX + self.bubbleRadius + 2
end

function Grid:getShooterPosition()
    -- Position shooter ball so outer edge has 2px buffer from dashed line
    return self.rightBoundaryX + self.bubbleRadius + 2, self.shooterY
end

function Grid:getPreviewPosition()
    local shooterX, shooterY = self:getShooterPosition()
    
    if self.uiFlipped then
        -- When flipped, position preview ball above and behind shooter
        return shooterX + (self.bubbleRadius * 2) + 5 - 11, shooterY - 25
    else
        -- Normal position: below and behind shooter, moved 11px left total
        return shooterX + (self.bubbleRadius * 2) + 5 - 11, shooterY + 25
    end
end

function Grid:initGrid()
    self.cells = {}
    for x = 1, self.width do
        self.cells[x] = {}
        for y = 1, self.height do
            self.cells[x][y] = nil
        end
    end
end

-- Convert grid coordinates to screen position (hex layout)
function Grid:gridToScreen(gridX, gridY)
    local screenX = (gridX - 1) * self.hexSpacingX
    local screenY = (gridY - 1) * self.hexSpacingY
    
    -- Offset even rows for hex pattern (matching prototype)
    if gridY % 2 == 0 then  
        screenX = screenX + self.hexOffsetX
    end
    
    -- Simple fixed positioning approach - center the grid with reasonable margins
    local startX = 50  -- Fixed left margin to center the grid better
    
    -- Center vertically  
    local gridHeight = (self.height - 1) * self.hexSpacingY + 2 * self.bubbleRadius
    local startY = (240 - gridHeight) / 2
    
    return startX + screenX + self.bubbleRadius, startY + screenY + self.bubbleRadius
end

-- Convert screen position to grid coordinates (hex layout)
function Grid:screenToGrid(screenX, screenY)
    -- Match the fixed positioning from gridToScreen
    local startX = 50  -- Fixed left margin to match gridToScreen
    
    local gridHeight = (self.height - 1) * self.hexSpacingY + 2 * self.bubbleRadius
    local startY = (240 - gridHeight) / 2
    
    local relativeX = screenX - startX - self.bubbleRadius
    local relativeY = screenY - startY - self.bubbleRadius
    
    local gridY = math.floor(relativeY / self.hexSpacingY) + 1
    local adjustedX = relativeX
    
    -- Adjust for hex offset
    if gridY % 2 == 0 then
        adjustedX = adjustedX - self.hexOffsetX
    end
    
    local gridX = math.floor(adjustedX / self.hexSpacingX) + 1
    
    return gridX, gridY
end

function Grid:setupLevel(level)
    self:initGrid()
    
    -- Define specific placement pattern
    local placementCells = {}
    
    -- Top and bottom rows (1 and 17): 12 dots each
    for x = 1, 12 do
        table.insert(placementCells, {x = x, y = 1, fillChance = 1.0})
        table.insert(placementCells, {x = x, y = 17, fillChance = 1.0})
    end
    
    -- Next rows in from top and bottom (2, 3, 15, 16): 8 dots each
    for _, row in ipairs({2, 3, 15, 16}) do
        for x = 1, 8 do
            table.insert(placementCells, {x = x, y = row, fillChance = 1.0})
        end
    end
    
    -- Columns 1 and 2: every cell (all rows)
    for y = 1, 17 do
        for x = 1, 2 do
            -- Only add if not already added by previous rules
            local alreadyAdded = false
            for _, existing in ipairs(placementCells) do
                if existing.x == x and existing.y == y then
                    alreadyAdded = true
                    break
                end
            end
            if not alreadyAdded then
                table.insert(placementCells, {x = x, y = y, fillChance = 1.0})
            end
        end
    end
    
    -- Row 8 and 10: 7 cells each
    for _, row in ipairs({8, 10}) do
        for x = 1, 7 do
            table.insert(placementCells, {x = x, y = row, fillChance = 1.0})
        end
    end
    
    -- Row 9: 8 cells
    for x = 1, 8 do
        table.insert(placementCells, {x = x, y = 9, fillChance = 1.0})
    end
    
    -- Place bubbles one by one, ensuring no 3-matches are created
    for _, cell in ipairs(placementCells) do
        if math.random() < cell.fillChance then
            local bubbleType = self:findSafeBubbleType(cell.x, cell.y)
            if bubbleType then
                self.cells[cell.x][cell.y] = {
                    type = bubbleType,
                    x = cell.x,
                    y = cell.y
                }
            end
        end
    end
end

function Grid:setupLevelWithMergedBalls(level, survivingMergedBalls)
    self:initGrid()
    
    
    -- First, place the surviving merged balls
    for _, ballData in ipairs(survivingMergedBalls) do
        if ballData.x >= 1 and ballData.x <= self.width and ballData.y >= 1 and ballData.y <= self.height then
            self.cells[ballData.x][ballData.y] = {
                type = ballData.type,
                x = ballData.x,
                y = ballData.y,
                isPreExisting = true, -- Mark as pre-existing merged ball
                isTier1 = ballData.isTier1 or false,
                tier1Config = ballData.tier1Config
            }
            
            -- If it's a Tier 1, log its occupied cells
            if ballData.isTier1 then
                local occupiedCells = self:getTier1OccupiedCells(ballData.x, ballData.y, ballData.tier1Config)
            end
        end
    end
    
    -- Then setup new basic balls using the same pattern as setupLevel, 
    -- but avoiding positions where merged balls already exist
    local placementCells = {}
    
    -- Top and bottom rows (1 and 17): 12 dots each
    for x = 1, 12 do
        if self:isCellAvailable(x, 1) then
            table.insert(placementCells, {x = x, y = 1, fillChance = 1.0})
        end
        if self:isCellAvailable(x, 17) then
            table.insert(placementCells, {x = x, y = 17, fillChance = 1.0})
        end
    end
    
    -- Next rows in from top and bottom (2, 3, 15, 16): 8 dots each
    for _, row in ipairs({2, 3, 15, 16}) do
        for x = 1, 8 do
            if self:isCellAvailable(x, row) then
                table.insert(placementCells, {x = x, y = row, fillChance = 1.0})
            end
        end
    end
    
    -- Columns 1 and 2: every cell (all rows)
    for y = 1, 17 do
        for x = 1, 2 do
            if self:isCellAvailable(x, y) then
                -- Only add if not already added by previous rules
                local alreadyAdded = false
                for _, existing in ipairs(placementCells) do
                    if existing.x == x and existing.y == y then
                        alreadyAdded = true
                        break
                    end
                end
                if not alreadyAdded then
                    table.insert(placementCells, {x = x, y = y, fillChance = 1.0})
                end
            end
        end
    end
    
    -- Row 8 and 10: 7 cells each
    for _, row in ipairs({8, 10}) do
        for x = 1, 7 do
            if self:isCellAvailable(x, row) then
                table.insert(placementCells, {x = x, y = row, fillChance = 1.0})
            end
        end
    end
    
    -- Row 9: 8 cells
    for x = 1, 8 do
        if self:isCellAvailable(x, 9) then
            table.insert(placementCells, {x = x, y = 9, fillChance = 1.0})
        end
    end
    
    -- Place new basic bubbles one by one, ensuring no 3-matches are created
    for _, cell in ipairs(placementCells) do
        if math.random() < cell.fillChance then
            local bubbleType = self:findSafeBubbleType(cell.x, cell.y)
            if bubbleType then
                self.cells[cell.x][cell.y] = {
                    type = bubbleType,
                    x = cell.x,
                    y = cell.y,
                    isPreExisting = false -- Mark as new basic ball
                }
            else
            end
        end
    end
    
    -- Mark cache as dirty since we may have restored Tier 1 bubbles
    self:markTier1CacheDirty()
    
end

function Grid:findSafeBubbleType(x, y)
    -- First check if the cell should even be used for bubble placement
    if not self:isCellAvailable(x, y) then
        return nil
    end
    
    -- Try bubble types in random order to add variety
    local types = {1, 2, 3, 4, 5}
    for i = #types, 2, -1 do
        local j = math.random(i)
        types[i], types[j] = types[j], types[i]
    end
    
    local bestType = nil
    local bestScore = -1
    
    for _, bubbleType in ipairs(types) do
        -- Store existing bubble (if any) before testing
        local existingBubble = self.cells[x] and self.cells[x][y]
        
        -- Test if this type would create a 3-match
        self.cells[x][y] = {type = bubbleType, x = x, y = y}
        local neighbors = self:getSameTypeNeighbors(x, y, bubbleType)
        local wouldCreate3Match = #neighbors >= 3
        
        -- Restore the original bubble (or nil)
        self.cells[x][y] = existingBubble
        
        if not wouldCreate3Match then
            -- Calculate how many 2-matches this would create
            local score = self:calculateMatchScore(x, y, bubbleType)
            if score > bestScore then
                bestScore = score
                bestType = bubbleType
            end
        end
    end
    
    return bestType
end

function Grid:calculateMatchScore(x, y, bubbleType)
    local score = 0
    local neighbors = self:getDirectNeighbors(x, y)
    
    -- Count how many neighbors would match this type
    for _, neighbor in ipairs(neighbors) do
        if self.cells[neighbor.x] and self.cells[neighbor.x][neighbor.y] and 
           self.cells[neighbor.x][neighbor.y].type == bubbleType then
            score = score + 1
        end
    end
    
    return score
end

function Grid:getDirectNeighbors(x, y)
    local neighbors = {}
    local directions
    
    if y % 2 == 1 then  -- Odd rows
        directions = {{0,1}, {0,-1}, {1,0}, {-1,0}, {-1,-1}, {-1,1}}
    else  -- Even rows
        directions = {{0,1}, {0,-1}, {1,0}, {-1,0}, {1,-1}, {1,1}}
    end
    
    for _, dir in ipairs(directions) do
        local nx, ny = x + dir[1], y + dir[2]
        if nx >= 1 and nx <= self.width and ny >= 1 and ny <= self.height then
            table.insert(neighbors, {x = nx, y = ny})
        end
    end
    
    return neighbors
end

function Grid:shootBubble()
    if self.projectile then
        return false
    end
    
    local shooterX, shooterY = self:getShooterPosition()
    
    self.projectile = {
        x = shooterX,
        y = shooterY,
        vx = math.cos(math.rad(self.aimAngle)) * (Constants and Constants.BUBBLE_SPEED or 8),
        vy = math.sin(math.rad(self.aimAngle)) * (Constants and Constants.BUBBLE_SPEED or 8),
        type = self.nextBubbleType,
        isTier1 = self.nextBubbleIsTier1 or false,
        isTier2 = self.nextBubbleIsTier2 or false,
        tier1Config = self.nextBubbleTier1Config
    }
    
    
    -- Start preview ball animation
    self.previewAnimating = true
    
    -- Shot queue is now managed by BubbleState, don't override here
    
    return true
end

function Grid:shouldFlipUI()
    -- Check if the shooting apparatus would cause shot counter to go off bottom of screen
    local _, shooterY = self:getShooterPosition()
    local previewY = shooterY + 25  -- preview ball position
    local currentFont = playdate.graphics.getFont()
    local textHeight = currentFont:getHeight()
    local gap = 8
    local shotCounterY = previewY + self.bubbleRadius + gap
    local textBottomY = shotCounterY + textHeight
    return textBottomY > 240
end

function Grid:update()
    -- Handle crank input for shooter vertical movement
    local crankChange = playdate.getCrankChange()
    if crankChange ~= 0 then
        self.crankTotal = self.crankTotal + crankChange
        
        -- Convert crank rotation to Y position (720° total range = 200px movement)
        local movementRange = self.maxShooterY - self.minShooterY
        local yOffset = (self.crankTotal / 720) * movementRange
        self.shooterY = self.baseShooterY + yOffset
        
        -- Clamp position and adjust crankTotal to prevent drift
        if self.shooterY < self.minShooterY then
            self.shooterY = self.minShooterY
            self.crankTotal = ((self.minShooterY - self.baseShooterY) / movementRange) * 720
        elseif self.shooterY > self.maxShooterY then
            self.shooterY = self.maxShooterY
            self.crankTotal = ((self.maxShooterY - self.baseShooterY) / movementRange) * 720
        end
    end
    
    -- Update UI flip state based on shooter position
    self.uiFlipped = self:shouldFlipUI()
    
    -- Handle D-pad aiming
    if playdate.buttonIsPressed(playdate.kButtonDown) then
        self.aimAngle = math.max(110, self.aimAngle - 2)
    elseif playdate.buttonIsPressed(playdate.kButtonUp) then
        self.aimAngle = math.min(250, self.aimAngle + 2)
    end
    
    -- Handle preview ball animation when shot is fired
    if self.previewAnimating then
        -- Simple animation - just turn off after a few frames
        self.previewAnimating = false
    end
    
    if self.projectile then
        self.projectile.x += self.projectile.vx
        self.projectile.y += self.projectile.vy
        
        -- Handle bouncing off grid boundaries (circumference-based)
        -- Left boundary bounce
        if self.projectile.x - self.bubbleRadius <= self.leftBoundaryX then
            self.projectile.x = self.leftBoundaryX + self.bubbleRadius
            self.projectile.vx = -self.projectile.vx
        end
        
        -- Top boundary bounce (screen edge)
        if self.projectile.y - self.bubbleRadius <= 0 then
            self.projectile.y = self.bubbleRadius
            self.projectile.vy = -self.projectile.vy
        end
        
        -- Bottom boundary bounce (screen edge)
        if self.projectile.y + self.bubbleRadius >= 240 then
            self.projectile.y = 240 - self.bubbleRadius
            self.projectile.vy = -self.projectile.vy
        end
        
        -- Remove projectile if it goes off screen or past right boundary
        if self.projectile.x <= 0 or self.projectile.y <= 0 or self.projectile.y >= 240 or 
           self.projectile.x - self.bubbleRadius >= self.rightBoundaryX then
            self.projectile = nil
        else
            self:checkProjectileCollision()
        end
    end
end

function Grid:checkProjectileCollision()
    -- Check if projectile went past boundaries first
    if self.projectile.x <= 0 or self.projectile.y <= 0 or self.projectile.y >= 240 then
        self.gameOver = true
        self.projectile = nil
        return
    end
    
    -- Check collision with existing bubbles using distance
    for x = 1, self.width do
        for y = 1, self.height do
            local bubble = self.cells[x][y]
            if bubble then
                if bubble.isTier1 then
                    -- Check collision with Tier 1 bubble - check all occupied cells
                    if self:checkTier1Collision(x, y, bubble) then
                        self:handleProjectileHit()
                        return
                    end
                elseif bubble.isTier2 then
                    -- Check collision with Tier 2 bubble - check all occupied cells
                    if self:checkTier2Collision(x, y, bubble) then
                        self:handleProjectileHit()
                        return
                    end
                else
                    -- Check collision with regular bubble
                    local bubbleX, bubbleY = self:gridToScreen(x, y)
                    local distance = math.sqrt((self.projectile.x - bubbleX)^2 + (self.projectile.y - bubbleY)^2)
                    
                    -- If projectile is close enough to an existing bubble (reduced hitbox by 5px for easier navigation)
                    if distance <= (self.bubbleRadius * 2) - 5 then
                        self:handleProjectileHit()
                        return
                    end
                end
            end
        end
    end
    
    -- Top wall attachment disabled - now handled by bouncing in update()
end

function Grid:checkTier1Collision(x, y, tier1Bubble)
    -- Check collision with any part of the Tier 1 bubble's occupied area
    local occupiedCells = self:getTier1OccupiedCells(x, y, tier1Bubble.tier1Config)
    
    for _, cell in ipairs(occupiedCells) do
        local cellX, cellY = self:gridToScreen(cell.x, cell.y)
        local distance = math.sqrt((self.projectile.x - cellX)^2 + (self.projectile.y - cellY)^2)
        
        if distance <= (self.bubbleRadius * 2) - 5 then
            return true
        end
    end
    
    return false
end

function Grid:checkTier2Collision(x, y, tier2Bubble)
    -- Check collision with any part of the Tier 2 bubble's occupied area (diamond pattern)
    local occupiedCells = self:getTier2OccupiedCells(x, y)
    
    for _, cell in ipairs(occupiedCells) do
        local cellX, cellY = self:gridToScreen(cell.x, cell.y)
        local distance = math.sqrt((self.projectile.x - cellX)^2 + (self.projectile.y - cellY)^2)
        
        if distance <= (self.bubbleRadius * 2) - 5 then
            return true
        end
    end
    
    return false
end

function Grid:handleProjectileHit()
    local bestX, bestY
    
    if self.projectile.isTier1 then
        -- Special placement for Tier 1 projectiles
        bestX, bestY = self:findBestTier1Spot(self.projectile.x, self.projectile.y, self.projectile.tier1Config)
    elseif self.projectile.isTier2 or self.projectile.type == 16 then
        -- Special placement for Tier 2 projectiles
        bestX, bestY = self:findBestTier2Spot(self.projectile.x, self.projectile.y)
    else
        -- Regular placement for normal bubbles
        bestX, bestY = self:findClosestEmptySpot(self.projectile.x, self.projectile.y)
    end
    
    if bestX and bestY then
        -- Check if this placement would cross the game boundary
        if self:checkBubbleCrossesGameBoundary(bestX, bestY) then
            self.gameOver = true
            self.projectile = nil
            return
        end
        
        -- Store projectile data before clearing it
        local wasT1 = self.projectile.isTier1
        local wasT2 = self.projectile.isTier2 or self.projectile.type == 16
        local projType = self.projectile.type
        local projTier1Config = self.projectile.tier1Config
        
        -- Clear conflicting bubbles BEFORE placing the new one
        if wasT2 then
            -- For Tier 2, clear any basic bubbles in the diamond pattern
            local occupiedCells = self:getTier2OccupiedCells(bestX, bestY)
            for _, cell in ipairs(occupiedCells) do
                local existingBubble = self.cells[cell.x] and self.cells[cell.x][cell.y]
                if existingBubble and existingBubble.type <= 5 then
                    self.cells[cell.x][cell.y] = nil
                end
            end
        elseif wasT1 then
            -- For Tier 1, clear any basic bubbles in the footprint
            local occupiedCells = self:getTier1OccupiedCells(bestX, bestY, projTier1Config)
            for _, cell in ipairs(occupiedCells) do
                local existingBubble = self.cells[cell.x] and self.cells[cell.x][cell.y]
                if existingBubble and existingBubble.type <= 5 then
                    self.cells[cell.x][cell.y] = nil
                end
            end
        end
        
        -- Place the bubble with proper footprint
        if wasT2 then
            -- Place Tier 2 in full diamond pattern
            local occupiedCells = self:getTier2OccupiedCells(bestX, bestY)
            for _, cell in ipairs(occupiedCells) do
                self.cells[cell.x][cell.y] = {
                    type = projType,
                    x = bestX,  -- Store center position
                    y = bestY,
                    isTier2 = true,
                    tier2Center = (cell.x == bestX and cell.y == bestY) -- Mark center cell
                }
                if cell.x == bestX and cell.y == bestY then
                    print("Set Tier 2 center at (" .. cell.x .. "," .. cell.y .. ") - isTier2: " .. tostring(self.cells[cell.x][cell.y].isTier2) .. " center: " .. tostring(self.cells[cell.x][cell.y].tier2Center))
                end
            end
            print("Placed Tier 2 projectile at (" .. bestX .. "," .. bestY .. ") - center at (" .. bestX .. "," .. bestY .. ")")
        elseif wasT1 then
            -- Place Tier 1 in full horizontal pattern
            local occupiedCells = self:getTier1OccupiedCells(bestX, bestY, projTier1Config)
            print("Tier 1 occupying " .. #occupiedCells .. " cells around anchor (" .. bestX .. "," .. bestY .. ")")
            for _, cell in ipairs(occupiedCells) do
                print("  Cell (" .. cell.x .. "," .. cell.y .. ") - is anchor: " .. tostring(cell.x == bestX and cell.y == bestY))
                self.cells[cell.x][cell.y] = {
                    type = projType,
                    x = bestX,  -- Store anchor position
                    y = bestY,
                    isTier1 = true,
                    tier1Config = projTier1Config,
                    tier1Anchor = (cell.x == bestX and cell.y == bestY) -- Mark anchor cell
                }
                if cell.x == bestX and cell.y == bestY then
                    print("Set Tier 1 anchor at (" .. cell.x .. "," .. cell.y .. ")")
                end
            end
            print("Placed Tier 1 projectile type " .. projType .. " config " .. tostring(projTier1Config) .. " at (" .. bestX .. "," .. bestY .. ") - anchor at (" .. bestX .. "," .. bestY .. ")")
        else
            -- Regular bubble - single cell
            self.cells[bestX][bestY] = {
                type = projType,
                x = bestX,
                y = bestY
            }
        end
        self.projectile = nil
        
        -- Mark cache dirty for Tier 1 placement
        if wasT1 then
            self:markTier1CacheDirty()
        end
        
        self:checkMerges(bestX, bestY)
    end
end

function Grid:findClosestEmptySpot(projX, projY)
    local bestX, bestY = nil, nil
    local bestDistanceSquared = math.huge  -- Use squared distance to avoid sqrt
    
    -- Check all grid positions for the closest empty spot
    for x = 1, self.width do
        for y = 1, self.height do
            if self:isCellAvailable(x, y) then
                local gridScreenX, gridScreenY = self:gridToScreen(x, y)
                -- Use squared distance to avoid expensive sqrt calculation
                local distanceSquared = (projX - gridScreenX)^2 + (projY - gridScreenY)^2
                
                if distanceSquared < bestDistanceSquared then
                    bestDistanceSquared = distanceSquared
                    bestX, bestY = x, y
                end
            end
        end
    end
    
    return bestX, bestY
end

function Grid:findBestTier1Spot(projX, projY, config)
    local bestX, bestY = nil, nil
    local bestDistanceSquared = math.huge
    
    -- First pass: Try to find spots that don't require overwriting bubbles
    for x = 1, self.width do
        for y = 1, self.height do
            if self:canPlaceTier1At(x, y, config, 11) then -- Use type 11 as test type
                -- Check if this spot is relatively empty (minimal overwriting)
                local isEmpty = self:isTier1SpotEmpty(x, y, config)
                if isEmpty then
                    local gridScreenX, gridScreenY = self:gridToScreen(x, y)
                    local distanceSquared = (projX - gridScreenX)^2 + (projY - gridScreenY)^2
                    
                    if distanceSquared < bestDistanceSquared then
                        bestDistanceSquared = distanceSquared
                        bestX, bestY = x, y
                    end
                end
            end
        end
    end
    
    -- If no empty spots found, fall back to any valid spot
    if not bestX then
        bestDistanceSquared = math.huge
        for x = 1, self.width do
            for y = 1, self.height do
                if self:canPlaceTier1At(x, y, config, 11) then -- Use type 11 as test type
                    local gridScreenX, gridScreenY = self:gridToScreen(x, y)
                    local distanceSquared = (projX - gridScreenX)^2 + (projY - gridScreenY)^2
                    
                    if distanceSquared < bestDistanceSquared then
                        bestDistanceSquared = distanceSquared
                        bestX, bestY = x, y
                    end
                end
            end
        end
    end
    
    return bestX, bestY
end

function Grid:isTier1SpotEmpty(x, y, config)
    local occupiedCells = self:getTier1OccupiedCells(x, y, config)
    
    for _, pos in ipairs(occupiedCells) do
        local existingBubble = self.cells[pos.x] and self.cells[pos.x][pos.y]
        if existingBubble then
            return false -- Found an existing bubble
        end
    end
    
    return true -- All cells are empty
end

function Grid:findBestTier2Spot(projX, projY)
    local bestX, bestY = nil, nil
    local bestDistanceSquared = math.huge
    local validSpots = 0
    local emptySpots = 0
    
    -- First pass: Try to find completely empty spots
    for x = 1, self.width do
        for y = 1, self.height do
            if self:canPlaceTier2At(x, y) then
                validSpots = validSpots + 1
                -- Check if this spot is completely empty (no bubbles to overwrite)
                local isEmpty = self:isTier2SpotEmpty(x, y)
                if isEmpty then
                    emptySpots = emptySpots + 1
                    local gridScreenX, gridScreenY = self:gridToScreen(x, y)
                    local distanceSquared = (projX - gridScreenX)^2 + (projY - gridScreenY)^2
                    
                    if distanceSquared < bestDistanceSquared then
                        bestDistanceSquared = distanceSquared
                        bestX, bestY = x, y
                    end
                end
            end
        end
    end
    
    -- If no empty spots found, fall back to any valid spot
    if not bestX then
        bestDistanceSquared = math.huge
        for x = 1, self.width do
            for y = 1, self.height do
                if self:canPlaceTier2At(x, y) then
                    local gridScreenX, gridScreenY = self:gridToScreen(x, y)
                    local distanceSquared = (projX - gridScreenX)^2 + (projY - gridScreenY)^2
                    
                    if distanceSquared < bestDistanceSquared then
                        bestDistanceSquared = distanceSquared
                        bestX, bestY = x, y
                    end
                end
            end
        end
    end
    
    return bestX, bestY
end

function Grid:isTier2SpotEmpty(x, y)
    local occupiedCells = self:getTier2OccupiedCells(x, y)
    
    for _, pos in ipairs(occupiedCells) do
        local existingBubble = self.cells[pos.x] and self.cells[pos.x][pos.y]
        if existingBubble then
            return false -- Found an existing bubble
        end
    end
    
    return true -- All cells are empty
end

function Grid:rebuildTier1Cache()
    -- Rebuild cache of all cells occupied by Tier 1 bubbles
    self.tier1OccupiedCache = {}
    
    for gx = 1, self.width do
        for gy = 1, self.height do
            local bubble = self.cells[gx] and self.cells[gx][gy]
            if bubble and bubble.isTier1 then
                local occupiedCells = self:getTier1OccupiedCells(gx, gy, bubble.tier1Config)
                for _, cell in ipairs(occupiedCells) do
                    local key = cell.x .. "," .. cell.y
                    self.tier1OccupiedCache[key] = true
                end
            end
        end
    end
    
    self.tier1CacheDirty = false
end

function Grid:markTier1CacheDirty()
    self.tier1CacheDirty = true
end

function Grid:isCellAvailable(x, y)
    -- Check if a cell is available (not occupied by any bubble or multi-cell footprint)
    if self.cells[x] and self.cells[x][y] then
        return false -- Cell has a bubble (including Tier 2 cells)
    end
    
    -- No need for additional Tier 1 cache check since Tier 1 bubbles now occupy all their cells
    return true
end

function Grid:checkBubbleCrossesGameBoundary(gridX, gridY)
    -- Check if bubble would be beyond column 20 (always game over)
    if gridX >= 21 then
        return true
    end
    
    -- For 20th column, check if the bubble position crosses the boundary line
    if gridX == 20 then
        local bubbleScreenX, _ = self:gridToScreen(gridX, gridY)
        
        -- If bubble center + radius crosses the boundary line, it's game over
        if bubbleScreenX + self.bubbleRadius > self.rightBoundaryX then
            return true
        end
    end
    
    return false
end

function Grid:checkMerges(x, y)
    local bubble = self.cells[x][y]
    if not bubble then return end
    
    -- Check for Tier 1 to Tier 2 merges first (touching, not 3+ matches)
    if bubble.isTier1 then
        self:checkTier1ToTier2Merge(x, y)
        return -- Tier 1 bubbles don't do traditional 3+ merges
    end
    
    local neighbors = self:getSameTypeNeighbors(x, y, bubble.type)
    
    if #neighbors >= 3 then
        -- Basic bubbles (1-5) merge into Tier 1 bubbles
        if bubble.type <= 5 then
            self:createTier1Bubble(neighbors, bubble.type)
        else
            -- Elite bubbles (6-10) merge normally  
            local leftmostX = math.huge
            local leftmostY = nil
            local lastShotRow = y
            
            for _, pos in ipairs(neighbors) do
                if pos.x < leftmostX or (pos.x == leftmostX and pos.y == lastShotRow) then
                    leftmostX = pos.x
                    leftmostY = pos.y
                end
            end
            
            -- Clear all merged cells
            for _, pos in ipairs(neighbors) do
                self.cells[pos.x][pos.y] = nil
            end
            
            -- Place super cell at leftmost position (elite bubbles merge to same type)
            self.cells[leftmostX][leftmostY] = {
                type = bubble.type,
                x = leftmostX,
                y = leftmostY
            }
        end
    end
end

function Grid:checkTier1ToTier2Merge(x, y)
    local bubble = self.cells[x][y]
    if not bubble or not bubble.isTier1 then return end
    
    -- Get the Tier 1 type (11-15) 
    local tier1Type = bubble.type
    
    -- Only check for merges among actually distinct Tier 1 bubbles
    -- Find all other Tier 1 bubbles of the same type in the grid
    for gx = 1, self.width do
        for gy = 1, self.height do
            if (gx ~= x or gy ~= y) then  -- Don't compare with self
                local otherBubble = self.cells[gx] and self.cells[gx][gy]
                -- Only consider OTHER Tier 1 bubbles at their ANCHOR positions to avoid self-merging
                if otherBubble and otherBubble.isTier1 and otherBubble.type == tier1Type and otherBubble.tier1Anchor then
                    print("Found matching Tier 1 type " .. tier1Type .. " at (" .. gx .. "," .. gy .. ") checking if touching (" .. x .. "," .. y .. ")")
                    -- Check if these two distinct Tier 1 bubbles are touching
                    if self:areTier1BubblesTouching(x, y, bubble.tier1Config, gx, gy, otherBubble.tier1Config) then
                        print("Creating Tier 2 from two " .. tier1Type .. " Tier 1 bubbles at (" .. x .. "," .. y .. ") and (" .. gx .. "," .. gy .. ")")
                        self:createTier2Bubble(x, y, gx, gy, tier1Type)
                        return
                    else
                        print("Not touching - no merge")
                    end
                end
            end
        end
    end
end

function Grid:areTier1BubblesTouching(x1, y1, config1, x2, y2, config2)
    -- Get the occupied cells for both Tier 1 bubbles
    local cells1 = self:getTier1OccupiedCells(x1, y1, config1)
    local cells2 = self:getTier1OccupiedCells(x2, y2, config2)
    
    -- Check if any cell from bubble 1 is adjacent to any cell from bubble 2
    for _, cell1 in ipairs(cells1) do
        for _, cell2 in ipairs(cells2) do
            local neighbors = self:getDirectNeighbors(cell1.x, cell1.y)
            for _, neighbor in ipairs(neighbors) do
                if neighbor.x == cell2.x and neighbor.y == cell2.y then
                    return true
                end
            end
        end
    end
    
    return false
end

function Grid:createTier2Bubble(tier1X1, tier1Y1, tier1X2, tier1Y2, tier1Type)
    -- Clear both Tier 1 bubbles FIRST to free up space
    self:clearTier1Bubble(tier1X1, tier1Y1)
    self:clearTier1Bubble(tier1X2, tier1Y2)
    
    -- Rebuild cache after clearing
    self:markTier1CacheDirty()
    
    -- Find a valid placement position AFTER clearing the Tier 1 bubbles
    local centerX, centerY = self:findTier2PlacementPosition(tier1X1, tier1Y1, tier1X2, tier1Y2)
    
    if centerX and centerY then
        -- Aggressively clear any basic bubbles in the Tier 2 footprint
        local occupiedCells = self:getTier2OccupiedCells(centerX, centerY)
        for _, cell in ipairs(occupiedCells) do
            local existingBubble = self.cells[cell.x] and self.cells[cell.x][cell.y]
            if existingBubble and existingBubble.type <= 5 then
                self.cells[cell.x][cell.y] = nil
            end
        end
        
        -- Place Tier 2 bubble in ALL cells of the diamond pattern
        for _, cell in ipairs(occupiedCells) do
            self.cells[cell.x][cell.y] = {
                type = 16, -- Tier 2 unified type
                x = centerX,  -- Store original center position
                y = centerY,
                isTier2 = true,
                tier2Center = (cell.x == centerX and cell.y == centerY) -- Mark the center cell
            }
        end
        
        print("Created Tier 2 bubble at (" .. centerX .. "," .. centerY .. ")")
    else
        -- This should be extremely rare with the expanded search
        print("ERROR: Could not find ANY valid placement for Tier 2 bubble")
    end
end

function Grid:findTier2PlacementPosition(tier1X1, tier1Y1, tier1X2, tier1Y2)
    -- Start with preferred positions, then expand search systematically
    local centerX = math.floor((tier1X1 + tier1X2) / 2)
    local centerY = math.floor((tier1Y1 + tier1Y2) / 2)
    
    -- Try preferred positions first
    local preferredAttempts = {
        {centerX, centerY},
        {math.min(tier1X1, tier1X2), (tier1X1 < tier1X2) and tier1Y1 or tier1Y2},
        {math.max(tier1X1, tier1X2), (tier1X1 > tier1X2) and tier1Y1 or tier1Y2},
        {tier1X1, tier1Y1},
        {tier1X2, tier1Y2}
    }
    
    for _, pos in ipairs(preferredAttempts) do
        local testX, testY = pos[1], pos[2]
        if testX >= 1 and testX <= self.width and testY >= 1 and testY <= self.height then
            if self:canPlaceTier2At(testX, testY) then
                return testX, testY
            end
        end
    end
    
    -- If preferred positions fail, do a systematic search in expanding rings
    for radius = 1, 5 do  -- Search in 5x5 area around merge zone
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then  -- Only check border of current radius
                    local testX, testY = centerX + dx, centerY + dy
                    if testX >= 1 and testX <= self.width and testY >= 1 and testY <= self.height then
                        if self:canPlaceTier2At(testX, testY) then
                            return testX, testY
                        end
                    end
                end
            end
        end
    end
    
    -- Last resort: try anywhere on the grid (should rarely be needed)
    for y = 1, self.height do
        for x = 1, self.width do
            if self:canPlaceTier2At(x, y) then
                return x, y
            end
        end
    end
    
    return nil, nil -- No valid position found (very rare)
end

function Grid:canPlaceTier2At(centerX, centerY)
    -- Check if a Tier 2 bubble can be placed at the given center position
    -- Tier 2 occupies a diamond pattern of 7 cells
    local occupiedCells = self:getTier2OccupiedCells(centerX, centerY)
    
    for _, cell in ipairs(occupiedCells) do
        if cell.x < 1 or cell.x > self.width or cell.y < 1 or cell.y > self.height then
            return false -- Out of bounds
        end
        
        -- Check if there's already a bubble at this position
        local existingBubble = self.cells[cell.x] and self.cells[cell.x][cell.y]
        if existingBubble then
            -- Allow clearing basic bubbles (1-5) but not elite/Tier 1/Tier 2
            if existingBubble.type > 5 or existingBubble.isTier1 or existingBubble.isTier2 then
                return false -- Cannot overwrite elite/Tier 1/Tier 2 bubbles
            end
        end
    end
    
    return true
end

function Grid:clearTier1Bubble(x, y)
    -- Clear a Tier 1 bubble and all its occupied cells
    local bubble = self.cells[x] and self.cells[x][y]
    if bubble and bubble.isTier1 then
        local occupiedCells = self:getTier1OccupiedCells(x, y, bubble.tier1Config)
        for _, cell in ipairs(occupiedCells) do
            if self.cells[cell.x] and self.cells[cell.x][cell.y] then
                self.cells[cell.x][cell.y] = nil
            end
        end
    else
        -- Fallback: just clear the main cell
        self.cells[x][y] = nil
    end
end

function Grid:createTier1Bubble(neighbors, basicType)
    -- Determine the best configuration BEFORE clearing bubbles
    local config = self:determineTier1Configuration(neighbors)
    
    -- Always clear the matched bubbles first (even if they're not under the final Tier 1)
    for _, pos in ipairs(neighbors) do
        if self.cells[pos.x] and self.cells[pos.x][pos.y] then
            self.cells[pos.x][pos.y] = nil
        end
    end
    
    -- Find the appropriate reference position based on triangle orientation
    local startX, startY
    
    if config == "UP" then
        -- For up-facing triangles, use the top bubble as reference for point positioning
        local minY = math.huge
        
        for _, pos in ipairs(neighbors) do
            if pos.y < minY then
                minY = pos.y
            end
        end
        
        -- Find the top bubble (there should be only one)
        for _, pos in ipairs(neighbors) do
            if pos.y == minY then
                startX = pos.x
                startY = pos.y  -- Place the Tier 1 at the top bubble's position
                break
            end
        end
    else
        -- For down-facing triangles, use leftmost position as before
        startX = math.huge
        for _, pos in ipairs(neighbors) do
            if pos.x < startX then
                startX = pos.x
                startY = pos.y
            end
        end
    end
    
    -- Get the Tier 1 bubble type from the mapping
    local tier1Type = Constants.BASIC_TO_TIER1[basicType]
    
    -- Find a legal placement position by nudging if necessary
    local finalX, finalY = self:findLegalTier1Position(startX, startY, config, tier1Type)
    
    if finalX and finalY then
        -- Clear all cells that will be occupied by the Tier 1 (only if they're lower quality)
        local occupiedCells = self:getTier1OccupiedCells(finalX, finalY, config)
        for _, pos in ipairs(occupiedCells) do
            if pos.x >= 1 and pos.x <= self.width and pos.y >= 1 and pos.y <= self.height then
                if self.cells[pos.x] and self.cells[pos.x][pos.y] and self:canOverwrite(self.cells[pos.x][pos.y], tier1Type) then
                    self.cells[pos.x][pos.y] = nil
                end
            end
        end
        
        -- Place the Tier 1 bubble in ALL cells of its footprint
        for _, cell in ipairs(occupiedCells) do
            self.cells[cell.x][cell.y] = {
                type = tier1Type,
                x = finalX,  -- Store original anchor position
                y = finalY,
                tier1Config = config,
                isTier1 = true,
                tier1Anchor = (cell.x == finalX and cell.y == finalY) -- Mark the anchor cell
            }
        end
        
        -- Mark cache as dirty since we added a Tier 1 bubble
        self:markTier1CacheDirty()
        
    else
    end
end

function Grid:findLegalTier1Position(startX, startY, config, tier1Type)
    -- Try positions in expanding search pattern: original, then nudge right, left, down, up, etc.
    local attempts = {
        {0, 0},   -- Original position
        {1, 0},   -- Right
        {-1, 0},  -- Left
        {0, 1},   -- Down
        {0, -1},  -- Up
        {1, 1},   -- Down-right
        {-1, 1},  -- Down-left
        {1, -1},  -- Up-right
        {-1, -1}, -- Up-left
        {2, 0},   -- Further right
        {-2, 0}   -- Further left
    }
    
    for _, offset in ipairs(attempts) do
        local testX = startX + offset[1]
        local testY = startY + offset[2]
        
        if testX >= 1 and testX <= self.width and testY >= 1 and testY <= self.height then
            if self:canPlaceTier1At(testX, testY, config, tier1Type) then
                return testX, testY
            end
        end
    end
    
    return nil, nil -- No legal position found
end

function Grid:canPlaceTier1At(x, y, config, tier1Type)
    local occupiedCells = self:getTier1OccupiedCells(x, y, config)
    
    -- Check if all required cells can be legally occupied
    for _, pos in ipairs(occupiedCells) do
        if pos.x < 1 or pos.x > self.width or pos.y < 1 or pos.y > self.height then
            return false -- Out of bounds
        end
        
        -- First check if there's a direct bubble in this cell
        local existingBubble = self.cells[pos.x] and self.cells[pos.x][pos.y]
        if existingBubble and not self:canOverwrite(existingBubble, tier1Type) then
            return false -- Can't overwrite this bubble
        end
        
        -- Also check if this cell is part of another Tier 1's footprint
        if not self:isCellAvailableForTier1Placement(pos.x, pos.y, tier1Type) then
            return false -- Cell is occupied by another Tier 1's footprint
        end
    end
    
    return true
end

function Grid:canPlaceTier2At(x, y)
    local occupiedCells = self:getTier2OccupiedCells(x, y)
    
    
    -- Check if all required cells can be legally occupied
    for i, pos in ipairs(occupiedCells) do
        if pos.x < 1 or pos.x > self.width or pos.y < 1 or pos.y > self.height then
            return false -- Out of bounds
        end
        
        -- Check if there's an existing bubble that can't be overwritten
        local existingBubble = self.cells[pos.x] and self.cells[pos.x][pos.y]
        if existingBubble and not self:canOverwriteForTier2(existingBubble) then
            return false -- Can't overwrite this bubble
        end
        
        -- Check for Tier 1 footprint conflicts
        if not self:isCellAvailableForTier1Placement(pos.x, pos.y, 16) then
            return false -- Cell is occupied by Tier 1 footprint
        end
    end
    
    return true
end

function Grid:getTier2OccupiedCells(x, y)
    local cells = {}
    
    for _, offset in ipairs(Constants.TIER2_CONFIG) do
        table.insert(cells, {
            x = x + offset[1],
            y = y + offset[2]
        })
    end
    
    return cells
end

function Grid:canOverwriteForTier2(existingBubble)
    -- Tier 2 can overwrite basic (1-5) and elite (6-10) bubbles, but not Tier 1 (11-15) or other Tier 2 (16)
    if existingBubble.type <= 10 then
        return true -- Can overwrite basic and elite bubbles
    else
        return false -- Cannot overwrite Tier 1 or higher tiers
    end
end

function Grid:isCellAvailableForTier1Placement(x, y, newTier1Type)
    -- Check if this cell conflicts with any existing Tier 1 bubble's footprint using cache
    if self.tier1CacheDirty then
        self:rebuildTier1Cache()
    end
    
    local key = x .. "," .. y
    return not self.tier1OccupiedCache[key]
end

function Grid:canOverwrite(existingBubble, newTier1Type)
    -- Tier 1 can overwrite basic bubbles (types 1-5) but not elite (6-10) or other Tier 1 (11-15)
    if existingBubble.type <= 5 then
        return true -- Can overwrite basic bubbles
    else
        return false -- Cannot overwrite elite, Tier 1, or higher tiers
    end
end

function Grid:determineTier1Configuration(neighbors)
    -- Analyze the actual shape pattern to determine UP or DOWN configuration
    -- UP: up-facing triangles (sprites 1-5, point on top)
    -- DOWN: down-facing triangles (sprites 6-10, point on bottom)
    
    if #neighbors ~= 3 then
        return "UP" -- Default to up-facing for safety
    end
    
    -- Sort neighbors by Y coordinate (top to bottom on screen)
    table.sort(neighbors, function(a, b) return a.y < b.y end)
    
    -- Check if we have a clear 2+1 or 1+2 pattern
    local firstY = neighbors[1].y
    local secondY = neighbors[2].y  
    local thirdY = neighbors[3].y
    
    
    -- Case 1: All three bubbles are on the same Y level (horizontal line)
    if firstY == secondY and secondY == thirdY then
        print("Detected horizontal pattern - defaulting to DOWN-facing")
        return "DOWN" -- Default to down-facing for horizontal patterns
    
    -- Case 2: Two bubbles on top row, one below (down-facing pattern)
    elseif firstY == secondY and thirdY > secondY then
        print("Detected down-facing pattern: 2 on top, 1 below")
        return "DOWN" -- Use down-facing sprite (sprites 6-10)
    
    -- Case 3: One bubble on top, two below (up-facing pattern)  
    elseif firstY < secondY and secondY == thirdY then
        print("Detected up-facing pattern: 1 on top, 2 below")
        return "UP" -- Use up-facing sprite (sprites 1-5)
    
    -- Case 4: Diagonal pattern (1-1-1 on different rows) - analyze visually
    else
        print("Detected diagonal pattern: bubbles on 3 different rows")
        -- For diagonal patterns, determine orientation by relative positions
        -- Look at the middle bubble and see if it's closer to a horizontal line with first or last
        local topBubble = neighbors[1]
        local midBubble = neighbors[2]  
        local botBubble = neighbors[3]
        
        -- Check if middle bubble forms better horizontal line with top or bottom
        local topMidDistance = math.abs(topBubble.x - midBubble.x)
        local midBotDistance = math.abs(midBubble.x - botBubble.x)
        
        if topMidDistance <= midBotDistance then
            -- Middle aligns better with top, so bottom is the point -> down-facing
            print("Diagonal: better top alignment -> DOWN-facing")
            return "DOWN"
        else
            -- Middle aligns better with bottom, so top is the point -> up-facing  
            print("Diagonal: better bottom alignment -> UP-facing")
            return "UP"
        end
    end
end

function Grid:getTier1OccupiedCells(anchorX, anchorY, config)
    -- Return the cells that would be occupied by a Tier 1 bubble
    -- anchorX, anchorY is the position where the bubble was placed (the "anchor" cell)
    local cells = {}
    
    if config == "DOWN" then
        -- DOWN-facing: horizontal line on top, point below (centered)
        -- Anchor is at the point (bottom), so top row is at anchorY - 1
        -- Top row: 2 cells side by side
        table.insert(cells, {x = anchorX, y = anchorY - 1})
        table.insert(cells, {x = anchorX + 1, y = anchorY - 1})
        -- Bottom row (point): the anchor cell itself
        table.insert(cells, {x = anchorX, y = anchorY})
    else -- UP configuration
        -- UP-facing: single point on top, horizontal line below
        -- Anchor is at the point (top), so base row is at anchorY + 1
        -- Top row (point): the anchor cell itself
        table.insert(cells, {x = anchorX, y = anchorY})
        -- Bottom row: 2 cells side by side below the point
        table.insert(cells, {x = anchorX, y = anchorY + 1})
        table.insert(cells, {x = anchorX + 1, y = anchorY + 1})
    end
    
    return cells
end

function Grid:getTier2OccupiedCells(centerX, centerY)
    -- Return the 7 cells occupied by a Tier 2 bubble in 2-3-2 diamond pattern
    local cells = {}
    
    -- Top row: 2 cells
    table.insert(cells, {x = centerX - 1, y = centerY - 1})
    table.insert(cells, {x = centerX, y = centerY - 1})
    
    -- Middle row: 3 cells (including center)
    table.insert(cells, {x = centerX - 1, y = centerY})
    table.insert(cells, {x = centerX, y = centerY})
    table.insert(cells, {x = centerX + 1, y = centerY})
    
    -- Bottom row: 2 cells  
    table.insert(cells, {x = centerX - 1, y = centerY + 1})
    table.insert(cells, {x = centerX, y = centerY + 1})
    
    return cells
end

-- Pre-define direction tables to avoid creating new tables each time
Grid.ODD_ROW_DIRECTIONS = {{0,1}, {0,-1}, {1,0}, {-1,0}, {-1,-1}, {-1,1}}
Grid.EVEN_ROW_DIRECTIONS = {{0,1}, {0,-1}, {1,0}, {-1,0}, {1,-1}, {1,1}}

function Grid:getSameTypeNeighbors(x, y, bubbleType)
    local neighbors = {{x = x, y = y}}
    local checked = {}
    local toCheck = {{x = x, y = y}}
    
    while #toCheck > 0 do
        local current = table.remove(toCheck, 1)
        local key = current.x .. "," .. current.y
        if not checked[key] then
            checked[key] = true
            
            -- Use pre-defined direction tables to avoid creating new tables
            local directions = (current.y % 2 == 1) and Grid.ODD_ROW_DIRECTIONS or Grid.EVEN_ROW_DIRECTIONS
            
            for _, dir in ipairs(directions) do
                local nx, ny = current.x + dir[1], current.y + dir[2]
                local nkey = nx .. "," .. ny
                if nx >= 1 and nx <= self.width and ny >= 1 and ny <= self.height 
                   and not checked[nkey] and self.cells[nx] and self.cells[nx][ny] 
                   and self.cells[nx][ny].type == bubbleType then
                    table.insert(toCheck, {x = nx, y = ny})
                    table.insert(neighbors, {x = nx, y = ny})
                end
            end
        end
    end
    
    return neighbors
end

function Grid:checkGameOver()
    -- Game over only happens when gameOver flag is set (bubbles spill past right boundary)
    -- No game over for bottom placement - bubbles can fill any row vertically
    if self.gameOver then
        return true
    end
    
    return false
end

function Grid:draw(showNewBubbles, transitionState, shotsRemaining)
    if showNewBubbles == nil then showNewBubbles = true end -- Default to showing all bubbles
    if transitionState == nil then transitionState = "playing" end -- Default to normal play
    if shotsRemaining == nil then shotsRemaining = self.shotsRemaining end -- Use grid's shots if not provided
    local gfx = playdate.graphics
    
    -- Draw boundary lines - left and right edges extend full screen height
    self:drawDashedLine(gfx, self.rightBoundaryX, 0, self.rightBoundaryX, 240)  -- Right boundary (full height)
    gfx.drawLine(self.leftBoundaryX, 0, self.leftBoundaryX, 240)  -- Left boundary (full height)
    
    -- Draw bubbles in hex grid
    local drawnTier1 = {} -- Track which Tier 1 bubbles we've already drawn
    
    for x = 1, self.width do
        for y = 1, self.height do
            local bubble = self.cells[x][y]
            if bubble then
                -- Draw all bubbles during normal gameplay
                -- Only filter by showNewBubbles during level transitions
                if bubble.isPreExisting or showNewBubbles or transitionState == "playing" then
                    if bubble.isTier1 then
                        -- Only draw Tier 1 from the anchor cell
                        if bubble.tier1Anchor then
                            self:drawTier1Bubble(x, y, bubble.type)
                        end
                    elseif bubble.isTier2 then
                        -- Only draw Tier 2 from the center cell
                        if bubble.tier2Center then
                            self:drawTier2Bubble(x, y, bubble.type)
                        end
                    else
                        -- Draw regular bubble (pass screen coordinates)
                        local drawX, drawY = self:gridToScreen(x, y)
                        self:drawBubbleByType(drawX, drawY, bubble.type)
                    end
                end
            end
        end
    end
    
    -- Draw projectile
    if self.projectile then
        if self.projectile.isTier1 then
            self:drawTier1Projectile(self.projectile.x, self.projectile.y, self.projectile.type, self.projectile.tier1Config)
        elseif self.projectile.isTier2 or self.projectile.type == 16 then
            self:drawTier2Projectile(self.projectile.x, self.projectile.y, self.projectile.type)
        else
            self:drawBubbleByType(self.projectile.x, self.projectile.y, self.projectile.type)
        end
    end
    
    local shooterX, shooterY = self:getShooterPosition()
    local previewX, previewY = self:getPreviewPosition()
    
    -- Draw ready-to-fire ball at shooter position
    if not self.projectile and shotsRemaining > 0 then
        if self.nextBubbleType == 16 or self.nextBubbleIsTier2 then
            self:drawTier2Projectile(shooterX, shooterY, self.nextBubbleType)
        elseif self.nextBubbleIsTier1 and self.nextBubbleType >= 11 and self.nextBubbleType <= 15 then
            self:drawTier1Projectile(shooterX, shooterY, self.nextBubbleType, self.nextBubbleTier1Config)
        else
            self:drawBubbleByType(shooterX, shooterY, self.nextBubbleType)
        end
    end
    
    -- Draw preview ball (next bubble to be shot)
    if not self.projectile and shotsRemaining > 0 then
        if self.previewBubbleType == 16 or self.previewBubbleIsTier2 then
            self:drawTier2Projectile(previewX, previewY, self.previewBubbleType)
        elseif self.previewBubbleIsTier1 and self.previewBubbleType >= 11 and self.previewBubbleType <= 15 then
            self:drawTier1Projectile(previewX, previewY, self.previewBubbleType, self.previewBubbleTier1Config)
        else
            self:drawBubbleByType(previewX, previewY, self.previewBubbleType)
        end
    end
    
    -- Draw shots remaining with proper edge-to-edge spacing
    local currentFont = gfx.getFont()
    local textHeight = currentFont:getHeight()
    local gap = 8  -- Visual gap between ball edge and text edge
    local shotCounterY
    if self.uiFlipped then
        -- Flipped: text above ball, measure from ball top edge to text bottom edge
        shotCounterY = previewY - self.bubbleRadius - gap - textHeight
    else
        -- Normal: text below ball, measure from ball bottom edge to text top edge  
        shotCounterY = previewY + self.bubbleRadius + gap
    end
    gfx.drawTextAligned(tostring(shotsRemaining), previewX, shotCounterY, kTextAlignment.center)
    
    -- Draw aim line from shooter position (only if not fired, in normal play mode, and shots remaining)
    if not self.projectile and transitionState == "playing" and shotsRemaining > 0 then
        -- Start line from edge of circle and extend 60px
        local startX = shooterX + math.cos(math.rad(self.aimAngle)) * self.bubbleRadius
        local startY = shooterY + math.sin(math.rad(self.aimAngle)) * self.bubbleRadius
        local endX = shooterX + math.cos(math.rad(self.aimAngle)) * (self.bubbleRadius + 60)
        local endY = shooterY + math.sin(math.rad(self.aimAngle)) * (self.bubbleRadius + 60)
        
        gfx.drawLine(startX, startY, endX, endY)
    end
end

function Grid:drawDashedLine(gfx, x1, y1, x2, y2)
    local length = math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
    local dashLength = 5
    local dx = (x2 - x1) / length
    local dy = (y2 - y1) / length
    
    local currentX, currentY = x1, y1
    local distance = 0
    local drawDash = true
    
    while distance < length do
        local nextDistance = math.min(distance + dashLength, length)
        local nextX = x1 + dx * nextDistance
        local nextY = y1 + dy * nextDistance
        
        if drawDash then
            gfx.drawLine(currentX, currentY, nextX, nextY)
        end
        
        currentX, currentY = nextX, nextY
        distance = nextDistance
        drawDash = not drawDash
    end
end

