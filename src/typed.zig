//! Checked nodes use declaration identities, concrete types, and local slots.
const std = @import("std");
const provider_contracts = @import("provider_contracts.zig");
const external_resources = @import("external_resources.zig");
const values = @import("value.zig");
const Span = @import("source.zig").Span;
/// Index of a checked expression in Program.nodes.
pub const NodeId = enum(usize) { _ };
/// Index of a checked statement in Program.statements.
pub const StatementId = enum(usize) { _ };
/// Index of a resolved function in Program.functions.
pub const FunctionId = enum(usize) { _ };
/// Index of a function-local value slot.
pub const LocalId = enum(usize) { _ };
pub const Type = @import("type_identity.zig").Type;
pub const Value = values.Value;
/// Checked arithmetic, logical, and comparison operation categories.
pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    rem,
    floor_div,
    floor_rem,
    logical_and,
    logical_or,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    bit_and,
    bit_or,
    bit_xor,
    shift_left,
    shift_right,
    wrapping_add,
    wrapping_sub,
    wrapping_mul,
    saturating_add,
    saturating_sub,
    saturating_mul,
    f64_add,
    f64_sub,
    f64_mul,
    f64_div,
    f64_eq,
    f64_lt,
    f64_le,
    f32_add,
    f32_sub,
    f32_mul,
    f32_div,
    f32_eq,
    f32_lt,
    f32_le,
};
/// Checked numeric negation and Boolean inversion operations.
pub const UnaryOp = enum {
    neg,
    not,
    bit_not,
    f64_sqrt,
    f64_floor,
    f64_ceil,
    f64_trunc,
    f64_abs,
    f64_neg,
    f64_from_u64,
    f64_to_u64,
    f64_from_i64,
    f64_to_i64,
    f64_to_i8,
    f64_to_i16,
    f64_to_i32,
    f64_to_u8,
    f64_to_u16,
    f64_to_u32,
    f64_sin,
    f64_cos,
    /// The IEEE bit pattern of a `float`, as `u64` (`__float_bits`).
    f64_bits,
    /// A `float` from its IEEE bit pattern, given as `u64` (`__float_from_bits`).
    f64_from_bits,
    /// The IEEE bit pattern of an `f32`, as `u32` (`__f32_bits`).
    f32_bits,
    /// An `f32` from its IEEE bit pattern, given as `u32` (`__f32_from_bits`).
    f32_from_bits,
    f32_neg,
    f32_sqrt,
    f32_floor,
    f32_ceil,
    f32_trunc,
    f32_abs,
    f32_from_i64,
    f32_from_u64,
    f32_to_i8,
    f32_to_i16,
    f32_to_i32,
    f32_to_i64,
    f32_to_u8,
    f32_to_u16,
    f32_to_u32,
    f32_to_u64,
    /// Widen an `f32` to `float` (exact).
    f64_from_f32,
    /// Round a `float` to the nearest `f32`.
    f32_from_f64,
};
/// Whether any expression of `program` is a typed hole checked in trap mode (`Node.data == .hole`).
pub fn hasHole(program: Program) bool {
    for (program.nodes) |node| if (std.meta.activeTag(node.data) == .hole) return true;
    return false;
}
/// How the name of the hidden local that holds a `detach` loop's collection while the loop runs begins (`loop_detach.zig`):
/// the word, a space and the place (`detached ev.items`). No source can spell it, and the ownership check knows the
/// put-back that moves it by this name (`single_owner.zig`, `detachExit`).
pub const detach_owner = "detached ";

/// `message` with each name of a `detach` loop's hidden local (`detach_owner`) written as what the user wrote: "the local
/// `detached ev.items`" reads "the list the `detach` loop set aside from `ev.items`", and any other quoted `detached ev.items`
/// reads `ev.items`. A message without one is returned as it is.
pub fn withDetachedNamesWritten(allocator: std.mem.Allocator, message: []const u8) std.mem.Allocator.Error![]const u8 {
    if (std.mem.indexOf(u8, message, detach_owner) == null) return message;
    var text: std.ArrayList(u8) = .empty;
    var at: usize = 0;
    while (at < message.len) {
        const quote = message[at];
        const opens = (quote == '`' or quote == '\'') and std.mem.startsWith(u8, message[at + 1 ..], detach_owner);
        const close = if (opens) std.mem.indexOfScalarPos(u8, message, at + 1, quote) else null;
        const end = close orelse {
            try text.append(allocator, quote);
            at += 1;
            continue;
        };
        const place = message[at + 1 + detach_owner.len .. end];
        if (std.mem.endsWith(u8, text.items, "the local ")) {
            text.shrinkRetainingCapacity(text.items.len - "the local ".len);
            try text.appendSlice(allocator, "the list the `detach` loop set aside from ");
        }
        try text.append(allocator, quote);
        try text.appendSlice(allocator, place);
        try text.append(allocator, quote);
        at = end + 1;
    }
    return text.items;
}

