//! Entry-anchored project configuration for the new compiler core. Import roots
//! follow module paths; configuration roots separately confine embedded assets.
//! The shared front end owns configuration, policy and .api parsing.
const std = @import("std");
const product = @import("selka").product;
const language = @import("selka");
const frontend = @import("frontend.zig");
const inputs = @import("inputs.zig");
const config = language.project_config;

/// Configuration and source failures have already been rendered to the caller;
/// `PolicyDenied` is an import the configured policy denies and `ConfigurationFailed`
/// a `selka.json` that does not load (NEW-CORE-S5-POLICY-1).
pub const Error = error{ SourceError, OutOfMemory, PolicyDenied, ConfigurationFailed };

/// The exit status of a rendered failure, as the old CLI's policy gate returns it: 3
/// for a denied import policy, 2 for a configuration that does not load, else 1.
pub fn status(err: Error) u8 {
    return switch (err) {
        error.PolicyDenied => 3,
        error.ConfigurationFailed => 2,
        else => 1,
    };
}

/// Append a warning for each name `Entry.shadowedStandard` found.
pub fn appendShadowedStandardWarnings(names: []const []const u8, allocator: std.mem.Allocator, report: *std.ArrayList(u8)) error{OutOfMemory}!void {
    for (names) |name| try report.print(allocator, "selka: local standard module '{s}' is ignored; pass --local-stdlib to prefer it\n", .{name});
}

/// The names of the `.selka` files directly in `root` that a standard module of the same name hides, read from the directory itself
/// (nothing is recorded: a command that does not replay by its inputs asks here). Empty when the directory cannot be listed.
pub fn shadowedIn(allocator: std.mem.Allocator, io: std.Io, root: []const u8) error{OutOfMemory}![]const []const u8 {
    const names = try inputs.listNames(allocator, io, root, .standard_modules);
    return names orelse &.{};
}

