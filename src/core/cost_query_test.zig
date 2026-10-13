//! Static query hits are checked against fresh Core measurement and real CLI runs.
const std = @import("std");
const queries = @import("cost_query.zig");
const cost = @import("cost.zig");
const passes = @import("passes.zig");
const build = @import("build.zig");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const canonical = @import("canonical_ir.zig");
const snapshot = @import("ir_snapshot.zig");
const emit = @import("emit_llvm.zig");
const stage = @import("stage_store.zig");
const tools = @import("core_test_options");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();

const program =
    \\func leaf(n: int) -> int:
    \\    return n % 3
    \\func idle(n: int) -> int:
    \\    return n % 5
    \\func main(out: Stream) -> int:
    \\    out.print(leaf(7), idle(9))
    \\    return 0
;

const Fixture = struct {
    directory: std.testing.TmpDir,
    store: stage.Store,

    fn init(a: std.mem.Allocator) !Fixture {
        var directory = std.testing.tmpDir(.{});
        errdefer directory.cleanup();
        const root = try directory.dir.realPathFileAlloc(io, ".", a);
        defer a.free(root);
        return .{ .directory = directory, .store = try stage.Store.init(a, io, root) };
    }
    fn deinit(self: *Fixture) void {
        self.store.deinit();
        self.directory.cleanup();
    }
};
fn location(_: *const anyopaque, span: u32) emit.Location {
    return .{ .path = "test.my", .line = 1, .column = span + 1 };
}
const locator_context: u8 = 0;
const locator: emit.Locator = .{ .context = &locator_context, .locate = location };

fn parity(a: std.mem.Allocator, cache: *queries.Cache, module: *ir.Module, result: *const passes.Result) !cost.Report {
    const fresh = try cost.measure(a, module, result, null);
    const restored = try cache.measure(a, module, result, locator);
    try std.testing.expectEqualStrings(try cost.render(a, fresh, true), try cost.render(a, restored, true));
    return restored;
}
fn run(a: std.mem.Allocator, cache: *queries.Cache, source: []const u8, optimized: bool) !cost.Report {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = if (optimized) try support.runPasses(a, &module, .trusted) else try passes.debug(a, &module);
    return parity(a, cache, &module, &result);
}
fn replace(a: std.mem.Allocator, source: []const u8, old: []const u8, new: []const u8) ![]const u8 {
    const at = std.mem.indexOf(u8, source, old) orelse return error.MissingFixture;
    return std.mem.concat(a, u8, &.{ source[0..at], new, source[at + old.len ..] });
}

