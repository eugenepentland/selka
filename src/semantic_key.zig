//! Per-function semantic dependencies and stable declaration identities.
//!
//! C1 replaces whole-program eligibility with per-function eligibility. Each
//! ordinary declaration carries a stable identity (qualified defining module
//! plus declared spelling, never a numeric catalog ordinal or the module's input
//! position) and a dependency digest over the declarations its signature and
//! body actually reference. References are resolved lexically: a bare name binds
//! in its defining module, an `alias.member` name binds through the module's
//! direct import alias, and a domain member binds through its declaring domain.
//! Only the resolved declaration identities participate, so a same-named
//! declaration in an unrelated module cannot invalidate a body; unresolved names
//! stay recorded as negative lookups scoped to the module that would bind them.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const embed = @import("embed.zig");
const nominal = @import("nominal_type_syntax.zig");
const interfaces = @import("interfaces.zig");
const effect_set = @import("effect_set.zig");
const Hash = std.crypto.hash.sha2.Sha256;

/// Domain for per-function dependency digests. Bump when the tracked dependency
/// model changes so stale entries are never admitted.
pub const functions_domain = "semantic-functions-v8";
/// Domain for the module export-directive digest. Kept in one place so the
/// indexed and per-declaration scan oracle hash the same prefix.
const export_domain = "export-v1";
/// Domain for the canonical C3 specialization key engine.
pub const specialization_domain = "semantic-specialization-v3";

/// Per-function dependency facts for one fresh compilation.
pub const Prepared = struct {
    /// Exact body interval per AST function.
    bodies: []source.Span,
    /// Relocatable declaration region `[header start, body end]` per AST function.
    /// The whole region is byte-identical whenever a declaration is reusable.
    regions: []source.Span,
    /// Stable declaration identity per AST function (caller-owned).
    keys: [][]const u8,
    /// Dependency digest per AST function.
    contexts: [][32]u8,
    /// Ordinary instance index -> AST function index.
    ordinary_ast: []usize,
    /// Whole-program nominal-syntax observation retained so the conservative
    /// compatibility observation keeps its owning module reachable. Per-function
    /// dependencies no longer use it to disable unrelated ordinary bodies.
    nominal_syntax: bool,
    /// Per AST function: its region digest and the names its syntax references.
    recalled: Recalled = .{},
};

/// One identifier-like reference a declaration's syntax makes: a bare or
/// dotted name, or a `member` called through `owner` (`Domain.member`).
pub const Name = struct { text: []const u8, owner: ?[]const u8 = null };

/// Names an earlier request collected, found by stable key and the BLAKE3
/// digest of the declaration region they were collected from. The names are
/// a function of the region's bytes, so a matching digest lets a request
/// resolve them again without walking the unchanged syntax.
pub const Recall = struct {
    context: *const anyopaque,
    names: *const fn (context: *const anyopaque, key: []const u8, digest: [32]u8) ?[]const Name,
};

/// Per AST function: the BLAKE3 digest of its declaration region and the
/// names its signature and body reference.
pub const Recalled = struct {
    digests: [][32]u8 = &.{},
    names: [][]const Name = &.{},
};

/// The contract strings every dependency digest is taken under.
pub const Contracts = struct { build: []const u8, mutation: []const u8 };

/// Build per-function dependency facts after declaration/type collection but
/// before checking any body. `resolution` supplies the project's module and
/// import identities; a single-unit compilation passes `null` and resolves
/// against its one lexical module. Dependencies are derived from syntax so they
/// stay stable when declaration or module order changes.
pub fn prepare(
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    contracts: Contracts,
    resolution: ?*interfaces.Index,
    recall: ?Recall,
) error{ OutOfMemory, InternalError }!Prepared {
    var contract_hash = Hash.init(.{});
    frame(&contract_hash, "semantic-context-v1");
    frame(&contract_hash, contracts.build);
    frame(&contract_hash, contracts.mutation);
    var contract_sha256: [32]u8 = undefined;
    contract_hash.final(&contract_sha256);

    const nominal_syntax = nominal.present(program);
    var builder = try Builder.init(allocator, src, program, resolution);
    defer builder.deinit();

    const bodies = try allocator.alloc(source.Span, program.functions.len);
    const regions = try allocator.alloc(source.Span, program.functions.len);
    const keys = try allocator.alloc([]const u8, program.functions.len);
    const contexts = try allocator.alloc([32]u8, program.functions.len);
    const recalled: Recalled = .{
        .digests = try allocator.alloc([32]u8, program.functions.len),
        .names = try allocator.alloc([]const Name, program.functions.len),
    };
    var ordinary: std.ArrayList(usize) = .empty;
    defer ordinary.deinit(allocator);

    for (program.functions, 0..) |function, i| {
        if (@backingInt(function.body) >= program.statements.items.len) return error.InternalError;
        const body = program.statements.items[@backingInt(function.body)].span;
        if (body.start > body.end or body.end > src.bytes.len) return error.InternalError;
        bodies[i] = body;
        // The region begins at the declaration's first attribute line, so an
        // edit to a contract clause above the `def` changes its bytes.
        const start = lineStart(src.bytes, ast.declarationStart(program, function.name));
        if (start > body.start) return error.InternalError;
        regions[i] = .{ .start = start, .end = body.end };
        keys[i] = try builder.functionKey(function);
        std.crypto.hash.Blake3.hash(src.bytes[start..body.end], &recalled.digests[i], .{});
        const known = if (recall) |memory| memory.names(memory.context, keys[i], recalled.digests[i]) else null;
        contexts[i] = try builder.context(function, keys[i], contract_sha256, .{ .known = known, .names = &recalled.names[i] });
        contexts[i] = withEmbeds(contexts[i], src.embedsWithin(regions[i]));
        if (function.signature.type_parameters.len == 0) try ordinary.append(allocator, i);
    }
    return .{
        .bodies = bodies,
        .regions = regions,
        .keys = keys,
        .contexts = contexts,
        .ordinary_ast = try ordinary.toOwnedSlice(allocator),
        .nominal_syntax = nominal_syntax,
        .recalled = recalled,
    };
}

/// EMBED-1: a declaration whose region reads embedded files keys on their content
/// too, so editing only such a file never reuses its checked body, its summary
/// stand-in or its stored unit. A region that embeds nothing keeps its context.
fn withEmbeds(context: [32]u8, embeds: []const source.Embed) [32]u8 {
    if (embeds.len == 0) return context;
    var hash = Hash.init(.{});
    frame(&hash, "semantic-embeds-v1");
    hash.update(&context);
    embed.hashInto(&hash, embeds);
    var mixed: [32]u8 = undefined;
    hash.final(&mixed);
    return mixed;
}

/// The names one declaration's context resolves: `known` when an earlier
/// request recorded them for identical region bytes, otherwise collected from
/// its syntax. `names` receives the list either way.
const ContextNames = struct { known: ?[]const Name, names: *[]const Name };

