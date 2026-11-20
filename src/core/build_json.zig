//! `json.encode[T]` and `json.decode[T]` (decisions CODEC-1 and CODEC-2, step 1): the derived plain JSON form of a type.
//!
//! `@stdlib/json.selka` declares both as generic `builtin func`s; the checker instantiates them for each concrete `T` as
//! ordinary calls (`codec_form.zig` says which types have a form), and this builder writes each instance's body: one
//! adapter per type the value holds, made once for the instance and shared by every place that type appears in it, as
//! `property_ir.zig` does for the test runner's copied inputs. The adapters build and read values with the ordinary Core
//! operations (`record_make`, `list_push`, `union_make`, `record_get`, `union_tag`), so ownership and the validator see
//! nothing new; the text work is the runtime's (`runtime/core_json.c`): a one-pass parse of the document into a tape,
//! typed reads that scan an integer's token against its width, a writer, and the first error with its field path.
//!
//! A decoder takes the tape's handle and a node index and answers a value; on an error (or a node of -1, a member that
//! is missing) it answers a placeholder that is dropped, and the instance returns the `json.CodecError` the runtime kept.
//! A missing member with a declared default takes it (the checker's `@default:Record.field` function); a decoded record
//! with `@invariant` is checked by its boundary validator (`@invariant:Record`) before the value returns.
const std = @import("std");
const ir = @import("ir.zig");
const tools = @import("test_builder.zig");
const language = @import("selka");
const typed = language.typed;
const codec_form = language.codec_form;
const Builder = tools.Builder;

/// Allocation and an unsupported declaration are the lowering failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// The two functions this builder writes.
pub const Which = enum { encode, decode };

/// Which derived function `checked` is, or null for every other function.
pub fn matched(source: ?language.source.Source, checked: typed.Function) ?Which {
    const src = source orelse return null;
    if (!checked.policy.builtin) return null;
    if (!std.mem.eql(u8, src.locate(checked.declaration.start).path, "@stdlib/json.selka")) return null;
    return std.meta.stringToEnum(Which, src.text(checked.declaration));
}

/// The prefix of the checker's default functions, `@default:Record.field`.
pub const default_prefix = "@default:";

/// One adapter: the checked type it serves and whether it writes or reads.
const Key = struct { ty: typed.Type, encode: bool };

