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

/// Which functions a facts payload describes: every checked function, or only
/// the transitive dependency closure of its roots — all `mylang test` ever
/// plans, since it only plans the tests and benchmarks it discovered.
pub const Scope = enum { all, closure };
/// Render checked native-test facts for one checked project. All temporary
/// fingerprints and dependency arrays live in a render-local arena; the returned
/// payload alone is owned by `allocator`. `.closure` describes only what the
/// roots reach, in program order, so its units carry exactly the facts a plan
/// of any root reads while a large project's untested code costs nothing.
pub fn render(allocator: std.mem.Allocator, src: source.Source, input: typed.Program, roots: []const typed.FunctionId, schema: []const u8, scope: Scope) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    // Layout fingerprints describe the catalog the backend lays out, where a
    // recursive value's boxed fields hold boxes (RECURSIVE-VALUES-2).
    var program = input;
    program.records = try @import("recursive_boxes.zig").physical(scratch, input.records);
    var catalog = native_types.Catalog.initRecords(scratch, program.records) catch |err| return mapLayoutError(err);
    defer catalog.deinit();
    const exported = try scratch.alloc(bool, program.functions.len);
    @memset(exported, false);
    for (roots) |root| {
        if (@backingInt(root) >= exported.len) return error.InvalidProgram;
        exported[@backingInt(root)] = true;
    }
    // The conservative indirect-call target set walks every body in the
    // program, so it is collected only once a described body invokes a
    // function value: a closure without indirect calls never pays for it.
    var address_taken: ?[]const typed.FunctionId = null;
    const codecs = try collectCodecs(scratch, program);
    const facts: FunctionFacts = .{
        .allocator = scratch,
        .src = src,
        .program = program,
        .catalog = &catalog,
        .address_taken = &address_taken,
        .codecs = codecs,
    };
    const described = try scratch.alloc(?dependencies.Metadata, program.functions.len);
    @memset(described, null);
    var pending: std.ArrayList(typed.FunctionId) = .empty;
    for (program.functions, 0..) |function, index| {
        if (scope == .all or exported[index]) try pending.append(scratch, function.id);
    }
    var callees: std.ArrayList(typed.FunctionId) = .empty;
    while (pending.pop()) |id| {
        const index = @backingInt(id);
        if (index >= program.functions.len) return error.InvalidProgram;
        if (described[index] != null) continue;
        callees.clearRetainingCapacity();
        described[index] = try facts.describe(program.functions[index], &callees);
        if (scope == .closure) try pending.appendSlice(scratch, callees.items);
    }
    var units: std.ArrayList(Unit) = .empty;
    for (program.functions, described, 0..) |function, metadata, index| {
        const checked = metadata orelse continue;
        try units.append(scratch, .{
            .name = function.name,
            .symbol = try symbol(scratch, function.name),
            .@"export" = if (exported[index]) .{ .name = function.name } else null,
            .test_dependencies = checked,
        });
    }
    const entry = if (@backingInt(program.main) < program.functions.len) try symbol(scratch, program.functions[@backingInt(program.main)].name) else "";
    return std.json.Stringify.valueAlloc(allocator, Graph{ .schema = schema, .entry = entry, .functions = units.items }, .{});
}

/// MODULE-TEST-1: one module's share of a program's checked facts: every
/// function the module emits, described as `render` describes it except for
/// the two program-wide dependency sets, which only a merge of every share
/// knows: an invoking body keeps its `conservative-indirect-target-set`
/// reason but no `indirect` edge, and no body gets `codec` runtime edges.
/// `values` names every function an emitted body takes as a value and
/// `codecs` every codec function the module's program declares; a merge's
/// union of them is the whole program's.
pub const Share = struct {
    version: []const u8 = "module-test-facts-v1",
    functions: []const Unit,
    values: []const []const u8,
    codecs: []const []const u8,
};

