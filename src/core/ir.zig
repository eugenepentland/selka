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

/// A Core IR type. Named members are leaves; unnamed members from
/// `first_compound` index `Module.compounds`.
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
    /// An immutable raw-octet block, sharing the string block layout.
    bytes,
    /// A borrowed UTF-8 span in SSA only; it has no storable memory layout.
    str_view,
    /// Mutable octets in a counted leaf block; source updates preserve value semantics.
    byte_buffer = 0xfffffff0,
    /// Counted immutable authority/provider scope for non-stream capabilities.
    capability,
    /// Counted external-handle identity; explicit completion is a runtime effect.
    resource,
    _,

    /// The first index that names a compound type.
    pub const first_compound: u32 = 15;

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
        return switch (self) {
            .byte_buffer, .capability, .resource => false,
            else => @backingInt(self) >= first_compound,
        };
    }
};

/// A compound type's structure (docs/design/new-core-s1.md §2). Slices are owned by
/// the module (`Module.intern` copies them).
pub const Compound = union(enum) {
    /// `list[T]`: an immutable list value. Elements may be scalars, `str`, lists,
    /// records, unions or boxes; `T` is the element type, not a storage type.
    list: Type,
    /// A record: its field types in declaration order. A value, never a reference;
    /// a nested record field is stored inline (flattened) in its parent.
    record: []const Type,
    /// A tagged union: one payload type per case, `.void` for a case without one.
    /// The tag is the case index in the checker's case order, so `Option[T]` is
    /// `{void, T}` (None is tag 0) and `Result[T, E]` lists its cases as the checker does.
    @"union": []const Type,
    /// An immutable reference-counted block holding one `T`: boxed (recursive)
    /// record fields and union payloads.
    box: Type,
    /// A dictionary value; its operations do not expose any table layout.
    dict: struct { key: Type, value: Type },
    /// A fixed inline array of `n` elements, at the element's natural stride.
    array: struct { elem: Type, n: u32 },
    /// A top-level function pointer with the internal call signature.
    @"fn": Signature,
};

/// How a union value is laid out (docs/design/new-core-s1.md §4).
pub const UnionForm = enum(u8) {
    /// Two cases, one without a payload and one whose payload is a block pointer
    /// (`str`, a list or a box): the value is that pointer, null for the empty case.
    niche,
    /// Every case with a payload has the same scalar or pointer type: `{i8 tag, T}`
    /// in registers.
    scalar,
    /// Anything else: `{i8 tag, [N x i64] words}` in registers, the payload's
    /// memory image in the words.
    words,
};

/// The layout of one union type. In memory every non-niche form is an 8-byte tag
/// word followed by the payload's memory image in `payload_words` words.
pub const UnionLayout = struct {
    form: UnionForm,
    /// Payload words in memory and in the `words` form's registers.
    payload_words: u32,
    /// `niche`: the index of the case without a payload (null pointer).
    empty_case: u32 = 0,
    /// `scalar`: the one payload type. `niche`: the pointer payload type.
    payload: Type = .void,
};

/// One step of a `list_get_field` path. On a record it selects a field; on a union
/// step 0 is the tag (`u32`) and step `k + 1` the payload of case `k`.
pub const FieldPath = struct {
    /// The most steps one path holds; deeper reads go through `record_get`.
    pub const max_steps = 5;
    len: u8 = 0,
    steps: [max_steps]u12 = @splat(0),

    /// A path from `steps`, or null when it is empty, too long or a step exceeds 4095.
    pub fn init(steps: []const u32) ?FieldPath {
        if (steps.len == 0 or steps.len > max_steps) return null;
        var path: FieldPath = .{ .len = @intCast(steps.len) };
        for (steps, 0..) |step, i| path.steps[i] = std.math.cast(u12, step) orelse return null;
        return path;
    }

    /// Pack into an instruction's `data` field: the length in the low 4 bits, then 12 bits per step.
    pub fn pack(self: FieldPath) u64 {
        var data: u64 = self.len;
        for (self.steps[0..self.len], 0..) |step, i| data |= @as(u64, step) << @intCast(4 + 12 * i);
        return data;
    }

    /// Unpack from an instruction's `data` field.
    pub fn unpack(data: u64) FieldPath {
        var path: FieldPath = .{ .len = @intCast(@min(data & 0xf, max_steps)) };
        for (0..path.len) |i| path.steps[i] = @truncate(data >> @intCast(4 + 12 * i));
        return path;
    }

    /// The steps in order.
    pub fn slice(self: *const FieldPath) []const u12 {
        return self.steps[0..self.len];
    }
};

