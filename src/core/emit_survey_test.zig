//! A program's survey (`emit_survey.zig`) and the fast paths read once per unit (`emit_fast_paths.zig`) leave every unit's
//! text as it was when each render read the whole module and scanned its text once for each helper.
const std = @import("std");
const ir = @import("ir.zig");
const emitter = @import("emit_llvm.zig");
const constants = @import("emit_constants.zig");
const survey_module = @import("emit_survey.zig");
const fast_paths = @import("emit_fast_paths.zig");
const support = @import("test_support.zig");
const test_builder = @import("test_builder.zig");

fn fixedLocation(_: *const anyopaque, _: u32) emitter.Location {
    return .{ .path = "survey.selka", .line = 1, .column = 1 };
}

const location_context: u8 = 0;

/// A module of two units' worth of functions: `app::main` calls `leaf::identity` and builds a list and a string.
fn surveyModule(a: std.mem.Allocator) !ir.Module {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const string = module.strings.items.len;
    try module.strings.append(a, "stable");
    var target = try support.Hand.init(a, &module, "leaf::identity", .{ .params = &.{.i64}, .ret = .i64 });
    _ = try target.emit(.{ .op = .ret, .ty = .void, .a = try target.param(0) });
    const callee = try target.finish();
    var caller = try support.Hand.init(a, &module, "app::main", .{ .params = &.{}, .ret = .i64 });
    _ = try caller.loose(.{ .op = .undef, .ty = list });
    _ = try caller.loose(.{ .op = .str_const, .ty = .str, .data = string });
    const number = try caller.int(.i64, 19);
    const call = try caller.emit(.{ .op = .call, .ty = .i64, .a = @fromBackingInt(callee), .data = try caller.extra(&.{number}), .span = 11 });
    _ = try caller.emit(.{ .op = .ret, .ty = .void, .a = call });
    module.entry = try caller.finish();
    return module;
}

/// Each function of `module` rendered as a unit of its own, then the entry unit, joined; with `survey` given to every render
/// when it is not null.
fn renderUnits(a: std.mem.Allocator, module: *const ir.Module, survey: ?*const survey_module.Survey) ![]const u8 {
    const summaries = try @import("effects.zig").analyze(a, module);
    const options: emitter.Options = .{ .locator = .{ .context = &location_context, .locate = fixedLocation }, .source_path = "survey.selka", .main = .{}, .analysis = .{ .effects = &summaries } };
    const catalog = try constants.Catalog.init(a, module);
    const exported = try a.alloc(bool, module.functions.items.len);
    @memset(exported, true);
    const symbols = try a.alloc(?[]const u8, exported.len);
    @memset(symbols, null);
    var joined: std.ArrayList(u8) = .empty;
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage != .internal) continue;
        const one = [_]u32{@intCast(index)};
        try joined.appendSlice(a, try emitter.emitUnitWithScratch(a, a, module, options, .{ .functions = &one, .exported = exported, .symbols = symbols, .source_path = "survey.selka", .constants = &catalog, .survey = survey }));
    }
    try joined.appendSlice(a, try emitter.emitUnitWithScratch(a, a, module, options, .{ .functions = &.{}, .exported = exported, .symbols = symbols, .entry = true, .source_path = "survey.selka", .constants = &catalog, .survey = survey }));
    return joined.items;
}

fn surveyOf(a: std.mem.Allocator, module: *const ir.Module) !survey_module.Survey {
    const summaries = try @import("effects.zig").analyze(a, module);
    return emitter.survey(a, module, .{ .locator = .{ .context = &location_context, .locate = fixedLocation }, .source_path = "survey.selka", .main = .{}, .analysis = .{ .effects = &summaries } });
}

test "a unit rendered with its program's survey is the unit each render made reading the whole module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try surveyModule(a);
    const plain = try surveyOf(a, &module);
    try std.testing.expect(plain.equality and !plain.test_counts and plain.fits(&module));
    try std.testing.expectEqualStrings(try renderUnits(a, &module, null), try renderUnits(a, &module, &plain));
    // A `testing` import declares the allocation counter, which selects the counting fast paths.
    _ = try test_builder.helper(a, &module, "myl_core_test_allocations", &.{.bool}, .i64);
    try std.testing.expect(!plain.fits(&module));
    const counted = try surveyOf(a, &module);
    try std.testing.expect(counted.test_counts and counted.fits(&module));
    const fresh = try renderUnits(a, &module, null);
    try std.testing.expectEqualStrings(fresh, try renderUnits(a, &module, &counted));
    // A survey of another module (fewer functions) is not read: the render reads the module.
    try std.testing.expectEqualStrings(fresh, try renderUnits(a, &module, &plain));
}

