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
const nominal = @import("nominal_type_syntax.zig");
const interfaces = @import("interfaces.zig");
const Hash = std.crypto.hash.sha2.Sha256;

/// Domain for per-function dependency digests. Bump when the tracked dependency
/// model changes so stale entries are never admitted.
pub const functions_domain = "semantic-functions-v5";
/// Domain for the canonical C3 specialization key engine.
pub const specialization_domain = "semantic-specialization-v2";

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
};

/// Build per-function dependency facts after declaration/type collection but
/// before checking any body. `resolution` supplies the project's module and
/// import identities; a single-unit compilation passes `null` and resolves
/// against its one lexical module. Dependencies are derived from syntax so they
/// stay stable when declaration or module order changes.
pub fn prepare(
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    contract: []const u8,
    mutation_contract: []const u8,
    resolution: ?*interfaces.Index,
) error{ OutOfMemory, InternalError }!Prepared {
    var contract_hash = Hash.init(.{});
    frame(&contract_hash, "semantic-context-v1");
    frame(&contract_hash, contract);
    frame(&contract_hash, mutation_contract);
    var contract_sha256: [32]u8 = undefined;
    contract_hash.final(&contract_sha256);

    const nominal_syntax = nominal.present(program);
    var builder = try Builder.init(allocator, src, program, resolution);
    defer builder.deinit();

    const bodies = try allocator.alloc(source.Span, program.functions.len);
    const regions = try allocator.alloc(source.Span, program.functions.len);
    const keys = try allocator.alloc([]const u8, program.functions.len);
    const contexts = try allocator.alloc([32]u8, program.functions.len);
    var ordinary: std.ArrayList(usize) = .empty;
    defer ordinary.deinit(allocator);

    for (program.functions, 0..) |function, i| {
        if (@backingInt(function.body) >= program.statements.items.len) return error.InternalError;
        const body = program.statements.items[@backingInt(function.body)].span;
        if (body.start > body.end or body.end > src.bytes.len) return error.InternalError;
        bodies[i] = body;
        const start = lineStart(src.bytes, function.name.start);
        if (start > body.start) return error.InternalError;
        regions[i] = .{ .start = start, .end = body.end };
        keys[i] = try builder.functionKey(function);
        contexts[i] = try builder.context(function, keys[i], contract_sha256);
        if (function.signature.type_parameters.len == 0) try ordinary.append(allocator, i);
    }
    return .{
        .bodies = bodies,
        .regions = regions,
        .keys = keys,
        .contexts = contexts,
        .ordinary_ast = try ordinary.toOwnedSlice(allocator),
        .nominal_syntax = nominal_syntax,
    };
}

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
    frame(&hash, if (function.signature.mutation_facts.writes) "writes" else "no-writes");
    frame(&hash, if (function.signature.mutation_facts.external) "external" else "internal");
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
    return std.fmt.allocPrint(allocator, "T:{s}", .{typed.typeName(ty, records)});
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

fn hexFingerprint(allocator: std.mem.Allocator, digest: [32]u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch error.OutOfMemory;
}

