//! `selka-core`: the new compiler core's executable (decision N2). It imports
//! the existing front end as the `selka` Zig module and owns everything below
//! `typed.Program`: the Core IR, its facts, LLVM emission and the native build.
const std = @import("std");
const language = @import("selka");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const typed_dump = @import("typed_dump.zig");
const build = @import("build.zig");
const print = @import("print.zig");
const pipeline = @import("pipeline.zig");
const passes = @import("passes.zig");
const facts = @import("facts.zig");
const ir = @import("ir.zig");
const test_runner = @import("test_runner.zig");
const check_command = @import("check_command.zig");
const cli_run = @import("cli_run.zig");
const ownership_commands = @import("ownership_commands.zig");
const fact_commands = @import("fact_commands.zig");
const verify_ir_commands = @import("verify_ir_commands.zig");
const fact_mutate_command = @import("fact_mutate_command.zig");

/// The flag naming the build cache directory.
const cache_dir_flag = "--cache-dir";
const shared_cache_dir_flag = "--shared-cache-dir";

const usage =
    \\usage: selka build FILE.selka -o OUT [--release | --unoptimized | --optimize-debug | --debug-o0] [--link FILE.c]... [--emit-llvm PATH] [--emit-certificates DIR] [--no-facts | --verify-facts] [--stats] [--zig PATH] [--cache-dir DIR] [--verify-cache] [--cache-report]
    \\Default: lean debug (Core's facts passes, LLVM code generation at -O2 minus its costly passes); --debug-o0 selects LLVM -O0 (the cheapest cold build); --optimize-debug selects LLVM -O2; --unoptimized runs no Core pass.
    \\Checked ownership is the default: assignments move, parameters borrow, and copy(value) duplicates storage.
    \\       selka check FILE.selka [--typed] [--stats] [--timings=json] [--cache-dir DIR] [--no-cache]
    \\       selka test FILE.selka|DIR [options]   (`selka test` alone lists them)
    \\       selka coverage FILE.selka...   (one line per function: ok with its checks, or the refusal reason)
    \\       selka dump-typed FILE.selka [FUNCTION]
    \\       selka dump-ir FILE.selka [--facts | --certificate | --fact-certificate]   (--facts: after the release passes, with intervals; --certificate: the ownership certificates of the final IR; --fact-certificate: its fact certificate)
    \\       selka validate-certificates PATH   (one verdict per function of the certificate files under PATH, as `lake exe certcheck` prints)
    \\       selka mutate-certificates FILE OUTDIR   (write the single-edit fault mutants of FILE's accepted functions into OUTDIR)
    \\       selka link-certificates PATH   (link each program's callee tables to the callees' function lines; one line per entry that does not match)
    \\       selka validate-fact-certificates PATH [--detail]   (one verdict per function of the fact certificate files under PATH)
    \\       selka mutate-fact-certificates FILE OUTDIR   (write the single-edit fault mutants of FILE's accepted fact certificates into OUTDIR)
    \\       selka verify-ir PATH   (the IR verifier's verdict on each function of the core-ir-v1 texts under PATH, as `lake exe irverify` prints)
    \\
;

/// `selka test`'s usage: every flag `testCommand` and the CLI accept.
const test_usage =
    \\usage: selka test <entry.selka|directory> [--filter SUBSTRING|GLOB] [--cases FILE] [--json]
    \\Default: optimized debug at LLVM -O0 (Core's facts passes); --debug-lean selects the lean debug build `build` and `run` use; --optimize-debug selects LLVM -O2; --mode Debug is the default.
    \\  --release | --unoptimized | --optimize-debug | --debug-lean | --debug-o0           --mode Debug|ReleaseFast
    \\  --no-facts | --verify-facts | --verify-ownership | --verify-facts-static | --verify-names | --no-validate
    \\  --local-stdlib                          prefer stdlib sources beside the entry
    \\  --affected --against REF                run only tests reaching a declaration changed since REF
    \\  --skip-test-modules FILE                run none of the tests of the modules FILE lists (another root of a directory run runs them)
    \\  --import-root DIR                       take DIR as the import root of the entry (a directory run places an entry there when no selka.json governs it and its own folder cannot serve its imports)
    \\  --jobs N                                tests at once (default: CPUs, capped by free memory)
    \\  --max-steps N --max-frames N --max-memory SIZE --timeout-ms N   per-test budgets
    \\  --seed N --property-runs N              property test inputs (runs: 1 to 1000000)
    \\  --property-policy legacy|indexed-v1    property generation and range reuse policy
    \\  --force --no-cache --cache-dir DIR      rerun every test / use a private cache / cache location
    \\  --emit-certificates DIR                 write the ownership certificates of each built test program under DIR
    \\  --shared-cache-dir DIR                 opt-in compatible project test receipts (else SELKA_TEST_SHARED_CACHE)
    \\  --cpu native|x86-64-v3                   the CPU model the tests are compiled for (default native: this machine's)
    \\  --link FILE.c (repeatable) --zig PATH
    \\
;

/// What stops a command before it has a status: memory, an unwritable stream, or a
/// test the runner cannot encode.
pub const Error = test_runner.Error || std.Io.File.Writer.Error || frontend.Error || project_entry.Error || build.Error || error{ReadFailed};

/// Dispatch one command; the process exit status is its result.
pub fn main(init: std.process.Init) !u8 {
    const allocator = init.arena.allocator();
    const raw_args = try init.minimal.args.toSlice(allocator);
    const args = try @import("cli_ownership.zig").prepare(init, raw_args) orelse return 2;
    if (args.len >= 2 and std.mem.eql(u8, args[1], "build")) return buildCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "check")) return check_command.run(init, args[2..]);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "test")) return testCommand(init, args[2..]);
    // `selka`'s run command (NEW-CORE-S5-RUN-1), which the core's own tests drive.
    for ([_][]const u8{ "run", "run-project" }) |name| if (args.len >= 2 and std.mem.eql(u8, args[1], name)) return cli_run.runCommand(init, name, args[2..]);
    return developer(init, args);
}

/// The developer commands `selka` shares (S5-D8): `dump-typed`, `dump-ir` and
/// `coverage`, from `args` (argv, the program name first). Anything else prints the usage.
pub fn developer(init: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len >= 3 and std.mem.eql(u8, args[1], "dump-typed")) return dumpTyped(init, args[2], if (args.len >= 4) args[3] else null);
    if (args.len >= 3 and std.mem.eql(u8, args[1], "dump-ir")) {
        var with_facts = false;
        var with_certificate = false;
        var with_validation = false;
        var with_fact_certificate = false;
        for (args[3..]) |arg| {
            if (std.mem.eql(u8, arg, "--facts")) {
                with_facts = true;
            } else if (std.mem.eql(u8, arg, "--fact-certificate")) {
                with_fact_certificate = true;
            } else if (std.mem.eql(u8, arg, "--certificate")) {
                with_certificate = true;
            } else if (std.mem.eql(u8, arg, "--validate")) {
                with_validation = true;
            } else return 2;
        }
        if (with_validation and !with_certificate) return 2;
        if (with_fact_certificate) return if (with_certificate or with_facts or with_validation) 2 else dumpFactCertificate(init, args[2]);
        if (with_certificate) return dumpCertificate(init, args[2], with_validation);
        return dumpIr(init, args[2], with_facts);
    }
    if (args.len >= 3 and std.mem.eql(u8, args[1], "coverage")) return coverageCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "validate-certificates")) return ownership_commands.validateCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "mutate-certificates")) return ownership_commands.mutateCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "link-certificates")) return ownership_commands.linkCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "validate-fact-certificates")) return fact_commands.validateCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "verify-ir")) return verify_ir_commands.verifyCommand(init, args[2..]);
    if (args.len >= 2 and std.mem.eql(u8, args[1], "mutate-fact-certificates")) return fact_mutate_command.mutateCommand(init, args[2..]);
    // The developer count of W3 (not in the usage text): what judging generic bodies at their declaration would refuse.
    if (args.len >= 2 and std.mem.eql(u8, args[1], "template-stand-ins")) return @import("template_stand_ins_command.zig").run(init, args[2..]);
    try std.Io.File.stderr().writeStreamingAll(init.io, usage);
    return 2;
}

