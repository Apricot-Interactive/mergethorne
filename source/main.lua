import "CoreLibs/graphics"
import "states/menuState"
import "states/bubbleState"

local pd <const> = playdate
local gfx <const> = pd.graphics

local GameManager = {
    currentState = nil,
    states = {}
}

function GameManager:init()
    self.states = {
        menu = MenuState:new(),
        bubble = BubbleState:new()
    }
    
    self:setState("menu")
end

function GameManager:setState(stateName)
    if self.currentState then
        self.currentState:exit()
    end
    
    self.currentState = self.states[stateName]
    if self.currentState then
        self.currentState:enter()
    end
end

function GameManager:update()
    if self.currentState then
        local nextState = self.currentState:update()
        if nextState then
            self:setState(nextState)
        end
    end
end

function GameManager:draw()
    if self.currentState then
        self.currentState:draw()
    end
end

GameManager:init()

function pd.update()
    GameManager:update()
    GameManager:draw()
end
