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
        shooterY = Constants and Constants.SHOOTER_Y or 120,
        boundaryX = Constants and Constants.BOUNDARY_X or 300,
        aimAngle = 180,
        projectile = nil,
        gameOver = false,
        shotsRemaining = 10,
        nextBubbleType = math.random(1, 5),
        bubbleSprites = {}
    }
    setmetatable(instance, self)
    self.__index = self
    
    instance:initGrid()
    instance:loadBubbleSprites()
    return instance
end

function Grid:loadBubbleSprites()
    -- Load the bubble sprite sheet
    local spriteSheet = playdate.graphics.image.new("assets/sprites/bubbles.png")
    
    if spriteSheet then
        local sheetWidth, sheetHeight = spriteSheet:getSize()
        print("Sprite sheet loaded: " .. sheetWidth .. "x" .. sheetHeight)
        
        -- Extract sprites from the sheet (handle both 5 and 10 sprite sheets)
        local numSprites = math.floor(sheetWidth / 30)
        print("Detected " .. numSprites .. " sprites in sheet")
        for i = 1, numSprites do
            local x = (i - 1) * 30  -- Each sprite is 30 pixels wide
            print("Extracting sprite " .. i .. " from x=" .. x)
            
            -- Create a new 30x30 image and draw the specific region
            local sprite = playdate.graphics.image.new(30, 30)
            playdate.graphics.pushContext(sprite)
            -- Draw the sprite sheet at negative offset to show only the desired region
            spriteSheet:draw(-x, 0)
            playdate.graphics.popContext()
            
            local w, h = sprite:getSize()
            print("Successfully created sprite " .. i .. ": " .. w .. "x" .. h)
            self.bubbleSprites[i] = sprite
        end
    else
        print("Failed to load sprite sheet, using fallback sprites")
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
        print("Drawing fallback circle for bubbleType=" .. tostring(bubbleType) .. " (sprite not available)")
        playdate.graphics.drawCircleAtPoint(x, y, self.bubbleRadius)
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
    
    -- Only place circles in leftmost 4 columns, only in top 6 rows (safe from game over)
    for y = 1, 6 do  -- Only top 6 rows to avoid immediate game over
        for x = 1, 4 do  -- Only leftmost 4 columns (removed first column)
            if math.random() < 0.6 then  -- 60% chance for gaps
                self.cells[x][y] = {
                    type = math.random(1, 5),
                    x = x,
                    y = y
                }
            end
        end
    end
end

