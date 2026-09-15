//! Per-function semantic dependencies and stable declaration identities.
//!
//! C1 replaces whole-program eligibility with per-function eligibility. Each
//! ordinary declaration carries a stable identity (defining source segment plus
//! declared spelling, never a numeric catalog ordinal) and a dependency digest
//! over the declarations its signature and body actually reference. A cached
//! body is reusable only when its own bytes, its declaration region and its
//! dependency digest are all unchanged; otherwise the query is a miss.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const nominal = @import("nominal_type_syntax.zig");
const Hash = std.crypto.hash.sha2.Sha256;

/// Domain for per-function dependency digests. Bump when the tracked dependency
/// model changes so stale entries are never admitted.
pub const functions_domain = "semantic-functions-v4";
/// Domain for the generic-specialization key primitive.
pub const specialization_domain = "semantic-specialization-v1";

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
    /// Per-origin module/import directive digest.
    import_digests: [][32]u8,
    /// Whole-program nominal-syntax observation retained for compatibility with
    /// the previous conservative gate. Per-function dependencies no longer use
    /// it to disable unrelated ordinary bodies.
    nominal_syntax: bool,
};

/// Build per-function dependency facts after declaration/type collection but
/// before checking any body. `records` is accepted for interface compatibility;
/// dependency fingerprints are derived from syntax so they stay stable even
/// when declaration order changes.
pub fn prepare(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, records: []const typed.Record, contract: []const u8) error{ OutOfMemory, InternalError }!Prepared {
    _ = records;
    var contract_sha256: [32]u8 = undefined;
    Hash.hash(contract, &contract_sha256, .{});

    const nominal_syntax = nominal.present(program);
    const module_count: usize = if (src.origins.len == 0) 1 else src.origins.len;
    const import_digests = try allocator.alloc([32]u8, module_count);
    for (import_digests, 0..) |*digest, module| digest.* = importDigest(src, module);

    var builder = try Builder.init(allocator, src, program);
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
        keys[i] = try functionKey(allocator, src, function);
        const module = moduleOf(src, function.name);
        contexts[i] = try builder.context(function, keys[i], contract_sha256, import_digests[module]);
        if (function.signature.type_parameters.len == 0) try ordinary.append(allocator, i);
    }
    return .{
        .bodies = bodies,
        .regions = regions,
        .keys = keys,
        .contexts = contexts,
        .ordinary_ast = try ordinary.toOwnedSlice(allocator),
        .import_digests = import_digests,
        .nominal_syntax = nominal_syntax,
    };
}

/// Canonical key for one generic specialization. This is a primitive for a future
/// reuse engine; `prepare` deliberately keeps generic templates on the fresh path.
pub fn specializationKey(
    allocator: std.mem.Allocator,
    template_identity: []const u8,
    arguments: []const []const u8,
    provider: []const u8,
    target_abi: []const u8,
    compiler_identity: []const u8,
) error{OutOfMemory}![]const u8 {
    var hash = Hash.init(.{});
    hash.update(specialization_domain);
    frame(&hash, template_identity);
    frame(&hash, provider);
    frame(&hash, target_abi);
    frame(&hash, compiler_identity);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, arguments.len, .little);
    hash.update(&count);
    for (arguments) |argument| frame(&hash, argument);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch error.OutOfMemory;
}

/// Stable identity of one ordinary function declaration. Never a catalog index.
fn functionKey(allocator: std.mem.Allocator, src: source.Source, function: ast.Function) std.mem.Allocator.Error![]const u8 {
    const owner = if (function.policy.owner) |owner_span| src.text(owner_span) else "";
    return std.fmt.allocPrint(allocator, "fn\x1f{d}\x1f{s}\x1f{s}", .{ moduleOf(src, function.name), owner, src.text(function.name) });
}

const DeclKind = enum(u4) { function = 0, record = 1, domain = 2, variant = 3, alias = 4, constraint = 5, resource = 6 };

fn declKey(kind: DeclKind, index: usize) u64 {
    return (@as(u64, @backingInt(kind)) << 32) | @as(u64, @as(u32, @truncate(index)));
}