test "a program whose equality declarations are refused fails every unit with or without its survey" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try surveyModule(a);
    // A reserved equality name whose key list is malformed grants no authority (`build_equality.declaration`).
    _ = try test_builder.helper(a, &module, @import("build_equality.zig").prefix ++ "not-a-key", &.{ .i64, .i64 }, .bool);
    const refused = try surveyOf(a, &module);
    try std.testing.expect(!refused.equality and refused.fits(&module));
    try std.testing.expectError(error.UnsupportedInstruction, renderUnits(a, &module, null));
    try std.testing.expectError(error.UnsupportedInstruction, renderUnits(a, &module, &refused));
    try std.testing.expectError(error.UnsupportedInstruction, survey_module.validateEquality(a, &refused, &module));
}

/// The fast paths as `emit_llvm.fastPaths` appended them before the prelude was parsed once and the unit read once: the
/// unit's text scanned for each name, and each reached definition for each name.
fn referenceFastPaths(a: std.mem.Allocator, out: *std.ArrayList(u8), prelude: []const u8, body: []const u8, layouts: []const u8) !void {
    const first = std.mem.indexOf(u8, prelude, "define internal") orelse return error.UnsupportedInstruction;
    try out.appendSlice(a, prelude[0..first]);
    var definitions: std.ArrayList([]const u8) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    var start = first;
    while (start < prelude.len) {
        const close = std.mem.indexOfPos(u8, prelude, start, "\n}\n") orelse break;
        const definition = prelude[start .. close + 3];
        var refs: constants.Symbols = .{ .text = definition };
        const name = refs.next() orelse return error.UnsupportedInstruction;
        try definitions.append(a, definition);
        try names.append(a, name);
        start = close + 3;
    }
    var reached: std.ArrayList(u32) = .empty;
    for (names.items, 0..) |name, index| if (fast_paths.mentions(body, name) or fast_paths.mentions(layouts, name)) try reached.append(a, @intCast(index));
    var index: usize = 0;
    while (index < reached.items.len) : (index += 1) {
        const definition = definitions.items[reached.items[index]];
        try out.appendSlice(a, definition);
        for (names.items, 0..) |name, dependency| {
            if (!fast_paths.mentions(definition, name) or std.mem.indexOfScalar(u32, reached.items, @intCast(dependency)) != null) continue;
            try reached.append(a, @intCast(dependency));
        }
    }
}

fn parsedFastPaths(a: std.mem.Allocator, prelude: []const u8, body: []const u8, layouts: []const u8) ![]const u8 {
    const parsed = try fast_paths.Prelude.parse(a, prelude);
    const named = try fast_paths.Named.of(a, &.{ body, layouts });
    var out: std.ArrayList(u8) = .empty;
    try fast_paths.append(a, &out, &parsed, &named);
    return out.items;
}

fn referenceText(a: std.mem.Allocator, prelude: []const u8, body: []const u8, layouts: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try referenceFastPaths(a, &out, prelude, body, layouts);
    return out.items;
}

fn expectSameFastPaths(a: std.mem.Allocator, bodies: []const []const u8, layouts: []const []const u8) !void {
    for (bodies) |body| for (layouts) |layout| {
        try std.testing.expectEqualStrings(try referenceText(a, sample_prelude, body, layout), try parsedFastPaths(a, sample_prelude, body, layout));
    };
}

const sample_prelude =
    \\%myl.pair = type { i64, i64 }
    \\define internal i64 @myl.fast.a(i64 %x) {
    \\  %y = call i64 @myl.fast.c(i64 %x)
    \\  ret i64 %y
    \\}
    \\define internal i64 @myl.fast.b(i64 %x) {
    \\  ret i64 %x
    \\}
    \\define internal i64 @myl.fast.c(i64 %x) {
    \\  %z = call i64 @myl.fast.b(i64 %x)
    \\  ret i64 %z
    \\}
    \\define internal i64 @myl.fast.d(i64 %x) {
    \\  ret i64 %x
    \\}
    \\
;

test "the fast paths a unit reaches are appended in the order the per-name scans appended them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bodies = [_][]const u8{
        "  %r = call i64 @myl.fast.a(i64 1)\n",
        "  %r = call i64 @myl.fast.d(i64 1)\n  %s = call i64 @myl.fast.b(i64 2)\n",
        // A name inside quoted data is no reference.
        "@s = private constant [14 x i8] c\"@myl.fast.d\\00\"\n",
        "",
    };
    const layouts = [_][]const u8{ "", "@myl.layout.0 = private constant { ptr } { ptr @myl.fast.c }\n" };
    try expectSameFastPaths(a, &bodies, &layouts);
    const reached = try parsedFastPaths(a, sample_prelude, bodies[0], "");
    try std.testing.expect(std.mem.indexOf(u8, reached, "@myl.fast.c(i64 %x) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, reached, "@myl.fast.d(i64 %x) {") == null);
    try std.testing.expectError(error.UnsupportedInstruction, fast_paths.Prelude.parse(a, "declare void @f()\n"));
}
