//! Cost CLI: the build's reachable Core module and passes, without native linking.
const std = @import("std");
const product = @import("selka").product;
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const cost = @import("cost.zig");
const clause_report = @import("clause_report.zig");
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
const typed = @import("selka").typed;
const source = @import("selka").source;

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
const usage = "usage: selka cost <entry.selka> [function] [--json] [--sites | --clauses [--asserts]] [--debug | --no-facts | --verify-facts] " ++
    "[--llvm-remarks FILE.opt.yaml] [--counters FILE.json] [--cache-dir DIR] [--no-cache | --verify-cache] [--cache-report]\n";

/// Parse supported modes and reject flags rather than silently changing the analysis.
pub fn parse(args: []const []const u8) ?Request {
    var request: ?Request = null;
    var index: usize = 0;
    var mode_seen = false;
    var sections: Sections = .{};
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
        } else if (Sections.named(arg)) {
            if (request == null or !sections.accept(arg, request.?.counters != null)) return null;
        } else if (std.mem.eql(u8, arg, "--counters")) {
            const taken = sections.sites or sections.clauses;
            if (request == null or taken or request.?.counters != null or index + 1 == args.len) return null;
            index += 1;
            request.?.counters = args[index];
        } else if (std.mem.eql(u8, arg, "--cache-dir")) {
            if (request == null or index + 1 == args.len) return null;
            index += 1;
        } else if (std.mem.eql(u8, arg, "--no-cache") or std.mem.eql(u8, arg, "--verify-cache") or std.mem.eql(u8, arg, "--cache-report")) {
            if (request == null) return null;
        } else if (std.mem.startsWith(u8, arg, "--")) return null else if (request == null) {
            request = .{ .path = arg };
        } else if (request.?.function == null) {
            request.?.function = arg;
        } else return null;
    }
    // `--asserts` adds rows to the clause section, so it needs `--clauses`.
    if (sections.asserts and !sections.clauses) return null;
    return request;
}

/// The section flags seen so far: `--sites`, or `--clauses` with `--asserts`. A request prints at most one section,
/// and none beside a counters file, which describes a run rather than the build.
const Sections = struct {
    sites: bool = false,
    clauses: bool = false,
    asserts: bool = false,

    fn named(arg: []const u8) bool {
        return std.mem.eql(u8, arg, "--sites") or std.mem.eql(u8, arg, "--clauses") or std.mem.eql(u8, arg, "--asserts");
    }

    /// Record the section flag `arg` and say whether it may join the flags seen so far.
    fn accept(self: *Sections, arg: []const u8, counters: bool) bool {
        if (counters or self.sites) return false;
        const sites = std.mem.eql(u8, arg, "--sites");
        const slot = if (sites) &self.sites else if (std.mem.eql(u8, arg, "--clauses")) &self.clauses else &self.asserts;
        if (slot.* or (sites and (self.clauses or self.asserts))) return false;
        slot.* = true;
        return true;
    }
};

/// Errors already have diagnostics; other failures propagate to the shared CLI.
pub const Error = frontend.Error || build.Error || project_entry.Error || pipeline.Error || std.Io.File.Writer.Error;

/// Rendered command output and its diagnosed exit status.
pub const Output = struct {
    text: []const u8 = "",
    status: u8 = 0,
    /// `--sites` rows, for a caller that reads the analysis instead of printing it.
    sites: []const cost.Site = &.{},
    /// The diagnostics a failed analysis rendered (also written to standard error unless the caller is a reader); empty on success.
    diagnostics: []const u8 = "",
};