/// Lexical declaration table and memoized contract fingerprints used to compute
/// per-function dependency digests.
const Builder = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: std.StringHashMapUnmanaged(std.ArrayList(u64)) = .empty,
    memo: std.AutoHashMapUnmanaged(u64, [32]u8) = .empty,
    active: std.AutoHashMapUnmanaged(u64, void) = .empty,

    fn init(allocator: std.mem.Allocator, src: source.Source, program: ast.Program) error{OutOfMemory}!Builder {
        var self: Builder = .{ .allocator = allocator, .src = src, .program = program };
        errdefer self.deinit();
        for (program.functions, 0..) |function, i| {
            try self.register(src.text(function.name), declKey(.function, i));
            if (function.policy.owner) |owner| try self.register(src.text(owner), declKey(.function, i));
        }
        for (program.types.records, 0..) |record, i| try self.register(src.text(record.name), declKey(.record, i));
        for (program.types.domains, 0..) |domain, i| try self.register(src.text(domain.name), declKey(.domain, i));
        for (program.types.resources, 0..) |domain, i| try self.register(src.text(domain.name), declKey(.resource, i));
        for (program.types.variants, 0..) |variant, i| try self.register(src.text(variant.name), declKey(.variant, i));
        for (program.types.expressions.aliases, 0..) |alias, i| try self.register(src.text(alias.name), declKey(.alias, i));
        for (program.types.constraints, 0..) |constraint, i| try self.register(src.text(constraint.name), declKey(.constraint, i));
        return self;
    }

    fn deinit(self: *Builder) void {
        var iterator = self.names.iterator();
        while (iterator.next()) |entry| entry.value_ptr.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.memo.deinit(self.allocator);
        self.active.deinit(self.allocator);
    }

    fn register(self: *Builder, name: []const u8, key: u64) error{OutOfMemory}!void {
        if (name.len == 0) return;
        const entry = try self.names.getOrPut(self.allocator, name);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        for (entry.value_ptr.items) |existing| if (existing == key) return;
        try entry.value_ptr.append(self.allocator, key);
    }

    /// Dependency digest for one declaration: its own contract plus the
    /// fingerprints of declarations its signature (and, for constants, body)
    /// references.
    fn context(self: *Builder, function: ast.Function, key: []const u8, contract: [32]u8, imports: [32]u8) error{ OutOfMemory, InternalError }![32]u8 {
        const body = self.program.statements.items[@backingInt(function.body)].span;
        const start = lineStart(self.src.bytes, function.name.start);
        if (start > body.start) return error.InternalError;
        var hash = Hash.init(.{});
        hash.update(functions_domain);
        hash.update(&contract);
        hash.update(&imports);
        frame(&hash, key);
        frame(&hash, self.src.bytes[start..body.start]);
        var collector = Collector.init(self.allocator, self.src, self.program);
        defer collector.deinit();
        // The whole declaration participates in the dependency digest: the
        // signature/effect ceiling and every declaration name the body uses.
        collector.collectValue(ast.Function, function) catch |err| return err;
        self.mixNames(&hash, &collector.names, null) catch |err| return err;
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
        frame(&hash, "decl-v2");
        frame(&hash, @tagName(kind));
        var collector = Collector.init(self.allocator, self.src, self.program);
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
                    collector.collectValue(ast.Function, function) catch |err| return err;
                } else {
                    collector.collectValue(ast.FunctionSignature, function.signature) catch |err| return err;
                    collector.collectValue(ast.FunctionPolicy, function.policy) catch |err| return err;
                    collector.addSpan(function.name) catch |err| return err;
                }
            },
            .record => {
                self.mixExport(&hash, self.program.types.records[index].name);
                collector.collectValue(ast.Record, self.program.types.records[index]) catch |err| return err;
            },
            .domain => {
                self.mixExport(&hash, self.program.types.domains[index].name);
                collector.collectValue(ast.Domain, self.program.types.domains[index]) catch |err| return err;
            },
            .resource => {
                self.mixExport(&hash, self.program.types.resources[index].name);
                collector.collectValue(ast.Domain, self.program.types.resources[index]) catch |err| return err;
            },
            .variant => {
                self.mixExport(&hash, self.program.types.variants[index].name);
                collector.collectValue(ast.Variants, self.program.types.variants[index]) catch |err| return err;
            },
            .alias => {
                self.mixExport(&hash, self.program.types.expressions.aliases[index].name);
                collector.collectValue(ast.TypeAlias, self.program.types.expressions.aliases[index]) catch |err| return err;
            },
            .constraint => {
                self.mixExport(&hash, self.program.types.constraints[index].name);
                collector.collectValue(ast.Constraint, self.program.types.constraints[index]) catch |err| return err;
            },
        }
        self.mixNames(&hash, &collector.names, key) catch |err| return err;
        const fingerprint = hash.finalResult();
        try self.memo.put(self.allocator, key, fingerprint);
        return fingerprint;
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
            const bare = lastComponent(declared) orelse declared;
            if (std.mem.eql(u8, declared, name) or std.mem.eql(u8, bare, name)) frame(&hash, trimmed);
        }
        return hash.finalResult();
    }

    /// Hash a deterministic, sorted view of every referenced name. Names that do
    /// not resolve to a declaration are recorded as explicit negative lookups so
    /// that introducing the name later forces a miss.
    fn mixNames(self: *Builder, hash: *Hash, names: *const std.StringHashMapUnmanaged(void), skip: ?u64) error{OutOfMemory}!void {
        const keys = try self.allocator.alloc([]const u8, names.count());
        defer self.allocator.free(keys);
        var iterator = names.keyIterator();
        var count: usize = 0;
        while (iterator.next()) |name| : (count += 1) keys[count] = name.*;
        std.mem.sort([]const u8, keys, {}, lessString);
        for (keys) |text| {
            var found = try self.mixName(hash, text, skip);
            if (lastComponent(text)) |bare| if (!std.mem.eql(u8, bare, text)) {
                if (try self.mixName(hash, bare, skip)) found = true;
            };
            if (!found) {
                frame(hash, "negative");
                frame(hash, text);
            }
        }
    }

    fn mixName(self: *Builder, hash: *Hash, text: []const u8, skip: ?u64) error{OutOfMemory}!bool {
        const declarations = self.names.get(text) orelse return false;
        var any = false;
        for (declarations.items) |key| {
            if (skip) |self_key| if (self_key == key) continue;
            const fingerprint = try self.declFingerprint(key);
            frame(hash, "reference");
            hash.update(&fingerprint);
            any = true;
        }
        return any;
    }
};

