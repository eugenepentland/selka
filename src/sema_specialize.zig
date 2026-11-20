//! Generic specialization: choosing the function instance a call names,
//! fingerprinting a concrete specialization, reusing a checked body from the
//! semantic cache (C3) and publishing freshly checked ones back to it, and
//! inferring type arguments from call operands. Each step is a free function
//! over the concrete checker type; `Checks` exposes the ones the rest of the
//! checker calls as `self.name(...)`.
const sem_copy = @import("semantic_copy.zig");
const generic_specializations = @import("generic_specializations.zig");
const semantic_key = @import("semantic_key.zig");
const sem_entry = @import("semantic_entry.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const std = @import("std");
const product = @import("product.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const instances = @import("generic_instances.zig");
const builtin = @import("builtin");
const impl = @This();
const type_recipe = @import("semantic_type_recipe.zig");
const stand_ins = @import("template_stand_ins.zig");

/// Extend one request's name index as checking appends catalog records. A
/// duplicate remains ambiguous, and every record name is visited exactly once.
fn indexRecordNames(allocator: std.mem.Allocator, names: *std.StringHashMapUnmanaged(usize), indexed: *usize, records: []const typed.Record) std.mem.Allocator.Error!usize {
    const before = indexed.*;
    while (indexed.* < records.len) : (indexed.* += 1) {
        const entry = try names.getOrPut(allocator, records[indexed.*].name);
        entry.value_ptr.* = if (entry.found_existing) std.math.maxInt(usize) else indexed.*;
    }
    return indexed.* - before;
}

// spec-case: SPECIALIZATION-NAME-INDEX-1
test "F10 specialization name index retains appended duplicates as ambiguous" {
    const testing = std.testing;
    var records: [3]typed.Record = undefined;
    for ([_][]const u8{ "First", "Second", "First" }, 0..) |name, index| {
        records[index] = .{ .id = @fromBackingInt(typed.Type.record_base + index), .name = name, .declaration = .{ .start = 0, .end = 0 }, .fields = &.{} };
    }
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(testing.allocator);
    var indexed: usize = 0;
    try testing.expectEqual(@as(usize, 2), try indexRecordNames(testing.allocator, &names, &indexed, records[0..2]));
    try testing.expectEqual(@as(?usize, 0), names.get("First"));
    try testing.expectEqual(@as(usize, 1), try indexRecordNames(testing.allocator, &names, &indexed, &records));
    try testing.expectEqual(@as(?usize, std.math.maxInt(usize)), names.get("First"));
    try testing.expectEqual(@as(?usize, 1), names.get("Second"));
    try testing.expectEqual(@as(?usize, null), names.get("Missing"));
    try testing.expectEqual(@as(usize, 0), try indexRecordNames(testing.allocator, &names, &indexed, &records));
    try testing.expectEqual(@as(?usize, std.math.maxInt(usize)), names.get("First"));
}

/// Bind generic specialization to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Replay one checked concrete specialization when every retained reference
        /// remaps to a fresh identity. A missing or ambiguous reference, an
        /// unvalidated fingerprint, a changed defining region or a reference to a
        /// specialization that the fresh run has not instantiated is a conservative
        /// miss; an unvalidated specialization is never reused.
        pub fn lookupSpecialization(self: *Checker, reuse: *generic_specializations.Session, allocator: std.mem.Allocator, index: usize, nodes: *std.ArrayList(typed.Node), statements: *std.ArrayList(typed.Statement)) Error!?typed.Function {
            return impl.lookupSpecialization(Checker, self, reuse, allocator, index, nodes, statements);
        }
        /// Install a borrowed request bridge so ordinary callers can retain validated instance edges.
        pub fn bindOrdinaryReferences(self: *Checker, queries: *@import("semantic_cache.zig").Session, reuse: *generic_specializations.Session) error{OutOfMemory}!void {
            const bridge = try self.allocator.create(ReferenceBridge(Checker));
            bridge.* = .{ .checker = self, .reuse = reuse };
            queries.reuse.resolver = .{
                .context = bridge,
                .capture = ReferenceBridge(Checker).capture,
                .resolve = ReferenceBridge(Checker).resolve,
                .resolve_type = ReferenceBridge(Checker).resolveType,
                .type_shape = ReferenceBridge(Checker).typeShape,
                .resolve_record = ReferenceBridge(Checker).resolveRecord,
                .instance = ReferenceBridge(Checker).instance,
            };
        }
        /// Capture every specialization freshly checked by this request and publish
        /// them after the whole graph passed. A tree that references a synthesized
        /// lambda, an interned catalog record or an unresolvable identity is a
        /// conservative miss, never a partial entry.
        pub fn publishSpecializations(self: *Checker, reuse: *generic_specializations.Session, allocator: std.mem.Allocator, program: typed.Program) Error!void {
            return impl.publishSpecializations(Checker, self, reuse, allocator, program);
        }
        /// The function instance a call to a declaration names: its ordinary instance, or a
        /// generic specialization for the inferred or explicit type arguments.
        pub fn specialize(self: *Checker, declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
            return impl.specialize(Checker, self, declaration, call, span);
        }
        /// Register a representative instance of each generic function of the program's own modules that
        /// nothing instantiated (`Sink.template_probes`, set by `check`); returns how many were registered.
        pub fn probeTemplates(self: *Checker, host: ?JudgmentHost) Error!usize {
            return impl.probeTemplates(Checker, self, host);
        }
    };
}

