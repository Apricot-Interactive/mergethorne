import "CoreLibs/graphics"

local pd <const> = playdate
local gfx <const> = pd.graphics
local Grid = import "game/grid"

Grid:init()

function pd.update()
    Grid:handleInput()
    Grid:updateBall()
    
    gfx.clear()
    Grid:draw()
end