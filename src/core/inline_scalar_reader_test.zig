//! Bounded local reader cloning preserves checked reads and scalar writeback CFGs.
const std = @import("std");
const ir = @import("ir.zig");
const reader = @import("inline_reader.zig");
const inliner = @import("inline.zig");
const origins = @import("inline_origins.zig");
const support = @import("test_support.zig");
const options = @import("core_test_options");
const build = @import("build.zig");
const fixture_name = "inline_scalar_reader.my";

fn fixture(a: std.mem.Allocator) !ir.Module {
    const path = try std.fs.path.join(a, &.{ options.fixtures, fixture_name });
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
    return fromSource(a, source);
}

fn fromSource(a: std.mem.Allocator, source: []const u8) !ir.Module {
    var unit = try @import("mylang").Compilation.init(a, fixture_name, source);
    try unit.check();
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = unit.program.?, .single_owner = true, .zero_rc = true }, &refusal);
    try support.verified(a, &module, &.{});
    return module;
}

fn named(module: *ir.Module, name: []const u8) *ir.Function {
    for (module.functions.items) |*f| {
        if (std.mem.endsWith(u8, f.name, name)) return f;
    }
    @panic("missing fixture function");
}

fn calls(module: *const ir.Module, f: *const ir.Function, name: []const u8) usize {
    var count: usize = 0;
    for (f.insts.items) |inst| {
        if (inst.op == .call and std.mem.endsWith(u8, module.functions.items[inst.a.index()].name, name)) count += 1;
    }
    return count;
}

// spec-case: NEW-CORE-INLINE-1
test "scalar reader qualifies closed mutable returns and refuses managed donors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var module = try fixture(arena.allocator());
    try std.testing.expect(reader.mutationFamily(&module, named(&module, "read_byte")));
    try std.testing.expect(reader.mutationFamily(&module, named(&module, "read_constant")));
    try std.testing.expect(reader.mutationFamily(&module, named(&module, "branch_reader")));
    try std.testing.expect(!reader.mutationFamily(&module, named(&module, "mutating_reader")));
    try std.testing.expect(!reader.mutationFamily(&module, named(&module, "string_reader")));
    module.zero_rc = false;
    try std.testing.expect(!reader.mutationFamily(&module, named(&module, "read_byte")));
}

// spec-case: NEW-CORE-INLINE-1
// spec-case: NEW-CORE-S4-SITES-1
test "scalar reader clones loop and differing early return writebacks with ancestry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    var table: origins.Table = .{};
    const before = calls(&module, &module.functions.items[module.entry], "read_byte");
    try std.testing.expect(before > 0);
    const changed = try inliner.cfgCallerDemandWithScratch(a, a, &module, module.entry, &table, null);
    try std.testing.expect(changed > 0);
    try std.testing.expectEqual(@as(usize, 0), calls(&module, &module.functions.items[module.entry], "read_byte"));
    try std.testing.expectEqual(@as(usize, 0), calls(&module, &module.functions.items[module.entry], "read_constant"));
    try std.testing.expectEqual(@as(usize, 0), calls(&module, &module.functions.items[module.entry], "branch_reader"));
    try std.testing.expect(table.frames.items.len > 0);
    try support.verified(a, &module, &.{});
    const result = try support.runPasses(a, &module, .verify);
    const ran = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("", ran.stderr);
}

fn padQuery(a: std.mem.Allocator, query: *ir.Function, blocks: usize, instructions: usize) !void {
    while (query.blocks.items.len < blocks) try query.blocks.append(a, .{});
    while (query.insts.items.len < instructions) try query.insts.append(a, .{ .op = .iconst, .ty = .i64 });
}

