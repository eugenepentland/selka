//! Capability and resource effects use ordered scalar C adapters and typed result slots.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("mylang").typed;
/// Allocation and located source refusals from effect lowering.
pub const Error = error{ OutOfMemory, Unsupported };
/// A live lexical file scope and the loop depth at which it was opened.
pub const Scope = struct { owner: ir.Ref, depth: usize, provider: ir.Ref = .none, pin: ?u32 = null };

const file_access_symbol = "myl_core_file_access";
const stream_write_symbol = "myl_core_stream_write";
const stream_write_bytes_symbol = "myl_core_stream_write_bytes";
const stream_write_buffer_symbol = "myl_core_stream_write_buffer";

fn durableLimit(comptime Context: type, c: Context, file: typed.FileAccess) Error!ir.Ref {
    if (file.kind == .read_regular_file or file.kind == .list_directory) return c.expression(file.arguments[2]);
    return c.constant(.i64, 0);
}

/// Read a C result slot, transferring managed pointers in the owned ABI.
fn slotField(comptime Context: type, c: Context, box: ir.Ref, field: u32, span: u32) Error!ir.Ref {
    const ty = c.module().compound(c.typeOfRef(box)).box;
    const field_type = c.module().compound(ty).record[field];
    if (c.module().zero_rc and c.module().isBlock(field_type))
        return c.effectCall("myl_core_result_take_pointer", &.{ c.typeOfRef(box), .u32 }, field_type, &.{ box, try c.constant(.u32, field) }, span);
    const value = try c.emit(.{ .op = .box_get, .ty = ty, .a = box, .span = span });
    return c.emit(.{ .op = .record_get, .ty = c.module().compound(ty).record[field], .a = value, .data = field, .span = span });
}

