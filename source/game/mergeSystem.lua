-- Merge System: handles bubble merge detection, execution, and combination rules
-- Extracted from bubbleState.lua for better code organization

-- Self-contained merge system with no external dependencies

MergeSystem = {}

function MergeSystem:new()
    local system = {}
    setmetatable(system, self)
    self.__index = self
    return system
end

-- Main entry point for merge detection
function MergeSystem:checkForMerges(placedAsset, bubbleState, cascadeSystem)
    if not placedAsset then return nil end
    
    -- Check for different types of merges based on the placed asset
    if placedAsset.type == "basic" and placedAsset.bubbleType >= 1 and placedAsset.bubbleType <= 5 then
        return self:checkForBasicMerges(placedAsset, bubbleState)
    elseif placedAsset.type == "tierOne" and placedAsset.bubbleType >= 6 and placedAsset.bubbleType <= 10 then
        return self:checkForTierTwoMerges(placedAsset, cascadeSystem or bubbleState.cascadeSystem, bubbleState)
    elseif placedAsset.type == "tierTwo" and placedAsset.bubbleType >= 11 and placedAsset.bubbleType <= 20 then
        return self:checkForTierThreeMerges(placedAsset, cascadeSystem or bubbleState.cascadeSystem, bubbleState)
    end
    
    return nil
end

