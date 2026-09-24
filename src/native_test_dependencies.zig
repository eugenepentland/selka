//! Compiler-owned native test dependency facts from checked bytecode and layouts.
const std = @import("std");
const bytecode = @import("bytecode_model.zig");
const typed = @import("typed.zig");
const layouts = @import("native_types.zig");
const effects = @import("effect_set.zig");
const Sha = std.crypto.hash.sha2.Sha256;
/// Implementation and type-fact digests are BLAKE3: they hash every emitted
/// unit's whole text, and std's SHA-256 runs at about 11 MB/s on this toolchain
/// (see `qbe_fragments.zig`). Linker symbols stay SHA-256 names.
const Fact = std.crypto.hash.Blake3;
/// Native ABI identity carried by every checked-facts manifest. This is the one
/// definition: the QBE units manifest, the durable checked-facts graph and the
/// native build driver's generation identity all reference it, so the meaning
/// of a manifest can only ever be spelled once. Version 7 is version 6 with the
/// two-word managed-object header: the runtime's tracing-heap image layout and
/// the mark word its generated frozen-literal blocks initialize changed, so a v6
/// manifest's image data cannot be linked against a v8 runtime and its reader
/// must refuse it rather than reuse the object. Version 8 is version 7 with
/// UTF-8 text storage: a text header, a `str` frozen-literal block and the
/// object a text is allocated as all changed shape, so a v7 image cannot be
/// linked against a v8 runtime either.
pub const abi = "mylang-qbe-native-v8";
/// The semantic reason another implementation can affect a function's behavior.
pub const Kind = enum { call, function_value, indirect, codec };
/// A dependency names a persistent linker symbol rather than a function-table index.
pub const Dependency = struct { symbol: []const u8, kind: Kind };
/// Facts emitted beside each QBE function without changing its native artifact key.
pub const Metadata = struct {
    implementation_hash: []const u8,
    dependencies: []const Dependency,
    cacheable: bool,
    /// No capability parameter and no declared `mutates(...)` footprint, so an
    /// unchanged result may be replayed without a positive receipt when the
    /// opt-in pure-path flag is set. Always implies `cacheable` is required too.
    pure: bool,
    reasons: []const []const u8,
};
/// Effects confined to one freshly spawned test process and its keyed inputs.
/// Output is one of them: a test's writes to `out` and `err` are determined by
/// the same keyed inputs as its result, and the runner captures both streams and
/// discards them when the test passes, while a receipt records only a pass. A
/// reused pass therefore shows exactly what an executed pass shows — nothing —
/// and a failure, whose captured output is reported, is never reused.
pub const deterministic_effects = effects.bit(.managed_allocation) | effects.bit(.mutation) | effects.bit(.output);
/// Record checked call edges and the canonical type inputs actually used by a unit.
/// All returned allocations belong to the caller's compilation arena.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, index: usize, il: []const u8, catalog: *layouts.Catalog, states: []const ?[]const typed.Type) layouts.Error!Metadata {
    const function = program.functions[index];
    var builder: Facts = .{ .allocator = allocator, .program = program, .catalog = catalog };
    defer builder.types.deinit(allocator);
    for (function.scope.instructions) |instruction| try builder.operation(instruction.op);
    if (function.policy.host != null) try builder.reason("host-call");
    const external_effects = function.policy.effects & ~deterministic_effects;
    if (external_effects != 0) try builder.reason("external-effects");
    const cacheable = function.policy.host == null and external_effects == 0 and !builder.external;
    try builder.typeInput(function.signature.return_type);
    for (function.scope.locals) |local| try builder.typeInput(local.ty);
    for (states) |state| if (state) |stack| for (stack) |ty| try builder.typeInput(ty);
    std.mem.sort(Dependency, builder.dependencies.items, {}, dependencyLess);
    std.mem.sort(TypeFact, builder.type_facts.items, {}, typeLess);
    var hash = Fact.init(.{});
    part(&hash, "native-test-implementation-v2");
    part(&hash, layouts.Catalog.abi_version);
    part(&hash, il);
    for (builder.type_facts.items) |fact| {
        part(&hash, fact.identity);
        part(&hash, &fact.digest);
    }
    return .{
        .implementation_hash = try allocator.dupe(u8, &std.fmt.bytesToHex(factDigest(&hash), .lower)),
        .dependencies = try builder.dependencies.toOwnedSlice(allocator),
        .cacheable = cacheable,
        .pure = signaturePure(function.signature, function.scope.locals),
        .reasons = try builder.reasons.toOwnedSlice(allocator),
    };
}
/// Whether a checked function's declared signature is pure: it exposes no
/// capability parameter and declares no `mutates(...)` footprint. This is a
/// strictly stronger condition than the effect-based `cacheable` fact and gates
/// the opt-in outcome-replay path, so a capability the test never reads still
/// keeps the test off that path.
pub fn signaturePure(signature: typed.FunctionSignature, locals: []const typed.Local) bool {
    if (signature.declared_mutates.len != 0) return false;
    const parameters = @min(signature.parameter_count, locals.len);
    for (locals[0..parameters]) |parameter| {
        if (parameter.ty.capabilityIndex() != null) return false;
    }
    return true;
}
const TypeFact = struct { identity: []const u8, digest: [32]u8 };
fn typeLess(_: void, a: TypeFact, b: TypeFact) bool {
    return std.mem.lessThan(u8, a.identity, b.identity);
}
fn dependencyLess(_: void, a: Dependency, b: Dependency) bool {
    const order = std.mem.order(u8, a.symbol, b.symbol);
    return if (order == .eq) @backingInt(a.kind) < @backingInt(b.kind) else order == .lt;
}
const Facts = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    catalog: *layouts.Catalog,
    dependencies: std.ArrayList(Dependency) = .empty,
    reasons: std.ArrayList([]const u8) = .empty,
    types: std.AutoHashMapUnmanaged(typed.Type, void) = .empty,
    type_facts: std.ArrayList(TypeFact) = .empty,
    external: bool = false,
    fn reason(self: *Facts, value: []const u8) layouts.Error!void {
        for (self.reasons.items) |existing| if (std.mem.eql(u8, existing, value)) return;
        try self.reasons.append(self.allocator, value);
    }
    fn edge(self: *Facts, id: typed.FunctionId, kind: Kind) layouts.Error!void {
        if (@backingInt(id) >= self.program.functions.len) return error.InvalidType;
        const name = self.program.functions[@backingInt(id)].name;
        var digest: [32]u8 = undefined;
        Sha.hash(name, &digest, .{});
        const symbol = try std.fmt.allocPrint(self.allocator, "myl_f_{s}", .{std.fmt.bytesToHex(digest, .lower)});
        for (self.dependencies.items) |existing| if (existing.kind == kind and std.mem.eql(u8, existing.symbol, symbol)) return;
        try self.dependencies.append(self.allocator, .{ .symbol = symbol, .kind = kind });
    }
    fn operation(self: *Facts, op: @FieldType(bytecode.Instruction, "op")) layouts.Error!void {
        switch (op) {
            .call => |id| try self.edge(id, .call),
            .function_value => |value| try self.edge(value.function, .function_value),
            .invoke => {
                try self.reason("conservative-indirect-target-set");
                for (self.program.functions) |function| for (function.scope.instructions) |instruction| {
                    if (instruction.op == .function_value) try self.edge(instruction.op.function_value.function, .indirect);
                };
            },
            .external_read, .environment_get, .environment_names, .acquire_resource, .complete_resource, .resource_io, .restrict_resource, .dir_resource => {
                self.external = true;
                try self.reason("external-capability-operation");
            },
            else => {},
        }
    }
    fn typeInput(self: *Facts, ty: typed.Type) layouts.Error!void {
        if ((try self.types.getOrPut(self.allocator, ty)).found_existing) return;
        const identity = try self.catalog.identity(ty);
        var hash = Fact.init(.{});
        part(&hash, &(try self.catalog.layout(ty)).hash);
        if (ty.isAggregate()) try self.recordInput(self.program.records[ty.recordIndex()], &hash);
        try self.type_facts.append(self.allocator, .{ .identity = identity, .digest = factDigest(&hash) });
    }
    fn child(self: *Facts, hash: *Fact, ty: typed.Type) layouts.Error!void {
        part(hash, try self.catalog.identity(ty));
        try self.typeInput(ty);
    }
    fn recordInput(self: *Facts, record: typed.Record, hash: *Fact) layouts.Error!void {
        part(hash, @tagName(record.collection.kind));
        if (record.managed) {
            const body = try self.catalog.heapLayout(record.id);
            defer self.catalog.releaseLayout(body);
            part(hash, &body.hash);
        }
        for (record.fields) |field| {
            part(hash, field.name);
            try self.child(hash, field.ty);
        }
        if (record.shape.domain) |ty| try self.child(hash, ty);
        if (record.shape.buffer) |ty| try self.child(hash, ty);
        if (record.collection.key) |ty| try self.child(hash, ty);
        if (record.shape.array) |array| {
            try self.child(hash, array.element);
            if (array.key) |ty| try self.child(hash, ty);
        }
        if (record.shape.variants) |variants| for (variants.cases) |case| {
            part(hash, case.name);
            if (case.payload) |ty| try self.child(hash, ty);
        };
        if (record.contract.callback) |signature| {
            for (signature.parameters) |ty| try self.child(hash, ty);
            try self.child(hash, signature.return_type);
        }
        if (record.contract.codec) |codec| {
            try self.reason("domain-codec-boundary");
            try self.edge(codec.decode, .codec);
            try self.edge(codec.encode, .codec);
            try self.child(hash, codec.wire);
            part(hash, self.program.functions[@backingInt(codec.decode)].name);
            part(hash, self.program.functions[@backingInt(codec.encode)].name);
        }
    }
};

