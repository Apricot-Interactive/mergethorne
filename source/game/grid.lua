local pd <const> = playdate
local gfx <const> = pd.graphics

-- Constants
local BALL_SPEED <const> = 9
local COLLISION_DIST_SQ <const> = 400
local MAX_BOUNCES <const> = 3
local AIM_LINE_LENGTH <const> = 50
local TOP_BOUNDARY <const> = 8
local BOTTOM_BOUNDARY <const> = 200
local LEFT_BOUNDARY <const> = 10
local SHOOTER_IDX <const> = 12 * 20 + 16

local Grid = {}

-- Load sprite sheets
local bubbleSheet = gfx.image.new("assets/sprites/bubbles-basic")
local bubbleSprites = {}
local sheetWidth, sheetHeight = bubbleSheet:getSize()
for i = 1, 5 do
    local spriteWidth = sheetWidth / 5
    bubbleSprites[i] = gfx.image.new(spriteWidth, sheetHeight)
    gfx.pushContext(bubbleSprites[i])
    bubbleSheet:draw(-(i-1) * spriteWidth, 0)
    gfx.popContext()
end

-- Load Tier 1 sprite sheet
local tierOneSheet = gfx.image.new("assets/sprites/bubbles-tier-one")
local tierOneSprites = {}
local tierOneWidth, tierOneHeight = tierOneSheet:getSize()
for i = 1, 5 do
    local spriteWidth = tierOneWidth / 5
    tierOneSprites[i] = gfx.image.new(spriteWidth, tierOneHeight)
    gfx.pushContext(tierOneSprites[i])
    tierOneSheet:draw(-(i-1) * spriteWidth, 0)
    gfx.popContext()
end

-- Load Tier 2 sprite sheet
local tierTwoSheet = gfx.image.new("assets/sprites/bubbles-tier-two")
local tierTwoSprites = {}
local tierTwoWidth, tierTwoHeight = tierTwoSheet:getSize()
for i = 1, 10 do
    local spriteWidth = tierTwoWidth / 10
    tierTwoSprites[i] = gfx.image.new(spriteWidth, tierTwoHeight)
    gfx.pushContext(tierTwoSprites[i])
    tierTwoSheet:draw(-(i-1) * spriteWidth, 0)
    gfx.popContext()
end

-- Bubble type constants
local BUBBLE_TYPES = {
    FIRE = 1,
    WATER = 2, 
    EARTH = 3,
    LIGHTNING = 4,
    WIND = 5
}

local BUBBLE_NAMES = {
    [BUBBLE_TYPES.FIRE] = "Fire",
    [BUBBLE_TYPES.WATER] = "Water",
    [BUBBLE_TYPES.EARTH] = "Earth", 
    [BUBBLE_TYPES.LIGHTNING] = "Lightning",
    [BUBBLE_TYPES.WIND] = "Wind"
}

local TIER_ONE_NAMES = {
    [BUBBLE_TYPES.FIRE] = "Flame",
    [BUBBLE_TYPES.WATER] = "Rain",
    [BUBBLE_TYPES.EARTH] = "Tremor",
    [BUBBLE_TYPES.LIGHTNING] = "Shock",
    [BUBBLE_TYPES.WIND] = "Gust"
}

-- Tier 2 combination mappings
local TIER_TWO_COMBINATIONS = {
    [BUBBLE_TYPES.FIRE] = {
        [BUBBLE_TYPES.WATER] = {name = "Steam", sprite = 1},
        [BUBBLE_TYPES.EARTH] = {name = "Magma", sprite = 2},
        [BUBBLE_TYPES.WIND] = {name = "Wild Fire", sprite = 7},
        [BUBBLE_TYPES.LIGHTNING] = {name = "Explosion", sprite = 9}
    },
    [BUBBLE_TYPES.WATER] = {
        [BUBBLE_TYPES.FIRE] = {name = "Steam", sprite = 1},
        [BUBBLE_TYPES.EARTH] = {name = "Quicksand", sprite = 3},
        [BUBBLE_TYPES.WIND] = {name = "Downpour", sprite = 4},
        [BUBBLE_TYPES.LIGHTNING] = {name = "Chain Lightning", sprite = 10}
    },
    [BUBBLE_TYPES.EARTH] = {
        [BUBBLE_TYPES.FIRE] = {name = "Magma", sprite = 2},
        [BUBBLE_TYPES.WATER] = {name = "Quicksand", sprite = 3},
        [BUBBLE_TYPES.WIND] = {name = "Sandstorm", sprite = 5},
        [BUBBLE_TYPES.LIGHTNING] = {name = "Crystal", sprite = 6}
    },
    [BUBBLE_TYPES.LIGHTNING] = {
        [BUBBLE_TYPES.FIRE] = {name = "Explosion", sprite = 9},
        [BUBBLE_TYPES.WATER] = {name = "Chain Lightning", sprite = 10},
        [BUBBLE_TYPES.EARTH] = {name = "Crystal", sprite = 6},
        [BUBBLE_TYPES.WIND] = {name = "Thunderstorm", sprite = 8}
    },
    [BUBBLE_TYPES.WIND] = {
        [BUBBLE_TYPES.FIRE] = {name = "Wild Fire", sprite = 7},
        [BUBBLE_TYPES.WATER] = {name = "Downpour", sprite = 4},
        [BUBBLE_TYPES.EARTH] = {name = "Sandstorm", sprite = 5},
        [BUBBLE_TYPES.LIGHTNING] = {name = "Thunderstorm", sprite = 8}
    }
}

-- 2-3-2 pattern for Tier 2 occupation (relative to center)
local TIER_TWO_PATTERN = {
    {-1, -1}, {-1, 0},
    {0, -1}, {0, 0}, {0, 1},
    {1, -1}, {1, 0}
}

local ballTypes = {"A", "B", "C", "D", "E"} -- Keep for compatibility

function Grid:drawDashedLine(x1, y1, x2, y2, dashLen, gapLen)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local ux = dx / len
    local uy = dy / len
    
    local pos = 0
    while pos < len do
        local dashEnd = math.min(pos + dashLen, len)
        local startX = x1 + ux * pos
        local startY = y1 + uy * pos
        local endX = x1 + ux * dashEnd
        local endY = y1 + uy * dashEnd
        gfx.drawLine(startX, startY, endX, endY)
        pos = dashEnd + gapLen
    end
end

function Grid:getRandomBallType()
    return math.random(1, 5)
end

