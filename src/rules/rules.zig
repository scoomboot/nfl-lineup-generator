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

// Import actual types
const Lineup = lineup_mod.Lineup;
const Player = player_mod.Player;

// Create rule engine with proper Lineup integration
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
        // Cast the concrete Lineup to the opaque type for rule engine
        const opaque_lineup: *const rule_engine.Lineup = @ptrCast(target_lineup);
        return try self.engine.validateLineup(opaque_lineup);
    }
    
    pub fn getRule(self: *Self, rule_name: []const u8) ?*Rule {
        return self.engine.getRule(rule_name);
    }
    
    pub fn removeRule(self: *Self, rule_name: []const u8) bool {
        return self.engine.removeRule(rule_name);
    }
};

// Helper function to create lineup validation rules with proper type casting
pub fn createLineupValidationFn(comptime validateFn: fn(*const Lineup, std.mem.Allocator) anyerror!RuleResult) 
    *const fn (rule: *const Rule, target_lineup: *const rule_engine.Lineup, allocator: std.mem.Allocator) anyerror!RuleResult {
    
    return struct {
        fn validate(rule: *const Rule, target_lineup: *const rule_engine.Lineup, allocator: std.mem.Allocator) anyerror!RuleResult {
            _ = rule;
            // Cast the opaque type back to concrete Lineup
            const concrete_lineup: *const Lineup = @ptrCast(target_lineup);
            return try validateFn(concrete_lineup, allocator);
        }
    }.validate;
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