test "a detach loop's hidden local is written as the place the user wrote" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings(
        "`b.name` is lent by the list the `detach` loop set aside from `ev.items`, and the place needs its own value",
        try withDetachedNamesWritten(a, "`b.name` is lent by the local `detached ev.items`, and the place needs its own value"),
    );
    try std.testing.expectEqualStrings("'ev.items' borrows from `r`", try withDetachedNamesWritten(a, "'detached ev.items' borrows from `r`"));
    try std.testing.expectEqualStrings("nothing hidden", try withDetachedNamesWritten(a, "nothing hidden"));
}
/// Typed expression with resolved operands and source location.
pub const Node = struct {
    ty: Type,
    span: Span,
    /// A slice expression (`s[a:b]`, `b[a:b]`, `xs[a:b]`) is a view of its
    /// source from this wave on, so it may not be moved into owning storage.
    /// `strings.char_slice` is a view too (`collection_lower.zig` sets this on
    /// its slice node); the stepped helpers (`char_stride`, `lists.stride`) copy.
    view: bool = false,
    /// The source wrote `own` on this expression. The marker's outer span is
    /// retained; Core decides whether this occurrence transfers ownership.
    own: bool = false,
    /// The original expression's symbolic type contains a generic parameter.
    /// This source fact is independent of the selected concrete instance type.
    type_dependent: bool = false,
    data: union(enum) {
        integer: i128,
        boolean: bool,
        unit,
        block_value: struct { body: StatementId, value: NodeId },
        borrow_selection: BorrowSelection,
        function_value: FunctionId,
        invoke: struct { evaluation_order: []const usize = &.{}, callee: NodeId, arguments: []const NodeId },
        local: LocalId,
        propagate: struct { value: NodeId, output: Type },
        buffer_operation: struct {
            kind: @import("buffer_operations.zig").Kind,
            owner: LocalId,
            arguments: []const NodeId,
            /// A scalar helper's search keeps scalar positions and a scalar window (C2).
            scalar: bool = false,
            /// A dictionary store `d[key] = value` whose key is written as a place (a name, a field or an element)
            /// reads it as a borrow: the table copies the key only when it is new, and an existing key keeps its
            /// stored copy (copy on insert). Set only for a managed key type; `d[copy(key)]` and `d[own key]` leave it clear.
            borrowed_key: bool = false,
        },
        acquire_resource: struct { capability: NodeId, request: NodeId },
        complete_resource: NodeId,
        resource_io: struct { kind: external_resources.IoKind, owner: LocalId, value: ?NodeId },
        restrict_resource: struct { permissions: external_resources.Permissions, value: NodeId },
        dir_resource: struct { capability: NodeId, path: NodeId },
        host_resource: struct { capability: NodeId, name: NodeId },
        environment_get: struct { capability: NodeId, name: NodeId },
        environment_only: struct { capability: NodeId, names: NodeId },
        environment_names: NodeId,
        external_read: struct { kind: @import("external_capabilities.zig").Kind, capability: NodeId },
        stand_in: struct { kind: @import("external_capabilities.zig").StandIn, first: NodeId, second: ?NodeId },
        acquire_buffer: struct { capacity: NodeId },
        print: Print,
        stream_write: StreamWrite,
        file_access: FileAccess,
        file_method: FileMethod,
        arena_escape: NodeId,
        cast: NodeId,
        wrap: NodeId,
        variant: struct { tag: usize, value: ?NodeId },
        unwrap: NodeId,
        array: []const NodeId,
        /// A file `embed_bytes`/`embed_str` read at load time, as `bytes` or
        /// `str` static data with no per-byte nodes (`EMBED-1`).
        blob: Blob,
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: []const FieldInit,
        update: struct { base: NodeId, fields: []const FieldInit },
        field: struct { base: NodeId, index: usize },
        call: struct { evaluation_order: []const usize = &.{}, function: FunctionId, arguments: []const NodeId },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
        accept_resource: LocalId,
        /// Appended last so the encoding of every earlier node keeps its tag, which
        /// the ownership digest covers (NEW-CORE-ZERO-RC-CACHE-1).
        stream_flush: StreamFlush,
        /// A whole `f"..."` literal, kept as its pieces until Core
        /// (`PY-FSTRING-1`): printing or writing it emits the pieces in order,
        /// and using it as a `str` fills one buffer. Appended last for the same
        /// reason as `stream_flush`.
        format: Format,
        /// A fused multiply-add `a * b + c` of one floating width, rounded once (`math.fma`). Appended
        /// last so that the variants before it keep their tags, and every digest over them.
        float_fma: struct { a: NodeId, b: NodeId, c: NodeId, op_span: Span },
        /// Elementwise `+ - * /` or a comparison of two `Simd` values of one type; a comparison answers `Simd[bool, N]`.
        vector_binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
        /// Elementwise negation of one `Simd` value.
        vector_neg: struct { operand: NodeId, op_span: Span },
        vector_sqrt: struct { operand: NodeId, op_span: Span },
        vector_convert: struct { operand: NodeId, op_span: Span },
        /// `simd.select(mask, a, b)`: lane `i` is `a[i]` where `mask[i]` holds, else `b[i]`.
        vector_select: struct { mask: NodeId, a: NodeId, b: NodeId, op_span: Span },
        /// `parallel.group()` opened by a `with` scope: the resource the scope closes, whose
        /// group is the scope's slot (E1). Appended last, as the variants above keep their tags.
        task_group_open,
        /// `g.submit(fn, ARGS)`: `call` is the checked direct call `fn(ARGS)` the task runs and
        /// `group` the group's local. Its type is `task_handle` when a `const` binding takes it, and
        /// `unit` for the bare statement, which submits a procedure that returns nothing (E1).
        task_submit: struct { group: LocalId, call: NodeId },
        /// `t.result()` of the handle `t` names: the task's value, or its checked result for a fallible
        /// function. The node's type is that value's type; reading it joins the task first (E1).
        task_result: LocalId,
        /// A fixed-width read of `bytes` at `offset` (`bytes.read_u32_be` and its siblings): the node's type
        /// is the width (`u16`..`u64`, `i16`..`i64`, `f32` or `f64`); `big_endian` selects the byte order.
        /// Appended last so the variants before it keep their tags and every digest over them.
        byte_load: struct { bytes: NodeId, offset: NodeId, big_endian: bool, op_span: Span },
        /// A `todo[T]()` typed hole checked in trap mode (`diagnostic.HoleMode.trap`): an expression of its
        /// declared type whose evaluation traps `R_TYPED_HOLE` at the node's span. Appended last so the
        /// variants before it keep their tags and every digest over them.
        hole,
        /// `take(mut place)` and `exchange(mut place, value)` (LANG1 item 3): the place's current value moves to
        /// the result and `value` (the type's empty value when null, for `take`) takes its place. `place` is a
        /// record-field chain of a mutable local, written and never moved from. Appended last, as the variants
        /// above keep their tags and every digest over them.
        place_exchange: struct { place: NodeId, value: ?NodeId },
    },
};
/// Compiler-generated selection borrows one of two eagerly evaluated inputs.
/// Inputs evaluate exactly once, first then second; no source syntax names this node.
pub const BorrowSelection = struct {
    kind: enum { min_text, max_text, optional_default },
    first: NodeId,
    second: NodeId,
};

