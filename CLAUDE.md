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
- **Basic Bubbles (1-5)**: Fire, Air, Earth, Lightning, Water (15x15px sprites)
- **Elite Bubbles (6-10)**: Stronger versions that become regular towers in TD phase  
- **Tier 1 Bubbles (11-15)**: Advanced triangular bubbles that occupy 3 cells, become powerful towers
- **Merging**: 3+ basic bubbles merge into corresponding Tier 1 (Fire→Fire Tier 1, etc.)

### Game Constants  
- Grid: 26x17 cells, hex layout with 15px bubble diameter
- Shots per level: 10
- Base HP: 100
- Max levels: 3
- Bubble types: 5 basic + 5 elite + 5 Tier 1

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

## Advanced Tier 1 System ✓

### Tier 1 Bubble Mechanics
- **Merge Trigger**: 3 matching basic bubbles merge into corresponding Tier 1 bubble
- **Element Mapping**: Fire(1)→Fire Tier 1(11), Air(2)→Air Tier 1(14), Earth(3)→Earth Tier 1(13), Lightning(4)→Lightning Tier 1(15), Water(5)→Water Tier 1(12)
- **Multi-cell Occupation**: Each Tier 1 occupies 3 cells in triangular hex pattern
- **Smart Configuration**: Configuration A/B selection based on merge shape and positioning

### Configuration System
- **Configuration A**: Horizontal line on top, point below left (sprite indices 1-5)
- **Configuration B**: Horizontal line on top, point below right (sprite indices 6-10)
- **Intelligent Selection**: Analyzes center of mass of merged bubbles to choose optimal configuration
- **Position Optimization**: Smart nudging system finds legal placement if preferred spot conflicts

### Advanced Collision & Placement
- **Hierarchical Rules**: Tier 1 can overwrite basic bubbles but not elite/Tier 1 bubbles
- **Complete Overlap Detection**: Prevents overlapping with existing Tier 1 footprints
- **Cached Performance**: O(1) collision detection using cached occupied cell lookups
- **Safe Merging**: Always clears all matched bubbles even if final placement differs

### Tower Integration  
- **Enhanced Power**: Tier 1 towers deal double damage compared to elite towers
- **Visual Preservation**: Maintain triangular appearance throughout bubble↔tower transitions
- **State Persistence**: Perfect restoration across level transitions with metadata preservation
- **Sprite Alignment**: Precise 30x27px sprite positioning for grid-perfect alignment

## Performance Optimizations ✓

### Major Performance Improvements
- **Tier 1 Cache System**: O(n³) → O(1) collision detection with cached occupied cells
- **Eliminated sqrt() Operations**: Use squared distance comparisons for faster placement
- **Pre-allocated Direction Tables**: Avoid table creation in merge detection loops  
- **Optimized Grid Traversal**: Smart availability checking with early exit conditions
- **Fixed Memory Leaks**: Proper bubble state preservation during match testing

### Device Performance
- **Eliminated Frame Lag**: Resolved multi-frame delays when balls stop moving
- **Smooth Collision Detection**: Near-instantaneous bubble placement and merge detection
- **Efficient State Transitions**: Fast level switching with proper cache management
- **Memory Optimized**: Minimal garbage collection with reused data structures

## Testing Process
**Build Command**: `pdc source towers_of_mergethorne.pdx` (user handles build and testing)
**Testing Notes**: User performs builds and gameplay testing to verify fixes

## Current Status: DEBUG MODE IMPLEMENTATION ⚠️
**Debug mode with Tier 2 bubble system** - core mechanics working but needs refinement:

### Recent Major Fixes Applied ✓
- **Fixed Invisible Bubbles**: Tier 1 and Tier 2 projectiles now properly occupy footprints and set anchor/center flags
- **Fixed Self-Merging**: Tier 1 bubbles no longer merge with their own footprint cells
- **Fixed Coordinate System**: Separated screen vs grid coordinate drawing functions
- **Expanded Tier 2 Search**: Systematic radial placement algorithm prevents merge failures
- **Reduced Debug Spam**: Cleaned up excessive logging for manageable output

### Current Issues Remaining 🔧
- **Tier 2 Visibility**: Some Tier 2 bubbles still not rendering correctly
- **Spacing Problems**: Tier 1 bubbles have inconsistent grid alignment and spacing
- **Overlap Issues**: Some bubbles placing inside/overlapping existing ones

### Debug Mode Status
- **Working**: Tier 1 placement, basic merging, tower conversion, level progression
- **Partial**: Tier 2 visibility (sometimes works, sometimes doesn't)
- **Needs Work**: Perfect grid alignment, consistent spacing, overlap prevention

### Next Session Priorities
1. Fix remaining Tier 2 rendering issues
2. Perfect Tier 1 grid alignment and spacing
3. Eliminate all bubble overlapping
4. Final polish and testing