/// The kinds of `err_trace` (ERROR-TRACE-1, design note §6.2). `origin` (building an
/// `Err`) and `runtime` (a runtime call answered `Err`) restart the trace; `append` is a `?`
/// that passes the error on, `converted` a `?` that wraps it into a case of the caller's
/// error union (`a` is a `str_const` naming `Union.case`), and `returned` the `Err` path of
/// a `return e` whose `Err` the statement did not build.
pub const TraceMode = enum(u8) { origin, append, runtime, converted, returned };

/// Records and unions of at most this many words travel as LLVM struct values in
/// registers; larger ones are passed by pointer and returned through `sret` (§3).
pub const max_register_words = 4;

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

/// Unary floating-point operations; `float_unary.data` is one of these tags.
pub const FloatUnary = enum(u8) { sqrt, floor, ceil, trunc, abs, sin, cos };

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
    /// List `a` with `b` appended; `a` must not be used afterwards (`own.zig` makes it so).
    list_push,
    /// A fresh copy of list `a` with room for one more element: what a push of a
    /// list that may be shared appends to.
    list_copy,
    /// The byte length of string `a` (`u64`).
    str_len,
    /// `int(a)` for string `a`: an `option(i64)`.
    str_parse_int,
    /// A union value with tag `data` and payload `a` (none for a case without one).
    union_make,
    /// The tag of union `a` (`u32`).
    union_tag,
    /// The payload of union `a` under tag `data` (only meaningful when that is its tag).
    union_payload,
    /// A record of the field values in `extra` at `data`, in declaration order.
    record_make,
    /// Field `data` of record `a`.
    record_get,
    /// Record `a` with field `data` replaced by `b`; consumes `a`.
    record_set,
    /// List `a` with element `b` replaced by `extra[0]` at `data` (bounds-checked);
    /// consumes `a` and the value, and drops the element it replaces.
    list_set,
    /// List `a` without its last element (checked: an empty list traps); consumes
    /// `a`. The element is not dropped: the builder reads it with `list_get` first,
    /// and that read takes the list's ownership of it.
    list_pop,
    /// The value at `FieldPath.unpack(data)` inside element `b` of list `a`
    /// (bounds-checked), read without loading the whole element.
    list_get_field,
    /// Empty dictionary with capacity hint `a: u64`.
    dict_new,
    /// Live dictionary entries (`u64`).
    dict_len,
    /// Pure lookup of key `b` in dictionary `a`; `i64` entry or negative insertion probe.
    dict_find,
    /// Borrowed key at entry `b: i64` of dictionary `a`.
    dict_entry_key,
    /// Borrowed value at entry `b: i64` of dictionary `a`.
    dict_entry_value,
    /// Dictionary `a` with entry `b` assigned `extra[0]`; consumes `a` and the value.
    dict_set_value,
    /// Insert `extra = {key, value}` using negative probe `b` from `dict_find(a, key)`.
    dict_insert,
    /// Remove entry `b: i64` from dictionary `a`; consumes `a`.
    dict_remove,
    /// Number of written entries (`u64`), including dead entries.
    dict_entries,
    /// Whether entry `b: i64` of dictionary `a` is live (`bool`).
    dict_entry_live,
    /// Independent copy of dictionary `a`.
    dict_copy,
    /// Empty value of dictionary `a`'s type; consumes `a`.
    dict_clear,
    /// Character string at byte offset `b: u64` in string `a`.
    str_char,
    /// UTF-8 width (`u64`) at byte offset `b: u64` in string `a`.
    str_width,
    /// Unicode scalar (`u32`) at byte offset `b: u64` in string `a`.
    str_code,
    /// Append string `b` to string `a`; consumes `a`, borrows `b`.
    str_append,
    /// Append the character at `extra[0]: u64` in string `b` to string `a`; consumes `a`.
    str_append_char,
    /// Copy string `a` between scalar positions `b: i64` and `extra[0]: i64`.
    str_slice,
    /// Borrow a byte span of string `a`: offset `b: u64`, length `extra[0]: u64`.
    str_view_of,
    /// Materialize borrowed span `a: str_view` as an owned string.
    str_from_view,
    /// Stable sort of list `a`, reversed when `b: bool`; consumes `a`.
    list_sort,
    /// Element `b` of inline array `a`, bounds-checked against its fixed length.
    array_get,
    /// Array `a` with element `b` replaced by `extra[0]`; consumes the old array and value.
    array_set,
    /// Top-level internal function `data`, with the matching function pointer type.
    func_ref,
    /// Call function value `a`, with arguments in `extra` at `data`.
    call_indirect,
    /// A fresh box holding `a`; consumes `a`.
    box_make,
    /// The value box `a` holds.
    box_get,
    /// Add one owner to managed value `a` (every block it references).
    retain,
    /// Drop one owner of managed value `a`; a block whose last owner goes is freed.
    release,
    /// Whether block pointer `a` (a `str`, list or box) has exactly one owner (`bool`).
    is_unique,
    /// Record the error-trace site at this instruction's span; `data` is a `TraceMode`.
    err_trace,
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
    /// Fresh mutable bytes with capacity `a: u64`.
    buffer_new,
    /// Independent mutable-byte copy of `a`.
    buffer_copy,
    /// Replace byte `b` of `a` with `extra[0]: u8`; consumes `a`, checked bounds.
    buffer_set,
    /// Append `b: u8` to `a: byte_buffer`; consumes `a`.
    buffer_push,
    /// Remove the last byte of `a`; consumes `a`, checked nonempty.
    buffer_pop,
    /// Checked integer shift: `a << b`, with wrapping bits, count below width.
    shift_left,
    /// Checked arithmetic/logical integer shift `a >> b` by signedness.
    shift_right,
    /// Integer addition clamped to the result type's bounds.
    saturating_add,
    /// Unary f64 operation selected by `data: FloatUnary`.
    float_unary,
    /// List `a` with the field at `FieldPath.unpack` of the `u64` constant `extra[1]`
    /// inside element `b` replaced by `extra[0]` (bounds-checked): an element-field
    /// store done in place. Consumes `a` and the value, and drops the field it replaces.
    list_set_field,
    /// Buffer `a` with the octets of `b` (bytes or a byte buffer) from `extra[0]` up to
    /// `extra[1]` (`i64`) appended, or `a` unchanged when that range is not inside `b`;
    /// consumes `a`.
    buffer_append,

    /// Whether this operation ends a block.
    pub fn terminates(self: Op) bool {
        return switch (self) {
            .jump, .branch, .ret, .@"unreachable" => true,
            else => false,
        };
    }

    /// Whether `data` packs an `extra` operand list (an `ExtraSlice`).
    pub fn hasExtra(self: Op) bool {
        return switch (self) {
            .phi, .call, .call_indirect, .print, .record_make, .list_set, .list_set_field, .buffer_append, .dict_set_value, .dict_insert, .str_append_char, .str_slice, .str_view_of, .array_set, .buffer_set => true,
            else => false,
        };
    }

    /// Whether the operation is a constant or parameter: defined outside every block,
    /// materialized at each use, so it dominates every use.
    pub fn isConstant(self: Op) bool {
        return switch (self) {
            .param, .iconst, .fconst, .undef, .str_const, .func_ref => true,
            else => false,
        };
    }

    /// Whether an update takes ownership of its first value operand.
    pub fn consumesOperand0(self: Op) bool {
        return switch (self) {
            .list_push, .list_set, .list_set_field, .list_pop, .record_set, .array_set, .dict_set_value, .dict_insert, .dict_remove, .dict_clear => true,
            .str_append, .str_append_char, .list_sort, .buffer_set, .buffer_push, .buffer_pop, .buffer_append => true,
            else => false,
        };
    }
};

