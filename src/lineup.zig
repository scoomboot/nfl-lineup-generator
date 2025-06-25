const std = @import("std");
const player = @import("player.zig");
const Player = player.Player;
const Position = player.Position;

// DraftKings Classic lineup structure (9 players total)
pub const DKClassicPositions = struct {
    qb: ?*const Player = null,     // 1 QB
    rb1: ?*const Player = null,    // 2 RB
    rb2: ?*const Player = null,
    wr1: ?*const Player = null,    // 3 WR  
    wr2: ?*const Player = null,
    wr3: ?*const Player = null,
    te: ?*const Player = null,     // 1 TE
    flex: ?*const Player = null,   // 1 FLEX (RB/WR/TE)
    dst: ?*const Player = null,    // 1 DST

    const Self = @This();

    // Get all players as a slice for iteration
    pub fn getPlayers(self: Self, allocator: std.mem.Allocator) ![]?*const Player {
        var players = std.ArrayList(?*const Player).init(allocator);
        defer players.deinit();
        
        try players.append(self.qb);
        try players.append(self.rb1);
        try players.append(self.rb2);
        try players.append(self.wr1);
        try players.append(self.wr2);
        try players.append(self.wr3);
        try players.append(self.te);
        try players.append(self.flex);
        try players.append(self.dst);
        
        return players.toOwnedSlice();
    }

    // Count how many positions are filled
    pub fn getFilledCount(self: Self) u8 {
        var count: u8 = 0;
        if (self.qb != null) count += 1;
        if (self.rb1 != null) count += 1;
        if (self.rb2 != null) count += 1;
        if (self.wr1 != null) count += 1;
        if (self.wr2 != null) count += 1;
        if (self.wr3 != null) count += 1;
        if (self.te != null) count += 1;
        if (self.flex != null) count += 1;
        if (self.dst != null) count += 1;
        return count;
    }

    // Check if lineup is complete (all 9 positions filled)
    pub fn isComplete(self: Self) bool {
        return self.getFilledCount() == 9;
    }
};

