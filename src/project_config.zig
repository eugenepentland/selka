//! Minimal `selka.json` project configuration and its required import policy.
//!
//! Discovery is anchored to the entry source file, never to the shell working
//! directory: the first `selka.json` found from the entry file's directory up
//! toward the filesystem root wins. A configured `import_policy` path is
//! resolved against the directory that holds the winning configuration.
//!
//! This module owns only the strict configuration shape and the policy file's
//! exact bytes. Policy parsing and evaluation live in `import_policy.zig` so
//! the CLI can keep one authoritative evaluator.
const std = @import("std");
const product = @import("product.zig");
const budget = @import("memory_budget");
const release_config = @import("release_config.zig");
const project = @import("project.zig");
const device_layout = @import("device_layout.zig");

/// Configuration filename frozen by the A1 contract.
pub const config_name = product.project_file;
/// Exact configuration byte ceiling; a larger file is a configuration failure.
pub const max_config_bytes = 1024 * 1024;

/// Failures returned while discovering or loading a project configuration.
pub const Error = error{
    ConfigTooLarge,
    DuplicateField,
    InvalidBudget,
    InvalidDevices,
    InvalidImportPolicy,
    InvalidInterfaceFiles,
    InvalidJson,
    InvalidLimits,
    InvalidLinks,
    InvalidLint,
    InvalidRelease,
    InvalidStores,
    InvalidTarget,
    InvalidValueSemantics,
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
    /// Holds `path` when it names a file `load` resolved itself (an import policy beside the
    /// configuration), whose own allocation is released before `load` returns.
    path_storage: [std.fs.max_path_bytes]u8 = undefined,
    /// Holds `detail` when it was written for this failure (a device's refusal, which names the region or the stage).
    detail_storage: [384]u8 = undefined,

    /// Point `path` at a copy of `name` this failure holds, so it outlives the caller's buffer.
    fn keepPath(self: *Failure, name: []const u8) void {
        const length = @min(name.len, self.path_storage.len);
        @memcpy(self.path_storage[0..length], name[0..length]);
        self.path = self.path_storage[0..length];
    }
};

/// One rejection message reused by every malformed numeric budget field.
const invalid_budget_detail = "budget values must be positive integers";

/// Optional `budgets` object in `selka.json`. Each absent field keeps the
/// matching `project.Options` default; present values must be positive integers.
pub const Budgets = struct {
    max_modules: ?usize = null,
    max_imports: ?usize = null,
    max_file_bytes: ?usize = null,
    max_total_bytes: ?usize = null,
};

/// Execution defaults one command reads from `selka.json`'s `limits` object.
/// A field the file leaves out stays null and the command's own default applies;
/// a flag on the command line, then `SELKA_MEMORY_LIMIT` for the memory
/// ceiling, always outranks it.
pub const CommandLimits = struct {
    /// `--max-steps`: the instruction ceiling.
    max_steps: ?u64 = null,
    /// `--max-frames`: the call-depth ceiling.
    max_frames: ?u64 = null,
    /// `--max-memory`: the guest byte ceiling; zero removes it.
    max_memory: ?u64 = null,
};

/// The optional `limits` object: defaults for `selka run` and `selka test`.
pub const Limits = struct {
    run: CommandLimits = .{},
    tests: CommandLimits = .{},
};

/// The places the optional `stores` object can set. Each is the setting of one
/// environment variable the compiler already reads, and is obeyed only when that
/// variable is unset (`store_settings.zig`, D-FR8-1).
pub const StorePlace = enum {
    cache_home,
    objects,
    compiler,
    stages,
    tests,
    temporary,

    /// The environment variable this place stands for.
    pub fn variable(self: StorePlace) []const u8 {
        return switch (self) {
            .cache_home => "XDG_CACHE_HOME",
            .objects => "SELKA_CORE_RUNTIME_CACHE",
            .compiler => "SELKA_COMPILER_SHARED_CACHE",
            .stages => "SELKA_STAGE_SHARED_CACHE",
            .tests => "SELKA_TEST_SHARED_CACHE",
            .temporary => "TMPDIR",
        };
    }

    /// Whether `false` (the store is off, as an empty variable says) is a value of this place.
    pub fn canBeOff(self: StorePlace) bool {
        return self != .cache_home and self != .temporary;
    }

    /// Whether builds read back what this place holds, so the file must name it outside the project.
    pub fn holdsRecords(self: StorePlace) bool {
        return self != .temporary;
    }
};

/// The number of places a `stores` object can set.
pub const store_place_count = std.enums.values(StorePlace).len;

/// One place's value as `selka.json` spells it: absent, off (`false`), or a path.
pub const StoreValue = union(enum) { unset, off, path: []const u8 };

/// The `stores` object of a configuration: each place's value, and where in the file it was.
pub const Stores = struct {
    values: [store_place_count]StoreValue = @splat(.unset),
    locations: [store_place_count]Location = @splat(.{}),

    /// Release the paths this object owns.
    pub fn deinit(self: *Stores, allocator: std.mem.Allocator) void {
        for (self.values) |value| switch (value) {
            .path => |text| allocator.free(text),
            else => {},
        };
        self.* = .{};
    }
};

/// Strict minimal configuration shape. Unknown fields, duplicate keys and
/// unsupported versions are rejected before any policy is loaded.
pub const Document = struct {
    version: u32,
    import_policy: ?[]const u8 = null,
    /// Per-project source-loading limits; all fields absent uses the defaults.
    budgets: Budgets = .{},
    /// Whether a `lint` object was present; its contents are parsed by the
    /// `selka` module's lint driver, which owns those types.
    lint: bool = false,
    /// `interface_files: true`: every project module's generated `.api` file
    /// must be current, or checking the project fails (API-FILE-3).
    interface_files: bool = false,
    /// Value semantics is the default; explicit false selects legacy sharing
    /// for the migration release (VALUE-SEMANTICS-1).
    value_semantics: bool = true,
    /// Project defaults for the `run` and `test` execution budgets.
    limits: Limits = .{},
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
    /// Absolute path of the winning `selka.json`.
    path: []const u8,
    /// Exact configuration bytes.
    bytes: []const u8,
    /// SHA-256 of `keyBytes`: the bytes without the `stores` member.
    digest: [32]u8,
    document: Document,
    /// Resolved policy file, when `import_policy` is configured.
    policy: ?PolicyFile = null,
    /// Owned release settings, present only for an explicit release object.
    release: ?release_config.Parsed = null,

    pub fn deinit(self: *Config) void {
        if (self.release) |parsed| parsed.deinit();
        self.allocator.free(self.bytes);
        self.allocator.free(self.path);
        if (self.document.import_policy) |value| self.allocator.free(value);
        if (self.policy) |value| {
            self.allocator.free(value.path);
            self.allocator.free(value.bytes);
        }
        self.* = undefined;
    }

    /// Borrow release settings until this configuration is deinitialized.
    pub fn releaseOptions(self: *const Config) release_config.Options {
        return if (self.release) |parsed| parsed.value.options orelse .{} else .{};
    }

    /// True when this configuration requires import-direction policy checking.
    pub fn hasPolicy(self: *const Config) bool {
        return self.policy != null;
    }

    /// The configuration's bytes as every cache key reads them: the exact bytes
    /// without the `stores` member, which says where stores live and never what
    /// they hold. A file without one is returned as it is, so its keys are the
    /// keys of the compilers before `stores` existed; the caller owns any copy.
    pub fn keyBytes(self: *const Config, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        return withoutStores(allocator, self.bytes);
    }

    /// Combine the exact configuration and policy bytes into the cache identity
    /// used for successful-verdict reuse. Returns false when neither a policy
    /// nor a `lint` or `release` object is configured, because configuration alone cannot
    /// change acceptance.
    pub fn cacheIdentity(self: *const Config, out: *[64]u8) bool {
        if (self.policy == null and !self.document.lint and self.release == null) return false;
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("project-config-cache-identity-v2");
        hash.update(&self.digest);
        if (self.policy) |policy| hash.update(&policy.digest);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        out.* = std.fmt.bytesToHex(digest, .lower);
        return true;
    }

    /// Content digests for verification receipts: the file's exact bytes, as a
    /// reader of the receipt would hash them. Every field uses `allocator`.
    pub fn receipt(self: *const Config, allocator: std.mem.Allocator) std.mem.Allocator.Error!Receipt {
        var exact: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(self.bytes, &exact, .{});
        return .{
            .config_sha256 = try hexDigest(allocator, exact),
            .policy_sha256 = if (self.policy) |policy| try hexDigest(allocator, policy.digest) else null,
        };
    }
};

