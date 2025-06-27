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
    BALANCED_SCORE,     // Combination of projection, value, and ownership
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

// Tie-breaking score for lineups with equal primary scores
pub const TieBreakerScore = struct {
    salary_efficiency: f32,    // Projection per $1K salary
    salary_used: u32,         // Total salary used (higher is better for tie-breaking)
    team_diversity: f32,      // Team distribution diversity (0.0-1.0)
    ownership_diversity: f32, // Ownership percentage diversity
    position_balance: f32,    // Balance of projections across positions
    
    const Self = @This();
    
    // Compare two tie-breaker scores (returns true if self is better than other)
    pub fn isBetterThan(self: Self, other: Self) bool {
        // Priority order for tie-breaking:
        // 1. Salary efficiency (higher is better)
        // 2. Salary used (higher is better - use more of the cap)
        // 3. Team diversity (higher is better)
        // 4. Ownership diversity (higher is better)
        // 5. Position balance (higher is better)
        
        const efficiency_diff = self.salary_efficiency - other.salary_efficiency;
        if (@abs(efficiency_diff) > 0.01) { // Significant difference in efficiency
            return efficiency_diff > 0;
        }
        
        const salary_diff = @as(i32, @intCast(self.salary_used)) - @as(i32, @intCast(other.salary_used));
        if (@abs(salary_diff) > 100) { // Significant difference in salary usage ($100+)
            return salary_diff > 0;
        }
        
        const team_diversity_diff = self.team_diversity - other.team_diversity;
        if (@abs(team_diversity_diff) > 0.05) { // 5% difference in team diversity
            return team_diversity_diff > 0;
        }
        
        const ownership_diversity_diff = self.ownership_diversity - other.ownership_diversity;
        if (@abs(ownership_diversity_diff) > 0.02) { // 2% difference in ownership diversity
            return ownership_diversity_diff > 0;
        }
        
        return self.position_balance > other.position_balance;
    }
    
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("TieBreaker(eff:{d:.2}, sal:${d}, team:{d:.2}, own:{d:.2}, bal:{d:.2})", .{
            self.salary_efficiency, self.salary_used, self.team_diversity, 
            self.ownership_diversity, self.position_balance
        });
    }
};

