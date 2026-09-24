//! Guest functions compiled in batches: one QBE run and one assembler run per
//! batch, many batches at once.
//!
//! A cold build used to start QBE and then `zig cc` once per guest function —
//! about 30 ms of process start per function before any code was generated,
//! and more as the build process grew (see `qbe_build_spawn.zig`). The
//! functions of one module now travel together. Each batch hands QBE every
//! member's IL as its own input file (QBE forgets aggregate types between
//! input files, so the members' `type` definitions cannot collide, while its
//! block labels stay unique across the whole run), frame-map annotates the one
//! assembly file it prints, and assembles that into one object. Every member
//! function keeps its own `.text.<symbol>` section, so the final link's
//! `--gc-sections` still drops a function nothing calls.
//!
//! **Grouping** is deterministic and stable under edits. Units are ordered by
//! module, then symbol; a batch never spans two modules, and inside a module a
//! function whose symbol hashes to a boundary starts a new batch (on average
//! every `spacing` functions, never more than `max_units`). Symbols name a
//! declaration, not its body, so a body edit changes one batch's input and
//! adding or removing a function disturbs only the batch it lands in. A test
//! graph that selects a module's functions forms the same batch every time.
//!
//! **Reuse** stays content addressed. A batch's key is the ordered list of its
//! members' own keys — each already the unit's IL under the build environment
//! and cache contract — so a changed function, driver, runtime, tool, mode or
//! target misses exactly as a per-function object did, and an unchanged batch
//! starts no tool at all.
const std = @import("std");
const cache_api = @import("qbe_build_cache.zig");
const fs = @import("qbe_build_io.zig");
const spawn = @import("qbe_build_spawn.zig");
const budget = @import("memory_budget");

/// Environment variable that caps how many functions one batch holds; `1`
/// compiles every function alone, the way builds did before batching.
pub const units_variable = "MYLANG_QBE_BATCH";
/// A batch holds at most this many functions unless `MYLANG_QBE_BATCH` says otherwise.
pub const default_max_units: usize = 128;
/// Inside one module a new batch starts, on average, every this many functions.
/// QBE-BATCH-5: a body edit recompiles the batch its function lands in, so the
/// spacing is the edit loop's codegen cost; at 8 a one-function edit of a 50,000-line
/// project spends about 65 ms in QBE and the assembler instead of about 170 ms at
/// 32, while a cold build of the same project starts four times as many
/// (still concurrent, still small) tools for no measurable cost.
pub const default_spacing: u64 = 8;
/// The version every batch key carries, so a change to how members combine
/// never reuses an object built the old way under an unchanged driver identity.
const key_version = "qbe-batch-v1";
/// The kind a group's assembled function metadata is keyed under, beside the
/// digest of what it is rendered from (`outputs.metadataDigest`).
pub const metadata_version = "qbe-batch-metadata-v3";
/// QBE-BATCH-6: how function metadata is grouped into assembled objects —
/// the same planner as code, with boundaries four times sparser. Assembling
/// one group's tables is little work next to starting the assembler, so a
/// cold build starts about a quarter as many metadata tools as code tools,
/// while an edit that moves one module's lines still reassembles only the
/// groups of that module.
pub const metadata_policy: Policy = .{ .max_units = default_max_units, .spacing = default_spacing * 4 };

/// One guest unit as the planner orders it: the module it belongs to, its
/// stable symbol, and whether it must be compiled alone.
pub const Unit = struct { module: []const u8, symbol: []const u8, alone: bool = false };
/// A run of consecutive units, in plan order, that compiles into one object.
pub const Batch = struct { first: usize, count: usize };
/// How units are grouped: the most functions one batch may hold and the
/// average run length inside a module.
pub const Policy = struct { max_units: usize = default_max_units, spacing: u64 = default_spacing };

/// The module a unit's qualified name places it in: everything before the
/// last `::`, or the empty module for an unqualified name.
pub fn moduleOf(name: []const u8) []const u8 {
    const split = std.mem.lastIndexOf(u8, name, "::") orelse return "";
    return name[0..split];
}

