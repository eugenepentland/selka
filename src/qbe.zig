//! Independent native QBE units. Source locations never enter native artifact bytes.
const slice_abi = ":myl_slice";
const scalar_lower = @import("qbe_scalar.zig");
const zero_local = @import("qbe_format.zig").zero_local;
const arena_lower = @import("qbe_arena.zig");
const managed_lower = @import("qbe_managed.zig");
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native_types = @import("native_types.zig");
const diagnostic = @import("diagnostic.zig");
const Source = @import("source.zig").Source;
const entry_adapter = @import("entry_adapter.zig");
const native_descriptors = @import("native_descriptors.zig");
const prelude = @import("prelude.zig");
/// Failures producing independent QBE native units.
pub const GenerateError = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const drop_local = " call $myl_native_owned_drop(l %heap, l extern ${s}, l %l{d})\n";
const store_scalar = " storel {d}, %s{d}\n";
const Location = struct { path: []const u8, line: usize, column: usize };
const Unit = struct { test_dependencies: ?@import("native_test_dependencies.zig").Metadata = null, name: []const u8, symbol: []const u8, il: []const u8, locations: []const Location, @"export": ?@import("qbe_exports.zig").Export = null };

/// Generate a JSON manifest whose independently linkable functions have stable names.
pub fn generate(allocator: std.mem.Allocator, program: bytecode.Program, src: Source, sink: *diagnostic.Sink) GenerateError![]u8 {
    return generateWithInterface(allocator, program, src, sink, .{});
}

/// Include authoritative public exports and an immutable interface schema snapshot.
pub fn generateWithInterface(allocator: std.mem.Allocator, program: bytecode.Program, src: Source, sink: *diagnostic.Sink, interface: @import("native_interface.zig").Interface) GenerateError![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var layouts = native_types.Catalog.initRecords(a, program.records) catch |err| return layoutError(err);
    defer layouts.deinit();
    const units = try a.alloc(Unit, program.functions.len);
    for (program.functions, units, 0..) |function, *unit, index| {
        const locations = try a.alloc(Location, function.scope.instructions.len);
        for (function.scope.instructions, locations) |instruction, *location| {
            const value = src.locate(instruction.span.start);
            location.* = .{ .path = value.path, .line = value.line, .column = value.column };
        }
        unit.* = .{ .name = function.name, .symbol = try symbol(a, function.name), .il = "", .locations = locations, .@"export" = try @import("qbe_exports.zig").describe(a, program, index, interface.roots) };
    }
    const arenas = arena_lower.present(program);
    for (program.functions, units, 0..) |function, *unit, index| {
        var emitter = Emitter{ .allocator = a, .program = program, .function = function, .units = units, .layouts = &layouts, .sink = sink, .output = .init(a), .arenas = arenas };
        unit.il = try emitter.emit(unit.symbol);
        unit.test_dependencies = @import("native_test_dependencies.zig").describe(a, program, index, unit.il, &layouts, emitter.states) catch |err| return layoutError(err);
    }
    const entry_function = program.functions[@backingInt(program.main)];
    const entry_parameters = try a.alloc([]const u8, entry_function.signature.parameter_count);
    for (entry_parameters, entry_function.scope.locals[0..entry_parameters.len]) |*parameter, local| parameter.* = layouts.identity(local.ty) catch |err| return layoutError(err);
    const entry_argv_element = if (entry_function.signature.parameter_count != 0) entry_adapter.argvElement(entry_function.scope.locals[0].ty, program.records) else null;
    const entry_argv = if (entry_argv_element) |element| native_descriptors.symbol(a, &layouts, element) catch |err| return layoutError(err) else null;
    const descriptors = native_descriptors.generate(a, &layouts) catch |err| return layoutError(err);
    const renderers = @import("native_render.zig").generate(a, &layouts, program) catch |err| return layoutError(err);
    // A program that never prints carries no renderers, and copies nothing.
    const runtime_data = if (renderers.len == 0) descriptors else try std.mem.concat(a, u8, &.{ descriptors, renderers });
    const wire_types = @import("qbe_wire.zig").describe(a, &layouts) catch |err| return layoutError(err);
    const codecs = @import("qbe_codecs.zig").describe(a, program, &layouts) catch |err| return layoutError(err);
    var text_format = false;
    for (program.functions) |function| for (function.scope.instructions) |instruction| {
        if (needsTextRuntime(program, instruction.op)) text_format = true;
    };
    const host = @import("qbe_host.zig").describe(a, program, &layouts) catch |err| return layoutError(err);
    return std.json.Stringify.valueAlloc(allocator, .{
        .host = host,
        .text_format = text_format,
        .entry_parameters = entry_parameters,
        .entry_argv_element = entry_argv,
        .wire_types = wire_types,
        .codecs = codecs,
        .schema = interface.schema,
        .runtime_data = runtime_data,
        .version = "qbe-units-v1",
        .abi = "mylang-qbe-native-v3",
        .functions = units,
        .entry = units[@backingInt(program.main)].symbol,
    }, .{});
}

/// Whether one operation needs the shared Zig text runtime unit: `str(value)`
/// formatting, or the pinned `int(text)` and `float(text)` grammar.
fn needsTextRuntime(program: bytecode.Program, op: @FieldType(bytecode.Instruction, "op")) bool {
    switch (op) {
        .cast_integer => |target| return target.isAggregate() and program.records[target.recordIndex()].collection.kind == .string,
        .buffer_operation => |operation| return operation.kind == .parse_int or operation.kind == .parse_float,
        else => return false,
    }
}

fn symbol(a: std.mem.Allocator, name: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &hash, .{});
    return std.fmt.allocPrint(a, "myl_f_{s}", .{std.fmt.bytesToHex(hash, .lower)});
}
fn layoutError(err: native_types.Error) GenerateError {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
fn scalar(ty: typed.Type, records: []const typed.Record) bool {
    // An open file and a capability are both one opaque native word.
    const authority = ty.capabilityIndex() != null or ty.isFile();
    if (ty.isInteger() or ty == .bool or ty == .unit or authority) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.managed or record.contract.callback != null or ownedPointer(record)) return true;
    return if (record.shape.domain) |backing| scalar(backing, records) else false;
}