/// The state of one instance's build: the module builder, the adapters made so far and those still to write.
fn Derivation(comptime Context: type) type {
    return struct {
        const Self = @This();
        mb: Context,
        span: u32,
        made: std.AutoHashMapUnmanaged(Key, u32) = .empty,
        pending: std.ArrayList(Key) = .empty,
        handle: ir.Type = .u64,

        fn allocator(self: *Self) std.mem.Allocator {
            return self.mb.allocator;
        }
        fn records(self: *Self) []const typed.Record {
            return self.mb.input.program.records;
        }

        /// The adapter of `key`, declared on first use and written by `finish`.
        fn adapter(self: *Self, key: Key) Error!u32 {
            if (self.made.get(key)) |index| return index;
            const physical = try self.mb.mapType(key.ty, self.span);
            const name = try self.mb.generatedName(.json_codec, if (key.encode) "json.encode" else "json.decode");
            const params = if (key.encode) try self.allocator().dupe(ir.Type, &.{ .u64, physical }) else try self.allocator().dupe(ir.Type, &.{ .u64, .i64 });
            const index: u32 = @intCast(self.mb.module.functions.items.len);
            try self.mb.module.functions.append(self.allocator(), .{ .name = name, .signature = .{ .params = params, .ret = if (key.encode) .void else physical }, .span = self.span });
            try self.made.put(self.allocator(), key, index);
            try self.pending.append(self.allocator(), key);
            return index;
        }

        /// Write every adapter declared, including those declared while writing others.
        fn finish(self: *Self) Error!void {
            var cursor: usize = 0;
            while (cursor < self.pending.items.len) : (cursor += 1) {
                const key = self.pending.items[cursor];
                const index = self.made.get(key).?;
                var b: Builder = .{ .arena = self.allocator(), .function = self.mb.module.functions.items[index] };
                b.function.insts = .empty;
                b.function.blocks = .empty;
                b.function.extra = .empty;
                b.function.loops = .empty;
                var at = try b.block();
                const handle = try b.detached(.{ .op = .param, .ty = .u64, .data = 0, .span = self.span });
                const physical = b.function.signature.params[1];
                const subject = try b.detached(.{ .op = .param, .ty = physical, .data = 1, .span = self.span });
                if (key.encode) {
                    try write(Emit(Self), .{ .d = self, .b = &b, .h = handle }, &at, subject, key.ty);
                    _ = try b.put(at, .{ .op = .ret, .ty = .void, .span = self.span });
                } else {
                    const value = try read(Emit(Self), .{ .d = self, .b = &b, .h = handle }, &at, subject, key.ty, b.function.signature.ret);
                    _ = try b.put(at, .{ .op = .ret, .ty = .void, .a = value, .span = self.span });
                }
                self.mb.module.functions.items[index] = b.function;
                try self.mb.touch(index);
            }
        }

        fn runtime(self: *Self, b: *Builder, at: ir.BlockId, name: []const u8, ret: ir.Type, args: []const ir.Ref) Error!ir.Ref {
            const params = try self.allocator().alloc(ir.Type, args.len);
            for (params, args) |*ty, ref| ty.* = b.function.inst(ref).ty;
            const callee = try self.mb.runtimeFunction(name, params, ret, .runtime_c);
            return b.put(at, .{ .op = .call, .ty = ret, .a = @fromBackingInt(callee), .data = try b.extra(args), .span = self.span });
        }
        fn text(self: *Self, b: *Builder, value: []const u8) Error!ir.Ref {
            const index = self.mb.module.strings.items.len;
            try self.mb.module.strings.append(self.allocator(), try self.allocator().dupe(u8, value));
            return b.detached(.{ .op = .str_const, .ty = .str, .data = index, .span = self.span });
        }
        fn int(_: *Self, b: *Builder, ty: ir.Type, value: i64) Error!ir.Ref {
            return b.constant(ty, value);
        }
        fn child(self: *Self, b: *Builder, at: ir.BlockId, key: Key, args: []const ir.Ref) Error!ir.Ref {
            const index = try self.adapter(key);
            return b.call(at, &self.mb.module, index, args);
        }
    };
}

/// One function being written: its derivation `D`, its builder and its runtime handle (the adapter's first parameter).
fn Emit(comptime D: type) type {
    return struct { d: *D, b: *Builder, h: ir.Ref };
}

// ---- writing ----------------------------------------------------------------------------------------------

fn write(comptime E: type, e: E, at: *ir.BlockId, value: ir.Ref, ty: typed.Type) Error!void {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const physical = b.function.inst(value).ty;
    switch (codec_form.kind(ty, self.records())) {
        .integer => {
            const signed = ty.integer().?.signed;
            const wide = if (physical == (if (signed) ir.Type.i64 else ir.Type.u64)) value else try b.put(at.*, .{ .op = .convert, .ty = if (signed) .i64 else .u64, .a = value, .span = self.span });
            _ = try self.runtime(b, at.*, if (signed) "myl_core_json_put_i64" else "myl_core_json_put_u64", .void, &.{ h, wide });
        },
        .boolean => _ = try self.runtime(b, at.*, "myl_core_json_put_bool", .void, &.{ h, value }),
        .float => _ = try self.runtime(b, at.*, if (physical == .f32) "myl_core_json_put_f32" else "myl_core_json_put_f64", .void, &.{ h, value }),
        .text => _ = try self.runtime(b, at.*, "myl_core_json_put_str", .void, &.{ h, value }),
        .record => try writeRecord(E, e, at, value, ty),
        .variants => try writeVariants(E, e, at, value, ty),
        .list => try writeList(E, e, at, value, ty),
        .fixed_array => {
            const array = self.mb.module.compound(physical).array;
            const element = self.records()[ty.recordIndex()].shape.array.?.element;
            _ = try self.runtime(b, at.*, "myl_core_json_begin_array", .void, &.{h});
            for (0..array.n) |i| {
                const item = try b.put(at.*, .{ .op = .array_get, .ty = array.elem, .a = value, .b = try self.int(b, .u64, @intCast(i)), .check = .exact, .span = self.span });
                _ = try self.child(b, at.*, .{ .ty = element, .encode = true }, &.{ h, item });
            }
            _ = try self.runtime(b, at.*, "myl_core_json_end_array", .void, &.{h});
        },
        .none, .later => return self.mb.refuse("json.encode of a type with no plain form", self.span),
    }
}

