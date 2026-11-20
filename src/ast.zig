//! Untyped expression and statement tables preserve source spelling and locations.
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
pub const UnaryOp = enum { neg, not, bit_not, is_none, f64_sqrt, f64_floor, f64_ceil, f64_trunc, f64_abs, f64_neg, f64_from_u64, f64_to_u64, f64_from_i64, f64_to_i64, f64_sin, f64_cos, f64_bits, f64_from_bits, f32_bits, f32_from_bits };
/// Source type spelling paired with an expression requiring that type.
pub const TypedValue = struct { ty: Span, value: NodeId };
/// Parsed expression with source-spelled names and unresolved operand identities.
pub const Node = struct {
    span: Span,
    data: union(enum) {
        synthetic_name: []const u8,
        field_assignment: struct { target: NodeId, value: NodeId, op: AssignmentOp = .set, declaration: ?bool = null },
        index_assignment: struct { target: NodeId, op: AssignmentOp, value: NodeId },
        list_literal: []const NodeId,
        /// `receiver.name(arguments)` on an expression receiver, with the keyword
        /// of each named argument (null for a positional one; empty when none is
        /// named).
        method_call: struct { base: NodeId, name: Span, arguments: []const NodeId, argument_names: []const ?Span = &.{} },
        list_operation: struct { base: NodeId, kind: @import("buffer_operations.zig").Kind, arguments: []const NodeId },
        buffer_operation: struct {
            kind: @import("buffer_operations.zig").Kind,
            owner: Span,
            arguments: []const NodeId,
            /// A scalar helper's search keeps scalar positions and a scalar window (C2).
            scalar: bool = false,
        },
        file_operation: struct { kind: @import("file_operations.zig").Method, owner: Span, argument: ?NodeId },
        slice: struct { base: NodeId, start: ?NodeId, end: ?NodeId, step: ?NodeId = null },
        integer: Span,
        bytes: []const u8,
        text: []const u8,
        format: []const NodeId,
        /// One interpolation with a literal format specification, `{value:spec}`
        /// (`PY-FSTRING-SPEC-1`); it appears only as a part of `format`.
        format_field: struct { value: NodeId, spec: Span },
        comprehension: Comprehension,
        /// A comprehension or generator expression whose clauses lower to
        /// ordinary loop statements (`PY-GATHER-1`).
        gather: Gather,
        dictionary_literal: []const NodeId,
        /// `{a, b, ...}`: a set literal's elements in source order (SET-1).
        set_literal: []const NodeId,
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
        /// `__stand_in[T](operand)` (a type span) or `__clock_advance(clock, count)`
        /// (no type span, two operands); standard-library sources only. `__clock_monotonic(clock)`
        /// and `__clock_sleep(clock, count)` are the clock's reading and wait (`op` tells them apart).
        stand_in: struct { ty: ?Span, first: NodeId, second: ?NodeId, op: enum { build, advance, monotonic, sleep, stream_memory, stream_text, fail } = .build },
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
        /// A binary operator. `chained` marks the later links of a Python comparison
        /// chain: `a < b <= c` is `(a < b) <= c` with the outer node chained, which
        /// reads as `a < b and b <= c` with `b` evaluated once.
        binary: struct { op: BinaryOp, left: NodeId, right: NodeId, op_span: Span, chained: bool = false },
        /// A parenthesized or bare tuple value; two to eight elements.
        tuple: []const NodeId,
        /// `value_if_true if condition else value_if_false`.
        conditional: struct { condition: NodeId, then_value: NodeId, else_value: NodeId },
        /// The `mut` call-argument marker wrapping its target. No type of its own.
        mut_argument: NodeId,
        /// A contextual `own value` expression in any transfer position. Core
        /// judges the marked value after typing preserves its source spelling.
        own_argument: NodeId,
        match_expression: struct { value: NodeId, arms: []const MatchArm },
        accept_resource: struct { ty: Span, value: NodeId },
        /// `value is PATTERN`: whether the value is one of the listed cases (`node is text`, `kind is ident | integer`).
        /// `check` is the `match value:` the parser built for it: its first `explicit` arms are the listed cases,
        /// each with an empty body, and a synthetic wildcard arm ends it. `binds` marks a pattern that binds names,
        /// which only the whole condition of an `if`, `elif` or `while` may spell; the parser turns that statement
        /// into the `match` itself, so a node that still binds when it is checked is refused.
        variant_test: struct { value: NodeId, check: StatementId, explicit: u32, binds: bool },
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
        fail: NodeId,
        yield_value: NodeId,
        loop_exit: bool,
        /// `detached` is the `detach` word of `for x in detach place:` (`loop_detach.zig`): the loop sets the place's
        /// collection aside for its run and puts it back at every exit; `iterable` is then the place.
        for_each: struct { name: Span, index_name: ?Span, iterable: NodeId, body: StatementId, enumerated: bool = false, vectorize: bool = false, detached: ?Span = null },
        for_range: struct { name: Span, start: NodeId, end: NodeId, body: StatementId, step: ?NodeId = null, vectorize: bool = false },
        discard: NodeId,
        branch: struct { condition: NodeId, then_body: StatementId, else_body: ?StatementId },
        /// `exclusive` is `match mut <place>:` (C1): the payload bindings write through to the place.
        match: struct { value: NodeId, arms: []const MatchArm, exclusive: bool = false },
        loop: struct { condition: NodeId, body: StatementId },
        /// `adopt` marks the compiler's own `mut x = x` of a bind-or-else: the new local takes over the payload the arm's
        /// binding of the same name holds, with `own` when the payload has managed storage and a plain read when it has none.
        binding: struct { name: Span, annotation: ?Span, mutable: bool, value: NodeId, initialized: bool = true, adopt: bool = false },
        assignment: struct { name: Span, value: NodeId, op: AssignmentOp, op_span: Span },
        /// The innermost statement of a gather loop: hand one produced value
        /// to the comprehension or generator that owns the loop.
        gather_step: GatherStep,
    },
};
/// Append the statements nested directly inside `statement` — a block's
/// children, both branches, every match arm, and the body of a loop, `for` or
/// `with` — so a worklist walk reaches every statement of a body.
pub fn appendNested(allocator: std.mem.Allocator, work: *std.ArrayList(StatementId), statement: Statement) std.mem.Allocator.Error!void {
    switch (statement.data) {
        .block => |children| try work.appendSlice(allocator, children),
        .branch => |branch| {
            try work.append(allocator, branch.then_body);
            if (branch.else_body) |other| try work.append(allocator, other);
        },
        .match => |match| for (match.arms) |arm| {
            try work.append(allocator, arm.body);
        },
        .loop => |loop| try work.append(allocator, loop.body),
        .for_each => |each| try work.append(allocator, each.body),
        .for_range => |range| try work.append(allocator, range.body),
        .with_scope => |scope| try work.append(allocator, scope.body),
        .assertion, .ret, .fail, .yield_value, .loop_exit, .discard, .binding, .assignment, .gather_step => {},
    }
}
/// The bounds of one `range(...)` iteration source: a unit `start` is the implicit
/// zero and a null `step` the implicit one (`PY-RANGE-STEP-1`).
pub const RangeBounds = struct { start: NodeId, end: NodeId, step: ?NodeId = null };
/// One generator with an optional filter, producing a value per retained element.
pub const Comprehension = struct {
    output: NodeId,
    name: Span,
    source: Source,
    filter: ?NodeId = null,
    /// `{value for ...}` builds a `set` instead of a list (SET-1).
    set: bool = false,
    /// A comprehension draws its elements from a collection expression or, like a `for`
    /// loop, from a half-open integer `range(...)`; a unit start means the implicit zero
    /// and a null step the implicit one.
    pub const Source = union(enum) { iterable: NodeId, range: RangeBounds };
};
/// What a gathered comprehension builds from the values its loop produces: a
/// list, a set, a dictionary, or — for a generator expression — whatever its
/// consuming call folds or collects.
pub const GatherShape = enum { list, set, dict, generator };
/// A comprehension or generator expression lowered through its own loop.
/// `loop` is the first `for` clause as an ordinary `for` statement; every
/// further `for` clause nests inside it and every `if` clause is a branch
/// around what follows it, so the innermost statement is the `gather_step`
/// that hands one value to the result. `open` is the opening bracket.
pub const Gather = struct { shape: GatherShape, loop: StatementId, open: Span };
/// One produced value of a gather loop and, for a dict comprehension, its key.
pub const GatherStep = struct { value: NodeId, key: ?NodeId = null };
/// Checked condition with the trap message its failure reports. `literal` is the
/// quoted message's span; `value` is a non-literal message expression, evaluated
/// only when the condition is false.
pub const Assertion = struct { condition: NodeId, message: []const u8, literal: ?Span = null, value: ?NodeId = null };
/// Expression match case with its payload bindings and its yielded value.
/// `bindings` is empty for a payload-free pattern, holds one entry per named
/// field of a parenthesized case, and a null entry discards that field.
pub const Pattern = struct { span: Span, data: union(enum) { binding: ?Span, variant: struct { ty: Span, name: Span, fields: []const PatternField, rest: bool = false } } };
/// One optional field label and its recursively nested payload pattern.
pub const PatternField = struct { name: ?Span = null, pattern: Pattern };
/// One source match case, its payload pattern, and its scoped body.
pub const MatchArm = struct {
    /// `labelled` marks a nested case under a labelled field: a bare name there is that
    /// field's rename, so its qualifier keeps its check without the short-name refusal.
    internal: struct { names: []const []const u8 = &.{}, wildcard: bool = false, labelled: bool = false } = .{},
    payload_patterns: []const PatternField = &.{},
    binding_names: []const ?Span = &.{},
    /// The literal alternatives of a literal arm (`case 0 | 1:`), each a literal
    /// node. Empty for a case arm; a bare name in an int, str, bytes or bool
    /// match is a constant, and sema reads it from `name` there.
    literals: []const NodeId = &.{},
    ty: Span,
    name: Span,
    bindings: []const ?Span = &.{},
    body: StatementId,
    /// How the source spelled the arm's list of cases.
    alternatives: Alternatives = .{},
};
/// What a `case` line adds to one arm beyond its pattern: the rest marker and the `|` list the arm belongs to.
pub const Alternatives = struct {
    /// The pattern ends with the rest marker, `case atom(text, ..)`: every field it does not name is discarded.
    rest: bool = false,
    /// The first alternative's body of the `case a(x) | b(x):` list this arm belongs to (every alternative is an
    /// arm of its own with a copy of the body); null for an arm written alone.
    group: ?StatementId = null,
    /// For a literal arm of bare names (`case a | b:`), a copy of the body for each name after the first, so that
    /// sema can split the list into one arm per case when the matched value is an enum or a union.
    name_bodies: []const StatementId = &.{},
    /// A bare case name in an `is` test (`node is text`): the case with any payload, so a case without one is fine too.
    bare: bool = false,
    /// The arm of a bind-or-else, `const x = f() else Err(e):`: which of the two cases of an Option or a Result it takes,
    /// whatever its source spells. The failure arm's block must leave the enclosing block.
    role: Role = .named,
};
/// Which case a bind-or-else arm takes: the success case (`Some`, `Ok`) or the failure case (`None`, `Err`).
pub const Role = enum { named, success, failure };
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
    named: bool = false,
    default_value: ?NodeId = null,
    name: Span,
    ty: Span,
    /// Whether the declared type was preceded by `mut`.
    mut: bool = false,
    /// Whether the parameter was spelled `own`. A parameter has one of three
    /// modes: plain (reads), `mut` (writes the caller's value) and `own` (takes
    /// the value, so the caller's binding is unusable after the line).
    own: bool = false,
};
/// Source-spelled wire type and domain decoder/encoder names.
pub const Codec = struct { wire: Span, decode: Span, encode: Span };
/// Nominal domain declaration with backing type and optional explicit codec.
pub const Domain = struct { managed: bool = false, type_parameters: []const TypeParameter = &.{}, name: Span, backing: Span, codec: ?Codec = null };
/// Parsed signature, visibility, provenance annotation, and body.
pub const Function = struct { policy: FunctionPolicy = .{}, signature: FunctionSignature, name: Span, body: StatementId };
/// Source visibility and ownership before name/type resolution.
pub const FunctionPolicy = struct {
    constant: bool = false,
    c_abi: bool = false,
    host: ?Span = null,
    owner: ?Span = null,
    restricted: bool = false,
    conversion: bool = false,
    /// `builtin func`: a standard-library declaration with no body on the page, whose calls the compiler supplies
    /// (`builtin_functions.zig`). Only a trusted standard-library source may declare one.
    builtin: bool = false,
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
    /// Source names in an explicit `from` clause, in their written order.
    /// An empty list means the signature declares an owned result.
    borrowing: []const Span = &.{},
    /// Failure type after the result and optional borrowing clause.
    failure_type: ?Span = null,
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
    /// What a program merged from modules knows about itself without a pass over its tables.
    facts: Facts = .{},
};

