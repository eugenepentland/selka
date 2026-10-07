//! Entry-anchored project configuration for the new compiler core. Import roots
//! follow module paths; configuration roots separately confine embedded assets.
//! The shared front end owns configuration, policy and .api parsing.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const config = language.project_config;

/// Configuration and source failures have already been rendered to the caller.
pub const Error = error{ SourceError, OutOfMemory };

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
                return error.SourceError;
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
    } else {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, absolute, allocator, .limited(64 << 20)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try report.print(allocator, "error: cannot read {s}: {s}\n", .{ absolute, @errorName(err) });
            return error.SourceError;
        };
        if (declaredModule(bytes)) |name| {
            const relative = language.project.modulePath(allocator, name) catch return error.OutOfMemory;
            if (rootFor(absolute, relative)) |root| {
                entry.root = root;
                entry.name = name;
            }
        }
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
            return error.SourceError;
        };
        if (!configured.document.value_semantics) {
            try report.print(allocator, "{s}: error[E_CORE_UNSUPPORTED]: the new core requires value_semantics\n", .{configured.path});
            return error.SourceError;
        }
        entry.configuration = configured;
    }
    return entry;
}

fn rootFor(path: []const u8, relative: []const u8) ?[]const u8 {
    if (!std.mem.endsWith(u8, path, relative) or path.len <= relative.len) return null;
    const separator = path.len - relative.len - 1;
    if (path[separator] != std.fs.path.sep) return null;
    return if (separator == 0) path[0..1] else path[0..separator];
}

fn declaredModule(bytes: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (!std.mem.startsWith(u8, line, "module ")) return null;
        var words = std.mem.tokenizeAny(u8, line["module ".len..], " \t\r#");
        const name = words.next() orelse return null;
        return if (language.project.validName(name)) name else null;
    }
    return null;
}

// spec: NEW-CORE-S4-PROJECT-1
test "nested module root resolution respects file boundaries and mismatched declarations" {
    try std.testing.expectEqualStrings("/project/src", rootFor("/project/src/types/shape.my", "types/shape.my").?);
    try std.testing.expectEqualStrings("/", rootFor("/main.my", "main.my").?);
    try std.testing.expect(rootFor("/project/my_main.my", "main.my") == null);
    try std.testing.expect(rootFor("/project/main.my", "wrong.my") == null);
    try std.testing.expectEqualStrings("types.shape", declaredModule("# comment\n\nmodule types.shape\n").?);
    try std.testing.expect(declaredModule("module ../escape\n") == null);
}
