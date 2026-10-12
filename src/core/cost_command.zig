//! Cost CLI: the build's reachable Core module and passes, without native linking.
const std = @import("std");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const ir = @import("ir.zig");
const remarks = @import("cost_remarks.zig");
const pipeline = @import("pipeline.zig");
const driver = @import("driver.zig");
const cli_run = @import("cli_run.zig");
const storage = @import("stage_store.zig");
const query = @import("cost_query.zig");
const lowering_cache = @import("lowering_cache.zig");
const stage_metrics = @import("stage_metrics.zig");
const dynamic = @import("cost_dynamic.zig");
const zero_rc_flag = @import("mylang").zero_rc_flag;

/// A malformed request is rendered as usage, with exit 2.
pub const Request = struct {
    path: []const u8,
    function: ?[]const u8 = null,
    json: bool = false,
    debug: bool = false,
    mode: passes.Mode = .trusted,
    llvm_remarks: ?[]const u8 = null,
    /// `--counters FILE.json`: a counting run's counts, added after the static report.
    counters: ?[]const u8 = null,
};
const usage = "usage: mylang cost <entry.my> [function] [--json] [--debug | --no-facts | --verify-facts] " ++
    "[--llvm-remarks FILE.opt.yaml] [--counters FILE.json] [--cache-dir DIR] [--no-cache | --verify-cache] [--cache-report] [--experimental-zero-rc]\n";

/// Parse supported modes and reject flags rather than silently changing the analysis.
pub fn parse(args: []const []const u8) ?Request {
    var request: ?Request = null;
    var index: usize = 0;
    var mode_seen = false;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--json")) {
            if (request == null) return null;
            request.?.json = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "--no-facts") or std.mem.eql(u8, arg, "--verify-facts")) {
            if (request == null or mode_seen) return null;
            mode_seen = true;
            request.?.debug = std.mem.eql(u8, arg, "--debug");
            request.?.mode = if (std.mem.eql(u8, arg, "--verify-facts")) .verify else if (std.mem.eql(u8, arg, "--no-facts")) .off else .trusted;
        } else if (std.mem.eql(u8, arg, "--llvm-remarks")) {
            if (request == null or index + 1 == args.len) return null;
            index += 1;
            request.?.llvm_remarks = args[index];
        } else if (std.mem.eql(u8, arg, "--counters")) {
            if (request == null or request.?.counters != null or index + 1 == args.len) return null;
            index += 1;
            request.?.counters = args[index];
        } else if (std.mem.eql(u8, arg, "--cache-dir")) {
            if (request == null or index + 1 == args.len) return null;
            index += 1;
        } else if (std.mem.eql(u8, arg, "--no-cache") or std.mem.eql(u8, arg, "--verify-cache") or std.mem.eql(u8, arg, "--cache-report") or std.mem.eql(u8, arg, zero_rc_flag)) {
            if (request == null) return null;
        } else if (std.mem.startsWith(u8, arg, "--")) return null else if (request == null) {
            request = .{ .path = arg };
        } else if (request.?.function == null) {
            request.?.function = arg;
        } else return null;
    }
    return request;
}

/// Errors already have diagnostics; other failures propagate to the shared CLI.
pub const Error = frontend.Error || build.Error || project_entry.Error || pipeline.Error || std.Io.File.Writer.Error;

/// Rendered command output and its diagnosed exit status.
pub const Output = struct { text: []const u8 = "", status: u8 = 0 };

/// Run one cost analysis and write its result.
pub fn run(init: std.process.Init, args: []const []const u8) Error!u8 {
    const request = parse(args) orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    };
    const rendered = try outputWithQuery(init, request, QueryOptions.parse(args));
    try std.Io.File.stdout().writeStreamingAll(init.io, rendered.text);
    return rendered.status;
}

/// Shared output for cost and list-interfaces --cost; one pipeline and schema.
pub fn output(init: std.process.Init, request: Request) Error!Output {
    return outputWithQuery(init, request, .{});
}

