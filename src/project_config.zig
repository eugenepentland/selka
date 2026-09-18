//! Minimal `mylang.json` project configuration and its required import policy.
//!
//! Discovery is anchored to the entry source file, never to the shell working
//! directory: the first `mylang.json` found from the entry file's directory up
//! toward the filesystem root wins. A configured `import_policy` path is
//! resolved against the directory that holds the winning configuration.
//!
//! This module owns only the strict configuration shape and the policy file's
//! exact bytes. Policy parsing and evaluation live in `import_policy.zig` so
//! the CLI can keep one authoritative evaluator.
const std = @import("std");

/// Configuration filename frozen by the A1 contract.
pub const config_name = "mylang.json";
/// Exact configuration byte ceiling; a larger file is a configuration failure.
pub const max_config_bytes = 1024 * 1024;

/// Failures returned while discovering or loading a project configuration.
pub const Error = error{
    ConfigTooLarge,
    DuplicateField,
    InvalidBudget,
    InvalidImportPolicy,
    InvalidJson,
    InvalidLint,
    InvalidVersion,
    MissingConfig,
    MissingImportPolicy,
    MissingVersion,
    OutOfMemory,
    PolicyTooLarge,
    ReadFailed,
    UnsupportedVersion,
    UnknownField,
};

/// One-based source location used to render located configuration diagnostics.
pub const Location = struct { line: u64 = 1, column: u64 = 1 };

/// Caller-visible failure detail: which file rejected the configuration, where,
/// and a short human-readable reason.
pub const Failure = struct {
    path: []const u8 = "",
    location: Location = .{},
    detail: []const u8 = "invalid project configuration",
};

/// One rejection message reused by every malformed numeric budget field.
const invalid_budget_detail = "budget values must be positive integers";

/// Optional `budgets` object in `mylang.json`. Each absent field keeps the
/// matching `project.Options` default; present values must be positive integers.
pub const Budgets = struct {
    max_modules: ?usize = null,
    max_imports: ?usize = null,
    max_file_bytes: ?usize = null,
    max_total_bytes: ?usize = null,
};

/// Strict minimal configuration shape. Unknown fields, duplicate keys and
/// unsupported versions are rejected before any policy is loaded.
pub const Document = struct {
    version: u32,
    import_policy: ?[]const u8 = null,
    /// Per-project source-loading limits; all fields absent uses the defaults.
    budgets: Budgets = .{},
    /// Whether a `lint` object was present; its contents are parsed by the
    /// `mylang` module's lint driver, which owns those types.
    lint: bool = false,
};

/// One resolved policy file: absolute path, exact bytes and content digest.
pub const PolicyFile = struct {
    path: []const u8,
    bytes: []const u8,
    digest: [32]u8,
    /// Whether the configuration's `import_policy` value was absolute.
    absolute: bool = false,
};

/// A parsed, validated configuration owning its file bytes and, when present,
/// the resolved import policy file.
pub const Config = struct {
    allocator: std.mem.Allocator,
    /// Absolute path of the winning `mylang.json`.
    path: []const u8,
    /// Exact configuration bytes.
    bytes: []const u8,
    digest: [32]u8,
    document: Document,
    /// Resolved policy file, when `import_policy` is configured.
    policy: ?PolicyFile = null,

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.bytes);
        self.allocator.free(self.path);
        if (self.document.import_policy) |value| self.allocator.free(value);
        if (self.policy) |value| {
            self.allocator.free(value.path);
            self.allocator.free(value.bytes);
        }
        self.* = undefined;
    }

    /// True when this configuration requires import-direction policy checking.
    pub fn hasPolicy(self: *const Config) bool {
        return self.policy != null;
    }

    /// Combine the exact configuration and policy bytes into the cache identity
    /// used for successful-verdict reuse. Returns false when neither a policy
    /// nor a `lint` object is configured, because configuration alone cannot
    /// change acceptance.
    pub fn cacheIdentity(self: *const Config, out: *[64]u8) bool {
        if (self.policy == null and !self.document.lint) return false;
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("project-config-cache-identity-v2");
        hash.update(&self.digest);
        if (self.policy) |policy| hash.update(&policy.digest);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        out.* = std.fmt.bytesToHex(digest, .lower);
        return true;
    }

    /// Content digests for verification receipts. Every field uses `allocator`.
    pub fn receipt(self: *const Config, allocator: std.mem.Allocator) std.mem.Allocator.Error!Receipt {
        return .{
            .config_sha256 = try hexDigest(allocator, self.digest),
            .policy_sha256 = if (self.policy) |policy| try hexDigest(allocator, policy.digest) else null,
        };
    }
};

