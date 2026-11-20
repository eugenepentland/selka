//! `selka engine bench`: what the engine costs, measured on a synthetic graph (plan C1's budgets).
//!
//! The graph has `queries` nodes of the script kind. Each reads `reads` files (round-robin over `files` files) and, from a
//! quarter of the way up, two nodes below it, so validation follows chains and shares dependencies. Two passes are timed:
//! the first computes every node and publishes its record; the second is a new process (a new engine over the same store,
//! nothing remembered) that asks for every node again and is served all of them. The second pass is the cost of serving:
//! one record open per query plus the validation of its reads. The files are in memory (the engine's own cost) or on disk
//! (`--os`: real stat calls). `--objects P` makes P percent of the nodes return a result over the object threshold, so
//! their records name a stored object; the serving pass must not open one (lazy payloads, spec §5), unless `--read-payloads`
//! makes every pass read each payload it is served. One JSON line is printed.
const std = @import("std");
const product = @import("selka").product;
const engine_rules = @import("engine.zig");
const memory_world = @import("memory_world.zig");
const os_world = @import("os_world.zig");
const script = @import("kinds/script.zig");
const world_rules = @import("world.zig");
const stats_rules = @import("stats.zig");
const Kind = @import("context.zig").Kind;

/// Which passes a run makes. `compute` publishes every record; `serve` is a new process served all of them; `verify` is
/// a new process served all of them and recomputing each (verify mode with every query sampled), which prices the kind
/// bodies. A run of `serve` or `verify` alone needs the store a run of `compute` left, and starts from a fresh process, so
/// its peak memory is its own.
pub const Phase = enum { all, compute, serve, verify };

/// The shape of the graph beyond its size: how many query reads a node makes past the first quarter of the graph, the
/// percentage of nodes whose result is large enough to be stored as an object, and whether the pass reads every payload it
/// is served (what a caller that uses every result costs, which is what the engine paid for objects before payloads were lazy).
pub const Mix = struct { deps: usize = 2, objects: usize = 0, read_payloads: bool = false };

/// The knobs of one run.
pub const Options = struct {
    queries: usize = 100_000,
    reads: usize = 3,
    files: usize = 1_000,
    os: bool = false,
    phase: Phase = .all,
    cache: []const u8 = product.work_dir ++ "/engine-bench",
    mix: Mix = .{},
};

/// The time each phase took, in nanoseconds of the wall clock, and the process's CPU time over the same phase.
pub const Times = struct { compute_ns: u64 = 0, serve_ns: u64 = 0, verify_ns: u64 = 0, compute_cpu_ns: u64 = 0, serve_cpu_ns: u64 = 0, verify_cpu_ns: u64 = 0 };

/// What the engine counted in each phase.
pub const Counts = struct { recomputed: u64 = 0, served: u64 = 0, verified: u64 = 0, object_reads: u64 = 0 };

/// What one run measured. A phase that did not run is zero.
pub const Measure = struct {
    times: Times = .{},
    counts: Counts = .{},
    /// Resident memory before the engine started, and its high-water mark after the phases, in KiB.
    rss_before_kib: u64 = 0,
    peak_rss_kib: u64 = 0,
};

/// Why a run could not finish.
pub const Error = std.mem.Allocator.Error || engine_rules.Error || engine_rules.RegisterError || std.Io.Dir.CreateDirPathError ||
    std.Io.Dir.WriteFileError || std.fmt.BufPrintError;

fn tick(io: std.Io) u64 {
    return @intCast(std.Io.Timestamp.now(io, .awake).nanoseconds);
}

fn cpuTick(io: std.Io) u64 {
    return @intCast(std.Io.Timestamp.now(io, .cpu_process).nanoseconds);
}

/// The size of the files the object-sized nodes read: over the object threshold, so their results are objects.
const big_size = 5_000;
/// How many distinct large files the object-sized nodes read.
const big_files = 8;

/// The process's resident-memory high-water mark in KiB (`VmHWM` of `/proc/self/status`), or 0.
pub fn peakResidentKiB(a: std.mem.Allocator, io: std.Io) u64 {
    var file = std.Io.Dir.cwd().openFile(io, "/proc/self/status", .{}) catch return 0;
    defer file.close(io);
    var reader = file.readerStreaming(io, &.{});
    const text = reader.interface.allocRemaining(a, .limited(1 << 16)) catch return 0;
    defer a.free(text);
    const at = std.mem.indexOf(u8, text, "VmHWM:") orelse return 0;
    var words = std.mem.tokenizeAny(u8, text[at + 6 ..], " \tkB\n");
    return std.fmt.parseInt(u64, words.next() orelse return 0, 10) catch 0;
}

fn fileName(a: std.mem.Allocator, prefix: []const u8, at: usize) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}/f{d}", .{ prefix, at });
}