/// The digest a finished fact hasher holds.
fn factDigest(hash: *const Fact) [32]u8 {
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

fn part(hash: *Fact, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

// spec: NATIVE-TEST-13
test "checked metadata allows process-local mutation but rejects external effects" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const instructions = [_]bytecode.Instruction{
        .{ .span = span, .op = .{ .function_value = .{ .function = @fromBackingInt(1), .ty = .i64 } } },
        .{ .span = span, .op = .{ .invoke = .i64 } },
    };
    var functions = [_]bytecode.Function{
        .{ .id = @fromBackingInt(0), .name = "testA", .scope = .{ .instructions = &instructions }, .policy = .{ .effects = effects.bit(.managed_allocation) | effects.bit(.mutation) }, .signature = .{ .declared_mutates = &.{0} } },
        .{ .id = @fromBackingInt(1), .name = "callback", .scope = .{ .instructions = &.{} } },
    };
    var catalog = try layouts.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    const first = try describe(a, .{ .functions = &functions }, 0, "stable IL", &catalog, &.{});
    try std.testing.expect(first.cacheable);
    try std.testing.expect(!first.pure);
    try std.testing.expectEqual(@as(usize, 2), first.dependencies.len);
    functions[0].policy.effects = effects.bit(.clock);
    const external = try describe(a, .{ .functions = &functions }, 0, "stable IL", &catalog, &.{});
    try std.testing.expect(!external.cacheable);
    try std.testing.expectEqualStrings(first.implementation_hash, external.implementation_hash);
}

// spec: NATIVE-TEST-OUTPUT-1
test "checked metadata keeps a test whose only external effect is output cacheable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var functions = [_]bytecode.Function{
        .{ .id = @fromBackingInt(0), .name = "test_prints", .scope = .{ .instructions = &.{} }, .policy = .{ .effects = effects.bit(.output) | effects.bit(.managed_allocation) } },
    };
    var catalog = try layouts.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    const printing = try describe(a, .{ .functions = &functions }, 0, "stable IL", &catalog, &.{});
    try std.testing.expect(printing.cacheable);
    try std.testing.expectEqual(@as(usize, 0), printing.reasons.len);
    functions[0].policy.effects = effects.bit(.output) | effects.bit(.environment);
    const environmental = try describe(a, .{ .functions = &functions }, 0, "stable IL", &catalog, &.{});
    try std.testing.expect(!environmental.cacheable);
}

