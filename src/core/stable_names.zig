//! Stable names for what Core IR refers to (docs/design/incremental-engine.md §17.1, part 2 step G3a1).
//!
//! Core IR holds positions: a function is an index into `Module.functions`, a compound type an index into
//! `Module.compounds`. An index moves whenever anything earlier in discovery order is added or removed, so a stored
//! result that holds one is wrong after an unrelated edit. This file is the vocabulary that replaces positions in
//! anything stored: a module is named by its path, a nominal record by its module and name, a function by what
//! created it. Positions exist only inside one process, assigned when a program is assembled (`op_log.zig`).
const std = @import("std");
const ir = @import("ir.zig");

/// A source module, named by its path. The path is the key path of the module's source, which is relative to the
/// project root for every module of a project build.
pub const ModuleName = []const u8;

/// A nominal record or union, as the front end declares it: its module and its checked name. Generic instances carry
/// their type arguments in the name (`Box<i64>`). `ordinal` tells apart records that share both, by declaration order
/// among them; it is 0 for a record whose module and name are unique, which is every record of the corpora measured.
pub const RecordName = struct {
    module: ModuleName,
    name: []const u8,
    ordinal: u32 = 0,

    /// Whether two names are the same record.
    pub fn eql(a: RecordName, b: RecordName) bool {
        return a.ordinal == b.ordinal and std.mem.eql(u8, a.name, b.name) and std.mem.eql(u8, a.module, b.module);
    }

    /// The canonical order: module, then name, then ordinal.
    pub fn lessThan(a: RecordName, b: RecordName) bool {
        return switch (std.mem.order(u8, a.module, b.module)) {
            .lt => true,
            .gt => false,
            .eq => switch (std.mem.order(u8, a.name, b.name)) {
                .lt => true,
                .gt => false,
                .eq => a.ordinal < b.ordinal,
            },
        };
    }

    /// A digest of the whole name, for what is keyed by names rather than positions (`ir.Module.nominal`).
    pub fn digest(self: RecordName) [32]u8 {
        var h = @import("fast_blake3.zig").Blake3.init(.{});
        h.update(std.mem.asBytes(&@as(u64, self.module.len)));
        h.update(self.module);
        h.update(std.mem.asBytes(&@as(u64, self.name.len)));
        h.update(self.name);
        h.update(std.mem.asBytes(&self.ordinal));
        var out: [32]u8 = undefined;
        h.final(&out);
        return out;
    }

    /// A hash that agrees with `eql`, for tables keyed by record name.
    pub fn hash(self: RecordName) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(self.module);
        h.update("\x00");
        h.update(self.name);
        h.update(std.mem.asBytes(&self.ordinal));
        return h.final();
    }
};

/// A hash map context for tables keyed by `RecordName`.
pub const RecordNameContext = struct {
    /// Hash a record name.
    pub fn hash(_: RecordNameContext, key: RecordName) u64 {
        return key.hash();
    }
    /// Compare two record names.
    pub fn eql(_: RecordNameContext, a: RecordName, b: RecordName) bool {
        return a.eql(b);
    }
};

/// The name prefix of an owned copy helper: `myl_core_owned_copy_<type key>`. The leaf of the import graph that the canonical form
/// (`canonical_ir.zig`) and the emitter both read it from.
pub const owned_copy_prefix = "myl_core_owned_copy_";

/// The families of compiler-made functions. Each family is named by its creating function and an ordinal local to
/// that function, never by a position in a program-wide table (G0b LW-13..20). Until G3a3 the families still spell
/// their legacy names; `generatedRole` recognizes those spellings.
pub const GeneratedRole = enum {
    /// A function value of a view-ABI function, `<callee>#value`.
    value_adapter,
    /// The thunk a task runs, `<task.thunk.K@creator>`: K counts the creator's thunks.
    task_thunk,
    /// The worker of `parallel.map`, `<parallel.map.worker.K@creator>`.
    parallel_worker,
    /// A render helper, `myl_core_show_<id>`.
    show,
    /// A render shape authorization, `myl_core_render_shape_<string>_<id>`.
    render_shape,
    /// The borrowed structural equality marker, `myl_core_borrow_equal_v1_<type>`.
    borrow_equal,
    /// A provider pin or keepalive marker (`myl_core_provider_pin_`, `myl_core_borrowed_provider_v1_` and the optional
    /// form).
    provider_pin,
    /// A borrow selection marker, `myl_core_borrow_select_v1_`.
    borrow_selection,
    /// A min/max or default choice marker, `myl_core_borrow_choice_v1_`.
    choice,
    /// An owned copy helper, `myl_core_owned_copy_<type>`.
    owned_copy,
    /// An adapter of `json.encode` or `json.decode`, `<json.encode.K@creator>` or `<json.decode.K@creator>`.
    json_codec,
};