// Main lineup struct
pub const Lineup = struct {
    positions: DKClassicPositions,
    total_salary: u32 = 0,
    total_projection: f32 = 0.0,
    
    // Metadata
    id: ?[]const u8 = null,
    created_at: ?i64 = null,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .positions = DKClassicPositions{},
        };
    }

    // Add a player to the appropriate position
    pub fn addPlayer(self: *Self, new_player: *const Player) !void {
        switch (new_player.position) {
            .QB => {
                if (self.positions.qb != null) return error.PositionAlreadyFilled;
                self.positions.qb = new_player;
            },
            .RB => {
                if (self.positions.rb1 == null) {
                    self.positions.rb1 = new_player;
                } else if (self.positions.rb2 == null) {
                    self.positions.rb2 = new_player;
                } else {
                    return error.PositionFull;
                }
            },
            .WR => {
                if (self.positions.wr1 == null) {
                    self.positions.wr1 = new_player;
                } else if (self.positions.wr2 == null) {
                    self.positions.wr2 = new_player;
                } else if (self.positions.wr3 == null) {
                    self.positions.wr3 = new_player;
                } else {
                    return error.PositionFull;
                }
            },
            .TE => {
                if (self.positions.te != null) return error.PositionAlreadyFilled;
                self.positions.te = new_player;
            },
            .DST => {
                if (self.positions.dst != null) return error.PositionAlreadyFilled;
                self.positions.dst = new_player;
            },
            .FLEX => {
                // FLEX position should not be added directly - use addToFlex
                return error.InvalidFlexAddition;
            },
        }
        
        // Update totals
        self.total_salary += new_player.salary;
        self.total_projection += new_player.projection;
    }

    // Add a FLEX-eligible player to the FLEX position
    pub fn addToFlex(self: *Self, new_player: *const Player) !void {
        if (!new_player.position.isFlexEligible()) {
            return error.NotFlexEligible;
        }
        if (self.positions.flex != null) {
            return error.PositionAlreadyFilled;
        }
        
        self.positions.flex = new_player;
        self.total_salary += new_player.salary;
        self.total_projection += new_player.projection;
    }

    // Remove a player from the lineup
    pub fn removePlayer(self: *Self, target_player: *const Player) !void {
        if (self.positions.qb == target_player) {
            self.positions.qb = null;
        } else if (self.positions.rb1 == target_player) {
            self.positions.rb1 = null;
        } else if (self.positions.rb2 == target_player) {
            self.positions.rb2 = null;
        } else if (self.positions.wr1 == target_player) {
            self.positions.wr1 = null;
        } else if (self.positions.wr2 == target_player) {
            self.positions.wr2 = null;
        } else if (self.positions.wr3 == target_player) {
            self.positions.wr3 = null;
        } else if (self.positions.te == target_player) {
            self.positions.te = null;
        } else if (self.positions.flex == target_player) {
            self.positions.flex = null;
        } else if (self.positions.dst == target_player) {
            self.positions.dst = null;
        } else {
            return error.PlayerNotInLineup;
        }
        
        // Update totals
        self.total_salary -= target_player.salary;
        self.total_projection -= target_player.projection;
    }

    // Check if a specific player is in the lineup
    pub fn containsPlayer(self: Self, target_player: *const Player) bool {
        return (self.positions.qb == target_player or
                self.positions.rb1 == target_player or
                self.positions.rb2 == target_player or
                self.positions.wr1 == target_player or
                self.positions.wr2 == target_player or
                self.positions.wr3 == target_player or
                self.positions.te == target_player or
                self.positions.flex == target_player or
                self.positions.dst == target_player);
    }

    // Get count of players from a specific team
    pub fn getTeamCount(self: Self, team: []const u8) u8 {
        var count: u8 = 0;
        
        if (self.positions.qb) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.rb1) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.rb2) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.wr1) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.wr2) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.wr3) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.te) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.flex) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        if (self.positions.dst) |p| {
            if (std.mem.eql(u8, p.team, team)) count += 1;
        }
        
        return count;
    }

    // Check if lineup meets basic position requirements
    pub fn isValid(self: Self) bool {
        return self.positions.isComplete();
    }

    // Check if lineup is under salary cap
    pub fn isUnderSalaryCap(self: Self, salary_cap: u32) bool {
        return self.total_salary <= salary_cap;
    }

    // Calculate lineup efficiency (projection per $1000 of salary)
    pub fn getEfficiency(self: Self) f32 {
        if (self.total_salary == 0) return 0.0;
        return self.total_projection / (@as(f32, @floatFromInt(self.total_salary)) / 1000.0);
    }

    // Get remaining salary cap space
    pub fn getRemainingSalary(self: Self, salary_cap: u32) i32 {
        return @as(i32, @intCast(salary_cap)) - @as(i32, @intCast(self.total_salary));
    }

    // Format lineup for display
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("Lineup (${d}, {d:.1}pts):\n", .{ self.total_salary, self.total_projection });
        
        if (self.positions.qb) |p| {
            try writer.print("  QB:  {}\n", .{p});
        }
        if (self.positions.rb1) |p| {
            try writer.print("  RB1: {}\n", .{p});
        }
        if (self.positions.rb2) |p| {
            try writer.print("  RB2: {}\n", .{p});
        }
        if (self.positions.wr1) |p| {
            try writer.print("  WR1: {}\n", .{p});
        }
        if (self.positions.wr2) |p| {
            try writer.print("  WR2: {}\n", .{p});
        }
        if (self.positions.wr3) |p| {
            try writer.print("  WR3: {}\n", .{p});
        }
        if (self.positions.te) |p| {
            try writer.print("  TE:  {}\n", .{p});
        }
        if (self.positions.flex) |p| {
            try writer.print("  FLEX: {}\n", .{p});
        }
        if (self.positions.dst) |p| {
            try writer.print("  DST: {}\n", .{p});
        }
    }
};

