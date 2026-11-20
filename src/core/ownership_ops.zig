//! The operation-class table of the ownership certificates (docs/design/ownership-certificates.md §3).
//!
//! Every `ir.Op` has one row: its class, which value operands it consumes by itself and the rule
//! that gives its result an ownership state. The `switch` in `row` has no `else`, so a new
//! operation fails to compile until a row names it. The table is the semantic interface between
//! the compiler and the validator: the exporter writes it into every certificate, the validator
//! reads it, and the Lean model states the same rows. It imports only `ir.zig` and `flags.zig`.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// The ownership class of an operation (the `Class` column of design §3).
pub const Class = enum {
    /// `param`: the state follows the signature.
    parameter,
    /// A literal, a function reference, `undef`, a static string.
    constant,
    /// Arithmetic over scalars.
    pure,
    /// Reads that return a scalar: lengths, tags, probes, byte loads.
    inspect,
    /// Allocates a fresh owner from scalars.
    fresh,
    /// Allocates a fresh owner that copies, slices or materializes its operand.
    copy,
    /// Reads a part of a container: a borrow of it, or a take of its slot.
    project,
    /// Borrows a span or slice of its operand.
    view,
    /// `str_char`: a fresh one-character string, or a static one.
    character,
    /// `text_frame`: the cache owner of a borrowed text.
    text_frame,
    /// `borrow`: lends owned storage without copying.
    borrow,
    /// Consumes a container and returns the updated one.
    update,
    /// Builds an aggregate from its operands.
    construct,
    /// Consumes an aggregate and transfers one part out of it.
    take,
    /// Destroys an owner.
    drop,
    /// A call: the callee's signature decides each argument and the result.
    call,
    /// Writes to a stream.
    output,
    /// Records an error-trace site.
    trace,
    /// A phi: ownership flows per incoming edge.
    join,
    /// A forwarding copy (`ir.Op.copy`): resolved away before any other class applies.
    forward,
    /// An unconditional jump.
    jump,
    /// A conditional branch on a scalar.
    branch,
    /// Returns from the function.
    @"return",
    /// Ends the path in a trap.
    trap,

    /// The spelling of the class in the certificate format.
    pub fn token(self: Class) []const u8 {
        return switch (self) {
            .parameter => "Parameter",
            .constant => "Constant",
            .pure => "Pure",
            .inspect => "Inspect",
            .fresh => "Fresh",
            .copy => "Copy",
            .project => "Project",
            .view => "View",
            .character => "Character",
            .text_frame => "TextFrame",
            .borrow => "Borrow",
            .update => "Update",
            .construct => "Construct",
            .take => "Take",
            .drop => "Drop",
            .call => "Call",
            .output => "Output",
            .trace => "Trace",
            .join => "Join",
            .forward => "Forward",
            .jump => "Jump",
            .branch => "Branch",
            .@"return" => "Return",
            .trap => "Trap",
        };
    }
};

/// Which of an operation's value operands (in `ir.Function.valueOperands` order) it consumes itself.
/// A call decides per argument from the callee's `ParameterPassing`; a phi decides per edge from its
/// own state; neither is a row of this table.
pub const Consumes = enum {
    /// Reads every operand.
    none,
    /// Consumes operand 0 (the container it updates).
    first,
    /// Consumes operands 0 and 1 (`list_push`, `record_set`: the container and the stored value).
    first_two,
    /// Consumes operand 0 and every operand from position 2 on (the stored values of the `set` forms
    /// and `dict_insert`: position 1 is an index or probe).
    first_and_tail,
    /// Consumes every operand.
    all,
};

/// How the result of an operation gets its state (design §3, Result column). A rule that yields a value
/// yields a scalar when the result type is unmanaged and holds no borrow.
pub const ResultRule = enum {
    /// The operation defines no value.
    none,
    /// A scalar, whatever the operands.
    scalar,
    /// A scalar for an unmanaged type, otherwise the immortal static block or null owner
    /// (`str_const`, `text_sentinel`, `undef`).
    immortal,
    /// From the function's signature: owned when the parameter is taken, else borrowed from the caller.
    parameter,
    /// A fresh owner (a stack list when promotion proved the list never escapes).
    fresh,
    /// Borrowed from operand `a` (or from a call's `from` sources, see §3), unless the instruction
    /// takes the slot: then the result is owned and the container is left with a hole.
    project,
    /// Borrowed from operand `a`.
    view,
    /// `text_frame`: borrowed from operand `b`, the text view the frame holds; `a`, the cache owner, only supplies the
    /// frame (`borrow_result.zig` takes `inst.b`, and a function that returns the frame states `from` the view).
    frame,
    /// An aggregate: owned, or borrowed when every managed operand is borrowed (design §3, Construct).
    construct,
    /// The callee's signature: owned, or borrowed from the arguments its `from` contract names.
    call,
    /// The phi's stated state.
    join,
    /// The state of the forwarded operand.
    forward,
};

/// One row of the table.
pub const Row = struct {
    class: Class,
    consumes: Consumes = .none,
    result: ResultRule = .scalar,
};