/// `check` judges every generic body at its declaration (W3 step 2, `diagnostic.Probes.declaration`): it registers one instance
/// of each template, the standard library's and the instantiated ones included, for each choice of
/// `template_stand_ins.declarationChoice` whose stand-ins the template's bounds admit, so the ownership checker sees each body as
/// a program passing that kind would. A template with a structural requirement, or a foreign declaration, is left to the
/// instances programs make. Returns how many instances are new; they are the instances from the count's first index on.
fn probeTemplates(comptime Checker: type, self: *Checker, host: ?JudgmentHost) Error!usize {
    switch (self.sink.template_probes) {
        .every => |log| return probeStandIns(Checker, self, log),
        else => {},
    }
    const first = self.instance_keys.items.len;
    const types = try standInTypes(Checker, self);
    for (self.syntax.functions, 0..) |function, index| {
        const parameters = function.signature.type_parameters;
        if (parameters.len == 0 or parameters.len > instances.Registry.max_arguments) continue;
        // A foreign declaration and a `builtin func` (the compiler supplies its calls) have no body to judge. The standard
        // library is judged once per compiler, by a gate test (`template-stand-ins --standard-library`), not in every check; and a
        // template whose judgment the ownership proofs hold under this run's inputs is not judged again (`held`).
        if (function.policy.c_abi or function.policy.host != null or function.policy.builtin) continue;
        if (standardOwner(self.src, function.policy.owner)) continue;
        var provider: @import("constraint_lookup.zig").Provider = .{ .program = self.syntax, .src = self.src, .names = self.catalog.module_names };
        const required = try @import("generic_requirements.zig").resolveBounds(self.allocator, self.src, parameters, self.sink, provider.lookup());
        defer @import("generic_requirements.zig").deinitResolved(self.allocator, required);
        const structural = for (required) |parameter| {
            if (parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0) break true;
        } else false;
        if (structural) continue;
        if (host) |given| if (try given.holds(self.allocator, self.src, index)) continue;
        const scratch = try self.allocator.alloc(stand_ins.Kind, parameters.len);
        defer self.allocator.free(scratch);
        var which: usize = 0;
        while (stand_ins.declarationChoice(parameters.len, which, scratch)) |chosen| : (which += 1) {
            // A constant length stands in as 2 whatever the kind, so only the choices that give it `int` are distinct.
            const repeated = for (required, chosen) |parameter, kind| {
                if (parameter.constant_length and kind != .int) break true;
            } else false;
            if (repeated) continue;
            _ = try standInOutcome(Checker, self, .{ .declaration = index, .required = required, .chosen = chosen, .types = &types });
        }
    }
    return self.instance_keys.items.len - first;
}

/// How `check` asks whether a template's judgment at its declaration is proven under this run's inputs (W3 step 2): the host's
/// callback (`semantic_summary.Demand.judged`) and the check's prepared keys.
pub const JudgmentHost = struct {
    context: *const anyopaque,
    judged: *const fn (context: *const anyopaque, key: []const u8, context_digest: [32]u8, region_digest: [32]u8) bool,
    prepared: *const semantic_key.Prepared,

    /// Whether the judgment of the template at AST index `index` of `src` is held: its stable key, its dependency context folded
    /// with the judgment's rule, and the digest of its declaration's tokens (`stand_in_kinds.tokenDigest`: a comment or a line shift
    /// leaves it, a token does not; the region's bytes when the lexer refuses the region alone).
    pub fn holds(self: JudgmentHost, allocator: std.mem.Allocator, src: source.Source, index: usize) error{OutOfMemory}!bool {
        const prepared = self.prepared;
        if (index >= prepared.keys.len or index >= prepared.recalled.digests.len or index >= prepared.regions.len) return false;
        const region = (try @import("stand_in_kinds.zig").tokenDigest(allocator, src.text(prepared.regions[index]))) orelse prepared.recalled.digests[index];
        return self.judged(self.context, prepared.keys[index], stand_ins.judgmentContext(prepared.contexts[index]), region);
    }
};

/// Whether a function owned by module `owner` comes from the compiler's embedded standard library.
fn standardOwner(src: source.Source, owner: ?source.Span) bool {
    const span = owner orelse return false;
    var path: [256]u8 = undefined;
    const name = src.text(span);
    if (name.len + product.source_suffix.len > path.len) return false;
    @memcpy(path[0..name.len], name);
    for (path[0..name.len]) |*byte| if (byte.* == '.') {
        byte.* = '/';
    };
    @memcpy(path[name.len..][0..product.source_suffix.len], product.source_suffix);
    return @import("standard_library.zig").source(path[0 .. name.len + product.source_suffix.len]) != null;
}

/// The type each stand-in kind stands for in this program: `int`, `str`, the record `tuple[str, int]`, `int[]`, and the first
/// resource the program declares (else a record that holds one; null when there is none).
fn standInTypes(comptime Checker: type, self: *Checker) Error![stand_ins.kinds.len]?typed.Type {
    const span: source.Span = .{ .start = 0, .end = 0 };
    var types: [stand_ins.kinds.len]?typed.Type = @splat(null);
    types[@backingInt(stand_ins.Kind.int)] = .i64;
    const text = try nominal_catalog.materializePrelude(&self.catalog, "str", span);
    types[@backingInt(stand_ins.Kind.text)] = text;
    if (text) |found| types[@backingInt(stand_ins.Kind.record)] = try nominal_catalog.instantiateTuple(&self.catalog, &.{ found, .i64 }, span);
    if (nominal_catalog.instanceDeclaration(&self.catalog, "List", 1)) |list| types[@backingInt(stand_ins.Kind.list)] = try nominal_catalog.instantiateLengths(&self.catalog, list, &.{.i64}, &.{}, span);
    // A resource itself (`network.Connection`) when the program has one, else a record that holds one.
    for (self.catalog.records) |record| if (record.contract.move_only and !record.contract.linear and record.shape.resource != null) {
        types[@backingInt(stand_ins.Kind.move_only)] = record.id;
        break;
    } else for (self.catalog.records) |holder| if (holder.contract.move_only and !holder.contract.linear) {
        types[@backingInt(stand_ins.Kind.move_only)] = holder.id;
        break;
    };
    return types;
}

