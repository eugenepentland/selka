//! Untyped expression and statement tables preserve source spelling and locations.
const effect_set = @import("effect_set.zig");
const std = @import("std");
const Span = @import("source.zig").Span;
/// Index of a parsed expression in the syntax program.
pub const NodeId = enum(usize) { _ };
/// Index of a parsed statement in the syntax program.
pub const StatementId = enum(usize) { _ };
/// Parsed arithmetic, logical, and comparison operators before type checking.
pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    rem,
    floor_div,
    floor_rem,
    python_div,
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
/// Parsed simple and augmented assignment forms.
pub const AssignmentOp = enum { set, add, sub, mul, div, floor_div, rem };
/// Parsed negation and Boolean inversion operators.
pub const UnaryOp = enum { neg, not, is_none, f64_sqrt, f64_floor, f64_ceil, f64_trunc, f64_abs, f64_neg, f64_from_u64, f64_to_u64, f64_from_i64, f64_to_i64 };
/// Source type spelling paired with an expression requiring that type.
pub const TypedValue = struct { ty: Span, value: NodeId };
/// Parsed expression with source-spelled names and unresolved operand identities.
pub const Node = struct {
    span: Span,
    data: union(enum) {
        field_assignment: struct { target: NodeId, value: NodeId },
        index_assignment: struct { target: NodeId, op: AssignmentOp, value: NodeId },
        list_literal: []const NodeId,
        /// `receiver.name(arguments)` on an expression receiver, with the keyword
        /// of each named argument (null for a positional one; empty when none is
        /// named).
        method_call: struct { base: NodeId, name: Span, arguments: []const NodeId, argument_names: []const ?Span = &.{} },
        list_operation: struct { base: NodeId, kind: @import("buffer_operations.zig").Kind, arguments: []const NodeId },
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: Span, arguments: []const NodeId },
        file_operation: struct { kind: @import("file_operations.zig").Method, owner: Span, argument: ?NodeId },
        slice: struct { base: NodeId, start: ?NodeId, end: ?NodeId, step: ?NodeId = null },
        integer: Span,
        bytes: []const u8,
        text: []const u8,
        format: []const NodeId,
        comprehension: Comprehension,
        dictionary_literal: []const NodeId,
        membership: struct { needle: NodeId, container: NodeId, negate: bool = false },
        boolean: bool,
        unit,
        name: Span,
        propagate: NodeId,
        acquire_resource: struct { ty: Span, capability: NodeId, request: NodeId },
        complete_resource: struct { ty: Span, value: NodeId },
        resource_io: struct { kind: @import("external_resources.zig").IoKind, owner: Span, ty: Span, value: ?NodeId },
        restrict_resource: struct { permissions: @import("external_resources.zig").Permissions, value: NodeId },
        environment_get: struct { ty: Span, capability: NodeId, name: NodeId },
        external_read: struct { kind: @import("external_capabilities.zig").Kind, ty: Span, capability: NodeId },
        arena_escape: struct { arena: Span, value: NodeId },
        cast: TypedValue,
        wrap: TypedValue,
        variant: struct {
            ty: Span,
            name: Span,
            /// The single payload of a `case: T` construction.
            value: ?NodeId = null,
            /// A parenthesized case's field arguments in source order, with the
            /// keyword name of each named argument (null for a positional one).
            values: []const NodeId = &.{},
            value_names: []const ?Span = &.{},
            /// Whether this node constructs a parenthesized named-field case,
            /// which stays true even when the call supplies no arguments.
            fielded: bool = false,
        },
        unwrap: NodeId,
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: struct { name: Span, fields: []const FieldInit },
        field: struct { base: NodeId, name: Span },
        call: struct { argument_names: []const ?Span = &.{}, evaluation_order: []const usize = &.{}, owner: ?Span = null, type_arguments: []const Span = &.{}, name: Span, arguments: []const NodeId },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
        /// A parenthesized or bare tuple value; two to eight elements.
        tuple: []const NodeId,
        /// `value_if_true if condition else value_if_false`.
        conditional: struct { condition: NodeId, then_value: NodeId, else_value: NodeId },
        /// The `mut` call-argument marker wrapping its target. No type of its own.
        mut_argument: NodeId,
    },
};
/// Parsed statement and control-flow structure before ownership and type checking.
pub const Statement = struct {
    span: Span,
    implicit_discard: bool = false,
    data: union(enum) {
        with_scope: struct { resource: ?NodeId, name: ?Span, body: StatementId },
        block: []const StatementId,
        assertion: Assertion,
        ret: NodeId,
        loop_exit: bool,
        for_each: struct { name: Span, index_name: ?Span, iterable: NodeId, body: StatementId, enumerated: bool = false },
        for_range: struct { name: Span, start: NodeId, end: NodeId, body: StatementId },
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { condition: NodeId, body: StatementId },
        binding: struct { name: Span, annotation: ?Span, mutable: bool, value: NodeId },
        assignment: struct { name: Span, value: NodeId, op: AssignmentOp, op_span: Span },
    },
};
/// One generator with an optional filter, producing a value per retained element.
pub const Comprehension = struct {
    output: NodeId,
    name: Span,
    source: Source,
    filter: ?NodeId = null,
    /// A comprehension draws its elements from a collection expression or, like a `for`
    /// loop, from a half-open integer `range(...)`; a unit start means the implicit zero.
    pub const Source = union(enum) { iterable: NodeId, range: struct { start: NodeId, end: NodeId } };
};
/// Checked condition with the trap message its failure reports. `literal` is the
/// quoted message's span; `value` is a non-literal message expression, evaluated
/// only when the condition is false.
pub const Assertion = struct { condition: NodeId, message: []const u8, literal: ?Span = null, value: ?NodeId = null };
/// Expression match case with its payload bindings and its yielded value.
/// `bindings` is empty for a payload-free pattern, holds one entry per named
/// field of a parenthesized case, and a null entry discards that field.
pub const MatchArm = struct { ty: Span, name: Span, bindings: []const ?Span = &.{}, body: StatementId };
/// Source-spelled case name, its optional single payload type, and the named
/// fields a parenthesized case declares. `payload` and `fields` are exclusive.
pub const Variant = struct { name: Span, payload: ?Span, fields: []const Parameter = &.{} };
/// Parsed enum, union, or result declaration with its closed case list.
pub const Variants = struct { type_parameters: []const TypeParameter = &.{}, fallible: bool = false, name: Span, is_union: bool, cases: []const Variant };
/// Source field spelling and its initializer expression. `default` marks an
/// initializer the constructor filled from the field's declared default, so a
/// cached literal still contributes a temporary at its construction site.
pub const FieldInit = struct { name: Span, value: NodeId, default: bool = false };
/// Parsed record name and ordered field declarations. `class` is the managed
/// reference spelling; `record` is the explicit copy/value spelling.
pub const Record = struct { managed: bool = false, type_parameters: []const TypeParameter = &.{}, name: Span, fields: []const Parameter };
/// Source parameter name, declared type, and optional literal default.
pub const Parameter = struct {
    default_value: ?NodeId = null,
    name: Span,
    ty: Span,
    /// Whether the declared type was preceded by `mut`.
    mut: bool = false,
};
/// Source-spelled wire type and domain decoder/encoder names.
pub const Codec = struct { wire: Span, decode: Span, encode: Span };
/// Nominal domain declaration with backing type and optional explicit codec.
pub const Domain = struct { managed: bool = false, type_parameters: []const TypeParameter = &.{}, name: Span, backing: Span, codec: ?Codec = null };
/// Parsed signature, visibility, effect bound, provenance annotation, and body.
pub const Function = struct { policy: FunctionPolicy = .{}, signature: FunctionSignature, name: Span, body: StatementId };
/// Source visibility and declared effect bound before name/type resolution.
pub const FunctionPolicy = struct {
    constant: bool = false,
    c_abi: bool = false,
    host: ?Span = null,
    effect_bound: ?effect_set.Bound = null,
    owner: ?Span = null,
    restricted: bool = false,
    conversion: bool = false,
};
/// One named bound requirement; `alias` is null for a same-module name.
pub const BoundReference = struct { alias: ?Span = null, name: Span };
/// Named type variable with explicit source-spelled requirements.
pub const TypeParameter = struct {
    default_copy: bool = false,
    constant_length: bool = false,
    name: Span,
    requirements: []const Span,
    field_requirements: []const Parameter = &.{},
    operation_requirements: []const Operation = &.{},
    named_requirements: []const BoundReference = &.{},
};
/// Explicit public domain operation required by a structural generic contract.
pub const Operation = struct {
    name: Span,
    parameters: []const Parameter,
    return_type: Span,
    effect_bound: effect_set.Bound,
};
/// Named reusable structural contract over exactly one subject binder.
/// `subject` carries the right-hand requirement lists; its own `named_requirements`
/// stays empty because V1 forbids constraint-to-constraint references.
pub const Constraint = struct {
    name: Span,
    span: Span,
    subject: TypeParameter,
};
/// Source parameter and result spellings of one declared function.
pub const FunctionSignature = struct {
    type_parameters: []const TypeParameter = &.{},
    parameters: []const Parameter,
    return_type: Span,
    /// Sorted zero-based positions of the parameters declared `name: mut T`.
    /// This set is the declared mutation footprint of the function.
    mut_positions: []const u16 = &.{},
    /// Abstract-checked direct input positions, retained for interface consumers.
    inferred_mutates: []const u16 = &.{},
    /// Whether the abstract body performed a managed receiver write.
    inferred_mutation_writes: bool = false,
    /// Zero-based index of the first keyword-only parameter, or null when the
    /// list has no `*`. Equal to the positional parameter count.
    keyword_only_from: ?usize = null,
};