/// Digest strings that participate in verification receipts.
pub const Receipt = struct { config_sha256: []const u8, policy_sha256: ?[]const u8 = null };

fn hexDigest(allocator: std.mem.Allocator, digest: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

/// Find the nearest `selka.json` starting at the entry file's directory.
/// Returns an owned absolute path, or null when no configuration exists.
pub fn discover(allocator: std.mem.Allocator, io: std.Io, entry_path: []const u8) Error!?[]const u8 {
    const absolute = try absoluteEntry(allocator, io, entry_path);
    defer allocator.free(absolute);
    return discoverAbove(allocator, io, std.fs.path.dirname(absolute) orelse return null);
}

/// Find the nearest `selka.json` starting at `directory` itself, as `discover`
/// does for an entry inside it: the project a directory of entries belongs to.
pub fn discoverDirectory(allocator: std.mem.Allocator, io: std.Io, directory: []const u8) Error!?[]const u8 {
    const absolute = try absoluteEntry(allocator, io, directory);
    defer allocator.free(absolute);
    return discoverAbove(allocator, io, absolute);
}

/// The first `selka.json` in `start` or an ancestor of it; `start` is absolute.
fn discoverAbove(allocator: std.mem.Allocator, io: std.Io, start: []const u8) Error!?[]const u8 {
    var directory = start;
    while (true) {
        const candidate = try std.fs.path.join(allocator, &.{ directory, config_name });
        if (exists(io, candidate)) return candidate;
        allocator.free(candidate);
        const parent = std.fs.path.dirname(directory) orelse return null;
        if (std.mem.eql(u8, parent, directory)) return null;
        directory = parent;
    }
}

/// A standalone `*_test.selka` entry's resolved project location: `root` is the
/// absolute enclosing project directory, `relative` is the entry path beneath
/// it (`tests/parser_test.selka`), and `name` is the dotted module name
/// (`tests.parser_test`). Every slice is owned by the caller's allocator.
pub const TestEntry = struct { root: []const u8, relative: []const u8, name: []const u8 };

/// Resolve any configured `.selka` entry, or an unconfigured `*_test.selka` entry,
/// against its enclosing project: the
/// nearest ancestor holding `selka.json`, else the nearest ancestor holding a
/// non-test `.selka` source, else the entry's own directory. Returns null when the
/// entry is unconfigured and not a `*_test.selka`, or cannot spell a dotted
/// module name. The caller owns the slices of a non-null result. The projection
/// the test runner materializes has a stub `main` appended, so this decision
/// rests only on the `*_test.selka` convention, never on the file's own contents.
pub fn testEntryLocation(allocator: std.mem.Allocator, io: std.Io, entry_path: []const u8) Error!?TestEntry {
    const absolute = try absoluteEntry(allocator, io, entry_path);
    defer allocator.free(absolute);
    if (!product.isSource(absolute)) return null;
    const entry_directory = std.fs.path.dirname(absolute) orelse return null;
    const configured = try discover(allocator, io, absolute);
    defer if (configured) |path| allocator.free(path);
    const root = if (configured) |path|
        try allocator.dupe(u8, std.fs.path.dirname(path) orelse entry_directory)
    else if (product.isTestSource(std.fs.path.basename(absolute)))
        (try nearestProjectRoot(allocator, io, entry_directory)) orelse try allocator.dupe(u8, entry_directory)
    else
        return null;
    if (!std.mem.startsWith(u8, absolute, root) or absolute.len <= root.len + 1 or absolute[root.len] != std.fs.path.sep) {
        allocator.free(root);
        return null;
    }
    const relative = allocator.dupe(u8, absolute[root.len + 1 ..]) catch |err| {
        allocator.free(root);
        return err;
    };
    const named = entryModuleName(allocator, product.sourceStem(relative)) catch |err| {
        allocator.free(relative);
        allocator.free(root);
        return err;
    };
    const name = named orelse {
        allocator.free(relative);
        allocator.free(root);
        return null;
    };
    return .{ .root = root, .relative = relative, .name = name };
}

/// The dotted module name of an entry's path beneath its project root, without `.selka` (`tests/parser_test` is `tests.parser_test`),
/// or null when a segment cannot spell one. A hidden segment (`.tmp`) is spelled `__hidden_tmp`, which `project.modulePath` reads
/// back as `.tmp`, so a file under a hidden folder of its project is an entry of that project (`.tmp/scratch.selka` is
/// `__hidden_tmp.scratch`) whose imports are read from the project's root. The caller owns the slice.
fn entryModuleName(allocator: std.mem.Allocator, stem: []const u8) std.mem.Allocator.Error!?[]u8 {
    var hidden_count: usize = 0;
    var parts = std.mem.splitScalar(u8, stem, std.fs.path.sep);
    while (parts.next()) |part| {
        const hidden = part.len > 1 and part[0] == '.';
        const spelled = if (hidden) part[1..] else part;
        const reserved = std.mem.startsWith(u8, spelled, project.hidden_segment_prefix) and spelled.len > project.hidden_segment_prefix.len;
        if (reserved or !validModuleName(spelled)) return null;
        if (hidden) hidden_count += 1;
    }
    const prefix = project.hidden_segment_prefix;
    const name = try allocator.alloc(u8, stem.len + hidden_count * (prefix.len - 1));
    var at: usize = 0;
    parts.reset();
    while (parts.next()) |part| {
        if (at != 0) {
            name[at] = '.';
            at += 1;
        }
        const hidden = part.len > 1 and part[0] == '.';
        if (hidden) {
            @memcpy(name[at..][0..prefix.len], prefix);
            at += prefix.len;
        }
        const spelled = if (hidden) part[1..] else part;
        @memcpy(name[at..][0..spelled.len], spelled);
        at += spelled.len;
    }
    return name;
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

/// Whether `directory` directly holds a `.selka` source that is not a test entry,
/// the evidence that it is a project root rather than a test-only subdirectory.
fn hasProjectSource(io: std.Io, directory: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true, .follow_symlinks = false }) catch return false;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (iterator.next(io) catch return false) |item| {
        if (item.kind != .file) continue;
        if (!product.isSource(item.name)) continue;
        if (product.isTestSource(item.name)) continue;
        return true;
    }
    return false;
}

