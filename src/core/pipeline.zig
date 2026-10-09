//! One `mylang-core build`: check, build the Core IR, compute facts (release),
//! emit LLVM IR and link. Every failure is rendered into `report`.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build_ir = @import("build.zig");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const emit_units = @import("emit_units.zig");
const driver = @import("driver.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const cost_remarks = @import("cost_remarks.zig");
const verify_ir = @import("verify_ir.zig");
const target_description = @import("target.zig");
const build_replay = @import("build_replay.zig");
const run_budget = @import("run_budget.zig");

/// What the command line asked for.
pub const Options = struct {
    zig: []const u8,
    output: []const u8 = "",
    release: bool = false,
    links: []const []const u8 = &.{},
    /// What to show besides the executable.
    show: Show = .{},
    cache: []const u8 = ".mylang-cache/core",
    /// Fact pass mode in a release build: `on`, `off` (`--no-facts`, to measure
    /// what facts buy), `verify` (`--verify-facts`: every fact the build relies on
    /// is also checked at run time and traps `R_CORE_FACT` when it does not hold),
    /// or `sabotage` (`--sabotage-facts`, test only: verify with one wrong rule), with
    /// `sabotage_widening` and `sabotage_length` for the other wrong rules of `facts.Sabotage`
    /// (`--sabotage-facts=widening`, `--sabotage-facts=length`), and `sabotage_overflow`
    /// for the overflow facts' rules (`--sabotage-facts=overflow`), and `sabotage_index` for
    /// the dominating-check rule (`--sabotage-facts=index`).
    facts: enum { on, off, verify, sabotage, sabotage_widening, sabotage_length, sabotage_overflow, sabotage_index } = .on,
};

/// Extra outputs of a build.
pub const Show = struct {
    /// Also write the emitted LLVM IR here (`--emit-llvm`).
    llvm: ?[]const u8 = null,
    /// Print what the release passes did (`--stats`) to the report.
    stats: bool = false,
    /// What the emitted code itself does beyond the program: vector lowering, trap
    /// frames and run-time counters.
    codegen: Codegen = .{},
    /// `--verify-cache`: recompile every unit the object store served and require
    /// identical object bytes; such a build never replays.
    verify_cache: bool = false,
    /// `--cache-report` (`text`) or `--report` (`json`, NEW-CORE-S5-REPORT-1): say what
    /// the caches served and how many tools ran.
    cache_report: CacheReport = .off,
    /// How the front end's diagnostics reach the report: `errors` only, as text
    /// (`mylang-core`), or every diagnostic, warnings included, as the `mylang` CLI
    /// prints them in `text` or `json` (`--diagnostics=json`, NEW-CORE-S5-CLI-1).
    diagnostics: Diagnostics = .errors,
};

/// Code-generation choices that change the executable without changing the program.
pub const Codegen = struct {
    /// Emit only generic LLVM vector code, no x86 intrinsics (`--generic-vectors`): the
    /// portable fallback a target without AVX2 would get, testable on this one.
    generic_vectors: bool = false,
    /// How trap reports find their caller frames (`--trap-frames=dwarf|labels|none`;
    /// default: the target's).
    trap_frames: ?target_description.Traps = null,
    /// A counting build (`--counters`, NEW-CORE-COUNTERS-1): the program records its
    /// count updates, uniqueness tests, copies and memory traffic and writes them as
    /// JSON at exit (`emit_count.zig`, `runtime/core_count.c`).
    counters: bool = false,
};

/// What `Show.diagnostics` selects.
pub const Diagnostics = enum { errors, text, json };

/// What `Show.cache_report` selects: no report, the `mylang-core: cache:` line, or one
/// `cache-report-v1` JSON line.
pub const CacheReport = enum { off, text, json };

/// Why a build stopped after its report was written.
pub const Error = error{ SourceError, Unsupported, ToolFailed, WriteFailed, OutOfMemory, InvalidIr, PolicyDenied, ConfigurationFailed };

/// Build `path` into `options.output`. An unchanged build replays its last
/// identical build's executable (`build_replay.zig`) before checking anything.
pub fn build(init: std.process.Init, path: []const u8, options: Options, report: *std.ArrayList(u8)) Error!u8 {
    return buildWith(init, path, options, null, report);
}

/// `build` for `mylang run`: the program also installs `budget` when `main` starts
/// (NEW-CORE-S5-RUN-1). The budget is part of the replay key.
pub fn buildRun(init: std.process.Init, path: []const u8, options: Options, budget: run_budget.RunBudget, report: *std.ArrayList(u8)) Error!u8 {
    return buildWith(init, path, options, budget, report);
}

/// The project entry `path` resolves to, with its configuration (`mylang.json`).
pub fn resolveEntry(init: std.process.Init, path: []const u8, report: *std.ArrayList(u8)) Error!project_entry.Entry {
    return project_entry.resolve(init.arena.allocator(), init.io, path, report);
}

fn buildWith(init: std.process.Init, path: []const u8, options: Options, budget: ?run_budget.RunBudget, report: *std.ArrayList(u8)) Error!u8 {
    const allocator = init.arena.allocator();
    const entry = try project_entry.resolve(allocator, init.io, path, report);
    const replaying = options.show.llvm == null;
    const context: build_replay.Context = .{ .arena = allocator, .io = init.io, .environment = init.environ_map, .cache = options.cache, .zig = options.zig, .flags = try flags(init, options, budget), .entry = entry };
    if (replaying and !options.show.verify_cache) if (try build_replay.replay(context, options.output, report)) {
        if (options.show.cache_report != .off) try cacheReport(allocator, options.show.cache_report, null, report);
        return 0;
    };
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    entry.configure(&session);
    if (options.show.diagnostics != .errors) session.setFormat(if (options.show.diagnostics == .json) .json else .text);
    try session.enableCache(init.gpa, options.cache);
    const checked = session.checkFile(allocator, if (options.show.diagnostics == .errors) entry.path else path, report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.SourceError,
    };
    if (options.show.diagnostics != .errors) try report.appendSlice(allocator, try session.warnings(allocator));
    const sources = if (replaying) try build_replay.inputs(context, &session) else null;
    try entry.validate(allocator, &session, report);
    var refusal: build_ir.Refusal = .{};
    // A `build --release` executable drops `debug(...)`; a run keeps it (DEBUG-LINE-1).
    const input: build_ir.Input = .{ .program = checked.program, .source = checked.src, .drop_debug = options.release and budget == null };
    var module = build_ir.buildExecutable(allocator, input, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            try refused(allocator, checked.src, refusal, options.show.diagnostics, report);
            return error.Unsupported;
        },
        else => |other| return other,
    };
    if (budget) |installed| try run_budget.instrumentRun(allocator, &module, installed);
    const unit = try unitFor(allocator, checked, entry.path, session.single != null);
    const outcome = try linkEmitted(init, &module, unit, options, report);
    // A record that cannot be written costs the next build its replay, nothing more.
    if (replaying) build_replay.remember(context, sources, outcome.tool, .{ .program = outcome.program, .foreign = outcome.foreign }, report.items) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => {},
    };
    if (options.show.cache_report != .off) try cacheReport(allocator, options.show.cache_report, outcome, report);
    return 0;
}

