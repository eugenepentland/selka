//! Host I/O and process policy stay outside the compiler and VM.
const inputs_prefix = "--inputs=";
const policy_prefix = "--policy=";
const std = @import("std");
const language = @import("mylang");
const diagnostic_output = language.diagnostic_output;
const Reporting = struct { timings: bool = false, diagnostics: ?diagnostic_output.Format = null };
const usage = "usage: mylang " ++
    "<invoke-project|check-value-project|schema-project|input-module|check|run|dump-bytecode|di" ++
    "scover-duplicates|discover-project-duplicates|report-project-quality|report-quality|fmt|fm" ++
    "t-module|fmt-project|emit-c|emit-project-c|eval-project|list-modules|list-interfaces|check" ++
    "-project|run-project|check-policy> <file.my>\n  schema-project: --schema-report (include " ++
    "checked source and compiler identities)\n  check-value-project: --value=path.json " ++
    "(required; validates and writes canonical typed-json-v1); --max-codec-steps=N " ++
    "--max-codec-frames=N --max-codec-calls=N --max-codec-bytes=N --max-codec-values=N\n  " ++
    "invoke-project: --request=path.json (typed-call-v1, schema-pinned public function call; " ++
    "same codec budgets)\n  input-module: reads a typed JSON manifest and writes generated " ++
    "module source\n  run/run-project: --max-steps=N --max-frames=N --memory=general|arena\n  " ++
    "eval-project: --max-steps=N --max-frames=N --max-eval-bytes=N " ++
    "--evaluation-report|--evaluation-request --inputs=manifest.json (repeat for up to 16 " ++
    "modules; effect-free, parameter-free entry)\n  " ++
    "schema-project/check-value-project/invoke-project: --inputs=manifest.json (repeat for up to 16 modules)\n  " ++
    "discover-duplicates/discover-project-duplicates: --min-nodes=N " ++
    "--population=production|tests|generated|reference|intentional --timings --approximate " ++
    "--max-work=N\n  report-quality/report-project-quality: --max-function-lines=N " ++
    "--max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a " ++
    "signal)\n  check-policy: --policy=path.json (required; policy failures exit 3)\n  " ++
    "fmt-project: --check (required; checks the reachable import graph)\n  fmt/fmt-module: " ++
    "--check (otherwise writes formatted source to " ++
    "stdout)\n  project-dependencies: checked module graph and hashes; --inputs supported\n" ++
    "  all commands: --diagnostics=text|json (stderr JSON Lines; stdout unchanged)\n" ++
    "  check-session: persistent check/clear/quit lines on stdin; JSON status on stdout; --inputs supported\n";

/// Dispatch compiler commands, reporting usage/source/IO failures through process exit status.
pub fn main(init: std.process.Init) void {
    const status = dispatch(init) catch |err| status: {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: host failure: {s}\n", .{@errorName(err)}) catch "mylang: host failure\n";
        std.Io.File.stderr().writeStreamingAll(init.io, message) catch break :status @as(u8, 2);
        break :status @as(u8, 2);
    };
    if (status != 0) std.process.exit(status);
}

