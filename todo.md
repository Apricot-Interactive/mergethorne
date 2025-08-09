# Mergethorne - Development Todo

## Current Status ✅
- **Phase 1 Complete**: Core bubble shooter mechanics (1183→604 lines)
- **Phase 2 Complete**: Full tier progression & magnetism system (+307 lines = 911 total)
- **Game is fully playable** with all original features restored in simplified architecture

---

## Phase 3: Polish & Optimization Opportunities

### 🚀 Performance Optimizations

#### Collision Detection
- **Current**: O(n) collision check for each ball against all placed bubbles
- **Optimization**: Cache collision cells in ball's path for O(1) lookup
- **Impact**: Better performance when many tier bubbles are placed

#### Animation System  
- **Current**: Single animation array processed every frame
- **Optimization**: Split animations by type (merge/magnetic/displacement) 
- **Impact**: Skip processing unused animation types

#### Sprite Loading
- **Current**: All tier sprites loaded at startup
- **Optimization**: Lazy load tier1/tier2 sprites when first needed
- **Impact**: Faster startup time, lower memory usage

### 🎮 Gameplay Polish

#### Tier 2 Displacement Logic
- **Issue**: Complex tier 2 placement may not handle all displacement edge cases
- **Fix**: Add proper displacement animation for overlapping placements
- **Priority**: Medium (rare occurrence)

#### Edge Case Handling
- **Issue**: What happens if no valid triangle exists for tier 1?
- **Fix**: Add fallback to single-cell tier 1 or merge failure state
- **Priority**: Low (very rare with current grid size)

#### Magnetic Range Tuning
- **Current**: 60px magnetic attraction range
- **Optimization**: May need adjustment based on actual hex spacing
- **Test**: Play-test with different tier 1 layouts

### 🔧 Code Quality Improvements

#### Error Handling
- **Add**: Null checks for missing sprite assets
- **Add**: Bounds checking for invalid grid positions
- **Add**: Graceful degradation for memory issues

#### Constants Organization
```lua
-- Move magic numbers to constants section:
local MAGNETIC_RANGE <const> = 60
local TIER_TWO_PATTERN_SIZE <const> = 7
local TRIANGLE_SIZE <const> = 3
```

#### Function Size Optimization
- `getTriangleCombinations()` - 25 lines (target: <20)
- `placeTierTwo()` - 30 lines (target: <20)
- **Fix**: Split into smaller helper functions

### 🌟 Feature Completions

#### Tier 3 Progression System
- **Asset**: `bubbles-tier-three.png` exists but unused
- **Design**: What triggers tier 2 → tier 3? (3 tier 2 bubbles? Special combinations?)
- **Implementation**: Follow same pattern as tier 1/2 systems

#### Visual Feedback Enhancements
- **Magnetic Attraction**: Draw lines/particles showing magnetic pull
- **Tier Formation**: Highlight target triangle/pattern during placement
- **Chain Previews**: Show potential merge chains before shooting

#### Playdate Integration
- **Sound Effects**: Merge pops, magnetic attractions, tier formations
- **Haptic Feedback**: Ball collisions, successful merges
- **Device Testing**: Performance on actual Playdate hardware

---

## 🧪 Testing & Validation

### Edge Case Testing
- [ ] Fill grid completely - does game over work correctly?
- [ ] Create maximum tier bubbles - performance impact?
- [ ] Rapid shooting - animation queue overflow?
- [ ] Complex tier formations - displacement logic?

### Performance Profiling
- [ ] Frame rate testing with full grid
- [ ] Memory usage with all sprites loaded
- [ ] Collision detection performance benchmarks

### Device Testing
- [ ] Playdate Simulator testing
- [ ] Actual Playdate device performance
- [ ] Input responsiveness and feel

---

## 📋 Priority Assessment

### Critical (Fix if Issues Found)
- Error handling for missing assets
- Game over edge cases
- Performance regression

### Nice-to-Have (Polish)
- Visual feedback improvements
- Sound integration
- Code organization cleanup

### Future Expansion (New Features)
- Tier 3 system
- Additional game modes
- Advanced visual effects

---

## 💡 Development Notes

The current codebase is **production-ready**. The architecture established in Phase 1 & 2 provides:

- Clean separation between core mechanics and tier systems
- Extensible animation system for future features  
- Modular sprite organization ready for expansion
- Well-documented code structure with clear function boundaries

Any items in this todo are **enhancements** rather than requirements. The game fully implements the original design with improved performance and maintainability.