/// Whether a directory path spells a valid dotted module name when separators
/// are read as dots.
pub fn validModuleName(stem: []const u8) bool {
    if (stem.len == 0) return false;
    var parts = std.mem.splitScalar(u8, stem, std.fs.path.sep);
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        if (!std.ascii.isAlphabetic(part[0]) and part[0] != '_') return false;
        for (part[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

/// Whether a source declares a top-level `func main`, the entry point a project
/// check requires. Library modules and `*_test.selka` files generally do not.
pub fn declaresMain(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trimStart(u8, raw, " \t");
        if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line[7..], " \t");
        const length: usize = if (std.mem.startsWith(u8, line, "func")) 4 else if (std.mem.startsWith(u8, line, "def")) 3 else continue;
        const after_def = line[length..];
        if (after_def.len == 0 or (after_def[0] != ' ' and after_def[0] != '\t')) continue;
        const name = std.mem.trimStart(u8, after_def, " \t");
        if (!std.mem.startsWith(u8, name, "main")) continue;
        const after_name = name["main".len..];
        if (after_name.len == 0 or after_name[0] == '(' or after_name[0] == ' ' or after_name[0] == '\t') return true;
    }
    return false;
}

/// Read and validate one discovered `selka.json`, resolving and reading its
/// required policy bytes when present. On failure `failure` names the offending
/// file and, for JSON shape errors, its location.
pub fn load(allocator: std.mem.Allocator, io: std.Io, config_path: []const u8, failure: *Failure) Error!Config {
    failure.* = .{ .path = config_path };
    const bytes = readConfig(allocator, io, config_path) catch |err| {
        switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ConfigTooLarge => failure.detail = "selka.json exceeds the 1 MiB configuration budget",
            error.MissingConfig => failure.detail = "configured selka.json is missing",
            else => failure.detail = "cannot read selka.json",
        }
        return err;
    };
    errdefer allocator.free(bytes);

    var release: ?release_config.Parsed = null;
    errdefer if (release) |parsed| parsed.deinit();
    const document = try parseDocument(allocator, bytes, failure, &release);
    errdefer if (document.import_policy) |value| allocator.free(value);

    var digest: [32]u8 = undefined;
    {
        const keyed = try withoutStores(allocator, bytes);
        defer if (keyed.ptr != bytes.ptr) allocator.free(keyed);
        std.crypto.hash.sha2.Sha256.hash(keyed, &digest, .{});
    }

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
        .release = release,
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

/// Read the import policy at `path`. A failure keeps its own copy of `path`: the caller frees
/// `path` while the error unwinds, before the failure is reported.
fn readPolicy(allocator: std.mem.Allocator, io: std.Io, path: []const u8, failure: *Failure) Error![]u8 {
    return readBounded(allocator, io, path, max_config_bytes) catch |err| switch (err) {
        error.TooLarge => {
            failure.* = .{ .detail = "import policy exceeds the 1 MiB configuration budget" };
            failure.keepPath(path);
            return error.PolicyTooLarge;
        },
        error.NotFound => {
            failure.* = .{ .detail = "required import policy file is missing" };
            failure.keepPath(path);
            return error.MissingImportPolicy;
        },
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => {
            failure.* = .{ .detail = "cannot read the required import policy file" };
            failure.keepPath(path);
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

fn parseDocument(allocator: std.mem.Allocator, bytes: []const u8, failure: *Failure, release: *?release_config.Parsed) Error!Document {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var diagnostics: std.json.Scanner.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);

    const first = try readToken(allocator, &scanner, failure);
    if (!isObjectBegin(first)) return fail(failure, &diagnostics, "selka.json must be a JSON object", error.InvalidJson);

    var version: ?u32 = null;
    var import_policy: ?[]u8 = null;
    errdefer if (import_policy) |value| allocator.free(value);
    var policy_seen = false;
    var budgets: Budgets = .{};
    var budgets_seen = false;
    var lint_seen = false;
    var interface_files: ?bool = null;
    var value_semantics: ?bool = null;
    var limits: Limits = .{};
    var limits_seen = false;
    var stores_seen = false;
    var lists_seen: ListsSeen = .{};
    var device_keys: DeviceKeys = .{};
    defer device_keys.deinit(allocator);

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
            if (parsed != 1 and parsed != 2) return fail(failure, &diagnostics, "unsupported selka.json version; expected 1 or 2", error.UnsupportedVersion);
            version = parsed;
        } else if (std.mem.eql(u8, key, "import_policy")) {
            if (policy_seen) return fail(failure, &diagnostics, "duplicate import_policy field", error.DuplicateField);
            policy_seen = true;
            const text = stringText(value) orelse return fail(failure, &diagnostics, "import_policy must be a JSON string", error.InvalidImportPolicy);
            if (text.len == 0) return fail(failure, &diagnostics, "import_policy must not be empty", error.InvalidImportPolicy);
            if (import_policy) |existing| allocator.free(existing);
            import_policy = try allocator.dupe(u8, text);
        } else if (std.mem.eql(u8, key, "budgets")) {
            budgets = try budgetsField(allocator, &scanner, value, &budgets_seen, failure);
        } else if (std.mem.eql(u8, key, "limits")) {
            if (limits_seen) return fail(failure, &diagnostics, duplicate_limit_detail, error.DuplicateField);
            limits_seen = true;
            if (!isObjectBegin(value)) return fail(failure, &diagnostics, "limits must be a JSON object", error.InvalidLimits);
            limits = try parseLimits(allocator, &scanner, failure);
        } else if (std.mem.eql(u8, key, "stores")) {
            try storesField(allocator, &scanner, value, &stores_seen, failure);
        } else if (lists_seen.slot(key)) |seen| {
            try stringList(allocator, &scanner, value, .{ .seen = seen, .failure = failure, .key = key });
        } else if (try device_keys.read(allocator, &scanner, .{ .key = key, .value = value }, failure)) {} else if (std.mem.eql(u8, key, "lint")) {
            if (lint_seen) return fail(failure, &diagnostics, "duplicate lint field", error.DuplicateField);
            if (!isObjectBegin(value)) return fail(failure, &diagnostics, "lint must be a JSON object", error.InvalidLint);
            lint_seen = true;
            try skipValue(allocator, &scanner, failure, &diagnostics);
        } else if (std.mem.eql(u8, key, "release")) {
            release.* = try releaseField(allocator, bytes, value, release.* != null, failure, &diagnostics);
            try skipValue(allocator, &scanner, failure, &diagnostics);
        } else if (std.mem.eql(u8, key, "interface_files")) {
            interface_files = try booleanField("interface_files", interface_files, value, .{ .failure = failure, .diagnostics = &diagnostics, .invalid = error.InvalidInterfaceFiles });
        } else if (std.mem.eql(u8, key, "value_semantics")) {
            value_semantics = try booleanField("value_semantics", value_semantics, value, .{ .failure = failure, .diagnostics = &diagnostics, .invalid = error.InvalidValueSemantics });
        } else {
            return fail(failure, &diagnostics, "unknown field in selka.json", error.UnknownField);
        }
    }

    const trailing = try readToken(allocator, &scanner, failure);
    if (!isEndOfDocument(trailing)) return fail(failure, &diagnostics, "trailing content after the configuration object", error.InvalidJson);
    try validateVersion(version, lint_seen, release.* != null, failure, &diagnostics);
    try device_keys.finish(failure, &diagnostics);
    return .{ .version = version.?, .import_policy = import_policy, .budgets = budgets, .lint = lint_seen, .interface_files = interface_files orelse false, .value_semantics = value_semantics orelse true, .limits = limits };
}

/// Which of the three string-list fields (`links`, `allow_links`, `include`) a configuration has named.
const ListsSeen = struct {
    links: bool = false,
    allow_links: bool = false,
    include: bool = false,

    /// The flag of the list field `key` names, or null for any other key.
    fn slot(self: *ListsSeen, key: []const u8) ?*bool {
        if (std.mem.eql(u8, key, "links")) return &self.links;
        if (std.mem.eql(u8, key, "allow_links")) return &self.allow_links;
        if (std.mem.eql(u8, key, "include")) return &self.include;
        return null;
    }
};

const invalid_links_detail = "links and allow_links must be JSON arrays of non-empty strings";
const invalid_include_detail = "include must be a JSON array of non-empty folder paths";

/// Whether the list field `key` being read was seen before, and where its rejection is reported.
const ListField = struct { seen: *bool, failure: *Failure, key: []const u8 };

/// Read a `links`, `allow_links` or `include` array after its opening token `value`: every element a non-empty string,
/// and the field named once.
fn stringList(allocator: std.mem.Allocator, scanner: *std.json.Scanner, value: std.json.Scanner.Token, field: ListField) Error!void {
    const diagnostics = scanner.diagnostics.?;
    const failure = field.failure;
    const include = std.mem.eql(u8, field.key, "include");
    const invalid = if (include) invalid_include_detail else invalid_links_detail;
    if (field.seen.*) return fail(failure, diagnostics, if (include) "duplicate include field" else "duplicate links or allow_links field", error.DuplicateField);
    field.seen.* = true;
    switch (value) {
        .array_begin => {},
        else => return fail(failure, diagnostics, invalid, error.InvalidLinks),
    }
    while (true) {
        const element = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, element);
        switch (element) {
            .array_end => return,
            else => {},
        }
        const text = stringText(element) orelse return fail(failure, diagnostics, invalid, error.InvalidLinks);
        if (text.len == 0) return fail(failure, diagnostics, invalid, error.InvalidLinks);
    }
}

