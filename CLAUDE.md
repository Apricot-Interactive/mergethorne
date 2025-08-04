# Towers of Mergethorne - Architecture Documentation

## Game Overview
Towers of Mergethorne is a hybrid bubble shooter + tower defense game for Playdate. Players alternate between bubble shooting phases and tower defense phases across 3 levels.

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

### Phase 2: Bubble Shooter Core ✓
- [x] Grid collision and placement
- [x] Bubble shooting mechanics with preview system
- [x] Merge detection and logic
- [x] Starting array generation (optimized placement)
- [x] Level progression with transition system

### Phase 3: Tower Defense Core ✓
- [x] Tower conversion from elite bubbles
- [x] Creep spawning and movement
- [x] Tower targeting and shooting
- [x] Base damage system

### Phase 4: Polish & Integration ✓
- [x] Sprite sheets and graphics
- [x] Transition system with visual continuity
- [x] UI polish and state management
- [x] Game balance and testing
- [x] Performance optimization

## Technical Notes

### Performance Considerations
- Use object pools for frequently created/destroyed objects
- Minimize table creation in update loops
- Pre-calculate common math operations
- Limit active objects (50 bubbles, 20 creeps, 10 towers max)

### Input Handling
- Menu: D-pad navigation, A to select
- Bubble phase: Up/Down for aiming, Crank for vertical shooter movement, A to shoot
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
**GAME COMPLETE** - Full hybrid bubble shooter + tower defense game with seamless transitions between phases. All core mechanics implemented including:
- Complete bubble shooter with merge system and strategic shooting
- Full tower defense with converted merged balls as towers
- Bidirectional transition system with visual continuity
- Clean UI with proper state management
- Precise position preservation across phases

## Recent Major Implementations

### Complete Transition System ✓
- **Bubble → Tower Defense**: 20-frame wait after final shot → despawn basic balls → 20-frame wait → tower phase
- **Tower Defense → Bubble**: Preserve merged ball positions → 20-frame delay → show new basic bubbles
- **Visual Continuity**: Towers use same sprites as merged balls, exact position preservation
- **State Management**: Proper reset after game over/victory, clean separation of game sessions

### Advanced Features ✓
- **UI Polish**: Hidden elements during transitions, no visual pop-in, clean interfaces
- **Improved Gameplay**: More generous hit detection (5px smaller) for strategic shots
- **Smart Positioning**: UI flip logic for low shooter positions, dynamic element placement
- **Performance**: Optimized bubble placement, efficient state handling, precise coordinate storage

### Core Game Systems ✓
- **Bubble Mechanics**: Preview system, merge detection, strategic shooting, crank controls
- **Tower Defense**: Converted merged balls as towers, creep spawning, auto-targeting, base defense
- **Level Progression**: 3 levels with increasing difficulty, win/lose conditions, menu integration