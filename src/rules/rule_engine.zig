const std = @import("std");

// Rule validation result
pub const RuleResult = struct {
    is_valid: bool,
    error_message: ?[]const u8 = null,
    rule_name: []const u8,
    
    const Self = @This();
    
    pub fn valid(rule_name: []const u8) Self {
        return Self{
            .is_valid = true,
            .rule_name = rule_name,
        };
    }
    
    pub fn invalid(rule_name: []const u8, error_message: []const u8) Self {
        return Self{
            .is_valid = false,
            .error_message = error_message,
            .rule_name = rule_name,
        };
    }
};

// Rule priority levels
pub const RulePriority = enum(u8) {
    CRITICAL = 0,   // Must pass for lineup to be valid (salary, positions)
    HIGH = 1,       // Important constraints (team limits, availability)
    MEDIUM = 2,     // Optimization rules (stacking, ownership)
    LOW = 3,        // Advisory rules (diversity, value)
    
    pub fn toString(self: RulePriority) []const u8 {
        return switch (self) {
            .CRITICAL => "CRITICAL",
            .HIGH => "HIGH", 
            .MEDIUM => "MEDIUM",
            .LOW => "LOW",
        };
    }
};

// Forward declaration for Lineup - will be defined elsewhere
pub const Lineup = opaque {};

// Rule interface - all rules must implement this
pub const Rule = struct {
    // Rule metadata
    name: []const u8,
    priority: RulePriority,
    enabled: bool = true,
    
    // Rule validation function pointer
    validateFn: *const fn (rule: *const Rule, target_lineup: *const Lineup, allocator: std.mem.Allocator) anyerror!RuleResult,
    
    const Self = @This();
    
    pub fn validate(self: *const Self, target_lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
        if (!self.enabled) {
            return RuleResult.valid(self.name);
        }
        return self.validateFn(self, target_lineup, allocator);
    }
    
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }
    
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }
};

// Rule validation context for detailed error reporting
pub const RuleValidationContext = struct {
    lineup: *const Lineup,
    contest_rules: ?*const ContestRules = null,
    
    const Self = @This();
    
    pub fn init(target_lineup: *const Lineup) Self {
        return Self{
            .lineup = target_lineup,
        };
    }
    
    pub fn withContestRules(self: Self, rules: *const ContestRules) Self {
        var new_context = self;
        new_context.contest_rules = rules;
        return new_context;
    }
};

// Contest-specific rule configuration
pub const ContestRules = struct {
    salary_cap: u32 = 50000,
    max_team_players: u8 = 8,
    required_positions: PositionRequirements = PositionRequirements{},
    
    const Self = @This();
};

pub const PositionRequirements = struct {
    qb: u8 = 1,
    rb: u8 = 2, 
    wr: u8 = 3,
    te: u8 = 1,
    flex: u8 = 1,
    dst: u8 = 1,
};

// Rule dependency system
pub const RuleDependency = struct {
    rule_name: []const u8,
    dependency_type: DependencyType,
    
    pub const DependencyType = enum {
        REQUIRES,      // This rule requires another rule to pass first
        CONFLICTS,     // This rule conflicts with another rule
        ENHANCES,      // This rule enhances another rule's validation
    };
};

// Rule engine validation results
pub const ValidationResult = struct {
    is_valid: bool,
    passed_rules: []RuleResult,
    failed_rules: []RuleResult,
    warnings: []RuleResult,
    total_rules_checked: u32,
    
    const Self = @This();
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.passed_rules);
        allocator.free(self.failed_rules);
        allocator.free(self.warnings);
    }
    
    pub fn isValid(self: Self) bool {
        return self.is_valid;
    }
    
    pub fn getFailureCount(self: Self) u32 {
        return @intCast(self.failed_rules.len);
    }
    
    pub fn getWarningCount(self: Self) u32 {
        return @intCast(self.warnings.len);
    }
};