/// An embedded file (`EMBED-1`) as checked code names it: the content digest
/// that identifies its static object and the payload length. The bytes stay with
/// the loaded source, so a checked tree carries no per-byte data.
pub const Blob = struct { digest: [32]u8, length: usize };
/// Whole-path file helper: its operands begin with the `Filesystem` capability.
pub const FileAccess = struct { kind: @import("file_operations.zig").Access, mode: u8, text: bool, arguments: []const NodeId, shapes: FileShapes };
/// Method call on an open `with` binding, addressed by its local slot.
pub const FileMethod = struct { kind: @import("file_operations.zig").Method, owner: LocalId, text: bool, argument: ?NodeId, shapes: FileShapes };
/// Nominal payload schemas a file operation needs to build its result.
pub const FileShapes = struct { text: Type, bytes: Type, list: Type };
/// Which standard stream an ambient `print` writes to when no receiver is given.
/// `error_report` is standard error as the entry wrapper reports `main`'s `Err`:
/// the line opens with `error: ` and the error return trace follows it.
pub const Sink = enum { stdout, stderr, error_report };
/// Rendered arguments and the optional `sep=`/`end=` text of one output call.
/// A `stream` receiver selects the fd at runtime; a `debug` call writes to stderr
/// and contributes no effect.
pub const Print = struct { sink: Sink = .stdout, arguments: []const NodeId, separator: ?NodeId, terminator: ?NodeId, stream: ?NodeId = null, debug: bool = false };
/// `stream.write(text)`: the receiver stream value and the text to write.
pub const StreamWrite = struct { stream: NodeId, text: NodeId };
/// `flush(stream)`: push the stream's buffered bytes to its descriptor now.
pub const StreamFlush = struct { stream: NodeId };
/// One `f"..."` literal (`PY-FSTRING-1`) as its pieces, in source order. Nothing
/// is joined, copied or converted at check time: the pieces reach Core as they
/// were written, so printing one needs no text buffer at all.
pub const Format = struct { pieces: []const FormatPiece };
/// One piece of a format string: literal bytes with their escapes already
/// decoded, or one interpolated value.
pub const FormatPiece = union(enum) {
    literal: []const u8,
    hole: FormatHole,
};
/// One interpolation: the checked value, read (never moved) when the string is
/// rendered, and the resolved specification the source gave it, if any.
pub const FormatHole = struct { value: NodeId, spec: ?FormatSpec = null };
/// A hole's resolved format specification: the family it applies to and the
/// word `format_spec.pack` made of it, which the runtime renders with.
pub const FormatSpec = struct { family: FormatFamily, word: u64 };
/// The value family a format specification applies to, in `format_spec.Family`
/// order: the checker resolves one and Core chooses the runtime renderer.
pub const FormatFamily = @import("format_spec.zig").Family;
/// The word a hole with no written specification renders with: the family's plain
/// spelling, which is the text `print` writes for the same value.
pub fn plainWord(family: FormatFamily) u64 {
    return @import("format_spec.zig").pack(.{ .family = family, .kind = switch (family) {
        .text => .s,
        .float => .none,
        .signed, .unsigned => .d,
    } });
}
/// Resolved aggregate field index and the expression supplying its value.
pub const FieldInit = struct { index: usize, value: NodeId };
/// Named aggregate field with its declaration location and resolved type.
/// `default_value` is the backing node id of a declared record-field default.
/// `boxed` marks a field that closes a recursive value type: it stores a
/// pointer to an immutable managed box, while `ty` stays the value's own type
/// everywhere the checker looks (RECURSIVE-VALUES-2).
pub const Field = struct { name: []const u8, declaration: Span, ty: Type, default_value: ?usize = null, boxed: bool = false };
/// Named closed variant case and its optional resolved payload type.
/// `fielded` marks a parenthesized case whose payload is one synthesized record
/// of named fields, so construction and patterns bind one name per field.
/// `boxed` marks a payload that closes a recursive value type and is stored
/// behind an immutable managed box (RECURSIVE-VALUES-2).
pub const Variant = struct { name: []const u8, declaration: Span, payload: ?Type, fielded: bool = false, boxed: bool = false };
/// Closed case set distinguishing enums, unions, and fallible results.
pub const Variants = struct { fallible: bool = false, is_union: bool, cases: []const Variant };
/// Fixed element count and type, with an optional enum key for tables.
/// `vector` marks a `Simd[T, N]` value: the same lanes as a fixed array, but a distinct type with
/// elementwise operators, passed in registers as one LLVM vector (`<N x T>`).
pub const Array = struct { element: Type, length: usize, key: ?Type = null, vector: bool = false };
// Aggregate schemas retain nominal record identities and intern structural arrays.
/// Nominal aggregate schema and associated array, domain, collection, or variant metadata.
pub const Record = struct {
    collection: @import("type_identity.zig").CollectionShape = .{},
    managed: bool = false,
    id: Type,
    name: []const u8,
    declaration: Span,
    fields: []const Field,
    shape: RecordShape = .{},
    contract: RecordContract = .{},
    /// Return the enum key type for a table, or null for other aggregates.
    pub fn tableKey(self: Record) ?Type {
        return if (self.shape.array) |a| a.key else null;
    }
    /// Identify a plain record rather than a specialized aggregate schema.
    pub fn isRecord(self: Record) bool {
        return !self.shape.hasRuntimeIdentity() and !self.shape.hasValueRepresentation();
    }
    /// The builtin Cell is the managed record with a closed one-field content policy.
    pub fn isCell(self: Record) bool {
        return self.managed and self.isRecord() and self.shape.builtin == .cell;
    }
    /// A managed nominal record: the builtin Cell or a user `class` declaration.
    /// Managed records carry reference identity, so assignment and calls share them.
    pub fn isManagedRecord(self: Record) bool {
        return self.managed and self.isRecord();
    }
    /// Managed collection operations require an element buffer, unlike Cell fields.
    pub fn isCollection(self: Record) bool {
        return self.managed and self.shape.buffer != null;
    }
    /// Identify a payload-free enum schema.
    pub fn isEnum(self: Record) bool {
        return if (self.shape.variants) |v| !v.is_union else false;
    }
    /// Return the number of statically addressable aggregate elements.
    pub fn count(self: Record) usize {
        return if (self.shape.array) |a| a.length else if (self.shape.domain != null) 1 else self.fields.len;
    }
    /// Call `visit(context, type, at)` for every type this record stores directly, in the order the stored-file rule (P4) reads
    /// them, `at` being the span of the field or case that names it (the record's own declaration for an element, key, value,
    /// parameter or result). A collection stores its keys and values and nothing else; a fixed array of no elements stores
    /// nothing. The open file in the payload of a fallible variant (the `Result[File, str]` of `fs.open`) is handed on rather
    /// than stored, so it is not visited. These two exceptions are made here and nowhere else. The walk of a
    /// local's type (`single_owner_files.zig`) and the check of a declaration (`record_layouts.zig`) read their edges here, so
    /// they refuse the same text.
    pub fn eachStored(self: Record, comptime Failure: type, context: anytype, comptime visit: fn (@TypeOf(context), Type, Span) Failure!void) Failure!void {
        if (self.isCollection()) {
            if (self.collection.kind == .dictionary) {
                try visit(context, self.collection.key.?, self.declaration);
                if (!self.collection.set) try visit(context, self.shape.buffer.?, self.declaration);
            }
            if (self.collection.kind == .list) try visit(context, self.shape.buffer.?, self.declaration);
            return;
        }
        for (self.fields) |field| try visit(context, field.ty, field.declaration);
        if (self.shape.array) |array| if (array.length != 0) try visit(context, array.element, self.declaration);
        if (self.shape.variants) |variants| for (variants.cases) |case| {
            const payload = case.payload orelse continue;
            if (variants.fallible and payload.isFile()) continue;
            try visit(context, payload, case.declaration);
        };
        if (self.contract.callback) |callback| {
            for (callback.parameters) |parameter| try visit(context, parameter, self.declaration);
            try visit(context, callback.return_type, self.declaration);
        }
    }
};
/// Optional specialized representations; bytecode validation rejects incompatible combinations.
pub const RecordShape = struct {
    array: ?Array = null,
    domain: ?Type = null,
    variants: ?Variants = null,
    buffer: ?Type = null,
    resource: ?external_resources.Kind = null,
    /// Declaration identity for builtin records with special transfer policies.
    /// `foreign_handle` is an `extern type`: an opaque C pointer, a `u64` in Core (`c_abi.zig`).
    builtin: enum { none, cell, live_view, foreign_handle } = .none,
    /// An anonymous tuple: positional fields no source can name, taken apart by
    /// destructuring only. It keeps the plain record representation, so
    /// construction, field reads, equality and layout are the record ones.
    tuple: bool = false,
    /// Identify representations carrying a managed collection or resource identity.
    pub fn hasRuntimeIdentity(self: RecordShape) bool {
        return self.buffer != null or self.resource != null;
    }
    fn hasValueRepresentation(self: RecordShape) bool {
        return self.array != null or self.domain != null or self.variants != null;
    }
};
/// Sound upper bound on the inputs a returned value may alias.
/// `fresh` requires proof; `unknown` is the conservative default and is never
/// treated as `fresh` or as `params(empty)`.
pub const ReturnOrigin = union(enum) {
    fresh,
    params: []const u16,
    unknown,

    /// Compare two return-origin bounds by exact normalized content.
    pub fn eql(a: ReturnOrigin, b: ReturnOrigin) bool {
        return switch (a) {
            .fresh => switch (b) {
                .fresh => true,
                else => false,
            },
            .unknown => switch (b) {
                .unknown => true,
                else => false,
            },
            .params => |left| switch (b) {
                .params => |right| std.mem.eql(u16, left, right),
                else => false,
            },
        };
    }
};
/// Checked obligations, type-argument visibility and an optional explicit domain wire contract.
/// Exact value parameter/result types, declared effect ceiling and mutation contract.
pub const Callable = struct {
    /// Required labels by parameter position; empty entries denote positional inputs.
    labels: []const []const u8 = &.{},
    parameters: []const Type,
    return_type: Type,
    mutates: []const u16 = &.{},
    return_origin: ReturnOrigin = .fresh,
    /// One flag per parameter, true where the callable type spelled `own`: a
    /// call through this value moves the argument at that position.
    own: []const bool = &.{},
};
/// Ownership and public schema policy for each concrete type.
pub const RecordContract = struct {
    callback: ?Callable = null,
    public_arguments: bool = true,
    move_only: bool = false,
    storable: bool = true,
    requires_handling: bool = false,
    /// The record is `@linear`, or holds a `@linear` value: each owner must be consumed (D-FFI-11). A linear record is
    /// move-only and carries the pending-value obligation L1 tracks, so the checker reports its own codes for it.
    linear: bool = false,
    /// The record is `@sealed`: only its declaring module and that module's test file build it or write its fields (W11,
    /// `sealed_rules.zig`). Unlike `linear` it is the record's own, never inherited by a record that holds one.
    sealed: bool = false,
};
/// The already-interned tuple record for a concrete element list, or null when
/// the catalog has not materialized that list yet. The spelling path and the
/// value path both ask here first, so one element list is one record.
pub fn internedTuple(records: []const Record, elements: []const Type) ?Type {
    for (records, 0..) |schema, index| {
        if (!schema.shape.tuple or schema.fields.len != elements.len) continue;
        var same = true;
        for (schema.fields, elements) |field, element| if (field.ty != element) {
            same = false;
            break;
        };
        if (same) return @fromBackingInt(Type.record_base + index);
    }
    return null;
}
/// The positional field name of one tuple element. The `$` makes every tuple
/// field unnameable from source, so no program can reach an element except by
/// destructuring and no declared field can collide with one.
pub fn positionalFieldName(allocator: std.mem.Allocator, index: usize) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "${d}", .{index});
}
/// Payload types and case tags of a checked ok/err result schema.
pub const ResultShape = struct { ok_type: Type, error_type: Type, ok_tag: usize, error_tag: usize };
/// Recognize a valid fallible result and return its payload types and tags.
pub fn resultShape(ty: Type, records: []const Record) ?ResultShape {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const variants = records[ty.recordIndex()].shape.variants orelse return null;
    if (!variants.fallible or !variants.is_union) return null;
    if (variants.cases.len != 2) return null;
    var ok: ?usize = null;
    var err: ?usize = null;
    for (variants.cases, 0..) |case, tag| {
        if (case.payload == null) return null;
        if (std.mem.eql(u8, case.name, "ok")) ok = tag;
        if (std.mem.eql(u8, case.name, "err")) err = tag;
    }
    return .{ .ok_type = variants.cases[ok orelse return null].payload.?, .error_type = variants.cases[err orelse return null].payload.?, .ok_tag = ok.?, .error_tag = err.? };
}
/// The cases of an error union that can carry an error of another type, in declaration order.
/// `try` and `fail` convert the error only when exactly one case fits (`unique`); with several
/// the program is refused (`E_ERROR_CASE_AMBIGUOUS`), so the order of an enum's cases never
/// chooses the error a program reports.
pub const CaseFit = struct {
    /// The fitting cases in declaration order; only the first `count` (at most 8) are kept.
    tags: [8]usize = undefined,
    /// How many cases fit.
    count: usize = 0,

    /// The one case that fits, or null when none or several do.
    pub fn unique(self: CaseFit) ?usize {
        return if (self.count == 1) self.tags[0] else null;
    }

    /// The fitting cases this answer kept, in declaration order.
    pub fn kept(self: *const CaseFit) []const usize {
        return self.tags[0..@min(self.count, self.tags.len)];
    }
};