/// Checked contract facts of one function that a persisted C2 entry must carry:
/// the inferred effect mask, normalized `mutates` positions, `return_origin`
/// bound and mutation facts. This is the digest a decoder compares before
/// admitting an entry under a compatible mutation contract.
pub fn contractDigest(function: typed.Function) [32]u8 {
    var hash = Hash.init(.{});
    frame(&hash, "checked-contract-v1");
    var mask: [4]u8 = undefined;
    std.mem.writeInt(u32, &mask, function.policy.effects, .little);
    hash.update(&mask);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, function.signature.mutates.len, .little);
    hash.update(&count);
    for (function.signature.mutates) |position| {
        var encoded: [2]u8 = undefined;
        std.mem.writeInt(u16, &encoded, position, .little);
        hash.update(&encoded);
    }
    switch (function.signature.return_origin) {
        .fresh => frame(&hash, "fresh"),
        .unknown => frame(&hash, "unknown"),
        .params => |positions| {
            frame(&hash, "params");
            std.mem.writeInt(u64, &count, positions.len, .little);
            hash.update(&count);
            for (positions) |position| {
                var encoded: [2]u8 = undefined;
                std.mem.writeInt(u16, &encoded, position, .little);
                hash.update(&encoded);
            }
        },
    }
    frame(&hash, if (function.signature.inferred.writes) "writes" else "no-writes");
    frame(&hash, if (function.signature.inferred.external) "external" else "internal");
    return hash.finalResult();
}

/// Declared-contract digest of one generic template signature: the declared
/// effect ceiling (or an explicit "none"), the normalized mutation footprint
/// and the published return-origin bound. It is a canonical specialization-key
/// dimension, so a declared ceiling or footprint edit invalidates every
/// concrete specialization of that template while unrelated ones stay reusable.
pub fn declaredContractDigest(effect_bound: ?effect_set.Bound, mutates: []const u16) [32]u8 {
    var hash = Hash.init(.{});
    frame(&hash, "declared-contract-v1");
    if (effect_bound) |bound| {
        frame(&hash, "ceiling");
        var mask: [4]u8 = undefined;
        std.mem.writeInt(u32, &mask, bound.allowed, .little);
        hash.update(&mask);
    } else frame(&hash, "no-ceiling");
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, mutates.len, .little);
    hash.update(&count);
    for (mutates) |position| {
        var encoded: [2]u8 = undefined;
        std.mem.writeInt(u16, &encoded, position, .little);
        hash.update(&encoded);
    }
    frame(&hash, "return-origin-unknown");
    return hash.finalResult();
}

/// Canonical specialization key dimensions. Positional argument order is
/// preserved; every field boundary is length-prefixed so two different
/// dimension sequences can never collide.
pub const SpecializationInputs = struct {
    template_identity: []const u8,
    /// Ordered positional descriptors, one per type parameter. A constant length
    /// parameter is `L:<decimal>`; a type argument is `T:<canonical type>`.
    arguments: []const []const u8,
    /// Canonical resolved provider identity over the concrete nominal shapes.
    provider: []const u8,
    /// Template dependency/constraint digest (`semantic_key.Prepared.contexts`).
    constraints: []const u8,
    /// Declared/effect/mutation/return-origin contract digest.
    contracts: []const u8,
    /// Build context: the cache-key contract fingerprint (compiler, target,
    /// runtime ABI, effects contract and flags).
    build: []const u8,
};

/// Canonical key for one concrete specialization. Two semantically identical
/// specializations share a key; a change to any keyed dimension misses. This is
/// the engine behind `specializationKey`.
pub fn specializationFingerprint(allocator: std.mem.Allocator, inputs: SpecializationInputs) error{OutOfMemory}![]const u8 {
    var hash = Hash.init(.{});
    frame(&hash, specialization_domain);
    frame(&hash, inputs.template_identity);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, inputs.arguments.len, .little);
    hash.update(&count);
    for (inputs.arguments) |argument| frame(&hash, argument);
    frame(&hash, inputs.provider);
    frame(&hash, inputs.constraints);
    frame(&hash, inputs.contracts);
    frame(&hash, inputs.build);
    return hexFingerprint(allocator, hash.finalResult());
}

/// Canonical key for one generic specialization. `prepare` still keeps generic
/// templates and their concrete instances on the fresh path until the reuse
/// engine can remap specialization references; this primitive exists so the key
/// dimensions are canonical today.
pub fn specializationKey(
    allocator: std.mem.Allocator,
    template_identity: []const u8,
    arguments: []const []const u8,
    provider: []const u8,
    target_abi: []const u8,
    compiler_identity: []const u8,
) error{OutOfMemory}![]const u8 {
    const build = std.fmt.allocPrint(allocator, "{s}\x1f{s}", .{ target_abi, compiler_identity }) catch return error.OutOfMemory;
    defer allocator.free(build);
    return specializationFingerprint(allocator, .{
        .template_identity = template_identity,
        .arguments = arguments,
        .provider = provider,
        .constraints = "",
        .contracts = "",
        .build = build,
    });
}

/// One positional descriptor for a concrete specialization argument. `length`
/// is present for a constant length parameter.
pub fn argumentDescriptor(allocator: std.mem.Allocator, ty: typed.Type, length: ?usize, records: []const typed.Record) error{OutOfMemory}![]const u8 {
    if (length) |value| return std.fmt.allocPrint(allocator, "L:{d}", .{value});
    if (!ty.isAggregate()) return std.fmt.allocPrint(allocator, "T:{s}", .{@tagName(ty)});
    // Catalog names identify declarations; the resolved transitive schema is
    // also required. Display spelling alone loses callback labels, mutation
    // positions and changes to the nominal arguments' provider contracts.
    const provider = try providerIdentity(allocator, &.{ty}, records);
    defer allocator.free(provider);
    return std.fmt.allocPrint(allocator, "T:resolved:{s}:{s}", .{ typed.typeName(ty, records), provider });
}

/// Canonical resolved provider identity over the transitive nominal records
/// reachable from the concrete arguments. Records are ordered by stable
/// qualified name with length-prefixed boundaries, matching the frozen
/// `contracts.providerIdentity` ordering discipline.
pub fn providerIdentity(allocator: std.mem.Allocator, arguments: []const typed.Type, records: []const typed.Record) error{OutOfMemory}![]const u8 {
    var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
    defer seen.deinit(allocator);
    var indices: std.ArrayList(usize) = .empty;
    defer indices.deinit(allocator);
    for (arguments) |argument| try collectProviderRecords(allocator, argument, records, &seen, &indices);
    std.mem.sort(usize, indices.items, records, lessRecordName);
    var hash = Hash.init(.{});
    frame(&hash, "provider-v1");
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, indices.items.len, .little);
    hash.update(&count);
    for (indices.items) |index| mixRecord(&hash, records[index], records);
    return hexFingerprint(allocator, hash.finalResult());
}

