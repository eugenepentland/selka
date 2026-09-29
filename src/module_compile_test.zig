//! Per-module compilation (MODULE-COMPILE-1..3): a module compiled from its
//! own source and its imports' interfaces emits the units the whole-program
//! emission emits for it, key for key; its interface carries the emission
//! facts its dependents read; and a lambda's name does not depend on what the
//! program merges around it (LAMBDA-NAME-1).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const iface = language.module_interface;
const oracle = language.module_interface_oracle;
const compile_module = language.module_compile;
const fragments = language.qbe_fragments;

const util_source =
    \\module util
    \\
    \\
    \\public record Pair:
    \\    left: int
    \\    right: int
    \\
    \\
    \\public def largest[T: integer](values: list[T]) -> T:
    \\    best = values[0]
    \\    for value in values:
    \\        if value > best:
    \\            best = value
    \\    return best
    \\
    \\
    \\public def twice(value: int) -> int effects():
    \\    return value * 2
    \\
    \\
    \\public def swapped(pair: Pair) -> int effects():
    \\    pair = Pair(left=pair.right, right=pair.left)
    \\    if pair.left > 1000:
    \\        return swapped(pair)
    \\    return pair.left * 10 + pair.right
    \\
    \\
    \\public def grow(values: list[int]) -> list[int]:
    \\    out: list[int] = []
    \\    for value in values:
    \\        out.append(value + largest(values))
    \\    return out
    \\
;

const stats_source =
    \\module stats
    \\import util
    \\
    \\
    \\public def top(values: list[int]) -> int:
    \\    ordered = sorted(values, key=lambda v: 0 - v)
    \\    return util.largest(ordered) + util.twice(len(values))
    \\
;

const main_source =
    \\module main
    \\import util
    \\import stats
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    values = util.grow([3, 9, 4])
    \\    ranked = sorted(values, key=lambda v: v % 3)
    \\    pair = util.Pair(left=ranked[0], right=stats.top(values))
    \\    out.print(pair)
    \\    return util.largest(values) + util.swapped(pair)
    \\
;

const Files = struct { util: []const u8 = util_source, stats: []const u8 = stats_source, main: []const u8 = main_source };

fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const files: *const Files = @ptrCast(@alignCast(context.?));
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, files.main);
    if (std.mem.eql(u8, path, "stats.my")) return allocator.dupe(u8, files.stats);
    if (std.mem.eql(u8, path, "util.my")) return allocator.dupe(u8, files.util);
    return error.NotFound;
}

/// The Debug configuration a plain `build` emits with, with the program's
/// arena switch.
const debug: iface.EmissionConfig = .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .checks = true, .arenas = false };

/// The whole-program lean executable emission's report, into `arena`.
fn wholeReport(arena: std.mem.Allocator, root: []const u8, files: *const Files) !fragments.Report {
    var store = try fragments.Store.open(arena, t.io, root, "test-compiler", "whole");
    defer store.deinit();
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = @constCast(files), .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    var report: fragments.Report = .{ .arena = arena };
    compilation.reuse = .{ .store = &store, .lean = true, .executable = true, .report = &report };
    const manifest = try compilation.emitQbe(t.allocator);
    t.allocator.free(manifest);
    return report;
}

/// Compile `module` against the interfaces in `list`; the caller deinits the result.
fn compileOne(arena: std.mem.Allocator, store: *fragments.Store, list: []const iface.Interface, module: Module) !compile_module.Compiled {
    var library = try oracle.Library.of(arena, list);
    var compiled: compile_module.Compiled = undefined;
    compile_module.compile(t.allocator, arena, .{
        .module = .{ .module = module.name, .bytes = module.bytes, .is_entry = std.mem.eql(u8, module.name, "main"), .library = &library },
        .config = debug,
        .reuse = .{ .store = store, .lean = true, .executable = true },
    }, &compiled) catch |err| {
        compiled.deinit();
        return err;
    };
    return compiled;
}

