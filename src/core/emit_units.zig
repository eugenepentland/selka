//! Independent LLVM modules with deterministic source ownership and dependencies.
const std = @import("std");
const ir = @import("ir.zig");
const llvm = @import("emit_llvm.zig");
const values = @import("emit_values.zig");
const constants = @import("emit_constants.zig");
const imports = @import("emit_imports.zig");
const clone_policy = @import("emit_clone_policy.zig");
const number_runtime = @import("number_runtime.zig");

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
};

/// Source modules, instantiated functions, compiler adapters and the C entry.
pub const Kind = enum { module, generic, helper, entry };

const Group = struct {
    path: []const u8,
    kind: Kind,
    functions: std.ArrayList(u32) = .empty,
    imports: []const u32 = &.{},
};

/// Partition the frozen IR, then emit each unit with only its reached constants.
pub fn emit(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
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
    const entry_imports = if (options.analysis.facts.len != 0) try imports.entry(a, module, owner) else &.{};
    const entry_private = try clone_policy.privateBodies(a, module, entry_imports);
    exportImports(module, owner, exported, entry_imports);
    if (options.analysis.facts.len != 0) for (groups.items, 0..) |*group, index| {
        group.imports = try imports.select(a, module, owner, group.functions.items, @intCast(index));
        exportImports(module, owner, exported, group.imports);
    };
    const catalog = try constants.Catalog.init(a, module);
    // Hash an adapter's complete closed text with a fixed self-name. Neither an IR
    // type ID nor the eventual hash can enter this seed, including recursively.
    for (groups.items) |group| {
        if (group.kind != .helper) continue;
        const index = group.functions.items[0];
        if (!values.generated(&module.functions.items[index])) continue;
        symbols[index] = "myl.helper.self";
        const seed = try llvm.emitUnit(a, module, options, .{
            .functions = group.functions.items,
            .imports = .{ .functions = group.imports },
            .exported = exported,
            .symbols = symbols,
            .source_path = group.path,
            .constants = &catalog,
        });
        symbols[index] = try std.fmt.allocPrint(a, "myl.helper.{s}", .{try digest(a, seed)});
    }
    var units: std.ArrayList(Unit) = .empty;
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(a);
    for (groups.items) |group| {
        const text = try llvm.emitUnit(a, module, options, .{
            .functions = group.functions.items,
            .imports = .{ .functions = group.imports },
            .exported = exported,
            .symbols = symbols,
            .source_path = group.path,
            .constants = &catalog,
        });
        const name = if (group.kind == .module) try std.fmt.allocPrint(a, "module-{s}", .{try digest(a, group.path)}) else try std.fmt.allocPrint(a, "{s}-{s}", .{ @tagName(group.kind), try digest(a, text) });
        try append(a, &units, &names, unit(name, group.path, group.kind, text));
    }
    const entry = try llvm.emitUnit(a, module, options, .{
        .functions = &.{},
        .imports = .{ .functions = entry_imports, .private_functions = entry_private },
        .exported = exported,
        .symbols = symbols,
        .entry = true,
        .source_path = options.source_path,
        .constants = &catalog,
    });
    try units.append(a, unit("entry", options.source_path, .entry, entry));
    return units.toOwnedSlice(a);
}

fn exportImports(module: *const ir.Module, owner: []const ?u32, exported: []bool, selected: []const u32) void {
    for (selected) |imported| {
        exported[imported] = true;
        // Imported bodies may retain a call or stored reference to a private owner.
        for (module.functions.items[imported].insts.items) |inst| {
            const target: usize = switch (inst.op) {
                .call => inst.a.index(),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            if (owner[target] != null) exported[target] = true;
        }
    }
}

fn append(a: std.mem.Allocator, units: *std.ArrayList(Unit), names: *std.StringHashMapUnmanaged(usize), next: Unit) llvm.Error!void {
    const entry = try names.getOrPut(a, next.name);
    if (entry.found_existing) {
        const previous = units.items[entry.value_ptr.*];
        // Equal closed adapters may arise from separate nominal source types.
        // Their callers already share the canonical symbol; emit its body once.
        if (previous.kind != next.kind or !std.mem.eql(u8, previous.llvm, next.llvm)) return error.UnsupportedInstruction;
        return;
    }
    entry.value_ptr.* = units.items.len;
    try units.append(a, next);
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

fn unit(name: []const u8, path: []const u8, kind: Kind, text: []const u8) Unit {
    return .{ .name = name, .source_path = path, .kind = kind, .llvm = text, .number = number_runtime.needed(text), .math = std.mem.indexOf(u8, text, "llvm.sin.f64") != null or std.mem.indexOf(u8, text, "llvm.cos.f64") != null };
}