/// Where one module's syntax lies in a merged program: its nodes, its statements and its source bytes, as half-open runs of ids and
/// offsets. Modules follow one another in all three, so each list is ordered.
pub const Extent = struct { node_start: usize, node_end: usize, statement_start: usize, statement_end: usize, source_start: usize, source_end: usize };

/// One literal the type catalog registers before any body is checked: a text literal (`bytes` null), or a bytes literal that is not spelled
/// `b"..."` and so has a fixed-array shape of `bytes` elements.
pub const Literal = struct { span: Span, bytes: ?usize = null };

/// Which constructs the retired-syntax rejections look for appear anywhere in a module (or, in a merged program, in any module): the
/// rejections scan every statement and node, and a module without the construct has nothing for them to find.
pub const Retired = packed struct {
    /// A `with` scope that names no resource (the retired arena scope).
    arena_scope: bool = false,
    /// A tuple value.
    tuple: bool = false,
    /// A domain `wrap` or `unwrap`.
    wrap: bool = false,
    /// A conditional or value-producing `match` expression, a comprehension or a generator: the forms the migration rejections look
    /// around when they build a repair.
    expression: bool = false,

    /// Whether any of the constructs is present.
    pub fn any(self: Retired) bool {
        return self.arena_scope or self.tuple or self.wrap or self.expression;
    }

    /// The constructs present in either.
    pub fn merge(self: Retired, other: Retired) Retired {
        return .{
            .arena_scope = self.arena_scope or other.arena_scope,
            .tuple = self.tuple or other.tuple,
            .wrap = self.wrap or other.wrap,
            .expression = self.expression or other.expression,
        };
    }

    /// The constructs one node is, or one statement is.
    pub fn ofNode(node: Node) Retired {
        return .{
            .tuple = node.data == .tuple,
            .wrap = node.data == .wrap or node.data == .unwrap,
            .expression = node.data == .conditional or node.data == .match_expression or node.data == .comprehension or node.data == .gather,
        };
    }

    /// The constructs a statement is.
    pub fn ofStatement(statement: Statement) Retired {
        return .{ .arena_scope = statement.data == .with_scope and statement.data.with_scope.resource == null };
    }
};