/// Transitive shape digests of one catalog's records, memoized per request.
/// A record's digest covers its own schema (fields and their types, cases and
/// payloads, element, backing and callback slots, managed and contract flags)
/// and the schema of every record those reach, in a canonical order. A body
/// that touched a record while it was checked depends on exactly this, however
/// the record was reached (a field's element type, a return type, a facade).
pub const Shapes = struct {
    /// Owns the memo; a request passes its arena.
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    memo: std.AutoHashMapUnmanaged(usize, [32]u8) = .empty,

    /// Release the memo; digests already returned are values.
    pub fn deinit(self: *Shapes) void {
        self.memo.deinit(self.allocator);
    }

    /// The transitive shape digest of record `index`, or null when the
    /// catalog has no such record.
    pub fn digest(self: *Shapes, index: usize) error{OutOfMemory}!?[32]u8 {
        const allocator = self.allocator;
        if (index >= self.records.len) return null;
        if (self.memo.get(index)) |known| return known;
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer seen.deinit(allocator);
        var reached: std.ArrayList(usize) = .empty;
        defer reached.deinit(allocator);
        try collectProviderRecords(allocator, self.records[index].id, self.records, &seen, &reached);
        std.mem.sort(usize, reached.items, self.records, lessRecordNameThenIndex);
        var hash = Hash.init(.{});
        frame(&hash, "shape-v1");
        frame(&hash, self.records[index].name);
        var count: [8]u8 = undefined;
        std.mem.writeInt(u64, &count, reached.items.len, .little);
        hash.update(&count);
        for (reached.items) |reached_index| mixRecord(&hash, self.records[reached_index], self.records);
        const result = hash.finalResult();
        try self.memo.put(allocator, index, result);
        return result;
    }
};

fn lessRecordNameThenIndex(records: []const typed.Record, a: usize, b: usize) bool {
    return switch (std.mem.order(u8, records[a].name, records[b].name)) {
        .lt => true,
        .gt => false,
        .eq => a < b,
    };
}

fn hexFingerprint(allocator: std.mem.Allocator, digest: [32]u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch error.OutOfMemory;
}

fn lessRecordName(records: []const typed.Record, a: usize, b: usize) bool {
    return std.mem.lessThan(u8, records[a].name, records[b].name);
}

/// Append to `out` every catalog record `ty` reaches through fields, cases,
/// elements, keys, domain backing, buffer elements and callback slots that
/// `seen` does not hold yet: the records a CHECK-SHAPES-1 digest covers.
pub fn reachableRecords(allocator: std.mem.Allocator, ty: typed.Type, records: []const typed.Record, seen: *std.AutoHashMapUnmanaged(usize, void), out: *std.ArrayList(usize)) error{OutOfMemory}!void {
    return collectProviderRecords(allocator, ty, records, seen, out);
}

fn collectProviderRecords(allocator: std.mem.Allocator, ty: typed.Type, records: []const typed.Record, seen: *std.AutoHashMapUnmanaged(usize, void), out: *std.ArrayList(usize)) error{OutOfMemory}!void {
    if (!ty.isAggregate()) return;
    const index = ty.recordIndex();
    if (index >= records.len) return;
    const entry = try seen.getOrPut(allocator, index);
    if (entry.found_existing) return;
    try out.append(allocator, index);
    const record = records[index];
    for (record.fields) |field| try collectProviderRecords(allocator, field.ty, records, seen, out);
    if (record.shape.variants) |variants| for (variants.cases) |case| if (case.payload) |payload| try collectProviderRecords(allocator, payload, records, seen, out);
    if (record.shape.array) |array| {
        try collectProviderRecords(allocator, array.element, records, seen, out);
        if (array.key) |key| try collectProviderRecords(allocator, key, records, seen, out);
    }
    if (record.shape.domain) |backing| try collectProviderRecords(allocator, backing, records, seen, out);
    if (record.shape.buffer) |element| try collectProviderRecords(allocator, element, records, seen, out);
    if (record.contract.callback) |callback| {
        for (callback.parameters) |parameter| try collectProviderRecords(allocator, parameter, records, seen, out);
        try collectProviderRecords(allocator, callback.return_type, records, seen, out);
    }
}

fn mixRecord(hash: *Hash, record: typed.Record, records: []const typed.Record) void {
    frame(hash, record.name);
    frame(hash, if (record.managed) "managed" else "value");
    frame(hash, if (record.contract.move_only) "move-only" else "copyable");
    frame(hash, if (record.contract.requires_handling) "handling" else "plain");
    frame(hash, if (record.contract.storable) "storable" else "transient");
    frame(hash, if (record.contract.public_arguments) "public" else "private");
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, record.fields.len, .little);
    hash.update(&count);
    // A boxed field or case is laid out as a pointer (RECURSIVE-VALUES-2);
    // the mark is framed only where it is set, so other keys keep their bytes.
    for (record.fields) |field| {
        frame(hash, field.name);
        frame(hash, typed.typeName(field.ty, records));
        if (field.boxed) frame(hash, "boxed");
    }
    if (record.shape.variants) |variants| {
        frame(hash, if (variants.fallible) "result" else if (variants.is_union) "union" else "enum");
        std.mem.writeInt(u64, &count, variants.cases.len, .little);
        hash.update(&count);
        for (variants.cases) |case| {
            frame(hash, case.name);
            frame(hash, if (case.payload) |payload| typed.typeName(payload, records) else "-");
            if (case.boxed) frame(hash, "boxed");
        }
    }
    if (record.shape.array) |array| {
        frame(hash, "array");
        frame(hash, typed.typeName(array.element, records));
        std.mem.writeInt(u64, &count, array.length, .little);
        hash.update(&count);
        frame(hash, if (array.key) |key| typed.typeName(key, records) else "-");
    }
    if (record.shape.domain) |backing| {
        frame(hash, "domain");
        frame(hash, typed.typeName(backing, records));
    }
    if (record.shape.buffer) |element| {
        frame(hash, "buffer");
        frame(hash, typed.typeName(element, records));
    }
    if (record.shape.resource) |kind| {
        frame(hash, "resource");
        frame(hash, @tagName(kind));
    }
    if (record.contract.callback) |callback| {
        frame(hash, "callback");
        for (callback.parameters, 0..) |_, index| frame(hash, if (index < callback.labels.len) callback.labels[index] else "");
        std.mem.writeInt(u64, &count, callback.parameters.len, .little);
        hash.update(&count);
        for (callback.parameters) |parameter| frame(hash, typed.typeName(parameter, records));
        frame(hash, typed.typeName(callback.return_type, records));
        std.mem.writeInt(u64, &count, callback.effects, .little);
        hash.update(&count);
        std.mem.writeInt(u64, &count, callback.mutates.len, .little);
        hash.update(&count);
        for (callback.mutates) |position| {
            var encoded: [2]u8 = undefined;
            std.mem.writeInt(u16, &encoded, position, .little);
            hash.update(&encoded);
        }
        switch (callback.return_origin) {
            .fresh => frame(hash, "fresh"),
            .unknown => frame(hash, "unknown"),
            .params => |positions| {
                frame(hash, "params");
                std.mem.writeInt(u64, &count, positions.len, .little);
                hash.update(&count);
                for (positions) |position| {
                    var encoded: [2]u8 = undefined;
                    std.mem.writeInt(u16, &encoded, position, .little);
                    hash.update(&encoded);
                }
            },
        }
    }
}

/// Which merged-program declaration table a declaration key indexes.
pub const DeclKind = enum(u4) { function = 0, record = 1, domain = 2, variant = 3, alias = 4, constraint = 5, resource = 6 };

fn declKey(kind: DeclKind, index: usize) u64 {
    return (@as(u64, @backingInt(kind)) << 32) | @as(u64, @as(u32, @truncate(index)));
}