/// The stand-in count of W3 (`diagnostic.Probes.every`): register an instance of every template, the standard library's and the
/// instantiated ones included, for each choice of stand-in kinds its bounds allow (`template_stand_ins.choice`), and record each
/// choice in `log`. A choice whose stand-in a bound refuses, a structural requirement, a `@linear` type or a missing move-only
/// type is recorded as skipped. Returns how many instances are new.
fn probeStandIns(comptime Checker: type, self: *Checker, log: *stand_ins.Log) Error!usize {
    log.first_stand_in = self.instance_keys.items.len;
    const types = try standInTypes(Checker, self);
    for (types, 0..) |maybe, k| log.types[k] = if (maybe) |ty| try log.allocator.dupe(u8, typed.typeName(ty, self.catalog.records)) else "";
    for (self.syntax.functions, 0..) |function, index| {
        const parameters = function.signature.type_parameters;
        if (parameters.len == 0) continue;
        const name = if (index < self.declared_names.len) self.declared_names[index] else self.src.text(function.name);
        var provider: @import("constraint_lookup.zig").Provider = .{ .program = self.syntax, .src = self.src, .names = self.catalog.module_names };
        const required = try @import("generic_requirements.zig").resolveBounds(self.allocator, self.src, parameters, self.sink, provider.lookup());
        defer @import("generic_requirements.zig").deinitResolved(self.allocator, required);
        const scratch = try self.allocator.alloc(stand_ins.Kind, parameters.len);
        defer self.allocator.free(scratch);
        var which: usize = 0;
        while (stand_ins.choice(parameters.len, which, scratch)) |chosen| : (which += 1) {
            // A constant length stands in as 2 whatever the kind, so only the choices that give it `int` are distinct.
            const repeated = for (required, chosen) |parameter, kind| {
                if (parameter.constant_length and kind != .int) break true;
            } else false;
            if (repeated) continue;
            const outcome = try standInOutcome(Checker, self, .{ .declaration = index, .required = required, .chosen = chosen, .types = &types });
            try log.rows.append(log.allocator, .{ .name = name, .at = function.name, .chosen = try log.allocator.dupe(stand_ins.Kind, chosen), .outcome = outcome });
        }
    }
    return self.instance_keys.items.len - log.first_stand_in;
}

/// One template and one choice of stand-in kinds, for `standInOutcome`.
const StandInChoice = struct {
    declaration: usize,
    required: []const @import("generic_requirements.zig").Parameter,
    chosen: []const stand_ins.Kind,
    types: *const [stand_ins.kinds.len]?typed.Type,
};

/// The instance one choice of stand-in kinds registers, or why it is skipped.
fn standInOutcome(comptime Checker: type, self: *Checker, given: StandInChoice) Error!stand_ins.Outcome {
    if (given.required.len > instances.Registry.max_arguments) return .{ .skipped = "too many type parameters" };
    const arguments = try self.allocator.alloc(typed.Type, given.required.len);
    const lengths = try self.allocator.alloc(?usize, given.required.len);
    @memset(lengths, null);
    for (given.required, given.chosen, arguments, lengths) |parameter, kind, *argument, *length| {
        if (parameter.constant_length) {
            // A constant length stands in as 2, the same for every kind.
            argument.* = .u64;
            length.* = 2;
            continue;
        }
        if (parameter.field_requirements.len != 0 or parameter.operation_requirements.len != 0) return .{ .skipped = "structural requirement" };
        argument.* = given.types[@backingInt(kind)] orelse return .{ .skipped = "no such type in the program" };
        if (typed.linear(argument.*, self.catalog.records)) return .{ .skipped = "@linear type argument" };
        if (!parameter.requirements.accepts(argument.*, self.catalog.records)) return .{ .skipped = "bound" };
    }
    const fingerprint = try specializationFingerprint(Checker, self, given.declaration, arguments, lengths);
    const id = registerInstance(Checker, self, @fromBackingInt(given.declaration), arguments, lengths, fingerprint) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return error.InternalError,
        else => return .{ .skipped = "instance budget" },
    };
    return .{ .instance = @backingInt(id) };
}