fn developerFailure(init: std.process.Init, report: []const u8, err: (project_entry.Error || frontend.Error || error{ReadFailed})) Error!u8 {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    if (err == error.InternalError) return error.InternalError;
    try std.Io.File.stderr().writeStreamingAll(init.io, report);
    return switch (err) {
        error.ConfigurationFailed => 2,
        error.PolicyDenied => 3,
        else => 1,
    };
}

fn dumpTyped(init: std.process.Init, path: []const u8, filter: ?[]const u8) !u8 {
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| return developerFailure(init, report.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = entry.check(allocator, &session, &report) catch |err| return developerFailure(init, report.items, err);
    const text = try typed_dump.render(allocator, checked.program, filter);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    return 0;
}

fn dumpIr(init: std.process.Init, path: []const u8, with_facts: bool) !u8 {
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| return developerFailure(init, report.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = entry.check(allocator, &session, &report) catch |err| return developerFailure(init, report.items, err);
    var refusal: build.Refusal = .{};
    var module = build.buildExecutable(allocator, .{ .program = checked.program, .source = checked.src }, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            try pipeline.reportBuildRefusal(allocator, checked.src, refusal, .text, &report);
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            return 1;
        },
        else => return err,
    };
    var ranges: std.ArrayList(u8) = .empty;
    var result_known: []const ?facts.Facts = &.{};
    if (with_facts) {
        const result = try passes.runWithScratch(allocator, init.gpa, &module, .trusted);
        result_known = result.known;
        for (module.functions.items, result.known) |function, maybe| {
            const known = maybe orelse continue;
            try ranges.print(allocator, "facts {s}:", .{function.name});
            for (known.ranges, known.floats, 0..) |range, float, index| {
                if (range) |r| try ranges.print(allocator, " %{d}=[{d},{d}]", .{ index, r.lo, r.hi });
                if (float) |r| try ranges.print(allocator, " %{d}=[{e},{e}]", .{ index, r.lo, r.hi });
            }
            try ranges.appendSlice(allocator, "\n");
            // List facts (settled, length, elements, len), for the lists that carry any.
            for (known.aggregates.lists, 0..) |list, index| {
                if (!list.settled and list.len == null and list.elements == null) continue;
                try ranges.print(allocator, "list {s} %{d}: settled={} length=%{d}", .{ function.name, index, list.settled, if (list.length == .none) -1 else @as(i64, @intCast(list.length.index())) });
                if (list.elements) |e| try ranges.print(allocator, " elements=[{d},{d}]", .{ e.lo, e.hi });
                if (list.len) |e| try ranges.print(allocator, " len=[{d},{d}]", .{ e.lo, e.hi });
                try ranges.appendSlice(allocator, "\n");
            }
        }
    }
    if (with_facts) {
        // Whole-program field intervals (NEW-CORE-F2-FIELD-1), from the final facts' writes.
        const table = try @import("fields.zig").hulls(allocator, &module, result_known, try @import("fields.zig").closedTypes(allocator, &module), false);
        for (table.types, 0..) |maybe, k| {
            const fields = maybe orelse continue;
            for (fields, 0..) |range, field| if (range) |r| {
                const full = facts.typeRange(module.compound(@fromBackingInt(@as(u32, @intCast(k + ir.Type.first_compound)))).record[field]) orelse continue;
                if (r.lo > full.lo or r.hi < full.hi) try ranges.print(allocator, "field type{d}.{d}: [{d}, {d}]\n", .{ k + ir.Type.first_compound, field, r.lo, r.hi });
            };
        }
    }
    const text = try print.module(allocator, &module);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    try std.Io.File.stdout().writeStreamingAll(init.io, ranges.items);
    return 0;
}

/// `dump-ir FILE --fact-certificate`: the fact certificate (`fact-certificate-v1`, docs/design/fact-certificates.md) of the program's
/// final IR and the fact tables the release passes leave, as `--emit-certificates` writes it for a release build.
fn dumpFactCertificate(init: std.process.Init, path: []const u8) !u8 {
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| return developerFailure(init, report.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = entry.check(allocator, &session, &report) catch |err| return developerFailure(init, report.items, err);
    var refusal: build.Refusal = .{};
    // twin-drift-ok: the three dump-ir forms start the same way and diverge at once; a shared prelude would need all three results as one struct
    var module = build.buildExecutable(allocator, .{ .program = checked.program, .source = checked.src }, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            try pipeline.reportBuildRefusal(allocator, checked.src, refusal, .text, &report);
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            return 1;
        },
        else => return err,
    };
    const result = try passes.runWithScratch(allocator, init.gpa, &module, .trusted);
    const described = try @import("fact_export.zig").describe(allocator, allocator, &module, .{ .known = result.known, .fields = result.emission.fields });
    var out: std.ArrayList(u8) = .empty;
    try @import("fact_text.zig").write(allocator, &out, described);
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return 0;
}

/// `dump-ir FILE --certificate`: the ownership certificates of the program's final IR (the IR the
/// release passes leave), in the `ownership-certificate-v2` text.
fn dumpCertificate(init: std.process.Init, path: []const u8, validate: bool) !u8 {
    const allocator = init.arena.allocator();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| return developerFailure(init, report.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = entry.check(allocator, &session, &report) catch |err| return developerFailure(init, report.items, err);
    var refusal: build.Refusal = .{};
    var module = build.buildExecutable(allocator, .{ .program = checked.program, .source = checked.src }, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            try pipeline.reportBuildRefusal(allocator, checked.src, refusal, .text, &report);
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            return 1;
        },
        else => return err,
    };
    var sink: @import("ownership_certificate.zig").Sink = .{};
    var stopped: @import("own.zig").Refusal = .{ .certificates = &sink };
    _ = (passes.Reporting{ .arena = allocator, .backing = init.gpa, .module = &module, .refusal = &stopped }).runWithScratch(.trusted) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => {
            try pipeline.reportOwnershipRefusal(allocator, checked.src, stopped, .text, &report);
            try std.Io.File.stderr().writeStreamingAll(init.io, report.items);
            return 1;
        },
    };
    const exporter = @import("ownership_export.zig");
    var problems: std.ArrayList(exporter.Problem) = .empty;
    var counts: exporter.Counts = .{};
    const indices = try allocator.alloc(u32, module.functions.items.len);
    for (indices, 0..) |*slot, i| slot.* = @intCast(i);
    const text = try exporter.render(allocator, .{ .module = &module, .sink = &sink, .problems = &problems }, indices, &counts);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
    var rejected: usize = 0;
    if (validate) rejected = try rejectedFunctions(init, &module, &sink, indices);
    for (problems.items) |problem| {
        const line = try std.fmt.allocPrint(allocator, "selka: certificate: cannot describe {s}: {s}\n", .{ problem.function, problem.reason });
        try std.Io.File.stderr().writeStreamingAll(init.io, line);
    }
    return if (problems.items.len == 0 and rejected == 0) 0 else 1;
}

