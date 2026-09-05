//! Host I/O and process policy stay outside the compiler and VM.
const std = @import("std");
const language = @import("mylang");
const usage = "usage: mylang <check|run|dump-bytecode|discover-duplicates> <file.my>\n  run: --max-steps=N --max-frames=N --memory=general|arena\n  discover-duplicates: --min-nodes=N --population=production|tests|generated|reference|intentional --timings --approximate --max-work=N\n";

pub fn main(init: std.process.Init) void {
    const status = dispatch(init) catch |err| status: {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: host failure: {s}\n", .{@errorName(err)}) catch "mylang: host failure\n";
        std.Io.File.stderr().writeStreamingAll(init.io, message) catch {};
        break :status 2;
    };
    if (status != 0) std.process.exit(status);
}

fn dispatch(init: std.process.Init) !u8 {
    const allocator = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const parsed = parseArgs(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    };
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    var compilation = try language.Compilation.init(allocator, parsed.path, bytes);
    defer compilation.deinit();
    const check_start = if (parsed.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    compilation.check() catch |err| switch (err) {
        error.SourceError => {
            try report(init, &compilation);
            return 1;
        },
        else => return err,
    };
    const check_ns = if (parsed.timings) check_start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds else 0;
    try report(init, &compilation);
    switch (parsed.command) {
        .check => return 0,
        .@"discover-duplicates" => {
            const start = std.Io.Timestamp.now(init.io, .awake);
            var analysis = try language.duplicates.discover(allocator, compilation.program.?, parsed.discovery);
            defer analysis.deinit();
            const analysis_ns = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
            const text = try language.duplicates.render(allocator, analysis, compilation.program.?, compilation.src);
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
            if (parsed.timings) {
                const counts = try std.fmt.allocPrint(allocator, "timings: frontend_ns={d} discovery_ns={d} source_bytes={d} ast_nodes={d} typed_nodes={d} canonical_bytes={d} functions={d}\n", .{ check_ns, analysis_ns, bytes.len, compilation.syntax.?.nodes.items.len + compilation.syntax.?.statements.items.len, compilation.program.?.nodes.len + compilation.program.?.statements.len, analysis.canonical_bytes, analysis.functions_examined });
                defer allocator.free(counts);
                try std.Io.File.stderr().writeStreamingAll(init.io, counts);
            }
        },
        .@"dump-bytecode" => {
            const text = try compilation.dump(allocator);
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
        },
        .run => switch (try compilation.executeWithOptions(allocator, parsed.options)) {
            .value => |value| {
                var buffer: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&buffer, "{d}\n", .{value});
                try std.Io.File.stdout().writeStreamingAll(init.io, text);
            },
            .trap => |diagnostic| {
                const rendered = try diagnostic.render(allocator, compilation.src);
                defer allocator.free(rendered);
                try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
                return 1;
            },
        },
    }
    return 0;
}

fn report(init: std.process.Init, compilation: *const language.Compilation) !void {
    for (compilation.diagnostics.items) |diagnostic| {
        const rendered = try diagnostic.render(init.gpa, compilation.src);
        defer init.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
    }
}

const Command = enum { check, run, @"dump-bytecode", @"discover-duplicates" };
const Parsed = struct { command: Command, path: []const u8, options: language.vm.Options, discovery: language.duplicates.Options, timings: bool };
fn parseArgs(args: []const []const u8) error{Usage}!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var path: ?[]const u8 = null;
    var options: language.vm.Options = .{};
    var saw_steps = false;
    var saw_frames = false;
    var saw_memory = false;
    var discovery: language.duplicates.Options = .{};
    var timings = false;
    var saw_min = false;
    var saw_population = false;
    var saw_work = false;
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--max-steps=")) {
            if (command != .run or saw_steps) return error.Usage;
            saw_steps = true;
            const digits = arg["--max-steps=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            options.max_steps = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (options.max_steps == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--max-frames=")) {
            if (command != .run or saw_frames) return error.Usage;
            saw_frames = true;
            const digits = arg["--max-frames=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            options.max_frames = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (options.max_frames == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--memory=")) {
            if (command != .run or saw_memory) return error.Usage;
            saw_memory = true;
            options.memory_backing = std.meta.stringToEnum(language.vm.MemoryBacking, arg["--memory=".len..]) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--min-nodes=")) {
            if (command != .@"discover-duplicates" or saw_min) return error.Usage;
            saw_min = true;
            discovery.min_nodes = std.math.cast(usize, try positive(arg["--min-nodes=".len..])) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--population=")) {
            if (command != .@"discover-duplicates" or saw_population) return error.Usage;
            saw_population = true;
            discovery.population = std.meta.stringToEnum(language.duplicates.Population, arg["--population=".len..]) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--approximate")) {
            if (command != .@"discover-duplicates" or discovery.approximate) return error.Usage;
            discovery.approximate = true;
        } else if (std.mem.startsWith(u8, arg, "--max-work=")) {
            if (command != .@"discover-duplicates" or saw_work) return error.Usage;
            saw_work = true;
            discovery.near_options.max_work = std.math.cast(usize, try positive(arg["--max-work=".len..])) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--timings")) {
            if (command != .@"discover-duplicates" or timings) return error.Usage;
            timings = true;
        } else {
            if (std.mem.startsWith(u8, arg, "--") or path != null) return error.Usage;
            path = arg;
        }
    }
    if (saw_work and !discovery.approximate) return error.Usage;
    return .{ .command = command, .path = path orelse return error.Usage, .options = options, .discovery = discovery, .timings = timings };
}

fn positive(digits: []const u8) error{Usage}!u64 {
    if (digits.len == 0) return error.Usage;
    for (digits) |ch| if (!std.ascii.isDigit(ch)) {
        return error.Usage;
    };
    const value = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
    if (value == 0) return error.Usage;
    return value;
}
