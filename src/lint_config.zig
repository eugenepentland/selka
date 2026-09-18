//! Strict `lint` object inside `mylang.json`: profile selection, per-rule
//! modes, and reasoned exemptions.
//!
//! The parser mirrors `project_config.zig`: unknown keys, duplicate keys and
//! malformed values are rejected with a located failure rather than silently
//! ignored, and every `exempt`/`allow` entry must carry a `reason`.
const std = @import("std");

/// How one rule participates in a run. `off` never measures; `report` prints
/// but never blocks; `ratchet` compares against a stored ceiling and may block
/// under `--gate`; `block` blocks under `--gate` and whenever `on_build` is
/// `block`.
pub const Mode = enum { off, report, ratchet, block };

/// Named bundle of per-rule defaults. `agent` demotes style rules to reports,
/// `strict` blocks everything blockable, `safety` additionally demotes size
/// budgets so a large legacy project can adopt without a wall.
pub const Profile = enum { agent, strict, safety };

/// Whether a plain `mylang lint` (no `--gate`) refuses on a `block` finding.
pub const OnBuild = enum { report, block };

/// Whether the compiler's `W_*` diagnostics become rejecting in the inner loop.
pub const Warnings = enum { report, deny };

/// One reviewed exception: a qualified declaration name and why it is exempt.
pub const Exemption = struct { name: []const u8, reason: []const u8 };

/// Per-rule configuration overrides. Every field is optional; an absent field
/// keeps the rule's own default for the selected profile.
pub const RuleSetting = struct {
    mode: ?Mode = null,
    max: ?usize = null,
    hard_max: ?usize = null,
    recover_pct: ?usize = null,
    exempt: []const Exemption = &.{},
    allow: []const Exemption = &.{},
    modules: []const []const u8 = &.{},
};

/// Located rejection detail for one malformed `lint` object.
pub const Failure = struct {
    detail: []const u8 = "invalid lint configuration",
    line: u64 = 1,
    column: u64 = 1,
};

/// Failures returned while parsing the `lint` object.
pub const Error = error{
    DuplicateField,
    InvalidJson,
    InvalidLint,
    OutOfMemory,
    UnknownField,
};

/// Parsed `lint` configuration. Owns every string it holds; call `deinit`.
pub const Config = struct {
    profile: Profile = .agent,
    on_build: OnBuild = .report,
    warnings: Warnings = .report,
    /// `undocumented-export` length floor in non-whitespace characters; 12 when
    /// the project does not set it.
    min_chars: ?usize = null,
    /// Per-rule overrides, keyed by rule name. The profile supplies the default
    /// for any rule without an entry.
    rules: std.StringHashMapUnmanaged(RuleSetting) = .empty,

    /// Release every owned key, string and array.
    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        var iterator = self.rules.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            freeSetting(allocator, entry.value_ptr.*);
        }
        self.rules.deinit(allocator);
        self.* = undefined;
    }

    /// The configured setting for `rule`, or null when the profile alone decides.
    pub fn setting(self: *const Config, rule: []const u8) ?*const RuleSetting {
        return self.rules.getPtr(rule);
    }

    /// Resolve one rule's mode: an explicit per-rule `mode` wins, then the
    /// parsed `block`/`report`/`ratchet` shorthands (already folded into the
    /// per-rule settings), then the profile default.
    pub fn modeFor(self: *const Config, rule: []const u8, profile_default: Mode) Mode {
        const entry = self.rules.get(rule) orelse return profile_default;
        return entry.mode orelse profile_default;
    }

    /// True when a finding for `rule` is enabled at all.
    pub fn enabled(self: *const Config, rule: []const u8, profile_default: Mode) bool {
        return self.modeFor(rule, profile_default) != .off;
    }
};

fn freeSetting(allocator: std.mem.Allocator, setting: RuleSetting) void {
    for (setting.exempt) |item| {
        allocator.free(item.name);
        allocator.free(item.reason);
    }
    if (setting.exempt.len != 0) allocator.free(setting.exempt);
    for (setting.allow) |item| {
        allocator.free(item.name);
        allocator.free(item.reason);
    }
    if (setting.allow.len != 0) allocator.free(setting.allow);
    for (setting.modules) |name| allocator.free(name);
    if (setting.modules.len != 0) allocator.free(setting.modules);
}