/// One reference accumulator: resolved declaration keys plus negative lookups.
const Refs = std.AutoHashMapUnmanaged(u64, void);
const Negatives = std.StringHashMapUnmanaged(void);

/// Declarations of one lexical module, keyed by their in-module reference name
/// (bare for free declarations, `Domain.member` for domain members).
const ModuleDecls = struct {
    names: std.StringHashMapUnmanaged(std.ArrayList(u64)) = .empty,
    exports: ExportIndex = .{},

    fn deinit(self: *ModuleDecls, allocator: std.mem.Allocator) void {
        var iterator = self.names.iterator();
        while (iterator.next()) |entry| entry.value_ptr.deinit(allocator);
        self.names.deinit(allocator);
        self.exports.deinit(allocator);
    }
};

/// Every `export NAME` directive line of one module, grouped by the declared
/// name the previous per-declaration scan matched. Stored slices borrow the
/// module's original source bytes and preserve line order, so hashing one
/// name's lines is byte-for-byte identical to scanning the module once per
/// declaration. `scanned` records the module bytes visited while building it.
const ExportIndex = struct {
    lines: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty,
    scanned: usize = 0,

    fn deinit(self: *ExportIndex, allocator: std.mem.Allocator) void {
        var iterator = self.lines.valueIterator();
        while (iterator.next()) |declarations| declarations.deinit(allocator);
        self.lines.deinit(allocator);
    }
};