fn writeRecord(comptime E: type, e: E, at: *ir.BlockId, value: ir.Ref, ty: typed.Type) Error!void {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const record = self.records()[ty.recordIndex()];
    const fields = self.mb.module.compound(b.function.inst(value).ty).record;
    if (fields.len != record.fields.len) return self.mb.refuse("json.encode of a record layout", self.span);
    _ = try self.runtime(b, at.*, "myl_core_json_begin_object", .void, &.{h});
    for (record.fields, fields, 0..) |field, stored, i| {
        _ = try self.runtime(b, at.*, "myl_core_json_put_key", .void, &.{ h, try self.text(b, field.name) });
        const part = try b.put(at.*, .{ .op = .record_get, .ty = stored, .a = value, .data = i, .span = self.span });
        // A list is written in the record's own adapter, so a value nested through lists takes one frame a level.
        if (codec_form.kind(field.ty, self.records()) == .list) {
            try write(E, e, at, part, field.ty);
        } else _ = try self.child(b, at.*, .{ .ty = field.ty, .encode = true }, &.{ h, part });
    }
    _ = try self.runtime(b, at.*, "myl_core_json_end_object", .void, &.{h});
}

fn writeVariants(comptime E: type, e: E, at: *ir.BlockId, value: ir.Ref, ty: typed.Type) Error!void {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const record = self.records()[ty.recordIndex()];
    const cases = record.shape.variants.?.cases;
    const payloads = self.mb.module.compound(b.function.inst(value).ty).@"union";
    const option = typed.surfaceOptionalPayload(record) != null;
    const tag = try b.put(at.*, .{ .op = .union_tag, .ty = .u32, .a = value, .span = self.span });
    const join = try b.block();
    for (cases, payloads, 0..) |case, payload, i| {
        const hit = try b.block();
        const next = try b.block();
        const is = try b.put(at.*, .{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.int(b, .u32, @intCast(i)), .data = @backingInt(ir.Predicate.eq), .span = self.span });
        try b.branch(at.*, is, hit, next);
        const inner = if (case.payload != null and payload != .void) try b.put(hit, .{ .op = .union_payload, .ty = payload, .a = value, .data = i, .span = self.span }) else .none;
        if (option) {
            if (inner == .none) _ = try self.runtime(b, hit, "myl_core_json_put_null", .void, &.{h}) else _ = try self.child(b, hit, .{ .ty = case.payload.?, .encode = true }, &.{ h, inner });
        } else if (inner == .none) {
            _ = try self.runtime(b, hit, "myl_core_json_put_case", .void, &.{ h, try self.text(b, case.name) });
        } else {
            _ = try self.runtime(b, hit, "myl_core_json_begin_object", .void, &.{h});
            _ = try self.runtime(b, hit, "myl_core_json_put_key", .void, &.{ h, try self.text(b, "case") });
            _ = try self.runtime(b, hit, "myl_core_json_put_case", .void, &.{ h, try self.text(b, case.name) });
            _ = try self.runtime(b, hit, "myl_core_json_put_key", .void, &.{ h, try self.text(b, "value") });
            _ = try self.child(b, hit, .{ .ty = case.payload.?, .encode = true }, &.{ h, inner });
            _ = try self.runtime(b, hit, "myl_core_json_end_object", .void, &.{h});
        }
        try b.jump(hit, join);
        at.* = next;
    }
    _ = try b.put(at.*, .{ .op = .@"unreachable", .ty = .void, .span = self.span });
    at.* = join;
}

