# Mergethorne - Development Guide

## 🤖 AI Development Guidelines

**CRITICAL READING**: This section contains essential information for AI assistants working on Mergethorne. Read this thoroughly before making any code changes.

### Core Development Principles

1. **Animation-Driven Architecture**: Most game state changes happen through animation completion, not immediate updates. Always check `self.isAnimating` before major state changes.

2. **State Consistency**: The game uses multiple interconnected state tables (cells, tierOnePositions, tierTwoPositions, troops, creeps). Changes to one often require updates to others.

3. **Rally Point Integrity**: Troops must always have valid rally points. When modifying troop systems, ensure rally point assignment logic remains intact.

4. **Coordinate System Awareness**: 
   - Grid indices: 1-300 (hex grid cells)
   - Pixel coordinates: Actual screen positions
   - Always convert properly between systems

### Common AI Modification Patterns

#### Adding New Tier Combinations
1. Update `MergeConstants.lua` with new sprite mappings
2. Modify magnetic detection logic in `checkMagneticCombinations()`
3. Add corresponding troop spawning behavior
4. Test thoroughly with tier progression flow

#### Modifying Troop Behavior
1. Focus on rally point assignment in `getBubbleRallyPoint()` and `findNearestRallyPoint()`
2. Update movement states in `updateTroops()`
3. Ensure troop transfer logic in `transferTroopsToNewRally()` handles new cases
4. Test with bubble merging scenarios

#### Balancing Game Mechanics
1. Check constants at top of `grid.lua` first
2. Look for magic numbers in `MergeConstants.lua`
3. Consider animation timing effects on gameplay feel
4. Test with various bubble configurations

#### Adding New Animations
1. Add animation type to `updateAnimations()` function
2. Add rendering logic to `drawAnimations()` function  
3. Ensure proper cleanup when animation completes
4. Consider interaction with `self.isAnimating` flag

### Critical Areas (Modify with Extreme Care)

⚠️ **Collision Detection**: Visual collision uses pixel-perfect detection with buffers. Changes here affect core gameplay feel.

⚠️ **Animation State Management**: Corrupted animation state can break the entire game. Always ensure animations clean up properly.

⚠️ **Grid Boundary Logic**: The hex grid has complex cutout areas and permanent boundaries. Changes require extensive testing.

⚠️ **Rally Point Assignment**: Troops without valid rally points will cause runtime errors. Always ensure fallback logic.

### Testing Protocols for AI

When making changes, always test these scenarios:
1. Basic bubble merge → Tier 1 formation → Troop spawning
2. Tier 1 magnetic combination → Tier 2 formation → Troop transfer
3. Tier 2 + Tier 1 magnetic → Tier 3 flash → Despawn + troop rally
4. Combat cycles: Creep spawning, staging, marching
5. Troop rally behavior during bubble merges
6. Game over and restart functionality

### Function Modification Guidelines

#### High-Impact Functions (Test Extensively)
- `updateAnimations()` - Core animation state management
- `checkMagneticCombinations()` - Tier progression logic
- `spawnTroop()` - Troop creation and rally assignment
- `transferTroopsToNewRally()` - Bubble merge troop handling
- `updateTroops()` - Troop movement and state management

#### Safe-to-Modify Functions (Lower Risk)
- Rendering functions (`draw*()`) - Visual only, no game state
- Constants and configuration values
- Debug and UI functions
- Sprite loading and initialization

#### Debug Tools Available
- `self.debugView` - Toggle with Left D-pad, shows grid and boundaries
- Print statements - Use sparingly, check performance impact
- Animation frame counters - Monitor animation timing

### Data Flow Understanding

**Bubble Lifecycle**: Basic → Merge Detection → Tier 1 Creation → Magnetic Detection → Tier 2/3 Formation → Troop Spawning → Rally Assignment

**Troop Lifecycle**: Spawn → Rally Assignment → Movement to Rally → Clustered → March Signal → March Formation → Off-screen

**Combat Cycle**: Shot Counter → Creep Spawn (cycle-based) → Staging → Hold → March (Shot 4) → Reset

### Common Pitfalls for AI