/// Digest strings that participate in verification receipts.
pub const Receipt = struct { config_sha256: []const u8, policy_sha256: ?[]const u8 = null };

fn hexDigest(allocator: std.mem.Allocator, digest: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

/// Find the nearest `mylang.json` starting at the entry file's directory.
/// Returns an owned absolute path, or null when no configuration exists.
pub fn discover(allocator: std.mem.Allocator, io: std.Io, entry_path: []const u8) Error!?[]const u8 {
    const absolute = try absoluteEntry(allocator, io, entry_path);
    defer allocator.free(absolute);
    var directory = std.fs.path.dirname(absolute) orelse return null;
    while (true) {
        const candidate = try std.fs.path.join(allocator, &.{ directory, config_name });
        if (exists(io, candidate)) return candidate;
        allocator.free(candidate);
        const parent = std.fs.path.dirname(directory) orelse return null;
        if (std.mem.eql(u8, parent, directory)) return null;
        directory = parent;
    }
}

/// A standalone `*_test.my` entry's resolved project location: `root` is the
/// absolute enclosing project directory, `relative` is the entry path beneath
/// it (`tests/parser_test.my`), and `name` is the dotted module name
/// (`tests.parser_test`). Every slice is owned by the caller's allocator.
pub const TestEntry = struct { root: []const u8, relative: []const u8, name: []const u8 };

/// Resolve a standalone `*_test.my` entry against its enclosing project: the
/// nearest ancestor holding `mylang.json`, else the nearest ancestor holding a
/// non-test `.my` source, else the entry's own directory. Returns null when the
/// entry is not a `*_test.my` or sits under a path that cannot spell a dotted
/// module name. The caller owns the slices of a non-null result. The projection
/// the test runner materializes has a stub `main` appended, so this decision
/// rests only on the `*_test.my` convention, never on the file's own contents.
pub fn testEntryLocation(allocator: std.mem.Allocator, io: std.Io, entry_path: []const u8) Error!?TestEntry {
    const absolute = try absoluteEntry(allocator, io, entry_path);
    defer allocator.free(absolute);
    if (!std.mem.endsWith(u8, std.fs.path.basename(absolute), "_test.my")) return null;
    const entry_directory = std.fs.path.dirname(absolute) orelse return null;
    const root = (try nearestProjectRoot(allocator, io, entry_directory)) orelse try allocator.dupe(u8, entry_directory);
    if (!std.mem.startsWith(u8, absolute, root) or absolute.len <= root.len + 1 or absolute[root.len] != std.fs.path.sep) {
        allocator.free(root);
        return null;
    }
    const relative = allocator.dupe(u8, absolute[root.len + 1 ..]) catch |err| {
        allocator.free(root);
        return err;
    };
    const stem = relative[0 .. relative.len - ".my".len];
    if (!validModuleName(stem)) {
        allocator.free(relative);
        allocator.free(root);
        return null;
    }
    const name = allocator.dupe(u8, stem) catch |err| {
        allocator.free(relative);
        allocator.free(root);
        return err;
    };
    for (name) |*byte| {
        if (byte.* == std.fs.path.sep) byte.* = '.';
    }
    return .{ .root = root, .relative = relative, .name = name };
}

/// Walk from `start` toward the filesystem root for the enclosing project root.
fn nearestProjectRoot(allocator: std.mem.Allocator, io: std.Io, start: []const u8) Error!?[]const u8 {
    var directory = start;
    while (true) {
        const candidate = try std.fs.path.join(allocator, &.{ directory, config_name });
        const configured = exists(io, candidate);
        allocator.free(candidate);
        if (configured) {
            const found = try allocator.dupe(u8, directory);
            return found;
        }
        if (hasProjectSource(io, directory)) {
            const found = try allocator.dupe(u8, directory);
            return found;
        }
        const parent = std.fs.path.dirname(directory) orelse return null;
        if (std.mem.eql(u8, parent, directory)) return null;
        directory = parent;
    }
}

/// Whether `directory` directly holds a `.my` source that is not a test entry,
/// the evidence that it is a project root rather than a test-only subdirectory.
fn hasProjectSource(io: std.Io, directory: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true, .follow_symlinks = false }) catch return false;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (iterator.next(io) catch return false) |item| {
        if (item.kind != .file) continue;
        if (!std.mem.endsWith(u8, item.name, ".my")) continue;
        if (std.mem.endsWith(u8, item.name, "_test.my")) continue;
        return true;
    }
    return false;
}

