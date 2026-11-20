//! `selka-core check`: exercise the same front-end session as build/test, with
//! optional complete typed trees for profiling their hydration separately.
const std = @import("std");
const product = @import("selka").product;
const language = @import("selka");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");

/// A check's host failures; source diagnostics are returned as process status.
pub const Error = error{ OutOfMemory, WriteFailed };

const Options = struct {
    path: []const u8 = "",
    cache: []const u8 = product.core_work_dir,
    mode: enum { normal, typed, ownership_audit } = .normal,
    stats: bool = false,
    timings: bool = false,
    no_cache: bool = false,
    local_stdlib: bool = false,
};

/// Check one file, emitting diagnostics or opt-in work/timing receipts.
pub fn run(given: std.process.Init, args: []const []const u8) Error!u8 {
    var options = parse(args) orelse return 2;
    if (options.mode == .ownership_audit) options.no_cache = true;
    // The project's `stores`, before any store opens (FR8).
    if (try @import("cli_run.zig").applyStores(given, options.path, false)) return 2;
    const init = try @import("compiler_sharing.zig").prepare(given, options.no_cache);
    const allocator = init.arena.allocator();
    // A check's stores are open until it returns, so its work directory is held for the whole run; the
    // bounded collector runs after the hold is released (defers run in reverse order).
    const retention = @import("work_retention.zig");
    const held: ?retention.Hold = if (options.no_cache) null else try retention.hold(allocator, init.io, options.cache);
    defer if (!options.no_cache) retention.automatic(allocator, init.gpa, init.io, options.cache, init.environ_map);
    defer if (held) |lease| lease.release();
    var report: std.ArrayList(u8) = .empty;
    var entry = project_entry.resolve(allocator, init.io, options.path, &report) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, report.items);
        return project_entry.status(err);
    };
    entry.prefer_standard_sources = options.local_stdlib or (options.mode == .ownership_audit and
        language.standard_library.source(std.fs.path.basename(entry.path)) != null);
    // The local files a standard module hides are named once, before anything the check prints.
    entry.shadowed = if (entry.prefer_standard_sources) &.{} else try project_entry.shadowedIn(allocator, init.io, entry.root);
    if (entry.shadowed.len != 0) {
        var warned: std.ArrayList(u8) = .empty;
        try project_entry.appendShadowedStandardWarnings(entry.shadowed, allocator, &warned);
        try write(init.io, warned.items);
    }
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    // A check reports a typed hole; only builds and tests keep one as a runtime trap.
    session.setHoleTraps(false);
    if (options.mode == .ownership_audit) {
        session.setOwnershipReports();
        session.setFormat(.json);
    }
    if (!options.no_cache) {
        try session.enableCache(init.gpa, options.cache);
        try session.enableSharedCache(init.environ_map);
    }
    if (options.mode == .normal) session.validationOnly();
    var profile = language.timings.Profile.init(init.io, options.timings, .compiler);
    session.setProfile(&profile);
    const checked = entry.checkLibrary(allocator, &session, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try write(init.io, report.items);
            const status: u8 = switch (err) {
                error.PolicyDenied => 3,
                error.ConfigurationFailed => 2,
                else => 1,
            };
            profile.report(status) catch return error.WriteFailed;
            return status;
        },
    };
    profile.counts = .{
        .modules = if (session.single != null) 1 else session.project.modules.items.len,
        .source_bytes = checked.src.bytes.len,
        .typed_nodes = checked.program.nodes.len,
    };
    if (options.stats) {
        const text = try std.json.Stringify.valueAlloc(allocator, .{
            .version = "core-check-work-v1",
            .typed = options.mode == .typed,
            .functions = checked.program.functions.len,
            .work = session.statistics(),
        }, .{});
        try write(init.io, text);
        try write(init.io, "\n");
    }
    if (options.mode == .ownership_audit) try write(init.io, report.items);
    profile.report(0) catch return error.WriteFailed;
    return 0;
}

fn write(io: std.Io, bytes: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

fn parse(args: []const []const u8) ?Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--typed")) {
            options.mode = .typed;
        } else if (std.mem.eql(u8, arg, "--ownership-audit")) {
            options.mode = .ownership_audit;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            options.stats = true;
        } else if (std.mem.eql(u8, arg, "--timings=json")) {
            options.timings = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            options.no_cache = true;
        } else if (std.mem.eql(u8, arg, "--local-stdlib")) {
            options.local_stdlib = true;
        } else if (std.mem.eql(u8, arg, "--cache-dir") and index + 1 < args.len) {
            index += 1;
            options.cache = args[index];
        } else if (options.path.len == 0 and !std.mem.startsWith(u8, arg, "-")) {
            options.path = arg;
        } else return null;
    }
    return if (options.path.len == 0) null else options;
}