/// One instruction. `data` holds the immediate (constant bits, predicate, block,
/// callee, tag, field index, `FieldPath`, `TraceMode`, or a packed `extra` slice);
/// `span` is the start offset of the source span in the merged source, for traps,
/// traces and error-trace sites.
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
    /// A new-runtime C helper: scalar/pointer ABI, including declared capability tokens.
    runtime_c,
};

/// Parameter and result types of a function, and its linkage.
pub const Signature = struct {
    params: []const Type,
    ret: Type,
    linkage: Linkage = .internal,
    /// Bit `i`: parameter `i` is passed owned (a `mut` parameter, by value: the call
    /// consumes the argument, the callee owns it and returns its final value).
    owned: u64 = 0,
    /// Bit `i`: an extern-C `str` parameter takes a borrowed `(data, byte_length)`
    /// span and admits an SSA `str_view`. Internal functions never use this ABI.
    views: u64 = 0,
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

    /// Every value `inst` reads, in order: `a` and `b` where the operation reads
    /// them as values (a call's `a` is its callee), then its `extra` list.
    pub fn valueOperands(self: *const Function, instruction: Inst) Operands {
        var out: Operands = .{};
        switch (instruction.op) {
            .phi, .call, .print, .record_make => {},
            .jump, .@"unreachable" => return out,
            else => for ([_]Ref{ instruction.a, instruction.b }) |operand| {
                if (operand == .none) continue;
                out.direct[out.direct_len] = operand;
                out.direct_len += 1;
            },
        }
        if (instruction.op.hasExtra()) out.extra = self.operands(instruction.data);
        return out;
    }
};

