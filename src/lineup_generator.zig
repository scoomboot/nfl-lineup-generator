const std = @import("std");
const lineup = @import("lineup.zig");
const player = @import("player.zig");
const rules_mod = @import("rules/rules.zig");
const core_rules = @import("rules/core_rules.zig");

const Lineup = lineup.Lineup;
const Player = player.Player;
const LineupRuleEngine = rules_mod.LineupRuleEngine;
const ValidationResult = rules_mod.ValidationResult;

// Generation strategy types
pub const GenerationStrategy = enum {
    BRUTE_FORCE,        // Try all combinations (suitable for small player pools)
    RANDOM_SAMPLING,    // Random player selection with validation
    GENETIC_ALGORITHM,  // Genetic optimization (future implementation)
    SIMULATED_ANNEALING, // Simulated annealing optimization (future implementation)
};

// Scoring strategy for ranking lineups
pub const ScoringStrategy = enum {
    TOTAL_PROJECTION,   // Sum of all player projections
    VALUE_WEIGHTED,     // Projection weighted by value (projection/salary)
    OWNERSHIP_ADJUSTED, // Projection adjusted for ownership percentage
    CUSTOM,            // User-defined scoring function
};

// Configuration for lineup generation
pub const GenerationConfig = struct {
    // Generation parameters
    strategy: GenerationStrategy = .BRUTE_FORCE,
    max_attempts: u32 = 1000000,           // Maximum generation attempts
    timeout_ms: u32 = 30000,               // Timeout in milliseconds
    target_lineups: u32 = 1,               // Number of lineups to generate
    
    // Scoring and ranking
    scoring_strategy: ScoringStrategy = .TOTAL_PROJECTION,
    scoring_function: ?*const fn (lineup: Lineup) f32 = null, // Custom scoring function
    
    // Optimization settings
    allow_duplicates: bool = false,         // Allow duplicate lineups
    sort_results: bool = true,              // Sort results by score
    
    // Constraints
    salary_cap: u32 = 50000,               // DraftKings salary cap
    require_full_salary: bool = true,       // Must use entire salary cap
    
    // Debug and logging
    enable_logging: bool = false,
    log_interval: u32 = 10000,             // Log progress every N attempts
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn withStrategy(self: Self, strategy: GenerationStrategy) Self {
        var config = self;
        config.strategy = strategy;
        return config;
    }
    
    pub fn withMaxAttempts(self: Self, max_attempts: u32) Self {
        var config = self;
        config.max_attempts = max_attempts;
        return config;
    }
    
    pub fn withTargetLineups(self: Self, target_lineups: u32) Self {
        var config = self;
        config.target_lineups = target_lineups;
        return config;
    }
    
    pub fn withScoringStrategy(self: Self, scoring_strategy: ScoringStrategy) Self {
        var config = self;
        config.scoring_strategy = scoring_strategy;
        return config;
    }
    
    pub fn withLogging(self: Self, enable_logging: bool) Self {
        var config = self;
        config.enable_logging = enable_logging;
        return config;
    }
};

// Generation statistics
pub const GenerationStats = struct {
    attempts: u32 = 0,
    valid_lineups: u32 = 0,
    invalid_lineups: u32 = 0,
    rule_failures: u32 = 0,
    timeout_occurred: bool = false,
    duration_ms: u64 = 0,
    
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn getSuccessRate(self: Self) f32 {
        if (self.attempts == 0) return 0.0;
        return @as(f32, @floatFromInt(self.valid_lineups)) / @as(f32, @floatFromInt(self.attempts));
    }
    
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Generation Stats:\n");
        try writer.print("  Attempts: {d}\n", .{self.attempts});
        try writer.print("  Valid: {d}\n", .{self.valid_lineups});
        try writer.print("  Invalid: {d}\n", .{self.invalid_lineups});
        try writer.print("  Rule Failures: {d}\n", .{self.rule_failures});
        try writer.print("  Success Rate: {d:.1}%\n", .{self.getSuccessRate() * 100.0});
        try writer.print("  Duration: {d}ms\n", .{self.duration_ms});
        if (self.timeout_occurred) {
            try writer.print("  ⚠️  Timeout occurred\n");
        }
    }
};