/// A project's C sources (`links`, each relative to the configuration's directory unless absolute), the packages whose
/// own `links` it allows (`allow_links`), and the folders added to the include path of every C source it links
/// (`include`, resolved as `links` is), as the configuration's bytes spell them.
pub const ForeignLinks = struct {
    links: []const []const u8 = &.{},
    allow_links: []const []const u8 = &.{},
    include: []const []const u8 = &.{},
};

/// The `links`, `allow_links` and `include` of a configuration `load` accepted, read from its bytes into `allocator`.
pub fn foreignLinks(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}!ForeignLinks {
    return std.json.parseFromSliceLeaky(ForeignLinks, allocator, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        // `load` validated the lists, so nothing else can fail here.
        else => .{},
    };
}

/// One entry of `devices`: what a build for that device needs. Every path is relative to the configuration's folder
/// and stays inside it (`staysInside`); `image` is `elf`, `bin` or `uf2`, and `uf2_family` a hex text (`uf2Family`). The keys that
/// describe the device instead of scripting it (`memory`, `place`, `stack`, `boot`, `hooks`) are one `startup`, read from the same
/// flat object (MCU-NOC4A).
pub const Device = struct {
    target: ?[]const u8 = null,
    linker_script: ?[]const u8 = null,
    links: []const []const u8 = &.{},
    include: []const []const u8 = &.{},
    image: ?[]const u8 = null,
    uf2_family: ?[]const u8 = null,
    startup: device_layout.Startup = .{},

    /// Read a device from the scanner: its object, then the flat keys it holds.
    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Device {
        const value = try std.json.Value.jsonParse(allocator, source, options);
        return jsonParseFromValue(allocator, value, options);
    }

    /// Read a device from a parsed object: each plain key by its own type, and the startup keys from the same object.
    pub fn jsonParseFromValue(allocator: std.mem.Allocator, value: std.json.Value, options: std.json.ParseOptions) !Device {
        if (value != .object) return error.UnexpectedToken;
        var device: Device = .{};
        inline for (comptime std.meta.fieldNames(Device)) |name| {
            if (comptime std.mem.eql(u8, name, "startup")) continue;
            if (value.object.get(name)) |item| @field(device, name) = try std.json.parseFromValueLeaky(@FieldType(Device, name), allocator, item, options);
        }
        device.startup = try std.json.parseFromValueLeaky(device_layout.Startup, allocator, value, .{ .ignore_unknown_fields = true, .allocate = options.allocate });
        return device;
    }
};

/// The device keys of a configuration: the target a build uses without `--target`, the device it chooses (a name of
/// `devices`, or `PACKAGE/NAME`), and the devices the file describes, by name.
pub const DeviceSettings = struct {
    target: ?[]const u8 = null,
    device: ?[]const u8 = null,
    devices: std.json.ArrayHashMap(Device) = .{},
};

/// The `target`, `device` and `devices` of a configuration `load` accepted, read from its bytes into `allocator`.
pub fn deviceSettings(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}!DeviceSettings {
    return std.json.parseFromSliceLeaky(DeviceSettings, allocator, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        // `load` validated the three keys, so nothing else can fail here.
        else => .{},
    };
}