/// The function instance a call to a declaration names: its ordinary instance, or a
/// generic specialization for the inferred or explicit type arguments.
fn specialize(comptime Checker: type, self: *Checker, declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
    const function = self.syntax.functions[@backingInt(declaration)];
    if (call.type_arguments.len != 0 and call.type_arguments.len != function.signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
    if (self.ordinary_ids[@backingInt(declaration)]) |id| return id;
    var provider: @import("constraint_lookup.zig").Provider = .{ .program = self.syntax, .src = self.src, .names = self.catalog.module_names };
    const required = try @import("generic_requirements.zig").resolveBounds(self.allocator, self.src, function.signature.type_parameters, self.sink, provider.lookup());
    defer @import("generic_requirements.zig").deinitResolved(self.allocator, required);
    const arguments = try self.allocator.alloc(typed.Type, required.len);
    const lengths = try self.allocator.alloc(?usize, required.len);
    @memset(lengths, null);
    if (call.type_arguments.len == 0) {
        try inferArguments(Checker, self, function.signature, call, span, arguments, lengths);
    }
    for (required, arguments, 0..) |parameter, *argument, argument_index| {
        const at = if (call.type_arguments.len == 0) span else call.type_arguments[argument_index];
        if (parameter.constant_length) {
            if (call.type_arguments.len != 0) lengths[argument_index] = try self.lengthArgument(at);
            argument.* = .u64;
            continue;
        }
        if (call.type_arguments.len != 0) argument.* = try self.ty(at);
        if (typed.linear(argument.*, self.catalog.records)) return @import("linear_rules.zig").refuse(self.sink, at, .generic);
        if (parameter.requirements.contains(.codec)) if (try @import("codec_form.zig").refusal(self.allocator, argument.*, self.catalog.records)) |text|
            return self.sink.failRelated(@import("codec_form.zig").code, at, text, .{ .span = parameter.name, .message = "the `codec` bound is declared here" });
        if (!parameter.requirements.accepts(argument.*, self.catalog.records)) return self.sink.failRelated(
            "E_GENERIC_ARGUMENT",
            at,
            "type argument does not satisfy the callee's declared requirements",
            .{ .span = parameter.name, .message = "required type parameter declared here" },
        );
    }
    for (required, arguments) |parameter, argument| try (@import("structural_constraints.zig").Context{
        .src = self.src,
        .catalog = &self.catalog,
        .program = self.syntax,
        .sink = self.sink,
        .lengths = lengths,
    }).accepts(self.allocator, argument, parameter, function.signature.type_parameters, arguments);
    const fingerprint = try specializationFingerprint(Checker, self, @backingInt(declaration), arguments, lengths);
    return registerInstance(Checker, self, declaration, arguments, lengths, fingerprint) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return error.InternalError,
        else => return self.sink.fail("E_GENERIC_LIMIT", span, "generic specialization exceeds instance or type argument budget"),
    };
}
/// Register only fresh, validated arguments; the existing bounded worklist checks or replays the body.
fn registerInstance(
    comptime Checker: type,
    self: *Checker,
    declaration: instances.DeclarationId,
    arguments: []const typed.Type,
    lengths: []const ?usize,
    fingerprint: ?[]const u8,
) error{ OutOfMemory, InternalError, TooManyInstances, TooManyTypeArguments }!typed.FunctionId {
    const instance = try self.generic_registry.intern(self.allocator, .{ .declaration = declaration, .arguments = arguments, .lengths = lengths });
    const index = self.ordinary_count + @backingInt(instance);
    if (index == self.instance_keys.items.len) {
        const owned_key = self.generic_registry.get(instance) catch return error.InternalError;
        try self.instance_keys.append(self.allocator, owned_key);
        try self.spec_ranges.append(self.allocator, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
        try self.spec_fingerprints.append(self.allocator, fingerprint);
        if (fingerprint) |canonical| {
            const entry = try self.spec_index.getOrPut(self.allocator, canonical);
            entry.value_ptr.* = @fromBackingInt(index);
        }
    }
    return @fromBackingInt(index);
}
/// Canonical `specialization-v2` fingerprint of one fresh instance. Null
/// when no semantic cache (and therefore no prepared declaration facts) is
/// attached. The template identity, ordered positional descriptors, resolved
/// provider contracts, template constraint dependency, declared
/// effect/mutation/return-origin contract and build context all participate;
/// every boundary is length-prefixed by the key engine.
fn specializationFingerprint(comptime Checker: type, self: *Checker, declaration: usize, arguments: []const typed.Type, lengths: []const ?usize) Error!?[]const u8 {
    // A zero-retention counting session cannot consume or publish these keys.
    if (!self.spec_fingerprints_enabled) return null;
    const prepared = self.prepared orelse return null;
    const function = self.syntax.functions[declaration];
    const descriptors = try self.allocator.alloc([]const u8, arguments.len);
    for (arguments, 0..) |argument, i| descriptors[i] = try semantic_key.argumentDescriptor(self.allocator, argument, if (i < lengths.len) lengths[i] else null, self.catalog.records);
    const provider = try semantic_key.providerIdentity(self.allocator, arguments, self.catalog.records);
    // Core's mandatory declaration preflight already validated source eligibility.
    // Canonical identity needs only those source names' declaration positions.
    const sources = try @import("declaration_borrow.zig").positions(self.allocator, self.src, function.signature);
    defer self.allocator.free(sources);
    const borrowing: typed.ReturnOrigin = if (sources.len == 0) .fresh else .{ .params = sources };
    const contract = semantic_key.declaredContractDigest(function.signature.mut_positions, borrowing);
    const canonical = try semantic_key.specializationFingerprint(self.allocator, .{
        .template_identity = prepared.keys[declaration],
        .arguments = descriptors,
        .provider = provider,
        .constraints = prepared.contexts[declaration][0..],
        .contracts = contract[0..],
        .build = self.spec_build,
    });
    return canonical;
}
// spec-case: SEMANTIC-CACHE-14
test "disabled specialization fingerprints allocate no canonical identity" {
    const t = std.testing;
    const span: source.Span = .{ .start = 0, .end = 0 };
    const functions = [_]ast.Function{.{ .name = span, .body = @fromBackingInt(@intCast(0)), .signature = .{ .parameters = &.{}, .return_type = span } }};
    const prepared: semantic_key.Prepared = .{ .bodies = &.{}, .regions = &.{}, .keys = &.{}, .contexts = &.{}, .ordinary_ast = &.{} };
    const Probe = struct {
        spec_fingerprints_enabled: bool,
        prepared: ?*const semantic_key.Prepared,
        syntax: struct { functions: []const ast.Function },
        allocator: std.mem.Allocator,
        catalog: struct { records: []const typed.Record },
        src: source.Source = .{ .path = "test.selka", .bytes = "", .line_starts = &.{0} },
        spec_build: []const u8 = "test",
    };
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    var probe: Probe = .{ .spec_fingerprints_enabled = false, .prepared = &prepared, .syntax = .{ .functions = &functions }, .allocator = failing.allocator(), .catalog = .{ .records = &.{} } };
    try t.expectEqual(@as(?[]const u8, null), try specializationFingerprint(Probe, &probe, 0, &.{.i64}, &.{}));
    probe.spec_fingerprints_enabled = true;
    try t.expectError(error.OutOfMemory, specializationFingerprint(Probe, &probe, 0, &.{.i64}, &.{}));
}
/// Replay one checked concrete specialization when every retained reference
/// remaps to a fresh identity. A missing or ambiguous reference, an
/// unvalidated fingerprint, a changed defining region or a reference to a
/// specialization that the fresh run has not instantiated is a conservative
/// miss; an unvalidated specialization is never reused.
fn lookupSpecialization(
    comptime Checker: type,
    self: *Checker,
    reuse: *generic_specializations.Session,
    allocator: std.mem.Allocator,
    index: usize,
    nodes: *std.ArrayList(typed.Node),
    statements: *std.ArrayList(typed.Statement),
) Error!?typed.Function {
    if (index >= self.spec_fingerprints.items.len) return null;
    if (!reuse.backend.enabled) {
        reuse.noteMiss(.cache_disabled);
        return null;
    }
    const fingerprint = self.spec_fingerprints.items[index] orelse return null;
    const prepared = self.prepared orelse {
        reuse.noteMiss(.context_changed);
        return null;
    };
    const instance = self.instance_keys.items[index];
    const declaration = @backingInt(instance.declaration);
    const context = prepared.contexts[declaration];
    // Dependency opens may grow the table; retain payload slices, never its row pointer.
    const opened = (try reuse.open(fingerprint, context)) orelse return null;
    const entry = opened.*;
    if (!std.mem.eql(u8, entry.payload.identity.fingerprint, fingerprint)) {
        reuse.noteMiss(.stale_identity);
        return null;
    }
    if (!std.mem.eql(u8, entry.payload.identity.template, prepared.keys[declaration])) {
        reuse.noteMiss(.stale_identity);
        return null;
    }
    if (!std.mem.eql(u8, entry.payload.identity.context[0..], context[0..])) {
        reuse.noteMiss(.context_changed);
        return null;
    }
    const fresh_region = prepared.regions[declaration];
    const region_len = entry.payload.source.region.end - entry.payload.source.region.start;
    if (region_len != fresh_region.end - fresh_region.start) {
        reuse.noteMiss(.region_length_changed);
        return null;
    }
    if (!std.mem.eql(u8, entry.payload.source.region_bytes, self.src.bytes[fresh_region.start..fresh_region.end])) {
        reuse.noteMiss(.region_bytes_changed);
        return null;
    }
    const fresh_body = prepared.bodies[declaration];
    const body_len = entry.payload.source.body.end - entry.payload.source.body.start;
    if (body_len != fresh_body.end - fresh_body.start) {
        reuse.noteMiss(.region_length_changed);
        return null;
    }
    if (!std.mem.eql(u8, entry.payload.source.body_bytes, self.src.bytes[fresh_body.start..fresh_body.end])) {
        reuse.noteMiss(.region_bytes_changed);
        return null;
    }
    const functions = try allocator.alloc(?typed.FunctionId, entry.payload.counts.old_function_count);
    @memset(functions, null);
    for (entry.payload.refs.function_refs) |reference| {
        const id = @backingInt(reference.id);
        if (id >= functions.len) {
            reuse.noteMiss(.relocation_failed);
            return null;
        }
        switch (reference.kind) {
            .ordinary => {
                const fresh = self.ordinary_instance_by_key.get(reference.key) orelse {
                    reuse.noteMiss(.missing_ordinary);
                    return null;
                };
                if (fresh == std.math.maxInt(usize)) {
                    reuse.noteMiss(.ambiguous_ordinary);
                    return null;
                }
                functions[id] = @fromBackingInt(fresh);
            },
            .specialization => {
                const fresh = (try preregister(Checker, self, reuse, reference)) orelse {
                    reuse.noteMiss(.missing_specialization);
                    return null;
                };
                functions[id] = fresh;
            },
        }
    }
    const record_remaps = try allocator.alloc(?typed.Type, entry.payload.counts.old_record_count);
    @memset(record_remaps, null);
    reuse.backend.memory.statistics.record_name_visits += try indexRecordNames(self.allocator, &self.record_by_name, &self.indexed_record_count, self.catalog.records);
    for (entry.payload.refs.record_refs) |reference| {
        // Body checking may have already instantiated this resolved nominal
        // application. Its old ordinal says nothing about fresh availability.
        // Index the current catalog and validate the complete provider shape;
        // absent or ambiguous identities remain conservative misses.
        const fresh = self.record_by_name.get(reference.key) orelse {
            reuse.noteMiss(.missing_record);
            return null;
        };
        if (fresh == std.math.maxInt(usize)) {
            reuse.noteMiss(.ambiguous_record);
            return null;
        }
        const shape = (try recordShape(Checker, self, fresh)) orelse {
            reuse.noteMiss(.missing_record);
            return null;
        };
        if (!std.mem.eql(u8, &shape, &reference.shape)) {
            reuse.noteMiss(.record_shape_changed);
            return null;
        }
        record_remaps[reference.index] = @fromBackingInt(fresh + typed.Type.record_base);
    }
    var segment = [_]sem_copy.Segment{.{ .before = entry.payload.source.region, .after = fresh_region.start }};
    const mapper: sem_copy.Mapper = .{
        .segments = &segment,
        .before = entry.payload.body.range,
        .after = .{
            .nodes = .{ .start = nodes.items.len, .end = nodes.items.len + entry.payload.body.nodes.len },
            .statements = .{ .start = statements.items.len, .end = statements.items.len + entry.payload.body.statements.len },
        },
        .functions = functions,
        .records = record_remaps,
    };
    try nodes.ensureUnusedCapacity(allocator, entry.payload.body.nodes.len);
    try statements.ensureUnusedCapacity(allocator, entry.payload.body.statements.len);
    var failure: sem_copy.Failure = .none;
    const function = mapper.copyWithFailure(allocator, typed.Function, entry.payload.body.function, &failure) catch |err| return specializationRelocationMiss(reuse, err);
    mapper.copySliceInto(allocator, typed.Node, entry.payload.body.nodes, nodes.unusedCapacitySlice()[0..entry.payload.body.nodes.len], &failure) catch |err| return specializationRelocationMiss(reuse, err);
    mapper.copySliceInto(allocator, typed.Statement, entry.payload.body.statements, statements.unusedCapacitySlice()[0..entry.payload.body.statements.len], &failure) catch |err| return specializationRelocationMiss(reuse, err);
    nodes.items.len += entry.payload.body.nodes.len;
    statements.items.len += entry.payload.body.statements.len;
    reuse.noteReused();
    return function;
}
/// A referenced instance can be registered only from its validated retained recipe.
/// Bodies are left on the bounded checker queue; cycles reuse the registry's existing ID.
fn preregister(comptime Checker: type, self: *Checker, reuse: *generic_specializations.Session, reference: sem_entry.SpecializationFunctionRef) Error!?typed.FunctionId {
    if (self.spec_index.get(reference.key)) |id| return id;
    const template = reference.template orelse return null;
    const declaration = (try uniqueTemplate(Checker, self, template)) orelse return null;
    const prepared = self.prepared orelse return null;
    const context = prepared.contexts[declaration];
    const opened = (try reuse.open(reference.key, context)) orelse return null;
    const entry = opened.payload;
    if (!std.mem.eql(u8, entry.identity.template, template) or !std.mem.eql(u8, &entry.identity.context, &context)) return null;
    if (!std.mem.eql(u8, entry.identity.fingerprint, reference.key)) return null;
    if (!sameTemplateSource(Checker, self, declaration, entry.source)) return null;
    const old_arguments = entry.body.function.type_arguments;
    if (old_arguments.len != self.syntax.functions[declaration].signature.type_parameters.len or old_arguments.len == 0) return null;
    if (entry.identity.lengths.len != 0 and entry.identity.lengths.len != old_arguments.len) return null;
    const arguments = try self.allocator.alloc(typed.Type, old_arguments.len);
    reuse.backend.memory.statistics.record_name_visits += try indexRecordNames(self.allocator, &self.record_by_name, &self.indexed_record_count, self.catalog.records);
    for (old_arguments, arguments) |old, *fresh| fresh.* = (try recipeArgument(Checker, self, old, entry.refs.record_refs)) orelse return null;
    const fingerprint = (try specializationFingerprint(Checker, self, declaration, arguments, entry.identity.lengths)) orelse return null;
    // This covers fresh providers, constraints, declared contracts and compiler context.
    if (!std.mem.eql(u8, fingerprint, reference.key)) return null;
    return registerInstance(Checker, self, @fromBackingInt(declaration), arguments, entry.identity.lengths, fingerprint) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return error.InternalError,
        else => return null,
    };
}

