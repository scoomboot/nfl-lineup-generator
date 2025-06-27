const std = @import("std");
const lineup_mod = @import("../lineup.zig");
const rules_mod = @import("rules.zig");

const Lineup = lineup_mod.Lineup;
const Rule = rules_mod.Rule;
const RuleResult = rules_mod.RuleResult;
const RuleUtils = rules_mod.RuleUtils;
const createLineupValidationFn = rules_mod.createLineupValidationFn;

const MAX_PLAYERS_PER_TEAM: u8 = 8;

pub fn createTeamLimitRule() Rule {
    return Rule{
        .name = "TeamLimitRule",
        .priority = .HIGH,
        .validateFn = createLineupValidationFn(validateTeamLimits),
    };
}

fn validateTeamLimits(lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
    const players = try lineup.positions.getPlayers(allocator);
    defer allocator.free(players);
    
    // Optimized team counting using a simple approach
    // Instead of HashMap, use direct counting since we only have 9 players max
    var team_counts = std.ArrayList(TeamCount).init(allocator);
    defer team_counts.deinit();
    
    for (players) |maybe_player| {
        if (maybe_player) |player| {
            // Look for existing team in our list
            var found = false;
            for (team_counts.items) |*team_count| {
                if (std.mem.eql(u8, team_count.team_name, player.team)) {
                    team_count.count += 1;
                    found = true;
                    break;
                }
            }
            
            // If team not found, add new entry
            if (!found) {
                try team_counts.append(TeamCount{
                    .team_name = player.team,
                    .count = 1,
                });
            }
        }
    }
    
    // Check for teams exceeding the limit
    for (team_counts.items) |team_count| {
        if (team_count.count > MAX_PLAYERS_PER_TEAM) {
            return try RuleUtils.createErrorResult(
                "TeamLimitRule",
                "Team {s} has {d} players, exceeding the maximum of {d}",
                .{ team_count.team_name, team_count.count, MAX_PLAYERS_PER_TEAM },
                allocator
            );
        }
    }
    
    return RuleResult.valid("TeamLimitRule");
}

// Simple struct for team counting - more efficient than HashMap for small counts
const TeamCount = struct {
    team_name: []const u8,
    count: u8,
};

test "TeamLimitRule validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const player_mod = @import("../player.zig");
    const PlayerBuilder = player_mod.PlayerBuilder;
    
    // Create players from different teams
    var player1_nyg = try PlayerBuilder.init()
        .setName("NYG Player 1")
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.QB)
        .setSalary(7000)
        .setProjection(18.0)
        .setValue(2.57)
        .setOwnership(0.15)
        .setSlateId("12345")
        .build();
    defer player1_nyg.deinit(allocator);
    
    var player2_nyg = try PlayerBuilder.init()
        .setName("NYG Player 2") 
        .setTeam("NYG")
        .setOpponent("DAL")
        .setPosition(.RB)
        .setSalary(6000)
        .setProjection(15.0)
        .setValue(2.5)
        .setOwnership(0.20)
        .setSlateId("12345")
        .build();
    defer player2_nyg.deinit(allocator);
    
    var player1_dal = try PlayerBuilder.init()
        .setName("DAL Player 1")
        .setTeam("DAL")
        .setOpponent("NYG")
        .setPosition(.WR)
        .setSalary(5500)
        .setProjection(12.0)
        .setValue(2.18)
        .setOwnership(0.25)
        .setSlateId("12345")
        .build();
    defer player1_dal.deinit(allocator);
    
    // Test case 1: Normal distribution should pass
    {
        var lineup = Lineup.init();
        try lineup.addPlayer(&player1_nyg);
        try lineup.addPlayer(&player2_nyg);
        try lineup.addPlayer(&player1_dal);
        
        const result = try validateTeamLimits(&lineup, allocator);
        try testing.expect(result.is_valid);
        try testing.expectEqualStrings("TeamLimitRule", result.rule_name);
    }
    
    // Test case 2: Empty lineup should pass
    {
        var empty_lineup = Lineup.init();
        
        const result = try validateTeamLimits(&empty_lineup, allocator);
        try testing.expect(result.is_valid);
    }
    
    // Test case 3: Simulate exceeding team limit
    // We'll create a lineup with all 9 players from same team to test the violation
    {
        var lineup = Lineup.init();
        
        // Create 9 players from the same team (simulating all positions filled)
        var players_same_team = [_]*player_mod.Player{undefined} ** 9;
        const positions = [_]player_mod.Position{ .QB, .RB, .RB, .WR, .WR, .WR, .TE, .RB, .DST };
        
        for (&players_same_team, 0..) |*player_ptr, i| {
            var name_buf: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "Player {d}", .{i});
            
            const temp_player = try PlayerBuilder.init()
                .setName(name)
                .setTeam("NYG")  // All same team
                .setOpponent("DAL")
                .setPosition(positions[i])
                .setSalary(5000 + @as(u32, @intCast(i)) * 100)
                .setProjection(10.0 + @as(f32, @floatFromInt(i)))
                .setValue(2.0)
                .setOwnership(0.10 * @as(f32, @floatFromInt(i + 1)))
                .setSlateId("12345")
                .build();
            player_ptr.* = temp_player;
        }
        defer {
            for (players_same_team) |player| {
                player.deinit(allocator);
            }
        }
        
        // Add players to lineup manually to bypass position validation
        lineup.positions.qb = &players_same_team[0];
        lineup.positions.rb1 = &players_same_team[1];
        lineup.positions.rb2 = &players_same_team[2];
        lineup.positions.wr1 = &players_same_team[3];
        lineup.positions.wr2 = &players_same_team[4];
        lineup.positions.wr3 = &players_same_team[5];
        lineup.positions.te = &players_same_team[6];
        lineup.positions.flex = &players_same_team[7];
        lineup.positions.dst = &players_same_team[8];
        
        var result = try validateTeamLimits(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("TeamLimitRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "NYG has 9 players") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "maximum of 8") != null);
    }
}

test "TeamLimitRule integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = rules_mod.LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    try engine.addRule(createTeamLimitRule());
    
    // Test with empty lineup
    var lineup = Lineup.init();
    
    var result = try engine.validateLineup(&lineup);
    defer result.deinit(allocator);
    
    try testing.expect(result.is_valid);
    try testing.expect(result.passed_rules.len == 1);
    try testing.expect(result.failed_rules.len == 0);
}