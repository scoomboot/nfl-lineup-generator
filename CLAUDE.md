# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NFL lineup generator written in Zig, designed to optimize daily fantasy sports lineups using player projections data. The project follows standard Zig project structure with both library and executable components.

## Build System & Commands

### Core Commands
- `zig build` - Builds the project (both library and executable)
- `zig build run` - Builds and runs the executable
- `zig build test` - Runs all unit tests (both library and executable tests)
- `zig build run -- [args]` - Run with command line arguments

### Development Workflow
- Use `zig build test` to run tests before making changes
- The project builds both a static library (`libnfl_lineup_generator.a`) and an executable
- Built artifacts are placed in `zig-out/` directory

## Architecture

### Project Structure
- **src/main.zig**: Entry point for the executable application (currently minimal stub)
- **src/root.zig**: Library entry point with core functionality (currently has basic add function)
- **data/projections.csv**: Contains NFL player projection data with DraftKings salary, projection, and value information
- **build.zig**: Standard Zig build configuration with library and executable targets
- **build.zig.zon**: Package configuration (version 0.0.0, requires Zig 0.14.0+)

### Module Design
The build system creates two modules:
- `lib_mod`: Library module based on src/root.zig
- `exe_mod`: Executable module based on src/main.zig, imports the library module as "nfl_lineup_generator_lib"

### Data Format
The projections.csv contains player data with columns:
- Player, Team, Opponent, DK Position, DK Salary, DK Projection, DK Value, DK Ownership, DKSlateID

## Development Notes

- Minimum Zig version: 0.14.0
- The project is currently in early development stage with placeholder implementations
- No external dependencies are currently used
- Both library and executable have separate test suites that run in parallel