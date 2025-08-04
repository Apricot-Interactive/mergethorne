Helpers = {}

-- Math utilities
function Helpers.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function Helpers.angle(x1, y1, x2, y2)
    return math.atan2(y2 - y1, x2 - x1)
end

function Helpers.normalize(x, y)
    local length = math.sqrt(x * x + y * y)
    if length == 0 then
        return 0, 0
    end
    return x / length, y / length
end

function Helpers.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Helpers.lerp(a, b, t)
    return a + (b - a) * t
end

-- Collision detection
function Helpers.circleCollision(x1, y1, r1, x2, y2, r2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= (r1 + r2)
end

function Helpers.pointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

-- Array utilities
function Helpers.removeFromArray(array, value)
    for i = #array, 1, -1 do
        if array[i] == value then
            table.remove(array, i)
            return true
        end
    end
    return false
end

function Helpers.shuffle(array)
    for i = #array, 2, -1 do
        local j = math.random(i)
        array[i], array[j] = array[j], array[i]
    end
end

-- Grid utilities
function Helpers.worldToGrid(worldX, worldY, cellSize)
    return math.floor(worldX / cellSize) + 1, math.floor(worldY / cellSize) + 1
end

function Helpers.gridToWorld(gridX, gridY, cellSize)
    return (gridX - 1) * cellSize + cellSize / 2, (gridY - 1) * cellSize + cellSize / 2
end

function Helpers.isValidGridPos(x, y, width, height)
    return x >= 1 and x <= width and y >= 1 and y <= height
end

-- Random utilities
function Helpers.randomFloat(min, max)
    return min + math.random() * (max - min)
end

function Helpers.randomChoice(array)
    if #array == 0 then return nil end
    return array[math.random(#array)]
end

function Helpers.weightedChoice(choices, weights)
    local totalWeight = 0
    for _, weight in ipairs(weights) do
        totalWeight = totalWeight + weight
    end
    
    local random = math.random() * totalWeight
    local currentWeight = 0
    
    for i, weight in ipairs(weights) do
        currentWeight = currentWeight + weight
        if random <= currentWeight then
            return choices[i], i
        end
    end
    
    return choices[1], 1
end

-- Debug utilities
function Helpers.debugPrint(...)
    if playdate.isSimulator then
        print(...)
    end
end

