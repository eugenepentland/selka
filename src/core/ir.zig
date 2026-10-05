//! The Core IR: typed SSA over basic blocks (docs/design/new-core-ir.md §3).
//!
//! Every instruction defines at most one value, named by its index (`Ref`).
//! Parameters and constants are instructions. Join values are `phi`
//! instructions at the head of a block with one operand per predecessor, in
//! the block's predecessor order. Lists, strings, options and records are
//! immutable values: an update returns a new value, and whether it reuses
//! storage in place is the ownership pass's decision (S1).
const std = @import("std");

/// A value: the index of the instruction that defines it.
pub const Ref = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    /// The instruction index behind a value that is not `none`.
    pub fn index(self: Ref) usize {
        return @backingInt(self);
    }
};

/// A basic block of a function.
pub const BlockId = enum(u32) {
    _,

    /// The position of the block in `Function.blocks`.
    pub fn index(self: BlockId) usize {
        return @backingInt(self);
    }
};

/// A Core IR type. The named members are scalars; members from `first_compound`
/// on index `Module.compounds`.
pub const Type = enum(u32) {
    void,
    bool,
    i8,
    i16,
    i32,
    i64,
    u8,
    u16,
    u32,
    u64,
    f64,
    /// A capability token (`Stream`, `Host`, …): an `i64`, dropped at `extern` calls.
    cap,
    /// An immutable UTF-8 string block.
    str,
    _,

    /// The first index that names a compound type.
    pub const first_compound: u32 = 13;

    /// Width and signedness of an integer type, or null for any other type.
    pub fn integer(self: Type) ?struct { bits: u16, signed: bool } {
        return switch (self) {
            .i8 => .{ .bits = 8, .signed = true },
            .i16 => .{ .bits = 16, .signed = true },
            .i32 => .{ .bits = 32, .signed = true },
            .i64 => .{ .bits = 64, .signed = true },
            .u8 => .{ .bits = 8, .signed = false },
            .u16 => .{ .bits = 16, .signed = false },
            .u32 => .{ .bits = 32, .signed = false },
            .u64 => .{ .bits = 64, .signed = false },
            else => null,
        };
    }

    /// Whether this names an entry of `Module.compounds`.
    pub fn isCompound(self: Type) bool {
        return @backingInt(self) >= first_compound;
    }
};

/// A compound type's structure.
pub const Compound = union(enum) {
    /// `list[T]`: an immutable list value of scalar elements.
    list: Type,
    /// `Option[T]`: tag 0 is `None`, tag 1 is `Some(T)` (the checker's case order).
    option: Type,
};

/// What a checkable instruction promises about its failure path.
pub const Check = enum(u8) {
    /// Cannot fail, or carries no check.
    none,
    /// Traps at this instruction, in program order (debug builds; release until moved).
    exact,
    /// The fact pass proved the failure impossible; nothing is emitted for it.
    proven,
};

/// Comparison predicates; signedness comes from the operand type.
pub const Predicate = enum(u8) { eq, ne, lt, le, gt, ge };

/// Instruction operations. Operand use is listed per operation.
pub const Op = enum(u8) {
    /// Function parameter `data`.
    param,
    /// Integer or boolean constant: the value in `data` (two's complement bits).
    iconst,
    /// Float constant: the IEEE bits in `data`.
    fconst,
    /// A value no execution reads (an unassigned local on an impossible path).
    undef,
    /// The immortal string constant `Module.strings[data]`.
    str_const,
    /// Forwarding: this value is `a` (a removed trivial phi).
    copy,
    /// Join value: operands in `extra` at `data`, one per predecessor.
    phi,
    add,
    sub,
    mul,
    /// Truncating division and remainder.
    div,
    rem,
    /// Python floor division and remainder.
    floor_div,
    floor_rem,
    neg,
    bit_and,
    bit_or,
    bit_xor,
    /// Boolean negation.
    not,
    /// Integer comparison `a <data as Predicate> b`.
    cmp,
    fadd,
    fsub,
    fmul,
    fdiv,
    fneg,
    /// Float comparison `a <data as Predicate> b` (ordered).
    fcmp,
    /// Integer to float.
    int_to_float,
    /// Float to integer, truncating; checked against the destination range.
    float_to_int,
    /// Integer to integer of another width or signedness; checked when the
    /// source range does not fit the destination.
    convert,
    /// A fresh empty list with capacity `a` (`u64`).
    list_new,
    /// The length of list `a` (`u64`).
    list_len,
    /// Element `b` of list `a` (bounds-checked).
    list_get,
    /// List `a` with `b` appended; `a` must not be used afterwards.
    list_push,
    /// The byte length of string `a` (`u64`).
    str_len,
    /// `int(a)` for string `a`: an `option(i64)`.
    str_parse_int,
    /// A union value with tag `data` and payload `a` (or none).
    union_make,
    /// The tag of union `a` (`u32`).
    union_tag,
    /// The payload of union `a` under tag `data`.
    union_payload,
    /// Direct call of function `a` (its index into `Module.functions`), arguments in `extra` at `data`.
    call,
    /// Write `extra[1..]` to stream `extra[0]`, separated by spaces and ended by a newline.
    print,
    /// Unconditional jump to block `data`.
    jump,
    /// `if a: block data.low else block data.high`.
    branch,
    /// Return `a` (or nothing for `void`).
    ret,
    /// Control never reaches here.
    @"unreachable",

    /// Whether this operation ends a block.
    pub fn terminates(self: Op) bool {
        return switch (self) {
            .jump, .branch, .ret, .@"unreachable" => true,
            else => false,
        };
    }
};