fn writeList(comptime E: type, e: E, at: *ir.BlockId, value: ir.Ref, ty: typed.Type) Error!void {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const element = self.records()[ty.recordIndex()].shape.buffer.?;
    // The instance's own parameter may be a borrowed list view (C9 lists); its elements are read in place.
    const physical = b.function.inst(value).ty;
    const stored = if (self.mb.module.kind(physical) == .list_view) self.mb.module.compound(physical).list_view else self.mb.module.compound(physical).list;
    _ = try self.runtime(b, at.*, "myl_core_json_begin_array", .void, &.{h});
    const count = try b.put(at.*, .{ .op = .list_len, .ty = .u64, .a = value, .span = self.span });
    const l = try loopCarrying(E, e, at, count, &.{}, &.{});
    const item = try b.put(l.body, .{ .op = .list_get, .ty = stored, .a = value, .b = l.index, .check = .exact, .span = self.span });
    _ = try self.child(b, l.body, .{ .ty = element, .encode = true }, &.{ h, item });
    try closeLoop(E, e, l, l.body, &.{});
    at.* = l.done;
    _ = try self.runtime(b, at.*, "myl_core_json_end_array", .void, &.{h});
}

/// A counted loop: `index` runs from 0 while it is below `count`; `carried` are extra loop values (phis).
const Loop = struct { header: ir.BlockId, body: ir.BlockId, done: ir.BlockId, index: ir.Ref, phis: []ir.Ref, initial: []const ir.Ref };

fn loopCarrying(comptime E: type, e: E, at: *ir.BlockId, count: ir.Ref, types: []const ir.Type, initial: []const ir.Ref) Error!Loop {
    const self = e.d;
    const b = e.b;
    const header = try b.block();
    const body = try b.block();
    const done = try b.block();
    try b.jump(at.*, header);
    const index = try b.put(header, .{ .op = .phi, .ty = .u64, .span = self.span });
    const phis = try self.allocator().alloc(ir.Ref, types.len);
    for (types, phis) |ty, *phi| phi.* = try b.put(header, .{ .op = .phi, .ty = ty, .span = self.span });
    const more = try b.put(header, .{ .op = .cmp, .ty = .bool, .a = index, .b = count, .data = @backingInt(ir.Predicate.lt), .span = self.span });
    try b.branch(header, more, body, done);
    return .{ .header = header, .body = body, .done = done, .index = index, .phis = phis, .initial = try self.allocator().dupe(ir.Ref, initial) };
}
fn closeLoop(comptime E: type, e: E, l: Loop, tail: ir.BlockId, next: []const ir.Ref) Error!void {
    const self = e.d;
    const b = e.b;
    const step = try b.put(tail, .{ .op = .add, .ty = .u64, .a = l.index, .b = try self.int(b, .u64, 1), .span = self.span });
    try b.jump(tail, l.header);
    // `extra` and `int` grow the instruction list, so each operand list is made before the phi is written.
    const zero = try self.int(b, .u64, 0);
    const counted = try b.extra(&.{ zero, step });
    b.function.insts.items[l.index.index()].data = counted;
    for (l.phis, l.initial, next) |phi, first, later| {
        const operands = try b.extra(&.{ first, later });
        b.function.insts.items[phi.index()].data = operands;
    }
    try b.function.loops.append(self.allocator(), .{ .id = b.function.loops.items.len, .header = l.header, .body = l.body, .latch = tail, .exit = l.done });
}

// ---- reading ----------------------------------------------------------------------------------------------