/// The legacy spelling of each generated family: a name starting with `prefix` is made by `role`.
pub const role_prefixes = [_]struct { prefix: []const u8, role: GeneratedRole }{
    .{ .prefix = "<task.thunk.", .role = .task_thunk },
    .{ .prefix = "<parallel.map.worker.", .role = .parallel_worker },
    .{ .prefix = "myl_core_show_", .role = .show },
    .{ .prefix = "myl_core_render_shape_", .role = .render_shape },
    .{ .prefix = "myl_core_borrow_equal_v1_", .role = .borrow_equal },
    .{ .prefix = "myl_core_provider_pin_", .role = .provider_pin },
    .{ .prefix = "myl_core_borrowed_provider_v1_", .role = .provider_pin },
    .{ .prefix = "myl_core_borrowed_optional_provider_v1_", .role = .provider_pin },
    .{ .prefix = "myl_core_borrow_select_v1_", .role = .borrow_selection },
    .{ .prefix = "myl_core_borrow_choice_v1_", .role = .choice },
    .{ .prefix = owned_copy_prefix, .role = .owned_copy },
    .{ .prefix = "<json.encode.", .role = .json_codec },
    .{ .prefix = "<json.decode.", .role = .json_codec },
};

/// The family of a compiler-made function's legacy name, or null for any other name.
pub fn generatedRole(name: []const u8) ?GeneratedRole {
    if (std.mem.endsWith(u8, name, "#value")) return .value_adapter;
    for (role_prefixes) |entry| if (std.mem.startsWith(u8, name, entry.prefix)) return entry.role;
    return null;
}

/// A function's stable identity. It is never a position.
pub const FunctionName = union(enum) {
    /// A checked source function: its module-qualified name, which carries a generic instance's type arguments.
    source: []const u8,
    /// A runtime or extern C function: its symbol, and a digest of its signature's structure. Several runtime helpers
    /// share a symbol and differ in signature (G0f U1: 38 of 3,731 functions at 99k).
    runtime: Runtime,
    /// A compiler-made function: the checked name of the function whose lowering made it, its family and its ordinal
    /// among that function's functions of the family.
    generated: Generated,

    /// The identity of a runtime function.
    pub const Runtime = struct { symbol: []const u8, signature: u64 };
    /// The identity of a compiler-made function.
    pub const Generated = struct { creator: []const u8, role: GeneratedRole, ordinal: u32 };

    /// Whether two names are the same function.
    pub fn eql(a: FunctionName, b: FunctionName) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .source => |name| std.mem.eql(u8, name, b.source),
            .runtime => |r| r.signature == b.runtime.signature and std.mem.eql(u8, r.symbol, b.runtime.symbol),
            .generated => |g| g.role == b.generated.role and g.ordinal == b.generated.ordinal and std.mem.eql(u8, g.creator, b.generated.creator),
        };
    }

    /// The canonical order of functions (G-D2): source functions by name, then runtime functions by symbol and
    /// signature, then compiler-made functions by creator, family and ordinal.
    pub fn lessThan(a: FunctionName, b: FunctionName) bool {
        const left = @backingInt(std.meta.activeTag(a));
        const right = @backingInt(std.meta.activeTag(b));
        if (left != right) return left < right;
        return switch (a) {
            .source => |name| std.mem.lessThan(u8, name, b.source),
            .runtime => |r| switch (std.mem.order(u8, r.symbol, b.runtime.symbol)) {
                .lt => true,
                .gt => false,
                .eq => r.signature < b.runtime.signature,
            },
            .generated => |g| switch (std.mem.order(u8, g.creator, b.generated.creator)) {
                .lt => true,
                .gt => false,
                .eq => if (g.role != b.generated.role) @backingInt(g.role) < @backingInt(b.generated.role) else g.ordinal < b.generated.ordinal,
            },
        };
    }
};

/// The identity of a type that names no position: 128 bits of a hash of its structure, with a nominal record by its name.
pub const TypeKey = [16]u8;