/// Validate each function of `module` (`dump-ir --certificate --validate`): name the rejected ones on standard error and
/// say how many were validated, left unchecked or rejected.
fn rejectedFunctions(init: std.process.Init, module: *const ir.Module, sink: *const @import("ownership_certificate.zig").Sink, indices: []const u32) !usize {
    const allocator = init.arena.allocator();
    const exporter = @import("ownership_export.zig");
    const validator = @import("validate_ownership.zig");
    var accepted: usize = 0;
    var unchecked: usize = 0;
    var rejected: usize = 0;
    for (indices) |index| {
        if (module.functions.items[index].signature.linkage != .internal) continue;
        var work = std.heap.ArenaAllocator.init(init.gpa);
        defer work.deinit();
        const a = work.allocator();
        switch (try exporter.build(a, module, sink, index)) {
            .refused => {},
            .described => |function| switch (try validator.validate(a, function)) {
                .accepted => accepted += 1,
                .unchecked => unchecked += 1,
                .rejected => |failure| {
                    rejected += 1;
                    const line = try validator.describe(a, function.name, failure);
                    try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "{s}\n", .{line}));
                },
            },
        }
    }
    const summary = try std.fmt.allocPrint(allocator, "selka: ownership: {d} validated, {d} unchecked, {d} rejected\n", .{ accepted, unchecked, rejected });
    try std.Io.File.stderr().writeStreamingAll(init.io, summary);
    return rejected;
}