/// Lexical declaration table and memoized declaration fingerprints used to
/// compute per-function dependency digests.
const Builder = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    resolution: ?*interfaces.Index,
    modules: []ModuleDecls,
    /// Declaration key -> transitive fingerprint.
    memo: std.AutoHashMapUnmanaged(u64, [32]u8) = .empty,
    /// Declaration key -> its own digest and the declarations it references.
    own: std.AutoHashMapUnmanaged(u64, Own) = .empty,
    /// Composite type spelling (`list[T]`, `dict[K, V]`, `tuple[...]`, an array
    /// or a callback type) -> the component type spans it is written with.
    type_parts: std.AutoHashMapUnmanaged(SpanKey, []const source.Span) = .empty,

    fn init(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, resolution: ?*interfaces.Index) error{OutOfMemory}!Builder {
        const module_count: usize = if (src.origins.len == 0) 1 else src.origins.len;
        var self: Builder = .{ .allocator = allocator, .src = src, .program = program, .resolution = resolution, .modules = &.{} };
        errdefer self.deinit();
        self.modules = try allocator.alloc(ModuleDecls, module_count);
        for (self.modules) |*module| module.* = .{};

        for (program.functions, 0..) |function, i| {
            const key = try self.declarationName(function.policy.owner, function.name);
            try self.register(moduleOf(src, function.name), key, declKey(.function, i));
        }
        for (program.types.records, 0..) |record, i| try self.register(moduleOf(src, record.name), src.text(record.name), declKey(.record, i));
        for (program.types.domains, 0..) |domain, i| try self.register(moduleOf(src, domain.name), src.text(domain.name), declKey(.domain, i));
        for (program.types.resources, 0..) |resource, i| try self.register(moduleOf(src, resource.name), src.text(resource.name), declKey(.resource, i));
        for (program.types.variants, 0..) |variant, i| try self.register(moduleOf(src, variant.name), src.text(variant.name), declKey(.variant, i));
        for (program.types.expressions.aliases, 0..) |alias, i| try self.register(moduleOf(src, alias.name), src.text(alias.name), declKey(.alias, i));
        for (program.types.constraints, 0..) |constraint, i| try self.register(moduleOf(src, constraint.name), src.text(constraint.name), declKey(.constraint, i));
        // Index each module's export directives once; `exportDigest` then hashes
        // only the lines matching a declaration instead of rescanning the module.
        for (self.modules, 0..) |*module, index| {
            const bytes = if (self.src.origins.len == 0) self.src.bytes else self.src.origins[index].original.bytes;
            try buildExportIndex(self.allocator, bytes, &module.exports);
        }
        try self.registerReExports();
        try self.indexTypeParts();
        return self;
    }

    /// A name a facade module re-exports binds the declaration it names, not a
    /// negative lookup in the facade, so a body reaching a type through a facade
    /// depends on the type itself.
    fn registerReExports(self: *Builder) error{OutOfMemory}!void {
        const index = self.resolution orelse return;
        for (index.units, 0..) |unit, module| {
            if (module >= self.modules.len) break;
            for (unit.symbols.items) |symbol| {
                const target = symbol.re_export orelse continue;
                if (target.module >= self.modules.len or target.module >= index.units.len) continue;
                const target_name = index.units[target.module].symbols.items[target.symbol].name;
                const declarations = self.modules[target.module].names.get(target_name) orelse continue;
                for (declarations.items) |declaration| try self.register(module, symbol.name, declaration);
            }
        }
    }

    /// Index every composite type spelling by its exact span, so collecting a
    /// type written `list[shapes.Inner]` references `shapes.Inner` as well.
    fn indexTypeParts(self: *Builder) error{OutOfMemory}!void {
        const expressions = self.program.types.expressions;
        for (expressions.applications) |application| {
            const parts = try self.allocator.alloc(source.Span, application.arguments.len + 1);
            parts[0] = application.name;
            @memcpy(parts[1..], application.arguments);
            try self.type_parts.put(self.allocator, SpanKey.of(application.span), parts);
        }
        for (expressions.arrays) |array| {
            const parts = try self.allocator.alloc(source.Span, 2);
            parts[0] = array.element;
            parts[1] = switch (array.index) {
                .length => |span| span,
                .enum_type => |span| span,
            };
            try self.type_parts.put(self.allocator, SpanKey.of(array.span), parts);
        }
        for (expressions.tuples) |tuple| try self.type_parts.put(self.allocator, SpanKey.of(tuple.span), tuple.elements);
        for (expressions.callbacks) |callback| {
            const parts = try self.allocator.alloc(source.Span, callback.parameters.len + 1);
            @memcpy(parts[0..callback.parameters.len], callback.parameters);
            parts[callback.parameters.len] = callback.return_type;
            try self.type_parts.put(self.allocator, SpanKey.of(callback.span), parts);
        }
    }

    fn deinit(self: *Builder) void {
        for (self.modules) |*module| module.deinit(self.allocator);
        self.allocator.free(self.modules);
        self.memo.deinit(self.allocator);
        self.own.deinit(self.allocator);
        self.type_parts.deinit(self.allocator);
    }

    fn register(self: *Builder, module: usize, name: []const u8, key: u64) error{OutOfMemory}!void {
        if (name.len == 0 or module >= self.modules.len) return;
        const entry = try self.modules[module].names.getOrPut(self.allocator, name);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        for (entry.value_ptr.items) |existing| if (existing == key) return;
        try entry.value_ptr.append(self.allocator, key);
    }

    /// Stable identity of one function declaration: qualified defining module,
    /// domain owner and declared spelling. Never a catalog index.
    fn functionKey(self: *Builder, function: ast.Function) std.mem.Allocator.Error![]const u8 {
        const module = self.moduleName(moduleOf(self.src, function.name));
        const owner = if (function.policy.owner) |owner_span| self.src.text(owner_span) else "";
        return std.fmt.allocPrint(self.allocator, "fn\x1f{s}\x1f{s}\x1f{s}", .{ module, owner, self.src.text(function.name) });
    }

    fn declarationName(self: *Builder, owner: ?source.Span, name: source.Span) std.mem.Allocator.Error![]const u8 {
        if (owner) |domain| return std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.src.text(domain), self.src.text(name) });
        return self.src.text(name);
    }

    fn moduleName(self: *Builder, module: usize) []const u8 {
        if (self.resolution) |index| {
            if (module < index.project.modules.items.len) return index.project.modules.items[module].name;
        }
        return self.src.path;
    }

    fn importTarget(self: *Builder, module: usize, alias: []const u8) ?usize {
        const index = self.resolution orelse return null;
        if (module >= index.project.modules.items.len) return null;
        for (index.project.modules.items[module].imports) |imported| {
            if (imported.matches(alias)) return imported.target;
        }
        return null;
    }

    /// Find the longest direct-import qualifier, retaining any domain suffix.
    /// Dotted module imports bind their full path, not its first segment.
    fn importedReference(self: *Builder, module: usize, text: []const u8) ?Binding {
        var index = text.len;
        while (index != 0) {
            index -= 1;
            const separator = text[index];
            if (separator != '.' and separator != ':') continue;
            const end = index + 1;
            if (separator == ':') {
                if (index == 0 or text[index - 1] != ':') continue;
                index -= 1;
            }
            if (end >= text.len) continue;
            const target = self.importTarget(module, text[0..index]) orelse continue;
            return .{ .module = target, .key = text[end..] };
        }
        return null;
    }

    /// Resolve one reference text to the declarations it lexically binds. A
    /// missing binding is recorded as a module-scoped negative lookup.
    fn resolve(self: *Builder, module: usize, name: []const u8, owner: ?[]const u8, refs: *Refs, negatives: *Negatives) error{OutOfMemory}!void {
        const key = if (owner) |prefix| try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ prefix, name }) else name;
        if (self.importedReference(module, key)) |binding| return self.resolveKey(binding.module, binding.key, refs, negatives);
        return self.resolveKey(module, key, refs, negatives);
    }

    fn resolveKey(self: *Builder, module: usize, key: []const u8, refs: *Refs, negatives: *Negatives) error{OutOfMemory}!void {
        if (module >= self.modules.len) return;
        if (self.modules[module].names.get(key)) |declarations| {
            for (declarations.items) |declaration| try refs.put(self.allocator, declaration, {});
            return;
        }
        try negatives.put(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}\x1f{s}", .{ self.moduleName(module), key }), {});
    }

    /// Dependency digest for one declaration: its own contract plus the
    /// fingerprints of declarations its signature (and, for constants, body)
    /// references.
    fn context(self: *Builder, function: ast.Function, key: []const u8, contract: [32]u8, names: ContextNames) error{ OutOfMemory, InternalError }![32]u8 {
        const body = self.program.statements.items[@backingInt(function.body)].span;
        const start = lineStart(self.src.bytes, ast.declarationStart(self.program, function.name));
        if (start > body.start) return error.InternalError;
        var hash = Hash.init(.{});
        hash.update(functions_domain);
        hash.update(&contract);
        frame(&hash, key);
        frame(&hash, self.src.bytes[start..body.start]);
        var collector = Collector.init(self, moduleOf(self.src, function.name));
        defer collector.deinit();
        if (names.known) |known| {
            // Resolution is set-valued, so resolving the recorded names binds
            // exactly what walking the identical syntax would.
            for (known) |name| try self.resolve(collector.module, name.text, name.owner, &collector.refs, &collector.negatives);
            names.names.* = known;
        } else {
            collector.recording = true;
            try collector.collectValue(ast.Function, function);
            // A contract clause may call a helper: its conditions are part of
            // what the checked body depends on.
            try collector.collectValue([]const ast.Attribute, ast.attributesOf(self.program, function.name));
            names.names.* = try self.allocator.dupe(Name, collector.names.items);
        }
        try self.mixRefs(&hash, &collector);
        return hash.finalResult();
    }

    /// Transitive fingerprint of one declaration: its own digest and the own
    /// digests of every declaration it reaches through its references, in a
    /// canonical order. It is independent of the order declarations are asked
    /// for, so a cycle (recursive or mutually recursive types) folds every
    /// member's content into every member's fingerprint.
    fn declFingerprint(self: *Builder, key: u64) error{OutOfMemory}!([32]u8) {
        if (self.memo.get(key)) |fingerprint| return fingerprint;
        var reached: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer reached.deinit(self.allocator);
        var pending: std.ArrayList(u64) = .empty;
        defer pending.deinit(self.allocator);
        var digests: std.ArrayList([32]u8) = .empty;
        defer digests.deinit(self.allocator);
        try reached.put(self.allocator, key, {});
        try pending.append(self.allocator, key);
        while (pending.pop()) |current| {
            const own = try self.ownDigest(current);
            if (current != key) try digests.append(self.allocator, own.digest);
            for (own.edges) |next| {
                const entry = try reached.getOrPut(self.allocator, next);
                if (entry.found_existing) continue;
                try pending.append(self.allocator, next);
            }
        }
        std.mem.sort([32]u8, digests.items, {}, lessFingerprint);
        var hash = Hash.init(.{});
        frame(&hash, "decl-v5");
        hash.update(&(try self.ownDigest(key)).digest);
        for (digests.items) |digest| {
            frame(&hash, "reaches");
            hash.update(&digest);
        }
        const fingerprint = hash.finalResult();
        try self.memo.put(self.allocator, key, fingerprint);
        return fingerprint;
    }

    /// One declaration's own content: kind, defining module, source bytes,
    /// visibility and negative lookups, plus the declarations it references.
    fn ownDigest(self: *Builder, key: u64) error{OutOfMemory}!Own {
        if (self.own.get(key)) |cached| return cached;
        const kind: DeclKind = @fromBackingInt(@intCast(@as(u4, @truncate(key >> 32))));
        const index: usize = @intCast(@as(u32, @truncate(key)));
        var hash = Hash.init(.{});
        frame(&hash, "own-v1");
        frame(&hash, @tagName(kind));
        // The defining module is part of a declaration's identity: an import
        // alias retargeted to another module's byte-identical declaration binds
        // a different declaration, with its own inferred facts and types.
        frame(&hash, self.moduleName(self.declarationModule(kind, index)));
        var collector = Collector.init(self, self.declarationModule(kind, index));
        defer collector.deinit();
        switch (kind) {
            .function => {
                const function = self.program.functions[index];
                const body = self.program.statements.items[@backingInt(function.body)].span;
                const start = lineStart(self.src.bytes, ast.declarationStart(self.program, function.name));
                const end = if (function.policy.constant) body.end else body.start;
                if (start > end or end > self.src.bytes.len) return error.OutOfMemory;
                frame(&hash, self.src.bytes[start..end]);
                self.mixExport(&hash, function.name);
                // `@deprecated` sits on the line above the declaration, outside
                // the header bytes, yet every cross-module caller warns about it.
                for (ast.attributesOf(self.program, function.name)) |attribute| {
                    if (attribute.kind != .deprecated) continue;
                    frame(&hash, "deprecated");
                    frame(&hash, if (attribute.argument) |reason| self.src.text(reason) else "");
                }
                if (function.policy.constant) {
                    try collector.collectValue(ast.Function, function);
                } else {
                    try collector.collectValue(ast.FunctionSignature, function.signature);
                    try collector.collectValue(ast.FunctionPolicy, function.policy);
                    try collector.addSpan(function.name);
                    try collector.collectValue([]const ast.Attribute, ast.attributesOf(self.program, function.name));
                }
            },
            .record => {
                self.mixExport(&hash, self.program.types.records[index].name);
                try collector.collectValue(ast.Record, self.program.types.records[index]);
                try collector.collectValue([]const ast.Attribute, ast.attributesOf(self.program, self.program.types.records[index].name));
                self.mixDeclarationBytes(&hash, self.program.types.records[index].name, collector.extent);
            },
            .domain => {
                self.mixExport(&hash, self.program.types.domains[index].name);
                try collector.collectValue(ast.Domain, self.program.types.domains[index]);
                try collector.collectValue([]const ast.Attribute, ast.attributesOf(self.program, self.program.types.domains[index].name));
                self.mixDeclarationBytes(&hash, self.program.types.domains[index].name, collector.extent);
            },
            .resource => {
                self.mixExport(&hash, self.program.types.resources[index].name);
                try collector.collectValue(ast.Domain, self.program.types.resources[index]);
                self.mixDeclarationBytes(&hash, self.program.types.resources[index].name, collector.extent);
            },
            .variant => {
                self.mixExport(&hash, self.program.types.variants[index].name);
                try collector.collectValue(ast.Variants, self.program.types.variants[index]);
                self.mixDeclarationBytes(&hash, self.program.types.variants[index].name, collector.extent);
            },
            .alias => {
                self.mixExport(&hash, self.program.types.expressions.aliases[index].name);
                try collector.collectValue(ast.TypeAlias, self.program.types.expressions.aliases[index]);
                self.mixDeclarationBytes(&hash, self.program.types.expressions.aliases[index].name, collector.extent);
            },
            .constraint => {
                self.mixExport(&hash, self.program.types.constraints[index].name);
                try collector.collectValue(ast.Constraint, self.program.types.constraints[index]);
                self.mixDeclarationBytes(&hash, self.program.types.constraints[index].name, collector.extent);
            },
        }
        try self.mixNegatives(&hash, &collector);
        var edges: std.ArrayList(u64) = .empty;
        var references = collector.refs.keyIterator();
        while (references.next()) |reference| {
            if (reference.* != key) try edges.append(self.allocator, reference.*);
        }
        const own: Own = .{ .digest = hash.finalResult(), .edges = try edges.toOwnedSlice(self.allocator) };
        try self.own.put(self.allocator, key, own);
        return own;
    }

    /// Frame a type declaration's source text, from the start of the line that
    /// names it to the end of the last span it is written with: a default
    /// value, a `record`/`class` spelling or a field order change is part of
    /// what every user of the type depends on.
    fn mixDeclarationBytes(self: *Builder, hash: *Hash, name: source.Span, extent: usize) void {
        // An `@invariant` above the declaration is part of every user's
        // dependency, so the framed text starts at its first attribute line.
        const start = lineStart(self.src.bytes, ast.declarationStart(self.program, name));
        const end = @min(@max(extent, name.end), self.src.bytes.len);
        frame(hash, self.src.bytes[start..end]);
    }

    fn declarationModule(self: *Builder, kind: DeclKind, index: usize) usize {
        return switch (kind) {
            .function => moduleOf(self.src, self.program.functions[index].name),
            .record => moduleOf(self.src, self.program.types.records[index].name),
            .domain => moduleOf(self.src, self.program.types.domains[index].name),
            .resource => moduleOf(self.src, self.program.types.resources[index].name),
            .variant => moduleOf(self.src, self.program.types.variants[index].name),
            .alias => moduleOf(self.src, self.program.types.expressions.aliases[index].name),
            .constraint => moduleOf(self.src, self.program.types.constraints[index].name),
        };
    }

    /// Mix the declaration's visibility directive so a newly private or newly
    /// exported declaration invalidates its callers' dependencies.
    fn mixExport(self: *Builder, hash: *Hash, span: source.Span) void {
        const digest = self.exportDigest(span);
        frame(hash, "export");
        hash.update(&digest);
        // A `public` modifier publishes the declaration without an export
        // directive line, so frame the visibility itself as well.
        frame(hash, if (ast.isPublicDeclaration(self.program, span)) "public" else "private");
    }

    fn exportDigest(self: *Builder, span: source.Span) [32]u8 {
        const module = moduleOf(self.src, span);
        const name = self.src.text(span);
        var hash = Hash.init(.{});
        frame(&hash, export_domain);
        if (module < self.modules.len) {
            if (self.modules[module].exports.lines.get(name)) |lines| {
                for (lines.items) |line| frame(&hash, line);
            }
        }
        return hash.finalResult();
    }

    /// Hash the resolved declaration fingerprints and module-scoped negative
    /// lookups recorded for one function's context, in deterministic order.
    fn mixRefs(self: *Builder, hash: *Hash, collector: *const Collector) error{OutOfMemory}!void {
        // Dependencies are ordered by their content fingerprints, never by a
        // fresh catalog ordinal, so reordering modules or declarations cannot
        // perturb an otherwise identical dependency digest.
        const fingerprints = try self.allocator.alloc([32]u8, collector.refs.count());
        defer self.allocator.free(fingerprints);
        var iterator = collector.refs.keyIterator();
        var count: usize = 0;
        while (iterator.next()) |key| : (count += 1) fingerprints[count] = try self.declFingerprint(key.*);
        std.mem.sort([32]u8, fingerprints[0..count], {}, lessFingerprint);
        for (fingerprints[0..count]) |fingerprint| {
            frame(hash, "reference");
            hash.update(&fingerprint);
        }
        try self.mixNegatives(hash, collector);
    }

    /// Hash one collection's module-scoped negative lookups in sorted order.
    fn mixNegatives(self: *Builder, hash: *Hash, collector: *const Collector) error{OutOfMemory}!void {
        const names = try self.allocator.alloc([]const u8, collector.negatives.count());
        defer self.allocator.free(names);
        var negative_iterator = collector.negatives.keyIterator();
        var count: usize = 0;
        while (negative_iterator.next()) |name| : (count += 1) names[count] = name.*;
        std.mem.sort([]const u8, names, {}, lessString);
        for (names) |name| {
            frame(hash, "negative");
            frame(hash, name);
        }
    }
};