// spec-case: NEW-CORE-INLINE-1
test "scalar reader caps query inspection at thirty two blocks and ninety six instructions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const query = named(&module, "instruction");
    const wrapper = named(&module, "read_byte");
    try padQuery(a, query, 32, query.insts.items.len);
    try std.testing.expect(reader.mutationFamily(&module, wrapper));
    try query.blocks.append(a, .{});
    try std.testing.expect(!reader.mutationFamily(&module, wrapper));
    query.blocks.items.len = 32;
    try padQuery(a, query, 32, 96);
    try std.testing.expect(reader.mutationFamily(&module, wrapper));
    try query.insts.append(a, .{ .op = .iconst, .ty = .i64 });
    try std.testing.expect(!reader.mutationFamily(&module, wrapper));
}

// spec-case: NEW-CORE-INLINE-1
test "scalar reader refuses borrowed views and bounded shared compound expansion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const wrapper = named(&module, "read_byte");
    const original = wrapper.signature.ret;
    const fields = module.compound(original).record;
    const first = fields[0];
    const writable = @constCast(fields);
    writable[0] = .str_view;
    try std.testing.expect(!reader.mutationFamily(&module, wrapper));
    writable[0] = first;
    var shared: ir.Type = .i64;
    for (0..8) |_| shared = try module.intern(a, .{ .record = &.{ shared, shared } });
    wrapper.signature.ret = try module.intern(a, .{ .record = &.{ shared, .i64 } });
    try std.testing.expect(!reader.mutationFamily(&module, wrapper));
    wrapper.signature.ret = original;
    wrapper.signature.owned |= 1;
    try std.testing.expect(!reader.mutationFamily(&module, wrapper));
}

fn duplicateCalls(a: std.mem.Allocator, caller: *ir.Function, template: ir.Ref, count: usize, projected: bool) !void {
    const original = caller.inst(template);
    var additions: std.ArrayList(ir.Ref) = .empty;
    for (0..count) |_| {
        const call: ir.Ref = @fromBackingInt(@intCast(caller.insts.items.len));
        try caller.insts.append(a, original);
        try additions.append(a, call);
        for (0..if (projected) @as(usize, 2) else 1) |field| {
            const ref: ir.Ref = @fromBackingInt(@intCast(caller.insts.items.len));
            try caller.insts.append(a, if (projected) .{ .op = .record_get, .ty = .i64, .a = call, .data = field } else .{ .op = .copy, .ty = original.ty, .a = call });
            try additions.append(a, ref);
        }
    }
    for (caller.blocks.items) |*block| {
        for (block.insts.items, 0..) |ref, at| {
            if (ref != template) continue;
            try block.insts.insertSlice(a, at, additions.items);
            return;
        }
    }
    return error.MissingCall;
}

// spec-case: NEW-CORE-INLINE-1
test "scalar reader duplicate fixture reports MissingCall for a call outside live blocks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var caller: ir.Function = .{ .name = "fixture", .signature = .{ .params = &.{}, .ret = .void } };
    try caller.insts.append(a, .{ .op = .call, .ty = .i64 });
    try std.testing.expectError(error.MissingCall, duplicateCalls(a, &caller, @fromBackingInt(0), 0, true));
}

fn firstByteCall(module: *const ir.Module, caller: *const ir.Function) ir.Ref {
    for (caller.insts.items, 0..) |inst, index| {
        if (inst.op == .call and std.mem.endsWith(u8, module.functions.items[inst.a.index()].name, "read_byte")) return @fromBackingInt(@intCast(index));
    }
    @panic("missing reader call");
}

// spec-case: NEW-CORE-INLINE-1
test "scalar reader refused whole tuple uses consume projection trial allowance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const caller = &module.functions.items[module.entry];
    const template = firstByteCall(&module, caller);
    const callee = &module.functions.items[caller.inst(template).a.index()];
    try std.testing.expect(reader.mutationFamily(&module, callee));
    try duplicateCalls(a, caller, template, reader.mutation_trial_limit + 20, false);
    const constants = calls(&module, caller, "read_constant");
    var table: origins.Table = .{};
    _ = try inliner.cfgCallerDemandWithScratch(a, a, &module, module.entry, &table, null);
    // Refused trials in the first block exhaust the new family's allowance.
    try std.testing.expectEqual(constants, calls(&module, caller, "read_constant"));
    try support.verified(a, &module, &.{});
}

