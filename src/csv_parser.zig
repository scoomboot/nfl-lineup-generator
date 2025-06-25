const std = @import("std");
const Player = @import("player.zig").Player;
const PlayerBuilder = @import("player.zig").PlayerBuilder;
const PlayerConfig = @import("player.zig").PlayerConfig;

// Structured error types for CSV parsing operations
pub const ParsingError = error{
    // File I/O errors
    FileNotFound,
    FileAccessDenied,
    FileReadError,
    
    // CSV structure errors
    EmptyFile,
    NoHeaderRow,
    MalformedCSV,
    InconsistentColumns,
    
    // Header validation errors  
    MissingRequiredColumns,
    DuplicateColumns,
    InvalidColumnName,
    
    // Row parsing errors
    EmptyRow,
    MalformedRow,
    FieldCountMismatch,
    
    // Data validation errors
    InvalidPlayerData,
    MissingRequiredField,
    InvalidFieldFormat,
    
    // Memory allocation errors
    OutOfMemory,
};

pub const DataValidationError = error{
    // Player field validation
    InvalidName,
    InvalidTeam,
    InvalidOpponent,
    InvalidPosition,
    InvalidSalary,
    InvalidProjection,
    InvalidValue,
    InvalidOwnership,
    InvalidSlateId,
    
    // Logical validation errors
    NegativeSalary,
    NegativeProjection,
    InvalidOwnershipRange, // Ownership should be 0.0-1.0
    EmptyRequiredField,
};

// Context information for error reporting
pub const ParseContext = struct {
    line_number: usize,
    column_name: ?[]const u8 = null,
    field_value: ?[]const u8 = null,
    player_name: ?[]const u8 = null,
    
    pub fn format(
        self: ParseContext,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("Line {d}", .{self.line_number});
        if (self.player_name) |name| {
            try writer.print(" (Player: {s})", .{name});
        }
        if (self.column_name) |col| {
            try writer.print(" Column: {s}", .{col});
        }
        if (self.field_value) |val| {
            try writer.print(" Value: '{s}'", .{val});
        }
    }
};

// Detailed parsing result with warnings and errors
pub const ParseResult = struct {
    players: []Player,
    warnings: []ParseWarning,
    errors: []ParseError,
    skipped_rows: usize = 0,
    total_rows: usize = 0,
    
    const Self = @This();
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.players);
        for (self.warnings) |*warning| {
            warning.deinit(allocator);
        }
        allocator.free(self.warnings);
        for (self.errors) |*err| {
            err.deinit(allocator);
        }
        allocator.free(self.errors);
    }
    
    pub fn hasErrors(self: Self) bool {
        return self.errors.len > 0;
    }
    
    pub fn hasWarnings(self: Self) bool {
        return self.warnings.len > 0;
    }
};