/// The values one instruction reads (`Function.valueOperands`), unresolved.
pub const Operands = struct {
    direct: [2]Ref = .{ .none, .none },
    direct_len: u8 = 0,
    extra: []const Ref = &.{},

    /// How many operands there are.
    pub fn len(self: *const Operands) usize {
        return self.direct_len + self.extra.len;
    }

    /// Operand `i`, `0 <= i < len()`.
    pub fn get(self: *const Operands, i: usize) Ref {
        return if (i < self.direct_len) self.direct[i] else self.extra[i - self.direct_len];
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

    /// The interned type for `compound`; a record's or union's type list is copied.
    pub fn intern(self: *Module, allocator: std.mem.Allocator, wanted: Compound) std.mem.Allocator.Error!Type {
        for (self.compounds.items, 0..) |existing, i| {
            if (sameCompound(existing, wanted)) return @fromBackingInt(@intCast(Type.first_compound + i));
        }
        const owned: Compound = switch (wanted) {
            .record => |fields| .{ .record = try allocator.dupe(Type, fields) },
            .@"union" => |cases| .{ .@"union" = try allocator.dupe(Type, cases) },
            .@"fn" => |signature| .{ .@"fn" = .{ .params = try allocator.dupe(Type, signature.params), .ret = signature.ret, .linkage = signature.linkage, .owned = signature.owned, .views = signature.views } },
            else => wanted,
        };
        try self.compounds.append(allocator, owned);
        return @fromBackingInt(@intCast(Type.first_compound + self.compounds.items.len - 1));
    }

    /// The interned `Option[payload]`: a union of no payload (tag 0) and `payload` (tag 1).
    pub fn option(self: *Module, allocator: std.mem.Allocator, payload: Type) std.mem.Allocator.Error!Type {
        return self.intern(allocator, .{ .@"union" = &.{ .void, payload } });
    }

    /// The structure of a compound type.
    pub fn compound(self: *const Module, ty: Type) Compound {
        return self.compounds.items[@backingInt(ty) - Type.first_compound];
    }

    /// Whether `ty` names a type: a scalar, or a compound this module interned.
    pub fn valid(self: *const Module, ty: Type) bool {
        return !ty.isCompound() or @backingInt(ty) - Type.first_compound < self.compounds.items.len;
    }

    /// The compound kind of `ty`, or null for a scalar.
    pub fn kind(self: *const Module, ty: Type) ?std.meta.Tag(Compound) {
        if (!ty.isCompound()) return null;
        return std.meta.activeTag(self.compound(ty));
    }

    /// Whether `ty` is a counted leaf, collection, authority, resource or box pointer.
    pub fn isBlock(self: *const Module, ty: Type) bool {
        if (ty == .str or ty == .bytes or ty == .byte_buffer) return true;
        if (ty == .capability or ty == .resource) return true;
        const k = self.kind(ty) orelse return false;
        return k == .list or k == .box or k == .dict;
    }

    /// Whether a value of `ty` holds a reference to a counted block anywhere: a block
    /// pointer, or a record or union with such a field or payload. Only these need RC.
    pub fn managed(self: *const Module, ty: Type) bool {
        if (self.isBlock(ty)) return true;
        if (!ty.isCompound()) return false;
        return switch (self.compound(ty)) {
            .record => |fields| for (fields) |field| {
                if (self.managed(field)) break true;
            } else false,
            .@"union" => |cases| for (cases) |case| {
                if (self.managed(case)) break true;
            } else false,
            .array => |array| array.n != 0 and self.managed(array.elem),
            else => false,
        };
    }

    /// Bytes a value of `ty` occupies in memory (a list element, a box, a field, a payload).
    /// A record follows C layout and its size is a multiple of its alignment.
    pub fn size(self: *const Module, ty: Type) u32 {
        return switch (ty) {
            .void => 0,
            .bool, .i8, .u8 => 1,
            .i16, .u16 => 2,
            .i32, .u32 => 4,
            .i64, .u64, .f64, .cap, .str, .bytes, .byte_buffer, .capability, .resource => 8,
            .str_view => 0,
            _ => switch (self.compound(ty)) {
                .list, .box, .dict, .@"fn" => 8,
                .array => |array| array.n * self.size(array.elem),
                .record => |fields| blk: {
                    var offset: u32 = 0;
                    for (fields) |field| offset = std.mem.alignForward(u32, offset, self.alignment(field)) + self.size(field);
                    break :blk std.mem.alignForward(u32, offset, self.alignment(ty));
                },
                .@"union" => blk: {
                    const layout = self.unionLayout(ty);
                    break :blk if (layout.form == .niche) 8 else 8 + 8 * layout.payload_words;
                },
            },
        };
    }

    /// The alignment of `ty` in memory, in bytes.
    pub fn alignment(self: *const Module, ty: Type) u32 {
        if (!ty.isCompound()) return @max(1, self.size(ty));
        return switch (self.compound(ty)) {
            .list, .box, .dict, .@"fn", .@"union" => 8,
            .array => |array| self.alignment(array.elem),
            .record => |fields| blk: {
                var most: u32 = 1;
                for (fields) |field| most = @max(most, self.alignment(field));
                break :blk most;
            },
        };
    }

    /// The memory size of `ty` in 8-byte words, rounded up.
    pub fn words(self: *const Module, ty: Type) u32 {
        return (self.size(ty) + 7) / 8;
    }

    /// Whether a record or union of `ty` crosses calls in memory (more than
    /// `max_register_words` words) rather than as an LLVM struct value.
    pub fn passedInMemory(self: *const Module, ty: Type) bool {
        const k = self.kind(ty) orelse return false;
        return (k == .record or k == .@"union" or k == .array) and self.words(ty) > max_register_words;
    }

    /// The byte offset of field `index` inside a record of type `record`.
    pub fn fieldOffset(self: *const Module, record: Type, index: usize) u32 {
        const fields = self.compound(record).record;
        var offset: u32 = 0;
        for (fields[0..index]) |field| offset = std.mem.alignForward(u32, offset, self.alignment(field)) + self.size(field);
        return std.mem.alignForward(u32, offset, self.alignment(fields[index]));
    }

    /// The layout of union type `ty` (§4).
    pub fn unionLayout(self: *const Module, ty: Type) UnionLayout {
        const cases = self.compound(ty).@"union";
        var payload_words: u32 = 0;
        var only: Type = .void;
        var uniform = true;
        for (cases) |case| {
            if (case == .void) continue;
            payload_words = @max(payload_words, self.words(case));
            if (only != .void and only != case) uniform = false;
            only = case;
            const k = self.kind(case);
            if (k == .record or k == .@"union" or k == .array) uniform = false;
        }
        if (cases.len == 2 and (cases[0] == .void) != (cases[1] == .void) and self.isBlock(only)) {
            return .{ .form = .niche, .payload_words = 1, .empty_case = if (cases[0] == .void) 0 else 1, .payload = only };
        }
        if (uniform and only != .void) return .{ .form = .scalar, .payload_words = payload_words, .payload = only };
        return .{ .form = .words, .payload_words = payload_words };
    }

    /// The type and byte offset `path` reaches inside a value of `ty`, or null when a
    /// step does not fit (a field or case out of range, a scalar, a list or a box).
    pub fn pathTarget(self: *const Module, ty: Type, path: FieldPath) ?PathTarget {
        var current = ty;
        var offset: u32 = 0;
        var tag_of: Type = .void;
        for (path.slice()) |step| {
            const k = self.kind(current) orelse return null;
            switch (k) {
                .array => {
                    const array = self.compound(current).array;
                    if (step >= array.n) return null;
                    offset += step * self.size(array.elem);
                    current = array.elem;
                },
                .record => {
                    const fields = self.compound(current).record;
                    if (step >= fields.len) return null;
                    offset += self.fieldOffset(current, step);
                    current = fields[step];
                },
                .@"union" => {
                    const cases = self.compound(current).@"union";
                    if (step == 0) {
                        // The tag: a scalar, so any further step fails above.
                        tag_of = current;
                        current = .u32;
                        continue;
                    }
                    if (step - 1 >= cases.len or cases[step - 1] == .void) return null;
                    if (self.unionLayout(current).form != .niche) offset += 8;
                    current = cases[step - 1];
                },
                else => return null,
            }
        }
        return .{ .ty = current, .offset = offset, .tag_of = tag_of };
    }

    /// Whether `path` inside a `ty` value passes through a union (its tag or a case's
    /// payload): bytes a union's cases share, which keep the generic data tag.
    pub fn pathCrossesUnion(self: *const Module, ty: Type, path: FieldPath) bool {
        var current = ty;
        for (path.slice()) |step| {
            const k = self.kind(current) orelse return false;
            switch (k) {
                .array => current = self.compound(current).array.elem,
                .record => {
                    const fields = self.compound(current).record;
                    if (step >= fields.len) return false;
                    current = fields[step];
                },
                else => return true,
            }
        }
        return false;
    }
};

/// Where a `FieldPath` leads inside an element.
pub const PathTarget = struct {
    /// The type of the value read.
    ty: Type,
    /// Its byte offset from the start of the element.
    offset: u32,
    /// When the last step reads a union's tag, that union's type (whose value starts
    /// at `offset`); `.void` otherwise.
    tag_of: Type = .void,
};

/// Whether two compound descriptions are the same type.
fn sameCompound(x: Compound, y: Compound) bool {
    if (std.meta.activeTag(x) != std.meta.activeTag(y)) return false;
    return switch (x) {
        .list => |element| element == y.list,
        .box => |inner| inner == y.box,
        .record => |fields| std.mem.eql(Type, fields, y.record),
        .@"union" => |cases| std.mem.eql(Type, cases, y.@"union"),
        .dict => |dict| dict.key == y.dict.key and dict.value == y.dict.value,
        .array => |array| array.elem == y.array.elem and array.n == y.array.n,
        .@"fn" => |signature| signature.ret == y.@"fn".ret and signature.linkage == y.@"fn".linkage and signature.owned == y.@"fn".owned and signature.views == y.@"fn".views and std.mem.eql(Type, signature.params, y.@"fn".params),
    };
}