/// The row of `op`. The `switch` has no `else`: adding an operation to `ir.Op` is a compile error here
/// until its row exists.
pub fn row(op: ir.Op) Row {
    return switch (op) {
        .param => .{ .class = .parameter, .result = .parameter },
        .iconst, .fconst, .func_ref => .{ .class = .constant },
        .str_const, .text_sentinel, .undef => .{ .class = .constant, .result = .immortal },
        .copy => .{ .class = .forward, .result = .forward },
        .borrow => .{ .class = .borrow, .result = .view },
        .phi => .{ .class = .join, .result = .join },

        .add, .sub, .mul, .div, .rem, .floor_div, .floor_rem, .neg, .bit_and, .bit_or, .bit_xor, .not, .cmp => .{ .class = .pure },
        .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp, .int_to_float, .float_to_int, .convert => .{ .class = .pure },
        .shift_left, .shift_right, .saturating_add, .float_unary, .float_convert, .bitcast, .float_fma, .vector_select => .{ .class = .pure },

        .list_len, .str_len, .dict_len, .dict_find, .dict_entries, .dict_entry_live => .{ .class = .inspect },
        .str_width, .str_code, .union_tag, .str_parse_int, .byte_load => .{ .class = .inspect },

        .list_new, .dict_new, .buffer_new => .{ .class = .fresh, .result = .fresh },
        .list_copy, .dict_copy, .buffer_copy, .str_slice, .str_from_view, .array_from_bytes => .{ .class = .copy, .result = .fresh },

        .list_get, .list_get_field, .record_get, .union_payload, .box_get => .{ .class = .project, .result = .project },
        .dict_entry_key, .dict_entry_value, .array_get => .{ .class = .project, .result = .project },
        .list_view_of, .list_slice_view, .str_view_of, .str_slice_view, .str_slice_bytes_view => .{ .class = .view, .result = .view },
        // A frame box (O4) lends its parameter: a view of it in this call's stack slot.
        .box_frame => .{ .class = .view, .result = .view },
        // A borrowed record's frame block (RB1) lends its parameter: the caller's block, or a frame copy of the view.
        .block_frame => .{ .class = .view, .result = .view },
        .str_char => .{ .class = .character, .result = .fresh },
        .text_frame => .{ .class = .text_frame, .result = .frame },

        .list_push, .record_set => .{ .class = .update, .consumes = .first_two, .result = .fresh },
        .list_set, .list_set_field, .array_set, .dict_set_value, .dict_insert => .{ .class = .update, .consumes = .first_and_tail, .result = .fresh },
        .list_pop, .dict_remove, .dict_clear, .str_append, .str_append_char, .list_sort => .{ .class = .update, .consumes = .first, .result = .fresh },
        .buffer_set, .buffer_push, .buffer_pop, .buffer_append => .{ .class = .update, .consumes = .first, .result = .fresh },

        .record_make, .union_make, .box_make => .{ .class = .construct, .consumes = .all, .result = .construct },
        .union_take, .box_take, .record_take => .{ .class = .take, .consumes = .all, .result = .fresh },

        .drop => .{ .class = .drop, .consumes = .all, .result = .none },
        .call, .call_indirect => .{ .class = .call, .result = .call },
        .print => .{ .class = .output, .result = .none },
        .err_trace => .{ .class = .trace, .result = .none },
        .jump => .{ .class = .jump, .result = .none },
        .branch => .{ .class = .branch, .result = .none },
        .ret => .{ .class = .@"return", .consumes = .all, .result = .none },
        .@"unreachable" => .{ .class = .trap, .result = .none },
    };
}

/// The class of `op`.
pub fn classOf(op: ir.Op) Class {
    return row(op).class;
}

/// Whether the table has the instruction consume its value operand `position` (an index into
/// `ir.Function.valueOperands`). Calls and phis decide elsewhere and answer false. A `box_make` with
/// `flags.lent_box` borrows its operand: the lender still destroys it.
pub fn consumesAt(inst: ir.Inst, position: usize) bool {
    if (inst.op == .box_make and inst.data & flags.lent_box != 0) return false;
    return switch (row(inst.op).consumes) {
        .none => false,
        .first => position == 0,
        .first_two => position < 2,
        .first_and_tail => position == 0 or position >= 2,
        .all => true,
    };
}

/// Whether `op` defines a value (an operation of `ResultRule.none` never does).
pub fn definesValue(op: ir.Op) bool {
    return row(op).result != .none;
}

/// How many operations the table covers.
pub fn count() usize {
    return std.enums.values(ir.Op).len;
}

fn classCounts() [std.enums.values(Class).len]usize {
    var classes: [std.enums.values(Class).len]usize = @splat(0);
    for (std.enums.values(ir.Op)) |op| classes[@backingInt(classOf(op))] += 1;
    return classes;
}

fn tokensDistinct() bool {
    for (std.enums.values(Class), 0..) |first, i| {
        for (std.enums.values(Class)[i + 1 ..]) |second| {
            if (std.mem.eql(u8, first.token(), second.token())) return false;
        }
    }
    return true;
}

test "every operation has a row and the class table is total" {
    const classes = classCounts();
    var covered: usize = 0;
    for (classes) |n| covered += n;
    try std.testing.expectEqual(count(), covered);
    try std.testing.expectEqual(@as(usize, 17), classes[@backingInt(Class.update)]);
    try std.testing.expectEqual(@as(usize, 3), classes[@backingInt(Class.take)]);
}

test "class tokens are distinct words" {
    try std.testing.expect(tokensDistinct());
}
