//! Dictionary iteration views retain their type and mutation checks through lowering.
const t = @import("std").testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

// spec: DICT-VIEWS-1
test "dictionary views reject structural mutation through a retained alias" {
    var c = try language.Compilation.init(t.allocator, "views.my",
        \\def main() -> int:
        \\    mapping = {1: 10, 2: 20}
        \\    view = mapping.values()
        \\    alias = mapping
        \\    for value in view:
        \\        alias[3] = value
        \\    return 0
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings("R_LIST_ITERATION_MUTATION", result.trap.code);
}

// spec-case: DICT-VIEWS-1
test "dictionary view reads are noalloc but explicit snapshots allocate" {
    var live = try language.Compilation.init(t.allocator, "live.my",
        \\def total(mapping: dict[str, int]) -> int noalloc:
        \\    result = 0
        \\    view = mapping.values()
        \\    for value in view:
        \\        result += value
        \\    return result + len(view)
        \\def main() -> int:
        \\    return 0
        \\
    );
    defer live.deinit();
    try live.check();
    try t.expect(live.program != null);
    var snapshot = try language.Compilation.init(t.allocator, "snapshot.my",
        \\def copy(mapping: dict[str, int]) -> list[int] noalloc:
        \\    return list(mapping.values())
        \\def main() -> int:
        \\    return 0
        \\
    );
    defer snapshot.deinit();
    try t.expectError(error.SourceError, snapshot.check());
    try t.expectEqualStrings("E_EFFECT_BOUND", snapshot.diagnostics.items[0].code);
}

// spec-case: DICT-VIEWS-1
test "dictionary views retain mappings and generic snapshots under GC stress" {
    var c = try language.Compilation.init(t.allocator, "rooted-views.my",
        \\def copy_values[T: copy + storable](mapping: dict[str, T]) -> list[T]:
        \\    return list(mapping.values())
        \\
        \\def live_values[T: copy + storable](mapping: dict[str, T]) -> DictValues[str, T] noalloc:
        \\    return mapping.values()
        \\
        \\def copy_items[T: copy + storable](mapping: dict[str, T]) -> list[DictItem[str, T]]:
        \\    return list(mapping.items())
        \\
        \\def main() -> int:
        \\    retained = {"alive": 42}.items()
        \\    mapping = {"a": 10, "b": 20}
        \\    values = live_values(mapping)
        \\    frozen = copy_values(mapping)
        \\    entries = copy_items(mapping)
        \\    alias = mapping
        \\    alias["a"] = 7
        \\    for index in range(200):
        \\        garbage = {"discard": index}
        \\        if len(garbage) != 1:
        \\            return 0
        \\    return list(retained)[0].value + frozen[0] + list(values)[0] + entries[1].value
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expect(!result.trapped());
    try t.expectEqual(@as(i64, 79), result.value);
}

// spec-case: DICT-VIEWS-1
test "dictionary views obey arena confinement and remain usable inside an arena" {
    var rejected = try language.Compilation.init(t.allocator, "arena-view-escape.my",
        \\def main() -> int:
        \\    retained = {"old": 1}.values()
        \\    with arena():
        \\        mapping = {"young": 42}
        \\        retained = mapping.values()
        \\    return len(retained)
        \\
    );
    defer rejected.deinit();
    try t.expectError(error.SourceError, rejected.check());
    try t.expectEqualStrings("E_ARENA_ESCAPE", rejected.diagnostics.items[0].code);

    var safe = try language.Compilation.init(t.allocator, "arena-view-live.my",
        \\def total(values: DictValues[str, int]) -> int noalloc:
        \\    result = 0
        \\    for value in values:
        \\        result += value
        \\    return result
        \\
        \\def main() -> int:
        \\    result = 0
        \\    kept = {"old": 0}.values()
        \\    with arena() as scratch:
        \\        mapping = {"a": 20, "b": 22}
        \\        result = total(mapping.values())
        \\        kept = scratch.escape(mapping.values())
        \\    return result + list(kept)[0]
        \\
    );
    defer safe.deinit();
    const outcome = try native.runWithOptions(&safe, .{ .gc_stress = true });
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(i64, 62), outcome.value);
}