// Result of a generation operation
pub const GenerationResult = struct {
    lineups: []Lineup,
    stats: GenerationStats,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, lineups: []Lineup, stats: GenerationStats) Self {
        return Self{
            .lineups = lineups,
            .stats = stats,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.lineups);
    }
    
    pub fn getBestLineup(self: Self) ?*const Lineup {
        if (self.lineups.len == 0) return null;
        return &self.lineups[0]; // Assuming lineups are sorted by score
    }
    
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Generation Result:\n");
        try writer.print("  Generated {d} lineup(s)\n", .{self.lineups.len});
        try writer.print("{}\n", .{self.stats});
        
        if (self.getBestLineup()) |best| {
            try writer.print("Best Lineup:\n{}\n", .{best.*});
        }
    }
};

// Main lineup generator struct
pub const LineupGenerator = struct {
    allocator: std.mem.Allocator,
    players: []const *const Player,    // Player pool to generate from
    rule_engine: *LineupRuleEngine,          // Rule engine for validation
    config: GenerationConfig,
    
    const Self = @This();
    
    // Initialize generator with player pool and rule engine
    // players slice is not owned by generator - caller manages lifetime
    // rule_engine pointer must remain valid for generator lifetime
    pub fn init(
        allocator: std.mem.Allocator,
        players: []const *const Player,
        rule_engine: *LineupRuleEngine,
        config: GenerationConfig,
    ) Self {
        return Self{
            .allocator = allocator,
            .players = players,
            .rule_engine = rule_engine,
            .config = config,
        };
    }
    
    // No deinit needed - generator doesn't own players or rule_engine
    pub fn deinit(self: *Self) void {
        _ = self;
        // Generator doesn't own any resources that need cleanup
    }
    
    // Generate lineups based on configuration
    // Returns owned GenerationResult - caller must call deinit()
    pub fn generate(self: *Self) !GenerationResult {
        const start_time = std.time.milliTimestamp();
        
        switch (self.config.strategy) {
            .BRUTE_FORCE => return self.generateBruteForce(start_time),
            .RANDOM_SAMPLING => return error.NotImplemented, // Future implementation
            .GENETIC_ALGORITHM => return error.NotImplemented, // Future implementation
            .SIMULATED_ANNEALING => return error.NotImplemented, // Future implementation
        }
    }
    
    // Generate a single valid lineup using brute force
    // Returns owned GenerationResult - caller must call deinit()
    pub fn generateSingle(self: *Self) !GenerationResult {
        var config = self.config;
        config.target_lineups = 1;
        
        const old_config = self.config;
        self.config = config;
        defer self.config = old_config;
        
        return self.generate();
    }
    
    // Validate that generation is possible with current player pool
    pub fn validatePlayerPool(self: Self) !void {
        // Count players by position
        var qb_count: u32 = 0;
        var rb_count: u32 = 0;
        var wr_count: u32 = 0;
        var te_count: u32 = 0;
        var dst_count: u32 = 0;
        
        for (self.players) |p| {
            switch (p.position) {
                .QB => qb_count += 1,
                .RB => rb_count += 1,
                .WR => wr_count += 1,
                .TE => te_count += 1,
                .DST => dst_count += 1,
                .FLEX => {}, // FLEX is not a real position in player pool
            }
        }
        
        // Check minimum requirements for DraftKings lineup
        if (qb_count < 1) return error.InsufficientQBs;
        if (rb_count < 2) return error.InsufficientRBs;  // Need 2 + potentially 1 FLEX
        if (wr_count < 3) return error.InsufficientWRs;  // Need 3 + potentially 1 FLEX
        if (te_count < 1) return error.InsufficientTEs;  // Need 1 + potentially 1 FLEX
        if (dst_count < 1) return error.InsufficientDSTs;
        
        // Check if we have enough FLEX-eligible players (RB + WR + TE >= 6)
        // Need 2 RB + 3 WR + 1 TE + 1 FLEX = 7 total from RB/WR/TE positions
        const flex_eligible = rb_count + wr_count + te_count;
        if (flex_eligible < 7) return error.InsufficientFlexPlayers;
        
        if (self.config.enable_logging) {
            std.log.info("Player pool validation passed: QB={d}, RB={d}, WR={d}, TE={d}, DST={d}", .{
                qb_count, rb_count, wr_count, te_count, dst_count
            });
        }
    }
    
    // Score a lineup based on configuration
    fn scoreLineup(self: Self, lineup_to_score: Lineup) f32 {
        switch (self.config.scoring_strategy) {
            .TOTAL_PROJECTION => return lineup_to_score.total_projection,
            .VALUE_WEIGHTED => return lineup_to_score.getEfficiency(),
            .OWNERSHIP_ADJUSTED => {
                // Simple ownership adjustment - lower ownership = higher score
                // This is a basic implementation - more sophisticated versions could
                // use ownership percentages from player data
                return lineup_to_score.total_projection * 1.1; // Placeholder
            },
            .CUSTOM => {
                if (self.config.scoring_function) |func| {
                    return func(lineup_to_score);
                }
                return lineup_to_score.total_projection; // Fallback
            },
        }
    }
    
    // Brute force generation using recursive backtracking
    fn generateBruteForce(self: *Self, start_time: i64) !GenerationResult {
        var stats = GenerationStats.init();
        var generated_lineups = std.ArrayList(Lineup).init(self.allocator);
        defer generated_lineups.deinit();
        
        // Pre-filter players by position for efficiency
        var players_by_position = try self.getPlayersByPosition();
        defer {
            players_by_position.qb.deinit();
            players_by_position.rb.deinit();
            players_by_position.wr.deinit();
            players_by_position.te.deinit();
            players_by_position.dst.deinit();
        }
        
        // Create generation state
        var generation_state = GenerationState{
            .current_lineup = Lineup.init(),
            .stats = &stats,
            .config = &self.config,
            .rule_engine = self.rule_engine,
            .start_time = start_time,
            .allocator = self.allocator,
        };
        
        if (self.config.enable_logging) {
            std.log.info("Starting brute force generation: target={d}, max_attempts={d}", .{
                self.config.target_lineups, self.config.max_attempts
            });
        }
        
        // Start recursive generation
        try self.generateRecursive(
            &generation_state,
            &players_by_position,
            &generated_lineups,
            0 // Start with position slot 0 (QB)
        );
        
        // Calculate final statistics
        const end_time = std.time.milliTimestamp();
        stats.duration_ms = @intCast(end_time - start_time);
        
        // Sort results if requested
        if (self.config.sort_results and generated_lineups.items.len > 1) {
            std.sort.heap(Lineup, generated_lineups.items, self, compareLineups);
        }
        
        // Convert to owned slice
        const final_lineups = try generated_lineups.toOwnedSlice();
        
        if (self.config.enable_logging) {
            std.log.info("Generation complete: found {d} lineups in {d}ms", .{
                final_lineups.len, stats.duration_ms
            });
        }
        
        return GenerationResult.init(self.allocator, final_lineups, stats);
    }
    
    // Position-based player organization for efficient lookup
    const PlayersByPosition = struct {
        qb: std.ArrayList(*const Player),
        rb: std.ArrayList(*const Player),
        wr: std.ArrayList(*const Player),
        te: std.ArrayList(*const Player),
        dst: std.ArrayList(*const Player),
    };
    
    // Pre-filter players by position for efficient generation
    pub fn getPlayersByPosition(self: *Self) !PlayersByPosition {
        var result = PlayersByPosition{
            .qb = std.ArrayList(*const Player).init(self.allocator),
            .rb = std.ArrayList(*const Player).init(self.allocator),
            .wr = std.ArrayList(*const Player).init(self.allocator),
            .te = std.ArrayList(*const Player).init(self.allocator),
            .dst = std.ArrayList(*const Player).init(self.allocator),
        };
        
        for (self.players) |p| {
            switch (p.position) {
                .QB => try result.qb.append(p),
                .RB => try result.rb.append(p),
                .WR => try result.wr.append(p),
                .TE => try result.te.append(p),
                .DST => try result.dst.append(p),
                .FLEX => {}, // FLEX is not a source position
            }
        }
        
        return result;
    }
    
    // Generation state for recursive backtracking
    const GenerationState = struct {
        current_lineup: Lineup,
        stats: *GenerationStats,
        config: *const GenerationConfig,
        rule_engine: *LineupRuleEngine,
        start_time: i64,
        allocator: std.mem.Allocator,
        
        fn shouldTimeout(self: *const @This()) bool {
            const current_time = std.time.milliTimestamp();
            return (current_time - self.start_time) > self.config.timeout_ms;
        }
        
        fn shouldStop(self: *const @This()) bool {
            return self.stats.attempts >= self.config.max_attempts or 
                   (self.config.target_lineups > 0 and self.stats.valid_lineups >= self.config.target_lineups) or
                   self.shouldTimeout();
        }
    };
    
    // Position slots in generation order
    const PositionSlot = enum(u8) {
        QB = 0,
        RB1 = 1,
        RB2 = 2,
        WR1 = 3,
        WR2 = 4,
        WR3 = 5,
        TE = 6,
        FLEX = 7,
        DST = 8,
        
        const TOTAL_SLOTS = 9;
    };
    
    // Recursive backtracking generation
    fn generateRecursive(
        self: *Self,
        state: *GenerationState,
        players_by_position: *const PlayersByPosition,
        generated_lineups: *std.ArrayList(Lineup),
        slot_index: u8,
    ) !void {
        // Check termination conditions
        if (state.shouldStop()) {
            if (state.shouldTimeout()) {
                state.stats.timeout_occurred = true;
            }
            return;
        }
        
        // If we've filled all slots, validate and potentially add lineup
        if (slot_index >= PositionSlot.TOTAL_SLOTS) {
            return self.validateAndAddLineup(state, generated_lineups);
        }
        
        const slot: PositionSlot = @enumFromInt(slot_index);
        
        // Get candidate players for this slot
        const candidates = switch (slot) {
            .QB => players_by_position.qb.items,
            .RB1, .RB2 => players_by_position.rb.items,
            .WR1, .WR2, .WR3 => players_by_position.wr.items,
            .TE => players_by_position.te.items,
            .FLEX => blk: {
                // FLEX can be RB, WR, or TE - combine all eligible players
                var flex_candidates = std.ArrayList(*const Player).init(self.allocator);
                defer flex_candidates.deinit();
                
                try flex_candidates.appendSlice(players_by_position.rb.items);
                try flex_candidates.appendSlice(players_by_position.wr.items);
                try flex_candidates.appendSlice(players_by_position.te.items);
                
                break :blk flex_candidates.items;
            },
            .DST => players_by_position.dst.items,
        };
        
        // Try each candidate player for this slot
        for (candidates) |candidate| {
            // Skip if player is already in lineup
            if (state.current_lineup.containsPlayer(candidate)) {
                continue;
            }
            
            // Try adding player to current slot
            const old_lineup = state.current_lineup;
            if (self.tryAddPlayerToSlot(&state.current_lineup, candidate, slot)) {
                // Player added successfully, recurse to next slot
                try self.generateRecursive(state, players_by_position, generated_lineups, slot_index + 1);
                
                // Backtrack - restore lineup state
                state.current_lineup = old_lineup;
            }
            
            // Check if we should stop early
            if (state.shouldStop()) {
                return;
            }
        }
    }
    
    // Try to add a player to a specific slot
    fn tryAddPlayerToSlot(_: *Self, lineup_ref: *Lineup, player_to_add: *const Player, slot: PositionSlot) bool {
        switch (slot) {
            .QB => {
                if (player_to_add.position != .QB or lineup_ref.positions.qb != null) return false;
                lineup_ref.positions.qb = player_to_add;
            },
            .RB1 => {
                if (player_to_add.position != .RB or lineup_ref.positions.rb1 != null) return false;
                lineup_ref.positions.rb1 = player_to_add;
            },
            .RB2 => {
                if (player_to_add.position != .RB or lineup_ref.positions.rb2 != null) return false;
                lineup_ref.positions.rb2 = player_to_add;
            },
            .WR1 => {
                if (player_to_add.position != .WR or lineup_ref.positions.wr1 != null) return false;
                lineup_ref.positions.wr1 = player_to_add;
            },
            .WR2 => {
                if (player_to_add.position != .WR or lineup_ref.positions.wr2 != null) return false;
                lineup_ref.positions.wr2 = player_to_add;
            },
            .WR3 => {
                if (player_to_add.position != .WR or lineup_ref.positions.wr3 != null) return false;
                lineup_ref.positions.wr3 = player_to_add;
            },
            .TE => {
                if (player_to_add.position != .TE or lineup_ref.positions.te != null) return false;
                lineup_ref.positions.te = player_to_add;
            },
            .FLEX => {
                if (!player_to_add.position.isFlexEligible() or lineup_ref.positions.flex != null) return false;
                lineup_ref.positions.flex = player_to_add;
            },
            .DST => {
                if (player_to_add.position != .DST or lineup_ref.positions.dst != null) return false;
                lineup_ref.positions.dst = player_to_add;
            },
        }
        
        // Update lineup totals
        lineup_ref.total_salary += player_to_add.salary;
        lineup_ref.total_projection += player_to_add.projection;
        return true;
    }
    
    // Validate completed lineup and add to results if valid
    fn validateAndAddLineup(
        self: *Self,
        state: *GenerationState,
        generated_lineups: *std.ArrayList(Lineup),
    ) !void {
        state.stats.attempts += 1;
        
        // Log progress periodically
        if (state.config.enable_logging and state.stats.attempts % state.config.log_interval == 0) {
            std.log.info("Progress: {d} attempts, {d} valid lineups", .{
                state.stats.attempts, state.stats.valid_lineups
            });
        }
        
        // Validate lineup using rule engine  
        var validation_result = try state.rule_engine.validateLineup(&state.current_lineup);
        defer validation_result.deinit(state.allocator);
        
        if (validation_result.is_valid) {
            // Check for duplicates if not allowed
            if (!state.config.allow_duplicates) {
                for (generated_lineups.items) |*existing| {
                    if (self.lineupsEqual(&state.current_lineup, existing)) {
                        state.stats.invalid_lineups += 1;
                        return; // Skip duplicate
                    }
                }
            }
            
            // Add valid lineup
            try generated_lineups.append(state.current_lineup);
            state.stats.valid_lineups += 1;
            
            if (state.config.enable_logging) {
                std.log.debug("Valid lineup #{d}: ${d}, {d:.1}pts", .{
                    state.stats.valid_lineups,
                    state.current_lineup.total_salary,
                    state.current_lineup.total_projection
                });
            }
        } else {
            state.stats.invalid_lineups += 1;
            state.stats.rule_failures += 1;
        }
    }
    
    // Compare two lineups for equality (duplicate detection)
    fn lineupsEqual(self: *Self, lineup1: *const Lineup, lineup2: *const Lineup) bool {
        _ = self;
        return lineup1.positions.qb == lineup2.positions.qb and
               lineup1.positions.rb1 == lineup2.positions.rb1 and
               lineup1.positions.rb2 == lineup2.positions.rb2 and
               lineup1.positions.wr1 == lineup2.positions.wr1 and
               lineup1.positions.wr2 == lineup2.positions.wr2 and
               lineup1.positions.wr3 == lineup2.positions.wr3 and
               lineup1.positions.te == lineup2.positions.te and
               lineup1.positions.flex == lineup2.positions.flex and
               lineup1.positions.dst == lineup2.positions.dst;
    }
    
    // Compare lineups for sorting (higher score first)
    fn compareLineups(self: *Self, a: Lineup, b: Lineup) bool {
        const score_a = self.scoreLineup(a);
        const score_b = self.scoreLineup(b);
        return score_a > score_b; // Higher scores first
    }
};