// Lineup utility functions
pub const LineupUtils = struct {
    // Constants for DraftKings Classic constraints
    pub const DK_SALARY_CAP: u32 = 50000;
    pub const DK_MAX_TEAM_PLAYERS: u8 = 8;
    pub const DK_REQUIRED_PLAYERS: u8 = 9;

    // Position count requirements
    pub const REQUIRED_QB: u8 = 1;
    pub const REQUIRED_RB: u8 = 2;
    pub const REQUIRED_WR: u8 = 3;
    pub const REQUIRED_TE: u8 = 1;
    pub const REQUIRED_FLEX: u8 = 1;
    pub const REQUIRED_DST: u8 = 1;

    // Validate lineup meets all DraftKings requirements
    pub fn validateDraftKingsLineup(lineup: Lineup) !void {
        // Check position count
        if (!lineup.isValid()) {
            return error.IncompleteLineup;
        }

        // Check salary cap
        if (!lineup.isUnderSalaryCap(DK_SALARY_CAP)) {
            return error.SalaryCapExceeded;
        }

        // Check FLEX eligibility
        if (lineup.positions.flex) |flex_player| {
            if (!flex_player.position.isFlexEligible()) {
                return error.InvalidFlexPosition;
            }
        }

        // Check team limits - need to verify no team has more than 8 players
        // This would require iterating through all teams represented in lineup
        // Implementation depends on having team information available
    }

    // Calculate lineup diversity score (lower is more diverse)
    pub fn calculateDiversityScore(lineup: Lineup) f32 {
        // Simple diversity based on team concentration
        // More sophisticated diversity could include ownership, stacking, etc.
        var team_counts = std.HashMap([]const u8, u8, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(std.heap.page_allocator);
        defer team_counts.deinit();

        // This is a simplified implementation - real version would need proper allocation handling
        _ = lineup;
        return 0.0; // Placeholder
    }
};

// Tests for lineup module
test "Lineup basic operations" {
    const testing = std.testing;

    var lineup = Lineup.init();
    
    // Test initial state
    try testing.expect(!lineup.isValid());
    try testing.expect(lineup.total_salary == 0);
    try testing.expect(lineup.total_projection == 0.0);

    // Create test players
    const qb = Player.init("Test QB", "TEST", "OPP", .QB, 7000, 25.0, 3.57, 0.15, "123");
    const rb = Player.init("Test RB", "TEST", "OPP", .RB, 6000, 20.0, 3.33, 0.25, "124");

    // Test adding players
    try lineup.addPlayer(&qb);
    try testing.expect(lineup.positions.qb == &qb);
    try testing.expect(lineup.total_salary == 7000);
    try testing.expect(lineup.total_projection == 25.0);

    try lineup.addPlayer(&rb);
    try testing.expect(lineup.positions.rb1 == &rb);
    try testing.expect(lineup.total_salary == 13000);

    // Test containsPlayer
    try testing.expect(lineup.containsPlayer(&qb));
    try testing.expect(lineup.containsPlayer(&rb));

    // Test team count
    try testing.expect(lineup.getTeamCount("TEST") == 2);
    try testing.expect(lineup.getTeamCount("OTHER") == 0);
}

test "Lineup FLEX position" {
    const testing = std.testing;

    var lineup = Lineup.init();
    
    const rb = Player.init("Flex RB", "TEST", "OPP", .RB, 5000, 15.0, 3.0, 0.20, "125");
    const qb = Player.init("Test QB", "TEST", "OPP", .QB, 7000, 25.0, 3.57, 0.15, "126");

    // Test adding RB to FLEX (should work)
    try lineup.addToFlex(&rb);
    try testing.expect(lineup.positions.flex == &rb);

    // Test adding QB to FLEX (should fail)
    try testing.expectError(error.NotFlexEligible, lineup.addToFlex(&qb));
}

test "Lineup validation" {
    const testing = std.testing;

    var lineup = Lineup.init();
    
    // Test salary cap checking - empty lineup has 0 salary
    try testing.expect(lineup.isUnderSalaryCap(50000)); // 0 <= 50000 is true
    try testing.expect(lineup.isUnderSalaryCap(0));     // 0 <= 0 is true
    
    // Add a high-salary player to test cap exceeded
    const expensive_player = Player.init("Expensive", "TEST", "OPP", .QB, 60000, 30.0, 0.5, 0.10, "999");
    try lineup.addPlayer(&expensive_player);
    try testing.expect(!lineup.isUnderSalaryCap(50000)); // 60000 > 50000 should be false
}