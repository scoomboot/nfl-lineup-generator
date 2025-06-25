# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NFL lineup generator written in Zig, designed to optimize daily fantasy sports lineups using player projections data. The project follows standard Zig project structure with both library and executable components.

## Build System & Commands

### Core Commands
- `zig build` - Builds the project (both library and executable)
- `zig build run` - Builds and runs the executable
- `zig build test` - Runs all unit tests (both library and executable tests)
- `zig build run -- [args]` - Run with command line arguments

### Development Workflow
- Use `zig build test` to run tests before making changes
- The project builds both a static library (`libnfl_lineup_generator.a`) and an executable
- Built artifacts are placed in `zig-out/` directory

### Testing
```bash
# Run all unit tests (both library and executable modules)
zig build test

# Run with fuzzing
zig build test --fuzz

# Run tests for a specific file
zig test src/models/player.zig

# Run tests for a specific module directory
zig test src/models/models.zig

# Run tests with verbose output
zig test src/models/player.zig --verbose
```

## Architecture

### Project Structure
- **src/main.zig**: Entry point for the executable application (currently minimal stub)
- **src/root.zig**: Library entry point with core functionality (currently has basic add function)
- **data/projections.csv**: Contains NFL player projection data with DraftKings salary, projection, and value information
- **build.zig**: Standard Zig build configuration with library and executable targets
- **build.zig.zon**: Package configuration (version 0.0.0, requires Zig 0.14.0+)
- **TODO.md**: Comprehensive development roadmap with 3-phase implementation plan
- **DK_NFL_CLASSIC_CONSTRAINTS.md**: Complete DraftKings contest rules and validation requirements

### Module Design
The build system creates two modules:
- `lib_mod`: Library module based on src/root.zig
- `exe_mod`: Executable module based on src/main.zig, imports the library module as "nfl_lineup_generator_lib"

### Data Format
The projections.csv contains player data with columns:
- Player, Team, Opponent, DK Position, DK Salary, DK Projection, DK Value, DK Ownership, DKSlateID

## Development Plan

### Implementation Strategy
The project follows a 3-phase incremental development approach detailed in TODO.md:

1. **Phase 1: Core Foundation** - Data structures, CSV parsing, rule engine framework
2. **Phase 2: Working System** - Basic lineup generation, DraftKings output, CLI interface
3. **Phase 3: Advanced Features** - Optimization algorithms, advanced rules, scaling

### Key Constraints
All lineup generation must comply with DraftKings NFL Classic rules (see DK_NFL_CLASSIC_CONSTRAINTS.md):
- Roster: 1 QB, 2 RB, 3 WR, 1 TE, 1 FLEX (RB/WR/TE), 1 DST
- Salary cap: $50,000 (must use entire cap)
- Team limit: Maximum 8 players per NFL team
- Player availability: Active players only, no bye weeks

### Current Status
- Project structure and build system complete
- Ready to begin Phase 1: Data Structures implementation
- Next step: Implement Player and Lineup structs as defined in TODO.md

## Development Notes

- Minimum Zig version: 0.14.0
- The project is currently in early development stage with placeholder implementations
- No external dependencies are currently used
- Both library and executable have separate test suites that run in parallel

## TODO.md Maintenance Requirements

**CRITICAL**: After completing any development step or implementing any feature, you MUST:

1. **Update TODO.md immediately** - Mark completed items with ✅ COMPLETE
2. **Add implementation details** - Include specific details about what was implemented
3. **Update Current Status section** - Reflect the new state of the project
4. **Update next steps** - Clearly indicate what should be done next

### TODO.md Update Checklist
After completing any work:
- [ ] Mark completed step/task with `✅ COMPLETE`
- [ ] Add bullet points describing what was implemented
- [ ] Update the "Current Status" section at the bottom
- [ ] Verify the "NEXT:" step is correctly identified
- [ ] Run `zig build test` to ensure implementation works
- [ ] Commit changes (if requested by user)

**Example of proper TODO.md update**:
```markdown
### Step X: Feature Name ✅ COMPLETE
- [x] Task description
  - Implementation detail 1
  - Implementation detail 2
  - Any important notes or decisions made
```

This ensures the project roadmap stays current and provides clear visibility into development progress.

## Code Quality Standards

### Memory Management Priority
**CRITICAL**: Always prioritize proper memory management when writing or reviewing code:

1. **Allocator Responsibility**: Clearly document which component owns allocated memory
2. **Cleanup Patterns**: Use `defer` statements for guaranteed cleanup
3. **Caller vs Callee**: Explicitly document who is responsible for freeing memory
4. **Memory Leaks**: Treat potential memory leaks as critical bugs that must be fixed immediately
5. **Resource Management**: Follow RAII patterns - acquire resources in constructors, release in destructors

### Memory Management Review Checklist
- [ ] Does this function allocate memory? If so, who frees it?
- [ ] Are all allocations paired with corresponding deallocations?
- [ ] Does the function signature clearly indicate memory ownership?
- [ ] Are there any potential double-free scenarios?
- [ ] Do all error paths properly clean up allocated resources?

**Example of good memory management documentation**:
```zig
// Returns owned slice - caller must call allocator.free() on result
pub fn getPlayers(self: Self, allocator: std.mem.Allocator) ![]?*const Player

// Takes ownership of name string - will be freed when Player is destroyed  
pub fn init(allocator: std.mem.Allocator, name: []const u8) !Player
```