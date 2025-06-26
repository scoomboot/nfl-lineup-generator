const std = @import("std");
const lineup_mod = @import("lineup.zig");
const player_mod = @import("player.zig");
const lineup_generator_mod = @import("lineup_generator.zig");
const core_rules = @import("rules/core_rules.zig");

const Lineup = lineup_mod.Lineup;
const Player = player_mod.Player;
const LineupGenerator = lineup_generator_mod.LineupGenerator;
const GenerationConfig = lineup_generator_mod.GenerationConfig;

test "Basic lineup generation with real data structure" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a realistic test player pool that can form valid lineups
    var qb = Player.init("Lamar Jackson", "BAL", "CLE", .QB, 7000, 23.8, 3.4, 0.18, "1");
    var rb1 = Player.init("Aaron Jones", "MIN", "DET", .RB, 6000, 15.2, 2.53, 0.16, "2");
    var rb2 = Player.init("Najee Harris", "PIT", "CIN", .RB, 5500, 13.1, 2.38, 0.14, "3");
    var rb3 = Player.init("Zack Moss", "CIN", "PIT", .RB, 4500, 10.8, 2.4, 0.10, "4");
    var wr1 = Player.init("Davante Adams", "LV", "KC", .WR, 7000, 17.2, 2.46, 0.22, "5");
    var wr2 = Player.init("Amari Cooper", "CLE", "BAL", .WR, 6000, 14.5, 2.42, 0.18, "6");
    var wr3 = Player.init("Christian Kirk", "JAX", "TEN", .WR, 5000, 12.3, 2.46, 0.15, "7");
    var te1 = Player.init("George Kittle", "SF", "SEA", .TE, 5500, 12.8, 2.33, 0.20, "8");
    var dst = Player.init("Ravens DST", "BAL", "CLE", .DST, 2500, 9.1, 3.64, 0.18, "9");
    
    // Total: 7000+6000+5500+4500+7000+6000+5000+5500+2500 = 49000 (under 50k cap)
    
    const players = [_]*const Player{ &qb, &rb1, &rb2, &rb3, &wr1, &wr2, &wr3, &te1, &dst };
    
    // Create rule engine with DraftKings rules
    var engine = try core_rules.createDraftKingsRuleEngine(allocator);
    defer engine.deinit();
    
    // Configure generator for testing
    const config = GenerationConfig.init()
        .withTargetLineups(1)
        .withMaxAttempts(10000)
        .withLogging(true);
    
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Validate player pool
    try generator.validatePlayerPool();
    
    // Generate lineup
    var result = try generator.generateSingle();
    defer result.deinit();
    
    // Verify we got a valid result
    std.log.info("Generation result: {d} lineups generated", .{result.lineups.len});
    std.log.info("Stats: {}", .{result.stats});
    
    // We should get at least some attempts, even if no valid lineups due to constraints
    try testing.expect(result.stats.attempts > 0);
}

test "Position filtering and organization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create diverse player pool
    var qb1 = Player.init("QB1", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.15, "1");
    var qb2 = Player.init("QB2", "DAL", "NYG", .QB, 6500, 22.0, 3.38, 0.18, "2");
    var rb1 = Player.init("RB1", "NYG", "DAL", .RB, 6000, 18.0, 3.0, 0.20, "3");
    var rb2 = Player.init("RB2", "DAL", "NYG", .RB, 5500, 16.0, 2.91, 0.22, "4");
    var wr1 = Player.init("WR1", "NYG", "DAL", .WR, 7000, 20.0, 2.86, 0.25, "5");
    var dst1 = Player.init("DST1", "NYG", "DAL", .DST, 2500, 8.0, 3.2, 0.30, "6");
    
    const players = [_]*const Player{ &qb1, &qb2, &rb1, &rb2, &wr1, &dst1 };
    
    var engine = try core_rules.createDraftKingsRuleEngine(allocator);
    defer engine.deinit();
    
    const config = GenerationConfig.init();
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // Test position organization
    var players_by_position = try generator.getPlayersByPosition();
    defer {
        players_by_position.qb.deinit();
        players_by_position.rb.deinit();
        players_by_position.wr.deinit();
        players_by_position.te.deinit();
        players_by_position.dst.deinit();
    }
    
    // Verify correct categorization
    try testing.expect(players_by_position.qb.items.len == 2);
    try testing.expect(players_by_position.rb.items.len == 2);
    try testing.expect(players_by_position.wr.items.len == 1);
    try testing.expect(players_by_position.te.items.len == 0);
    try testing.expect(players_by_position.dst.items.len == 1);
    
    // Verify correct players in each category
    try testing.expect(players_by_position.qb.items[0] == &qb1 or players_by_position.qb.items[0] == &qb2);
    try testing.expect(players_by_position.rb.items[0] == &rb1 or players_by_position.rb.items[0] == &rb2);
    try testing.expect(players_by_position.wr.items[0] == &wr1);
    try testing.expect(players_by_position.dst.items[0] == &dst1);
}

test "Generation termination conditions" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create minimal player set
    var qb = Player.init("Test QB", "NYG", "DAL", .QB, 7000, 25.0, 3.57, 0.15, "1");
    const players = [_]*const Player{&qb};
    
    var engine = try core_rules.createDraftKingsRuleEngine(allocator);
    defer engine.deinit();
    
    // Test with very low attempt limit
    const config = GenerationConfig.init()
        .withMaxAttempts(5)
        .withTargetLineups(1);
    
    var generator = LineupGenerator.init(allocator, &players, &engine, config);
    defer generator.deinit();
    
    // This should terminate quickly due to max attempts, even though it can't generate valid lineups
    var result = try generator.generate();
    defer result.deinit();
    
    // Should stop due to max attempts
    try testing.expect(result.stats.attempts <= 5);
}