/// Computes `TypeKey`s of the types of one module, remembering each. Two types have the same key when they have the same
/// structure and, for a nominal record or union, the same `RecordName`; the ids of the types in the module do not
/// enter it, so a helper named by a key has the same name wherever the program's tables put the type.
pub const TypeKeys = struct {
    /// The names of the module's nominal types; without it every compound is taken to be structural.
    nominals: ?*const std.AutoHashMapUnmanaged(ir.Type, RecordName) = null,
    memo: std.AutoHashMapUnmanaged(ir.Type, TypeKey) = .empty,

    /// The key of `ty`. Cycles of types pass through a nominal type, which is keyed by name, so the walk is finite.
    pub fn key(self: *TypeKeys, a: std.mem.Allocator, module: *const ir.Module, ty: ir.Type) std.mem.Allocator.Error!TypeKey {
        var hash = std.crypto.hash.Blake3.init(.{});
        if (!ty.isCompound() or !module.valid(ty)) {
            hash.update("leaf");
            hash.update(std.mem.asBytes(&ty));
            return finish(&hash);
        }
        if (self.memo.get(ty)) |known| return known;
        if (self.nominals) |named| if (named.get(ty)) |record| {
            hash.update("nominal");
            hash.update(record.module);
            hash.update("\x00");
            hash.update(record.name);
            hash.update("\x00");
            hash.update(std.mem.asBytes(&record.ordinal));
            const made = finish(&hash);
            try self.memo.put(a, ty, made);
            return made;
        };
        try self.compound(a, module, &hash, module.compound(ty));
        const made = finish(&hash);
        try self.memo.put(a, ty, made);
        return made;
    }

    fn finish(hash: *std.crypto.hash.Blake3) TypeKey {
        var out: TypeKey = undefined;
        hash.final(&out);
        return out;
    }

    fn child(self: *TypeKeys, a: std.mem.Allocator, module: *const ir.Module, hash: *std.crypto.hash.Blake3, ty: ir.Type) std.mem.Allocator.Error!void {
        hash.update(&try self.key(a, module, ty));
    }

    fn compound(self: *TypeKeys, a: std.mem.Allocator, module: *const ir.Module, hash: *std.crypto.hash.Blake3, shape: ir.Compound) std.mem.Allocator.Error!void {
        hash.update("structural");
        hash.update(&.{@backingInt(std.meta.activeTag(shape))});
        switch (shape) {
            .list, .list_view, .box, .borrowed => |inner| try self.child(a, module, hash, inner),
            .record, .@"union" => |parts| {
                hash.update(std.mem.asBytes(&parts.len));
                for (parts) |part| try self.child(a, module, hash, part);
            },
            .dict => |dict| {
                try self.child(a, module, hash, dict.key);
                try self.child(a, module, hash, dict.value);
            },
            .array => |array| {
                try self.child(a, module, hash, array.elem);
                hash.update(std.mem.asBytes(&array.n));
                hash.update(&.{@intFromBool(array.vector)});
            },
            .@"fn" => |function| try self.signature(a, module, hash, function),
        }
    }

    /// Mix a signature's structure into `hash`: its types by key and its passing and borrowing contracts.
    pub fn signature(self: *TypeKeys, a: std.mem.Allocator, module: *const ir.Module, hash: *std.crypto.hash.Blake3, value: ir.Signature) std.mem.Allocator.Error!void {
        hash.update(std.mem.asBytes(&value.params.len));
        for (value.params) |param| try self.child(a, module, hash, param);
        try self.child(a, module, hash, value.ret);
        hash.update(&.{@backingInt(value.linkage)});
        hash.update(std.mem.asBytes(&value.passing.owned));
        hash.update(std.mem.asBytes(&value.passing.consumes));
        hash.update(std.mem.asBytes(&value.passing.views));
        hash.update(std.mem.sliceAsBytes(value.passing.extra_owned));
        hash.update(std.mem.sliceAsBytes(value.passing.extra_consumes));
        hash.update(std.mem.sliceAsBytes(value.passing.extra_views));
        projection(hash, value.borrow.path);
        for (value.borrow.sources) |source| switch (source) {
            .argument => |position| {
                hash.update("argument");
                hash.update(std.mem.asBytes(&position));
            },
            .result => |path| {
                hash.update("result");
                projection(hash, path);
            },
        };
    }

    fn projection(hash: *std.crypto.hash.Blake3, path: []const ir.BorrowProjection) void {
        hash.update(std.mem.asBytes(&path.len));
        for (path) |step| switch (step) {
            .field => |index| {
                hash.update("field");
                hash.update(std.mem.asBytes(&index));
            },
            .payload => |tag| {
                hash.update("payload");
                hash.update(std.mem.asBytes(&tag));
            },
        };
    }
};

/// The text of a key: 32 lower-case hexadecimal digits, for a helper's name.
pub fn keyText(key: TypeKey) [32]u8 {
    return std.fmt.bytesToHex(key, .lower);
}