const Module = struct { name: []const u8, bytes: []const u8 };

fn entryOf(report: fragments.Report, name: []const u8) ?fragments.FunctionReport {
    for (report.functions) |entry| if (std.mem.eql(u8, entry.name, name)) return entry;
    return null;
}

/// What compiling every module in import order produced: each module's
/// interface (as a dependent reads it) and how many modules emitted each unit.
const Compiled = struct { interfaces: []const iface.Interface, emitted: std.StringHashMapUnmanaged(usize), compared: usize };

/// Compile `util`, `stats` and `main` in import order, each against the
/// interfaces the earlier ones wrote, and require every unit each emits to be
/// the whole program's: the same fragment key, text and metadata digests and
/// emission facts.
fn compileAll(arena: std.mem.Allocator, store: *fragments.Store, whole: fragments.Report) !Compiled {
    var interfaces: std.ArrayList(iface.Interface) = .empty;
    var out: Compiled = .{ .interfaces = &.{}, .emitted = .empty, .compared = 0 };
    for ([_]Module{ .{ .name = "util", .bytes = util_source }, .{ .name = "stats", .bytes = stats_source }, .{ .name = "main", .bytes = main_source } }) |module| {
        var compiled = try compileOne(arena, store, interfaces.items, module);
        defer compiled.deinit();
        try interfaces.append(arena, iface.decode(arena, try iface.encode(arena, compiled.interface)) orelse return error.TestUnexpectedResult);
        for (compiled.report.functions) |entry| {
            if (!entry.emitted) continue;
            const reference = entryOf(whole, entry.name) orelse return error.TestUnexpectedResult;
            try t.expectEqualStrings(reference.keys.unit, entry.keys.unit);
            try t.expectEqualStrings(reference.keys.il, entry.keys.il);
            try t.expectEqualStrings(reference.keys.meta, entry.keys.meta);
            try t.expectEqual(reference.allocates, entry.allocates);
            try t.expectEqualSlices(bool, reference.writes, entry.writes);
            const seen = try out.emitted.getOrPut(arena, entry.name);
            seen.value_ptr.* = if (seen.found_existing) seen.value_ptr.* + 1 else 1;
            out.compared += 1;
        }
    }
    out.interfaces = interfaces.items;
    return out;
}

/// Whether every unit of the whole program was emitted by some module.
fn everyUnitEmitted(whole: fragments.Report, emitted: std.StringHashMapUnmanaged(usize)) bool {
    for (whole.functions) |entry| if (entry.emitted and !emitted.contains(entry.name)) return false;
    return true;
}

/// Whether `interface` states that `name` is pure and writes its first parameter.
fn pureWriter(interface: iface.Interface, name: []const u8) bool {
    for (interface.emission.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function.writes[0] and !function.allocates;
    }
    return false;
}

// spec: MODULE-COMPILE-1
test "every module compiled from its imports' interfaces emits the whole program's units, key for key" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", arena);
    const files: Files = .{};
    const whole = try wholeReport(arena, try std.fs.path.join(arena, &.{ base, "whole" }), &files);
    try t.expect(!whole.arenas);
    var store = try fragments.Store.open(arena, t.io, try std.fs.path.join(arena, &.{ base, "modules" }), "test-compiler", "modules");
    defer store.deinit();
    const compiled = try compileAll(arena, &store, whole);
    // Every unit of the whole program came from some module; `util.largest[i64]`
    // came from `util`, `stats` and `main` alike, as one unit.
    try t.expect(everyUnitEmitted(whole, compiled.emitted));
    try t.expectEqual(@as(usize, 3), compiled.emitted.get("util::largest[i64]").?);
    try t.expect(compiled.compared > whole.functions.len / 2);
    // `main` stood `util.swapped` in, a pure function that writes its record
    // parameter: the caller read that from `util`'s interface.
    try t.expect(pureWriter(compiled.interfaces[0], "util::swapped"));
}