/// Borrowed entry settings, owned by the command's allocator.
pub const Entry = struct {
    path: []const u8,
    root: []const u8,
    name: []const u8,
    configuration: ?config.Config = null,
    /// Prefer a standard module's source beside the entry over the embedded copy
    /// (`--local-stdlib`); set once by the build before the entry is configured.
    prefer_standard_sources: bool = false,
    /// The local files a standard module hides (`shadowedStandard`), kept for the project's messages (`limits`).
    shadowed: []const []const u8 = &.{},

    /// Apply source budgets, nested module identity and embedded-file boundaries.
    pub fn configure(self: Entry, session: *frontend.Session) void {
        if (self.configuration) |configured| session.files.embed_root = std.fs.path.dirname(configured.path);
        session.configureProject(self.limits(), self.name);
    }

    /// The project root cache keys name the entry under (`entry_name.zig`): the directory of the loaded selka.json,
    /// or empty for the working directory.
    pub fn keyRoot(self: Entry) []const u8 {
        const configured = self.configuration orelse return "";
        return std.fs.path.dirname(configured.path) orelse "";
    }

    /// The local `.selka` files whose names are also standard modules while the embedded
    /// copy is in use. The entry directory is the only place `--local-stdlib` would
    /// look, so only it is listed, through `handle`: a file that appears or goes is
    /// then a change of the build's record, which holds the warnings it printed.
    pub fn shadowedStandard(self: Entry, handle: *inputs.Handle) error{OutOfMemory}![]const []const u8 {
        if (self.prefer_standard_sources) return &.{};
        return handle.listing(self.root, .standard_modules);
    }

    /// Check a developer view as the `check` CLI does: a file with no `main` is a
    /// library, while a declared entry is an ordinary program.
    pub fn checkLibrary(self: Entry, allocator: std.mem.Allocator, session: *frontend.Session, report: *std.ArrayList(u8)) (Error || frontend.Error || error{ReadFailed})!frontend.Checked {
        self.configure(session);
        const checked = try session.checkFileLibrary(allocator, self.path, report);
        try self.validate(allocator, session, report);
        return checked;
    }

    /// Check a developer view with the same budgets, module identity and policy as builds.
    pub fn check(self: Entry, allocator: std.mem.Allocator, session: *frontend.Session, report: *std.ArrayList(u8)) (Error || frontend.Error || error{ReadFailed})!frontend.Checked {
        self.configure(session);
        const checked = try session.checkFile(allocator, self.path, report);
        try self.validate(allocator, session, report);
        return checked;
    }

    /// The same source limits apply to discovery and full checking.
    pub fn limits(self: Entry) language.project.Options {
        var options: language.project.Options = .{ .standard = .{ .from_provider = self.prefer_standard_sources, .hidden = self.shadowed } };
        if (self.configuration) |configured| {
            const budgets = configured.document.budgets;
            if (budgets.max_modules) |maximum| options.max_modules = maximum;
            if (budgets.max_imports) |maximum| options.max_imports = maximum;
            if (budgets.max_file_bytes) |maximum| options.max_file_bytes = maximum;
            if (budgets.max_total_bytes) |maximum| options.max_total_bytes = maximum;
        }
        return options;
    }

    /// The C sources a build of this entry links: the configuration's `links`, each resolved against the configuration's
    /// directory and spelled relative to the working directory when it lies under it, then `command_line`'s, less any
    /// that names a file already listed. A `links` entry that names no file is `ConfigurationFailed`, with a line that
    /// names the configuration and the entry.
    pub fn linkSources(self: Entry, allocator: std.mem.Allocator, io: std.Io, command_line: []const []const u8, report: *std.ArrayList(u8)) Error![]const []const u8 {
        const configured = self.configuration orelse return command_line;
        const listed = (try config.foreignLinks(allocator, configured.bytes)).links;
        if (listed.len == 0) return command_line;
        const cwd = std.Io.Dir.cwd();
        const here = cwd.realPathFileAlloc(io, ".", allocator) catch "";
        const directory = std.fs.path.dirname(configured.path) orelse ".";
        var sources: std.ArrayList([]const u8) = .empty;
        var named: std.ArrayList([]const u8) = .empty;
        for (listed) |entry| {
            const absolute = try std.fs.path.resolve(allocator, &.{ directory, entry });
            const real = cwd.realPathFileAlloc(io, absolute, allocator) catch {
                try report.print(allocator, "{s}: error[E_PROJECT_CONFIG]: links entry \"{s}\" names no file ({s})\n", .{ configured.path, entry, absolute });
                return error.ConfigurationFailed;
            };
            try named.append(allocator, real);
            try sources.append(allocator, underDirectory(here, absolute) orelse absolute);
        }
        for (command_line) |link| {
            const real = cwd.realPathFileAlloc(io, link, allocator) catch link;
            if (listedAlready(named.items, real)) continue;
            try named.append(allocator, real);
            try sources.append(allocator, link);
        }
        return sources.items;
    }

    /// The include folders of every C source a build of this entry links: the configuration's `include`, each resolved
    /// against the configuration's directory, then `command_line`'s (`--include`, and a chosen device's).
    pub fn includeFolders(self: Entry, allocator: std.mem.Allocator, command_line: []const []const u8) error{OutOfMemory}![]const []const u8 {
        const configured = self.configuration orelse return command_line;
        const listed = (try config.foreignLinks(allocator, configured.bytes)).include;
        if (listed.len == 0) return command_line;
        const directory = std.fs.path.dirname(configured.path) orelse ".";
        var folders: std.ArrayList([]const u8) = .empty;
        for (listed) |folder| try folders.append(allocator, try std.fs.path.resolve(allocator, &.{ directory, folder }));
        try folders.appendSlice(allocator, command_line);
        return folders.items;
    }

    /// Enforce the configured import policy and generated interfaces after checking.
    pub fn validate(self: Entry, allocator: std.mem.Allocator, session: *frontend.Session, report: *std.ArrayList(u8)) Error!void {
        const configured = self.configuration orelse return;
        if (session.single != null) return;
        if (configured.policy) |file| {
            var policy = language.import_policy.Policy.parse(allocator, file.bytes) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try report.print(allocator, "{s}: error[E_PROJECT_CONFIG]: invalid import policy: {s}\n", .{ file.path, @errorName(err) });
                return error.SourceError;
            };
            defer policy.deinit();
            var result = language.import_policy.evaluate(allocator, &session.project, policy) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try report.appendSlice(allocator, "error[E_PROJECT_CONFIG]: configured import policy requires a complete module graph\n");
                return error.SourceError;
            };
            defer result.deinit();
            if (result.denied != 0) {
                try report.appendSlice(allocator, try language.import_policy.render(allocator, result, &session.project, policy));
                return error.PolicyDenied;
            }
        }
        if (configured.document.interface_files) {
            const stale = language.api_files.staleDiagnostics(allocator, session.files.io, self.root, self.path, session.interfaceIndex(), language.api_files.stagedRun()) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                try report.print(allocator, "{s}: error[E_INTERFACE_FILE_STALE]: cannot validate generated interfaces: {s}\n", .{ self.path, @errorName(err) });
                return error.SourceError;
            };
            if (stale) |text| {
                try report.appendSlice(allocator, text);
                return error.SourceError;
            }
        }
    }
};