/// Collect every identifier-like span in a syntax subtree, following expression
/// and statement identities without revisiting shared nodes.
const Collector = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    names: std.StringHashMapUnmanaged(void) = .empty,
    visited_nodes: std.AutoHashMapUnmanaged(usize, void) = .empty,
    visited_statements: std.AutoHashMapUnmanaged(usize, void) = .empty,

    fn init(allocator: std.mem.Allocator, src: source.Source, program: ast.Program) Collector {
        return .{ .allocator = allocator, .src = src, .program = program };
    }

    fn deinit(self: *Collector) void {
        self.names.deinit(self.allocator);
        self.visited_nodes.deinit(self.allocator);
        self.visited_statements.deinit(self.allocator);
    }

    fn addSpan(self: *Collector, span: source.Span) error{OutOfMemory}!void {
        if (span.end <= span.start or span.end > self.src.bytes.len) return;
        const text = self.src.bytes[span.start..span.end];
        if (!identifierLike(text)) return;
        try self.names.put(self.allocator, text, {});
    }

    fn collectValue(self: *Collector, comptime T: type, value: T) error{OutOfMemory}!void {
        if (T == source.Span) return self.addSpan(value);
        if (T == ast.NodeId) {
            const id = @backingInt(value);
            if (id >= self.program.nodes.items.len) return;
            const entry = try self.visited_nodes.getOrPut(self.allocator, id);
            if (entry.found_existing) return;
            return self.collectValue(ast.Node, self.program.nodes.items[id]);
        }
        if (T == ast.StatementId) {
            const id = @backingInt(value);
            if (id >= self.program.statements.items.len) return;
            const entry = try self.visited_statements.getOrPut(self.allocator, id);
            if (entry.found_existing) return;
            return self.collectValue(ast.Statement, self.program.statements.items[id]);
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
fn lastComponent(text: []const u8) ?[]const u8 {
    const at = std.mem.lastIndexOfAny(u8, text, ".:") orelse return null;
    if (at + 1 >= text.len) return null;
    return text[at + 1 ..];
}
fn lessString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
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
fn importDigest(src: source.Source, module: usize) [32]u8 {
    const bytes = if (src.origins.len == 0) src.bytes else src.origins[module].original.bytes;
    var hash = Hash.init(.{});
    frame(&hash, "imports-v1");
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "module ") or std.mem.startsWith(u8, trimmed, "import ")) frame(&hash, trimmed);
    }
    return hash.finalResult();
}
fn frame(hash: *Hash, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}