/// Native query policy, separate from the established seven-field cost request.
pub const QueryOptions = struct {
    cache: []const u8 = ".mylang-cache/core",
    enabled: bool = true,
    verify: bool = false,
    report: bool = false,
    codegen: pipeline.Codegen = .{},

    fn parse(args: []const []const u8) QueryOptions {
        var options: QueryOptions = .{};
        var index: usize = 0;
        while (index < args.len) : (index += 1) {
            if (std.mem.eql(u8, args[index], "--cache-dir")) {
                index += 1;
                options.cache = args[index];
            } else if (std.mem.eql(u8, args[index], "--llvm-remarks") or std.mem.eql(u8, args[index], "--counters")) {
                index += 1;
            } else if (std.mem.eql(u8, args[index], "--no-cache")) {
                options.enabled = false;
            } else if (std.mem.eql(u8, args[index], "--verify-cache")) {
                options.verify = true;
            } else if (std.mem.eql(u8, args[index], "--cache-report")) {
                options.report = true;
            } else if (std.mem.eql(u8, args[index], zero_rc_flag)) {
                options.codegen.single_owner = true;
                options.codegen.zero_rc = true;
            }
        }
        return options;
    }
};

/// Check current sources and reuse only exact compiler-query inputs.
pub fn outputWithQuery(given: std.process.Init, request: Request, policy: QueryOptions) Error!Output {
    const init = try @import("compiler_sharing.zig").prepare(given, !policy.enabled or policy.verify);
    const a = init.arena.allocator();
    var store = try storage.Store.init(init.gpa, init.io, policy.cache);
    defer store.deinit();
    var queries: query.Cache = .{ .store = &store, .verify = policy.verify };
    var stages: stage_metrics.Report = .{};
    var lowering = lowering_cache.Cache.init(&store);
    var diagnostics: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(a, init.io, request.path, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    session.setOwnership(policy.codegen.single_owner, policy.codegen.zero_rc);
    entry.configure(&session);
    if (policy.enabled and !policy.verify) {
        try session.enableCache(init.gpa, policy.cache);
        try session.enableSharedCache(init.environ_map);
    }
    const checked = session.checkFile(a, request.path, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    entry.validate(a, &session, &diagnostics) catch |err| return failure(init, diagnostics.items, err);
    if (policy.codegen.single_owner and !try @import("single_owner.zig").validateMode(a, checked.program, checked.src, .text, &diagnostics, policy.codegen.zero_rc)) {
        return failure(init, diagnostics.items, error.SourceError);
    }
    var refusal: build.Refusal = .{};
    const input = loweringInput(checked, request, policy.codegen);
    var module = (if (policy.enabled and !policy.verify) build.buildExecutableCached(a, input, &refusal, &lowering) else build.buildExecutable(a, input, &refusal)) catch |err| {
        if (err != error.Unsupported) return err;
        const at = frontend.position(checked.src, .{ .start = refusal.span, .end = refusal.span });
        try diagnostics.print(a, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: the new core does not support {s} yet\n", .{ at.path, at.line, at.column, refusal.reason });
        return failure(init, diagnostics.items, err);
    };
    const options: pipeline.Options = .{
        .zig = cli_run.zigPath(init),
        .mode = if (request.debug) .debug else .release,
        .facts = if (request.mode == .verify) .verify else if (request.mode == .off) .off else .on,
        .show = .{ .stats = true, .codegen = policy.codegen },
        .cache = policy.cache,
    };
    const unit = try pipeline.unitFor(a, checked, entry.path, session.single != null);
    const emission = (if (policy.enabled) pipeline.emittedQuery(.{ .arena = a, .backing = init.gpa }, &module, unit, options, .{
        .store = &store,
        .io = init.io,
        .metrics = &stages,
        .cost = &queries,
        .fresh = policy.verify,
    }, &diagnostics) else pipeline.emittedWithScratch(a, init.gpa, &module, unit, options, &diagnostics)) catch |err| return failure(init, diagnostics.items, err);
    var report = emission.cost_report.?;
    if (!policy.enabled) queries.statistics = .{ .computed = report.functions.len, .bypassed = report.functions.len };
    var llvm_work: struct { processes: u32 = 0, reused: u32 = 0 } = .{};
    if (request.llvm_remarks == null) {
        const captured = try driver.optimizationRemarks(a, init.io, init.environ_map, .{
            .zig = options.zig,
            .work = options.cache,
            .output = "",
            .mode = options.mode,
            .links = &.{},
            .units = emission.units,
            .verify = !policy.enabled or policy.verify,
        });
        llvm_work = .{ .processes = captured.processes, .reused = captured.reused };
        if (captured.yaml) |yaml| remarks.apply(&report, yaml);
        var timing: std.ArrayList(u8) = .empty;
        try cost.llvmStats(a, &timing, report.totals, captured);
        try std.Io.File.stderr().writeStreamingAll(init.io, timing.items);
    }
    if (policy.enabled) _ = try store.flush();
    if (policy.report) {
        const work = .{
            .version = "cost-query-work-v1",
            .policy = .{ .enabled = policy.enabled, .verify = policy.verify, .stage_instrumentation = policy.enabled and !policy.verify },
            .frontend = session.statistics(),
            .lowering = .{ .reused = lowering.reused, .computed = lowering.lowered },
            .optimizer = stages.optimizer,
            .cost = queries.statistics,
            .llvm = llvm_work,
        };
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, work, .{})}));
    }
    report = try cost.select(a, report, request.function);
    if (report.functions.len == 0) {
        const message = try std.fmt.allocPrint(a, "mylang cost: no reachable function named {s}\n", .{request.function orelse "<entry>"});
        try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return .{ .status = 2 };
    }
    if (request.llvm_remarks) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch {
            try std.Io.File.stderr().writeStreamingAll(init.io, "mylang cost: cannot read LLVM optimization remarks\n");
            return .{ .status = 2 };
        };
        remarks.apply(&report, bytes);
    }
    const path = request.counters orelse return .{ .text = try cost.render(a, report, request.json) };
    const document = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(256 << 20)) catch {
        try std.Io.File.stderr().writeStreamingAll(init.io, "mylang cost: cannot read the counters file\n");
        return .{ .status = 2 };
    };
    const section = dynamic.rows(a, report, document) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCounters => {
            try std.Io.File.stderr().writeStreamingAll(init.io, "mylang cost: the counters file is not a mylang-counters-v1 document\n");
            return .{ .status = 2 };
        },
    };
    return .{ .text = try withCounters(a, report, section, request.json) };
}