fn read(comptime E: type, e: E, at: *ir.BlockId, node: ir.Ref, ty: typed.Type, physical: ir.Type) Error!ir.Ref {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    switch (codec_form.kind(ty, self.records())) {
        .integer => {
            const info = ty.integer().?;
            if (info.signed) {
                const low = try self.int(b, .i64, @intCast(ty.min()));
                const high = try self.int(b, .i64, @intCast(ty.max()));
                const wide = try self.runtime(b, at.*, "myl_core_json_i64", .i64, &.{ h, node, low, high });
                return if (physical == .i64) wide else b.put(at.*, .{ .op = .convert, .ty = physical, .a = wide, .span = self.span });
            }
            const high = try self.int(b, .u64, @bitCast(@as(u64, @intCast(ty.max()))));
            const wide = try self.runtime(b, at.*, "myl_core_json_u64", .u64, &.{ h, node, high });
            return if (physical == .u64) wide else b.put(at.*, .{ .op = .convert, .ty = physical, .a = wide, .span = self.span });
        },
        .boolean => return self.runtime(b, at.*, "myl_core_json_bool", .bool, &.{ h, node }),
        .float => return self.runtime(b, at.*, if (physical == .f32) "myl_core_json_f32" else "myl_core_json_f64", physical, &.{ h, node }),
        .text => return self.runtime(b, at.*, "myl_core_json_str", .str, &.{ h, node }),
        .record => return readRecord(E, e, at, node, ty, physical),
        .variants => return readVariants(E, e, at, node, ty, physical),
        .list => return readList(E, e, at, node, ty, physical),
        .fixed_array => {
            const array = self.mb.module.compound(physical).array;
            const element = self.records()[ty.recordIndex()].shape.array.?.element;
            _ = try self.runtime(b, at.*, "myl_core_json_array", .u64, &.{ h, node, try self.int(b, .i64, @intCast(array.n)) });
            const items = try self.allocator().alloc(ir.Ref, array.n);
            var previous = try self.int(b, .i64, -1);
            for (items) |*item| {
                const at_child = try self.runtime(b, at.*, "myl_core_json_element", .i64, &.{ h, node, previous });
                item.* = try self.child(b, at.*, .{ .ty = element, .encode = false }, &.{ h, at_child });
                previous = at_child;
            }
            return b.put(at.*, .{ .op = .record_make, .ty = physical, .data = try b.extra(items), .span = self.span });
        },
        .none, .later => return self.mb.refuse("json.decode of a type with no plain form", self.span),
    }
}

fn readRecord(comptime E: type, e: E, at: *ir.BlockId, node: ir.Ref, ty: typed.Type, physical: ir.Type) Error!ir.Ref {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const record = self.records()[ty.recordIndex()];
    const fields = self.mb.module.compound(physical).record;
    if (fields.len != record.fields.len) return self.mb.refuse("json.decode of a record layout", self.span);
    const object = try self.runtime(b, at.*, "myl_core_json_object", .i64, &.{ h, node });
    var names: std.ArrayList(u8) = .empty;
    const values = try self.allocator().alloc(ir.Ref, fields.len);
    for (record.fields, fields, values) |field, stored, *value| {
        try names.appendSlice(self.allocator(), field.name);
        try names.append(self.allocator(), '\n');
        const default = try defaultFunction(E, e, record, field);
        // An option without a declared default reads an absent member as `None` (the design's table).
        const optional = codec_form.kind(field.ty, self.records()) == .variants and typed.surfaceOptionalPayload(self.records()[field.ty.recordIndex()]) != null;
        const required = default == null and !optional;
        const member = try self.runtime(b, at.*, "myl_core_json_member", .i64, &.{ h, object, try self.text(b, field.name), try self.int(b, .bool, @intFromBool(required)) });
        const callee = default orelse {
            value.* = try readField(E, e, at, member, field.ty, stored);
            continue;
        };
        const present = try b.put(at.*, .{ .op = .cmp, .ty = .bool, .a = member, .b = try self.int(b, .i64, 0), .data = @backingInt(ir.Predicate.ge), .span = self.span });
        const given = try b.block();
        const absent = try b.block();
        const join = try b.block();
        try b.branch(at.*, present, given, absent);
        var given_end = given;
        const read_value = try readField(E, e, &given_end, member, field.ty, stored);
        try b.jump(given_end, join);
        const default_value = try b.call(absent, &self.mb.module, callee, &.{});
        try b.jump(absent, join);
        value.* = try b.put(join, .{ .op = .phi, .ty = stored, .data = try b.extra(&.{ read_value, default_value }), .span = self.span });
        at.* = join;
    }
    _ = try self.runtime(b, at.*, "myl_core_json_close", .void, &.{ h, object, try self.text(b, names.items) });
    const made = try b.put(at.*, .{ .op = .record_make, .ty = physical, .data = try b.extra(values), .span = self.span });
    try validate(E, e, at, object, record, made);
    return made;
}