pub const ParseWarning = struct {
    context: ParseContext,
    message: []u8,
    
    pub fn deinit(self: *ParseWarning, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

pub const ParseError = struct {
    context: ParseContext,
    error_type: ParsingError,
    message: []u8,
    
    pub fn deinit(self: *ParseError, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};

// Logging levels for structured logging
pub const LogLevel = enum {
    DEBUG,
    INFO,
    WARN,
    ERROR,
    
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .DEBUG => "DEBUG",
            .INFO => "INFO",
            .WARN => "WARN",
            .ERROR => "ERROR",
        };
    }
};

// CSV Parser struct with configurable options
pub const CSVParser = struct {
    allocator: std.mem.Allocator,
    config: PlayerConfig,
    enable_logging: bool = true,
    max_warnings: usize = 100,
    skip_malformed_rows: bool = true,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, config: PlayerConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }
    
    // Parse CSV file and return structured results
    pub fn parseFile(self: *Self, file_path: []const u8) !ParseResult {
        self.log(.INFO, "Starting CSV parsing for file: {s}", .{file_path});
        
        // Read file contents
        const file_contents = std.fs.cwd().readFileAlloc(
            self.allocator, 
            file_path, 
            1024 * 1024 * 10 // 10MB max
        ) catch |err| switch (err) {
            error.FileNotFound => return ParsingError.FileNotFound,
            error.AccessDenied => return ParsingError.FileAccessDenied,
            else => return ParsingError.FileReadError,
        };
        defer self.allocator.free(file_contents);
        
        return try self.parseString(file_contents);
    }
    
    // Parse CSV string content
    pub fn parseString(self: *Self, csv_content: []const u8) !ParseResult {
        if (csv_content.len == 0) {
            return ParsingError.EmptyFile;
        }
        
        var lines = std.mem.splitScalar(u8, csv_content, '\n');
        
        // Parse header row
        const header_line = lines.next() orelse return ParsingError.NoHeaderRow;
        const headers = try self.parseCSVRow(header_line);
        defer self.allocator.free(headers);
        
        if (headers.len == 0) {
            return ParsingError.NoHeaderRow;
        }
        
        self.log(.DEBUG, "Found {d} columns in header", .{headers.len});
        
        // Validate headers against configuration
        self.config.validateHeaders(headers) catch |err| {
            self.log(.ERROR, "Header validation failed: {}", .{err});
            return ParsingError.MissingRequiredColumns;
        };
        
        // Initialize result arrays
        var players = std.ArrayList(Player).init(self.allocator);
        var warnings = std.ArrayList(ParseWarning).init(self.allocator);
        var errors = std.ArrayList(ParseError).init(self.allocator);
        
        var line_number: usize = 2; // Start from 2 (header is line 1)
        var skipped_rows: usize = 0;
        var total_rows: usize = 0;
        
        // Parse data rows
        while (lines.next()) |line| {
            total_rows += 1;
            
            // Skip empty lines
            const trimmed_line = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed_line.len == 0) {
                line_number += 1;
                continue;
            }
            
            const parse_result = self.parseDataRow(headers, trimmed_line, line_number);
            
            switch (parse_result) {
                .success => |player| {
                    try players.append(player);
                    self.log(.DEBUG, "Successfully parsed player: {s}", .{player.name});
                },
                .warning => |warning_info| {
                    try players.append(warning_info.player);
                    if (warnings.items.len < self.max_warnings) {
                        try warnings.append(warning_info.warning);
                    }
                    self.log(.WARN, "Warning at line {d}: {s}", .{line_number, warning_info.warning.message});
                },
                .parse_error => |error_info| {
                    if (self.skip_malformed_rows) {
                        skipped_rows += 1;
                        try errors.append(error_info);
                        self.log(.WARN, "Skipped malformed row at line {d}: {s}", .{line_number, error_info.message});
                    } else {
                        // Cleanup and return error
                        players.deinit();
                        warnings.deinit();
                        errors.deinit();
                        return error_info.error_type;
                    }
                },
            }
            
            line_number += 1;
        }
        
        self.log(.INFO, "Parsing complete. Parsed: {d}, Skipped: {d}, Total: {d}", .{players.items.len, skipped_rows, total_rows});
        
        return ParseResult{
            .players = try players.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
            .errors = try errors.toOwnedSlice(),
            .skipped_rows = skipped_rows,
            .total_rows = total_rows,
        };
    }
    
    // Parse a single CSV row into fields
    fn parseCSVRow(self: *Self, row: []const u8) ![][]const u8 {
        var fields = std.ArrayList([]const u8).init(self.allocator);
        
        var i: usize = 0;
        var in_quotes = false;
        var field_start: usize = 0;
        
        while (i < row.len) {
            const char = row[i];
            
            switch (char) {
                '"' => {
                    in_quotes = !in_quotes;
                },
                ',' => {
                    if (!in_quotes) {
                        var field = row[field_start..i];
                        // Remove surrounding quotes if present
                        if (field.len >= 2 and field[0] == '"' and field[field.len - 1] == '"') {
                            field = field[1..field.len - 1];
                        }
                        try fields.append(field);
                        field_start = i + 1;
                    }
                },
                else => {},
            }
            i += 1;
        }
        
        // Add final field
        var field = row[field_start..];
        if (field.len >= 2 and field[0] == '"' and field[field.len - 1] == '"') {
            field = field[1..field.len - 1];
        }
        try fields.append(field);
        
        return try fields.toOwnedSlice();
    }
    
    // Result type for row parsing
    const RowParseResult = union(enum) {
        success: Player,
        warning: struct { player: Player, warning: ParseWarning },
        parse_error: ParseError,
    };
    
    // Parse a single data row into a Player
    fn parseDataRow(self: *Self, headers: [][]const u8, row: []const u8, line_number: usize) RowParseResult {
        const context = ParseContext{ .line_number = line_number };
        
        // Parse CSV fields
        const fields = self.parseCSVRow(row) catch {
            return RowParseResult{
                .parse_error = ParseError{
                    .context = context,
                    .error_type = ParsingError.MalformedRow,
                    .message = self.allocator.dupe(u8, "Failed to parse CSV row") catch return RowParseResult{
                        .parse_error = ParseError{
                            .context = context,
                            .error_type = ParsingError.OutOfMemory,
                            .message = &[_]u8{},
                        }
                    },
                }
            };
        };
        defer self.allocator.free(fields);
        
        // Check field count matches header count
        if (fields.len != headers.len) {
            return RowParseResult{
                .parse_error = ParseError{
                    .context = context,
                    .error_type = ParsingError.FieldCountMismatch,
                    .message = self.allocator.dupe(u8, "Field count doesn't match header count") catch return RowParseResult{
                        .parse_error = ParseError{
                            .context = context,
                            .error_type = ParsingError.OutOfMemory,
                            .message = &[_]u8{},
                        }
                    },
                }
            };
        }
        
        // Check for malformed data (like "#N/A" values)
        if (self.hasMalformedData(fields)) {
            return RowParseResult{
                .parse_error = ParseError{
                    .context = context,
                    .error_type = ParsingError.InvalidPlayerData,
                    .message = self.allocator.dupe(u8, "Row contains malformed data (#N/A or missing values)") catch return RowParseResult{
                        .parse_error = ParseError{
                            .context = context,
                            .error_type = ParsingError.OutOfMemory,
                            .message = &[_]u8{},
                        }
                    },
                }
            };
        }
        
        // Create player using PlayerConfig
        var builder = self.config.createPlayerBuilder(headers, fields) catch |err| {
            const error_msg = switch (err) {
                error.MissingNameColumn => "Missing required name column",
                error.MissingTeamColumn => "Missing required team column", 
                error.MissingPositionColumn => "Missing required position column",
                error.InvalidPosition => "Invalid position value",
                error.InvalidSalary => "Invalid salary format",
                error.InvalidProjection => "Invalid projection format",
                error.InvalidValue => "Invalid value format",
                error.InvalidOwnership => "Invalid ownership format",
                else => "Unknown parsing error",
            };
            
            return RowParseResult{
                .parse_error = ParseError{
                    .context = context,
                    .error_type = ParsingError.InvalidPlayerData,
                    .message = self.allocator.dupe(u8, error_msg) catch return RowParseResult{
                        .parse_error = ParseError{
                            .context = context,
                            .error_type = ParsingError.OutOfMemory,
                            .message = &[_]u8{},
                        }
                    },
                }
            };
        };
        
        // Build the player
        const player = builder.build() catch |err| {
            const error_msg = switch (err) {
                error.MissingPlayerName => "Missing player name",
                error.MissingPlayerTeam => "Missing player team",
                error.MissingPlayerPosition => "Missing player position",
                error.MissingPlayerSalary => "Missing player salary",
                error.MissingPlayerProjection => "Missing player projection",
                error.MissingPlayerValue => "Missing player value",
                error.MissingPlayerOwnership => "Missing player ownership",
                error.MissingPlayerSlateId => "Missing player slate ID",
                else => "Failed to build player",
            };
            
            return RowParseResult{
                .parse_error = ParseError{
                    .context = context,
                    .error_type = ParsingError.InvalidPlayerData,
                    .message = self.allocator.dupe(u8, error_msg) catch return RowParseResult{
                        .parse_error = ParseError{
                            .context = context,
                            .error_type = ParsingError.OutOfMemory,
                            .message = &[_]u8{},
                        }
                    },
                }
            };
        };
        
        // Validate player data
        if (self.validatePlayerData(player)) |validation_error| {
            return RowParseResult{
                .parse_error = ParseError{
                    .context = ParseContext{
                        .line_number = line_number,
                        .player_name = player.name,
                    },
                    .error_type = ParsingError.InvalidPlayerData,
                    .message = self.allocator.dupe(u8, validation_error) catch return RowParseResult{
                        .parse_error = ParseError{
                            .context = context,
                            .error_type = ParsingError.OutOfMemory,
                            .message = &[_]u8{},
                        }
                    },
                }
            };
        }
        
        return RowParseResult{ .success = player };
    }
    
    // Check if row contains malformed data like "#N/A"
    fn hasMalformedData(self: *Self, fields: []const []const u8) bool {
        _ = self;
        for (fields) |field| {
            // Check for common malformed data indicators
            if (std.mem.eql(u8, field, "#N/A") or
                std.mem.eql(u8, field, "N/A") or  
                std.mem.eql(u8, field, "") or
                std.mem.eql(u8, field, "$")) {
                return true;
            }
        }
        return false;
    }
    
    // Validate player data for logical consistency
    fn validatePlayerData(self: *Self, player: Player) ?[]const u8 {
        _ = self;
        
        // Validate salary is positive
        if (player.salary == 0) {
            return "Salary cannot be zero";
        }
        
        // Validate projection is non-negative
        if (player.projection < 0.0) {
            return "Projection cannot be negative";
        }
        
        // Validate ownership is in valid range (0.0 - 1.0)
        if (player.ownership < 0.0 or player.ownership > 1.0) {
            return "Ownership must be between 0.0 and 1.0";
        }
        
        // Validate required string fields are not empty
        if (player.name.len == 0) {
            return "Player name cannot be empty";
        }
        
        if (player.team.len == 0) {
            return "Team cannot be empty";
        }
        
        return null; // No validation errors
    }
    
    // Structured logging function
    fn log(self: *Self, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
        if (!self.enable_logging) return;
        
        const stderr = std.io.getStdErr().writer();
        stderr.print("[{s}] CSV_PARSER: ", .{level.toString()}) catch return;
        stderr.print(fmt, args) catch return;
        stderr.print("\n", .{}) catch return;
    }
};