/// Parse the `lint` object out of one complete `mylang.json` document. Returns
/// an empty configuration when the document carries no `lint` object, so a
/// project without one runs the default `agent` profile.
pub fn parseConfig(allocator: std.mem.Allocator, bytes: []const u8, failure: *Failure) Error!Config {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var diagnostics: std.json.Scanner.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);
    const first = try readToken(allocator, &scanner, failure);
    defer freeToken(allocator, first);
    if (!isObjectBegin(first)) return fail(failure, &scanner, "mylang.json must be a JSON object", error.InvalidJson);
    var config: Config = .{};
    errdefer config.deinit(allocator);
    var found = false;
    while (true) {
        const key_token = try readToken(allocator, &scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, &scanner, "configuration keys must be strings", error.InvalidJson);
        const value = try readToken(allocator, &scanner, failure);
        defer freeToken(allocator, value);
        if (std.mem.eql(u8, key, "lint")) {
            if (found) return fail(failure, &scanner, "duplicate lint field", error.DuplicateField);
            if (!isObjectBegin(value)) return fail(failure, &scanner, "lint must be a JSON object", error.InvalidLint);
            config = try parseObject(allocator, &scanner, failure);
            found = true;
        } else switch (value) {
            .object_begin, .array_begin => try skipValue(allocator, &scanner, failure),
            else => {},
        }
    }
    return config;
}

/// Consume the rest of a JSON value whose opening object or array token was
/// already read.
fn skipValue(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!void {
    var depth: usize = 1;
    while (depth != 0) {
        const token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, token);
        switch (token) {
            .object_begin, .array_begin => depth += 1,
            .object_end, .array_end => depth -= 1,
            .end_of_document => return fail(failure, scanner, "unterminated JSON value", error.InvalidJson),
            else => {},
        }
    }
}

/// Parse the body of the `lint` object after its opening brace.
pub fn parseObject(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!Config {
    var config: Config = .{};
    errdefer config.deinit(allocator);
    var seen: u8 = 0;
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, scanner, "lint keys must be strings", error.InvalidLint);
        const bit = keyBit(key) orelse return fail(failure, scanner, "unknown field in lint", error.UnknownField);
        if (seen & bit != 0) return fail(failure, scanner, "duplicate lint field", error.DuplicateField);
        seen |= bit;
        if (std.mem.eql(u8, key, "profile")) {
            config.profile = (try readEnum(Profile, allocator, scanner, failure)) orelse return error.InvalidLint;
        } else if (std.mem.eql(u8, key, "on_build")) {
            config.on_build = (try readEnum(OnBuild, allocator, scanner, failure)) orelse return error.InvalidLint;
        } else if (std.mem.eql(u8, key, "warnings")) {
            config.warnings = (try readEnum(Warnings, allocator, scanner, failure)) orelse return error.InvalidLint;
        } else if (std.mem.eql(u8, key, "min_chars")) {
            config.min_chars = try readPositive(allocator, scanner, failure);
        } else if (std.mem.eql(u8, key, "block") or std.mem.eql(u8, key, "ratchet") or std.mem.eql(u8, key, "report")) {
            const mode: Mode = if (key[0] == 'b') .block else if (key[0] == 'r' and key[1] == 'a') .ratchet else .report;
            try parseShorthand(allocator, scanner, failure, &config, mode);
        } else if (std.mem.eql(u8, key, "rules")) {
            try parseRules(allocator, scanner, failure, &config);
        }
    }
    return config;
}

fn keyBit(key: []const u8) ?u8 {
    inline for (.{ "profile", "on_build", "warnings", "min_chars", "block", "ratchet", "report", "rules" }, 0..) |name, index| {
        if (std.mem.eql(u8, key, name)) return @as(u8, 1) << @intCast(index);
    }
    return null;
}

fn parseShorthand(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure, config: *Config, mode: Mode) Error!void {
    const first = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, first);
    if (!isArrayBegin(first)) return fail(failure, scanner, "block, ratchet and report must be arrays of rule names", error.InvalidLint);
    while (true) {
        const token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, token);
        if (isArrayEnd(token)) break;
        const name = stringText(token) orelse return fail(failure, scanner, "rule lists must carry strings", error.InvalidLint);
        if (name.len == 0) return fail(failure, scanner, "rule names must not be empty", error.InvalidLint);
        const owned = try allocator.dupe(u8, name);
        errdefer allocator.free(owned);
        const gop = try config.rules.getOrPut(allocator, owned);
        if (gop.found_existing) {
            allocator.free(owned);
            gop.value_ptr.mode = mode;
        } else {
            gop.value_ptr.* = .{ .mode = mode };
        }
    }
}