/// One field's value: a list is read in the record's own adapter (one frame a level for a value nested through lists),
/// anything else by its type's adapter.
fn readField(comptime E: type, e: E, at: *ir.BlockId, node: ir.Ref, ty: typed.Type, physical: ir.Type) Error!ir.Ref {
    if (codec_form.kind(ty, e.d.records()) == .list) return read(E, e, at, node, ty, physical);
    const value = try e.d.child(e.b, at.*, .{ .ty = ty, .encode = false }, &.{ e.h, node });
    return value;
}

/// Test a decoded record's `@invariant` with its checker-made test (`@holds:Record`), only when the document had no error
/// (a placeholder is not a value the invariant is about): one that does not hold makes the decode fail with kind
/// `invariant`, at the record's path and the offset of its `{` (CODEC-INV). Nothing traps.
fn validate(comptime E: type, e: E, at: *ir.BlockId, object: ir.Ref, record: typed.Record, value: ir.Ref) Error!void {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const expected = try std.fmt.allocPrint(self.allocator(), "@holds:{s}", .{record.name});
    const program = self.mb.input.program;
    for (program.functions, 0..) |function, id| {
        if (!std.mem.eql(u8, function.name, expected)) continue;
        const index = try self.mb.functionIndex(@fromBackingInt(@as(u32, @intCast(id))));
        const signature = self.mb.module.functions.items[index].signature;
        if (signature.params.len != 1 or signature.params[0] != b.function.inst(value).ty) return self.mb.refuse("json.decode of a record whose invariant takes another layout", self.span);
        const ok = try self.runtime(b, at.*, "myl_core_json_ok", .bool, &.{h});
        const check = try b.block();
        const broken = try b.block();
        const join = try b.block();
        try b.branch(at.*, ok, check, join);
        const answer = try b.call(check, &self.mb.module, index, &.{value});
        const holds = try b.put(check, .{ .op = .cmp, .ty = .bool, .a = answer, .b = try self.int(b, .i64, 0), .data = @backingInt(ir.Predicate.ne), .span = self.span });
        try b.branch(check, holds, join, broken);
        const name = try language.display_name.printed(self.allocator(), record.name);
        _ = try self.runtime(b, broken, "myl_core_json_invariant", .void, &.{ h, object, try self.text(b, name) });
        try b.jump(broken, join);
        at.* = join;
        return;
    }
}

/// The checker's function that builds the declared default of `field`, declared in Core, or null when the field
/// has none (or the checker made none).
fn defaultFunction(comptime E: type, e: E, record: typed.Record, field: typed.Field) Error!?u32 {
    const self = e.d;
    if (field.default_value == null) return null;
    const expected = try std.fmt.allocPrint(self.allocator(), "{s}{s}.{s}", .{ default_prefix, record.name, field.name });
    for (self.mb.input.program.functions, 0..) |function, id| {
        if (!std.mem.eql(u8, function.name, expected)) continue;
        const index = try self.mb.functionIndex(@fromBackingInt(@as(u32, @intCast(id))));
        return index;
    }
    return null;
}

