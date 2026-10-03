//! Physical imports must resolve names against the current catalog and reject missing authority.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const physical = language.module_physical;
const bytecode = language.bytecode;
const typed = @import("typed.zig");

// spec-case: MODULE-COMPILE-1
test "physical imports remap type and callee IDs and decline missing symbols" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const functions = [_]bytecode.Function{
        .{ .name = "lib.read", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.helper", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{} } },
    };
    const record: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "lib.Item", .declaration = .{ .start = 4, .end = 8 }, .fields = &.{} };
    const body: bytecode.Function = .{
        .name = "lib.read",
        .id = @fromBackingInt(0),
        .signature = .{ .return_type = record.id },
        .scope = .{ .instructions = &.{.{ .span = .{ .start = 20, .end = 21 }, .op = .{ .call = @fromBackingInt(1) } }} },
    };
    const data = try physical.write(a, .{ .functions = &functions, .records = &.{record} }, body);
    var ids: physical.Ids = .{};
    try ids.functions.put(a, "lib.read", @fromBackingInt(3));
    try ids.functions.put(a, "lib.helper", @fromBackingInt(8));
    try ids.records.put(a, "lib.Item", @fromBackingInt(typed.Type.record_base + 4));
    const restored = try physical.read(a, &ids, bytecode.Function, data);
    try t.expectEqual(@as(usize, 3), @backingInt(restored.id));
    try t.expectEqual(@as(usize, 8), @backingInt(restored.scope.instructions[0].op.call));
    try t.expectEqual(@as(usize, typed.Type.record_base + 4), @backingInt(restored.signature.return_type));
    _ = ids.functions.remove("lib.helper");
    try t.expectError(error.InvalidEncoding, physical.read(a, &ids, bytecode.Function, data));
}

// spec-case: MODULE-COMPILE-1
test "physical imports refuse conflicting record shapes and real bodies" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const record: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "lib.Item", .declaration = .{ .start = 0, .end = 0 }, .fields = &.{} };
    // The body names the record, so its archive keeps the record's row.
    const body: bytecode.Function = .{ .name = "lib.read", .id = @fromBackingInt(0), .signature = .{ .return_type = record.id }, .scope = .{ .instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1 } }} } };
    const code: bytecode.Program = .{ .functions = &.{body}, .records = &.{record} };
    const original = try physical.archive(a, code, &.{true});
    var other_record = record;
    other_record.managed = true;
    const different_shape = try physical.archive(a, .{ .functions = &.{body}, .records = &.{other_record} }, &.{true});
    var other_body = body;
    other_body.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 2 } }};
    const different_body = try physical.archive(a, .{ .functions = &.{other_body}, .records = &.{record} }, &.{true});
    const restore = @import("module_physical_inputs.zig").restore;
    const first: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = original } };
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, .{ .module = "lib", .text = "", .emission = .{ .physical = different_shape } } }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, .{ .module = "lib", .text = "", .emission = .{ .physical = different_body } } }));
    try t.expectError(error.InternalError, restore(a, code, &.{false}, &.{null}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = different_shape } }}));
}

// spec-case: MODULE-COMPILE-1
test "signature-only original imports cannot prove unique mutable parameters" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bytecode.Function = .{
        .name = "lib.mutate",
        .id = @fromBackingInt(0),
        .signature = .{ .parameter_count = 1, .declared_mutates = &.{0} },
        .scope = .{ .locals = &.{.{ .name = "items", .ty = .i64, .declaration = .{ .start = 0, .end = 0 }, .mutable = true }}, .instructions = &.{} },
    };
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{});
    try t.expect(!@import("ownership_model.zig").uniqueParameter(restored.code.functions[0], 0));
    try t.expect(restored.code.functions[0].physical.?.unknown);
    try t.expect(restored.imported[0].?.allocates);
    try t.expect(restored.imported[0].?.writes[0]);
    var actual = signature;
    actual.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1 } }};
    const archive = try physical.archive(a, .{ .functions = &.{actual} }, &.{true});
    const supplied: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = archive, .functions = &.{.{ .name = "lib.mutate", .allocates = false, .writes = &.{true} }} } };
    const known = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{supplied});
    try t.expect(@import("ownership_model.zig").uniqueParameter(known.code.functions[0], 0));
    try t.expect(!known.code.functions[0].physical.?.unknown);
    try t.expect(!known.imported[0].?.allocates);
}