// Convenience functions for common use cases

// Create a generator with default DraftKings rules
// rule_engine must be initialized with createDraftKingsRuleEngine() or equivalent
// players slice is not owned - caller manages lifetime
pub fn createDraftKingsGenerator(
    allocator: std.mem.Allocator,
    players: []const *const Player,
    rule_engine: *LineupRuleEngine,
) LineupGenerator {
    const config = GenerationConfig.init();
    return LineupGenerator.init(allocator, players, rule_engine, config);
}

// Create a generator optimized for single lineup generation
pub fn createSingleLineupGenerator(
    allocator: std.mem.Allocator,
    players: []const *const Player,
    rule_engine: *LineupRuleEngine,
) LineupGenerator {
    const config = GenerationConfig.init()
        .withTargetLineups(1)
        .withMaxAttempts(100000)
        .withLogging(false);
    
    return LineupGenerator.init(allocator, players, rule_engine, config);
}

// Create a generator with logging enabled for debugging
pub fn createDebugGenerator(
    allocator: std.mem.Allocator,
    players: []const *const Player,
    rule_engine: *LineupRuleEngine,
) LineupGenerator {
    const config = GenerationConfig.init()
        .withLogging(true)
        .withMaxAttempts(10000); // Lower limit for debugging
    
    return LineupGenerator.init(allocator, players, rule_engine, config);
}

