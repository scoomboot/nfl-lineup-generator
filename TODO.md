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

### Step 1.5: Data Structure Quality Improvements ✅ COMPLETE
- [x] **CRITICAL**: Fix memory management bug in `DKClassicPositions.getPlayers()` - clarify caller responsibility
  - Fixed memory leak by removing incorrect `defer players.deinit()`
  - Added clear documentation that caller must free returned slice
- [x] Implement `PlayerBuilder` pattern for flexible Player creation:
  - Added fluent builder interface with method chaining
  - Support for both direct values and string parsing methods
  - Validates all required fields at build time with clear error messages
  - Easy addition of new CSV fields without breaking existing code
- [x] Add `PlayerConfig` struct for configurable CSV parsing:
  - Configurable required vs optional field definitions
  - Column mapping support for different data source formats
  - Header validation with structured error reporting
  - Direct integration with PlayerBuilder pattern
  - Support for DraftKings default and custom configurations

### Step 2: Enhanced CSV Input Parser ✅ COMPLETE
- [x] Create CSV parser module to read projection data
  - Implemented comprehensive CSVParser struct with configurable options
  - Support for both file and string content parsing
  - Memory-efficient parsing with proper cleanup
- [x] Parse CSV headers and validate expected columns using PlayerConfig
  - Header validation against PlayerConfig requirements
  - Column mapping and index resolution
  - Structured error reporting for missing columns
- [x] Parse CSV rows into Player structs using PlayerBuilder pattern:
  - Remove $ from salary and convert to integer
  - Remove % from ownership and convert to float (0.0-1.0)
  - Handle malformed rows (e.g., line 77 with "#N/A" values)
  - Proper CSV field parsing with quote handling
  - Integration with existing PlayerBuilder and PlayerConfig
- [x] **Enhanced Error Handling**: 
  - Create structured error types (`ParsingError`, `DataValidationError`)
  - Include context (line numbers, field names, values)
  - Skip malformed rows with detailed warnings
  - Comprehensive ParseResult with warnings and errors
  - ParseContext for detailed error reporting
- [x] Add utility functions for parsing salary ($7900 -> 7900) and ownership (46% -> 0.46)
  - Utility functions already implemented in PlayerUtils (from Step 1.5)
  - CSV parser integrates with existing parsing functions
- [x] **Structured Logging**: Add debug/info/warn logging for parsing operations
  - Configurable logging levels (DEBUG, INFO, WARN, ERROR)
  - Detailed parsing progress and error logging
  - Optional logging that can be disabled for testing
- [x] Add data validation and type conversion with clear error messages
  - Player data validation for logical consistency
  - Clear error messages with context information
  - Validation of salary, projection, ownership ranges
  - **Tested with actual data**: Successfully parsed 291/293 rows, correctly skipped malformed row

### Step 2.5: Integration Testing & Validation ✅ COMPLETE
- [x] **Core Pipeline Integration Tests**:
  - Test complete CSV→Player pipeline with known good data
  - Test malformed data handling with real edge cases
  - Test memory management across full pipeline with allocator tracking
- [x] **Data Validation Integration Tests**:
  - Test edge cases found in actual projections.csv data
  - Test different CSV format variations (quotes, separators, line endings)
  - Validate parsing decisions match expected behavior
- [x] **Error Handling Integration Tests**:
  - Test structured error propagation with line numbers and context
  - Test ParseResult warnings vs errors distinction
  - Validate logging output at different levels (debug vs production)
- [x] **Performance & Memory Integration Tests**:
  - Test with large datasets (1000 players) for performance characteristics
  - Memory usage profiling and peak allocation tracking with ArenaAllocator
  - Verify cleanup on error paths and proper resource management
- [x] **Configuration Integration Tests**:
  - Test PlayerConfig flexibility with different column orders
  - Test custom field mappings and missing optional fields
  - Test PlayerBuilder integration through complete CSV parsing chain
  - **Comprehensive Integration Test Suite**: Created `src/integration_tests.zig` with 15 integration tests
  - **Real Data Validation**: Successfully tested with actual projections.csv (291/293 parsed, 99.3% success rate)
  - **Performance Testing**: Validated parsing of 1000 players with performance metrics
  - **Memory Management**: Confirmed proper cleanup with ArenaAllocator and error path handling
  - **Edge Case Coverage**: Tested malformed data, missing columns, empty files, and invalid formats

### Step 3: Rule Engine Framework ✅ COMPLETE  
- [x] Design `Rule` interface/trait for lineup validation
  - Created Rule struct with name, priority, enabled flag, and validation function pointer
  - Implemented RuleResult for structured validation results with error messages
  - Added rule enable/disable functionality for flexible rule management
- [x] Create `RuleEngine` struct to manage multiple rules
  - Implemented RuleEngine with ArrayList-based rule storage and management
  - Added rule addition, removal, and retrieval by name functionality
  - Created rule statistics tracking for engine monitoring
- [x] Implement rule validation pipeline with error reporting
  - Built comprehensive ValidationResult with passed/failed/warning categorization
  - Implemented priority-based rule execution (CRITICAL rules first)
  - Added structured error handling with context information and line numbers
  - Created RuleUtils for common validation result creation patterns
- [x] Add rule priority and dependency system
  - Implemented RulePriority enum (CRITICAL, HIGH, MEDIUM, LOW) with automatic sorting
  - Added RuleDependency system for rule relationships (REQUIRES, CONFLICTS, ENHANCES)
  - Rules are validated in priority order with different failure handling per priority level
  - CRITICAL/HIGH failures invalidate lineup, MEDIUM/LOW failures become warnings

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
- [x] **Step 1.5 - Critical Quality Improvements** ✅ COMPLETE
  - Memory management bug fixed in DKClassicPositions.getPlayers()
  - PlayerBuilder pattern implemented with validation and flexibility
  - PlayerConfig struct added for configurable CSV parsing
- [x] **Step 2 - Enhanced CSV Input Parser** ✅ COMPLETE
  - Comprehensive CSV parser with structured error handling and logging
  - Successfully tested with actual projections.csv data (291/293 rows parsed)
  - Integration with PlayerBuilder and PlayerConfig patterns
  - Proper handling of malformed data and edge cases
- [x] **Step 2.5 - Integration Testing & Validation** ✅ COMPLETE
  - Comprehensive integration test suite with 15 test cases covering all pipeline components
  - Real data validation with actual projections.csv (99.3% success rate)
  - Performance testing with 1000 players and memory management validation
  - Edge case coverage including malformed data, errors, and configuration flexibility
- [x] **Step 3 - Rule Engine Framework** ✅ COMPLETE
  - Comprehensive rule engine with priority system and validation pipeline
  - Rule interface with function pointers for flexible rule implementation
  - Structured error reporting and warning system
  - Integration layer for type safety with Lineup structs
- [ ] **NEXT: Step 4 - Core Rule Implementations**

## Key Improvements in This Plan
- **Quality built-in from start** (Step 1.5) - fix critical bugs and add flexibility early
- **Enhanced error handling integrated** (Step 2) - structured errors and logging from CSV parser onward
- **CSV parser moved early** (Step 2) - need data to test everything else
- **Testing and documentation integrated** (Step 8) - validate working system before advanced features  
- **Architecture improvements timed right** (Step 9) - refactor position logic after working system proven
- **Incremental approach** - each phase delivers working functionality
- **Advanced features last** - focus on correctness before optimization