/// Run one cost analysis and write its result.
pub fn run(init: std.process.Init, args: []const []const u8) Error!u8 {
    const request = parse(args) orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, usage);
        return 2;
    };
    // The project's `stores`, before any store opens (FR8).
    if (try @import("cli_run.zig").applyStores(init, request.path, false)) return 2;
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
    cache: []const u8 = product.core_work_dir,
    enabled: bool = true,
    verify: bool = false,
    report: bool = false,
    /// `--sites`: also enumerate the final allocation and copy sites; `--clauses` (with `--asserts`): print the
    /// clause section instead (`clause_report.zig`).
    section: Section = .cost,
    codegen: pipeline.Codegen = .{},
    /// A reader wants the rows, not a report: leave LLVM out of the analysis
    /// (collecting remarks compiles the units) and write no diagnostics.
    reader: bool = false,

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
            } else if (std.mem.eql(u8, args[index], "--sites")) {
                options.section = .sites;
            } else if (std.mem.eql(u8, args[index], "--clauses")) {
                if (options.section != .clauses_and_asserts) options.section = .clauses;
            } else if (std.mem.eql(u8, args[index], "--asserts")) {
                options.section = .clauses_and_asserts;
            }
        }
        return options;
    }
};

/// The static sites of the functions the `roots` of a program with no `main` reach (its discovered tests), after the same
/// release passes `cost --sites` runs, with LLVM left out. `cost --sites` follows only the functions `main` reaches, so a
/// test file, which has none, has no rows without this. One root the Core refuses is left out; the others still answer.
pub fn rootSites(a: std.mem.Allocator, checked: Checked, roots: []const typed.FunctionId, entry_path: []const u8) std.mem.Allocator.Error![]const cost.Site {
    if (roots.len == 0) return &.{};
    var refusal: build.Refusal = .{};
    var module = build.buildRootsCached(a, roots, .{ .program = checked.program, .source = checked.src, .drop_debug = true }, &refusal, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.CacheMiss => unreachable,
        error.Unsupported => return aloneSites(a, checked, roots, entry_path),
    };
    const result = passes.run(a, &module, .trusted) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return aloneSites(a, checked, roots, entry_path),
    };
    return cost.sites(a, &module, &result, pipeline.locator(&checked.src), entry_path, checked.src.bytes);
}

/// The sites of each root built alone, for the roots the Core accepts, when the roots together were refused.
fn aloneSites(a: std.mem.Allocator, checked: Checked, roots: []const typed.FunctionId, entry_path: []const u8) std.mem.Allocator.Error![]const cost.Site {
    if (roots.len < 2) return &.{};
    var rows: std.ArrayList(cost.Site) = .empty;
    for (roots) |root| try rows.appendSlice(a, try rootSites(a, checked, &.{root}, entry_path));
    return rows.toOwnedSlice(a);
}

/// A checked program and the merged source its spans index.
pub const Checked = struct { program: typed.Program, src: source.Source };

/// The section a cost request prints after (or instead of) the function rows.
pub const Section = enum { cost, sites, clauses, clauses_and_asserts };

