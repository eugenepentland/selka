//! Entry-anchored project configuration for the new compiler core. Import roots
//! follow module paths; configuration roots separately confine embedded assets.
//! The shared front end owns configuration, policy and .api parsing.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const config = language.project_config;

/// Configuration and source failures have already been rendered to the caller;
/// `PolicyDenied` is an import the configured policy denies and `ConfigurationFailed`
/// a `mylang.json` that does not load (NEW-CORE-S5-POLICY-1).
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

/// Borrowed entry settings, owned by the command's allocator.
pub const Entry = struct {
    path: []const u8,
    root: []const u8,
    name: []const u8,
    configuration: ?config.Config = null,

    /// Apply source budgets, nested module identity and embedded-file boundaries.
    pub fn configure(self: Entry, session: *frontend.Session) void {
        if (self.configuration) |configured| session.files.embed_root = std.fs.path.dirname(configured.path);
        session.configureProject(self.limits(), self.name);
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
        var options: language.project.Options = .{};
        if (self.configuration) |configured| {
            const budgets = configured.document.budgets;
            if (budgets.max_modules) |maximum| options.max_modules = maximum;
            if (budgets.max_imports) |maximum| options.max_imports = maximum;
            if (budgets.max_file_bytes) |maximum| options.max_file_bytes = maximum;
            if (budgets.max_total_bytes) |maximum| options.max_total_bytes = maximum;
        }
        return options;
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
            const stale = language.api_files.staleDiagnostics(allocator, session.files.io, self.root, self.path, session.interfaceIndex()) catch |err| {
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

/// Resolve an entry and its nearest strict mylang.json before loading sources.
pub fn resolve(allocator: std.mem.Allocator, io: std.Io, path: []const u8, report: *std.ArrayList(u8)) Error!Entry {
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

// spec: NEW-CORE-S4-PROJECT-1
test "unconfigured entry identity comes from its file path" {
    const entry = frontend.entryOf("/project/src/types/shape.my");
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
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = "import helper\nfunc main() -> int:\n    return helper.value()\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "helper.my", .data = "public func value() -> int effects():\n    return 7\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "mylang.json", .data = "{\"version\":1,\"import_policy\":\"policy.json\"}" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "policy.json", .data = "{\"version\":1,\"default_action\":\"deny\",\"rules\":[]}" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "main.my", a);
    var report: std.ArrayList(u8) = .empty;
    const entry = try resolve(a, std.testing.io, path, &report);
    var session = frontend.Session.init(a, std.testing.io, entry.root);
    entry.configure(&session);
    _ = try session.checkFile(a, path, &report);
    try std.testing.expectError(error.PolicyDenied, entry.validate(a, &session, &report));
    try std.testing.expectEqual(@as(u8, 3), status(error.PolicyDenied));
    try std.testing.expectEqual(@as(u8, 1), status(error.SourceError));
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "mylang.json", .data = "{" });
    try std.testing.expectError(error.ConfigurationFailed, resolve(a, std.testing.io, path, &report));
    try std.testing.expectEqual(@as(u8, 2), status(error.ConfigurationFailed));
}
