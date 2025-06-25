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

// PlayerBuilder pattern for flexible Player creation
pub const PlayerBuilder = struct {
    // Required fields
    name: ?[]const u8 = null,
    team: ?[]const u8 = null,
    opponent: ?[]const u8 = null,
    position: ?Position = null,
    salary: ?u32 = null,
    projection: ?f32 = null,
    value: ?f32 = null,
    ownership: ?f32 = null,
    slate_id: ?[]const u8 = null,
    
    // Optional fields
    injury_status: ?InjuryStatus = null,
    is_on_bye: bool = false,
    game_time: ?[]const u8 = null,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    // Required field setters - these must be called for a valid Player
    pub fn setName(self: *Self, name: []const u8) *Self {
        self.name = name;
        return self;
    }

    pub fn setTeam(self: *Self, team: []const u8) *Self {
        self.team = team;
        return self;
    }

    pub fn setOpponent(self: *Self, opponent: []const u8) *Self {
        self.opponent = opponent;
        return self;
    }

    pub fn setPosition(self: *Self, position: Position) *Self {
        self.position = position;
        return self;
    }

    pub fn setSalary(self: *Self, salary: u32) *Self {
        self.salary = salary;
        return self;
    }

    pub fn setProjection(self: *Self, projection: f32) *Self {
        self.projection = projection;
        return self;
    }

    pub fn setValue(self: *Self, value: f32) *Self {
        self.value = value;
        return self;
    }

    pub fn setOwnership(self: *Self, ownership: f32) *Self {
        self.ownership = ownership;
        return self;
    }

    pub fn setSlateId(self: *Self, slate_id: []const u8) *Self {
        self.slate_id = slate_id;
        return self;
    }

    // Optional field setters
    pub fn setInjuryStatus(self: *Self, status: InjuryStatus) *Self {
        self.injury_status = status;
        return self;
    }

    pub fn setByeWeek(self: *Self, is_on_bye: bool) *Self {
        self.is_on_bye = is_on_bye;
        return self;
    }

    pub fn setGameTime(self: *Self, game_time: []const u8) *Self {
        self.game_time = game_time;
        return self;
    }

    // Convenience methods for parsing from strings
    pub fn setSalaryFromString(self: *Self, salary_str: []const u8) !*Self {
        const salary = try PlayerUtils.parseSalary(salary_str);
        return self.setSalary(salary);
    }

    pub fn setOwnershipFromString(self: *Self, ownership_str: []const u8) !*Self {
        const ownership = try PlayerUtils.parseOwnership(ownership_str);
        return self.setOwnership(ownership);
    }

    pub fn setProjectionFromString(self: *Self, projection_str: []const u8) !*Self {
        const projection = try PlayerUtils.parseProjection(projection_str);
        return self.setProjection(projection);
    }

    pub fn setValueFromString(self: *Self, value_str: []const u8) !*Self {
        const value = try PlayerUtils.parseValue(value_str);
        return self.setValue(value);
    }

    pub fn setPositionFromString(self: *Self, position_str: []const u8) !*Self {
        const position = try Position.fromString(position_str);
        return self.setPosition(position);
    }

    pub fn setInjuryStatusFromString(self: *Self, status_str: []const u8) !*Self {
        const status = try InjuryStatus.fromString(status_str);
        return self.setInjuryStatus(status);
    }

    // Build the Player - validates all required fields are present
    pub fn build(self: Self) !Player {
        // Validate required fields
        const name = self.name orelse return error.MissingPlayerName;
        const team = self.team orelse return error.MissingPlayerTeam;
        const opponent = self.opponent orelse return error.MissingPlayerOpponent;
        const position = self.position orelse return error.MissingPlayerPosition;
        const salary = self.salary orelse return error.MissingPlayerSalary;
        const projection = self.projection orelse return error.MissingPlayerProjection;
        const value = self.value orelse return error.MissingPlayerValue;
        const ownership = self.ownership orelse return error.MissingPlayerOwnership;
        const slate_id = self.slate_id orelse return error.MissingPlayerSlateId;

        return Player{
            .name = name,
            .team = team,
            .opponent = opponent,
            .position = position,
            .salary = salary,
            .projection = projection,
            .value = value,
            .ownership = ownership,
            .slate_id = slate_id,
            .injury_status = self.injury_status,
            .is_on_bye = self.is_on_bye,
            .game_time = self.game_time,
        };
    }
};

