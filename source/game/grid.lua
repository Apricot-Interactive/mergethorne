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
        previewBubbleType = math.random(1, 5),
        bubbleSprites = {},
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
    instance:updateBoundaryCache()
    return instance
end

function Grid:loadBubbleSprites()
    -- Load the bubble sprite sheet
    local spriteSheet = playdate.graphics.image.new("assets/sprites/bubbles.png")
    
    if spriteSheet then
        local sheetWidth, sheetHeight = spriteSheet:getSize()
        
        -- Extract sprites from the sheet (handle both 5 and 10 sprite sheets)
        local numSprites = math.floor(sheetWidth / 30)
        for i = 1, numSprites do
            local x = (i - 1) * 30  -- Each sprite is 30 pixels wide
            
            -- Create a new 30x30 image and draw the specific region
            local sprite = playdate.graphics.image.new(30, 30)
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
            local sprite = playdate.graphics.image.new(30, 30)
            playdate.graphics.pushContext(sprite)
            playdate.graphics.setColor(playdate.graphics.kColorBlack)
            playdate.graphics.fillCircleAtPoint(15, 15, 14)  -- Fill circle in center
            playdate.graphics.popContext()
            self.bubbleSprites[i] = sprite
        end
    end
end

function Grid:drawBubbleByType(x, y, bubbleType)
    if bubbleType and bubbleType >= 1 and bubbleType <= 10 and self.bubbleSprites[bubbleType] then
        -- Draw sprite centered at x, y
        self.bubbleSprites[bubbleType]:drawCentered(x, y)
    else
        -- Fallback to circle if sprite not available - this means sprite loading failed
        playdate.graphics.drawCircleAtPoint(x, y, self.bubbleRadius)
    end
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
    local _, bottomRowY = self:gridToScreen(1, 8)
    local col9EvenRowX, _ = self:gridToScreen(9, 2)
    
    self.leftBoundaryX = leftmostX - self.bubbleRadius - 2
    self.topBoundaryY = topmostY - self.bubbleRadius - 2
    self.bottomBoundaryY = bottomRowY + self.bubbleRadius + 2
    self.rightBoundaryX = col9EvenRowX + self.bubbleRadius + 2
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
    
    -- Center the grid vertically and add left margin for removed column
    local gridHeight = (self.height - 1) * self.hexSpacingY
    local startX = 50  -- Increased left margin for dead space
    local startY = (240 - gridHeight) / 2  -- Center vertically
    
    return startX + screenX + self.bubbleRadius, startY + screenY + self.bubbleRadius
end