/// Whether case `tag` of the union `container` carries an error of type `payload`: its payload
/// is that type, or a record of one named field of that type (`wrappingRecord`).
pub fn caseCarries(records: []const Record, container: Type, tag: usize, payload: Type) bool {
    if (!container.isAggregate() or container.recordIndex() >= records.len) return false;
    const variants = records[container.recordIndex()].shape.variants orelse return false;
    if (!variants.is_union or tag >= variants.cases.len) return false;
    const declared = variants.cases[tag].payload orelse return false;
    return declared == payload or wrappingRecord(records, container, tag, payload) != null;
}

/// The cases of the union `container` that can carry an error of type `payload`: the one answer
/// the checker, generic bodies and lowering all take for `try` and `fail value`.
pub fn errorCaseFit(records: []const Record, container: Type, payload: Type) CaseFit {
    var fit: CaseFit = .{};
    if (!container.isAggregate() or container.recordIndex() >= records.len) return fit;
    const variants = records[container.recordIndex()].shape.variants orelse return fit;
    if (!variants.is_union) return fit;
    for (0..variants.cases.len) |tag| {
        if (!caseCarries(records, container, tag, payload)) continue;
        if (fit.count < fit.tags.len) fit.tags[fit.count] = tag;
        fit.count += 1;
    }
    return fit;
}
/// Single named-field payload record required when widening an error into an enum case.
pub fn wrappingRecord(records: []const Record, container: Type, tag: usize, payload: Type) ?Type {
    if (!container.isAggregate() or container.recordIndex() >= records.len) return null;
    const variants = records[container.recordIndex()].shape.variants orelse return null;
    if (tag >= variants.cases.len or !variants.cases[tag].fielded) return null;
    const declared = variants.cases[tag].payload orelse return null;
    if (!declared.isAggregate() or declared.recordIndex() >= records.len) return null;
    const fields = records[declared.recordIndex()].fields;
    return if (fields.len == 1 and fields[0].ty == payload) declared else null;
}
/// Equality supported by concrete expressions and generic equality requirements.
/// Scalars, enums and domains compare directly; records, fixed arrays, unions,
/// results and options compare structurally; a managed `class` compares by
/// reference. A type that reaches a callback, a Cell or a resource does not
/// support equality and neither does one that nests such a field. The visited
/// stack bounds reference recursion, and it is sound to accept a type already on
/// it: the runtime traverses references with cycle-safe identity.
pub fn supportsEquality(ty: Type, records: []const Record) bool {
    var visited: [64]usize = undefined;
    return equalitySupport(ty, records, &visited, 0);
}

fn equalitySupport(ty: Type, records: []const Record, visited: *[64]usize, depth: usize) bool {
    if (ty.isInteger() or ty == .bool or ty == .unit) return true;
    if (!ty.isAggregate()) return false;
    const index = ty.recordIndex();
    if (index >= records.len) return false;
    for (visited[0..depth]) |seen| if (seen == index) return true;
    const record = records[index];
    if (record.contract.callback != null) return false;
    if (record.shape.builtin == .cell or record.shape.resource != null) return false;
    if (record.isEnum() or record.shape.domain != null) return true;
    if (depth == visited.len) return false;
    visited[depth] = index;
    const next = depth + 1;
    if (record.isCollection()) {
        if (record.collection.kind == .string or record.collection.kind == .bytes) return true;
        // A set's values are unit, which compare trivially: only its elements matter.
        if (!record.collection.set) if (record.shape.buffer) |element| if (!equalitySupport(element, records, visited, next)) return false;
        if (record.collection.key) |key| if (!equalitySupport(key, records, visited, next)) return false;
        return true;
    }
    if (record.shape.array) |array| return equalitySupport(array.element, records, visited, next);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| {
            if (case.payload) |payload| if (!equalitySupport(payload, records, visited, next)) return false;
        }
        return true;
    }
    for (record.fields) |field| if (!equalitySupport(field.ty, records, visited, next)) return false;
    return true;
}
/// Whether a value of this type is a `@sealed` record (W11).
pub fn sealed(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].contract.sealed;
}
/// Whether a value of this type is a `@linear` owner or holds one (D-FFI-11).
pub fn linear(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].contract.linear;
}
/// Determine whether a type carries ownership that forbids implicit copying.
pub fn moveOnly(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].contract.move_only;
}
/// Values eligible for managed storage without external resource cleanup;
/// pending Result obligations are tracked separately.
pub fn storable(ty: Type, records: []const Record) bool {
    return !ty.isAggregate() or records[ty.recordIndex()].contract.storable;
}
/// Determine whether a value contains an unacknowledged fallible result obligation.
pub fn requiresHandling(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].contract.requires_handling;
}
/// Return the scalar spelling or borrowed nominal schema name of a type.
pub fn typeName(ty: Type, records: []const Record) []const u8 {
    return if (ty.isAggregate()) records[ty.recordIndex()].name else @tagName(ty);
}
/// Whether a parameter of this type can be written through at all. `list`,
/// `dict`, `class`, `Cell`, `[N]T`, `byte_buffer` and any record, union, option
/// or result holding one carry mutable managed storage; scalars, `str`, `bytes`
/// and records built only from those do not, so `mut` on them would promise a
/// write that cannot reach the caller.
pub fn carriesWritableStorage(records: []const Record, ty: Type) bool {
    return writableDepth(records, ty, 0);
}

/// Whether a `mut` parameter of this type crosses the call as the caller's own
/// storage: a fixed array `[N]T` or enum table `[Kind]T`. Every other writable
/// parameter is a reference already, so only these value types need the
/// callee to write through the caller's address for an element write to reach
/// the caller.
pub fn referenceArray(records: []const Record, ty: Type) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].shape.array != null;
}

/// A plain value `record` or tuple crosses a `mut` position as the caller's
/// own storage (`inout`) in either value mode. A field assignment, a nested
/// write or a rebinding of the parameter therefore reaches the caller.
pub fn referenceRecord(records: []const Record, ty: Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    return !record.managed and record.isRecord() and record.contract.callback == null;
}

/// Whether a `mut` parameter of this type receives the caller's address: a
/// fixed array, or under value semantics a plain record (`referenceRecord`).
pub fn referenceMut(records: []const Record, ty: Type) bool {
    return referenceArray(records, ty) or referenceRecord(records, ty);
}

/// Whether a schema is a `set[T]`: a dictionary-kind collection from its
/// elements to unit that answers the set vocabulary instead of the mapping one.
pub fn isSet(record: Record) bool {
    return record.managed and record.collection.kind == .dictionary and record.collection.set;
}

/// The schema of a set type, or null for any other type.
pub fn setRecord(records: []const Record, ty: Type) ?Record {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    return if (isSet(records[ty.recordIndex()])) records[ty.recordIndex()] else null;
}

/// Whether a managed byte-kind schema is the immutable byte string rather than
/// the mutable octet buffer. The two share one collection kind, so the builtin
/// name -- repeated here rather than imported, because the template index that
/// declares it depends on this module -- is what tells them apart.
fn isImmutableBytes(record: Record) bool {
    if (record.collection.kind == .string) return true;
    return isByteString(record);
}