/// Plan order: by module, then by symbol.
pub fn less(_: void, left: Unit, right: Unit) bool {
    const order = std.mem.order(u8, left.module, right.module);
    if (order != .eq) return order == .lt;
    return std.mem.lessThan(u8, left.symbol, right.symbol);
}

/// The grouping `MYLANG_QBE_BATCH` asks for: a positive number caps the
/// functions per batch (`1` compiles each alone); anything else is the default.
pub fn policy(environ: *const std.process.Environ.Map) Policy {
    const text = environ.get(units_variable) orelse return .{};
    const units = std.fmt.parseUnsigned(usize, text, 10) catch return .{};
    if (units == 0) return .{};
    return .{ .max_units = units };
}

/// Whether a symbol starts a new batch inside its module.
fn boundary(symbol: []const u8, spacing: u64) bool {
    return std.hash.Wyhash.hash(0x6d796c616e67, symbol) % @max(1, spacing) == 0;
}

/// Group units, already in plan order, into batches: a batch never spans two
/// modules, holds at most `max_units` functions, begins at every boundary
/// symbol, and keeps a unit that must compile alone to itself.
pub fn plan(allocator: std.mem.Allocator, units: []const Unit, rule: Policy) error{OutOfMemory}![]Batch {
    var batches: std.ArrayList(Batch) = .empty;
    for (units, 0..) |unit, index| {
        const joins = index != 0 and !unit.alone and !units[index - 1].alone and
            std.mem.eql(u8, units[index - 1].module, unit.module) and
            batches.items[batches.items.len - 1].count < @max(1, rule.max_units) and
            !boundary(unit.symbol, rule.spacing);
        if (joins) {
            batches.items[batches.items.len - 1].count += 1;
        } else {
            try batches.append(allocator, .{ .first = index, .count = 1 });
        }
    }
    return batches.toOwnedSlice(allocator);
}

/// Whether a unit's IL defines data. Two units' private data may share a name,
/// which one assembly file cannot hold, so such a unit is compiled alone.
/// Only lines that contain the word are examined: every unit is scanned on
/// every build, and splitting all of a large program's IL into lines cost more
/// than the rest of planning.
pub fn definesData(il: []const u8) bool {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, il, at, "data")) |found| {
        const start = if (std.mem.lastIndexOfScalar(u8, il[0..found], '\n')) |newline| newline + 1 else 0;
        const end = std.mem.indexOfScalarPos(u8, il, found, '\n') orelse il.len;
        at = end;
        const line = il[start..end];
        if (line.len == 0 or !std.ascii.isAlphabetic(line[0])) continue;
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "data")) return true;
            if (std.mem.eql(u8, token, "function") or std.mem.eql(u8, token, "type")) break;
        }
    }
    return false;
}

/// A unit's IL with every function it defines placed in its own
/// `.text.<symbol>` section, so a batch object still lets the final link
/// collect a function nothing references, exactly as a per-function object did.
/// Only the header lines are rewritten, found by searching for the keyword:
/// the bodies are copied as they are, since this runs on the build's critical
/// path for every batch it compiles.
pub fn sectioned(allocator: std.mem.Allocator, il: []const u8) error{OutOfMemory}![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    var copied: usize = 0;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, il, at, "function ")) |found| {
        const start = if (std.mem.lastIndexOfScalar(u8, il[0..found], '\n')) |newline| newline + 1 else 0;
        const end = std.mem.indexOfScalarPos(u8, il, found, '\n') orelse il.len;
        at = end;
        const line = il[start..end];
        const exported = std.mem.startsWith(u8, line, "export function ");
        if (!exported and !std.mem.startsWith(u8, line, "function ")) continue;
        const symbol = functionSymbol(line) orelse continue;
        const rest = if (exported) line["export ".len..] else line;
        w.writeAll(il[copied..start]) catch return error.OutOfMemory;
        w.print("{s}section \".text.{s}\" \"ax\" {s}", .{ if (exported) "export " else "", symbol, rest }) catch return error.OutOfMemory;
        copied = end;
    }
    w.writeAll(il[copied..]) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

