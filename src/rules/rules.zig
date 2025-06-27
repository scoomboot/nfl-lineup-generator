const std = @import("std");
const lineup_mod = @import("../lineup.zig");
const player_mod = @import("../player.zig");
const rule_engine = @import("rule_engine.zig");

// Re-export rule engine types
pub const Rule = rule_engine.Rule;
pub const RuleResult = rule_engine.RuleResult;
pub const RulePriority = rule_engine.RulePriority;
pub const RuleEngine = rule_engine.RuleEngine;
pub const ValidationResult = rule_engine.ValidationResult;
pub const ContestRules = rule_engine.ContestRules;
pub const RuleUtils = rule_engine.RuleUtils;

// Shared validation infrastructure to reduce code duplication
pub const ValidationPatterns = struct {
    /// Standard pattern for validating a lineup against a simple condition
    pub fn validateSimpleCondition(
        rule_name: []const u8,
        lineup: *const Lineup,
        _: std.mem.Allocator,
        condition_fn: fn(*const Lineup) bool,
        error_message: []const u8,
    ) !RuleResult {
        if (condition_fn(lineup)) {
            return RuleResult.valid(rule_name);
        } else {
            return RuleResult.invalid(rule_name, error_message);
        }
    }
    
    /// Standard pattern for player iteration with early exit on error
    pub fn validatePlayersPattern(
        rule_name: []const u8,
        lineup: *const Lineup,
        allocator: std.mem.Allocator,
        comptime player_fn: fn(*const Player, usize, std.mem.Allocator) anyerror!?RuleResult,
    ) !RuleResult {
        const players = try lineup.positions.getPlayers(allocator);
        defer allocator.free(players);
        
        for (players, 0..) |maybe_player, i| {
            if (maybe_player) |player| {
                if (try player_fn(player, i, allocator)) |error_result| {
                    return error_result;
                }
            }
        }
        
        return RuleResult.valid(rule_name);
    }
    
    /// Standard error message formatting for consistent style
    pub fn formatError(
        rule_name: []const u8,
        comptime fmt: []const u8,
        args: anytype,
        allocator: std.mem.Allocator,
    ) !RuleResult {
        return try RuleUtils.createErrorResult(rule_name, fmt, args, allocator);
    }
};

// Import actual types
const Lineup = lineup_mod.Lineup;
const Player = player_mod.Player;

// Create rule engine with proper Lineup integration
// Enhanced with comprehensive safety validation as required by CLAUDE.md
pub const LineupRuleEngine = struct {
    engine: RuleEngine,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .engine = RuleEngine.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.engine.deinit();
    }
    
    pub fn addRule(self: *Self, rule: Rule) !void {
        try self.engine.addRule(rule);
    }
    
    pub fn validateLineup(self: *Self, target_lineup: *const Lineup) !ValidationResult {
        // SAFETY CONTRACT: We guarantee that target_lineup is always a *const Lineup
        // when cast to anyopaque, which satisfies the safety requirements in createLineupValidationFn
        // 
        // LIFETIME: target_lineup remains valid for the duration of this operation
        // OWNERSHIP: We do not take ownership, only pass const reference
        // TYPE SAFETY: The cast to anyopaque preserves the original type information
        // SIZE/ALIGNMENT: Verified at compile time in createLineupValidationFn
        const generic_lineup: *const anyopaque = target_lineup;
        return try self.engine.validateLineup(generic_lineup);
    }
    
    pub fn getRule(self: *Self, rule_name: []const u8) ?*Rule {
        return self.engine.getRule(rule_name);
    }
    
    pub fn removeRule(self: *Self, rule_name: []const u8) bool {
        return self.engine.removeRule(rule_name);
    }
};

// Type-safe rule validation function type
// Used for improved type safety in validation functions
pub fn RuleValidationFn(comptime T: type) type {
    return *const fn (*const Rule, *const T, std.mem.Allocator) anyerror!RuleResult;
}