/// Whether a managed schema is the immutable `bytes` byte string rather than the
/// mutable `byte_buffer` or the separate `str` kind. The distinction is nominal,
/// like `isImmutableBytes`, because both byte kinds share one collection kind.
pub fn isByteString(record: Record) bool {
    return record.managed and record.collection.kind == .bytes and !std.mem.eql(u8, record.name, "byte_buffer");
}

fn writableDepth(records: []const Record, ty: Type, depth: usize) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len or depth == 64) return false;
    const record = records[ty.recordIndex()];
    if (record.managed) {
        // `str`, `bytes` and a byte kind that is not the octet buffer are
        // immutable; every other managed schema -- a collection, `byte_buffer`,
        // `Cell`, or a user `class` -- keeps writable storage.
        return !isImmutableBytes(record);
    }
    if (record.shape.array) |array| if (writableDepth(records, array.element, depth + 1)) return true;
    // A boxed value is immutable: a write through it copies the path to it into
    // the holder's own storage, so it adds no storage a callee could write.
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.boxed) continue;
        if (case.payload) |payload| if (writableDepth(records, payload, depth + 1)) return true;
    };
    for (record.fields) |field| if (!field.boxed and writableDepth(records, field.ty, depth + 1)) return true;
    return false;
}

/// Render a type the way source spells it, for user-facing diagnostics.
pub fn surfaceTypeName(allocator: std.mem.Allocator, ty: Type, records: []const Record) std.mem.Allocator.Error![]const u8 {
    const builtin = switch (ty) {
        .unit => "Unit",
        .clock_cap => "Clock",
        .random_cap => "Random",
        .filesystem_cap => "Filesystem",
        .network_cap => "Network",
        .environment_cap => "Environment",
        .stream_cap => "Stream",
        .host_cap => "Host",
        .process_cap => "Process",
        .input_cap => "Input",
        .stop_cap => "Stop",
        .registers_cap => "Registers",
        else => null,
    };
    if (builtin) |name| return allocator.dupe(u8, name);
    if (ty.isAggregate()) {
        const record = records[ty.recordIndex()];
        if (record.shape.array) |array| if (array.key == null) {
            const element = try surfaceTypeName(allocator, array.element, records);
            defer allocator.free(element);
            return std.fmt.allocPrint(allocator, "{s}[{s}, {d}]", .{ if (array.vector) "Simd" else "FixedArray", element, array.length });
        };
        if (record.collection.kind == .list) if (record.shape.buffer) |payload| {
            const element = try surfaceTypeName(allocator, payload, records);
            defer allocator.free(element);
            return if (isFunctionText(element)) std.fmt.allocPrint(allocator, "({s})[]", .{element}) else std.fmt.allocPrint(allocator, "{s}[]", .{element});
        };
        if (surfaceOptionalPayload(record)) |payload| {
            const element = try surfaceTypeName(allocator, payload, records);
            defer allocator.free(element);
            return if (isFunctionText(element)) std.fmt.allocPrint(allocator, "({s})?", .{element}) else std.fmt.allocPrint(allocator, "{s}?", .{element});
        }
    }
    const spelled = try surfaceTypeText(allocator, typeName(ty, records));
    defer allocator.free(spelled);
    return messageTypeText(allocator, spelled);
}
/// Whether a rendered type is a function type, whose `-> result` would swallow a `[]` or `?` written after it: a list of
/// `func(int) -> int` is written `(func(int) -> int)[]`, never `func(int) -> int[]`, which reads as a function returning a list.
fn isFunctionText(rendered: []const u8) bool {
    return std.mem.startsWith(u8, rendered, "func(");
}
/// Identify the builtin optional schema without depending on the prelude module.
pub fn surfaceOptionalPayload(record: Record) ?Type {
    if (!std.mem.startsWith(u8, record.name, "Option<") and
        !std.mem.startsWith(u8, record.name, "std_result::Option<")) return null;
    const variants = record.shape.variants orelse return null;
    if (!variants.is_union or variants.fallible or variants.cases.len != 2) return null;
    var payload: ?Type = null;
    var empty = false;
    for (variants.cases) |variant| {
        if (std.mem.eql(u8, variant.name, "some")) payload = variant.payload;
        if (std.mem.eql(u8, variant.name, "none") and variant.payload == null) empty = true;
    }
    return if (empty) payload else null;
}
/// Rewrite an internal type or signature spelling into the source surface spelling.
pub fn surfaceTypeText(allocator: std.mem.Allocator, raw: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    var index: usize = 0;
    while (index < raw.len) {
        const ch = raw[index];
        if (ch == '-' and index + 1 < raw.len and raw[index + 1] == '>') {
            try out.appendSlice(allocator, "->");
            index += 2;
            continue;
        }
        if (ch == ':' and index + 1 < raw.len and raw[index + 1] == ':') {
            try out.append(allocator, '.');
            index += 2;
            continue;
        }
        if (ch == '<') {
            try out.append(allocator, '[');
            index += 1;
            continue;
        }
        if (ch == '>') {
            try out.append(allocator, ']');
            index += 1;
            continue;
        }
        if (ch == ',') {
            try out.appendSlice(allocator, ", ");
            index += 1;
            while (index < raw.len and raw[index] == ' ') index += 1;
            continue;
        }
        if (std.ascii.isAlphanumeric(ch) or ch == '_') {
            var end = index;
            while (end < raw.len and (std.ascii.isAlphanumeric(raw[end]) or raw[end] == '_')) end += 1;
            const word = raw[index..end];
            if (std.mem.eql(u8, word, "i64")) {
                try out.appendSlice(allocator, "int");
            } else if (std.mem.eql(u8, word, "f64")) {
                try out.appendSlice(allocator, "float");
            } else if (std.mem.eql(u8, word, "def")) {
                try out.appendSlice(allocator, "func");
            } else {
                try out.appendSlice(allocator, word);
            }
            index = end;
            continue;
        }
        try out.append(allocator, ch);
        index += 1;
    }
    const rendered = try out.toOwnedSlice(allocator);
    // `List` is the compiler-internal spelling; source always writes `list`.
    // Lowercase every standalone `List[` so nested lists read `list[...]` too.
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, rendered, cursor, "List[")) |at| {
        const standalone = at == 0 or !(std.ascii.isAlphanumeric(rendered[at - 1]) or rendered[at - 1] == '_');
        if (standalone) rendered[at] = 'l';
        cursor = at + 5;
    }
    return rendered;
}
/// `surfaceTypeText` for a message: every `list[X]` in the surface spelling is written as the source writes a list, `X[]`, and
/// every `Option[X]` as the source writes an option, `X?` (`dict[str, list[int]]` is `dict[str, int[]]`, `Box[Option[int]]` is
/// `Box[int?]`, `func(own list[int]) -> int` is `func(own int[]) -> int`, and a list or an option of functions is
/// `(func(int) -> int)[]` or `(func(int) -> int)?`). `surfaceTypeText` itself keeps `list[X]` and `Option[X]`: the module
/// interface files are written in it.
pub fn messageTypeText(allocator: std.mem.Allocator, surface: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try respellSurface(allocator, surface, &out);
    return allocator.dupe(u8, out.items);
}
/// The generic type `text` starts with, when it is one the source writes with a suffix: `list[` (`X[]`) or the builtin `Option[`
/// (`X?`, never after a `.`, where a module's own `Option` stands). The word it opens with and the suffix.
fn suffixedGeneric(text: []const u8, before: ?u8) ?struct { open: []const u8, suffix: []const u8 } {
    if (std.mem.startsWith(u8, text, "list[")) return .{ .open = "list[", .suffix = "[]" };
    if (std.mem.startsWith(u8, text, "Option[") and before != '.') return .{ .open = "Option[", .suffix = "?" };
    return null;
}
/// Append `text` to `out`, writing each standalone `list[X]` as `X[]` and `Option[X]` as `X?` (an element that is a function
/// type in parentheses).
fn respellSurface(allocator: std.mem.Allocator, text: []const u8, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    var at: usize = 0;
    while (at < text.len) {
        const standalone = at == 0 or !(std.ascii.isAlphanumeric(text[at - 1]) or text[at - 1] == '_');
        if (standalone) if (suffixedGeneric(text[at..], if (at == 0) null else text[at - 1])) |generic| {
            var depth: usize = 1;
            var comma = false;
            var end = at + generic.open.len;
            while (end < text.len and depth != 0) : (end += 1) switch (text[end]) {
                '[' => depth += 1,
                ']' => depth -= 1,
                ',' => if (depth == 1) {
                    comma = true;
                },
                else => {},
            };
            if (depth == 0 and !comma) {
                var element: std.ArrayList(u8) = .empty;
                defer element.deinit(allocator);
                try respellSurface(allocator, text[at + generic.open.len .. end - 1], &element);
                if (isFunctionText(element.items)) try out.append(allocator, '(');
                try out.appendSlice(allocator, element.items);
                if (isFunctionText(element.items)) try out.append(allocator, ')');
                try out.appendSlice(allocator, generic.suffix);
                at = end;
                continue;
            }
        };
        try out.append(allocator, text[at]);
        at += 1;
    }
}
/// The source spelling of an internal type name, for a message that holds only the name: `List<i64>` is `int[]`, `Option<T>` is
/// `T?`, `[2]Box` is `FixedArray[Box, 2]`, `Simd[4]f32` is `Simd[f32, 4]`, `m::Box` is `m.Box`, `i64` is `int`, `f64` is `float`,
/// `def(` is `func(` and a capability tag such as `host_cap` is `Host`. Anything it does not know is copied as written.
pub fn sourceTypeSpelling(allocator: std.mem.Allocator, raw: []const u8) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try spellNames(allocator, raw, &out);
    return allocator.dupe(u8, out.items);
}
/// Where the type that starts `raw` ends: the first `,` or unmatched closing bracket outside any bracket, or the end of `raw`.
fn typeLength(raw: []const u8) usize {
    var depth: usize = 0;
    var index: usize = 0;
    while (index < raw.len) : (index += 1) {
        if (std.mem.startsWith(u8, raw[index..], "->")) {
            index += 1;
            continue;
        }
        switch (raw[index]) {
            '<', '(', '[' => depth += 1,
            '>', ')', ']', ',' => {
                if (depth == 0) return index;
                if (raw[index] != ',') depth -= 1;
            },
            else => {},
        }
    }
    return raw.len;
}
/// The source spelling of one name word of an internal type: a fixed-width alias, or a capability tag.
fn spellWord(word: []const u8) []const u8 {
    const renames = [_][2][]const u8{
        .{ "i64", "int" },
        .{ "f64", "float" },
        .{ "def", "func" },
        .{ "host_cap", "Host" },
        .{ "clock_cap", "Clock" },
        .{ "random_cap", "Random" },
        .{ "filesystem_cap", "Filesystem" },
        .{ "network_cap", "Network" },
        .{ "environment_cap", "Environment" },
        .{ "stream_cap", "Stream" },
        .{ "process_cap", "Process" },
        .{ "input_cap", "Input" },
        .{ "stop_cap", "Stop" },
        .{ "registers_cap", "Registers" },
    };
    for (renames) |pair| if (std.mem.eql(u8, word, pair[0])) return pair[1];
    return word;
}
/// The `[N]` or `Simd[N]` that opens an internal array name: how many bytes it takes, its count and the source name of the type.
const SizedPrefix = struct { length: usize, count: []const u8, name: []const u8 };
fn sizedPrefix(raw: []const u8) ?SizedPrefix {
    const simd = std.mem.startsWith(u8, raw, "Simd[");
    if (!simd and !std.mem.startsWith(u8, raw, "[")) return null;
    const open: usize = if (simd) 5 else 1;
    const digits = std.mem.indexOfNone(u8, raw[open..], "0123456789") orelse return null;
    if (digits == 0 or raw[open + digits] != ']') return null;
    return .{ .length = open + digits + 1, .count = raw[open .. open + digits], .name = if (simd) "Simd" else "FixedArray" };
}
/// Append `raw` to `out` with each internal type form in it spelled as source spells it (see `sourceTypeSpelling`).
fn spellNames(allocator: std.mem.Allocator, raw: []const u8, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    const wrappers = [_][2][]const u8{ .{ "List<", "[]" }, .{ "Option<", "?" }, .{ "std_result::Option<", "?" } };
    var index: usize = 0;
    scan: while (index < raw.len) {
        const rest = raw[index..];
        const at_word = std.ascii.isAlphanumeric(rest[0]) or rest[0] == '_';
        if (sizedPrefix(rest)) |sized| {
            const element = rest[sized.length..][0..typeLength(rest[sized.length..])];
            try out.print(allocator, "{s}[", .{sized.name});
            try spellNames(allocator, element, out);
            try out.print(allocator, ", {s}]", .{sized.count});
            index += sized.length + element.len;
            continue :scan;
        }
        const after_dot = out.items.len != 0 and out.items[out.items.len - 1] == '.';
        if (at_word and !after_dot) for (wrappers) |wrapper| {
            if (!std.mem.startsWith(u8, rest, wrapper[0])) continue;
            const inner = rest[wrapper[0].len..][0..typeLength(rest[wrapper[0].len..])];
            try spellNames(allocator, inner, out);
            try out.appendSlice(allocator, wrapper[1]);
            index += wrapper[0].len + inner.len + 1;
            continue :scan;
        };
        if (at_word) {
            var end: usize = 1;
            while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_')) end += 1;
            try out.appendSlice(allocator, spellWord(rest[0..end]));
            index += end;
        } else if (std.mem.startsWith(u8, rest, "->")) {
            try out.appendSlice(allocator, "->");
            index += 2;
        } else if (std.mem.startsWith(u8, rest, "::")) {
            try out.append(allocator, '.');
            index += 2;
        } else if (rest[0] == '<' or rest[0] == '>') {
            try out.append(allocator, if (rest[0] == '<') '[' else ']');
            index += 1;
        } else if (rest[0] == ',') {
            try out.appendSlice(allocator, ", ");
            index += 1;
            while (index < raw.len and raw[index] == ' ') index += 1;
        } else {
            try out.append(allocator, rest[0]);
            index += 1;
        }
    }
}
/// Return the segment after the final `::` or `.` of a qualified name.
pub fn localSegment(name: []const u8) []const u8 {
    var start: usize = 0;
    for (name, 0..) |ch, index| if (ch == ':' or ch == '.') {
        start = index + 1;
    };
    return name[start..];
}
/// How `plainName` treats a name: whether it lower-cases it, and what it does when the name outgrows the buffer.
pub const PlainOptions = struct { lower: bool = false, truncate: bool = false };
/// `name` without its underscores (`isdigit` is the plain name of `is_digit`), in `buffer`, lower-cased when `options.lower`. A
/// name that outgrows the buffer is cut where the buffer ends when `options.truncate`, and has no plain name (null) otherwise.
pub fn plainName(buffer: []u8, name: []const u8, options: PlainOptions) ?[]const u8 {
    var length: usize = 0;
    for (name) |byte| {
        if (byte == '_') continue;
        if (length == buffer.len) return if (options.truncate) buffer[0..length] else null;
        buffer[length] = if (options.lower) std.ascii.toLower(byte) else byte;
        length += 1;
    }
    return buffer[0..length];
}
/// Bounded Levenshtein distance; returns `limit + 1` when the distance exceeds it.
pub fn editDistanceAtMost(a: []const u8, b: []const u8, limit: usize) usize {
    if (a.len > b.len + limit or b.len > a.len + limit) return limit + 1;
    if (a.len > 256 or b.len > 256) return limit + 1;
    var previous: [257]usize = undefined;
    var current: [257]usize = undefined;
    for (0..b.len + 1) |j| previous[j] = j;
    for (a, 0..) |left, i| {
        current[0] = i + 1;
        for (b, 0..) |right, j| {
            const substitution = previous[j] + @as(usize, @intFromBool(left != right));
            const deletion = previous[j + 1] + 1;
            const insertion = current[j] + 1;
            current[j + 1] = @min(@min(substitution, deletion), insertion);
        }
        @memcpy(previous[0 .. b.len + 1], current[0 .. b.len + 1]);
    }
    return previous[b.len];
}
test "a plain name drops underscores, lowers on request, and is cut or refused when it outgrows the buffer" {
    var buffer: [4]u8 = undefined;
    try std.testing.expectEqualStrings("isdigit"[0..4], plainName(&buffer, "is_digit", .{ .truncate = true }).?);
    try std.testing.expect(plainName(&buffer, "is_digit", .{}) == null);
    var wide: [16]u8 = undefined;
    try std.testing.expectEqualStrings("isdigit", plainName(&wide, "is_digit", .{}).?);
    try std.testing.expectEqualStrings("isdigit", plainName(&wide, "Is_Digit", .{ .lower = true }).?);
    try std.testing.expectEqualStrings("Isdigit", plainName(&wide, "Is_digit", .{}).?);
}
/// Render the `; did you mean ...?` clause naming declared keys within edit
/// distance two of `target`, or an empty slice when no close candidate exists.
pub fn suggestionClause(allocator: std.mem.Allocator, map: anytype, target: []const u8) std.mem.Allocator.Error![]const u8 {
    var candidates: std.ArrayList([]const u8) = .empty;
    defer candidates.deinit(allocator);
    var iterator = map.iterator();
    while (iterator.next()) |entry| {
        const name = localSegment(entry.key_ptr.*);
        if (std.mem.eql(u8, name, target)) continue;
        if (editDistanceAtMost(name, target, 2) > 2) continue;
        try candidates.append(allocator, name);
    }
    if (candidates.items.len == 0) return "";
    std.mem.sort([]const u8, candidates.items, {}, nameLessThan);
    var unique: usize = 0;
    for (candidates.items, 0..) |name, index| {
        if (index != 0 and std.mem.eql(u8, candidates.items[unique - 1], name)) continue;
        candidates.items[unique] = name;
        unique += 1;
    }
    const shown = candidates.items[0..@min(unique, 3)];
    var joined: std.ArrayList(u8) = .empty;
    defer joined.deinit(allocator);
    for (shown, 0..) |name, index| {
        if (index != 0) try joined.appendSlice(allocator, "`, `");
        try joined.appendSlice(allocator, name);
    }
    return std.fmt.allocPrint(allocator, "; did you mean {s}`{s}`?", .{ if (shown.len == 1) "" else "one of: ", joined.items });
}
fn nameLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
/// Resolved local assignment target and the expression being stored.
/// `element` marks the store an element write such as `a[i] = v` lowers to:
/// the value rebuilds the local from its own current value with one element
/// changed, so the write is a mutation of the binding rather than a rebinding.
pub const Store = struct {
    slot: LocalId,
    value: NodeId,
    element: bool = false,
    /// This temporary stages an assignment's value for owning storage.
    /// Core applies the source transfer rules at this evaluation point.
    transfer: bool = false,
    /// Initialize-only complete tuple staging: consume the hidden whole slot,
    /// bind every non-null field slot, and destroy explicitly ignored fields.
    unpack: ?[]const ?LocalId = null,
};
/// A checked source range keeps its endpoints and binding together. The
/// normalized loop plan preserves the checked direction, overflow and exits.
pub const RangeParts = struct {
    binding: Span,
    start: Store,
    end: Store,
    setup: []const StatementId,
    loop: Loop,
};
/// The single owned plan avoids growing every statement's tagged union.
/// Persisted decoders validate exact-one ownership before publishing a tree.
pub const RangeLoop = struct {
    parts: []const RangeParts,

    /// Checked source plan shared by traversal and lowering. Construction owns one.
    pub fn plan(self: RangeLoop) RangeParts {
        std.debug.assert(self.parts.len == 1);
        return self.parts[0];
    }
};
/// Checked loop control shared by while and source range lowering.
pub const Loop = struct { id: usize = 0, condition: NodeId, body: StatementId, step: ?StatementId = null, vectorize: bool = false };
/// Checked control flow, ownership operations, and expression statements.
pub const Statement = struct {
    span: Span,
    terminates: bool,
    data: union(enum) {
        with_scope: struct { slot: LocalId, resource: ?NodeId, body: StatementId },
        block: []const StatementId,
        assertion: Assertion,
        ret: NodeId,
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        /// `continuation` marks the match of a bind-or-else: its success arm holds the rest of the enclosing block, so a named
        /// scrutinee is held until the arm's last use of a payload binding, as a `const` alias of it would be.
        match: struct { value: NodeId, arms: []const MatchArm, borrowed: bool = false, exclusive: bool = false, continuation: bool = false },
        loop: Loop,
        range_loop: RangeLoop,
        loop_exit: struct { target: usize, continuing: bool },
        initialize: Store,
        assign: Store,
    },
};
/// Checked condition with its static message and optional rendered message
/// expression, which is evaluated only when the condition is false. `kind`
/// names the clause the checker placed it for: an `assert` statement, or one
/// `@requires`, `@ensures` or `@invariant` contract clause.
pub const Assertion = struct { condition: NodeId, message: []const u8, message_value: ?NodeId = null, kind: AssertionKind = .statement };
/// The clause one checked assertion enforces.
pub const AssertionKind = enum { statement, requires, ensures, invariant };
/// Resolved case tag, optional payload local, and checked arm body.
pub const MatchArm = struct {
    tag: usize,
    slot: ?LocalId,
    body: StatementId,
    /// A fielded pattern can split an owned payload before its source body.
    /// `body` above retains the ordinary borrowing projection prologue.
    unpack: ?UnpackedArm = null,
};
/// Every payload field has one binding or is discarded; no partial owner remains.
pub const UnpackedArm = struct { fields: []const ?LocalId, body: StatementId };
/// Local type, declaration, usage counts, and tracked ownership/borrow state.
pub const Local = struct {
    ownership: LocalOwnership = .{},
    usage: LocalUsage = .{},
    name: []const u8,
    declaration: Span,
    ty: Type,
    mutable: bool,
    /// Where this binding's value came from, for copy-semantics diagnostics.
    origin: LocalOrigin = .local,

    /// Whether the program wrote this local's name: a name a person could have written is made of letters, digits and
    /// underscores. A temporary, an empty name, a `<`-name (`<collection>`) and the compiler's own owners, whose names
    /// are words with a space in them (`consumed list`, `temporary list`, `temporary option`), are not written, so a
    /// tool that reports a name to the author skips them: the author has no such variable.
    pub fn written(self: Local) bool {
        if (self.usage.temporary or self.name.len == 0) return false;
        for (self.name) |byte| {
            if (byte >= 0x80 or byte == '_' or std.ascii.isAlphanumeric(byte)) continue;
            return false;
        }
        return true;
    }
};
/// Compile-time ownership availability, definite-assignment, and arena confinement.
pub const LocalOwnership = struct {
    scoped_file: bool = false,
    transfer_span: ?Span = null,
    initialized: bool = false,
    maybe_initialized: bool = false,
    transfer_available: bool = false,
    /// This immutable binding holds a view of another local's text rather than
    /// its own copy (wave 3: a slice is a view). The builder gives the binding a
    /// `str_view` value and keeps it borrowed; every owned use materializes a
    /// copy, so the value a program sees is unchanged.
    view: bool = false,
    /// This parameter is spelled `own`: the callee owns its value, so its writes
    /// stay in the callee and never reach a caller's binding.
    owned_parameter: bool = false,
};
/// Static binding reads and writes used by quality diagnostics.
pub const LocalUsage = struct {
    temporary: bool = false,
    reads: usize = 0,
    writes: usize = 0,
    /// Read count immediately after the most recent candidate field write.
    dead_write_reads: usize = 0,
    /// Span of the most recent candidate field write; null when none happened.
    dead_write_span: ?Span = null,
};
/// The name of the hidden `contract_value` local a generated invariant check reads a container into while a running
/// `match mut` arm holds it (FX7b, `sema_contracts.checkAfterBindingWrites`). The source ownership check lets the
/// initializer of such a local, and no other read, reach the held place.
pub const invariant_hold_read = "<match-mut-invariant>";
/// Source of a local's value when differing copy semantics matter.
/// `contract_old` is the hidden local an `@ensures` clause's `old(...)`
/// value is captured in at entry, whose initializer must be effect-free;
/// `contract_value` holds the value a contract clause is checked against
/// (`result`, or an invariant's `self`).
/// `view` is a binding of a slice: a view of its source until its first owned use.
pub const LocalOrigin = enum { local, parameter, iteration, collection_copy, contract_old, contract_value, pattern, view };