/// The global name a `function` line defines: the `$name` before its `(`.
fn functionSymbol(line: []const u8) ?[]const u8 {
    const dollar = std.mem.indexOfScalar(u8, line, '$') orelse return null;
    const open = std.mem.indexOfScalarPos(u8, line, dollar, '(') orelse return null;
    const name = line[dollar + 1 .. open];
    if (name.len == 0) return null;
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.') return null;
    return name;
}

/// How many batch tools run at once: every core this process may use, but no
/// more than the machine's free memory holds at `memory_budget.headroom` per
/// tool, and never more than there are batches to build.
pub fn width(io: std.Io, batches: usize) usize {
    return budget.workers(.{
        .programs = batches,
        .cores = std.Thread.getCpuCount() catch 1,
        .free = budget.available(io),
        .ceiling = 0,
    });
}

/// What a missed object is built from: each member's IL in plan order (QBE,
/// frame-map annotation, then the assembler), ready assembly (the assembler
/// alone), or a C unit the object cache already staged (its compiler alone).
pub const Input = union(enum) { il: []const []const u8, files: Files, assembly: []const u8, staged: cache_api.Job };
/// A code batch whose members' sectioned IL the caller already wrote, one
/// `.ssa` file each, into the private directory `work` (`BUILD-MEMORY-1`): the
/// caller reads one unit text at a time, so a cold build of a large program
/// never holds every miss's text at once.
pub const Files = struct { work: []const u8, paths: []const []const u8 };

/// Write one code batch's members for `Input.files`: each text `sectioned`
/// into its own `.ssa` file in a fresh private directory. `texts` yields each
/// member's IL in plan order through `next(scratch)`; everything a member
/// needs is allocated from `scratch`, which is reset after it is written.
pub fn stage(cache: cache_api.Cache, count: usize, texts: anytype) !Files {
    const context = cache.context;
    const a = context.allocator;
    const work = try context.temporary(cache.temporary);
    errdefer context.remove(work);
    var scratch = std.heap.ArenaAllocator.init(context.parent);
    defer scratch.deinit();
    const paths = try a.alloc([]const u8, count);
    for (paths, 0..) |*path, member| {
        defer _ = scratch.reset(.retain_capacity);
        const text = try texts.next(scratch.allocator());
        path.* = try std.fs.path.join(a, &.{ work, try std.fmt.allocPrint(a, "{d}.ssa", .{member}) });
        try context.write(path.*, try sectioned(scratch.allocator(), text));
    }
    return .{ .work = work, .paths = paths };
}
/// One object that missed the cache: the key it is published under, where the
/// built object is recorded, and what it is built from.
pub const Miss = struct { key: []const u8, object: *cache_api.Object, input: Input };

/// One running tool of a missed object, and what it has written to standard
/// error so far.
const Running = struct { miss: usize, work: []const u8, stage: enum { qbe, assemble, compile }, started: spawn.Started, stderr: std.ArrayList(u8) = .empty };

/// Build every missed object, `limit` tools at a time. A code batch runs QBE
/// over its members' IL files, then frame-map annotation, then the assembler;
/// a metadata batch runs the assembler; a staged C unit runs its compiler.
/// Each publishes its object, and a freed tool slot goes to the next step of
/// whichever job finished first, then to the next object. Every object lands
/// in its own slot, so the order tools finish in never changes the link. After
/// the first failure nothing new starts, every running tool is still reaped
/// and every scratch directory removed, and then that failure is returned.
pub fn build(cache: cache_api.Cache, misses: []const Miss, limit: usize) cache_api.Error!void {
    const context = cache.context;
    const a = context.allocator;
    var running: std.ArrayList(Running) = .empty;
    var next: usize = 0;
    var failure: ?cache_api.Error = null;
    while (true) {
        while (failure == null and next < misses.len and running.items.len < @max(1, limit)) : (next += 1) {
            const started = startJob(cache, misses[next], next) catch |err| {
                failure = err;
                break;
            };
            try running.append(a, started);
        }
        if (running.items.len == 0) break;
        const current = running.swapRemove(try finished(a, running.items));
        const advanced = advance(cache, misses[current.miss], current, failure != null) catch |err| {
            if (failure == null) failure = err;
            context.remove(current.work);
            continue;
        };
        if (advanced) |started| try running.append(a, started) else context.remove(current.work);
    }
    // A staged C unit whose compiler never started still owns its scratch, and
    // so does a batch whose files were written but whose QBE never ran.
    for (misses[next..]) |miss| switch (miss.input) {
        .staged => |job| cache.discard(job),
        .files => |files| context.remove(files.work),
        else => {},
    };
    if (failure) |err| return err;
}

