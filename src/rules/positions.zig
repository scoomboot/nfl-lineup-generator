const std = @import("std");
const lineup_mod = @import("../lineup.zig");
const rules_mod = @import("rules.zig");

const Lineup = lineup_mod.Lineup;
const Rule = rules_mod.Rule;
const RuleResult = rules_mod.RuleResult;
const RuleUtils = rules_mod.RuleUtils;
const createLineupValidationFn = rules_mod.createLineupValidationFn;

pub fn createPositionConstraintRule() Rule {
    return Rule{
        .name = "PositionConstraintRule",
        .priority = .CRITICAL,
        .validateFn = createLineupValidationFn(validatePositionConstraints),
    };
}

pub fn createFlexPositionRule() Rule {
    return Rule{
        .name = "FlexPositionRule", 
        .priority = .CRITICAL,
        .validateFn = createLineupValidationFn(validateFlexPosition),
    };
}

fn validatePositionConstraints(lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
    const positions = lineup.positions;
    
    // Check QB (exactly 1)
    if (positions.qb == null) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 1 QB (found 0)",
            .{},
            allocator
        );
    }
    
    // Check RB (exactly 2)
    const rb_count = @as(u8, if (positions.rb1 != null) 1 else 0) + 
                     @as(u8, if (positions.rb2 != null) 1 else 0);
    if (rb_count != 2) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 2 RB (found {d})",
            .{rb_count},
            allocator
        );
    }
    
    // Check WR (exactly 3)
    const wr_count = @as(u8, if (positions.wr1 != null) 1 else 0) +
                     @as(u8, if (positions.wr2 != null) 1 else 0) +
                     @as(u8, if (positions.wr3 != null) 1 else 0);
    if (wr_count != 3) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 3 WR (found {d})",
            .{wr_count},
            allocator
        );
    }
    
    // Check TE (exactly 1)
    if (positions.te == null) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 1 TE (found 0)",
            .{},
            allocator
        );
    }
    
    // Check FLEX (exactly 1)
    if (positions.flex == null) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 1 FLEX (found 0)",
            .{},
            allocator
        );
    }
    
    // Check DST (exactly 1)
    if (positions.dst == null) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 1 DST (found 0)",
            .{},
            allocator
        );
    }
    
    // Check total positions (should be 9)
    const total_filled = positions.getFilledCount();
    if (total_filled != 9) {
        return try RuleUtils.createErrorResult(
            "PositionConstraintRule",
            "Lineup must have exactly 9 positions filled (found {d})",
            .{total_filled},
            allocator
        );
    }
    
    return RuleResult.valid("PositionConstraintRule");
}

fn validateFlexPosition(lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
    const flex_player = lineup.positions.flex;
    
    if (flex_player == null) {
        // FlexPositionRule only validates if FLEX position is filled
        // PositionConstraintRule will catch empty FLEX
        return RuleResult.valid("FlexPositionRule");
    }
    
    const player_position = flex_player.?.position;
    if (!player_position.isFlexEligible()) {
        return try RuleUtils.createErrorResult(
            "FlexPositionRule",
            "FLEX position must be filled by RB, WR, or TE (found {s})",
            .{@tagName(player_position)},
            allocator
        );
    }
    
    return RuleResult.valid("FlexPositionRule");
}

test "PositionConstraintRule validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const player_mod = @import("../player.zig");
    const Player = player_mod.Player;
    const Position = player_mod.Position;
    const PlayerBuilder = player_mod.PlayerBuilder;
    
    // Create sample players for testing
    var qb_player = try PlayerBuilder.init(allocator)
        .setName("QB1")
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.QB)
        .setSalary(7500)
        .setProjection(20.5)
        .setValue(2.73)
        .setOwnership(0.15)
        .setSlateId("12345")
        .build();
    defer qb_player.deinit(allocator);
    
    var rb1_player = try PlayerBuilder.init(allocator)
        .setName("RB1")
        .setTeam("NYG")  
        .setOpponent("DAL")
        .setPosition(.RB)
        .setSalary(6500)
        .setProjection(18.0)
        .setValue(2.77)
        .setOwnership(0.20)
        .setSlateId("12345")
        .build();
    defer rb1_player.deinit(allocator);
    
    var rb2_player = try PlayerBuilder.init(allocator)
        .setName("RB2")
        .setTeam("DAL")
        .setOpponent("NYG")
        .setPosition(.RB)
        .setSalary(5500)
        .setProjection(15.0)
        .setValue(2.73)
        .setOwnership(0.25)
        .setSlateId("12345")
        .build();
    defer rb2_player.deinit(allocator);
    
    // Test case 1: Empty lineup should fail
    {
        var empty_lineup = Lineup.init();
        
        var result = try validatePositionConstraints(&empty_lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("PositionConstraintRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "QB") != null);
    }
    
    // Test case 2: Missing RB should fail
    {
        var partial_lineup = Lineup.init();
        try partial_lineup.addPlayer(&qb_player);
        
        var result = try validatePositionConstraints(&partial_lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "RB") != null);
    }
    
    // Test case 3: Only 1 RB should fail  
    {
        var partial_lineup = Lineup.init();
        try partial_lineup.addPlayer(&qb_player);
        try partial_lineup.addPlayer(&rb1_player);
        
        var result = try validatePositionConstraints(&partial_lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "exactly 2 RB (found 1)") != null);
    }
}

test "FlexPositionRule validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const player_mod = @import("../player.zig");
    const PlayerBuilder = player_mod.PlayerBuilder;
    
    // Create sample players
    var rb_player = try PlayerBuilder.init(allocator)
        .setName("Flex RB")
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.RB)
        .setSalary(5000)
        .setProjection(12.0)
        .setValue(2.4)
        .setOwnership(0.30)
        .setSlateId("12345")
        .build();
    defer rb_player.deinit(allocator);
    
    var qb_player = try PlayerBuilder.init(allocator)
        .setName("QB1")
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.QB)
        .setSalary(7500)
        .setProjection(20.5)
        .setValue(2.73)
        .setOwnership(0.15)
        .setSlateId("12345")
        .build();
    defer qb_player.deinit(allocator);
    
    // Test case 1: Empty FLEX should pass (other rule will catch this)
    {
        var lineup = Lineup.init();
        
        const result = try validateFlexPosition(&lineup, allocator);
        try testing.expect(result.is_valid);
    }
    
    // Test case 2: Valid FLEX (RB) should pass
    {
        var lineup = Lineup.init();
        try lineup.addToFlex(&rb_player);
        
        const result = try validateFlexPosition(&lineup, allocator);
        try testing.expect(result.is_valid);
    }
    
    // Test case 3: Invalid FLEX (QB) should fail
    {
        var lineup = Lineup.init();
        // Manually set flex to invalid position (this wouldn't happen through normal API)
        lineup.positions.flex = &qb_player;
        
        var result = try validateFlexPosition(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "FLEX position must be filled by RB, WR, or TE") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "QB") != null);
    }
}

test "Position rules integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = rules_mod.LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    try engine.addRule(createPositionConstraintRule());
    try engine.addRule(createFlexPositionRule());
    
    // Test with empty lineup
    var empty_lineup = Lineup.init();
    
    var result = try engine.validateLineup(&empty_lineup);
    defer result.deinit(allocator);
    
    try testing.expect(!result.is_valid);
    try testing.expect(result.failed_rules.len >= 1);
}