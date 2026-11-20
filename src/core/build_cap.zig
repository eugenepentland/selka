//! Capability and resource effects use ordered scalar C adapters and typed result slots.
const std = @import("std");
const ir = @import("ir.zig");
const typed = @import("selka").typed;
const build_format = @import("build_format.zig");
/// Allocation and located source refusals from effect lowering.
pub const Error = error{ OutOfMemory, Unsupported };
/// A live lexical file scope and the loop depth at which it was opened.
/// A scope the builder closes on every exit edge. A task group (E1) has no provider: its end joins its tasks.
pub const Scope = struct { owner: ir.Ref, depth: usize, provider: ir.Ref = .none, group: bool = false, variable: ?u32 = null };

const file_access_symbol = "myl_core_file_access";
const stream_write_symbol = "myl_core_stream_write";
const stream_write_bytes_symbol = "myl_core_stream_write_bytes";
const stream_write_buffer_symbol = "myl_core_stream_write_buffer";

fn durableLimit(comptime Context: type, c: Context, file: typed.FileAccess) Error!ir.Ref {
    switch (file.kind) {
        .read_regular_file, .list_directory, .chmod_path, .set_modified_path, .mkdir_mode, .create_mode => return c.expression(file.arguments[2]),
        .atomic_write_file_mode, .replace_file_mode, .replace_file_synced_mode, .read_at_path => return c.expression(file.arguments[3]),
        else => return c.constant(.i64, 0),
    }
}

/// The type of the answer box of one file method: the method's own result, except `sync`, whose `Result` the box carries as a
/// status, the payload and the failure text.
fn fileMethodSlot(comptime Context: type, c: Context, node: typed.Node, file: typed.FileMethod, span: u32) Error!ir.Type {
    if (file.kind != .sync) return c.mb.mapType(node.ty, span);
    const shape = typed.resultShape(node.ty, c.mb.input.program.records) orelse return c.mb.refuse("capability result shape", span);
    return c.mb.mapType(shape.ok_type, span);
}

/// The value of one file method from its answer box: nothing for a unit method, the box's payload for the others, and for
/// `sync` (the one fallible method) the `Result` merged as every durable call merges its own.
fn fileMethodAnswer(comptime Context: type, c: Context, node: typed.Node, file: typed.FileMethod, box: ir.Ref, span: u32) Error!ir.Ref {
    if (file.kind == .sync) {
        const shape = typed.resultShape(node.ty, c.mb.input.program.records) orelse return c.mb.refuse("capability result shape", span);
        return Lower(Context).mergeResult(c, node.ty, shape, box, true, span);
    }
    return if ((try c.mb.mapType(node.ty, span)) == .void) .none else slotField(Context, c, box, 1, span);
}

/// The immortal empty `str` that stands in for an operand a call does not take.
fn emptyText(comptime Context: type, c: Context) Error!ir.Ref {
    const index = c.module().strings.items.len;
    try c.module().strings.append(c.allocator(), "");
    return c.detached(.{ .op = .str_const, .ty = .str, .data = index });
}

/// The path a durable call judges against the grant and the text it carries beside it (a rename's destination, the bytes of a
/// publication, a link's target), evaluated in source order. `symlink_path(fs, target, path)` is written target first, as `ln -s` and
/// Zig's `symLink` take it, and the runtime wants the link as its path and the target as the text to store. `link_path(fs, target,
/// path)` is written the same way but keeps its order, as a rename's two ends do: the existing file is the path, the new name the text.
fn durableOperands(comptime Context: type, c: Context, file: typed.FileAccess) Error!struct { path: ir.Ref, input: ir.Ref } {
    const first = try c.expression(file.arguments[1]);
    const second = if (file.kind.publishes() or file.kind.namesTwoPaths() or file.kind == .read_at_path) try c.expression(file.arguments[2]) else try emptyText(Context, c);
    const link = file.kind == .symlink_path;
    return .{ .path = if (link) second else first, .input = if (link) first else second };
}