fn readVariants(comptime E: type, e: E, at: *ir.BlockId, node: ir.Ref, ty: typed.Type, physical: ir.Type) Error!ir.Ref {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const record = self.records()[ty.recordIndex()];
    const cases = record.shape.variants.?.cases;
    const payloads = self.mb.module.compound(physical).@"union";
    if (typed.surfaceOptionalPayload(record) != null) {
        var some: usize = 0;
        var none: usize = 0;
        for (cases, 0..) |case, i| {
            if (std.mem.eql(u8, case.name, "some")) some = i else none = i;
        }
        const absent = try self.runtime(b, at.*, "myl_core_json_none", .bool, &.{ h, node });
        const empty = try b.block();
        const given = try b.block();
        const join = try b.block();
        try b.branch(at.*, absent, empty, given);
        const nothing = try b.put(empty, .{ .op = .union_make, .ty = physical, .data = none, .span = self.span });
        try b.jump(empty, join);
        const inner = try self.child(b, given, .{ .ty = cases[some].payload.?, .encode = false }, &.{ h, node });
        const something = try b.put(given, .{ .op = .union_make, .ty = physical, .a = inner, .data = some, .span = self.span });
        try b.jump(given, join);
        at.* = join;
        return b.put(join, .{ .op = .phi, .ty = physical, .data = try b.extra(&.{ nothing, something }), .span = self.span });
    }
    var names: std.ArrayList(u8) = .empty;
    for (cases, payloads) |case, payload| {
        try names.append(self.allocator(), if (case.payload != null and payload != .void) '+' else '-');
        try names.appendSlice(self.allocator(), case.name);
        try names.append(self.allocator(), '\n');
    }
    const index = try self.runtime(b, at.*, "myl_core_json_case", .i64, &.{ h, node, try self.text(b, names.items) });
    const join = try b.block();
    const made = try self.allocator().alloc(ir.Ref, cases.len);
    for (cases, payloads, made, 0..) |case, payload, *value, i| {
        const hit = try b.block();
        const next = try b.block();
        const is = try b.put(at.*, .{ .op = .cmp, .ty = .bool, .a = index, .b = try self.int(b, .i64, @intCast(i)), .data = @backingInt(ir.Predicate.eq), .span = self.span });
        try b.branch(at.*, is, hit, next);
        var inner: ir.Ref = .none;
        if (case.payload != null and payload != .void) {
            const at_value = try self.runtime(b, hit, "myl_core_json_case_value", .i64, &.{ h, node });
            inner = try self.child(b, hit, .{ .ty = case.payload.?, .encode = false }, &.{ h, at_value });
        }
        value.* = try b.put(hit, .{ .op = .union_make, .ty = physical, .a = inner, .data = i, .span = self.span });
        try b.jump(hit, join);
        at.* = next;
    }
    _ = try b.put(at.*, .{ .op = .@"unreachable", .ty = .void, .span = self.span });
    at.* = join;
    return b.put(join, .{ .op = .phi, .ty = physical, .data = try b.extra(made), .span = self.span });
}

fn readList(comptime E: type, e: E, at: *ir.BlockId, node: ir.Ref, ty: typed.Type, physical: ir.Type) Error!ir.Ref {
    const self = e.d;
    const b = e.b;
    const h = e.h;
    const element = self.records()[ty.recordIndex()].shape.buffer.?;
    const count = try self.runtime(b, at.*, "myl_core_json_array", .u64, &.{ h, node, try self.int(b, .i64, -1) });
    const empty = try b.put(at.*, .{ .op = .list_new, .ty = physical, .a = count, .span = self.span });
    const l = try loopCarrying(E, e, at, count, &.{ physical, .i64 }, &.{ empty, try self.int(b, .i64, -1) });
    const list = l.phis[0];
    const previous = l.phis[1];
    const at_child = try self.runtime(b, l.body, "myl_core_json_element", .i64, &.{ h, node, previous });
    const item = try self.child(b, l.body, .{ .ty = element, .encode = false }, &.{ h, at_child });
    const pushed = try b.put(l.body, .{ .op = .list_push, .ty = physical, .a = list, .b = item, .span = self.span });
    try closeLoop(E, e, l, l.body, &.{ pushed, at_child });
    at.* = l.done;
    return list;
}

