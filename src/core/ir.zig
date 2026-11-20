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
    /// An IEEE binary32 value: four bytes in memory, the `float` of LLVM.
    f32,
    /// Mutable octets in an owned leaf block; source updates preserve value semantics.
    byte_buffer = 0xfffffff0,
    /// Counted immutable authority/provider scope for non-stream capabilities.
    capability,
    /// Counted external-handle identity; explicit completion is a runtime effect.
    resource,
    /// A borrowed raw-octet span in SSA only (C9 bytes): the family marker of a view. It has the same
    /// `(data, byte_length)` layout as `str_view`, and a plain `bytes` parameter takes it. Named apart from
    /// `str_view` so a view's family travels with its type through signatures, callable types and operands.
    bytes_view = 0xfffffff3,
    /// A parallel task group block: joined and destroyed when its `with` scope ends (E1).
    task_group,
    /// A submitted task handle of a group: one block, read once through `myl_core_owned_group_take` (E1).
    task_handle,
    _,

    /// The first index that names a compound type.
    pub const first_compound: u32 = 16;

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

    /// Whether this is a borrowed text or bytes span (`str_view` or `bytes_view`).
    pub fn isSpan(self: Type) bool {
        return self == .str_view or self == .bytes_view;
    }

    /// Whether this names an entry of `Module.compounds`.
    pub fn isCompound(self: Type) bool {
        return switch (self) {
            .byte_buffer, .capability, .resource, .bytes_view, .f32 => false,
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
    /// An owned block holding one `T`: boxed (recursive)
    /// record fields and union payloads.
    box: Type,
    /// A dictionary value; its operations do not expose any table layout.
    dict: struct { key: Type, value: Type },
    /// A fixed inline array of `n` elements, at the element's natural stride.
    /// A vector (`vector`) is a `Simd` value: `n` lanes of `elem` held as one LLVM `<n x elem>` in SSA.
    array: struct { elem: Type, n: u32, vector: bool = false },
    /// A borrowed span of elements of a list (wave 3: a list slice is a view):
    /// SSA only, `{ptr, i64}` with the element type for indexing and iteration.
    list_view: Type,
    /// Read-only borrowed storage with the same physical layout as its owned type.
    borrowed: Type,
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
    /// Lend owned storage without copying; the result has its borrowed overlay type.
    borrow,
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
    /// The elements of list `a` as a view of its storage (`list_view`).
    list_view_of,
    /// A view of the elements of `a` from `b` up to `extra[0]` (`i64`), both
    /// already clamped by the builder to `0 <= first <= last <= len`; `a` may be
    /// a list or a `list_view`.
    list_slice_view,
    /// List `a` with `b` appended; `a` must not be used afterwards (`own.zig` makes it so).
    list_push,
    /// A fresh independent copy of scalar list `a`, with spare append capacity.
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
    /// The static sentinel owner of a borrowed text (`myl_core_text_no_cache`): no cached facts, nothing written.
    /// Detached (an operand, like `func_ref`).
    text_sentinel,
    /// The cache owner of a plain `str` parameter (C9 S1): `a: str` is the parameter's owner (its block, or the
    /// sentinel), `b: str_view` its span. A sentinel owner is replaced by a frame header on the stack, of the
    /// span's length and with no facts, so one call's scalar lookups walk only the distance moved.
    text_frame,
    /// Stable sort of list `a`, reversed when `b: bool`; consumes `a`.
    list_sort,
    /// Element `b` of inline array `a`, bounds-checked against its fixed length.
    array_get,
    /// Array `a` with element `b` replaced by `extra[0]`; consumes the old array and value.
    array_set,
    /// The inline `u8` array of this instruction's type, copied from the first `n` octets of byte
    /// list `a`, which holds at least `n`: one bulk copy, however large the array is.
    array_from_bytes,
    /// Top-level internal function `data`, with the matching function pointer type.
    func_ref,
    /// Call function value `a`, with arguments in `extra` at `data`.
    call_indirect,
    /// A fresh box holding `a`; consumes `a`.
    box_make,
    /// The value box `a` holds.
    box_get,
    /// A box of this call's frame that holds read-only record parameter `a` (O4): an entry-block stack slot with a box
    /// header (static storage, so no drop frees it) and the parameter's value. Borrowed from `a`; never returned.
    box_frame,
    /// The block a borrowed record holds for read-only text, bytes or list parameter view `a` (RB1): the parameter's C9 owner
    /// `b` when the argument was a whole value (`b` is not the sentinel), else this call's frame copy of the view, made at its
    /// first use, shared by every use of the same parameter and freed at every return (static storage, so no drop frees it).
    /// Borrowed from `a`; never returned. `b` is `none` for bytes, which carries no owner.
    block_frame,
    /// Destroy owned value `a` and every managed child it owns.
    drop,
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
    /// Borrow string `a` between scalar positions `b: i64` and `extra[0]: i64`, clamped
    /// exactly as `str_slice` clamps them: the `str_view` of the octets `str_slice` would copy.
    str_slice_view,
    /// Borrow string `a` between byte offsets `b: i64` and `extra[0]: i64`, clamped and
    /// boundary-checked exactly as `myl_core_ir_str_slice_bytes` checks them: the
    /// `str_view` of the octets that byte slice would copy.
    str_slice_bytes_view,
    /// Consume an owned union and transfer case `data`, unboxing its payload when
    /// needed and freeing only the box shell. Zero-RC only; the active tag must
    /// already be established. Unlike `union_payload`, the result is an owner.
    union_take,
    /// Consume a zero-RC box, transferring its inner value before freeing its shell.
    box_take,
    /// Convert a float to a float of the other width: `fpext` widens an `f32` to `f64`
    /// exactly, `fptrunc` rounds an `f64` to the nearest `f32`. The result type is `ty`.
    float_convert,
    /// Reinterpret the bits of `a` as `ty`, of the same width: a `float` as its `u64` pattern,
    /// an `f32` as its `u32` pattern, and back.
    bitcast,
    /// `a * b + c` of one floating width with a single rounding: `c` is the one extra operand,
    /// packed in `extra` at `data` (`llvm.fma`).
    float_fma,
    /// Lane `i` of `a` where the mask `b` holds, else lane `i` of `extra[0]` (`select` on vectors).
    vector_select,
    /// One fixed-width read of the octets of view `a` (`bytes_view`) at offset `b: u64` (already checked in
    /// bounds): a single unaligned load of the result type `ty`, byte-swapped when `data` is 1 (big-endian).
    /// Reads its operand without consuming it.
    byte_load,

    /// Consume record `a`, transfer stored field `data`, and destroy every
    /// sibling at this instruction. The result owns the selected field.
    record_take,

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
            .phi,
            .call,
            .call_indirect,
            .print,
            .record_make,
            .list_set,
            .list_set_field,
            .buffer_append,
            .dict_set_value,
            .dict_insert,
            .str_append_char,
            .str_slice,
            .str_view_of,
            .str_slice_view,
            .str_slice_bytes_view,
            .float_fma,
            .vector_select,
            .array_set,
            .list_slice_view,
            .buffer_set,
            => true,
            else => false,
        };
    }

    /// Whether the operation is a constant or parameter: defined outside every block,
    /// materialized at each use, so it dominates every use.
    pub fn isConstant(self: Op) bool {
        return switch (self) {
            .param, .iconst, .fconst, .undef, .str_const, .text_sentinel, .func_ref => true,
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

    /// The largest length `pack` can hold: bit 63 of `data` is a flag (`flags.written_copy`)
    /// on the instructions that carry an `extra` list, so the length takes bits 32 to 62.
    pub const max_len: u32 = 0x7fff_ffff;

    /// Pack into an instruction's `data` field.
    pub fn pack(self: ExtraSlice) u64 {
        return @as(u64, self.start) | (@as(u64, self.len) << 32);
    }
    /// Unpack from an instruction's `data` field, ignoring its flag bit 63.
    pub fn unpack(data: u64) ExtraSlice {
        return .{ .start = @truncate(data), .len = @truncate((data >> 32) & max_len) };
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
    /// Written with `@vectorize`: the latch carries `llvm.loop.vectorize.enable` (checked in release builds).
    vectorize: bool = false,
};

/// How a function is reached.
pub const Linkage = enum(u8) {
    /// A selka function with a body, internal to the module.
    internal,
    /// An `extern def`: a C function; capability arguments are dropped.
    extern_c,
    /// A new-runtime C helper: scalar/pointer ABI, including declared capability tokens.
    runtime_c,
    /// An `@address` `extern func`: called like `extern_c`, through the address its first passed parameter holds, with
    /// no symbol declared or referenced (`emit_llvm.zig` `addressTarget`). Last, so the other linkages keep their tags.
    extern_address,

    /// Whether this is a source `extern func` or a runtime helper declared like one: a C callee whose capability
    /// arguments are dropped.
    pub fn externC(self: Linkage) bool {
        return self == .extern_c or self == .extern_address;
    }
};

/// One projection through a returned record or a standard success/Some payload.
pub const BorrowProjection = union(enum) { field: u32, payload: u32 };

/// A caller argument or a final owner returned through the mutable-parameter ABI.
pub const BorrowSource = union(enum) { argument: u32, result: []const BorrowProjection };

/// The one borrowed result leaf and all of its possible owner sources.
pub const BorrowContract = struct {
    path: []const BorrowProjection = &.{},
    sources: []const BorrowSource = &.{},

    /// Copy all retained source and projection slices onto the destination allocator.
    pub fn clone(self: BorrowContract, a: std.mem.Allocator) std.mem.Allocator.Error!BorrowContract {
        const sources = try a.dupe(BorrowSource, self.sources);
        for (sources) |*source| if (source.* == .result) {
            source.result = try a.dupe(BorrowProjection, source.result);
        };
        return .{ .path = try a.dupe(BorrowProjection, self.path), .sources = sources };
    }

    /// Compare paths and source sets by value rather than by backing allocation.
    pub fn eql(a: BorrowContract, b: BorrowContract) bool {
        if (!samePath(a.path, b.path) or a.sources.len != b.sources.len) return false;
        for (a.sources, b.sources) |left, right| {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
            switch (left) {
                .argument => |position| if (position != right.argument) return false,
                .result => |path| if (!samePath(path, right.result)) return false,
            }
        }
        return true;
    }
};

/// Compare two canonical result projection paths.
pub fn samePath(a: []const BorrowProjection, b: []const BorrowProjection) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
}

/// Physical parameter conventions: compact common positions and unbounded tails.
pub const ParameterPassing = struct {
    owned: u64 = 0,
    consumes: u64 = 0,
    views: u64 = 0,
    extra_owned: []const u32 = &.{},
    extra_consumes: []const u32 = &.{},
    extra_views: []const u32 = &.{},

    /// Whether a source own/mut argument transfers ownership at this position.
    pub fn ownedAt(self: ParameterPassing, index: usize) bool {
        return at(self.owned, self.extra_owned, index);
    }

    /// Whether an inferred ordinary argument transfers ownership at this position.
    pub fn consumesAt(self: ParameterPassing, index: usize) bool {
        return at(self.consumes, self.extra_consumes, index);
    }

    /// Whether an external parameter uses its borrowed span ABI.
    pub fn viewAt(self: ParameterPassing, index: usize) bool {
        return at(self.views, self.extra_views, index);
    }

    /// Whether either ownership convention consumes this argument.
    pub fn takes(self: ParameterPassing, index: usize) bool {
        return self.ownedAt(index) or self.consumesAt(index);
    }

    /// Whether any source own/mut position exists.
    pub fn hasOwned(self: ParameterPassing) bool {
        return self.owned != 0 or self.extra_owned.len != 0;
    }

    /// Whether any inferred consuming position exists.
    pub fn hasConsumes(self: ParameterPassing) bool {
        return self.consumes != 0 or self.extra_consumes.len != 0;
    }

    /// Whether any external span position exists.
    pub fn hasViews(self: ParameterPassing) bool {
        return self.views != 0 or self.extra_views.len != 0;
    }

    /// Whether a compact-mask-only optimization must use its general fallback.
    pub fn hasExtras(self: ParameterPassing) bool {
        return self.extra_owned.len != 0 or self.extra_consumes.len != 0 or self.extra_views.len != 0;
    }

    /// Add an owned parameter; callers supply physical positions in any order.
    pub fn setOwned(self: *ParameterPassing, a: std.mem.Allocator, index: usize) std.mem.Allocator.Error!void {
        try set(a, &self.owned, &self.extra_owned, index);
    }

    /// Add an inferred consuming parameter.
    pub fn setConsumes(self: *ParameterPassing, a: std.mem.Allocator, index: usize) std.mem.Allocator.Error!void {
        try set(a, &self.consumes, &self.extra_consumes, index);
    }

    /// Add an externally admitted borrowed span parameter.
    pub fn setView(self: *ParameterPassing, a: std.mem.Allocator, index: usize) std.mem.Allocator.Error!void {
        try set(a, &self.views, &self.extra_views, index);
    }

    /// Require sorted unique tails, valid bounds and no overlapping conventions.
    pub fn valid(self: ParameterPassing, count: usize) bool {
        if (!validSet(self.owned, self.extra_owned, count)) return false;
        if (!validSet(self.consumes, self.extra_consumes, count)) return false;
        if (!validSet(self.views, self.extra_views, count)) return false;
        if (self.owned & self.consumes != 0 or (self.owned | self.consumes) & self.views != 0) return false;
        for (self.extra_owned) |index| if (self.consumesAt(index) or self.viewAt(index)) return false;
        for (self.extra_consumes) |index| if (self.viewAt(index)) return false;
        return true;
    }

    /// Deep equality includes every arbitrary position.
    pub fn eql(a: ParameterPassing, b: ParameterPassing) bool {
        return a.owned == b.owned and a.consumes == b.consumes and a.views == b.views and
            std.mem.eql(u32, a.extra_owned, b.extra_owned) and std.mem.eql(u32, a.extra_consumes, b.extra_consumes) and std.mem.eql(u32, a.extra_views, b.extra_views);
    }

    /// Retain all tail slices on the supplied allocator.
    pub fn clone(self: ParameterPassing, a: std.mem.Allocator) std.mem.Allocator.Error!ParameterPassing {
        var result = self;
        result.extra_owned = try a.dupe(u32, self.extra_owned);
        result.extra_consumes = try a.dupe(u32, self.extra_consumes);
        result.extra_views = try a.dupe(u32, self.extra_views);
        return result;
    }

    fn at(mask: u64, extra: []const u32, index: usize) bool {
        return if (index < 64) mask & (@as(u64, 1) << @intCast(index)) != 0 else std.mem.indexOfScalar(u32, extra, std.math.cast(u32, index) orelse return false) != null;
    }

    fn set(a: std.mem.Allocator, mask: *u64, extra: *[]const u32, index: usize) std.mem.Allocator.Error!void {
        if (index < 64) {
            mask.* |= @as(u64, 1) << @intCast(index);
            return;
        }
        const position = std.math.cast(u32, index) orelse return error.OutOfMemory;
        if (std.mem.indexOfScalar(u32, extra.*, position) != null) return;
        const next = try a.alloc(u32, extra.len + 1);
        @memcpy(next[0..extra.len], extra.*);
        next[extra.len] = position;
        std.mem.sort(u32, next, {}, std.sort.asc(u32));
        extra.* = next;
    }

    fn validSet(mask: u64, extra: []const u32, count: usize) bool {
        if (count < 64 and mask >> @intCast(count) != 0) return false;
        for (extra, 0..) |index, i| if (index < 64 or index >= count or (i != 0 and extra[i - 1] >= index)) return false;
        return true;
    }
};

/// Parameter and result types of a function, and its linkage.
/// One function's parameter and result types plus the passing conventions the
/// builder inferred for them.
pub const Signature = struct {
    params: []const Type,
    ret: Type,
    linkage: Linkage = .internal,
    /// Physical argument conventions, including positions above the compact mask.
    passing: ParameterPassing = .{},
    /// The borrowed result leaf and every argument or returned owner keeping it alive.
    borrow: BorrowContract = .{},

    /// Copy the parameter list and complete borrowing metadata for retained IR.
    pub fn clone(self: Signature, a: std.mem.Allocator) std.mem.Allocator.Error!Signature {
        var result = self;
        result.params = try a.dupe(Type, self.params);
        result.borrow = try self.borrow.clone(a);
        result.passing = try self.passing.clone(a);
        return result;
    }

    /// Compare the complete ABI and declared borrowing contract, including nested paths.
    pub fn eql(a: Signature, b: Signature) bool {
        return a.ret == b.ret and a.linkage == b.linkage and a.passing.eql(b.passing) and
            std.mem.eql(Type, a.params, b.params) and a.borrow.eql(b.borrow);
    }

    /// A singleton argument source used by slice optimizations; multiple sources stay unknown.
    pub fn viewSource(self: Signature) ?usize {
        if (self.borrow.path.len != 0 or self.borrow.sources.len != 1) return null;
        return switch (self.borrow.sources[0]) {
            .argument => |position| position,
            .result => null,
        };
    }
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
    /// The source module the function belongs to, by its key path (`stable_names.ModuleName`); empty for a runtime
    /// function and for a program built without a source. Lowering sets it from the declaration's span.
    module: []const u8 = "",

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
            .jump => return out,
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

/// `Module.lowering`.
pub const ModuleLowering = struct {
    /// Told of every compound type lowering obtains from `intern`, while an op log records (`op_log.zig`); null otherwise.
    tap: ?*Module.Tap = null,
    /// Bytes of a pointer on the build's target (`Target.pointerBytes`): the size of a block reference, a list, box,
    /// dictionary or function value, and of a niche union, in every layout below. 8 for the host.
    pointer_bytes: u32 = 8,
};

/// A whole program: interned compound types and functions.
pub const Module = struct {
    compounds: std.ArrayList(Compound) = .empty,
    functions: std.ArrayList(Function) = .empty,
    /// UTF-8 bytes of string constants, by `str_const` index.
    strings: std.ArrayList([]const u8) = .empty,
    /// The function `main` is, by index.
    entry: u32 = 0,
    /// What the lowering that builds this module is given: its op-log tap and the target's pointer width.
    lowering: ModuleLowering = .{},

    /// The digest of the stable name (`stable_names.RecordName.digest`) of each nominal compound, by compound index: null for a
    /// structural one. A nominal record is told apart from a structurally equal record by its name, which the optimizer's records
    /// use to find a type again after the table moved. Empty when lowering did not name them.
    nominal: []const ?[32]u8 = &.{},
    /// The names of the functions no other unit can name (`typed.Program.private`), as `nameKey`s: the linkage rule of spec section
    /// 17.5 reads it, so a function is `internal` in its unit only when its own module's source says it can be. A name two functions
    /// share is in it only when both are private. Empty when the check did not decide it, which makes every function visible. The
    /// keys are hashes because the name strings of a restored function do not live as long as the module.
    private: std.AutoHashMapUnmanaged(u128, void) = .empty,
    /// The names of the `@freestanding` functions (`freestanding.zig`), as `nameKey`s: their failed checks are faults that
    /// call nothing (`emit_llvm.zig`) and their emitted text names no runtime symbol (`freestanding_emitted.zig`). Empty in a
    /// program with none, which is then emitted as before.
    freestanding: std.AutoHashMapUnmanaged(u128, void) = .empty,
    /// The names of the `@freestanding(ram)` functions, a subset of `freestanding`: on a bare target their code goes to the
    /// section `.ramfunc` with no jump table (`emit_llvm.zig`), and the linked image is checked to reach nothing in flash
    /// from them (`ram_image.zig`). Empty in a program with none.
    ram: std.AutoHashMapUnmanaged(u128, void) = .empty,

    /// The key of a function name in `private`: two independent 64-bit hashes of its bytes.
    pub fn nameKey(name: []const u8) u128 {
        return (@as(u128, std.hash.Wyhash.hash(0x6d796c616e67, name)) << 64) | std.hash.Wyhash.hash(0x70726976617465, name);
    }

    /// Whether `function` is private to its unit (see `private`).
    pub fn isPrivate(self: *const Module, function: *const Function) bool {
        return self.private.contains(nameKey(function.name));
    }

    /// Whether `function` is `@freestanding` (see `freestanding`).
    pub fn isFreestanding(self: *const Module, function: *const Function) bool {
        return self.freestanding.count() != 0 and self.freestanding.contains(nameKey(function.name));
    }

    /// Whether `function` is `@freestanding(ram)` (see `ram`).
    pub fn isRam(self: *const Module, function: *const Function) bool {
        return self.ram.count() != 0 and self.ram.contains(nameKey(function.name));
    }

    /// The observer of `Module.intern`: `op_log.Recorder` embeds one. A copy of a module shares its tap.
    pub const Tap = struct {
        /// Called with the module and the type `intern` is about to return, whether it was found or appended.
        on_intern: *const fn (tap: *Tap, module: *const Module, ty: Type) void,
    };

    /// The block ABI starts with its kind tag.
    pub fn kindOffset(_: *const Module) u8 {
        return 0;
    }

    /// The interned type for `compound`; a record's or union's type list is copied.
    pub fn intern(self: *Module, allocator: std.mem.Allocator, wanted: Compound) std.mem.Allocator.Error!Type {
        for (self.compounds.items, 0..) |existing, i| {
            if (sameCompound(existing, wanted)) {
                const found: Type = @fromBackingInt(@intCast(Type.first_compound + i));
                if (self.lowering.tap) |tap| tap.on_intern(tap, self, found);
                return found;
            }
        }
        const owned: Compound = switch (wanted) {
            .record => |fields| .{ .record = try allocator.dupe(Type, fields) },
            .@"union" => |cases| .{ .@"union" = try allocator.dupe(Type, cases) },
            .@"fn" => |signature| .{ .@"fn" = try signature.clone(allocator) },
            else => wanted,
        };
        try self.compounds.append(allocator, owned);
        const appended: Type = @fromBackingInt(@intCast(Type.first_compound + self.compounds.items.len - 1));
        if (self.lowering.tap) |tap| tap.on_intern(tap, self, appended);
        return appended;
    }

    /// The interned `Option[payload]`: a union of no payload (tag 0) and `payload` (tag 1).
    pub fn option(self: *Module, allocator: std.mem.Allocator, payload: Type) std.mem.Allocator.Error!Type {
        return self.intern(allocator, .{ .@"union" = &.{ .void, payload } });
    }

    /// The structure of a compound type.
    pub fn compound(self: *const Module, ty: Type) Compound {
        return self.compounds.items[@backingInt(ty) - Type.first_compound];
    }

    /// The physical storage type underneath a read-only borrowed overlay.
    pub fn storageType(self: *const Module, ty: Type) Type {
        var current = ty;
        var remaining = self.compounds.items.len + 1;
        while (remaining != 0 and current.isCompound() and self.valid(current)) : (remaining -= 1) {
            const value = self.compound(current);
            if (value != .borrowed) return current;
            current = value.borrowed;
        }
        return current;
    }

    /// The key and value types of a dictionary, or of a read-only borrowed overlay of one (`borrowed`
    /// shares its storage type's layout), and null for any other type. Reading `.dict` of
    /// `compound(ty)` directly is wrong for an overlay: its active member is `borrowed`.
    pub fn dictShape(self: *const Module, ty: Type) ?@FieldType(Compound, "dict") {
        const stored = self.storageType(ty);
        if (!self.valid(stored) or self.kind(stored) != .dict) return null;
        return self.compound(stored).dict;
    }

    /// Whether this exact type is a non-owning overlay of ordinary managed storage.
    pub fn isBorrowed(self: *const Module, ty: Type) bool {
        return ty.isCompound() and self.valid(ty) and self.compound(ty) == .borrowed;
    }

    /// Intern a non-owning storage overlay; an existing overlay remains itself.
    pub fn borrowedType(self: *Module, a: std.mem.Allocator, ty: Type) std.mem.Allocator.Error!Type {
        if (self.isBorrowed(ty)) return ty;
        return self.intern(a, .{ .borrowed = ty });
    }

    const TypeAncestor = struct { ty: Type, parent: ?*const TypeAncestor };

    /// Whether a value contains transient borrowed storage, including a result wrapper.
    pub fn containsBorrow(self: *const Module, ty: Type) bool {
        return self.containsBorrowAt(ty, null);
    }

    fn containsBorrowAt(self: *const Module, ty: Type, previous: ?*const TypeAncestor) bool {
        if (ty.isSpan() or self.isBorrowed(ty)) return true;
        if (!ty.isCompound() or !self.valid(ty)) return false;
        var ancestor = previous;
        while (ancestor) |seen| : (ancestor = seen.parent) if (seen.ty == ty) return false;
        const seen: TypeAncestor = .{ .ty = ty, .parent = previous };
        return switch (self.compound(ty)) {
            .list_view => true,
            // A collection of lent elements (RB2) owns its buffer and lends its elements.
            .list => |element| self.isBorrowed(element),
            .dict => |dict| self.isBorrowed(dict.value),
            .record, .@"union" => |parts| for (parts) |part| {
                if (self.containsBorrowAt(part, &seen)) break true;
            } else false,
            else => false,
        };
    }

    /// The lent element type of a collection of borrows (RB2): a `list` whose elements are read-only overlays of managed
    /// storage. It owns its buffer and never its elements, so its drop frees the buffer alone. Null for any other type.
    pub fn lentElement(self: *const Module, ty: Type) ?Type {
        if (!ty.isCompound() or !self.valid(ty)) return null;
        return switch (self.compound(ty)) {
            .list => |element| if (self.isBorrowed(element)) element else null,
            .dict => |dict| if (self.isBorrowed(dict.value)) dict.value else null,
            else => null,
        };
    }

    /// Whether `instruction` stores an element into a collection of borrows (RB2, `lentElement`): its stored value is lent
    /// to the collection, not consumed, and the updated collection holds it.
    pub fn lentStore(self: *const Module, instruction: Inst) bool {
        return switch (instruction.op) {
            .list_push, .list_set, .dict_set_value, .dict_insert => self.lentElement(instruction.ty) != null,
            else => false,
        };
    }

    /// The owned collection type whose layout a collection of borrows shares (RB2): `list[T]` for `list[borrowed T]`. A read
    /// of the collection as a whole is the read-only overlay of this type. Null for any other type.
    pub fn lentStorage(self: *Module, a: std.mem.Allocator, ty: Type) std.mem.Allocator.Error!?Type {
        const element = self.lentElement(ty) orelse return null;
        const storage = if (self.kind(ty) == .dict)
            try self.intern(a, .{ .dict = .{ .key = self.compound(ty).dict.key, .value = self.storageType(element) } })
        else
            try self.intern(a, .{ .list = self.storageType(element) });
        return storage;
    }

    /// Whether a source can contain storage of the borrowed leaf's physical family.
    pub fn borrowCompatible(self: *const Module, source: Type, leaf: Type) bool {
        return self.borrowCompatibleAt(source, leaf, null);
    }

    fn borrowCompatibleAt(self: *const Module, source: Type, leaf: Type, previous: ?*const TypeAncestor) bool {
        const stored = self.storageType(source);
        if (!self.valid(stored) or !self.valid(leaf)) return false;
        if (self.isBorrowed(leaf) and stored == self.storageType(leaf)) return true;
        // A borrowed record (1A) is made of fields lent from its sources: a source that holds storage of one of its
        // managed fields can lend it.
        if (self.isBorrowed(leaf) and self.kind(self.storageType(leaf)) == .record) {
            for (self.compound(self.storageType(leaf)).record) |field| {
                if (!self.managed(field)) continue;
                if (self.lendableField(stored, field, 0)) return true;
            }
        }
        if (leaf == .str_view and (stored == .str or stored == .str_view)) return true;
        if (leaf == .bytes_view and (stored == .bytes or stored == .byte_buffer or stored == .bytes_view)) return true;
        if (self.kind(leaf) == .list_view) {
            const element = self.compound(leaf).list_view;
            if (self.listElement(stored)) |candidate| if (candidate == element) return true;
        }
        if (!stored.isCompound()) return false;
        var ancestor = previous;
        while (ancestor) |seen| : (ancestor = seen.parent) if (seen.ty == stored) return false;
        const seen: TypeAncestor = .{ .ty = stored, .parent = previous };
        return switch (self.compound(stored)) {
            .record, .@"union" => |parts| for (parts) |part| {
                if (self.borrowCompatibleAt(part, leaf, &seen)) break true;
            } else false,
            .box, .list, .list_view => |child| self.borrowCompatibleAt(child, leaf, &seen),
            .array => |array| self.borrowCompatibleAt(array.elem, leaf, &seen),
            .dict => |dict| self.borrowCompatibleAt(dict.key, leaf, &seen) or self.borrowCompatibleAt(dict.value, leaf, &seen),
            .borrowed => false,
            .@"fn" => false,
        };
    }

    /// Whether `source` is or holds storage of type `field`, through records, unions, boxes, lists, arrays and dictionaries.
    /// Whether a source of type `stored` can lend borrowed-record field `field`: it holds storage of the field, or, for an
    /// option field holding a lent projection (`Some(owner.a)`, RB1), of one of the option's payloads.
    fn lendableField(self: *const Module, stored: Type, field: Type, depth: u32) bool {
        if (self.storageWithin(stored, field, null)) return true;
        if (depth > 8 or !self.valid(field) or self.kind(field) != .@"union") return false;
        for (self.compound(field).@"union") |part| {
            if (part == .void or !self.managed(part)) continue;
            if (self.lendableField(stored, part, depth + 1)) return true;
        }
        return false;
    }

    fn storageWithin(self: *const Module, source: Type, field: Type, previous: ?*const TypeAncestor) bool {
        const stored = self.storageType(source);
        if (stored == field) return true;
        if (!stored.isCompound() or !self.valid(stored)) return false;
        var ancestor = previous;
        while (ancestor) |seen| : (ancestor = seen.parent) if (seen.ty == stored) return false;
        const seen: TypeAncestor = .{ .ty = stored, .parent = previous };
        return switch (self.compound(stored)) {
            .record, .@"union" => |parts| for (parts) |part| {
                if (self.storageWithin(part, field, &seen)) break true;
            } else false,
            .box, .list, .list_view => |child| self.storageWithin(child, field, &seen),
            .array => |array| self.storageWithin(array.elem, field, &seen),
            .dict => |dict| self.storageWithin(dict.key, field, &seen) or self.storageWithin(dict.value, field, &seen),
            .borrowed, .@"fn" => false,
        };
    }

    /// Resolve a declared borrowed leaf or final returned owner projection.
    pub fn projectedType(self: *const Module, root: Type, path: []const BorrowProjection) ?Type {
        var current = root;
        for (path) |step| {
            const stored = self.storageType(current);
            if (!stored.isCompound() or !self.valid(stored)) return null;
            const value = self.compound(stored);
            switch (step) {
                .field => |index| {
                    if (value != .record or index >= value.record.len) return null;
                    current = value.record[index];
                },
                .payload => |tag| {
                    if (value != .@"union" or tag >= value.@"union".len or value.@"union"[tag] == .void) return null;
                    current = value.@"union"[tag];
                },
            }
        }
        return current;
    }

    /// Check source bounds, transient result shape and final-owner acyclicity.
    pub fn validBorrow(self: *const Module, signature: Signature) bool {
        const contract = signature.borrow;
        if (contract.sources.len == 0) return contract.path.len == 0 and !self.containsBorrow(signature.ret);
        const leaf = self.projectedType(signature.ret, contract.path) orelse return false;
        if (!self.isView(leaf) and !self.isBorrowed(leaf)) return false;
        if (self.isBorrowed(leaf)) {
            const stored = self.storageType(leaf);
            if (stored == leaf or !self.valid(stored)) return false;
            if (!self.managed(stored) or self.containsBorrow(stored)) return false;
        }
        var current = signature.ret;
        for (contract.path, 0..) |step, depth| {
            const value = self.compound(current);
            switch (step) {
                .field => |index| {
                    if (depth != 0 or index != 0 or value != .record) return false;
                    for (value.record[1..]) |sibling| if (self.containsBorrow(sibling)) return false;
                    current = value.record[0];
                },
                .payload => |tag| {
                    if (value != .@"union" or value.@"union".len != 2) return false;
                    for (value.@"union", 0..) |sibling, index| if (index != tag and self.containsBorrow(sibling)) return false;
                    current = value.@"union"[tag];
                },
            }
        }
        for (contract.sources) |source| switch (source) {
            .argument => |position| {
                if (position >= signature.params.len) return false;
                const parameter = signature.params[position];
                const has_storage = self.managed(parameter) or self.containsBorrow(parameter);
                if (!has_storage or !self.borrowCompatible(parameter, leaf)) return false;
            },
            .result => |path| {
                if (path.len == 0 or path.len > contract.path.len and samePath(path[0..contract.path.len], contract.path)) return false;
                if (path.len <= contract.path.len and samePath(path, contract.path[0..path.len])) return false;
                const owner = self.projectedType(signature.ret, path) orelse return false;
                if (!self.managed(owner) or self.containsBorrow(owner)) return false;
                if (!self.borrowCompatible(owner, leaf)) return false;
            },
        };
        return true;
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

    /// The element type of list `ty` or of list view `ty` (C9 lists), or null for any other type.
    pub fn listElement(self: *const Module, ty: Type) ?Type {
        return switch (self.kind(ty) orelse return null) {
            .list => self.compound(ty).list,
            .list_view => self.compound(ty).list_view,
            else => null,
        };
    }

    /// Whether `ty` is a borrowed view: the SSA-only `str_view`, or a list view
    /// (a borrowed span of a list's elements). A view has no storable layout.
    pub fn isView(self: *const Module, ty: Type) bool {
        if (ty.isSpan()) return true;
        return ty.isCompound() and std.meta.activeTag(self.compound(ty)) == .list_view;
    }

    /// Whether `ty` is a managed leaf, collection, authority, resource or box pointer.
    pub fn isBlock(self: *const Module, ty: Type) bool {
        if (ty == .str or ty == .bytes or ty == .byte_buffer) return true;
        if (ty == .capability or ty == .resource) return true;
        const k = self.kind(ty) orelse return false;
        return k == .list or k == .box or k == .dict;
    }

    /// Whether a value owns a managed block directly or within a field/payload.
    /// These values need lifetime analysis and direct destruction.
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
        return self.layoutOf(ty).size;
    }

    /// The alignment of `ty` in memory, in bytes.
    pub fn alignment(self: *const Module, ty: Type) u32 {
        return self.layoutOf(ty).alignment;
    }

    /// The size and alignment of a type in memory.
    const Layout = struct { size: u32, alignment: u32 };

    /// Size and alignment of `ty` together, so a record reads each field's layout once: asking for the size and then for the alignment
    /// of every field, and of the record again, walks a nested type once per nesting level and per question (emission asks for the
    /// layout of nearly every operand it renders).
    fn layoutOf(self: *const Module, ty: Type) Layout {
        if (self.isBorrowed(ty)) return self.layoutOf(self.storageType(ty));
        const bytes: u32 = switch (ty) {
            .void => 0,
            .bool, .i8, .u8 => 1,
            .i16, .u16 => 2,
            .i32, .u32, .f32 => 4,
            .i64, .u64, .f64, .cap => 8,
            .str, .bytes, .byte_buffer, .capability, .resource, .task_group, .task_handle => self.lowering.pointer_bytes,
            .str_view, .bytes_view => 16,
            _ => return self.compoundLayout(ty),
        };
        return .{ .size = bytes, .alignment = if (ty.isSpan()) 8 else @max(1, bytes) };
    }

    fn compoundLayout(self: *const Module, ty: Type) Layout {
        return switch (self.compound(ty)) {
            .list, .box, .dict, .@"fn" => .{ .size = self.lowering.pointer_bytes, .alignment = self.lowering.pointer_bytes },
            .list_view => .{ .size = 16, .alignment = 8 },
            .borrowed => |inner| self.layoutOf(inner),
            .array => |array| blk: {
                const element = self.layoutOf(array.elem);
                const bytes = array.n * element.size;
                break :blk .{ .size = bytes, .alignment = if (array.vector) @max(element.alignment, bytes) else element.alignment };
            },
            .record => |fields| blk: {
                var offset: u32 = 0;
                var most: u32 = 1;
                for (fields) |field| {
                    const member = self.layoutOf(field);
                    offset = std.mem.alignForward(u32, offset, member.alignment) + member.size;
                    most = @max(most, member.alignment);
                }
                break :blk .{ .size = std.mem.alignForward(u32, offset, most), .alignment = most };
            },
            .@"union" => blk: {
                const layout = self.unionLayout(ty);
                if (layout.form == .niche) break :blk .{ .size = self.lowering.pointer_bytes, .alignment = self.lowering.pointer_bytes };
                break :blk .{ .size = 8 + 8 * layout.payload_words, .alignment = 8 };
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
        if (self.isBorrowed(ty)) return self.passedInMemory(self.storageType(ty));
        const k = self.kind(ty) orelse return false;
        // A vector stays in SSA: LLVM passes `<N x T>` in registers, so no call boundary spills it.
        if (k == .array and self.compound(ty).array.vector) return false;
        return (k == .record or k == .@"union" or k == .array) and self.words(ty) > max_register_words;
    }

    /// The byte offset of field `index` inside a record of type `record`.
    pub fn fieldOffset(self: *const Module, record: Type, index: usize) u32 {
        const fields = self.compound(self.storageType(record)).record;
        var offset: u32 = 0;
        for (fields[0..index]) |field| offset = std.mem.alignForward(u32, offset, self.alignment(field)) + self.size(field);
        return std.mem.alignForward(u32, offset, self.alignment(fields[index]));
    }

    /// The layout of union type `ty` (§4).
    pub fn unionLayout(self: *const Module, ty: Type) UnionLayout {
        const cases = self.compound(self.storageType(ty)).@"union";
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

/// Whether two compound descriptions are the same type, as `Module.intern` judges it (an array's `vector` flag is not part of
/// the comparison).
pub fn sameCompound(x: Compound, y: Compound) bool {
    if (std.meta.activeTag(x) != std.meta.activeTag(y)) return false;
    return switch (x) {
        .list => |element| element == y.list,
        .list_view => |element| element == y.list_view,
        .box => |inner| inner == y.box,
        .borrowed => |inner| inner == y.borrowed,
        .record => |fields| std.mem.eql(Type, fields, y.record),
        .@"union" => |cases| std.mem.eql(Type, cases, y.@"union"),
        .dict => |dict| dict.key == y.dict.key and dict.value == y.dict.value,
        .array => |array| array.elem == y.array.elem and array.n == y.array.n,
        .@"fn" => |signature| signature.eql(y.@"fn"),
    };
}

test "declared result borrowing compares all argument and final owner paths" {
    const first: Signature = .{ .params = &.{.str}, .ret = .str_view, .borrow = .{ .sources = &.{.{ .argument = 0 }} } };
    try std.testing.expectEqual(@as(?usize, 0), first.viewSource());
    try std.testing.expect(first.eql(first));
    var changed = first;
    changed.borrow = .{ .sources = &.{.{ .result = &.{.{ .field = 1 }} }} };
    try std.testing.expect(!first.eql(changed));
    try std.testing.expectEqual(@as(?usize, null), changed.viewSource());
}

test "parameter passing preserves arbitrary positions and owns retained metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var passing: ParameterPassing = .{};
    try passing.setOwned(a, 70);
    try passing.setOwned(a, 2);
    try passing.setOwned(a, 65);
    try passing.setOwned(a, 70);
    try passing.setConsumes(a, 69);
    try passing.setView(a, 68);
    try std.testing.expect(passing.valid(71));
    try std.testing.expect(!passing.valid(70));
    try std.testing.expect(passing.ownedAt(2) and passing.ownedAt(65) and passing.ownedAt(70));
    try std.testing.expect(!passing.ownedAt(64) and passing.takes(69) and passing.viewAt(68));
    try std.testing.expectEqualSlices(u32, &.{ 65, 70 }, passing.extra_owned);
    const retained = try passing.clone(a);
    @constCast(passing.extra_owned)[0] = 64;
    try std.testing.expect(!passing.eql(retained));
    try std.testing.expectEqualSlices(u32, &.{ 65, 70 }, retained.extra_owned);
    var overlapping = retained;
    try overlapping.setConsumes(a, 70);
    try std.testing.expect(!overlapping.valid(71));
}

test "borrowed result contracts validate payload families and final writeback owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: Module = .{};
    const optional = try module.intern(a, .{ .@"union" = &.{ .void, .str_view } });
    const fallible = try module.intern(a, .{ .@"union" = &.{ optional, .bytes } });
    const returned = try module.intern(a, .{ .record = &.{ fallible, .str } });
    const contract: BorrowContract = .{
        .path = &.{ .{ .field = 0 }, .{ .payload = 0 }, .{ .payload = 1 } },
        .sources = &.{.{ .result = &.{.{ .field = 1 }} }},
    };
    var signature: Signature = .{ .params = &.{.str}, .ret = returned, .passing = .{ .owned = 1 }, .borrow = contract };
    try std.testing.expect(module.validBorrow(signature));
    try std.testing.expect(module.managed(returned));
    try std.testing.expect(!module.managed(optional));
    // An error is still owned, while the success span and mutable owner have
    // distinct paths and cannot become each other's ownership ancestor.
    try std.testing.expect(module.managed(fallible));
    signature.borrow.sources = &.{.{ .result = contract.path }};
    try std.testing.expect(!module.validBorrow(signature));
    signature.borrow.sources = &.{.{ .argument = 1 }};
    try std.testing.expect(!module.validBorrow(signature));
    signature.borrow.sources = &.{.{ .argument = 0 }};
    signature.params = &.{.bytes};
    try std.testing.expect(!module.validBorrow(signature));
    signature.params = &.{.str};
    try std.testing.expect(module.validBorrow(signature));
    const retained = try signature.clone(a);
    try std.testing.expect(signature.eql(retained));
    signature.borrow.path = &.{.{ .field = 1 }};
    try std.testing.expect(!signature.eql(retained));
    try std.testing.expect(samePath(contract.path, retained.borrow.path));
}

/// The layout rules as they were written before `layoutOf` asked for size and alignment together: the size of a record asks for the
/// alignment of each field, then the size of each field, then the alignment of the record. The test below holds the one-pass answer to it.
fn referenceSize(m: *const Module, ty: Type) u32 {
    if (m.isBorrowed(ty)) return referenceSize(m, m.storageType(ty));
    return switch (ty) {
        .void => 0,
        .bool, .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32, .f32 => 4,
        .i64, .u64, .f64, .cap, .str, .bytes, .byte_buffer, .capability, .resource, .task_group, .task_handle => 8,
        .str_view, .bytes_view => 16,
        _ => switch (m.compound(ty)) {
            .list, .box, .dict, .@"fn" => 8,
            .list_view => 16,
            .borrowed => |inner| referenceSize(m, inner),
            .array => |array| array.n * referenceSize(m, array.elem),
            .record => |fields| blk: {
                var offset: u32 = 0;
                for (fields) |field| offset = std.mem.alignForward(u32, offset, referenceAlignment(m, field)) + referenceSize(m, field);
                break :blk std.mem.alignForward(u32, offset, referenceAlignment(m, ty));
            },
            .@"union" => blk: {
                const layout = m.unionLayout(ty);
                break :blk if (layout.form == .niche) 8 else 8 + 8 * layout.payload_words;
            },
        },
    };
}

fn referenceAlignment(m: *const Module, ty: Type) u32 {
    if (m.isBorrowed(ty)) return referenceAlignment(m, m.storageType(ty));
    if (ty.isSpan()) return 8;
    if (!ty.isCompound()) return @max(1, referenceSize(m, ty));
    return switch (m.compound(ty)) {
        .list, .box, .dict, .@"fn", .list_view, .@"union" => 8,
        .borrowed => |inner| referenceAlignment(m, inner),
        .array => |array| if (array.vector) @max(referenceAlignment(m, array.elem), referenceSize(m, ty)) else referenceAlignment(m, array.elem),
        .record => |fields| blk: {
            var most: u32 = 1;
            for (fields) |field| most = @max(most, referenceAlignment(m, field));
            break :blk most;
        },
    };
}

test "size and alignment from one layout walk equal the question-by-question rules on nested types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: Module = .{};
    const small = try module.intern(a, .{ .record = &.{ .u8, .bool, .i16 } });
    const mixed = try module.intern(a, .{ .record = &.{ .u8, .f64, .i32, small } });
    const empty = try module.intern(a, .{ .record = &.{} });
    const deep = try module.intern(a, .{ .record = &.{ .bool, mixed, .u16, empty, small } });
    const lists = try module.intern(a, .{ .list = deep });
    const boxed = try module.intern(a, .{ .box = mixed });
    const array = try module.intern(a, .{ .array = .{ .elem = mixed, .n = 3 } });
    const vector = try module.intern(a, .{ .array = .{ .elem = .f32, .n = 8, .vector = true } });
    const narrow = try module.intern(a, .{ .array = .{ .elem = .u8, .n = 5 } });
    const view = try module.intern(a, .{ .list_view = deep });
    const dict = try module.intern(a, .{ .dict = .{ .key = .str, .value = deep } });
    const optional = try module.option(a, boxed);
    const words = try module.intern(a, .{ .@"union" = &.{ .void, mixed, deep } });
    const scalar_union = try module.intern(a, .{ .@"union" = &.{ .i32, .i32 } });
    const wrapped = try module.intern(a, .{ .record = &.{ .u8, words, optional, vector, array } });
    const overlay = try module.intern(a, .{ .borrowed = wrapped });
    const types = [_]Type{
        .void,        .bool,   .u8,     .i16, .i32,  .f32,  .i64,  .f64,   .str,   .bytes, .byte_buffer, .str_view, .bytes_view,
        small,        mixed,   empty,   deep, lists, boxed, array, vector, narrow, view,   dict,         optional,  words,
        scalar_union, wrapped, overlay,
    };
    for (types) |ty| {
        try std.testing.expectEqual(referenceSize(&module, ty), module.size(ty));
        try std.testing.expectEqual(referenceAlignment(&module, ty), module.alignment(ty));
    }
    // A task group has never had an alignment of its own (it is not a compound, yet its number is one): its size is a word.
    try std.testing.expectEqual(@as(u32, 8), module.size(.task_group));
    try std.testing.expectEqual(@as(u32, 8), module.alignment(.task_group));
    try std.testing.expectEqual(@as(u32, 1), module.alignment(empty));
    try std.testing.expectEqual(@as(u32, 0), module.size(empty));
    try std.testing.expectEqual(@as(u32, 32), module.size(vector));
    try std.testing.expectEqual(@as(u32, 32), module.alignment(vector));
}