/// Facts about a merged program that its consumers would otherwise find by scanning every node or statement. A program that was not merged
/// from modules (a parse, a test's hand-made tables) has none, and each consumer then scans as it always did.
pub const Facts = struct {
    /// The modules' extents in module order; empty when the program is one module.
    extents: []const Extent = &.{},
    /// The literals of the whole program in node order, or null when nothing recorded them.
    literals: ?[]const Literal = null,
    /// The retired constructs the program holds, or null when nothing recorded them (a scan then looks, as it always did).
    retired: ?Retired = null,
    /// The loader of a program whose bodies are filled on demand, or null for a program whose tables are complete.
    loader: ?*const Loader = null,
};

/// How a program whose function bodies are filled on demand gets them: the merged tables are as long as the eager ones and hold every
/// declaration-level tree, and a body's nodes and statements are written at their own ids when something asks (`ensureBody`). One
/// loader serves one program on one thread; it is not safe to call from two.
pub const Loader = struct {
    context: *anyopaque,
    /// Fill the body whose root statement is `root`; a root that names no lazy body is already complete.
    body: *const fn (context: *anyopaque, root: StatementId) std.mem.Allocator.Error!void,
    /// Fill every body of module `module`.
    module: *const fn (context: *anyopaque, module: usize) std.mem.Allocator.Error!void,
    /// Fill every body of every module.
    all: *const fn (context: *anyopaque) std.mem.Allocator.Error!void,
    /// Fill, and give the ids of, the lazy body whose root statement spans source offset `at`; null when `at` lies in no lazy body.
    body_at: *const fn (context: *anyopaque, at: usize) std.mem.Allocator.Error!?Scan,
};