// spec-case: MODULE-COMPILE-1
test "RC module compiled physical inputs preserve whole-program units and pin contracts" {
    const saved_runtime = language.runtime_mode.get();
    defer language.runtime_mode.set(saved_runtime);
    language.runtime_mode.set(.rc);
    const saved_values = language.value_semantics.enabled();
    defer language.value_semantics.setEnabled(saved_values);
    language.value_semantics.setEnabled(true);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", arena);
    const files: Files = .{};
    const whole = try wholeReport(arena, try std.fs.path.join(arena, &.{ base, "whole" }), &files);
    try t.expect(!whole.arenas);
    var store = try fragments.Store.open(arena, t.io, try std.fs.path.join(arena, &.{ base, "modules" }), "test-compiler", "modules");
    defer store.deinit();
    const compiled = try compileAll(arena, &store, whole);
    // Every unit of the whole program came from some module; `util.largest[i64]`
    // came from `util`, `stats` and `main` alike, as one unit.
    try t.expect(everyUnitEmitted(whole, compiled.emitted));
    try t.expectEqual(@as(usize, 3), compiled.emitted.get("util::largest[i64]").?);
    try t.expect(compiled.compared > whole.functions.len / 2);
    // `main` stood `util.swapped` in, a pure function that writes its record
    // parameter: the caller read that from `util`'s interface.
    try t.expect(pureWriter(compiled.interfaces[0], "util::swapped"));
}

// spec: MODULE-COMPILE-2
test "a compiled module's interface carries its emission facts under their own hash" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", arena);
    var store = try fragments.Store.open(arena, t.io, base, "test-compiler", "modules");
    defer store.deinit();
    var compiled = try compileOne(arena, &store, &.{}, .{ .name = "util", .bytes = util_source });
    defer compiled.deinit();
    const interface = compiled.interface;
    try t.expectEqualStrings(try iface.configName(arena, debug), interface.emission.config);
    try t.expect(interface.emission.functions.len >= 3);
    const decoded = iface.decode(arena, try iface.encode(arena, interface)) orelse return error.TestUnexpectedResult;
    try t.expectEqualSlices(u8, &iface.emissionHash(interface), &iface.emissionHash(decoded));
    // A flipped fact changes the emission hash and leaves the interface hash.
    var flipped = decoded;
    const functions = try arena.dupe(iface.EmittedFunction, decoded.emission.functions);
    functions[0].allocates = !functions[0].allocates;
    flipped.emission.functions = functions;
    try t.expect(!std.mem.eql(u8, &iface.emissionHash(decoded), &iface.emissionHash(flipped)));
    try t.expectEqualSlices(u8, &iface.interfaceHash(decoded), &iface.interfaceHash(flipped));
    try t.expect(std.mem.indexOf(u8, try iface.render(arena, decoded), "emission debug=kept") != null);
    // `stats` cannot compile against an interface that holds no emission
    // facts (one `interfaces emit` wrote from a check alone).
    var bare = decoded;
    bare.emission = .{};
    try t.expectError(error.MissingEmission, compileOne(arena, &store, &.{bare}, .{ .name = "stats", .bytes = stats_source }));
}

/// How many of the program's functions carry one of `names`.
fn named(functions: []const @import("typed.zig").Function, names: []const []const u8) usize {
    var found: usize = 0;
    for (functions) |function| {
        for (names) |name| found += @intFromBool(std.mem.eql(u8, function.name, name));
    }
    return found;
}