/// Build one instance's body: parse or start writing, run the type's adapter, and answer the value or the error.
pub fn build(mb: anytype, declared: ir.Function, checked: typed.Function, which: Which) Error!ir.Function {
    const span = declared.span;
    const program = mb.input.program;
    const ret = declared.signature.ret;
    const result_type = checked.signature.return_type;
    const shape = typed.resultShape(result_type, program.records) orelse return mb.refuse("json codec without a fallible result", span);
    if (declared.signature.params.len == 0 or declared.signature.params.len > 2) return mb.refuse("json codec with an unexpected signature", span);
    const subject_type: typed.Type = checked.scope.locals[0].ty;
    const value_type: typed.Type = if (which == .encode) subject_type else shape.ok_type;
    const D = Derivation(@TypeOf(mb));
    var d: D = .{ .mb = mb, .span = span };
    var b: Builder = .{ .arena = mb.allocator, .function = declared };
    var at = try b.block();
    // The value or the source, then the owner of a borrowed view, which the body does not read.
    const input = try b.detached(.{ .op = .param, .ty = declared.signature.params[0], .data = 0, .span = span });
    if (declared.signature.params.len == 2) _ = try b.detached(.{ .op = .param, .ty = declared.signature.params[1], .data = 1, .span = span });
    var h: ir.Ref = undefined;
    var output: ir.Ref = undefined;
    if (which == .decode) {
        h = try d.runtime(&b, at, "myl_core_json_read", .u64, &.{input});
        const root = try d.int(&b, .i64, 0);
        output = try d.child(&b, at, .{ .ty = value_type, .encode = false }, &.{ h, root });
    } else {
        h = try d.runtime(&b, at, "myl_core_json_writer", .u64, &.{});
        // The top level is written in the body, so a borrowed text or list view is read where it was lent.
        try write(Emit(D), .{ .d = &d, .b = &b, .h = h }, &at, input, value_type);
    }
    const ok = try d.runtime(&b, at, "myl_core_json_ok", .bool, &.{h});
    const good = try b.block();
    const bad = try b.block();
    try b.branch(at, ok, good, bad);
    const payloads = mb.module.compound(ret).@"union";
    if (which == .encode) output = try d.runtime(&b, good, "myl_core_json_written", .str, &.{h});
    const success = try b.put(good, .{ .op = .union_make, .ty = ret, .a = output, .data = shape.ok_tag, .span = span });
    _ = try d.runtime(&b, good, "myl_core_json_done", .void, &.{h});
    _ = try b.put(good, .{ .op = .ret, .ty = .void, .a = success, .span = span });
    const failure = try codecError(Emit(D), .{ .d = &d, .b = &b, .h = h }, bad, shape.error_type, payloads[shape.error_tag]);
    const refused = try b.put(failure.at, .{ .op = .union_make, .ty = ret, .a = failure.value, .data = shape.error_tag, .span = span });
    _ = try d.runtime(&b, failure.at, "myl_core_json_done", .void, &.{h});
    _ = try b.put(failure.at, .{ .op = .ret, .ty = .void, .a = refused, .span = span });
    try d.finish();
    return b.function;
}

/// The `json.CodecError` the runtime kept: its kind (a case of `CodecErrorKind`), path, offset and sentence.
fn codecError(comptime E: type, e: E, start: ir.BlockId, error_type: typed.Type, physical: ir.Type) Error!struct { at: ir.BlockId, value: ir.Ref } {
    const d = e.d;
    const b = e.b;
    const h = e.h;
    const fields = d.mb.module.compound(physical).record;
    if (fields.len != 4) return d.mb.refuse("json.CodecError layout", d.span);
    const record = d.records()[error_type.recordIndex()];
    const kind_type = record.fields[0].ty;
    const cases = d.records()[kind_type.recordIndex()].shape.variants.?.cases;
    var at = start;
    const code = try d.runtime(b, at, "myl_core_json_error_kind", .i64, &.{h});
    const join = try b.block();
    const made = try d.allocator().alloc(ir.Ref, cases.len);
    for (made, 0..) |*value, i| {
        const hit = try b.block();
        const next = try b.block();
        const is = try b.put(at, .{ .op = .cmp, .ty = .bool, .a = code, .b = try d.int(b, .i64, @intCast(i)), .data = @backingInt(ir.Predicate.eq), .span = d.span });
        try b.branch(at, is, hit, next);
        value.* = try b.put(hit, .{ .op = .union_make, .ty = fields[0], .data = i, .span = d.span });
        try b.jump(hit, join);
        at = next;
    }
    _ = try b.put(at, .{ .op = .@"unreachable", .ty = .void, .span = d.span });
    const kind = try b.put(join, .{ .op = .phi, .ty = fields[0], .data = try b.extra(made), .span = d.span });
    const path = try d.runtime(b, join, "myl_core_json_error_path", .str, &.{h});
    const offset = try d.runtime(b, join, "myl_core_json_error_offset", .i64, &.{h});
    const message = try d.runtime(b, join, "myl_core_json_error_message", .str, &.{h});
    const value = try b.put(join, .{ .op = .record_make, .ty = physical, .data = try b.extra(&.{ kind, path, offset, message }), .span = d.span });
    return .{ .at = join, .value = value };
}