// spec-case: MODULE-COMPILE-1
test "physical imports reject dependency signature conflicts in either order and against originals" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bytecode.Function = .{ .name = "lib.helper", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } };
    var different = signature;
    different.signature.return_type = .bool;
    const left = try signatureArchive(a, .{ .functions = &.{signature} });
    const right = try signatureArchive(a, .{ .functions = &.{different} });
    const first: language.module_interface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = left } };
    const second: language.module_interface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = right } };
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, second }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ second, first }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{second}));
    const valid = try restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, first });
    try t.expectEqual(typed.Type.i64, valid.code.functions[0].signature.return_type);
    try t.expect(valid.code.functions[0].physical.?.unknown);
}

// spec-case: MODULE-COMPILE-1
test "physical imports bind decoded function IDs to named slots before granting readonly authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signatures = [_]bytecode.Function{
        .{ .name = "lib.first", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.second", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{
            .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .print = .{ .types = &.{}, .separator = false, .terminator = false } } },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .pop },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 0 } },
            .{ .span = .{ .start = 0, .end = 0 }, .op = .ret },
        } } },
    };
    var body = signatures[0];
    body.scope.instructions = &.{ .{ .span = .{ .start = 0, .end = 0 }, .op = .{ .call = signatures[1].id } }, .{ .span = .{ .start = 0, .end = 0 }, .op = .ret } };
    const good = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    const supplied: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = .{ .functions = &.{good} } } };
    const restore = @import("module_physical_inputs.zig").restore;
    const restored = try restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{supplied});
    var layouts = try @import("native_types.zig").Catalog.initRecords(a, restored.code.records);
    defer layouts.deinit();
    var catalog = try @import("rc_shape.zig").Catalog.init(a, &layouts);
    defer catalog.deinit();
    try t.expect((try @import("rc_readonly_calls.zig").certify(&catalog, restored.code.functions, restored.code.functions[0], "rc-v3")) == null);
    body.id = signatures[1].id;
    const bad = try physical.write(a, .{ .functions = &signatures, .records = &.{} }, body);
    var forged = supplied;
    forged.emission.physical.functions = &.{bad};
    try t.expectError(error.InternalError, restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{forged}));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &signatures }, &.{ true, false }, &.{ null, null }, &.{forged}));
    forged.emission.physical = .{ .dependencies = &.{bad} };
    try t.expectError(error.InternalError, restore(a, .{ .functions = &signatures }, &.{ false, false }, &.{ null, null }, &.{forged}));
}

// spec-case: MODULE-COMPILE-1
test "physical imports compare declaration signatures without importing body-local facts" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const signature: bytecode.Function = .{
        .name = "lib.helper",
        .id = @fromBackingInt(0),
        .signature = .{ .parameter_count = 1, .declared_mutates = &.{0} },
        .scope = .{ .locals = &.{.{ .name = "n", .ty = .i64, .declaration = .{ .start = 0, .end = 1 }, .mutable = false }}, .instructions = &.{} },
    };
    var actual = signature;
    actual.signature.inferred.writes = true;
    actual.policy.effects = @import("effect_set.zig").bit(.managed_allocation);
    actual.scope.locals = &.{
        .{ .name = "n", .ty = .i64, .declaration = .{ .start = 9, .end = 10 }, .mutable = true, .usage = .{ .reads = 4 }, .origin = .parameter },
        .{ .name = "local", .ty = .bool, .declaration = .{ .start = 0, .end = 0 }, .mutable = false },
    };
    actual.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .push_i64 = 1 } }};
    const archive = try physical.archive(a, .{ .functions = &.{actual} }, &.{true});
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{signature} }, &.{false}, &.{null}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = archive } }});
    try t.expectEqual(@as(usize, 2), restored.code.functions[0].scope.locals.len);
    try t.expect(restored.code.functions[0].signature.inferred.writes);
    try t.expect(@import("ownership_model.zig").writesParameter(restored.code.functions[0], 0));
}