1. **Modifying game state during animations** - Always check `self.isAnimating`
2. **Breaking rally point chains** - Troops without rally points crash the game
3. **Coordinate system confusion** - Grid indices vs pixel coordinates
4. **Animation cleanup failure** - Leads to memory leaks and state corruption
5. **Ignoring boundary constraints** - Troops/creeps moving into invalid areas

## Project Overview

Mergethorne is a bubble shooter game for the Playdate console featuring hex grid mechanics and multi-tier bubble progression. The project underwent a complete architecture refactor to simplify and optimize the codebase while preserving all original functionality.

### Transformation Summary
- **Before**: 1,183 lines of complex, overlapping systems
- **After**: ~2800 lines with complete feature set including combat systems
- **Evolution**: Added tier progression, enemy creeps, allied troops, and unified collision
- **Performance**: Maintained 60fps stable gameplay with complex unit interactions

---

## Architecture Overview

### Phase 1: Core Simplification
Established the fundamental game architecture with clean separation of concerns:

```
main.lua (18 lines)     - Clean game loop: input → update → render
├── Grid:handleInput()  - D-pad aim, A button shoot
├── Grid:update()       - Ball physics, collision, merging  
└── Grid:draw()         - Visual rendering pipeline
```

### Phase 2: Tier Progression Systems
Extended the core with advanced bubble mechanics:

```
Basic Bubbles → Tier 1 → Tier 2 → Tier 3
    (3-merge)   (magnetic) (magnetic)
```

### Phase 3: Combat Systems
Added dynamic enemy and allied unit systems:

```
Enemy Creeps: Spawn → Stage → March (4-shot cycles)
Allied Troops: Spawn from tiers → Rally at 7,1 → March on shot 4
Unified Collision: All units respect 1px sprite buffers
```

### Key Design Principles
1. **Single Responsibility**: Each function handles one clear task
2. **Function Size Limit**: Target <20 lines per function
3. **Minimal Nesting**: Avoid deep conditional hierarchies
4. **Extensible Structure**: Ready for future feature expansion

---

## Core Systems Reference

### Grid System (`grid.lua`)
The unified cell structure supporting all bubble types:

```lua
cells[idx] = {
    ballType = 1-5,           -- Bubble color/type
    occupied = true/false,    -- Cell state
    permanent = true/false,   -- Boundary marker
    tier = "basic"/"tier1"/"tier2"  -- Progression level
}
```

### Coordinate System
- **20px hex circles** in 15 rows (odd=20 cols, even=19 cols)
- **Index formula**: `idx = (row-1) * 20 + col`
- **Shooter position**: `SHOOTER_IDX = 12 * 20 + 16` (bottom center)

### Boundary Areas
Three unplayable regions:
- **Left cutout**: Parabolic curve (cells 5,1 through 9,2)
- **Bottom boundary**: Rows 14-15, cols 1-16
- **Right boundary**: All rows, col 17+

---

## Tier Progression Flow

### Basic Tier (Starting State)
```
Shoot Ball → Collision → Grid Snap → Merge Check
                           ↓
             3+ Connected Same-Color → Merge Animation
```

### Tier 1 Creation
```
3+ Basic Merge → Center Point Calculation → Triangle Formation
    ↓
Find Best Triangle → Occupy 3 Cells → Render at Center Point
    ↓
Check Magnetic Range → Auto-Combine Different Types
```

### Tier 2 Formation  
```
2 Different Tier 1 Within 60px → Magnetic Attraction
    ↓
Remove Tier 1 Bubbles → Create Tier 2 at Midpoint
    ↓
Occupy 2-3-2 Pattern (7 cells) → Render Combination Sprite
```

### Combination Matrix
Tier 1 magnetic combinations create specific Tier 2 sprites:

| Type 1 + Type 2 | Result | Sprite |
|------------------|--------|---------|
| Fire + Water     | Steam  | 1       |
| Fire + Earth     | Magma  | 2       |
| Water + Earth    | Quicksand | 3    |
| Water + Wind     | Downpour | 4     |
| Earth + Wind     | Sandstorm | 5    |
| Earth + Lightning| Crystal | 6      |
| Fire + Wind      | Wild Fire | 7    |
| Wind + Lightning | Thunderstorm | 8 |
| Fire + Lightning | Explosion | 9    |
| Water + Lightning| Chain Lightning | 10 |

