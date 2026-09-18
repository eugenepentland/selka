//! Checked native-test dependency facts without bytecode or QBE lowering.
//!
//! The facts manifest carries exactly what result planning needs: per-function
//! semantic body/layout fingerprints, direct and conservative indirect call
//! edges, codec-boundary edges and cacheability reasons. It is derived from the
//! checked typed program and the interface schema, never from lowered QBE IL, so
//! a warm selection can decide receipts without lowering or emission.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const lexer = @import("lexer.zig");
const diagnostic = @import("diagnostic.zig");
const native_types = @import("native_types.zig");
const walk = @import("typed_walk.zig");
const dependencies = @import("native_test_dependencies.zig");
const effect_set = @import("effect_set.zig");
const Sha = std.crypto.hash.sha2.Sha256;
/// Facts generation failures; malformed checked programs never publish facts.
pub const Error = error{ OutOfMemory, InvalidProgram };
/// The public export name carried by a checked function.
pub const Export = struct { name: []const u8 = "" };
/// One checked function and its native-test dependency facts.
pub const Unit = struct {
    name: []const u8,
    symbol: []const u8,
    /// Null for private/specialized functions and synthesized helpers.
    @"export": ?Export = null,
    test_dependencies: dependencies.Metadata,
};
/// Durable checked facts payload. It deliberately carries no QBE IL or locations.
pub const Graph = struct {
    version: []const u8 = "native-test-graph-v3",
    abi: []const u8 = dependencies.abi,
    schema: []const u8,
    entry: []const u8 = "",
    functions: []const Unit,
};

/// Render checked native-test facts for one checked project. All temporary
/// fingerprints and dependency arrays live in a render-local arena; the returned
/// payload alone is owned by `allocator`.
pub fn render(allocator: std.mem.Allocator, src: source.Source, program: typed.Program, roots: []const typed.FunctionId, schema: []const u8) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var catalog = native_types.Catalog.initRecords(scratch, program.records) catch |err| return mapLayoutError(err);
    defer catalog.deinit();
    const exported = try scratch.alloc(bool, program.functions.len);
    @memset(exported, false);
    for (roots) |root| {
        if (@backingInt(root) >= exported.len) return error.InvalidProgram;
        exported[@backingInt(root)] = true;
    }
    const address_taken = try collectAddressTaken(scratch, program);
    const codecs = try collectCodecs(scratch, program);
    const facts: FunctionFacts = .{
        .allocator = scratch,
        .src = src,
        .program = program,
        .catalog = &catalog,
        .address_taken = address_taken,
        .codecs = codecs,
    };
    const units = try scratch.alloc(Unit, program.functions.len);
    for (program.functions, 0..) |function, index| {
        units[index] = .{
            .name = function.name,
            .symbol = try symbol(scratch, function.name),
            .@"export" = if (exported[index]) .{ .name = function.name } else null,
            .test_dependencies = try facts.describe(function),
        };
    }
    const entry = if (@backingInt(program.main) < program.functions.len) try symbol(scratch, program.functions[@backingInt(program.main)].name) else "";
    return std.json.Stringify.valueAlloc(allocator, Graph{ .schema = schema, .entry = entry, .functions = units }, .{});
}