// Utility functions for enhanced CSV parsing
pub const CSVUtils = struct {
    // Clean and normalize field data
    pub fn cleanField(field: []const u8) []const u8 {
        return std.mem.trim(u8, field, " \t\r\n");
    }
    
    // Check if field represents missing/invalid data
    pub fn isValidField(field: []const u8) bool {
        const cleaned = cleanField(field);
        return cleaned.len > 0 and 
               !std.mem.eql(u8, cleaned, "#N/A") and
               !std.mem.eql(u8, cleaned, "N/A") and
               !std.mem.eql(u8, cleaned, "$");
    }
    
    // Format parsing statistics for display
    pub fn formatStats(result: ParseResult, allocator: std.mem.Allocator) ![]u8 {
        return try std.fmt.allocPrint(allocator,
            "Parsing Statistics:\n" ++
            "  Total rows processed: {d}\n" ++
            "  Players successfully parsed: {d}\n" ++
            "  Rows skipped due to errors: {d}\n" ++
            "  Warnings generated: {d}\n" ++
            "  Errors encountered: {d}\n",
            .{
                result.total_rows,
                result.players.len,
                result.skipped_rows,
                result.warnings.len,
                result.errors.len,
            }
        );
    }
};

// Tests for CSV parser module
test "CSV field parsing" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = CSVParser.init(allocator, PlayerConfig.draftKingsDefault());
    parser.enable_logging = false;
    
    // Test basic CSV row parsing
    const row = "\"Player Name\",\"Team\",\"$7500\",\"25.4\"";
    const fields = try parser.parseCSVRow(row);
    defer allocator.free(fields);
    
    try testing.expect(fields.len == 4);
    try testing.expectEqualStrings("Player Name", fields[0]);
    try testing.expectEqualStrings("Team", fields[1]);
    try testing.expectEqualStrings("$7500", fields[2]);
    try testing.expectEqualStrings("25.4", fields[3]);
}