// spec-case: NEW-CORE-INLINE-1
test "scalar reader successful clones remain within existing constructor instruction budget" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fixture(a);
    const caller = &module.functions.items[module.entry];
    const template = firstByteCall(&module, caller);
    const callee = &module.functions.items[caller.inst(template).a.index()];
    const cost = callee.insts.items.len + 3;
    try duplicateCalls(a, caller, template, 40, true);
    const before = calls(&module, caller, "read_byte");
    var table: origins.Table = .{};
    _ = try inliner.cfgCallerDemandWithScratch(a, a, &module, module.entry, &table, null);
    const copied = before - calls(&module, caller, "read_byte");
    try std.testing.expect(copied > 0 and copied <= @import("destination.zig").max_caller_instructions / cost);
    try std.testing.expect(copied < before);
    try support.verified(a, &module, &.{});
}

const cache = @import("optimization_cache.zig");
const store = @import("stage_store.zig");
const emitter = @import("emit_llvm.zig");
const snapshot = @import("ir_snapshot.zig");
const passes = @import("passes.zig");

fn locate(_: *const anyopaque, offset: u32) emitter.Location {
    return .{ .line = 1, .column = offset + 1, .path = fixture_name };
}

const Produced = struct { llvm: []const u8, text: []const u8, canonical: [32]u8, statistics: cache.Statistics, native_status: u8 };

fn compileSource(a: std.mem.Allocator, backing: std.mem.Allocator, source: []const u8, storage: ?*store.Store) !Produced {
    var module = try fromSource(a, source);
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = locate };
    var context: cache.Context = undefined;
    if (storage) |s| context = cache.Context.init(s, try snapshot.Context.init(a, &module, null), locator);
    const result = if (storage != null) try passes.runCached(a, backing, &module, .verify, &context) else try passes.runWithScratch(a, backing, &module, .verify);
    try support.verified(a, &module, result.plans);
    const llvm = try emitter.emitModule(a, &module, .{ .locator = locator, .source_path = fixture_name, .main = .{ .parameters = &.{"out"}, .capabilities = &.{0} }, .analysis = support.analysis(&result) });
    const ran = try support.runOwned(a, &module, .{ .release = true, .verify = true, .own = false, .analysis = support.analysis(&result) });
    try std.testing.expectEqualStrings("", ran.stderr);
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, locator);
    var semantic = std.crypto.hash.Blake3.init(.{});
    for (module.functions.items, 0..) |_, index| {
        const digest = try canon.functionDigest(@intCast(index));
        semantic.update(&digest);
    }
    var canonical: [32]u8 = undefined;
    semantic.final(&canonical);
    return .{ .canonical = canonical, .llvm = llvm, .text = try @import("print.zig").module(a, &module), .statistics = if (storage != null) context.statistics else .{}, .native_status = ran.status };
}

