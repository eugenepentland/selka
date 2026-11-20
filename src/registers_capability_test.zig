//! The `Registers` capability's checking (MCU-B1, MCU-B1D): the check accepts `main(reg: Registers)` on every target (a
//! build for a target without registers refuses it, `E_TARGET_CAPABILITY`, in `test/target_cli_test.zig`) and refuses
//! `Registers?`, which needs no grant (`E_MAIN`), a
//! task cannot take one (`E_TASK_CAPABILITY`), it has no text (`print`, `str` and a format hole refuse it), an ordinary
//! program cannot build a stand-in, and `registers.simulated()` allocates, so a `@noalloc` function may read and write a
//! bank but not make one. `tests/lang/registers_bank.selka` runs the accepted shapes.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

/// Check `source` as a project (so it may import `registers` and `parallel`) and require that it checks clean, or that
/// its first diagnostic carries `code` and a message containing `needle`.
fn expectFirst(source: []const u8, code: []const u8, needle: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(), source);
    if (code.len == 0) return checked.expectAccepted();
    try t.expect(!checked.passed);
    const first = checked.firstError().?;
    try t.expectEqualStrings(code, first.code);
    try t.expect(std.mem.indexOf(u8, first.message, needle) != null);
}

test "a program makes a simulated bank, and a record, a list and an option hold it" {
    try expectFirst(
        \\import registers
        \\
        \\record Device:
        \\    reg: Registers
        \\    base: u32
        \\
        \\func main(out: Stream) -> int:
        \\    const device = Device(reg=registers.simulated(), base=64)
        \\    const all = [device.reg, registers.simulated()]
        \\    const maybe: Registers? = Some(all[1])
        \\    registers.write32(all[0], device.base, 1)
        \\    print(out, registers.read32(device.reg, 64), maybe is None)
        \\    return 0
    , "", "");
}

test "the check accepts a main that asks for a Registers, and refuses a Registers? that needs no grant" {
    try expectFirst(
        \\import registers
        \\
        \\func main(reg: Registers) -> int:
        \\    return int(registers.read32(reg, 0x40000000))
    , "", "");
    try expectFirst(
        \\func main(out: Stream, reg: Registers?) -> int:
        \\    print(out, 1)
        \\    return 0
    , "E_MAIN", "`Stop` or `Registers` needs no grant");
}

test "a Registers has no text: print, str and a format hole refuse it" {
    try expectFirst(
        \\import registers
        \\
        \\func main(out: Stream) -> int:
        \\    const reg = registers.simulated()
        \\    print(out, reg)
        \\    return 0
    , "E_IO_ARGUMENT", "capabilities");
    try expectFirst(
        \\import registers
        \\
        \\func main(out: Stream) -> int:
        \\    const reg = registers.simulated()
        \\    print(out, str(reg))
        \\    return 0
    , "E_TEXT_CONVERSION", "`str` of `Registers` is refused");
    try expectFirst(
        \\import registers
        \\
        \\func main(out: Stream) -> int:
        \\    const reg = registers.simulated()
        \\    print(out, f"{reg}")
        \\    return 0
    , "E_TEXT_CONVERSION", "interpolation requires a value with a rendering");
}

test "a task cannot take a Registers" {
    try expectFirst(
        \\import parallel
        \\import registers
        \\
        \\func probe(n: int, reg: Registers) -> int:
        \\    return int(registers.read8(reg, 0)) + n
        \\
        \\func main(out: Stream) -> int:
        \\    const reg = registers.simulated()
        \\    const results = parallel.map([1, 2], probe, reg)
        \\    print(out, len(results))
        \\    return 0
    , "E_TASK_CAPABILITY", "`Registers`");
}

test "an ordinary program cannot build a Registers stand-in directly" {
    try expectFirst(
        \\func main(out: Stream) -> int:
        \\    const reg = __stand_in[Registers](0)
        \\    print(out, 1)
        \\    return 0
    , "E_INTERNAL_NAME", "__stand_in");
}

test "a Registers has no methods, and the message names the function form" {
    try expectFirst(
        \\import registers
        \\
        \\func main(out: Stream) -> int:
        \\    const reg = registers.simulated()
        \\    print(out, reg.read32(0))
        \\    return 0
    , "E_UNKNOWN_TYPE", "registers.read32(reg, 0)");
}