-- Check for basic bubble merges (3+ basic → Tier 1)
function MergeSystem:checkForBasicMerges(placedAsset, bubbleState)
    if not placedAsset or placedAsset.type ~= "basic" then return nil end
    
    -- Find all connected bubbles of the same type as the placed bubble
    local connectedBubbles = bubbleState:findAdjacentBubbles(
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
        print("DEBUG: Placed bubble not in connected group, adding it")
        table.insert(connectedBubbles, {
            row = placedAsset.anchorRow,
            col = placedAsset.anchorCol,
            asset = placedAsset,
            distanceFromShot = 0
        })
    end
    
    print("DEBUG: Placed bubble", placedAsset.id, "is included in connected group of", #connectedBubbles, "bubbles")
    
    -- Check if we have enough bubbles for a merge (3 or more)
    if #connectedBubbles >= 3 then
        -- Convert basic type to corresponding Tier 1 type (1→6, 2→7, 3→8, 4→10, 5→9)
        local elementToTier1 = {
            [1] = 6,   -- Fire → Flame
            [2] = 7,   -- Water → Rain  
            [3] = 8,   -- Earth → Tremor
            [4] = 10,  -- Lightning → Shock
            [5] = 9    -- Wind → Gust
        }
        
        local tierOneBubbleType = elementToTier1[placedAsset.bubbleType]
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

-- Check for Tier 2 merges (Tier 1 + Tier 1 = Tier 2, or Tier 2 + Tier 1 = Tier 3)
function MergeSystem:checkForTierTwoMerges(placedAsset, cascadeSystem, bubbleState)
    if not placedAsset or placedAsset.type ~= "tierOne" then return nil end
    
    print("DEBUG: Checking for Tier 2 merges with placed", placedAsset.type, "type", placedAsset.bubbleType, "at", placedAsset.anchorRow, placedAsset.anchorCol)
    
    -- Find all adjacent tier 1 bubbles that can combine with this one
    local adjacentTierOnes = cascadeSystem:findAdjacentTierOneBubbles(placedAsset.anchorRow, placedAsset.anchorCol, bubbleState)
    
    -- ALSO find adjacent tier 2 bubbles for potential Tier 3 combinations
    local adjacentTierTwos = cascadeSystem:findAdjacentTierTwoBubbles(placedAsset.anchorRow, placedAsset.anchorCol, bubbleState)
    
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

-- Check for Tier 3 merges (Tier 2 + Tier 1 = Tier 3)
function MergeSystem:checkForTierThreeMerges(placedAsset, cascadeSystem, bubbleState)
    if not placedAsset or placedAsset.type ~= "tierTwo" then return nil end
    
    print("DEBUG: Checking for Tier 3 merges with placed", placedAsset.type, "type", placedAsset.bubbleType)
    
    -- Find all adjacent tier 1 bubbles that can combine with this tier 2
    local adjacentTierOnes = cascadeSystem:findAdjacentTierOneBubbles(placedAsset.anchorRow, placedAsset.anchorCol, bubbleState)
    
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
    
    print("DEBUG: No Tier 3 merges found")
    return nil
end

-- Execute a merge by removing bubbles and placing the new one
function MergeSystem:executeMerge(mergeInfo, bubbleState, placementSystem)
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
        
        -- Calculate distances before selection
        local shotBubble = mergeInfo.placedBubble
        local shotCell = bubbleState:getCellAtRowCol(shotBubble.row, shotBubble.col)
        for _, bubble in ipairs(mergeInfo.bubblesToRemove) do
            local bubbleCell = bubbleState:getCellAtRowCol(bubble.row, bubble.col)
            if shotCell and bubbleCell then
                bubble.distanceFromShot = (shotCell.x - bubbleCell.x)^2 + (shotCell.y - bubbleCell.y)^2
            else
                bubble.distanceFromShot = 9999  -- Fallback for invalid cells
            end
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
    
    -- Distances already calculated above for Tier 1 merges
    
    -- Find the bubble that's furthest forward (closest to bottom of screen)
    local targetBubble = nil
    local maxRow = -1
    
    for _, bubble in ipairs(allConnectedBubbles) do
        if bubble.row > maxRow then
            maxRow = bubble.row
            targetBubble = bubble
        elseif bubble.row == maxRow then
            -- If same row, prefer the one with smaller distance from shot
            if not targetBubble or bubble.distanceFromShot < targetBubble.distanceFromShot then
                targetBubble = bubble
            end
        end
    end
    
    local targetRow = targetBubble and targetBubble.row or shotBubble.row
    local targetCol = targetBubble and targetBubble.col or shotBubble.col
    
    -- Adjust anchor position for multi-cell assets
    local assetTypeForAdjustment = mergeInfo.resultTier or "tierOne"
    local adjustedRow, adjustedCol = self:adjustAnchorForFrontPlacement(
        assetTypeForAdjustment, targetRow, targetCol
    )
    
    print("DEBUG: Target front position at", targetRow, targetCol, "-> anchor at", adjustedRow, adjustedCol, "for new bubble type", mergeInfo.newBubbleType)
    
    -- Remove the selected bubbles first
    for _, bubble in ipairs(selectedBubbles) do
        bubbleState:removeAsset(bubble.asset.id)
    end
    
    -- Determine the asset type and sprite index for the new bubble
    local newAssetType, newBubbleIndex = self:getAssetTypeAndIndex(mergeInfo.newBubbleType, mergeInfo.resultTier)
    
    -- Try to place the new bubble with placement system
    -- IMPORTANT: Use the actual bubble type, not the sprite index!
    local shotRow = mergeInfo.placedBubble and mergeInfo.placedBubble.row or nil
    local shotCol = mergeInfo.placedBubble and mergeInfo.placedBubble.col or nil
    print("DEBUG: Shot location for placement:", shotRow or "none", shotCol or "none")
    if mergeInfo.placedBubble then
        print("DEBUG: placedBubble data:", mergeInfo.placedBubble.row, mergeInfo.placedBubble.col, "asset:", mergeInfo.placedBubble.asset and mergeInfo.placedBubble.asset.id or "none")
    end
    
    local placedAsset = placementSystem:placeAssetWithNudge(
        newAssetType, 
        mergeInfo.newBubbleType,  -- Use the full bubble type (6-10, 11-20, 21-30)
        adjustedRow, 
        adjustedCol, 
        3,  -- Maximum nudge distance
        shotRow,  -- shot location for better placement priority
        shotCol,
        bubbleState  -- Pass bubbleState for asset creation
    )
    
    if not placedAsset then
        print("DEBUG: Failed to place merged bubble, despawning")
        return false
    end
    
    print("DEBUG: Successfully merged bubbles into", newAssetType, "bubbleType", mergeInfo.newBubbleType, "spriteIndex", newBubbleIndex)
    return placedAsset
end

-- Select 3 bubbles for a basic merge (shot + 2 closest)
function MergeSystem:selectBubblesForMerge(connectedBubbles, shotBubble)
    if #connectedBubbles < 3 then
        return nil
    end
    
    -- Sort by distance from shot
    table.sort(connectedBubbles, function(a, b)
        return a.distanceFromShot < b.distanceFromShot
    end)
    
    -- The shot bubble should be first (distance 0), then get next 2 closest
    local selected = {}
    for i = 1, 3 do
        table.insert(selected, connectedBubbles[i])
        print("DEBUG: Selected", i, "bubbles for merge:", connectedBubbles[i].asset.id)
    end
    
    return selected
end

-- Get Tier 2 combination result from two Tier 1 types
function MergeSystem:getTierTwoCombination(type1, type2)
    -- Check all possible combinations from constants
    local combinations = {
        ["6-7"] = 11,   -- Flame + Rain = Steam
        ["7-6"] = 11,   -- Rain + Flame = Steam
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
function MergeSystem:getTierThreeCombination(tier2Type, tier1Type)
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
function MergeSystem:getAssetTypeAndIndex(bubbleType, resultTier)
    local assetType, spriteIndex
    
    if resultTier == "tierOne" then
        assetType = "tierOne"
        -- Map bubble types 6-10 to sprite indices 1-5
        local tierOneMapping = {[6]=1, [7]=2, [8]=3, [9]=4, [10]=5}
        spriteIndex = tierOneMapping[bubbleType] or 1
    elseif resultTier == "tierTwo" then
        assetType = "tierTwo"
        -- Map bubble types 11-20 to sprite indices 1-10
        spriteIndex = bubbleType - 10
    elseif resultTier == "tierThree" then
        assetType = "tierThree"
        -- Map bubble types 21-30 to sprite indices 1-10
        spriteIndex = bubbleType - 20
    else
        assetType = "basic"
        spriteIndex = bubbleType
    end
    
    return assetType, spriteIndex
end

-- Adjust anchor position for front placement of multi-cell assets
function MergeSystem:adjustAnchorForFrontPlacement(assetType, targetFrontRow, targetFrontCol)
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
    
    return targetFrontRow, targetFrontCol
end

-- MergeSystem is now available globally