const Context = struct {
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    diagnostics: diagnostic_output.Format,
    fn text(self: Context, bytes: []const u8) !void {
        if (self.diagnostics == .text) return std.Io.File.stderr().writeStreamingAll(self.io, bytes);
        const rendered = try diagnostic_output.message(self.gpa, bytes, self.diagnostics);
        defer self.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(self.io, rendered);
    }
};
fn dispatch(process: std.process.Init) !u8 {
    const args = try process.minimal.args.toSlice(process.arena.allocator());
    const parsed = parseArgs(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    const init: Context = .{ .gpa = process.gpa, .arena = process.arena, .io = process.io, .diagnostics = parsed.reporting.diagnostics orelse .text };
    return run(init, parsed) catch |err| {
        const message = try std.fmt.allocPrint(init.gpa, "mylang: host failure: {s}\n", .{@errorName(err)});
        defer init.gpa.free(message);
        try init.text(message);
        return 2;
    };
}
fn run(init: Context, parsed: Parsed) !u8 {
    const allocator = init.gpa;
    if (parsed.command == .@"check-session") return checkSession(init, parsed);
    switch (parsed.command) {
        .@"project-dependencies",
        .@"check-session",
        .@"invoke-project",
        .@"check-value-project",
        .@"schema-project",
        .@"eval-project",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"run-project",
        .@"check-policy",
        .@"discover-project-duplicates",
        .@"report-project-quality",
        .@"fmt-project",
        .@"emit-project-c",
        => return listModules(init, parsed),
        else => {},
    }
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    if (parsed.command == .@"input-module") {
        var manifest = (try parseInputManifest(init, parsed.path, bytes)) orelse return 2;
        defer manifest.deinit();
        const generated = try manifest.generate(allocator);
        defer allocator.free(generated);
        try std.Io.File.stdout().writeStreamingAll(init.io, generated);
        return 0;
    }
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
            try init.text("formatting differs\n");
            return 1;
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, formatted);
        return 0;
    }
    const check_start = if (parsed.reporting.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    compilation.check() catch |err| switch (err) {
        error.SourceError => {
            try report(init, &compilation);
            return 1;
        },
        else => return err,
    };
    const check_ns = if (parsed.reporting.timings) check_start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds else 0;
    if (parsed.command != .@"emit-c") try report(init, &compilation);
    switch (parsed.command) {
        .@"project-dependencies",
        .@"check-session",
        .@"invoke-project",
        .@"check-value-project",
        .@"schema-project",
        .@"input-module",
        .@"eval-project",
        .fmt,
        .@"fmt-module",
        .@"fmt-project",
        .@"emit-project-c",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"run-project",
        .@"check-policy",
        .@"discover-project-duplicates",
        .@"report-project-quality",
        => unreachable,
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
            if (parsed.reporting.timings) {
                const counts = try std.fmt.allocPrint(allocator, "timings: frontend_ns={d} discovery_ns={d} source_bytes={d} ast_nodes={d} typed_nodes={d} " ++
                    "canonical_bytes={d} functions={d}" ++
                    "\n", .{
                    check_ns,
                    analysis_ns,
                    bytes.len,
                    compilation.syntax.?.nodes.items.len + compilation.syntax.?.statements.items.len,
                    compilation.program.?.nodes.len + compilation.program.?.statements.len,
                    analysis.canonical_bytes,
                    analysis.functions_examined,
                });
                defer allocator.free(counts);
                try init.text(counts);
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
                const rendered = try diagnostic_output.render(allocator, diagnostic, compilation.src, init.diagnostics);
                defer allocator.free(rendered);
                try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
                return 1;
            },
        },
    }
    return 0;
}

fn report(init: Context, compilation: *const language.Compilation) !void {
    for (compilation.diagnostics.items) |diagnostic| {
        const rendered = try diagnostic_output.render(init.gpa, diagnostic, compilation.src, init.diagnostics);
        defer init.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
    }
}