fn parseRules(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure, config: *Config) Error!void {
    const first = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, first);
    if (!isObjectBegin(first)) return fail(failure, scanner, "rules must be a JSON object", error.InvalidLint);
    var named: std.StringHashMapUnmanaged(void) = .empty;
    defer named.deinit(allocator);
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const rule = stringText(key_token) orelse return fail(failure, scanner, "rule names must be strings", error.InvalidLint);
        if (rule.len == 0) return fail(failure, scanner, "rule names must not be empty", error.InvalidLint);
        const gop = try named.getOrPut(allocator, rule);
        if (gop.found_existing) return fail(failure, scanner, "duplicate rule entry", error.DuplicateField);
        const owned = try allocator.dupe(u8, rule);
        errdefer allocator.free(owned);
        const entry = try config.rules.getOrPut(allocator, owned);
        if (entry.found_existing) {
            allocator.free(owned);
        } else {
            entry.value_ptr.* = .{};
        }
        errdefer {
            if (!entry.found_existing) _ = config.rules.remove(owned);
        }
        try parseRuleSetting(allocator, scanner, failure, entry.value_ptr);
    }
}

fn parseRuleSetting(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure, setting: *RuleSetting) Error!void {
    const first = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, first);
    if (!isObjectBegin(first)) return fail(failure, scanner, "a rule setting must be a JSON object", error.InvalidLint);
    var seen: u8 = 0;
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, scanner, "rule setting keys must be strings", error.InvalidLint);
        const bit = settingBit(key) orelse return fail(failure, scanner, "unknown field in a rule setting", error.UnknownField);
        if (seen & bit != 0) return fail(failure, scanner, "duplicate rule setting field", error.DuplicateField);
        seen |= bit;
        if (std.mem.eql(u8, key, "mode")) {
            setting.mode = (try readEnum(Mode, allocator, scanner, failure)) orelse return error.InvalidLint;
        } else if (std.mem.eql(u8, key, "max")) {
            setting.max = try readPositive(allocator, scanner, failure);
        } else if (std.mem.eql(u8, key, "hard_max")) {
            setting.hard_max = try readPositive(allocator, scanner, failure);
        } else if (std.mem.eql(u8, key, "recover_pct")) {
            setting.recover_pct = try readPositive(allocator, scanner, failure);
        } else if (std.mem.eql(u8, key, "exempt")) {
            setting.exempt = try parseExemptions(allocator, scanner, failure);
        } else if (std.mem.eql(u8, key, "allow")) {
            setting.allow = try parseExemptions(allocator, scanner, failure);
        } else {
            setting.modules = try parseStringArray(allocator, scanner, failure);
        }
    }
}

fn settingBit(key: []const u8) ?u8 {
    inline for (.{ "mode", "max", "hard_max", "recover_pct", "exempt", "allow", "modules" }, 0..) |name, index| {
        if (std.mem.eql(u8, key, name)) return @as(u8, 1) << @intCast(index);
    }
    return null;
}