/// Check current sources and reuse only exact compiler-query inputs.
pub fn outputWithQuery(given: std.process.Init, request: Request, policy: QueryOptions) Error!Output {
    const init = try @import("compiler_sharing.zig").prepare(given, !policy.enabled or policy.verify);
    const a = init.arena.allocator();
    // The query store is open until this returns: its work directory is held, so no collection removes a pack it lists.
    const lease = try @import("work_retention.zig").hold(a, init.io, policy.cache);
    defer lease.release();
    var store = try storage.Store.init(init.gpa, init.io, policy.cache);
    defer store.deinit();
    var queries: query.Cache = .{ .store = &store, .verify = policy.verify };
    var stages: stage_metrics.Report = .{};
    var lowering = lowering_cache.Cache.init(&store);
    var diagnostics: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(a, init.io, request.path, &diagnostics) catch |err| return failure(init, policy, diagnostics.items, err);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    entry.configure(&session);
    if (policy.enabled and !policy.verify) {
        try session.enableCache(init.gpa, policy.cache);
        try session.enableSharedCache(init.environ_map);
    }
    const checked = session.checkFile(a, request.path, &diagnostics) catch |err| return failure(init, policy, diagnostics.items, err);
    entry.validate(a, &session, &diagnostics) catch |err| return failure(init, policy, diagnostics.items, err);
    if (!try @import("single_owner.zig").validate(a, init.gpa, checked.program, checked.src, .text, &diagnostics)) {
        return failure(init, policy, diagnostics.items, error.SourceError);
    }
    var refusal: build.Refusal = .{};
    const input = loweringInput(checked, request);
    var module = (if (policy.enabled and !policy.verify) build.buildExecutableCached(a, input, &refusal, &lowering) else build.buildExecutable(a, input, &refusal)) catch |err| {
        if (err != error.Unsupported) return err;
        try pipeline.reportBuildRefusal(a, checked.src, refusal, .text, &diagnostics);
        return failure(init, policy, diagnostics.items, err);
    };
    const options: pipeline.Options = .{
        .zig = cli_run.zigPath(init),
        .mode = if (request.debug) .debug else .release,
        .facts = if (request.mode == .verify) .verify else if (request.mode == .off) .off else .on,
        .show = .{ .stats = true, .codegen = policy.codegen },
        .cache = policy.cache,
    };
    const unit = try pipeline.unitFor(a, checked, entry.path, session.single != null);
    const query_memory: pipeline.QueryMemory = .{ .arena = a, .backing = init.gpa };
    const query_context: pipeline.QueryContext = .{ .store = &store, .io = init.io, .metrics = &stages, .cost = &queries, .fresh = policy.verify, .sites = policy.section == .sites };
    const emission = (if (policy.enabled)
        pipeline.emittedQuery(query_memory, &module, unit, options, query_context, &diagnostics)
    else if (policy.section == .sites)
        pipeline.emittedCost(a, init.gpa, &module, unit, options, &diagnostics)
    else
        pipeline.emittedWithScratch(a, init.gpa, &module, unit, options, &diagnostics)) catch |err| return failure(init, policy, diagnostics.items, err);
    var report = emission.cost_report.?;
    if (!policy.enabled) queries.statistics = .{ .computed = report.functions.len, .bypassed = report.functions.len };
    var llvm_work: struct { processes: u32 = 0, reused: u32 = 0 } = .{};
    if (request.llvm_remarks == null and !policy.reader) {
        const captured = try driver.optimizationRemarks(a, init.io, init.environ_map, .{
            .zig = options.zig,
            .work = options.cache,
            .output = "",
            .family = .{ .mode = options.mode },
            .links = &.{},
            .units = emission.units,
            .inspection = .{ .verify = !policy.enabled or policy.verify },
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
            .lowering = .{ .reused = lowering.counts.reused, .computed = lowering.counts.lowered },
            .optimizer = stages.optimizer,
            .cost = queries.statistics,
            .llvm = llvm_work,
        };
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "{s}\n", .{try std.json.Stringify.valueAlloc(a, work, .{})}));
    }
    report = try cost.select(a, report, request.function);
    const site_rows = try cost.selectSites(a, emission.sites, request.function);
    const listing_clauses = policy.section == .clauses or policy.section == .clauses_and_asserts;
    const clauses = try clause_report.select(a, emission.clauses, request.function);
    // A record's invariant has no function row of its own; selecting the record by name lists its clauses.
    if (report.functions.len == 0 and !(listing_clauses and clauses.clauses.len != 0)) {
        const message = try std.fmt.allocPrint(a, "selka cost: no reachable function named {s}\n", .{request.function orelse "<entry>"});
        if (!policy.reader) try std.Io.File.stderr().writeStreamingAll(init.io, message);
        return .{ .status = 2 };
    }
    if (request.llvm_remarks) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(64 << 20)) catch {
            try std.Io.File.stderr().writeStreamingAll(init.io, "selka cost: cannot read LLVM optimization remarks\n");
            return .{ .status = 2 };
        };
        remarks.apply(&report, bytes);
    }
    if (policy.section == .sites) return .{ .text = try cost.renderSites(a, report, site_rows, request.json), .sites = try ownedSites(a, site_rows) };
    if (listing_clauses) {
        return .{ .text = try clause_report.render(a, report, clauses, .{ .json = request.json, .asserts = policy.section == .clauses_and_asserts }) };
    }
    const path = request.counters orelse return .{ .text = try cost.render(a, report, request.json) };
    const document = std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(256 << 20)) catch {
        try std.Io.File.stderr().writeStreamingAll(init.io, "selka cost: cannot read the counters file\n");
        return .{ .status = 2 };
    };
    const section = dynamic.rows(a, report, document) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCounters => {
            try std.Io.File.stderr().writeStreamingAll(init.io, "selka cost: the counters file is not a selka-counters-v1 document\n");
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

/// Copy a site row's borrowed text into `a`: a reader keeps the rows after the
/// session that mapped their source positions is closed.
fn ownedSites(a: std.mem.Allocator, rows: []const cost.Site) std.mem.Allocator.Error![]const cost.Site {
    const owned = try a.alloc(cost.Site, rows.len);
    for (rows, owned) |row, *site| {
        site.* = row;
        site.function = try a.dupe(u8, row.function);
        site.path = try a.dupe(u8, row.path);
    }
    return owned;
}

fn failure(init: std.process.Init, policy: QueryOptions, text: []const u8, err: anyerror) Error!Output {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    if (!policy.reader) try std.Io.File.stderr().writeStreamingAll(init.io, text);
    return .{
        .status = if (err == error.PolicyDenied) 3 else if (err == error.ConfigurationFailed or err == error.ToolFailed or err == error.InvalidIr or err == error.WriteFailed) 2 else 1,
        .diagnostics = text,
    };
}

/// Cost reports lower the same source ownership and ABI that emission verifies.
fn loweringInput(checked: frontend.Checked, request: Request) build.Input {
    return .{
        .program = checked.program,
        .source = checked.src,
        .drop_debug = !request.debug,
    };
}

// spec-case: NEW-CORE-ZERO-RC-3
test "zero RC cost lowering and emission select the count-free ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const arguments = [_][]const u8{"cost.selka"};
    const request = parse(&arguments).?;
    const policy = QueryOptions.parse(&arguments);
    var unit = try @import("selka").Compilation.init(a, "cost.selka", "func main() -> int:\n    const value = \"value-\" + str(7)\n    return strings.char_count(value)\n");
    defer unit.deinit();
    try unit.check();
    const checked: frontend.Checked = .{ .program = unit.program.?, .src = unit.src };
    var why: build.Refusal = .{};
    var module = try build.buildExecutable(a, loweringInput(checked, request), &why);
    var report: std.ArrayList(u8) = .empty;
    const emission = try pipeline.emittedWithScratch(a, a, &module, .{ .src = checked.src, .source_path = "cost.selka", .main = .{} }, .{
        .zig = "unused",
        .show = .{ .llvm = "unused", .codegen = policy.codegen },
    }, &report);
    try std.testing.expect(std.mem.indexOf(u8, emission.whole.?, "; selka-zero-rc-v2") != null);
    try std.testing.expect(@import("zero_rc.zig").emittedClean(emission.whole.?));
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts inspect borrowed views without legacy lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contracts = @import("allocation_contract.zig");
    var compilation = try @import("selka").Compilation.init(a, "view.selka",
        \\@noalloc
        \\func prefix_length(text: str) -> int:
        \\    const part = text[0:2]
        \\    return len(part)
    );
    const program = try compilation.checkLibraryProgram();
    const owned = try contracts.collectProgram(a, program, compilation.src);
    try std.testing.expectEqual(@as(usize, 0), owned.len);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts count independent encode and buffer reverse copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const contracts = @import("allocation_contract.zig");
    // `strings.encode` needs `import strings` (W13-S5), so this library is checked as an embedded project.
    const library = try @import("test_support.zig").libraryProject(a,
        \\import strings
        \\
        \\@noalloc
        \\func encoded(text: str) -> bytes:
        \\    return strings.encode(text)
    );
    const owned = try contracts.collectProgram(a, library.program, library.src);
    try std.testing.expectEqual(@as(usize, 1), owned.len);
    try std.testing.expect(owned[0].unsupported == null and !owned[0].unresolved);
    var copying = try @import("selka").Compilation.init(a, "copy.selka",
        \\@noalloc
        \\func copied(text: str) -> str:
        \\    return copy(text)
    );
    const copied_program = try copying.checkLibraryProgram();
    const copies = try contracts.collectProgram(a, copied_program, copying.src);
    try std.testing.expectEqual(@as(usize, 1), copies.len);
    {
        var module: ir.Module = .{};
        try module.functions.append(a, .{ .name = "myl_core_buffer_reverse", .signature = .{ .params = &.{.byte_buffer}, .ret = .byte_buffer, .linkage = .runtime_c } });
        const function: ir.Function = .{ .name = "caller", .signature = .{ .params = &.{}, .ret = .void } };
        // The reverse is in place: the receiver is consumed and returned, so it allocates nothing.
        try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .call, .a = @fromBackingInt(0), .ty = .byte_buffer }));
    }
    {
        var module: ir.Module = .{};
        try module.functions.append(a, .{ .name = "myl_core_buffer_clear", .signature = .{ .params = &.{.byte_buffer}, .ret = .byte_buffer, .linkage = .runtime_c } });
        const function: ir.Function = .{ .name = "caller", .signature = .{ .params = &.{}, .ret = .void } };
        // `buffers.clear` keeps the storage: the receiver is consumed and returned with its length at 0, so it allocates nothing.
        try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, .{ .op = .call, .a = @fromBackingInt(0), .ty = .byte_buffer }));
    }
}