const Command = enum {
    @"project-dependencies",
    @"check-session",
    @"invoke-project",
    @"check-value-project",
    @"schema-project",
    @"input-module",
    @"eval-project",
    @"emit-project-c",
    @"fmt-project",
    @"fmt-module",
    @"report-project-quality",
    @"discover-project-duplicates",
    @"check-policy",
    @"check-project",
    @"run-project",
    @"list-interfaces",
    @"list-modules",
    @"emit-c",
    fmt,
    check,
    run,
    @"dump-bytecode",
    @"discover-duplicates",
    @"report-quality",
};
const Parsed = struct {
    codec: language.codec_json.Options,
    schema_report: bool,
    value_path: ?[]const u8,
    inputs: [16][]const u8,
    input_count: usize,
    evaluation_request: bool,
    evaluation_report: bool,
    evaluation: language.evaluation.Options,
    policy: ?[]const u8,
    format_check: bool,
    quality: language.quality.Options,
    command: Command,
    path: []const u8,
    options: language.vm.Options,
    discovery: language.duplicates.Options,
    reporting: Reporting,
};
fn parseArgs(args: []const []const u8) error{Usage}!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var parser: ArgumentParser = .{ .command = command };
    if (command == .@"eval-project") {
        parser.options.max_steps = parser.evaluation.max_steps;
        parser.options.max_frames = parser.evaluation.max_frames;
    }
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--diagnostics=")) {
            if (parser.reporting.diagnostics != null) return error.Usage;
            parser.reporting.diagnostics = std.meta.stringToEnum(diagnostic_output.Format, arg["--diagnostics=".len..]) orelse return error.Usage;
            continue;
        }
        if (try parser.codecOption(arg)) continue;
        if (try parser.evaluationOption(arg)) continue;
        if (try parser.qualityOption(arg)) continue;
        if (try parser.executionOption(arg)) continue;
        if (try parser.discoveryOption(arg)) continue;
        if (std.mem.startsWith(u8, arg, policy_prefix)) {
            if (command != .@"check-policy" or parser.policy != null or arg.len == policy_prefix.len) return error.Usage;
            parser.policy = arg[policy_prefix.len..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--") or parser.path != null) return error.Usage;
        parser.path = arg;
    }
    return parser.finish();
}
const ArgumentParser = struct {
    command: Command,
    codec: language.codec_json.Options = .{},
    codec_seen: u8 = 0,
    schema_report: bool = false,
    value_path: ?[]const u8 = null,
    evaluation: language.evaluation.Options = .{},
    saw_eval_bytes: bool = false,
    evaluation_report: bool = false,
    evaluation_request: bool = false,
    inputs: [16][]const u8 = @splat(""),
    input_count: usize = 0,
    quality: language.quality.Options = .{},
    quality_seen: u8 = 0,
    format_check: bool = false,
    path: ?[]const u8 = null,
    policy: ?[]const u8 = null,
    options: language.vm.Options = .{},
    saw_steps: bool = false,
    saw_frames: bool = false,
    saw_memory: bool = false,
    discovery: language.duplicates.Options = .{},
    reporting: Reporting = .{},
    saw_min: bool = false,
    saw_population: bool = false,
    saw_work: bool = false,
    fn codecOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, arg, "--schema-report")) {
            if (self.command != .@"schema-project" or self.schema_report) return error.Usage;
            self.schema_report = true;
            return true;
        }
        inline for (.{
            "max_steps",
            "max_frames",
            "max_calls",
            "max_bytes",
            "max_work_values",
        }, .{
            "--max-codec-steps=",
            "--max-codec-frames=",
            "--max-codec-calls=",
            "--max-codec-bytes=",
            "--max-codec-values=",
        }, 0..) |field, prefix, index| {
            if (std.mem.startsWith(u8, arg, prefix)) {
                const bit: u8 = 1 << index;
                if ((self.command != .@"check-value-project" and self.command != .@"invoke-project") or self.codec_seen & bit != 0) return error.Usage;
                self.codec_seen |= bit;
                @field(self.codec, field) = std.math.cast(@TypeOf(@field(self.codec, field)), try positive(arg[prefix.len..])) orelse return error.Usage;
                return true;
            }
        }
        if (std.mem.startsWith(u8, arg, "--value=") or std.mem.startsWith(u8, arg, "--request=")) {
            const prefix = if (self.command == .@"invoke-project") "--request=" else "--value=";
            if (self.command != .@"check-value-project" and self.command != .@"invoke-project") return error.Usage;
            if (!std.mem.startsWith(u8, arg, prefix)) return error.Usage;
            if (self.value_path != null or arg.len == prefix.len) return error.Usage;
            self.value_path = arg[prefix.len..];
            return true;
        }
        return false;
    }

    fn evaluationOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.startsWith(u8, arg, inputs_prefix)) {
            switch (self.command) {
                .@"eval-project", .@"schema-project", .@"invoke-project", .@"check-value-project", .@"check-session", .@"project-dependencies" => {},
                else => return error.Usage,
            }
            if (self.input_count == self.inputs.len or arg.len == inputs_prefix.len) return error.Usage;
            const input = arg[inputs_prefix.len..];
            for (self.inputs[0..self.input_count]) |previous| if (std.mem.eql(u8, previous, input)) return error.Usage;
            self.inputs[self.input_count] = input;
            self.input_count += 1;
            return true;
        }
        if (std.mem.eql(u8, arg, "--evaluation-request")) {
            if (self.command != .@"eval-project" or self.evaluation_request or self.evaluation_report) return error.Usage;
            self.evaluation_request = true;
            return true;
        }
        if (std.mem.eql(u8, arg, "--evaluation-report")) {
            if (self.command != .@"eval-project" or self.evaluation_report or self.evaluation_request) return error.Usage;
            self.evaluation_report = true;
            return true;
        }
        if (std.mem.startsWith(u8, arg, "--max-eval-bytes=")) {
            if (self.command != .@"eval-project" or self.saw_eval_bytes) return error.Usage;
            self.saw_eval_bytes = true;
            self.evaluation.max_bytes = std.math.cast(usize, try positive(arg["--max-eval-bytes=".len..])) orelse return error.Usage;
            return true;
        }
        return false;
    }

    fn qualityOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        inline for (.{
            "max_function_lines",
            "max_parameters",
            "max_nesting",
            "max_decisions",
            "max_line_bytes",
        }, .{
            "--max-function-lines=",
            "--max-parameters=",
            "--max-nesting=",
            "--max-decisions=",
            "--max-line-bytes=",
        }, 0..) |field, prefix, index| {
            if (std.mem.startsWith(u8, arg, prefix)) {
                const bit: u8 = 1 << index;
                if ((self.command != .@"report-quality" and self.command != .@"report-project-quality") or self.quality_seen & bit != 0) return error.Usage;
                self.quality_seen |= bit;
                const digits = arg[prefix.len..];
                if (digits.len == 0) return error.Usage;
                for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                    return error.Usage;
                };
                @field(self.quality, field) = std.fmt.parseUnsigned(usize, digits, 10) catch return error.Usage;
                return true;
            }
        }
        return false;
    }

    fn executionOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, arg, "--check")) {
            if ((self.command != .fmt and self.command != .@"fmt-module" and self.command != .@"fmt-project") or self.format_check) return error.Usage;
            self.format_check = true;
        } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
            if ((self.command != .run and self.command != .@"run-project" and self.command != .@"eval-project") or self.saw_steps) return error.Usage;
            self.saw_steps = true;
            const digits = arg["--max-steps=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            self.options.max_steps = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (self.options.max_steps == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--max-frames=")) {
            if ((self.command != .run and self.command != .@"run-project" and self.command != .@"eval-project") or self.saw_frames) return error.Usage;
            self.saw_frames = true;
            const digits = arg["--max-frames=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            self.options.max_frames = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (self.options.max_frames == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--memory=")) {
            if ((self.command != .run and self.command != .@"run-project") or self.saw_memory) return error.Usage;
            self.saw_memory = true;
            self.options.memory.backing = std.meta.stringToEnum(language.vm.MemoryBacking, arg["--memory=".len..]) orelse return error.Usage;
        } else return false;
        return true;
    }

    fn discoveryOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.startsWith(u8, arg, "--min-nodes=")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.saw_min) return error.Usage;
            self.saw_min = true;
            self.discovery.min_nodes = std.math.cast(usize, try positive(arg["--min-nodes=".len..])) orelse return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--population=")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.saw_population) return error.Usage;
            self.saw_population = true;
            self.discovery.population = std.meta.stringToEnum(language.duplicates.Population, arg["--population=".len..]) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--approximate")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.discovery.approximate) return error.Usage;
            self.discovery.approximate = true;
        } else if (std.mem.startsWith(u8, arg, "--max-work=")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.saw_work) return error.Usage;
            self.saw_work = true;
            self.discovery.near_options.max_work = std.math.cast(usize, try positive(arg["--max-work=".len..])) orelse return error.Usage;
        } else if (std.mem.eql(u8, arg, "--timings")) {
            if ((self.command != .@"discover-duplicates" and self.command != .@"discover-project-duplicates") or self.reporting.timings) return error.Usage;
            self.reporting.timings = true;
        } else return false;
        return true;
    }
    fn finish(self: *ArgumentParser) error{Usage}!Parsed {
        if (self.saw_work and !self.discovery.approximate) return error.Usage;
        if (self.command == .@"fmt-project" and !self.format_check) return error.Usage;
        if (self.command == .@"check-policy" and self.policy == null) return error.Usage;
        if ((self.command == .@"check-value-project" or self.command == .@"invoke-project") and self.value_path == null) return error.Usage;
        return .{
            .codec = self.codec,
            .schema_report = self.schema_report,
            .value_path = self.value_path,
            .inputs = self.inputs,
            .input_count = self.input_count,
            .evaluation_request = self.evaluation_request,
            .evaluation_report = self.evaluation_report,
            .evaluation = .{
                .max_steps = self.options.max_steps,
                .max_frames = self.options.max_frames,
                .max_bytes = self.evaluation.max_bytes,
            },
            .policy = self.policy,
            .format_check = self.format_check,
            .quality = self.quality,
            .command = self.command,
            .path = self.path orelse return error.Usage,
            .options = self.options,
            .discovery = self.discovery,
            .reporting = self.reporting,
        };
    }
};