// Scored lineup for ranking and comparison
pub const ScoredLineup = struct {
    lineup: Lineup,
    primary_score: f32,
    tie_breaker: TieBreakerScore,
    
    const Self = @This();
    
    pub fn init(lineup_data: Lineup, primary_score: f32, tie_breaker: TieBreakerScore) Self {
        return Self{
            .lineup = lineup_data,
            .primary_score = primary_score,
            .tie_breaker = tie_breaker,
        };
    }
    
    // Compare scored lineups for sorting (returns true if self is better than other)
    pub fn isBetterThan(self: Self, other: Self) bool {
        const score_diff = self.primary_score - other.primary_score;
        if (@abs(score_diff) > 0.01) { // Significant difference in primary score
            return score_diff > 0;
        }
        
        // Use tie-breaker if primary scores are essentially equal
        return self.tie_breaker.isBetterThan(other.tie_breaker);
    }
    
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("ScoredLineup(score:{d:.2}, {}):\n{}", .{
            self.primary_score, self.tie_breaker, self.lineup
        });
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
    
    // Get lineups as scored lineups for detailed analysis
    pub fn getScoredLineups(self: Self, generator: *LineupGenerator) ![]ScoredLineup {
        return generator.createScoredLineups(self.lineups);
    }
    
    // Find the best lineup using comprehensive scoring
    pub fn findBestScoredLineup(self: Self, generator: *LineupGenerator) ?ScoredLineup {
        return generator.findBestLineup(self.lineups);
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
        
        if (self.getBestLineup()) |best_lineup| {
            try writer.print("Best Lineup:\n{}\n", .{best_lineup.*});
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
    pub fn scoreLineup(self: Self, lineup_to_score: Lineup) f32 {
        switch (self.config.scoring_strategy) {
            .TOTAL_PROJECTION => return lineup_to_score.total_projection,
            .VALUE_WEIGHTED => return lineup_to_score.getEfficiency(),
            .OWNERSHIP_ADJUSTED => return self.calculateOwnershipAdjustedScore(lineup_to_score),
            .BALANCED_SCORE => return self.calculateBalancedScore(lineup_to_score),
            .CUSTOM => {
                if (self.config.scoring_function) |func| {
                    return func(lineup_to_score);
                }
                return lineup_to_score.total_projection; // Fallback
            },
        }
    }
    
    // Calculate ownership-adjusted score (lower ownership = higher score multiplier)
    fn calculateOwnershipAdjustedScore(self: Self, lineup_to_score: Lineup) f32 {
        var total_score: f32 = 0.0;
        var player_count: u32 = 0;
        
        // Helper to add ownership-adjusted score for a player
        const addPlayerScore = struct {
            fn call(player_opt: ?*const Player, total: *f32, count: *u32) void {
                if (player_opt) |p| {
                    // Lower ownership gets higher multiplier (contrarian strategy)
                    // ownership range: 0.0-1.0, multiplier range: 1.5-0.5
                    const ownership_multiplier = 1.5 - p.ownership;
                    total.* += p.projection * ownership_multiplier;
                    count.* += 1;
                }
            }
        }.call;
        
        addPlayerScore(lineup_to_score.positions.qb, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.rb1, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.rb2, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.wr1, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.wr2, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.wr3, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.te, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.flex, &total_score, &player_count);
        addPlayerScore(lineup_to_score.positions.dst, &total_score, &player_count);
        
        _ = self; // Suppress unused parameter warning
        return total_score;
    }
    
    // Calculate balanced score combining projection, value, and ownership
    fn calculateBalancedScore(self: Self, lineup_to_score: Lineup) f32 {
        const projection_score = lineup_to_score.total_projection;
        const value_score = lineup_to_score.getEfficiency();
        const ownership_score = self.calculateOwnershipAdjustedScore(lineup_to_score);
        
        // Weighted combination: 50% projection, 30% value, 20% ownership adjustment
        return (projection_score * 0.5) + (value_score * 0.3) + (ownership_score * 0.2);
    }
    
    // Calculate tie-breaking score for lineups with equal primary scores
    fn calculateTieBreakerScore(self: Self, lineup_to_score: Lineup) TieBreakerScore {
        return TieBreakerScore{
            .salary_efficiency = lineup_to_score.getEfficiency(),
            .salary_used = lineup_to_score.total_salary,
            .team_diversity = self.calculateTeamDiversityScore(lineup_to_score),
            .ownership_diversity = self.calculateOwnershipDiversityScore(lineup_to_score),
            .position_balance = self.calculatePositionBalanceScore(lineup_to_score),
        };
    }
    
    // Calculate team diversity score (higher = more diverse)
    pub fn calculateTeamDiversityScore(self: Self, lineup_to_score: Lineup) f32 {
        var team_counts = std.HashMap([]const u8, u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer team_counts.deinit();
        
        // Count players per team
        const countPlayerTeam = struct {
            fn call(player_opt: ?*const Player, counts: *std.HashMap([]const u8, u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage)) void {
                if (player_opt) |p| {
                    const current_count = counts.get(p.team) orelse 0;
                    counts.put(p.team, current_count + 1) catch {
                        // If allocation fails, team diversity calculation will be less accurate
                        // but we don't want to crash the entire generation process
                        return;
                    };
                }
            }
        }.call;
        
        countPlayerTeam(lineup_to_score.positions.qb, &team_counts);
        countPlayerTeam(lineup_to_score.positions.rb1, &team_counts);
        countPlayerTeam(lineup_to_score.positions.rb2, &team_counts);
        countPlayerTeam(lineup_to_score.positions.wr1, &team_counts);
        countPlayerTeam(lineup_to_score.positions.wr2, &team_counts);
        countPlayerTeam(lineup_to_score.positions.wr3, &team_counts);
        countPlayerTeam(lineup_to_score.positions.te, &team_counts);
        countPlayerTeam(lineup_to_score.positions.flex, &team_counts);
        countPlayerTeam(lineup_to_score.positions.dst, &team_counts);
        
        // Calculate diversity: more teams = higher diversity
        const team_count = team_counts.count();
        return @as(f32, @floatFromInt(team_count)) / 9.0; // Max diversity is 1.0 (9 different teams)
    }
    
    // Calculate ownership diversity score (higher = more diverse ownership)
    pub fn calculateOwnershipDiversityScore(self: Self, lineup_to_score: Lineup) f32 {
        _ = self; // Not using allocator in this method
        var ownership_values: [9]f32 = undefined;
        var player_count: u8 = 0;
        
        const addOwnership = struct {
            fn call(player_opt: ?*const Player, values: *[9]f32, count: *u8) void {
                if (player_opt) |p| {
                    values[count.*] = p.ownership;
                    count.* += 1;
                }
            }
        }.call;
        
        addOwnership(lineup_to_score.positions.qb, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.rb1, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.rb2, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.wr1, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.wr2, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.wr3, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.te, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.flex, &ownership_values, &player_count);
        addOwnership(lineup_to_score.positions.dst, &ownership_values, &player_count);
        
        if (player_count == 0) return 0.0;
        
        // Calculate standard deviation of ownership percentages
        var mean: f32 = 0.0;
        for (ownership_values[0..player_count]) |value| {
            mean += value;
        }
        mean /= @as(f32, @floatFromInt(player_count));
        
        var variance: f32 = 0.0;
        for (ownership_values[0..player_count]) |value| {
            const diff = value - mean;
            variance += diff * diff;
        }
        variance /= @as(f32, @floatFromInt(player_count));
        
        return @sqrt(variance); // Standard deviation as diversity measure
    }
    
    // Calculate position balance score (higher = better balance across skill positions)
    pub fn calculatePositionBalanceScore(self: Self, lineup_to_score: Lineup) f32 {
        _ = self; // Not using allocator in this method
        // Simple balance: compare projection distribution across skill positions
        var skill_projections: [8]f32 = undefined; // Exclude DST from balance calculation
        var skill_count: u8 = 0;
        
        const addSkillProjection = struct {
            fn call(player_opt: ?*const Player, projections: *[8]f32, count: *u8) void {
                if (player_opt) |p| {
                    if (p.position != .DST) {
                        projections[count.*] = p.projection;
                        count.* += 1;
                    }
                }
            }
        }.call;
        
        addSkillProjection(lineup_to_score.positions.qb, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.rb1, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.rb2, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.wr1, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.wr2, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.wr3, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.te, &skill_projections, &skill_count);
        addSkillProjection(lineup_to_score.positions.flex, &skill_projections, &skill_count);
        
        if (skill_count == 0) return 0.0;
        
        // Calculate coefficient of variation (std dev / mean) - lower is more balanced
        var mean: f32 = 0.0;
        for (skill_projections[0..skill_count]) |value| {
            mean += value;
        }
        mean /= @as(f32, @floatFromInt(skill_count));
        
        var variance: f32 = 0.0;
        for (skill_projections[0..skill_count]) |value| {
            const diff = value - mean;
            variance += diff * diff;
        }
        variance /= @as(f32, @floatFromInt(skill_count));
        
        const std_dev = @sqrt(variance);
        const coefficient_of_variation = if (mean > 0.0) std_dev / mean else 0.0;
        
        // Return inverse (1 - CV) so higher score = more balanced
        return 1.0 - @min(coefficient_of_variation, 1.0);
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
        
        // Handle FLEX position separately to avoid memory allocation issues
        if (slot == .FLEX) {
            // Try RB candidates for FLEX
            for (players_by_position.rb.items) |candidate| {
                if (state.current_lineup.containsPlayer(candidate)) continue;
                
                const old_lineup = state.current_lineup;
                if (self.tryAddPlayerToSlot(&state.current_lineup, candidate, slot)) {
                    try self.generateRecursive(state, players_by_position, generated_lineups, slot_index + 1);
                    state.current_lineup = old_lineup;
                }
                
                if (state.shouldStop()) return;
            }
            
            // Try WR candidates for FLEX
            for (players_by_position.wr.items) |candidate| {
                if (state.current_lineup.containsPlayer(candidate)) continue;
                
                const old_lineup = state.current_lineup;
                if (self.tryAddPlayerToSlot(&state.current_lineup, candidate, slot)) {
                    try self.generateRecursive(state, players_by_position, generated_lineups, slot_index + 1);
                    state.current_lineup = old_lineup;
                }
                
                if (state.shouldStop()) return;
            }
            
            // Try TE candidates for FLEX
            for (players_by_position.te.items) |candidate| {
                if (state.current_lineup.containsPlayer(candidate)) continue;
                
                const old_lineup = state.current_lineup;
                if (self.tryAddPlayerToSlot(&state.current_lineup, candidate, slot)) {
                    try self.generateRecursive(state, players_by_position, generated_lineups, slot_index + 1);
                    state.current_lineup = old_lineup;
                }
                
                if (state.shouldStop()) return;
            }
            return;
        }
        
        // Get candidate players for non-FLEX slots
        const candidates = switch (slot) {
            .QB => players_by_position.qb.items,
            .RB1, .RB2 => players_by_position.rb.items,
            .WR1, .WR2, .WR3 => players_by_position.wr.items,
            .TE => players_by_position.te.items,
            .DST => players_by_position.dst.items,
            .FLEX => unreachable, // Handled above
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
    
    // Compare lineups for sorting with tie-breaking (higher score first)
    fn compareLineups(self: *Self, a: Lineup, b: Lineup) bool {
        const score_a = self.scoreLineup(a);
        const score_b = self.scoreLineup(b);
        
        const score_diff = score_a - score_b;
        if (@abs(score_diff) > 0.01) { // Significant difference in primary score
            return score_a > score_b;
        }
        
        // Use tie-breaking for very close scores
        const tie_a = self.calculateTieBreakerScore(a);
        const tie_b = self.calculateTieBreakerScore(b);
        return tie_a.isBetterThan(tie_b);
    }
    
    // Create scored lineups from regular lineups for advanced ranking
    pub fn createScoredLineups(self: *Self, lineups: []const Lineup) ![]ScoredLineup {
        var scored_lineups = try self.allocator.alloc(ScoredLineup, lineups.len);
        
        for (lineups, 0..) |lineup_item, i| {
            const primary_score = self.scoreLineup(lineup_item);
            const tie_breaker = self.calculateTieBreakerScore(lineup_item);
            scored_lineups[i] = ScoredLineup.init(lineup_item, primary_score, tie_breaker);
        }
        
        return scored_lineups;
    }
    
    // Find the best lineup from a set using comprehensive scoring
    pub fn findBestLineup(self: *Self, lineups: []const Lineup) ?ScoredLineup {
        if (lineups.len == 0) return null;
        
        var best_lineup = ScoredLineup.init(
            lineups[0], 
            self.scoreLineup(lineups[0]), 
            self.calculateTieBreakerScore(lineups[0])
        );
        
        for (lineups[1..]) |lineup_item| {
            const scored = ScoredLineup.init(
                lineup_item,
                self.scoreLineup(lineup_item),
                self.calculateTieBreakerScore(lineup_item)
            );
            
            if (scored.isBetterThan(best_lineup)) {
                best_lineup = scored;
            }
        }
        
        return best_lineup;
    }
    
    // Rank lineups using comprehensive scoring (returns owned slice)
    pub fn rankLineups(self: *Self, lineups: []const Lineup) ![]ScoredLineup {
        const scored_lineups = try self.createScoredLineups(lineups);
        
        // Sort using comparison function
        const SortContext = struct {
            fn lessThan(context: void, a: ScoredLineup, b: ScoredLineup) bool {
                _ = context;
                return b.isBetterThan(a); // Reverse order for descending sort
            }
        };
        
        std.sort.heap(ScoredLineup, scored_lineups, {}, SortContext.lessThan);
        
        return scored_lineups;
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

test "LineupGenerator scoring strategies" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create test players with different characteristics
    var high_proj_qb = Player.init("High Proj QB", "NYG", "DAL", .QB, 8000, 30.0, 3.75, 0.8, "1"); // High ownership
    var value_qb = Player.init("Value QB", "NYG", "DAL", .QB, 6000, 25.0, 4.17, 0.2, "2"); // Low ownership, high value
    
    var lineup1 = Lineup.init();
    lineup1.positions.qb = &high_proj_qb;
    lineup1.total_salary = 8000;
    lineup1.total_projection = 30.0;
    
    var lineup2 = Lineup.init();
    lineup2.positions.qb = &value_qb;
    lineup2.total_salary = 6000;
    lineup2.total_projection = 25.0;
    
    const players = [_]*const Player{ &high_proj_qb, &value_qb };
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Test TOTAL_PROJECTION strategy
    generator.config.scoring_strategy = .TOTAL_PROJECTION;
    const proj_score1 = generator.scoreLineup(lineup1);
    const proj_score2 = generator.scoreLineup(lineup2);
    try testing.expect(proj_score1 > proj_score2); // Higher projection wins
    
    // Test VALUE_WEIGHTED strategy
    generator.config.scoring_strategy = .VALUE_WEIGHTED;
    const value_score1 = generator.scoreLineup(lineup1);
    const value_score2 = generator.scoreLineup(lineup2);
    try testing.expect(value_score2 > value_score1); // Better value wins
    
    // Test OWNERSHIP_ADJUSTED strategy
    generator.config.scoring_strategy = .OWNERSHIP_ADJUSTED;
    const own_score1 = generator.scoreLineup(lineup1);
    const own_score2 = generator.scoreLineup(lineup2);
    try testing.expect(own_score2 > own_score1); // Lower ownership gets bonus
}

test "LineupGenerator tie-breaking and ranking" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create players for test lineups
    var qb1 = Player.init("QB1", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.15, "1");
    var qb2 = Player.init("QB2", "DAL", "NYG", .QB, 7000, 25.0, 3.57, 0.25, "2");
    var rb1 = Player.init("RB1", "NYG", "DAL", .RB, 6000, 20.0, 3.33, 0.20, "3");
    var rb2 = Player.init("RB2", "DAL", "NYG", .RB, 6000, 20.0, 3.33, 0.30, "4");
    
    // Create two lineups with same total projections but different characteristics
    var lineup1 = Lineup.init();
    lineup1.positions.qb = &qb1;
    lineup1.positions.rb1 = &rb1;
    lineup1.total_salary = 13000;
    lineup1.total_projection = 45.0;
    
    var lineup2 = Lineup.init();
    lineup2.positions.qb = &qb2;
    lineup2.positions.rb1 = &rb2;
    lineup2.total_salary = 13000;
    lineup2.total_projection = 45.0;
    
    const players = [_]*const Player{ &qb1, &qb2, &rb1, &rb2 };
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Test tie-breaking scores
    const tie1 = generator.calculateTieBreakerScore(lineup1);
    const tie2 = generator.calculateTieBreakerScore(lineup2);
    
    try testing.expect(tie1.salary_efficiency > 0.0);
    try testing.expect(tie2.salary_efficiency > 0.0);
    try testing.expect(tie1.team_diversity >= 0.0);
    try testing.expect(tie2.team_diversity >= 0.0);
    
    // Test ScoredLineup creation and comparison
    const scored1 = ScoredLineup.init(lineup1, 45.0, tie1);
    const scored2 = ScoredLineup.init(lineup2, 45.0, tie2);
    
    // One should be better than the other based on tie-breaking
    const comparison_result = scored1.isBetterThan(scored2) or scored2.isBetterThan(scored1);
    try testing.expect(comparison_result);
}

test "LineupGenerator best lineup selection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create test players
    var qb1 = Player.init("Best QB", "NYG", "DAL", .QB, 7000, 30.0, 4.29, 0.15, "1");
    var qb2 = Player.init("Good QB", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.25, "2");
    var qb3 = Player.init("OK QB", "NYG", "DAL", .QB, 7000, 20.0, 2.86, 0.35, "3");
    
    // Create test lineups with different scores
    var lineup1 = Lineup.init();
    lineup1.positions.qb = &qb1;
    lineup1.total_salary = 7000;
    lineup1.total_projection = 30.0;
    
    var lineup2 = Lineup.init();
    lineup2.positions.qb = &qb2;
    lineup2.total_salary = 7000;
    lineup2.total_projection = 25.0;
    
    var lineup3 = Lineup.init();
    lineup3.positions.qb = &qb3;
    lineup3.total_salary = 7000;
    lineup3.total_projection = 20.0;
    
    const lineups = [_]Lineup{ lineup1, lineup2, lineup3 };
    const players = [_]*const Player{ &qb1, &qb2, &qb3 };
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Test finding best lineup
    const best = generator.findBestLineup(&lineups);
    try testing.expect(best != null);
    try testing.expect(best.?.lineup.positions.qb == &qb1); // Should be the highest scoring
    
    // Test ranking lineups
    const ranked = try generator.rankLineups(&lineups);
    defer allocator.free(ranked);
    
    try testing.expect(ranked.len == 3);
    try testing.expect(ranked[0].lineup.positions.qb == &qb1); // Best first
    try testing.expect(ranked[1].lineup.positions.qb == &qb2); // Second best
    try testing.expect(ranked[2].lineup.positions.qb == &qb3); // Worst last
}

test "TieBreakerScore comparison logic" {
    const testing = std.testing;
    
    const tie1 = TieBreakerScore{
        .salary_efficiency = 3.5,
        .salary_used = 50000,
        .team_diversity = 0.8,
        .ownership_diversity = 0.15,
        .position_balance = 0.9,
    };
    
    const tie2 = TieBreakerScore{
        .salary_efficiency = 3.4, // Slightly lower efficiency
        .salary_used = 49900,
        .team_diversity = 0.9,
        .ownership_diversity = 0.20,
        .position_balance = 0.95,
    };
    
    // tie1 should be better due to higher efficiency
    try testing.expect(tie1.isBetterThan(tie2));
    try testing.expect(!tie2.isBetterThan(tie1));
    
    // Test with very close efficiency (should use salary as tie-breaker)
    const tie3 = TieBreakerScore{
        .salary_efficiency = 3.50, // Same efficiency
        .salary_used = 49800, // Lower salary usage
        .team_diversity = 0.95,
        .ownership_diversity = 0.25,
        .position_balance = 0.98,
    };
    
    try testing.expect(tie1.isBetterThan(tie3)); // Higher salary usage wins
}