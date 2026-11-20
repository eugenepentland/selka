//! The `@noalloc` promises of a checked program, as the `noalloc-closure` kind states them (spec §17.2, G2i): for each root, the
//! bodies of the functions Core reaches from it, tied to the declarations of the program, and the verdict.
//!
//! A root is a function that promises `@noalloc` (`allocation_contract` checks it by lowering the root and everything it calls to
//! Core). Its closure is the set of Core functions reachable from it; each is a function the front end made from a declaration, so
//! the declaration whose region holds the function's declaration start is the source of its body, and the body's digest is the one
//! `module-check` states for it (its key, region and dependency context of *this* run's check, never a stored record's: D-48). A
//! generic function that promises `@noalloc` is judged where it is instantiated, so each instance is a root of its own, and a root is
//! an instance when it carries type arguments.
//!
//! A root that breaks its promise has no answer (the program fails its check and nothing is recorded), and neither has a root whose
//! closure holds a function no declaration owns: it is not recorded rather than recorded with reads that are too few.
const std = @import("std");
const language = @import("selka");
const record = @import("engine/record.zig");
const noalloc_kind = @import("engine/kinds/noalloc_closure.zig");
const check_facts = @import("module_check_facts.zig");
const allocation_contract = @import("allocation_contract.zig");

/// The first line of the payload.
pub const payload_magic = "selka-noalloc-closure-v1";
/// The domain string of the verdict's digest.
const domain = "selka-noalloc-closure-verdict-v1";

/// One `@noalloc` root of a program: the argument it is queried under, the module that declares it, whether it is an instance of a
/// generic function, and the answer, absent when the root is not recorded.
pub const Root = struct { argument: []const u8, module: []const u8, instance: bool, answer: ?noalloc_kind.Answer };

/// What the roots are computed from: the checked program, its merged source and syntax, the declaration graph over them, the
/// regions the front end prepared for each declaration, and the query flags of the program's modules.
pub const Input = struct {
    program: language.typed.Program,
    src: language.source.Source,
    syntax: language.ast.Program,
    surface: *language.semantic_key.Surface,
    index: *language.interfaces.Index,
    regions: []const language.source.Span,
};

/// A declaration region, with the declaration it is the region of.
const Region = struct { span: language.source.Span, function: usize };

fn regionBefore(_: void, left: Region, right: Region) bool {
    return left.span.start < right.span.start;
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The function whose region holds `offset`, or null. `regions` are sorted by start and do not overlap.
fn ownerOf(regions: []const Region, offset: usize) ?usize {
    var low: usize = 0;
    var high = regions.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (regions[middle].span.start <= offset) low = middle + 1 else high = middle;
    }
    if (low == 0) return null;
    const candidate = regions[low - 1];
    return if (offset < candidate.span.end) candidate.function else null;
}

/// The argument a root is queried under: the declaring module's path, the root's name and the program flags.
pub fn argumentOf(a: std.mem.Allocator, module: []const u8, name: []const u8, flags: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x1f{s}\x00{s}", .{ module, name, flags });
}

/// Every `@noalloc` root of the program, in program order, with its answer. Everything is allocated in `a`, which should be an arena.
pub fn compute(a: std.mem.Allocator, input: Input, flags: []const u8) std.mem.Allocator.Error![]const Root {
    const analysed = try allocation_contract.analyzeProgram(a, input.program, input.src);
    const regions = try a.alloc(Region, input.regions.len);
    for (input.regions, regions, 0..) |span, *slot, function| slot.* = .{ .span = span, .function = function };
    std.mem.sort(Region, regions, {}, regionBefore);
    const modules = input.index.project.modules.items;
    const out = try a.alloc(Root, analysed.len);
    var count: usize = 0;
    for (analysed) |root| {
        const function = input.program.functions[@backingInt(root.function)];
        const declaring = ownerOf(regions, function.declaration.start) orelse continue;
        const module = input.surface.moduleOfKey(language.semantic_key.Surface.functionKey(declaring));
        if (module >= modules.len) continue;
        const path = modules[module].src.path;
        const argument = try argumentOf(a, path, function.name, flags);
        out[count] = .{ .argument = argument, .module = path, .instance = function.type_arguments.len != 0, .answer = try answerOf(a, input, regions, flags, root, argument) };
        count += 1;
    }
    return out[0..count];
}

/// The answer for one analysed root, or null when it breaks its promise or its closure cannot be tied to declarations.
fn answerOf(a: std.mem.Allocator, input: Input, regions: []const Region, flags: []const u8, root: allocation_contract.Root, argument: []const u8) std.mem.Allocator.Error!?noalloc_kind.Answer {
    if (root.failure != null or root.reached.len == 0) return null;
    const modules = input.index.project.modules.items;
    var by_module: std.array_hash_map.String(std.ArrayList([]const u8)) = .empty;
    for (root.reached) |reached| {
        if (reached.span == 0) return null;
        const owner = ownerOf(regions, @as(usize, reached.span)) orelse return null;
        const key = language.semantic_key.Surface.functionKey(owner);
        const module = input.surface.moduleOfKey(key);
        if (module >= modules.len) return null;
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ check_facts.body_prefix, try input.surface.nameOf(key) });
        const found = try by_module.getOrPut(a, try check_facts.moduleArgument(a, input.index, module, flags));
        if (!found.found_existing) found.value_ptr.* = .empty;
        if (!contains(found.value_ptr.items, name)) try found.value_ptr.append(a, name);
    }
    const reads = try a.alloc(noalloc_kind.Reads, by_module.count());
    for (by_module.keys(), by_module.values(), reads) |queried, names, *slot| {
        std.mem.sort([]const u8, names.items, {}, lessThan);
        slot.* = .{ .argument = queried, .names = names.items };
    }
    std.mem.sort(noalloc_kind.Reads, reads, {}, readsBefore);
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(domain);
    state.update("\x00");
    state.update(argument);
    var digest: [32]u8 = undefined;
    state.final(&digest);
    const parts = try a.dupe(record.Part, &.{.{ .name = noalloc_kind.verdict_part, .digest = digest }});
    const payload = try std.fmt.allocPrint(a, "{s}\n{s}\nkeeps its promise\n", .{ payload_magic, argument[0..std.mem.indexOfScalar(u8, argument, 0).?] });
    return .{ .payload = payload, .parts = parts, .bodies = reads };
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |known| if (std.mem.eql(u8, known, name)) return true;
    return false;
}

fn readsBefore(_: void, left: noalloc_kind.Reads, right: noalloc_kind.Reads) bool {
    return std.mem.lessThan(u8, left.argument, right.argument);
}

test "the owner of an offset is the region that holds it" {
    const regions = [_]Region{
        .{ .span = .{ .start = 0, .end = 10 }, .function = 3 },
        .{ .span = .{ .start = 20, .end = 30 }, .function = 1 },
    };
    try std.testing.expectEqual(@as(?usize, 3), ownerOf(&regions, 0));
    try std.testing.expectEqual(@as(?usize, 3), ownerOf(&regions, 9));
    try std.testing.expectEqual(@as(?usize, null), ownerOf(&regions, 10));
    try std.testing.expectEqual(@as(?usize, 1), ownerOf(&regions, 25));
    try std.testing.expectEqual(@as(?usize, null), ownerOf(&regions, 30));
    try std.testing.expectEqual(@as(?usize, null), ownerOf(regions[1..], 5));
}