test "semantic type fingerprints follow managed elements and ignore unused declarations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const element: typed.Type = @fromBackingInt(typed.Type.record_base);
    const list: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
    const unused: typed.Type = @fromBackingInt(typed.Type.record_base + 2);
    var fields = [_]typed.Field{.{ .name = "x", .ty = .i64, .declaration = span }};
    var records = [_]typed.Record{
        .{ .id = element, .name = "Element", .declaration = span, .fields = &fields },
        .{ .id = list, .name = "List<Element>", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = element } },
        .{ .id = unused, .name = "Unused", .declaration = span, .fields = &.{} },
    };
    const functions = [_]bytecode.Function{.{ .id = @fromBackingInt(0), .name = "test", .signature = .{ .return_type = list }, .scope = .{ .instructions = &.{} } }};
    var original = try layouts.Catalog.initRecords(a, &records);
    defer original.deinit();
    const before = try describe(a, .{ .functions = &functions, .records = &records }, 0, "same pointer IL", &original, &.{});
    records[2].fields = &fields;
    var unrelated = try layouts.Catalog.initRecords(a, &records);
    defer unrelated.deinit();
    const same = try describe(a, .{ .functions = &functions, .records = &records }, 0, "same pointer IL", &unrelated, &.{});
    try std.testing.expectEqualStrings(before.implementation_hash, same.implementation_hash);
    fields[0].ty = .u8;
    var changed = try layouts.Catalog.initRecords(a, &records);
    defer changed.deinit();
    const after = try describe(a, .{ .functions = &functions, .records = &records }, 0, "same pointer IL", &changed, &.{});
    try std.testing.expect(!std.mem.eql(u8, before.implementation_hash, after.implementation_hash));
}

