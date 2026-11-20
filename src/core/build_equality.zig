//! Exact compiler declarations for synchronous structural equality of borrowed values.
const std = @import("std");
const ir = @import("ir.zig");

/// Exact compiler-only borrowed equality symbol prefix.
pub const prefix = "myl_core_borrow_equal_v1_";
/// An invalid physical contract is refused before emission.
pub const Error = error{UnsupportedInstruction};

/// A source extern or malformed reserved name never grants compiler authority. The name holds the key of the compared type
/// and no position; the type itself is the signature's.
pub fn declaration(module: *const ir.Module, function: *const ir.Function) Error!bool {
    if (!std.mem.startsWith(u8, function.name, prefix)) return false;
    if (!@import("stable_names.zig").isKeyList(function.name[prefix.len..], 1)) return error.UnsupportedInstruction;
    const signature = function.signature;
    if (signature.params.len != 2) return error.UnsupportedInstruction;
    const ty = signature.params[0];
    if (!ty.isCompound() or !module.valid(ty)) return error.UnsupportedInstruction;
    if (module.kind(ty) == .@"fn") return error.UnsupportedInstruction;
    if (signature.linkage != .runtime_c) return error.UnsupportedInstruction;
    if (signature.ret != .bool) return error.UnsupportedInstruction;
    if (!std.mem.eql(ir.Type, signature.params, &.{ ty, ty })) return error.UnsupportedInstruction;
    if (signature.passing.hasOwned() or signature.passing.hasConsumes() or signature.passing.hasViews()) return error.UnsupportedInstruction;
    if (function.span != 0) return error.UnsupportedInstruction;
    if (function.blocks.items.len != 0 or function.insts.items.len != 0) return error.UnsupportedInstruction;
    if (function.extra.items.len != 0 or function.loops.items.len != 0) return error.UnsupportedInstruction;
    return true;
}

/// The ordinary physical descriptor catalog. Transient spans and every type
/// containing one are excluded; pointer-identity callbacks do not expose their
/// signatures. Child-to-parent propagation closes recursive graphs in linear work.
pub fn descriptorTypes(a: std.mem.Allocator, module: *const ir.Module) (std.mem.Allocator.Error || Error)![]const bool {
    const supported = try a.alloc(bool, module.compounds.items.len);
    errdefer a.free(supported);
    @memset(supported, true);
    const parents = try a.alloc(std.ArrayList(usize), supported.len);
    defer a.free(parents);
    @memset(parents, .empty);
    defer for (parents) |*list| list.deinit(a);
    const catalog: DescriptorCatalog = .{ .supported = supported, .parents = parents };
    for (module.compounds.items, 0..) |shape, index| switch (shape) {
        .record, .@"union" => |fields| for (fields) |field| try catalog.child(a, module, index, field),
        .box, .list, .borrowed => |child| try catalog.child(a, module, index, child),
        .array => |array| try catalog.child(a, module, index, array.elem),
        .dict => |dict| {
            try catalog.child(a, module, index, dict.key);
            try catalog.child(a, module, index, dict.value);
        },
        .list_view => supported[index] = false,
        .@"fn" => {},
    };
    var pending: std.ArrayList(usize) = .empty;
    defer pending.deinit(a);
    for (supported, 0..) |ordinary, index| if (!ordinary) try pending.append(a, index);
    while (pending.pop()) |index| for (parents[index].items) |parent| {
        if (!supported[parent]) continue;
        supported[parent] = false;
        try pending.append(a, parent);
    };
    return supported;
}

const DescriptorCatalog = struct {
    supported: []bool,
    parents: []std.ArrayList(usize),

    fn child(self: DescriptorCatalog, a: std.mem.Allocator, module: *const ir.Module, parent: usize, ty: ir.Type) (std.mem.Allocator.Error || Error)!void {
        if (!module.valid(ty)) return error.UnsupportedInstruction;
        if (module.isView(ty)) {
            self.supported[parent] = false;
        } else if (ty.isCompound()) {
            try self.parents[@backingInt(ty) - ir.Type.first_compound].append(a, parent);
        }
    }
};