/// Whether a directory path spells a valid dotted module name when separators
/// are read as dots.
fn validModuleName(stem: []const u8) bool {
    if (stem.len == 0) return false;
    var parts = std.mem.splitScalar(u8, stem, std.fs.path.sep);
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        if (!std.ascii.isAlphabetic(part[0]) and part[0] != '_') return false;
        for (part[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

/// Whether a source declares a top-level `def main`, the entry point a project
/// check requires. Library modules and `*_test.my` files generally do not.
pub fn declaresMain(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimStart(u8, raw, " \t");
        if (!std.mem.startsWith(u8, line, "def")) continue;
        const after_def = line["def".len..];
        if (after_def.len == 0 or (after_def[0] != ' ' and after_def[0] != '\t')) continue;
        const name = std.mem.trimStart(u8, after_def, " \t");
        if (!std.mem.startsWith(u8, name, "main")) continue;
        const after_name = name["main".len..];
        if (after_name.len == 0 or after_name[0] == '(' or after_name[0] == ' ' or after_name[0] == '\t') return true;
    }
    return false;
}

/// Read and validate one discovered `mylang.json`, resolving and reading its
/// required policy bytes when present. On failure `failure` names the offending
/// file and, for JSON shape errors, its location.
pub fn load(allocator: std.mem.Allocator, io: std.Io, config_path: []const u8, failure: *Failure) Error!Config {
    failure.* = .{ .path = config_path };
    const bytes = readConfig(allocator, io, config_path) catch |err| {
        switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ConfigTooLarge => failure.detail = "mylang.json exceeds the 1 MiB configuration budget",
            error.MissingConfig => failure.detail = "configured mylang.json is missing",
            else => failure.detail = "cannot read mylang.json",
        }
        return err;
    };
    errdefer allocator.free(bytes);

    const document = try parseDocument(allocator, bytes, failure);
    errdefer if (document.import_policy) |value| allocator.free(value);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});

    var policy: ?PolicyFile = null;
    errdefer if (policy) |value| {
        allocator.free(value.path);
        allocator.free(value.bytes);
    };

    if (document.import_policy) |raw| {
        const absolute = std.fs.path.isAbsolute(raw);
        const path = if (absolute) try allocator.dupe(u8, raw) else blk: {
            const directory = std.fs.path.dirname(config_path) orelse ".";
            break :blk try std.fs.path.resolve(allocator, &.{ directory, raw });
        };
        errdefer allocator.free(path);
        const policy_bytes = try readPolicy(allocator, io, path, failure);
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(policy_bytes, &hash, .{});
        policy = .{ .path = path, .bytes = policy_bytes, .digest = hash, .absolute = absolute };
    }

    return .{
        .allocator = allocator,
        .path = try allocator.dupe(u8, config_path),
        .bytes = bytes,
        .digest = digest,
        .document = document,
        .policy = policy,
    };
}

fn absoluteEntry(allocator: std.mem.Allocator, io: std.Io, entry_path: []const u8) Error![]const u8 {
    if (std.fs.path.isAbsolute(entry_path)) return std.fs.path.resolve(allocator, &.{entry_path}) catch return error.OutOfMemory;
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(io, ".", allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ReadFailed,
    };
    defer allocator.free(cwd);
    return std.fs.path.resolve(allocator, &.{ cwd, entry_path }) catch return error.OutOfMemory;
}