/// The declaration of the one generic template with stable key `template`; null when none, several, or the one declaration is not generic.
/// The index of keys is built on the first lookup of a request: a scan of every key per lookup made restoring a program's specializations
/// grow with the program as well as with the specializations.
fn uniqueTemplate(comptime Checker: type, self: *Checker, template: []const u8) error{OutOfMemory}!?usize {
    const prepared = self.prepared orelse return null;
    if (self.template_by_key == null) {
        var map: std.StringHashMapUnmanaged(usize) = .empty;
        try map.ensureTotalCapacity(self.allocator, @intCast(prepared.keys.len));
        for (prepared.keys, 0..) |key, declaration| {
            const entry = map.getOrPutAssumeCapacity(key);
            entry.value_ptr.* = if (entry.found_existing) std.math.maxInt(usize) else declaration;
        }
        self.template_by_key = map;
    }
    const declaration = self.template_by_key.?.get(template) orelse return null;
    if (declaration == std.math.maxInt(usize) or self.syntax.functions[declaration].signature.type_parameters.len == 0) return null;
    return declaration;
}

test "G2p a template is found by its key through one index: a unique generic declaration, and nothing else" {
    var keys = [_][]const u8{ "fn\x1fm\x1f\x1fgeneric", "fn\x1fm\x1f\x1fplain", "fn\x1fm\x1f\x1ftwice", "fn\x1fm\x1f\x1ftwice" };
    const prepared: semantic_key.Prepared = .{ .bodies = &.{}, .regions = &.{}, .keys = &keys, .contexts = &.{}, .ordinary_ast = &.{} };
    const Declaration = struct { signature: struct { type_parameters: []const u8 } };
    const declarations = [_]Declaration{ .{ .signature = .{ .type_parameters = "T" } }, .{ .signature = .{ .type_parameters = "" } }, .{ .signature = .{ .type_parameters = "T" } }, .{ .signature = .{ .type_parameters = "T" } } };
    const Fake = struct {
        allocator: std.mem.Allocator,
        prepared: ?*const semantic_key.Prepared,
        template_by_key: ?std.StringHashMapUnmanaged(usize) = null,
        syntax: struct { functions: []const Declaration },
    };
    var fake: Fake = .{ .allocator = std.testing.allocator, .prepared = &prepared, .syntax = .{ .functions = &declarations } };
    defer fake.template_by_key.?.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(?usize, 0), try uniqueTemplate(Fake, &fake, keys[0]));
    // A key one non-generic declaration holds, a key two declarations hold, and a key none holds.
    try std.testing.expectEqual(@as(?usize, null), try uniqueTemplate(Fake, &fake, keys[1]));
    try std.testing.expectEqual(@as(?usize, null), try uniqueTemplate(Fake, &fake, keys[2]));
    try std.testing.expectEqual(@as(?usize, null), try uniqueTemplate(Fake, &fake, "fn\x1fm\x1f\x1fabsent"));
}