/// Render one module's `Share` of checked facts: `emitted` marks the
/// functions the module emits and `roots` the tests and benchmarks among
/// them, which carry their export name.
pub fn renderShare(allocator: std.mem.Allocator, src: source.Source, input: typed.Program, emitted: []const bool, roots: []const bool) Error![]u8 {
    if (emitted.len != input.functions.len or roots.len != input.functions.len) return error.InvalidProgram;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var program = input;
    program.records = try @import("recursive_boxes.zig").physical(scratch, input.records);
    var catalog = native_types.Catalog.initRecords(scratch, program.records) catch |err| return mapLayoutError(err);
    defer catalog.deinit();
    // The program-wide sets are the merge's: an invoking body finds no
    // targets here, and no codec runtime set is added.
    var address_taken: ?[]const typed.FunctionId = &.{};
    const facts: FunctionFacts = .{
        .allocator = scratch,
        .src = src,
        .program = program,
        .catalog = &catalog,
        .address_taken = &address_taken,
        .codecs = &.{},
    };
    var units: std.ArrayList(Unit) = .empty;
    var callees: std.ArrayList(typed.FunctionId) = .empty;
    var values: std.ArrayList([]const u8) = .empty;
    var seen_values: std.StringHashMapUnmanaged(void) = .empty;
    for (program.functions, emitted, roots) |function, emit, root| {
        if (!emit) continue;
        callees.clearRetainingCapacity();
        try units.append(scratch, .{
            .name = function.name,
            .symbol = try symbol(scratch, function.name),
            .@"export" = if (root) .{ .name = function.name } else null,
            .test_dependencies = try facts.describe(function, &callees),
        });
        var walker = walk.Walker.init(scratch, program, function.scope.body) catch |err| return mapError(err);
        defer walker.deinit();
        while (true) {
            const item = walker.next() catch |err| return mapError(err);
            const current = item orelse break;
            const node = switch (current) {
                .expression => |id| program.nodes[@backingInt(id)],
                .statement => continue,
            };
            switch (node.data) {
                .function_value => |id| {
                    if (@backingInt(id) >= program.functions.len) return error.InvalidProgram;
                    const name = program.functions[@backingInt(id)].name;
                    if ((seen_values.getOrPut(scratch, name) catch return error.OutOfMemory).found_existing) continue;
                    values.append(scratch, name) catch return error.OutOfMemory;
                },
                else => {},
            }
        }
    }
    const codec_ids = try collectCodecs(scratch, program);
    const codecs = try scratch.alloc([]const u8, codec_ids.len);
    for (codec_ids, codecs) |id, *name| name.* = program.functions[@backingInt(id)].name;
    std.mem.sort([]const u8, values.items, {}, stringLess);
    std.mem.sort([]const u8, codecs, {}, stringLess);
    return std.json.Stringify.valueAlloc(allocator, Share{ .functions = units.items, .values = values.items, .codecs = codecs }, .{}) catch error.OutOfMemory;
}

/// What a merge of shares is rendered with: the schema of the roots, the
/// entry's symbol and whether to keep only what the roots reach.
pub const MergeOptions = struct { schema: []const u8, entry: []const u8, scope: Scope };

/// MODULE-TEST-1: the checked facts graph of a program from its modules'
/// shares, as `render` renders it: each identical function once, conflicting
/// definitions rejected, every invoking body's `indirect` edges to the union of the
/// shares' value sets, and, when any share declares a codec, every body's
/// `codec` edges to the union of their codec sets. `.closure` keeps what the
/// exported roots reach, in share order.
pub fn mergeShares(allocator: std.mem.Allocator, shares: []const Share, options: MergeOptions) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var order: std.ArrayList(Unit) = .empty;
    var by_symbol: std.StringHashMapUnmanaged(usize) = .empty;
    var values: std.array_hash_map.String(void) = .empty;
    var codecs: std.array_hash_map.String(void) = .empty;
    for (shares) |share| {
        for (share.functions) |unit| {
            const slot = by_symbol.getOrPut(scratch, unit.symbol) catch return error.OutOfMemory;
            if (slot.found_existing) {
                const previous = std.json.Stringify.valueAlloc(scratch, order.items[slot.value_ptr.*], .{}) catch return error.OutOfMemory;
                const next = std.json.Stringify.valueAlloc(scratch, unit, .{}) catch return error.OutOfMemory;
                if (!std.mem.eql(u8, previous, next)) return error.InvalidProgram;
                continue;
            }
            slot.value_ptr.* = order.items.len;
            order.append(scratch, unit) catch return error.OutOfMemory;
        }
        for (share.values) |name| values.put(scratch, try symbol(scratch, name), {}) catch return error.OutOfMemory;
        for (share.codecs) |name| codecs.put(scratch, try symbol(scratch, name), {}) catch return error.OutOfMemory;
    }
    for (order.items) |*unit| unit.test_dependencies = try completed(scratch, unit.test_dependencies, values.keys(), codecs.keys());
    const keep = try scratch.alloc(bool, order.items.len);
    @memset(keep, options.scope == .all);
    if (options.scope == .closure) {
        var pending: std.ArrayList(usize) = .empty;
        for (order.items, 0..) |unit, index| if (unit.@"export" != null) pending.append(scratch, index) catch return error.OutOfMemory;
        while (pending.pop()) |index| {
            if (keep[index]) continue;
            keep[index] = true;
            for (order.items[index].test_dependencies.dependencies) |dependency| {
                const next = by_symbol.get(dependency.symbol) orelse continue;
                if (!keep[next]) pending.append(scratch, next) catch return error.OutOfMemory;
            }
        }
    }
    var units: std.ArrayList(Unit) = .empty;
    for (order.items, keep) |unit, kept| if (kept) units.append(scratch, unit) catch return error.OutOfMemory;
    return std.json.Stringify.valueAlloc(allocator, Graph{ .schema = options.schema, .entry = options.entry, .functions = units.items }, .{}) catch error.OutOfMemory;
}