// spec-case: NEW-CORE-INLINE-1
// spec-case: NEW-CORE-STAGE-CACHE-8
test "scalar reader query body edit invalidates transitive caller eligibility" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try std.fs.path.join(a, &.{ options.fixtures, fixture_name });
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var storage = try store.Store.init(std.testing.allocator, std.testing.io, try dir.dir.realPathFileAlloc(std.testing.io, ".", a));
    defer storage.deinit();
    const cold = try compileSource(a, std.testing.allocator, source, &storage);
    const warm = try compileSource(a, std.testing.allocator, source, &storage);
    try std.testing.expectEqualStrings(cold.llvm, warm.llvm);
    try std.testing.expectEqual(cold.canonical, warm.canonical);
    try std.testing.expectEqual(@as(u8, 0), warm.native_status);
    try std.testing.expect(warm.statistics.hits[@backingInt(cache.Stage.inline_cfg)] > 0);
    const edited = try editQuery(a, source);
    try std.testing.expectEqual(source.len, edited.len);
    // Caller and wrapper text and absolute spans remain fixed; only the query changes.
    var original_module = try fromSource(a, source);
    var altered_module = try fromSource(a, edited);
    const original_context = try snapshot.Context.init(a, &original_module, null);
    const altered_context = try snapshot.Context.init(a, &altered_module, null);
    try std.testing.expectEqual(try snapshot.layout(a, original_context), try snapshot.layout(a, altered_context));
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = locate };
    var original_canon = try @import("canonical_ir.zig").Canon.prepare(a, &original_module, locator);
    var altered_canon = try @import("canonical_ir.zig").Canon.prepare(a, &altered_module, locator);
    var wrapper_index: u32 = undefined;
    for (original_module.functions.items, 0..) |f, index| {
        if (std.mem.eql(u8, f.name, "read_byte")) wrapper_index = @intCast(index);
    }
    try std.testing.expectEqual(try original_canon.functionDigest(wrapper_index), try altered_canon.functionDigest(wrapper_index));
    try std.testing.expect(!reader.mutationFamily(&altered_module, named(&altered_module, "read_byte")));
    const uncached = try compileSource(a, std.testing.allocator, edited, null);
    const reused = try compileSource(a, std.testing.allocator, edited, &storage);
    try std.testing.expectEqual(@as(u8, 0), reused.native_status);
    try std.testing.expectEqual(uncached.native_status, reused.native_status);
    try std.testing.expectEqual(uncached.canonical, reused.canonical);
    try std.testing.expectEqualStrings(uncached.llvm, reused.llvm);
    try std.testing.expect(reused.statistics.misses[@backingInt(cache.Stage.inline_cfg)] > 0);
}

// spec-case: NEW-CORE-INLINE-1
// spec-case: NEW-CORE-S4-SITES-1
test "scalar reader five native modes and RC control retain discarded checks and failure order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    try environment.put("MYLANG_COUNTERS", try std.fs.path.join(a, &.{ root, "counters.json" }));
    const compiler_path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, options.corePath(), a);
    const fixture_relative = try std.fs.path.join(a, &.{ options.fixtures, fixture_name });
    const fixture_path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, fixture_relative, a);
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, fixture_path, a, .limited(1 << 20));
    const prefix = source[0..std.mem.indexOf(u8, source, "func main(out:").?];
    const Case = struct { name: []const u8, call: []const u8, ip: []const u8, object: []const u8, category: []const u8 };
    const cases = [_]Case{
        .{ .name = "discarded", .call = "_ = read_byte(rt, 0, mut ip)", .ip = "5", .object = "Object.function(value=Function(code=[18], constants=[]))", .category = "R_LIST_BOUNDS" },
        .{ .name = "read-first", .call = "_ = read_byte(rt, 0, mut ip)", .ip = "9223372036854775807", .object = "Object.function(value=Function(code=[18], constants=[]))", .category = "R_LIST_BOUNDS" },
        .{ .name = "advance-first", .call = "_ = advance_first(rt, 0, mut ip)", .ip = "9223372036854775807", .object = "Object.function(value=Function(code=[18], constants=[]))", .category = "R_OVERFLOW" },
        .{ .name = "kind", .call = "_ = read_byte(rt, 0, mut ip)", .ip = "0", .object = "Object.alternate(value=3)", .category = "R_ASSERT" },
        .{ .name = "constant-pool", .call = "_ = read_constant(rt, 0, mut ip)", .ip = "0", .object = "Object.function(value=Function(code=[7], constants=[Item.integer(value=42)]))", .category = "R_LIST_BOUNDS" },
    };
    for ([_][]const []const u8{ &.{ "--release", "--verify-facts" }, &.{"--release"}, &.{"--unoptimized"}, &.{"--optimize-debug"}, &.{ "--release", "--no-facts" } }) |flags| {
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ compiler_path, "run", fixture_path, "--cache-dir", root, "--experimental-zero-rc" });
        try argv.appendSlice(a, flags);
        const good = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment, .cwd = .{ .path = root } });
        if (good.term != .exited or good.term.exited != 0) std.debug.print("{s}{s}\n", .{ good.stdout, good.stderr });
        try std.testing.expect(good.term == .exited and good.term.exited == 0);
        try std.testing.expectEqualStrings("", good.stderr);
        for (cases) |case| {
            const path = try std.fs.path.join(a, &.{ root, try std.fmt.allocPrint(a, "{s}.my", .{case.name}) });
            const main = try std.fmt.allocPrint(a, "func main(out: Stream) -> int:\n" ++
                "    mut rt = Runtime(objects=[{s}])\n    mut ip = {s}\n" ++
                "    out.print(\"before\")\n    {s}\n" ++
                "    out.print(\"after\")\n    return 0\n", .{ case.object, case.ip, case.call });
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = try std.mem.concat(a, u8, &.{ prefix, main }) });
            argv.clearRetainingCapacity();
            try argv.appendSlice(a, &.{ compiler_path, "run", path, "--cache-dir", root, "--experimental-zero-rc" });
            try argv.appendSlice(a, flags);
            const bad = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment, .cwd = .{ .path = root } });
            try std.testing.expect(bad.term == .exited and bad.term.exited != 0);
            try std.testing.expectEqualStrings("before\n", bad.stdout);
            try std.testing.expect(std.mem.indexOf(u8, bad.stderr, case.category) != null);
            if (std.mem.eql(u8, case.name, "kind")) try std.testing.expect(std.mem.indexOf(u8, bad.stderr, "object is not a function") != null);
        }
    }
    const rc = try std.process.run(a, std.testing.io, .{ .argv = &.{ compiler_path, "run", fixture_path, "--cache-dir", root, "--release" }, .environ_map = &environment, .cwd = .{ .path = root } });
    try std.testing.expect(rc.term == .exited and rc.term.exited == 0);
    try std.testing.expectEqualStrings("", rc.stderr);
}