fn lessRecordName(records: []const typed.Record, a: usize, b: usize) bool {
    return std.mem.lessThan(u8, records[a].name, records[b].name);
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
    for (record.fields) |field| {
        frame(hash, field.name);
        frame(hash, typed.typeName(field.ty, records));
    }
    if (record.shape.variants) |variants| {
        frame(hash, if (variants.fallible) "result" else if (variants.is_union) "union" else "enum");
        std.mem.writeInt(u64, &count, variants.cases.len, .little);
        hash.update(&count);
        for (variants.cases) |case| {
            frame(hash, case.name);
            frame(hash, if (case.payload) |payload| typed.typeName(payload, records) else "-");
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
        std.mem.writeInt(u64, &count, callback.parameters.len, .little);
        hash.update(&count);
        for (callback.parameters) |parameter| frame(hash, typed.typeName(parameter, records));
        frame(hash, typed.typeName(callback.return_type, records));
        std.mem.writeInt(u64, &count, callback.effects, .little);
        hash.update(&count);
    }
}

const DeclKind = enum(u4) { function = 0, record = 1, domain = 2, variant = 3, alias = 4, constraint = 5, resource = 6 };

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

    fn deinit(self: *ModuleDecls, allocator: std.mem.Allocator) void {
        var iterator = self.names.iterator();
        while (iterator.next()) |entry| entry.value_ptr.deinit(allocator);
        self.names.deinit(allocator);
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
    memo: std.AutoHashMapUnmanaged(u64, [32]u8) = .empty,
    active: std.AutoHashMapUnmanaged(u64, void) = .empty,

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
        return self;
    }

    fn deinit(self: *Builder) void {
        for (self.modules) |*module| module.deinit(self.allocator);
        self.allocator.free(self.modules);
        self.memo.deinit(self.allocator);
        self.active.deinit(self.allocator);
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
            if (std.mem.eql(u8, imported.alias, alias)) return imported.target;
        }
        return null;
    }

    /// Resolve one reference text to the declarations it lexically binds. A
    /// missing binding is recorded as a module-scoped negative lookup.
    fn resolve(self: *Builder, module: usize, name: []const u8, owner: ?[]const u8, refs: *Refs, negatives: *Negatives) error{OutOfMemory}!void {
        if (owner) |owner_text| {
            if (splitHead(owner_text)) |head| if (self.importTarget(module, head.alias)) |target| {
                const key = if (head.rest.len == 0) name else try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ head.rest, name });
                return self.resolveKey(target, key, refs, negatives);
            };
            const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ owner_text, name });
            return self.resolveKey(module, key, refs, negatives);
        }
        if (splitHead(name)) |head| if (self.importTarget(module, head.alias)) |target| return self.resolveKey(target, head.rest, refs, negatives);
        return self.resolveKey(module, name, refs, negatives);
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
    fn context(self: *Builder, function: ast.Function, key: []const u8, contract: [32]u8) error{ OutOfMemory, InternalError }![32]u8 {
        const body = self.program.statements.items[@backingInt(function.body)].span;
        const start = lineStart(self.src.bytes, function.name.start);
        if (start > body.start) return error.InternalError;
        var hash = Hash.init(.{});
        hash.update(functions_domain);
        hash.update(&contract);
        frame(&hash, key);
        frame(&hash, self.src.bytes[start..body.start]);
        var collector = Collector.init(self, moduleOf(self.src, function.name));
        defer collector.deinit();
        try collector.collectValue(ast.Function, function);
        try self.mixRefs(&hash, &collector, null);
        return hash.finalResult();
    }

    fn declFingerprint(self: *Builder, key: u64) error{OutOfMemory}!([32]u8) {
        if (self.memo.get(key)) |fingerprint| return fingerprint;
        if (self.active.contains(key)) return @splat(0);
        try self.active.put(self.allocator, key, {});
        defer _ = self.active.remove(key);
        const kind: DeclKind = @fromBackingInt(@intCast(@as(u4, @truncate(key >> 32))));
        const index: usize = @intCast(@as(u32, @truncate(key)));
        var hash = Hash.init(.{});
        frame(&hash, "decl-v3");
        frame(&hash, @tagName(kind));
        var collector = Collector.init(self, self.declarationModule(kind, index));
        defer collector.deinit();
        switch (kind) {
            .function => {
                const function = self.program.functions[index];
                const body = self.program.statements.items[@backingInt(function.body)].span;
                const start = lineStart(self.src.bytes, function.name.start);
                const end = if (function.policy.constant) body.end else body.start;
                if (start > end or end > self.src.bytes.len) return error.OutOfMemory;
                frame(&hash, self.src.bytes[start..end]);
                self.mixExport(&hash, function.name);
                if (function.policy.constant) {
                    try collector.collectValue(ast.Function, function);
                } else {
                    try collector.collectValue(ast.FunctionSignature, function.signature);
                    try collector.collectValue(ast.FunctionPolicy, function.policy);
                    try collector.addSpan(function.name);
                }
            },
            .record => {
                self.mixExport(&hash, self.program.types.records[index].name);
                try collector.collectValue(ast.Record, self.program.types.records[index]);
            },
            .domain => {
                self.mixExport(&hash, self.program.types.domains[index].name);
                try collector.collectValue(ast.Domain, self.program.types.domains[index]);
            },
            .resource => {
                self.mixExport(&hash, self.program.types.resources[index].name);
                try collector.collectValue(ast.Domain, self.program.types.resources[index]);
            },
            .variant => {
                self.mixExport(&hash, self.program.types.variants[index].name);
                try collector.collectValue(ast.Variants, self.program.types.variants[index]);
            },
            .alias => {
                self.mixExport(&hash, self.program.types.expressions.aliases[index].name);
                try collector.collectValue(ast.TypeAlias, self.program.types.expressions.aliases[index]);
            },
            .constraint => {
                self.mixExport(&hash, self.program.types.constraints[index].name);
                try collector.collectValue(ast.Constraint, self.program.types.constraints[index]);
            },
        }
        try self.mixRefs(&hash, &collector, key);
        const fingerprint = hash.finalResult();
        try self.memo.put(self.allocator, key, fingerprint);
        return fingerprint;
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
    }

    fn exportDigest(self: *Builder, span: source.Span) [32]u8 {
        const module = moduleOf(self.src, span);
        const bytes = if (self.src.origins.len == 0) self.src.bytes else self.src.origins[module].original.bytes;
        const name = self.src.text(span);
        var hash = Hash.init(.{});
        frame(&hash, "export-v1");
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

    /// Hash the resolved declaration fingerprints and module-scoped negative
    /// lookups recorded for one declaration, in deterministic order.
    fn mixRefs(self: *Builder, hash: *Hash, collector: *const Collector, skip: ?u64) error{OutOfMemory}!void {
        // Dependencies are ordered by their content fingerprints, never by a
        // fresh catalog ordinal, so reordering modules or declarations cannot
        // perturb an otherwise identical dependency digest.
        const fingerprints = try self.allocator.alloc([32]u8, collector.refs.count());
        defer self.allocator.free(fingerprints);
        var iterator = collector.refs.keyIterator();
        var count: usize = 0;
        while (iterator.next()) |key| {
            if (skip) |self_key| if (self_key == key.*) continue;
            fingerprints[count] = try self.declFingerprint(key.*);
            count += 1;
        }
        std.mem.sort([32]u8, fingerprints[0..count], {}, lessFingerprint);
        for (fingerprints[0..count]) |fingerprint| {
            frame(hash, "reference");
            hash.update(&fingerprint);
        }
        const names = try self.allocator.alloc([]const u8, collector.negatives.count());
        defer self.allocator.free(names);
        var negative_iterator = collector.negatives.keyIterator();
        count = 0;
        while (negative_iterator.next()) |name| : (count += 1) names[count] = name.*;
        std.mem.sort([]const u8, names, {}, lessString);
        for (names) |name| {
            frame(hash, "negative");
            frame(hash, name);
        }
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

    fn init(builder: *Builder, module: usize) Collector {
        return .{ .builder = builder, .module = module };
    }

    fn deinit(self: *Collector) void {
        self.refs.deinit(self.builder.allocator);
        self.negatives.deinit(self.builder.allocator);
        self.visited_nodes.deinit(self.builder.allocator);
        self.visited_statements.deinit(self.builder.allocator);
    }

    fn addSpan(self: *Collector, span: source.Span) error{OutOfMemory}!void {
        if (span.end <= span.start or span.end > self.builder.src.bytes.len) return;
        const text = self.builder.src.bytes[span.start..span.end];
        if (!identifierLike(text)) return;
        try self.builder.resolve(self.module, text, null, &self.refs, &self.negatives);
    }

    fn addMember(self: *Collector, owner: source.Span, name: source.Span) error{OutOfMemory}!void {
        if (owner.end <= owner.start or owner.end > self.builder.src.bytes.len) return;
        if (name.end <= name.start or name.end > self.builder.src.bytes.len) return;
        const owner_text = self.builder.src.bytes[owner.start..owner.end];
        const name_text = self.builder.src.bytes[name.start..name.end];
        if (owner_text.len == 0 or name_text.len == 0) return;
        try self.builder.resolve(self.module, name_text, owner_text, &self.refs, &self.negatives);
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
const Qualified = struct { alias: []const u8, rest: []const u8 };
/// Split a qualified reference at its first module separator.
fn splitHead(text: []const u8) ?Qualified {
    const at = std.mem.indexOfAny(u8, text, ".:") orelse return null;
    if (at == 0) return null;
    var rest_start = at + 1;
    if (text[at] == ':') {
        if (rest_start >= text.len or text[rest_start] != ':') return null;
        rest_start += 1;
    }
    if (rest_start >= text.len) return null;
    return .{ .alias = text[0..at], .rest = text[rest_start..] };
}
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
