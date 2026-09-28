//! A same-slot return arm moves its element's payload into the binding.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const marker = "# RC-ELEMENT-TAKE-1";
const source =
    \\record Table:
    \\    entries: list[int]
    \\    count: int
    \\record Instance:
    \\    klass: int
    \\    fields: Table
    \\union Obj:
    \\    free,
    \\    instance: Instance
    \\def put(t: mut Table, value: int):
    \\    t.entries.append(value)
    \\    t.count += 1
    \\def returned(objects: mut list[Obj], ref: int, value: int):
    \\    match objects[ref]:
    \\        case Obj.instance(instance):
    \\            klass = instance.klass
    \\            fields = instance.fields
    \\            put(mut fields, value)
    \\            objects[ref] = Obj.instance(Instance(klass=klass, fields=fields))
    \\        case _:
    \\            assert False, "not an instance"
    \\def observed(objects: mut list[Obj], ref: int, value: int):
    \\    match objects[ref]:
    \\        case Obj.instance(instance):
    \\            klass = instance.klass
    \\            fields = instance.fields
    \\            put(mut fields, value + len(objects))
    \\            objects[ref] = Obj.instance(Instance(klass=klass, fields=fields))
    \\        case _:
    \\            assert False, "not an instance"
    \\def elsewhere(objects: mut list[Obj], ref: int, value: int):
    \\    match objects[ref]:
    \\        case Obj.instance(instance):
    \\            klass = instance.klass
    \\            fields = instance.fields
    \\            put(mut fields, value)
    \\            objects[0] = Obj.instance(Instance(klass=klass, fields=fields))
    \\        case _:
    \\            assert False, "not an instance"
    \\def early(objects: mut list[Obj], ref: int, value: int):
    \\    match objects[ref]:
    \\        case Obj.instance(instance):
    \\            klass = instance.klass
    \\            fields = instance.fields
    \\            put(mut fields, value)
    \\            if value < 0:
    \\                return
    \\            objects[ref] = Obj.instance(Instance(klass=klass, fields=fields))
    \\        case _:
    \\            assert False, "not an instance"
    \\def owned(value: int) -> int:
    \\    objects = [Obj.instance(Instance(klass=1, fields=Table(entries=[], count=0)))]
    \\    match objects[0]:
    \\        case Obj.instance(instance):
    \\            klass = instance.klass
    \\            fields = instance.fields
    \\            put(mut fields, value)
    \\            objects[0] = Obj.instance(Instance(klass=klass, fields=fields))
    \\        case _:
    \\            assert False, "not an instance"
    \\    return len(objects)
    \\def main() -> int:
    \\    objects = [Obj.instance(Instance(klass=1, fields=Table(entries=[], count=0)))]
    \\    returned(mut objects, 0, 5)
    \\    observed(mut objects, 0, 6)
    \\    elsewhere(mut objects, 0, 7)
    \\    early(mut objects, 0, 8)
    \\    return owned(9) + len(objects)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_element_take.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

// spec: RC-ELEMENT-TAKE-1
test "RC same-slot return arms move the element payload and other shapes copy it" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const expected = [_]struct { []const u8, bool }{
        .{ "returned", true }, .{ "observed", false }, .{ "elsewhere", false }, .{ "early", false }, .{ "owned", false },
    };
    for (expected) |case| try t.expectEqual(case[1], contains(try named(manifest.value, case[0]), marker));
}

// spec-case: RC-ELEMENT-TAKE-1
test "RC element take tests the scrutinee and list at run time and GC lowering is unchanged" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted();
    defer manifest.deinit();
    const il = try named(manifest.value, "returned");
    const taken = std.mem.indexOf(u8, il, marker) orelse return error.TestUnexpectedResult;
    try t.expect(contains(il[taken..], "@rctakeelement"));
    try t.expect(contains(il[taken..], "@rctakecopy"));
    // The extracted field then moves out of the binding (RC-DEAD-FIELD-MOVE-1).
    try t.expect(contains(il[taken..], "# RC-DEAD-FIELD-MOVE-1"));
    runtime.set(.gc);
    var collected = try emitted();
    defer collected.deinit();
    try t.expect(!contains(try named(collected.value, "returned"), marker));
}