---

## Combat Systems Overview

### Enemy Creep System
Hostile units that spawn and march across the battlefield in coordinated waves:

```
Creep Cycle (4 shots):
Shot 1: 5x Basic creeps (3px collision) spawn at random staging positions (3,18 through 11,18)
Shot 2: 3x Tier 1 creeps (4px collision) spawn and march to staging points
Shot 3: 2x Tier 2 creeps (8px collision) spawn with enhanced capabilities  
Shot 4: All staged creeps march left off-screen, cycle resets
```

**Staging Positions**: Rows 3, 5, 7, 9, 11 at column 18 (right edge)
**Movement**: Spawn off-screen right → March to staging → Hold → March left off-screen

### Allied Troop System  
Friendly units spawned from tier bubbles that rally and march in formation:

```
Troop Spawning Rules:
- Every shot: All tier bubbles (T1/T2/T3) spawn corresponding troops
- Shots 2,6,10,etc: 1/3 of basic bubbles also spawn basic troops
- Shot 4: All troops march right off-screen in formation

Rally Behavior:
- Rally Point: Position 7,1 (left side of hex grid)
- Clustering: Tight hexagonal packing around rally point, respects screen boundaries
- March Formation: Fan out vertically across rows 1-13 for first 200px of march
```

**Collision System**: All units (troops/creeps) respect 1px sprite collision buffers
**Boundary Awareness**: Units stay within screen bounds, cluster forward/up/down when needed

---

## File Structure & Organization

```
mergethorne/
├── source/
│   ├── main.lua              # Game loop (18 lines)
│   ├── game/
│   │   ├── grid.lua          # Complete game logic (~1900 lines)
│   │   └── mergeConstants.lua # Tier combinations & sprite constants (120 lines)
│   ├── assets/
│   │   └── sprites/
│   │       ├── bubbles-basic.png     # 5 basic bubble types
│   │       ├── bubbles-tier-one.png  # 5 tier 1 variants
│   │       ├── bubbles-tier-two.png  # 10 tier 2 combination sprites
│   │       ├── bubbles-tier-three.png # 10 tier 3 combination sprites
│   │       ├── creeps-basic.png      # Enemy basic creeps
│   │       ├── creeps-tier-one.png   # Enemy tier 1 creeps
│   │       ├── creeps-tier-two.png   # Enemy tier 2 creeps
│   │       ├── troops-basic.png      # Allied basic troops
│   │       ├── troops-tier-one.png   # Allied tier 1 troops
│   │       ├── troops-tier-two.png   # Allied tier 2 troops
│   │       ├── troops-tier-three.png # Allied tier 3 troops
│   │       └── ref-grid.png          # Development reference
│   └── pdxinfo               # Playdate metadata
├── builds/                   # Compiled .pdx files
├── CLAUDE.md                 # This documentation
└── todo.md                   # Future development tasks
```

### Function Organization (grid.lua)
```
Lines 1-60:     Constants & sprite loading
Lines 61-120:   Sprite loading functions (Basic + Tier + Creep + Troop)
Lines 121-280:  Core game systems (init, grid, boundaries, game state)
Lines 281-430:  Input handling, ball physics & collision detection
Lines 431-685:  Merge detection, animations, and tier progression
Lines 686-1230:  Tier progression systems (T1 → T2 → T3)
Lines 1231-1513: Enemy creep systems (spawning, staging, marching)
Lines 1514-1900: Allied troop systems (spawning, rallying, collision)
Lines 1901-end:  Rendering pipeline (grid, balls, units, UI)
```

---

## Key Functions Reference

### Core Game Loop
- `Grid:init()` - Initialize all game systems
- `Grid:handleInput()` - Process D-pad and A button
- `Grid:update()` - Update ball physics and animations
- `Grid:draw()` - Render complete game state