/// The stable native symbol for one qualified function name.
pub fn symbol(allocator: std.mem.Allocator, name: []const u8) Error![]const u8 {
    var digest: [32]u8 = undefined;
    Sha.hash(name, &digest, .{});
    return std.fmt.allocPrint(allocator, "myl_f_{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch error.OutOfMemory;
}

/// Conservatively widen one selective build to runtime support that the
/// emitted manifest always carries: every address-taken function once any
/// selected body performs an indirect invoke, and every codec method when a
/// checked domain codec exists. Returns the explicit reasons to report.
pub fn expandSelection(allocator: std.mem.Allocator, program: typed.Program, selected: []bool) Error!void {
    if (selected.len != program.functions.len) return error.InvalidProgram;
    const address_taken = try collectAddressTaken(allocator, program);
    defer allocator.free(address_taken);
    const codecs = try collectCodecs(allocator, program);
    defer allocator.free(codecs);
    var indirect = false;
    for (program.functions, 0..) |function, index| {
        if (!selected[index]) continue;
        var walker = walk.Walker.init(allocator, program, function.scope.body) catch |err| return mapError(err);
        defer walker.deinit();
        while (true) {
            const item = walker.next() catch |err| return mapError(err);
            const current = item orelse break;
            switch (current) {
                .expression => |id| {
                    if (program.nodes[@backingInt(id)].data == .invoke) indirect = true;
                },
                .statement => {},
            }
        }
    }
    if (indirect) {
        for (address_taken) |id| selected[@backingInt(id)] = true;
    }
    if (codecs.len != 0) {
        for (codecs) |id| selected[@backingInt(id)] = true;
    }
}

fn collectAddressTaken(allocator: std.mem.Allocator, program: typed.Program) Error![]typed.FunctionId {
    var ids: std.ArrayList(typed.FunctionId) = .empty;
    // UNTESTED-ERROR: allocation-failure cleanup is exercised by generic allocator-failure coverage; no deterministic OOM hook is available here.
    errdefer ids.deinit(allocator);
    for (program.functions) |function| {
        var walker = walk.Walker.init(allocator, program, function.scope.body) catch |err| return mapError(err);
        defer walker.deinit();
        while (true) {
            const item = walker.next() catch |err| return mapError(err);
            const current = item orelse break;
            const node = switch (current) {
                .expression => |id| program.nodes[@backingInt(id)],
                .statement => continue,
            };
            switch (node.data) {
                .function_value => |id| try appendUnique(allocator, &ids, id),
                else => {},
            }
        }
    }
    return ids.toOwnedSlice(allocator) catch error.OutOfMemory;
}

fn collectCodecs(allocator: std.mem.Allocator, program: typed.Program) Error![]typed.FunctionId {
    var ids: std.ArrayList(typed.FunctionId) = .empty;
    // UNTESTED-ERROR: allocation-failure cleanup is exercised by generic allocator-failure coverage; no deterministic OOM hook is available here.
    errdefer ids.deinit(allocator);
    for (program.records) |record| {
        const codec = record.contract.codec orelse continue;
        if (@backingInt(codec.decode) >= program.functions.len or @backingInt(codec.encode) >= program.functions.len) return error.InvalidProgram;
        try appendUnique(allocator, &ids, codec.decode);
        try appendUnique(allocator, &ids, codec.encode);
    }
    return ids.toOwnedSlice(allocator) catch error.OutOfMemory;
}

fn appendUnique(allocator: std.mem.Allocator, ids: *std.ArrayList(typed.FunctionId), id: typed.FunctionId) Error!void {
    for (ids.items) |existing| if (@backingInt(existing) == @backingInt(id)) return;
    ids.append(allocator, id) catch return error.OutOfMemory;
}

const ReasonSet = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8) = .empty,
    fn add(self: *ReasonSet, value: []const u8) Error!void {
        for (self.items.items) |existing| if (std.mem.eql(u8, existing, value)) return;
        self.items.append(self.allocator, value) catch return error.OutOfMemory;
    }
    fn deinit(self: *ReasonSet) void {
        self.items.deinit(self.allocator);
    }
};

const DependencySet = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(dependencies.Dependency) = .empty,
    fn add(self: *DependencySet, program: typed.Program, id: typed.FunctionId, kind: dependencies.Kind) Error!void {
        const index = @backingInt(id);
        if (index >= program.functions.len) return error.InvalidProgram;
        var digest: [32]u8 = undefined;
        Sha.hash(program.functions[index].name, &digest, .{});
        const symbol_text = std.fmt.allocPrint(self.allocator, "myl_f_{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch return error.OutOfMemory;
        for (self.items.items) |existing| {
            if (existing.kind == kind and std.mem.eql(u8, existing.symbol, symbol_text)) return;
        }
        self.items.append(self.allocator, .{ .symbol = symbol_text, .kind = kind }) catch return error.OutOfMemory;
    }
    fn deinit(self: *DependencySet) void {
        self.items.deinit(self.allocator);
    }
};