// spec: NEW-CORE-COST-QUERY-1
test "cost query cold warm private edits and fresh verification preserve exact rows" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cache: queries.Cache = .{ .store = &fixture.store };
    const cold = try run(a, &cache, program, false);
    try std.testing.expectEqual(cold.functions.len, cache.statistics.computed);
    cache.statistics = .{};
    _ = try run(a, &cache, program, false);
    try std.testing.expectEqual(cold.functions.len, cache.statistics.reused);
    try std.testing.expectEqual(@as(usize, 0), cache.statistics.computed);
    cache.statistics = .{};
    _ = try run(a, &cache, try replace(a, program, "n % 5", "n % 6"), false);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.computed);
    try std.testing.expectEqual(cold.functions.len - 1, cache.statistics.reused);
    cache.statistics = .{};
    cache.verify = true;
    _ = try run(a, &cache, program, false);
    try std.testing.expectEqual(cold.functions.len, cache.statistics.verified);
    try std.testing.expectEqual(@as(usize, 0), cache.statistics.reused);
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query shared helper edits invalidate optimized callers and preserve independent rows" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cache: queries.Cache = .{ .store = &fixture.store };
    _ = try run(a, &cache, program, true);
    cache.statistics = .{};
    _ = try run(a, &cache, try replace(a, program, "n % 3", "n % 4"), true);
    try std.testing.expect(cache.statistics.computed >= 2);
    try std.testing.expect(cache.statistics.reused >= 1);
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query binds pass events verifying mode reachability and extern provenance" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    var function: ir.Function = .{ .name = "caller", .signature = .{ .params = &.{}, .ret = .void } };
    try function.insts.append(a, .{ .op = .call, .ty = .void, .a = @fromBackingInt(1), .check = .proven });
    var block: ir.Block = .{};
    try block.insts.append(a, @fromBackingInt(0));
    try function.blocks.append(a, block);
    try module.functions.append(a, function);
    try module.functions.append(a, .{ .name = "myl_core_text_encode", .signature = .{ .params = &.{}, .ret = .void, .linkage = .extern_c } });
    var events = [_]passes.FunctionStats{.{}};
    var known = [_]?@import("facts.zig").Facts{null};
    var result: passes.Result = .{ .known = &known, .plans = &.{}, .per_function = &events };
    var cache: queries.Cache = .{ .store = &fixture.store };
    const first = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(u32, 0), first.totals.allocation.unresolved_calls);
    module.functions.items[1].span = 9;
    cache.statistics = .{};
    const external = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.computed);
    try std.testing.expectEqual(@as(u32, 1), external.totals.allocation.unresolved_calls);
    // Fix the catalog, including both provenance bits, then change only target.
    try module.functions.append(a, .{ .name = "myl_core_text_encode", .signature = .{ .params = &.{}, .ret = .void, .linkage = .extern_c } });
    _ = try parity(a, &cache, &module, &result);
    cache.statistics = .{};
    _ = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.reused);
    module.functions.items[0].insts.items[0].a = @fromBackingInt(2);
    cache.statistics = .{};
    const switched = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.computed);
    try std.testing.expectEqual(@as(u32, 0), switched.totals.allocation.unresolved_calls);
    module.functions.items[0].insts.items[0].a = @fromBackingInt(1);

    events[0].counts.proven = 17;
    cache.statistics = .{};
    const changed = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(u32, 17), changed.totals.checks.proved);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.computed);
    result.emission.verifying = true;
    cache.statistics = .{};
    const verified = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(u32, 1), verified.totals.checks.kept);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.computed);
    const facts = try @import("facts.zig").analyze(a, &module.functions.items[0], .{});
    facts.reachable[0] = false;
    known[0] = facts;
    cache.statistics = .{};
    const unreachable_row = try parity(a, &cache, &module, &result);
    try std.testing.expectEqual(@as(u32, 0), unreachable_row.totals.allocation.sites);
    try std.testing.expectEqual(@as(usize, 1), cache.statistics.computed);
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query loadValue rejects damaged missing and foreign row records and preserves OOM" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    const result = try passes.debug(a, &module);
    var cache: queries.Cache = .{ .store = &fixture.store };
    _ = try parity(a, &cache, &module, &result);
    var canon = try canonical.Canon.prepare(a, &module, locator);
    const key = (try cache.key(a, &canon, .{
        .layout = try snapshot.layout(a, .{ .module = &module }),
        .allocation = queries.allocationIdentity(&module),
    }, &result, 0)).?;
    const path = (try fixture.store.artifactPath(a, key)).?;
    try cwd.writeFile(io, .{ .sub_path = path, .data = "broken" });
    cache.statistics = .{};
    _ = try parity(a, &cache, &module, &result);
    try std.testing.expect(cache.statistics.computed > 0);
    try @import("stage_loss_test_support.zig").remove(a, &fixture.store, key);
    cache.statistics = .{};
    _ = try parity(a, &cache, &module, &result);
    try std.testing.expect(cache.statistics.computed > 0);
    try std.testing.expectError(error.OutOfMemory, cache.measure(std.testing.failing_allocator, &module, &result, locator));
}

