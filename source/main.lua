-- Mergethorne - Phase 1: Simplified bubble shooter with hex grid
-- Architecture: Clean game loop with separated input, update, and render phases
-- Designed for Phase 2 expansion: tier systems and magnetic mechanics

import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Grid = import "game/grid"

Grid:init()

function pd.update()
    Grid:handleInput()
    Grid:update()
    
    gfx.clear()
    Grid:draw()
end