const after_query =
    \\func read(values: int[], mut ip: int) -> int:
    \\    const selected = values[ip]
    \\    ip = ip + 1
    \\    return selected
    \\func arithmetic(mut ip: int, branch: bool) -> int:
    \\    if branch:
    \\        ip = ip + 1
    \\        return ip
    \\    ip = ip + 2
    \\    return ip
    \\func main(out: Stream) -> int:
    \\    mut values = [7, 9]
    \\    mut ip = 0
    \\    out.print(read(values, mut ip))
    \\    out.print(arithmetic(mut ip, True))
    \\    return 0
;

// spec-case: NEW-CORE-INLINE-1
test "scalar reader call free checked shape stays budgeted while arithmetic helper stays ordinary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try fromSource(a, after_query);
    const read = named(&module, "read");
    try std.testing.expect(reader.mutationShell(&module, read));
    try std.testing.expect(reader.mutationFamily(&module, read));
    try std.testing.expect(@import("inline_cfg.zig").qualifies(read));
    try std.testing.expect(!reader.mutationShell(&module, named(&module, "arithmetic")));
    const caller = &module.functions.items[module.entry];
    var template: ir.Ref = undefined;
    for (caller.insts.items, 0..) |inst, index| {
        if (inst.op == .call and std.mem.eql(u8, module.functions.items[inst.a.index()].name, "read")) template = @fromBackingInt(@intCast(index));
    }
    const cost = read.insts.items.len + 3;
    try duplicateCalls(a, caller, template, 40, true);
    const before = calls(&module, caller, "read");
    var table: origins.Table = .{};
    _ = try inliner.cfgCallerDemandWithScratch(a, a, &module, module.entry, &table, null);
    const cloned = before - calls(&module, caller, "read");
    try std.testing.expect(cloned > 0 and cloned <= @import("destination.zig").max_caller_instructions / cost);
    try std.testing.expect(cloned < before);
    try support.verified(a, &module, &.{});
}

const RawLoader = struct {
    arena: std.mem.Allocator,
    context: snapshot.Context,
    bodies: []snapshot.Wire,
    fn ensure(pointer: *anyopaque, index: u32) @import("demand_ir.zig").Error!void {
        const self: *RawLoader = @ptrCast(@alignCast(pointer));
        self.context.module.functions.items[index] = snapshot.restore(self.arena, self.context, self.bodies[index]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return error.CacheMiss,
        };
    }
};