/// The fact mode a `--sabotage-facts[=RULE]` flag selects: verify with one wrong rule.
fn sabotageFlag(arg: []const u8) ?@FieldType(pipeline.Options, "facts") {
    const flags = [_]struct { []const u8, @FieldType(pipeline.Options, "facts") }{
        .{ "--sabotage-facts", .sabotage },
        .{ "--sabotage-facts=widening", .sabotage_widening },
        .{ "--sabotage-facts=length", .sabotage_length },
        .{ "--sabotage-facts=overflow", .sabotage_overflow },
        .{ "--sabotage-facts=index", .sabotage_index },
        .{ "--sabotage-facts=field", .sabotage_field },
        .{ "--sabotage-facts=version", .sabotage_version },
    };
    for (flags) |flag| if (std.mem.eql(u8, arg, flag[0])) return flag[1];
    return null;
}

/// The developer build (`selka build` given `--sabotage-facts`,
/// `--generic-vectors` or `--trap-frames=`, S5-D8): the core's own flag set,
/// every failure exit 1, the source path displayed relative to its directory.
pub fn buildCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    const allocator = init.arena.allocator();
    var options: pipeline.Options = .{ .zig = cli_run.zigPath(init) };
    var links: std.ArrayList([]const u8) = .empty;
    var explicit_mode = false;
    var path: ?[]const u8 = null;
    var no_cache = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        const has_value = index + 1 < args.len;
        if (std.mem.eql(u8, arg, "--release")) {
            options.mode.select(&explicit_mode, .release) catch return 2;
        } else if (std.mem.eql(u8, arg, "--optimize-debug")) {
            options.mode.select(&explicit_mode, .optimized_o2) catch return 2;
        } else if (std.mem.eql(u8, arg, "--unoptimized")) {
            options.mode.select(&explicit_mode, .debug) catch return 2;
        } else if (std.mem.eql(u8, arg, "--debug-o0")) {
            options.mode.select(&explicit_mode, .optimized_debug) catch return 2;
        } else if (std.mem.eql(u8, arg, "--debug-lean")) {
            options.mode.select(&explicit_mode, .lean_debug) catch return 2;
        } else if (std.mem.eql(u8, arg, "--project")) {
            // Project configuration and graph checks are always applied.
        } else if (std.mem.eql(u8, arg, "--mode") and has_value) {
            index += 1;
            const modes = std.StaticStringMap(@import("build_mode.zig").Mode).initComptime(.{
                .{ "ReleaseFast", .release }, .{ "Debug", .optimized_debug },
            });
            options.mode.select(&explicit_mode, modes.get(args[index]) orelse return 2) catch return 2;
        } else if (std.mem.eql(u8, arg, "--no-facts")) {
            options.facts = .off;
        } else if (std.mem.eql(u8, arg, "--generic-vectors")) {
            options.show.codegen.generic_vectors = true;
        } else if (flagValue(args, &index, "--cpu")) |text| {
            options.show.codegen.target = try hostCpu(init, text) orelse return 2;
        } else if (trapFrames(arg)) |frames| {
            options.show.codegen.trap_frames = frames;
        } else if (buildOutputFlag(&options, &no_cache, arg)) {} else if (std.mem.eql(u8, arg, "--verify-facts")) {
            options.facts = .verify;
        } else if (sabotageFlag(arg)) |mode| {
            options.facts = mode;
        } else if (std.mem.eql(u8, arg, "-o") and has_value) {
            index += 1;
            options.output = args[index];
        } else if (std.mem.eql(u8, arg, "--link") and has_value) {
            index += 1;
            try links.append(allocator, args[index]);
        } else if (std.mem.eql(u8, arg, "--emit-llvm") and has_value) {
            index += 1;
            options.show.llvm = args[index];
        } else if (std.mem.eql(u8, arg, "--zig") and has_value) {
            index += 1;
            options.zig = args[index];
        } else if (std.mem.eql(u8, arg, cache_dir_flag) and has_value) {
            index += 1;
            options.cache = args[index];
        } else if (path == null and !std.mem.startsWith(u8, arg, "-")) {
            path = arg;
        } else {
            try std.Io.File.stderr().writeStreamingAll(init.io, usage);
            return 2;
        }
    }
    options.links = links.items;
    const source = path orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    };
    if (options.output.len == 0) {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    }
    var report: std.ArrayList(u8) = .empty;
    if (no_cache) options.cache = try cli_run.privateCache(init, options.cache);
    defer if (no_cache) cli_run.discard(init.io, options.cache);
    const compilation_init = try @import("compiler_sharing.zig").prepare(init, no_cache or options.show.verify_cache);
    const status = pipeline.build(compilation_init, source, options, &report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => failed: {
            try @import("build_failure.zig").note(init.arena.allocator(), &report, err, options.cache);
            break :failed 1;
        },
    };
    if (report.items.len != 0) try language.warning_display.write(init.io, report.items);
    return status;
}