test "R_REGISTER_BANK has a row in the diagnostic code index that points at the I/O guide" {
    const row = for (@import("diagnostic_codes.zig").entries) |entry| {
        if (std.mem.eql(u8, entry.code, "R_REGISTER_BANK")) break entry;
    } else return error.TestUnexpectedResult;
    try t.expectEqualStrings("io", row.guide);
    try t.expect(std.mem.indexOf(u8, row.meaning, "registers.simulated()") != null);
}

test "registers.start_core1 takes the Registers and a top-level func(Registers) -> int, and answers a bool (MCU-CORE1)" {
    try expectFirst(
        \\import registers
        \\
        \\func counter(reg: Registers) -> int:
        \\    registers.write32(reg, 0xD0000054, 1)
        \\    return 7
        \\
        \\func main(reg: Registers) -> int:
        \\    const started: bool = registers.start_core1(reg, counter)
        \\    if started:
        \\        return 0
        \\    return 1
    , "", "");
    try expectFirst(
        \\import registers
        \\
        \\func counter(reg: Registers) -> bool:
        \\    return registers.read32(reg, 0) == 0
        \\
        \\func main(reg: Registers) -> int:
        \\    if registers.start_core1(reg, counter):
        \\        return 0
        \\    return 1
    , "E_TYPE", "expected func(registers_cap) -> int, found func(registers_cap) -> bool");
    try expectFirst(
        \\import registers
        \\
        \\func counter(reg: Registers, step: int) -> int:
        \\    registers.write32(reg, 0, 1)
        \\    return step
        \\
        \\func main(reg: Registers) -> int:
        \\    if registers.start_core1(reg, counter):
        \\        return 0
        \\    return 1
    , "E_TYPE", "expected func(registers_cap) -> int, found func(registers_cap, int) -> int");
}

test "E_TARGET_DEVICE_REGISTERS has a row in the diagnostic code index that points at the I/O guide" {
    const row = for (@import("diagnostic_codes.zig").entries) |entry| {
        if (std.mem.eql(u8, entry.code, "E_TARGET_DEVICE_REGISTERS")) break entry;
    } else return error.TestUnexpectedResult;
    try t.expectEqualStrings("io", row.guide);
    try t.expect(std.mem.indexOf(u8, row.meaning, "start_core1") != null);
}

/// A program whose `select` holds interrupts off around two register writes; `ending` is how it leaves the hold (MCU-NOC1).
fn heldProgram(comptime ending: []const u8) []const u8 {
    return "import cpu\nimport registers\n\nfunc select(reg: Registers, fast: bool) -> int:\n" ++
        "    const held = cpu.interrupts_off(reg)\n    registers.write32(reg, 0x40018000, 0)\n" ++ ending ++
        "    return 0\n\nfunc main(out: Stream) -> int:\n    print(out, select(registers.simulated(), True))\n    return 0\n";
}

test "cpu.interrupts_off answers a state that interrupts_restore must take: once, on every path (MCU-NOC1)" {
    try expectFirst(heldProgram("    cpu.interrupts_restore(reg, own held)\n"), "", "");
    // The restore forgotten, on every path and on one.
    try expectFirst(heldProgram(""), "E_LINEAR_UNCONSUMED", "`@linear` owner `held` is not consumed");
    try expectFirst(heldProgram("    if fast:\n        return 1\n    cpu.interrupts_restore(reg, own held)\n"), "E_LINEAR_UNCONSUMED", "`held` is not consumed");
    // Restored twice, and the state thrown away.
    try expectFirst(heldProgram("    cpu.interrupts_restore(reg, own held)\n    cpu.interrupts_restore(reg, own held)\n"), "E_LINEAR_CONSUMED", "`held` was already consumed");
    try expectFirst(
        \\import cpu
        \\import registers
        \\
        \\func main(out: Stream) -> int:
        \\    _ = cpu.interrupts_off(registers.simulated())
        \\    print(out, 1)
        \\    return 0
    , "E_LINEAR_USE", "a `@linear` value cannot be discarded");
}

test "only module cpu makes or ends an InterruptState: no forged state and no end by its field (MCU-NOC1)" {
    try expectFirst(heldProgram("    cpu.interrupts_restore(reg, own held)\n    cpu.interrupts_restore(reg, own cpu.InterruptState(primask=0))\n"), "E_SEALED_RECORD", "`cpu.InterruptState` is sealed");
    try expectFirst(heldProgram("    const primask = own held.primask\n    registers.write32(reg, 0x40018000, primask)\n"), "E_SEALED_RECORD", "ends the sealed `@linear` `cpu.InterruptState` outside module `cpu`");
}
