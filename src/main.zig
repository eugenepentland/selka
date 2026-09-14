//! Host I/O and process policy stay outside the compiler and VM.
const lowering_phase = "bytecode_lowering";
const inputs_prefix = "--inputs=";
const policy_prefix = "--policy=";
const std = @import("std");
const language = @import("mylang");
const diagnostic_output = language.diagnostic_output;
const Reporting = struct { print_result: bool = false, timings: bool = false, timings_json: bool = false, diagnostics: ?diagnostic_output.Format = null };
const usage = "usage: mylang test <entry.my> [--filter GLOB] [--cases FILE] [--json] [--force]\n       mylang build <file.my> (-o <output> | --run) [--help]\n" ++
    "       mylang doc-coverage [<repo-root>] (every implemented feature and standard export needs a documented example)\n       mylang " ++
    "<schema-project|input-module|check|run|dump-bytecode|di" ++
    "scover-duplicates|discover-project-duplicates|report-project-quality|report-quality|fmt|fm" ++
    "t-module|fmt-project|emit-qbe|emit-project-qbe|list-modules|list-interfaces|list-" ++
    "declarations|check" ++
    "-project|run-project|check-policy> <file.my>\n  schema-project: --schema-report (include " ++
    "checked source and compiler identities)\n  " ++
    "input-module: reads a typed JSON manifest and writes generated " ++
    "module source\n  run/run-project: --max-steps=N --max-frames=N --dispatch=optimized|generic --gc-stress " ++
    "--print-result\n  " ++
    "run/run-project authority: every capability is granted by default; --restrict denies them " ++
    "and enables --allow-read=DIR --allow-write=DIR (repeatable) --allow-clock --allow-random[=SEED] " ++
    "--allow-env[=NAME,...] --allow-all. Under --restrict an entry point requesting an ungranted " ++
    "capability exits 2 before execution; --allow-random=SEED pins the seed in either mode\n  " ++
    "run: --timings (VM execution nanoseconds on stderr; excludes source compilation)\n  " ++
    "schema-project: --inputs=manifest.json (repeat for up to 16 modules)\n  " ++
    "discover-duplicates/discover-project-duplicates: --min-nodes=N " ++
    "--population=production|tests|generated|reference|intentional --timings --approximate " ++
    "--max-work=N\n  report-quality/report-project-quality: --max-function-lines=N " ++
    "--max-parameters=N --max-nesting=N --max-decisions=N --max-line-bytes=N (0 disables a " ++
    "signal)\n  check-policy: --policy=path.json (required; policy failures exit 3)\n  " ++
    "fmt-project: --check (required; checks the reachable import graph)\n  fmt/fmt-module: " ++
    "--check (otherwise writes formatted source to " ++
    "stdout)\n" ++
    "  list-declarations: parse-only declarations-v1 JSON with byte ranges\n" ++
    "  index-project: JSON symbols, references and pinned source snapshot\n  project-dependencies: checked module graph and hashes; --inputs supported\n" ++
    "  one-shot commands: --timings=json (phase-timings-v1 JSON Lines on stderr)\n" ++
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