/// One declaration's own digest and the declarations it references directly.
pub const Own = struct { digest: [32]u8, edges: []const u64 };

/// A declaration key's table and its index in that table of the merged program.
pub const Declaration = struct { kind: DeclKind, index: usize };

/// MODULE-INTERFACE-1: the declaration graph of one merged program, for
/// building module interfaces. Keys are the opaque declaration keys dependency
/// contexts are folded from; `own` is a declaration's own digest with the
/// declarations its declaration references (a function's signature, a type's
/// fields, a constant's value), `bodyReferences` everything one whole function
/// references, and `fingerprint` the transitive fingerprint callers' contexts
/// fold, so an interface built from them agrees with the check's own keys.
pub const Surface = struct {
    builder: Builder,

    /// Index the merged program's declarations; `resolution` names its modules
    /// and import aliases. Everything it allocates is released by `deinit`.
    pub fn init(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, resolution: *interfaces.Index) error{OutOfMemory}!Surface {
        return .{ .builder = try Builder.init(allocator, src, program, resolution) };
    }

    /// Release the declaration tables and every memo.
    pub fn deinit(self: *Surface) void {
        self.builder.deinit();
    }

    /// The declarations module `module` binds under `name`: a bare name or a
    /// `Domain.member` spelling, with a facade's re-exported names included.
    pub fn named(self: *const Surface, module: usize, name: []const u8) []const u64 {
        if (module >= self.builder.modules.len) return &.{};
        const list = self.builder.modules[module].names.get(name) orelse return &.{};
        return list.items;
    }

    /// The key of the merged program's function `index`.
    pub fn functionKey(index: usize) u64 {
        return declKey(.function, index);
    }

    /// The key of the merged program's type declaration `index` of `kind`.
    pub fn typeKey(kind: DeclKind, index: usize) u64 {
        return declKey(kind, index);
    }

    /// The table and index a key names.
    pub fn declaration(key: u64) Declaration {
        return .{ .kind = @fromBackingInt(@intCast(@as(u4, @truncate(key >> 32)))), .index = @intCast(@as(u32, @truncate(key))) };
    }

    /// The module (merged input) that declares `key`.
    pub fn moduleOfKey(self: *Surface, key: u64) usize {
        const decl = declaration(key);
        return self.builder.declarationModule(decl.kind, decl.index);
    }

    /// A declaration's own digest and the declarations its declaration names.
    pub fn own(self: *Surface, key: u64) error{OutOfMemory}!Own {
        return self.builder.ownDigest(key);
    }

    /// Every declaration one whole function names, its body included, without
    /// the function itself, sorted; allocated with `arena`, which keeps a
    /// partial list after a failure.
    pub fn bodyReferences(self: *Surface, arena: std.mem.Allocator, function: usize) error{OutOfMemory}![]u64 {
        const allocator = arena;
        const key = declKey(.function, function);
        var collector = Collector.init(&self.builder, self.builder.declarationModule(.function, function));
        defer collector.deinit();
        try collector.collectValue(ast.Function, self.builder.program.functions[function]);
        var out: std.ArrayList(u64) = .empty;
        var references = collector.refs.keyIterator();
        while (references.next()) |reference| if (reference.* != key) try out.append(allocator, reference.*);
        std.mem.sort(u64, out.items, {}, std.sort.asc(u64));
        return out.toOwnedSlice(allocator);
    }

    /// The transitive declaration fingerprint dependency contexts fold.
    pub fn fingerprint(self: *Surface, key: u64) error{OutOfMemory}![32]u8 {
        return self.builder.declFingerprint(key);
    }
};