/// Collect standard error from whichever running tools are ready until one
/// of them closes it, and return that tool's index. A tool is reaped only after
/// its stream ends, so one that writes more than a pipe holds never stalls.
fn finished(allocator: std.mem.Allocator, running: []Running) cache_api.Error!usize {
    const started = try allocator.alloc(spawn.Started, running.len);
    for (running, started) |one, *slot| slot.* = one.started;
    while (true) {
        const index = try spawn.ready(allocator, started);
        if (try spawn.pump(allocator, running[index].started, &running[index].stderr)) return index;
    }
}

/// Stage one missed object in a private directory and start its first tool.
fn startJob(cache: cache_api.Cache, miss: Miss, index: usize) cache_api.Error!Running {
    const context = cache.context;
    const a = context.allocator;
    if (miss.input == .staged) {
        const job = miss.input.staged;
        errdefer cache.discard(job);
        const started = try spawn.start(a, .{ .argv = job.argv, .environment = job.environment });
        return .{ .miss = index, .work = job.work, .stage = .compile, .started = started };
    }
    if (miss.input == .files) {
        const files = miss.input.files;
        errdefer context.remove(files.work);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ cache.codegen.tool, "-t", "amd64_sysv", "-o", try std.fs.path.join(a, &.{ files.work, "batch.s" }) });
        try argv.appendSlice(a, files.paths);
        const started = try spawn.start(a, .{ .argv = argv.items });
        return .{ .miss = index, .work = files.work, .stage = .qbe, .started = started };
    }
    const work = try context.temporary(cache.temporary);
    errdefer context.remove(work);
    const assembly = try std.fs.path.join(a, &.{ work, "batch.s" });
    switch (miss.input) {
        .assembly => |text| {
            try context.write(assembly, text);
            const started = try spawn.start(a, .{ .argv = try assembler(cache, work) });
            return .{ .miss = index, .work = work, .stage = .assemble, .started = started };
        },
        .il => |members| {
            var argv: std.ArrayList([]const u8) = .empty;
            try argv.appendSlice(a, &.{ cache.codegen.tool, "-t", "amd64_sysv", "-o", assembly });
            for (members, 0..) |il, member| {
                const path = try std.fs.path.join(a, &.{ work, try std.fmt.allocPrint(a, "{d}.ssa", .{member}) });
                try context.write(path, try sectioned(a, il));
                try argv.append(a, path);
            }
            const started = try spawn.start(a, .{ .argv = argv.items });
            return .{ .miss = index, .work = work, .stage = .qbe, .started = started };
        },
        .staged, .files => unreachable,
    }
}

/// The assembler command for a job's `batch.s`. It is Zig's bundled LLVM
/// assembler invoked directly: `zig cc` would first probe the host C library
/// with two compiler runs and then relink its one output with `ld.lld -r`,
/// about a third of an assembly's cost, for an input that needs neither.
fn assembler(cache: cache_api.Cache, work: []const u8) cache_api.Error![]const []const u8 {
    const a = cache.context.allocator;
    return a.dupe([]const u8, &.{
        cache.zig,            "clang", "-cc1as", "-triple",                                       "x86_64-unknown-linux-gnu",                     "-filetype", "obj", "-target-cpu", "x86-64",
        "-mrelocation-model", "pic",   "-o",     try std.fs.path.join(a, &.{ work, "object.o" }), try std.fs.path.join(a, &.{ work, "batch.s" }),
    });
}

