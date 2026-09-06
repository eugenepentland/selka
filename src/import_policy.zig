//! Opt-in dependency direction policy; never a language-validity rule.
/// Failures returned by parse; callers must handle these boundary errors.
pub const ParseError = error{
    InternalError,
    DuplicateField,
    DuplicatePolicyRule,
    InvalidCharacter,
    InvalidEnumTag,
    InvalidNumber,
    InvalidPolicyPattern,
    InvalidPolicyReason,
    MissingField,
    OutOfMemory,
    Overflow,
    PolicyTooLarge,
    SyntaxError,
    TooManyPolicyRules,
    UnexpectedEndOfInput,
    UnexpectedToken,
    UnknownField,
    UnsupportedPolicyVersion,
};
/// Failures returned by evaluate; callers must handle these boundary errors.
pub const EvaluateError = error{
    IncompleteProject,
    OutOfMemory,
};

const std = @import("std");
const graph = @import("project.zig");
pub const version = "import-direction-v1";
/// Allow or deny outcome applied to a resolved import edge.
pub const Action = enum { allow, deny };
/// Source/target namespace patterns and the documented reason for their action.
pub const Rule = struct { from: []const u8, to: []const u8, action: Action, reason: []const u8 };
/// Versioned ordered policy rules and the default edge action.
pub const Document = struct { version: u32, default_action: Action, rules: []const Rule };
/// Validated import policy owning the parsed document storage.
pub const Policy = struct {
    parsed: std.json.Parsed(Document),
    digest: [32]u8,
    /// Validate policy version, keys, patterns, duplicate rules, and required reasons.
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Policy {
        if (bytes.len > 1024 * 1024) return error.PolicyTooLarge;
        // parseFromSlice supplies complete input and uses its length as max_value_len.
        // These concrete documents contain no fixed-size arrays; generic parser-only
        // failures indicate an internal contract mismatch, not a caller input category.
        const parsed = std.json.parseFromSlice(Document, allocator, bytes, .{ .allocate = .alloc_always }) catch |err| switch (err) {
            error.BufferUnderrun, error.LengthMismatch, error.ValueTooLong => return error.InternalError,
            else => |failure| return failure,
        };
        errdefer parsed.deinit();
        if (parsed.value.version != 1) return error.UnsupportedPolicyVersion;
        if (parsed.value.rules.len > 1024) return error.TooManyPolicyRules;
        for (parsed.value.rules, 0..) |rule, i| {
            if (!validPattern(rule.from) or !validPattern(rule.to)) return error.InvalidPolicyPattern;
            if (rule.reason.len == 0 or rule.reason.len > 512 or !std.unicode.utf8ValidateSlice(rule.reason)) return error.InvalidPolicyReason;
            for (rule.reason) |byte| if (byte < 32 or byte == 127) return error.InvalidPolicyReason;
            for (parsed.value.rules[0..i]) |previous| {
                if (std.mem.eql(u8, rule.from, previous.from) and std.mem.eql(u8, rule.to, previous.to)) return error.DuplicatePolicyRule;
            }
        }
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        return .{ .parsed = parsed, .digest = digest };
    }
    pub fn deinit(self: *Policy) void {
        self.parsed.deinit();
    }
};
/// Check a namespace pattern with supported segment wildcard syntax.
pub fn validPattern(pattern: []const u8) bool {
    if (pattern.len > 256) return false;
    if (std.mem.eql(u8, pattern, "*")) return true;
    const name = if (std.mem.endsWith(u8, pattern, ".*")) pattern[0 .. pattern.len - 2] else pattern;
    return graph.validName(name);
}
/// Match a module name while respecting namespace segment boundaries.
pub fn matches(pattern: []const u8, name: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.endsWith(u8, pattern, ".*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return name.len > prefix.len and std.mem.startsWith(u8, name, prefix);
    }
    return std.mem.eql(u8, pattern, name);
}
/// Resolved import edge and the first matching rule, or default action.
pub const Decision = struct { module: usize, imported: usize, rule: ?usize, action: Action };
/// Owned edge decisions and rule-match evidence for the reachable project graph.
pub const Report = struct {
    arena: std.heap.ArenaAllocator,
    decisions: []const Decision,
    rule_hits: []const usize,
    denied: usize,
    pub fn deinit(self: *Report) void {
        self.arena.deinit();
    }
};
/// Apply ordered rules to the loaded graph without changing language semantics.
pub fn evaluate(allocator: std.mem.Allocator, project: *const graph.Project, policy: Policy) EvaluateError!Report {
    if (!project.progress.complete or project.problem != null) return error.IncompleteProject;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const hits = try scratch.alloc(usize, policy.parsed.value.rules.len);
    @memset(hits, 0);
    var decisions: std.ArrayList(Decision) = .empty;
    var denied: usize = 0;
    for (project.order.items) |id| {
        const module = project.modules.items[id];
        for (module.imports, 0..) |imported, i| {
            var action = policy.parsed.value.default_action;
            var chosen: ?usize = null;
            for (policy.parsed.value.rules, 0..) |rule, r| {
                if (!matches(rule.from, module.name) or !matches(rule.to, project.modules.items[imported.target].name)) continue;
                action = rule.action;
                chosen = r;
                hits[r] += 1;
                break;
            }
            if (action == .deny) denied += 1;
            try decisions.append(scratch, .{ .module = id, .imported = i, .rule = chosen, .action = action });
        }
    }
    return .{ .arena = arena, .decisions = try decisions.toOwnedSlice(scratch), .rule_hits = hits, .denied = denied };
}
/// Allocate the edge decisions, source evidence, and policy identity as a text report.
pub fn render(allocator: std.mem.Allocator, report: Report, project: *const graph.Project, policy: Policy) std.mem.Allocator.Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    writer.print("{s}: {s}; scope=reachable-import-graph; edges={d}; denied={d}; config-sha256={s}\n", .{
        version,
        if (report.denied == 0) "passed" else "failed",
        report.decisions.len,
        report.denied,
        std.fmt.bytesToHex(policy.digest, .lower),
    }) catch return error.OutOfMemory;
    writer.writeAll("Policy is separate from language validity; first matching rule wins.\n") catch return error.OutOfMemory;
    for (report.decisions) |decision| {
        const module = project.modules.items[decision.module];
        const imported = module.imports[decision.imported];
        const at = module.src.locate(imported.span.start);
        writer.print("{s}:{d}:{d}: {s} -> {s}: {s}", .{ at.path, at.line, at.column, module.name, project.modules.items[imported.target].name, @tagName(decision.action) }) catch return error.OutOfMemory;
        if (decision.rule) |rule| writer.print("; rule={d}; {s}\n", .{ rule + 1, policy.parsed.value.rules[rule].reason }) catch return error.OutOfMemory else writer.writeAll("; rule=default\n") catch return error.OutOfMemory;
    }
    for (report.rule_hits, 0..) |hits, rule| writer.print("rule {d}: matched-edges={d}\n", .{ rule + 1, hits }) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}