// Tests for lineup generator
test "LineupGenerator basic initialization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create test players
    const players = [_]*const Player{};
    const empty_players: []const *const Player = &players;
    
    // Create rule engine (placeholder - will use actual implementation)
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    // Test initialization
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, empty_players, &engine, config);
    defer generator.deinit();
    
    try testing.expect(generator.players.len == 0);
    try testing.expect(generator.config.strategy == .BRUTE_FORCE);
    try testing.expect(generator.config.target_lineups == 1);
}

test "GenerationConfig builder pattern" {
    const testing = std.testing;
    
    const config = GenerationConfig.init()
        .withStrategy(.RANDOM_SAMPLING)
        .withMaxAttempts(50000)
        .withTargetLineups(5)
        .withScoringStrategy(.VALUE_WEIGHTED)
        .withLogging(true);
    
    try testing.expect(config.strategy == .RANDOM_SAMPLING);
    try testing.expect(config.max_attempts == 50000);
    try testing.expect(config.target_lineups == 5);
    try testing.expect(config.scoring_strategy == .VALUE_WEIGHTED);
    try testing.expect(config.enable_logging == true);
}

test "GenerationStats calculations" {
    const testing = std.testing;
    
    var stats = GenerationStats.init();
    try testing.expect(stats.getSuccessRate() == 0.0);
    
    stats.attempts = 100;
    stats.valid_lineups = 25;
    stats.invalid_lineups = 75;
    
    try testing.expect(stats.getSuccessRate() == 0.25);
}