/// Checked function signature, local/reference metadata, effects, and body identity.
pub const Function = struct {
    policy: FunctionPolicy = .{},
    /// Concrete specialization arguments; empty for an ordinary source function.
    type_arguments: []const Type = &.{},
    signature: FunctionSignature = .{},
    scope: FunctionScope,
    id: FunctionId,
    name: []const u8,
    declaration: Span,
};
/// Declared visibility, foreign-call policy and Core allocation promises.
pub const FunctionPolicy = struct {
    c_abi: bool = false,
    host: ?Span = null,
    /// Explicit Core allocation promise, independent of source authority.
    noalloc: ?Span = null,
    /// The `@freestanding` attribute: the function needs nothing from the runtime (`freestanding.zig`).
    freestanding: ?Span = null,
    /// `@freestanding(ram)`: the function's code runs from RAM, so it calls only RAM code (`freestanding.zig`) and its image
    /// is checked to reach nothing in flash (`core/ram_image.zig`).
    ram: bool = false,
    owner: ?Type = null,
    restricted: bool = false,
    conversion: bool = false,
    /// A `builtin func` of the standard library: the compiler supplies its calls and, where it needs one, its body.
    builtin: bool = false,
    /// An `@address` `extern func`: its C target is the value of its parameter after `host`, not a symbol. Last, and
    /// hashed only when set (`lowering_cache.zig`, `typed_digest.zig`), so every other function keys as before.
    address: bool = false,

    /// Whether field `name` is hashed only when set (`address`, `freestanding`, `ram`), so a function without it keys and
    /// digests exactly as before the field existed (`lowering_cache.zig` `TreeHash`, `typed_digest.zig`; W07 pins it).
    pub fn keyedWhenSet(comptime name: []const u8) bool {
        return std.mem.eql(u8, name, "address") or std.mem.eql(u8, name, "freestanding") or std.mem.eql(u8, name, "ram");
    }
};
/// Checked write facts used after body inference.
pub const InferredFacts = struct {
    /// Any managed receiver write in the body.
    writes: bool = false,
    /// A write not proven to target definitely fresh local storage.
    external: bool = false,
};
/// Resolved value result and parameter count of a checked function.
pub const FunctionSignature = struct {
    constant_arguments: []const ?usize = &.{},
    return_type: Type = .i64,
    parameter_count: usize = 0,
    /// Declared `mut` parameter positions, normalized and sorted.
    mutates: []const u16 = &.{},
    /// Declared result borrowing: fresh without `from`, otherwise sorted source positions.
    return_origin: ReturnOrigin = .fresh,
    /// Source-declared mutation footprint, retained for body validation.
    declared_mutates: []const u16 = &.{},
    /// Write facts kept separate so a fresh-local write can stay unenforced.
    inferred: InferredFacts = .{},
};
/// Whether a `HoleMode.recover` check stood `function` in for a body that failed to check: no complete body and no host
/// binding. Only a recovered program, which is never lowered or stored, holds such a function outside a summary check.
pub fn recoveredStandIn(function: Function) bool {
    return !function.scope.body_complete and function.policy.host == null;
}
/// Checked function body and its lexical local table.
pub const FunctionScope = struct {
    /// True only when this graph contains the complete checked function body.
    body_complete: bool = false,
    /// Named parameter labels retained for runtime callable contract validation.
    parameter_labels: []const []const u8 = &.{},
    /// One flag per parameter in source order, true where the declaration
    /// spelled `own`: the parameter takes its argument, may store, return or
    /// move it, and destroys it at the callee's scope end otherwise.
    own_parameters: []const bool = &.{},
    body: StatementId,
    locals: []const Local = &.{},
};
/// Borrowed checked expression, statement, function, and nominal schema tables.
/// Checked transparent name and its canonical target, retained for public interfaces.
pub const TypeAlias = struct { name: []const u8, target: Type, declaration: Span };
/// Checked semantic graph with arena-owned type and alias identities.
pub const Program = struct {
    aliases: []const TypeAlias = &.{},
    nodes: []const Node,
    statements: []const Statement,
    functions: []const Function,
    main: FunctionId,
    records: []const Record = &.{},
    /// One flag per function: true for a function no other unit of the build can name. It is a source function that its module's interface
    /// does not export, with no owner, conversion or foreign linkage, declared in a module with no generic function declaration (an instance
    /// of a template calls the private functions the template names, from the unit of the instance) and no test file in the build (a
    /// `<module>_test` file reaches its module's private declarations), and neither a specialization nor a
    /// compiler-made body. Empty when the check did not decide it: every function then counts as visible (spec section 17.5).
    private: []const bool = &.{},
};