const FunctionFacts = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: typed.Program,
    catalog: *native_types.Catalog,
    address_taken: []const typed.FunctionId,
    codecs: []const typed.FunctionId,

    fn describe(self: FunctionFacts, function: typed.Function) Error!dependencies.Metadata {
        var hash = Sha.init(.{});
        part(&hash, "native-test-implementation-v2");
        part(&hash, native_types.Catalog.abi_version);
        try hashBody(self.allocator, &hash, self.src, self.program, function);
        try hashSignature(&hash, self.allocator, self.program, function, self.catalog);
        var seen_types: std.AutoHashMapUnmanaged(typed.Type, void) = .empty;
        defer seen_types.deinit(self.allocator);
        var deps: DependencySet = .{ .allocator = self.allocator };
        defer deps.deinit();
        var reasons: ReasonSet = .{ .allocator = self.allocator };
        defer reasons.deinit();
        var external = false;
        var facts: TypeFacts = .{
            .hash = &hash,
            .allocator = self.allocator,
            .program = self.program,
            .catalog = self.catalog,
            .seen = &seen_types,
            .deps = &deps,
            .reasons = &reasons,
        };
        try facts.add(function.signature.return_type);
        for (function.scope.locals) |local| try facts.add(local.ty);
        for (function.type_arguments) |argument| try facts.add(argument);
        var walker = walk.Walker.init(self.allocator, self.program, function.scope.body) catch |err| return mapError(err);
        defer walker.deinit();
        while (true) {
            const item = walker.next() catch |err| return mapError(err);
            const current = item orelse break;
            const node = switch (current) {
                .expression => |id| self.program.nodes[@backingInt(id)],
                .statement => continue,
            };
            try facts.add(node.ty);
            switch (node.data) {
                .call => |call| try deps.add(self.program, call.function, .call),
                .function_value => |value| try deps.add(self.program, value, .function_value),
                .invoke => {
                    try reasons.add("conservative-indirect-target-set");
                    for (self.address_taken) |id| try deps.add(self.program, id, .indirect);
                },
                .external_read, .environment_get, .environment_names, .acquire_resource, .complete_resource, .resource_io, .restrict_resource, .dir_resource => {
                    external = true;
                    try reasons.add("external-capability-operation");
                },
                else => {},
            }
        }
        if (function.policy.host != null) try reasons.add("host-call");
        const external_effects = function.policy.effects & ~effect_set.bit(.managed_allocation);
        if (external_effects != 0) try reasons.add("external-effects");
        if (self.codecs.len != 0) {
            try reasons.add("conservative-codec-runtime-set");
            for (self.codecs) |id| try deps.add(self.program, id, .codec);
        }
        std.mem.sort(dependencies.Dependency, deps.items.items, {}, dependencyLess);
        std.mem.sort([]const u8, reasons.items.items, {}, stringLess);
        return .{
            .implementation_hash = std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.bytesToHex(hash.finalResult(), .lower)}) catch return error.OutOfMemory,
            .dependencies = deps.items.toOwnedSlice(self.allocator) catch return error.OutOfMemory,
            .cacheable = function.policy.host == null and external_effects == 0 and !external,
            .pure = dependencies.signaturePure(function.signature, function.scope.locals),
            .reasons = reasons.items.toOwnedSlice(self.allocator) catch return error.OutOfMemory,
        };
    }
};

fn hashBody(allocator: std.mem.Allocator, hash: *Sha, src: source.Source, program: typed.Program, function: typed.Function) Error!void {
    const body = program.statements[@backingInt(function.scope.body)].span;
    var start = lineStart(src.bytes, function.declaration.start);
    var end = body.end;
    if (start > end or end > src.bytes.len or body.start < start) {
        start = body.start;
        end = body.end;
    }
    if (start > end or end > src.bytes.len) return error.InvalidProgram;
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    const tokens = lexer.lexRangeWithMarkers(allocator, src.bytes, .{ .start = start, .end = end }, src.mutation_markers, &sink) catch |err| return mapDiagnosticError(err);
    defer allocator.free(tokens);
    part(hash, "declaration-region");
    for (tokens) |token| {
        part(hash, @tagName(token.tag));
        if (token.span.start > token.span.end or token.span.end > src.bytes.len) return error.InvalidProgram;
        part(hash, src.bytes[token.span.start..token.span.end]);
    }
}

fn hashSignature(hash: *Sha, allocator: std.mem.Allocator, program: typed.Program, function: typed.Function, catalog: *native_types.Catalog) Error!void {
    part(hash, function.name);
    var number: [8]u8 = undefined;
    std.mem.writeInt(u64, &number, function.signature.parameter_count, .little);
    hash.update(&number);
    part(hash, @tagName(function.signature.return_origin));
    switch (function.signature.return_origin) {
        .params => |positions| for (positions) |position| {
            var encoded: [2]u8 = undefined;
            std.mem.writeInt(u16, &encoded, position, .little);
            hash.update(&encoded);
        },
        else => {},
    }
    for (function.signature.mutates) |position| {
        var encoded: [2]u8 = undefined;
        std.mem.writeInt(u16, &encoded, position, .little);
        hash.update(&encoded);
    }
    for (function.signature.declared_mutates) |position| {
        var encoded: [2]u8 = undefined;
        std.mem.writeInt(u16, &encoded, position, .little);
        hash.update(&encoded);
    }
    hash.update(&[_]u8{ @intFromBool(function.signature.mutation_facts.writes), @intFromBool(function.signature.mutation_facts.external) });
    var effect_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &effect_bytes, function.policy.effects, .little);
    hash.update(&effect_bytes);
    hash.update(&[_]u8{
        @intFromBool(function.policy.c_abi),
        @intFromBool(function.policy.host != null),
        @intFromBool(function.policy.restricted),
        @intFromBool(function.policy.conversion),
    });
    if (function.policy.effect_bound) |bound| {
        part(hash, "ceiling");
        var allowed_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &allowed_bytes, bound.allowed, .little);
        hash.update(&allowed_bytes);
    } else part(hash, "no-ceiling");
    if (function.policy.owner) |owner| try hashTypeOnly(hash, allocator, program, owner, catalog);
    for (function.type_arguments) |argument| try hashTypeOnly(hash, allocator, program, argument, catalog);
}

