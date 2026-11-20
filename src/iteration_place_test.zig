//! D1 ownership rejects structural changes along an active iteration place.
const std = @import("std");
const transition = @import("ownership_transition_test_support.zig");
const t = std.testing;

// spec-case: D1-LIVE-PLACE
test "D1 live list shrink is refused on the final continued step" {
    try transition.refuses(t.allocator,
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut items = [1, 2]
        \\    for value in items:
        \\        _ = value
        \\        _ = lists.pop(mut items)
        \\        continue
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 growth then shrink is refused against the last observed length" {
    try transition.refuses(t.allocator,
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut items = [1]
        \\    for value in items:
        \\        if value == 1:
        \\            append(mut items, 2)
        \\        else:
        \\            _ = lists.pop(mut items)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 indexed ancestor growth is refused before switching storage" {
    try transition.refuses(t.allocator,
        \\func main() -> int:
        \\    mut rows = [[1, 2]]
        \\    for value in rows[0]:
        \\        append(mut rows, [value])
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 indexed ancestor shrink by mut callee is refused" {
    try transition.refuses(t.allocator,
        \\import lists
        \\
        \\
        \\func shrink(mut rows: int[][]) -> Unit:
        \\    lists.clear(mut rows)
        \\func main() -> int:
        \\    mut rows = [[1, 2]]
        \\    for value in rows[0]:
        \\        _ = value
        \\        shrink(mut rows)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 copied dictionary growth is refused" {
    try transition.refuses(t.allocator,
        \\func main() -> int:
        \\    mut values = {1: 10}
        \\    mut snapshot = copy(values)
        \\    for key in values:
        \\        values[2] = key
        \\    return len(snapshot)
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 copied set growth is refused" {
    try transition.refuses(t.allocator,
        \\import sets
        \\
        \\func main() -> int:
        \\    mut values = {1}
        \\    mut snapshot = copy(values)
        \\    for value in values:
        \\        sets.add(mut values, value + 1)
        \\    return len(snapshot)
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 dictionary ancestor growth is refused before indexed list refresh" {
    try transition.refuses(t.allocator,
        \\func main() -> int:
        \\    mut rows = {1: [1, 2]}
        \\    for value in rows[1]:
        \\        rows[2] = [value]
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 managed ancestor of a fixed array rejects mutation" {
    try transition.refuses(t.allocator,
        \\func main() -> int:
        \\    mut rows: FixedArray[int, 2][] = [FixedArray[int, 2]([1, 2])]
        \\    for value in rows[0]:
        \\        append(mut rows, FixedArray[int, 2]([value, value]))
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 managed ancestor of immutable text rejects mutation" {
    try transition.refuses(t.allocator,
        \\import lists
        \\import strings
        \\
        \\
        \\func main() -> int:
        \\    mut rows = ["a🙂"]
        \\    mut snapshot = copy(rows)
        \\    for letter in strings.chars(rows[0]):
        \\        _ = letter
        \\        lists.clear(mut rows)
        \\    return len(snapshot)
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: D1-LIVE-PLACE
test "D1 managed ancestor of immutable bytes rejects mutation" {
    try transition.refuses(t.allocator,
        \\func main() -> int:
        \\    mut rows = [b"ab"]
        \\    mut snapshot = copy(rows)
        \\    for octet in rows[0]:
        \\        append(mut rows, b"cd")
        \\        _ = octet
        \\    return len(snapshot)
    , "E_SINGLE_OWNER_OVERLAP");
}
