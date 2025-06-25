# NFL Lineup Generator CLI - Development TODO

## Phase 1: Core Foundation

### Step 1: Data Structures ✅ COMPLETE
- [x] Define `Player` struct with fields:
  - **Required from CSV**: name, team, opponent, position, salary, projection, value, ownership, slate_id
  - **Optional/Derived**: injury_status, is_on_bye, game_time
- [x] Define `Lineup` struct to hold 9 players with metadata and total salary
- [x] Add Position enum (QB, RB, WR, TE, DST, FLEX) 
- [x] Add InjuryStatus enum (OUT, DOUBTFUL, QUESTIONABLE, ACTIVE) - optional field
- [x] Add basic utility functions for players and lineups

### Step 1.5: Data Structure Quality Improvements
- [ ] **CRITICAL**: Fix memory management bug in `DKClassicPositions.getPlayers()` - clarify caller responsibility
- [ ] Implement `PlayerBuilder` pattern for flexible Player creation:
  - Replace fixed `init()` parameter list with builder pattern
  - Support easy addition of new CSV fields without breaking existing code
  - Validate required fields at build time
- [ ] Add `PlayerConfig` struct for configurable CSV parsing:
  - Define which columns are required vs optional
  - Support different data source formats

### Step 2: Enhanced CSV Input Parser
- [ ] Create CSV parser module to read projection data
- [ ] Parse CSV headers and validate expected columns using PlayerConfig
- [ ] Parse CSV rows into Player structs using PlayerBuilder pattern:
  - Remove $ from salary and convert to integer
  - Remove % from ownership and convert to float (0.0-1.0)
  - Handle malformed rows (e.g., line 77 with "#N/A" values)
- [ ] **Enhanced Error Handling**: 
  - Create structured error types (`ParsingError`, `DataValidationError`)
  - Include context (line numbers, field names, values)
  - Skip malformed rows with detailed warnings
- [ ] Add utility functions for parsing salary ($7900 -> 7900) and ownership (46% -> 0.46)
- [ ] **Structured Logging**: Add debug/info/warn logging for parsing operations
- [ ] Add data validation and type conversion with clear error messages

### Step 3: Rule Engine Framework
- [ ] Design `Rule` interface/trait for lineup validation
- [ ] Create `RuleEngine` struct to manage multiple rules
- [ ] Implement rule validation pipeline with error reporting
- [ ] Add rule priority and dependency system

### Step 4: Core Rule Implementations
- [ ] `SalaryCapRule` - enforce $50,000 salary limit (must use entire cap)
- [ ] `PositionConstraintRule` - validate position requirements (1 QB, 2 RB, 3 WR, 1 TE, 1 FLEX, 1 DST)
- [ ] `FlexPositionRule` - ensure FLEX can be RB/WR/TE only
- [ ] `UniquePlayerRule` - prevent duplicate players in lineup
- [ ] `TeamLimitRule` - maximum 8 players from any single NFL team
- [ ] `PlayerAvailabilityRule` - exclude OUT players, validate active status

## Phase 2: Working System

### Step 5: Basic Lineup Generation
- [ ] Implement simple lineup generator using rule engine
- [ ] Start with brute force approach for single valid lineup
- [ ] Add lineup scoring/ranking based on projections
- [ ] Test with actual CSV data to ensure it works

### Step 6: DraftKings Output Format
- [ ] Research DraftKings CSV upload format requirements
- [ ] Create output module to format lineups as DraftKings CSV
- [ ] Include proper headers and player identification
- [ ] Validate output format compatibility

### Step 7: Basic CLI Interface
- [ ] Add basic command line argument parsing
- [ ] Support input file, output file, and lineup count
- [ ] Add help text and basic error handling
- [ ] Create working end-to-end pipeline

### Step 8: Enhanced Testing & Integration
- [ ] Unit tests for data structures and parsing
- [ ] Rule engine tests with sample data
- [ ] **Property-based testing**: Generate random valid lineups and verify constraints
- [ ] Integration test: CSV input → lineup generation → CSV output
- [ ] Test with actual sample DraftKings data
- [ ] **API Documentation**: Document all public interfaces with examples as we build
- [ ] Add benchmark suite for parsing and lineup generation performance