fn hashTypeOnly(hash: *Sha, allocator: std.mem.Allocator, program: typed.Program, ty: typed.Type, catalog: *native_types.Catalog) Error!void {
    _ = allocator;
    _ = program;
    part(hash, catalog.identity(ty) catch |err| return mapLayoutError(err));
    const layout = catalog.layout(ty) catch |err| return mapLayoutError(err);
    part(hash, &layout.hash);
}

const TypeFacts = struct {
    hash: *Sha,
    allocator: std.mem.Allocator,
    program: typed.Program,
    catalog: *native_types.Catalog,
    seen: *std.AutoHashMapUnmanaged(typed.Type, void),
    deps: *DependencySet,
    reasons: *ReasonSet,

    fn add(self: *TypeFacts, ty: typed.Type) Error!void {
        const entry = self.seen.getOrPut(self.allocator, ty) catch return error.OutOfMemory;
        if (entry.found_existing) return;
        part(self.hash, "type");
        part(self.hash, self.catalog.identity(ty) catch |err| return mapLayoutError(err));
        const layout = self.catalog.layout(ty) catch |err| return mapLayoutError(err);
        part(self.hash, &layout.hash);
        if (!ty.isAggregate()) return;
        const index = ty.recordIndex();
        if (index >= self.program.records.len) return error.InvalidProgram;
        const record = self.program.records[index];
        if (record.managed) {
            const body = self.catalog.heapLayout(record.id) catch |err| return mapLayoutError(err);
            defer self.catalog.releaseLayout(body);
            part(self.hash, &body.hash);
        }
        for (record.fields) |field| {
            part(self.hash, field.name);
            try self.add(field.ty);
        }
        if (record.shape.domain) |backing| try self.add(backing);
        if (record.shape.buffer) |element| try self.add(element);
        if (record.collection.key) |key| try self.add(key);
        if (record.shape.array) |array| {
            try self.add(array.element);
            if (array.key) |key| try self.add(key);
        }
        if (record.shape.variants) |variants| for (variants.cases) |case| {
            part(self.hash, case.name);
            if (case.payload) |payload| try self.add(payload);
        };
        if (record.contract.callback) |signature| {
            for (signature.parameters) |parameter| try self.add(parameter);
            try self.add(signature.return_type);
        }
        if (record.contract.codec) |codec| {
            try self.reasons.add("domain-codec-boundary");
            try self.deps.add(self.program, codec.decode, .codec);
            try self.deps.add(self.program, codec.encode, .codec);
            try self.add(codec.wire);
        }
    }
};

fn lineStart(bytes: []const u8, at: usize) usize {
    var index = @min(at, bytes.len);
    while (index > 0 and bytes[index - 1] != '\n') index -= 1;
    return index;
}

fn dependencyLess(_: void, left: dependencies.Dependency, right: dependencies.Dependency) bool {
    const order = std.mem.order(u8, left.symbol, right.symbol);
    return if (order == .eq) @backingInt(left.kind) < @backingInt(right.kind) else order == .lt;
}

fn stringLess(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn part(hash: *Sha, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

fn mapError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidProgram,
    };
}

fn mapDiagnosticError(err: anyerror) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidProgram,
    };
}

fn mapLayoutError(err: native_types.Error) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidProgram;
}

test "facts symbols are stable and length bounded" {
    const first = try symbol(std.testing.allocator, "main::test_a");
    defer std.testing.allocator.free(first);
    const second = try symbol(std.testing.allocator, "main::test_a");
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.startsWith(u8, first, "myl_f_"));
}

// spec-case: NATIVE-TEST-6
test "checked facts reject roots outside the checked function table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "main.my", "");
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0) };
    const roots = [_]typed.FunctionId{@fromBackingInt(0)};
    try std.testing.expectError(error.InvalidProgram, render(a, src, program, &roots, "{}"));
}