/// Reap a tool whose standard error has ended, replay what it wrote, and take
/// its object a step further: after QBE, annotate the assembly and start the
/// assembler; after the assembler or a C compiler, publish the object. Returns
/// the tool it started, or null when the object is finished. Once `stopping`,
/// a reaped job goes no further.
fn advance(cache: cache_api.Cache, miss: Miss, current: Running, stopping: bool) cache_api.Error!?Running {
    const context = cache.context;
    const a = context.allocator;
    const term = spawn.reap(current.started);
    try std.Io.File.stderr().writeStreamingAll(context.io, current.stderr.items);
    if (fs.exitCode(term) != 0) return error.NativeToolFailed;
    if (stopping) return null;
    // BUILD-MEMORY-1: the assembly a step annotates and the object it
    // fingerprints are read through a scratch arena freed when the step ends,
    // so a cold build holds one batch's worth of them, not the program's.
    var scratch = std.heap.ArenaAllocator.init(context.parent);
    defer scratch.deinit();
    var light = cache;
    light.context.allocator = scratch.allocator();
    switch (current.stage) {
        .qbe => {
            try light.annotateAssembly(try std.fs.path.join(a, &.{ current.work, "batch.s" }));
            const started = try spawn.start(a, .{ .argv = try assembler(cache, current.work) });
            return .{ .miss = current.miss, .work = current.work, .stage = .assemble, .started = started };
        },
        .assemble => {
            miss.object.* = try copiedObject(a, try light.keep(miss.key, try std.fs.path.join(a, &.{ current.work, "object.o" })));
            return null;
        },
        .compile => {
            miss.object.* = try copiedObject(a, try light.publish(miss.input.staged));
            return null;
        },
    }
}

/// An object published through a scratch cache, with its names copied out of
/// the scratch arena into `allocator`.
fn copiedObject(allocator: std.mem.Allocator, object: cache_api.Object) error{OutOfMemory}!cache_api.Object {
    return .{ .key = try allocator.dupe(u8, object.key), .path = try allocator.dupe(u8, object.path), .reused = object.reused };
}

/// The cache key of a batch: its members' own keys, in plan order.
pub fn key(cache: cache_api.Cache, members: []const []const u8) cache_api.Error![]const u8 {
    return cache.derived(key_version, try std.mem.join(cache.context.allocator, "\n", members));
}

/// `count` units with hash-like symbols in plan order: the first `split` in
/// module `big`, the rest in module `small`.
fn syntheticUnits(a: std.mem.Allocator, count: usize, split: usize) ![]Unit {
    const units = try a.alloc(Unit, count);
    for (units, 0..) |*unit, index| unit.* = .{
        .module = if (index < split) "big" else "small",
        .symbol = try std.fmt.allocPrint(a, "myl_f_{x:0>16}", .{std.hash.Wyhash.hash(7, std.mem.asBytes(&index))}),
    };
    std.mem.sort(Unit, units, {}, less);
    return units;
}

/// `units` plus one more function in module `big`, in plan order.
fn withAdded(a: std.mem.Allocator, units: []const Unit) ![]Unit {
    const added = try a.alloc(Unit, units.len + 1);
    @memcpy(added[0..units.len], units);
    added[units.len] = .{ .module = "big", .symbol = "myl_f_added" };
    std.mem.sort(Unit, added, {}, less);
    return added;
}

// spec: QBE-BATCH-1
test "batches follow modules, stay stable when a function is added, and honour the cap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const units = try syntheticUnits(a, 200, 150);
    const before = try plan(a, units, .{});
    // No batch crosses from `big` into `small`, no batch exceeds the cap, and
    // a module of 150 functions splits into several batches.
    try std.testing.expect(batchesRespect(units, before, default_max_units));
    try std.testing.expect(before.len >= 4);
    // Adding one function to `big` disturbs only the batch it lands in (two,
    // when its own symbol is a boundary and splits that batch).
    const added = try withAdded(a, units);
    const changed = try changedBatches(a, units, before, added, try plan(a, added, .{}));
    try std.testing.expect(changed >= 1 and changed <= 2);
    // A cap of one compiles every function alone; a data-defining unit is always alone.
    try std.testing.expectEqual(units.len, (try plan(a, units, .{ .max_units = 1 })).len);
    units[3].alone = true;
    try std.testing.expect(isolatedAlone(try plan(a, units, .{}), 3));
    try std.testing.expectEqualStrings("m001", moduleOf("m001::f001_00"));
    try std.testing.expectEqualStrings("", moduleOf("main"));
}

