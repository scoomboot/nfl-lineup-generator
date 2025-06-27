const std = @import("std");
const rules_mod = @import("rules.zig");

// Import all core rule modules
const salary_cap = @import("salary_cap.zig");
const positions = @import("positions.zig");
const unique_player = @import("unique_player.zig");
const team_limits = @import("team_limits.zig");
const availability = @import("availability.zig");

// Re-export rule engine types
pub const Rule = rules_mod.Rule;
pub const LineupRuleEngine = rules_mod.LineupRuleEngine;
pub const ValidationResult = rules_mod.ValidationResult;

// Core rule factory functions
pub const createSalaryCapRule = salary_cap.createSalaryCapRule;
pub const createPositionConstraintRule = positions.createPositionConstraintRule;
pub const createFlexPositionRule = positions.createFlexPositionRule;
pub const createUniquePlayerRule = unique_player.createUniquePlayerRule;
pub const createTeamLimitRule = team_limits.createTeamLimitRule;
pub const createPlayerAvailabilityRule = availability.createPlayerAvailabilityRule;

// Convenience function to create a rule engine with all core DraftKings rules
pub fn createDraftKingsRuleEngine(allocator: std.mem.Allocator) !LineupRuleEngine {
    var engine = LineupRuleEngine.init(allocator);
    
    // Add all core rules in priority order
    try engine.addRule(createSalaryCapRule());
    try engine.addRule(createPositionConstraintRule());
    try engine.addRule(createFlexPositionRule());
    try engine.addRule(createUniquePlayerRule());
    try engine.addRule(createTeamLimitRule());
    try engine.addRule(createPlayerAvailabilityRule());
    
    return engine;
}

test "All core rules integration test" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const lineup_mod = @import("../lineup.zig");
    const player_mod = @import("../player.zig");
    const Lineup = lineup_mod.Lineup;
    const PlayerBuilder = player_mod.PlayerBuilder;
    
    // Create a fully valid DraftKings lineup
    var qb = try PlayerBuilder.init()
        .setName("Josh Allen")
        .setTeam("BUF")
        .setOpponent("MIA")
        .setPosition(.QB)
        .setSalary(8200)
        .setProjection(22.5)
        .setValue(2.74)
        .setOwnership(0.18)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer qb.deinit(allocator);
    
    var rb1 = try PlayerBuilder.init()
        .setName("Saquon Barkley")
        .setTeam("PHI")
        .setOpponent("WAS")
        .setPosition(.RB)
        .setSalary(7800)
        .setProjection(18.2)
        .setValue(2.33)
        .setOwnership(0.25)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer rb1.deinit(allocator);
    
    var rb2 = try PlayerBuilder.init()
        .setName("Josh Jacobs")
        .setTeam("GB")
        .setOpponent("MIN")
        .setPosition(.RB)
        .setSalary(6800)
        .setProjection(15.8)
        .setValue(2.32)
        .setOwnership(0.22)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer rb2.deinit(allocator);
    
    var wr1 = try PlayerBuilder.init()
        .setName("Tyreek Hill")
        .setTeam("MIA")
        .setOpponent("BUF")
        .setPosition(.WR)
        .setSalary(7500)
        .setProjection(16.5)
        .setValue(2.20)
        .setOwnership(0.20)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer wr1.deinit(allocator);
    
    var wr2 = try PlayerBuilder.init()
        .setName("A.J. Brown")
        .setTeam("PHI")
        .setOpponent("WAS")
        .setPosition(.WR)
        .setSalary(6900)
        .setProjection(14.8)
        .setValue(2.14)
        .setOwnership(0.15)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer wr2.deinit(allocator);
    
    var wr3 = try PlayerBuilder.init()
        .setName("Jaylen Waddle")
        .setTeam("MIA")
        .setOpponent("BUF")
        .setPosition(.WR)
        .setSalary(6200)
        .setProjection(13.2)
        .setValue(2.13)
        .setOwnership(0.18)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer wr3.deinit(allocator);
    
    var te = try PlayerBuilder.init()
        .setName("Travis Kelce")
        .setTeam("KC")
        .setOpponent("DEN")
        .setPosition(.TE)
        .setSalary(6500)
        .setProjection(14.0)
        .setValue(2.15)
        .setOwnership(0.12)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer te.deinit(allocator);
    
    var flex = try PlayerBuilder.init()
        .setName("Amari Cooper")
        .setTeam("BUF")
        .setOpponent("MIA")
        .setPosition(.WR)
        .setSalary(5100)
        .setProjection(11.5)
        .setValue(2.25)
        .setOwnership(0.14)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer flex.deinit(allocator);
    
    var dst = try PlayerBuilder.init()
        .setName("Bills DST")
        .setTeam("BUF")
        .setOpponent("MIA")
        .setPosition(.DST)
        .setSalary(3000)
        .setProjection(8.5)
        .setValue(2.83)
        .setOwnership(0.08)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer dst.deinit(allocator);
    
    // Create and populate a valid lineup
    var valid_lineup = Lineup.init();
    try valid_lineup.addPlayer(&qb);
    try valid_lineup.addPlayer(&rb1);
    try valid_lineup.addPlayer(&rb2);
    try valid_lineup.addPlayer(&wr1);
    try valid_lineup.addPlayer(&wr2);
    try valid_lineup.addPlayer(&wr3);
    try valid_lineup.addPlayer(&te);
    try valid_lineup.addToFlex(&flex);
    try valid_lineup.addPlayer(&dst);
    
    // Manually set salary to exactly $50,000 for salary cap rule
    valid_lineup.total_salary = 50000;
    
    // Test with full DraftKings rule engine
    var engine = try createDraftKingsRuleEngine(allocator);
    defer engine.deinit();
    
    var result = try engine.validateLineup(&valid_lineup);
    defer result.deinit(allocator);
    
    // All rules should pass
    try testing.expect(result.is_valid);
    try testing.expect(result.total_rules_checked == 6);
    try testing.expect(result.passed_rules.len == 6);
    try testing.expect(result.failed_rules.len == 0);
    try testing.expect(result.warning_rules.len == 0);
    
    // Verify all expected rules are present
    const expected_rule_names = [_][]const u8{
        "SalaryCapRule",
        "PositionConstraintRule", 
        "FlexPositionRule",
        "UniquePlayerRule",
        "TeamLimitRule",
        "PlayerAvailabilityRule"
    };
    
    for (expected_rule_names) |expected_name| {
        var found = false;
        for (result.passed_rules) |passed_rule| {
            if (std.mem.eql(u8, passed_rule.rule_name, expected_name)) {
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "Core rules failure scenarios" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const lineup_mod = @import("../lineup.zig");
    const Lineup = lineup_mod.Lineup;
    
    var engine = try createDraftKingsRuleEngine(allocator);
    defer engine.deinit();
    
    // Test case 1: Empty lineup should fail multiple rules
    {
        var empty_lineup = Lineup.init();
        
        var result = try engine.validateLineup(&empty_lineup);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expect(result.failed_rules.len >= 2); // At least salary cap and position constraints
    }
    
    // Test case 2: Wrong salary should fail salary cap rule
    {
        var wrong_salary_lineup = Lineup.init();
        wrong_salary_lineup.total_salary = 45000; // Too low
        
        var result = try engine.validateLineup(&wrong_salary_lineup);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        
        // Find the salary cap rule failure
        var found_salary_failure = false;
        for (result.failed_rules) |failed_rule| {
            if (std.mem.eql(u8, failed_rule.rule_name, "SalaryCapRule")) {
                found_salary_failure = true;
                break;
            }
        }
        try testing.expect(found_salary_failure);
    }
}