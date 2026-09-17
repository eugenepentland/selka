//! Checked nodes use declaration identities, concrete types, and local slots.
const effect_set = @import("effect_set.zig");
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
pub const Type = values.Type;
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
};
/// Checked numeric negation and Boolean inversion operations.
pub const UnaryOp = enum { neg, not, f64_sqrt, f64_floor, f64_ceil, f64_trunc, f64_abs, f64_neg, f64_from_u64, f64_to_u64, f64_from_i64, f64_to_i64 };
/// Typed expression with resolved operands and source location.
pub const Node = struct {
    ty: Type,
    span: Span,
    data: union(enum) {
        integer: i128,
        boolean: bool,
        unit,
        block_value: struct { body: StatementId, value: NodeId },
        function_value: FunctionId,
        invoke: struct { callee: NodeId, arguments: []const NodeId },
        local: LocalId,
        propagate: struct { value: NodeId, output: Type },
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: LocalId, arguments: []const NodeId },
        acquire_resource: struct { capability: NodeId, request: NodeId },
        complete_resource: NodeId,
        resource_io: struct { kind: external_resources.IoKind, owner: LocalId, value: ?NodeId },
        restrict_resource: struct { permissions: external_resources.Permissions, value: NodeId },
        dir_resource: struct { capability: NodeId, path: NodeId },
        environment_get: struct { capability: NodeId, name: NodeId },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, capability: NodeId },
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
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: []const FieldInit,
        update: struct { base: NodeId, fields: []const FieldInit },
        field: struct { base: NodeId, index: usize },
        call: struct { evaluation: ?struct { body: StatementId, cleanup: []const LocalId } = null, function: FunctionId, arguments: []const NodeId },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