/// Read a C result slot, transferring managed pointers in the owned ABI.
fn slotField(comptime Context: type, c: Context, box: ir.Ref, field: u32, span: u32) Error!ir.Ref {
    const ty = c.module().compound(c.module().storageType(c.typeOfRef(box))).box;
    const field_type = c.module().compound(ty).record[field];
    if (c.module().isBlock(field_type))
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
                .restrict_resource => |restrict| c.effectCall("myl_core_cap_restrict", &.{ .cap, .u32 }, .cap, &.{ try c.expression(restrict.value), try c.constant(.u32, restrict.permissions) }, span),
                .dir_resource => |dir| narrow(c, "myl_core_cap_dir", dir.capability, dir.path, span),
                .host_resource => |host| narrow(c, "myl_core_cap_host", host.capability, host.name, span),
                .environment_only => |only| c.effectCall("myl_core_environment_only", &.{ .cap, .bytes }, .cap, &.{ try c.expression(only.capability), try byteRequest(c, only.names, span) }, span),
                .environment_names => |cap| c.effectCall("myl_core_environment_names", &.{.cap}, ty, &.{try c.expression(cap)}, span),
                .environment_get => |get| environmentGet(c, node, get, span),
                .stream_write => |write| streamWrite(Context, c, write, ty, span),
                .file_access => |file| fileAccess(c, node, file, span),
                .file_method => |file| fileMethod(c, node, file, span),
                .acquire_resource => |acquire| acquireResource(c, node, acquire, span),
                .accept_resource => |value| acceptResource(c, node, value, span),
                .complete_resource => |value| completeResource(c, node, value, span),
                .resource_io => |io| resourceIo(c, node, io, span),
                else => c.mb.refuse(@tagName(node.data), span),
            };
        }

        fn narrow(c: Context, symbol: []const u8, capability: typed.NodeId, name: typed.NodeId, span: u32) Error!ir.Ref {
            const cap = try c.expression(capability);
            const spelling = try byteRequest(c, name, span);
            return c.effectCall(symbol, &.{ .cap, c.typeOfRef(spelling) }, .cap, &.{ cap, spelling }, span);
        }

        fn standIn(c: Context, stand: @FieldType(@FieldType(typed.Node, "data"), "stand_in"), ty: ir.Type, span: u32) Error!ir.Ref {
            const first = try c.expression(stand.first);
            return switch (stand.kind) {
                .stream_memory => c.effectCall("myl_core_stream_memory", &.{.i64}, ty, &.{first}, span),
                .stream_text => c.effectCall("myl_core_stream_text", &.{.cap}, ty, &.{first}, span),
                .monotonic => c.effectCall("myl_core_clock_monotonic", &.{.cap}, ty, &.{first}, span),
                .sleep => c.effectCall("myl_core_clock_sleep", &.{ .cap, .i64 }, ty, &.{ first, try c.expression(stand.second.?) }, span),
                .fail => c.effectCall("myl_core_stand_in_fail", &.{ .cap, .i64 }, ty, &.{ first, try c.expression(stand.second.?) }, span),
                .advance => c.effectCall("myl_core_clock_advance", &.{ .cap, .i64 }, ty, &.{ first, try c.expression(stand.second.?) }, span),
                .environment => c.effectCall("myl_core_environment_fixed", &.{.str}, ty, &.{first}, span),
                .process => c.effectCall("myl_core_process_scripted", &.{c.typeOfRef(first)}, ty, &.{first}, span),
                .input => c.effectCall("myl_core_input_memory", &.{c.typeOfRef(first)}, ty, &.{first}, span),
                .stop => c.effectCall("myl_core_stop_simulated", &.{.i64}, ty, &.{first}, span),
                else => c.effectCall("myl_core_stand_in", &.{ .u32, .i64 }, ty, &.{ try c.constant(.u32, @backingInt(stand.kind)), first }, span),
            };
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
            const box = try c.effectCall("myl_core_external_read", &.{ .cap, .u32 }, try resultSlot(c, value_type), &.{ try c.expression(read.capability), try c.constant(.u32, @backingInt(read.kind)) }, span);
            return mergeResult(c, node_type, shape, box, false, span);
        }
        fn fileAccess(c: Context, node: typed.Node, file: typed.FileAccess, span: u32) Error!ir.Ref {
            if (file.kind.isInput()) return inputAccess(c, node, file, span);
            if (file.kind.isStop()) return c.effectCall("myl_core_stop_control", &.{ .cap, .i64 }, .bool, &.{ try c.expression(file.arguments[0]), try c.expression(file.arguments[1]) }, span);
            if (file.kind.isDurable()) return durableFileAccess(c, node, file, span);
            if (file.kind == .run_process or file.kind == .process_control) return processRun(c, node, file, span);
            const cap = try c.expression(file.arguments[0]);
            const path = try c.expression(file.arguments[1]);
            const input = if (file.arguments.len > 2) try c.expression(file.arguments[2]) else try emptyString(c);
            const request = @as(u32, @backingInt(file.kind)) | (@as(u32, file.mode) << 8) | (@as(u32, @intFromBool(file.text)) << 16) | (@as(u32, @intFromBool(node.ty.isFile())) << 17);
            const arguments = &.{ cap, try c.constant(.u32, request), path, input };
            if (node.ty.isFile()) return c.effectCall(file_access_symbol, &.{ .cap, .u32, c.typeOfRef(path), c.typeOfRef(input) }, .resource, arguments, span);
            if (node.ty == .bool) {
                const box = try c.effectCall(file_access_symbol, &.{ .cap, .u32, c.typeOfRef(path), c.typeOfRef(input) }, try resultSlot(c, .bool), arguments, span);
                return slotField(Context, c, box, 1, span);
            }
            const shape = try shapeOf(c, node.ty, span);
            const box = try c.effectCall(file_access_symbol, &.{ .cap, .u32, c.typeOfRef(path), c.typeOfRef(input) }, try resultSlot(c, try c.mb.mapType(shape.ok_type, span)), arguments, span);
            return mergeResult(c, node.ty, shape, box, true, span);
        }
        fn durableFileAccess(c: Context, node: typed.Node, file: typed.FileAccess, span: u32) Error!ir.Ref {
            const cap = try c.expression(file.arguments[0]);
            const operands = try durableOperands(Context, c, file);
            const path = operands.path;
            const input = operands.input;
            const limit = try durableLimit(Context, c, file);
            const request = @as(u32, @backingInt(file.kind)) | (@as(u32, @intFromBool(node.ty.isFile())) << 17);
            const arguments = &.{ cap, try c.constant(.u32, request), path, input, limit };
            const parameters = &.{ ir.Type.cap, .u32, c.typeOfRef(path), c.typeOfRef(input), .i64 };
            const symbol = "myl_core_durable_access";
            if (node.ty.isFile()) return c.effectCall(symbol, parameters, .resource, arguments, span);
            const shape = try shapeOf(c, node.ty, span);
            const box = try c.effectCall(symbol, parameters, try resultSlot(c, try c.mb.mapType(shape.ok_type, span)), arguments, span);
            return mergeResult(c, node.ty, shape, box, true, span);
        }
        /// An `Input` method: `read(max)` is one runtime call answering the octets; `read_exact(n)` and `read_line()` call
        /// the runtime for what the input holds and answer `Some` of it when it is a whole answer (as many octets as asked,
        /// or at least one for a line) and `None` otherwise. The handle is the `Input` value itself, a descriptor or an
        /// in-memory input; a failed read traps `R_INPUT` inside the runtime, so there is no failure to merge.
        fn inputAccess(c: Context, node: typed.Node, file: typed.FileAccess, span: u32) Error!ir.Ref {
            const input = try c.expression(file.arguments[0]);
            const bytes = try c.mb.mapType(file.shapes.bytes, span);
            switch (file.kind) {
                .read => {
                    const most = try c.expression(file.arguments[1]);
                    return c.effectCall("myl_core_input_read", &.{ .cap, c.typeOfRef(most) }, bytes, &.{ input, most }, span);
                },
                .read_exact => {
                    const wanted = try c.expression(file.arguments[1]);
                    const data = try c.effectCall("myl_core_input_read_exact", &.{ .cap, c.typeOfRef(wanted) }, bytes, &.{ input, wanted }, span);
                    const got = try c.emit(.{ .op = .list_len, .ty = .u64, .a = data, .span = span });
                    const whole = try c.emit(.{ .op = .cmp, .ty = .bool, .a = try c.emit(.{ .op = .convert, .ty = .i64, .a = got, .span = span }), .b = wanted, .data = @backingInt(ir.Predicate.eq), .span = span });
                    return someUnless(c, node, data, whole, span);
                },
                .read_line => {
                    const data = try c.effectCall("myl_core_input_read_line", &.{.cap}, bytes, &.{input}, span);
                    const got = try c.emit(.{ .op = .list_len, .ty = .u64, .a = data, .span = span });
                    const present = try c.emit(.{ .op = .cmp, .ty = .bool, .a = got, .b = try c.constant(.u64, 0), .data = @backingInt(ir.Predicate.ne), .span = span });
                    return someUnless(c, node, data, present, span);
                },
                else => return c.mb.refuse("input access", span),
            }
        }
        /// `Some(data)` when `condition` holds and `None` otherwise (the data is released on that path).
        fn someUnless(c: Context, node: typed.Node, data: ir.Ref, condition: ir.Ref, span: u32) Error!ir.Ref {
            const ty = try c.mb.mapType(node.ty, span);
            const option = @import("selka").reference_tables.prelude.optionShape(node.ty, c.mb.input.program.records) orelse return c.mb.refuse("input option shape", span);
            const variable = try c.synthetic(ty);
            const some = try c.newBlock();
            const none = try c.newBlock();
            const done = try c.newBlock();
            try c.branch(condition, some, none, span);
            try c.seal(some);
            c.enter(some);
            try c.write(variable, some, try c.emit(.{ .op = .union_make, .ty = ty, .a = data, .data = option.some, .span = span }));
            try c.jump(done);
            try c.seal(none);
            c.enter(none);
            try c.write(variable, none, try c.emit(.{ .op = .union_make, .ty = ty, .data = option.none, .span = span }));
            try c.jump(done);
            try c.seal(done);
            c.enter(done);
            return c.read(variable, done);
        }
        /// `run_process(proc, request, limit)`: one runtime call with the capability, the packed request (a borrowed
        /// view takes the span form) and the byte limit, answering the packed result or the failure text.
        /// `process_control(proc, data, op)` has the same shape, with the operation in the integer slot.
        fn processRun(c: Context, node: typed.Node, file: typed.FileAccess, span: u32) Error!ir.Ref {
            const cap = try c.expression(file.arguments[0]);
            const request = try c.expression(file.arguments[1]);
            const limit = try c.expression(file.arguments[2]);
            const shape = try shapeOf(c, node.ty, span);
            const parameters = &.{ ir.Type.cap, c.typeOfRef(request), .i64 };
            const symbol = if (file.kind == .process_control) "myl_core_process_control" else "myl_core_process_run";
            const box = try c.effectCall(symbol, parameters, try resultSlot(c, try c.mb.mapType(shape.ok_type, span)), &.{ cap, request, limit }, span);
            return mergeResult(c, node.ty, shape, box, true, span);
        }
        fn fileMethod(c: Context, node: typed.Node, file: typed.FileMethod, span: u32) Error!ir.Ref {
            const owner = try c.receiverOf(file.owner);
            const argument = if (file.argument) |arg| try c.expression(arg) else try c.constant(.i64, -1);
            const writing = file.kind == .write;
            const count = if (writing) try c.constant(.i64, -1) else argument;
            const input = if (writing) argument else try emptyString(c);
            const request = @as(u32, @backingInt(file.kind)) | (@as(u32, @intFromBool(file.text)) << 16);
            const slot = try resultSlot(c, try fileMethodSlot(Context, c, node, file, span));
            const box = try c.effectCall("myl_core_file_method", &.{ .resource, .u32, .i64, c.typeOfRef(input) }, slot, &.{ owner, try c.constant(.u32, request), count, input }, span);
            return fileMethodAnswer(Context, c, node, file, box, span);
        }
        fn emptyString(c: Context) Error!ir.Ref {
            return emptyText(Context, c);
        }
        fn environmentGet(c: Context, node: typed.Node, get: @FieldType(@FieldType(typed.Node, "data"), "environment_get"), span: u32) Error!ir.Ref {
            const ty = try c.mb.mapType(node.ty, span);
            if (typed.environmentShape(node.ty, c.mb.input.program.records) != null) return rawEnvironment(c, node, get, span);
            const cap = try c.expression(get.capability);
            const name = try byteRequest(c, get.name, span);
            return c.effectCall("myl_core_environment_text", &.{ .cap, c.typeOfRef(name) }, ty, &.{ cap, name }, span);
        }
        fn acquireResource(c: Context, node: typed.Node, acquire: @FieldType(@FieldType(typed.Node, "data"), "acquire_resource"), span: u32) Error!ir.Ref {
            const shape = try shapeOf(c, node.ty, span);
            const cap = try c.expression(acquire.capability);
            const request = try byteRequest(c, acquire.request, span);
            const box = try c.effectCall("myl_core_resource_acquire", &.{ .cap, .bytes }, try resultSlot(c, .resource), &.{ cap, request }, span);
            return mergeResult(c, node.ty, shape, box, false, span);
        }
        fn acceptResource(c: Context, node: typed.Node, input: typed.LocalId, span: u32) Error!ir.Ref {
            const shape = try shapeOf(c, node.ty, span);
            const owner = try c.receiverOf(input);
            const box = try c.effectCall("myl_core_resource_accept", &.{.resource}, try resultSlot(c, .resource), &.{owner}, span);
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
            // A plain bytes or text parameter is a view (C9): the request takes its span like any other argument.
            if (ty == .bytes or ty == .str or ty == .bytes_view or ty == .str_view) return value;
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
            const box = try c.effectCall("myl_core_environment_raw", &.{ .cap, c.typeOfRef(name), .u64 }, try rawSlot(c), &.{ cap, name, try c.constant(.u64, @intCast(capacity)) }, span);
            return byteResult(c, node.ty, shape, box, span);
        }
        fn resourceIo(c: Context, node: typed.Node, io: @FieldType(@FieldType(typed.Node, "data"), "resource_io"), span: u32) Error!ir.Ref {
            const owner = try c.receiverOf(io.owner);
            if (io.kind == .write) {
                const input = try byteRequest(c, io.value.?, span);
                const shape = try shapeOf(c, node.ty, span);
                // A borrowed text or bytes value is written in place through its span (C9 bytes): no copy of the octets.
                const write_symbol = if (c.typeOfRef(input).isSpan()) "myl_core_span_resource_write" else "myl_core_resource_write";
                const box = try c.effectCall(write_symbol, &.{ .resource, c.typeOfRef(input) }, try resultSlot(c, .u64), &.{ owner, input }, span);
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
            const array = try bytesArray(Context, c, array_ty, try slotField(Context, c, raw, 1, span), span);
            return byteResultWith(c, result_type, shape, raw, array, span);
        }
        fn byteResultWith(c: Context, result_type: typed.Type, shape: typed.ByteResultShape, raw: ir.Ref, array: ir.Ref, span: u32) Error!ir.Ref {
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

/// The inline `u8` array of type `array_ty` holding the first `n` octets of byte list `bytes`. An
/// array held in memory is filled by one bulk copy, so its size does not set the size of the code
/// (a 64 KiB chunk once cost a minute to compile, FR-217); a small one stays in registers.
fn bytesArray(comptime Context: type, c: Context, array_ty: ir.Type, bytes: ir.Ref, span: u32) Error!ir.Ref {
    if (c.module().passedInMemory(array_ty)) return c.emit(.{ .op = .array_from_bytes, .ty = array_ty, .a = bytes, .span = span });
    const capacity = c.module().compound(array_ty).array.n;
    const octets = try c.allocator().alloc(ir.Ref, capacity);
    for (octets, 0..) |*octet, index| octet.* = try c.emit(.{ .op = .list_get, .ty = .u8, .a = bytes, .b = try c.constant(.u64, @intCast(index)), .span = span });
    return c.emit(.{ .op = .record_make, .ty = array_ty, .data = try c.extraSlice(octets), .span = span });
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
    {
        // A `with`-bound handle closes the value its binding holds now: a `mut` argument hands the handle back through the binding.
        const owner = if (scope.variable) |variable| try c.read(variable, c.current.?) else scope.owner;
        const ty = c.typeOfRef(owner);
        // A task group is joined and destroyed by its own runtime end: it has no provider (E1, parallel.group).
        if (scope.group) {
            _ = try c.effectCall("myl_core_owned_group_end", &.{ty}, .void, &.{owner}, span);
            return;
        }
        // A narrowed capability is a handle like its parent (5C): its scope's end destroys nothing.
        if (ty == .cap) return;
        _ = try c.effectCall("myl_core_owned_file_scope_end", &.{ ty, c.typeOfRef(scope.provider) }, .void, &.{ owner, scope.provider }, span);
    }
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

/// Print options retain ordinary print behavior and use ordered writes for dynamic
/// separators. A format-string argument writes its own pieces between those writes.
pub fn printOptions(comptime Context: type, c: Context, print: typed.Print, span: u32) Error!ir.Ref {
    const stream = if (print.stream) |receiver| try c.expression(receiver) else try c.constant(.cap, if (print.debug or print.sink == .stderr) 2 else 1);
    // Every argument is evaluated before any of them is written, so an f-string's
    // holes keep their place in source order beside the other arguments.
    const arguments = try c.allocator().alloc(Argument, print.arguments.len);
    for (print.arguments, arguments) |source, *argument| argument.* = try evaluate(Context, c, source, span);
    if (c.current == null) return .none;
    const separator = if (print.separator) |source| try c.expression(source) else try literal(Context, c, " ");
    const terminator = if (print.terminator) |source| try c.expression(source) else try literal(Context, c, "\n");
    _ = try c.effectCall("myl_core_output_begin", &.{.cap}, .void, &.{stream}, span);
    for (arguments, 0..) |argument, index| {
        if (index != 0) _ = try c.effectCall(stream_write_symbol, &.{ .cap, .str }, .void, &.{ stream, separator }, span);
        switch (argument) {
            .format => |format| _ = try build_format.print(Context, c, format, stream, span),
            .value => |value| {
                const text = try c.textOf(value, c.nodeOf(print.arguments[index]).ty, span);
                _ = try c.effectCall(stream_write_symbol, &.{ .cap, .str }, .void, &.{ stream, text }, span);
            },
        }
    }
    _ = try c.effectCall(stream_write_symbol, &.{ .cap, .str }, .void, &.{ stream, terminator }, span);
    return c.effectCall("myl_core_output_end", &.{.cap}, .void, &.{stream}, span);
}

/// A `debug` line in a build that drops debug output (`build --release`) keeps the meaning of the line and loses its cost: every
/// argument is evaluated in the order `printOptions` evaluates them (an f-string's holes in source order, then the separator and
/// the terminator when the line gives them), so a call runs, a `mut` argument is written and a bad index traps as in every
/// other build. Nothing is formatted and nothing is written. An evaluated value that is never printed keeps its owner, so the
/// ownership plan destroys it right after its definition, as it does any fresh value with no later use.
pub fn evaluateDroppedDebug(comptime Context: type, c: Context, print: typed.Print) Error!ir.Ref {
    for (print.arguments) |source| {
        switch (c.nodeOf(source).data) {
            .format => |format| for (format.pieces) |piece| switch (piece) {
                .literal => {},
                .hole => |hole| _ = try c.expression(hole.value),
            },
            else => _ = try c.expression(source),
        }
        if (c.current == null) return .none;
    }
    if (print.separator) |source| _ = try c.expression(source);
    if (print.terminator) |source| _ = try c.expression(source);
    return .none;
}

/// One evaluated print argument: an ordinary value, or a format string whose
/// holes are already evaluated.
const Argument = union(enum) { format: build_format.Prepared, value: ir.Ref };

fn evaluate(comptime Context: type, c: Context, source: typed.NodeId, span: u32) Error!Argument {
    const node = c.nodeOf(source);
    if (node.data == .format) return .{ .format = try build_format.evaluate(Context, c, node.data.format, span) };
    return .{ .value = try c.expression(source) };
}
/// `Stream.write` takes `str`, `bytes` or `byte_buffer`; each gets a helper declared
/// with its own type, since one program may write all three (each is one
/// length-prefixed block, written as is). It answers what it wrote, as `len` counts
/// it: a string's scalars, a byte value's bytes (NEW-CORE-S5-STREAM-WRITE-1). A
/// format string is written from its pieces instead of being built first.
fn streamWrite(comptime Context: type, c: Context, write: typed.StreamWrite, result: ir.Type, span: u32) Error!ir.Ref {
    const stream = try c.expression(write.stream);
    if (c.nodeOf(write.text).data == .format) return formatWrite(Context, c, write.text, stream, result, span);
    const text = try c.expression(write.text);
    const ty = try c.mb.mapType(c.nodeOf(write.text).ty, span);
    const symbol = switch (ty) {
        .str => stream_write_symbol,
        .bytes => stream_write_bytes_symbol,
        .byte_buffer => stream_write_buffer_symbol,
        else => return c.mb.refuse("stream write argument", span),
    };
    _ = try c.effectCall(symbol, &.{ .cap, c.typeOfRef(text) }, .void, &.{ stream, text }, span);
    if (result == .void) return .none;
    const count = if (ty == .str) try c.stringChars(text, span) else try c.emit(.{ .op = .list_len, .ty = .u64, .a = text, .span = span });
    return c.emit(.{ .op = .convert, .ty = result, .a = count, .span = span });
}

/// Write a format string's pieces to `stream`, counted as `write` counts them: as
/// many Unicode scalars as the pieces spelled. A discarded result needs no count,
/// so it takes the path that never scans a text hole.
fn formatWrite(comptime Context: type, c: Context, text: typed.NodeId, stream: ir.Ref, result: ir.Type, span: u32) Error!ir.Ref {
    const prepared = try build_format.evaluate(Context, c, c.nodeOf(text).data.format, span);
    if (c.current == null) return .none;
    _ = try c.effectCall("myl_core_output_begin", &.{.cap}, .void, &.{stream}, span);
    const count = if (result == .void) counted: {
        _ = try build_format.print(Context, c, prepared, stream, span);
        break :counted ir.Ref.none;
    } else try build_format.write(Context, c, prepared, stream, span);
    _ = try c.effectCall("myl_core_output_end", &.{.cap}, .void, &.{stream}, span);
    if (result == .void) return .none;
    return c.emit(.{ .op = .convert, .ty = result, .a = count, .span = span });
}

fn literal(comptime Context: type, c: Context, bytes: []const u8) Error!ir.Ref {
    const index = c.module().strings.items.len;
    try c.module().strings.append(c.allocator(), bytes);
    return c.detached(.{ .op = .str_const, .ty = .str, .data = index });
}

/// `flush(stream)`: one runtime call pushes the stream's buffered bytes out.
pub fn streamFlush(comptime Context: type, c: Context, stream: ir.Ref, span: u32) Error!void {
    _ = try c.effectCall("myl_core_stream_flush", &.{.cap}, .void, &.{stream}, span);
}
