-- Placement System: handles asset placement, nudging, conflict resolution, and positioning
-- Extracted from bubbleState.lua for better code organization

-- Self-contained placement system with no external dependencies

PlacementSystem = {}

function PlacementSystem:new()
    local system = {}
    setmetatable(system, self)
    self.__index = self
    return system
end

-- Main placement function with nudging system
function PlacementSystem:placeAssetWithNudge(assetType, bubbleType, preferredRow, preferredCol, maxNudgeDistance, shotRow, shotCol, bubbleState)
    -- Determine actual nudge distance based on asset type
    local actualNudgeDistance = self:getMaxNudgeDistance(assetType)
    local searchDistance = math.min(maxNudgeDistance, actualNudgeDistance)
    
    print("DEBUG: Nudging", assetType, "with max distance", searchDistance)
    
    -- First try the preferred position, but for Tier 1 check for floating appearance
    if bubbleState:canPlaceAsset(assetType, preferredRow, preferredCol) then
        if assetType == "tierOne" and self:wouldAppearFloating(assetType, preferredRow, preferredCol, bubbleState) then
            print("DEBUG: Preferred position", preferredRow, preferredCol, "would appear floating, searching alternatives")
        else
            print("DEBUG: Preferred position", preferredRow, preferredCol, "is available, using it directly")
            return bubbleState:placeAssetDirect(assetType, bubbleType, preferredRow, preferredCol, false)
        end
    else
        print("DEBUG: Preferred position", preferredRow, preferredCol, "is NOT available, searching alternatives")
    end
    
    -- Collect all positions within nudge range
    local candidatePositions = {}
    for distance = 1, searchDistance do
        local positions = self:getPositionsAtDistance(preferredRow, preferredCol, distance)
        
        -- For Tier 1, sort positions to prefer left/left-down/left-up to avoid floating appearance
        if assetType == "tierOne" then
            table.sort(positions, function(a, b)
                -- Priority 1: Prefer leftward movement (negative deltaCol)
                local aLeftward = a.deltaCol < 0
                local bLeftward = b.deltaCol < 0
                if aLeftward ~= bLeftward then
                    return aLeftward  -- Prefer leftward over non-leftward
                end
                
                -- Priority 2: Among leftward moves, prefer left-down over left-up
                if aLeftward and bLeftward then
                    if a.deltaRow ~= b.deltaRow then
                        return a.deltaRow > b.deltaRow  -- Prefer same row (0) or down (+) over up (-)
                    end
                    -- If same row delta, prefer closer to left (more negative deltaCol)
                    return a.deltaCol < b.deltaCol
                end
                
                -- Priority 3: For non-leftward moves, use original logic
                if a.deltaRow ~= b.deltaRow then
                    return a.deltaRow > b.deltaRow  -- 0 or positive deltaRow preferred over negative
                end
                return math.abs(a.deltaCol) < math.abs(b.deltaCol)
            end)
        end
        
        for _, pos in ipairs(positions) do
            if bubbleState:isValidCell(pos.row, pos.col) then
                table.insert(candidatePositions, pos)
            end
        end
    end
    
    -- Find the best placement using stomping logic  
    local bestPlacement = self:findBestPlacementWithStomping(assetType, candidatePositions, preferredRow, preferredCol, shotRow, shotCol, bubbleState)
    
    if bestPlacement then
        
        -- Execute the stomping (remove conflicting assets)
        if bestPlacement.assetsToRemove and #bestPlacement.assetsToRemove > 0 then
            print("DEBUG: Stomping", #bestPlacement.assetsToRemove, "assets for placement")
            for _, assetId in ipairs(bestPlacement.assetsToRemove) do
                local stompedAsset = bubbleState.assets[assetId]
                if stompedAsset then
                    print("DEBUG: Stomping asset", assetId, "-", stompedAsset.type, "bubbleType", stompedAsset.bubbleType, "for", assetType, "placement")
                end
                bubbleState:removeAsset(assetId)
            end
        end
        
        -- Place the new asset
        print("DEBUG: Placing at", bestPlacement.row, bestPlacement.col, "after stomping")
        return bubbleState:placeAssetDirect(assetType, bubbleType, bestPlacement.row, bestPlacement.col, false)
    end
    
    print("DEBUG: Could not find valid placement with stomping within", searchDistance, "spaces")
    return nil
end

-- Find the best placement position using stomping logic
function PlacementSystem:findBestPlacementWithStomping(assetType, candidatePositions, targetRow, targetCol, shotRow, shotCol, bubbleState)
    local placements = {}
    
    -- Analyze each candidate position
    for _, pos in ipairs(candidatePositions) do
        local analysis = self:analyzePlacement(assetType, pos.row, pos.col, bubbleState)
        if analysis then
            -- Check if Tier 1 would appear floating at this position
            analysis.wouldFloat = (assetType == "tierOne") and self:wouldAppearFloating(assetType, pos.row, pos.col, bubbleState)
            
            -- Check if this position would stay within screen bounds
            analysis.withinBounds = self:isWithinScreenBounds(assetType, pos.row, pos.col, bubbleState)
            
            -- Check if this position could trigger a cascade merge
            analysis.cascadePotential = self:evaluateCascadePotential(assetType, pos.row, pos.col, bubbleState)
            
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
    placements = self:filterAcceptablePlacements(placements, assetType)
    
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
        
        -- 2. For Tier 3, absolutely prioritize staying within screen bounds
        if assetType == "tierThree" and a.withinBounds ~= b.withinBounds then
            return a.withinBounds  -- Prefer on-screen over off-screen for Tier 3
        end
        
        -- 3. Within same cascade tier, strongly prefer non-floating positions for Tier 1
        if a.wouldFloat ~= b.wouldFloat then
            return not a.wouldFloat  -- Prefer non-floating over floating
        end
        
        -- 4. Within same cascade tier and floating status, prefer exact target matches (distance 0) 
        local aExact = (a.distanceFromTarget == 0)
        local bExact = (b.distanceFromTarget == 0)
        if aExact ~= bExact then
            return aExact -- Prefer the exact match
        end
        
        -- 5. Within same tier and floating status, prefer positions closer to merge target
        if a.distanceFromTarget ~= b.distanceFromTarget then
            return a.distanceFromTarget < b.distanceFromTarget
        end
        
        -- 6. Among equal distances, prefer higher exact cascade scores
        if a.cascadePotential ~= b.cascadePotential then
            return a.cascadePotential > b.cascadePotential
        end
        
        -- 7. Among equal cascade scores, prefer positions closer to shot location
        -- For Tier 1, give extra weight to shot location proximity
        if assetType == "tierOne" and shotRow and shotCol then
            if a.distanceFromShot ~= b.distanceFromShot then
                return a.distanceFromShot < b.distanceFromShot
            end
        elseif a.distanceFromShot ~= b.distanceFromShot then
            return a.distanceFromShot < b.distanceFromShot
        end
        
        -- 8. Finally use stomping priority
        return self:comparePlacementPriority(a, b, assetType)
    end)
    
    -- Debug output to show top placement choices
    if (assetType == "tierOne" or assetType == "tierThree") and #placements > 1 then
        print("DEBUG: Top 3", assetType, "placement options (target:", targetRow, targetCol, "shot:", shotRow or "?", shotCol or "?", "):")
        for i = 1, math.min(3, #placements) do
            local p = placements[i]
            local stompCount = p.assetsToRemove and #p.assetsToRemove or 0
            local boundsText = (assetType == "tierThree") and ("bounds " .. tostring(p.withinBounds)) or ""
            local floatText = (assetType == "tierOne") and ("floating " .. tostring(p.wouldFloat or false)) or ""
            local extraInfo = (boundsText ~= "" and boundsText) or floatText
            print("DEBUG:  ", i, "- Position", p.row, p.col, "targetDist", p.distanceFromTarget, "shotDist", p.distanceFromShot, "stomps", stompCount, "cascade", p.cascadePotential, extraInfo)
        end
    end
    
    return placements[1]
end

-- Evaluate the cascade potential of placing an asset at a specific position
function PlacementSystem:evaluateCascadePotential(assetType, row, col, bubbleState)
    -- Enhanced cascade evaluation that considers stomping-induced merges
    local potentialScore = 0
    
    -- First check if stomping basic bubbles here could create additional Tier 1s
    if assetType == "tierOne" then
        local analysis = self:analyzePlacement(assetType, row, col, bubbleState)
        if analysis and analysis.assetsToRemove then
            for _, assetId in ipairs(analysis.assetsToRemove) do
                local asset = bubbleState.assets[assetId]
                if asset and asset.type == "basic" then
                    -- Check if removing this basic bubble would trigger another merge
                    local mergeInfo = self:simulateBasicRemovalMerge(asset, bubbleState)
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
    local patternCells = bubbleState:findPatternCells(assetType, row, col)
    if not patternCells then
        return potentialScore
    end
    
    -- Track unique adjacent assets to avoid counting them multiple times
    local seenAssets = {}
    
    for _, patternCell in ipairs(patternCells) do
        for _, dir in ipairs(directions) do
            local checkRow = patternCell.row + dir[1]
            local checkCol = patternCell.col + dir[2]
            
            if bubbleState:isValidCell(checkRow, checkCol) then
                local occupantId = bubbleState:getCellOccupant(checkRow, checkCol)
                if occupantId and not seenAssets[occupantId] then
                    seenAssets[occupantId] = true
                    local adjacentAsset = bubbleState.assets[occupantId]
                    if adjacentAsset then
                        if assetType == "tierOne" and adjacentAsset.type == "tierOne" then
                            -- Tier 1 + Tier 1 could form Tier 2
                            potentialScore = potentialScore + 500
                            print("DEBUG: CASCADE POTENTIAL +500 for Tier 1 + Tier 1 = Tier 2 at", row, col, "with", adjacentAsset.type, "bubbleType", adjacentAsset.bubbleType)
                        elseif assetType == "tierOne" and adjacentAsset.type == "tierTwo" then
                            -- Tier 1 + Tier 2 could form Tier 3
                            potentialScore = potentialScore + 1000
                            print("DEBUG: CASCADE POTENTIAL +1000 for Tier 1 + Tier 2 = Tier 3 at", row, col, "with", adjacentAsset.type, "bubbleType", adjacentAsset.bubbleType)
                        elseif assetType == "tierTwo" and adjacentAsset.type == "tierOne" then
                            -- Tier 2 + Tier 1 could form Tier 3
                            potentialScore = potentialScore + 1000
                            print("DEBUG: CASCADE POTENTIAL +1000 for Tier 2 + Tier 1 = Tier 3 at", row, col, "with", adjacentAsset.type, "bubbleType", adjacentAsset.bubbleType)
                        end
                    end
                end
            end
        end
    end
    
    return potentialScore
end

-- Simulate what would happen if we removed a basic bubble (for cascade evaluation)
function PlacementSystem:simulateBasicRemovalMerge(basicAsset, bubbleState)
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
        
        if bubbleState:isValidCell(checkRow, checkCol) then
            local neighborId = bubbleState:getCellOccupant(checkRow, checkCol)
            if neighborId and neighborId ~= basicAsset.id then
                local neighbor = bubbleState.assets[neighborId]
                if neighbor and neighbor.type == "basic" and neighbor.bubbleType == basicAsset.bubbleType then
                    -- Found a same-type neighbor, check if removing basicAsset would enable a merge
                    -- Simplified check: count same-type neighbors excluding the asset being stomped
                    local sameTypeCount = self:countSameTypeNeighbors(neighbor.bubbleType, checkRow, checkCol, basicAsset.id, bubbleState)
                    
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
function PlacementSystem:countSameTypeNeighbors(bubbleType, startRow, startCol, excludeAssetId, bubbleState)
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
            
            local occupantId = bubbleState:getCellOccupant(current.row, current.col)
            if occupantId and occupantId ~= excludeAssetId then
                local asset = bubbleState.assets[occupantId]
                if asset and asset.type == "basic" and asset.bubbleType == bubbleType then
                    count = count + 1
                    
                    -- Add neighbors to queue
                    for _, dir in ipairs(directions) do
                        local checkRow = current.row + dir[1]
                        local checkCol = current.col + dir[2]
                        local checkKey = checkRow .. "," .. checkCol
                        
                        if bubbleState:isValidCell(checkRow, checkCol) and not visited[checkKey] then
                            table.insert(queue, {row = checkRow, col = checkCol})
                        end
                    end
                end
            end
        end
    end
    
    return count
end

-- Analyze placement conflicts at a specific position
function PlacementSystem:analyzePlacement(assetType, row, col, bubbleState)
    -- Get all cells this asset would occupy
    local patternCells = bubbleState:findPatternCells(assetType, row, col)
    if not patternCells or #patternCells == 0 then
        return nil
    end
    
    -- Check for conflicts with existing assets
    local conflicts = {
        basic = {},
        tierOne = {},
        tierTwo = {},
        tierThree = {}
    }
    
    local totalConflicts = 0
    
    for _, cellInfo in ipairs(patternCells) do
        local occupantId = bubbleState:getCellOccupant(cellInfo.row, cellInfo.col)
        if occupantId then
            local occupant = bubbleState.assets[occupantId]
            if occupant then
                table.insert(conflicts[occupant.type], occupantId)
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

-- Get all conflicting asset IDs from conflict structure
function PlacementSystem:getAllConflictingAssets(conflicts)
    local allAssets = {}
    for tierType, assetIds in pairs(conflicts) do
        for _, assetId in ipairs(assetIds) do
            table.insert(allAssets, assetId)
        end
    end
    return allAssets
end

-- Check if a placement would fit within screen bounds
function PlacementSystem:isWithinScreenBounds(assetType, row, col, bubbleState)
    local patternCells = bubbleState:findPatternCells(assetType, row, col)
    if not patternCells then return false end
    
    for _, cell in ipairs(patternCells) do
        if not bubbleState:isValidCell(cell.row, cell.col) then
            return false
        end
    end
    return true
end

-- Filter out unacceptable placements based on asset type rules
function PlacementSystem:filterAcceptablePlacements(placements, assetType)
    local filtered = {}
    
    for _, placement in ipairs(placements) do
        local acceptable = true
        
        -- Tier 1 placement rules
        if assetType == "tierOne" then
            -- Absolutely refuse any placement that would stomp Tier 1+ bubbles
            if #placement.conflicts.tierOne > 0 or 
               #placement.conflicts.tierTwo > 0 or 
               #placement.conflicts.tierThree > 0 then
                acceptable = false
            end
        elseif assetType == "tierTwo" then
            -- Tier 2 can stomp basic and Tier 1, but not Tier 2+
            if #placement.conflicts.tierTwo > 0 or 
               #placement.conflicts.tierThree > 0 then
                acceptable = false
            end
        elseif assetType == "tierThree" then
            -- For Tier 3, prioritize staying on screen over stomping rules
            if placement.withinBounds then
                -- If on-screen, can stomp basic, Tier 1, and Tier 2, but not other Tier 3
                if #placement.conflicts.tierThree > 0 then
                    acceptable = false
                end
            else
                -- If off-screen, reject this placement entirely
                acceptable = false
            end
        end
        
        if acceptable then
            table.insert(filtered, placement)
        end
    end
    
    print("DEBUG: Filtered", #placements, "placements down to", #filtered, "acceptable ones for", assetType)
    return filtered
end

-- Compare placement priority for final tiebreaking
function PlacementSystem:comparePlacementPriority(a, b, placingAssetType)
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
            return true
        elseif bBasicOnlyStomping and (a.totalConflicts == 0) then
            print("DEBUG: Tier 1 placement prefers stomping", #b.conflicts.basic, "basic bubbles over empty space")
            return false
        end
        
        -- Both are basic-only stomping or both are empty, prefer fewer stomps
        if aBasicOnlyStomping and bBasicOnlyStomping then
            return #a.conflicts.basic < #b.conflicts.basic
        end
    end
    
    -- (c) Higher tier placements: allow stomping of lower tiers
    if placingAssetType == "tierTwo" or placingAssetType == "tierThree" then
        local aAcceptableStomping = (#a.conflicts.tierTwo == 0) and (#a.conflicts.tierThree == 0)
        local bAcceptableStomping = (#b.conflicts.tierTwo == 0) and (#b.conflicts.tierThree == 0)
        
        if aAcceptableStomping and not bAcceptableStomping then
            return true
        elseif bAcceptableStomping and not aAcceptableStomping then
            return false
        end
    end
    
    -- If all else is equal, choose the one with fewer total conflicts
    return a.totalConflicts < b.totalConflicts
end

-- Generate positions at a specific distance from center
function PlacementSystem:getPositionsAtDistance(centerRow, centerCol, distance)
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

-- Check if a Tier 1 bubble would appear floating at this position
function PlacementSystem:wouldAppearFloating(assetType, row, col, bubbleState)
    if assetType ~= "tierOne" then return false end
    
    -- For Tier 1 bubbles, check if there are occupied cells below the visual footprint
    -- This prevents the triangular shape from appearing to float in mid-air
    
    local patternCells = bubbleState:findPatternCells(assetType, row, col)
    if not patternCells then return false end
    
    -- Find the bottommost row of the pattern
    local bottomRow = row
    for _, cell in ipairs(patternCells) do
        bottomRow = math.max(bottomRow, cell.row)
    end
    
    -- Check if there are any occupied cells in the row directly below the pattern
    local supportFound = false
    for _, cell in ipairs(patternCells) do
        if cell.row == bottomRow then
            -- Check cell directly below this pattern cell
            local belowRow = cell.row + 1
            if bubbleState:isValidCell(belowRow, cell.col) then
                if bubbleState:isCellOccupied(belowRow, cell.col) then
                    supportFound = true
                    break
                end
            else
                -- If we're at the bottom edge of the grid, that's support too
                supportFound = true
                break
            end
        end
    end
    
    return not supportFound
end

-- Get maximum nudge distance for different asset types
function PlacementSystem:getMaxNudgeDistance(assetType)
    if assetType == "basic" then
        return 1
    elseif assetType == "tierOne" then
        return 2
    elseif assetType == "tierTwo" then
        return 3
    elseif assetType == "tierThree" then
        return 5  -- Increased range for Tier 3 to find on-screen placement
    else
        return 1
    end
end

return PlacementSystem