/// A run of the node table and a run of the statement table, as ids: what a pass that looks around one source offset reads.
pub const Scan = struct { node_start: usize, node_end: usize, statement_start: usize, statement_end: usize };

/// The tables around source offset `at`, for a pass that looks for the trees next to one site (the node that wraps a call, the binding of
/// a name): the lazy body holding `at`, filled first, or, when `at` lies in no lazy body (a declaration-level tree, a function whose tree is
/// stored with the declarations) or the program is complete, the tables of the module that holds it, which are filled first. A program that
/// records no module extents is one module.
pub fn scanAt(program: Program, at: usize) std.mem.Allocator.Error!Scan {
    if (program.facts.loader) |loader| {
        if (try loader.body_at(loader.context, at)) |body| return body;
        if (extentIndexAt(program, at)) |position| try ensureModule(program, position) else try ensureAll(program);
    }
    const extent = program.facts.extents[extentIndexAt(program, at) orelse return .{ .node_start = 0, .node_end = program.nodes.items.len, .statement_start = 0, .statement_end = program.statements.items.len }];
    return .{ .node_start = extent.node_start, .node_end = extent.node_end, .statement_start = extent.statement_start, .statement_end = extent.statement_end };
}

/// Make the body of the function whose root statement is `root` readable. A program with no loader is complete, so this does nothing.
pub fn ensureBody(program: Program, root: StatementId) std.mem.Allocator.Error!void {
    const loader = program.facts.loader orelse return;
    return loader.body(loader.context, root);
}