/// The static report followed by the counters section, as text or as one JSON document
/// whose `counters` member follows the static members unchanged.
fn withCounters(a: std.mem.Allocator, report: cost.Report, section: []const dynamic.Row, json: bool) std.mem.Allocator.Error![]const u8 {
    if (json) {
        const document = .{ .version = report.version, .functions = report.functions, .totals = report.totals, .counters = section };
        return std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, document, .{})});
    }
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, try cost.render(a, report, false));
    try dynamic.render(a, &out, section);
    return out.toOwnedSlice(a);
}

fn failure(init: std.process.Init, text: []const u8, err: anyerror) Error!Output {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    try std.Io.File.stderr().writeStreamingAll(init.io, text);
    return .{ .status = if (err == error.PolicyDenied) 3 else if (err == error.ConfigurationFailed or err == error.ToolFailed or err == error.InvalidIr or err == error.WriteFailed) 2 else 1 };
}

/// Cost reports lower the same source ownership and ABI that emission verifies.
fn loweringInput(checked: frontend.Checked, request: Request, codegen: pipeline.Codegen) build.Input {
    return .{
        .program = checked.program,
        .source = checked.src,
        .drop_debug = !request.debug,
        .single_owner = codegen.single_owner,
        .zero_rc = codegen.zero_rc,
    };
}