/// One share's metadata with the program-wide edges `describe` would have
/// added: `indirect` to every value target of an invoking body, `codec` to
/// every codec function when the program declares one.
fn completed(allocator: std.mem.Allocator, metadata: dependencies.Metadata, values: []const []const u8, codecs: []const []const u8) Error!dependencies.Metadata {
    var reasons: std.ArrayList([]const u8) = .empty;
    reasons.appendSlice(allocator, metadata.reasons) catch return error.OutOfMemory;
    var edges: std.ArrayList(dependencies.Dependency) = .empty;
    edges.appendSlice(allocator, metadata.dependencies) catch return error.OutOfMemory;
    const invokes = for (metadata.reasons) |reason| {
        if (std.mem.eql(u8, reason, "conservative-indirect-target-set")) break true;
    } else false;
    if (invokes) for (values) |target| try addEdge(allocator, &edges, target, .indirect);
    if (codecs.len != 0) {
        const reason = "conservative-codec-runtime-set";
        const present = for (reasons.items) |existing| {
            if (std.mem.eql(u8, existing, reason)) break true;
        } else false;
        if (!present) reasons.append(allocator, reason) catch return error.OutOfMemory;
        for (codecs) |target| try addEdge(allocator, &edges, target, .codec);
    }
    std.mem.sort(dependencies.Dependency, edges.items, {}, dependencyLess);
    std.mem.sort([]const u8, reasons.items, {}, stringLess);
    var out = metadata;
    out.dependencies = edges.items;
    out.reasons = reasons.items;
    return out;
}