/// The graph of `options`: node `i` reads files `i*reads .. i*reads + reads` (mod files) and, from the quarter mark, the
/// nodes `i/2`, `i/3` and so on (`mix.deps` of them). A node in the first `mix.objects` percent of each hundred also reads
/// one of the large files and returns the concatenation of everything it read, which makes its result an object.
pub fn buildGraph(a: std.mem.Allocator, prefix: []const u8, options: Options) std.mem.Allocator.Error!script.Graph {
    const nodes = try a.alloc(script.Node, options.queries);
    for (nodes, 0..) |*node, at| {
        const deps: usize = if (at >= options.queries / 4 and at >= 6) options.mix.deps else 0;
        const large = at % 100 < options.mix.objects;
        const ops = try a.alloc(script.Op, options.reads + deps + @intFromBool(large));
        for (ops[0..options.reads], 0..) |*op, read| op.* = .{ .file = try fileName(a, prefix, (at * options.reads + read) % options.files) };
        for (0..deps) |dep| ops[options.reads + dep] = .{ .node = @intCast(at / (dep + 2)) };
        if (large) ops[options.reads + deps] = .{ .file = try bigName(a, prefix, at % big_files) };
        node.* = .{ .ops = ops, .fold = if (large) .concat else .length };
    }
    return .{ .nodes = nodes };
}

fn bigName(a: std.mem.Allocator, prefix: []const u8, at: usize) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}/big{d}", .{ prefix, at });
}

fn askAll(runner: *engine_rules.Engine, kind: *const Kind, options: Options) Error!void {
    var text: [24]u8 = undefined;
    for (0..options.queries) |at| {
        const argument = try std.fmt.bufPrint(&text, "{d}", .{at});
        const answered = try runner.query(kind, argument);
        if (options.mix.read_payloads) _ = try answered.payload();
    }
}

/// One pass: a new engine over the store, asked for every query. Returns the wall and CPU time and the engine's numbers.
fn pass(gpa: std.mem.Allocator, io: std.Io, world: world_rules.World, options: Options, kind: *const Kind, verify_every: u32) Error!struct { ns: u64, cpu_ns: u64, numbers: stats_rules.Snapshot } {
    var runner = try engine_rules.Engine.init(gpa, io, world, .{ .work = options.cache, .verify_every = verify_every });
    defer runner.deinit();
    try runner.register(kind);
    const started = tick(io);
    const cpu_started = cpuTick(io);
    try askAll(&runner, kind, options);
    return .{ .ns = tick(io) - started, .cpu_ns = cpuTick(io) - cpu_started, .numbers = runner.snapshot(kind).? };
}

/// Run the passes `options.phase` asks for and measure.
pub fn measure(gpa: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, options: Options) Error!Measure {
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var files: memory_world.MemoryWorld = .init(gpa);
    defer files.deinit();
    var machine: os_world.OsWorld = .{ .io = io, .environment = environment, .work = options.cache };
    const sources = try std.fmt.allocPrint(a, "{s}/sources", .{options.cache});
    const prefix: []const u8 = if (options.os) sources else "/bench";
    // The files on disk are written once, by the run that computes: a later phase in a new process finds them untouched, as
    // an unedited tree is, and its recorded stat tuples hold. The in-memory files are the same in every process.
    const writes = options.phase == .all or options.phase == .compute;
    if (options.os and writes) try std.Io.Dir.cwd().createDirPath(io, sources);
    for (0..options.files) |at| {
        const name = try fileName(a, prefix, at);
        const text = try std.fmt.allocPrint(a, "content {d}", .{at});
        if (!options.os) try files.write(name, text) else if (writes) try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = name, .data = text });
    }
    var large: [big_size]u8 = @splat('x');
    for (0..big_files) |at| {
        if (options.mix.objects == 0) break;
        const name = try bigName(a, prefix, at);
        large[0] = @intCast('a' + at);
        if (!options.os) try files.write(name, &large) else if (writes) try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = name, .data = &large });
    }
    files.advance(2 * std.time.ns_per_s);
    if (options.os and writes) try std.Io.sleep(io, .fromMilliseconds(100), .awake);
    const graph = try buildGraph(a, prefix, options);
    const world: world_rules.World = if (options.os) machine.world() else files.world();
    var kind = script.kindFor(&graph, @splat(7));
    var found: Measure = .{ .rss_before_kib = peakResidentKiB(a, io) };
    if (options.phase == .all or options.phase == .compute) {
        const computed = try pass(gpa, io, world, options, &kind, 0);
        found.times.compute_ns = computed.ns;
        found.times.compute_cpu_ns = computed.cpu_ns;
        found.counts.recomputed = computed.numbers.count(.recomputed);
    }
    if (options.phase == .all or options.phase == .serve) {
        const served = try pass(gpa, io, world, options, &kind, 0);
        found.times.serve_ns = served.ns;
        found.times.serve_cpu_ns = served.cpu_ns;
        found.counts.served = served.numbers.count(.served);
        found.counts.object_reads = served.numbers.count(.object_reads);
    }
    if (options.phase == .all or options.phase == .verify) {
        const verified = try pass(gpa, io, world, options, &kind, 1);
        found.times.verify_ns = verified.ns;
        found.times.verify_cpu_ns = verified.cpu_ns;
        found.counts.verified = verified.numbers.count(.verified);
    }
    found.peak_rss_kib = peakResidentKiB(a, io);
    return found;
}