// spec-case: MODULE-COMPILE-1
test "physical imports reject host effect declarations that change emitted host authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const effects = @import("effect_set.zig");
    const plain: bytecode.Function = .{
        .name = "lib.hosted",
        .id = @fromBackingInt(0),
        .policy = .{ .host = .{ .start = 0, .end = 0 }, .effects = effects.bit(.host) },
        .signature = .{ .parameter_count = 1 },
        .scope = .{ .locals = &.{.{ .name = "host", .ty = .host_cap, .declaration = .{ .start = 0, .end = 0 }, .mutable = false }}, .instructions = &.{} },
    };
    var changed = plain;
    changed.policy.effects |= effects.bit(.clock);
    var layouts = try @import("native_types.zig").Catalog.initRecords(a, &.{});
    defer layouts.deinit();
    const before = try @import("qbe_host.zig").describe(a, .{ .functions = &.{plain} }, &layouts);
    const after = try @import("qbe_host.zig").describe(a, .{ .functions = &.{changed} }, &layouts);
    try t.expect(before.declarations[0].effects != after.declarations[0].effects);
    const left: language.module_interface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{plain} }) } };
    const right: language.module_interface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{changed} }) } };
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ left, right }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ right, left }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{plain} }, &.{false}, &.{null}, &.{right}));
    var foreign = plain;
    foreign.policy.host = null;
    foreign.policy.c_abi = true;
    changed = foreign;
    changed.policy.effects |= effects.bit(.clock);
    const orphan: language.module_interface.Interface = .{ .module = "third", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{changed} }) } };
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{foreign} }, &.{false}, &.{null}, &.{orphan}));
}

// spec-case: MODULE-COMPILE-1
test "physical imports reject explicit callback effect ceilings while ignoring bound source spans" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const effects = @import("effect_set.zig");
    const plain: bytecode.Function = .{
        .name = "lib.callback",
        .id = @fromBackingInt(0),
        .policy = .{ .effect_bound = .{ .allowed = 0, .span = .{ .start = 0, .end = 1 } } },
        .scope = .{ .instructions = &.{} },
    };
    var changed = plain;
    changed.policy.effect_bound.?.allowed = effects.bit(.output);
    const left: language.module_interface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{plain} }) } };
    const right: language.module_interface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{changed} }) } };
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ left, right }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ right, left }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{plain} }, &.{false}, &.{null}, &.{right}));
    changed = plain;
    changed.policy.effect_bound.?.span = .{ .start = 40, .end = 45 };
    const moved: language.module_interface.Interface = .{ .module = "third", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{changed} }) } };
    const valid = try restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ left, moved });
    try t.expectEqual(@as(effects.Mask, 0), valid.code.functions[0].policy.effect_bound.?.allowed);
    changed.policy.effect_bound = null;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{changed} }, &.{false}, &.{null}, &.{left}));
}

// spec-case: MODULE-COMPILE-1
test "physical imports reject declaration mutation conflicts that change caller storage authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const array: typed.Record = .{
        .id = @fromBackingInt(typed.Type.record_base),
        .name = "Array[int,2]",
        .declaration = .{ .start = 0, .end = 0 },
        .fields = &.{},
        .shape = .{ .array = .{ .element = .i64, .length = 2 } },
    };
    const plain: bytecode.Function = .{
        .name = "lib.helper",
        .id = @fromBackingInt(0),
        .signature = .{ .parameter_count = 1 },
        .scope = .{ .locals = &.{.{ .name = "items", .ty = array.id, .declaration = .{ .start = 0, .end = 0 }, .mutable = false }}, .instructions = &.{} },
    };
    var changed = plain;
    changed.signature.declared_mutates = &.{0};
    try t.expect(typed.referenceMut(&.{array}, array.id));
    try t.expect(!@import("ownership_model.zig").writesParameter(plain, 0));
    try t.expect(@import("ownership_model.zig").writesParameter(changed, 0));
    const left: language.module_interface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{plain}, .records = &.{array} }) } };
    const right: language.module_interface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = try signatureArchive(a, .{ .functions = &.{changed}, .records = &.{array} }) } };
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ left, right }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ right, left }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{plain}, .records = &.{array} }, &.{false}, &.{null}, &.{right}));
}