/// The request's shape memo, over the records the catalog holds now.
fn requestShapes(comptime Checker: type, self: *Checker) *semantic_key.Shapes {
    if (self.spec_shapes == null) self.spec_shapes = .{ .allocator = self.allocator, .records = self.catalog.records };
    const shapes = &self.spec_shapes.?;
    shapes.records = self.catalog.records;
    return shapes;
}

/// The transitive shape of record `index` through the request's memo. A Debug compiler holds each answer against a fresh computation, so every
/// test that restores a specialization checks that the memo is never stale.
fn recordShape(comptime Checker: type, self: *Checker, index: usize) error{OutOfMemory}!?[32]u8 {
    const digest = try requestShapes(Checker, self).digest(index);
    if (builtin.mode == .debug) {
        var fresh: semantic_key.Shapes = .{ .allocator = self.allocator, .records = self.catalog.records };
        defer fresh.deinit();
        const expected = try fresh.digest(index);
        std.debug.assert((digest == null) == (expected == null));
        if (digest) |value| std.debug.assert(std.mem.eql(u8, &value, &expected.?));
    }
    return digest;
}

fn sameTemplateSource(comptime Checker: type, self: *Checker, declaration: usize, stored: sem_entry.SymbolicSource) bool {
    const prepared = self.prepared orelse return false;
    const region = prepared.regions[declaration];
    const body = prepared.bodies[declaration];
    return std.mem.eql(u8, stored.region_bytes, self.src.bytes[region.start..region.end]) and std.mem.eql(u8, stored.body_bytes, self.src.bytes[body.start..body.end]);
}