/// One instruction. `data` holds the immediate (constant bits, predicate, block,
/// callee, tag, or a packed `extra` slice); `span` is the start offset of the
/// source span in the merged source, for traps and traces.
pub const Inst = struct {
    op: Op,
    ty: Type,
    a: Ref = .none,
    b: Ref = .none,
    data: u64 = 0,
    check: Check = .none,
    span: u32 = 0,
};

/// A slice of `Function.extra`, packed into an instruction's `data`.
pub const ExtraSlice = struct {
    start: u32,
    len: u32,

    /// Pack into an instruction's `data` field.
    pub fn pack(self: ExtraSlice) u64 {
        return @as(u64, self.start) | (@as(u64, self.len) << 32);
    }
    /// Unpack from an instruction's `data` field.
    pub fn unpack(data: u64) ExtraSlice {
        return .{ .start = @truncate(data), .len = @truncate(data >> 32) };
    }
};

/// Pack the two targets of a `branch`.
pub fn packTargets(then: BlockId, otherwise: BlockId) u64 {
    return @as(u64, @backingInt(then)) | (@as(u64, @backingInt(otherwise)) << 32);
}

/// Unpack the two targets of a `branch`.
pub fn unpackTargets(data: u64) struct { then: BlockId, otherwise: BlockId } {
    return .{ .then = @fromBackingInt(@intCast(@as(u32, @truncate(data)))), .otherwise = @fromBackingInt(@intCast(@as(u32, @truncate(data >> 32)))) };
}

/// A basic block: its instructions in order (phis first, terminator last) and
/// its predecessors in the order phi operands follow.
pub const Block = struct {
    insts: std.ArrayList(Ref) = .empty,
    preds: std.ArrayList(BlockId) = .empty,
};

/// A counted or conditional loop as the checked tree wrote it, recorded by the
/// builder so later passes never re-discover loops from back edges.
pub const Loop = struct {
    /// The checker's loop id (`loop_exit.target`).
    id: usize,
    /// Evaluates the condition; its first predecessor enters the loop.
    header: BlockId,
    /// The first block of the body.
    body: BlockId,
    /// Runs the step and jumps back to the header (`continue` target).
    latch: BlockId,
    /// Where control goes when the condition is false (`break` target).
    exit: BlockId,
};

/// How a function is reached.
pub const Linkage = enum(u8) {
    /// A mylang function with a body, internal to the module.
    internal,
    /// An `extern def`: a C function; capability arguments are dropped.
    extern_c,
};

/// Parameter and result types of a function, and its linkage.
pub const Signature = struct {
    params: []const Type,
    ret: Type,
    linkage: Linkage = .internal,
};

/// A function: its instructions, blocks, packed operand lists and loops.
pub const Function = struct {
    name: []const u8,
    signature: Signature,
    insts: std.ArrayList(Inst) = .empty,
    blocks: std.ArrayList(Block) = .empty,
    extra: std.ArrayList(Ref) = .empty,
    loops: std.ArrayList(Loop) = .empty,
    /// The declaration's span start, for traces.
    span: u32 = 0,

    /// The instruction defining `ref`.
    pub fn inst(self: *const Function, ref: Ref) Inst {
        return self.insts.items[ref.index()];
    }

    /// Follow forwarding copies to the value `ref` stands for.
    pub fn resolve(self: *const Function, ref: Ref) Ref {
        var current = ref;
        while (current != .none and self.insts.items[current.index()].op == .copy) current = self.insts.items[current.index()].a;
        return current;
    }

    /// The operands packed in `data` of an instruction with an `extra` list.
    pub fn operands(self: *const Function, data: u64) []const Ref {
        const slice = ExtraSlice.unpack(data);
        return self.extra.items[slice.start..][0..slice.len];
    }
};

/// A whole program: interned compound types and functions.
pub const Module = struct {
    compounds: std.ArrayList(Compound) = .empty,
    functions: std.ArrayList(Function) = .empty,
    /// UTF-8 bytes of string constants, by `str_const` index.
    strings: std.ArrayList([]const u8) = .empty,
    /// The function `main` is, by index.
    entry: u32 = 0,

    /// The interned type for `compound`.
    pub fn intern(self: *Module, allocator: std.mem.Allocator, wanted: Compound) std.mem.Allocator.Error!Type {
        for (self.compounds.items, 0..) |existing, i| {
            if (std.meta.eql(existing, wanted)) return @fromBackingInt(@intCast(Type.first_compound + i));
        }
        try self.compounds.append(allocator, wanted);
        return @fromBackingInt(@intCast(Type.first_compound + self.compounds.items.len - 1));
    }

    /// The structure of a compound type.
    pub fn compound(self: *const Module, ty: Type) Compound {
        return self.compounds.items[@backingInt(ty) - Type.first_compound];
    }
};