/// Whether `text` is `count` keys' texts joined by `_`: what follows a helper family's prefix in a helper's name.
pub fn isKeyList(text: []const u8, count: usize) bool {
    const width = 32;
    if (count == 0 or text.len != count * width + (count - 1)) return false;
    var at: usize = 0;
    for (0..count) |index| {
        if (index != 0) {
            if (text[at] != '_') return false;
            at += 1;
        }
        for (text[at..][0..width]) |digit| if (!std.ascii.isDigit(digit) and (digit < 'a' or digit > 'f')) return false;
        at += width;
    }
    return true;
}

/// The name of a compiler helper of the family `prefix` for `types`: the prefix, then the text of each type's key,
/// joined by `_`. The name holds no position, so a function that asks for the helper in another program asks for the
/// same name.
pub fn helperName(a: std.mem.Allocator, keys: *TypeKeys, module: *const ir.Module, prefix: []const u8, types: []const ir.Type) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, prefix);
    for (types, 0..) |ty, index| {
        if (index != 0) try out.append(a, '_');
        try out.appendSlice(a, &keyText(try keys.key(a, module, ty)));
    }
    return out.items;
}

/// The three sorts of unit every stage after the front end takes as its argument (§17.1).
pub const UnitName = union(enum) {
    /// One source module.
    module: ModuleName,
    /// A generic template with its type arguments: the template's name and a digest of the arguments' structure.
    instance: struct { template: []const u8, arguments: u64 },
    /// A runtime helper, by its symbol and signature.
    helper: FunctionName.Runtime,

    /// Whether two names are the same unit.
    pub fn eql(a: UnitName, b: UnitName) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .module => |path| std.mem.eql(u8, path, b.module),
            .instance => |i| i.arguments == b.instance.arguments and std.mem.eql(u8, i.template, b.instance.template),
            .helper => |h| h.signature == b.helper.signature and std.mem.eql(u8, h.symbol, b.helper.symbol),
        };
    }
};

/// The unit a function with `name` and `module` belongs to: a generic instance (its checked name carries `[`) is a
/// unit of its own, attributed to the template's module; every other source function belongs to its module. The
/// template name is the name up to its type arguments.
pub fn unitOf(name: []const u8, module: ModuleName) UnitName {
    if (std.mem.indexOfScalar(u8, name, '[')) |open| return .{ .instance = .{ .template = name[0..open], .arguments = std.hash.Wyhash.hash(0, name[open..]) } };
    return .{ .module = module };
}

test "stable names: record names compare, order and hash by module, name and ordinal" {
    const a: RecordName = .{ .module = "a.selka", .name = "Pair" };
    const same: RecordName = .{ .module = "a.selka", .name = "Pair" };
    const other_module: RecordName = .{ .module = "b.selka", .name = "Pair" };
    const second: RecordName = .{ .module = "a.selka", .name = "Pair", .ordinal = 1 };
    try std.testing.expect(a.eql(same));
    try std.testing.expectEqual(a.hash(), same.hash());
    try std.testing.expect(!a.eql(other_module) and !a.eql(second));
    try std.testing.expect(a.lessThan(other_module) and a.lessThan(second) and !second.lessThan(a));
    try std.testing.expect(!a.lessThan(same));
}

test "stable names: function names order source before runtime before generated, then by name and signature" {
    const source_a: FunctionName = .{ .source = "app::a" };
    const source_b: FunctionName = .{ .source = "app::b" };
    const helper_low: FunctionName = .{ .runtime = .{ .symbol = "myl_core_x", .signature = 1 } };
    const helper_high: FunctionName = .{ .runtime = .{ .symbol = "myl_core_x", .signature = 2 } };
    const made: FunctionName = .{ .generated = .{ .creator = "app::a", .role = .task_thunk, .ordinal = 0 } };
    const made_next: FunctionName = .{ .generated = .{ .creator = "app::a", .role = .task_thunk, .ordinal = 1 } };
    try std.testing.expect(source_a.lessThan(source_b) and source_b.lessThan(helper_low));
    try std.testing.expect(helper_low.lessThan(helper_high) and helper_high.lessThan(made));
    try std.testing.expect(made.lessThan(made_next) and !made_next.lessThan(made));
    try std.testing.expect(source_a.eql(.{ .source = "app::a" }) and !source_a.eql(source_b) and !helper_low.eql(helper_high));
    try std.testing.expect(made.eql(.{ .generated = .{ .creator = "app::a", .role = .task_thunk, .ordinal = 0 } }));
}

