//! Host I/O and process policy stay outside the compiler and VM.
const std = @import("std");
const language = @import("mylang");
const usage = "usage: mylang <check|run|dump-bytecode|discover-duplicates|discover-project-duplicates|report-project-quality|report-quality|fmt|fmt-module|fmt-project|emit-c|emit-project-c|eval-project|list-modules|list-interfaces|check-project|run-project|check-policy> <file.my>\n  run/run-project: --max-steps=N --max-frames=N --memory=general|arena\n  eval-project: --max-steps=N --max-frames=N --max-eval-bytes=N --evaluation-report (effect-free, parameter-free entry)\n  discover-duplicates/discover-project-duplicates: --min-nodes=N --population=production|tests|generated|reference|intentional --timings --approximate --max-work=N\n  report-quality/report-project-quality: --max-function-lines=N --max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a signal)\n  check-policy: --policy=path.json (required; policy failures exit 3)\n  fmt-project: --check (required; checks the reachable import graph)\n  fmt/fmt-module: --check (otherwise writes formatted source to stdout)\n";

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
    if (parsed.command == .@"eval-project" or parsed.command == .@"list-modules" or parsed.command == .@"list-interfaces" or parsed.command == .@"check-project" or parsed.command == .@"run-project" or parsed.command == .@"check-policy" or parsed.command == .@"discover-project-duplicates" or parsed.command == .@"report-project-quality" or parsed.command == .@"fmt-project" or parsed.command == .@"emit-project-c") return listModules(init, parsed);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    var compilation = try language.Compilation.init(allocator, parsed.path, bytes);
    defer compilation.deinit();
    if (parsed.command == .fmt or parsed.command == .@"fmt-module") {
        const formatted = (if (parsed.command == .@"fmt-module") compilation.formatModule(allocator) else compilation.format(allocator)) catch |err| switch (err) {
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
        .@"eval-project", .fmt, .@"fmt-module", .@"fmt-project", .@"emit-project-c", .@"list-modules", .@"list-interfaces", .@"check-project", .@"run-project", .@"check-policy", .@"discover-project-duplicates", .@"report-project-quality" => unreachable,
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

const Command = enum { @"eval-project", @"emit-project-c", @"fmt-project", @"fmt-module", @"report-project-quality", @"discover-project-duplicates", @"check-policy", @"check-project", @"run-project", @"list-interfaces", @"list-modules", @"emit-c", fmt, check, run, @"dump-bytecode", @"discover-duplicates", @"report-quality" };
const Parsed = struct { evaluation_report: bool, evaluation: language.evaluation.Options, policy: ?[]const u8, format_check: bool, quality: language.quality.Options, command: Command, path: []const u8, options: language.vm.Options, discovery: language.duplicates.Options, timings: bool };
fn parseArgs(args: []const []const u8) error{Usage}!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var evaluation: language.evaluation.Options = .{};
    var saw_eval_bytes = false;
    var evaluation_report = false;
    var quality: language.quality.Options = .{};
    var quality_seen: u8 = 0;
    var format_check = false;
    var path: ?[]const u8 = null;
    var policy: ?[]const u8 = null;
    var options: language.vm.Options = .{};
    if (command == .@"eval-project") {
        options.max_steps = evaluation.max_steps;
        options.max_frames = evaluation.max_frames;
    }
    var saw_steps = false;
    var saw_frames = false;
    var saw_memory = false;
    var discovery: language.duplicates.Options = .{};
    var timings = false;
    var saw_min = false;
    var saw_population = false;
    var saw_work = false;
    argument: for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--evaluation-report")) {
            if (command != .@"eval-project" or evaluation_report) return error.Usage;
            evaluation_report = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--max-eval-bytes=")) {
            if (command != .@"eval-project" or saw_eval_bytes) return error.Usage;
            saw_eval_bytes = true;
            evaluation.max_bytes = std.math.cast(usize, try positive(arg["--max-eval-bytes=".len..])) orelse return error.Usage;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--policy=")) {
            if (command != .@"check-policy" or policy != null or arg.len == "--policy=".len) return error.Usage;
            policy = arg["--policy=".len..];
            continue;
        }
        inline for (.{ "max_function_lines", "max_parameters", "max_nesting", "max_decisions", "max_line_bytes" }, .{ "--max-function-lines=", "--max-parameters=", "--max-nesting=", "--max-decisions=", "--max-line-bytes=" }, 0..) |field, prefix, index| {
            if (std.mem.startsWith(u8, arg, prefix)) {
                const bit: u8 = 1 << index;
                if ((command != .@"report-quality" and command != .@"report-project-quality") or quality_seen & bit != 0) return error.Usage;
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
            if ((command != .fmt and command != .@"fmt-module" and command != .@"fmt-project") or format_check) return error.Usage;
            format_check = true;
        } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
            if ((command != .run and command != .@"run-project" and command != .@"eval-project") or saw_steps) return error.Usage;
            saw_steps = true;
            const digits = arg["--max-steps=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            options.max_steps = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (options.max_steps == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--max-frames=")) {
            if ((command != .run and command != .@"run-project" and command != .@"eval-project") or saw_frames) return error.Usage;
            saw_frames = true;
            const digits = arg["--max-frames=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            options.max_frames = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (options.max_frames == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--memory=")) {
            if ((command != .run and command != .@"run-project") or saw_memory) return error.Usage;
            saw_memory = true;
            options.memory_backing = std.meta.stringToEnum(language.vm.MemoryBacking, arg["--memory=".len..]) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--min-nodes=")) {
            if ((command != .@"discover-duplicates" and command != .@"discover-project-duplicates") or saw_min) return error.Usage;
            saw_min = true;
            discovery.min_nodes = std.math.cast(usize, try positive(arg["--min-nodes=".len..])) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--population=")) {
            if ((command != .@"discover-duplicates" and command != .@"discover-project-duplicates") or saw_population) return error.Usage;
            saw_population = true;
            discovery.population = std.meta.stringToEnum(language.duplicates.Population, arg["--population=".len..]) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--approximate")) {
            if ((command != .@"discover-duplicates" and command != .@"discover-project-duplicates") or discovery.approximate) return error.Usage;
            discovery.approximate = true;
        } else if (std.mem.startsWith(u8, arg, "--max-work=")) {
            if ((command != .@"discover-duplicates" and command != .@"discover-project-duplicates") or saw_work) return error.Usage;
            saw_work = true;
            discovery.near_options.max_work = std.math.cast(usize, try positive(arg["--max-work=".len..])) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--timings")) {
            if ((command != .@"discover-duplicates" and command != .@"discover-project-duplicates") or timings) return error.Usage;
            timings = true;
        } else {
            if (std.mem.startsWith(u8, arg, "--") or path != null) return error.Usage;
            path = arg;
        }
    }
    if (saw_work and !discovery.approximate) return error.Usage;
    if (command == .@"fmt-project" and !format_check) return error.Usage;
    if (command == .@"check-policy" and policy == null) return error.Usage;
    return .{ .evaluation_report = evaluation_report, .evaluation = .{ .max_steps = options.max_steps, .max_frames = options.max_frames, .max_bytes = evaluation.max_bytes }, .policy = policy, .format_check = format_check, .quality = quality, .command = command, .path = path orelse return error.Usage, .options = options, .discovery = discovery, .timings = timings };
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

