//! NFL Lineup Generator Library
//! This library provides data structures and utilities for generating 
//! DraftKings NFL lineup combinations.

const std = @import("std");

// Export public modules
pub const player = @import("player.zig");
pub const lineup = @import("lineup.zig");

// Re-export commonly used types
pub const Player = player.Player;
pub const Position = player.Position;
pub const InjuryStatus = player.InjuryStatus;
pub const PlayerUtils = player.PlayerUtils;

pub const Lineup = lineup.Lineup;
pub const DKClassicPositions = lineup.DKClassicPositions;
pub const LineupUtils = lineup.LineupUtils;

test {
    // Run all tests from imported modules
    std.testing.refAllDecls(@This());
}