/// Every batch lies inside one module and holds at most `cap` units.
fn batchesRespect(units: []const Unit, batches: []const Batch, cap: usize) bool {
    for (batches) |batch| {
        if (batch.count > cap) return false;
        for (units[batch.first .. batch.first + batch.count]) |unit| if (!std.mem.eql(u8, unit.module, units[batch.first].module)) return false;
    }
    return true;
}

/// How many batches of `after` have a member list no batch of `before` had.
fn changedBatches(a: std.mem.Allocator, before_units: []const Unit, before: []const Batch, after_units: []const Unit, after: []const Batch) !usize {
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (before) |batch| try known.put(a, try memberList(a, before_units, batch), {});
    var changed: usize = 0;
    for (after) |batch| changed += @intFromBool(!known.contains(try memberList(a, after_units, batch)));
    return changed;
}

fn memberList(a: std.mem.Allocator, units: []const Unit, batch: Batch) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (units[batch.first .. batch.first + batch.count]) |unit| {
        try text.appendSlice(a, unit.symbol);
        try text.append(a, ',');
    }
    return text.items;
}

/// The unit at `index` sits in a batch of its own.
fn isolatedAlone(batches: []const Batch, index: usize) bool {
    for (batches) |batch| if (batch.first <= index and index < batch.first + batch.count) return batch.count == 1;
    return false;
}

// spec: QBE-BATCH-5
test "a module's batches hold about eight functions, so an edit recompiles a handful" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const units = try syntheticUnits(a, 1000, 1000);
    const batches = try plan(a, units, .{});
    // 1,000 functions of one module form about 125 batches.
    try std.testing.expect(batches.len >= 100 and batches.len <= 160);
    try std.testing.expect(largestBatch(batches) <= 64);
}

// spec: QBE-BATCH-6
test "function metadata is grouped more coarsely than code, still within modules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const units = try syntheticUnits(a, 1000, 500);
    const groups = try plan(a, units, metadata_policy);
    const batches = try plan(a, units, .{});
    try std.testing.expect(batchesRespect(units, groups, default_max_units));
    try std.testing.expect(groups.len * 2 < batches.len);
    try std.testing.expect(groups.len >= 1000 / default_max_units);
}

/// The member count of the largest batch.
fn largestBatch(batches: []const Batch) usize {
    var largest: usize = 0;
    for (batches) |batch| largest = @max(largest, batch.count);
    return largest;
}

// spec-case: QBE-BATCH-1
test "each function of a unit gets its own text section and data-defining units are found" {
    const a = std.testing.allocator;
    const il = "type :t = { l }\ndbgfile \"myl_f_a\"\nexport function l $myl_f_a(l %ctx) {\n@start\n ret 0\n}\nfunction w $helper() {\n@s\n ret 1\n}";
    const rewritten = try sectioned(a, il);
    defer a.free(rewritten);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "export section \".text.myl_f_a\" \"ax\" function l $myl_f_a(l %ctx) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "\nsection \".text.helper\" \"ax\" function w $helper() {") != null);
    try std.testing.expect(std.mem.startsWith(u8, rewritten, "type :t = { l }\ndbgfile \"myl_f_a\"\n"));
    try std.testing.expect(std.mem.endsWith(u8, rewritten, "() {\n@s\n ret 1\n}"));
    // Only header lines move; a body line that mentions the word is copied as it is.
    const body = "export function l $f() {\n@s\n # a function call follows\n ret 0\n}\n";
    const kept = try sectioned(a, body);
    defer a.free(kept);
    try std.testing.expectEqualStrings("export section \".text.f\" \"ax\" function l $f() {\n@s\n # a function call follows\n ret 0\n}\n", kept);
    try std.testing.expect(!definesData(il));
    try std.testing.expect(definesData("export data $d = { l 1 }\nexport function l $f() {\n@s\n ret 0\n}"));
    try std.testing.expect(definesData("data $d = { b 0 }"));
    // The word inside a name, a parameter or a body line is not a definition.
    try std.testing.expect(!definesData("export function l $metadata(l %data) {\n@s\n %data2 =l copy 1\n ret 0\n}\n"));
    try std.testing.expect(definesData("type :t = { l }\nexport function l $f() {\n@s\n ret 0\n}\nexport data $late = { l 1 }"));
}

