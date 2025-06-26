const std = @import("std");
const lineup_mod = @import("../lineup.zig");
const rules_mod = @import("rules.zig");

const Lineup = lineup_mod.Lineup;
const Rule = rules_mod.Rule;
const RuleResult = rules_mod.RuleResult;
const RuleUtils = rules_mod.RuleUtils;
const createLineupValidationFn = rules_mod.createLineupValidationFn;

pub fn createUniquePlayerRule() Rule {
    return Rule{
        .name = "UniquePlayerRule",
        .priority = .CRITICAL,
        .validateFn = createLineupValidationFn(validateUniquePlayer),
    };
}

fn validateUniquePlayer(lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
    const players = try lineup.positions.getPlayers(allocator);
    defer allocator.free(players);
    
    // Check for duplicates by comparing player pointers
    for (players, 0..) |player1, i| {
        if (player1 == null) continue;
        
        for (players[i + 1..], i + 1..) |player2, j| {
            if (player2 == null) continue;
            
            // Compare player pointers - same pointer = same player instance
            if (player1.? == player2.?) {
                return try RuleUtils.createErrorResult(
                    "UniquePlayerRule",
                    "Duplicate player found: {s} appears in positions {d} and {d}",
                    .{ player1.?.name, i, j },
                    allocator
                );
            }
            
            // Also check for same player name as additional safety
            if (std.mem.eql(u8, player1.?.name, player2.?.name)) {
                return try RuleUtils.createErrorResult(
                    "UniquePlayerRule",
                    "Duplicate player name found: {s} appears in positions {d} and {d}",
                    .{ player1.?.name, i, j },
                    allocator
                );
            }
        }
    }
    
    return RuleResult.valid("UniquePlayerRule");
}

test "UniquePlayerRule validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const player_mod = @import("../player.zig");
    const PlayerBuilder = player_mod.PlayerBuilder;
    
    // Create sample players
    var player1 = try PlayerBuilder.init(allocator)
        .setName("Player 1")
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.RB)
        .setSalary(6000)
        .setProjection(15.0)
        .setValue(2.5)
        .setOwnership(0.20)
        .setSlateId("12345")
        .build();
    defer player1.deinit(allocator);
    
    var player2 = try PlayerBuilder.init(allocator)
        .setName("Player 2")
        .setTeam("DAL")
        .setOpponent("NYG")
        .setPosition(.RB)
        .setSalary(5500)
        .setProjection(13.0)
        .setValue(2.36)
        .setOwnership(0.25)
        .setSlateId("12345")
        .build();
    defer player2.deinit(allocator);
    
    var duplicate_name_player = try PlayerBuilder.init(allocator)
        .setName("Player 1")  // Same name as player1
        .setTeam("WAS")
        .setOpponent("PHI")
        .setPosition(.WR)
        .setSalary(7000)
        .setProjection(16.0)
        .setValue(2.29)
        .setOwnership(0.18)
        .setSlateId("12345")
        .build();
    defer duplicate_name_player.deinit(allocator);
    
    // Test case 1: No duplicates should pass
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&player1);
        try lineup.addPlayer(&player2);
        
        const result = try validateUniquePlayer(&lineup, allocator);
        try testing.expect(result.is_valid);
        try testing.expectEqualStrings("UniquePlayerRule", result.rule_name);
    }
    
    // Test case 2: Duplicate player pointer should fail
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&player1);
        // Manually add the same player to another position (this wouldn't happen through normal API)
        lineup.positions.rb2 = &player1;  // Same pointer as rb1
        
        var result = try validateUniquePlayer(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("UniquePlayerRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "Duplicate player found") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "Player 1") != null);
    }
    
    // Test case 3: Duplicate player name should fail
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&player1);
        try lineup.addPlayer(&duplicate_name_player);
        
        var result = try validateUniquePlayer(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("UniquePlayerRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "Duplicate player name found") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "Player 1") != null);
    }
    
    // Test case 4: Empty lineup should pass
    {
        var empty_lineup = Lineup.init();
        
        const result = try validateUniquePlayer(&empty_lineup, allocator);
        try testing.expect(result.is_valid);
    }
}

test "UniquePlayerRule integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = rules_mod.LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    try engine.addRule(createUniquePlayerRule());
    
    // Test with valid lineup
    var valid_lineup = Lineup.init();
    
    var valid_result = try engine.validateLineup(&valid_lineup);
    defer valid_result.deinit(allocator);
    
    try testing.expect(valid_result.is_valid);
    try testing.expect(valid_result.passed_rules.len == 1);
    try testing.expect(valid_result.failed_rules.len == 0);
}