//! Resolve generic requirements against the same value operations as concrete code.
const eRequirement = diagnostic.generic_requirement;
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const structural_declarations = @import("structural_declarations.zig");
/// Diagnostic code for generic limits shared by resolution and boundary validation.
const e_generic_limit: []const u8 = "E_GENERIC_LIMIT";
/// Diagnostic code for malformed or shadowing type parameters.
const e_generic_parameter: []const u8 = "E_GENERIC_PARAMETER";
/// Message for too many type parameters on one declaration.
const msg_type_parameter_limit: []const u8 = "at most 16 type parameters are permitted";
/// Message for too many combined requirements on one type parameter.
const msg_requirement_limit: []const u8 = "at most 16 requirements are permitted";
/// Message for a repeated type parameter name.
const msg_duplicate_type_parameter: []const u8 = "duplicate type parameter";
/// Message for a type parameter that shadows a builtin type name.
const msg_shadow_builtin: []const u8 = "type parameter cannot shadow a builtin type";
/// Message for a type parameter with no explicit requirement list.
const msg_explicit_requirement: []const u8 = "type parameter requires an explicit requirement";
/// Related-span message pointing at a named constraint declaration.
const msg_constraint_declared_here: []const u8 = "constraint declared here";
/// Builtin requirements; integer implies equality and equality implies copy.
pub const Requirement = enum(u3) { copy, equality, integer, codec, storable };
/// Closed set of operations promised by an explicitly declared requirement list.
pub const Set = struct {
    bits: u5 = 0,
    /// Include a requirement and its implied prerequisites.
    pub fn include(self: *Set, requirement: Requirement) void {
        self.bits |= switch (requirement) {
            .copy => 17,
            .equality => 19,
            .integer => 23,
            .codec => 8,
            .storable => 16,
        };
    }
    /// Test whether this contract promises a particular operation.
    pub fn contains(self: Set, requirement: Requirement) bool {
        return self.bits & (@as(u5, 1) << @backingInt(requirement)) != 0;
    }
    /// Check implication when forwarding a type parameter to another generic.
    pub fn implies(self: Set, required: Set) bool {
        return self.bits & required.bits == required.bits;
    }
    /// Test a concrete checked type without erasing nominal or result obligations.
    pub fn accepts(self: Set, ty: typed.Type, records: []const typed.Record) bool {
        if (self.contains(.storable) and !typed.storable(ty, records)) return false;
        if (self.contains(.codec) and !@import("source_json.zig").supportsCodec(ty, records)) return false;
        if (self.contains(.integer) and !ty.isInteger()) return false;
        if (self.contains(.equality) and !typed.supportsEquality(ty, records)) return false;
        if (self.contains(.copy) and (typed.moveOnly(ty, records) or typed.requiresHandling(ty, records))) return false;
        return true;
    }
};
/// One named bundle's subject binder re-interpreted by the consuming parameter index.
pub const SubjectAlias = struct { name: source.Span, scope: source.Span, parameter: usize };
/// Heap-owned subject alias list; indirection keeps `Parameter` at its original size.
pub const AliasSet = struct { items: []SubjectAlias };
/// Subject aliases attached to one resolved parameter.
pub fn subjectAliases(parameter: Parameter) []const SubjectAlias {
    return if (parameter.aliases) |set| set.items else &.{};
}
/// How one source span relates to the named-bundle scopes attached to a parameter.
pub const ScopeMatch = union(enum) {
    /// The span is the named declaration's subject and maps to this parameter.
    subject: usize,
    /// The span is declared inside a named declaration but is not its subject.
    foreign,
    /// The span belongs to the consuming declaration's own scope.
    local,
};
/// Classify a span: only a matched subject may become a consumer type-parameter
/// identity; every other leaf inside a named declaration resolves in the
/// declaration's own scope, never by consumer binder spelling.
pub fn matchScope(aliases: []const SubjectAlias, src: source.Source, span: source.Span) ScopeMatch {
    var foreign = false;
    for (aliases) |alias| {
        if (alias.scope.start > span.start or alias.scope.end < span.end) continue;
        foreign = true;
        if (std.mem.eql(u8, src.text(span), src.text(alias.name))) return .{ .subject = alias.parameter };
    }
    return if (foreign) .foreign else .local;
}
/// A named structural contract resolved to its declaration in the active source coordinates.
pub const Definition = struct {
    module: ?usize = null,
    name: source.Span,
    subject: source.Span,
    scope: source.Span,
    body: *const ast.TypeParameter,
    /// Whether the declaration's own builtin list guarantees `copy`.
    copyable: bool = false,
};
/// Lookup seam used by semantic and interface layers without importing module name tables.
pub const Lookup = struct {
    ctx: *anyopaque,
    find: *const fn (ctx: *anyopaque, reference: ast.BoundReference, sink: *diagnostic.Sink) diagnostic.Error!Definition,
};
/// Resolved local type-variable identity and its declared operation contract.
pub const Parameter = struct {
    constant_length: bool = false,
    name: source.Span,
    requirements: Set,
    field_requirements: []const ast.Parameter = &.{},
    operation_requirements: []const ast.Operation = &.{},
    aliases: ?*const AliasSet = null,
};
const ConstraintIdentity = struct { module: ?usize, start: usize, end: usize };
const Counts = struct {
    builtins: u5 = 0,
    fields: std.StringHashMapUnmanaged(void) = .empty,
    operations: std.StringHashMapUnmanaged(void) = .empty,
    fn deinit(self: *Counts, allocator: std.mem.Allocator) void {
        self.fields.deinit(allocator);
        self.operations.deinit(allocator);
    }
    fn total(self: Counts) usize {
        return @as(usize, @popCount(self.builtins)) + self.fields.count() + self.operations.count();
    }
};
/// Resolve names and diagnose malformed declarations even in uncalled templates.
pub fn resolve(allocator: std.mem.Allocator, src: source.Source, parameters: []const ast.TypeParameter, sink: *diagnostic.Sink) diagnostic.Error![]const Parameter {
    if (parameters.len == 0) return &.{};
    if (parameters.len > 16) return sink.fail(e_generic_limit, parameters[16].name, msg_type_parameter_limit);
    const resolved = try allocator.alloc(Parameter, parameters.len);
    errdefer allocator.free(resolved);
    for (parameters, resolved, 0..) |parameter, *out, index| {
        const name = src.text(parameter.name);
        if (typed.Type.fromName(name) != null) return sink.fail(e_generic_parameter, parameter.name, msg_shadow_builtin);
        for (parameters[0..index]) |previous| if (std.mem.eql(u8, name, src.text(previous.name))) return sink.fail(e_generic_parameter, parameter.name, msg_duplicate_type_parameter);
        out.* = .{
            .name = parameter.name,
            .constant_length = parameter.constant_length,
            .requirements = try resolveRequirements(src, parameter, sink),
            .field_requirements = parameter.field_requirements,
            .operation_requirements = parameter.operation_requirements,
        };
        try structural_declarations.validate(src, parameter, out.requirements.contains(.copy), sink);
    }
    return resolved;
}
fn resolveRequirements(src: source.Source, parameter: ast.TypeParameter, sink: *diagnostic.Sink) diagnostic.Error!Set {
    if (parameter.constant_length) return .{};
    if (parameter.default_copy) {
        var default: Set = .{};
        default.include(.copy);
        return default;
    }
    const total = parameter.requirements.len + parameter.named_requirements.len;
    if (total == 0) return sink.fail(eRequirement, parameter.name, msg_explicit_requirement);
    if (total > 16) {
        const at = if (parameter.requirements.len < 16)
            parameter.named_requirements[parameter.requirements.len].name
        else
            parameter.requirements[16];
        return sink.fail(e_generic_limit, at, msg_requirement_limit);
    }
    var result: Set = .{};
    var explicit: u5 = 0;
    try addBuiltinSpans(src, parameter.requirements, sink, &explicit, &result);
    if (parameter.named_requirements.len != 0) return sink.fail(eRequirement, parameter.named_requirements[0].name, "named constraints may only bound function type parameters");
    return result;
}
/// Validate function bounds through a declaration lookup without expanding foreign source spans.
pub fn validateBounds(allocator: std.mem.Allocator, src: source.Source, parameters: []const ast.TypeParameter, sink: *diagnostic.Sink, lookup: Lookup) diagnostic.Error!void {
    if (parameters.len == 0) return;
    if (parameters.len > 16) return sink.fail(e_generic_limit, parameters[16].name, msg_type_parameter_limit);
    for (parameters, 0..) |parameter, index| {
        const name = src.text(parameter.name);
        if (typed.Type.fromName(name) != null) return sink.fail(e_generic_parameter, parameter.name, msg_shadow_builtin);
        for (parameters[0..index]) |previous| if (std.mem.eql(u8, name, src.text(previous.name))) return sink.fail(e_generic_parameter, parameter.name, msg_duplicate_type_parameter);
        try validateOneBound(allocator, src, parameter, sink, lookup);
    }
}
/// Whether an explicit builtin list guarantees `copy` (copy, equality, or integer).
pub fn explicitCopyable(src: source.Source, spans: []const source.Span) bool {
    for (spans) |span| {
        const requirement = std.meta.stringToEnum(Requirement, src.text(span)) orelse continue;
        if (requirement == .copy or requirement == .equality or requirement == .integer) return true;
    }
    return false;
}
/// Expand builtins, named bundles, and inline requirements into the semantic model.
pub fn resolveBounds(allocator: std.mem.Allocator, src: source.Source, parameters: []const ast.TypeParameter, sink: *diagnostic.Sink, lookup: Lookup) diagnostic.Error![]const Parameter {
    if (parameters.len == 0) return &.{};
    if (parameters.len > 16) return sink.fail(e_generic_limit, parameters[16].name, msg_type_parameter_limit);
    const resolved = try allocator.alloc(Parameter, parameters.len);
    errdefer allocator.free(resolved);
    var initialized: usize = 0;
    errdefer deinitResolvedEntries(allocator, resolved[0..initialized]);
    for (parameters, resolved, 0..) |parameter, *out, index| {
        const name = src.text(parameter.name);
        if (typed.Type.fromName(name) != null) return sink.fail(e_generic_parameter, parameter.name, msg_shadow_builtin);
        for (parameters[0..index]) |previous| if (std.mem.eql(u8, name, src.text(previous.name))) return sink.fail(e_generic_parameter, parameter.name, msg_duplicate_type_parameter);
        out.* = try resolveOneBound(allocator, src, parameter, sink, lookup, index);
        initialized += 1;
    }
    return resolved;
}
/// Release parameters and every nested slice allocated by resolveBounds.
pub fn deinitResolved(allocator: std.mem.Allocator, parameters: []const Parameter) void {
    if (parameters.len == 0) return;
    deinitResolvedEntries(allocator, parameters);
    allocator.free(parameters);
}
fn deinitResolvedEntries(allocator: std.mem.Allocator, parameters: []const Parameter) void {
    for (parameters) |parameter| {
        if (parameter.field_requirements.len != 0) allocator.free(parameter.field_requirements);
        if (parameter.operation_requirements.len != 0) allocator.free(parameter.operation_requirements);
        if (parameter.aliases) |set| {
            if (set.items.len != 0) allocator.free(set.items);
            allocator.destroy(@constCast(set));
        }
    }
}
fn validateOneBound(allocator: std.mem.Allocator, src: source.Source, parameter: ast.TypeParameter, sink: *diagnostic.Sink, lookup: Lookup) diagnostic.Error!void {
    if (parameter.constant_length) {
        if (parameter.requirements.len != 0 or parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0 or parameter.named_requirements.len != 0)
            return sink.fail(eRequirement, parameter.name, "constant-length parameters cannot declare requirements");
        return;
    }
    var counts: Counts = .{};
    defer counts.deinit(allocator);
    if (parameter.default_copy) counts.builtins |= @as(u5, 1) << @backingInt(Requirement.copy);
    var resolved: Set = .{};
    try addBuiltinSpans(src, parameter.requirements, sink, &counts.builtins, &resolved);
    for (parameter.field_requirements) |field| try counts.fields.put(allocator, src.text(field.name), {});
    for (parameter.operation_requirements) |operation| try counts.operations.put(allocator, src.text(operation.name), {});
    var identities: std.ArrayList(ConstraintIdentity) = .empty;
    defer identities.deinit(allocator);
    var named_count: usize = 0;
    var copyable = resolved.contains(.copy);
    for (parameter.named_requirements) |reference| {
        const definition = try lookup.find(lookup.ctx, reference, sink);
        copyable = copyable or definition.copyable;
        const identity = identityOf(definition);
        for (identities.items) |previous| if (identityEqual(previous, identity)) return sink.failRelated(
            eRequirement,
            reference.name,
            "duplicate named constraint requirement",
            .{ .span = definition.name, .message = msg_constraint_declared_here },
        );
        try identities.append(allocator, identity);
        if (definition.body.named_requirements.len != 0)
            return sink.failRelated(eRequirement, reference.name, "nested named constraints are not supported in this version", .{ .span = definition.name, .message = msg_constraint_declared_here });
        // Foreign declaration spans stay in their own module's coordinate space:
        // count their declared members directly instead of reading their names.
        named_count += definition.body.requirements.len + definition.body.field_requirements.len + definition.body.operation_requirements.len;
    }
    try structural_declarations.validate(src, parameter, copyable, sink);
    if (counts.builtins == 0 and counts.fields.count() == 0 and counts.operations.count() == 0 and named_count == 0)
        return sink.fail(eRequirement, parameter.name, msg_explicit_requirement);
    // The expanded 16-requirement limit needs resolved member identities, which
    // only the semantic normalization pass has; the parser still bounds each
    // source list, so preflight stays bounded.
}
fn resolveOneBound(allocator: std.mem.Allocator, src: source.Source, parameter: ast.TypeParameter, sink: *diagnostic.Sink, lookup: Lookup, index: usize) diagnostic.Error!Parameter {
    if (parameter.constant_length) {
        if (parameter.requirements.len != 0 or parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0 or parameter.named_requirements.len != 0)
            return sink.fail(eRequirement, parameter.name, "constant-length parameters cannot declare requirements");
        return .{ .name = parameter.name, .constant_length = true, .requirements = .{} };
    }
    var set: Set = .{};
    var explicit: u5 = 0;
    if (parameter.default_copy) {
        explicit |= @as(u5, 1) << @backingInt(Requirement.copy);
        set.include(.copy);
    }
    try addBuiltinSpans(src, parameter.requirements, sink, &explicit, &set);
    var fields: std.ArrayList(ast.Parameter) = .empty;
    defer fields.deinit(allocator);
    try fields.appendSlice(allocator, parameter.field_requirements);
    var operations: std.ArrayList(ast.Operation) = .empty;
    defer operations.deinit(allocator);
    try operations.appendSlice(allocator, parameter.operation_requirements);
    var aliases: std.ArrayList(SubjectAlias) = .empty;
    defer aliases.deinit(allocator);
    var identities: std.ArrayList(ConstraintIdentity) = .empty;
    defer identities.deinit(allocator);
    for (parameter.named_requirements) |reference| {
        const definition = try lookup.find(lookup.ctx, reference, sink);
        const identity = identityOf(definition);
        for (identities.items) |previous| if (identityEqual(previous, identity)) return sink.failRelated(
            eRequirement,
            reference.name,
            "duplicate named constraint requirement",
            .{ .span = definition.name, .message = msg_constraint_declared_here },
        );
        try identities.append(allocator, identity);
        if (definition.body.named_requirements.len != 0)
            return sink.failRelated(eRequirement, reference.name, "nested named constraints are not supported in this version", .{ .span = definition.name, .message = msg_constraint_declared_here });
        var body_set: Set = .{};
        var body_explicit: u5 = 0;
        if (definition.body.default_copy) {
            body_explicit |= @as(u5, 1) << @backingInt(Requirement.copy);
            body_set.include(.copy);
        }
        try addBuiltinSpans(src, definition.body.requirements, sink, &body_explicit, &body_set);
        try structural_declarations.validate(src, definition.body.*, body_set.contains(.copy), sink);
        explicit |= body_explicit;
        set.bits |= body_set.bits;
        try aliases.append(allocator, .{ .name = definition.subject, .scope = definition.scope, .parameter = index });
        try fields.appendSlice(allocator, definition.body.field_requirements);
        try operations.appendSlice(allocator, definition.body.operation_requirements);
    }
    if (explicit == 0 and fields.items.len == 0 and operations.items.len == 0)
        return sink.fail(eRequirement, parameter.name, msg_explicit_requirement);
    // Apply the inline contract's own rules now; cross-bundle identities are
    // coalesced later by the semantic normalization pass.
    try structural_declarations.validate(src, parameter, set.contains(.copy), sink);
    var distinct_fields: std.StringHashMapUnmanaged(void) = .empty;
    defer distinct_fields.deinit(allocator);
    for (fields.items) |field| try distinct_fields.put(allocator, src.text(field.name), {});
    var distinct_operations: std.StringHashMapUnmanaged(void) = .empty;
    defer distinct_operations.deinit(allocator);
    for (operations.items) |operation| try distinct_operations.put(allocator, src.text(operation.name), {});
    // The limit counts unique explicit builtins and unique member names; merging
    // equivalent members keeps that count and conflicting members reject later.
    if (@as(usize, @popCount(explicit)) + distinct_fields.count() + distinct_operations.count() > 16)
        return sink.fail(e_generic_limit, parameter.name, msg_requirement_limit);
    const field_slice = try allocator.dupe(ast.Parameter, fields.items);
    errdefer allocator.free(field_slice);
    const operation_slice = try allocator.dupe(ast.Operation, operations.items);
    errdefer allocator.free(operation_slice);
    const alias_set: ?*AliasSet = if (aliases.items.len == 0) null else set: {
        const items = try allocator.dupe(SubjectAlias, aliases.items);
        errdefer allocator.free(items);
        const created = try allocator.create(AliasSet);
        errdefer allocator.destroy(created);
        created.* = .{ .items = items };
        break :set created;
    };
    return .{
        .name = parameter.name,
        .constant_length = false,
        .requirements = set,
        .field_requirements = field_slice,
        .operation_requirements = operation_slice,
        .aliases = alias_set,
    };
}
fn addBuiltinSpans(src: source.Source, spans: []const source.Span, sink: *diagnostic.Sink, explicit: *u5, set: *Set) diagnostic.Error!void {
    var local: u5 = 0;
    for (spans) |span| {
        const requirement = std.meta.stringToEnum(Requirement, src.text(span)) orelse return sink.fail(eRequirement, span, "unknown requirement; expected copy, equality, integer, codec, or storable");
        const bit: u5 = @as(u5, 1) << @backingInt(requirement);
        if (local & bit != 0) return sink.fail(eRequirement, span, "duplicate type requirement");
        local |= bit;
        explicit.* |= bit;
        set.include(requirement);
    }
}
fn identityOf(definition: Definition) ConstraintIdentity {
    return .{ .module = definition.module, .start = definition.name.start, .end = definition.name.end };
}
fn identityEqual(left: ConstraintIdentity, right: ConstraintIdentity) bool {
    return left.module == right.module and left.start == right.start and left.end == right.end;
}