fn exists(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

fn readConfig(allocator: std.mem.Allocator, io: std.Io, path: []const u8) Error![]u8 {
    return readBounded(allocator, io, path, max_config_bytes) catch |err| switch (err) {
        error.TooLarge => error.ConfigTooLarge,
        error.NotFound => error.MissingConfig,
        else => |failure| failure,
    };
}

fn readPolicy(allocator: std.mem.Allocator, io: std.Io, path: []const u8, failure: *Failure) Error![]u8 {
    return readBounded(allocator, io, path, max_config_bytes) catch |err| switch (err) {
        error.TooLarge => {
            failure.* = .{ .path = path, .detail = "import policy exceeds the 1 MiB configuration budget" };
            return error.PolicyTooLarge;
        },
        error.NotFound => {
            failure.* = .{ .path = path, .detail = "required import policy file is missing" };
            return error.MissingImportPolicy;
        },
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => {
            failure.* = .{ .path = path, .detail = "cannot read the required import policy file" };
            return error.ReadFailed;
        },
    };
}

const ReadBoundedError = error{ NotFound, TooLarge, OutOfMemory, ReadFailed };

fn readBounded(allocator: std.mem.Allocator, io: std.Io, path: []const u8, limit: usize) ReadBoundedError![]u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(limit + 1)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return error.NotFound,
        error.StreamTooLong => return error.TooLarge,
        else => return error.ReadFailed,
    };
    if (bytes.len > limit) {
        allocator.free(bytes);
        return error.TooLarge;
    }
    return bytes;
}

fn parseDocument(allocator: std.mem.Allocator, bytes: []const u8, failure: *Failure) Error!Document {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var diagnostics: std.json.Scanner.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);

    const first = try readToken(allocator, &scanner, failure);
    if (!isObjectBegin(first)) return fail(failure, &diagnostics, "mylang.json must be a JSON object", error.InvalidJson);

    var version: ?u32 = null;
    var import_policy: ?[]u8 = null;
    errdefer if (import_policy) |value| allocator.free(value);
    var policy_seen = false;
    var budgets: Budgets = .{};
    var budgets_seen = false;
    var lint_seen = false;

    while (true) {
        const key_token = try readToken(allocator, &scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, &diagnostics, "configuration keys must be strings", error.InvalidJson);
        const value = try readToken(allocator, &scanner, failure);
        defer freeToken(allocator, value);
        if (std.mem.eql(u8, key, "version")) {
            if (version != null) return fail(failure, &diagnostics, "duplicate version field", error.DuplicateField);
            const text = numberText(value) orelse return fail(failure, &diagnostics, "version must be the integer 1 or 2", error.InvalidVersion);
            const parsed = std.fmt.parseUnsigned(u32, text, 10) catch return fail(failure, &diagnostics, "version must be the integer 1 or 2", error.InvalidVersion);
            if (parsed != 1 and parsed != 2) return fail(failure, &diagnostics, "unsupported mylang.json version; expected 1 or 2", error.UnsupportedVersion);
            version = parsed;
        } else if (std.mem.eql(u8, key, "import_policy")) {
            if (policy_seen) return fail(failure, &diagnostics, "duplicate import_policy field", error.DuplicateField);
            policy_seen = true;
            const text = stringText(value) orelse return fail(failure, &diagnostics, "import_policy must be a JSON string", error.InvalidImportPolicy);
            if (text.len == 0) return fail(failure, &diagnostics, "import_policy must not be empty", error.InvalidImportPolicy);
            if (import_policy) |existing| allocator.free(existing);
            import_policy = try allocator.dupe(u8, text);
        } else if (std.mem.eql(u8, key, "budgets")) {
            if (budgets_seen) return fail(failure, &diagnostics, "duplicate budgets field", error.DuplicateField);
            budgets_seen = true;
            if (!isObjectBegin(value)) return fail(failure, &diagnostics, "budgets must be a JSON object", error.InvalidBudget);
            budgets = try parseBudgets(allocator, &scanner, failure);
        } else if (std.mem.eql(u8, key, "lint")) {
            if (lint_seen) return fail(failure, &diagnostics, "duplicate lint field", error.DuplicateField);
            if (!isObjectBegin(value)) return fail(failure, &diagnostics, "lint must be a JSON object", error.InvalidLint);
            lint_seen = true;
            try skipValue(allocator, &scanner, failure, &diagnostics);
        } else {
            return fail(failure, &diagnostics, "unknown field in mylang.json", error.UnknownField);
        }
    }

    const trailing = try readToken(allocator, &scanner, failure);
    if (!isEndOfDocument(trailing)) return fail(failure, &diagnostics, "trailing content after the configuration object", error.InvalidJson);
    if (version == null) return fail(failure, &diagnostics, "mylang.json must carry version: 1", error.MissingVersion);
    if (lint_seen and version.? != 2) return fail(failure, &diagnostics, "lint requires mylang.json version 2", error.InvalidLint);
    return .{ .version = version.?, .import_policy = import_policy, .budgets = budgets, .lint = lint_seen };
}