/// Hashable exact source span.
const SpanKey = struct {
    start: usize,
    end: usize,
    fn of(span: source.Span) SpanKey {
        return .{ .start = span.start, .end = span.end };
    }
};

/// Collect every identifier-like span in a syntax subtree, following expression
/// and statement identities without revisiting shared nodes. Lexical call sites
/// keep their owner so a domain or import-alias reference resolves as one binding.
const Collector = struct {
    builder: *Builder,
    module: usize,
    refs: Refs = .empty,
    negatives: Negatives = .empty,
    visited_nodes: std.AutoHashMapUnmanaged(usize, void) = .empty,
    visited_statements: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// End of the furthest span collected, for a declaration's source extent.
    extent: usize = 0,
    /// When set, every distinct name resolved is also kept in `names`.
    recording: bool = false,
    names: std.ArrayList(Name) = .empty,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    fn init(builder: *Builder, module: usize) Collector {
        return .{ .builder = builder, .module = module };
    }

    fn deinit(self: *Collector) void {
        self.refs.deinit(self.builder.allocator);
        self.negatives.deinit(self.builder.allocator);
        self.visited_nodes.deinit(self.builder.allocator);
        self.visited_statements.deinit(self.builder.allocator);
        self.names.deinit(self.builder.allocator);
        self.seen.deinit(self.builder.allocator);
    }

    /// Resolve one name, keeping it once when recording.
    fn add(self: *Collector, text: []const u8, owner: ?[]const u8) error{OutOfMemory}!void {
        if (self.recording) {
            // A member name joins its owner in the dedupe key; `.` never
            // starts an identifier, so the joined key cannot collide with a bare one.
            const seen_key = if (owner) |spelled| try std.fmt.allocPrint(self.builder.allocator, ".{s}\x1f{s}", .{ spelled, text }) else text;
            const entry = try self.seen.getOrPut(self.builder.allocator, seen_key);
            if (entry.found_existing) return;
            try self.names.append(self.builder.allocator, .{ .text = text, .owner = owner });
        }
        try self.builder.resolve(self.module, text, owner, &self.refs, &self.negatives);
    }

    fn addSpan(self: *Collector, span: source.Span) error{OutOfMemory}!void {
        if (span.end <= span.start or span.end > self.builder.src.bytes.len) return;
        self.extent = @max(self.extent, span.end);
        const text = self.builder.src.bytes[span.start..span.end];
        if (identifierLike(text)) return self.add(text, null);
        // A composite type spelling names its component types.
        const parts = self.builder.type_parts.get(SpanKey.of(span)) orelse return;
        for (parts) |part| {
            // Components lie strictly inside their spelling, so expansion ends.
            const inside = part.start >= span.start and part.end <= span.end;
            if (inside and part.end - part.start < span.end - span.start) try self.addSpan(part);
        }
    }

    fn addMember(self: *Collector, owner: source.Span, name: source.Span) error{OutOfMemory}!void {
        if (owner.end <= owner.start or owner.end > self.builder.src.bytes.len) return;
        if (name.end <= name.start or name.end > self.builder.src.bytes.len) return;
        self.extent = @max(self.extent, @max(owner.end, name.end));
        const owner_text = self.builder.src.bytes[owner.start..owner.end];
        const name_text = self.builder.src.bytes[name.start..name.end];
        if (owner_text.len == 0 or name_text.len == 0) return;
        try self.add(name_text, owner_text);
    }

    fn collectValue(self: *Collector, comptime T: type, value: T) error{OutOfMemory}!void {
        if (T == source.Span) return self.addSpan(value);
        if (T == ast.NodeId) {
            const id = @backingInt(value);
            if (id >= self.builder.program.nodes.items.len) return;
            const entry = try self.visited_nodes.getOrPut(self.builder.allocator, id);
            if (entry.found_existing) return;
            return self.collectValue(ast.Node, self.builder.program.nodes.items[id]);
        }
        if (T == ast.StatementId) {
            const id = @backingInt(value);
            if (id >= self.builder.program.statements.items.len) return;
            const entry = try self.visited_statements.getOrPut(self.builder.allocator, id);
            if (entry.found_existing) return;
            return self.collectValue(ast.Statement, self.builder.program.statements.items[id]);
        }
        if (T == ast.Node) {
            switch (value.data) {
                .call => |call| {
                    // Keep owner and member together: `alias.fn()` and
                    // `Domain.method()` bind one declaration, not two names.
                    if (call.owner) |owner| try self.addMember(owner, call.name) else try self.addSpan(call.name);
                    for (call.type_arguments) |argument| try self.addSpan(argument);
                    for (call.arguments) |argument| try self.collectValue(ast.NodeId, argument);
                    return;
                },
                else => {},
            }
        }
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |field_name, Field| {
                try self.collectValue(Field, @field(value, field_name));
            },
            .@"union" => inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |field_name, Field| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(T), field_name)) try self.collectValue(Field, @field(value, field_name));
            },
            .optional => |optional| if (value) |present| try self.collectValue(optional.child, present),
            .pointer => |pointer| {
                if (pointer.size != .slice or pointer.child == u8) return;
                for (value) |item| try self.collectValue(pointer.child, item);
            },
            .array => |array| for (value) |item| try self.collectValue(array.child, item),
            else => {},
        }
    }
};