fn recipeArgument(comptime Checker: type, self: *Checker, old: typed.Type, references: []const sem_entry.RecordRef) error{OutOfMemory}!?typed.Type {
    if (!old.isAggregate()) return old;
    for (references) |reference| {
        if (reference.index != old.recordIndex()) continue;
        const fresh = self.record_by_name.get(reference.key) orelse return null;
        if (fresh == std.math.maxInt(usize)) return null;
        const digest = (try recordShape(Checker, self, fresh)) orelse return null;
        if (!std.mem.eql(u8, &digest, &reference.shape)) return null;
        return @fromBackingInt(fresh + typed.Type.record_base);
    }
    return null;
}

fn specializationRelocationMiss(reuse: *generic_specializations.Session, err: sem_copy.Error) error{ OutOfMemory, InternalError }!?typed.Function {
    return switch (err) {
        error.InvalidRelocation => blk: {
            reuse.noteMiss(.relocation_failed);
            break :blk null;
        },
        error.OutOfMemory => error.OutOfMemory,
        error.InternalError => error.InternalError,
    };
}
/// Capture every specialization freshly checked by this request and publish
/// them after the whole graph passed. A tree that references a synthesized
/// lambda, an interned catalog record or an unresolvable identity is a
/// conservative miss, never a partial entry.
fn publishSpecializations(comptime Checker: type, self: *Checker, reuse: *generic_specializations.Session, allocator: std.mem.Allocator, program: typed.Program) Error!void {
    // Zero retention must perform the checks but publish nothing, so
    // `--no-cache` never reads or writes a specialization entry.
    if (!reuse.backend.enabled) return;
    const prepared = self.prepared orelse return;
    reuse.backend.memory.statistics.record_name_visits += try indexRecordNames(self.allocator, &self.record_by_name, &self.indexed_record_count, program.records);
    for (self.spec_fresh.items) |index| {
        if (index >= self.spec_fingerprints.items.len) continue;
        const fingerprint = self.spec_fingerprints.items[index] orelse continue;
        const instance = self.instance_keys.items[index];
        const declaration = @backingInt(instance.declaration);
        if (declaration >= prepared.keys.len) continue;
        const range = self.spec_ranges.items[index];
        if (range.nodes.end > program.nodes.len or range.statements.end > program.statements.len) continue;
        var refs = sem_copy.RefSet.init(allocator);
        defer refs.deinit();
        sem_copy.collectRefs(allocator, program.functions[index], program.nodes[range.nodes.start..range.nodes.end], program.statements[range.statements.start..range.statements.end], &refs) catch continue;
        const function_refs = allocator.alloc(sem_entry.SpecializationFunctionRef, refs.functions.count()) catch return error.OutOfMemory;
        defer allocator.free(function_refs);
        var iterator = refs.functions.keyIterator();
        var function_count: usize = 0;
        var representable = true;
        while (iterator.next()) |id| {
            const old = id.*;
            if (old < prepared.ordinary_ast.len) {
                function_refs[function_count] = .{ .kind = .ordinary, .id = @fromBackingInt(old), .key = prepared.keys[prepared.ordinary_ast[old]] };
            } else if (old < self.ordinary_count) {
                representable = false;
                break;
            } else {
                if (old >= self.spec_fingerprints.items.len) {
                    representable = false;
                    break;
                }
                const canonical = self.spec_fingerprints.items[old] orelse {
                    representable = false;
                    break;
                };
                function_refs[function_count] = .{ .kind = .specialization, .id = @fromBackingInt(old), .key = canonical, .template = prepared.keys[@backingInt(self.instance_keys.items[old].declaration)] };
            }
            function_count += 1;
        }
        if (!representable) {
            reuse.noteMiss(.lambda_reference);
            continue;
        }
        sem_entry.sortFunctionRefs(sem_entry.SpecializationFunctionRef, function_refs[0..function_count]);
        const record_refs = allocator.alloc(sem_entry.RecordRef, refs.records.count()) catch return error.OutOfMemory;
        defer allocator.free(record_refs);
        var record_iterator = refs.records.keyIterator();
        var record_count: usize = 0;
        var stable_records = true;
        var shapes: semantic_key.Shapes = .{ .allocator = allocator, .records = program.records };
        defer shapes.deinit();
        while (record_iterator.next()) |record_index| {
            if (record_index.* >= program.records.len) {
                stable_records = false;
                break;
            }
            if (self.record_by_name.get(program.records[record_index.*].name) != record_index.*) {
                stable_records = false;
                break;
            }
            const shape = (try shapes.digest(record_index.*)) orelse {
                stable_records = false;
                break;
            };
            record_refs[record_count] = .{ .index = record_index.*, .key = program.records[record_index.*].name, .shape = shape };
            record_count += 1;
        }
        if (!stable_records) {
            reuse.noteMiss(.interned_record);
            continue;
        }
        const descriptors = allocator.alloc([]const u8, instance.arguments.len) catch return error.OutOfMemory;
        defer allocator.free(descriptors);
        for (instance.arguments, 0..) |argument, argument_index| {
            descriptors[argument_index] = semantic_key.argumentDescriptor(allocator, argument, instance.length(argument_index), program.records) catch return error.OutOfMemory;
        }
        const region = prepared.regions[declaration];
        const body = prepared.bodies[declaration];
        // The retained entry owns an arena backed by the cache's allocator,
        // never this per-request compilation arena: the cache outlives the
        // request that produced the body.
        const entry = sem_entry.createSpecialization(reuse.allocator, program, index, range, .{
            .identity = .{
                .key = generic_specializations.Session.stableKey(allocator, fingerprint) catch return error.OutOfMemory,
                .fingerprint = fingerprint,
                .template = prepared.keys[declaration],
                .context = prepared.contexts[declaration],
                .arguments = descriptors,
                .lengths = instance.lengths,
            },
            .source = .{
                .old_len = self.src.bytes.len,
                .region = region,
                .body = body,
                .region_bytes = self.src.bytes[region.start..region.end],
                .body_bytes = self.src.bytes[body.start..body.end],
            },
            .function_refs = function_refs[0..function_count],
            .record_refs = record_refs[0..record_count],
            .old_function_count = self.instance_keys.items.len,
            .old_record_count = program.records.len,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InternalError => continue,
        };
        // UNTESTED-ERROR: this branch only releases the just-built entry
        // when the cache-owned append allocation fails; the cache-wide
        // FailingAllocator scenario covers allocation failure at the
        // checkWithCache boundary, not this release path.
        reuse.record(entry) catch |err| {
            var released = entry;
            released.deinit();
            return err;
        };
    }
    try reuse.publish();
}
fn inferArguments(comptime Checker: type, self: *Checker, signature: @FieldType(ast.Function, "signature"), call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span, arguments: []typed.Type, lengths: []?usize) Error!void {
    const inference = @import("generic_inference.zig");
    var context: inference.Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = span };
    if (self.expected_types.get(span)) |expected| try context.matchResult(signature.return_type, signature.failure_type, .{ .concrete = expected });
    for (signature.parameters, call.arguments) |parameter, input| {
        const resolved = self.resolved.at(@backingInt(input)) orelse continue;
        const actual = self.nodes.items[@backingInt(resolved)].ty;
        try context.matchArgument(parameter.ty, .{ .concrete = actual }, self.syntax.nodes.items[@backingInt(input)].span);
    }
    var inferred: [16]@import("symbolic_types.zig").Value = undefined;
    try context.finish(inferred[0..arguments.len]);
    for (inferred[0..arguments.len], arguments, lengths) |value, *argument, *length| {
        switch (value) {
            .concrete => |ty_value| argument.* = ty_value,
            .length => |count| {
                argument.* = .u64;
                length.* = count;
            },
            else => return error.InternalError,
        }
    }
}