// spec-case: MODULE-COMPILE-1
test "physical record imports erase source-local default node indexes but retain layout authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original: typed.Record = .{
        .id = @fromBackingInt(typed.Type.record_base),
        .name = "lib.Item",
        .declaration = .{ .start = 0, .end = 0 },
        .fields = &.{.{ .name = "value", .ty = .i64, .declaration = .{ .start = 0, .end = 0 }, .default_value = 1 }},
    };
    var relocated = original;
    relocated.fields = &.{.{ .name = "value", .ty = .i64, .declaration = .{ .start = 20, .end = 21 }, .default_value = 64 }};
    const left = try physical.write(a, .{ .functions = &.{}, .records = &.{original} }, original);
    const right = try physical.write(a, .{ .functions = &.{}, .records = &.{relocated} }, relocated);
    try t.expectEqualSlices(u8, left.bytes, right.bytes);
    const supplied: language.module_interface.Interface = .{ .module = "lib", .text = "", .emission = .{ .physical = .{ .records = &.{right} } } };
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{}, .records = &.{original} }, &.{}, &.{}, &.{ supplied, supplied });
    try t.expectEqual(typed.Type.i64, restored.code.records[0].fields[0].ty);
    try t.expectEqual(@as(?usize, 1), restored.code.records[0].fields[0].default_value);
}

/// An archive holding a signature-only dependency row for every function of
/// `code` and a row for every record, as a module whose bodies name them all
/// would publish.
fn signatureArchive(a: std.mem.Allocator, code: bytecode.Program) !physical.Archive {
    const names: physical.Names = .{ .functions = code.functions, .records = code.records };
    const dependencies = try a.alloc(physical.Data, code.functions.len);
    for (code.functions, dependencies) |function, *data| {
        var plain = function;
        plain.scope.instructions = &.{};
        data.* = try physical.write(a, names, plain);
    }
    const records = try a.alloc(physical.Data, code.records.len);
    for (code.records, records) |record, *data| data.* = try physical.write(a, names, record);
    return .{ .records = records, .dependencies = dependencies };
}

// spec: MODULE-ARCHIVE-TRIM-1
test "an archive keeps only the dependency and record rows its kept rows name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const at: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const used: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "lib.Used", .declaration = at, .fields = &.{} };
    const unused: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base + 1), .name = "lib.Unused", .declaration = at, .fields = &.{} };
    // `lib.read` calls `lib.helper` and returns a `lib.Used`; `lib.other` is
    // declared but named by nothing kept.
    const functions = [_]bytecode.Function{
        .{ .name = "lib.read", .id = @fromBackingInt(0), .signature = .{ .return_type = used.id }, .scope = .{ .instructions = &.{.{ .span = at, .op = .{ .call = @fromBackingInt(1) } }} } },
        .{ .name = "lib.helper", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{} } },
        .{ .name = "lib.other", .id = @fromBackingInt(2), .signature = .{ .return_type = unused.id }, .scope = .{ .instructions = &.{} } },
    };
    const archive = try physical.archive(a, .{ .functions = &functions, .records = &.{ used, unused } }, &.{ true, false, false });
    try t.expectEqual(@as(usize, 1), archive.functions.len);
    try t.expectEqual(@as(usize, 1), archive.dependencies.len);
    try t.expectEqualStrings("lib.helper", archive.dependencies[0].name);
    try t.expectEqual(@as(usize, 1), archive.records.len);
    try t.expectEqualStrings("lib.Used", archive.records[0].name);
    // A dependent restores the trimmed archive: every name its rows spell is there.
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = archive } }});
    try t.expectEqual(@as(usize, 2), restored.code.functions.len);
    try t.expectEqual(@as(usize, 1), restored.code.records.len);
}

/// A root spliced from two nested callees, with an ordinary callable dependency
/// in the leaf and a record referenced only by the leaf's result signature.
fn inlineArchiveCode() bytecode.Program {
    const at: @import("source.zig").Span = .{ .start = 0, .end = 0 };
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base);
    return .{ .functions = &.{
        .{ .name = "lib.root", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{
            .{ .span = at, .op = .{ .jump = 0 }, .inline_origin = .{ .callee = @fromBackingInt(1), .callee_pc = 0, .call_position = 0 } },
        } } },
        .{ .name = "lib.middle", .id = @fromBackingInt(1), .scope = .{ .instructions = &.{
            .{ .span = at, .op = .{ .jump = 0 }, .inline_origin = .{ .callee = @fromBackingInt(2), .callee_pc = 1, .call_position = 0 } },
        } } },
        .{ .name = "lib.leaf", .id = @fromBackingInt(2), .signature = .{ .return_type = ty }, .scope = .{ .instructions = &.{
            .{ .span = at, .op = .{ .call = @fromBackingInt(3) } },
            .{ .span = at, .op = .ret },
        } } },
        .{ .name = "lib.helper", .id = @fromBackingInt(3), .scope = .{ .instructions = &.{.{ .span = at, .op = .ret }} } },
        .{ .name = "lib.unused", .id = @fromBackingInt(4), .scope = .{ .instructions = &.{} } },
    }, .records = &.{.{ .id = ty, .name = "lib.Returned", .declaration = at, .fields = &.{} }} };
}

