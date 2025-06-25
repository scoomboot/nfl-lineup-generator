const std = @import("std");

// Position enum for NFL positions
pub const Position = enum {
    QB,
    RB,
    WR,
    TE,
    DST,
    FLEX, // Can be RB, WR, or TE

    pub fn fromString(str: []const u8) !Position {
        if (std.mem.eql(u8, str, "QB")) return .QB;
        if (std.mem.eql(u8, str, "RB")) return .RB;
        if (std.mem.eql(u8, str, "WR")) return .WR;
        if (std.mem.eql(u8, str, "TE")) return .TE;
        if (std.mem.eql(u8, str, "DST")) return .DST;
        if (std.mem.eql(u8, str, "FLEX")) return .FLEX;
        return error.InvalidPosition;
    }

    pub fn toString(self: Position) []const u8 {
        return switch (self) {
            .QB => "QB",
            .RB => "RB",
            .WR => "WR",
            .TE => "TE",
            .DST => "DST",
            .FLEX => "FLEX",
        };
    }

    // Check if position is eligible for FLEX slot
    pub fn isFlexEligible(self: Position) bool {
        return switch (self) {
            .RB, .WR, .TE => true,
            .QB, .DST, .FLEX => false,
        };
    }
};

// Injury status enum for player availability
pub const InjuryStatus = enum {
    OUT,
    DOUBTFUL,
    QUESTIONABLE,
    ACTIVE,

    pub fn fromString(str: []const u8) !InjuryStatus {
        if (std.mem.eql(u8, str, "OUT")) return .OUT;
        if (std.mem.eql(u8, str, "DOUBTFUL")) return .DOUBTFUL;
        if (std.mem.eql(u8, str, "QUESTIONABLE")) return .QUESTIONABLE;
        if (std.mem.eql(u8, str, "ACTIVE")) return .ACTIVE;
        return error.InvalidInjuryStatus;
    }

    pub fn toString(self: InjuryStatus) []const u8 {
        return switch (self) {
            .OUT => "OUT",
            .DOUBTFUL => "DOUBTFUL",
            .QUESTIONABLE => "QUESTIONABLE",
            .ACTIVE => "ACTIVE",
        };
    }

    // Check if player is available for selection
    pub fn isAvailable(self: InjuryStatus) bool {
        return switch (self) {
            .OUT => false,
            .DOUBTFUL, .QUESTIONABLE, .ACTIVE => true,
        };
    }
};

// Player struct representing an NFL player with all relevant data
pub const Player = struct {
    // Required fields from CSV
    name: []const u8,
    team: []const u8,
    opponent: []const u8,
    position: Position,
    salary: u32,            // DK Salary (converted from $7900 -> 7900)
    projection: f32,        // DK Projection (expected fantasy points)
    value: f32,             // DK Value (points per $1000 of salary)
    ownership: f32,         // DK Ownership (converted from 46% -> 0.46)
    slate_id: []const u8,   // DKSlateID

    // Optional/derived fields
    injury_status: ?InjuryStatus = null,
    is_on_bye: bool = false,
    game_time: ?[]const u8 = null,

    const Self = @This();

    // Initialize a new player with required fields
    pub fn init(
        name: []const u8,
        team: []const u8,
        opponent: []const u8,
        position: Position,
        salary: u32,
        projection: f32,
        value: f32,
        ownership: f32,
        slate_id: []const u8,
    ) Self {
        return Self{
            .name = name,
            .team = team,
            .opponent = opponent,
            .position = position,
            .salary = salary,
            .projection = projection,
            .value = value,
            .ownership = ownership,
            .slate_id = slate_id,
        };
    }

    // Check if player is available for lineup selection
    pub fn isAvailable(self: Self) bool {
        // Check injury status if provided
        if (self.injury_status) |status| {
            if (!status.isAvailable()) return false;
        }

        // Check bye week
        if (self.is_on_bye) return false;

        return true;
    }

    // Get player's value per dollar (projection / salary * 1000)
    pub fn getValuePerDollar(self: Self) f32 {
        if (self.salary == 0) return 0.0;
        return self.projection / (@as(f32, @floatFromInt(self.salary)) / 1000.0);
    }

    // Check if player can fill a specific position slot
    pub fn canFillPosition(self: Self, target_position: Position) bool {
        // Direct position match
        if (self.position == target_position) return true;

        // FLEX position can be filled by RB, WR, or TE
        if (target_position == .FLEX and self.position.isFlexEligible()) return true;

        return false;
    }

    // Format player for debugging/display
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s} ({s}) ${d} - {d:.1}pts", .{
            self.name,
            self.position.toString(),
            self.salary,
            self.projection,
        });
    }
};