// PlayerConfig struct for configurable CSV parsing
pub const PlayerConfig = struct {
    // Define which columns are required vs optional
    require_name: bool = true,
    require_team: bool = true,
    require_opponent: bool = true,
    require_position: bool = true,
    require_salary: bool = true,
    require_projection: bool = true,
    require_value: bool = true,
    require_ownership: bool = true,
    require_slate_id: bool = true,
    
    // Allow optional fields
    allow_injury_status: bool = true,
    allow_bye_week: bool = true,
    allow_game_time: bool = true,
    
    // Column mapping for different data source formats
    name_column: []const u8 = "Player",
    team_column: []const u8 = "Team",
    opponent_column: []const u8 = "Opponent", 
    position_column: []const u8 = "DK Position",
    salary_column: []const u8 = "DK Salary",
    projection_column: []const u8 = "DK Projection",
    value_column: []const u8 = "DK Value",
    ownership_column: []const u8 = "DK Ownership",
    slate_id_column: []const u8 = "DKSlateID",
    
    // Optional column mappings
    injury_status_column: ?[]const u8 = null,
    bye_week_column: ?[]const u8 = null,
    game_time_column: ?[]const u8 = null,

    const Self = @This();

    // Default configuration for DraftKings CSV format
    pub fn draftKingsDefault() Self {
        return Self{};
    }

    // Flexible configuration for custom CSV formats
    pub fn custom() Self {
        return Self{
            .require_name = true,
            .require_team = true,
            .require_position = true,
            .require_salary = true,
            .require_projection = false,  // May not always be available
            .require_value = false,       // May not always be available  
            .require_ownership = false,   // May not always be available
            .require_opponent = false,    // May not always be available
            .require_slate_id = false,    // May not always be available
        };
    }

    // Validate that required columns are present in header
    pub fn validateHeaders(self: Self, headers: []const []const u8) !void {
        // Check for required columns
        if (self.require_name and !self.hasColumn(headers, self.name_column)) {
            return error.MissingNameColumn;
        }
        if (self.require_team and !self.hasColumn(headers, self.team_column)) {
            return error.MissingTeamColumn;
        }
        if (self.require_opponent and !self.hasColumn(headers, self.opponent_column)) {
            return error.MissingOpponentColumn;
        }
        if (self.require_position and !self.hasColumn(headers, self.position_column)) {
            return error.MissingPositionColumn;
        }
        if (self.require_salary and !self.hasColumn(headers, self.salary_column)) {
            return error.MissingSalaryColumn;
        }
        if (self.require_projection and !self.hasColumn(headers, self.projection_column)) {
            return error.MissingProjectionColumn;
        }
        if (self.require_value and !self.hasColumn(headers, self.value_column)) {
            return error.MissingValueColumn;
        }
        if (self.require_ownership and !self.hasColumn(headers, self.ownership_column)) {
            return error.MissingOwnershipColumn;
        }
        if (self.require_slate_id and !self.hasColumn(headers, self.slate_id_column)) {
            return error.MissingSlateIdColumn;
        }
    }

    // Helper function to check if column exists in headers
    fn hasColumn(self: Self, headers: []const []const u8, column_name: []const u8) bool {
        _ = self;
        for (headers) |header| {
            if (std.mem.eql(u8, header, column_name)) {
                return true;
            }
        }
        return false;
    }

    // Get column index for a given column name
    pub fn getColumnIndex(self: Self, headers: []const []const u8, column_name: []const u8) ?usize {
        _ = self;
        for (headers, 0..) |header, i| {
            if (std.mem.eql(u8, header, column_name)) {
                return i;
            }
        }
        return null;
    }

    // Create PlayerBuilder from CSV row data using this configuration
    pub fn createPlayerBuilder(self: Self, headers: []const []const u8, row: []const []const u8) !PlayerBuilder {
        var builder = PlayerBuilder.init();

        // Set required fields
        if (self.require_name) {
            const idx = self.getColumnIndex(headers, self.name_column) orelse return error.MissingNameColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = builder.setName(row[idx]);
        }

        if (self.require_team) {
            const idx = self.getColumnIndex(headers, self.team_column) orelse return error.MissingTeamColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = builder.setTeam(row[idx]);
        }

        if (self.require_opponent) {
            const idx = self.getColumnIndex(headers, self.opponent_column) orelse return error.MissingOpponentColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = builder.setOpponent(row[idx]);
        }

        if (self.require_position) {
            const idx = self.getColumnIndex(headers, self.position_column) orelse return error.MissingPositionColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = try builder.setPositionFromString(row[idx]);
        }

        if (self.require_salary) {
            const idx = self.getColumnIndex(headers, self.salary_column) orelse return error.MissingSalaryColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = try builder.setSalaryFromString(row[idx]);
        }

        if (self.require_projection) {
            const idx = self.getColumnIndex(headers, self.projection_column) orelse return error.MissingProjectionColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = try builder.setProjectionFromString(row[idx]);
        }

        if (self.require_value) {
            const idx = self.getColumnIndex(headers, self.value_column) orelse return error.MissingValueColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = try builder.setValueFromString(row[idx]);
        }

        if (self.require_ownership) {
            const idx = self.getColumnIndex(headers, self.ownership_column) orelse return error.MissingOwnershipColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = try builder.setOwnershipFromString(row[idx]);
        }

        if (self.require_slate_id) {
            const idx = self.getColumnIndex(headers, self.slate_id_column) orelse return error.MissingSlateIdColumn;
            if (idx >= row.len) return error.InvalidRowData;
            _ = builder.setSlateId(row[idx]);
        }

        // Set optional fields if available
        if (self.allow_injury_status and self.injury_status_column != null) {
            if (self.getColumnIndex(headers, self.injury_status_column.?)) |idx| {
                if (idx < row.len and row[idx].len > 0) {
                    _ = builder.setInjuryStatusFromString(row[idx]) catch {
                        // Ignore invalid injury status, leave as null
                    };
                }
            }
        }

        if (self.allow_bye_week and self.bye_week_column != null) {
            if (self.getColumnIndex(headers, self.bye_week_column.?)) |idx| {
                if (idx < row.len) {
                    const is_bye = std.mem.eql(u8, row[idx], "true") or 
                                   std.mem.eql(u8, row[idx], "TRUE") or
                                   std.mem.eql(u8, row[idx], "1");
                    _ = builder.setByeWeek(is_bye);
                }
            }
        }

        if (self.allow_game_time and self.game_time_column != null) {
            if (self.getColumnIndex(headers, self.game_time_column.?)) |idx| {
                if (idx < row.len and row[idx].len > 0) {
                    _ = builder.setGameTime(row[idx]);
                }
            }
        }

        return builder;
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

test "PlayerBuilder pattern" {
    const testing = std.testing;

    // Test successful build with all required fields
    var builder = PlayerBuilder.init();
    const player = try builder
        .setName("Test Player")
        .setTeam("TEST")
        .setOpponent("OPP")
        .setPosition(.QB)
        .setSalary(7000)
        .setProjection(25.0)
        .setValue(3.57)
        .setOwnership(0.15)
        .setSlateId("12345")
        .setInjuryStatus(.ACTIVE)
        .setByeWeek(false)
        .build();

    try testing.expectEqualStrings("Test Player", player.name);
    try testing.expect(player.position == .QB);
    try testing.expect(player.salary == 7000);
    try testing.expect(player.injury_status.? == .ACTIVE);
    try testing.expect(!player.is_on_bye);

    // Test missing required field
    var incomplete_builder = PlayerBuilder.init();
    try testing.expectError(error.MissingPlayerName, incomplete_builder.build());

    // Test string parsing methods
    var string_builder = PlayerBuilder.init();
    _ = try string_builder.setPositionFromString("RB");
    _ = try string_builder.setSalaryFromString("$6500");
    _ = try string_builder.setProjectionFromString("18.5");
    _ = try string_builder.setValueFromString("2.85");
    _ = try string_builder.setOwnershipFromString("25%");
    const parsed_player = try string_builder
        .setName("String Test")
        .setTeam("TEST")
        .setOpponent("OPP")
        .setSlateId("67890")
        .build();

    try testing.expect(parsed_player.position == .RB);
    try testing.expect(parsed_player.salary == 6500);
    try testing.expect(parsed_player.ownership == 0.25);
}

test "PlayerConfig header validation" {
    const testing = std.testing;

    const config = PlayerConfig.draftKingsDefault();
    
    // Test valid headers
    const valid_headers = [_][]const u8{
        "Player", "Team", "Opponent", "DK Position", "DK Salary", 
        "DK Projection", "DK Value", "DK Ownership", "DKSlateID"
    };
    try config.validateHeaders(&valid_headers);

    // Test missing required column
    const invalid_headers = [_][]const u8{ "Player", "Team" };
    try testing.expectError(error.MissingOpponentColumn, config.validateHeaders(&invalid_headers));

    // Test column index lookup
    try testing.expect(config.getColumnIndex(&valid_headers, "Player").? == 0);
    try testing.expect(config.getColumnIndex(&valid_headers, "Team").? == 1);
    try testing.expect(config.getColumnIndex(&valid_headers, "NonExistent") == null);
}

test "PlayerConfig createPlayerBuilder" {
    const testing = std.testing;

    const config = PlayerConfig.draftKingsDefault();
    const headers = [_][]const u8{
        "Player", "Team", "Opponent", "DK Position", "DK Salary", 
        "DK Projection", "DK Value", "DK Ownership", "DKSlateID"
    };
    const row = [_][]const u8{
        "Test Player", "TEST", "OPP", "QB", "$7500", 
        "24.5", "3.27", "18%", "12345"
    };

    var builder = try config.createPlayerBuilder(&headers, &row);
    const player = try builder.build();

    try testing.expectEqualStrings("Test Player", player.name);
    try testing.expectEqualStrings("TEST", player.team);
    try testing.expect(player.position == .QB);
    try testing.expect(player.salary == 7500);
    try testing.expect(player.ownership == 0.18);
}