/// Write the line `measure` found for `options`.
pub fn write(writer: *std.Io.Writer, options: Options, found: Measure) std.Io.Writer.Error!void {
    const count: u64 = @max(1, options.queries);
    try writer.print("{{\"engine-bench-v1\":{{\"queries\":{d},\"reads_per_query\":{d},\"files\":{d},\"world\":\"{s}\",\"phase\":\"{s}\",", .{
        options.queries, options.reads, options.files, if (options.os) "os" else "memory", @tagName(options.phase),
    });
    try writer.print("\"compute_ns_per_query\":{d},\"serve_ns_per_query\":{d},\"verify_ns_per_query\":{d},", .{
        found.times.compute_ns / count, found.times.serve_ns / count, found.times.verify_ns / count,
    });
    try writer.print("\"serve_cpu_ns_per_query\":{d},\"compute_cpu_ns_per_query\":{d},\"verify_cpu_ns_per_query\":{d},\"deps\":{d},\"objects_pct\":{d},\"read_payloads\":{},", .{
        found.times.serve_cpu_ns / count, found.times.compute_cpu_ns / count, found.times.verify_cpu_ns / count, options.mix.deps, options.mix.objects, options.mix.read_payloads,
    });
    try writer.print("\"recomputed\":{d},\"served\":{d},\"verified\":{d},\"object_reads\":{d},\"rss_before_kib\":{d},\"peak_rss_kib\":{d}}}}}\n", .{
        found.counts.recomputed, found.counts.served, found.counts.verified, found.counts.object_reads, found.rss_before_kib, found.peak_rss_kib,
    });
}

test "a small graph is computed once and then served whole by a new process" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(work);
    const options: Options = .{ .queries = 200, .reads = 2, .files = 20, .cache = work };
    const found = try measure(std.testing.allocator, std.testing.io, &environment, options);
    try std.testing.expectEqual(@as(u64, 200), found.counts.recomputed);
    try std.testing.expectEqual(@as(u64, 200), found.counts.served);
    try std.testing.expectEqual(@as(u64, 200), found.counts.verified);
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try write(&writer, options, found);
    try std.testing.expect(std.mem.startsWith(u8, writer.buffered(), "{\"engine-bench-v1\":{\"queries\":200,"));
}

test "on disk, a phase run in a new process finds the files the first phase wrote and is served all of its queries" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(work);
    var options: Options = .{ .queries = 100, .reads = 1, .files = 10, .os = true, .phase = .compute, .cache = work };
    const computed = try measure(std.testing.allocator, std.testing.io, &environment, options);
    try std.testing.expectEqual(@as(u64, 100), computed.counts.recomputed);
    try std.testing.expectEqual(@as(u64, 0), computed.counts.served);
    options.phase = .serve;
    const served = try measure(std.testing.allocator, std.testing.io, &environment, options);
    try std.testing.expectEqual(@as(u64, 100), served.counts.served);
    try std.testing.expectEqual(@as(u64, 0), served.counts.recomputed);
}

test "serving a graph a quarter of whose results are objects opens no object, and the verify pass reads the sampled ones" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(work);
    const options: Options = .{ .queries = 400, .reads = 2, .files = 20, .cache = work, .mix = .{ .deps = 3, .objects = 25 } };
    const found = try measure(std.testing.allocator, std.testing.io, &environment, options);
    try std.testing.expectEqual(@as(u64, 400), found.counts.recomputed);
    try std.testing.expectEqual(@as(u64, 400), found.counts.served);
    try std.testing.expectEqual(@as(u64, 0), found.counts.object_reads);
    var buffer: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try write(&writer, options, found);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"deps\":3,\"objects_pct\":25,") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "\"object_reads\":0,") != null);
}

test "reading every payload opens every served object, which is what serving them eagerly cost" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(work);
    const options: Options = .{ .queries = 400, .reads = 2, .files = 20, .cache = work, .mix = .{ .deps = 3, .objects = 25, .read_payloads = true } };
    const found = try measure(std.testing.allocator, std.testing.io, &environment, options);
    try std.testing.expectEqual(@as(u64, 400), found.counts.served);
    try std.testing.expectEqual(@as(u64, 100), found.counts.object_reads);
}