// spec: LAMBDA-NAME-1
test "a lambda is named by its module and its offset in that module's source" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    const files: Files = .{};
    try project.load(.{ .context = @constCast(&files), .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    var buffer: [2][64]u8 = undefined;
    const in_main = try std.fmt.bufPrint(&buffer[0], "lambda@main::{d}", .{std.mem.indexOf(u8, main_source, "lambda v: v % 3").?});
    const in_stats = try std.fmt.bufPrint(&buffer[1], "lambda@stats::{d}", .{std.mem.indexOf(u8, stats_source, "lambda v: 0 - v").?});
    try t.expectEqual(@as(usize, 2), named(compilation.program.?.functions, &.{ in_main, in_stats }));
}

// spec: MODULE-COMPILE-3
test "descriptor and renderer blocks render to the unit a whole emission writes" {
    const blocks = [_]language.native_descriptors.Block{ .{ .name = "myl_t_a", .text = "A;\n" }, .{ .name = "myl_t_b", .text = "B;\n" } };
    const rendered = try language.native_descriptors.render(t.allocator, &blocks);
    defer t.allocator.free(rendered);
    try t.expectEqualStrings("#include \"native_heap.h\"\nextern const myl_native_type myl_t_a;\nextern const myl_native_type myl_t_b;\nA;\nB;\n", rendered);
    const none = try language.native_render.render(t.allocator, &.{});
    defer t.allocator.free(none);
    try t.expectEqualStrings("", none);
    const renderers = [_]language.native_render.Block{.{ .name = "myl_r_a", .text = "R;\n" }};
    const printed = try language.native_render.render(t.allocator, &renderers);
    defer t.allocator.free(printed);
    try t.expectEqualStrings("#include \"native_print.h\"\nvoid myl_r_a(MylPrint *, const void *, unsigned);\nR;\n", printed);
}

/// A units file of one module: its manifest's store, entry and units, and
/// its descriptor blocks, as `compile-module` writes it.
fn unitsFile(arena: std.mem.Allocator, text: []const u8) !std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, arena, text, .{});
}

// spec-case: MODULE-COMPILE-3
test "a link keeps one copy of a specialization two modules emitted, and refuses two different ones" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const library = try unitsFile(a,
        \\{"descriptors":[{"name":"myl_t_b","text":"B;\n"}],"renderers":[],"manifest":{"store":"/s","entry":"","text_format":false,
        \\ "host":{"types":[],"declarations":[]},"functions":[{"name":"m::f[i64]","symbol":"myl_f_1","il_digest":"aa","meta_digest":"bb"}]}}
    );
    const entry = try unitsFile(a,
        \\{"descriptors":[{"name":"myl_t_a","text":"A;\n"},{"name":"myl_t_b","text":"B;\n"}],"renderers":[],"manifest":{"store":"/s","entry":"myl_f_0",
        \\ "text_format":true,"host":{"types":[],"declarations":[]},"functions":[{"name":"main::main","symbol":"myl_f_0","il_digest":"cc","meta_digest":"dd"},
        \\ {"name":"m::f[i64]","symbol":"myl_f_1","il_digest":"aa","meta_digest":"bb"}]}}
    );
    const merged = try language.module_link.merge(a, &.{ library, entry });
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, merged, "\"myl_f_1\""));
    try t.expect(std.mem.indexOf(u8, merged, "extern const myl_native_type myl_t_a;\\nextern const myl_native_type myl_t_b;\\nA;\\nB;\\n") != null);
    try t.expect(std.mem.indexOf(u8, merged, "\"text_format\":true") != null);
    // The same symbol with another text is two different programs.
    const clash = try unitsFile(a,
        \\{"descriptors":[],"renderers":[],"manifest":{"store":"/s","entry":"","host":{},"functions":[{"name":"m::f[i64]","symbol":"myl_f_1","il_digest":"ee","meta_digest":"bb"}]}}
    );
    try t.expectError(error.Conflict, language.module_link.merge(a, &.{ entry, clash }));
    // Without the entry module, or across two unit stores, there is no program.
    try t.expectError(error.Incomplete, language.module_link.merge(a, &.{library}));
    const elsewhere = try unitsFile(a,
        \\{"descriptors":[],"renderers":[],"manifest":{"store":"/other","entry":"","host":{},"functions":[]}}
    );
    try t.expectError(error.Incomplete, language.module_link.merge(a, &.{ entry, elsewhere }));
}