fn buildOutputFlag(options: *pipeline.Options, no_cache: *bool, arg: []const u8) bool {
    if (std.mem.eql(u8, arg, "--stats")) {
        options.show.stats = true;
    } else if (std.mem.eql(u8, arg, "--verify-cache")) {
        options.show.verify_cache = true;
    } else if (std.mem.eql(u8, arg, "--no-cache")) {
        no_cache.* = true;
        // A cold build also keeps out of the shared stage store (NO-CACHE-COLD-1).
        options.show.compiler_cache_disabled = true;
    } else if (std.mem.eql(u8, arg, "--cache-report")) {
        options.show.cache_report = .text;
    } else return false;
    return true;
}

const mode_conflict = "--release, --unoptimized, --optimize-debug, --debug-lean, --debug-o0 and --mode Debug are mutually exclusive";

/// `selka-core test` and `selka test`: the per-test conformance runner (`test_runner.zig`).
pub fn testCommand(init: std.process.Init, args: []const []const u8) Error!u8 {
    var options: test_runner.Options = .{ .path = "", .build = .{ .zig = cli_run.zigPath(init) } };
    var links: std.ArrayList([]const u8) = .empty;
    var explicit_mode = false;
    var affected = false;
    var no_cache = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const start = index;
        if (testControls(&options, args, &index, &explicit_mode) catch return invalidValue(init, args, start, index)) continue;
        const arg = args[index];
        const has_value = index + 1 < args.len;
        if (std.mem.eql(u8, arg, "--affected")) {
            affected = true;
        } else if (scopeFlag(&options, args, &index)) {} else if (std.mem.eql(u8, arg, "--no-cache")) {
            no_cache = true;
        } else if (flagValue(args, &index, language.warning_display.count_option)) |file| {
            language.warning_display.countInto(file);
        } else if (flagValue(args, &index, "--skip-test-modules")) |list| {
            options.controls.scope.skipped = testModules(init, list) catch return invalidValue(init, args, start, index);
        } else if (flagValue(args, &index, "--cpu")) |text| {
            options.build.show.codegen.target = try hostCpu(init, text) orelse return 2;
        } else if (testBuildFlag(&options, arg, &explicit_mode) catch return testUsage(init, mode_conflict)) {} else if (std.mem.eql(u8, arg, "--link") and has_value) {
            index += 1;
            try links.append(init.arena.allocator(), args[index]);
        } else if (std.mem.eql(u8, arg, "--seed") and has_value) {
            index += 1;
            options.properties.seed = std.fmt.parseInt(u64, args[index], 10) catch return invalidValue(init, args, index - 1, index);
        } else if (std.mem.eql(u8, arg, "--property-policy") and has_value) {
            index += 1;
            options.properties.policy = @import("property_campaign_contract.zig").Policy.parse(args[index]) orelse return invalidValue(init, args, index - 1, index);
        } else if (std.mem.eql(u8, arg, "--property-runs") and has_value) {
            index += 1;
            options.properties.runs = propertyRuns(args[index]) orelse return invalidValue(init, args, index - 1, index);
        } else if (std.mem.eql(u8, arg, "--filter") and has_value) {
            index += 1;
            options.filter = args[index];
        } else if (std.mem.eql(u8, arg, "--zig") and has_value) {
            index += 1;
            options.build.zig = args[index];
        } else if (std.mem.eql(u8, arg, cache_dir_flag) and has_value) {
            index += 1;
            options.build.cache = args[index];
        } else if (options.path.len == 0 and !std.mem.startsWith(u8, arg, "-")) {
            options.path = arg;
        } else {
            const problem = if (std.mem.startsWith(u8, arg, "-")) (if (has_value or !takesValue(arg)) "unknown option" else "missing value for") else "unexpected argument";
            return testUsage(init, try std.fmt.allocPrint(init.arena.allocator(), "{s} '{s}'", .{ problem, arg }));
        }
    }
    if (options.path.len == 0) return testUsage(init, null);
    // The project's `stores`, before any store opens (FR8). A directory run decides once, from the directory's project, and
    // its child compilers inherit the decision; the test processes get the caller's environment back (`childEnvironment`).
    if (try cli_run.applyStores(init, options.path, false)) return 2;
    // NEW-CORE-S5-AFFECTED-1: the two switches only mean something together.
    if (affected != (options.controls.scope.against != null)) return testUsage(init, "--affected and --against REF go together");
    options.build.links = links.items;
    // Rule C joins facts verification by default; SELKA_VERIFY_WRITTEN_COPIES=0 turns it off (a child compiler inherits it).
    if (options.build.facts == .verify and @import("pipeline.zig").writtenCopiesOn(init.environ_map.get("SELKA_VERIFY_WRITTEN_COPIES"))) options.build.facts = .verify_written;
    options.shared_cache = @import("test_runner_options.zig").sharedCache(options.shared_cache, init.environ_map);
    // NEW-CORE-S5-NO-CACHE-1: run against a private cache, removed afterwards.
    if (no_cache) {
        options.build.cache = try cli_run.privateCache(init, options.build.cache);
        options.shared_cache = "";
        options.build.show.compiler_cache_disabled = true;
    }
    defer if (no_cache) cli_run.discard(init.io, options.build.cache);
    const compilation_init = try @import("compiler_sharing.zig").prepare(init, no_cache or options.build.show.verify_cache);
    return test_runner.run(compilation_init, options);
}