/// Refuse an actual equality root that requires an unsupported transient
/// descriptor, while unrelated borrowed result wrappers stay outside the catalog.
pub fn validateModule(a: std.mem.Allocator, module: *const ir.Module) (std.mem.Allocator.Error || Error)!void {
    var roots: std.ArrayList(ir.Type) = .empty;
    defer roots.deinit(a);
    for (module.functions.items) |*function| if (try declaration(module, function)) {
        try roots.append(a, function.signature.params[0]);
    };
    if (roots.items.len == 0) return;
    const ordinary = try descriptorTypes(a, module);
    defer a.free(ordinary);
    for (roots.items) |ty| {
        if (!ordinary[@backingInt(ty) - ir.Type.first_compound]) return error.UnsupportedInstruction;
    }
    try validateLayouts(a, module, ordinary);
}

const Layout = struct { ty: ir.Type, leave: bool = false };
const Size = struct { bytes: u64, alignment: u64 };
const maximum_size = std.math.maxInt(u32) - 7;

fn sizeOf(module: *const ir.Module, sizes: []const Size, ty: ir.Type) Size {
    if (ty.isCompound()) return sizes[@backingInt(ty) - ir.Type.first_compound];
    const bytes = module.size(ty);
    return .{ .bytes = bytes, .alignment = @max(1, bytes) };
}

fn completedSize(module: *const ir.Module, sizes: []const Size, ty: ir.Type) Error!Size {
    var result: Size = .{ .bytes = 8, .alignment = 8 };
    switch (module.compound(ty)) {
        .borrowed => |child| result = sizeOf(module, sizes, child),
        .array => |shape| {
            const child = sizeOf(module, sizes, shape.elem);
            result = .{ .bytes = child.bytes * @as(u64, shape.n), .alignment = child.alignment };
        },
        .record => |fields| {
            result = .{ .bytes = 0, .alignment = 1 };
            for (fields) |field| {
                const child = sizeOf(module, sizes, field);
                result.bytes = std.mem.alignForward(u64, result.bytes, @intCast(child.alignment)) + child.bytes;
                result.alignment = @max(result.alignment, child.alignment);
                if (result.bytes > maximum_size) return error.UnsupportedInstruction;
            }
            result.bytes = std.mem.alignForward(u64, result.bytes, @intCast(result.alignment));
        },
        .@"union" => |cases| {
            const niche = cases.len == 2 and (cases[0] == .void) != (cases[1] == .void) and module.isBlock(if (cases[0] == .void) cases[1] else cases[0]);
            if (!niche) for (cases) |child| {
                result.bytes = @max(result.bytes, 8 + std.mem.alignForward(u64, sizeOf(module, sizes, child).bytes, 8));
            };
        },
        .box, .list, .dict, .@"fn", .list_view => {},
    }
    if (result.bytes > maximum_size) return error.UnsupportedInstruction;
    return result;
}

fn validateLayouts(a: std.mem.Allocator, module: *const ir.Module, reachable: []const bool) (std.mem.Allocator.Error || Error)!void {
    const state = try a.alloc(u8, reachable.len);
    defer a.free(state);
    @memset(state, 0);
    const sizes = try a.alloc(Size, reachable.len);
    defer a.free(sizes);
    var pending: std.ArrayList(Layout) = .empty;
    defer pending.deinit(a);
    for (reachable, 0..) |used, index| {
        if (!used or state[index] == 2) continue;
        try pending.append(a, .{ .ty = @fromBackingInt(@as(u32, @intCast(index)) + ir.Type.first_compound) });
        while (pending.pop()) |item| {
            if (!item.ty.isCompound()) continue;
            const slot = @backingInt(item.ty) - ir.Type.first_compound;
            if (item.leave) {
                sizes[slot] = try completedSize(module, sizes, item.ty);
                state[slot] = 2;
                continue;
            }
            if (state[slot] == 2) continue;
            if (state[slot] == 1) return error.UnsupportedInstruction;
            state[slot] = 1;
            try pending.append(a, .{ .ty = item.ty, .leave = true });
            switch (module.compound(item.ty)) {
                .record, .@"union" => |fields| for (fields) |field| {
                    try pending.append(a, .{ .ty = field });
                },
                .array => |shape| try pending.append(a, .{ .ty = shape.elem }),
                .borrowed => |child| try pending.append(a, .{ .ty = child }),
                .box, .list, .dict, .@"fn", .list_view => {},
            }
        }
    }
}