function Grid:startOnDeckAnimation()
    if self.shotCounter > 1 then
        self.animatingOnDeck = true
        local onDeckPos = self.onDeckPos
        self.onDeckAnimX = onDeckPos.x
        self.onDeckAnimY = onDeckPos.y
    end
end

function Grid:updateOnDeckAnimation()
    if not self.animatingOnDeck then return end
    
    local targetX = self.shooterPos.x
    local targetY = self.shooterPos.y
    local dx = targetX - self.onDeckAnimX
    local dy = targetY - self.onDeckAnimY
    local speed = 8
    
    if math.abs(dx) < speed and math.abs(dy) < speed then
        self.animatingOnDeck = false
        self.shooterBallType = self.onDeckBallType
        if self.shotCounter > 1 then
            self.onDeckBallType = self:getRandomBallType()
        end
    else
        local length = math.sqrt(dx * dx + dy * dy)
        self.onDeckAnimX = self.onDeckAnimX + (dx / length) * speed
        self.onDeckAnimY = self.onDeckAnimY + (dy / length) * speed
    end
end

function Grid:init()
    self.occupied = {}
    self.positions = {}
    self.permanent = {}
    self.collidable = {}
    self.ballTypes = {}
    self.ballTiers = {}
    
    for row = 1, 15 do
        local cols = (row % 2 == 1) and 20 or 19
        local rowY = (row - 1) * 16 + 8
        local rowX = (row % 2 == 0) and 10 or 0
        
        for col = 1, cols do
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = false
            self.positions[idx] = {
                x = rowX + (col - 1) * 20 + 10,
                y = rowY,
                row = row,
                col = col
            }
        end
    end
    
    local collidableCells = {
        {5,1},{5,2},{6,1},{6,2},{7,1},{7,2},{7,3},{8,1},{8,2},{9,1},{9,2}
    }
    local boundaryCells = {}
    for i = 1, 15 do
        boundaryCells[#boundaryCells + 1] = {i, 17}
    end
    for col = 1, 16 do
        boundaryCells[#boundaryCells + 1] = {14, col}
    end
    for col = 1, 16 do
        boundaryCells[#boundaryCells + 1] = {15, col}
    end
    
    for _, cell in ipairs(collidableCells) do
        local row, col = cell[1], cell[2]
        if row <= 15 and col <= ((row % 2 == 1) and 20 or 19) then
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = true
            self.permanent[idx] = true
            self.collidable[idx] = true
        end
    end
    
    for _, cell in ipairs(boundaryCells) do
        local row, col = cell[1], cell[2]
        if row <= 15 and col <= ((row % 2 == 1) and 20 or 19) then
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = true
            self.permanent[idx] = true
        end
    end
    
    self.angle = 45
    self.ball = nil
    self.shooterPos = self.positions[SHOOTER_IDX]
    self.onDeckPos = self.positions[(15 - 1) * 20 + 17]
    self.showDebug = false
    self.aimCache = {cos = 0, sin = 0}
    self.gameState = "playing"
    self.flashCounter = 0
    self.shooterBallType = self:getRandomBallType()
    self.onDeckBallType = self:getRandomBallType()
    self.shotCounter = 15
    self.animatingOnDeck = false
    self.onDeckAnimX = 0
    self.onDeckAnimY = 0
    self.animatingPop = false
    self.popAnimations = {}
    self.animatingSnap = false
    self.snapAnimations = {}
    self.pendingTierOne = nil
    self.animatingDisplacement = false
    self.displacementAnimations = {}
    self.tierOnePositions = {}
    self.tierTwoPositions = {}
    self.animatingMagnetic = false
    self.magneticAnimations = {}
    self.magneticDelayCounter = 0
    self.activeCollidables = {}
    
    local shooterIdx = SHOOTER_IDX
    self.occupied[shooterIdx] = true
    
    self:setupPreplacedBalls()
    
    local radians = math.rad(self.angle)
    self.aimCache.cos = math.cos(radians)
    self.aimCache.sin = math.sin(radians)
end

function Grid:setupPreplacedBalls()
    -- Pre-place basic balls with intentional pattern
    -- Randomize sprite assignments for variation (each sprite 1-5 used exactly once)
    local spriteTypes = {1, 2, 3, 4, 5}
    -- Shuffle the sprite assignments
    for i = 5, 2, -1 do
        local j = math.random(i)
        spriteTypes[i], spriteTypes[j] = spriteTypes[j], spriteTypes[i]
    end
    
    local prePlacedBalls = {
        {1, 1, spriteTypes[1]}, {1, 2, spriteTypes[1]}, {2, 1, spriteTypes[1]}, {2, 2, spriteTypes[1]}, -- group 1
        {3, 1, spriteTypes[2]}, {3, 2, spriteTypes[2]}, {4, 1, spriteTypes[2]}, {4, 2, spriteTypes[2]}, -- group 2
        {5, 3, spriteTypes[5]}, {5, 4, spriteTypes[5]}, {6, 3, spriteTypes[5]}, -- group 5
        {6, 4, spriteTypes[3]}, {7, 4, spriteTypes[3]}, {7, 5, spriteTypes[3]}, {8, 4, spriteTypes[3]}, -- group 3
        {8, 3, spriteTypes[1]}, {9, 3, spriteTypes[1]}, {9, 4, spriteTypes[1]}, -- group 1
        {10, 1, spriteTypes[4]}, {10, 2, spriteTypes[4]}, {11, 1, spriteTypes[4]}, {11, 2, spriteTypes[4]}, -- group 4
        {12, 1, spriteTypes[5]}, {12, 2, spriteTypes[5]}, {13, 1, spriteTypes[5]}, {13, 2, spriteTypes[5]} -- group 5
    }
    
    for _, ball in ipairs(prePlacedBalls) do
        local row, col, ballType = ball[1], ball[2], ball[3]
        if row <= 15 and col <= ((row % 2 == 1) and 20 or 19) then
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = true
            self.collidable[idx] = true
            self.ballTypes[idx] = ballType
            self.ballTiers[idx] = "basic"
        end
    end
end

function Grid:getPos(row, col)
    if row < 1 or row > 15 then return nil end
    local maxCol = (row % 2 == 1) and 20 or 19
    if col < 1 or col > maxCol then return nil end
    local idx = (row - 1) * 20 + col
    return self.positions[idx]
end

function Grid:findNearestEmpty(x, y)
    local minDist = 99999
    local nearestIdx = nil
    
    for idx, occupied in pairs(self.occupied) do
        if not occupied then
            local pos = self.positions[idx]
            if pos then
                local dist = (x - pos.x) * (x - pos.x) + (y - pos.y) * (y - pos.y)
                if dist < minDist then
                    minDist = dist
                    nearestIdx = idx
                end
            end
        end
    end
    
    return nearestIdx
end

function Grid:findNearestEmptyInRange(x, y, maxDist)
    local minDist = 99999
    local nearestIdx = nil
    local maxDistSq = maxDist * maxDist
    local shooterIdx = SHOOTER_IDX
    
    for idx, occupied in pairs(self.occupied) do
        if not occupied and self.positions[idx] and idx ~= shooterIdx then
            local pos = self.positions[idx]
            -- Ensure position exists and is valid
            if pos and pos.row and pos.col then
                local maxCol = (pos.row % 2 == 1) and 20 or 19
                if pos.col <= maxCol then
                    local distSq = (x - pos.x) * (x - pos.x) + (y - pos.y) * (y - pos.y)
                    if distSq < minDist and distSq <= maxDistSq then
                        minDist = distSq
                        nearestIdx = idx
                    end
                end
            end
        end
    end
    
    return nearestIdx
end

function Grid:getNeighbors(idx)
    local pos = self.positions[idx]
    if not pos then return {} end
    
    local row, col = pos.row, pos.col
    local neighbors = {}
    
    if row % 2 == 1 then -- odd row
        local candidates = {
            {row-1, col-1}, {row-1, col}, {row, col-1}, {row, col+1}, {row+1, col-1}, {row+1, col}
        }
        for _, candidate in ipairs(candidates) do
            local r, c = candidate[1], candidate[2]
            if r >= 1 and r <= 15 and c >= 1 and c <= ((r % 2 == 1) and 20 or 19) then
                local nIdx = (r - 1) * 20 + c
                if self.positions[nIdx] then
                    neighbors[#neighbors + 1] = nIdx
                end
            end
        end
    else -- even row
        local candidates = {
            {row-1, col}, {row-1, col+1}, {row, col-1}, {row, col+1}, {row+1, col}, {row+1, col+1}
        }
        for _, candidate in ipairs(candidates) do
            local r, c = candidate[1], candidate[2]
            if r >= 1 and r <= 15 and c >= 1 and c <= ((r % 2 == 1) and 20 or 19) then
                local nIdx = (r - 1) * 20 + c
                if self.positions[nIdx] then
                    neighbors[#neighbors + 1] = nIdx
                end
            end
        end
    end
    
    return neighbors
end

function Grid:findChain(startIdx)
    local ballType = self.ballTypes[startIdx]
    local tier = self.ballTiers[startIdx]
    
    if not ballType or tier ~= "basic" then return {} end
    
    local visited = {}
    local chain = {}
    local queue = {startIdx}
    
    while #queue > 0 do
        local idx = table.remove(queue, 1)
        if not visited[idx] then
            visited[idx] = true
            chain[#chain + 1] = idx
            
            local neighbors = self:getNeighbors(idx)
            for _, neighborIdx in ipairs(neighbors) do
                if not visited[neighborIdx] and 
                   self.ballTypes[neighborIdx] == ballType and 
                   self.ballTiers[neighborIdx] == "basic" and
                   self.collidable[neighborIdx] then
                    queue[#queue + 1] = neighborIdx
                end
            end
        end
    end
    
    return #chain >= 3 and chain or {}
end

function Grid:checkForChains(startIdx)
    if self.animatingPop or self.animatingSnap then return end
    
    local chain = self:findChain(startIdx)
    if #chain > 0 then
        self:startPopAnimation(chain)
    end
end

function Grid:startPopAnimation(chain)
    self.animatingPop = true
    self.popAnimations = {}
    
    local centerX, centerY = 0, 0
    for _, idx in ipairs(chain) do
        local pos = self.positions[idx]
        centerX = centerX + pos.x
        centerY = centerY + pos.y
    end
    centerX = centerX / #chain
    centerY = centerY / #chain
    
    for _, idx in ipairs(chain) do
        local pos = self.positions[idx]
        self.popAnimations[idx] = {
            startX = pos.x,
            startY = pos.y,
            currentX = pos.x,
            currentY = pos.y,
            targetX = centerX,
            targetY = centerY,
            frame = 0,
            ballType = self.ballTypes[idx]
        }
    end
    
    self.pendingTierOne = {
        ballType = self.ballTypes[chain[1]],
        centerX = centerX,
        centerY = centerY
    }
end

function Grid:updatePopAnimation()
    if not self.animatingPop then return end
    
    local allComplete = true
    local speed = 8
    
    for idx, anim in pairs(self.popAnimations) do
        anim.frame = anim.frame + 1
        
        local dx = anim.targetX - anim.startX
        local dy = anim.targetY - anim.startY
        local progress = math.min(anim.frame / 8, 1.0)
        
        anim.currentX = anim.startX + dx * progress
        anim.currentY = anim.startY + dy * progress
        
        if progress < 1.0 then
            allComplete = false
        end
    end
    
    if allComplete then
        for idx, _ in pairs(self.popAnimations) do
            self.occupied[idx] = false
            self.collidable[idx] = false
            self.ballTypes[idx] = nil
            self.ballTiers[idx] = nil
            
            if self.tierOnePositions[idx] then
                self.tierOnePositions[idx] = nil
            end
            
            if self.tierTwoPositions[idx] then
                self.tierTwoPositions[idx] = nil
            end
        end
        
        self.animatingPop = false
        self.popAnimations = {}
        
        if self.pendingTierOne then
            self:spawnTierOne(self.pendingTierOne)
            self.pendingTierOne = nil
        end
    end
end

function Grid:spawnTierOne(tierOneData)
    local closestIdx = self:findNearestEmpty(tierOneData.centerX, tierOneData.centerY)
    if not closestIdx then return end
    
    local triangles = self:getTriangleCombinations(closestIdx)
    local bestTriangle = nil
    local minDist = 99999
    
    for _, triangle in ipairs(triangles) do
        local triangleCenter = self:getTriangleCenter(triangle)
        local dist = (tierOneData.centerX - triangleCenter.x) * (tierOneData.centerX - triangleCenter.x) + 
                     (tierOneData.centerY - triangleCenter.y) * (tierOneData.centerY - triangleCenter.y)
        if dist < minDist then
            minDist = dist
            bestTriangle = triangle
        end
    end
    
    if bestTriangle then
        local triangleCenter = self:getTriangleCenter(bestTriangle)
        self:startSnapAnimation(tierOneData, triangleCenter, bestTriangle)
    end
end

function Grid:getTriangleCombinations(centerIdx)
    local neighbors = self:getNeighbors(centerIdx)
    local triangles = {}
    
    for i = 1, #neighbors do
        for j = i + 1, #neighbors do
            local triangle = {centerIdx, neighbors[i], neighbors[j]}
            if self:isValidTriangle(triangle) then
                triangles[#triangles + 1] = triangle
            end
        end
    end
    
    return triangles
end

function Grid:isValidTriangle(triangle)
    for _, idx in ipairs(triangle) do
        if not self.positions[idx] then
            return false
        end
    end
    return true
end

function Grid:getTriangleCenter(triangle)
    local centerX, centerY = 0, 0
    for _, idx in ipairs(triangle) do
        local pos = self.positions[idx]
        centerX = centerX + pos.x
        centerY = centerY + pos.y
    end
    return {
        x = centerX / 3,
        y = centerY / 3
    }
end

function Grid:startSnapAnimation(tierOneData, targetCenter, triangle)
    self.animatingSnap = true
    self.snapAnimations = {
        startX = tierOneData.centerX,
        startY = tierOneData.centerY,
        currentX = tierOneData.centerX,
        currentY = tierOneData.centerY,
        targetX = targetCenter.x,
        targetY = targetCenter.y,
        frame = 0,
        ballType = tierOneData.ballType,
        triangle = triangle
    }
end

function Grid:updateSnapAnimation()
    if not self.animatingSnap then return end
    
    local anim = self.snapAnimations
    anim.frame = anim.frame + 1
    
    local dx = anim.targetX - anim.startX
    local dy = anim.targetY - anim.startY
    local progress = math.min(anim.frame / 8, 1.0)
    
    anim.currentX = anim.startX + dx * progress
    anim.currentY = anim.startY + dy * progress
    
    if progress >= 1.0 then
        self:finalizeTierOneSnap(anim)
    end
end

function Grid:finalizeTierOneSnap(anim)
    self:handleDisplacements(anim.triangle)
    
    -- Mark all triangle cells as occupied by the same Tier 1 bubble
    -- Only the first cell in the triangle will render the sprite
    for i, idx in ipairs(anim.triangle) do
        self.occupied[idx] = true
        self.collidable[idx] = true
        self.ballTypes[idx] = anim.ballType
        self.ballTiers[idx] = "tier1"
        if i == 1 then
            self.tierOnePositions[idx] = {
                centerX = anim.targetX,
                centerY = anim.targetY,
                ballType = anim.ballType,
                triangle = anim.triangle
            }
        end
    end
    
    self.animatingSnap = false
    self.snapAnimations = {}
    
    -- Check for magnetic Tier 1 combinations
    self:checkMagneticCombinations()
end

function Grid:checkMagneticCombinations()
    if self.animatingMagnetic then return end
    
    -- Find all Tier 1 bubbles
    local tierOnes = {}
    for idx, tier in pairs(self.ballTiers) do
        if tier == "tier1" and self.tierOnePositions[idx] then
            tierOnes[#tierOnes + 1] = {
                idx = idx,
                ballType = self.ballTypes[idx],
                pos = self.tierOnePositions[idx]
            }
        end
    end
    
    -- Check for magnetic pairs
    for i = 1, #tierOnes do
        for j = i + 1, #tierOnes do
            local tierOne1 = tierOnes[i]
            local tierOne2 = tierOnes[j]
            
            if tierOne1.ballType ~= tierOne2.ballType then
                local combination = TIER_TWO_COMBINATIONS[tierOne1.ballType]
                if combination and combination[tierOne2.ballType] then
                    local distance = self:getMagneticDistance(tierOne1.idx, tierOne2.idx)
                    if distance <= 2 then -- magnetic range (touching or 1 cell apart)
                        self:startMagneticAttraction(tierOne1, tierOne2, combination[tierOne2.ballType])
                        return -- Only handle one pair at a time
                    end
                end
            end
        end
    end
end

function Grid:getMagneticDistance(idx1, idx2)
    local pos1 = self.positions[idx1]
    local pos2 = self.positions[idx2]
    if not pos1 or not pos2 then return 999 end
    
    local rowDiff = math.abs(pos1.row - pos2.row)
    local colDiff = math.abs(pos1.col - pos2.col)
    
    -- Manhattan distance for hex grid (approximate)
    return math.max(rowDiff, colDiff)
end

function Grid:startMagneticAttraction(tierOne1, tierOne2, tierTwoData)
    self.animatingMagnetic = true
    self.magneticDelayCounter = 8 -- 8-frame delay
    
    local centerX = (tierOne1.pos.centerX + tierOne2.pos.centerX) / 2
    local centerY = (tierOne1.pos.centerY + tierOne2.pos.centerY) / 2
    
    self.magneticAnimations = {
        tierOne1 = {
            idx = tierOne1.idx,
            startX = tierOne1.pos.centerX,
            startY = tierOne1.pos.centerY,
            currentX = tierOne1.pos.centerX,
            currentY = tierOne1.pos.centerY,
            targetX = centerX,
            targetY = centerY,
            ballType = tierOne1.ballType,
            frame = 0
        },
        tierOne2 = {
            idx = tierOne2.idx,
            startX = tierOne2.pos.centerX,
            startY = tierOne2.pos.centerY,
            currentX = tierOne2.pos.centerX,
            currentY = tierOne2.pos.centerY,
            targetX = centerX,
            targetY = centerY,
            ballType = tierOne2.ballType,
            frame = 0
        },
        tierTwoData = tierTwoData,
        mergeCenter = {x = centerX, y = centerY}
    }
end

function Grid:updateMagneticAnimation()
    if not self.animatingMagnetic then return end
    
    -- Handle delay counter
    if self.magneticDelayCounter > 0 then
        self.magneticDelayCounter = self.magneticDelayCounter - 1
        return
    end
    
    -- Update both Tier 1 animations
    local anim = self.magneticAnimations
    local allComplete = true
    
    for _, tierOne in pairs({anim.tierOne1, anim.tierOne2}) do
        tierOne.frame = tierOne.frame + 1
        
        local dx = tierOne.targetX - tierOne.startX
        local dy = tierOne.targetY - tierOne.startY
        local progress = math.min(tierOne.frame / 8, 1.0)
        
        tierOne.currentX = tierOne.startX + dx * progress
        tierOne.currentY = tierOne.startY + dy * progress
        
        if progress < 1.0 then
            allComplete = false
        end
    end
    
    if allComplete then
        self:finalizeMagneticMerge()
    end
end

function Grid:finalizeMagneticMerge()
    local anim = self.magneticAnimations
    
    -- Remove both Tier 1 bubbles completely
    for _, tierOne in pairs({anim.tierOne1, anim.tierOne2}) do
        -- Clear the specific triangle for this Tier 1
        if self.tierOnePositions[tierOne.idx] then
            local triangle = self.tierOnePositions[tierOne.idx].triangle
            if triangle then
                for _, idx in ipairs(triangle) do
                    self.occupied[idx] = false
                    self.collidable[idx] = false
                    self.ballTypes[idx] = nil
                    self.ballTiers[idx] = nil
                end
            end
            self.tierOnePositions[tierOne.idx] = nil
        else
            -- Fallback: clear the specific cell if no triangle info
            self.occupied[tierOne.idx] = false
            self.collidable[tierOne.idx] = false
            self.ballTypes[tierOne.idx] = nil
            self.ballTiers[tierOne.idx] = nil
        end
    end
    
    -- Spawn Tier 2
    self:spawnTierTwo(anim.mergeCenter, anim.tierTwoData)
    
    self.animatingMagnetic = false
    self.magneticAnimations = {}
end

function Grid:spawnTierTwo(mergeCenter, tierTwoData)
    -- Find the best center cell for the 2-3-2 pattern
    local bestCenterIdx = self:findBestTierTwoCenter(mergeCenter.x, mergeCenter.y)
    if not bestCenterIdx then return end
    
    -- Calculate the 2-3-2 pattern positions
    local pattern = self:getTierTwoPattern(bestCenterIdx)
    if not pattern then return end
    
    -- Handle displacements for occupied cells
    self:handleTierTwoDisplacements(pattern)
    
    -- Place the Tier 2
    self:placeTierTwo(bestCenterIdx, pattern, tierTwoData)
end

function Grid:findBestTierTwoCenter(x, y)
    local bestIdx = nil
    local minDist = 99999
    
    -- Search for valid center positions
    for idx, pos in pairs(self.positions) do
        if pos then
            local dist = (x - pos.x) * (x - pos.x) + (y - pos.y) * (y - pos.y)
            if dist < minDist then
                local pattern = self:getTierTwoPattern(idx)
                if pattern and #pattern == 7 then -- Valid 2-3-2 pattern
                    minDist = dist
                    bestIdx = idx
                end
            end
        end
    end
    
    return bestIdx
end

function Grid:getTierTwoPattern(centerIdx)
    local centerPos = self.positions[centerIdx]
    if not centerPos then return nil end
    
    local pattern = {}
    local positions = self.positions -- Cache table reference
    
    for _, offset in ipairs(TIER_TWO_PATTERN) do
        local row = centerPos.row + offset[1]
        local col = centerPos.col + offset[2]
        
        -- Check if position is valid
        if row >= 1 and row <= 15 and col >= 1 then
            local maxCol = (row % 2 == 1) and 20 or 19
            if col <= maxCol then
                local idx = (row - 1) * 20 + col
                if positions[idx] then
                    pattern[#pattern + 1] = idx
                end
            end
        end
    end
    
    return #pattern == 7 and pattern or nil
end


function Grid:handleTierTwoDisplacements(pattern)
    local displacements = {}
    
    for _, idx in ipairs(pattern) do
        if self.occupied[idx] and not self.permanent[idx] then
            local displacement = self:findDisplacementTarget(idx)
            if displacement then
                displacements[#displacements + 1] = displacement
            else
                local fallbackTarget = self:findNearestEmpty(self.positions[idx].x, self.positions[idx].y)
                if fallbackTarget then
                    displacements[#displacements + 1] = {
                        fromIdx = idx,
                        toIdx = fallbackTarget,
                        ballType = self.ballTypes[idx],
                        tier = self.ballTiers[idx]
                    }
                end
            end
        end
    end
    
    if #displacements > 0 then
        self:startDisplacementAnimation(displacements)
        -- Wait for displacements to complete before placing Tier 2
        -- This is handled by the displacement animation system
    end
end

function Grid:placeTierTwo(centerIdx, pattern, tierTwoData)
    -- Mark all pattern cells as occupied
    for _, idx in ipairs(pattern) do
        self.occupied[idx] = true
        self.collidable[idx] = true
        self.ballTypes[idx] = tierTwoData.sprite
        self.ballTiers[idx] = "tier2"
    end
    
    -- Store rendering info for the center cell
    self.tierTwoPositions[centerIdx] = {
        centerX = self.positions[centerIdx].x,
        centerY = self.positions[centerIdx].y,
        sprite = tierTwoData.sprite,
        name = tierTwoData.name,
        pattern = pattern
    }
    
    -- Check for further chain reactions
    self:checkMagneticCombinations()
end

function Grid:handleDisplacements(triangle)
    local displacements = {}
    
    for _, idx in ipairs(triangle) do
        if self.occupied[idx] and not self.permanent[idx] then
            local displacement = self:findDisplacementTarget(idx)
            if displacement then
                displacements[#displacements + 1] = displacement
            else
                -- If we can't find a displacement target, try to place it anywhere nearby
                local fallbackTarget = self:findNearestEmpty(self.positions[idx].x, self.positions[idx].y)
                if fallbackTarget then
                    displacements[#displacements + 1] = {
                        fromIdx = idx,
                        toIdx = fallbackTarget,
                        ballType = self.ballTypes[idx],
                        tier = self.ballTiers[idx]
                    }
                end
                -- If even that fails, the bubble will be lost (should be rare)
            end
        end
    end
    
    if #displacements > 0 then
        self:startDisplacementAnimation(displacements)
    end
end

function Grid:findDisplacementTarget(idx)
    local neighbors = self:getNeighbors(idx)
    
    for _, neighborIdx in ipairs(neighbors) do
        if not self.occupied[neighborIdx] then
            return {
                fromIdx = idx,
                toIdx = neighborIdx,
                ballType = self.ballTypes[idx],
                tier = self.ballTiers[idx]
            }
        end
    end
    
    for _, neighborIdx in ipairs(neighbors) do
        if self.occupied[neighborIdx] and not self.permanent[neighborIdx] then
            local chainedDisplacement = self:findDisplacementTarget(neighborIdx)
            if chainedDisplacement then
                return {
                    fromIdx = idx,
                    toIdx = neighborIdx,
                    ballType = self.ballTypes[idx],
                    tier = self.ballTiers[idx],
                    chainedDisplacement = chainedDisplacement
                }
            end
        end
    end
    
    return nil
end

function Grid:startDisplacementAnimation(displacements)
    self.animatingDisplacement = true
    self.displacementAnimations = {}
    
    for _, displacement in ipairs(displacements) do
        self:addDisplacementAnimation(displacement)
    end
end

function Grid:addDisplacementAnimation(displacement)
    local fromPos = self.positions[displacement.fromIdx]
    local toPos = self.positions[displacement.toIdx]
    
    self.displacementAnimations[displacement.fromIdx] = {
        startX = fromPos.x,
        startY = fromPos.y,
        currentX = fromPos.x,
        currentY = fromPos.y,
        targetX = toPos.x,
        targetY = toPos.y,
        frame = 0,
        toIdx = displacement.toIdx,
        ballType = displacement.ballType,
        tier = displacement.tier
    }
    
    if displacement.chainedDisplacement then
        self:addDisplacementAnimation(displacement.chainedDisplacement)
    end
end

function Grid:updateDisplacementAnimation()
    if not self.animatingDisplacement then return end
    
    local allComplete = true
    
    for fromIdx, anim in pairs(self.displacementAnimations) do
        anim.frame = anim.frame + 1
        
        local dx = anim.targetX - anim.startX
        local dy = anim.targetY - anim.startY
        local progress = math.min(anim.frame / 4, 1.0)
        
        anim.currentX = anim.startX + dx * progress
        anim.currentY = anim.startY + dy * progress
        
        if progress < 1.0 then
            allComplete = false
        end
    end
    
    if allComplete then
        for fromIdx, anim in pairs(self.displacementAnimations) do
            self.occupied[fromIdx] = false
            self.collidable[fromIdx] = false
            self.ballTypes[fromIdx] = nil
            self.ballTiers[fromIdx] = nil
            
            if self.tierOnePositions[fromIdx] then
                self.tierOnePositions[fromIdx] = nil
            end
            
            if self.tierTwoPositions[fromIdx] then
                self.tierTwoPositions[fromIdx] = nil
            end
            
            self.occupied[anim.toIdx] = true
            self.collidable[anim.toIdx] = true
            self.ballTypes[anim.toIdx] = anim.ballType
            self.ballTiers[anim.toIdx] = anim.tier
            
            if anim.tier == "tier1" then
                self.tierOnePositions[anim.toIdx] = {
                    centerX = anim.targetX,
                    centerY = anim.targetY,
                    ballType = anim.ballType
                }
            elseif anim.tier == "tier2" then
                self.tierTwoPositions[anim.toIdx] = {
                    centerX = anim.targetX,
                    centerY = anim.targetY,
                    sprite = anim.ballType, -- For Tier 2, ballType is the sprite index
                    name = anim.name or "Unknown"
                }
            end
        end
        
        self.animatingDisplacement = false
        self.displacementAnimations = {}
    end
end

function Grid:restart()
    self.occupied = {}
    self.positions = {}
    self.permanent = {}
    self.collidable = {}
    self.ballTypes = {}
    self.ballTiers = {}
    
    for row = 1, 15 do
        local cols = (row % 2 == 1) and 20 or 19
        local rowY = (row - 1) * 16 + 8
        local rowX = (row % 2 == 0) and 10 or 0
        
        for col = 1, cols do
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = false
            self.positions[idx] = {
                x = rowX + (col - 1) * 20 + 10,
                y = rowY,
                row = row,
                col = col
            }
        end
    end
    
    local collidableCells = {
        {5,1},{5,2},{6,1},{6,2},{7,1},{7,2},{7,3},{8,1},{8,2},{9,1},{9,2}
    }
    local boundaryCells = {}
    for i = 1, 15 do
        boundaryCells[#boundaryCells + 1] = {i, 17}
    end
    for col = 1, 16 do
        boundaryCells[#boundaryCells + 1] = {14, col}
    end
    for col = 1, 16 do
        boundaryCells[#boundaryCells + 1] = {15, col}
    end
    
    for _, cell in ipairs(collidableCells) do
        local row, col = cell[1], cell[2]
        if row <= 15 and col <= ((row % 2 == 1) and 20 or 19) then
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = true
            self.permanent[idx] = true
            self.collidable[idx] = true
        end
    end
    
    for _, cell in ipairs(boundaryCells) do
        local row, col = cell[1], cell[2]
        if row <= 15 and col <= ((row % 2 == 1) and 20 or 19) then
            local idx = (row - 1) * 20 + col
            self.occupied[idx] = true
            self.permanent[idx] = true
        end
    end
    
    self.angle = 45
    self.ball = nil
    self.shooterPos = self.positions[SHOOTER_IDX]
    self.onDeckPos = self.positions[(15 - 1) * 20 + 17]
    self.gameState = "playing"
    self.flashCounter = 0
    self.shooterBallType = self:getRandomBallType()
    self.onDeckBallType = self:getRandomBallType()
    self.shotCounter = 15
    self.animatingOnDeck = false
    self.onDeckAnimX = 0
    self.onDeckAnimY = 0
    self.animatingPop = false
    self.popAnimations = {}
    self.animatingSnap = false
    self.snapAnimations = {}
    self.pendingTierOne = nil
    self.animatingDisplacement = false
    self.displacementAnimations = {}
    self.tierOnePositions = {}
    self.tierTwoPositions = {}
    self.animatingMagnetic = false
    self.magneticAnimations = {}
    self.magneticDelayCounter = 0
    self.activeCollidables = {}
    
    local shooterIdx = SHOOTER_IDX
    self.occupied[shooterIdx] = true
    
    self:setupPreplacedBalls()
    
    local radians = math.rad(self.angle)
    self.aimCache.cos = math.cos(radians)
    self.aimCache.sin = math.sin(radians)
end

function Grid:handleInput()
    if self.gameState == "gameOver" then
        if pd.buttonJustPressed(pd.kButtonA) then
            self:restart()
        end
        return
    end
    
    local angleChanged = false
    if pd.buttonIsPressed(pd.kButtonUp) and self.angle < 86 then
        self.angle = self.angle + 2
        angleChanged = true
    elseif pd.buttonIsPressed(pd.kButtonDown) and self.angle > 1 then
        self.angle = self.angle - 2
        angleChanged = true
    elseif pd.buttonJustPressed(pd.kButtonLeft) then
        self.showDebug = not self.showDebug
    elseif pd.buttonJustPressed(pd.kButtonA) and not self.ball and self.shotCounter > 0 and 
           not self.animatingPop and not self.animatingSnap and not self.animatingDisplacement and not self.animatingMagnetic then
        self.ball = {
            x = self.shooterPos.x,
            y = self.shooterPos.y,
            vx = -self.aimCache.cos * BALL_SPEED,
            vy = -self.aimCache.sin * BALL_SPEED,
            bounces = 0,
            state = "flying",
            ballType = self.shooterBallType
        }
    end
    
    if angleChanged then
        local radians = math.rad(self.angle)
        self.aimCache.cos = math.cos(radians)
        self.aimCache.sin = math.sin(radians)
    end
end

function Grid:updateBall()
    self:updateOnDeckAnimation()
    self:updatePopAnimation()
    self:updateSnapAnimation()
    self:updateDisplacementAnimation()
    self:updateMagneticAnimation()
    
    if not self.ball then return end
    
    if self.ball.state == "flashing" then
        self.flashCounter = self.flashCounter + 1
        if self.flashCounter >= 60 then
            self.gameState = "gameOver"
            self.flashCounter = 0
        end
        return
    end
    
    if self.ball.state == "flying" or self.ball.state == "failed" then
        self.ball.x = self.ball.x + self.ball.vx
        self.ball.y = self.ball.y + self.ball.vy
    end
    
    if self.ball.y <= TOP_BOUNDARY or self.ball.y >= BOTTOM_BOUNDARY then
        if self.ball.state == "failed" then
            self.ball.state = "flashing"
            self.flashCounter = 0
            return
        end
        
        if self.ball.bounces >= MAX_BOUNCES then
            local nearestIdx = self:findNearestEmptyInRange(self.ball.x, self.ball.y, 15)
            if nearestIdx then
                self.occupied[nearestIdx] = true
                self.collidable[nearestIdx] = true
                self.ballTypes[nearestIdx] = self.ball.ballType
                self.ball = nil
                self.shotCounter = self.shotCounter - 1
                self:startOnDeckAnimation()
                return
            else
                self.ball.state = "failed"
            end
        else
            self.ball.vy = -self.ball.vy
            self.ball.bounces = self.ball.bounces + 1
        end
    end
    
    if self.ball.x <= LEFT_BOUNDARY then
        if self.ball.state == "failed" then
            self.ball.state = "flashing"
            self.flashCounter = 0
            return
        end
        
        local nearestIdx = self:findNearestEmptyInRange(self.ball.x, self.ball.y, 15)
        if nearestIdx then
            self.occupied[nearestIdx] = true
            self.collidable[nearestIdx] = true
            self.ballTypes[nearestIdx] = self.ball.ballType
            self.ballTiers[nearestIdx] = "basic"
            self.ball = nil
            self.shotCounter = self.shotCounter - 1
            self:checkForChains(nearestIdx)
            self:startOnDeckAnimation()
            return
        else
            self.ball.state = "failed"
        end
    end
    
    for idx, collidable in pairs(self.collidable) do
        if collidable and self.positions[idx] then
            local pos = self.positions[idx]
            local collided = false
            
            -- For multi-cell bubbles, check collision against their actual center
            if self.ballTiers[idx] == "tier1" and self.tierOnePositions[idx] then
                -- Use the Tier 1's actual center position and radius
                local tierOnePos = self.tierOnePositions[idx]
                local dist = (self.ball.x - tierOnePos.centerX) * (self.ball.x - tierOnePos.centerX) + 
                           (self.ball.y - tierOnePos.centerY) * (self.ball.y - tierOnePos.centerY)
                if dist <= (18 * 18) then -- Tier 1 collision radius
                    collided = true
                end
            elseif self.ballTiers[idx] == "tier2" and self.tierTwoPositions[idx] then
                -- Use the Tier 2's actual center position and radius
                local tierTwoPos = self.tierTwoPositions[idx]
                local dist = (self.ball.x - tierTwoPos.centerX) * (self.ball.x - tierTwoPos.centerX) + 
                           (self.ball.y - tierTwoPos.centerY) * (self.ball.y - tierTwoPos.centerY)
                if dist <= (26 * 26) then -- Tier 2 collision radius
                    collided = true
                end
            else
                -- Basic bubble collision
                local dist = (self.ball.x - pos.x) * (self.ball.x - pos.x) + (self.ball.y - pos.y) * (self.ball.y - pos.y)
                if dist <= (10 * 10) then -- Basic bubble collision radius
                    collided = true
                end
            end
            
            if collided then
                if self.ball.state == "failed" then
                    self.ball.state = "flashing"
                    self.flashCounter = 0
                    return
                end
                
                local nearestIdx = self:findNearestEmptyInRange(self.ball.x, self.ball.y, 15)
                if nearestIdx then
                    self.occupied[nearestIdx] = true
                    self.collidable[nearestIdx] = true
                    self.ballTypes[nearestIdx] = self.ball.ballType
                    self.ballTiers[nearestIdx] = "basic"
                    self.ball = nil
                    self.shotCounter = self.shotCounter - 1
                    self:checkForChains(nearestIdx)
                    self:startOnDeckAnimation()
                    return
                else
                    self.ball.state = "failed"
                end
            end
        end
    end
end

function Grid:draw()
    for row = 1, 15 do
        local cols = (row % 2 == 1) and 20 or 19
        local rowY = (row - 1) * 16 + 8
        local rowX = (row % 2 == 0) and 10 or 0
        
        for col = 1, cols do
            local idx = (row - 1) * 20 + col
            local x = rowX + (col - 1) * 20 + 10
            local shooterIdx = SHOOTER_IDX
            
            -- Skip rendering the shooter position in grid logic
            if idx ~= shooterIdx then
                if self.showDebug then
                    if self.permanent[idx] then
                        gfx.fillCircleAtPoint(x, rowY, 2)
                    elseif self.occupied[idx] then
                        if self.ballTypes[idx] then
                            if self.ballTiers[idx] == "tier1" and self.tierOnePositions[idx] then
                                local tierOnePos = self.tierOnePositions[idx]
                                tierOneSprites[tierOnePos.ballType]:draw(tierOnePos.centerX-18, tierOnePos.centerY-18)
                            elseif self.ballTiers[idx] == "tier2" and self.tierTwoPositions[idx] then
                                local tierTwoPos = self.tierTwoPositions[idx]
                                tierTwoSprites[tierTwoPos.sprite]:draw(tierTwoPos.centerX-26, tierTwoPos.centerY-26)
                            elseif self.ballTiers[idx] == "basic" then
                                bubbleSprites[self.ballTypes[idx]]:draw(x-10, rowY-10)
                            end
                        else
                            gfx.fillCircleAtPoint(x, rowY, 10)
                        end
                    else
                        gfx.drawCircleAtPoint(x, rowY, 10)
                    end
                else
                    if self.occupied[idx] and not self.permanent[idx] then
                        if self.ballTypes[idx] then
                            if self.ballTiers[idx] == "tier1" and self.tierOnePositions[idx] then
                                local tierOnePos = self.tierOnePositions[idx]
                                tierOneSprites[tierOnePos.ballType]:draw(tierOnePos.centerX-18, tierOnePos.centerY-18)
                            elseif self.ballTiers[idx] == "tier2" and self.tierTwoPositions[idx] then
                                local tierTwoPos = self.tierTwoPositions[idx]
                                tierTwoSprites[tierTwoPos.sprite]:draw(tierTwoPos.centerX-26, tierTwoPos.centerY-26)
                            elseif self.ballTiers[idx] == "basic" then
                                bubbleSprites[self.ballTypes[idx]]:draw(x-10, rowY-10)
                            end
                        else
                            gfx.fillCircleAtPoint(x, rowY, 10)
                        end
                    end
                end
            end
        end
    end
    
    local bottomTangent = 12 * 16 + 8 + 10
    self:drawDashedLine(0, bottomTangent, 400, bottomTangent, 6, 4)
    
    local rightTangent = self.positions[20 + 16].x
    self:drawDashedLine(rightTangent, 0, rightTangent, bottomTangent, 6, 4)
    
    local topY = self.positions[4*20+2].y - 7
    local topEndX = self.positions[4*20+2].x + 7
    local bottomY = self.positions[8*20+2].y + 7
    local bottomEndX = self.positions[8*20+2].x + 7
    local apexX = self.positions[6*20+3].x + 10
    local apexY = self.positions[6*20+3].y
    
    gfx.drawLine(0, topY, topEndX, topY)
    gfx.drawLine(0, bottomY, bottomEndX, bottomY)
    
    local prevX, prevY = topEndX, topY
    for t = 0.1, 0.9, 0.1 do
        local tt = t * t
        local u = 1 - t
        local uu = u * u
        local x = uu * topEndX + 2 * u * t * apexX + tt * bottomEndX
        local y = uu * topY + 2 * u * t * apexY + tt * bottomY
        gfx.drawLine(prevX, prevY, x, y)
        prevX, prevY = x, y
    end
    gfx.drawLine(prevX, prevY, bottomEndX, bottomY)
    
    -- Only draw shooter ball if no ball is flying and not animating on-deck
    if not self.ball and not self.animatingOnDeck then
        bubbleSprites[self.shooterBallType]:draw(self.shooterPos.x-10, self.shooterPos.y-10)
    end
    
    if not self.ball and not self.animatingOnDeck then
        local endX = self.shooterPos.x - self.aimCache.cos * AIM_LINE_LENGTH
        local endY = self.shooterPos.y - self.aimCache.sin * AIM_LINE_LENGTH
        gfx.drawLine(self.shooterPos.x, self.shooterPos.y, endX, endY)
    end
    
    if self.ball then
        if self.ball.state == "flashing" then
            local flashPhase = math.floor(self.flashCounter / 10) % 2
            if flashPhase == 0 then
                bubbleSprites[self.ball.ballType]:draw(self.ball.x-10, self.ball.y-10)
            end
        else
            bubbleSprites[self.ball.ballType]:draw(self.ball.x-10, self.ball.y-10)
        end
    end
    
    -- Draw pop animations
    for idx, anim in pairs(self.popAnimations) do
        bubbleSprites[anim.ballType]:draw(anim.currentX-10, anim.currentY-10)
    end
    
    -- Draw snap animation
    if self.animatingSnap then
        local anim = self.snapAnimations
        tierOneSprites[anim.ballType]:draw(anim.currentX-18, anim.currentY-18)
    end
    
    -- Draw displacement animations
    for fromIdx, anim in pairs(self.displacementAnimations) do
        if anim.tier == "tier1" then
            tierOneSprites[anim.ballType]:draw(anim.currentX-18, anim.currentY-18)
        elseif anim.tier == "tier2" then
            tierTwoSprites[anim.ballType]:draw(anim.currentX-26, anim.currentY-26)
        else
            bubbleSprites[anim.ballType]:draw(anim.currentX-10, anim.currentY-10)
        end
    end
    
    -- Draw magnetic animations
    if self.animatingMagnetic and self.magneticDelayCounter <= 0 then
        local anim = self.magneticAnimations
        tierOneSprites[anim.tierOne1.ballType]:draw(anim.tierOne1.currentX-18, anim.tierOne1.currentY-18)
        tierOneSprites[anim.tierOne2.ballType]:draw(anim.tierOne2.currentX-18, anim.tierOne2.currentY-18)
    end
    
    -- Draw on-deck ball and shot counter
    if self.shotCounter > 1 then
        local onDeckPos = self.onDeckPos
        if onDeckPos then
            if self.animatingOnDeck then
                bubbleSprites[self.onDeckBallType]:draw(self.onDeckAnimX-10, self.onDeckAnimY-10)
            else
                bubbleSprites[self.onDeckBallType]:draw(onDeckPos.x-10, onDeckPos.y-10)
            end
        end
    end
    
    -- Draw shot counter
    if self.shotCounter > 0 then
        local onDeckPos = self.onDeckPos
        if onDeckPos then
            gfx.drawText(self.shotCounter, onDeckPos.x + 25, onDeckPos.y - 8)
        end
    end
    
    if self.gameState == "gameOver" then
        local boxWidth = 200
        local boxHeight = 80
        local boxX = 200 - boxWidth / 2
        local boxY = 120 - boxHeight / 2
        
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(boxX, boxY, boxWidth, boxHeight)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(boxX, boxY, boxWidth, boxHeight)
        
        gfx.drawTextInRect("GAME OVER", boxX, boxY + 15, boxWidth, 20, nil, nil, kTextAlignment.center)
        gfx.drawTextInRect("Press A to restart", boxX, boxY + 45, boxWidth, 20, nil, nil, kTextAlignment.center)
    end
end

return Grid