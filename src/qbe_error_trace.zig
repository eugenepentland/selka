//! Error return traces (`ERROR-TRACE-1`): the recorder calls generated code makes on
//! the error path so that an `Err` reaching `main` or failing a test can say
//! where it came from.
//!
//! The trace is one process-wide `MylQbeErrorTrace` in the runtime
//! (`src/qbe_runtime.h`): an origin site, an append count and a ring of the last
//! 32 appended sites. A site is two words, the address of the recording
//! function's `_meta` table and `pc | kind << 32`; the runtime reads the path,
//! line, column, function name and — for a converting `?` — the case name out of
//! that table, so no source location enters the unit's text and no string is
//! built at run time. Every recorder call sits on a path only an `Err` takes:
//! the `Err(...)` construction itself, the error branch a runtime result or a
//! `?` already has, and — for a `return` whose value is not a literal `Ok(...)`
//! or `Err(...)` — a branch on the returned tag.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const inline_site = @import("bytecode_inline_site.zig");
/// Failures reported while emitting the trace recorder calls.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// What one recorded site did; the ordinals are the runtime's
/// `MYL_QBE_ERROR_*` kinds.
pub const Kind = enum(u64) {
    /// An `Err(...)` construction: the trace restarts here.
    created = 0,
    /// A runtime operation (a file, resource or boundary call) answered `Err`;
    /// the trace restarts here too.
    produced = 1,
    /// A `return` handed an `Err` it did not construct itself to the caller.
    returned = 2,
    /// A `?` passed the `Err` on unchanged.
    propagated = 3,
    /// A `?` wrapped the error in a case of the caller's error union.
    converted = 4,
};
/// The cold runtime recorder that restarts the trace at a new `Err`.
pub const origin_symbol = "myl_qbe_error_trace_origin";
/// The cold runtime recorder that appends one site to the trace's ring.
pub const append_symbol = "myl_qbe_error_trace_append";

/// The site word for `kind` at bytecode position `pc`.
fn siteWord(kind: Kind, pc: usize) u64 {
    return @as(u64, @intCast(pc)) | (@backingInt(kind) << 32);
}

/// The `Union.case` a converting `?` wraps its error in, the text the runtime
/// prints after "converted to"; null when the `?` at `op` converts nothing.
pub fn conversionCase(allocator: std.mem.Allocator, records: []const typed.Record, op: @FieldType(bytecode.Instruction, "op")) error{OutOfMemory}!?[]const u8 {
    if (op != .try_result) return null;
    const input = typed.resultShape(op.try_result.input, records) orelse return null;
    const output = typed.resultShape(op.try_result.output, records) orelse return null;
    if (input.error_type == output.error_type) return null;
    const tag = typed.wrappingCase(records, output.error_type, input.error_type) orelse return null;
    const record = records[output.error_type.recordIndex()];
    const cases = record.shape.variants.?.cases;
    const label = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ record.name, cases[tag].name });
    return label;
}

/// Bind the trace recorder calls to the concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Record the site of the current instruction: `created` and `produced`
        /// restart the trace at it, every other kind appends to the ring. Each
        /// is one call to a cold runtime recorder that allocates nothing.
        pub fn record(self: *E, kind: Kind) Error!void {
            const site = try inline_site.resolve(self.program, self.function, self.pc);
            const meta = self.units[@backingInt(site.function.id)].symbol;
            const recorder = if (kind == .created or kind == .produced) origin_symbol else append_symbol;
            try self.print(" call ${s}(l extern ${s}_meta, l {d})\n", .{ recorder, meta, siteWord(kind, site.pc) });
        }
        /// A new value of variant type `ty` with case `tag`: an `Err` restarts
        /// the trace at this construction, any other value records nothing.
        pub fn construction(self: *E, ty: typed.Type, tag: usize) Error!void {
            const shape = typed.resultShape(ty, self.program.records) orelse return;
            if (shape.error_tag == tag) try record(self, .created);
        }
        /// The error branch of a `?` from a result of type `input` in a function
        /// returning `output`: passed on unchanged, or wrapped in a union case.
        pub fn propagation(self: *E, input: typed.ResultShape, output: typed.ResultShape) Error!void {
            try record(self, if (input.error_type == output.error_type) .propagated else .converted);
        }
        /// The `ret` of the value at `pointer`: appends its site when the value
        /// may be an `Err` this `return` did not construct (`returnNeedsCheck`).
        pub fn returning(self: *E, pointer: usize, branch_target: bool) Error!void {
            if (!returnNeedsCheck(self.program.records, self.function, self.pc, branch_target)) return;
            try recordIfError(self, self.function.signature.return_type, pointer, .returned);
        }
        /// A spliced `ret` is a jump in its caller, but still records an error
        /// returned through a variable, call or conditional in its own function.
        pub fn inlinedReturn(self: *E, stack: []const typed.Type) Error!void {
            const instruction = self.function.scope.instructions[self.pc];
            if (instruction.op != .jump or instruction.inline_origin == null) return;
            const site = try inline_site.resolve(self.program, self.function, self.pc);
            if (site.function.scope.instructions[site.pc].op != .ret) return;
            if (!returnNeedsCheck(self.program.records, site.function, site.pc, bytecode.branchTarget(site.function.scope.instructions, site.pc))) return;
            if (stack.len == 0) return error.InternalError;
            try recordIfError(self, site.function.signature.return_type, try self.load("s", stack.len - 1), .returned);
        }
        /// Record `kind` only when the result of type `ty` at `pointer` is an
        /// `Err`: the branch a `return` of a value that may be either case takes.
        pub fn recordIfError(self: *E, ty: typed.Type, pointer: usize, kind: Kind) Error!void {
            const shape = typed.resultShape(ty, self.program.records) orelse return error.InternalError;
            const tag = try self.readTag(ty, pointer);
            const failed = self.temp();
            try self.print(" %v{d} =l ceql %v{d}, {d}\n jnz %v{d}, @errtrace{d}, @errtraced{d}\n@errtrace{d}\n", .{ failed, tag, shape.error_tag, failed, failed, failed, failed });
            try record(self, kind);
            try self.print(" jmp @errtraced{d}\n@errtraced{d}\n", .{ failed, failed });
        }
    };
}

/// Whether the `ret` at `pc` of `function` hands back a result whose case the
/// code does not already fix: not the `ret` a failing `?` jumps to (that site
/// is recorded as propagated), and not one whose only predecessor is the
/// `Ok(...)` or `Err(...)` construction of the value it returns (an `Err`
/// there already started the trace at the construction).
fn returnNeedsCheck(records: []const typed.Record, function: bytecode.Function, pc: usize, branch_target: bool) bool {
    const result_type = function.signature.return_type;
    if (typed.resultShape(result_type, records) == null) return false;
    const code = function.scope.instructions;
    for (code) |instruction| switch (instruction.op) {
        .try_result => |propagate| if (propagate.error_target == pc) return false,
        else => {},
    };
    if (branch_target or pc == 0) return true;
    return switch (code[pc - 1].op) {
        .make_variant => |variant| variant.ty != result_type,
        else => true,
    };
}