/// Compiler-only equality declarations cannot escape as callable function values.
pub fn reference(module: *const ir.Module, inst: ir.Inst) Error!void {
    if (inst.op != .func_ref) return;
    if (inst.data >= module.functions.items.len) return error.UnsupportedInstruction;
    if (try declaration(module, &module.functions.items[@intCast(inst.data)])) return error.UnsupportedInstruction;
}

/// Validate argument bounds before general SSA verification or special emission.
pub fn call(module: *const ir.Module, function: *const ir.Function, inst: ir.Inst) Error!bool {
    if (inst.op != .call) return false;
    if (inst.a == .none or inst.a.index() >= module.functions.items.len) return error.UnsupportedInstruction;
    const callee = &module.functions.items[inst.a.index()];
    if (!try declaration(module, callee)) return false;
    if (inst.ty != .bool) return error.UnsupportedInstruction;
    const range = ir.ExtraSlice.unpack(inst.data);
    if (range.start > function.extra.items.len or range.len != 2 or range.len > function.extra.items.len - range.start) return error.UnsupportedInstruction;
    for (function.extra.items[range.start..][0..range.len]) |raw| {
        const value = try @import("borrow_selection.zig").resolve(function, raw);
        if (function.inst(value).ty != callee.signature.params[0]) return error.UnsupportedInstruction;
    }
    return true;
}

/// Declare the complete borrowed contract directly; symbol-only helper allowlists do not apply.
pub fn equal(comptime Context: type, b: Context, left: ir.Ref, right: ir.Ref, span: u32) error{ OutOfMemory, Unsupported }!ir.Ref {
    const ty = b.typeOfRef(left);
    if (b.typeOfRef(right) != ty) return b.mb.refuse("structural equality operand type", span);
    const symbol = try b.mb.helperName(prefix, &.{ty});
    const callee: u32 = find: {
        for (b.module().functions.items, 0..) |*function, index| {
            if (!std.mem.eql(u8, function.name, symbol)) continue;
            _ = declaration(b.module(), function) catch return b.mb.refuse("invalid structural equality declaration", span);
            break :find @intCast(index);
        }
        const function: ir.Function = .{ .name = symbol, .signature = .{ .params = try b.allocator().dupe(ir.Type, &.{ ty, ty }), .ret = .bool, .linkage = .runtime_c } };
        _ = declaration(b.module(), &function) catch return b.mb.refuse("structural equality type", span);
        const index: u32 = @intCast(b.module().functions.items.len);
        try b.module().functions.append(b.allocator(), function);
        break :find index;
    };
    try b.mb.touch(callee);
    return b.emit(.{ .op = .call, .ty = .bool, .a = @fromBackingInt(callee), .data = try b.extraSlice(&.{ left, right }), .span = span });
}

/// Canonical stack images borrow all descendants until the synchronous comparison returns.
pub fn runtimeCall(comptime Context: type, comptime Output: type, context: Context, out: Output, name: []const u8, inst: ir.Inst) (std.mem.Allocator.Error || Error || error{UnsupportedEntry})!bool {
    if (!try call(context.state.module, context.function, inst)) return false;
    const module = context.state.module;
    const physical_type = module.functions.items[inst.a.index()].signature.params[0];
    const operands = context.function.operands(inst.data);
    const left = try context.stackSlot(module.size(physical_type));
    const right = try context.stackSlot(module.size(physical_type));
    try context.storeOperand(out, physical_type, operands[0], left);
    try context.storeOperand(out, physical_type, operands[1], right);
    try out.print(context.a(), "  {s} = call zeroext i1 @myl_core_values_equal(ptr @myl.value.{s}, ptr {s}, ptr {s})\n", .{ name, context.state.local.ids.text(physical_type), left, right });
    return true;
}