-- Convert screen position to grid coordinates (hex layout)
function Grid:screenToGrid(screenX, screenY)
    local gridHeight = (self.height - 1) * self.hexSpacingY
    local startX = 50  -- Match the margin from gridToScreen
    local startY = (240 - gridHeight) / 2  -- Match vertical centering
    
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
    
    -- Define placement areas
    local placementCells = {}
    
    -- Leftmost 3 columns (all rows 2-7 to avoid game over)
    for y = 2, 7 do
        for x = 1, 3 do
            table.insert(placementCells, {x = x, y = y, fillChance = x == 3 and 0.5 or 1.0})
        end
    end
    
    -- Row 1 and row 8, positions 1-6
    for x = 1, 6 do
        table.insert(placementCells, {x = x, y = 1, fillChance = 1.0})
        table.insert(placementCells, {x = x, y = 8, fillChance = 1.0})
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
    
    print("=== Setting up level with pre-existing merged balls ===")
    
    -- First, place the surviving merged balls
    for _, ballData in ipairs(survivingMergedBalls) do
        if ballData.x >= 1 and ballData.x <= self.width and ballData.y >= 1 and ballData.y <= self.height then
            self.cells[ballData.x][ballData.y] = {
                type = ballData.type,
                x = ballData.x,
                y = ballData.y,
                isPreExisting = true -- Mark as pre-existing merged ball
            }
            print("Placed surviving merged ball: Type " .. ballData.type .. " at grid (" .. ballData.x .. "," .. ballData.y .. ")")
        end
    end
    
    -- Then setup new basic balls, avoiding positions where merged balls already exist
    local placementCells = {}
    
    -- Leftmost 3 columns (all rows 2-7 to avoid game over)
    for y = 2, 7 do
        for x = 1, 3 do
            if not self.cells[x][y] then -- Only add if position is empty
                table.insert(placementCells, {x = x, y = y, fillChance = x == 3 and 0.5 or 1.0})
            end
        end
    end
    
    -- Row 1 and row 8, positions 1-6
    for x = 1, 6 do
        if not self.cells[x][1] then -- Only add if position is empty
            table.insert(placementCells, {x = x, y = 1, fillChance = 1.0})
        end
        if not self.cells[x][8] then -- Only add if position is empty
            table.insert(placementCells, {x = x, y = 8, fillChance = 1.0})
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
            end
        end
    end
    
    print("=== Level setup complete with " .. #survivingMergedBalls .. " pre-existing merged balls ===")
end

function Grid:findSafeBubbleType(x, y)
    -- Try bubble types in random order to add variety
    local types = {1, 2, 3, 4, 5}
    for i = #types, 2, -1 do
        local j = math.random(i)
        types[i], types[j] = types[j], types[i]
    end
    
    local bestType = nil
    local bestScore = -1
    
    for _, bubbleType in ipairs(types) do
        -- Test if this type would create a 3-match
        self.cells[x][y] = {type = bubbleType, x = x, y = y}
        local neighbors = self:getSameTypeNeighbors(x, y, bubbleType)
        local wouldCreate3Match = #neighbors >= 3
        self.cells[x][y] = nil  -- Remove test bubble
        
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
    if self.projectile or self.shotsRemaining <= 0 then
        return false
    end
    
    local shooterX, shooterY = self:getShooterPosition()
    
    self.projectile = {
        x = shooterX,
        y = shooterY,
        vx = math.cos(math.rad(self.aimAngle)) * (Constants and Constants.BUBBLE_SPEED or 8),
        vy = math.sin(math.rad(self.aimAngle)) * (Constants and Constants.BUBBLE_SPEED or 8),
        type = self.nextBubbleType
    }
    
    
    -- Start preview ball animation
    self.previewAnimating = true
    
    -- Generate next bubble (don't decrement shots until projectile lands)
    self.nextBubbleType = self.previewBubbleType
    self.previewBubbleType = math.random(1, 5)
    
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
        
        -- Remove projectile if it goes off screen (but not right boundary check since shooter is outside play area)
        if self.projectile.x <= 0 or self.projectile.y <= 0 or self.projectile.y >= 240 then
            self.projectile = nil
            self.shotsRemaining = self.shotsRemaining - 1
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
        self.shotsRemaining = self.shotsRemaining - 1
        return
    end
    
    -- Check collision with existing bubbles using distance
    for x = 1, self.width do
        for y = 1, self.height do
            local bubble = self.cells[x][y]
            if bubble then
                local bubbleX, bubbleY = self:gridToScreen(x, y)
                local distance = math.sqrt((self.projectile.x - bubbleX)^2 + (self.projectile.y - bubbleY)^2)
                
                -- If projectile is close enough to an existing bubble (reduced hitbox by 5px for easier navigation)
                if distance <= (self.bubbleRadius * 2) - 5 then
                    -- Find the best empty spot to place the new bubble
                    local bestX, bestY = self:findClosestEmptySpot(self.projectile.x, self.projectile.y)
                    
                    if bestX and bestY then
                        -- Check if this placement would cross the game boundary
                        if self:checkBubbleCrossesGameBoundary(bestX, bestY) then
                            self.gameOver = true
                            self.projectile = nil
                            return
                        end
                        
                        self.cells[bestX][bestY] = {
                            type = self.projectile.type,
                            x = bestX,
                            y = bestY
                        }
                        self.projectile = nil
                        self.shotsRemaining = self.shotsRemaining - 1
                        self:checkMerges(bestX, bestY)
                        return
                    end
                end
            end
        end
    end
    
    -- Top wall attachment disabled - now handled by bouncing in update()
end

function Grid:findClosestEmptySpot(projX, projY)
    local bestX, bestY = nil, nil
    local bestDistance = math.huge
    
    -- Check all grid positions for the closest empty spot
    for x = 1, self.width do
        for y = 1, self.height do
            if self.cells[x][y] == nil then
                local gridScreenX, gridScreenY = self:gridToScreen(x, y)
                local distance = math.sqrt((projX - gridScreenX)^2 + (projY - gridScreenY)^2)
                
                if distance < bestDistance then
                    bestDistance = distance
                    bestX, bestY = x, y
                end
            end
        end
    end
    
    return bestX, bestY
end

function Grid:checkBubbleCrossesGameBoundary(gridX, gridY)
    -- Check if bubble would be in 10th column (always game over)
    if gridX >= 10 then
        return true
    end
    
    -- For 9th column, check if the bubble position crosses the boundary line
    if gridX == 9 then
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
    
    local neighbors = self:getSameTypeNeighbors(x, y, bubble.type)
    
    if #neighbors >= 3 then
        -- Find leftmost position for super cell (with tie-breaker for last shot row)
        local leftmostX = math.huge
        local leftmostY = nil
        local lastShotRow = y  -- The row where the last shot landed
        
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
        
        -- Place super cell at leftmost position (basic bubbles only)
        if bubble.type <= 5 then
            self.cells[leftmostX][leftmostY] = {
                type = bubble.type + 5,
                x = leftmostX,
                y = leftmostY
            }
        end
    end
end

function Grid:getSameTypeNeighbors(x, y, bubbleType)
    local neighbors = {{x = x, y = y}}
    local checked = {}
    local toCheck = {{x = x, y = y}}
    
    while #toCheck > 0 do
        local current = table.remove(toCheck, 1)
        local key = current.x .. "," .. current.y
        if not checked[key] then
            checked[key] = true
            
            -- Hex grid neighbors: 6 directions for staggered hex grid
            local directions
            if current.y % 2 == 1 then  -- Odd rows (not staggered)
                -- For odd rows: diagonal neighbors are to the left
                directions = {{0,1}, {0,-1}, {1,0}, {-1,0}, {-1,-1}, {-1,1}}
            else  -- Even rows (staggered right)
                -- For even rows: diagonal neighbors are to the right  
                directions = {{0,1}, {0,-1}, {1,0}, {-1,0}, {1,-1}, {1,1}}
            end
            for _, dir in ipairs(directions) do
                local nx, ny = current.x + dir[1], current.y + dir[2]
                local nkey = nx .. "," .. ny
                if nx >= 1 and nx <= self.width and ny >= 1 and ny <= self.height 
                   and not checked[nkey] and self.cells[nx][ny] 
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
    -- Check if any bubbles reached the bottom row
    for x = 1, self.width do
        if self.cells[x][self.height] then
            return true
        end
    end
    
    -- Check if gameOver flag was set (projectile went past boundary)
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
    for x = 1, self.width do
        for y = 1, self.height do
            local bubble = self.cells[x][y]
            if bubble then
                -- Only draw if it's a pre-existing bubble, or if we should show new bubbles
                if bubble.isPreExisting or showNewBubbles then
                    local drawX, drawY = self:gridToScreen(x, y)
                    self:drawBubbleByType(drawX, drawY, bubble.type)
                end
            end
        end
    end
    
    -- Draw projectile
    if self.projectile then
        self:drawBubbleByType(self.projectile.x, self.projectile.y, self.projectile.type)
    end
    
    local shooterX, shooterY = self:getShooterPosition()
    local previewX, previewY = self:getPreviewPosition()
    
    -- Draw ready-to-fire ball at shooter position
    if not self.projectile and self.shotsRemaining > 0 then
        self:drawBubbleByType(shooterX, shooterY, self.nextBubbleType)
    end
    
    -- Draw preview ball (next bubble to be shot)
    if not self.projectile and self.shotsRemaining > 0 then
        self:drawBubbleByType(previewX, previewY, self.previewBubbleType)
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

