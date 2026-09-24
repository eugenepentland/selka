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
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const instances = @import("generic_instances.zig");
const impl = @This();
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
    };
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
    const instance = self.generic_registry.intern(self.allocator, .{ .declaration = declaration, .arguments = arguments, .lengths = lengths }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return self.sink.fail("E_GENERIC_LIMIT", span, "generic specialization exceeds instance or type argument budget"),
    };
    const index = self.ordinary_count + @backingInt(instance);
    if (index == self.instance_keys.items.len) {
        const owned_key = self.generic_registry.get(instance) catch return error.InternalError;
        try self.instance_keys.append(self.allocator, owned_key);
        try self.spec_ranges.append(self.allocator, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
        const fingerprint = try specializationFingerprint(Checker, self, @backingInt(declaration), arguments, lengths);
        try self.spec_fingerprints.append(self.allocator, fingerprint);
        if (fingerprint) |canonical| {
            const entry = try self.spec_index.getOrPut(self.allocator, canonical);
            entry.value_ptr.* = @fromBackingInt(index);
        }
    }
    return @fromBackingInt(index);
}
/// Canonical `specialization-v1` fingerprint of one fresh instance. Null
/// when no semantic cache (and therefore no prepared declaration facts) is
/// attached. The template identity, ordered positional descriptors, resolved
/// provider contracts, template constraint dependency, declared
/// effect/mutation/return-origin contract and build context all participate;
/// every boundary is length-prefixed by the key engine.
fn specializationFingerprint(comptime Checker: type, self: *Checker, declaration: usize, arguments: []const typed.Type, lengths: []const ?usize) Error!?[]const u8 {
    const prepared = self.prepared orelse return null;
    const function = self.syntax.functions[declaration];
    const descriptors = try self.allocator.alloc([]const u8, arguments.len);
    for (arguments, 0..) |argument, i| descriptors[i] = try semantic_key.argumentDescriptor(self.allocator, argument, if (i < lengths.len) lengths[i] else null, self.catalog.records);
    const provider = try semantic_key.providerIdentity(self.allocator, arguments, self.catalog.records);
    const contract = semantic_key.declaredContractDigest(function.policy.effect_bound, function.signature.mut_positions);
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
    const fingerprint = self.spec_fingerprints.items[index] orelse return null;
    const prepared = self.prepared orelse {
        reuse.noteMiss(.context_changed);
        return null;
    };
    const instance = self.instance_keys.items[index];
    const declaration = @backingInt(instance.declaration);
    const context = prepared.contexts[declaration];
    const entry = (try reuse.open(fingerprint, context)) orelse return null;
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
                const fresh = self.spec_index.get(reference.key) orelse {
                    reuse.noteMiss(.missing_specialization);
                    return null;
                };
                functions[id] = fresh;
            },
        }
    }
    const record_remaps = try allocator.alloc(?typed.Type, entry.payload.counts.old_record_count);
    @memset(record_remaps, null);
    for (entry.payload.refs.record_refs) |reference| {
        if (reference.index >= self.initial_record_count) {
            reuse.noteMiss(.interned_record);
            return null;
        }
        const fresh = self.record_by_name.get(reference.key) orelse {
            reuse.noteMiss(.missing_record);
            return null;
        };
        if (fresh == std.math.maxInt(usize)) {
            reuse.noteMiss(.ambiguous_record);
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
    const function = mapper.copy(allocator, typed.Function, entry.payload.body.function) catch |err| return specializationRelocationMiss(reuse, err);
    const copied_nodes = mapper.copy(allocator, []const typed.Node, entry.payload.body.nodes) catch |err| return specializationRelocationMiss(reuse, err);
    const copied_statements = mapper.copy(allocator, []const typed.Statement, entry.payload.body.statements) catch |err| return specializationRelocationMiss(reuse, err);
    try nodes.appendSlice(allocator, copied_nodes);
    try statements.appendSlice(allocator, copied_statements);
    reuse.noteReused();
    return function;
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
                function_refs[function_count] = .{ .kind = .specialization, .id = @fromBackingInt(old), .key = canonical };
            }
            function_count += 1;
        }
        if (!representable) {
            reuse.noteMiss(.lambda_reference);
            continue;
        }
        const record_refs = allocator.alloc(sem_entry.RecordRef, refs.records.count()) catch return error.OutOfMemory;
        defer allocator.free(record_refs);
        var record_iterator = refs.records.keyIterator();
        var record_count: usize = 0;
        var stable_records = true;
        while (record_iterator.next()) |record_index| {
            if (record_index.* >= self.initial_record_count or record_index.* >= program.records.len) {
                stable_records = false;
                break;
            }
            record_refs[record_count] = .{ .index = record_index.*, .key = program.records[record_index.*].name };
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
    if (self.expected_types.get(span)) |expected| try context.match(signature.return_type, .{ .concrete = expected });
    for (signature.parameters, call.arguments) |parameter, input| {
        const resolved = self.resolved[@backingInt(input)] orelse continue;
        const actual = self.nodes.items[@backingInt(resolved)].ty;
        try context.match(parameter.ty, .{ .concrete = actual });
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
    const prepared: semantic_key.Prepared = .{ .bodies = &.{}, .regions = &.{}, .keys = &.{}, .contexts = &.{}, .ordinary_ast = &.{}, .nominal_syntax = false };
    var table: generic_specializations.Table = .{};
    var reuse: generic_specializations.Session = .{ .allocator = std.testing.allocator, .prepared = &prepared, .backend = .{ .memory = &table, .persistent = null, .enabled = true, .build = "" } };
    const miss = @backingInt(generic_specializations.MissReason.relocation_failed);
    try std.testing.expectEqual(@as(?typed.Function, null), try specializationRelocationMiss(&reuse, error.InvalidRelocation));
    try std.testing.expectEqual(1, table.statistics.misses[miss]);
    try std.testing.expectError(error.OutOfMemory, specializationRelocationMiss(&reuse, error.OutOfMemory));
    try std.testing.expectEqual(1, table.statistics.misses[miss]);
}