test "domain signatures depend on codec callbacks without a JSON instruction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const domain: typed.Type = @fromBackingInt(typed.Type.record_base);
    const records = [_]typed.Record{.{
        .id = domain,
        .name = "D",
        .declaration = .{ .start = 0, .end = 0 },
        .fields = &.{},
        .shape = .{ .domain = .i64 },
        .contract = .{ .codec = .{ .wire = .i64, .decode = @fromBackingInt(1), .encode = @fromBackingInt(2) } },
    }};
    const functions = [_]bytecode.Function{
        .{ .id = @fromBackingInt(0), .name = "echo", .signature = .{ .return_type = domain }, .scope = .{ .instructions = &.{} } },
        .{ .id = @fromBackingInt(1), .name = "D.decode", .scope = .{ .instructions = &.{} } },
        .{ .id = @fromBackingInt(2), .name = "D.encode", .scope = .{ .instructions = &.{} } },
    };
    var catalog = try layouts.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    const facts = try describe(a, .{ .functions = &functions, .records = &records }, 0, "echo IL", &catalog, &.{});
    try std.testing.expect(facts.cacheable);
    try std.testing.expectEqual(@as(usize, 2), facts.dependencies.len);
    for (facts.dependencies) |dependency| try std.testing.expectEqual(Kind.codec, dependency.kind);
    try std.testing.expectEqualStrings("domain-codec-boundary", facts.reasons[0]);
}
test "metadata rejects InvalidType for a forged function target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const instructions = [_]bytecode.Instruction{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .call = @fromBackingInt(99) } }};
    const functions = [_]bytecode.Function{.{ .id = @fromBackingInt(0), .name = "bad", .scope = .{ .instructions = &instructions } }};
    var catalog = try layouts.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    try std.testing.expectError(error.InvalidType, describe(a, .{ .functions = &functions }, 0, "bad IL", &catalog, &.{}));
}

// spec-case: EFFECT-CEILING-1
test "an exported declared ceiling does not suppress body-change invalidation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bound: effects.Bound = .{ .allowed = effects.bit(.managed_allocation), .span = .{ .start = 0, .end = 0 } };
    const first_il = "push_integer 1\nret\n";
    const second_il = "acquire_buffer list[i64]\npush_integer 1\nbuffer_operation append\nret\n";
    const functions = [_]bytecode.Function{.{
        .id = @fromBackingInt(0),
        .name = "test_value",
        .policy = .{ .effect_bound = bound, .effects = bound.allowed },
        .scope = .{ .instructions = &.{} },
    }};
    var catalog = try layouts.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    const first = try describe(a, .{ .functions = &functions }, 0, first_il, &catalog, &.{});
    try std.testing.expect(first.cacheable);
    const same = try describe(a, .{ .functions = &functions }, 0, first_il, &catalog, &.{});
    try std.testing.expectEqualStrings(first.implementation_hash, same.implementation_hash);
    const changed = try describe(a, .{ .functions = &functions }, 0, second_il, &catalog, &.{});
    try std.testing.expect(!std.mem.eql(u8, first.implementation_hash, changed.implementation_hash));
}

// spec-case: PURE-SKIP-1
test "signature purity excludes capability parameters and declared mutates" {
    const span = @import("source.zig").Span{ .start = 0, .end = 0 };
    const value_locals = [_]typed.Local{.{ .name = "x", .declaration = span, .ty = .i64, .mutable = false }};
    const capability_locals = [_]typed.Local{.{ .name = "fs", .declaration = span, .ty = .filesystem_cap, .mutable = false }};
    const plain: typed.FunctionSignature = .{ .return_type = .bool, .parameter_count = 1 };
    const mutating: typed.FunctionSignature = .{ .return_type = .bool, .parameter_count = 1, .declared_mutates = &[_]u16{0} };
    try std.testing.expect(signaturePure(plain, &value_locals));
    try std.testing.expect(!signaturePure(plain, &capability_locals));
    try std.testing.expect(!signaturePure(mutating, &value_locals));
}