/// `path` relative to `directory` when it lies under it, else null.
fn underDirectory(directory: []const u8, path: []const u8) ?[]const u8 {
    if (directory.len == 0 or !std.mem.startsWith(u8, path, directory)) return null;
    if (path.len <= directory.len + 1 or path[directory.len] != '/') return null;
    return path[directory.len + 1 ..];
}

fn listedAlready(names: []const []const u8, name: []const u8) bool {
    for (names) |listed| if (std.mem.eql(u8, listed, name)) return true;
    return false;
}

/// Resolve an entry and its nearest strict selka.json before loading sources.
pub fn resolve(allocator: std.mem.Allocator, io: std.Io, path: []const u8, report: *std.ArrayList(u8)) Error!Entry {
    return resolveUnder(allocator, io, path, null, report);
}

/// `resolve` for an entry that a directory run placed under `directory`: when no `selka.json` governs the entry, `directory`
/// is its import root and its module name is its path beneath it, as `check DIR` names it (`rows/more_test.selka` is
/// `rows.more_test`). With a `selka.json`, a null `directory`, or an entry that is not beneath `directory` or cannot spell a
/// module name, it is `resolve`. A relative `directory` (`--import-root sub`, `--import-root .`) is taken from the working directory,
/// as every other path option is, and compared as the real path the entry's own path is.
pub fn resolveUnder(allocator: std.mem.Allocator, io: std.Io, path: []const u8, directory: ?[]const u8, report: *std.ArrayList(u8)) Error!Entry {
    var entry = try resolveOwn(allocator, io, path, report);
    const given = directory orelse return entry;
    if (entry.configuration != null) return entry;
    const root = std.Io.Dir.cwd().realPathFileAlloc(io, given, allocator) catch given;
    const relative = underDirectory(root, entry.path) orelse return entry;
    if (!product.isSource(relative) or !config.validModuleName(product.sourceStem(relative))) return entry;
    const name = try allocator.dupe(u8, product.sourceStem(relative));
    for (name) |*byte| {
        if (byte.* == std.fs.path.sep) byte.* = '.';
    }
    entry.root = root;
    entry.name = name;
    return entry;
}

fn resolveOwn(allocator: std.mem.Allocator, io: std.Io, path: []const u8, report: *std.ArrayList(u8)) Error!Entry {
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch path;
    const ordinary = frontend.entryOf(absolute);
    var entry: Entry = .{ .path = absolute, .root = ordinary.root, .name = ordinary.module };
    const located = config.testEntryLocation(allocator, io, absolute) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try report.print(allocator, "{s}: error[E_PROJECT_CONFIG]: cannot locate project entry: {s}\n", .{ absolute, @errorName(err) });
        return error.SourceError;
    };
    if (located) |test_entry| {
        entry.root = test_entry.root;
        entry.name = test_entry.name;
    }
    const discovered = config.discover(allocator, io, absolute) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try report.print(allocator, "{s}: error[E_PROJECT_CONFIG]: cannot discover configuration: {s}\n", .{ absolute, @errorName(err) });
        return error.SourceError;
    };
    if (discovered) |where| {
        var failure: config.Failure = .{};
        const configured = config.load(allocator, io, where, &failure) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try report.print(allocator, "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n", .{ failure.path, failure.location.line, failure.location.column, failure.detail });
            return error.ConfigurationFailed;
        };
        if (!configured.document.value_semantics) {
            try report.print(allocator, "{s}: error[E_CORE_UNSUPPORTED]: the new core requires value_semantics\n", .{configured.path});
            return error.SourceError;
        }
        entry.configuration = configured;
    }
    return entry;
}