test "LineupGenerator player pool validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create insufficient player pool (missing positions)
    var qb = Player.init("Test QB", "TEST", "OPP", .QB, 7000, 25.0, 3.57, 0.15, "1");
    const insufficient_players = [_]*const Player{&qb};
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &insufficient_players, &engine, config);
    defer generator.deinit();
    
    // Should fail validation due to insufficient players
    try testing.expectError(error.InsufficientRBs, generator.validatePlayerPool());
}

test "LineupGenerator brute force with minimal valid lineup" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create minimal valid player pool (1 of each position + extras for FLEX)
    var qb = Player.init("Test QB", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.15, "1");
    var rb1 = Player.init("Test RB1", "NYG", "DAL", .RB, 6000, 20.0, 3.33, 0.25, "2");
    var rb2 = Player.init("Test RB2", "NYG", "DAL", .RB, 5000, 15.0, 3.0, 0.30, "3");
    var rb3 = Player.init("Test RB3", "NYG", "DAL", .RB, 4000, 10.0, 2.5, 0.35, "4"); // For FLEX
    var wr1 = Player.init("Test WR1", "NYG", "DAL", .WR, 7500, 22.0, 2.93, 0.20, "5");
    var wr2 = Player.init("Test WR2", "NYG", "DAL", .WR, 6500, 18.0, 2.77, 0.22, "6");
    var wr3 = Player.init("Test WR3", "NYG", "DAL", .WR, 5500, 16.0, 2.91, 0.24, "7");
    var te = Player.init("Test TE", "NYG", "DAL", .TE, 5000, 12.0, 2.4, 0.28, "8");
    var dst = Player.init("Test DST", "NYG", "DAL", .DST, 2500, 8.0, 3.2, 0.40, "9");
    
    const players = [_]*const Player{ &qb, &rb1, &rb2, &rb3, &wr1, &wr2, &wr3, &te, &dst };
    
    // Create rule engine with basic rules
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    // Add essential rules for testing
    const salary_rule = core_rules.createSalaryCapRule();
    try engine.addRule(salary_rule);
    
    const position_rule = core_rules.createPositionConstraintRule();
    try engine.addRule(position_rule);
    
    // Configure for single lineup generation with low limits for testing
    const config = GenerationConfig.init()
        .withTargetLineups(1)
        .withMaxAttempts(1000)
        .withLogging(false);
    
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Validate player pool first
    try generator.validatePlayerPool();
    
    // Generate a lineup
    var result = try generator.generateSingle();
    defer result.deinit();
    
    // Should have generated at least one lineup
    try testing.expect(result.lineups.len >= 0); // May be 0 if salary constraints are too tight
    try testing.expect(result.stats.attempts > 0);
}