fn prependDeadCalls(a: std.mem.Allocator, module: *ir.Module, count: usize) !void {
    const caller = &module.functions.items[module.entry];
    var dead = caller.inst(firstByteCall(module, caller));
    // Different query: dead read_constant shells must not hide live read_byte.
    for (module.functions.items, 0..) |f, index| {
        if (std.mem.eql(u8, f.name, "read_constant")) {
            dead.a = @fromBackingInt(@intCast(index));
            dead.ty = f.signature.ret;
        }
    }
    @memset(try caller.insts.addManyAt(a, 0, count), dead);
    for (caller.insts.items[count..]) |*inst| {
        if (inst.a != .none and inst.op != .call) inst.a = @fromBackingInt(@intCast(inst.a.index() + count));
        if (inst.b != .none) inst.b = @fromBackingInt(@intCast(inst.b.index() + count));
    }
    for (caller.extra.items) |*ref| if (ref.* != .none) {
        ref.* = @fromBackingInt(@intCast(ref.index() + count));
    };
    for (caller.blocks.items) |*block| for (block.insts.items) |*ref| {
        ref.* = @fromBackingInt(@intCast(ref.index() + count));
    };
}

fn compileDeferred(a: std.mem.Allocator, backing: std.mem.Allocator, source: []const u8, storage: *store.Store, dead_calls: usize) !Produced {
    var module = try fromSource(a, source);
    try prependDeadCalls(a, &module, dead_calls);
    const token: u8 = 0;
    const locator: emitter.Locator = .{ .context = &token, .locate = locate };
    const source_context = try snapshot.Context.init(a, &module, null);
    const layout = try snapshot.layout(a, source_context);
    const count = module.functions.items.len;
    const bodies = try a.alloc(snapshot.Wire, count);
    const keys = try a.alloc(?store.Digest, count);
    const loaded = try a.alloc(bool, count);
    for (module.functions.items, bodies, keys, loaded) |*f, *wire, *key, *present| {
        wire.* = try snapshot.capture(a, source_context, f.*);
        const digest = try snapshot.digest(a, source_context, f.*);
        key.* = storage.key("scalar-reader-raw", &.{ &layout, &digest });
        present.* = f.signature.linkage != .internal;
        if (!present.*) f.* = .{ .name = f.name, .signature = f.signature, .span = f.span };
    }
    var loader: RawLoader = .{ .arena = a, .context = source_context, .bodies = bodies };
    var demand: @import("demand_ir.zig").Context = .{ .keys = keys, .loaded = loaded, .pointer = &loader, .ensure_fn = RawLoader.ensure };
    var context = cache.Context.init(storage, source_context, locator);
    context.lazy.raw = &demand;
    var table = try @import("deferred_facts.zig").Table.init(a, count);
    var result = try passes.runCachedDeferred(a, backing, &module, .verify, &context, &table);
    var final_work = std.heap.ArenaAllocator.init(backing);
    defer final_work.deinit();
    for (module.functions.items, 0..) |f, index| {
        if (f.signature.linkage != .internal) continue;
        if (!context.lazy.loaded[index]) try passes.restoreDeferredFinal(a, final_work.allocator(), &context, @intCast(index), &result);
        result.known[index] = try table.load(a, index);
        _ = final_work.reset(.retain_capacity);
    }
    try support.verified(a, &module, result.plans);
    const llvm = try emitter.emitModule(a, &module, .{ .locator = locator, .source_path = fixture_name, .main = .{ .parameters = &.{"out"}, .capabilities = &.{0} }, .analysis = support.analysis(&result) });
    var canon = try @import("canonical_ir.zig").Canon.prepare(a, &module, locator);
    var hash = std.crypto.hash.Blake3.init(.{});
    for (module.functions.items, 0..) |_, index| {
        const digest = try canon.functionDigest(@intCast(index));
        hash.update(&digest);
    }
    var canonical: [32]u8 = undefined;
    hash.final(&canonical);
    return .{ .llvm = llvm, .text = try @import("print.zig").module(a, &module), .canonical = canonical, .statistics = context.statistics, .native_status = 0 };
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "scalar reader prepares deferred live query after thirty two dead raw shells" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]usize{ 31, 32, 33 }) |dead_calls| {
        var module = try fixture(a);
        try prependDeadCalls(a, &module, dead_calls);
        const context = try snapshot.Context.init(a, &module, null);
        const bodies = try a.alloc(snapshot.Wire, module.functions.items.len);
        const keys = try a.alloc(?store.Digest, bodies.len);
        @memset(keys, null);
        const loaded = try a.alloc(bool, bodies.len);
        var query: ?usize = null;
        for (module.functions.items, bodies, loaded, 0..) |*f, *body, *present, index| {
            body.* = try snapshot.capture(a, context, f.*);
            if (std.mem.eql(u8, f.name, "instruction")) query = index;
            present.* = index == module.entry or f.signature.linkage != .internal;
            if (!present.*) f.* = .{ .name = f.name, .signature = f.signature, .span = f.span };
        }
        try std.testing.expect(query != null);
        try std.testing.expect(!loaded[query.?]);
        var loader: RawLoader = .{ .arena = a, .context = context, .bodies = bodies };
        var demand: @import("demand_ir.zig").Context = .{ .keys = keys, .loaded = loaded, .pointer = &loader, .ensure_fn = RawLoader.ensure };
        try passes.prepareReaderQueries(&module, &demand, module.entry);
        try std.testing.expect(loaded[query.?]);
        try std.testing.expect(reader.mutationFamily(&module, named(&module, "read_byte")));
    }
}