/// Whole-path file helper: its operands begin with the `Filesystem` capability.
pub const FileAccess = struct { kind: @import("file_operations.zig").Access, mode: u8, text: bool, arguments: []const NodeId, shapes: FileShapes };
/// Method call on an open `with` binding, addressed by its local slot.
pub const FileMethod = struct { kind: @import("file_operations.zig").Method, owner: LocalId, text: bool, argument: ?NodeId, shapes: FileShapes };
/// Nominal payload schemas a file operation needs to build its result.
pub const FileShapes = struct { text: Type, bytes: Type, list: Type };
/// Which standard stream an ambient `print` writes to when no receiver is given.
pub const Sink = enum { stdout, stderr };
/// Rendered arguments and the optional `sep=`/`end=` text of one output call.
/// A `stream` receiver selects the fd at runtime; a `debug` call writes to stderr
/// and contributes no effect.
pub const Print = struct { sink: Sink = .stdout, arguments: []const NodeId, separator: ?NodeId, terminator: ?NodeId, stream: ?NodeId = null, debug: bool = false };
/// `stream.write(text)`: the receiver stream value and the text to write.
pub const StreamWrite = struct { stream: NodeId, text: NodeId };
/// Resolved aggregate field index and the expression supplying its value.
pub const FieldInit = struct { index: usize, value: NodeId };
/// Named aggregate field with its declaration location and resolved type.
pub const Field = struct { name: []const u8, declaration: Span, ty: Type };
/// Named closed variant case and its optional resolved payload type.
pub const Variant = struct { name: []const u8, declaration: Span, payload: ?Type };
/// Closed case set distinguishing enums, unions, and fallible results.
pub const Variants = struct { fallible: bool = false, is_union: bool, cases: []const Variant };
/// Fixed element count and type, with an optional enum key for tables.
pub const Array = struct { element: Type, length: usize, key: ?Type = null };
// Aggregate schemas retain nominal record identities and intern structural arrays.
/// Declared domain wire type and resolved decoder/encoder function identities.
pub const Codec = struct { wire: Type, decode: FunctionId, encode: FunctionId };
/// Nominal aggregate schema and associated array, domain, collection, or variant metadata.
pub const Record = struct {
    collection: @import("runtime_values.zig").CollectionShape = .{},
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
        return self.managed and self.isRecord() and self.shape.builtin_cell;
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
    /// Resolve a field or array element type by its checked index.
    pub fn elementType(self: Record, index: usize) Type {
        return if (self.shape.array) |a| a.element else self.shape.domain orelse self.fields[index].ty;
    }
};
/// Optional specialized representations; bytecode validation rejects incompatible combinations.
pub const RecordShape = struct {
    array: ?Array = null,
    domain: ?Type = null,
    variants: ?Variants = null,
    buffer: ?Type = null,
    resource: ?external_resources.Kind = null,
    /// The builtin Cell: a managed record with closed field and content rules.
    builtin_cell: bool = false,
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
    parameters: []const Type,
    return_type: Type,
    effects: effect_set.Mask,
    mutates: []const u16 = &.{},
    return_origin: ReturnOrigin = .unknown,
    /// Every callback parameter is an ordinary operand-stack value.
    pub fn valueCount(self: Callable) usize {
        return self.parameters.len;
    }
};
/// Ownership and public schema policy for each concrete type.
pub const RecordContract = struct {
    callback: ?Callable = null,
    public_arguments: bool = true,
    codec: ?Codec = null,
    codec_declared: bool = false,
    move_only: bool = false,
    storable: bool = true,
    requires_handling: bool = false,
};
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
/// Equality supported by concrete expressions and generic equality requirements.
pub fn supportsEquality(ty: Type, records: []const Record) bool {
    if (ty.isInteger() or ty == .bool) return true;
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    if (record.contract.callback != null) return false;
    return record.isEnum() or record.shape.domain != null;
}
/// Determine whether a type carries ownership that forbids implicit copying.
pub fn moveOnly(ty: Type, records: []const Record) bool {
    return ty.isAggregate() and records[ty.recordIndex()].contract.move_only;
}
/// Values whose destruction requires neither result handling nor external provider effects.
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
/// Render a type the way source spells it, for user-facing diagnostics.
pub fn surfaceTypeName(allocator: std.mem.Allocator, ty: Type, records: []const Record) std.mem.Allocator.Error![]const u8 {
    return surfaceTypeText(allocator, typeName(ty, records));
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
/// Return the segment after the final `::` or `.` of a qualified name.
pub fn localSegment(name: []const u8) []const u8 {
    var start: usize = 0;
    for (name, 0..) |ch, index| if (ch == ':' or ch == '.') {
        start = index + 1;
    };
    return name[start..];
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
pub const Store = struct { slot: LocalId, value: NodeId };
/// Checked control flow, ownership operations, and expression statements.
pub const Statement = struct {
    span: Span,
    terminates: bool,
    owned_cleanup: []const LocalId = &.{},
    data: union(enum) {
        with_scope: struct { slot: LocalId, resource: ?NodeId, body: StatementId },
        block: []const StatementId,
        assertion: Assertion,
        ret: NodeId,
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { id: usize = 0, condition: NodeId, body: StatementId, step: ?StatementId = null },
        loop_exit: struct { target: usize, continuing: bool, arenas: []const LocalId = &.{} },
        initialize: Store,
        assign: Store,
    },
};
/// Checked condition with the trap message its failure reports.
pub const Assertion = struct { condition: NodeId, message: []const u8 };
/// Resolved case tag, optional payload local, and checked arm body.
pub const MatchArm = struct { tag: usize, slot: ?LocalId, body: StatementId };
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
};
/// Compile-time ownership availability, definite-assignment, and arena confinement.
pub const LocalOwnership = struct { transfer_span: ?Span = null, initialized: bool = false, arena_confined: bool = false, transfer_available: bool = false };
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
/// Source of a local's value when differing copy semantics matter.
pub const LocalOrigin = enum { local, parameter, iteration, collection_copy };

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
/// Declared visibility and effect policy, with its inferred execution effects.
pub const FunctionPolicy = struct {
    c_abi: bool = false,
    host: ?Span = null,
    effect_bound: ?effect_set.Bound = null,
    effects: effect_set.Mask = 0,
    owner: ?Type = null,
    restricted: bool = false,
    conversion: bool = false,
};
/// Managed-write facts recorded before M2 origin enforcement.
pub const MutationFacts = struct {
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
    /// Inferred parameter positions this function may write, normalized and sorted.
    mutates: []const u16 = &.{},
    /// Inferred upper bound on inputs returned values may alias.
    return_origin: ReturnOrigin = .unknown,
    /// Declared `mutates(...)` footprint; empty also spells an omitted clause.
    declared_mutates: []const u16 = &.{},
    /// Write facts kept separate so a fresh-local write can stay unenforced.
    mutation_facts: MutationFacts = .{},
};
/// Checked function body and its lexical local table.
pub const FunctionScope = struct {
    body: StatementId,
    locals: []const Local = &.{},
};
/// Borrowed checked expression, statement, function, and nominal schema tables.
/// Checked transparent name and its canonical target, retained for public interfaces.
pub const TypeAlias = struct { name: []const u8, target: Type, declaration: Span };
/// Checked semantic graph with arena-owned type and alias identities.
pub const Program = struct { aliases: []const TypeAlias = &.{}, nodes: []const Node, statements: []const Statement, functions: []const Function, main: FunctionId, records: []const Record = &.{} };

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