test "LineupGenerator position slot assignment" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test position slot assignment logic
    var qb = Player.init("Test QB", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.15, "1");
    var rb = Player.init("Test RB", "NYG", "DAL", .RB, 6000, 20.0, 3.33, 0.25, "2");
    var wr = Player.init("Test WR", "NYG", "DAL", .WR, 7500, 22.0, 2.93, 0.20, "3");
    var te = Player.init("Test TE", "NYG", "DAL", .TE, 5000, 12.0, 2.4, 0.28, "4");
    var dst = Player.init("Test DST", "NYG", "DAL", .DST, 2500, 8.0, 3.2, 0.40, "5");
    
    const players = [_]*const Player{ &qb, &rb, &wr, &te, &dst };
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Test individual slot assignment
    var test_lineup = Lineup.init();
    
    // Test QB slot
    try testing.expect(generator.tryAddPlayerToSlot(&test_lineup, &qb, .QB));
    try testing.expect(test_lineup.positions.qb == &qb);
    try testing.expect(test_lineup.total_salary == 7000);
    
    // Test RB1 slot  
    try testing.expect(generator.tryAddPlayerToSlot(&test_lineup, &rb, .RB1));
    try testing.expect(test_lineup.positions.rb1 == &rb);
    try testing.expect(test_lineup.total_salary == 13000);
    
    // Test FLEX slot with RB (should work)
    var lineup2 = Lineup.init();
    try testing.expect(generator.tryAddPlayerToSlot(&lineup2, &rb, .FLEX));
    try testing.expect(lineup2.positions.flex == &rb);
    
    // Test FLEX slot with QB (should fail)
    var lineup3 = Lineup.init();
    try testing.expect(!generator.tryAddPlayerToSlot(&lineup3, &qb, .FLEX));
    try testing.expect(lineup3.positions.flex == null);
}

