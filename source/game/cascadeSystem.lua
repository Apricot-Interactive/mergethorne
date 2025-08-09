-- Cascade System: handles cascade merge detection, timing, and adjacent bubble finding
-- Extracted from bubbleState.lua for better code organization

-- Self-contained cascade system with no external dependencies

CascadeSystem = {}

function CascadeSystem:new()
    local system = {
        cascadeQueue = {}
    }
    setmetatable(system, self)
    self.__index = self
    return system
end

-- Schedule a cascade merge check with 8-frame delay
function CascadeSystem:scheduleCascadeMerge(placedAsset)
    if not placedAsset then return end
    
    print("DEBUG: Scheduling cascade merge check for asset", placedAsset.id, "in 8 frames")
    
    -- Initialize cascade system if needed
    if not self.cascadeQueue then
        self.cascadeQueue = {}
    end
    
    -- Add to cascade queue with 8-frame delay
    table.insert(self.cascadeQueue, {
        asset = placedAsset,
        framesRemaining = 8
    })
end

-- Process cascade merges (call this in update loop)
function CascadeSystem:processCascadeMerges(mergeSystem, bubbleState)
    if not self.cascadeQueue or #self.cascadeQueue == 0 then
        return
    end
    
    -- Process each queued cascade merge
    for i = #self.cascadeQueue, 1, -1 do
        local cascadeItem = self.cascadeQueue[i]
        cascadeItem.framesRemaining = cascadeItem.framesRemaining - 1
        
        if cascadeItem.framesRemaining <= 0 then
            -- Time to check for cascade merge
            print("DEBUG: Checking cascade merge for asset", cascadeItem.asset.id)
            local cascadeMergeInfo = self:checkCascadeMerge(cascadeItem.asset, mergeSystem, bubbleState)
            
            if cascadeMergeInfo then
                print("DEBUG: Cascade merge found! Executing...")
                local newAsset = mergeSystem:executeMerge(cascadeMergeInfo, bubbleState, bubbleState.placementSystem)
                
                -- Schedule another cascade check for the newly placed asset
                if newAsset then
                    self:scheduleCascadeMerge(newAsset)
                end
            else
                print("DEBUG: No cascade merge found")
            end
            
            -- Remove from queue
            table.remove(self.cascadeQueue, i)
        end
    end
end

-- Check if a cascade merge is possible from a placed asset
function CascadeSystem:checkCascadeMerge(placedAsset, mergeSystem, bubbleState)
    if not placedAsset or not bubbleState.assets[placedAsset.id] then
        return nil  -- Asset was removed or doesn't exist
    end
    
    -- Use the merge system to check for merges
    return mergeSystem:checkForMerges(placedAsset, bubbleState, self)
end

-- Unified function to find adjacent bubbles of a specific tier
function CascadeSystem:findAdjacentBubblesOfTier(tierType, centerRow, centerCol, bubbleState)
    local adjacentBubbles = {}
    local directions = {
        {-1, -1}, {-1, 0}, {-1, 1},  -- Above row
        {0, -1},           {0, 1},   -- Same row
        {1, -1},  {1, 0},  {1, 1}    -- Below row
    }
    
    print("DEBUG: Looking for adjacent", tierType, "bubbles around", centerRow, centerCol)
    
    -- Get all cells occupied by the center asset
    local centerAssetId = bubbleState:getCellOccupant(centerRow, centerCol)
    local centerAsset = centerAssetId and bubbleState.assets[centerAssetId]
    
    if not centerAsset then
        print("DEBUG: No center asset found at", centerRow, centerCol, "for", tierType, "search")
        return adjacentBubbles
    end
    
    -- Check all cells that the center asset occupies
    local centerCells = centerAsset.patternCells or {{row = centerRow, col = centerCol}}
    
    for _, centerCell in ipairs(centerCells) do
        for _, dir in ipairs(directions) do
            local checkRow = centerCell.row + dir[1]
            local checkCol = centerCell.col + dir[2]
            
            if bubbleState:isValidCell(checkRow, checkCol) then
                local occupantId = bubbleState:getCellOccupant(checkRow, checkCol)
                if occupantId and occupantId ~= centerAssetId then
                    local asset = bubbleState.assets[occupantId]
                    if asset and asset.type == tierType then
                        -- Check if we already have this asset (avoid duplicates)
                        local alreadyAdded = false
                        for _, existing in ipairs(adjacentBubbles) do
                            if existing.asset.id == asset.id then
                                alreadyAdded = true
                                break
                            end
                        end
                        
                        if not alreadyAdded then
                            table.insert(adjacentBubbles, {
                                row = asset.anchorRow,
                                col = asset.anchorCol,
                                asset = asset,
                                distanceFromShot = math.abs(asset.anchorRow - centerRow) + math.abs(asset.anchorCol - centerCol)
                            })
                            print("DEBUG: Found adjacent", tierType, "bubble:", asset.bubbleType, "at", asset.anchorRow, asset.anchorCol)
                        end
                    end
                end
            end
        end
    end
    
    print("DEBUG: Found", #adjacentBubbles, "adjacent", tierType, "bubbles")
    return adjacentBubbles
end

-- Find adjacent Tier 1 bubbles for cascade detection
function CascadeSystem:findAdjacentTierOneBubbles(centerRow, centerCol, bubbleState)
    return self:findAdjacentBubblesOfTier("tierOne", centerRow, centerCol, bubbleState)
end

-- Find adjacent Tier 2 bubbles for potential Tier 3 combinations
function CascadeSystem:findAdjacentTierTwoBubbles(centerRow, centerCol, bubbleState)
    return self:findAdjacentBubblesOfTier("tierTwo", centerRow, centerCol, bubbleState)
end

-- Clear all cascade queues (for game reset)
function CascadeSystem:reset()
    self.cascadeQueue = {}
end

return CascadeSystem