fn ownedPointer(record: typed.Record) bool {
    return record.shape.buffer != null or record.shape.resource != null;
}

const Emitter = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    function: bytecode.Function,
    units: []const Unit,
    sink: *diagnostic.Sink,
    layouts: *native_types.Catalog,
    pc: usize = 0,
    has_roots: bool = false,
    heap_frame: bool = false,
    arenas: bool = false,
    frame_offset: u64 = 0,
    output: std.Io.Writer.Allocating,
    states: []?[]const typed.Type = &.{},
    serial: usize = 0,

    /// Shared lowering primitive for target operation emitters.
    pub fn reject(self: *Emitter, pc: usize) GenerateError {
        const span = if (self.function.scope.instructions.len > pc) self.function.scope.instructions[pc].span else @import("source.zig").Span{ .start = 0, .end = 0 };
        return self.sink.fail("E_QBE_UNSUPPORTED", span, "this operation or signature is not supported by the native QBE lowering");
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn print(self: *Emitter, comptime fmt: []const u8, args: anytype) GenerateError!void {
        self.output.writer.print(fmt, args) catch return error.OutOfMemory;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn temp(self: *Emitter) usize {
        const id = self.serial;
        self.serial += 1;
        return id;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn load(self: *Emitter, comptime kind: []const u8, slot: usize) GenerateError!usize {
        const id = self.temp();
        try self.print(" %v{d} =l loadl %{s}{d}\n", .{ id, kind, slot });
        return id;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn store(self: *Emitter, slot: usize, id: usize) GenerateError!void {
        try self.print(" storel %v{d}, %s{d}\n", .{ id, slot });
    }
    fn emit(self: *Emitter, name: []const u8) GenerateError![]const u8 {
        const f = self.function;
        if (f.policy.c_abi) return @import("qbe_c_abi.zig").emit(self, name);
        if (f.policy.host != null) return @import("qbe_host_lower.zig").emit(self, name);
        if (!try self.supported(f.signature.return_type)) return self.reject(0);
        for (f.scope.locals) |local| if (!try self.supported(local.ty)) return self.reject(0);
        const ir = @import("native_ir.zig").analyze(self.allocator, self.program, f) catch |err| switch (err) {
            error.UnsupportedOperation => return self.reject(0),
            error.InternalError => return error.InternalError,
            error.OutOfMemory => return error.OutOfMemory,
        };
        self.states = ir.states;
        try self.findRoots();
        const capacity = ir.stack_capacity;
        const frame_bytes = try self.frameBytes(capacity);
        self.heap_frame = frame_bytes > 32768;
        const stack_bytes = if (self.heap_frame) try self.abiStackBytes() else frame_bytes;
        if (stack_bytes > 32768) return self.sink.fail("E_QBE_UNSUPPORTED", f.scope.instructions[0].span, "native ABI arguments or results exceed the 32 KiB stack safety limit");
        try self.typeDefinitions();
        try self.print("export function {s} ${s}(l %ctx", .{ try self.returnType(f), name });
        if (try self.largeResult(f)) try self.print(", l %out", .{});
        if (try self.packedParameters(f)) {
            try self.print(", l %packed", .{});
        } else {
            for (f.scope.locals[0..f.signature.parameter_count], 0..) |local, i| try self.print(", {s} %a{d}", .{ try self.parameterType(local), i });
        }
        try self.print(") {{\n@entry\n", .{});
        const return_bytes = try self.returnStorageBytes();
        if (return_bytes != 0) {
            try self.print(" %empty =l alloc8 {d}\n call $memset(l %empty, w 0, l {d})\n", .{ @max(8, return_bytes), @max(8, return_bytes) });
            if (self.heap_frame) try self.print(" %return_storage =l alloc8 {d}\n", .{@max(8, return_bytes)});
        }
        try self.print(" call $myl_qbe_enter_at_sized(l %ctx, l extern ${s}_meta, l {d})\n", .{ name, stack_bytes });
        try self.checkFailure("entry_failure");
        try arena_lower.Lower(Emitter).mark(self);
        if (self.heap_frame) {
            try self.print(" %frame_memory =l call $myl_qbe_frame_allocate(l %ctx, l {d})\n", .{frame_bytes});
            try self.checkFailure("allocation_failure");
        }
        try self.initializeStorage(capacity);
        if (self.has_roots) try self.print(" %heap =l call $myl_qbe_heap(l %ctx)\n %root_mark =l call $myl_qbe_root_mark(l %ctx)\n", .{});
        try self.print(" %maxsteps =l add %ctx, 16\n %active =l add %ctx, 48\n %frame =l loadl %active\n %position =l add %frame, 8\n jmp @i0\n", .{});
        try self.emitInstructions();
        try self.print("@step_limit\n call $myl_qbe_fail_step(l %ctx)\n jmp @failure\n@failure\n", .{});
        try arena_lower.Lower(Emitter).restore(self);
        if (self.has_roots) try self.print(" call $myl_qbe_root_restore(l %ctx, l %root_mark)\n", .{});
        if (self.heap_frame) try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n jmp @allocation_failure\n@allocation_failure\n", .{});
        try self.print(" call $myl_qbe_leave(l %ctx)\n@entry_failure\n ret {s}\n}}\n", .{if (return_bytes == 0) "0" else "%empty"});
        return self.output.toOwnedSlice();
    }
    fn findRoots(self: *Emitter) GenerateError!void {
        const f = self.function;
        for (f.scope.locals) |local| self.has_roots = self.has_roots or (try self.layout(local.ty)).trace;
        for (self.states) |state| if (state) |stack| {
            for (stack) |ty| self.has_roots = self.has_roots or (try self.layout(ty)).trace;
        };
    }
    fn initializeStorage(self: *Emitter, capacity: usize) GenerateError!void {
        const f = self.function;
        try self.allocateSlot("scratch", 16);
        try self.allocateSlot("arguments", try self.argumentVectorBytes());
        for (f.scope.locals, 0..) |local, i| try self.allocateIndex("l", i, @max(8, (try self.layout(local.ty)).size));
        for (self.states, 0..) |state, pc| if (state != null and self.usesTemporary(pc)) {
            const size = try self.temporarySize(pc);
            try self.allocateIndex("agg", pc, size);
            try self.allocateIndex("aux", pc, size);
        };
        for (0..capacity) |i| try self.allocateIndex("s", i, 8);
        if (self.has_roots) for (0..f.scope.locals.len + capacity) |i| try self.allocateIndex("root", i, 24);
        for (f.scope.locals, 0..) |local, i| {
            if ((try self.layout(local.ty)).trace) try self.print(zero_local, .{ i, @max(8, (try self.layout(local.ty)).size) });
        }
        const packed_args = try self.packedParameters(f);
        for (f.scope.locals[0..f.signature.parameter_count], 0..) |local, i| {
            if (packed_args) try self.unpackArgument(i);
            if (scalar(local.ty, self.program.records)) try self.print(" storel %a{d}, %l{d}\n", .{ i, i }) else try self.print(" blit %a{d}, %l{d}, {d}\n", .{ i, i, (try self.layout(local.ty)).size });
        }
    }
    fn emitInstructions(self: *Emitter) GenerateError!void {
        const f = self.function;
        for (f.scope.instructions, 0..) |instruction, pc| {
            const stack = self.states[pc] orelse continue;
            try self.print("@i{d}\n storel {d}, %position\n", .{ pc, pc });
            try self.step();
            self.pc = pc;
            const safepoint = self.has_roots and allocates(instruction.op);
            if (safepoint) try self.roots(stack);
            try self.emitOp(instruction.op, stack);
            if (safepoint) try self.print(" call $myl_qbe_root_restore(l %ctx, l %root_mark)\n", .{});
            switch (instruction.op) {
                .binary_integer => |operation| {
                    if (operation.ty.integer()) |integer| {
                        if (scalar_lower.select(operation.op, integer.signed) == null and operation.op != .add and operation.op != .sub and @backingInt(operation.op) < @backingInt(typed.BinaryOp.f64_add)) try self.checkFailure("failure");
                    }
                },
                .call,
                .invoke,
                .acquire_buffer,
                .buffer_operation,
                .external_read,
                .environment_get,
                .acquire_resource,
                .complete_resource,
                .resource_io,
                .restrict_resource,
                .mul_i64_checked,
                .div_i64_checked,
                .rem_i64_checked,
                .cast_integer,
                .neg_integer,
                .neg_i64_checked,
                .unary_float,
                => try self.checkFailure("failure"),
                else => {},
            }
            switch (instruction.op) {
                .ret, .jump, .jump_if_false, .switch_variant => {},
                else => try self.print(" jmp @i{d}\n", .{pc + 1}),
            }
            if (instruction.op == .jump_if_false) try self.print("@next{d}\n jmp @i{d}\n", .{ self.serial, pc + 1 });
        }
    }
    fn allocates(op: @FieldType(bytecode.Instruction, "op")) bool {
        return switch (op) {
            .cast_integer,
            .call,
            .invoke,
            .acquire_buffer,
            .buffer_operation,
            .make_record,
            .get_index,
            .binary_integer,
            .acquire_resource,
            .complete_resource,
            .resource_io,
            .file_access,
            .file_method,
            => true,
            else => false,
        };
    }
    fn allocateIndex(self: *Emitter, kind: []const u8, index: usize, size: u64) GenerateError!void {
        try self.allocateSlot(try std.fmt.allocPrint(self.allocator, "{s}{d}", .{ kind, index }), size);
    }
    fn allocateSlot(self: *Emitter, name: []const u8, size: u64) GenerateError!void {
        if (self.heap_frame) {
            try self.print(" %{s} =l add %frame_memory, {d}\n", .{ name, self.frame_offset });
            self.frame_offset = try addFrame(self.frame_offset, size);
        } else try self.print(" %{s} =l alloc8 {d}\n", .{ name, @max(8, size) });
    }
    /// Return a value after releasing heap-backed execution storage safely.
    pub fn returnValue(self: *Emitter, value: usize) GenerateError!void {
        try self.cleanupLocals();
        try arena_lower.Lower(Emitter).restore(self);
        var output = value;
        const indirect = try self.largeResult(self.function);
        if (indirect) {
            try self.print(" blit %v{d}, %out, {d}\n", .{ value, (try self.layout(self.function.signature.return_type)).size });
            output = self.temp();
            try self.print(" %v{d} =l copy 0\n", .{output});
        }
        if (self.heap_frame) {
            const bytes = try self.returnStorageBytes();
            if (bytes != 0) {
                try self.print(" blit %v{d}, %return_storage, {d}\n", .{ value, bytes });
                output = self.temp();
                try self.print(" %v{d} =l copy %return_storage\n", .{output});
            }
            try self.print(" call $myl_qbe_frame_release(l %ctx, l %frame_memory)\n", .{});
        }
        try self.print(" call $myl_qbe_leave(l %ctx)\n ret %v{d}\n", .{output});
    }
    fn dropOperand(self: *Emitter, slot: usize, ty: typed.Type) GenerateError!void {
        if (!(try self.layout(ty)).drop) return;
        if (self.isScalar(ty)) {
            try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %s{d})\n", .{ try self.descriptor(ty), slot });
        } else {
            try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(ty), try self.load("s", slot) });
        }
    }
    fn cleanupLocals(self: *Emitter) GenerateError!void {
        var index = self.function.scope.locals.len;
        while (index > 0) {
            index -= 1;
            const local = self.function.scope.locals[index];
            if (!(try self.layout(local.ty)).drop) continue;
            try self.print(drop_local, .{ try self.descriptor(local.ty), index });
        }
    }
    fn returnStorageBytes(self: *Emitter) GenerateError!u64 {
        const f = self.function;
        if (self.isScalar(f.signature.return_type) or try self.largeResult(f)) return 0;
        return @max(8, (try self.layout(f.signature.return_type)).size);
    }
    fn valueStackBytes(self: *Emitter, ty: typed.Type) GenerateError!u64 {
        if (self.isScalar(ty) or try self.largeValue(ty)) return 8;
        return addFrame(0, @max(8, (try self.layout(ty)).size));
    }
    fn parameterStackBytes(self: *Emitter, local: typed.Local) GenerateError!u64 {
        return self.valueStackBytes(local.ty);
    }
    /// Wide signatures pass normalized scalar words and aggregate pointers in one vector.
    pub fn packedParameters(self: *Emitter, function: bytecode.Function) GenerateError!bool {
        if (function.signature.parameter_count > 128) return true;
        var bytes: u64 = 0;
        for (function.scope.locals[0..function.signature.parameter_count]) |local| bytes = try addFrame(bytes, try self.parameterStackBytes(local));
        return bytes > 4096;
    }
    fn packedCallback(self: *Emitter, signature: typed.Callable) GenerateError!bool {
        if (signature.parameters.len > 128) return true;
        var bytes: u64 = 0;
        for (signature.parameters) |ty| bytes = try addFrame(bytes, try self.valueStackBytes(ty));
        return bytes > 4096;
    }
    /// Read one packed ABI parameter immediately before snapshotting its local value.
    pub fn unpackArgument(self: *Emitter, i: usize) GenerateError!void {
        const pointer = self.temp();
        try self.print(" %v{d} =l add %packed, {d}\n %a{d} =l loadl %v{d}\n", .{ pointer, i * 8, i, pointer });
    }
    fn packArgument(self: *Emitter, i: usize, value: usize) GenerateError!void {
        const pointer = self.temp();
        try self.print(" %v{d} =l add %arguments, {d}\n storel %v{d}, %v{d}\n", .{ pointer, i * 8, value, pointer });
    }
    fn argumentVectorBytes(self: *Emitter) GenerateError!u64 {
        var count: usize = 0;
        for (self.function.scope.instructions) |instruction| {
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                else => null,
            };
            if (target) |id| {
                const f = self.program.functions[@backingInt(id)];
                if (try self.packedParameters(f)) count = @max(count, f.signature.parameter_count);
            }
            if (instruction.op == .invoke) {
                const sig = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
                if (try self.packedCallback(sig)) count = @max(count, sig.parameters.len);
            }
        }
        return @max(8, @as(u64, count) * 8);
    }
    fn resultStackBytes(self: *Emitter, function: bytecode.Function) GenerateError!u64 {
        return self.valueStackBytes(function.signature.return_type);
    }
    fn abiStackBytes(self: *Emitter) GenerateError!u64 {
        // Bounded scalar spill reserve plus exact native argument and result copies.
        var incoming: u64 = 4096;
        if (try self.packedParameters(self.function)) {
            incoming += 8;
        } else {
            for (self.function.scope.locals[0..self.function.signature.parameter_count]) |local| incoming = try addFrame(incoming, try self.parameterStackBytes(local));
        }
        incoming = try addFrame(incoming, (try self.resultStackBytes(self.function)) * 2);
        var outgoing: u64 = 0;
        for (self.function.scope.instructions) |instruction| {
            var bytes: u64 = 0;
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                else => null,
            };
            if (target) |id| {
                const function = self.program.functions[@backingInt(id)];
                if (try self.packedParameters(function)) {
                    bytes = 8;
                } else {
                    for (function.scope.locals[0..function.signature.parameter_count]) |local| bytes = try addFrame(bytes, try self.parameterStackBytes(local));
                }
                bytes = try addFrame(bytes, try self.resultStackBytes(function));
            }
            if (instruction.op == .invoke) {
                const signature = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
                if (try self.packedCallback(signature)) {
                    bytes = 8;
                } else {
                    for (signature.parameters) |ty| bytes = try addFrame(bytes, try self.valueStackBytes(ty));
                }
                bytes = try addFrame(bytes, if (try self.largeValue(signature.return_type)) 8 else (try self.layout(signature.return_type)).size);
            }
            outgoing = @max(outgoing, bytes);
        }
        return addFrame(incoming, outgoing);
    }
    fn usesTemporary(self: *Emitter, pc: usize) bool {
        return switch (self.function.scope.instructions[pc].op) {
            .make_record,
            .make_variant,
            .get_field,
            .update_record,
            .replace_index,
            .get_index,
            .arena_escape,
            .try_result,
            .acquire_buffer,
            .buffer_operation,
            .external_read,
            .environment_get,
            .acquire_resource,
            .complete_resource,
            .resource_io,
            .file_access,
            => true,
            .load_local, .move_local => |slot| !self.isScalar(self.function.scope.locals[@backingInt(slot)].ty),
            .call => |id| self.largeResult(self.program.functions[@backingInt(id)]) catch false,
            .invoke => |ty| self.largeValue(self.program.records[ty.recordIndex()].contract.callback.?.return_type) catch false,
            else => false,
        };
    }
    fn temporarySize(self: *Emitter, pc: usize) GenerateError!u64 {
        var size: u64 = 8;
        const op = self.function.scope.instructions[pc].op;
        if (op == .try_result) size = @max(size, (try self.layout(op.try_result.output)).size);
        if (self.states[pc]) |stack| for (stack) |ty| {
            size = @max(size, (try self.layout(ty)).size);
        };
        if (pc + 1 < self.states.len) if (self.states[pc + 1]) |stack| {
            for (stack) |ty| size = @max(size, (try self.layout(ty)).size);
        };
        return size;
    }
    fn frameBytes(self: *Emitter, capacity: usize) GenerateError!u64 {
        var size: u64 = (try self.argumentVectorBytes()) + 64 + @as(u64, capacity) * 8;
        for (self.function.scope.locals) |local| size = try addFrame(size, @max(8, (try self.layout(local.ty)).size));
        for (self.states, 0..) |state, pc| if (state != null and self.usesTemporary(pc)) {
            const temporary = try self.temporarySize(pc);
            size = try addFrame(size, temporary);
            size = try addFrame(size, temporary);
        };
        if (self.has_roots) size = try addFrame(size, @as(u64, self.function.scope.locals.len + capacity) * 24);
        size = try addFrame(size, @max(16, (try self.layout(self.function.signature.return_type)).size));
        var outgoing: u64 = 0;
        for (self.function.scope.instructions) |instruction| {
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                else => null,
            };
            if (instruction.op == .invoke) {
                const signature = self.program.records[instruction.op.invoke.recordIndex()].contract.callback.?;
                var arguments: u64 = 0;
                for (signature.parameters) |ty| arguments = try addFrame(arguments, @max(8, (try self.layout(ty)).size));
                outgoing = @max(outgoing, arguments);
            }
            if (target) |id| {
                const callee = self.program.functions[@backingInt(id)];
                var arguments: u64 = 0;
                for (callee.scope.locals[0..callee.signature.parameter_count]) |local| arguments = try addFrame(arguments, @max(8, (try self.layout(local.ty)).size));
                outgoing = @max(outgoing, arguments);
            }
        }
        return std.math.mul(u64, try addFrame(size, outgoing), 2) catch error.InternalError;
    }
    fn addFrame(left: u64, right: u64) GenerateError!u64 {
        const aligned = std.math.add(u64, right, 7) catch return error.InternalError;
        return std.math.add(u64, left, aligned & ~@as(u64, 7)) catch error.InternalError;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn layout(self: *Emitter, ty: typed.Type) GenerateError!native_types.Layout {
        return self.layouts.layout(ty) catch |err| return layoutError(err);
    }
    /// Whether the native value is represented in one scalar register.
    pub fn isScalar(self: *Emitter, ty: typed.Type) bool {
        return scalar(ty, self.program.records);
    }
    fn supported(self: *Emitter, ty: typed.Type) GenerateError!bool {
        if (ty.isAggregate() and self.program.records[ty.recordIndex()].managed) return true;
        if (scalar(ty, self.program.records)) return true;
        const value = try self.layout(ty);
        return value.kind == .record or value.kind == .array or value.kind == .variant or value.kind == .domain;
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn abiType(self: *Emitter, ty: typed.Type) GenerateError![]const u8 {
        if (scalar(ty, self.program.records)) return "l";
        return std.fmt.allocPrint(self.allocator, ":t{s}", .{std.fmt.bytesToHex((try self.layout(ty)).hash, .lower)});
    }
    /// Large native values cross function boundaries through caller-owned storage.
    pub fn largeValue(self: *Emitter, ty: typed.Type) GenerateError!bool {
        return !self.isScalar(ty) and (try self.layout(ty)).size > 4096;
    }
    /// Large native values cross function boundaries through caller-owned storage.
    pub fn largeResult(self: *Emitter, function: bytecode.Function) GenerateError!bool {
        return self.largeValue(function.signature.return_type);
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn parameterType(self: *Emitter, local: typed.Local) GenerateError![]const u8 {
        return if (try self.largeValue(local.ty)) "l" else self.abiType(local.ty);
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn returnType(self: *Emitter, function: bytecode.Function) GenerateError![]const u8 {
        return if (try self.largeValue(function.signature.return_type)) "l" else self.abiType(function.signature.return_type);
    }
    /// Shared ABI lowering for guest and trusted host wrappers.
    pub fn typeDefinitions(self: *Emitter) GenerateError!void {
        try self.print("type :myl_slice = {{ l, l }}\n", .{});
        var seen: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
        defer seen.deinit(self.allocator);
        try seen.put(self.allocator, self.function.signature.return_type, {});
        for (self.function.scope.locals) |local| try seen.put(self.allocator, local.ty, {});
        for (self.states) |state| if (state) |stack| {
            for (stack) |ty| try seen.put(self.allocator, ty, {});
        };
        // Iterate sorted stable names so catalog insertion order never affects bytes.
        var names: std.ArrayList([]const u8) = .empty;
        var it = seen.keyIterator();
        while (it.next()) |ty| if (!scalar(ty.*, self.program.records)) {
            const value = try self.layout(ty.*);
            try names.append(self.allocator, try std.fmt.allocPrint(self.allocator, "type {s} = align {d} {{ b {d} }}\n", .{ try self.abiType(ty.*), value.alignment, @max(1, value.size) }));
        };
        std.mem.sort([]const u8, names.items, {}, struct {
            fn less(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.less);
        for (names.items) |line| try self.print("{s}", .{line});
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn descriptor(self: *Emitter, ty: typed.Type) GenerateError![]const u8 {
        return native_descriptors.symbol(self.allocator, self.layouts, ty) catch |err| return layoutError(err);
    }
    fn roots(self: *Emitter, stack: []const typed.Type) GenerateError!void {
        var count: usize = 0;
        for (self.function.scope.locals, 0..) |local, i| if ((try self.layout(local.ty)).trace) {
            try self.print(" call $myl_native_root_push(l %heap, l %root{d}, l %l{d}, l extern ${s})\n", .{ count, i, try self.descriptor(local.ty) });
            count += 1;
        };
        for (stack, 0..) |ty, i| if ((try self.layout(ty)).trace) {
            if (scalar(ty, self.program.records)) {
                try self.print(" call $myl_native_root_push(l %heap, l %root{d}, l %s{d}, l extern ${s})\n", .{ count, i, try self.descriptor(ty) });
            } else {
                const pointer = try self.load("s", i);
                try self.print(" call $myl_native_root_push(l %heap, l %root{d}, l %v{d}, l extern ${s})\n", .{ count, pointer, try self.descriptor(ty) });
            }
            count += 1;
        };
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn require(self: *Emitter, value: usize, failure: []const u8) GenerateError!void {
        const label = self.temp();
        try self.print(" jnz %v{d}, @success{d}, @failed{d}\n@failed{d}\n call ${s}(l %ctx)\n jmp @failure\n@success{d}\n", .{ value, label, label, label, failure, label });
    }
    fn step(self: *Emitter) GenerateError!void {
        const used = self.temp();
        const maximum = self.temp();
        const exhausted = self.temp();
        const next = self.temp();
        try self.print(" %v{d} =l loadl %ctx\n %v{d} =l loadl %maxsteps\n", .{ used, maximum });
        try self.print(" %v{d} =l ceql %v{d}, %v{d}\n jnz %v{d}, @step_limit, @step{d}\n@step{d}\n", .{ exhausted, used, maximum, exhausted, next, next });
        try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %ctx\n", .{ next, used, next });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn checkFailure(self: *Emitter, target: []const u8) GenerateError!void {
        const failed = self.temp();
        try self.print(" %v{d} =l call $myl_qbe_failed(l %ctx)\n jnz %v{d}, @{s}, @ok{d}\n@ok{d}\n", .{ failed, failed, target, failed, failed });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn address(self: *Emitter, base: usize, offset: u64) GenerateError!usize {
        const result = self.temp();
        try self.print(" %v{d} =l add %v{d}, {d}\n", .{ result, base, offset });
        return result;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn readValue(self: *Emitter, pointer: usize, ty: typed.Type) GenerateError!usize {
        if (!scalar(ty, self.program.records)) return pointer;
        const result = self.temp();
        var backing = ty;
        while (backing.isAggregate()) {
            const record = self.program.records[backing.recordIndex()];
            if (record.managed or record.contract.callback != null or ownedPointer(record)) {
                backing = .u64;
                break;
            }
            backing = record.shape.domain.?;
        }
        const load_op: []const u8 = if (backing.integer()) |info| switch (info.bits) {
            8 => if (info.signed) "loadsb" else "loadub",
            16 => if (info.signed) "loadsh" else "loaduh",
            32 => if (info.signed) "loadsw" else "loaduw",
            else => "loadl",
        } else if (backing == .bool) "loadub" else "loadl";
        if (backing == .unit) try self.print(" %v{d} =l copy 0\n", .{result}) else try self.print(" %v{d} =l {s} %v{d}\n", .{ result, load_op, pointer });
        return result;
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn writeValue(self: *Emitter, pointer: usize, value: usize, ty: typed.Type) GenerateError!void {
        const size = (try self.layout(ty)).size;
        if (size == 0) return;
        if (!scalar(ty, self.program.records)) {
            try self.print(" blit %v{d}, %v{d}, {d}\n", .{ value, pointer, size });
            return;
        }
        const op: []const u8 = switch (size) {
            1 => "storeb",
            2 => "storeh",
            4 => "storew",
            else => "storel",
        };
        try self.print(" {s} %v{d}, %v{d}\n", .{ op, value, pointer });
    }
    /// Shared lowering primitive for target operation emitters.
    pub fn aggregatePointer(self: *Emitter) GenerateError!usize {
        const pointer = self.temp();
        try self.print(" %v{d} =l copy %agg{d}\n", .{ pointer, self.pc });
        return pointer;
    }
    /// Resolve a field to its native offset and exact type.
    pub fn field(self: *Emitter, ty: typed.Type, index: usize) GenerateError!native_types.Field {
        if (self.program.records[ty.recordIndex()].isCell()) {
            const body = self.layouts.heapLayout(ty) catch |err| return layoutError(err);
            defer self.layouts.releaseLayout(body);
            return body.fields[index];
        }
        const value = try self.layout(ty);
        if (value.kind == .array) return .{ .offset = value.stride * index, .ty = value.fields[0].ty };
        return value.fields[index];
    }
    fn enumComparison(self: *Emitter, predicate_value: bytecode.Equality, height: usize) GenerateError!void {
        const right = try self.load("s", height - 1);
        const left = try self.load("s", height - 2);
        const a = self.temp();
        const b = self.temp();
        const result = self.temp();
        try self.print(" %v{d} =l loaduw %v{d}\n %v{d} =l loaduw %v{d}\n", .{ a, left, b, right });
        try self.print(" %v{d} =l {s} %v{d}, %v{d}\n", .{ result, if (predicate_value == .eq) "ceql" else "cnel", a, b });
        try self.store(height - 2, result);
    }
    fn invoke(self: *Emitter, callback_type: typed.Type, stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        const signature = self.program.records[callback_type.recordIndex()].contract.callback.?;
        const base = h - signature.valueCount() - 1;
        const function_pointer = try self.load("s", base);
        const args = try self.allocator.alloc(usize, signature.parameters.len);
        const packed_args = try self.packedCallback(signature);
        for (args, 0..) |*arg, i| {
            arg.* = try self.load("s", base + 1 + i);
            if (packed_args) try self.packArgument(i, arg.*);
        }
        const value = self.temp();
        const indirect = try self.largeValue(signature.return_type);
        try self.print(" %v{d} ={s} call %v{d}(l %ctx", .{ value, if (indirect) "l" else try self.abiType(signature.return_type), function_pointer });
        if (indirect) try self.print(", l %aux{d}", .{self.pc});
        if (packed_args) {
            try self.print(", l %arguments", .{});
        } else {
            for (args, signature.parameters) |arg, ty| try self.print(", {s} %v{d}", .{ if (try self.largeValue(ty)) "l" else try self.abiType(ty), arg });
        }
        try self.print(")\n", .{});
        if (indirect) try self.print(" storel %aux{d}, %s{d}\n", .{ self.pc, base }) else try self.store(base, value);
    }
    fn acquireBuffer(self: *Emitter, ty: typed.Type, stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        const schema = self.program.records[ty.recordIndex()];
        if (!schema.managed or schema.collection.kind != .list) return self.reject(self.pc);
        const capacity = try self.load("s", h - 1);
        if (stack[h - 1].integer().?.signed) {
            const valid = self.temp();
            try self.print(" %v{d} =l csgel %v{d}, 0\n", .{ valid, capacity });
            try self.require(valid, "myl_qbe_fail_list_capacity");
        }
        const value = self.temp();
        try self.print(" %v{d} =l call $myl_native_list_new(l %heap, l extern ${s}, l %v{d})\n", .{ value, try self.descriptor(schema.shape.buffer.?), capacity });
        try self.require(value, "myl_qbe_fail_allocation");
        try self.store(h - 1, value);
    }
    fn emitCall(self: *Emitter, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        const target = op.call;
        const callee = self.program.functions[@backingInt(target)];
        const count = bytecode.valueParameterCount(callee);
        const args = try self.allocator.alloc(usize, callee.signature.parameter_count);
        const packed_args = try self.packedParameters(callee);
        for (args, 0..) |*arg, i| {
            arg.* = try self.load("s", h - count + i);
            if (packed_args) try self.packArgument(i, arg.*);
        }
        const v = self.temp();
        try self.print(" %v{d} ={s} call ${s}(l %ctx", .{ v, try self.returnType(callee), self.units[@backingInt(target)].symbol });
        const indirect = try self.largeResult(callee);
        if (indirect) try self.print(", l %aux{d}", .{self.pc});
        if (packed_args) {
            try self.print(", l %arguments", .{});
        } else {
            for (args, callee.scope.locals[0..callee.signature.parameter_count]) |arg, local| try self.print(", {s} %v{d}", .{ try self.parameterType(local), arg });
        }
        try self.print(")\n", .{});
        if (indirect) try self.print(" storel %aux{d}, %s{d}\n", .{ self.pc, h - count }) else try self.store(h - count, v);
    }
    fn emitOp(self: *Emitter, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) GenerateError!void {
        const h = stack.len;
        switch (op) {
            .acquire_resource, .complete_resource, .resource_io, .restrict_resource => try @import("qbe_resources.zig").Lower(Emitter).emit(self, op, stack),
            .external_read, .environment_get => try @import("qbe_boundaries.zig").emit(self, op, stack),
            .begin_arena, .end_arena, .arena_escape => try arena_lower.Lower(Emitter).emit(self, op, stack),
            .print => |output| try @import("qbe_io.zig").Lower(Emitter).emit(self, output, stack),
            .file_access => |call| try @import("qbe_files.zig").Lower(Emitter).access(self, call, stack),
            .file_method => |call| try @import("qbe_files.zig").Lower(Emitter).method(self, call, stack),
            .try_result => |propagate| {
                const source = try self.load("s", h - 1);
                const input_offset = (try self.layout(propagate.input)).payload_offset;
                if (typed.resultShape(propagate.input, self.program.records)) |input| {
                    const output = typed.resultShape(propagate.output, self.program.records).?;
                    const tag = self.temp();
                    const success = self.temp();
                    try self.print(" %v{d} =l loaduw %v{d}\n %v{d} =l ceql %v{d}, {d}\n", .{ tag, source, success, tag, input.ok_tag });
                    try self.print(" jnz %v{d}, @tryok{d}, @tryerror{d}\n@tryerror{d}\n", .{ success, tag, tag, tag });
                    const pointer = try self.aggregatePointer();
                    try self.print(" storew {d}, %v{d}\n", .{ output.error_tag, pointer });
                    const payload = try self.readValue(try self.address(source, input_offset), input.error_type);
                    try self.writeValue(try self.address(pointer, (try self.layout(propagate.output)).payload_offset), payload, output.error_type);
                    for (stack[0 .. h - 1], 0..) |ty, slot| try self.dropOperand(slot, ty);
                    try self.store(0, pointer);
                    try self.print(" jmp @i{d}\n@tryok{d}\n", .{ propagate.error_target, tag });
                    try self.store(h - 1, try self.readValue(try self.address(source, input_offset), input.ok_type));
                } else if (prelude.optionShape(propagate.input, self.program.records)) |input| {
                    const output = prelude.optionShape(propagate.output, self.program.records).?;
                    const tag = self.temp();
                    const success = self.temp();
                    try self.print(" %v{d} =l loaduw %v{d}\n %v{d} =l ceql %v{d}, {d}\n", .{ tag, source, success, tag, input.some });
                    try self.print(" jnz %v{d}, @tryok{d}, @tryerror{d}\n@tryerror{d}\n", .{ success, tag, tag, tag });
                    const pointer = try self.aggregatePointer();
                    try self.print(" storew {d}, %v{d}\n", .{ output.none, pointer });
                    for (stack[0 .. h - 1], 0..) |ty, slot| try self.dropOperand(slot, ty);
                    try self.store(0, pointer);
                    try self.print(" jmp @i{d}\n@tryok{d}\n", .{ propagate.error_target, tag });
                    try self.store(h - 1, try self.readValue(try self.address(source, input_offset), input.element));
                } else return error.InternalError;
            },
            .function_value => |value| try self.print(" storel extern ${s}, %s{d}\n", .{ self.units[@backingInt(value.function)].symbol, h }),
            .invoke => |callback_type| try self.invoke(callback_type, stack),
            .acquire_buffer => |ty| try self.acquireBuffer(ty, stack),
            .buffer_operation => |operation| try managed_lower.Lower(Emitter).operation(self, operation, stack),
            .push_i64 => |v| try self.print(store_scalar, .{ v, h }),
            .push_integer => |v| try self.print(store_scalar, .{ v.value, h }),
            .push_bool => |v| try self.print(store_scalar, .{ @intFromBool(v), h }),
            .push_unit => try self.print(" storel 0, %s{d}\n", .{h}),
            .make_record, .get_field, .update_record, .array_length, .get_index, .replace_index, .make_variant, .switch_variant => try @import("qbe_aggregate.zig").emit(self, op, stack),
            .load_local, .move_local => |slot| {
                const ty = self.function.scope.locals[@backingInt(slot)].ty;
                if (scalar(ty, self.program.records)) try self.store(h, try self.load("l", @backingInt(slot))) else {
                    try self.print(" blit %l{d}, %agg{d}, {d}\n storel %agg{d}, %s{d}\n", .{ @backingInt(slot), self.pc, (try self.layout(ty)).size, self.pc, h });
                }
                if (op == .move_local and (try self.layout(ty)).drop) try self.print(zero_local, .{ @backingInt(slot), @max(8, (try self.layout(ty)).size) });
            },
            .store_local => |slot| {
                const v = try self.load("s", h - 1);
                const ty = self.function.scope.locals[@backingInt(slot)].ty;
                if ((try self.layout(ty)).drop) {
                    try self.print(drop_local, .{ try self.descriptor(ty), @backingInt(slot) });
                }
                if (scalar(ty, self.program.records)) try self.print(" storel %v{d}, %l{d}\n", .{ v, @backingInt(slot) }) else try self.print(" blit %v{d}, %l{d}, {d}\n", .{ v, @backingInt(slot), (try self.layout(ty)).size });
            },
            .drop_local => |slot| {
                const ty = self.function.scope.locals[@backingInt(slot)].ty;
                if ((try self.layout(ty)).drop) {
                    try self.print(drop_local, .{ try self.descriptor(ty), @backingInt(slot) });
                } else if ((try self.layout(ty)).trace) try self.print(zero_local, .{ @backingInt(slot), @max(8, (try self.layout(ty)).size) });
            },
            .pop, .acknowledge => try self.dropOperand(h - 1, stack[h - 1]),
            .wrap_domain, .unwrap_domain => {},
            .jump => |target| try self.print(" jmp @i{d}\n", .{target}),
            .assert_true => {
                const v = try self.load("s", h - 1);
                try self.require(v, "myl_qbe_fail_assert");
            },
            .jump_if_false => |target| {
                const v = try self.load("s", h - 1);
                try self.print(" jnz %v{d}, @next{d}, @i{d}\n", .{ v, self.serial, target });
            },
            .ret => {
                const v = try self.load("s", h - 1);
                try self.returnValue(v);
            },
            .call => try self.emitCall(op, stack),
            .binary_integer => |b| {
                if (b.ty.isAggregate()) return managed_lower.Lower(Emitter).binary(self, b, stack);
                try scalar_lower.Lower(Emitter).binary(self, b.op, b.ty, h);
            },
            .add_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .add, .i64, h),
            .sub_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .sub, .i64, h),
            .mul_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .mul, .i64, h),
            .div_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .div, .i64, h),
            .rem_i64_checked => try scalar_lower.Lower(Emitter).binary(self, .rem, .i64, h),
            .cmp_i64 => |p| try scalar_lower.Lower(Emitter).binary(self, predicate(p), .i64, h),
            .cmp_bool => |p| try scalar_lower.Lower(Emitter).binary(self, if (p == .eq) .eq else .ne, .u8, h),
            .cmp_enum => |comparison| try self.enumComparison(comparison.predicate, h),
            .cmp_domain => |comparison| try scalar_lower.Lower(Emitter).binary(self, if (comparison.predicate == .eq) .eq else .ne, .u64, h),
            .not_bool => {
                const operand = try self.load("s", h - 1);
                const v = self.temp();
                try self.print(" %v{d} =l xor %v{d}, 1\n", .{ v, operand });
                try self.store(h - 1, v);
            },
            .cast_integer, .neg_integer, .neg_i64_checked => {
                const ty: typed.Type = switch (op) {
                    .cast_integer, .neg_integer => |t| t,
                    else => .i64,
                };
                if (op == .cast_integer and ty.isAggregate()) return managed_lower.Lower(Emitter).cast(self, ty, stack);
                const info = ty.integer().?;
                const operand = try self.load("s", h - 1);
                const v = self.temp();
                if (op == .cast_integer) {
                    const from = stack[h - 1].integer() orelse return error.InternalError;
                    try self.print(" %v{d} =l call $myl_qbe_int_cast(l %ctx, l {d}, l {d}, l {d}, l %v{d})\n", .{ v, @intFromBool(from.signed), @intFromBool(info.signed), info.bits, operand });
                } else try self.print(" %v{d} =l call $myl_qbe_int_neg(l %ctx, l {d}, l {d}, l %v{d})\n", .{ v, @intFromBool(info.signed), info.bits, operand });
                try self.store(h - 1, v);
            },
            .unary_float => |unary| {
                const operand = try self.load("s", h - 1);
                const v = self.temp();
                try self.print(" %v{d} =l call $myl_qbe_float_unary(l %ctx, l {d}, l %v{d})\n", .{ v, @backingInt(unary), operand });
                try self.store(h - 1, v);
            },
        }
    }
};
fn predicate(p: bytecode.Predicate) typed.BinaryOp {
    return switch (p) {
        .eq => .eq,
        .ne => .ne,
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
    };
}

comptime {
    // These ordinals are the versioned C helper protocol, not native enum layout.
    const binary_names = .{
        "add",
        "sub",
        "mul",
        "div",
        "rem",
        "floor_div",
        "floor_rem",
        "logical_and",
        "logical_or",
        "eq",
        "ne",
        "lt",
        "le",
        "gt",
        "ge",
        "bit_and",
        "bit_or",
        "bit_xor",
        "shift_left",
        "shift_right",
        "wrapping_add",
        "wrapping_sub",
        "wrapping_mul",
        "saturating_add",
        "saturating_sub",
        "saturating_mul",
        "f64_add",
        "f64_sub",
        "f64_mul",
        "f64_div",
        "f64_eq",
        "f64_lt",
        "f64_le",
    };
    for (binary_names, 0..) |name, i| if (@backingInt(@field(typed.BinaryOp, name)) != i) @compileError("QBE runtime binary ABI changed");
    const unary_names = .{ "neg", "not", "f64_sqrt", "f64_floor", "f64_ceil", "f64_trunc", "f64_abs", "f64_neg", "f64_from_u64", "f64_to_u64", "f64_from_i64", "f64_to_i64" };
    for (unary_names, 0..) |name, i| if (@backingInt(@field(typed.UnaryOp, name)) != i) @compileError("QBE runtime unary ABI changed");
}