fn parseExemptions(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error![]const Exemption {
    const first = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, first);
    if (!isArrayBegin(first)) return fail(failure, scanner, "exempt and allow must be arrays", error.InvalidLint);
    var items: std.ArrayList(Exemption) = .empty;
    errdefer {
        for (items.items) |item| {
            allocator.free(item.name);
            allocator.free(item.reason);
        }
        items.deinit(allocator);
    }
    while (true) {
        const token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, token);
        if (isArrayEnd(token)) break;
        if (!isObjectBegin(token)) return fail(failure, scanner, "an exemption must be an object", error.InvalidLint);
        var name: ?[]const u8 = null;
        var reason: ?[]const u8 = null;
        errdefer if (name) |value| allocator.free(value);
        errdefer if (reason) |value| allocator.free(value);
        while (true) {
            const entry_key = try readToken(allocator, scanner, failure);
            defer freeToken(allocator, entry_key);
            if (isObjectEnd(entry_key)) break;
            const key = stringText(entry_key) orelse return fail(failure, scanner, "exemption keys must be strings", error.InvalidLint);
            const value_token = try readToken(allocator, scanner, failure);
            defer freeToken(allocator, value_token);
            const text = stringText(value_token) orelse return fail(failure, scanner, "exemption values must be strings", error.InvalidLint);
            if (std.mem.eql(u8, key, "name")) {
                if (name != null) return fail(failure, scanner, "duplicate exemption field", error.DuplicateField);
                name = try allocator.dupe(u8, text);
            } else if (std.mem.eql(u8, key, "reason")) {
                if (reason != null) return fail(failure, scanner, "duplicate exemption field", error.DuplicateField);
                reason = try allocator.dupe(u8, text);
            } else return fail(failure, scanner, "unknown field in an exemption", error.UnknownField);
        }
        const owned_name = name orelse return fail(failure, scanner, "an exemption needs a name", error.InvalidLint);
        const owned_reason = reason orelse return fail(failure, scanner, "an exemption needs a reason", error.InvalidLint);
        if (owned_reason.len == 0) return fail(failure, scanner, "an exemption reason must not be empty", error.InvalidLint);
        try items.append(allocator, .{ .name = owned_name, .reason = owned_reason });
    }
    return items.toOwnedSlice(allocator);
}

fn parseStringArray(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error![]const []const u8 {
    const first = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, first);
    if (!isArrayBegin(first)) return fail(failure, scanner, "modules must be an array of module globs", error.InvalidLint);
    var items: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (items.items) |item| allocator.free(item);
        items.deinit(allocator);
    }
    while (true) {
        const token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, token);
        if (isArrayEnd(token)) break;
        const text = stringText(token) orelse return fail(failure, scanner, "module globs must be strings", error.InvalidLint);
        if (text.len == 0) return fail(failure, scanner, "a module glob must not be empty", error.InvalidLint);
        try items.append(allocator, try allocator.dupe(u8, text));
    }
    return items.toOwnedSlice(allocator);
}

fn readEnum(comptime T: type, allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!?T {
    const token = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, token);
    const text = stringText(token) orelse return fail(failure, scanner, "enum fields must be strings", error.InvalidLint);
    if (std.meta.stringToEnum(T, text)) |value| return value;
    return fail(failure, scanner, "unknown enum value in lint", error.InvalidLint);
}

/// One rejection message reused by every malformed numeric lint field.
const invalid_number_detail = "numeric lint fields must be positive integers";

fn readPositive(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!usize {
    const token = try readToken(allocator, scanner, failure);
    defer freeToken(allocator, token);
    const text = numberText(token) orelse return fail(failure, scanner, invalid_number_detail, error.InvalidLint);
    const value = std.fmt.parseUnsigned(usize, text, 10) catch return fail(failure, scanner, invalid_number_detail, error.InvalidLint);
    if (value == 0) return fail(failure, scanner, invalid_number_detail, error.InvalidLint);
    return value;
}

/// Read one token, consuming it.
fn readToken(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!std.json.Scanner.Token {
    return scanner.nextAlloc(allocator, .alloc_if_needed) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => fail(failure, scanner, "malformed JSON", error.InvalidJson),
    };
}

fn freeToken(allocator: std.mem.Allocator, token: std.json.Scanner.Token) void {
    switch (token) {
        .allocated_string, .allocated_number => |value| allocator.free(value),
        else => {},
    }
}

fn fail(failure: *Failure, scanner: *const std.json.Scanner, detail: []const u8, err: Error) Error {
    failure.detail = detail;
    if (scanner.diagnostics) |diagnostics| {
        failure.line = diagnostics.getLine();
        failure.column = diagnostics.getColumn();
    }
    return err;
}

fn isObjectBegin(token: std.json.Scanner.Token) bool {
    return token == .object_begin;
}
fn isObjectEnd(token: std.json.Scanner.Token) bool {
    return token == .object_end;
}
fn isArrayBegin(token: std.json.Scanner.Token) bool {
    return token == .array_begin;
}
fn isArrayEnd(token: std.json.Scanner.Token) bool {
    return token == .array_end;
}
fn stringText(token: std.json.Scanner.Token) ?[]const u8 {
    return switch (token) {
        .string, .partial_string, .allocated_string => |value| value,
        else => null,
    };
}
fn numberText(token: std.json.Scanner.Token) ?[]const u8 {
    return switch (token) {
        .number, .partial_number, .allocated_number => |value| value,
        else => null,
    };
}