test "Malformed data detection" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = CSVParser.init(allocator, PlayerConfig.draftKingsDefault());
    parser.enable_logging = false;
    
    // Test malformed data detection
    const valid_fields = [_][]const u8{ "Player", "Team", "$7500", "25.4" };
    const malformed_fields = [_][]const u8{ "#N/A", "Team", "$", "25.4" };
    
    try testing.expect(!parser.hasMalformedData(&valid_fields));
    try testing.expect(parser.hasMalformedData(&malformed_fields));
}

test "Player data validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var parser = CSVParser.init(allocator, PlayerConfig.draftKingsDefault());
    parser.enable_logging = false;
    
    // Valid player
    const valid_player = Player.init(
        "Test Player", "TEST", "OPP", .QB, 7500, 25.4, 3.39, 0.18, "12345"
    );
    try testing.expect(parser.validatePlayerData(valid_player) == null);
    
    // Invalid player - zero salary
    const invalid_player = Player.init(
        "Bad Player", "TEST", "OPP", .QB, 0, 25.4, 3.39, 0.18, "12345"
    );
    try testing.expect(parser.validatePlayerData(invalid_player) != null);
    
    // Invalid ownership range
    const bad_ownership_player = Player.init(
        "Bad Ownership", "TEST", "OPP", .QB, 7500, 25.4, 3.39, 1.5, "12345"
    );
    try testing.expect(parser.validatePlayerData(bad_ownership_player) != null);
}

test "CSV Utils functions" {
    const testing = std.testing;
    
    // Test field cleaning
    try testing.expectEqualStrings("clean", CSVUtils.cleanField("  clean  "));
    try testing.expectEqualStrings("", CSVUtils.cleanField("   "));
    
    // Test field validation
    try testing.expect(CSVUtils.isValidField("valid field"));
    try testing.expect(!CSVUtils.isValidField("#N/A"));
    try testing.expect(!CSVUtils.isValidField(""));
    try testing.expect(!CSVUtils.isValidField("$"));
}