/// Bind capability lowering to one concrete function builder.
pub fn Lower(comptime Context: type) type {
    return struct {
        /// Lower a checked capability operation without changing authority or evaluation order.
        pub fn expression(c: Context, node: typed.Node, span: u32) Error!ir.Ref {
            const ty = try c.mb.mapType(node.ty, span);
            return switch (node.data) {
                .stand_in => |stand| standIn(c, stand, ty, span),
                .external_read => |read| externalRead(c, node.ty, read, span),
                .restrict_resource => |restrict| c.effectCall("myl_core_cap_restrict", &.{ .capability, .u32 }, .capability, &.{ try c.expression(restrict.value), try c.constant(.u32, restrict.permissions) }, span),
                .dir_resource => |dir| narrow(c, "myl_core_cap_dir", dir.capability, dir.path, span),
                .host_resource => |host| narrow(c, "myl_core_cap_host", host.capability, host.name, span),
                .environment_only => |only| c.effectCall("myl_core_environment_only", &.{ .capability, .bytes }, .capability, &.{ try c.expression(only.capability), try byteRequest(c, only.names, span) }, span),
                .environment_names => |cap| c.effectCall("myl_core_environment_names", &.{.capability}, ty, &.{try c.expression(cap)}, span),
                .environment_get => |get| environmentGet(c, node, get, span),
                .stream_write => |write| streamWrite(c, write, ty, span),
                .file_access => |file| fileAccess(c, node, file, span),
                .file_method => |file| fileMethod(c, node, file, span),
                .acquire_resource => |acquire| acquireResource(c, node, acquire, span),
                .complete_resource => |value| completeResource(c, node, value, span),
                .resource_io => |io| resourceIo(c, node, io, span),
                else => c.mb.refuse(@tagName(node.data), span),
            };
        }

        /// `Stream.write` takes `str`, `bytes` or `byte_buffer`; each gets a helper declared
        /// with its own type, since one program may write all three (each is one
        /// length-prefixed block, written as is). It answers what it wrote, as `len` counts
        /// it: a string's scalars, a byte value's bytes (NEW-CORE-S5-STREAM-WRITE-1).
        fn streamWrite(c: Context, write: typed.StreamWrite, result: ir.Type, span: u32) Error!ir.Ref {
            const stream = try c.expression(write.stream);
            const text = try c.expression(write.text);
            const ty = try c.mb.mapType(c.nodeOf(write.text).ty, span);
            const symbol = switch (ty) {
                .str => stream_write_symbol,
                .bytes => stream_write_bytes_symbol,
                .byte_buffer => stream_write_buffer_symbol,
                else => return c.mb.refuse("stream write argument", span),
            };
            _ = try c.effectCall(symbol, &.{ .cap, ty }, .void, &.{ stream, text }, span);
            if (result == .void) return .none;
            const count = if (ty == .str) try c.stringChars(text, span) else try c.emit(.{ .op = .list_len, .ty = .u64, .a = text, .span = span });
            return c.emit(.{ .op = .convert, .ty = result, .a = count, .span = span });
        }

        fn narrow(c: Context, symbol: []const u8, capability: typed.NodeId, name: typed.NodeId, span: u32) Error!ir.Ref {
            const cap = try c.expression(capability);
            const spelling = try byteRequest(c, name, span);
            return c.effectCall(symbol, &.{ .capability, c.typeOfRef(spelling) }, .capability, &.{ cap, spelling }, span);
        }

        fn standIn(c: Context, stand: @FieldType(@FieldType(typed.Node, "data"), "stand_in"), ty: ir.Type, span: u32) Error!ir.Ref {
            const first = try c.expression(stand.first);
            if (stand.kind == .advance) return c.effectCall("myl_core_clock_advance", &.{ .capability, .i64 }, ty, &.{ first, try c.expression(stand.second.?) }, span);
            if (stand.kind == .environment) return c.effectCall("myl_core_environment_fixed", &.{.str}, ty, &.{first}, span);
            return c.effectCall("myl_core_stand_in", &.{ .u32, .i64 }, ty, &.{ try c.constant(.u32, @backingInt(stand.kind)), first }, span);
        }

        /// One explicit C result box: status, scalar/pointer payload and optional owned error text.
        pub fn resultSlot(c: Context, value_type: ir.Type) Error!ir.Type {
            const slot = try c.module().intern(c.allocator(), .{ .record = &.{ .u64, if (value_type == .void) .u64 else value_type, .str } });
            return c.module().intern(c.allocator(), .{ .box = slot });
        }
        fn unionValue(c: Context, ty: ir.Type, tag: usize, payload: ir.Ref, span: u32) Error!ir.Ref {
            return c.emit(.{ .op = .union_make, .ty = ty, .a = payload, .data = tag, .span = span });
        }
        fn mergeResult(c: Context, result_type: typed.Type, shape: typed.ResultShape, box: ir.Ref, error_text: bool, span: u32) Error!ir.Ref {
            const ty = try c.mb.mapType(result_type, span);
            const status = try slotField(Context, c, box, 0, span);
            const good = try c.emit(.{ .op = .cmp, .ty = .bool, .a = status, .b = try c.constant(.u64, 0), .data = @backingInt(ir.Predicate.eq), .span = span });
            const success = try c.newBlock();
            const failure = try c.newBlock();
            const done = try c.newBlock();
            const variable = try c.synthetic(ty);
            try c.branch(good, success, failure, span);
            try c.seal(success);
            c.enter(success);
            const payload = if (shape.ok_type == .unit) ir.Ref.none else try slotField(Context, c, box, 1, span);
            try c.write(variable, success, try unionValue(c, ty, shape.ok_tag, payload, span));
            try c.jump(done);
            try c.seal(failure);
            c.enter(failure);
            const code = if (error_text) try slotField(Context, c, box, 2, span) else try c.emit(.{ .op = .convert, .ty = .i64, .a = status, .span = span });
            const bad = try unionValue(c, ty, shape.error_tag, code, span);
            _ = try c.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.runtime), .span = span });
            try c.write(variable, failure, bad);
            try c.jump(done);
            try c.seal(done);
            c.enter(done);
            return c.read(variable, done);
        }
        fn shapeOf(c: Context, ty: typed.Type, span: u32) Error!typed.ResultShape {
            return typed.resultShape(ty, c.mb.input.program.records) orelse return c.mb.refuse("capability result shape", span);
        }
        fn externalRead(c: Context, node_type: typed.Type, read: @FieldType(@FieldType(typed.Node, "data"), "external_read"), span: u32) Error!ir.Ref {
            const shape = try shapeOf(c, node_type, span);
            const value_type = try c.mb.mapType(shape.ok_type, span);
            const box = try c.effectCall("myl_core_external_read", &.{ .capability, .u32 }, try resultSlot(c, value_type), &.{ try c.expression(read.capability), try c.constant(.u32, @backingInt(read.kind)) }, span);
            return mergeResult(c, node_type, shape, box, false, span);
        }
        fn fileAccess(c: Context, node: typed.Node, file: typed.FileAccess, span: u32) Error!ir.Ref {
            switch (file.kind) {
                .atomic_write_file, .lock_directory, .sync_directory, .read_regular_file, .list_directory => return durableFileAccess(c, node, file, span),
                else => {},
            }
            const cap = try c.expression(file.arguments[0]);
            const path = try c.expression(file.arguments[1]);
            const input = if (file.arguments.len > 2) try c.expression(file.arguments[2]) else try emptyString(c);
            const request = @as(u32, @backingInt(file.kind)) | (@as(u32, file.mode) << 8) | (@as(u32, @intFromBool(file.text)) << 16) | (@as(u32, @intFromBool(node.ty.isFile())) << 17);
            const arguments = &.{ cap, try c.constant(.u32, request), path, input };
            if (node.ty.isFile()) return c.effectCall(file_access_symbol, &.{ .capability, .u32, .str, c.typeOfRef(input) }, .resource, arguments, span);
            if (node.ty == .bool) {
                const box = try c.effectCall(file_access_symbol, &.{ .capability, .u32, .str, c.typeOfRef(input) }, try resultSlot(c, .bool), arguments, span);
                return slotField(Context, c, box, 1, span);
            }
            const shape = try shapeOf(c, node.ty, span);
            const box = try c.effectCall(file_access_symbol, &.{ .capability, .u32, .str, c.typeOfRef(input) }, try resultSlot(c, try c.mb.mapType(shape.ok_type, span)), arguments, span);
            return mergeResult(c, node.ty, shape, box, true, span);
        }
        fn durableFileAccess(c: Context, node: typed.Node, file: typed.FileAccess, span: u32) Error!ir.Ref {
            const cap = try c.expression(file.arguments[0]);
            const path = try c.expression(file.arguments[1]);
            const input = if (file.kind == .atomic_write_file) try c.expression(file.arguments[2]) else try emptyString(c);
            const limit = try durableLimit(Context, c, file);
            const request = @as(u32, @backingInt(file.kind)) | (@as(u32, @intFromBool(node.ty.isFile())) << 17);
            const arguments = &.{ cap, try c.constant(.u32, request), path, input, limit };
            const parameters = &.{ ir.Type.capability, .u32, .str, c.typeOfRef(input), .i64 };
            const symbol = "myl_core_durable_access";
            if (node.ty.isFile()) return c.effectCall(symbol, parameters, .resource, arguments, span);
            const shape = try shapeOf(c, node.ty, span);
            const box = try c.effectCall(symbol, parameters, try resultSlot(c, try c.mb.mapType(shape.ok_type, span)), arguments, span);
            return mergeResult(c, node.ty, shape, box, true, span);
        }
        fn fileMethod(c: Context, node: typed.Node, file: typed.FileMethod, span: u32) Error!ir.Ref {
            const ty = try c.mb.mapType(node.ty, span);
            const owner = try c.receiverOf(file.owner);
            const argument = if (file.argument) |arg| try c.expression(arg) else try c.constant(.i64, -1);
            const writing = file.kind == .write;
            const count = if (writing) try c.constant(.i64, -1) else argument;
            const input = if (writing) argument else try emptyString(c);
            const request = @as(u32, @backingInt(file.kind)) | (@as(u32, @intFromBool(file.text)) << 16);
            const box = try c.effectCall("myl_core_file_method", &.{ .resource, .u32, .i64, c.typeOfRef(input) }, try resultSlot(c, ty), &.{ owner, try c.constant(.u32, request), count, input }, span);
            return if (ty == .void) .none else slotField(Context, c, box, 1, span);
        }
        fn emptyString(c: Context) Error!ir.Ref {
            const index = c.module().strings.items.len;
            try c.module().strings.append(c.allocator(), "");
            return c.detached(.{ .op = .str_const, .ty = .str, .data = index });
        }
        fn environmentGet(c: Context, node: typed.Node, get: @FieldType(@FieldType(typed.Node, "data"), "environment_get"), span: u32) Error!ir.Ref {
            const ty = try c.mb.mapType(node.ty, span);
            if (typed.environmentShape(node.ty, c.mb.input.program.records) != null) return rawEnvironment(c, node, get, span);
            const cap = try c.expression(get.capability);
            const name = try byteRequest(c, get.name, span);
            return c.effectCall("myl_core_environment_text", &.{ .capability, c.typeOfRef(name) }, ty, &.{ cap, name }, span);
        }
        fn acquireResource(c: Context, node: typed.Node, acquire: @FieldType(@FieldType(typed.Node, "data"), "acquire_resource"), span: u32) Error!ir.Ref {
            const shape = try shapeOf(c, node.ty, span);
            const cap = try c.expression(acquire.capability);
            const request = try byteRequest(c, acquire.request, span);
            const box = try c.effectCall("myl_core_resource_acquire", &.{ .capability, .bytes }, try resultSlot(c, .resource), &.{ cap, request }, span);
            return mergeResult(c, node.ty, shape, box, false, span);
        }
        fn completeResource(c: Context, node: typed.Node, input: typed.NodeId, span: u32) Error!ir.Ref {
            const shape = typed.completionShape(node.ty, c.mb.input.program.records) orelse return c.mb.refuse("resource completion shape", span);
            const owner = try c.expression(input);
            const code = try c.effectCall("myl_core_resource_complete", &.{.resource}, .i64, &.{owner}, span);
            const ty = try c.mb.mapType(node.ty, span);
            const status = try c.emit(.{ .op = .cmp, .ty = .bool, .a = code, .b = try c.constant(.i64, 0), .data = @backingInt(ir.Predicate.eq), .span = span });
            const success = try c.newBlock();
            const failure = try c.newBlock();
            const done = try c.newBlock();
            const variable = try c.synthetic(ty);
            try c.branch(status, success, failure, span);
            try c.seal(success);
            c.enter(success);
            try c.write(variable, success, try unionValue(c, ty, shape.result.ok_tag, try c.detached(.{ .op = .iconst, .ty = .bool, .data = 1 }), span));
            try c.jump(done);
            try c.seal(failure);
            c.enter(failure);
            const bad_ty = try c.mb.mapType(shape.result.error_type, span);
            const fields = try c.allocator().alloc(ir.Ref, 2);
            fields[shape.resource_field] = owner;
            fields[shape.code_field] = code;
            const payload = try c.emit(.{ .op = .record_make, .ty = bad_ty, .data = try c.extraSlice(fields), .span = span });
            _ = try c.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.runtime), .span = span });
            try c.write(variable, failure, try unionValue(c, ty, shape.result.error_tag, payload, span));
            try c.jump(done);
            try c.seal(done);
            c.enter(done);
            return c.read(variable, done);
        }
        fn byteRequest(c: Context, input: typed.NodeId, span: u32) Error!ir.Ref {
            const value = try c.expression(input);
            const ty = c.typeOfRef(value);
            if (ty == .bytes or ty == .str) return value;
            if (c.module().kind(ty) != .array) return c.mb.refuse("resource request type", span);
            const shape = c.module().compound(ty).array;
            const list_ty = try c.module().intern(c.allocator(), .{ .list = .u8 });
            var list = try c.emit(.{ .op = .list_new, .ty = list_ty, .a = try c.constant(.u64, shape.n), .span = span });
            for (0..shape.n) |field| {
                const octet = try c.emit(.{ .op = .array_get, .ty = .u8, .a = value, .b = try c.constant(.u64, @intCast(field)), .check = .exact, .span = span });
                list = try c.emit(.{ .op = .list_push, .ty = list_ty, .a = list, .b = octet, .span = span });
            }
            return c.effectCall("myl_core_io_bytes_from_u8_list", &.{list_ty}, .bytes, &.{list}, span);
        }
        fn rawEnvironment(c: Context, node: typed.Node, get: @FieldType(@FieldType(typed.Node, "data"), "environment_get"), span: u32) Error!ir.Ref {
            const shape = typed.environmentShape(node.ty, c.mb.input.program.records).?;
            const cap = try c.expression(get.capability);
            const name = try byteRequest(c, get.name, span);
            const array = try c.mb.mapType(shape.bytes_type, span);
            const capacity = c.module().compound(array).array.n;
            const box = try c.effectCall("myl_core_environment_raw", &.{ .capability, c.typeOfRef(name), .u64 }, try rawSlot(c), &.{ cap, name, try c.constant(.u64, @intCast(capacity)) }, span);
            return byteResult(c, node.ty, shape, box, span);
        }
        fn resourceIo(c: Context, node: typed.Node, io: @FieldType(@FieldType(typed.Node, "data"), "resource_io"), span: u32) Error!ir.Ref {
            const owner = try c.receiverOf(io.owner);
            if (io.kind == .write) {
                const input = try byteRequest(c, io.value.?, span);
                const shape = try shapeOf(c, node.ty, span);
                const box = try c.effectCall("myl_core_resource_write", &.{ .resource, c.typeOfRef(input) }, try resultSlot(c, .u64), &.{ owner, input }, span);
                return mergeResult(c, node.ty, shape, box, false, span);
            }
            const shape = typed.resourceReadShape(node.ty, c.mb.input.program.records) orelse return c.mb.refuse("resource read shape", span);
            const array = try c.mb.mapType(shape.bytes_type, span);
            const capacity = c.module().compound(array).array.n;
            const box = try c.effectCall("myl_core_resource_read", &.{ .resource, .u64 }, try rawSlot(c), &.{ owner, try c.constant(.u64, @intCast(capacity)) }, span);
            return byteResult(c, node.ty, shape, box, span);
        }
        fn rawSlot(c: Context) Error!ir.Type {
            const record = try c.module().intern(c.allocator(), .{ .record = &.{ .u64, .bytes, .u64, .bool } });
            return c.module().intern(c.allocator(), .{ .box = record });
        }
        fn byteResult(c: Context, result_type: typed.Type, shape: typed.ByteResultShape, raw: ir.Ref, span: u32) Error!ir.Ref {
            const array_ty = try c.mb.mapType(shape.bytes_type, span);
            const capacity = c.module().compound(array_ty).array.n;
            const bytes = try slotField(Context, c, raw, 1, span);
            const octets = try c.allocator().alloc(ir.Ref, capacity);
            for (octets, 0..) |*octet, index| octet.* = try c.emit(.{ .op = .list_get, .ty = .u8, .a = bytes, .b = try c.constant(.u64, @intCast(index)), .span = span });
            const array = try c.emit(.{ .op = .record_make, .ty = array_ty, .data = try c.extraSlice(octets), .span = span });
            const payload_ty = try c.mb.mapType(shape.result.ok_type, span);
            const fields = try c.allocator().alloc(ir.Ref, 3);
            fields[shape.bytes_field] = array;
            fields[shape.length_field] = try slotField(Context, c, raw, 2, span);
            fields[shape.flag_field] = try slotField(Context, c, raw, 3, span);
            const payload = try c.emit(.{ .op = .record_make, .ty = payload_ty, .data = try c.extraSlice(fields), .span = span });
            const status = try slotField(Context, c, raw, 0, span);
            // Rebox the copied fixed payload using ordinary typed Core record construction.
            const slot_ty = c.module().compound(try resultSlot(c, payload_ty)).box;
            const slot = try c.emit(.{ .op = .record_make, .ty = slot_ty, .data = try c.extraSlice(&.{ status, payload, try emptyString(c) }), .span = span });
            const box = try c.emit(.{ .op = .box_make, .ty = try resultSlot(c, payload_ty), .a = slot, .span = span });
            return mergeResult(c, result_type, shape.result, box, false, span);
        }
    };
}