const ModuleFiles = struct {
    io: std.Io,
    root: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *ModuleFiles = @ptrCast(@alignCast(context.?));
        const path = try std.fs.path.join(allocator, &.{ self.root, relative });
        defer allocator.free(path);
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, allocator, .limited(limit)) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.FileNotFound => error.NotFound,
            error.StreamTooLong => error.TooLarge,
            else => error.ReadFailed,
        };
    }
};
fn listModules(init: std.process.Init, parsed: Parsed) !u8 {
    const frontend_start = if (parsed.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    const path = parsed.path;
    const basename = std.fs.path.basename(path);
    if (!std.mem.endsWith(u8, basename, ".my") or !language.project.validName(basename[0 .. basename.len - 3]) or std.mem.indexOfScalar(u8, basename[0 .. basename.len - 3], '.') != null) {
        try std.Io.File.stderr().writeStreamingAll(init.io, "list-modules: entry must be an identifier.my file; imports resolve beneath its directory\n");
        return 2;
    }
    var files: ModuleFiles = .{ .io = init.io, .root = std.fs.path.dirname(path) orelse "." };
    var project = language.project.Project.init(init.gpa);
    defer project.deinit();
    project.load(.{ .context = &files, .read = ModuleFiles.read }, basename[0 .. basename.len - 3], .{}) catch |err| switch (err) {
        error.SourceError => {
            const message = try project.renderProblem(init.gpa);
            defer init.gpa.free(message);
            try std.Io.File.stderr().writeStreamingAll(init.io, message);
            return 1;
        },
        else => return err,
    };
    if (parsed.command == .@"fmt-project") {
        var changed: std.ArrayList([]const u8) = .empty;
        defer changed.deinit(init.gpa);
        for (project.order.items) |module_id| {
            const src = project.modules.items[module_id].src;
            var compilation = try language.Compilation.init(init.gpa, src.path, src.bytes);
            defer compilation.deinit();
            const formatted = compilation.formatModule(init.gpa) catch |err| switch (err) {
                error.SourceError => {
                    try report(init, &compilation);
                    return 1;
                },
                else => return err,
            };
            defer init.gpa.free(formatted);
            if (!std.mem.eql(u8, formatted, src.bytes)) try changed.append(init.gpa, src.path);
        }
        for (changed.items) |path_name| {
            const message = try std.fmt.allocPrint(init.gpa, "{s}: formatting differs\n", .{path_name});
            defer init.gpa.free(message);
            try std.Io.File.stderr().writeStreamingAll(init.io, message);
        }
        return if (changed.items.len == 0) 0 else 1;
    }
    const output = if (parsed.command != .@"list-modules") result: {
        var index = language.interfaces.build(&project) catch |err| switch (err) {
            error.SourceError => {
                const message = try project.renderProblem(init.gpa);
                defer init.gpa.free(message);
                try std.Io.File.stderr().writeStreamingAll(init.io, message);
                return 1;
            },
            else => return err,
        };
        if (parsed.command == .@"list-interfaces") break :result try index.render(init.gpa);
        var compilation = try language.project_compile.Compilation.init(&index);
        compilation.check() catch |err| switch (err) {
            error.SourceError => {
                try reportProject(init, &compilation);
                return 1;
            },
            else => return err,
        };
        if (parsed.command == .@"emit-project-c") {
            const generated = compilation.emitC(init.gpa) catch |err| switch (err) {
                error.SourceError => {
                    try reportProject(init, &compilation);
                    return 1;
                },
                else => return err,
            };
            errdefer init.gpa.free(generated);
            try reportProject(init, &compilation);
            break :result generated;
        }
        if (parsed.command != .@"eval-project") try reportProject(init, &compilation);
        if (parsed.command == .@"check-project") return 0;
        if (parsed.command == .@"report-project-quality") {
            const roots = try compilation.exportRoots(init.gpa);
            defer init.gpa.free(roots);
            var analysis = try language.quality.analyzeWithExports(init.gpa, compilation.program.?, compilation.src, parsed.quality, roots);
            defer analysis.deinit();
            break :result try language.quality.render(init.gpa, analysis, compilation.program.?, compilation.src);
        }
        if (parsed.command == .@"discover-project-duplicates") {
            const start = std.Io.Timestamp.now(init.io, .awake);
            var analysis = try language.duplicates.discover(init.gpa, compilation.program.?, parsed.discovery);
            defer analysis.deinit();
            const discovery_ns = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
            const text = try language.duplicates.render(init.gpa, analysis, compilation.program.?, compilation.src);
            defer init.gpa.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, "scope: reachable module graph; declaration visibility and dependency policy require separate review\n");
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
            if (parsed.timings) {
                const counts = try std.fmt.allocPrint(init.gpa, "timings: project_frontend_ns={d} discovery_ns={d} modules={d} source_bytes={d} ast_nodes={d} typed_nodes={d} canonical_bytes={d} functions={d}\n", .{ frontend_start.durationTo(start).nanoseconds, discovery_ns, project.modules.items.len, project.total_bytes, compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len, compilation.program.?.nodes.len + compilation.program.?.statements.len, analysis.canonical_bytes, analysis.functions_examined });
                defer init.gpa.free(counts);
                try std.Io.File.stderr().writeStreamingAll(init.io, counts);
            }
            return 0;
        }
        if (parsed.command == .@"check-policy") {
            const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.policy.?, init.gpa, .limited(1024 * 1024));
            defer init.gpa.free(bytes);
            var policy = language.import_policy.Policy.parse(init.gpa, bytes) catch |err| {
                if (err == error.OutOfMemory) return err;
                const message = try std.fmt.allocPrint(init.gpa, "{s}: invalid import policy: {s}\n", .{ parsed.policy.?, @errorName(err) });
                defer init.gpa.free(message);
                try std.Io.File.stderr().writeStreamingAll(init.io, message);
                return 2;
            };
            defer policy.deinit();
            var policy_report = try language.import_policy.evaluate(init.gpa, &project, policy);
            defer policy_report.deinit();
            const text = try language.import_policy.render(init.gpa, policy_report, &project, policy);
            defer init.gpa.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, "language: valid\n");
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
            return if (policy_report.denied == 0) 0 else 3;
        }
        try compilation.emit();
        const outcome = if (parsed.command == .@"eval-project") language.evaluation.evaluate(init.gpa, compilation.code.?, &compilation.diagnostics, parsed.evaluation) catch |err| switch (err) {
            error.SourceError => {
                try reportProject(init, &compilation);
                return 1;
            },
            else => return err,
        } else try language.vm.runWithOptions(init.gpa, compilation.code.?, parsed.options);
        if (parsed.command == .@"eval-project") try reportProject(init, &compilation);
        switch (outcome) {
            .value => |value| {
                if (parsed.evaluation_report) break :result try language.evaluation_report.render(init.gpa, &project, value, parsed.evaluation, try evaluationIdentity(init.io));
                break :result try std.fmt.allocPrint(init.gpa, "{d}\n", .{value});
            },
            .trap => |trap| {
                const message = try trap.render(init.gpa, compilation.src);
                defer init.gpa.free(message);
                try std.Io.File.stderr().writeStreamingAll(init.io, message);
                return 1;
            },
        }
    } else try project.render(init.gpa);
    defer init.gpa.free(output);
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    return 0;
}

fn reportProject(init: std.process.Init, compilation: *language.project_compile.Compilation) !void {
    for (compilation.diagnostics.items.items) |problem| {
        const message = try problem.render(init.gpa, compilation.src);
        defer init.gpa.free(message);
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
    }
}

fn evaluationIdentity(io: std.Io) !language.evaluation_report.Identity {
    const executable = try std.process.openExecutable(io, .{});
    defer executable.close(io);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [65536]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const count = try executable.readPositional(io, &.{&buffer}, offset);
        if (count == 0) break;
        hash.update(buffer[0..count]);
        offset += count;
    }
    const builtin = @import("builtin");
    return .{ .compiler_sha256 = hash.finalResult(), .zig_version = builtin.zig_version_string, .architecture = @tagName(builtin.cpu.arch), .os = @tagName(builtin.os.tag), .abi = @tagName(builtin.abi), .optimize = @tagName(builtin.mode) };
}
