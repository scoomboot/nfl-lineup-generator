const std = @import("std");
const nfl_lib = @import("nfl_lineup_generator_lib");

pub fn main() !void {
    std.log.info("NFL Lineup Generator CLI", .{});
    
    // Example usage of our data structures
    const example_player = nfl_lib.Player.init(
        "Alvin Kamara",
        "NO",
        "CAR", 
        .RB,
        7900,
        25.4,
        3.2,
        0.46,
        "15642244"
    );
    
    var lineup = nfl_lib.Lineup.init();
    try lineup.addPlayer(&example_player);
    
    std.log.info("Created lineup with {} players, total salary: ${}, projection: {d:.1}pts", 
        .{ lineup.positions.getFilledCount(), lineup.total_salary, lineup.total_projection });
}