fn addEdge(allocator: std.mem.Allocator, edges: *std.ArrayList(dependencies.Dependency), target: []const u8, kind: dependencies.Kind) Error!void {
    for (edges.items) |existing| if (existing.kind == kind and std.mem.eql(u8, existing.symbol, target)) return;
    edges.append(allocator, .{ .symbol = target, .kind = kind }) catch return error.OutOfMemory;
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
    // The address-taken set walks every body in the program, so only a
    // selection that invokes a function value pays for it.
    if (indirect) {
        const address_taken = try collectAddressTaken(allocator, program);
        defer allocator.free(address_taken);
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
    for (program.functions) |function| if (@import("invariant_callbacks.zig").isName(function.name)) {
        try appendUnique(allocator, &ids, function.id);
    };
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
    /// Every dependency's function, for a closure walk over the facts.
    ids: std.ArrayList(typed.FunctionId) = .empty,
    fn add(self: *DependencySet, program: typed.Program, id: typed.FunctionId, kind: dependencies.Kind) Error!void {
        const index = @backingInt(id);
        if (index >= program.functions.len) return error.InvalidProgram;
        self.ids.append(self.allocator, id) catch return error.OutOfMemory;
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
        self.ids.deinit(self.allocator);
    }
};

const FunctionFacts = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: typed.Program,
    catalog: *native_types.Catalog,
    /// Every address-taken function, collected on first use.
    address_taken: *?[]const typed.FunctionId,
    codecs: []const typed.FunctionId,

    /// One function's facts; every function it depends on is appended to `callees`.
    fn describe(self: FunctionFacts, function: typed.Function, callees: *std.ArrayList(typed.FunctionId)) Error!dependencies.Metadata {
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
                .statement => |id| {
                    // CONTRACT-INTERFACE-1: a contract clause checked in this
                    // body may be written outside its source region (an
                    // `@invariant` on a record it builds), so its text is
                    // part of the implementation identity.
                    const statement = self.program.statements[@backingInt(id)];
                    if (statement.data == .assertion and statement.data.assertion.kind != .statement) part(&hash, statement.data.assertion.message);
                    continue;
                },
            };
            try facts.add(node.ty);
            switch (node.data) {
                .call => |call| try deps.add(self.program, call.function, .call),
                .function_value => |value| try deps.add(self.program, value, .function_value),
                // EMBED-1: an embedded file is part of the implementation the test result depends on.
                .blob => |file| part(&hash, &file.digest),
                .invoke => {
                    try reasons.add("conservative-indirect-target-set");
                    const targets = self.address_taken.* orelse targets: {
                        const collected = try collectAddressTaken(self.allocator, self.program);
                        self.address_taken.* = collected;
                        break :targets collected;
                    };
                    for (targets) |id| try deps.add(self.program, id, .indirect);
                },
                else => {},
            }
        }
        if (function.policy.host != null) try reasons.add("host-call");
        const external_effects = function.policy.effects & ~dependencies.deterministic_effects;
        if (external_effects != 0) try reasons.add("external-effects");
        if (self.codecs.len != 0) {
            try reasons.add("conservative-codec-runtime-set");
            for (self.codecs) |id| try deps.add(self.program, id, .codec);
        }
        callees.appendSlice(self.allocator, deps.ids.items) catch return error.OutOfMemory;
        std.mem.sort(dependencies.Dependency, deps.items.items, {}, dependencyLess);
        std.mem.sort([]const u8, reasons.items.items, {}, stringLess);
        return .{
            .implementation_hash = std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.bytesToHex(hash.finalResult(), .lower)}) catch return error.OutOfMemory,
            .dependencies = deps.items.toOwnedSlice(self.allocator) catch return error.OutOfMemory,
            .cacheable = function.policy.host == null and external_effects == 0,
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
    const tokens = lexer.lexRange(allocator, src.bytes, .{ .start = start, .end = end }, &sink) catch |err| return mapDiagnosticError(err);
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
    part(hash, @tagName(function.signature.inferred.borrow_origin));
    switch (function.signature.inferred.borrow_origin) {
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
    hash.update(&[_]u8{ @intFromBool(function.signature.inferred.writes), @intFromBool(function.signature.inferred.external) });
    var storage_bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &storage_bytes, function.signature.inferred.caller_storage, .little);
    hash.update(&storage_bytes);
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

/// A share's unit for `name`, depending on `calls` by call and giving
/// `reasons`.
fn shareUnit(allocator: std.mem.Allocator, name: []const u8, calls: []const []const u8, reasons: []const []const u8, root: bool) !Unit {
    const edges = try allocator.alloc(dependencies.Dependency, calls.len);
    for (calls, edges) |callee, *edge| edge.* = .{ .symbol = try symbol(allocator, callee), .kind = .call };
    return .{
        .name = name,
        .symbol = try symbol(allocator, name),
        .@"export" = if (root) .{ .name = name } else null,
        .test_dependencies = .{ .implementation_hash = name, .dependencies = edges, .cacheable = true, .pure = true, .reasons = reasons },
    };
}