// spec-case: MODULE-ARCHIVE-TRIM-1
test "physical archives retain remapped nested inline provenance without emitting closure bodies" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const code = inlineArchiveCode();
    const archive = try physical.archive(a, code, &.{true});
    try t.expectEqual(@as(usize, 3), archive.functions.len);
    try t.expectEqual(@as(usize, 1), archive.dependencies.len);
    try t.expectEqualStrings("lib.helper", archive.dependencies[0].name);
    try t.expectEqual(@as(usize, 1), archive.records.len);
    const own: bytecode.Function = .{ .name = "app.own", .id = @fromBackingInt(0), .scope = .{ .instructions = &.{} } };
    const restored = try @import("module_physical_inputs.zig").restore(a, .{ .functions = &.{own} }, &.{true}, &.{null}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = archive } }});
    const site = try @import("bytecode_inline_site.zig").resolve(restored.code, restored.code.functions[1], 0);
    try t.expectEqualStrings("lib.leaf", site.function.name);
    try t.expectEqual(@as(usize, 2), site.depth);
    try t.expectEqual(@as(usize, 1), site.pc);
    try t.expect(site.function.scope.instructions[site.pc].op == .ret);
    try t.expectEqual(@as(usize, 5), restored.code.functions.len);
    try t.expectEqualSlices(bool, &.{ true, false, false, false, false }, restored.emit);
    try t.expect(restored.code.functions[4].physical.?.unknown);
}

// spec-case: MODULE-ARCHIVE-TRIM-1
test "physical archives reject missing cyclic and out of range inline provenance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var code = inlineArchiveCode();
    const functions = try a.dupe(bytecode.Function, code.functions);
    code.functions = functions;
    functions[2].scope.instructions = &.{};
    try t.expectError(error.InternalError, physical.archive(a, code, &.{true}));
    functions[2] = inlineArchiveCode().functions[2];
    const middle = try a.dupe(bytecode.Instruction, functions[1].scope.instructions);
    functions[1].scope.instructions = middle;
    middle[0].inline_origin.?.callee_pc = 999;
    try t.expectError(error.InternalError, physical.archive(a, code, &.{true}));
    middle[0].inline_origin.?.callee = functions[0].id;
    middle[0].inline_origin.?.callee_pc = 0;
    try t.expectError(error.InternalError, physical.archive(a, code, &.{true}));
}

// spec-case: MODULE-ARCHIVE-TRIM-1
test "physical import refuses a legacy inline archive missing original body authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const code = inlineArchiveCode();
    var archive = try signatureArchive(a, code);
    const root = try physical.write(a, .{ .functions = code.functions, .records = code.records }, code.functions[0]);
    archive.functions = &.{root};
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{.{ .module = "lib", .text = "", .emission = .{ .physical = archive } }}));
}

// spec-case: MODULE-ARCHIVE-TRIM-1
test "physical import refuses conflicting bodies retained only for inline provenance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var code = inlineArchiveCode();
    const archive = try physical.archive(a, code, &.{true});
    const functions = try a.dupe(bytecode.Function, code.functions);
    code.functions = functions;
    const leaf = try a.dupe(bytecode.Instruction, functions[2].scope.instructions);
    functions[2].scope.instructions = leaf;
    leaf[0].op = .{ .push_i64 = 7 };
    const conflicting = try physical.archive(a, code, &.{true});
    const first: language.module_interface.Interface = .{ .module = "first", .text = "", .emission = .{ .physical = archive } };
    const second: language.module_interface.Interface = .{ .module = "second", .text = "", .emission = .{ .physical = conflicting } };
    const restore = @import("module_physical_inputs.zig").restore;
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ first, second }));
    try t.expectError(error.InternalError, restore(a, .{ .functions = &.{} }, &.{}, &.{}, &.{ second, first }));
}