fn testBuildFlag(options: *test_runner.Options, arg: []const u8, explicit_mode: *bool) error{Usage}!bool {
    if (std.mem.eql(u8, arg, "--release")) {
        try options.build.mode.select(explicit_mode, .release);
    } else if (std.mem.eql(u8, arg, "--optimize-debug")) {
        try options.build.mode.select(explicit_mode, .optimized_o2);
    } else if (std.mem.eql(u8, arg, "--unoptimized")) {
        try options.build.mode.select(explicit_mode, .debug);
    } else if (std.mem.eql(u8, arg, "--debug-o0")) {
        try options.build.mode.select(explicit_mode, .optimized_debug);
    } else if (std.mem.eql(u8, arg, "--debug-lean")) {
        try options.build.mode.select(explicit_mode, .lean_debug);
    } else if (std.mem.eql(u8, arg, "--json")) {
        options.json = true;
    } else if (std.mem.eql(u8, arg, "--local-stdlib")) {
        options.build.show.codegen.local_stdlib = true;
    } else if (std.mem.eql(u8, arg, "--no-facts")) {
        options.build.facts = .off;
    } else if (std.mem.eql(u8, arg, "--verify-facts")) {
        options.build.facts = .verify;
    } else if (std.mem.eql(u8, arg, "--verify-written-copies")) {
        options.build.facts = .verify_written;
    } else if (options.build.show.verify.ask(arg)) {} else return false;
    return true;
}

/// The build mode `selka test` reaches after reading `flags`, one mode option each, in order.
fn testModeAfter(flags: []const []const u8) error{Usage}!@import("build_mode.zig").Mode {
    var options: test_runner.Options = .{ .path = "", .build = .{ .zig = "zig" } };
    var explicit = false;
    for (flags) |flag| _ = try testBuildFlag(&options, flag, &explicit);
    return options.build.mode;
}

// spec-case: DEBUG-OPTIMIZE-1
test "selka test starts from the -O0 debug build, and takes every mode option, refusing two different ones" {
    try std.testing.expectEqual(.optimized_debug, try testModeAfter(&.{}));
    try std.testing.expectEqual(.optimized_debug, try testModeAfter(&.{"--debug-o0"}));
    try std.testing.expectEqual(.lean_debug, try testModeAfter(&.{"--debug-lean"}));
    try std.testing.expectEqual(.optimized_o2, try testModeAfter(&.{ "--optimize-debug", "--optimize-debug" }));
    try std.testing.expectEqual(.debug, try testModeAfter(&.{"--unoptimized"}));
    try std.testing.expectEqual(.release, try testModeAfter(&.{"--release"}));
    try std.testing.expectError(error.Usage, testModeAfter(&.{ "--debug-lean", "--debug-o0" }));
    try std.testing.expectError(error.Usage, testModeAfter(&.{ "--release", "--debug-lean" }));
    try std.testing.expectError(error.Usage, testModeAfter(&.{ "--debug-o0", "--optimize-debug" }));
}

fn propertyRuns(text: []const u8) ?u32 {
    const runs = std.fmt.parseInt(u32, text, 10) catch return null;
    return if (runs == 0 or runs > 1000000) null else runs;
}

/// Print `selka test: PROBLEM` (when there is one) and the test usage; status 2.
fn testUsage(init: std.process.Init, problem: ?[]const u8) Error!u8 {
    const text = if (problem) |line| try std.fmt.allocPrint(init.arena.allocator(), "selka test: {s}\n" ++ test_usage, .{line}) else test_usage;
    try std.Io.File.stderr().writeStreamingAll(init.io, text);
    return 2;
}