/// Whether `path` names a place inside the folder it is relative to: not empty, not absolute, and no `..` climbs above
/// that folder (`a/../b` stays, `../b` and `a/../../b` leave).
pub fn staysInside(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) return false;
    var depth: usize = 0;
    var parts = std.mem.tokenizeScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "..")) {
            if (depth == 0) return false;
            depth -= 1;
        } else if (!std.mem.eql(u8, part, ".")) depth += 1;
    }
    return true;
}

/// Whether the real path `path` is `folder` or under it (both absolute and free of symbolic links): a device path whose
/// real location is elsewhere left the folder through a symbolic link, which `staysInside` cannot see in its spelling.
pub fn realPathInside(folder: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, folder)) return false;
    return path.len == folder.len or path[folder.len] == '/' or std.mem.endsWith(u8, folder, "/");
}

/// The UF2 family id a device's `uf2_family` spells: `0x` and one to eight hex digits (`"0xe48bff56"`), or null.
pub fn uf2Family(text: []const u8) ?u32 {
    if (text.len < 3 or text.len > 10 or !std.mem.startsWith(u8, text, "0x")) return null;
    return std.fmt.parseUnsigned(u32, text[2..], 16) catch null;
}

/// Whether `name` can name a device: letters, digits, `-`, `_` and `.`, not starting with `.`.
fn validDeviceName(name: []const u8) bool {
    if (name.len == 0 or name[0] == '.') return false;
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        if (std.mem.indexOfScalar(u8, "-_.", byte) == null) return false;
    }
    return true;
}

/// Whether `choice` can be a `device` value: a device name, or a package name, `/` and a device name.
fn validDeviceChoice(choice: []const u8) bool {
    const slash = std.mem.indexOfScalar(u8, choice, '/') orelse return validDeviceName(choice);
    return validDeviceName(choice[0..slash]) and validDeviceName(choice[slash + 1 ..]);
}

const device_fields = [_][]const u8{ "target", "linker_script", "links", "include", "image", "uf2_family", "memory", "place", "stack", "boot", "hooks" };
/// The index in `device_fields` of the first key that describes the device (`memory`); the others follow it.
const first_startup_field = 6;
const unknown_device_field = "unknown field in a device; expected target, linker_script, links, include, image, uf2_family, memory, place, stack, boot or hooks";
const startup_shape_detail = "a device's memory is {\"NAME\": [\"ORIGIN\", \"LENGTH\"]}, place {\"vectors\": R, \"code\": R, \"data\": R}, stack \"SIZE\" or [\"SIZE\", \"REGION\"], boot a stage name and hooks {\"HOOK\": \"MODULE.FUNCTION\"}";
const device_path_detail = "a device's paths must be non-empty, relative to this selka.json and stay inside its folder";
const device_image_detail = "a device's image must be \"elf\", \"bin\" or \"uf2\"";
const uf2_family_detail = "a device's uf2_family must be a hex text such as \"0xe48bff56\"";

/// One key of the configuration object and its first token, as `DeviceKeys.read` is given it.
const KeyValue = struct { key: []const u8, value: std.json.Scanner.Token };

/// What `parseDocument` has read of the device keys (`target`, `device`, `devices`): a repeat is refused, and so is a
/// `device` that names no entry of the file's own `devices` (a `PACKAGE/NAME` choice is resolved by the build).
const DeviceKeys = struct {
    target: bool = false,
    device: ?[]u8 = null,
    devices: ?std.StringHashMapUnmanaged(void) = null,

    fn deinit(self: *DeviceKeys, allocator: std.mem.Allocator) void {
        if (self.device) |value| allocator.free(value);
        if (self.devices) |*names| {
            var keys = names.keyIterator();
            while (keys.next()) |name| allocator.free(name.*);
            names.deinit(allocator);
        }
    }

    /// Read `entry` when its key is one of the three; false for any other key.
    fn read(self: *DeviceKeys, allocator: std.mem.Allocator, scanner: *std.json.Scanner, entry: KeyValue, failure: *Failure) Error!bool {
        const diagnostics = scanner.diagnostics.?;
        if (std.mem.eql(u8, entry.key, "target")) {
            if (self.target) return fail(failure, diagnostics, "duplicate target field", error.DuplicateField);
            self.target = true;
            const text = stringText(entry.value) orelse "";
            if (text.len == 0) return fail(failure, diagnostics, "target must be a target name such as \"thumbv6m-none\"", error.InvalidTarget);
        } else if (std.mem.eql(u8, entry.key, "device")) {
            if (self.device != null) return fail(failure, diagnostics, "duplicate device field", error.DuplicateField);
            const text = stringText(entry.value) orelse "";
            if (!validDeviceChoice(text)) return fail(failure, diagnostics, "device must name a device of devices, or PACKAGE/NAME for a package's", error.InvalidDevices);
            self.device = try allocator.dupe(u8, text);
        } else if (std.mem.eql(u8, entry.key, "devices")) {
            try self.readDevices(allocator, scanner, entry.value, failure);
        } else return false;
        return true;
    }

    /// Read the `devices` object after its opening token: each entry a distinct, valid name and a device object.
    fn readDevices(self: *DeviceKeys, allocator: std.mem.Allocator, scanner: *std.json.Scanner, value: std.json.Scanner.Token, failure: *Failure) Error!void {
        const diagnostics = scanner.diagnostics.?;
        if (self.devices != null) return fail(failure, diagnostics, "duplicate devices field", error.DuplicateField);
        if (!isObjectBegin(value)) return fail(failure, diagnostics, "devices must be a JSON object of device entries", error.InvalidDevices);
        self.devices = .empty;
        while (true) {
            const name_token = try readToken(allocator, scanner, failure);
            defer freeToken(allocator, name_token);
            if (isObjectEnd(name_token)) return;
            const name = stringText(name_token) orelse "";
            if (!validDeviceName(name)) return fail(failure, diagnostics, "a device name is letters, digits, '-', '_' and '.', and does not start with '.'", error.InvalidDevices);
            if (self.devices.?.contains(name)) return fail(failure, diagnostics, "two devices of one name in devices", error.DuplicateField);
            try self.devices.?.ensureUnusedCapacity(allocator, 1);
            self.devices.?.putAssumeCapacity(try allocator.dupe(u8, name), {});
            const entry = try readToken(allocator, scanner, failure);
            defer freeToken(allocator, entry);
            if (!isObjectBegin(entry)) return fail(failure, diagnostics, "a device must be a JSON object", error.InvalidDevices);
            try readDevice(allocator, scanner, failure);
        }
    }

    /// Refuse a `device` that names no entry of this file's `devices`.
    fn finish(self: *const DeviceKeys, failure: *Failure, diagnostics: *const std.json.Scanner.Diagnostics) Error!void {
        const choice = self.device orelse return;
        if (std.mem.indexOfScalar(u8, choice, '/') != null) return;
        if (self.devices) |names| if (names.contains(choice)) return;
        return fail(failure, diagnostics, "device names no entry of this selka.json's devices", error.InvalidDevices);
    }
};