fn identifierLike(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!isIdentifierStart(text[0])) return false;
    for (text[1..]) |byte| if (!isIdentifierContinue(byte)) return false;
    return true;
}
fn isIdentifierStart(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_';
}
fn isIdentifierContinue(byte: u8) bool {
    return isIdentifierStart(byte) or std.ascii.isDigit(byte) or byte == '.' or byte == ':';
}
const Binding = struct { module: usize, key: []const u8 };
fn lessString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}
fn lessFingerprint(_: void, a: [32]u8, b: [32]u8) bool {
    return std.mem.order(u8, &a, &b) == .lt;
}
fn moduleOf(src: source.Source, span: source.Span) usize {
    if (src.origins.len == 0) return 0;
    const original = src.originalSpan(span) catch return 0;
    return original.input;
}
fn lineStart(bytes: []const u8, offset: usize) usize {
    var index = @min(offset, bytes.len);
    while (index != 0 and bytes[index - 1] != '\n') index -= 1;
    return index;
}
fn frame(hash: *Hash, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// Index every `export NAME` directive in one module in a single pass.
/// `trimmed` keeps the exact text (and trailing whitespace) the old scan hashed,
/// and `declared` is extracted with the same separator set, so a digest over the
/// grouped lines cannot differ from the per-declaration scan it replaces.
fn buildExportIndex(allocator: std.mem.Allocator, bytes: []const u8, index: *ExportIndex) error{OutOfMemory}!void {
    index.scanned += bytes.len;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "export ")) continue;
        const rest = std.mem.trim(u8, trimmed["export ".len..], " \t\r");
        const end = std.mem.indexOfAny(u8, rest, "; \t\r") orelse rest.len;
        const declared = rest[0..end];
        if (declared.len == 0) continue;
        const entry = try index.lines.getOrPut(allocator, declared);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try entry.value_ptr.append(allocator, trimmed);
    }
}

/// Test-only oracle: the pre-index per-declaration module scan, kept so the
/// indexed digest can be compared against the exact previous hash inputs.
fn legacyExportDigest(bytes: []const u8, name: []const u8) [32]u8 {
    var hash = Hash.init(.{});
    frame(&hash, export_domain);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "export ")) continue;
        const rest = std.mem.trim(u8, trimmed["export ".len..], " \t\r");
        const end = std.mem.indexOfAny(u8, rest, "; \t\r") orelse rest.len;
        const declared = rest[0..end];
        if (declared.len == 0) continue;
        if (std.mem.eql(u8, declared, name)) frame(&hash, trimmed);
    }
    return hash.finalResult();
}

fn indexedExportDigest(index: *const ExportIndex, name: []const u8) [32]u8 {
    var hash = Hash.init(.{});
    frame(&hash, export_domain);
    if (index.lines.get(name)) |lines| for (lines.items) |line| frame(&hash, line);
    return hash.finalResult();
}

fn expectExportDigestParity(bytes: []const u8, index: *const ExportIndex, names: []const []const u8) !void {
    for (names) |name| {
        const expected = legacyExportDigest(bytes, name);
        const actual = indexedExportDigest(index, name);
        try std.testing.expectEqualSlices(u8, &expected, &actual);
    }
}

// spec-case: SEMANTIC-CACHE-7
test "a module export index reproduces the per-declaration scan byte for byte" {
    const bytes =
        "" ++
        "export alpha\nexport  spaced \t\n" ++
        "  export tabbed;\n" ++
        "export\tnot-a-directive\n" ++
        "export \n" ++
        "export alpha\nexport alpha;\n" ++
        "export beta\nexport alpha.member\n" ++
        "export gamma\r\nexport missing ;\n";
    var index: ExportIndex = .{};
    defer index.deinit(std.testing.allocator);
    try buildExportIndex(std.testing.allocator, bytes, &index);
    const names = [_][]const u8{ "alpha", "spaced", "tabbed", "not-a-directive", "beta", "alpha.member", "gamma", "missing", "absent", "" };
    try expectExportDigestParity(bytes, &index, &names);
    try std.testing.expectEqual(@as(usize, bytes.len), index.scanned);
}

test "export indexing visits each module byte once regardless of declaration count" {
    const allocator = std.testing.allocator;
    const declarations = 512;
    const bytes = try exportScaleFixture(allocator, declarations);
    defer allocator.free(bytes);
    var index: ExportIndex = .{};
    defer index.deinit(allocator);
    try buildExportIndex(allocator, bytes, &index);
    try std.testing.expectEqual(@as(usize, bytes.len), index.scanned);
    // The replaced scan revisited every module byte once per declaration, so the
    // indexed build is cheaper by the declaration count: `declarations * bytes`
    // versus `bytes`.
    try std.testing.expect(index.scanned < declarations * bytes.len);
}

test "export indexing scans many small and fewer large modules once each" {
    const allocator = std.testing.allocator;
    const small = try exportScaleFixture(allocator, 4);
    defer allocator.free(small);
    const large = try exportScaleFixture(allocator, 256);
    defer allocator.free(large);
    var small_index: ExportIndex = .{};
    defer small_index.deinit(allocator);
    var large_index: ExportIndex = .{};
    defer large_index.deinit(allocator);
    try buildExportIndex(allocator, small, &small_index);
    try buildExportIndex(allocator, large, &large_index);
    try std.testing.expectEqual(@as(usize, small.len + large.len), small_index.scanned + large_index.scanned);
    const names = [_][]const u8{ "name0", "name3", "name255", "absent" };
    try expectExportDigestParity(small, &small_index, &names);
    try expectExportDigestParity(large, &large_index, &names);
}

/// A module with one uniquely named `export` line per declaration.
fn exportScaleFixture(allocator: std.mem.Allocator, declarations: usize) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    try text.appendSlice(allocator, "");
    var declaration: usize = 0;
    while (declaration < declarations) : (declaration += 1) {
        var buffer: [64]u8 = undefined;
        try text.appendSlice(allocator, try std.fmt.bufPrint(&buffer, "export name{d}\n", .{declaration}));
    }
    return text.toOwnedSlice(allocator);
}
