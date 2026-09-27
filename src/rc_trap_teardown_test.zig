//! RC frames keep no runtime journal: every drop is emitted statically with
//! its slot's type, and a trap is left to heap teardown. The behavior against
//! the tracing collector is checked through the CLI in test/rc_teardown_test.zig.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");

const conditional =
    \\def maybe(flag: int) -> int:
    \\    if flag > 1:
    \\        extra = [flag, flag]
    \\        if flag > 5:
    \\            return len(extra)
    \\    if flag == 3:
    \\        return 3
    \\    return 1
    \\
    \\def search(items: list[str], target: str) -> int:
    \\    found = -1
    \\    index = 0
    \\    while index < len(items):
    \\        current = items[index] + "!"
    \\        if current == target + "!":
    \\            found = index
    \\            break
    \\        index += 1
    \\    return found
    \\
    \\def label(flag: int) -> str:
    \\    text = "other"
    \\    if flag > 0:
    \\        text = "positive" + str(flag)
    \\    chosen: Option[int] = None
    \\    if flag == 1:
    \\        chosen = Some(flag)
    \\    match chosen:
    \\        case Some(one):
    \\            names = ["one", str(one)]
    \\            return text + names[0]
    \\        case None:
    \\            pass
    \\    return text
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(maybe(0), maybe(3), maybe(4), maybe(9))
    \\    out.print(search(["a", "b", "c"], "b"), search(["a"], "z"))
    \\    out.print(label(1), label(2), label(0))
    \\    return 0
;

const nested_returns =
    \\record Box:
    \\    items: list[int]
    \\
    \\def value(n: int) -> Result[int, str]:
    \\    if n > 2:
    \\        return Err("big" + str(n))
    \\    return Ok(n)
    \\
    \\def fill(boxes: mut list[Box], n: int) -> Result[int, str]:
    \\    i = 0
    \\    while i < n:
    \\        boxes[0].items.append(value(i)?)
    \\        i += 1
    \\    return Ok(len(boxes[0].items))
    \\
    \\def grow(d: mut dict[str, list[int]], n: int) -> Result[int, str]:
    \\    d["a"].append(value(n)?)
    \\    return Ok(len(d["a"]))
    \\
    \\def first_big(rows: list[list[int]], limit: int) -> int:
    \\    for row in rows:
    \\        for item in row:
    \\            if item > limit:
    \\                return item
    \\    return -1
    \\
    \\def inside(limit: int) -> int:
    \\    with arena() as scratch:
    \\        rows: list[list[int]] = [[1, 2], [limit, 9]]
    \\        if limit > 3:
    \\            return first_big(rows, 3)
    \\    return 0
    \\
    \\def show(out: Stream, result: Result[int, str]) -> None:
    \\    match result:
    \\        case Ok(v):
    \\            out.print(v)
    \\        case Err(e):
    \\            out.print(e)
    \\
    \\def main(out: Stream) -> int:
    \\    boxes = [Box(items=[1])]
    \\    show(out, fill(mut boxes, 5))
    \\    d: dict[str, list[int]] = {"a": [1]}
    \\    show(out, grow(mut d, 1))
    \\    show(out, grow(mut d, 7))
    \\    out.print(len(boxes[0].items), len(d["a"]))
    \\    out.print(first_big([[1], [2, 8]], 5), first_big([[1]], 5))
    \\    out.print(inside(7), inside(2))
    \\    return 0
;

// spec: RC-STATIC-DROPS-1
test "RC-STATIC-DROPS-1 RC frames link nothing and drop through static types" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try language.Compilation.init(t.allocator, "teardown.my", conditional);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "# rc-frame") != null);
    try t.expect(std.mem.indexOf(u8, text, "# rc-exit") != null);
    try t.expect(std.mem.indexOf(u8, text, "@rcslotdrop") != null);
    try t.expect(std.mem.indexOf(u8, text, "myl_qbe_rc_frame") == null);
    try t.expect(std.mem.indexOf(u8, text, "rcentries") == null);
    try t.expect(std.mem.indexOf(u8, text, "slot_drop") == null);
    // A copyable counted slot routes a loan or held role apart from its owner
    // release. Both go through the static type's glue (RC-GLUE-1): the role
    // returns its holds (unloan), the owner drops, and neither looks the type
    // up in the runtime.
    // The manifest is JSON, so a label line starts after an escaped newline.
    const role = std.mem.indexOf(u8, text, "\\n@rcslotrole") orelse return error.TestUnexpectedResult;
    const owner = std.mem.indexOf(u8, text[role..], "\\n@rcslotowner") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, text[role .. role + owner], "# RC-GLUE-1 unloan") != null);
    try t.expect(std.mem.indexOf(u8, text[role + owner ..], "# RC-GLUE-1 drop") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_drop_role(") == null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_native_drop(") == null);
}

// spec-case: RC-EXIT-SCOPES-1
test "RC-EXIT-SCOPES-1 a frame with receiver scopes tests them at every return" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try language.Compilation.init(t.allocator, "teardown.my", nested_returns);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_scopes_close(") != null);
    try t.expect(std.mem.indexOf(u8, text, "@rcscopesopen") != null);
    // A receiver record starts inactive with one store, not a zero-fill call.
    try t.expect(std.mem.indexOf(u8, text, "memset(l %rcborrow") == null);
    try t.expect(std.mem.indexOf(u8, text, "%rcborrow") != null);
}