fn positive(digits: []const u8) error{Usage}!u64 {
    if (digits.len == 0) return error.Usage;
    for (digits) |ch| if (!std.ascii.isDigit(ch)) {
        return error.Usage;
    };
    const value = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
    if (value == 0) return error.Usage;
    return value;
}

const GeneratedInput = struct { module: []const u8, path: []const u8, source: []const u8, manifest_path: []const u8, manifest_sha256: []const u8 };
const ModuleFiles = struct {
    io: std.Io,
    root: []const u8,
    inputs: []const GeneratedInput = &.{},
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *ModuleFiles = @ptrCast(@alignCast(context.?));
        for (self.inputs) |input| if (std.mem.eql(u8, input.path, relative)) {
            if (input.source.len > limit) return error.TooLarge;
            return allocator.dupe(u8, input.source);
        };
        var files: language.project_files.Files = .{ .io = self.io, .root = self.root };
        return language.project_files.Files.read(&files, allocator, relative, limit);
    }
};
fn listModules(init: Context, parsed: Parsed) !u8 {
    return listModulesWithCache(init, parsed, null, null);
}
fn listModulesWithCache(init: Context, parsed: Parsed, cache: ?*language.syntax_cache.Cache, verdict: ?*language.check_cache.Cache) !u8 {
    const frontend_start = if (parsed.reporting.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    const path = parsed.path;
    const basename = std.fs.path.basename(path);
    if (!validEntryBasename(basename)) {
        try init.text("list-modules: entry must be an identifier.my file; imports resolve beneath its directory\n");
        return 2;
    }
    var files: ModuleFiles = .{ .io = init.io, .root = std.fs.path.dirname(path) orelse "." };
    files.inputs = (try prepareInputs(init, parsed, basename)) orelse return 2;
    var project = language.project.Project.init(init.gpa);
    defer project.deinit();
    if (try loadModules(init, &project, &files, basename)) |status| return status;
    if (parsed.command == .@"fmt-project") return formatProject(init, &project);
    if (try replayCheck(init, parsed.command, &project, verdict)) return 0;
    const output = if (parsed.command != .@"list-modules") result: {
        var index = (try buildIndex(init, &project, cache)) orelse return 1;
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
        if (parsed.command == .@"project-dependencies") break :result try dependencyReport(init, &compilation, files.inputs);
        if (parsed.command == .@"check-project") return rememberCheck(verdict, &project, &compilation);
        if (parsed.command == .@"check-value-project" or parsed.command == .@"invoke-project") break :result (try checkValue(init, &compilation, parsed.value_path.?, parsed.codec, parsed.command == .@"invoke-project")) orelse return 1;
        if (parsed.command == .@"schema-project") break :result if (parsed.schema_report)
            try language.schema_report.render(init.gpa, &compilation, try compilerIdentity(init.io))
        else
            try language.schema.render(init.gpa, &compilation);
        if (parsed.command == .@"report-project-quality") {
            const roots = try compilation.exportRoots(init.gpa);
            defer init.gpa.free(roots);
            var analysis = try language.quality.analyzeWithExports(init.gpa, compilation.program.?, compilation.src, parsed.quality, roots);
            defer analysis.deinit();
            break :result try language.quality.render(init.gpa, analysis, compilation.program.?, compilation.src);
        }
        if (parsed.command == .@"discover-project-duplicates") return discoverProject(init, parsed, &project, &compilation, frontend_start);
        if (parsed.command == .@"check-policy") return checkProjectPolicy(init, parsed, &project);
        try compilation.emit();
        if (parsed.evaluation_request) break :result (try evaluationRequest(init, parsed, &project, &compilation)) orelse return 1;
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
                if (parsed.evaluation_report) break :result try language.evaluation_report.render(init.gpa, &project, value, parsed.evaluation, try compilerIdentity(init.io));
                break :result try std.fmt.allocPrint(init.gpa, "{d}\n", .{value});
            },
            .trap => |trap| {
                const message = try diagnostic_output.render(init.gpa, trap, compilation.src, init.diagnostics);
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

fn loadModules(init: Context, project: *language.project.Project, files: *ModuleFiles, basename: []const u8) !?u8 {
    project.load(.{ .context = files, .read = ModuleFiles.read }, basename[0 .. basename.len - 3], .{}) catch |err| switch (err) {
        error.SourceError => {
            const message = try diagnostic_output.renderProject(init.gpa, project, init.diagnostics);
            defer init.gpa.free(message);
            try std.Io.File.stderr().writeStreamingAll(init.io, message);
            return 1;
        },
        else => return err,
    };
    if (!try checkImportedInputs(init, files.inputs, project)) return 2;
    return null;
}

fn buildIndex(init: Context, project: *language.project.Project, cache: ?*language.syntax_cache.Cache) !?language.interfaces.Index {
    return language.interfaces.buildWithCache(project, cache) catch |err| switch (err) {
        error.SourceError => {
            const message = try diagnostic_output.renderProject(init.gpa, project, init.diagnostics);
            defer init.gpa.free(message);
            try std.Io.File.stderr().writeStreamingAll(init.io, message);
            return null;
        },
        else => return err,
    };
}

fn rememberCheck(verdict: ?*language.check_cache.Cache, project: *const language.project.Project, compilation: *const language.project_compile.Compilation) !u8 {
    if (verdict) |saved| try saved.remember(project, compilation.src, compilation.diagnostics.items.items);
    return 0;
}

fn replayCheck(init: Context, command: Command, project: *const language.project.Project, verdict: ?*language.check_cache.Cache) !bool {
    if (command != .@"check-project") return false;
    const cache = verdict orelse return false;
    const warnings = cache.lookup(project) orelse return false;
    try std.Io.File.stderr().writeStreamingAll(init.io, warnings);
    return true;
}

fn reportProject(init: Context, compilation: *language.project_compile.Compilation) !void {
    for (compilation.diagnostics.items.items) |problem| {
        const message = try diagnostic_output.render(init.gpa, problem, compilation.src, init.diagnostics);
        defer init.gpa.free(message);
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
    }
}

fn compilerIdentity(io: std.Io) !language.evaluation_report.Identity {
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

fn parseInputManifest(init: Context, path: []const u8, bytes: []const u8) !?language.input_manifest.Manifest {
    return language.input_manifest.Manifest.parse(init.gpa, bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        const message = try std.fmt.allocPrint(init.gpa, "{s}: invalid input manifest: {s}\n", .{ path, @errorName(err) });
        defer init.gpa.free(message);
        try init.text(message);
        return null;
    };
}

fn valueFailure(init: Context, path: []const u8, err: anyerror, location: ?*const language.typed_json.Location, invocation: bool) !?[]u8 {
    const pointer = if (location) |at| (if (at.has_path) try std.json.Stringify.valueAlloc(init.gpa, at.text(), .{}) else null) else null;
    defer if (pointer) |text| init.gpa.free(text);
    const detail = if (pointer) |text| try std.fmt.allocPrint(init.gpa, " at JSON pointer {s}{s}", .{ text, if (location.?.truncated) " (path truncated)" else "" }) else try init.gpa.dupe(u8, "");
    defer init.gpa.free(detail);
    const message = try std.fmt.allocPrint(init.gpa, "{s}: invalid {s}: {s}{s}\n", .{ path, if (invocation) "invocation" else "typed JSON", @errorName(err), detail });
    defer init.gpa.free(message);
    try init.text(message);
    return null;
}
fn checkValue(init: Context, compilation: *language.project_compile.Compilation, path: []const u8, options: language.codec_json.Options, invocation: bool) !?[]u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(options.json.max_bytes + 1)) catch |err| {
        if (err == error.StreamTooLong) return valueFailure(init, path, error.CodecByteLimit, null, invocation);
        return err;
    };
    defer init.gpa.free(bytes);
    var failure: language.codec_json.Failure = .{};
    defer failure.deinit(init.gpa);
    return (if (invocation) language.codec_json.invokeProject(init.gpa, compilation, bytes, options, &failure) else language.codec_json.canonicalProject(init.gpa, compilation, bytes, options, &failure)) catch |err| {
        if (err == error.OutOfMemory) return err;
        _ = try valueFailure(init, path, err, &failure.location, invocation);
        if (failure.execution.trap) |trap| {
            const rendered = try diagnostic_output.render(init.gpa, trap, compilation.src, init.diagnostics);
            defer init.gpa.free(rendered);
            try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
        }
        if (failure.execution.rejection) |rejection| {
            const rendered = language.typed_json.encode(init.gpa, compilation.program.?.records, rejection.typeOf(), rejection, options.json) catch |render_error| {
                if (render_error == error.OutOfMemory) return render_error;
                try init.text("codec error payload exceeds diagnostic serialization limits\n");
                return null;
            };
            defer init.gpa.free(rendered);
            const message = try std.fmt.allocPrint(init.gpa, "codec rejection: {s}\n", .{rendered});
            defer init.gpa.free(message);
            try init.text(message);
        }
        return null;
    };
}

fn formatProject(init: Context, project: *language.project.Project) !u8 {
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
        try init.text(message);
    }
    return if (changed.items.len == 0) 0 else 1;
}

fn discoverProject(init: Context, parsed: Parsed, project: *language.project.Project, compilation: *language.project_compile.Compilation, frontend_start: std.Io.Timestamp) !u8 {
    const start = std.Io.Timestamp.now(init.io, .awake);
    var analysis = try language.duplicates.discover(init.gpa, compilation.program.?, parsed.discovery);
    defer analysis.deinit();
    const discovery_ns = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
    const text = try language.duplicates.render(init.gpa, analysis, compilation.program.?, compilation.src);
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "scope: reachable module graph; declaration visibility and dependency policy require separate review\n");
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    if (parsed.reporting.timings) {
        const counts = try std.fmt.allocPrint(init.gpa, "timings: project_frontend_ns={d} discovery_ns={d} modules={d} source_bytes={d} " ++
            "ast_nodes={d} typed_nodes={d} canonical_bytes={d} functions={d}" ++
            "\n", .{
            frontend_start.durationTo(start).nanoseconds,
            discovery_ns,
            project.modules.items.len,
            project.counts.bytes,
            compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len,
            compilation.program.?.nodes.len + compilation.program.?.statements.len,
            analysis.canonical_bytes,
            analysis.functions_examined,
        });
        defer init.gpa.free(counts);
        try init.text(counts);
    }
    return 0;
}