// spec: MODULE-TEST-1
test "merged shares add the program-wide indirect and codec edges and keep the roots' closure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Module `m` invokes a function value; module `n` takes one and declares a codec.
    const first: Share = .{
        .functions = &.{
            try shareUnit(a, "m::test_it", &.{"m::apply"}, &.{}, true),
            try shareUnit(a, "m::apply", &.{}, &.{"conservative-indirect-target-set"}, false),
        },
        .values = &.{},
        .codecs = &.{},
    };
    const second: Share = .{
        .functions = &.{
            try shareUnit(a, "n::target", &.{}, &.{}, false),
            try shareUnit(a, "n::unused", &.{}, &.{}, false),
            try shareUnit(a, "m::apply", &.{}, &.{"conservative-indirect-target-set"}, false),
        },
        .values = &.{"n::target"},
        .codecs = &.{"n::decode"},
    };
    const merged = try mergeShares(a, &.{ first, second }, .{ .schema = "{}", .entry = "", .scope = .closure });
    const graph = try std.json.parseFromSliceLeaky(Graph, a, merged, .{ .allocate = .alloc_always });
    // The first share's `apply` wins; `unused` is reached by no root.
    try std.testing.expectEqual(@as(usize, 3), graph.functions.len);
    const apply = graph.functions[1].test_dependencies;
    try std.testing.expectEqualStrings("m::apply", graph.functions[1].name);
    try std.testing.expectEqual(@as(usize, 2), apply.dependencies.len);
    try std.testing.expectEqual(dependencies.Kind.codec, apply.dependencies[0].kind);
    try std.testing.expectEqual(dependencies.Kind.indirect, apply.dependencies[1].kind);
    try std.testing.expectEqualStrings(try symbol(a, "n::target"), apply.dependencies[1].symbol);
    try std.testing.expectEqualStrings("conservative-codec-runtime-set", apply.reasons[0]);
    try std.testing.expectEqualStrings("n::target", graph.functions[2].name);
}

// spec-case: MODULE-TEST-1
test "merged shares reject conflicting facts for one shared specialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try shareUnit(a, "m::specialization", &.{}, &.{}, true);
    var changed = first;
    changed.test_dependencies.implementation_hash = "different body";
    const shares = [_]Share{
        .{ .functions = &.{first}, .values = &.{}, .codecs = &.{} },
        .{ .functions = &.{changed}, .values = &.{}, .codecs = &.{} },
    };
    try std.testing.expectError(error.InvalidProgram, mergeShares(a, &shares, .{ .schema = "", .entry = "", .scope = .all }));
}

test "facts symbols are stable and length bounded" {
    const first = try symbol(std.testing.allocator, "main::test_a");
    defer std.testing.allocator.free(first);
    const second = try symbol(std.testing.allocator, "main::test_a");
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.startsWith(u8, first, "myl_f_"));
}

// spec-case: RETURN-BORROW-1
test "native function fact key changes with physical return origin" {
    const a = std.testing.allocator;
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0) };
    var catalog = try native_types.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    var function: typed.Function = .{
        .scope = .{ .body = @fromBackingInt(0) },
        .id = @fromBackingInt(0),
        .name = "accessor",
        .declaration = .{ .start = 0, .end = 0 },
    };
    function.signature.return_origin = .fresh;
    var first = Sha.init(.{});
    function.signature.inferred.borrow_origin = .{ .params = &.{0} };
    try hashSignature(&first, a, program, function, &catalog);
    var second = Sha.init(.{});
    function.signature.inferred.borrow_origin = .fresh;
    try hashSignature(&second, a, program, function, &catalog);
    var first_digest: [32]u8 = undefined;
    var second_digest: [32]u8 = undefined;
    first.final(&first_digest);
    second.final(&second_digest);
    try std.testing.expect(!std.mem.eql(u8, &first_digest, &second_digest));
}

// spec-case: MUT-REBIND-CALLER-1
test "native function fact key changes with caller storage ABI" {
    const a = std.testing.allocator;
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0) };
    var catalog = try native_types.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    var function: typed.Function = .{
        .scope = .{ .body = @fromBackingInt(0) },
        .id = @fromBackingInt(0),
        .name = "accessor",
        .declaration = .{ .start = 0, .end = 0 },
    };
    var first = Sha.init(.{});
    function.signature.inferred.caller_storage = 1;
    try hashSignature(&first, a, program, function, &catalog);
    var second = Sha.init(.{});
    function.signature.inferred.caller_storage = 0;
    try hashSignature(&second, a, program, function, &catalog);
    var first_digest: [32]u8 = undefined;
    var second_digest: [32]u8 = undefined;
    first.final(&first_digest);
    second.final(&second_digest);
    try std.testing.expect(!std.mem.eql(u8, &first_digest, &second_digest));
}

// spec-case: NATIVE-TEST-6
test "checked facts reject roots outside the checked function table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "main.my", "");
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0) };
    const roots = [_]typed.FunctionId{@fromBackingInt(0)};
    try std.testing.expectError(error.InvalidProgram, render(a, src, program, &roots, "{}", .all));
}