/// The source-level parent whose lifetime encloses a dependent scope.
pub fn scopeProvider(program: typed.Program, source: typed.NodeId) ?typed.NodeId {
    const node = program.nodes[@backingInt(source)];
    return switch (node.data) {
        .propagate => |value| scopeProvider(program, value.value),
        .block_value => |block| scopeProvider(program, block.value),
        .call => |call| call.arguments[@import("single_owner_resource.zig").parameter(program, program.functions[@backingInt(call.function)]) orelse return null],
        .file_access => |file| file.arguments[0],
        .dir_resource => |dir| dir.capability,
        .host_resource => |host| host.capability,
        .restrict_resource => |restrict| restrict.value,
        .environment_only => |only| only.capability,
        else => null,
    };
}

/// Close and drop a scoped handle while its provider is still a borrowed argument.
pub fn closeScope(comptime Context: type, c: Context, scope: Scope, span: u32) Error!void {
    if (scope.pin) |slot| {
        _ = try c.effectCall("myl_core_provider_keepalive", &.{.capability}, .void, &.{try c.read(slot, c.current.?)}, span);
        return;
    }
    if (c.module().zero_rc) {
        const ty = c.typeOfRef(scope.owner);
        const symbol = if (ty == .resource) "myl_core_owned_file_scope_end" else "myl_core_owned_cap_scope_end";
        _ = try c.effectCall(symbol, &.{ ty, .capability }, .void, &.{ scope.owner, scope.provider }, span);
    } else if (c.typeOfRef(scope.owner) == .resource) _ = try c.effectCall("myl_core_file_scope_close", &.{.resource}, .void, &.{scope.owner}, span);
}