/// Identify the external provider family associated with a type.
pub fn resourceKind(ty: Type, records: []const Record) ?external_resources.Kind {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    return records[ty.recordIndex()].shape.resource;
}
/// Check whether a type has the byte-array representation required by provider requests.
pub fn byteRequest(ty: Type, records: []const Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const array = records[ty.recordIndex()].shape.array orelse return false;
    return array.element == .u8 and array.key == null;
}
/// Acquisition accepts an ordinary fixed byte array without an enum key.
pub fn acquisitionBytes(ty: Type, records: []const Record) bool {
    return byteRequest(ty, records);
}
/// Whether a type is the managed immutable `bytes` value rather than its buffer.
pub fn byteString(ty: Type, records: []const Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    return isByteString(records[ty.recordIndex()]);
}
/// Result schema and fields needed to preserve a resource on failed completion.
pub const CompletionShape = struct { result: ResultShape, resource_type: Type, resource_field: usize, code_field: usize };
/// Recognize the resource-preserving completion result layout.
pub fn completionShape(ty: Type, records: []const Record) ?CompletionShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.ok_type != .bool or !result.error_type.isAggregate() or result.error_type.recordIndex() >= records.len) return null;
    const schema = records[result.error_type.recordIndex()];
    const slots = providerFields(schema, records, .completion) orelse return null;
    return .{ .result = result, .resource_type = schema.fields[slots[0]].ty, .resource_field = slots[0], .code_field = slots[1] };
}