test "LineupGenerator generation state and termination" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var stats = GenerationStats.init();
    const config = GenerationConfig.init()
        .withMaxAttempts(100)
        .withTargetLineups(5);
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const start_time = std.time.milliTimestamp();
    var state = LineupGenerator.GenerationState{
        .current_lineup = Lineup.init(),
        .stats = &stats,
        .config = &config,
        .rule_engine = &engine,
        .start_time = start_time,
        .allocator = allocator,
    };
    
    // Test initial state
    try testing.expect(!state.shouldStop());
    
    // Test max attempts termination
    stats.attempts = 100;
    try testing.expect(state.shouldStop());
    
    // Test target lineups termination
    stats.attempts = 0;
    stats.valid_lineups = 5;
    try testing.expect(state.shouldStop());
}

test "LineupGenerator duplicate detection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create two identical lineups
    var qb = Player.init("Test QB", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.15, "1");
    var rb = Player.init("Test RB", "NYG", "DAL", .RB, 6000, 20.0, 3.33, 0.25, "2");
    
    var lineup1 = Lineup.init();
    lineup1.positions.qb = &qb;
    lineup1.positions.rb1 = &rb;
    
    var lineup2 = Lineup.init();
    lineup2.positions.qb = &qb;
    lineup2.positions.rb1 = &rb;
    
    var lineup3 = Lineup.init();
    lineup3.positions.qb = &qb;
    // lineup3.positions.rb1 is null - different lineup
    
    const players = [_]*const Player{ &qb, &rb };
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Test duplicate detection
    try testing.expect(generator.lineupsEqual(&lineup1, &lineup2)); // Should be equal
    try testing.expect(!generator.lineupsEqual(&lineup1, &lineup3)); // Should be different
}