const grants = @import("cli_grants.zig");
const Context = struct {
    gpa: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    diagnostics: diagnostic_output.Format,
    timings: *language.timings.Profile,
    fn text(self: Context, bytes: []const u8) !void {
        if (self.diagnostics == .text) return std.Io.File.stderr().writeStreamingAll(self.io, bytes);
        const rendered = try diagnostic_output.message(self.gpa, bytes, self.diagnostics);
        defer self.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(self.io, rendered);
    }
};
fn dispatch(process: std.process.Init) !u8 {
    const args = try process.minimal.args.toSlice(process.arena.allocator());
    if (args.len == 2 and std.mem.eql(u8, args[1], "--features")) {
        try featureReport(process);
        return 0;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "build")) return @import("qbe_build.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "test")) return @import("native_test_command.zig").run(process, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "doc-coverage")) return @import("doc_coverage_command.zig").run(process, args[2..]);
    const parsed = parseArgs(args[1..]) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    var timings = language.timings.Profile.init(process.io, parsed.reporting.timings_json, .compiler);
    const init: Context = .{ .timings = &timings, .gpa = process.gpa, .arena = process.arena, .io = process.io, .environ = process.environ_map, .diagnostics = parsed.reporting.diagnostics orelse .text };
    const status = run(init, parsed) catch |err| status: {
        const message = try std.fmt.allocPrint(init.gpa, "mylang: host failure: {s}\n", .{@errorName(err)});
        defer init.gpa.free(message);
        try init.text(message);
        break :status @as(u8, 2);
    };
    try timings.report(status);
    return status;
}
fn run(init: Context, parsed: Parsed) !u8 {
    const allocator = init.gpa;
    if (parsed.command == .@"check-session") return checkSession(init, parsed);
    switch (parsed.command) {
        .@"index-project",
        .@"project-dependencies",
        .@"check-session",
        .@"schema-project",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"run-project",
        .@"check-policy",
        .@"discover-project-duplicates",
        .@"report-project-quality",
        .@"fmt-project",
        .@"emit-project-qbe",
        => return listModules(init, parsed),
        else => {},
    }
    init.timings.begin("source_load", false);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, parsed.path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(bytes);
    init.timings.counts.source_bytes = bytes.len;
    init.timings.counts.modules = 1;
    init.timings.end();
    if (parsed.command == .@"input-module") {
        var manifest = (try parseInputManifest(init, parsed.path, bytes)) orelse return 2;
        defer manifest.deinit();
        const generated = try manifest.generate(allocator);
        defer allocator.free(generated);
        try std.Io.File.stdout().writeStreamingAll(init.io, generated);
        return 0;
    }
    init.timings.begin("frontend", false);
    var compilation = try language.Compilation.init(allocator, parsed.path, bytes);
    defer compilation.deinit();
    if (parsed.command == .fmt or parsed.command == .@"fmt-module") {
        init.timings.begin("format_inclusive", true);
        const formatted = (if (parsed.command == .@"fmt-module") compilation.formatModule(allocator) else compilation.format(allocator)) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            else => return err,
        };
        init.timings.end();
        defer allocator.free(formatted);
        if (parsed.format_check) {
            if (std.mem.eql(u8, formatted, bytes)) return 0;
            try init.text("formatting differs\n");
            return 1;
        }
        try std.Io.File.stdout().writeStreamingAll(init.io, formatted);
        return 0;
    }
    if (parsed.command == .@"list-declarations") {
        init.timings.begin("declaration_listing", true);
        const listing = compilation.listDeclarations(allocator) catch |err| switch (err) {
            error.SourceError => {
                try report(init, &compilation);
                return 1;
            },
            else => return err,
        };
        init.timings.end();
        defer allocator.free(listing);
        try std.Io.File.stdout().writeStreamingAll(init.io, listing);
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
    init.timings.counts.ast_nodes = compilation.syntax.?.nodes.items.len + compilation.syntax.?.statements.items.len;
    init.timings.counts.typed_nodes = compilation.program.?.nodes.len + compilation.program.?.statements.len;
    init.timings.end();
    const check_ns = if (parsed.reporting.timings) check_start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds else 0;
    if (parsed.command != .@"emit-qbe") try report(init, &compilation);
    switch (parsed.command) {
        .@"index-project",
        .@"project-dependencies",
        .@"check-session",
        .@"schema-project",
        .@"input-module",
        .fmt,
        .@"fmt-module",
        .@"fmt-project",
        .@"list-declarations",
        .@"emit-project-qbe",
        .@"list-modules",
        .@"list-interfaces",
        .@"check-project",
        .@"run-project",
        .@"check-policy",
        .@"discover-project-duplicates",
        .@"report-project-quality",
        => unreachable,
        .@"emit-qbe" => {
            const generated = emitMeasuredNative(init, &compilation) catch |err| switch (err) {
                error.SourceError => {
                    try report(init, &compilation);
                    return 1;
                },
                else => return err,
            };
            init.timings.end();
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
            init.timings.begin("discovery", false);
            var analysis = try language.duplicates.discover(allocator, compilation.program.?, parsed.discovery);
            init.timings.end();
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
            init.timings.begin("bytecode_dump_inclusive", true);
            const text = try compilation.dump(allocator);
            init.timings.end();
            defer allocator.free(text);
            try std.Io.File.stdout().writeStreamingAll(init.io, text);
        },
        .run => switch ((try executeRun(init, &compilation, parsed)) orelse return 2) {
            .value => |value| {
                if (!parsed.reporting.print_result) return 0;
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

/// Report the flag that would grant an entry point the authority it asked for.
/// Only `--restrict` can withhold one, so the message names the active mode.
fn reportUngranted(init: Context, flag: []const u8) !u8 {
    const message = try std.fmt.allocPrint(
        init.gpa,
        "mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass {s}, or drop --restrict to grant every capability\n",
        .{flag},
    );
    defer init.gpa.free(message);
    try init.text(message);
    return 2;
}

fn executeRun(init: Context, compilation: *language.Compilation, parsed: Parsed) !?language.vm.Result {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    defer flushOutput(&stdout);
    init.timings.begin(lowering_phase, false);
    try compilation.emit();
    if (grants.ungranted(compilation.code.?, parsed.grants)) |flag| {
        init.timings.end();
        _ = try reportUngranted(init, flag);
        return null;
    }
    var state: grants.State = undefined;
    try state.init(init.gpa, init.io, .{ .config = parsed.grants, .environ = init.environ });
    defer state.deinit();
    var options = state.apply(parsed.options);
    options.output = &stdout.interface;
    init.timings.begin("vm_execution", false);
    const start = std.Io.Timestamp.now(init.io, .awake);
    const result = try language.vm.runWithOptions(init.gpa, compilation.code.?, options);
    init.timings.end();
    if (!parsed.reporting.timings) return result;
    const elapsed = start.durationTo(std.Io.Timestamp.now(init.io, .awake)).nanoseconds;
    var timing_buffer: [96]u8 = undefined;
    const text = try std.fmt.bufPrint(&timing_buffer, "timings: bytecode_ns={d}\n", .{elapsed});
    try init.text(text);
    return result;
}

fn report(init: Context, compilation: *const language.Compilation) !void {
    for (compilation.diagnostics.items) |diagnostic| {
        const rendered = try diagnostic_output.render(init.gpa, diagnostic, compilation.src, init.diagnostics);
        defer init.gpa.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(init.io, rendered);
    }
}

const Command = enum {
    @"index-project",
    @"project-dependencies",
    @"check-session",
    @"schema-project",
    @"input-module",
    @"emit-project-qbe",
    @"fmt-project",
    @"fmt-module",
    @"report-project-quality",
    @"discover-project-duplicates",
    @"check-policy",
    @"check-project",
    @"run-project",
    @"list-interfaces",
    @"list-modules",
    @"emit-qbe",
    @"list-declarations",
    fmt,
    check,
    run,
    @"dump-bytecode",
    @"discover-duplicates",
    @"report-quality",
};
const Parsed = struct {
    schema_report: bool,
    inputs: [16][]const u8,
    input_count: usize,
    policy: ?[]const u8,
    format_check: bool,
    write: bool,
    quality: language.quality.Options,
    command: Command,
    path: []const u8,
    grants: grants.Config,
    options: language.vm.Options,
    discovery: language.duplicates.Options,
    reporting: Reporting,
};
fn parseArgs(args: []const []const u8) error{Usage}!Parsed {
    if (args.len < 2) return error.Usage;
    const command = std.meta.stringToEnum(Command, args[0]) orelse return error.Usage;
    var parser: ArgumentParser = .{ .command = command };
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--diagnostics=")) {
            if (parser.reporting.diagnostics != null) return error.Usage;
            parser.reporting.diagnostics = std.meta.stringToEnum(diagnostic_output.Format, arg["--diagnostics=".len..]) orelse return error.Usage;
            continue;
        }
        if (try parser.surfaceOption(arg)) continue;
        if (try parser.qualityOption(arg)) continue;
        if (try parser.grantOption(arg)) continue;
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
    schema_report: bool = false,
    inputs: [16][]const u8 = @splat(""),
    input_count: usize = 0,
    quality: language.quality.Options = .{},
    quality_seen: u8 = 0,
    format_check: bool = false,
    write: bool = false,
    path: ?[]const u8 = null,
    policy: ?[]const u8 = null,
    grants: grants.Config = .{},
    options: language.vm.Options = .{},
    saw_steps: bool = false,
    saw_frames: bool = false,
    saw_dispatch: bool = false,
    discovery: language.duplicates.Options = .{},
    reporting: Reporting = .{},
    saw_min: bool = false,
    saw_population: bool = false,
    saw_work: bool = false,
    fn surfaceOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, arg, "--schema-report")) {
            if (self.command != .@"schema-project" or self.schema_report) return error.Usage;
            self.schema_report = true;
            return true;
        }
        if (std.mem.startsWith(u8, arg, inputs_prefix)) {
            switch (self.command) {
                .@"schema-project", .@"check-session", .@"project-dependencies" => {},
                else => return error.Usage,
            }
            if (self.input_count == self.inputs.len or arg.len == inputs_prefix.len) return error.Usage;
            const input = arg[inputs_prefix.len..];
            for (self.inputs[0..self.input_count]) |previous| if (std.mem.eql(u8, previous, input)) return error.Usage;
            self.inputs[self.input_count] = input;
            self.input_count += 1;
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

    fn checks(self: *const ArgumentParser) bool {
        return switch (self.command) {
            .fmt, .@"fmt-module", .@"fmt-project" => true,
            else => false,
        };
    }
    /// Authority options apply only to the commands that execute a program.
    fn grantOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (!std.mem.startsWith(u8, arg, "--allow-") and !std.mem.eql(u8, arg, grants.restrict_flag)) return false;
        if (self.command != .run and self.command != .@"run-project") return error.Usage;
        if (!try self.grants.parse(arg)) return error.Usage;
        return true;
    }
    fn executionOption(self: *ArgumentParser, arg: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, arg, "--check")) {
            if (!self.checks() or self.format_check) return error.Usage;
            self.format_check = true;
        } else if (std.mem.eql(u8, arg, "--gc-stress")) {
            if (self.command != .run and self.command != .@"run-project") return error.Usage;
            if (self.options.memory.gc.stress) return error.Usage;
            self.options.memory.gc.stress = true;
        } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
            if ((self.command != .run and self.command != .@"run-project") or self.saw_steps) return error.Usage;
            self.saw_steps = true;
            const digits = arg["--max-steps=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            self.options.max_steps = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (self.options.max_steps == 0) return error.Usage;
        } else if (std.mem.startsWith(u8, arg, "--max-frames=")) {
            if ((self.command != .run and self.command != .@"run-project") or self.saw_frames) return error.Usage;
            self.saw_frames = true;
            const digits = arg["--max-frames=".len..];
            if (digits.len == 0) return error.Usage;
            for (digits) |ch| if (!std.ascii.isDigit(ch)) {
                return error.Usage;
            };
            self.options.max_frames = std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            if (self.options.max_frames == 0) return error.Usage;
        } else if (std.mem.eql(u8, arg, "--print-result")) {
            if ((self.command != .run and self.command != .@"run-project") or self.reporting.print_result) return error.Usage;
            self.reporting.print_result = true;
        } else if (std.mem.eql(u8, arg, "--print-result")) {
            if ((self.command != .run and self.command != .@"run-project") or self.reporting.print_result) return error.Usage;
            self.reporting.print_result = true;
        } else if (std.mem.startsWith(u8, arg, "--dispatch=")) {
            if ((self.command != .run and self.command != .@"run-project") or self.saw_dispatch) return error.Usage;
            self.saw_dispatch = true;
            const mode = arg["--dispatch=".len..];
            self.options.memory.optimize_dispatch = if (std.mem.eql(u8, mode, "optimized")) true else if (std.mem.eql(u8, mode, "generic")) false else return error.Usage;
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
        } else if (std.mem.eql(u8, arg, "--timings=json")) {
            if (self.command == .@"check-session" or self.reporting.timings or self.reporting.timings_json) return error.Usage;
            self.reporting.timings_json = true;
        } else if (std.mem.eql(u8, arg, "--timings")) {
            const supported = self.command == .run or self.command == .@"discover-duplicates" or self.command == .@"discover-project-duplicates";
            if (!supported or self.reporting.timings or self.reporting.timings_json) return error.Usage;
            self.reporting.timings = true;
        } else return false;
        return true;
    }
    fn finish(self: *ArgumentParser) error{Usage}!Parsed {
        if (self.saw_work and !self.discovery.approximate) return error.Usage;
        if (self.command == .@"fmt-project" and !self.format_check) return error.Usage;
        if (self.command == .@"check-policy" and self.policy == null) return error.Usage;
        return .{
            .schema_report = self.schema_report,
            .inputs = self.inputs,
            .input_count = self.input_count,
            .policy = self.policy,
            .format_check = self.format_check,
            .write = self.write,
            .quality = self.quality,
            .command = self.command,
            .path = self.path orelse return error.Usage,
            .grants = self.grants,
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
    return listModulesWithCache(init, parsed, null, null, null);
}
fn listModulesWithCache(init: Context, parsed: Parsed, cache: ?*language.syntax_cache.Cache, verdict: ?*language.check_cache.Cache, functions: ?*language.semantic_cache.Cache) !u8 {
    const frontend_start = if (parsed.reporting.timings) std.Io.Timestamp.now(init.io, .awake) else std.Io.Timestamp.zero;
    const path = parsed.path;
    const basename = std.fs.path.basename(path);
    if (!validEntryBasename(basename)) {
        try init.text("list-modules: entry must be an identifier.my file; imports resolve beneath its directory\n");
        return 2;
    }
    init.timings.begin("source_load_parse", false);
    var files: ModuleFiles = .{ .io = init.io, .root = std.fs.path.dirname(path) orelse "." };
    files.inputs = (try prepareInputs(init, parsed, basename)) orelse return 2;
    var project = language.project.Project.init(init.gpa);
    defer project.deinit();
    if (try loadModules(init, &project, &files, basename)) |status| return status;
    init.timings.counts.modules = project.modules.items.len;
    init.timings.counts.source_bytes = project.counts.bytes;
    init.timings.end();
    if (try surfaceProject(init, &project, parsed)) |status| return status;
    if (try replayCheck(init, parsed.command, &project, verdict)) return 0;
    const output = if (parsed.command != .@"list-modules") result: {
        init.timings.begin("frontend", false);
        var index = (try buildIndex(init, &project, cache)) orelse return partialNavigation(init, &project, parsed.command);
        if (parsed.command == .@"list-interfaces") break :result try index.render(init.gpa);
        var compilation = try language.project_compile.Compilation.init(&index);
        if (parsed.command == .@"index-project") break :result try renderNavigation(init, &compilation);
        compilation.checkWithCache(functions) catch |err| switch (err) {
            error.SourceError => {
                try reportProject(init, &compilation);
                return 1;
            },
            else => return err,
        };
        init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
        init.timings.counts.typed_nodes = compilation.program.?.nodes.len + compilation.program.?.statements.len;
        init.timings.end();
        if (parsed.command == .@"emit-project-qbe") break :result (try emitProjectNative(init, &compilation)) orelse return 1;
        try reportProject(init, &compilation);
        if (parsed.command == .@"project-dependencies") break :result try dependencyReport(init, &compilation, files.inputs);
        if (parsed.command == .@"check-project") return rememberCheck(verdict, &project, &compilation);
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
        init.timings.begin(lowering_phase, false);
        try compilation.emit();
        init.timings.end();
        init.timings.begin("vm_execution", false);
        const outcome = (try runProjectProgram(init, compilation.code.?, parsed)) orelse return 2;
        init.timings.end();
        switch (outcome) {
            .value => |value| break :result (try entryOutcome(init, parsed, value)) orelse return 0,
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

/// Render the entry result when `--print-result` asks for it, and nothing otherwise.
fn entryOutcome(init: Context, parsed: Parsed, value: i64) !?[]u8 {
    if (!parsed.reporting.print_result) return null;
    const rendered = try std.fmt.allocPrint(init.gpa, "{d}\n", .{value});
    return rendered;
}

/// A refused final flush cannot be reported once the guest program has ended.
fn flushOutput(stdout: *std.Io.File.Writer) void {
    stdout.interface.flush() catch |err| switch (err) {
        error.WriteFailed => return,
    };
}

/// Stream guest `print` output to stdout and grant only the requested authority.
fn runProjectProgram(init: Context, code: language.bytecode.Program, parsed: Parsed) !?language.vm.Result {
    if (grants.ungranted(code, parsed.grants)) |flag| {
        _ = try reportUngranted(init, flag);
        return null;
    }
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    defer flushOutput(&stdout);
    var state: grants.State = undefined;
    try state.init(init.gpa, init.io, .{ .config = parsed.grants, .environ = init.environ });
    defer state.deinit();
    var options = state.apply(parsed.options);
    options.output = &stdout.interface;
    const outcome = try language.vm.runWithOptions(init.gpa, code, options);
    return outcome;
}

fn emitProjectNative(init: Context, compilation: *language.project_compile.Compilation) !?[]u8 {
    const generated = emitMeasuredNative(init, compilation) catch |err| switch (err) {
        error.SourceError => {
            try reportProject(init, compilation);
            return null;
        },
        else => return err,
    };
    init.timings.end();
    errdefer init.gpa.free(generated);
    try reportProject(init, compilation);
    return generated;
}

fn partialNavigation(init: Context, project: *language.project.Project, command: Command) !u8 {
    if (command != .@"index-project") return 1;
    const output = try language.navigation_partial.render(init.gpa, project, try compilerIdentity(init.io));
    defer init.gpa.free(output);
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    return 0;
}

fn renderNavigation(init: Context, compilation: *language.project_compile.Compilation) ![]u8 {
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    init.timings.counts.ast_nodes = compilation.syntax.nodes.items.len + compilation.syntax.statements.items.len;
    if (compilation.program) |program| init.timings.counts.typed_nodes = program.nodes.len + program.statements.len;
    init.timings.end();
    try reportProject(init, compilation);
    return language.navigation.render(init.gpa, compilation, try compilerIdentity(init.io), .{});
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

/// `compiler_sha256` is a build-time digest of the compiler's own source inputs, Zig
/// version and optimize mode, embedded by `build.zig`. Re-reading the installed
/// executable to hash it cost seconds per report on a Debug build and told receipts
/// nothing extra: two builds of the same sources share this identity, and any source,
/// toolchain or mode change still changes it.
fn compilerIdentity(io: std.Io) !language.source_receipt.Identity {
    _ = io;
    const builtin = @import("builtin");
    return .{ .compiler_sha256 = build_identity, .zig_version = builtin.zig_version_string, .architecture = @tagName(builtin.cpu.arch), .os = @tagName(builtin.os.tag), .abi = @tagName(builtin.abi), .optimize = @tagName(builtin.mode) };
}
const build_identity: [32]u8 = identity: {
    const text = @import("qbe_build_assets").compiler_identity;
    var decoded: [32]u8 = undefined;
    for (&decoded, 0..) |*byte, index| byte.* = nibble(text[index * 2]) << 4 | nibble(text[index * 2 + 1]);
    break :identity decoded;
};
fn nibble(character: u8) u8 {
    return if (character <= '9') character - '0' else character - 'a' + 10;
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

/// Dispatch the whole-graph source-surface commands that never lower or execute.
fn surfaceProject(init: Context, project: *language.project.Project, parsed: Parsed) !?u8 {
    if (parsed.command == .@"fmt-project") {
        const status = try formatProject(init, project);
        return status;
    }
    return null;
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
    init.timings.begin("discovery", false);
    var analysis = try language.duplicates.discover(init.gpa, compilation.program.?, parsed.discovery);
    init.timings.end();
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

const SessionCache = struct { syntax: language.syntax_cache.Cache, semantic: language.check_cache.Cache, functions: language.semantic_cache.Cache };
fn checkSession(init: Context, parsed: Parsed) !u8 {
    if (!validEntryBasename(std.fs.path.basename(parsed.path))) {
        try init.text("check-session: entry must be an identifier.my file\n");
        return 2;
    }
    var cache: SessionCache = .{
        .syntax = language.syntax_cache.Cache.init(init.gpa, .{}),
        .semantic = language.check_cache.Cache.init(init.gpa, 16 * 1024 * 1024),
        .functions = language.semantic_cache.Cache.init(init.gpa, 16 * 1024 * 1024),
    };
    defer cache.syntax.deinit();
    defer cache.semantic.deinit();
    defer cache.functions.deinit();
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
            cache.functions.clear();
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
    const status = listModulesWithCache(request_init, request, &cache.syntax, &cache.semantic, &cache.functions) catch |err| {
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
        .functions = cache.functions.statistics,
    }, .{});
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

/// Report the installed compiler identity and its versioned supported surface.
fn featureReport(init: std.process.Init) !void {
    const identity = try compilerIdentity(init.io);
    const manifest = try std.json.parseFromSlice(std.json.Value, init.gpa, @embedFile("features.json"), .{});
    defer manifest.deinit();
    const text = try std.json.Stringify.valueAlloc(init.gpa, .{
        .version = "language-features-v1",
        .compiler_sha256 = std.fmt.bytesToHex(identity.compiler_sha256, .lower),
        .zig_version = identity.zig_version,
        .features = manifest.value,
    }, .{});
    defer init.gpa.free(text);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

fn emitMeasuredNative(init: Context, compilation: anytype) ![]u8 {
    init.timings.begin(lowering_phase, false);
    try compilation.emit();
    init.timings.begin("native_emission", false);
    const generated = try compilation.emitQbe(init.gpa);
    init.timings.end();
    return generated;
}
