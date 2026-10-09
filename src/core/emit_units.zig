//! Independent LLVM modules with deterministic source ownership and dependencies.
const std = @import("std");
const ir = @import("ir.zig");
const llvm = @import("emit_llvm.zig");
const values = @import("emit_values.zig");
const constants = @import("emit_constants.zig");
const number_runtime = @import("number_runtime.zig");
const effects = @import("effects.zig");

/// Native input suffix shared by the driver and ordered test-program identity.
pub const native_extension = ".ll";

/// One object input and its link dependencies, independent of other units' contents.
pub const Unit = struct {
    name: []const u8,
    source_path: []const u8,
    kind: Kind,
    llvm: []const u8,
    number: bool,
    math: bool,
    /// Emitted with `--counters`: the build links the counting runtime (`count_runtime.zig`).
    counting: bool,
};

/// Source modules, instantiated functions, compiler adapters, the C entry, and the
/// one whole-program unit of a release build (S4-1a).
pub const Kind = enum { module, generic, helper, entry, program };

const Group = struct {
    path: []const u8,
    kind: Kind,
    functions: std.ArrayList(u32) = .empty,
};

/// A release build's single unit: the whole program, so LLVM optimizes across every
/// module boundary. Like any unit it is keyed by its exact text.
/// The returned slice, names, paths and LLVM text belong to `a`.
/// Scratch uses `a`; arena callers retain its backing pages.
pub fn whole(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
    return wholeWithScratch(a, a, module, options);
}

/// Emit one whole-program unit, releasing temporary storage to `backing`.
pub fn wholeWithScratch(a: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
    const text = try llvm.emitModuleWithScratch(a, backing, module, options);
    errdefer a.free(text);
    const units = try a.alloc(Unit, 1);
    errdefer a.free(units);
    const name = try a.dupe(u8, "program");
    errdefer a.free(name);
    const path = try a.dupe(u8, options.source_path);
    units[0] = unit(name, path, .program, text);
    return units;
}

/// Partition the frozen IR, then emit each unit with only its reached constants.
/// Debug builds use this: an edit recompiles only the units whose text changed.
/// The returned slice, names, paths and LLVM text belong to `allocator`.
/// Scratch uses `allocator`; arena callers retain its backing pages.
pub fn emit(allocator: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
    return emitWithScratch(allocator, allocator, module, options);
}