/// Fixed integer length or enum key spelling of an array/table type.
pub const ArrayIndex = union(enum) { length: Span, enum_type: Span };
/// Source-spelled array/table shape and element type.
pub const ArrayType = struct { span: Span, index: ArrayIndex, element: Span };
/// Parsed declaration and syntax collections allocated during one parse.
pub const Program = struct {
    types: TypeDeclarations = .{},
    nodes: std.ArrayList(Node),
    statements: std.ArrayList(Statement),
    functions: []const Function,
    lambdas: []const Lambda = &.{},
    /// Fixed-vocabulary attributes attached to declarations, keyed by name span.
    attributes: []const DeclarationAttributes = &.{},
    /// Leading string statements, keyed by the declaration they document.
    docstrings: []const DeclarationDoc = &.{},
};

/// Whether the declaration whose name has this span carries the `public` modifier.
pub fn isPublicDeclaration(program: Program, declaration: Span) bool {
    for (program.types.public_declarations) |span| {
        if (span.start == declaration.start and span.end == declaration.end) return true;
    }
    return false;
}

/// The declaration key a module-level docstring is stored under: the empty span,
/// which no declaration name can occupy.
pub const module_docstring_span = Span{ .start = 0, .end = 0 };
/// One leading string statement: its declaration key, quote-stripped source
/// text, and the literal's own span for diagnostics.
pub const DeclarationDoc = struct { declaration: Span, text: []const u8, span: Span };

