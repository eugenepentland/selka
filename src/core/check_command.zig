//! `mylang-core check`: exercise the same front-end session as build/test, with
//! optional complete typed trees for profiling their hydration separately.
const std = @import("std");
const single_owner_contract = @import("single_owner.zig");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");

/// A check's host failures; source diagnostics are returned as process status.
pub const Error = error{ OutOfMemory, WriteFailed };

const Options = struct {
    path: []const u8 = "",
    cache: []const u8 = ".mylang-cache/core",
    typed: bool = false,
    stats: bool = false,
    timings: bool = false,
    no_cache: bool = false,
    single_owner: bool = false,
    zero_rc: bool = false,
};

/// Check one file, emitting diagnostics or opt-in work/timing receipts.
pub fn run(given: std.process.Init, args: []const []const u8) Error!u8 {
    const options = parse(args) orelse return 2;
    const init = try @import("compiler_sharing.zig").prepare(given, options.no_cache);
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, options.path, &report) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, report.items);
        return project_entry.status(err);
    };
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    if (!options.no_cache) {
        try session.enableCache(init.gpa, options.cache);
        try session.enableSharedCache(init.environ_map);
    }
    if (!options.typed and !options.single_owner) session.validationOnly();
    var profile = language.timings.Profile.init(init.io, options.timings, .compiler);
    session.setProfile(&profile);
    const checked = entry.check(allocator, &session, &report) catch |err| switch (err) {
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
    if (options.single_owner and !try single_owner_contract.validateMode(allocator, checked.program, checked.src, .text, &report, options.zero_rc)) {
        try write(init.io, report.items);
        return 1;
    }
    profile.counts = .{
        .modules = if (session.single != null) 1 else session.project.modules.items.len,
        .source_bytes = checked.src.bytes.len,
        .typed_nodes = checked.program.nodes.len,
    };
    if (options.stats) {
        const text = try std.json.Stringify.valueAlloc(allocator, .{
            .version = "core-check-work-v1",
            .typed = options.typed,
            .functions = checked.program.functions.len,
            .work = session.statistics(),
        }, .{});
        try write(init.io, text);
        try write(init.io, "\n");
    }
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
            options.typed = true;
        } else if (std.mem.eql(u8, arg, "--experimental-single-owner")) {
            options.single_owner = true;
        } else if (std.mem.eql(u8, arg, "--experimental-zero-rc")) {
            options.single_owner = true;
            options.zero_rc = true;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            options.stats = true;
        } else if (std.mem.eql(u8, arg, "--timings=json")) {
            options.timings = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            options.no_cache = true;
        } else if (std.mem.eql(u8, arg, "--cache-dir") and index + 1 < args.len) {
            index += 1;
            options.cache = args[index];
        } else if (options.path.len == 0 and !std.mem.startsWith(u8, arg, "-")) {
            options.path = arg;
        } else return null;
    }
    return if (options.path.len == 0) null else options;
}
