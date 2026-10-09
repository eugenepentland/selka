//! Copied property inputs/results lowered through the frozen Core operations.
//! Each checked shape gets a small recursive adapter; batches share the adapters.
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const types = @import("property_types.zig");
const v = @import("property_value.zig");
const Builder = tools.Builder;
/// Allocation or an unsupported checked generation shape.
pub const Error = error{ OutOfMemory, UnsupportedTestType };
const Request = struct { name: []const u8, ty: ir.Type, index: u32, encode: bool };
const Child = struct { name: []const u8, ty: ir.Type, encode: bool, value: ir.Ref };
const State = struct { request: Request, shape: types.Shape, source: ir.Ref, header: ir.Ref = .none, count: ir.Ref = .none };
const Insertion = struct { dict: ir.Ref, key: ir.Ref, value: ir.Ref, ty: ir.Type };
/// Adapter declarations and work queue for one test executable.
pub const Context = struct {
    arena: std.mem.Allocator,
    module: *ir.Module,
    schema: types.Schema,
    known: std.StringHashMapUnmanaged(u32) = .empty,
    pending: std.ArrayList(Request) = .empty,
    /// Declare an adapter, reserving it before traversing recursive children.
    pub fn adapter(self: *Context, name: []const u8, ty: ir.Type, encode: bool) Error!u32 {
        const key = try std.fmt.allocPrint(self.arena, "{d}:{}:{s}", .{ @backingInt(ty), encode, name });
        if (self.known.get(key)) |index| return index;
        const index: u32 = @intCast(self.module.functions.items.len);
        try self.known.put(self.arena, key, index);
        try self.pending.append(self.arena, .{ .name = name, .ty = ty, .index = index, .encode = encode });
        const kind = if (self.module.kind(ty)) |found| @tagName(found) else @tagName(ty);
        const semantic = try std.fmt.allocPrint(self.arena, "{s}:{s}", .{ kind, name });
        var digest: [16]u8 = undefined;
        std.crypto.hash.Blake3.hash(semantic, &digest, .{});
        const symbol = try std.fmt.allocPrint(self.arena, "__test_{s}_{s}", .{ if (encode) "encode" else "decode", std.fmt.bytesToHex(digest, .lower) });
        try self.module.functions.append(self.arena, .{ .name = symbol, .signature = .{
            .params = if (encode) try self.arena.dupe(ir.Type, &.{ty}) else &.{},
            .ret = if (encode) .void else ty,
        } });
        return index;
    }
    /// Build all adapters, including children declared while processing parents.
    pub fn finish(self: *Context) Error!void {
        var cursor: usize = 0;
        while (cursor < self.pending.items.len) : (cursor += 1) {
            const request = self.pending.items[cursor];
            var b: Builder = .{ .arena = self.arena, .function = self.module.functions.items[request.index] };
            var at = try b.block();
            const value = if (request.encode) try b.detached(.{ .op = .param, .ty = request.ty }) else .none;
            const result = try self.transfer(&b, &at, request, value);
            if (!request.encode) try self.validate(&b, at, request.name, result);
            _ = try b.put(at, .{ .op = .ret, .ty = .void, .a = if (request.encode) .none else result });
            self.module.functions.items[request.index] = b.function;
        }
        self.known.deinit(self.arena);
        self.pending.deinit(self.arena);
    }
    fn runtime(self: *Context, b: *Builder, at: ir.BlockId, name: []const u8, ret: ir.Type, args: []const ir.Ref) Error!ir.Ref {
        const params = try self.arena.alloc(ir.Type, args.len);
        for (params, args) |*ty, ref| ty.* = b.function.inst(ref).ty;
        return b.call(at, self.module, try tools.helper(self.arena, self.module, name, params, ret), args);
    }
    fn read(self: *Context, b: *Builder, at: ir.BlockId) Error!ir.Ref {
        return self.runtime(b, at, "myl_core_test_read", .u64, &.{});
    }
    fn write(self: *Context, b: *Builder, at: ir.BlockId, word: ir.Ref) Error!void {
        const widened = if (b.function.inst(word).ty == .u64) word else try b.put(at, .{ .op = .convert, .ty = .u64, .a = word });
        _ = try self.runtime(b, at, "myl_core_test_write", .void, &.{widened});
    }
    fn child(self: *Context, b: *Builder, at: ir.BlockId, input: Child) Error!ir.Ref {
        if (input.ty == .void) return .none;
        const index = try self.adapter(input.name, input.ty, input.encode);
        return b.call(at, self.module, index, if (input.encode) &.{input.value} else &.{});
    }
    fn transfer(self: *Context, b: *Builder, at: *ir.BlockId, request: Request, source: ir.Ref) Error!ir.Ref {
        const ty = request.ty;
        if (self.module.kind(ty) == .box) {
            const inner = self.module.compound(ty).box;
            const value_ref = if (request.encode) try b.put(at.*, .{ .op = .box_get, .ty = inner, .a = source }) else .none;
            const child_ref = try self.child(b, at.*, .{ .name = request.name, .ty = inner, .encode = request.encode, .value = value_ref });
            return if (request.encode) .none else b.put(at.*, .{ .op = .box_make, .ty = ty, .a = child_ref });
        }
        const shape = try self.schema.shape(request.name);
        if (ty == .bool) {
            if (request.encode) {
                _ = try self.runtime(b, at.*, "myl_core_test_write_bool", .void, &.{source});
                return .none;
            }
            return self.runtime(b, at.*, "myl_core_test_read_bool", .bool, &.{});
        }
        if (ty.integer() != null) {
            if (request.encode) {
                try self.write(b, at.*, source);
                try self.write(b, at.*, try b.constant(.u64, 0));
                return .none;
            }
            const bits = try self.read(b, at.*);
            _ = try self.read(b, at.*);
            return b.put(at.*, .{ .op = .convert, .ty = ty, .a = bits });
        }
        if (ty == .f64) {
            if (request.encode) {
                _ = try self.runtime(b, at.*, "myl_core_test_write_float", .void, &.{source});
                return .none;
            }
            return self.runtime(b, at.*, "myl_core_test_read_float", .f64, &.{});
        }
        if (ty == .str or ty == .bytes or ty == .byte_buffer) {
            // A `byte_buffer` crosses the boundary as `bytes`: the blocks share one layout.
            const kind = try b.constant(.u32, @intFromBool(ty != .str));
            if (request.encode) {
                _ = try self.runtime(b, at.*, "myl_core_test_write_text", .void, &.{ source, kind });
                return .none;
            }
            if (ty == .str) return self.runtime(b, at.*, "myl_core_test_read_text", ty, &.{});
            const octets = try self.runtime(b, at.*, "myl_core_test_read_bytes", .bytes, &.{});
            if (ty == .bytes) return octets;
            return self.runtime(b, at.*, "myl_core_buffer_from_bytes", .byte_buffer, &.{octets});
        }
        if (!ty.isCompound()) return error.UnsupportedTestType;
        const header = if (request.encode) .none else try self.read(b, at.*);
        const count = if (request.encode) .none else try self.read(b, at.*);
        const state: State = .{ .request = request, .shape = shape, .source = source, .header = header, .count = count };
        return switch (self.module.compound(ty)) {
            .record => self.record(b, at, state),
            .array => self.fixedArray(b, at, state),
            .@"union" => self.variant(b, at, state),
            .list, .dict => self.collection(b, at, state),
            else => error.UnsupportedTestType,
        };
    }

    fn record(self: *Context, b: *Builder, at: *ir.BlockId, state: State) Error!ir.Ref {
        const request = state.request;
        const shape = state.shape;
        const source = state.source;
        const fields = self.module.compound(request.ty).record;
        if (shape != .record) return error.UnsupportedTestType;
        if (request.encode) {
            try self.write(b, at.*, try b.constant(.u64, 0));
            try self.write(b, at.*, try b.constant(.u64, @intCast(fields.len)));
        }
        const refs = try self.arena.alloc(ir.Ref, fields.len);
        for (fields, refs, 0..) |ty, *ref, index| {
            const field = if (request.encode) try b.put(at.*, .{ .op = .record_get, .ty = ty, .a = source, .data = index }) else .none;
            ref.* = try self.child(b, at.*, .{ .name = shape.record[index].type, .ty = ty, .encode = request.encode, .value = field });
        }
        return if (request.encode) .none else b.put(at.*, .{ .op = .record_make, .ty = request.ty, .data = try b.extra(refs) });
    }
    fn fixedArray(self: *Context, b: *Builder, at: *ir.BlockId, state: State) Error!ir.Ref {
        const request = state.request;
        const shape = state.shape;
        const source = state.source;
        const array_type = self.module.compound(request.ty).array;
        const name = if (shape == .sequence) shape.sequence.element else shape.keyed.value;
        if (request.encode) {
            try self.write(b, at.*, try b.constant(.u64, 0));
            try self.write(b, at.*, try b.constant(.u64, array_type.n));
        }
        const refs = try self.arena.alloc(ir.Ref, array_type.n);
        for (refs, 0..) |*ref, index| {
            const field = if (request.encode) try b.put(at.*, .{ .op = .array_get, .ty = array_type.elem, .a = source, .b = try b.constant(.u64, @intCast(index)), .check = .exact }) else .none;
            ref.* = try self.child(b, at.*, .{ .name = name, .ty = array_type.elem, .encode = request.encode, .value = field });
        }
        return if (request.encode) .none else b.put(at.*, .{ .op = .record_make, .ty = request.ty, .data = try b.extra(refs) });
    }
    fn variant(self: *Context, b: *Builder, at: *ir.BlockId, state: State) Error!ir.Ref {
        const request = state.request;
        const source = state.source;
        const header = state.header;
        const cases = state.shape.cases.cases;
        const payloads = self.module.compound(request.ty).@"union";
        const tag = if (request.encode) try b.put(at.*, .{ .op = .union_tag, .ty = .u32, .a = source }) else header;
        const join = try b.block();
        const refs = try self.arena.alloc(ir.Ref, payloads.len);
        for (payloads, refs, 0..) |payload, *ref, index| {
            const hit = try b.block();
            const next = try b.block();
            const is = try b.put(at.*, .{ .op = .cmp, .ty = .bool, .a = tag, .b = try b.constant(b.function.inst(tag).ty, @intCast(index)), .data = @backingInt(ir.Predicate.eq) });
            try b.branch(at.*, is, hit, next);
            if (request.encode) {
                try self.write(b, hit, tag);
                try self.write(b, hit, try b.constant(.u64, @intFromBool(payload != .void)));
            }
            const value_ref = if (request.encode and payload != .void) try b.put(hit, .{ .op = .union_payload, .ty = payload, .a = source, .data = index }) else .none;
            const decoded = try self.child(b, hit, .{ .name = v.text(v.get(cases[index], "payload")), .ty = payload, .encode = request.encode, .value = value_ref });
            ref.* = if (request.encode) .none else try b.put(hit, .{ .op = .union_make, .ty = request.ty, .a = decoded, .data = index });
            try b.jump(hit, join);
            at.* = next;
        }
        _ = try b.put(at.*, .{ .op = .@"unreachable", .ty = .void });
        at.* = join;
        return if (request.encode) .none else b.put(join, .{ .op = .phi, .ty = request.ty, .data = try b.extra(refs) });
    }
    fn collection(self: *Context, b: *Builder, at: *ir.BlockId, state: State) Error!ir.Ref {
        const request = state.request;
        const shape = state.shape;
        const source = state.source;
        const decoded_count = state.count;
        const element = if (self.module.kind(request.ty) == .dict) self.module.compound(request.ty).dict.key else self.module.compound(request.ty).list;
        const dict = self.module.kind(request.ty) == .dict;
        const count = if (request.encode) try b.put(at.*, .{ .op = if (dict) .dict_len else .list_len, .ty = .u64, .a = source }) else decoded_count;
        if (request.encode) {
            try self.write(b, at.*, try b.constant(.u64, 0));
            try self.write(b, at.*, count);
        }
        const first = at.*;
        const initial = if (request.encode) source else try b.put(first, .{ .op = if (dict) .dict_new else .list_new, .ty = request.ty, .a = count });
        const loop = try b.block();
        const body = try b.block();
        const done = try b.block();
        try b.jump(first, loop);
        const index = try b.put(loop, .{ .op = .phi, .ty = .u64 });
        const list = try b.put(loop, .{ .op = .phi, .ty = request.ty });
        const more = try b.put(loop, .{ .op = .cmp, .ty = .bool, .a = index, .b = count, .data = @backingInt(ir.Predicate.lt) });
        try b.branch(loop, more, body, done);
        var tail = body;
        const name = if (shape == .sequence) shape.sequence.element else shape.keyed.key;
        const entry_index = if (dict and request.encode) try self.runtime(b, tail, "myl_core_dict_ordinal", .i64, &.{ list, index }) else index;
        const value_ref = if (request.encode) try b.put(tail, .{ .op = if (dict) .dict_entry_key else .list_get, .ty = element, .a = list, .b = entry_index, .check = if (dict) .none else .exact }) else .none;
        const decoded = try self.child(b, tail, .{ .name = name, .ty = element, .encode = request.encode, .value = value_ref });
        var updated = list;
        if (dict) {
            const val_ty = self.module.compound(request.ty).dict.value;
            const val_ref = if (request.encode and val_ty != .void) try b.put(tail, .{ .op = .dict_entry_value, .ty = val_ty, .a = list, .b = entry_index }) else .none;
            const val_name = if (shape == .keyed) shape.keyed.value else "unit";
            const val = try self.child(b, tail, .{ .name = val_name, .ty = val_ty, .encode = request.encode, .value = val_ref });
            if (!request.encode) updated = try self.insert(b, &tail, .{ .dict = list, .key = decoded, .value = val, .ty = request.ty });
        } else if (!request.encode) updated = try b.put(tail, .{ .op = .list_push, .ty = request.ty, .a = list, .b = decoded });
        const next = try b.put(tail, .{ .op = .add, .ty = .u64, .a = index, .b = try b.constant(.u64, 1) });
        try b.jump(tail, loop);
        const zero = try b.constant(.u64, 0);
        const index_operands = try b.extra(&.{ zero, next });
        const list_operands = try b.extra(&.{ initial, updated });
        b.function.insts.items[index.index()].data = index_operands;
        b.function.insts.items[list.index()].data = list_operands;
        at.* = done;
        return if (request.encode) .none else list;
    }
    fn insert(self: *Context, b: *Builder, at: *ir.BlockId, input: Insertion) Error!ir.Ref {
        _ = self;
        const dict = input.dict;
        const key = input.key;
        const value_ref = input.value;
        const ty = input.ty;
        const stored_value = if (value_ref == .none) try b.put(at.*, .{ .op = .undef, .ty = .void }) else value_ref;
        const probe = try b.put(at.*, .{ .op = .dict_find, .ty = .i64, .a = dict, .b = key });
        const found = try b.block();
        const missing = try b.block();
        const join = try b.block();
        const present = try b.put(at.*, .{ .op = .cmp, .ty = .bool, .a = probe, .b = try b.constant(.i64, 0), .data = @backingInt(ir.Predicate.ge) });
        try b.branch(at.*, present, found, missing);
        const changed = if (value_ref == .none) dict else try b.put(found, .{ .op = .dict_set_value, .ty = ty, .a = dict, .b = probe, .data = try b.extra(&.{value_ref}) });
        try b.jump(found, join);
        const inserted = try b.put(missing, .{ .op = .dict_insert, .ty = ty, .a = dict, .b = probe, .data = try b.extra(&.{ key, stored_value }) });
        try b.jump(missing, join);
        at.* = join;
        return b.put(join, .{ .op = .phi, .ty = ty, .data = try b.extra(&.{ changed, inserted }) });
    }
    fn validate(self: *Context, b: *Builder, at: ir.BlockId, name: []const u8, value_ref: ir.Ref) Error!void {
        const expected = try std.fmt.allocPrint(self.arena, "@invariant:{s}", .{name});
        for (self.module.functions.items, 0..) |f, index| if (std.mem.eql(u8, f.name, expected) and f.signature.params.len == 1 and f.signature.params[0] == b.function.inst(value_ref).ty) {
            _ = try b.call(at, self.module, @intCast(index), &.{value_ref});
            return;
        };
    }
};

// spec-case: PROPERTY-TEST-6
test "an adapter for a builtin type the boundary cannot carry is refused instead of indexing compounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, "[{\"name\":\"handle\",\"kind\":\"resource\",\"opaque\":true}]", .{});
    var module: ir.Module = .{};
    var context: Context = .{ .arena = a, .module = &module, .schema = try types.Schema.init(a, parsed.array.items) };
    _ = try context.adapter("handle", .resource, false);
    try std.testing.expectError(error.UnsupportedTestType, context.finish());
}