/// Member texts for the staging test, handed out one at a time.
const TestTexts = struct {
    texts: []const []const u8,
    at: usize = 0,
    /// The next member's IL, copied into the caller's scratch arena.
    pub fn next(self: *TestTexts, scratch: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        defer self.at += 1;
        return scratch.dupe(u8, self.texts[self.at]);
    }
};

// spec: BUILD-MEMORY-1
test "a staged batch writes each member's sectioned text and leaves no scratch when it never runs" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const cache: cache_api.Cache = .{ .context = context, .directory = root, .temporary = root, .assets = "/assets", .environment = "env", .zig = "/bin/false", .mode = "Debug", .codegen = .{ .tool = "/bin/false" } };
    const members = [_][]const u8{ "export function l $a() {\n@s\n ret 0\n}", "function w $b() {\n@s\n ret 1\n}" };
    var texts: TestTexts = .{ .texts = &members };
    const files = try stage(cache, members.len, &texts);
    try std.testing.expectEqual(@as(usize, 2), files.paths.len);
    try std.testing.expectEqualStrings(try sectioned(context.allocator, members[0]), try context.read(files.paths[0]));
    try std.testing.expectEqualStrings(try sectioned(context.allocator, members[1]), try context.read(files.paths[1]));
    // A failing first batch stops the pool; the staged batch that never started
    // still has its directory removed.
    var objects: [2]cache_api.Object = undefined;
    const misses = [_]Miss{
        .{ .key = "first", .input = .{ .il = &.{"export function l $c() {\n@s\n ret 0\n}"} }, .object = &objects[0] },
        .{ .key = "second", .input = .{ .files = files }, .object = &objects[1] },
    };
    try std.testing.expectError(error.NativeToolFailed, build(cache, &misses, 1));
    try std.testing.expect(!context.exists(files.work));
}

// spec-case: QBE-BATCH-1
test "a failing batch tool stops new batches, reaps the running ones and leaves no scratch" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const cache: cache_api.Cache = .{ .context = context, .directory = root, .temporary = root, .assets = "/assets", .environment = "env", .zig = "/bin/false", .mode = "Debug", .codegen = .{ .tool = "/bin/false" } };
    var objects: [3]cache_api.Object = undefined;
    const misses = [_]Miss{
        .{ .key = "first", .input = .{ .il = &.{"export function l $a() {\n@s\n ret 0\n}"} }, .object = &objects[0] },
        .{ .key = "second", .input = .{ .il = &.{ "export function l $b() {\n@s\n ret 0\n}", "export function l $c() {\n@s\n ret 0\n}" } }, .object = &objects[1] },
        .{ .key = "third", .input = .{ .assembly = "\t.text\n" }, .object = &objects[2] },
    };
    try std.testing.expectError(error.NativeToolFailed, build(cache, &misses, 2));
    // Every batch's private directory was removed, and with them the shared staging folder.
    const staging = try std.fs.path.join(context.allocator, &.{ root, ".pending" });
    try std.testing.expect(!context.exists(staging));
    // A QBE that cannot start fails the batch at once and removes its scratch too.
    var missing = cache;
    missing.codegen.tool = "/no/such/mylang-qbe";
    try std.testing.expectError(error.FileNotFound, startJob(missing, misses[0], 0));
    try std.testing.expect(!context.exists(staging));
    // The pool is never wider than the work, and never empty.
    try std.testing.expectEqual(@as(usize, 1), width(std.testing.io, 0));
    try std.testing.expect(width(std.testing.io, 3) <= 3);
}