fn checkProjectPolicy(init: Context, parsed: Parsed, project: *language.project.Project) !u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.policy.?, init.gpa, .limited(1024 * 1024));
    defer init.gpa.free(bytes);
    var policy = language.import_policy.Policy.parse(init.gpa, bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        const message = try std.fmt.allocPrint(init.gpa, "{s}: invalid import policy: {s}\n", .{ parsed.policy.?, @errorName(err) });
        defer init.gpa.free(message);
        try init.text(message);
        return 2;
    };
    defer policy.deinit();
    var policy_report = try language.import_policy.evaluate(init.gpa, project, policy);
    defer policy_report.deinit();
    const text = try language.import_policy.render(init.gpa, policy_report, project, policy);
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "language: valid\n");
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return if (policy_report.denied == 0) 0 else 3;
}

fn prepareInputs(init: Context, parsed: Parsed, basename: []const u8) !?[]GeneratedInput {
    const input_allocator = init.arena.allocator();
    var generated_inputs: std.ArrayList(GeneratedInput) = .empty;
    defer generated_inputs.deinit(input_allocator);
    var manifest_bytes: usize = 0;
    for (parsed.inputs[0..parsed.input_count]) |manifest_path| {
        // This Zig snapshot rejects reads that reach the supplied limit.
        // Add one so the documented manifest byte budgets are inclusive.
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, manifest_path, init.gpa, .limited(@min(1024 * 1024, 8 * 1024 * 1024 - manifest_bytes) + 1)) catch |err| switch (err) {
            error.StreamTooLong => {
                try init.text("input manifest byte budget exceeded (1 MiB per file, 8 MiB combined)\n");
                return null;
            },
            else => return err,
        };
        manifest_bytes += bytes.len;
        defer init.gpa.free(bytes);
        var manifest = (try parseInputManifest(init, manifest_path, bytes)) orelse return null;
        defer manifest.deinit();
        const module = manifest.parsed.value.module;
        if (std.mem.eql(u8, module, basename[0 .. basename.len - 3])) {
            try init.text("input manifest must supply an imported module, not the entry module\n");
            return null;
        }
        for (generated_inputs.items) |previous| if (std.mem.eql(u8, previous.module, module)) {
            const message = try std.fmt.allocPrint(init.gpa, "{s}: duplicate input module {s}; already supplied by {s}\n", .{ manifest_path, module, previous.manifest_path });
            defer init.gpa.free(message);
            try init.text(message);
            return null;
        };
        try generated_inputs.append(input_allocator, .{
            .module = try input_allocator.dupe(u8, module),
            .path = try language.project.modulePath(input_allocator, module),
            .source = try manifest.generate(input_allocator),
            .manifest_path = manifest_path,
            .manifest_sha256 = try language.dependency_report.hashBytes(input_allocator, bytes),
        });
    }
    const inputs = try generated_inputs.toOwnedSlice(input_allocator);
    return inputs;
}

