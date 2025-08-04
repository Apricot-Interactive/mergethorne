# Mergeria - Architecture Documentation

## Game Overview
Mergeria is a hybrid bubble shooter + tower defense game for Playdate. Players alternate between bubble shooting phases and tower defense phases across 3 levels.

### Game Flow
1. **Main Menu**: Simple menu with "Play" option
2. **Bubble Phase**: Shoot bubbles right-to-left into a grid. Matching 3+ bubbles merges them into stronger types. Limited shots per level.
3. **Tower Phase**: Elite bubbles become towers, creeps spawn and move toward the player's base. Towers auto-attack.
4. **Progression**: After completing both phases, advance to next level. Complete 3 levels to win.

## Architecture

### File Structure
```
source/
├── main.lua                    # Entry point with GameManager state machine
├── states/                     # Game state management
│   ├── menuState.lua          # Main menu with navigation
│   ├── bubbleState.lua        # Bubble shooter gameplay
│   ├── towerState.lua         # Tower defense gameplay
│   └── gameOverState.lua      # Win/lose screens
├── game/                      # Core game logic
│   ├── grid.lua               # Grid system + bubble management + shooting
│   ├── towers.lua             # Tower system + tower objects + targeting
│   ├── creeps.lua             # Creep system + spawning + pathfinding
│   └── projectiles.lua        # Reusable projectile system
├── utils/                     # Utilities and configuration
│   ├── constants.lua          # Game constants and configuration
│   └── helpers.lua            # Math, collision, and utility functions
└── assets/                    # Game assets
    ├── sprites/               # Sprite sheets for bubbles, towers, UI
    └── sounds/                # Sound effects
```

### Key Design Decisions

1. **State Machine**: Clean separation between game phases using a simple state manager in main.lua
2. **Entity + System Hybrid**: Combined entity definitions with their management systems for simplicity
3. **Grid-Centric**: The grid system handles both bubble placement and tower conversion
4. **Performance Focus**: Object pooling, minimal garbage collection, integer math where possible

### Bubble Types
- **Basic Bubbles (1-5)**: Red, Blue, Green, Yellow, Purple
- **Elite Bubbles (6-10)**: Stronger versions that become towers in TD phase
- **Merging**: 3+ matching bubbles merge into the next tier

### Game Constants
- Grid: 12x8 cells, 30px cell size
- Shots per level: 10
- Base HP: 100
- Max levels: 3
- Bubble types: 5 basic + 5 elite

## Development Phases

### Phase 1: Foundation ✓
- [x] State manager and state classes
- [x] Main menu with navigation
- [x] Basic file structure

### Phase 2: Bubble Shooter Core
- [ ] Grid collision and placement
- [ ] Bubble shooting mechanics
- [ ] Merge detection and logic
- [ ] Level progression

### Phase 3: Tower Defense Core  
- [ ] Tower conversion from elite bubbles
- [ ] Creep spawning and movement
- [ ] Tower targeting and shooting
- [ ] Base damage system

### Phase 4: Polish & Integration
- [ ] Sprite sheets and graphics
- [ ] Sound effects
- [ ] Game balance and testing
- [ ] Performance optimization

## Technical Notes

### Performance Considerations
- Use object pools for frequently created/destroyed objects
- Minimize table creation in update loops
- Pre-calculate common math operations
- Limit active objects (50 bubbles, 20 creeps, 10 towers max)

### Input Handling
- Menu: D-pad navigation, A to select
- Bubble phase: Up/Down for aiming, A to shoot
- Tower phase: Passive observation

### Memory Management
- Clear unused objects between state transitions
- Reuse textures between game phases
- Use local variables in tight loops
- Efficient sprite batching

### Art Pipeline Requirements
- **Transparency**: Use magenta (RGB 255, 0, 255) for transparent pixels in all sprites
- **Format**: PNG format, the Playdate SDK automatically converts magenta to transparency
- **Sprite Sheets**: 30x30 pixel sprites arranged horizontally in bubbles.png
- **No manual masking needed**: SDK handles transparency conversion during build process

## Screenshots Reference
Screenshots are stored in `.sshots/` directory for development reference in .png format
- Future screenshots can be added and will be accessible for development guidance

## Current Status
Hex grid system implemented. Updating proportions and spacing to match prototype design. Ready to refine visual layout and implement core bubble shooter mechanics.