function Grid:shootBubble()
    print("DEBUG: shootBubble called - projectile exists:", self.projectile ~= nil, "shots remaining:", self.shotsRemaining)
    
    if self.projectile or self.shotsRemaining <= 0 then
        print("DEBUG: shootBubble blocked - projectile exists:", self.projectile ~= nil, "shots:", self.shotsRemaining)
        return false
    end
    
    -- Calculate dynamic shooter position (match the draw() method)
    local col9EvenRowX, _ = self:gridToScreen(9, 2)
    local actualBoundaryX = col9EvenRowX + self.bubbleRadius + 2
    local dynamicShooterX = actualBoundaryX + 25
    
    self.projectile = {
        x = dynamicShooterX,
        y = self.shooterY,
        vx = math.cos(math.rad(self.aimAngle)) * (Constants and Constants.BUBBLE_SPEED or 8),
        vy = math.sin(math.rad(self.aimAngle)) * (Constants and Constants.BUBBLE_SPEED or 8),
        type = self.nextBubbleType
    }
    
    print("DEBUG: Projectile created at", dynamicShooterX, self.shooterY, "angle:", self.aimAngle, "velocity:", self.projectile.vx, self.projectile.vy)
    
    -- Generate next bubble (don't decrement shots until projectile lands)
    self.nextBubbleType = math.random(1, 5)
    
    return true
end

function Grid:update()
    if playdate.buttonIsPressed(playdate.kButtonUp) then
        self.aimAngle = math.max(135, self.aimAngle - 2)
    elseif playdate.buttonIsPressed(playdate.kButtonDown) then
        self.aimAngle = math.min(225, self.aimAngle + 2)
    end
    
    if self.projectile then
        local oldX, oldY = self.projectile.x, self.projectile.y
        self.projectile.x += self.projectile.vx
        self.projectile.y += self.projectile.vy
        print("DEBUG: Projectile moved from", oldX, oldY, "to", self.projectile.x, self.projectile.y)
        
        -- Calculate grid boundaries for bouncing (same as draw() method)
        local leftmostX, _ = self:gridToScreen(1, 1)
        local _, topmostY = self:gridToScreen(1, 1)
        local _, bottomRowY = self:gridToScreen(1, 8)
        local col9EvenRowX, _ = self:gridToScreen(9, 2)
        
        local leftBoundaryX = leftmostX - self.bubbleRadius - 2
        local topBoundaryY = topmostY - self.bubbleRadius - 2
        local bottomBoundaryY = bottomRowY + self.bubbleRadius + 2
        local rightBoundaryX = col9EvenRowX + self.bubbleRadius + 2
        
        print("DEBUG: Boundaries - Left:", leftBoundaryX, "Top:", topBoundaryY, "Bottom:", bottomBoundaryY, "Right:", rightBoundaryX)
        print("DEBUG: Projectile edge check - Right edge at:", self.projectile.x + self.bubbleRadius)
        
        -- Handle bouncing off grid boundaries (circumference-based)
        -- Left boundary bounce
        if self.projectile.x - self.bubbleRadius <= leftBoundaryX then
            self.projectile.x = leftBoundaryX + self.bubbleRadius
            self.projectile.vx = -self.projectile.vx
        end
        
        -- Top boundary bounce
        if self.projectile.y - self.bubbleRadius <= topBoundaryY then
            self.projectile.y = topBoundaryY + self.bubbleRadius
            self.projectile.vy = -self.projectile.vy
            print("DEBUG: Top bounce at y=", self.projectile.y)
        end
        
        -- Bottom boundary bounce (don't let it go off screen)
        if self.projectile.y + self.bubbleRadius >= bottomBoundaryY then
            self.projectile.y = bottomBoundaryY - self.bubbleRadius
            self.projectile.vy = -self.projectile.vy
        end
        
        -- Remove projectile if it goes off screen (but not right boundary check since shooter is outside play area)
        if self.projectile.x <= 0 or self.projectile.y <= 0 or self.projectile.y >= 240 then
            print("DEBUG: Projectile removed - pos:", self.projectile.x, self.projectile.y, "reason: boundary hit")
            self.projectile = nil
            self.shotsRemaining = self.shotsRemaining - 1
            print("DEBUG: Shots remaining after removal:", self.shotsRemaining)
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
                
                -- If projectile is close enough to an existing bubble (reduced hitbox by 2px)
                if distance <= (self.bubbleRadius * 2) - 2 then
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
        
        -- Calculate the same boundary position as in draw()
        local col9EvenRowX, _ = self:gridToScreen(9, 2)
        local boundaryLineX = col9EvenRowX + self.bubbleRadius + 2
        
        -- If bubble center + radius crosses the boundary line, it's game over
        if bubbleScreenX + self.bubbleRadius > boundaryLineX then
            return true
        end
    end
    
    return false
end

function Grid:checkMerges(x, y)
    local bubble = self.cells[x][y]
    if not bubble then return end
    
    local neighbors = self:getSameTypeNeighbors(x, y, bubble.type)
    print("Found " .. #neighbors .. " neighbors of type " .. bubble.type .. " at " .. x .. "," .. y)
    
    if #neighbors >= 3 then
        print("Merging " .. #neighbors .. " bubbles of type " .. bubble.type)
        for _, pos in ipairs(neighbors) do
            self.cells[pos.x][pos.y] = nil
        end
        
        if bubble.type <= 5 then
            self.cells[x][y] = {
                type = bubble.type + 5,
                x = x,
                y = y
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

function Grid:draw()
    local gfx = playdate.graphics
    
    -- Calculate boundary line position: 9th column should be right against it
    -- Account for stagger - even rows (like row 2, 4, 6, 8) push further right
    local col9EvenRowX, _ = self:gridToScreen(9, 2)  -- Even row (staggered)
    local col9OddRowX, _ = self:gridToScreen(9, 1)   -- Odd row (not staggered)
    
    -- Use the rightmost possible position for 9th column (staggered even row)
    local actualBoundaryX = col9EvenRowX + self.bubbleRadius + 2  -- Just touching the edge
    
    -- Calculate grid bounds for boundary lines with 2-cell buffer
    local leftmostX, _ = self:gridToScreen(1, 1)
    local topmostX, topmostY = self:gridToScreen(1, 1)
    local _, bottomRowY = self:gridToScreen(1, 8)  -- Always use row 8 as bottom
    
    local leftBoundaryX = leftmostX - self.bubbleRadius - 2  -- Add 2px buffer
    local topBoundaryY = topmostY - self.bubbleRadius - 2  -- 2px buffer
    local bottomBoundaryY = bottomRowY + self.bubbleRadius + 2  -- 2px buffer
    
    -- Draw boundary lines
    self:drawDashedLine(gfx, actualBoundaryX, topBoundaryY, actualBoundaryX, bottomBoundaryY)  -- Right boundary (stop at top/bottom)
    gfx.drawLine(leftBoundaryX, topBoundaryY, actualBoundaryX, topBoundaryY)  -- Top boundary
    gfx.drawLine(leftBoundaryX, bottomBoundaryY, actualBoundaryX, bottomBoundaryY)  -- Bottom boundary
    gfx.drawLine(leftBoundaryX, topBoundaryY, leftBoundaryX, bottomBoundaryY)  -- Left boundary
    
    -- Draw bubbles in hex grid
    for x = 1, self.width do
        for y = 1, self.height do
            local bubble = self.cells[x][y]
            if bubble then
                local drawX, drawY = self:gridToScreen(x, y)
                self:drawBubbleByType(drawX, drawY, bubble.type)
            end
        end
    end
    
    -- Draw projectile
    if self.projectile then
        self:drawBubbleByType(self.projectile.x, self.projectile.y, self.projectile.type)
    end
    
    -- Update shooter position relative to boundary
    local dynamicShooterX = actualBoundaryX + 25
    
    -- Draw ready-to-fire ball at shooter position
    if not self.projectile and self.shotsRemaining > 0 then
        self:drawBubbleByType(dynamicShooterX, self.shooterY, self.nextBubbleType)
    end
    
    -- Draw shots remaining below the shooter ball
    gfx.drawTextAligned(tostring(self.shotsRemaining), dynamicShooterX, self.shooterY + self.bubbleRadius + 10, kTextAlignment.center)
    
    -- Draw aim line from dynamic shooter position (only if not fired)
    if not self.projectile then
        gfx.drawLine(dynamicShooterX, self.shooterY, 
                     dynamicShooterX + math.cos(math.rad(self.aimAngle)) * 30,
                     self.shooterY + math.sin(math.rad(self.aimAngle)) * 30)
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

