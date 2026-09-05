//! Host I/O and process policy stay outside the compiler and VM.
const std = @import("std");
const language = @import("mylang");
const usage = "usage: mylang <check|run|dump-bytecode|discover-duplicates|report-quality|fmt|emit-c> <file.my>\n  run: --max-steps=N --max-frames=N --memory=general|arena\n  discover-duplicates: --min-nodes=N --population=production|tests|generated|reference|intentional --timings --approximate --max-work=N\n  report-quality: --max-function-lines=N --max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a signal)\n  fmt: --check (otherwise writes formatted source to stdout)\n";

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
    if (parsed.command == .fmt) {
        const formatted = compilation.format(allocator) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            else => return err,
        };
        defer allocator.free(formatted);
        if (parsed.format_check) {
            if (std.mem.eql(u8, formatted, bytes)) return 0;
            try std.Io.File.stderr().writeStreamingAll(init.io, "formatting differs\n");
            return 1;
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, formatted);
        return 0;
    }
    const check_start = if (parsed.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    compilation.check() catch |err| switch (err) {
        error.SourceError => {
            try report(init, &compilation);
            return 1;
        },
        else => return err,
    };
    const check_ns = if (parsed.timings) check_start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds else 0;
    if (parsed.command != .@"emit-c") try report(init, &compilation);
    switch (parsed.command) {
        .fmt => unreachable,
        .@"emit-c" => {
            const generated = compilation.emitC(allocator) catch |err| switch (err) {
                error.SourceError => {
                    try report(init, &compilation);
                    return 1;
                },
                else => return err,
            };
            defer allocator.free(generated);
            try report(init, &compilation);
            try std.Io.File.stdout().writeStreamingAll(init.io, generated);
        },
        .check => return 0,
        .@"report-quality" => {
            var analysis = try language.quality.analyze(allocator, compilation.program.?, compilation.src, parsed.quality);
            defer analysis.deinit();
            const text = try language.quality.render(allocator, analysis, compilation.program.?, compilation.src);
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
        },
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

const Command = enum { @"emit-c", fmt, check, run, @"dump-bytecode", @"discover-duplicates", @"report-quality" };
const Parsed = struct { format_check: bool, quality: language.quality.Options, command: Command, path: []const u8, options: language.vm.Options, discovery: language.duplicates.Options, timings: bool };
fn parseArgs(args: []const []const u8) error{Usage}!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var quality: language.quality.Options = .{};
    var quality_seen: u8 = 0;
    var format_check = false;
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
    argument: for (args[1..]) |arg| {
        inline for (.{ "max_function_lines", "max_parameters", "max_nesting", "max_decisions", "max_line_bytes" }, .{ "--max-function-lines=", "--max-parameters=", "--max-nesting=", "--max-decisions=", "--max-line-bytes=" }, 0..) |field, prefix, index| {
            if (std.mem.startsWith(u8, arg, prefix)) {
                const bit: u8 = 1 << index;
                if (command != .@"report-quality" or quality_seen & bit != 0) return error.Usage;
                quality_seen |= bit;
                const digits = arg[prefix.len..];
                if (digits.len == 0) return error.Usage;
                for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                    return error.Usage;
                };
                @field(quality, field) = std.fmt.parseUnsigned(usize, digits, 10) catch return error.Usage;
                continue :argument;
            }
        }
        if (std.mem.eql(u8, arg, "--check")) {
            if (command != .fmt or format_check) return error.Usage;
            format_check = true;
        } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
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
    return .{ .format_check = format_check, .quality = quality, .command = command, .path = path orelse return error.Usage, .options = options, .discovery = discovery, .timings = timings };
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
