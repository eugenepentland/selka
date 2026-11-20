//! The function value of a view-ABI function (`build.zig` `declare`).
//!
//! An internal function reads a plain `str` parameter as a borrowed `str_view`, but a function
//! value has the callable type's owned `str` parameters, and `func_ref` and `call_indirect` must
//! agree on one signature. A function value of such a function is therefore a generated adapter:
//! it takes the owned `str` arguments and lends each one to the callee as a view (`str_len` and
//! `str_view_of`, which copy nothing). The adapter is an ordinary internal function, so the
//! lowering cache keeps it with the body that refers to it.
const std = @import("std");
const ir = @import("ir.zig");

/// The index of the function a function value of `index` refers to: `index` itself when its parameters
/// are the callable type's `expected` (a plain `str` is a view with its owner, the same form on both sides),
/// otherwise the adapter (declared on first use). Null when the callee returns a view, which a function value
/// cannot carry.
pub fn valueIndex(allocator: std.mem.Allocator, module: *ir.Module, index: u32, expected: []const ir.Type) std.mem.Allocator.Error!?u32 {
    const callee = module.functions.items[index];
    if (callee.signature.linkage != .internal or std.mem.eql(ir.Type, callee.signature.params, expected)) return index;
    if (callee.signature.ret == .str_view) return null;
    const name = try std.fmt.allocPrint(allocator, "{s}#value", .{callee.name});
    for (module.functions.items, 0..) |existing, at| {
        if (std.mem.eql(u8, existing.name, name)) return @intCast(at);
    }
    // The callee's passed parameters come first, then one owner per borrowed `str` (C9 S1): the adapter takes
    // the passed parameters as owned `str`, lends each one to the callee as its span, and passes it as its owner.
    const passed = callee.signature.params.len - viewCount(module, callee.signature.params);
    const params = try allocator.dupe(ir.Type, callee.signature.params[0..passed]);
    for (params) |*param| param.* = try ownedOf(allocator, module, param.*);
    var signature = callee.signature;
    signature.params = params;
    var f: ir.Function = .{ .name = name, .signature = signature, .span = callee.span };
    try f.blocks.append(allocator, .{});
    var args: std.ArrayList(ir.Ref) = .empty;
    defer args.deinit(allocator);
    var owners: std.ArrayList(ir.Ref) = .empty;
    defer owners.deinit(allocator);
    for (params, callee.signature.params[0..passed], 0..) |ty, wanted, position| {
        const param = try emit(allocator, &f, .{ .op = .param, .ty = ty, .data = position });
        // A list view lends the owned list's elements (C9 lists): no copy, and the owned list is its owner.
        if (module.kind(wanted) == .list_view) {
            try args.append(allocator, try emit(allocator, &f, .{ .op = .list_view_of, .ty = wanted, .a = param, .span = callee.span }));
            try owners.append(allocator, param);
            continue;
        }
        if (!wanted.isSpan()) {
            try args.append(allocator, param);
            continue;
        }
        // A bytes parameter's view has no owner (C9 bytes): its octets are the whole argument.
        const len = try emit(allocator, &f, .{ .op = if (ty == .bytes) .list_len else .str_len, .ty = .u64, .a = param, .span = callee.span });
        const zero = try emit(allocator, &f, .{ .op = .iconst, .ty = .u64, .data = 0 });
        const start: u32 = @intCast(f.extra.items.len);
        try f.extra.append(allocator, len);
        const view = try emit(allocator, &f, .{
            .op = .str_view_of,
            .ty = wanted,
            .a = param,
            .b = zero,
            .data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack(),
            .span = callee.span,
        });
        try args.append(allocator, view);
        if (wanted == .str_view) try owners.append(allocator, param);
    }
    try args.appendSlice(allocator, owners.items);
    const start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(allocator, args.items);
    const result = try emit(allocator, &f, .{
        .op = .call,
        .ty = callee.signature.ret,
        .a = @fromBackingInt(index),
        .data = (ir.ExtraSlice{ .start = start, .len = @intCast(args.items.len) }).pack(),
        .span = callee.span,
    });
    _ = try emit(allocator, &f, .{ .op = .ret, .ty = .void, .a = if (callee.signature.ret == .void) .none else result, .span = callee.span });
    const adapter: u32 = @intCast(module.functions.items.len);
    try module.functions.append(allocator, f);
    return adapter;
}

/// The owned form of parameter type `ty` the adapter takes: a text or bytes view is its owned value, and a list view is
/// the owned list of its elements. Any other type is unchanged.
fn ownedOf(allocator: std.mem.Allocator, module: *ir.Module, ty: ir.Type) std.mem.Allocator.Error!ir.Type {
    if (ty == .str_view) return .str;
    if (ty == .bytes_view) return .bytes;
    if (module.kind(ty) != .list_view) return ty;
    return module.intern(allocator, .{ .list = module.compound(ty).list_view });
}

/// Whether any parameter is a borrowed view.
fn takesView(module: *const ir.Module, params: []const ir.Type) bool {
    return viewCount(module, params) != 0;
}

/// How many parameters are borrowed views: each has one trailing owner parameter (C9 S1).
fn viewCount(module: *const ir.Module, params: []const ir.Type) usize {
    var count: usize = 0;
    for (params) |param| count += @intFromBool(param == .str_view or module.kind(param) == .list_view);
    return count;
}

/// Append `inst` to `f`'s entry block (parameters and constants stay out of the block, as
/// `Writer` in `build_parallel.zig` does) and return its reference.
fn emit(allocator: std.mem.Allocator, f: *ir.Function, inst: ir.Inst) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(f.insts.items.len)));
    try f.insts.append(allocator, inst);
    if (inst.op != .param and inst.op != .iconst) try f.blocks.items[0].insts.append(allocator, ref);
    return ref;
}
