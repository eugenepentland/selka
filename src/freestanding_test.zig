//! `@freestanding` at check time (MCU-NOC2): each rule's refusal with its message, and what the promise accepts.
const std = @import("std");
const language = @import("compiler.zig");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// The first diagnostic a check of `text` reports: its code and message.
fn refusal(text: []const u8, code: []const u8, piece: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "free.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, piece) != null);
}

fn accepted(text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "free.selka", text);
    defer c.deinit();
    try c.check();
}

test "a freestanding function refuses managed data in a local, a parameter and a text literal" {
    try refusal("@freestanding\nfunc f(x: int) -> int:\n    const names = [x]\n    return len(names)\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "a local has type `int[]`, which the runtime manages (rule: unmanaged data only)");
    try refusal("@freestanding\nfunc f(xs: int[]) -> int:\n    return 0\n\n\nfunc main() -> int:\n    return f([1])\n", "E_FREESTANDING", "a parameter has type `int[]`");
    try refusal("@freestanding\nfunc f(x: int) -> int:\n    const name = \"abc\"\n    return x\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "a local has type `str`");
}

test "a freestanding function calls only freestanding functions, extern funcs and inline built-ins" {
    try refusal("func plain(x: int) -> int:\n    return x\n\n\n@freestanding\nfunc f(x: int) -> int:\n    return plain(x)\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "`plain` is a function not marked @freestanding (rule: calls only of @freestanding functions, `extern func`s and inline built-ins)");
    try refusal("@freestanding\nfunc f(x: int) -> int:\n    debug(x)\n    return x\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "output: printing and writing a stream are runtime calls (rule: no runtime operations)");
    try refusal("@freestanding\nfunc f(out: Stream, x: int) -> int:\n    print(out, x)\n    return x\n\n\nfunc main(out: Stream) -> int:\n    return f(out, 1)\n", "E_FREESTANDING", "a parameter has type `Stream`");
    try refusal("func g(x: int) -> int:\n    return x\n\n\n@freestanding\nfunc f(x: int) -> int:\n    const h = g\n    return h(x)\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "func(int) -> int");
    try accepted("extern func twice(host: Host, x: int) -> int\n\n\n@freestanding\nfunc inner(x: int) -> int:\n    return x + 1\n\n\n@freestanding\nfunc outer(host: Host, x: int) -> int:\n    return twice(host, inner(x))\n\n\nfunc main() -> int:\n    return inner(41)\n");
}

test "a freestanding placement is `ram` or none, and an unknown word is refused" {
    try accepted("@freestanding(ram)\nfunc f(x: int) -> int:\n    return x + 1\n\n\nfunc main() -> int:\n    return f(1)\n");
    try refusal("@freestanding(flash)\nfunc f(x: int) -> int:\n    return x\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "unknown placement of a @freestanding function; the only placement is `ram`");
    try refusal("@freestanding()\nfunc f(x: int) -> int:\n    return x\n\n\nfunc main() -> int:\n    return f(1)\n", "E_SYNTAX", "");
}

test "a ram function calls only ram functions, extern funcs and inline built-ins" {
    try refusal("@freestanding\nfunc g(x: int) -> int:\n    return x\n\n\n@freestanding(ram)\nfunc f(x: int) -> int:\n    return g(x)\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "`g` is @freestanding but not placed in RAM, so its code is in flash (rule: a @freestanding(ram) function calls only @freestanding(ram) functions, `extern func`s and inline built-ins)");
    try refusal("func g(x: int) -> int:\n    return x\n\n\n@freestanding(ram)\nfunc f(x: int) -> int:\n    return g(x)\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "`g` is a function not marked @freestanding(ram)");
    // A flash function may call a ram one, and a ram one calls ram functions and extern funcs (register writes:
    // tests/lang/freestanding.selka).
    try accepted("extern func erase(host: Host, x: int) -> int\n\n\n@freestanding(ram)\nfunc inner(x: int) -> int:\n    return x + 1\n\n\n@freestanding(ram)\nfunc outer(host: Host, x: int) -> int:\n    return erase(host, inner(x))\n\n\n@freestanding\nfunc flash(x: int) -> int:\n    return inner(x)\n\n\nfunc main() -> int:\n    return flash(41)\n");
}

test "a freestanding assert takes no message and the attribute attaches to a function" {
    try refusal("@freestanding\nfunc f(x: int) -> int:\n    assert x > 0, \"positive\"\n    return x\n\n\nfunc main() -> int:\n    return f(1)\n", "E_FREESTANDING", "an `assert` takes no message");
    try accepted("@freestanding\nfunc f(x: int) -> int:\n    assert x > 0\n    return x\n\n\nfunc main() -> int:\n    return f(1)\n");
    try refusal("@freestanding\nrecord R:\n    x: int\n\n\nfunc main() -> int:\n    return 0\n", "E_ATTRIBUTE_TARGET", "@freestanding attaches to a function with a body");
}

/// Check `text` as a project, so it may import `cpu` and `registers` (a single unit cannot), and require that it checks clean.
fn projectAccepted(text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(), text);
    try checked.expectAccepted();
}

/// Check `text` as a project and require that its first diagnostic carries `code` and a message with `piece`.
fn projectRefusal(text: []const u8, code: []const u8, piece: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(), text);
    try t.expect(!checked.passed);
    const first = checked.firstError().?;
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, piece) != null);
}

/// The seven `cpu` functions that act on the machine, called from one function with the linear state held and restored.
const cpu_body = "    const held = cpu.interrupts_off(reg)\n    cpu.send_event(reg)\n    cpu.wait_for_event(reg)\n    cpu.wait_for_interrupt(reg)\n    cpu.barrier(reg)\n    cpu.breakpoint(reg)\n    cpu.interrupts_restore(reg, own held)\n";

test "a freestanding and a ram function call the cpu functions that act on the machine" {
    try projectAccepted("import cpu\nimport registers\n\n\n@freestanding\nfunc f(reg: Registers):\n" ++ cpu_body ++ "\n\nfunc main() -> int:\n    f(registers.simulated())\n    return 0\n");
    try projectAccepted("import cpu\nimport registers\n\n\n@freestanding(ram)\nfunc f(reg: Registers) -> u32:\n    const held = cpu.interrupts_off(reg)\n    const before = held.primask\n    cpu.barrier(reg)\n    cpu.interrupts_restore(reg, own held)\n    return before\n\n\nfunc main() -> int:\n    return int(f(registers.simulated()))\n");
    try projectAccepted("import cpu\nimport registers\n\n\n@freestanding(ram)\nfunc f(reg: Registers):\n" ++ cpu_body ++ "\n\nfunc main() -> int:\n    f(registers.simulated())\n    return 0\n");
}

test "the simulated bank's readers are refused by name in freestanding and ram code" {
    const message = "(rule: calls only of @freestanding functions, `extern func`s and inline built-ins)";
    try projectRefusal("import cpu\nimport registers\n\n\n@freestanding\nfunc f(reg: Registers) -> int:\n    return cpu.event_count(reg)\n\n\nfunc main() -> int:\n    return f(registers.simulated())\n", "E_FREESTANDING", "`cpu::event_count` is a built-in that calls the runtime " ++ message);
    try projectRefusal("import cpu\nimport registers\n\n\n@freestanding\nfunc f(reg: Registers) -> bool:\n    return cpu.interrupts_are_off(reg)\n\n\nfunc main() -> int:\n    return 0\n", "E_FREESTANDING", "`cpu::interrupts_are_off` is a function not marked @freestanding " ++ message);
    try projectRefusal("import cpu\nimport registers\n\n\n@freestanding(ram)\nfunc f(reg: Registers) -> bool:\n    return cpu.write_with_interrupts_off(reg, 0)\n\n\nfunc main() -> int:\n    return 0\n", "E_FREESTANDING", "`cpu::write_with_interrupts_off` is a function not marked @freestanding(ram)");
    try projectRefusal("import cpu\nimport registers\n\n\n@freestanding(ram)\nfunc f(reg: Registers) -> int:\n    return cpu.event_writes_before(reg, 0)\n\n\nfunc main() -> int:\n    return 0\n", "E_FREESTANDING", "`cpu::event_writes_before` is a built-in that calls the runtime");
}

test "an interrupt state held in a freestanding function checks as it does elsewhere" {
    try projectRefusal("import cpu\nimport registers\n\n\n@freestanding\nfunc f(reg: Registers):\n    const held = cpu.interrupts_off(reg)\n    cpu.barrier(reg)\n\n\nfunc main() -> int:\n    f(registers.simulated())\n    return 0\n", "E_LINEAR_UNCONSUMED", "");
    try projectRefusal("import cpu\nimport registers\n\n\n@freestanding(ram)\nfunc f(reg: Registers):\n    const held = cpu.interrupts_off(reg)\n    cpu.interrupts_restore(reg, own held)\n    cpu.interrupts_restore(reg, own held)\n\n\nfunc main() -> int:\n    f(registers.simulated())\n    return 0\n", "E_LINEAR_CONSUMED", "");
}