/// Read one device object after its opening token: only the fields of `device_fields`, each once, with values of the
/// right kind; an `image` of `uf2` needs a `uf2_family`, and the keys that describe the device are checked together
/// (`device_layout.parse`).
fn readDevice(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!void {
    const diagnostics = scanner.diagnostics.?;
    var seen: [device_fields.len]bool = @splat(false);
    var uf2 = false;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var startup_keys: std.json.ObjectMap = .empty;
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse "";
        const index = for (device_fields, 0..) |field, at| {
            if (std.mem.eql(u8, field, key)) break at;
        } else return fail(failure, diagnostics, unknown_device_field, error.UnknownField);
        if (seen[index]) return fail(failure, diagnostics, "duplicate field in a device", error.DuplicateField);
        seen[index] = true;
        const value = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, value);
        const text: []const u8 = stringText(value) orelse "";
        switch (index) {
            0 => if (text.len == 0) return fail(failure, diagnostics, "a device's target must be a target name such as \"thumbv6m-none\"", error.InvalidTarget),
            1 => if (!staysInside(text)) return fail(failure, diagnostics, device_path_detail, error.InvalidDevices),
            2, 3 => try devicePaths(allocator, scanner, value, failure),
            4 => {
                const image = std.meta.stringToEnum(enum { elf, bin, uf2 }, text) orelse
                    return fail(failure, diagnostics, device_image_detail, error.InvalidDevices);
                uf2 = image == .uf2;
            },
            5 => if (uf2Family(text) == null) return fail(failure, diagnostics, uf2_family_detail, error.InvalidDevices),
            else => {
                const kept = try readJsonValue(arena.allocator(), scanner, value, failure);
                try startup_keys.put(arena.allocator(), device_fields[index], kept);
            },
        }
    }
    if (uf2 and !seen[5]) return fail(failure, diagnostics, "a device whose image is uf2 needs a uf2_family, such as \"0xe48bff56\"", error.InvalidDevices);
    if (try startupProblem(arena.allocator(), startup_keys, seen[1], &failure.detail_storage)) |line|
        return fail(failure, diagnostics, line, error.InvalidDevices);
}

/// The keys of a device that describe it instead of scripting it, in the order a lock records them.
pub const startup_fields = device_fields[first_startup_field..];

/// The `startup_fields` that the device object `device` holds, copied into one object in `arena`.
pub fn startupKeys(arena: std.mem.Allocator, device: std.json.ObjectMap) error{OutOfMemory}!std.json.ObjectMap {
    var keys: std.json.ObjectMap = .empty;
    for (startup_fields) |field| if (device.get(field)) |kept| try keys.put(arena, field, kept);
    return keys;
}

/// The line that refuses the description `keys` (the `startup_fields` a device holds) as `load` refuses it, or null when it
/// holds none or they are sound. `linker_script` says the device names a script too; the line is written into `buffer`.
pub fn startupProblem(arena: std.mem.Allocator, keys: std.json.ObjectMap, linker_script: bool, buffer: []u8) error{OutOfMemory}!?[]const u8 {
    const startup = std.json.parseFromValueLeaky(device_layout.Startup, arena, .{ .object = keys }, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return startup_shape_detail,
    };
    return switch (try device_layout.parse(arena, startup, linker_script, buffer)) {
        .refused => |line| line,
        .absent, .layout => null,
    };
}

/// Read the JSON value whose first token is `first` into `arena`, for a key whose shape the device layout checks.
fn readJsonValue(arena: std.mem.Allocator, scanner: *std.json.Scanner, first: std.json.Scanner.Token, failure: *Failure) Error!std.json.Value {
    switch (first) {
        .object_begin => {
            var object: std.json.ObjectMap = .empty;
            while (true) {
                const key = try readToken(arena, scanner, failure);
                if (isObjectEnd(key)) return .{ .object = object };
                const name = stringText(key) orelse return fail(failure, scanner.diagnostics.?, "malformed JSON", error.InvalidJson);
                try object.put(arena, name, try readJsonValue(arena, scanner, try readToken(arena, scanner, failure), failure));
            }
        },
        .array_begin => {
            var array = std.json.Array.init(arena);
            while (true) {
                const element = try readToken(arena, scanner, failure);
                if (element == .array_end) return .{ .array = array };
                try array.append(try readJsonValue(arena, scanner, element, failure));
            }
        },
        .string, .allocated_string => |text| return .{ .string = try arena.dupe(u8, text) },
        .number, .allocated_number => |text| return .{ .number_string = try arena.dupe(u8, text) },
        .true => return .{ .bool = true },
        .false => return .{ .bool = false },
        .null => return .null,
        else => return fail(failure, scanner.diagnostics.?, "malformed JSON", error.InvalidJson),
    }
}

/// Read a device's `links` or `include` array after its opening token: every element a path that stays inside the folder.
fn devicePaths(allocator: std.mem.Allocator, scanner: *std.json.Scanner, value: std.json.Scanner.Token, failure: *Failure) Error!void {
    const diagnostics = scanner.diagnostics.?;
    if (value != .array_begin) return fail(failure, diagnostics, "a device's links and include must be JSON arrays of paths", error.InvalidDevices);
    while (true) {
        const element = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, element);
        if (element == .array_end) return;
        if (!staysInside(stringText(element) orelse "")) return fail(failure, diagnostics, device_path_detail, error.InvalidDevices);
    }
}

fn validateVersion(version: ?u32, lint_seen: bool, release_seen: bool, failure: *Failure, diagnostics: *std.json.Scanner.Diagnostics) Error!void {
    if (version == null) return fail(failure, diagnostics, "selka.json must carry version: 1", error.MissingVersion);
    if (release_seen and version.? != 2) return fail(failure, diagnostics, "release requires selka.json version 2", error.InvalidRelease);
    if (lint_seen and version.? != 2) return fail(failure, diagnostics, "lint requires selka.json version 2", error.InvalidLint);
}

fn releaseField(allocator: std.mem.Allocator, bytes: []const u8, value: std.json.Scanner.Token, seen: bool, failure: *Failure, diagnostics: *std.json.Scanner.Diagnostics) Error!release_config.Parsed {
    if (seen) return fail(failure, diagnostics, "duplicate release field", error.DuplicateField);
    if (!isObjectBegin(value)) return fail(failure, diagnostics, "release must be a JSON object", error.InvalidRelease);
    return release_config.parseConfig(allocator, bytes) catch |err| return fail(failure, diagnostics, "invalid release settings; expected known keys and project-relative paths", err);
}

