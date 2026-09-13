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
/// Parsed simple, additive, and subtractive assignment forms.
pub const AssignmentOp = enum { set, add, sub };
/// Parsed negation and Boolean inversion operators.
pub const UnaryOp = enum { neg, not, f64_sqrt, f64_floor, f64_ceil, f64_trunc, f64_abs, f64_neg, f64_from_u64, f64_to_u64, f64_from_i64, f64_to_i64 };
/// Source type spelling paired with an expression requiring that type.
pub const TypedValue = struct { ty: Span, value: NodeId };
/// Parsed expression with source-spelled names and unresolved operand identities.
pub const Node = struct {
    span: Span,
    data: union(enum) {
        field_assignment: struct { target: NodeId, value: NodeId },
        list_literal: []const NodeId,
        method_call: struct { base: NodeId, name: Span, arguments: []const NodeId },
        list_operation: struct { base: NodeId, kind: @import("buffer_operations.zig").Kind, arguments: []const NodeId },
        buffer_operation: struct { kind: @import("buffer_operations.zig").Kind, owner: Span, arguments: []const NodeId },
        slice: struct { base: NodeId, start: ?NodeId, end: ?NodeId },
        integer: Span,
        bytes: []const u8,
        text: []const u8,
        format: []const NodeId,
        dictionary_literal: []const NodeId,
        membership: struct { needle: NodeId, container: NodeId, negate: bool = false },
        boolean: bool,
        unit,
        match_expression: struct { value: NodeId, arms: []const MatchValueArm },
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
        variant: struct { ty: Span, name: Span, value: ?NodeId },
        unwrap: NodeId,
        array: struct { ty: Span, values: []const NodeId },
        index: struct { base: NodeId, index: NodeId },
        replace: struct { base: NodeId, index: NodeId, value: NodeId },
        length: NodeId,
        record: struct { name: Span, fields: []const FieldInit },
        field: struct { base: NodeId, name: Span },
        call: struct { argument_names: []const ?Span = &.{}, evaluation_order: []const usize = &.{}, owner: ?Span = null, type_arguments: []const Span = &.{}, name: Span, arguments: []const NodeId },
        unary: struct { op: UnaryOp, operand: NodeId, op_span: Span },
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span },
    },
};
/// Parsed statement and control-flow structure before ownership and type checking.
pub const Statement = struct {
    span: Span,
    implicit_discard: bool = false,
    data: union(enum) {
        managed_arena: struct { name: ?Span, body: StatementId },
        block: []const StatementId,
        assertion: Assertion,
        ret: NodeId,
        loop_exit: bool,
        for_each: struct { name: Span, index_name: ?Span, iterable: NodeId, body: StatementId },
        for_range: struct { name: Span, start: NodeId, end: NodeId, body: StatementId },
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        match: struct { value: NodeId, arms: []const MatchArm },
        loop: struct { condition: NodeId, body: StatementId },
        binding: struct { name: Span, annotation: ?Span, mutable: bool, value: NodeId },
        assignment: struct { python: bool = false, name: Span, value: NodeId, op: AssignmentOp, op_span: Span },
    },
};
/// Checked condition with the trap message its failure reports.
pub const Assertion = struct { condition: NodeId, message: []const u8, literal: ?Span = null };
/// Expression match case with an optional payload binding and its yielded value.
pub const MatchValueArm = struct { ty: Span, name: Span, binding: ?Span, discard_payload: bool, value: NodeId };
/// Source case spelling, optional payload binding, and arm body.
pub const MatchArm = struct { ty: Span, name: Span, binding: ?Span, discard_payload: bool, body: StatementId };
/// Source-spelled case name and optional payload type.
pub const Variant = struct { name: Span, payload: ?Span };
/// Parsed enum, union, or result declaration with its closed case list.
pub const Variants = struct { type_parameters: []const TypeParameter = &.{}, fallible: bool = false, name: Span, is_union: bool, cases: []const Variant };
/// Source field spelling and its initializer expression.
pub const FieldInit = struct { name: Span, value: NodeId };
/// Parsed record name and ordered field declarations.
pub const Record = struct { type_parameters: []const TypeParameter = &.{}, name: Span, fields: []const Parameter };
/// Source parameter name, declared type, and optional literal default.
pub const Parameter = struct { default_value: ?NodeId = null, name: Span, ty: Span };
/// Source-spelled wire type and domain decoder/encoder names.
pub const Codec = struct { wire: Span, decode: Span, encode: Span };
/// Nominal domain declaration with backing type and optional explicit codec.
pub const Domain = struct { managed: bool = false, type_parameters: []const TypeParameter = &.{}, name: Span, backing: Span, codec: ?Codec = null };
/// Parsed signature, visibility, effect bound, provenance annotation, and body.
pub const Function = struct { policy: FunctionPolicy = .{}, signature: FunctionSignature, name: Span, body: StatementId };
/// Source visibility and declared effect bound before name/type resolution.
pub const FunctionPolicy = struct {
    python: bool = false,
    constant: bool = false,
    c_abi: bool = false,
    host: ?Span = null,
    effect_bound: ?effect_set.Bound = null,
    owner: ?Span = null,
    restricted: bool = false,
    conversion: bool = false,
};
/// Named type variable with explicit source-spelled requirements.
pub const TypeParameter = struct {
    default_copy: bool = false,
    constant_length: bool = false,
    name: Span,
    requirements: []const Span,
    field_requirements: []const Parameter = &.{},
    operation_requirements: []const Operation = &.{},
};
/// Explicit public domain operation required by a structural generic contract.
pub const Operation = struct {
    name: Span,
    parameters: []const Parameter,
    return_type: Span,
    effect_bound: effect_set.Bound,
};
/// Source parameter and result spellings of one declared function.
pub const FunctionSignature = struct { type_parameters: []const TypeParameter = &.{}, parameters: []const Parameter, return_type: Span };

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
};
/// Source type declarations collected separately from function bodies and expression tables.
pub const TypeDeclarations = struct {
    resources: []const Domain = &.{},
    domains: []const Domain = &.{},
    variants: []const Variants = &.{},
    expressions: TypeExpressions = .{},
    records: []const Record = &.{},
};

/// Parsed nominal application; the base name and each type argument retain exact source spans.
pub const TypeApplication = struct { span: Span, name: Span, arguments: []const Span };
/// Structural and nominal type expressions referenced by declarations and function bodies.
/// Transparent non-parameterized alias; the target retains its source type spelling.
pub const TypeAlias = struct { name: Span, target: Span };
/// Structural type syntax, concrete nominal applications and transparent aliases.
/// Noncapturing callable value signature with an explicit effect ceiling.
pub const CallbackType = struct { span: Span, parameters: []const Span, return_type: Span, effect_bound: effect_set.Bound };
/// Source catalog of structural types and nominal type applications.
pub const TypeExpressions = struct { callbacks: []const CallbackType = &.{}, arrays: []const ArrayType = &.{}, applications: []const TypeApplication = &.{}, aliases: []const TypeAlias = &.{} };