/// Emit independent units, releasing partition and unit scratch to `backing`.
pub fn emitWithScratch(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, given: llvm.Options) llvm.Error![]Unit {
    // The partition, descriptor catalog and canonical symbol table are needed
    // only while emitting. Their explicit backing can return pages independently
    // of the caller's build arena, which retains just each finished unit.
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    var options = given;
    if (options.analysis.effects == null) {
        const summaries = try a.create(effects.Summaries);
        summaries.* = try effects.analyze(a, module);
        options.analysis.effects = summaries;
    }
    var groups: std.ArrayList(Group) = .empty;
    const owner = try a.alloc(?u32, module.functions.items.len);
    const exported = try a.alloc(bool, owner.len);
    const symbols = try a.alloc(?[]const u8, owner.len);
    @memset(owner, null);
    @memset(exported, false);
    @memset(symbols, null);
    for (module.functions.items, 0..) |*function, index| {
        const adapter = values.generated(function);
        const synthetic = function.signature.linkage == .internal and
            (std.mem.startsWith(u8, function.name, "lambda@") or std.mem.startsWith(u8, function.name, "__test_") or std.mem.eql(u8, function.name, "<entry>"));
        const helper = adapter or synthetic;
        if (function.signature.linkage != .internal and !helper) continue;
        const location = options.locator.locate(options.locator.context, function.span);
        const path = if (location.path.len != 0) location.path else options.source_path;
        const kind: Kind = if (helper) .helper else if (std.mem.indexOfScalar(u8, function.name, '[') != null) .generic else .module;
        const group = if (kind == .module) moduleGroup(groups.items, path) else null;
        const target = group orelse blk: {
            try groups.append(a, .{ .path = try a.dupe(u8, if (adapter) "myl.helper" else path), .kind = kind });
            break :blk @as(u32, @intCast(groups.items.len - 1));
        };
        owner[index] = target;
        try groups.items[target].functions.append(a, @intCast(index));
    }
    for (module.functions.items, 0..) |function, index| {
        for (function.insts.items) |inst| {
            const target: usize = switch (inst.op) {
                .call => inst.a.index(),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            if (target >= owner.len) return error.UnsupportedInstruction;
            if (owner[target] != null and owner[target] != owner[index]) exported[target] = true;
        }
    }
    exported[module.entry] = true;
    const catalog = try constants.Catalog.init(a, module);
    // Hash an adapter's complete closed text with a fixed self-name. Neither an IR
    // type ID nor the eventual hash can enter this seed, including recursively.
    for (groups.items) |group| {
        if (group.kind != .helper) continue;
        const index = group.functions.items[0];
        if (!values.generated(&module.functions.items[index])) continue;
        symbols[index] = "myl.helper.self";
        const seed = try llvm.emitUnitWithScratch(backing, backing, module, options, .{
            .functions = group.functions.items,
            .exported = exported,
            .symbols = symbols,
            .source_path = group.path,
            .constants = &catalog,
        });
        defer backing.free(seed);
        symbols[index] = try std.fmt.allocPrint(a, "myl.helper.{s}", .{try digest(a, seed)});
    }
    var units: std.ArrayList(Unit) = .empty;
    errdefer for (units.items) |emitted| {
        allocator.free(emitted.name);
        allocator.free(emitted.source_path);
        allocator.free(emitted.llvm);
    };
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(a);
    for (groups.items) |group| {
        const text = try llvm.emitUnitWithScratch(allocator, backing, module, options, .{
            .functions = group.functions.items,
            .exported = exported,
            .symbols = symbols,
            .source_path = group.path,
            .constants = &catalog,
        });
        errdefer allocator.free(text);
        const name = if (group.kind == .module) try std.fmt.allocPrint(a, "module-{s}", .{try digest(a, group.path)}) else try std.fmt.allocPrint(a, "{s}-{s}", .{ @tagName(group.kind), try digest(a, text) });
        try append(allocator, a, &units, &names, unit(name, group.path, group.kind, text));
    }
    {
        const entry = try llvm.emitUnitWithScratch(allocator, backing, module, options, .{
            .functions = &.{},
            .exported = exported,
            .symbols = symbols,
            .entry = true,
            .source_path = options.source_path,
            .constants = &catalog,
        });
        errdefer allocator.free(entry);
        try append(allocator, a, &units, &names, unit("entry", options.source_path, .entry, entry));
    }
    return allocator.dupe(Unit, units.items);
}

fn append(allocator: std.mem.Allocator, scratch: std.mem.Allocator, units: *std.ArrayList(Unit), names: *std.StringHashMapUnmanaged(usize), next: Unit) llvm.Error!void {
    const entry = try names.getOrPut(scratch, next.name);
    if (entry.found_existing) {
        const previous = units.items[entry.value_ptr.*];
        // Equal closed adapters may arise from separate nominal source types.
        // Their callers already share the canonical symbol; emit its body once.
        if (previous.kind != next.kind or !std.mem.eql(u8, previous.llvm, next.llvm)) return error.UnsupportedInstruction;
        allocator.free(next.llvm);
        return;
    }
    var owned = next;
    owned.name = try allocator.dupe(u8, next.name);
    errdefer allocator.free(owned.name);
    owned.source_path = try allocator.dupe(u8, next.source_path);
    errdefer allocator.free(owned.source_path);
    entry.value_ptr.* = units.items.len;
    try units.append(scratch, owned);
}

fn moduleGroup(groups: []const Group, path: []const u8) ?u32 {
    for (groups, 0..) |group, index| if (group.kind == .module and std.mem.eql(u8, group.path, path)) return @intCast(index);
    return null;
}

fn digest(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(text, &hash, .{});
    return std.fmt.allocPrint(a, "{x}", .{hash});
}

/// A unit of `text` with its link dependencies (number-text helpers, `-lm`) read from it.
pub fn unit(name: []const u8, path: []const u8, kind: Kind, text: []const u8) Unit {
    const math = std.mem.indexOf(u8, text, "llvm.sin.f64") != null or std.mem.indexOf(u8, text, "llvm.cos.f64") != null;
    const counting = std.mem.indexOf(u8, text, "@myl_count_current") != null;
    return .{ .name = name, .source_path = path, .kind = kind, .llvm = text, .number = number_runtime.needed(text), .math = math, .counting = counting };
}