/// Read a `budgets` member whose opening token is `value`.
fn budgetsField(allocator: std.mem.Allocator, scanner: *std.json.Scanner, value: std.json.Scanner.Token, seen: *bool, failure: *Failure) Error!Budgets {
    const diagnostics = scanner.diagnostics.?;
    if (seen.*) return fail(failure, diagnostics, "duplicate budgets field", error.DuplicateField);
    seen.* = true;
    if (!isObjectBegin(value)) return fail(failure, diagnostics, "budgets must be a JSON object", error.InvalidBudget);
    const budgets = try parseBudgets(allocator, scanner, failure);
    return budgets;
}

/// Validate a `stores` member whose opening token is `value`; its paths are read again by `storeSettings`.
fn storesField(allocator: std.mem.Allocator, scanner: *std.json.Scanner, value: std.json.Scanner.Token, seen: *bool, failure: *Failure) Error!void {
    const diagnostics = scanner.diagnostics.?;
    if (seen.*) return fail(failure, diagnostics, "duplicate stores field", error.DuplicateField);
    seen.* = true;
    if (!isObjectBegin(value)) return fail(failure, diagnostics, "stores must be a JSON object", error.InvalidStores);
    var stores = try parseStores(allocator, scanner, failure);
    stores.deinit(allocator);
}

const stores_value_detail = "stores values must be a non-empty path; objects, compiler, stages and tests may also be false (off)";

/// Read the body of a `stores` object after its opening brace: each place at most
/// once, a path or (for a store that can be off) `false`. A path that would let the
/// project's own checkout supply a store is refused here (`storePath`).
fn parseStores(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!Stores {
    const diagnostics = scanner.diagnostics.?;
    var stores: Stores = .{};
    errdefer stores.deinit(allocator);
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, diagnostics, "stores keys must be strings", error.InvalidStores);
        const value = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, value);
        const place = std.meta.stringToEnum(StorePlace, key) orelse
            return fail(failure, diagnostics, "unknown field in stores; expected cache_home, objects, compiler, stages, tests or temporary", error.UnknownField);
        const slot = &stores.values[@backingInt(place)];
        if (slot.* != .unset) return fail(failure, diagnostics, "duplicate stores field", error.DuplicateField);
        switch (value) {
            .false => {
                if (!place.canBeOff()) return fail(failure, diagnostics, "stores.cache_home and stores.temporary must be paths; only a store can be false (off)", error.InvalidStores);
                slot.* = .off;
            },
            else => {
                const text = stringText(value) orelse return fail(failure, diagnostics, stores_value_detail, error.InvalidStores);
                if (storePathProblem(place, text)) |detail| return fail(failure, diagnostics, detail, error.InvalidStores);
                slot.* = .{ .path = try allocator.dupe(u8, text) };
            },
        }
        stores.locations[@backingInt(place)] = .{ .line = diagnostics.getLine(), .column = diagnostics.getColumn() };
    }
    return stores;
}

/// Why `text` is not a path `place` may take, or null. A path is absolute or starts
/// with `~/` (the user's home); only `temporary` may also be relative to the
/// directory that holds `selka.json`, because a store inside the checkout could be
/// one the project ships with its records prepared (D-FR8-3).
pub fn storePathProblem(place: StorePlace, text: []const u8) ?[]const u8 {
    if (text.len == 0) return stores_value_detail;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return "stores paths must not contain a NUL byte";
    if (text[0] == '~' and !std.mem.startsWith(u8, text, "~/")) return "only a leading ~/ names the home directory in stores";
    if (std.fs.path.isAbsolute(text) or std.mem.startsWith(u8, text, "~/")) return null;
    if (place.holdsRecords()) return "a store must lie outside the project: spell it as an absolute path or from ~/";
    return null;
}

/// The `stores` object of configuration bytes `load` accepted, with each path owned
/// by `allocator`, or null when the file has none.
pub fn storeSettings(allocator: std.mem.Allocator, bytes: []const u8) Error!?Stores {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    var diagnostics: std.json.Scanner.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);
    var failure: Failure = .{};
    const first = try readToken(allocator, &scanner, &failure);
    if (!isObjectBegin(first)) return null;
    while (true) {
        const key_token = try readToken(allocator, &scanner, &failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) return null;
        const key = stringText(key_token) orelse return null;
        if (std.mem.eql(u8, key, "stores")) {
            const value = try readToken(allocator, &scanner, &failure);
            if (!isObjectBegin(value)) return null;
            const stores = try parseStores(allocator, &scanner, &failure);
            return stores;
        }
        scanner.skipValue() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidJson;
    }
}

/// `bytes` without its top-level `stores` member, spliced out with the comma that
/// joined it, so a file reads as it did before the member was added (`{"version": 1}`
/// for `{"version": 1, "stores": {...}}`). Bytes without the member, or that are not
/// a JSON object, are returned as they are; otherwise the copy is the caller's.
pub fn withoutStores(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![]const u8 {
    const span = storesSpan(allocator, bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return bytes,
    } orelse return bytes;
    return std.mem.concat(allocator, u8, &.{ bytes[0..span.start], bytes[span.end..] });
}

/// The byte range `withoutStores` removes.
const Span = struct { start: usize, end: usize };

fn storesSpan(allocator: std.mem.Allocator, bytes: []const u8) !?Span {
    var scanner = std.json.Scanner.initCompleteInput(allocator, bytes);
    defer scanner.deinit();
    if (try scanner.next() != .object_begin) return null;
    var member: usize = 0;
    while (true) : (member += 1) {
        const before_key = scanner.cursor;
        const key_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) return null;
        const key = stringText(key_token) orelse return null;
        try scanner.skipValue();
        if (!std.mem.eql(u8, key, "stores")) continue;
        const after_value = scanner.cursor;
        // A later member keeps its own comma: the one before `stores` goes with it.
        if (member != 0) return .{ .start = before_key, .end = after_value };
        // The first member takes the comma after it, up to the next key.
        const start = skipBlank(bytes, before_key);
        var end = skipBlank(bytes, after_value);
        if (end < bytes.len and bytes[end] == ',') end = skipBlank(bytes, end + 1) else end = after_value;
        return .{ .start = start, .end = end };
    }
}

fn skipBlank(bytes: []const u8, from: usize) usize {
    var index = from;
    while (index < bytes.len and std.mem.indexOfScalar(u8, " \t\r\n", bytes[index]) != null) index += 1;
    return index;
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

const duplicate_limit_detail = "duplicate limits field";
const invalid_limit_detail = "limits values must be positive integers no larger than 4294967295, and max_memory a byte count or a size such as \"1G\"";

/// Read the body of a `limits` object after its opening brace: an optional `run`
/// and an optional `test` object, each a set of execution budgets.
fn parseLimits(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!Limits {
    var limits: Limits = .{};
    var seen: u8 = 0;
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, scanner.diagnostics.?, "limits keys must be strings", error.InvalidLimits);
        const value = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, value);
        const is_run = std.mem.eql(u8, key, "run");
        if (!is_run and !std.mem.eql(u8, key, "test")) return fail(failure, scanner.diagnostics.?, "unknown field in limits; expected run or test", error.UnknownField);
        const bit: u8 = if (is_run) 1 else 2;
        if (seen & bit != 0) return fail(failure, scanner.diagnostics.?, duplicate_limit_detail, error.DuplicateField);
        seen |= bit;
        if (!isObjectBegin(value)) return fail(failure, scanner.diagnostics.?, "each limits entry must be a JSON object", error.InvalidLimits);
        const parsed = try parseCommandLimits(allocator, scanner, failure);
        if (is_run) limits.run = parsed else limits.tests = parsed;
    }
    return limits;
}