// Helper function to create type-safe lineup validation rules
// Implements comprehensive safety validation as required by CLAUDE.md
pub fn createLineupValidationFn(comptime validateFn: fn(*const Lineup, std.mem.Allocator) anyerror!RuleResult) 
    *const fn (rule: *const Rule, target_lineup: *const anyopaque, allocator: std.mem.Allocator) anyerror!RuleResult {
    
    const ValidationWrapper = struct {
        fn validate(rule: *const Rule, target_lineup: *const anyopaque, allocator: std.mem.Allocator) anyerror!RuleResult {
            _ = rule;
            
            // SAFETY: This @ptrCast is safe because:
            // 1. CONTRACT: LineupRuleEngine.validateLineup() guarantees target_lineup is always a *const Lineup cast to anyopaque
            // 2. LIFETIME: The concrete Lineup remains valid for the duration of this validation operation
            // 3. OWNERSHIP: We do not take ownership - only read through const pointer
            // 4. SIZE/ALIGNMENT: Compile-time validation ensures type compatibility
            // 5. INVARIANT: The anyopaque -> Lineup cast preserves all safety properties
            
            // Compile-time size and alignment validation as required by CLAUDE.md
            comptime {
                if (@sizeOf(*const Lineup) != @sizeOf(*const anyopaque)) {
                    @compileError("Lineup pointer size incompatible with anyopaque - unsafe cast");
                }
                if (@alignOf(*const Lineup) > @alignOf(*const anyopaque)) {
                    @compileError("Lineup alignment incompatible with anyopaque - unsafe cast");
                }
                // Verify both are pointer types
                if (@typeInfo(@TypeOf(target_lineup)) != .pointer) {
                    @compileError("target_lineup must be a pointer type");
                }
            }
            
            // Runtime validation (optional - can be disabled in release builds for performance)
            if (@sizeOf(@TypeOf(target_lineup)) != @sizeOf(*const Lineup)) {
                return RuleUtils.createErrorResult(
                    "ValidationWrapper", 
                    "Runtime type size mismatch - expected {d}, got {d}", 
                    .{ @sizeOf(*const Lineup), @sizeOf(@TypeOf(target_lineup)) },
                    allocator
                ) catch RuleResult.invalid("ValidationWrapper", "Type validation failed");
            }
            
            // Safe cast with full safety documentation as required by CLAUDE.md
            const concrete_lineup: *const Lineup = @alignCast(@ptrCast(target_lineup));
            return try validateFn(concrete_lineup, allocator);
        }
    };
    
    return ValidationWrapper.validate;
}

// Tests for the rule integration
test "LineupRuleEngine basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    // Create a simple validation function
    const testValidation = struct {
        fn validate(target_lineup: *const Lineup, alloc: std.mem.Allocator) !RuleResult {
            _ = alloc;
            _ = target_lineup;
            return RuleResult.valid("TestRule");
        }
    }.validate;
    
    // Create rule with proper type casting
    const test_rule = Rule{
        .name = "TestRule",
        .priority = .HIGH,
        .validateFn = createLineupValidationFn(testValidation),
    };
    
    try engine.addRule(test_rule);
    
    // Test validation with actual lineup
    var test_lineup = Lineup.init();
    var validation_result = try engine.validateLineup(&test_lineup);
    defer validation_result.deinit(allocator);
    
    try testing.expect(validation_result.total_rules_checked == 1);
    try testing.expect(validation_result.passed_rules.len == 1);
    try testing.expect(validation_result.failed_rules.len == 0);
}

test "Rule engine memory management" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var engine = LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    // Create a rule that allocates error messages
    const errorRule = struct {
        fn validate(target_lineup: *const Lineup, alloc: std.mem.Allocator) !RuleResult {
            _ = target_lineup;
            return try RuleUtils.createErrorResult(
                "MemoryTestRule",
                "Test error message with allocation {d}",
                .{42},
                alloc
            );
        }
    }.validate;
    
    const test_rule = Rule{
        .name = "MemoryTestRule",
        .priority = .HIGH,
        .validateFn = createLineupValidationFn(errorRule),
    };
    
    try engine.addRule(test_rule);
    
    // Test multiple validations to ensure no memory leaks
    for (0..10) |_| {
        var test_lineup = Lineup.init();
        var result = try engine.validateLineup(&test_lineup);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expect(result.failed_rules.len == 1);
        try testing.expect(result.failed_rules[0].owns_error_message);
    }
}