const Cli = struct { stdout: []const u8, work: std.json.Value };
fn cli(a: std.mem.Allocator, root: []const u8, extra: []const []const u8) !Cli {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ tools.corePath(), "cost", try std.fs.path.join(a, &.{ root, "main.my" }), "--json", "--cache-dir", try std.fs.path.join(a, &.{ root, "cli-cache" }), "--cache-report" });
    try argv.appendSlice(a, extra);
    const child = try std.process.run(a, io, .{ .argv = argv.items });
    if (child.term != .exited or child.term.exited != 0) try std.testing.expectEqualStrings("", child.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, child.term);
    return .{ .stdout = child.stdout, .work = try cliWork(a, child.stderr) };
}
fn cliWork(a: std.mem.Allocator, stderr: []const u8) !std.json.Value {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] != '{') continue;
        const value = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
        const version = value.object.get("version") orelse continue;
        if (std.mem.eql(u8, version.string, "cost-query-work-v1")) return value;
    }
    return error.MissingWorkReport;
}
fn number(value: std.json.Value, group: []const u8, field: []const u8) i64 {
    return value.object.get(group).?.object.get(field).?.integer;
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query outputWithQuery restores compiler stages and LLVM units with fresh and edited oracle parity" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try fixture.directory.dir.realPathFileAlloc(io, ".", a);
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "main.my", .data = program });
    const cold = try cli(a, root, &.{});
    try std.testing.expect(number(cold.work, "cost", "computed") > 0);
    try std.testing.expectEqual(@as(i64, 1), number(cold.work, "llvm", "processes"));
    const warm = try cli(a, root, &.{});
    try std.testing.expectEqualStrings(cold.stdout, warm.stdout);
    try std.testing.expect(number(warm.work, "cost", "reused") > 0);
    try std.testing.expect(number(warm.work, "lowering", "reused") > 0);
    try std.testing.expectEqual(@as(i64, 0), number(warm.work, "llvm", "processes"));
    try std.testing.expectEqual(@as(i64, 1), number(warm.work, "llvm", "reused"));
    const verified = try cli(a, root, &.{"--verify-cache"});
    try std.testing.expectEqualStrings(cold.stdout, verified.stdout);
    try std.testing.expect(number(verified.work, "cost", "verified") > 0);
    try std.testing.expectEqual(@as(i64, 1), number(verified.work, "llvm", "processes"));
    const edited = try replace(a, program, "n % 3", "n % 4");
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "main.my", .data = edited });
    const changed = try cli(a, root, &.{});
    const forced = try cli(a, root, &.{"--no-cache"});
    try std.testing.expectEqualStrings(forced.stdout, changed.stdout);
    try std.testing.expect(number(forced.work, "cost", "computed") > 0);
    try std.testing.expectEqual(number(forced.work, "cost", "computed"), number(forced.work, "cost", "bypassed"));
    try std.testing.expect(number(changed.work, "cost", "computed") >= 2);
    try std.testing.expectEqual(@as(i64, 1), number(changed.work, "llvm", "processes"));
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query CLI reads supplied remarks and counters again under unchanged static identity" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try fixture.directory.dir.realPathFileAlloc(io, ".", a);
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "main.my", .data = program });
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "remarks.yaml", .data = "" });
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "counters.json", .data = "{\"version\":\"mylang-counters-v1\",\"functions\":[],\"sites\":[]}" });
    const remarks_path = try std.fs.path.join(a, &.{ root, "remarks.yaml" });
    const counters_path = try std.fs.path.join(a, &.{ root, "counters.json" });
    const flags = &.{ "--llvm-remarks", remarks_path, "--counters", counters_path };
    const first = try cli(a, root, flags);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, first.stdout, .{});
    const name = parsed.object.get("functions").?.array.items[0].object.get("name").?.string;
    const yaml = try std.fmt.allocPrint(a, "--- !Passed\nPass: loop-vectorize\nName: Vectorized\nFunction: '{s}'\n...\n", .{name});
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "remarks.yaml", .data = yaml });
    const counters = try std.fmt.allocPrint(a, "{{\"version\":\"mylang-counters-v1\",\"functions\":[{{\"name\":\"{s}\",\"calls\":17}}],\"sites\":[]}}", .{name});
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "counters.json", .data = counters });
    const changed = try cli(a, root, flags);
    try std.testing.expect(!std.mem.eql(u8, first.stdout, changed.stdout));
    try std.testing.expect(number(changed.work, "cost", "reused") > 0);
    try std.testing.expectEqual(@as(i64, 0), number(changed.work, "llvm", "processes"));
    const values = try std.json.parseFromSliceLeaky(std.json.Value, a, changed.stdout, .{});
    try std.testing.expectEqual(@as(i64, 1), values.object.get("functions").?.array.items[0].object.get("counts").?.object.get("llvm_vectorized_loops").?.integer);
    try std.testing.expectEqual(@as(i64, 17), values.object.get("counters").?.array.items[0].object.get("run").?.object.get("calls").?.integer);
    var oracle_args: std.ArrayList([]const u8) = .empty;
    try oracle_args.appendSlice(a, flags);
    try oracle_args.append(a, "--no-cache");
    try std.testing.expectEqualStrings(changed.stdout, (try cli(a, root, oracle_args.items)).stdout);
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query measure verification rejects checksum-valid wrong rows" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    const result = try passes.debug(a, &module);
    var cache: queries.Cache = .{ .store = &fixture.store };
    _ = try parity(a, &cache, &module, &result);
    var canon = try canonical.Canon.prepare(a, &module, locator);
    const key = (try cache.key(a, &canon, .{
        .layout = try snapshot.layout(a, .{ .module = &module }),
        .allocation = queries.allocationIdentity(&module),
    }, &result, 0)).?;
    try fixture.store.storeValue(key, cost.Counts, .{ .checks = .{ .proved = 999 } });
    cache.verify = true;
    try std.testing.expectError(error.InvalidQuery, cache.measure(a, &module, &result, locator));
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query qualification helpers reject MissingFixture and MissingWorkReport" {
    try std.testing.expectError(error.MissingFixture, replace(std.testing.allocator, program, "not present", ""));
    try std.testing.expectError(error.MissingWorkReport, cliWork(std.testing.allocator, "compiler diagnostic\n"));
}
