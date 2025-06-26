const std = @import("std");
const lineup_mod = @import("../lineup.zig");
const rules_mod = @import("rules.zig");

const Lineup = lineup_mod.Lineup;
const Rule = rules_mod.Rule;
const RuleResult = rules_mod.RuleResult;
const RuleUtils = rules_mod.RuleUtils;
const createLineupValidationFn = rules_mod.createLineupValidationFn;

const DRAFTKINGS_SALARY_CAP: u32 = 50000;

pub fn createSalaryCapRule() Rule {
    return Rule{
        .name = "SalaryCapRule",
        .priority = .CRITICAL,
        .validateFn = createLineupValidationFn(validateSalaryCap),
    };
}

fn validateSalaryCap(lineup: *const Lineup, allocator: std.mem.Allocator) !RuleResult {
    const total_salary = lineup.total_salary;
    
    if (total_salary != DRAFTKINGS_SALARY_CAP) {
        return try RuleUtils.createErrorResult(
            "SalaryCapRule",
            "Lineup salary ${d} must equal exactly ${d} (DraftKings requirement)",
            .{ total_salary, DRAFTKINGS_SALARY_CAP },
            allocator
        );
    }
    
    return RuleResult.valid("SalaryCapRule");
}

test "SalaryCapRule validation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    // Test case 1: Exact salary cap should pass
    {
        var lineup = Lineup.init();
        lineup.total_salary = DRAFTKINGS_SALARY_CAP;
        
        const result = try validateSalaryCap(&lineup, allocator);
        try testing.expect(result.is_valid);
        try testing.expectEqualStrings("SalaryCapRule", result.rule_name);
    }
    
    // Test case 2: Under salary cap should fail
    {
        var lineup = Lineup.init();
        lineup.total_salary = DRAFTKINGS_SALARY_CAP - 100;
        
        var result = try validateSalaryCap(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("SalaryCapRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "49900") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "50000") != null);
    }
    
    // Test case 3: Over salary cap should fail
    {
        var lineup = Lineup.init();
        lineup.total_salary = DRAFTKINGS_SALARY_CAP + 500;
        
        var result = try validateSalaryCap(&lineup, allocator);
        defer result.deinit(allocator);
        
        try testing.expect(!result.is_valid);
        try testing.expectEqualStrings("SalaryCapRule", result.rule_name);
        try testing.expect(result.error_message != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "50500") != null);
        try testing.expect(std.mem.indexOf(u8, result.error_message.?, "50000") != null);
    }
}

test "SalaryCapRule integration" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var engine = rules_mod.LineupRuleEngine.init(allocator);
    defer engine.deinit();
    
    try engine.addRule(createSalaryCapRule());
    
    // Test with valid lineup
    var valid_lineup = Lineup.init();
    valid_lineup.total_salary = DRAFTKINGS_SALARY_CAP;
    
    var valid_result = try engine.validateLineup(&valid_lineup);
    defer valid_result.deinit(allocator);
    
    try testing.expect(valid_result.is_valid);
    try testing.expect(valid_result.passed_rules.len == 1);
    try testing.expect(valid_result.failed_rules.len == 0);
    
    // Test with invalid lineup
    var invalid_lineup = Lineup.init();
    invalid_lineup.total_salary = DRAFTKINGS_SALARY_CAP - 1000;
    
    var invalid_result = try engine.validateLineup(&invalid_lineup);
    defer invalid_result.deinit(allocator);
    
    try testing.expect(!invalid_result.is_valid);
    try testing.expect(invalid_result.passed_rules.len == 0);
    try testing.expect(invalid_result.failed_rules.len == 1);
}