/// Read the body of a `budgets` object after its opening brace. Every key is
/// optional, unique and a positive integer; unknown keys stay rejected.
fn parseBudgets(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!Budgets {
    var budgets: Budgets = .{};
    var seen: u8 = 0;
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, scanner.diagnostics.?, "budget keys must be strings", error.InvalidBudget);
        const value = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, value);
        var matched = false;
        inline for (.{
            .{ "max_modules", "max_modules" },
            .{ "max_imports", "max_imports" },
            .{ "max_file_bytes", "max_file_bytes" },
            .{ "max_total_bytes", "max_total_bytes" },
        }, 0..) |entry, index| {
            if (std.mem.eql(u8, key, entry[0])) {
                matched = true;
                const bit: u8 = 1 << index;
                if (seen & bit != 0) return fail(failure, scanner.diagnostics.?, "duplicate budget field", error.DuplicateField);
                seen |= bit;
                const text = numberText(value) orelse return fail(failure, scanner.diagnostics.?, invalid_budget_detail, error.InvalidBudget);
                const parsed = std.fmt.parseUnsigned(usize, text, 10) catch return fail(failure, scanner.diagnostics.?, invalid_budget_detail, error.InvalidBudget);
                if (parsed == 0) return fail(failure, scanner.diagnostics.?, invalid_budget_detail, error.InvalidBudget);
                @field(budgets, entry[1]) = parsed;
            }
        }
        if (!matched) return fail(failure, scanner.diagnostics.?, "unknown field in budgets", error.UnknownField);
    }
    return budgets;
}

/// Consume the rest of a JSON value whose opening object or array token was
/// already read, including nested containers and scalar leaves. The `lint`
/// object's contents belong to the lint driver, which parses them itself.
// twin-drift-ok: this root-module file cannot import the `mylang` module's
// lint_config.zig, so the strict-JSON skip is deliberately duplicated there.
fn skipValue(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure, diagnostics: *const std.json.Scanner.Diagnostics) Error!void {
    var depth: usize = 1;
    while (depth != 0) {
        const token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, token);
        switch (token) {
            .object_begin, .array_begin => depth += 1,
            .object_end, .array_end => depth -= 1,
            .end_of_document => return fail(failure, diagnostics, "unterminated lint object in mylang.json", error.InvalidJson),
            else => {},
        }
    }
}

fn freeToken(allocator: std.mem.Allocator, token: std.json.Scanner.Token) void {
    switch (token) {
        .allocated_string, .allocated_number => |value| allocator.free(value),
        else => {},
    }
}

fn readToken(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!std.json.Scanner.Token {
    return scanner.nextAlloc(allocator, .alloc_if_needed) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => fail(failure, scanner.diagnostics.?, "malformed JSON", error.InvalidJson),
    };
}

fn fail(failure: *Failure, diagnostics: *const std.json.Scanner.Diagnostics, detail: []const u8, err: Error) Error {
    failure.detail = detail;
    failure.location = .{ .line = diagnostics.getLine(), .column = diagnostics.getColumn() };
    return err;
}

fn isObjectBegin(token: std.json.Scanner.Token) bool {
    return switch (token) {
        .object_begin => true,
        else => false,
    };
}
fn isObjectEnd(token: std.json.Scanner.Token) bool {
    return switch (token) {
        .object_end => true,
        else => false,
    };
}
fn isEndOfDocument(token: std.json.Scanner.Token) bool {
    return switch (token) {
        .end_of_document => true,
        else => false,
    };
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