### Ball Mechanics
- `Grid:shootBall()` - Create flying ball from shooter
- `Grid:checkBallCollision()` - Test collision with all bubble types
- `Grid:handleBallLanding()` - Place ball and check for merges

### Merge System
- `Grid:findMergeChain()` - Flood-fill algorithm for connected bubbles
- `Grid:startMergeAnimation()` - Animate balls converging to center
- `Grid:createTierOne()` - Convert merge point into Tier 1 bubble

### Tier Progression
- `Grid:checkMagneticCombinations()` - Detect Tier 1 pairs in range
- `Grid:createTierTwoCombination()` - Form Tier 2 from Tier 1 pair
- `MergeConstants.getTierTwoSprite()` - Lookup combination sprite from constants

### Constants & Configuration (`mergeConstants.lua`)
- `MergeConstants.BASIC_TYPES` - Elemental bubble type definitions
- `MergeConstants.TIER_2_COMBINATIONS` - Tier 1 + Tier 1 → Tier 2 matrix
- `MergeConstants.SPRITE_INFO` - Size and centering data for all tiers
- `MergeConstants.getSpriteOffset()` - Helper for consistent sprite positioning

### Rendering Pipeline
- `Grid:drawGrid()` - Debug view of hex grid
- `Grid:drawBoundaries()` - Cutout and boundary lines
- `Grid:drawBalls()` - All bubble types (basic/tier1/tier2)
- `Grid:drawAnimations()` - Active merge animations

---

## Development Notes & Decisions

### Performance Optimizations Made
1. **Visual Collision Detection**: Immediate grid snapping instead of complex physics
2. **Cached Aim Direction**: Precomputed cos/sin values for aiming
3. **Efficient Neighbor Search**: Hex grid neighbor algorithm optimized
4. **Animation Batching**: Single animation array with type-based processing

### Architecture Decisions
1. **Single Cell System**: Unified structure supports all bubble types
2. **Center-Point Rendering**: Tier bubbles render at calculated centers
3. **Triangle/Pattern Occupation**: Higher tiers occupy multiple cells
4. **Extensible Animation**: Queue-based system ready for new animation types

### Code Quality Standards
- **Comprehensive Comments**: Structure decisions documented at file/function level
- **Consistent Naming**: Clear, descriptive function and variable names
- **Error Prevention**: Bounds checking and null safety throughout
- **Modular Design**: Clean separation between core mechanics and advanced features
- **Constants Organization**: MergeConstants.lua centralizes tier combinations and sprite data

### Recent Quality Analysis (Phase 3)
- **Collision Detection**: Identified 6-10x optimization potential via collision caching
- **Magic Numbers**: Most hardcoded values moved to MergeConstants module
- **Performance Status**: 60fps target achieved, optimizations now polish-level priority
- **Architecture Maturity**: Codebase ready for feature expansion rather than structural changes

---

## Troubleshooting

### Common Issues

**Game runs slow/choppy**
- Check sprite loading - all assets should load successfully
- Verify collision detection isn't hitting edge cases with too many bubbles

**Tier bubbles not appearing**
- Ensure 3+ basic bubbles are connected before merging
- Check that triangle formation has available space near merge center

**Magnetic combinations not working**  
- Verify different tier 1 types are within 60px range
- Check that both tier 1 bubbles exist in `tierOnePositions` table

**Visual rendering issues**
- Confirm all sprite sheets exist in `assets/sprites/`
- Check that sprite loading doesn't fail silently

### Debug Commands
- **Left D-pad**: Toggle debug view (shows grid positions and boundaries)
- **Debug view**: Displays hex grid positions and permanent boundary cells

---

## Future Development

The current architecture is designed for easy expansion. See `todo.md` for detailed enhancement opportunities, including:

- **Tier 3 progression system** (sprites already available)
- **Visual feedback improvements** (magnetic attraction indicators)
- **Performance optimizations** (collision caching, lazy loading)
- **Playdate integration** (sound, haptics, device testing)

The codebase provides a solid foundation for these enhancements while maintaining the clean, efficient structure established during the refactor.
- User always runs build process and tests (instruct user, don't try to compile)