fn dependencyReport(init: Context, compilation: *language.project_compile.Compilation, inputs: []const GeneratedInput) ![]u8 {
    const manifests = try init.gpa.alloc(language.dependency_report.Manifest, inputs.len);
    defer init.gpa.free(manifests);
    for (manifests, inputs) |*manifest, input| manifest.* = .{ .module = input.module, .path = input.manifest_path, .sha256 = input.manifest_sha256 };
    return language.dependency_report.render(init.gpa, compilation, try compilerIdentity(init.io), manifests);
}

fn evaluationRequest(init: Context, parsed: Parsed, project: *language.project.Project, compilation: *language.project_compile.Compilation) !?[]u8 {
    const failure = language.evaluation.preflight(init.gpa, compilation.code.?, &compilation.diagnostics, parsed.evaluation) catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return null;
        },
        else => return err,
    };
    try reportProject(init, compilation);
    if (failure) |trap| {
        const message = try diagnostic_output.render(init.gpa, trap, compilation.src, init.diagnostics);
        defer init.gpa.free(message);
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return null;
    }
    const report_text = try language.evaluation_report.renderRequest(init.gpa, project, parsed.evaluation, try compilerIdentity(init.io));
    return report_text;
}

fn checkImportedInputs(init: Context, inputs: []const GeneratedInput, project: *const language.project.Project) !bool {
    for (inputs) |input| if (!project.names.contains(input.module)) {
        const message = try std.fmt.allocPrint(init.gpa, "{s}: declared input module {s} is not imported by the reachable project\n", .{ input.manifest_path, input.module });
        defer init.gpa.free(message);
        try init.text(message);
        return false;
    };
    return true;
}

