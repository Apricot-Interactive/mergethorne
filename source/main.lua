import "CoreLibs/graphics"
import "states/menuState"
import "states/bubbleState"
import "states/towerState"
import "states/gameOverState"

local gfx <const> = playdate.graphics

-- Game state manager
local GameManager = {
    currentState = nil,
    states = {},
    gameData = {}
}

function GameManager:init()
    self.states = {
        menu = MenuState:new(),
        bubble = BubbleState:new(),
        tower = TowerState:new(),
        gameOver = GameOverState:new(),
        win = GameOverState:new()
    }
    
    self:setState("menu")
end

function GameManager:setState(stateName, data)
    if self.currentState then
        self.currentState:exit()
        
        if self.currentState.getGameData then
            local newData = self.currentState:getGameData()
            print("GameManager transferring data:")
            for k, v in pairs(newData) do
                if k == "flyoffTowers" then
                    print("  " .. k .. ": " .. #v .. " towers")
                else
                    print("  " .. k .. ": " .. tostring(v))
                end
            end
            -- Clear previous data to avoid stale keys
            self.gameData = {}
            -- Copy new data
            for k, v in pairs(newData) do
                self.gameData[k] = v
            end
        end
    end
    
    -- Clear game data when returning to menu for fresh start
    if stateName == "menu" then
        print("=== Returning to menu - clearing all game data ===")
        self.gameData = {}
    end
    
    self.currentState = self.states[stateName]
    if self.currentState then
        local dataToPass = data or self.gameData
        if stateName == "win" then
            dataToPass.isWin = true
        end
        self.currentState:enter(dataToPass)
    end
end

function GameManager:update()
    if self.currentState then
        local nextState = self.currentState:update()
        if nextState and nextState ~= self:getCurrentStateName() then
            self:setState(nextState)
        end
    end
end

function GameManager:draw()
    if self.currentState then
        self.currentState:draw()
    end
end

function GameManager:getCurrentStateName()
    for name, state in pairs(self.states) do
        if state == self.currentState then
            return name
        end
    end
    return "unknown"
end

-- Initialize the game
GameManager:init()

function playdate.update()
    GameManager:update()
    GameManager:draw()
end