/// The Core function of the checked program whose name ends `name`.
fn namedRoot(program: typed.Program, name: []const u8) typed.FunctionId {
    for (program.functions) |function| if (std.mem.endsWith(u8, function.name, name)) return function.id;
    unreachable;
}

/// How many of `rows` are a copy at loop depth 1 or more.
fn copiesInLoops(rows: []const cost.Site) usize {
    var count: usize = 0;
    for (rows) |row| count += @intFromBool(row.kind == .copy and row.loop_depth >= 1);
    return count;
}

test "root sites give a test's copy in a loop, where a program with no main has no cost rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const library = try @import("test_support.zig").libraryProject(a,
        \\func gather(rows: str[]) -> str[]:
        \\    mut kept: str[] = []
        \\    for row in rows:
        \\        append(mut kept, copy(row))
        \\    return kept
        \\
        \\
        \\func unreached(rows: str[]) -> str[]:
        \\    mut kept: str[] = []
        \\    for row in rows:
        \\        append(mut kept, copy(row))
        \\    return kept
        \\
        \\
        \\public func test_gather() -> bool:
        \\    return len(gather(["a", "b"])) == 2
    );
    const checked: Checked = .{ .program = library.program, .src = library.src };
    // The test reaches `gather`, so its copy in the loop is a row; `unreached` is reached by no test, so its copy is not.
    const rows = try rootSites(a, checked, &.{namedRoot(library.program, "test_gather")}, "gather_test.selka");
    try std.testing.expectEqual(@as(usize, 1), copiesInLoops(rows));
    // No root, no rows.
    try std.testing.expectEqual(@as(usize, 0), (try rootSites(a, checked, &.{}, "gather_test.selka")).len);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts audit borrowed identity queries without source extern authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    try module.functions.append(a, .{ .name = "myl_core_owned_same_block", .signature = .{ .params = &.{ list, list }, .ret = .i64, .linkage = .runtime_c } });
    const call: ir.Inst = .{ .op = .call, .a = @fromBackingInt(0), .ty = .i64 };
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
    // A source-spanned foreign declaration cannot claim the compiler's audit.
    module.functions.items[0].signature.linkage = .extern_c;
    module.functions.items[0].span = 13;
    try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, &module.functions.items[0], call));
    const original =
        // migrate-embedded: skip intentional original effects-removal witness
        \\extern func myl_core_owned_same_block(host: Host) -> int effects(host)
        \\func bounded(host: Host) -> int noalloc:
        \\    return myl_core_owned_same_block(host)
    ;
    var retired = try @import("selka").Compilation.init(a, "foreign-original.selka", original);
    try std.testing.expectError(error.SourceError, retired.checkLibraryProgram());
    try std.testing.expectEqualStrings("E_EFFECTS_REMOVED", retired.diagnostics.items[0].code);
    // Modern allocation syntax must not grant source externs runtime authority.
    var foreign = try @import("selka").Compilation.init(a, "foreign.selka",
        \\extern func myl_core_owned_same_block(host: Host) -> int
        \\@noalloc
        \\func bounded(host: Host) -> int:
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
    var module: ir.Module = .{};
    const record = try module.intern(a, .{ .record = &.{ .i64, .capability } });
    var keys: @import("stable_names.zig").TypeKeys = .{};
    const canonical = try @import("stable_names.zig").helperName(a, &keys, &module, @import("aggregate_provider.zig").prefix, &.{record});
    const marker: ir.Function = .{ .name = canonical, .signature = .{ .params = &.{record}, .ret = .void, .linkage = .runtime_c } };
    try module.functions.append(a, marker);
    const call: ir.Inst = .{ .op = .call, .a = @fromBackingInt(0), .ty = .void };
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
    for (0..9) |invalid| {
        module.functions.items[0] = marker;
        const callee = &module.functions.items[0];
        switch (invalid) {
            0 => callee.signature.params = &.{.i64},
            1 => callee.signature.ret = .i64,
            2 => callee.signature.passing.owned = 1,
            3 => callee.signature.passing.consumes = 1,
            4 => callee.signature.passing.views = 1,
            5 => {
                callee.signature.linkage = .extern_c;
                callee.span = 13;
            },
            6 => callee.name = try std.fmt.allocPrint(a, "{s}0{s}", .{ @import("aggregate_provider.zig").prefix, callee.name[@import("aggregate_provider.zig").prefix.len..] }),
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
    var compilation = try @import("selka").Compilation.init(a, "round.selka",
        \\@noalloc
        \\func rounded(value: float, digits: int) -> float:
        \\    return round(value, digits)
    );
    const program = try compilation.checkLibraryProgram();
    const failures = try @import("allocation_contract.zig").collectProgram(a, program, compilation.src);
    try std.testing.expectEqual(@as(usize, 0), failures.len);
    var module: ir.Module = .{};
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

// spec-case: FRONTEND-CORE-NOALLOC-1
test "zero RC allocation contracts require validated borrowed selection markers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const dictionary = try module.intern(a, .{ .dict = .{ .key = .i64, .value = .str } });
    var selection_keys: @import("stable_names.zig").TypeKeys = .{};
    const name = try @import("stable_names.zig").helperName(a, &selection_keys, &module, @import("borrow_selection.zig").prefix, &.{ dictionary, .str });
    const marker: ir.Function = .{ .name = name, .signature = .{ .params = &.{ .str, dictionary, .str }, .ret = .str, .linkage = .runtime_c } };
    try module.functions.append(a, marker);
    const call: ir.Inst = .{ .op = .call, .a = @fromBackingInt(0), .ty = .str };
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &module.functions.items[0], call));
    for (0..10) |invalid| {
        module.functions.items[0] = marker;
        const callee = &module.functions.items[0];
        switch (invalid) {
            0 => callee.signature.params = &.{ .str, dictionary },
            1 => callee.signature.ret = .i64,
            2 => callee.signature.passing.owned = 1,
            3 => callee.signature.passing.consumes = 1,
            4 => callee.signature.passing.views = 1,
            5 => {
                callee.signature.linkage = .extern_c;
                callee.span = 13;
            },
            6 => callee.name = "myl_core_borrow_select_v1_01_5",
            7 => callee.name = "myl_core_borrow_select_v1_4294967295_5",
            8 => callee.signature.params = &.{ .str, .i64, .str },
            9 => try callee.blocks.append(a, .{}),
            else => unreachable,
        }
        try std.testing.expectEqual(cost.Allocation.unresolved, cost.allocation(&module, callee, call));
    }
}
