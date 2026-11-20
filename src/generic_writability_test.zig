//! Frontend B1 applies before substitution without introducing Core move checks.
const std = @import("std");
const language = @import("compiler.zig");

fn accepts(allocator: std.mem.Allocator, comptime text: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "generic_writability.selka", text ++ "\nfunc main() -> int:\n    return 0\n");
    defer compilation.deinit();
    try compilation.check();
    for (compilation.program.?.functions) |function| try std.testing.expectEqual(@as(usize, 0), function.type_arguments.len);
}

fn refuses(allocator: std.mem.Allocator, comptime text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try @import("stdlib_fixture.zig").check(arena.allocator(), text ++ "\nfunc main() -> int:\n    return 0\n");
    try std.testing.expect(!checked.passed);
    const item = checked.firstError() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("E_IMMUTABLE", item.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.B1, item.provenance.rule.?);
}

test "F3 writable own parameters and mutable receiver facts stay valid before substitution" {
    try accepts(std.testing.allocator,
        \\func update[T: copy + storable](own values: T[], item: T):
        \\    values[0] = copy(item)
        \\    append(mut values, copy(item))
    );
    try accepts(std.testing.allocator,
        \\record Box[T]:
        \\    value: T
        \\func update[T: copy + storable](mut boxes: Box[T][], item: T):
        \\    boxes[0].value = copy(item)
    );
}

test "F3 direct and nested intrinsic writes reject readonly roots" {
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\record Box[T]:
        \\    value: T
        \\func update[T: copy + storable](boxes: Box[T][], item: T):
        \\    boxes[0].value = copy(item)
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](values: T[], item: T):
        \\    append(mut values, copy(item))
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\import lists
        \\func update[T: copy + storable](values: T[]):
        \\    _ = lists.pop(mut values)
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](item: T):
        \\    const values = [copy(item)]
        \\    values[0] = copy(item)
    );
}

test "F3 immutable tuple targets and fixed array roots stay readonly" {
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T](item: T):
        \\    _ = item
        \\    const left = 1
        \\    mut right = 2
        \\    left, right = (3, 4)
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](values: FixedArray[T, 1], item: T):
        \\    values[0] = copy(item)
    );
}

test "F3 deferred const initializers remain legal on exclusive and returning paths" {
    try accepts(std.testing.allocator,
        \\func choose[T: copy + storable](item: T, flag: bool) -> T:
        \\    const selected: T
        \\    if flag:
        \\        selected = copy(item)
        \\    else:
        \\        selected = copy(item)
        \\    return selected
    );
    try accepts(std.testing.allocator,
        \\func choose[T: copy + storable](item: T, flag: bool) -> T:
        \\    const selected: T
        \\    if flag:
        \\        selected = copy(item)
        \\        return selected
        \\    selected = copy(item)
        \\    return selected
    );
    try accepts(std.testing.allocator,
        \\func choose[T: copy + storable](item: T) -> T:
        \\    const selected: T
        \\    while True:
        \\        selected = copy(item)
        \\        break
        \\    return selected
    );
}

test "F3 maybe initialized deferred const cannot initialize again after a join" {
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](item: T, flag: bool):
        \\    const selected: T
        \\    if flag:
        \\        selected = copy(item)
        \\    selected = copy(item)
        \\    _ = selected
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](item: T, flag: int?):
        \\    const selected: T
        \\    match flag:
        \\        case Some(value):
        \\            _ = value
        \\            selected = copy(item)
        \\        case None:
        \\            pass
        \\    selected = copy(item)
        \\    _ = selected
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](item: T, repeat: bool):
        \\    const selected: T
        \\    while repeat:
        \\        selected = copy(item)
        \\        break
        \\    selected = copy(item)
        \\    _ = selected
    );
}

test "F3 a deferred const initialization cannot repeat on a loop backedge" {
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](item: T, repeat: bool):
        \\    const selected: T
        \\    while repeat:
        \\        selected = copy(item)
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](item: T, repeat: bool):
        \\    const selected: T
        \\    while repeat:
        \\        selected = copy(item)
        \\        continue
    );
}

test "F3 match mut payloads preserve writability through normalized nested patterns" {
    try accepts(std.testing.allocator,
        \\func update[T: copy + storable](mut value: T?, replacement: T):
        \\    match mut value:
        \\        case Some(item):
        \\            item = copy(replacement)
        \\        case None:
        \\            pass
    );
    try accepts(std.testing.allocator,
        \\func update[T: copy + storable](mut value: T??, replacement: T):
        \\    match mut value:
        \\        case Some(Some(item)):
        \\            item = copy(replacement)
        \\        case Some(None):
        \\            pass
        \\        case None:
        \\            pass
    );
    // migrate-embedded: skip intentional uncalled B1 refusal fixtures
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](mut value: T??, replacement: T):
        \\    match value:
        \\        case Some(Some(item)):
        \\            item = copy(replacement)
        \\        case Some(None):
        \\            pass
        \\        case None:
        \\            pass
    );
}

test "F3 uncalled Core marker transfer and writable owner predicates remain per instance" {
    try accepts(std.testing.allocator,
        \\func change(mut values: int[]):
        \\    append(mut values, 1)
        \\func unchecked[T](values: int[], optional: int[]?):
        \\    change(mut values)
        \\    match mut optional:
        \\        case Some(items):
        \\            append(mut items, 1)
        \\        case None:
        \\            pass
    );
}

test "F3 enumerate positions are readonly while an explicit mut copy remains writable" {
    // migrate-embedded: skip intentional uncalled enumerate-position B1 refusal
    try refuses(std.testing.allocator,
        \\func update[T: copy + storable](values: T[]):
        \\    for position, value in enumerate(values):
        \\        position = 9
        \\        _ = value
    );
    try accepts(std.testing.allocator,
        \\func update[T: copy + storable](values: T[]):
        \\    for position, value in enumerate(values):
        \\        mut writable_position = position
        \\        writable_position += 1
        \\        _ = writable_position
        \\        _ = value
    );
}