/// Read one command's budgets after its opening brace. `max_steps` and
/// `max_frames` are positive 32-bit integers, as `selka test` takes them;
/// `max_memory` is a byte count or a suffixed size, and zero removes the ceiling.
fn parseCommandLimits(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure) Error!CommandLimits {
    var limits: CommandLimits = .{};
    while (true) {
        const key_token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, key_token);
        if (isObjectEnd(key_token)) break;
        const key = stringText(key_token) orelse return fail(failure, scanner.diagnostics.?, "limits keys must be strings", error.InvalidLimits);
        const value = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, value);
        if (std.mem.eql(u8, key, "max_memory")) {
            if (limits.max_memory != null) return fail(failure, scanner.diagnostics.?, duplicate_limit_detail, error.DuplicateField);
            limits.max_memory = memoryBytes(value) orelse return fail(failure, scanner.diagnostics.?, invalid_limit_detail, error.InvalidLimits);
            continue;
        }
        var slot: *?u64 = &limits.max_steps;
        if (std.mem.eql(u8, key, "max_frames")) {
            slot = &limits.max_frames;
        } else if (!std.mem.eql(u8, key, "max_steps")) {
            return fail(failure, scanner.diagnostics.?, "unknown field in limits", error.UnknownField);
        }
        if (slot.* != null) return fail(failure, scanner.diagnostics.?, duplicate_limit_detail, error.DuplicateField);
        const text = numberText(value) orelse return fail(failure, scanner.diagnostics.?, invalid_limit_detail, error.InvalidLimits);
        const parsed = std.fmt.parseUnsigned(u32, text, 10) catch return fail(failure, scanner.diagnostics.?, invalid_limit_detail, error.InvalidLimits);
        if (parsed == 0) return fail(failure, scanner.diagnostics.?, invalid_limit_detail, error.InvalidLimits);
        slot.* = parsed;
    }
    return limits;
}

/// A `max_memory` value: a non-negative byte count, or the suffixed text
/// `memory_budget.parse` reads on the command line.
fn memoryBytes(token: std.json.Scanner.Token) ?u64 {
    if (numberText(token)) |text| return std.fmt.parseUnsigned(u64, text, 10) catch null;
    const text = stringText(token) orelse return null;
    return budget.parse(text) catch null;
}

/// Consume the rest of a JSON value whose opening object or array token was
/// already read, including nested containers and scalar leaves. The `lint`
/// object's contents belong to the lint driver, which parses them itself.
// twin-drift-ok: this root-module file cannot import the `selka` module's
// lint_config.zig, so the strict-JSON skip is deliberately duplicated there.
fn skipValue(allocator: std.mem.Allocator, scanner: *std.json.Scanner, failure: *Failure, diagnostics: *const std.json.Scanner.Diagnostics) Error!void {
    var depth: usize = 1;
    while (depth != 0) {
        const token = try readToken(allocator, scanner, failure);
        defer freeToken(allocator, token);
        switch (token) {
            .object_begin, .array_begin => depth += 1,
            .object_end, .array_end => depth -= 1,
            .end_of_document => return fail(failure, diagnostics, "unterminated lint object in selka.json", error.InvalidJson),
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

/// Where a boolean field's rejection is reported, and the error it names.
const BooleanRejection = struct { failure: *Failure, diagnostics: *const std.json.Scanner.Diagnostics, invalid: Error };

/// Read one optional boolean field named `name`: a repeat is a duplicate, and
/// anything but `true` or `false` is `rejection.invalid`.
fn booleanField(comptime name: []const u8, seen: ?bool, value: std.json.Scanner.Token, rejection: BooleanRejection) Error!bool {
    if (seen != null) return fail(rejection.failure, rejection.diagnostics, "duplicate " ++ name ++ " field", error.DuplicateField);
    return switch (value) {
        .true => true,
        .false => false,
        else => fail(rejection.failure, rejection.diagnostics, name ++ " must be true or false", rejection.invalid),
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

// FR8: `parseStores` releases the paths it already read when a later key is refused.
test "project stores: parseStores frees what it read when a later key is refused" {
    var scanner = std.json.Scanner.initCompleteInput(std.testing.allocator, "{\"objects\": \"/a\", \"stages\": \"/b\", \"objects\": \"/c\"}");
    defer scanner.deinit();
    var diagnostics: std.json.Scanner.Diagnostics = .{};
    scanner.enableDiagnostics(&diagnostics);
    var failure: Failure = .{};
    try std.testing.expect(isObjectBegin(try scanner.next()));
    try std.testing.expectError(error.DuplicateField, parseStores(std.testing.allocator, &scanner, &failure));
    try std.testing.expectEqualStrings("duplicate stores field", failure.detail);
}

/// `testEntryLocation` run once for the allocation-failure check below.
fn locateAndFree(allocator: std.mem.Allocator, io: std.Io, entry: []const u8) !void {
    const found = (try testEntryLocation(allocator, io, entry)) orelse return;
    allocator.free(found.root);
    allocator.free(found.relative);
    allocator.free(found.name);
}

test "an entry under a hidden folder is named by the reserved spelling, and a failed allocation leaves nothing behind" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "app/.tmp/deep");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/selka.json", .data = "{\"version\":1}" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "app/.tmp/deep/x.selka", .data = "" });
    const entry = try tmp.dir.realPathFileAlloc(std.testing.io, "app/.tmp/deep/x.selka", std.testing.allocator);
    defer std.testing.allocator.free(entry);
    const found = (try testEntryLocation(std.testing.allocator, std.testing.io, entry)).?;
    defer std.testing.allocator.free(found.root);
    defer std.testing.allocator.free(found.relative);
    defer std.testing.allocator.free(found.name);
    try std.testing.expectEqualStrings(".tmp/deep/x.selka", found.relative);
    try std.testing.expectEqualStrings("__hidden_tmp.deep.x", found.name);
    try std.testing.expect(std.mem.endsWith(u8, found.root, "/app"));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, locateAndFree, .{ std.testing.io, entry });
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, entryModuleName(failing.allocator(), ".tmp/x"));
    // A segment that cannot be a module name, or that already begins with the reserved prefix, has no name.
    for ([_][]const u8{ "my-dir/x", "9d/x", ".9d-x/y", "a//b", "app/__hidden_tmp/x", "app/.__hidden_tmp/x", "." }) |stem| {
        try std.testing.expect(try entryModuleName(std.testing.allocator, stem) == null);
    }
}