// Utility functions for player operations
pub const PlayerUtils = struct {
    // Parse salary string from CSV format ($7900 -> 7900)
    pub fn parseSalary(salary_str: []const u8) !u32 {
        if (salary_str.len == 0) return error.EmptySalary;
        
        // Remove $ prefix if present
        const clean_str = if (salary_str[0] == '$') salary_str[1..] else salary_str;
        
        // Handle empty string after removing $
        if (clean_str.len == 0) return error.InvalidSalary;
        
        return std.fmt.parseInt(u32, clean_str, 10) catch error.InvalidSalary;
    }

    // Parse ownership string from CSV format (46% -> 0.46)
    pub fn parseOwnership(ownership_str: []const u8) !f32 {
        if (ownership_str.len == 0) return error.EmptyOwnership;
        
        // Remove % suffix if present
        const clean_str = if (ownership_str[ownership_str.len - 1] == '%')
            ownership_str[0..ownership_str.len - 1]
        else
            ownership_str;
        
        // Handle empty string after removing %
        if (clean_str.len == 0) return error.InvalidOwnership;
        
        const percentage = std.fmt.parseFloat(f32, clean_str) catch return error.InvalidOwnership;
        return percentage / 100.0; // Convert percentage to decimal
    }

    // Parse projection value, handling potential formatting issues
    pub fn parseProjection(projection_str: []const u8) !f32 {
        if (projection_str.len == 0) return error.EmptyProjection;
        return std.fmt.parseFloat(f32, projection_str) catch error.InvalidProjection;
    }

    // Parse value, handling potential formatting issues
    pub fn parseValue(value_str: []const u8) !f32 {
        if (value_str.len == 0) return error.EmptyValue;
        return std.fmt.parseFloat(f32, value_str) catch error.InvalidValue;
    }
};

// Tests for player module
test "Position enum operations" {
    const testing = std.testing;

    // Test fromString
    try testing.expect(try Position.fromString("QB") == .QB);
    try testing.expect(try Position.fromString("RB") == .RB);
    try testing.expect(try Position.fromString("FLEX") == .FLEX);

    // Test invalid position
    try testing.expectError(error.InvalidPosition, Position.fromString("INVALID"));

    // Test toString
    try testing.expectEqualStrings("QB", Position.QB.toString());
    try testing.expectEqualStrings("WR", Position.WR.toString());

    // Test FLEX eligibility
    try testing.expect(Position.RB.isFlexEligible());
    try testing.expect(Position.WR.isFlexEligible());
    try testing.expect(Position.TE.isFlexEligible());
    try testing.expect(!Position.QB.isFlexEligible());
    try testing.expect(!Position.DST.isFlexEligible());
}

test "InjuryStatus enum operations" {
    const testing = std.testing;

    // Test availability
    try testing.expect(!InjuryStatus.OUT.isAvailable());
    try testing.expect(InjuryStatus.ACTIVE.isAvailable());
    try testing.expect(InjuryStatus.QUESTIONABLE.isAvailable());
}

test "Player utility functions" {
    const testing = std.testing;

    // Test salary parsing
    try testing.expect(try PlayerUtils.parseSalary("$7900") == 7900);
    try testing.expect(try PlayerUtils.parseSalary("7900") == 7900);
    try testing.expectError(error.InvalidSalary, PlayerUtils.parseSalary("$"));
    try testing.expectError(error.EmptySalary, PlayerUtils.parseSalary(""));

    // Test ownership parsing
    try testing.expect(try PlayerUtils.parseOwnership("46%") == 0.46);
    try testing.expect(try PlayerUtils.parseOwnership("46") == 0.46);
    try testing.expectError(error.InvalidOwnership, PlayerUtils.parseOwnership("%"));
    try testing.expectError(error.EmptyOwnership, PlayerUtils.parseOwnership(""));

    // Test projection parsing
    try testing.expect(try PlayerUtils.parseProjection("25.4") == 25.4);
    try testing.expectError(error.InvalidProjection, PlayerUtils.parseProjection("invalid"));
}

test "Player position compatibility" {
    const testing = std.testing;

    const rb_player = Player.init(
        "Test RB", "TEST", "OPP", .RB, 5000, 15.0, 3.0, 0.25, "12345"
    );

    // RB can fill RB position
    try testing.expect(rb_player.canFillPosition(.RB));
    
    // RB can fill FLEX position
    try testing.expect(rb_player.canFillPosition(.FLEX));
    
    // RB cannot fill QB position
    try testing.expect(!rb_player.canFillPosition(.QB));
}