fn editQuery(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, source, "    # query edit reservation:").?;
    const end = start + std.mem.indexOfScalar(u8, source[start..], '\n').?;
    const line = try a.dupe(u8, source[start..end]);
    @memset(line, 'x');
    const prefix = "    _ = constant_operand(rt, 1, 0) # ";
    @memcpy(line[0..prefix.len], prefix);
    return std.mem.replaceOwned(u8, a, source, source[start..end], line);
}

// spec-case: NEW-CORE-STAGE-CACHE-8
test "scalar reader deferred query edits in both directions match fresh cache at raw boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try std.fs.path.join(a, &.{ options.fixtures, fixture_name });
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
    const edited = try editQuery(a, source);
    try std.testing.expectEqual(source.len, edited.len);
    for ([_]usize{ 32, 33 }) |dead_calls| {
        for ([_]bool{ false, true }) |reverse| {
            var old_dir = std.testing.tmpDir(.{});
            defer old_dir.cleanup();
            var fresh_dir = std.testing.tmpDir(.{});
            defer fresh_dir.cleanup();
            var prior = try store.Store.init(std.testing.allocator, std.testing.io, try old_dir.dir.realPathFileAlloc(std.testing.io, ".", a));
            defer prior.deinit();
            var fresh = try store.Store.init(std.testing.allocator, std.testing.io, try fresh_dir.dir.realPathFileAlloc(std.testing.io, ".", a));
            defer fresh.deinit();
            const before = if (reverse) edited else source;
            const after = if (reverse) source else edited;
            const cold = try compileDeferred(a, std.testing.allocator, before, &prior, dead_calls);
            const warm = try compileDeferred(a, std.testing.allocator, before, &prior, dead_calls);
            try std.testing.expectEqual(cold.canonical, warm.canonical);
            try std.testing.expectEqualStrings(cold.llvm, warm.llvm);
            const oracle = try compileDeferred(a, std.testing.allocator, after, &fresh, dead_calls);
            const reused = try compileDeferred(a, std.testing.allocator, after, &prior, dead_calls);
            try std.testing.expectEqual(oracle.canonical, reused.canonical);
            try std.testing.expectEqualStrings(oracle.llvm, reused.llvm);
            try std.testing.expect(reused.statistics.restores.checkpoints > 0);
        }
    }
}