test "stable names: the legacy spellings of the generated families are recognized" {
    try std.testing.expectEqual(GeneratedRole.task_thunk, generatedRole("<task.thunk.12>").?);
    try std.testing.expectEqual(GeneratedRole.parallel_worker, generatedRole("<parallel.map.worker.3>").?);
    try std.testing.expectEqual(GeneratedRole.value_adapter, generatedRole("app::f#value").?);
    try std.testing.expectEqual(GeneratedRole.show, generatedRole("myl_core_show_4_p20").?);
    try std.testing.expectEqual(GeneratedRole.render_shape, generatedRole("myl_core_render_shape_9_4_p20").?);
    try std.testing.expectEqual(GeneratedRole.borrow_equal, generatedRole("myl_core_borrow_equal_v1_21").?);
    try std.testing.expectEqual(GeneratedRole.provider_pin, generatedRole("myl_core_provider_pin_21").?);
    try std.testing.expectEqual(GeneratedRole.provider_pin, generatedRole("myl_core_borrowed_optional_provider_v1_21").?);
    try std.testing.expectEqual(GeneratedRole.borrow_selection, generatedRole("myl_core_borrow_select_v1_3_4").?);
    try std.testing.expectEqual(GeneratedRole.choice, generatedRole("myl_core_borrow_choice_v1_min_3_4").?);
    try std.testing.expectEqual(GeneratedRole.owned_copy, generatedRole("myl_core_owned_copy_21").?);
    try std.testing.expectEqual(GeneratedRole.json_codec, generatedRole("<json.decode.2@json::decode[app::Store]>").?);
    try std.testing.expectEqual(GeneratedRole.json_codec, generatedRole("<json.encode.0@json::encode[int]>").?);
    try std.testing.expectEqual(@as(?GeneratedRole, null), generatedRole("app::main"));
    try std.testing.expectEqual(@as(?GeneratedRole, null), generatedRole("myl_core_str_len"));
}

test "stable names: a type key follows structure and record names, not table positions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Two modules that made the same types in a different order, and a second record with the same fields.
    var first: ir.Module = .{};
    const list_a = try first.intern(a, .{ .list = .str });
    const boxed_a = try first.intern(a, .{ .box = list_a });
    var second: ir.Module = .{};
    _ = try second.intern(a, .{ .list = .i64 });
    const list_b = try second.intern(a, .{ .list = .str });
    const boxed_b = try second.intern(a, .{ .box = list_b });
    var keys_a: TypeKeys = .{};
    var keys_b: TypeKeys = .{};
    try std.testing.expectEqual(try keys_a.key(a, &first, boxed_a), try keys_b.key(a, &second, boxed_b));
    try std.testing.expect(!std.mem.eql(u8, &try keys_a.key(a, &first, list_a), &try keys_a.key(a, &first, boxed_a)));
    // Records with equal fields are told apart by their names.
    var module: ir.Module = .{};
    try module.compounds.appendSlice(a, &.{ .{ .record = &.{.i64} }, .{ .record = &.{.i64} } });
    var named: std.AutoHashMapUnmanaged(ir.Type, RecordName) = .empty;
    try named.put(a, @fromBackingInt(ir.Type.first_compound), .{ .module = "m.selka", .name = "Id" });
    try named.put(a, @fromBackingInt(ir.Type.first_compound + 1), .{ .module = "m.selka", .name = "Count" });
    var by_name: TypeKeys = .{ .nominals = &named };
    const id = try by_name.key(a, &module, @fromBackingInt(ir.Type.first_compound));
    const count = try by_name.key(a, &module, @fromBackingInt(ir.Type.first_compound + 1));
    try std.testing.expect(!std.mem.eql(u8, &id, &count));
    var structural: TypeKeys = .{};
    try std.testing.expectEqual(try structural.key(a, &module, @fromBackingInt(ir.Type.first_compound)), try structural.key(a, &module, @fromBackingInt(ir.Type.first_compound + 1)));
    try std.testing.expectEqual(@as(usize, 32), keyText(id).len);
}

test "stable names: a generic instance is a unit of its own and a plain function belongs to its module" {
    const plain = unitOf("app::main", "src/app.selka");
    try std.testing.expect(plain.eql(.{ .module = "src/app.selka" }));
    const instance = unitOf("lib::Box[i64]::get", "src/lib.selka");
    const other = unitOf("lib::Box[str]::get", "src/lib.selka");
    try std.testing.expectEqualStrings("lib::Box", instance.instance.template);
    try std.testing.expect(!instance.eql(other) and !instance.eql(plain));
    try std.testing.expect(instance.eql(unitOf("lib::Box[i64]::get", "src/lib.selka")));
}
