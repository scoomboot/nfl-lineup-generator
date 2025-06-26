const std = @import("std");

// Rule validation result
pub const RuleResult = struct {
    is_valid: bool,
    error_message: ?[]const u8 = null,
    rule_name: []const u8,
    owns_error_message: bool = false, // Track if we need to free error_message
    
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
    
    pub fn invalidOwned(rule_name: []const u8, error_message: []const u8) Self {
        return Self{
            .is_valid = false,
            .error_message = error_message,
            .rule_name = rule_name,
            .owns_error_message = true,
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.owns_error_message and self.error_message != null) {
            allocator.free(self.error_message.?);
            self.error_message = null;
            self.owns_error_message = false;
        }
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

// Type-safe rule interface using void pointers to avoid @ptrCast
// The concrete lineup type is passed through the validation context
pub const Rule = struct {
    // Rule metadata
    name: []const u8,
    priority: RulePriority,
    enabled: bool = true,
    
    // Type-safe rule validation function pointer
    // Uses *const anyopaque instead of opaque type to avoid @ptrCast
    validateFn: *const fn (rule: *const Rule, target_lineup: *const anyopaque, allocator: std.mem.Allocator) anyerror!RuleResult,
    
    const Self = @This();
    
    pub fn validate(self: *const Self, target_lineup: *const anyopaque, allocator: std.mem.Allocator) !RuleResult {
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
    lineup: *const anyopaque,
    contest_rules: ?*const ContestRules = null,
    
    const Self = @This();
    
    pub fn init(target_lineup: *const anyopaque) Self {
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
        // Clean up individual RuleResult error messages with null protection
        for (self.passed_rules) |*result| {
            result.deinit(allocator);
        }
        for (self.failed_rules) |*result| {
            result.deinit(allocator);
        }
        for (self.warnings) |*result| {
            result.deinit(allocator);
        }
        
        // Free the slices themselves - safe to call on valid slices
        if (self.passed_rules.len > 0) allocator.free(self.passed_rules);
        if (self.failed_rules.len > 0) allocator.free(self.failed_rules);
        if (self.warnings.len > 0) allocator.free(self.warnings);
        
        // Reset to prevent double-free
        self.passed_rules = &[_]RuleResult{};
        self.failed_rules = &[_]RuleResult{};
        self.warnings = &[_]RuleResult{};
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
    rule_map: std.HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), // name -> index in rules
    dependencies: std.ArrayList(RuleDependency),
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .rules = std.ArrayList(Rule).init(allocator),
            .rule_map = std.HashMap([]const u8, usize, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .dependencies = std.ArrayList(RuleDependency).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.rules.deinit();
        self.rule_map.deinit();
        self.dependencies.deinit();
    }
    
    // Add a rule to the engine
    pub fn addRule(self: *Self, rule: Rule) !void {
        // Check if rule name already exists
        if (self.rule_map.contains(rule.name)) {
            return error.DuplicateRuleName;
        }
        
        const index = self.rules.items.len;
        try self.rules.append(rule);
        try self.rule_map.put(rule.name, index);
    }
    
    // Add a rule dependency
    pub fn addDependency(self: *Self, dependency: RuleDependency) !void {
        try self.dependencies.append(dependency);
    }
    
    // Remove a rule by name
    pub fn removeRule(self: *Self, rule_name: []const u8) bool {
        if (self.rule_map.get(rule_name)) |index| {
            _ = self.rules.orderedRemove(index);
            _ = self.rule_map.remove(rule_name);
            
            // Update indices in map for rules that were shifted
            var iterator = self.rule_map.iterator();
            while (iterator.next()) |entry| {
                if (entry.value_ptr.* > index) {
                    entry.value_ptr.* -= 1;
                }
            }
            return true;
        }
        return false;
    }
    
    // Get rule by name - O(1) lookup
    pub fn getRule(self: *Self, rule_name: []const u8) ?*Rule {
        if (self.rule_map.get(rule_name)) |index| {
            return &self.rules.items[index];
        }
        return null;
    }
    
    // Validate lineup against all rules
    pub fn validateLineup(self: *Self, target_lineup: *const anyopaque) !ValidationResult {
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
            // Check dependencies before validation
            if (!self.checkDependencies(rule.name, passed_rules.items)) {
                // Skip rule due to unsatisfied dependencies
                const skip_result = RuleResult.valid(rule.name); // Consider dependency skip as valid
                try passed_rules.append(skip_result);
                continue;
            }
            
            const result = rule.validate(target_lineup, self.allocator) catch |err| {
                // Handle rule validation errors - create owned error message
                const error_msg = try std.fmt.allocPrint(self.allocator, "Rule validation error: {}", .{err});
                const error_result = RuleResult.invalidOwned(rule.name, error_msg);
                try failed_rules.append(error_result);
                overall_valid = false;
                continue;
            };
            
            if (result.is_valid) {
                try passed_rules.append(result);
            } else {
                // CRITICAL and HIGH priority rule failures make lineup invalid
                if (rule.priority == .CRITICAL or rule.priority == .HIGH) {
                    try failed_rules.append(result);
                    overall_valid = false;
                } else {
                    // MEDIUM and LOW priority failures are warnings only
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
    fn checkDependencies(self: *Self, rule_name: []const u8, passed_rules: []const RuleResult) bool {
        for (self.dependencies.items) |dependency| {
            if (std.mem.eql(u8, dependency.rule_name, rule_name)) {
                switch (dependency.dependency_type) {
                    .REQUIRES => {
                        // Check if required rule has passed
                        var found_passed = false;
                        for (passed_rules) |result| {
                            if (std.mem.eql(u8, result.rule_name, dependency.rule_name) and result.is_valid) {
                                found_passed = true;
                                break;
                            }
                        }
                        if (!found_passed) return false;
                    },
                    .CONFLICTS => {
                        // Check if conflicting rule has passed - if so, this rule should not run
                        for (passed_rules) |result| {
                            if (std.mem.eql(u8, result.rule_name, dependency.rule_name) and result.is_valid) {
                                return false; // Conflict detected
                            }
                        }
                    },
                    .ENHANCES => {
                        // ENHANCES rules can always run, they just work better when other rules pass
                        // No blocking behavior needed
                    },
                }
            }
        }
        return true;
    }
    
    // Detect dependency cycles during rule registration
    fn hasDependencyCycle(self: *Self, new_dependency: RuleDependency) bool {
        // Simple cycle detection: check if adding this dependency would create a cycle
        var visited = std.HashMap([]const u8, void, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(self.allocator);
        defer visited.deinit();
        
        return self.visitDependency(new_dependency.rule_name, &visited, new_dependency);
    }
    
    fn visitDependency(self: *Self, rule_name: []const u8, visited: *std.HashMap([]const u8, void, std.hash_map.StringContext, std.hash_map.default_max_load_percentage), target_dependency: RuleDependency) bool {
        // If we've already visited this rule, we have a cycle
        if (visited.contains(rule_name)) {
            return true;
        }
        
        visited.put(rule_name, {}) catch return false;
        
        // Check if this rule depends on the target dependency's rule_name
        if (std.mem.eql(u8, rule_name, target_dependency.rule_name)) {
            return true; // Cycle detected
        }
        
        // Visit all rules that this rule depends on
        for (self.dependencies.items) |dependency| {
            if (std.mem.eql(u8, dependency.rule_name, rule_name) and dependency.dependency_type == .REQUIRES) {
                if (self.visitDependency(dependency.rule_name, visited, target_dependency)) {
                    return true;
                }
            }
        }
        
        _ = visited.remove(rule_name);
        return false;
    }
    
    // Enhanced addDependency with cycle detection
    pub fn addDependencyWithValidation(self: *Self, dependency: RuleDependency) !void {
        // Validate that both rules exist
        if (self.getRule(dependency.rule_name) == null) {
            return error.RuleNotFound;
        }
        
        // Check for dependency cycles
        if (self.hasDependencyCycle(dependency)) {
            return error.DependencyCycle;
        }
        
        try self.dependencies.append(dependency);
    }
    
    /// Get rules by priority level - returns owned slice, caller must free with allocator.free()
    pub fn getRulesByPriority(self: *Self, priority: RulePriority, allocator: std.mem.Allocator) ![]Rule {
        var matching_rules = std.ArrayList(Rule).init(allocator);
        errdefer matching_rules.deinit();
        
        for (self.rules.items) |rule| {
            if (rule.priority == priority) {
                try matching_rules.append(rule);
            }
        }
        
        return try matching_rules.toOwnedSlice();
    }
    
    /// Helper function to get count of rules by priority without allocating
    pub fn countRulesByPriority(self: *Self, priority: RulePriority) u32 {
        var count: u32 = 0;
        for (self.rules.items) |rule| {
            if (rule.priority == priority) {
                count += 1;
            }
        }
        return count;
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
    /// Creates an error result with allocated error message - caller must call result.deinit()
    pub fn createErrorResult(rule_name: []const u8, comptime fmt: []const u8, args: anytype, allocator: std.mem.Allocator) !RuleResult {
        const error_message = try std.fmt.allocPrint(allocator, fmt, args);
        return RuleResult.invalidOwned(rule_name, error_message);
    }
    
    pub fn createValidResult(rule_name: []const u8) RuleResult {
        return RuleResult.valid(rule_name);
    }
};

// Note: Tests for this module should be created in a separate test file 
// that properly imports the Lineup type from the lineup module