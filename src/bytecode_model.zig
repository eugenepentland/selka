//! Checked instruction model independent of validation and effect inference.
const external_resources = @import("external_resources.zig");
const std = @import("std");
const Span = @import("source.zig").Span;
const typed = @import("typed.zig");
/// Signed scalar ordering and equality predicates.
pub const Predicate = enum { eq, ne, lt, le, gt, ge };
/// Equality predicates for boolean and nominal identity values.
pub const Equality = enum { eq, ne };
/// Destination and optional payload local for one variant case.
pub const SwitchArm = struct { target: usize, slot: ?typed.LocalId };
/// Which inlined callee one spliced instruction came from. `callee` is the
/// directly spliced function, `callee_pc` its local program counter and
/// `call_position` the pc in the function that owns the instruction whose
/// location entry is the call site. The emitter groups consecutive instructions
/// sharing a callee and call site into one inline-frame record.
pub const InlineOrigin = struct { callee: typed.FunctionId, callee_pc: usize, call_position: usize };
/// An element read or replace: the receiver type, and whether a fixed array
/// first counts a negative index back from its end (`PY-ARRAY-NEGATIVE-1`).
/// Managed receivers normalize their own indices and ignore `from_end`.
pub const Access = struct { ty: typed.Type, from_end: bool = false };
/// Source-located operation in the checked instruction stream.
pub const Instruction = struct {
    span: Span,
    op: union(enum) {
        try_result: struct { input: typed.Type, output: typed.Type, error_target: usize },
        push_i64: i64,
        push_bool: bool,
        push_unit,
        push_integer: struct { ty: typed.Type, value: i128 },
        cast_integer: typed.Type,
        wrap_domain: typed.Type,
        make_variant: struct { ty: typed.Type, tag: usize },
        switch_variant: struct { ty: typed.Type, arms: []const SwitchArm },
        cmp_domain: struct { ty: typed.Type, predicate: Equality },
        cmp_enum: struct { ty: typed.Type, predicate: Equality },
        unwrap_domain: typed.Type,
        neg_integer: typed.Type,
        binary_integer: struct { ty: typed.Type, op: typed.BinaryOp },
        make_record: struct { ty: typed.Type, fields: usize, order: []const usize = &.{} },
        update_record: struct { ty: typed.Type, indices: []const usize },
        get_field: usize,
        get_index: Access,
        replace_index: Access,
        array_length: typed.Type,
        begin_arena: typed.LocalId,
        end_arena: typed.LocalId,
        arena_escape: typed.Type,
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: typed.LocalId, output: typed.Type },
        complete_resource: typed.Type,
        acquire_resource: struct { output: typed.Type, request: typed.Type },
        resource_io: struct { kind: external_resources.IoKind, owner: typed.LocalId, output: typed.Type, input: ?typed.Type },
        restrict_resource: struct { permissions: external_resources.Permissions, ty: typed.Type },
        dir_resource: struct { output: typed.Type, path: typed.Type },
        host_resource: struct { output: typed.Type, name: typed.Type },
        environment_get: struct { output: typed.Type, name: typed.Type },
        environment_only: struct { output: typed.Type, names: typed.Type },
        environment_names: struct { output: typed.Type },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, output: typed.Type },
        acquire_buffer: typed.Type,
        print: Print,
        stream_write: StreamWrite,
        file_access: FileAccess,
        file_method: FileMethod,
        move_local: typed.LocalId,
        drop_local: typed.LocalId,
        load_local: typed.LocalId,
        /// Push the address of a local's own storage rather than its value: the
        /// argument a `mut` fixed-array parameter receives, which the callee
        /// writes the caller's array through.
        ref_local: typed.LocalId,
        store_local: typed.LocalId,
        add_i64_checked,
        sub_i64_checked,
        mul_i64_checked,
        div_i64_checked,
        rem_i64_checked,
        neg_i64_checked,
        unary_float: typed.UnaryOp,
        cmp_i64: Predicate,
        cmp_bool: Equality,
        not_bool,
        assert_true: []const u8,
        pop,
        acknowledge: typed.Type,
        jump: usize,
        jump_if_false: usize,
        function_value: struct { ty: typed.Type, function: typed.FunctionId },
        invoke: typed.Type,
        call: typed.FunctionId,
        ret,
    },
    /// Set exactly on an instruction spliced from an inlined callee, so the
    /// native emitter can rebuild the callee's frames for a trap trace.
    inline_origin: ?InlineOrigin = null,
};
/// Whole-path file helper; operands are the capability, the path and any input.
pub const FileAccess = struct { kind: @import("file_operations.zig").Access, mode: u8, text: bool, operands: usize, output: typed.Type, shapes: typed.FileShapes };
/// Method on an open handle held in a local slot, with one optional operand.
pub const FileMethod = struct { kind: @import("file_operations.zig").Method, owner: typed.LocalId, text: bool, argument: bool, output: typed.Type, shapes: typed.FileShapes };
/// Static argument types and whether explicit `sep=`/`end=` operands follow them.
/// `stream` puts the receiver value at the stack bottom; `debug` writes to stderr.
pub const Print = struct { sink: typed.Sink = .stdout, types: []const typed.Type, separator: bool, terminator: bool, stream: bool = false, debug: bool = false };
/// `stream.write(text)`: a stream value and text operand are on the stack.
pub const StreamWrite = struct { stream: typed.Type, text: typed.Type };
/// Checked function signature, locals, and instruction body.
pub const Function = struct {
    policy: typed.FunctionPolicy = .{},
    signature: typed.FunctionSignature = .{},
    scope: FunctionScope,
    id: typed.FunctionId,
    name: []const u8,
};
/// Lowered instructions and the checked lexical local table they address.
pub const FunctionScope = struct {
    locals: []const typed.Local = &.{},
    instructions: []const Instruction,
};
/// Complete instruction program and its nominal type metadata.
pub const Program = struct { functions: []const Function, main: typed.FunctionId = @fromBackingInt(0), records: []const typed.Record = &.{} };
/// Count stack-passed value arguments.
pub fn valueParameterCount(function: Function) usize {
    return function.signature.parameter_count;
}