test "resolveUnder takes the directory as the root of an unconfigured entry beneath it, and leaves a configured one alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "suite/rows");
    try tmp.dir.createDirPath(std.testing.io, "other");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "suite/rows/more.selka", .data = "" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "suite/rows/more_test.selka", .data = "" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "other/x.selka", .data = "" });
    const suite = try tmp.dir.realPathFileAlloc(std.testing.io, "suite", a);
    const nested = try tmp.dir.realPathFileAlloc(std.testing.io, "suite/rows/more_test.selka", a);
    var report: std.ArrayList(u8) = .empty;
    const own = try resolveUnder(a, std.testing.io, nested, null, &report);
    try std.testing.expectEqualStrings("more_test", own.name);
    try std.testing.expect(std.mem.endsWith(u8, own.root, "suite/rows"));
    const placed = try resolveUnder(a, std.testing.io, nested, suite, &report);
    try std.testing.expectEqualStrings("rows.more_test", placed.name);
    try std.testing.expectEqualStrings(suite, placed.root);
    // A relative directory (`--import-root .`, `--import-root sub`) is taken from the working directory, as the real path it names.
    const working = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", a);
    const relative = try std.fs.path.relative(a, working, null, working, suite);
    const by_relative = try resolveUnder(a, std.testing.io, nested, relative, &report);
    try std.testing.expectEqualStrings("rows.more_test", by_relative.name);
    try std.testing.expectEqualStrings(suite, by_relative.root);
    // An entry that is not beneath the directory keeps its own root.
    const elsewhere = try resolveUnder(a, std.testing.io, try tmp.dir.realPathFileAlloc(std.testing.io, "other/x.selka", a), suite, &report);
    try std.testing.expectEqualStrings("x", elsewhere.name);
    // A `selka.json` above the entry decides the root, whatever the directory.
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":1}" });
    const configured = try resolveUnder(a, std.testing.io, nested, try tmp.dir.realPathFileAlloc(std.testing.io, "suite/rows", a), &report);
    try std.testing.expectEqualStrings("suite.rows.more_test", configured.name);
    try std.testing.expect(configured.configuration != null);
}

test "an entry under a hidden folder of a configured project takes the project's root, and its name loads the file back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, ".tmp/deep");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":1}" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    return 7\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".tmp/scratch.selka", .data = "import helper\nfunc main() -> int:\n    return helper.value()\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".tmp/deep/more.selka", .data = "" });
    const project = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
    var report: std.ArrayList(u8) = .empty;
    const scratch = try resolve(a, std.testing.io, try tmp.dir.realPathFileAlloc(std.testing.io, ".tmp/scratch.selka", a), &report);
    // Before: the root was `.tmp` itself, and `import helper` was E_MODULE_READ (no `helper.selka` under the import root).
    try std.testing.expectEqualStrings(project, scratch.root);
    try std.testing.expectEqualStrings("__hidden_tmp.scratch", scratch.name);
    try std.testing.expect(scratch.configuration != null);
    try std.testing.expectEqualStrings(".tmp/scratch.selka", try language.project.modulePath(a, scratch.name));
    const deep = try resolve(a, std.testing.io, try tmp.dir.realPathFileAlloc(std.testing.io, ".tmp/deep/more.selka", a), &report);
    try std.testing.expectEqualStrings("__hidden_tmp.deep.more", deep.name);
    try std.testing.expectEqualStrings(".tmp/deep/more.selka", try language.project.modulePath(a, deep.name));
    var session = frontend.Session.init(a, std.testing.io, scratch.root);
    scratch.configure(&session);
    _ = try session.check(a, scratch.name, &report);
    try std.testing.expectEqualStrings("", report.items);
}

// spec: NEW-CORE-S4-PROJECT-1
test "unconfigured entry identity comes from its file path" {
    const entry = frontend.entryOf("/project/src/types/shape.selka");
    try std.testing.expectEqualStrings("/project/src/types", entry.root);
    try std.testing.expectEqualStrings("shape", entry.module);
}

// spec: NEW-CORE-S5-POLICY-1
test "an import the configured policy denies is its own failure, with the policy gate's status 3" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "import helper\nfunc main() -> int:\n    return helper.value()\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    return 7\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "selka.json", .data = "{\"version\":1,\"import_policy\":\"policy.json\"}" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "policy.json", .data = "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "main.selka", a);
    var report: std.ArrayList(u8) = .empty;
    const entry = try resolve(a, std.testing.io, path, &report);
    var session = frontend.Session.init(a, std.testing.io, entry.root);
    entry.configure(&session);
    _ = try session.checkFile(a, path, &report);
    try std.testing.expectError(error.PolicyDenied, entry.validate(a, &session, &report));
    try std.testing.expectEqual(@as(u8, 3), status(error.PolicyDenied));
    try std.testing.expectEqual(@as(u8, 1), status(error.SourceError));
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "selka.json", .data = "{" });
    try std.testing.expectError(error.ConfigurationFailed, resolve(a, std.testing.io, path, &report));
    try std.testing.expectEqual(@as(u8, 2), status(error.ConfigurationFailed));
}