fn validEntryBasename(basename: []const u8) bool {
    if (!std.mem.endsWith(u8, basename, ".my")) return false;
    const name = basename[0 .. basename.len - 3];
    if (!language.project.validName(name)) return false;
    return std.mem.indexOfScalar(u8, name, '.') == null;
}

const SessionCache = struct { syntax: language.syntax_cache.Cache, semantic: language.check_cache.Cache };
fn checkSession(init: Context, parsed: Parsed) !u8 {
    if (!validEntryBasename(std.fs.path.basename(parsed.path))) {
        try init.text("check-session: entry must be an identifier.my file\n");
        return 2;
    }
    var cache: SessionCache = .{
        .syntax = language.syntax_cache.Cache.init(init.gpa, .{}),
        .semantic = language.check_cache.Cache.init(init.gpa, 16 * 1024 * 1024),
    };
    defer cache.syntax.deinit();
    defer cache.semantic.deinit();
    cache.semantic.format = init.diagnostics;
    var buffer: [256]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    while (true) {
        const line = input.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try sessionReply(init, "invalid", 2, "RequestTooLong", cache.syntax.statistics, &cache);
                return 2;
            },
            else => return err,
        } orelse return 0;
        if (line.len > 128) {
            try sessionReply(init, "invalid", 2, "RequestTooLong", cache.syntax.statistics, &cache);
            return 2;
        }
        const action = std.mem.trim(u8, line, " \t\r");
        const before = cache.syntax.statistics;
        if (std.mem.eql(u8, action, "quit")) {
            try sessionReply(init, "quit", 0, null, before, &cache);
            return 0;
        }
        if (std.mem.eql(u8, action, "clear")) {
            cache.syntax.clear();
            cache.semantic.clear();
            try sessionReply(init, "clear", 0, null, before, &cache);
        } else if (std.mem.eql(u8, action, "check")) {
            try sessionCheck(init, parsed, &cache);
        } else {
            try sessionReply(init, "invalid", 2, "UnknownSessionCommand", before, &cache);
        }
    }
}
fn sessionCheck(init: Context, parsed: Parsed, cache: *SessionCache) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    var request_init = init;
    request_init.arena = &arena;
    var request = parsed;
    request.command = .@"check-project";
    const before = cache.syntax.statistics;
    const status = listModulesWithCache(request_init, request, &cache.syntax, &cache.semantic) catch |err| {
        try sessionReply(init, "check", 2, @errorName(err), before, cache);
        return;
    };
    try sessionReply(init, "check", status, null, before, cache);
}
fn sessionReply(init: Context, action: []const u8, status: u8, failure: ?[]const u8, before: language.syntax_cache.Statistics, cache: *const SessionCache) !void {
    const text = try std.json.Stringify.valueAlloc(init.gpa, .{
        .version = "check-session-v1",
        .action = action,
        .status = status,
        .failure = failure,
        .reuse = .{ .hits = cache.syntax.statistics.hits - before.hits, .misses = cache.syntax.statistics.misses - before.misses },
        .cache = cache.syntax.statistics,
        .semantic = cache.semantic.statistics,
    }, .{});
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