/// Report the new core's refusal of a construct at `refusal`, as text or as a
/// `diagnostic-v1` record.
/// Entry metadata shared by ordinary builds and cost's identical LLVM emission.
pub fn unitFor(a: std.mem.Allocator, checked: frontend.Checked, absolute: []const u8, single: bool) std.mem.Allocator.Error!Unit {
    return .{
        .src = checked.src,
        .source_path = if (single) absolute else shownPath(checked.src, checked.program),
        .main = .{
            .parameters = try mainParameters(a, checked.program),
            .result = mainResult(checked.program),
            .capabilities = try mainCapabilities(a, checked.program),
            .runtime_options = true,
        },
    };
}

fn refused(allocator: std.mem.Allocator, src: language.source.Source, refusal: build_ir.Refusal, diagnostics: Diagnostics, report: *std.ArrayList(u8)) Error!void {
    const message = try std.fmt.allocPrint(allocator, "the new core does not support {s} yet", .{refusal.reason});
    if (diagnostics == .json) {
        const item: language.diagnostic.Diagnostic = .{ .severity = .err, .code = "E_CORE_UNSUPPORTED", .span = .{ .start = refusal.span, .end = refusal.span }, .message = message };
        return report.appendSlice(allocator, try language.diagnostic_output.render(allocator, item, src, .json));
    }
    const at = frontend.position(src, .{ .start = refusal.span, .end = refusal.span });
    try report.print(allocator, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: {s}\n", .{ at.path, at.line, at.column, message });
}

/// The canonical encoding of every build flag that changes the executable or the
/// report, with `--link` sources by absolute path.
fn flags(init: std.process.Init, options: Options, budget: ?run_budget.RunBudget) Error![]const u8 {
    const allocator = init.arena.allocator();
    const links = try allocator.alloc([]const u8, options.links.len);
    for (options.links, links) |link, *absolute| absolute.* = std.Io.Dir.cwd().realPathFileAlloc(init.io, link, allocator) catch link;
    return std.json.Stringify.valueAlloc(allocator, .{
        .release = options.release,
        .facts = options.facts,
        .stats = options.show.stats,
        .vectors = options.show.codegen.generic_vectors,
        .frames = options.show.codegen.trap_frames,
        .counters = options.show.codegen.counters,
        .links = links,
        .diagnostics = options.show.diagnostics,
        .run = budget,
    }, .{}) catch return error.OutOfMemory;
}

/// Say what the caches served: for a replayed build (`outcome` null) that it replayed,
/// else the units linked, reused, compiled and verified, whether the program store
/// served the executable, and the tool processes started.
fn cacheReport(allocator: std.mem.Allocator, form: CacheReport, outcome: ?driver.Outcome, report: *std.ArrayList(u8)) Error!void {
    const c = if (outcome) |built| built.counts else driver.Counts{};
    const program = if (outcome) |built| (if (built.program_reused) "reused" else "linked") else "replayed";
    if (form == .json) {
        const record = std.json.Stringify.valueAlloc(allocator, .{
            .version = "cache-report-v1",
            .program = program,
            .units = c.units,
            .reused = c.reused,
            .compiled = c.compiled,
            .verified = c.verified,
            .processes = c.processes,
        }, .{}) catch return error.OutOfMemory;
        try report.print(allocator, "{s}\n", .{record});
        return;
    }
    if (outcome == null) return report.appendSlice(allocator, "mylang-core: cache: replayed the last identical build\n");
    const format = "mylang-core: cache: {d} units, {d} reused, {d} compiled, {d} verified; program {s}; {d} processes\n";
    try report.print(allocator, format, .{ c.units, c.reused, c.compiled, c.verified, program, c.processes });
}

/// What the back half of a build needs to know about the checked source.
pub const Unit = struct {
    /// The merged source trap positions are located in.
    src: language.source.Source,
    /// The path traps and error traces report: the entry file's, as the old core shows it
    /// (`shownPath`).
    source_path: []const u8,
    /// The entry function's parameter names (which pick stdout or stderr for a
    /// `Stream`) and, when it returns a `Result`, its case tags.
    main: emit_llvm.Main,
};

/// The back half of `build`: run the release passes on `module`, emit LLVM IR, and
/// link the executable. `mylang-core test` reaches it with a module of its own making.
pub fn finish(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!u8 {
    _ = try linkEmitted(init, module, unit, options, report);
    return 0;
}

fn linkEmitted(init: std.process.Init, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!driver.Outcome {
    const allocator = init.arena.allocator();
    const emission = try emitted(allocator, module, unit, options, report);
    if (options.show.llvm) |where| std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = where, .data = emission.whole.? }) catch return error.WriteFailed;
    var outcome = driver.link(allocator, init.io, init.environ_map, .{
        .zig = options.zig,
        .work = options.cache,
        .output = options.output,
        .release = options.release,
        .links = options.links,
        .units = emission.units,
        .verify = options.show.verify_cache,
    }, report) catch |err| return err;
    if (emission.cost_report) |measured| {
        var final = measured;
        const remarks = try driver.optimizationRemarks(allocator, init.io, init.environ_map, .{ .zig = options.zig, .work = options.cache, .output = "", .release = options.release, .links = &.{}, .units = emission.units });
        if (remarks.yaml) |yaml| cost_remarks.apply(&final, yaml);
        try cost.llvmStats(allocator, report, final.totals, remarks);
        outcome.counts.processes += remarks.processes;
    }
    return outcome;
}

/// Arena-owned native units and optional compatibility LLVM from one pass run.
pub const Emission = struct { units: []const emit_units.Unit, whole: ?[]const u8 = null, cost_report: ?cost.Report = null };

/// Run the same passes and emission used for linking, without invoking a tool.
/// Test receipts hash this exact reachable program.
pub fn emitted(allocator: std.mem.Allocator, module: *ir.Module, unit: Unit, options: Options, report: *std.ArrayList(u8)) Error!Emission {
    // A debug build of the compiler checks the IR it built, and again after the release passes.
    if (verify_ir.enabled) try verify_ir.check(allocator, module, &.{}, report);
    // Release builds compute facts and drop the checks they rule out; debug builds keep every check.
    const verify = options.facts != .on and options.facts != .off;
    const mode: passes.Mode = switch (options.facts) {
        .on => .trusted,
        .off => .off,
        .verify => .verify,
        .sabotage => .sabotage,
        .sabotage_widening => .sabotage_widening,
        .sabotage_length => .sabotage_length,
        .sabotage_overflow => .sabotage_overflow,
        .sabotage_index => .sabotage_index,
    };
    var result = if (options.release) try passes.run(allocator, module, mode) else try passes.debug(allocator, module);
    if (verify_ir.enabled) try verify_ir.check(allocator, module, result.plans, report);
    const measured = if (options.show.stats) try cost.measure(allocator, module, &result, null) else null;
    if (measured) |snapshot| try cost.stats(allocator, report, snapshot.totals);
    // One summary of the final IR serves every unit a debug build emits.
    const summaries = try @import("effects.zig").analyze(allocator, module);
    const emission: emit_llvm.Options = .{
        .locator = locator(&unit.src),
        .source_path = unit.source_path,
        .main = unit.main,
        .analysis = .{ .facts = result.known, .vectors = result.plans, .provenance = &result.provenance, .effects = &summaries },
        .verify = verify and options.release,
        .target = targetFor(options.show),
        .counters = options.show.codegen.counters,
    };
    // S4-1a: a release build is one unit, so LLVM optimizes across every module
    // boundary; a debug build is one unit per module, so an edit recompiles one unit.
    const split = if (options.release) emit_units.whole(allocator, module, emission) else emit_units.emit(allocator, module, emission);
    const units = split catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try report.print(allocator, "error[E_CORE_UNSUPPORTED]: LLVM emission failed: {s}\n", .{@errorName(err)});
            return error.Unsupported;
        },
    };
    if (options.show.llvm == null) return .{ .units = units, .cost_report = measured };
    if (options.release) return .{ .units = units, .whole = units[0].llvm, .cost_report = measured };
    const whole = emit_llvm.emitModule(allocator, module, emission) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Unsupported,
    };
    return .{ .units = units, .whole = whole, .cost_report = measured };
}

