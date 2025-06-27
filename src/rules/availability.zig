const std = @import("std");
const lineup_mod = @import("../lineup.zig");
const player_mod = @import("../player.zig");
const rules_mod = @import("rules.zig");

const Lineup = lineup_mod.Lineup;
const Player = player_mod.Player;
const InjuryStatus = player_mod.InjuryStatus;
const Rule = rules_mod.Rule;
const RuleResult = rules_mod.RuleResult;
const RuleUtils = rules_mod.RuleUtils;
const createLineupValidationFn = rules_mod.createLineupValidationFn;

pub fn createPlayerAvailabilityRule() Rule {
    return Rule{
        .name = "PlayerAvailabilityRule",
        .priority = .HIGH,
        .validateFn = createLineupValidationFn(validatePlayerAvailability),
    };
}

fn validatePlayerAvailability(lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
    const players = try lineup.positions.getPlayers(allocator);
    defer allocator.free(players);
    
    for (players, 0..) |maybe_player, position_index| {
        if (maybe_player) |player| {
            // Check if player is OUT due to injury
            if (player.injury_status) |injury_status| {
                if (injury_status == .OUT) {
                    return try RuleUtils.createErrorResult(
                        "PlayerAvailabilityRule",
                        "Player {s} in position {d} is marked as OUT and cannot be used",
                        .{ player.name, position_index },
                        allocator
                    );
                }
            }
            
            // Check if player is on bye week
            if (player.is_on_bye) {
                return try RuleUtils.createErrorResult(
                    "PlayerAvailabilityRule",
                    "Player {s} in position {d} is on bye week and cannot be used",
                    .{ player.name, position_index },
                    allocator
                );
            }
        }
    }
    
    return RuleResult.valid("PlayerAvailabilityRule");
}

test "PlayerAvailabilityRule validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const PlayerBuilder = player_mod.PlayerBuilder;
    
    // Create available player
    var available_player = try PlayerBuilder.init()
        .setName("Available Player")
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.RB)
        .setSalary(6000)
        .setProjection(15.0)
        .setValue(2.5)
        .setOwnership(0.20)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(false)
        .build();
    defer available_player.deinit(allocator);
    
    // Create injured (OUT) player
    var out_player = try PlayerBuilder.init()
        .setName("OUT Player")
        .setTeam("DAL")
        .setOpponent("NYG")
        .setPosition(.WR)
        .setSalary(7000)
        .setProjection(18.0)
        .setValue(2.57)
        .setOwnership(0.15)
        .setSlateId("12345")
        .setInjuryStatus(.OUT)
        .setIsOnBye(false)
        .build();
    defer out_player.deinit(allocator);
    
    // Create bye week player
    var bye_player = try PlayerBuilder.init()
        .setName("Bye Player")
        .setTeam("WAS")
        .setOpponent("BYE")
        .setPosition(.QB)
        .setSalary(8000)
        .setProjection(20.0)
        .setValue(2.5)
        .setOwnership(0.12)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setIsOnBye(true)
        .build();
    defer bye_player.deinit(allocator);
    
    // Create questionable player (should be allowed)
    var questionable_player = try PlayerBuilder.init()
        .setName("Questionable Player")
        .setTeam("PHI")
        .setOpponent("WAS")
        .setPosition(.TE)
        .setSalary(5500)
        .setProjection(12.0)
        .setValue(2.18)
        .setOwnership(0.22)
        .setSlateId("12345")
        .setInjuryStatus(.QUESTIONABLE)
        .setIsOnBye(false)
        .build();
    defer questionable_player.deinit(allocator);
    
    // Test case 1: Available players should pass
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&available_player);
        try lineup.addPlayer(&questionable_player);
        
        const result = try validatePlayerAvailability(&lineup, allocator);
        try testing.expect(result.is_valid);
        try testing.expectEqualStrings("PlayerAvailabilityRule", result.rule_name);
    }
    
    // Test case 2: OUT player should fail
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&available_player);
        try lineup.addPlayer(&out_player);
        
        var result = try validatePlayerAvailability(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("PlayerAvailabilityRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "OUT Player") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "marked as OUT") != null);
    }
    
    // Test case 3: Bye week player should fail
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&bye_player);
        
        var result = try validatePlayerAvailability(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("PlayerAvailabilityRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "Bye Player") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "bye week") != null);
    }
    
    // Test case 4: Empty lineup should pass
    {
        var empty_lineup = Lineup.init();
        
        const result = try validatePlayerAvailability(&empty_lineup, allocator);
        try testing.expect(result.is_valid);
    }
    
    // Test case 5: Player with no injury status (null) should pass
    {
        var no_injury_player = try PlayerBuilder.init()
            .setName("No Injury Status")
            .setTeam("ATL")
            .setOpponent("TB")
            .setPosition(.DST)
            .setSalary(4000)
            .setProjection(8.0)
            .setValue(2.0)
            .setOwnership(0.30)
            .setSlateId("12345")
            .setIsOnBye(false)
            .build();
        defer no_injury_player.deinit(allocator);
        
        var lineup = Lineup.init();
        try lineup.addPlayer(&no_injury_player);
        
        const result = try validatePlayerAvailability(&lineup, allocator);
        try testing.expect(result.is_valid);
    }
}

test "PlayerAvailabilityRule integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = rules_mod.LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    try engine.addRule(createPlayerAvailabilityRule());
    
    // Test with empty lineup
    var lineup = Lineup.init();
    
    var result = try engine.validateLineup(&lineup);
    defer result.deinit(allocator);
    
    try testing.expect(result.is_valid);
    try testing.expect(result.passed_rules.len == 1);
    try testing.expect(result.failed_rules.len == 0);
}