test "a cached body that cannot be relocated is a counted miss, not an error" {
    const prepared: semantic_key.Prepared = .{ .bodies = &.{}, .regions = &.{}, .keys = &.{}, .contexts = &.{}, .ordinary_ast = &.{} };
    var table: generic_specializations.Table = .{};
    var reuse: generic_specializations.Session = .{ .allocator = std.testing.allocator, .prepared = &prepared, .backend = .{ .memory = &table, .persistent = null, .enabled = true, .build = "" } };
    const miss = @backingInt(generic_specializations.MissReason.relocation_failed);
    try std.testing.expectEqual(@as(?typed.Function, null), try specializationRelocationMiss(&reuse, error.InvalidRelocation));
    try std.testing.expectEqual(1, table.statistics.misses[miss]);
    try std.testing.expectError(error.OutOfMemory, specializationRelocationMiss(&reuse, error.OutOfMemory));
    try std.testing.expectEqual(1, table.statistics.misses[miss]);
}

fn ReferenceBridge(comptime Checker: type) type {
    return struct {
        checker: *Checker,
        reuse: *generic_specializations.Session,
        type_sites: type_recipe.Sites = .{},
        record_names: std.StringHashMapUnmanaged(usize) = .empty,
        indexed_records: usize = 0,
        fn resolveRecord(context: *anyopaque, name: []const u8, expected: [32]u8) error{OutOfMemory}!?typed.Type {
            const self: *@This() = @ptrCast(@alignCast(context));
            const records = self.checker.catalog.records;
            _ = try indexRecordNames(self.checker.allocator, &self.record_names, &self.indexed_records, records);
            const index = self.record_names.get(name) orelse return null;
            if (index == std.math.maxInt(usize)) return null;
            const actual = (try recordShape(Checker, self.checker, index)) orelse return null;
            if (!std.mem.eql(u8, &actual, &expected)) return null;
            return records[index].id;
        }
        /// The generic named instance a checked record type is, as its portable recipe inputs.
        fn instance(context: *anyopaque, ty: typed.Type, allocator: std.mem.Allocator) error{ OutOfMemory, InternalError }!?sem_entry.Instance {
            const self: *@This() = @ptrCast(@alignCast(context));
            const found = (try nominal_catalog.instanceOf(allocator, &self.checker.catalog, ty)) orelse return null;
            return .{ .name = found.name, .arguments = found.arguments, .lengths = found.lengths };
        }
        fn typeShape(context: *anyopaque, ty: typed.Type) error{OutOfMemory}!?[32]u8 {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (!ty.isAggregate()) return null;
            return recordShape(Checker, self.checker, ty.recordIndex());
        }
        fn resolveType(context: *anyopaque, recipe: sem_entry.TypeRecipe, before: source.Span, after: source.Span, remaps: []const sem_copy.RecordRemap) error{ OutOfMemory, InternalError }!?typed.Type {
            const self: *@This() = @ptrCast(@alignCast(context));
            const diagnostics_before = self.checker.sink.items.items.len;
            return type_recipe.resolve(Checker, self.checker, &self.type_sites, recipe, before, after, remaps) catch |err| switch (err) {
                error.SourceError => failed: {
                    self.checker.sink.items.shrinkRetainingCapacity(diagnostics_before);
                    break :failed null;
                },
                error.OutOfMemory => return error.OutOfMemory,
                error.InternalError => return error.InternalError,
            };
        }
        fn capture(context: *anyopaque, id: typed.FunctionId) error{OutOfMemory}!?sem_entry.FunctionRef {
            const self: *@This() = @ptrCast(@alignCast(context));
            const index = @backingInt(id);
            if (index >= self.checker.spec_fingerprints.items.len) return null;
            const key = self.checker.spec_fingerprints.items[index] orelse return null;
            const prepared = self.checker.prepared orelse return null;
            const declaration = @backingInt(self.checker.instance_keys.items[index].declaration);
            return .{ .id = id, .key = key, .template = prepared.keys[declaration] };
        }
        fn resolve(context: *anyopaque, reference: sem_entry.FunctionRef) error{ OutOfMemory, InternalError }!?typed.FunctionId {
            const self: *@This() = @ptrCast(@alignCast(context));
            return preregister(Checker, self.checker, self.reuse, .{ .kind = .specialization, .id = reference.id, .key = reference.key, .template = reference.template }) catch |err| switch (err) {
                error.SourceError => null,
                error.OutOfMemory => return error.OutOfMemory,
                error.InternalError => return error.InternalError,
            };
        }
    };
}