// Main rule engine
pub const RuleEngine = struct {
    rules: std.ArrayList(Rule),
    dependencies: std.ArrayList(RuleDependency),
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .rules = std.ArrayList(Rule).init(allocator),
            .dependencies = std.ArrayList(RuleDependency).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.rules.deinit();
        self.dependencies.deinit();
    }
    
    // Add a rule to the engine
    pub fn addRule(self: *Self, rule: Rule) !void {
        try self.rules.append(rule);
    }
    
    // Add a rule dependency
    pub fn addDependency(self: *Self, dependency: RuleDependency) !void {
        try self.dependencies.append(dependency);
    }
    
    // Remove a rule by name
    pub fn removeRule(self: *Self, rule_name: []const u8) bool {
        for (self.rules.items, 0..) |rule, i| {
            if (std.mem.eql(u8, rule.name, rule_name)) {
                _ = self.rules.orderedRemove(i);
                return true;
            }
        }
        return false;
    }
    
    // Get rule by name
    pub fn getRule(self: *Self, rule_name: []const u8) ?*Rule {
        for (self.rules.items) |*rule| {
            if (std.mem.eql(u8, rule.name, rule_name)) {
                return rule;
            }
        }
        return null;
    }
    
    // Validate lineup against all rules
    pub fn validateLineup(self: *Self, target_lineup: *const Lineup) !ValidationResult {
        var passed_rules = std.ArrayList(RuleResult).init(self.allocator);
        var failed_rules = std.ArrayList(RuleResult).init(self.allocator);
        var warnings = std.ArrayList(RuleResult).init(self.allocator);
        
        // Sort rules by priority (CRITICAL first)
        const sorted_rules = try self.allocator.dupe(Rule, self.rules.items);
        defer self.allocator.free(sorted_rules);
        
        std.sort.insertion(Rule, sorted_rules, {}, rulePriorityLessThan);
        
        var overall_valid = true;
        
        // Validate each rule in priority order
        for (sorted_rules) |*rule| {
            const result = rule.validate(target_lineup, self.allocator) catch |err| {
                // Handle rule validation errors
                const error_msg = try std.fmt.allocPrint(self.allocator, "Rule validation error: {}", .{err});
                defer self.allocator.free(error_msg);
                
                const error_result = RuleResult.invalid(rule.name, error_msg);
                try failed_rules.append(error_result);
                overall_valid = false;
                continue;
            };
            
            if (result.is_valid) {
                try passed_rules.append(result);
            } else {
                try failed_rules.append(result);
                
                // CRITICAL and HIGH priority rule failures make lineup invalid
                if (rule.priority == .CRITICAL or rule.priority == .HIGH) {
                    overall_valid = false;
                }
                
                // MEDIUM and LOW priority failures are warnings
                if (rule.priority == .MEDIUM or rule.priority == .LOW) {
                    try warnings.append(result);
                }
            }
        }
        
        return ValidationResult{
            .is_valid = overall_valid,
            .passed_rules = try passed_rules.toOwnedSlice(),
            .failed_rules = try failed_rules.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
            .total_rules_checked = @intCast(sorted_rules.len),
        };
    }
    
    // Check if dependencies are satisfied before validation
    fn checkDependencies(self: *Self, rule_name: []const u8) bool {
        // Implementation for dependency checking
        // For now, return true (no dependencies)
        _ = self;
        _ = rule_name;
        return true;
    }
    
    // Get rules by priority level
    pub fn getRulesByPriority(self: *Self, priority: RulePriority) []Rule {
        var matching_rules = std.ArrayList(Rule).init(self.allocator);
        
        for (self.rules.items) |rule| {
            if (rule.priority == priority) {
                matching_rules.append(rule) catch continue;
            }
        }
        
        return matching_rules.toOwnedSlice() catch &[_]Rule{};
    }
    
    // Enable/disable rules by priority
    pub fn setRulePriorityEnabled(self: *Self, priority: RulePriority, enabled: bool) void {
        for (self.rules.items) |*rule| {
            if (rule.priority == priority) {
                rule.enabled = enabled;
            }
        }
    }
    
    // Get rule statistics
    pub fn getStats(self: *Self) RuleEngineStats {
        var stats = RuleEngineStats{};
        
        for (self.rules.items) |rule| {
            stats.total_rules += 1;
            if (rule.enabled) {
                stats.enabled_rules += 1;
            }
            
            switch (rule.priority) {
                .CRITICAL => stats.critical_rules += 1,
                .HIGH => stats.high_rules += 1,
                .MEDIUM => stats.medium_rules += 1,
                .LOW => stats.low_rules += 1,
            }
        }
        
        stats.total_dependencies = @intCast(self.dependencies.items.len);
        return stats;
    }
};

// Rule engine statistics
pub const RuleEngineStats = struct {
    total_rules: u32 = 0,
    enabled_rules: u32 = 0,
    critical_rules: u32 = 0,
    high_rules: u32 = 0,
    medium_rules: u32 = 0,
    low_rules: u32 = 0,
    total_dependencies: u32 = 0,
};

// Helper function for sorting rules by priority
fn rulePriorityLessThan(context: void, a: Rule, b: Rule) bool {
    _ = context;
    return @intFromEnum(a.priority) < @intFromEnum(b.priority);
}

// Utility functions for creating common rule validation results
pub const RuleUtils = struct {
    pub fn createErrorResult(rule_name: []const u8, comptime fmt: []const u8, args: anytype, allocator: std.mem.Allocator) !RuleResult {
        const error_message = try std.fmt.allocPrint(allocator, fmt, args);
        return RuleResult{
            .is_valid = false,
            .error_message = error_message,
            .rule_name = rule_name,
        };
    }
    
    pub fn createValidResult(rule_name: []const u8) RuleResult {
        return RuleResult.valid(rule_name);
    }
};

// Note: Tests for this module should be created in a separate test file 
// that properly imports the Lineup type from the lineup module