/// One fixed-vocabulary attribute kind the parser accepts above a declaration.
pub const AttributeKind = enum { deprecated, @"test", allow };
/// One `@name(...)` clause attached to a declaration.
pub const Attribute = struct {
    kind: AttributeKind,
    /// The whole `@name(...)` clause.
    span: Span,
    /// The `@deprecated` reason or the `@allow` rule name.
    argument: ?Span = null,
    /// The `@allow` `reason="..."` payload.
    reason: ?Span = null,
};
/// One declaration's attribute list, keyed by the declaration name span.
pub const DeclarationAttributes = struct { declaration: Span, attributes: []const Attribute };

/// The attributes attached to the declaration whose name has this span.
pub fn attributesOf(program: Program, declaration: Span) []const Attribute {
    for (program.attributes) |entry| {
        if (entry.declaration.start == declaration.start and entry.declaration.end == declaration.end) return entry.attributes;
    }
    return &.{};
}

/// Whether the declaration whose name has this span carries the given attribute.
pub fn hasAttribute(program: Program, declaration: Span, kind: AttributeKind) bool {
    for (attributesOf(program, declaration)) |attribute| if (attribute.kind == kind) return true;
    return false;
}

/// The docstring recorded for the declaration whose name has this span, if any.
pub fn docstringOf(program: Program, declaration: Span) ?DeclarationDoc {
    for (program.docstrings) |entry| {
        if (entry.declaration.start == declaration.start and entry.declaration.end == declaration.end) return entry;
    }
    return null;
}

/// Zero-based positions of the parameters one flag list marks `mut`, in source
/// order. Consumes the per-parameter flag list a callback type records; the
/// caller owns the returned slice.
pub fn mutPositions(allocator: std.mem.Allocator, flags: []const bool) std.mem.Allocator.Error![]const u16 {
    var positions: [16]u16 = undefined;
    var count: usize = 0;
    for (flags, 0..) |flag, index| {
        if (!flag or count == positions.len) continue;
        positions[count] = @intCast(index);
        count += 1;
    }
    return allocator.dupe(u16, positions[0..count]);
}

/// Expression-bodied anonymous function with contextually typed parameters and result.
pub const Lambda = struct { span: Span, parameters: []const Span, body: NodeId };
/// Source type declarations collected separately from function bodies and expression tables.
pub const TypeDeclarations = struct {
    resources: []const Domain = &.{},
    domains: []const Domain = &.{},
    variants: []const Variants = &.{},
    expressions: TypeExpressions = .{},
    records: []const Record = &.{},
    constraints: []const Constraint = &.{},
    /// Name spans of declarations written with the `public` modifier, which
    /// publishes a declaration instead of a separate `export NAME` directive.
    public_declarations: []const Span = &.{},
};

/// Parsed nominal application; the base name and each type argument retain exact source spans.
pub const TypeApplication = struct { span: Span, name: Span, arguments: []const Span };
/// Structural and nominal type expressions referenced by declarations and function bodies.
/// Transparent non-parameterized alias; the target retains its source type spelling.
pub const TypeAlias = struct { name: Span, target: Span };
/// Structural type syntax, concrete nominal applications and transparent aliases.
/// Noncapturing callable value signature with an explicit effect ceiling.
pub const CallbackType = struct {
    span: Span,
    parameters: []const Span,
    /// Optional binder spelling per parameter; names are excluded from identity.
    parameter_names: []const ?Span = &.{},
    return_type: Span,
    effect_bound: effect_set.Bound,
    /// One flag per parameter in source order, true where the declared type was
    /// preceded by `mut`. The set is the callable's declared mutation footprint.
    mut_parameters: []const bool = &.{},
};
/// One `tuple[T1, ..., Tn]` type spelling with its element type spans.
pub const TupleType = struct { span: Span, elements: []const Span };
/// Source catalog of structural types and nominal type applications.
pub const TypeExpressions = struct { callbacks: []const CallbackType = &.{}, arrays: []const ArrayType = &.{}, applications: []const TypeApplication = &.{}, aliases: []const TypeAlias = &.{}, tuples: []const TupleType = &.{} };