/// The usage error for the flag at `args[start]` whose value (after `=`, or the
/// argument at `index`) is not one the flag accepts (NEW-CORE-S5-TEST-USAGE-1).
fn invalidValue(init: std.process.Init, args: []const []const u8, start: usize, index: usize) Error!u8 {
    const arg = args[start];
    const split = std.mem.indexOfScalar(u8, arg, '=');
    const value = if (split) |at| arg[at + 1 ..] else if (index > start) args[index] else "";
    return testUsage(init, try std.fmt.allocPrint(init.arena.allocator(), "invalid value '{s}' for {s}", .{ value, arg[0 .. split orelse arg.len] }));
}

/// A flag that sets the run's scope: `--allow-host`, `--against REF`, `--import-root DIR`.
fn scopeFlag(options: *test_runner.Options, args: []const []const u8, index: *usize) bool {
    const scope = &options.controls.scope;
    if (std.mem.eql(u8, args[index.*], "--allow-host")) {
        scope.allow_host = true;
    } else if (flagValue(args, index, "--against")) |reference| {
        scope.against = reference;
    } else if (flagValue(args, index, "--import-root")) |directory| {
        scope.under = directory;
    } else return false;
    return true;
}

/// Whether `arg` is a `selka test` flag that reads the next argument as its value.
fn takesValue(arg: []const u8) bool {
    const valued = [_][]const u8{
        "--filter",            "--cases",       "--jobs",              "--mode",          "--max-steps",       "--max-frames",
        "--max-memory",        "--timeout-ms",  "--seed",              "--property-runs", "--property-policy", "--link",
        "--zig",               cache_dir_flag,  shared_cache_dir_flag, "--against",       "--threads",         "--emit-certificates",
        "--skip-test-modules", "--import-root", "--cpu",
    };
    for (valued) |name| if (std.mem.eql(u8, arg, name)) return true;
    return std.mem.eql(u8, arg, language.warning_display.count_option);
}

fn testControls(options: *test_runner.Options, args: []const []const u8, index: *usize, explicit_mode: *bool) error{Usage}!bool {
    if (try sharedCacheFlag(options, args, index)) return true;
    const arg = args[index.*];
    const has_value = index.* + 1 < args.len;
    if (std.mem.eql(u8, arg, "--mode") and has_value) {
        index.* += 1;
        if (std.mem.eql(u8, args[index.*], "ReleaseFast")) {
            try options.build.mode.select(explicit_mode, .release);
        } else if (std.mem.eql(u8, args[index.*], "Debug")) {
            try options.build.mode.select(explicit_mode, .optimized_debug);
        } else return error.Usage;
    } else if (flagValue(args, index, "--emit-certificates")) |directory| {
        options.build.show.certificates = directory;
    } else if (std.mem.eql(u8, arg, "--force")) {
        options.controls.force = true;
    } else if (std.mem.eql(u8, arg, "--cases") and has_value) {
        index.* += 1;
        options.controls.cases = args[index.*];
    } else if (std.mem.eql(u8, arg, "--jobs") and has_value) {
        index.* += 1;
        options.controls.jobs = std.fmt.parseInt(usize, args[index.*], 10) catch return error.Usage;
        if (options.controls.jobs.? == 0) return error.Usage;
    } else if (std.mem.startsWith(u8, arg, "--jobs=")) {
        options.controls.jobs = std.fmt.parseInt(usize, arg[7..], 10) catch return error.Usage;
        if (options.controls.jobs.? == 0) return error.Usage;
    } else if (std.mem.eql(u8, arg, "--timeout-ms") and has_value) {
        index.* += 1;
        options.controls.timeout_ms = std.fmt.parseInt(u32, args[index.*], 10) catch return error.Usage;
        if (options.controls.timeout_ms == 0) return error.Usage;
    } else if (std.mem.eql(u8, arg, "--max-steps") and has_value) {
        index.* += 1;
        options.controls.max_steps = std.fmt.parseInt(u64, args[index.*], 10) catch return error.Usage;
        options.controls.ceilings.explicit_steps = true;
    } else if (std.mem.startsWith(u8, arg, "--max-steps=")) {
        options.controls.max_steps = std.fmt.parseInt(u64, arg[12..], 10) catch return error.Usage;
        options.controls.ceilings.explicit_steps = true;
    } else if (flagValue(args, index, "--max-frames")) |text| {
        options.controls.ceilings.frames = std.fmt.parseInt(u32, text, 10) catch return error.Usage;
        if (options.controls.ceilings.frames == 0) return error.Usage;
        options.controls.ceilings.explicit_frames = true;
    } else if (flagValue(args, index, "--max-memory")) |text| {
        options.controls.ceilings.memory = @import("memory_budget").parse(text) catch return error.Usage;
        options.controls.ceilings.explicit_memory = true;
    } else if (flagValue(args, index, "--threads")) |text| {
        const count = std.fmt.parseInt(u64, text, 10) catch return error.Usage;
        if (count == 0 or count > @import("cli_args.zig").max_threads) return error.Usage;
        options.controls.ceilings.threads = count;
    } else return false;
    return true;
}