/// Make every body of module `module` readable.
pub fn ensureModule(program: Program, module: usize) std.mem.Allocator.Error!void {
    const loader = program.facts.loader orelse return;
    return loader.module(loader.context, module);
}

/// Make every body of the program readable: what a pass that scans the whole tables calls first.
pub fn ensureAll(program: Program) std.mem.Allocator.Error!void {
    const loader = program.facts.loader orelse return;
    return loader.all(loader.context);
}

/// The position in `program.facts.extents` of the module whose source holds offset `at`, or null for a program that records none (one
/// module) or an offset outside them.
pub fn extentIndexAt(program: Program, at: usize) ?usize {
    const extents = program.facts.extents;
    var low: usize = 0;
    var high: usize = extents.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (extents[middle].source_start <= at) low = middle + 1 else high = middle;
    }
    if (low == 0) return null;
    return if (at <= extents[low - 1].source_end) low - 1 else null;
}

/// The position in `program.facts.extents` of the module that holds node `id`, or null for a program that records none or an id outside them.
pub fn extentIndexOfNode(program: Program, id: NodeId) ?usize {
    const extents = program.facts.extents;
    const at = @backingInt(id);
    var low: usize = 0;
    var high: usize = extents.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (extents[middle].node_start <= at) low = middle + 1 else high = middle;
    }
    // A module with no nodes starts where the next one does, so the last extent that starts at or before `at` is the one that holds it.
    if (low == 0) return null;
    return if (at < extents[low - 1].node_end) low - 1 else null;
}