/// How emission finds a span's file, line and column in the merged source `src`.
pub fn locator(src: *const language.source.Source) emit_llvm.Locator {
    return .{ .context = src, .locate = locate };
}

fn locate(context: *const anyopaque, offset: u32) emit_llvm.Location {
    const src: *const language.source.Source = @ptrCast(@alignCast(context));
    const at = frontend.position(src.*, .{ .start = offset, .end = offset });
    return .{ .line = at.line, .column = at.column, .path = at.path };
}

/// The `Ok` and `Err` tags of `main`'s return type when it is a `Result`.
fn mainResult(program: language.typed.Program) ?emit_llvm.MainResult {
    const main = program.functions[@backingInt(program.main)];
    const shape = language.typed.resultShape(main.signature.return_type, program.records) orelse return null;
    return .{ .ok_tag = @intCast(shape.ok_tag), .error_tag = @intCast(shape.error_tag) };
}

/// The names of `main`'s parameters, which pick stdout or stderr for a `Stream`.
fn mainParameters(allocator: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const []const u8 {
    const main = program.functions[@backingInt(program.main)];
    const names = try allocator.alloc([]const u8, main.signature.parameter_count);
    for (names, main.scope.locals[0..names.len]) |*name, local| name.* = local.name;
    return names;
}

/// The target description a build uses: the generic vector fallback when asked for,
/// and the trap-frame mechanism `--trap-frames` picks.
fn targetFor(show: Show) target_description.Target {
    var target = if (show.codegen.generic_vectors) target_description.generic_256 else target_description.current;
    if (show.codegen.trap_frames) |frames| target.traps = frames;
    return target;
}

/// The path reports show for a module-headed entry file, as the front end names it and
/// the old core prints it: relative to its module root.
pub fn shownPath(src: language.source.Source, program: language.typed.Program) []const u8 {
    const main = program.functions[@backingInt(program.main)];
    const start: u32 = @intCast(main.declaration.start);
    return frontend.position(src, .{ .start = start, .end = start }).path;
}

/// Checked entry capability families distinguish Host from Stream and provider tokens.
fn mainCapabilities(allocator: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const u8 {
    const main = program.functions[@backingInt(program.main)];
    const families = try allocator.alloc(u8, main.signature.parameter_count);
    for (families, main.scope.locals[0..families.len]) |*family, local| family.* = if (local.ty.capabilityIndex()) |index| @as(u8, index) else 255;
    return families;
}