fn sharedCacheFlag(options: *test_runner.Options, args: []const []const u8, index: *usize) error{Usage}!bool {
    const start = index.*;
    const directory = flagValue(args, index, shared_cache_dir_flag) orelse return false;
    if (options.shared_cache != null or directory.len == 0) return error.Usage;
    if (index.* != start and std.mem.startsWith(u8, directory, "--")) return error.Usage;
    options.shared_cache = directory;
    return true;
}

/// The value of `--NAME VALUE` or `--NAME=VALUE` at `index` (advancing past a separate
/// value), or null when the argument is another flag.
/// The module paths `--skip-test-modules FILE` names: one path relative to the entry's root on each line, empty lines
/// ignored. A directory run writes the file for each child root (D-TL2-3 of experiments/test-loop-20261109/DECISIONS.md).
fn testModules(init: std.process.Init, path: []const u8) error{ OutOfMemory, ReadFailed }![]const []const u8 {
    const a = init.arena.allocator();
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
    var found: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| if (line.len != 0) try found.append(a, line);
    return found.items;
}

fn flagValue(args: []const []const u8, index: *usize, comptime name: []const u8) ?[]const u8 {
    const arg = args[index.*];
    if (std.mem.startsWith(u8, arg, name ++ "=")) return arg[name.len + 1 ..];
    if (!std.mem.eql(u8, arg, name) or index.* + 1 >= args.len) return null;
    index.* += 1;
    return args[index.*];
}

/// The coverage sweep: check each file and try to build each of its functions alone.
/// Prints `ok NAME\tproven=P exact=E` (the checks the fact pass proves and keeps in
/// reachable code of the function analysed alone; `stack=S`, the lists it would put on
/// the stack), `refused REASON\tNAME` or
/// `frontend FILE` per line.
fn coverageCommand(init: std.process.Init, arguments: []const []const u8) !u8 {
    if (arguments.len == 0) return 2;
    for (arguments) |arg| if (std.mem.startsWith(u8, arg, "--")) return 2;
    var refused = false;
    var out: std.ArrayList(u8) = .empty;
    for (arguments) |path| {
        if (std.mem.startsWith(u8, path, "--")) continue;
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        var report: std.ArrayList(u8) = .empty;
        const entry = project_entry.resolve(allocator, init.io, path, &report) catch |err| {
            if (err == error.OutOfMemory) return err;
            try out.print(init.arena.allocator(), "frontend {s}\t{s}\n", .{ path, std.mem.sliceTo(report.items, '\n') });
            refused = true;
            continue;
        };
        var session = frontend.Session.init(init.gpa, init.io, entry.root);
        defer session.deinit();
        const checked = entry.check(allocator, &session, &report) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => {
                const first = std.mem.sliceTo(report.items, '\n');
                try out.print(init.arena.allocator(), "frontend {s}\t{s}\n", .{ path, first });
                refused = true;
                continue;
            },
        };
        for (try build.coverageInput(allocator, .{ .program = checked.program, .source = checked.src })) |outcome| {
            const keep = init.arena.allocator();
            if (outcome.refusal) |reason| {
                try out.print(keep, "refused {s}\t{s}", .{ reason, outcome.name });
                if (outcome.rule) |rule| try out.print(keep, "\trule={s}", .{@tagName(rule)});
                try out.appendSlice(keep, "\n");
                continue;
            }
            var function = outcome.function.?;
            const known = try facts.analyze(allocator, &function, .{});
            var exact: u32 = 0;
            for (function.blocks.items, known.reachable) |block, live| {
                if (!live) continue;
                for (block.insts.items) |ref| exact += @intFromBool(function.inst(ref).check == .exact);
            }
            // Intraprocedural promotion: coverage builds each function alone, so
            // calls without a borrowing summary remain conservative.
            const stack = try @import("promote.zig").promote(allocator, &outcome.module.?, &function, &known, .{});
            try out.print(keep, "ok {s}\tproven={d} exact={d} stack={d}\n", .{ outcome.name, known.proven, exact, stack.lists });
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, out.items);
    return @intFromBool(refused);
}

/// The host target compiled for the CPU model `--cpu` names, `text`: the commands that build only for the host (`selka test`
/// and the developer build). For a word that is no model it prints the one-line refusal and returns null (the caller exits 2).
fn hostCpu(init: std.process.Init, text: []const u8) Error!?*const @import("target.zig").Target {
    const target = @import("target.zig");
    const cpu = target.Cpu.parse(text) orelse {
        const a = init.arena.allocator();
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "selka: {s}\n", .{try target.Cpu.unknown(a, text)}));
        return null;
    };
    return target.host.forCpu(cpu);
}

/// The mechanism `--trap-frames=NAME` names (a `target.Traps`), or null for any other argument.
fn trapFrames(arg: []const u8) ?@import("target.zig").Traps {
    const flag = "--trap-frames=";
    if (!std.mem.startsWith(u8, arg, flag)) return null;
    return std.meta.stringToEnum(@import("target.zig").Traps, arg[flag.len..]);
}

test "selka test's usage lists the validator flags and the way out of the default validation" {
    try std.testing.expect(std.mem.indexOf(u8, test_usage, "--verify-ownership | --verify-facts-static | --verify-names | --no-validate") != null);
}