// spec-case: NEW-CORE-ZERO-RC-3
test "zero RC cost lowering and emission select the count-free ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const arguments = [_][]const u8{ "cost.my", zero_rc_flag };
    const request = parse(&arguments).?;
    const policy = QueryOptions.parse(&arguments);
    var unit = try @import("mylang").Compilation.init(a, "cost.my", "func main() -> int:\n    const value = \"value-\" + str(7)\n    return len(value)\n");
    defer unit.deinit();
    try unit.check();
    const checked: frontend.Checked = .{ .program = unit.program.?, .src = unit.src };
    var why: build.Refusal = .{};
    var module = try build.buildExecutable(a, loweringInput(checked, request, policy.codegen), &why);
    try std.testing.expect(module.single_owner and module.zero_rc);
    var report: std.ArrayList(u8) = .empty;
    const emission = try pipeline.emittedWithScratch(a, a, &module, .{ .src = checked.src, .source_path = "cost.my", .main = .{} }, .{
        .zig = "unused",
        .show = .{ .llvm = "unused", .codegen = policy.codegen },
    }, &report);
    try std.testing.expect(std.mem.indexOf(u8, emission.whole.?, "; mylang-zero-rc-v2") != null);
    try std.testing.expect(@import("zero_rc.zig").emittedClean(emission.whole.?));
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts inspect borrowed views without legacy lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contracts = @import("allocation_contract.zig");
    var compilation = try @import("mylang").Compilation.init(a, "view.my",
        \\func prefix_length(text: str) -> int noalloc:
        \\    const part = text.borrow(0, 2)
        \\    return len(part)
    );
    const program = try compilation.checkLibraryProgram();
    const legacy = try contracts.collectProgram(a, program, compilation.src);
    try std.testing.expectEqual(@as(usize, 1), legacy.len);
    try std.testing.expect(legacy[0].unsupported != null);
    const owned = try contracts.collectProgramWithOwnership(a, program, compilation.src, .{ .single_owner = true, .zero_rc = true });
    try std.testing.expectEqual(@as(usize, 0), owned.len);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts count independent encode and buffer reverse copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contracts = @import("allocation_contract.zig");
    var compilation = try @import("mylang").Compilation.init(a, "encode.my",
        \\func encoded(text: str) -> bytes noalloc:
        \\    return text.encode()
    );
    const program = try compilation.checkLibraryProgram();
    const legacy = try contracts.collectProgram(a, program, compilation.src);
    try std.testing.expectEqual(@as(usize, 0), legacy.len);
    const owned = try contracts.collectProgramWithOwnership(a, program, compilation.src, .{ .single_owner = true, .zero_rc = true });
    try std.testing.expectEqual(@as(usize, 1), owned.len);
    try std.testing.expect(owned[0].unsupported == null and !owned[0].unresolved);
    var copying = try @import("mylang").Compilation.init(a, "copy.my",
        \\func copied(text: str) -> str noalloc:
        \\    return text.copy()
    );
    const copied_program = try copying.checkLibraryProgram();
    const copies = try contracts.collectProgramWithOwnership(a, copied_program, copying.src, .{ .single_owner = true, .zero_rc = true });
    try std.testing.expectEqual(@as(usize, 1), copies.len);
    for ([_]bool{ false, true }) |zero_rc| {
        var module: ir.Module = .{ .single_owner = zero_rc, .zero_rc = zero_rc };
        try module.functions.append(a, .{ .name = "myl_core_buffer_reverse", .signature = .{ .params = &.{.byte_buffer}, .ret = .byte_buffer, .linkage = .runtime_c } });
        const function: ir.Function = .{ .name = "caller", .signature = .{ .params = &.{}, .ret = .void } };
        try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, .{ .op = .call, .a = @fromBackingInt(0), .ty = .byte_buffer }));
    }
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts audit borrowed identity queries without source extern authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .single_owner = true, .zero_rc = true };
    const list = try module.intern(a, .{ .list = .i64 });
    try module.functions.append(a, .{ .name = "myl_core_owned_same_block", .signature = .{ .params = &.{ list, list }, .ret = .i64, .linkage = .runtime_c } });
    const call: ir.Inst = .{ .op = .call, .a = @fromBackingInt(0), .ty = .i64 };
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
    // A source-spanned foreign declaration cannot claim the compiler's audit.
    module.functions.items[0].signature.linkage = .extern_c;
    module.functions.items[0].span = 13;
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &module.functions.items[0], call));
    var foreign = try @import("mylang").Compilation.init(a, "foreign.my",
        \\extern func myl_core_owned_same_block(host: Host) -> int effects(host)
        \\func bounded(host: Host) -> int noalloc:
        \\    return myl_core_owned_same_block(host)
    );
    try std.testing.expectError(error.SourceError, foreign.checkLibraryProgram());
    try std.testing.expectEqualStrings("E_EXTERN_SYMBOL", foreign.diagnostics.items[0].code);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts require validated aggregate provider pin markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{ .single_owner = true, .zero_rc = true };
    const record = try module.intern(a, .{ .record = &.{ .i64, .capability } });
    const canonical = try std.fmt.allocPrint(a, "{s}{d}", .{ @import("aggregate_provider.zig").prefix, @backingInt(record) });
    const marker: ir.Function = .{ .name = canonical, .signature = .{ .params = &.{record}, .ret = .void, .linkage = .runtime_c } };
    try module.functions.append(a, marker);
    const call: ir.Inst = .{ .op = .call, .a = @fromBackingInt(0), .ty = .void };
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
    module.zero_rc = false;
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &module.functions.items[0], call));
    module.zero_rc = true;
    for (0..9) |invalid| {
        module.functions.items[0] = marker;
        const callee = &module.functions.items[0];
        switch (invalid) {
            0 => callee.signature.params = &.{.i64},
            1 => callee.signature.ret = .i64,
            2 => callee.signature.owned = 1,
            3 => callee.signature.consumes = 1,
            4 => callee.signature.views = 1,
            5 => {
                callee.signature.linkage = .extern_c;
                callee.span = 13;
            },
            6 => callee.name = try std.fmt.allocPrint(a, "{s}0{d}", .{ @import("aggregate_provider.zig").prefix, @backingInt(record) }),
            7 => callee.name = "myl_core_provider_pin_4294967295",
            8 => callee.signature.params = &.{},
            else => unreachable,
        }
        try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, callee, call));
    }
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts audit scalar rounding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var compilation = try @import("mylang").Compilation.init(a, "round.my",
        \\func rounded(value: float, digits: int) -> float noalloc:
        \\    return round(value, digits)
    );
    const program = try compilation.checkLibraryProgram();
    const failures = try @import("allocation_contract.zig").collectProgramWithOwnership(a, program, compilation.src, .{ .single_owner = true, .zero_rc = true });
    try std.testing.expectEqual(@as(usize, 0), failures.len);
    var module: ir.Module = .{ .single_owner = true, .zero_rc = true };
    try module.functions.append(a, .{ .name = "myl_core_round_float", .signature = .{ .params = &.{ .f64, .i64 }, .ret = .f64, .linkage = .runtime_c } });
    const call: ir.Inst = .{ .op = .call, .a = @fromBackingInt(0), .ty = .f64 };
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
    module.functions.items[0].signature.linkage = .extern_c;
    module.functions.items[0].span = 13;
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &module.functions.items[0], call));
    module.functions.items[0].signature.linkage = .runtime_c;
    module.functions.items[0].span = 0;
    module.functions.items[0].name = "myl_core_round_float_unreviewed";
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &module.functions.items[0], call));
}