/// Close active file scopes crossed by a return or a loop exit, innermost first.
pub fn closeScopes(comptime Context: type, c: Context, depth: usize, span: u32) Error!void {
    var left = c.ssa.resources.items.len;
    while (left != 0) {
        left -= 1;
        const scope = c.ssa.resources.items[left];
        if (scope.depth < depth) continue;
        try closeScope(Context, c, scope, span);
    }
}

/// Print options retain ordinary print behavior and use ordered writes for dynamic separators.
pub fn printOptions(comptime Context: type, c: Context, print: typed.Print, span: u32) Error!ir.Ref {
    const stream = if (print.stream) |receiver| try c.expression(receiver) else try c.constant(.cap, if (print.debug or print.sink == .stderr) 2 else 1);
    const arguments = try c.allocator().alloc(ir.Ref, print.arguments.len);
    for (print.arguments, arguments) |source, *argument| argument.* = try c.expression(source);
    const separator = if (print.separator) |source| try c.expression(source) else try literal(Context, c, " ");
    const terminator = if (print.terminator) |source| try c.expression(source) else try literal(Context, c, "\n");
    _ = try c.effectCall("myl_core_output_begin", &.{.cap}, .void, &.{stream}, span);
    for (arguments, 0..) |argument, index| {
        if (index != 0) _ = try c.effectCall(stream_write_symbol, &.{ .cap, .str }, .void, &.{ stream, separator }, span);
        const text = try c.textOf(argument, c.nodeOf(print.arguments[index]).ty, span);
        _ = try c.effectCall(stream_write_symbol, &.{ .cap, .str }, .void, &.{ stream, text }, span);
    }
    _ = try c.effectCall(stream_write_symbol, &.{ .cap, .str }, .void, &.{ stream, terminator }, span);
    return c.effectCall("myl_core_output_end", &.{.cap}, .void, &.{stream}, span);
}
fn literal(comptime Context: type, c: Context, bytes: []const u8) Error!ir.Ref {
    const index = c.module().strings.items.len;
    try c.module().strings.append(c.allocator(), bytes);
    return c.detached(.{ .op = .str_const, .ty = .str, .data = index });
}