/// Result payload layout containing bytes, a length, and a status flag.
pub const ByteResultShape = struct { result: ResultShape, bytes_type: Type, bytes_field: usize, length_field: usize, flag_field: usize };
/// Recognize the required environment lookup result layout.
pub fn environmentShape(ty: Type, records: []const Record) ?ByteResultShape {
    return byteResultShape(ty, records, .environment);
}
/// Recognize the required fixed-buffer resource read result layout.
pub fn resourceReadShape(ty: Type, records: []const Record) ?ByteResultShape {
    return byteResultShape(ty, records, .read);
}
fn byteResultShape(ty: Type, records: []const Record, operation: provider_contracts.Operation) ?ByteResultShape {
    const result = resultShape(ty, records) orelse return null;
    if (result.error_type != .i64 or !result.ok_type.isAggregate() or result.ok_type.recordIndex() >= records.len) return null;
    const schema = records[result.ok_type.recordIndex()];
    const slots = providerFields(schema, records, operation) orelse return null;
    return .{ .result = result, .bytes_type = schema.fields[slots[0]].ty, .bytes_field = slots[0], .length_field = slots[1], .flag_field = slots[2] };
}

fn providerFields(schema: Record, records: []const Record, operation: provider_contracts.Operation) ?[3]usize {
    const required = provider_contracts.fields(operation);
    if (!schema.isRecord() or schema.fields.len != required.len) return null;
    var slots: [3]usize = @splat(0);
    for (required, 0..) |rule, slot| {
        var found = false;
        for (schema.fields, 0..) |field, index| {
            if (!std.mem.eql(u8, field.name, rule.name)) continue;
            const matches = switch (rule.requirement) {
                .i64 => field.ty == .i64,
                .u64 => field.ty == .u64,
                .boolean => field.ty == .bool,
                .bytes => byteRequest(field.ty, records),
                .resource => resourceKind(field.ty, records) != null,
            };
            if (!matches) return null;
            slots[slot] = index;
            found = true;
        }
        if (!found) return null;
    }
    return slots;
}