/// The nodes of the module whose source holds offset `at`, or every node of a program that records no extents.
pub fn nodesAt(program: Program, at: usize) []const Node {
    const extent = program.facts.extents[extentIndexAt(program, at) orelse return program.nodes.items];
    return program.nodes.items[extent.node_start..extent.node_end];
}

/// The statements of the module whose source holds offset `at`, or every statement of a program that records no extents.
pub fn statementsAt(program: Program, at: usize) []const Statement {
    const extent = program.facts.extents[extentIndexAt(program, at) orelse return program.statements.items];
    return program.statements.items[extent.statement_start..extent.statement_end];
}

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
/// `requires`, `ensures` and `invariant` are the contract clauses: they carry a
/// condition expression and may repeat on one declaration.
pub const AttributeKind = enum {
    deprecated,
    noalloc,
    @"test",
    allow,
    requires,
    ensures,
    invariant,
    /// `@linear` on a `record`: every owner must be consumed on every path (D-FFI-11, `docs/records-and-unions.md`).
    linear,
    /// `@sealed` on a `record`: only its own module and that module's test file build or change one (W11,
    /// `docs/records-and-unions.md#sealed-records`).
    sealed,
    /// `@freestanding` on a function with a body: it needs nothing from the runtime, which the compiler checks over
    /// everything it calls (`src/freestanding.zig`, `docs/functions.md#freestanding-functions`). After the older
    /// kinds, so they keep their stored numbers.
    freestanding,
    /// `@address` on an `extern func`: the C function it calls is the value of its parameter after `host` (an `extern
    /// type` handle or an address), not a symbol (`docs/c-ffi.md#calls-through-an-address`). Last, so the kinds
    /// before it keep their ordinals.
    address,

    /// Whether this kind is a contract clause with a checked condition.
    pub fn contract(self: AttributeKind) bool {
        return self == .requires or self == .ensures or self == .invariant;
    }
};
/// One `@name(...)` clause attached to a declaration.
pub const Attribute = struct {
    kind: AttributeKind,
    /// The whole `@name(...)` clause.
    span: Span,
    /// The `@deprecated` reason, the `@allow` rule name, or a contract clause's
    /// optional message literal.
    argument: ?Span = null,
    /// The `@allow` `reason="..."` payload.
    reason: ?Span = null,
    /// A contract clause's condition expression.
    condition: ?NodeId = null,
    /// The `old(...)` calls an `@ensures` condition makes, in source order.
    olds: []const NodeId = &.{},
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

/// The source offset a declaration begins at: its first attribute's `@`, or
/// its name when it carries none. Cache regions and interface spellings start
/// here, so an edit to a contract clause above a declaration changes them.
pub fn declarationStart(program: Program, declaration: Span) usize {
    var start = declaration.start;
    for (attributesOf(program, declaration)) |attribute| start = @min(start, attribute.span.start);
    return start;
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
/// Noncapturing callable value signature with explicit parameter types.
pub const CallbackType = struct {
    failure_type: ?Span = null,
    span: Span,
    parameters: []const Span,
    /// Optional binder spelling per parameter; names are excluded from identity.
    parameter_names: []const ?Span = &.{},
    return_type: Span,
    /// One flag per parameter in source order, true where the declared type was
    /// preceded by `mut`. The set is the callable's declared mutation footprint.
    /// `own` marks the positions that take their argument, so a call through
    /// this function type moves the value it passes.
    parameter_modes: struct { mut: []const bool = &.{}, named: []const bool = &.{}, own: []const bool = &.{} } = .{},
};
/// One `tuple[T1, ..., Tn]` type spelling with its element type spans.
pub const TupleType = struct { span: Span, elements: []const Span };
/// Source catalog of structural types and nominal type applications.
pub const TypeSuffix = struct { span: Span, base: Span, kind: enum { growable, optional } };
/// Source structural types, applications, and transparent aliases.
pub const TypeExpressions = struct {
    suffixes: []const TypeSuffix = &.{},
    callbacks: []const CallbackType = &.{},
    arrays: []const ArrayType = &.{},
    applications: []const TypeApplication = &.{},
    aliases: []const TypeAlias = &.{},
    tuples: []const TupleType = &.{},
};