## Phase 3: Advanced Features & Optimization

### Step 9: Advanced Rules & Architecture Improvements
- [ ] **Position Management Refactoring**:
  - Create `PositionSlot` enum (QB_SLOT, RB1_SLOT, RB2_SLOT, etc.)
  - Replace hard-coded position logic with generic `addPlayerToSlot()` methods
  - Use position mapping configuration instead of switch statements
- [ ] **Configurable Contest Support**:
  - Implement `LineupConstraints` struct for different contest types
  - Support Classic, Showdown, and custom lineup structures
- [ ] **Advanced Rules Implementation**:
  - `OwnershipConstraintRule` - limit high ownership players
  - `StackingRule` - enforce QB+WR from same team stacks  
  - `ExposureRule` - limit player exposure across lineups
  - `BudgetOptimizationRule` - ensure efficient salary usage
  - `ByeWeekRule` - exclude players on bye weeks
  - `GameTimeRule` - validate players are in current week's games
  - `LateSwapRule` - support player substitution logic

### Step 10: Enhanced CLI & Features
- [ ] Advanced command line options and configuration files
- [ ] Progress reporting and logging for large batch generation
- [ ] Support for multiple lineup generation strategies
- [ ] Export to multiple formats beyond DraftKings

### Step 11: Optimization & Scale
- [ ] Implement genetic algorithm or simulated annealing for optimization
- [ ] Add parallel processing for generating 10,000+ lineups
- [ ] Memory optimization for large player pools
- [ ] Performance benchmarking and optimization

### Step 12: Comprehensive Testing
- [ ] Comprehensive unit tests for all modules
- [ ] Performance testing with large datasets
- [ ] Rule engine stress testing with edge cases
- [ ] End-to-end validation with real DraftKings contests

## Module Structure Plan

```
src/
├── main.zig              # CLI entry point
├── player.zig            # Player data structures
├── lineup.zig            # Lineup data structures  
├── rules/
│   ├── rule_engine.zig   # Rule interface and engine
│   ├── salary_cap.zig    # Salary cap rule
│   ├── positions.zig     # Position constraint rules
│   ├── team_limits.zig   # Team and game constraint rules
│   ├── availability.zig  # Player availability and injury rules
│   ├── stacking.zig      # Player stacking rules
│   └── exposure.zig      # Player exposure rules
├── csv_parser.zig        # Input CSV parsing
├── lineup_generator.zig  # Core lineup generation using rule engine
├── output.zig            # DraftKings CSV output formatting
└── cli.zig               # Command line argument parsing
```

## Development Approach

This plan prioritizes incremental development and early validation:
1. **Data flow first** - Get data structures and CSV parsing working early for testing
2. **Build rule engine with core rules** - Establish validation framework with essential constraints
3. **Working system quickly** - Create basic generation + output + CLI for complete pipeline
4. **Test incrementally** - Validate each phase before moving to advanced features
5. **Modular design** - Each rule and component can be developed and tested independently
6. **Optimize last** - Get correctness first, then focus on performance for 10,000+ lineups

## Current Status
- [x] Project structure created
- [x] Basic Zig build configuration  
- [x] Development plan with rule engine (reordered for better flow)
- [x] DraftKings constraints documented
- [x] CSV data format analyzed
- [x] **Step 1 - Data Structures** ✅ COMPLETE
- [ ] **NEXT: Step 1.5 - Critical Quality Improvements (fix memory bug + add flexibility)**
- [ ] **THEN: Step 2 - Enhanced CSV Input Parser**

## Key Improvements in This Plan
- **Quality built-in from start** (Step 1.5) - fix critical bugs and add flexibility early
- **Enhanced error handling integrated** (Step 2) - structured errors and logging from CSV parser onward
- **CSV parser moved early** (Step 2) - need data to test everything else
- **Testing and documentation integrated** (Step 8) - validate working system before advanced features  
- **Architecture improvements timed right** (Step 9) - refactor position logic after working system proven
- **Incremental approach** - each phase delivers working functionality
- **Advanced features last** - focus on correctness before optimization