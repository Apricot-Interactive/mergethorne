-- Math utilities and common helper functions
-- Extracted from bubbleState.lua for better maintainability

local helpers = {}

-- Math utilities
function helpers.distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function helpers.distanceSquared(x1, y1, x2, y2)
    return (x2 - x1)^2 + (y2 - y1)^2
end

-- Optimized distance comparison - use squared distance to avoid sqrt when possible
function helpers.isWithinDistance(x1, y1, x2, y2, maxDistance)
    local maxDistanceSquared = maxDistance * maxDistance
    return helpers.distanceSquared(x1, y1, x2, y2) <= maxDistanceSquared
end

function helpers.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

function helpers.lerp(a, b, t)
    return a + (b - a) * t
end

-- Angle utilities
function helpers.normalizeAngle(angle)
    while angle < 0 do
        angle = angle + 360
    end
    while angle >= 360 do
        angle = angle - 360
    end
    return angle
end

function helpers.degreesToRadians(degrees)
    return math.rad(degrees)
end

function helpers.radiansToDegrees(radians)
    return math.deg(radians)
end

-- Grid and hex utilities
function helpers.getHexStagger(row)
    -- Standardized hex stagger calculation matching grid setup
    -- Returns 1 if row has hex offset, 0 if not
    return ((row - 1) % 2)
end

function helpers.isValidGridPosition(row, col, totalRows, rowLengths)
    return row >= 1 and row <= totalRows and 
           col >= 1 and col <= (rowLengths[row] or 0)
end

-- Array utilities
function helpers.hasElements(table)
    for _, _ in pairs(table) do
        return true
    end
    return false
end

function helpers.tableCount(table)
    local count = 0
    for _, _ in pairs(table) do
        count = count + 1
    end
    return count
end

-- Collision detection utilities
function helpers.circleCollision(x1, y1, r1, x2, y2, r2)
    local distance = helpers.distance(x1, y1, x2, y2)
    return distance < (r1 + r2)
end

function helpers.pointInRect(x, y, rectX, rectY, rectWidth, rectHeight)
    return x >= rectX and x <= rectX + rectWidth and 
           y >= rectY and y <= rectY + rectHeight
end

-- Boundary checking utilities
function helpers.isWithinGameBounds(x, y, leftPadding, rightPadding, screenWidth, screenHeight)
    return x >= leftPadding and x <= screenWidth - rightPadding and
           y >= 0 and y <= screenHeight
end

function helpers.isWithinScreenBounds(x, y, margin, screenWidth, screenHeight)
    return x >= -margin and x <= screenWidth + margin and
           y >= -margin and y <= screenHeight + margin
end

-- Drawing utilities
function helpers.drawDashedLine(x1, y1, x2, y2, dashLength, gapLength)
    local dx = x2 - x1
    local dy = y2 - y1
    local totalLength = helpers.distance(x1, y1, x2, y2)
    local segmentLength = dashLength + gapLength
    
    local dirX = dx / totalLength
    local dirY = dy / totalLength
    
    local currentPos = 0
    while currentPos < totalLength do
        local segmentStart = currentPos
        local segmentEnd = math.min(currentPos + dashLength, totalLength)
        
        if segmentEnd > segmentStart then
            local startX = x1 + dirX * segmentStart
            local startY = y1 + dirY * segmentStart
            local endX = x1 + dirX * segmentEnd
            local endY = y1 + dirY * segmentEnd
            
            playdate.graphics.drawLine(startX, startY, endX, endY)
        end
        
        currentPos = currentPos + segmentLength
    end
end

-- Random utilities
function helpers.randomChoice(array)
    if #array == 0 then return nil end
    return array[math.random(#array)]
end

function helpers.randomRange(min, max)
    return math.random(min, max)
end

return helpers