//! `--target`: an unknown name is refused with the names that are known, a bare target only
//! builds (`run`, `build --run` and `test` refuse it) (MCU-A1); a capability `main` asks for that
//! the target does not provide is refused at its parameter (MCU-A1B); a bare build links the bare
//! runtime with the platform's `--link` file into an ARM image laid out by `--linker-script`,
//! refuses a build without a script and a program that needs the host's number-text runtime, and
//! the image runs on QEMU when `qemu-system-arm` is on PATH (MCU-A2P2); a device `main` takes a `Host` and calls C
//! through `extern func`, and `debug` links without the platform defining its runtime function (MCU-EXT).
const std = @import("std");
const testing = std.testing;

/// The `selka` executable under test, which `zig build` names at run time (TEST-PATHS-1).
fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

/// Run the compiler with the shared stores disabled, as the other command-line tests do.
fn privateRun(a: std.mem.Allocator, argv: []const []const u8) !std.process.RunResult {
    var environment = try @import("test_paths").privateEnvironment(a);
    defer environment.deinit();
    return std.process.run(a, testing.io, .{ .argv = argv, .environ_map = &environment });
}

const list_program =
    \\record Led:
    \\    pin: u32
    \\    on: bool
    \\
    \\func label(n: int) -> str:
    \\    return f"led {n}"
    \\
    \\func main() -> int:
    \\    mut led = Led(pin=25u32, on=False)
    \\    mut names: str[] = []
    \\    for i in range(40):
    \\        led.on = not led.on
    \\        append(mut names, label(i))
    \\    return len(names[39]) + int(led.pin % 7u32)
    \\
;

const dict_program =
    \\func main() -> int:
    \\    mut counts: dict[str, int] = {}
    \\    mut seen: dict[int, int] = {}
    \\    for i in range(50):
    \\        const key = f"k{i % 7}"
    \\        if key in counts:
    \\            counts[key] = counts[key] + 1
    \\        else:
    \\            counts[key] = 1
    \\        seen[i * 3] = i
    \\    return counts["k3"] + len(seen) + seen[9]
    \\
;

/// The host vectorizes this loop (its text calls `llvm.x86.avx2`); the bare target keeps it scalar.
const summing_program =
    \\func checksum(values: int[]) -> int:
    \\    mut total = 0
    \\    for v in values:
    \\        total = total + v * 31
    \\    return total
    \\
    \\func main() -> int:
    \\    mut values: int[] = []
    \\    for i in range(16):
    \\        append(mut values, i)
    \\    return checksum(values) % 200
    \\
;

/// The QEMU platform of `scripts/bare/` (declared in `build_test_inputs.zig`): its hooks and its linker script.
const qemu_platform = "scripts/bare/qemu/platform.c";
const qemu_script = "scripts/bare/qemu/link.ld";
const only_builds = "the target `thumbv6m-none` only builds";

/// `main` asks for a `Stream` and a `Filesystem?`: the host provides both, the bare target neither.
const capability_program =
    \\func main(out: Stream, _fs: Filesystem?) -> int:
    \\    print(out, "blink")
    \\    return 0
    \\
;

/// Build `source` for the target `target_name` with `--emit-llvm` into `dir`, adding `extra` (a bare build's platform file
/// and linker script) to the command line.
fn targetBuild(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, source: []const u8, target_name: []const u8, extra: []const []const u8) !std.process.RunResult {
    const file = try std.fmt.allocPrint(a, "{s}.selka", .{name});
    try dir.writeFile(testing.io, .{ .sub_path = file, .data = source });
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, file });
    const output = try std.fs.path.join(a, &.{ root, name });
    const llvm = try std.fmt.allocPrint(a, "{s}.ll", .{output});
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const head = [_][]const u8{ compilerPath(), "build", "--target", target_name, path, "-o", output, "--emit-llvm", llvm, "--cache-dir", cache };
    return privateRun(a, try std.mem.concat(a, []const u8, &.{ &head, extra }));
}

/// Build `source` for the host.
fn hostBuild(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, source: []const u8) !std.process.RunResult {
    return targetBuild(a, dir, name, source, "x86_64-linux", &.{});
}

test "a bare build refuses each capability main asks for at its parameter; the host builds the same program" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const bare = try targetBuild(a, temp.dir, "caps", capability_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, bare.term);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "caps.selka:1:11: error[E_TARGET_CAPABILITY]: `Stream` is not provided on the target `thumbv6m-none`") != null);
    try testing.expect(std.mem.indexOf(u8, bare.stderr, "caps.selka:1:24: error[E_TARGET_CAPABILITY]: `Filesystem` is not provided on the target `thumbv6m-none`, which provides `Host` and `Registers`; remove the parameter") != null);
    const host = try hostBuild(a, temp.dir, "caps", capability_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, host.term);
    try testing.expect(std.mem.indexOf(u8, host.stderr, "E_TARGET_CAPABILITY") == null);
    try temp.dir.access(testing.io, "caps", .{});
}

/// The C a device program calls through `extern func` (MCU-EXT): a computed value, and four scalars of three widths (the
/// `int64_t` takes r2:r3 under AAPCS, so the last two go on the stack).
const extern_c =
    \\#include <stdint.h>
    \\int32_t square_plus(int32_t x) { return x * x + 1; }
    \\int32_t mix(int32_t a, int64_t b, uint8_t c, int32_t d) { return a * 1000 + (int32_t)b * 100 + (int32_t)c * 10 + d; }
    \\
;

/// `main(PARAMETERS)` calls both functions of `extern_c` and answers 1234 - 20 * 50 = 234 (plus a register read, for a
/// `main` that also takes the registers).
fn hostProgram(a: std.mem.Allocator, parameters: []const u8, registers_term: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a,
        \\{s}
        \\extern func square_plus(host: Host, x: i32) -> i32
        \\
        \\extern func mix(host: Host, a: i32, b: i64, c: u8, d: i32) -> i32
        \\
        \\func main({s}) -> int:
        \\    const computed = square_plus(host, 7)
        \\    return int(mix(host, 1, 2, 3, 4)) - 20 * int(computed){s}
        \\
    , .{ if (registers_term.len == 0) "" else "import registers\n", parameters, registers_term });
}

/// Build `source` for the bare target with the QEMU platform file, the C file `extern_c` and the linker script.
fn externBuild(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, source: []const u8) !std.process.RunResult {
    try dir.writeFile(testing.io, .{ .sub_path = "extern.c", .data = extern_c });
    const c_path = try std.fs.path.join(a, &.{ try dir.realPathFileAlloc(testing.io, ".", a), "extern.c" });
    return targetBuild(a, dir, name, source, "thumbv6m-none", &.{ "--link", qemu_platform, "--link", c_path, "--linker-script", qemu_script });
}

test "a device main takes a Host alone or beside Registers in either order, and each extern func call is a plain call of the C symbol" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const alone = try externBuild(a, temp.dir, "alone", try hostProgram(a, "host: Host", ""));
    try testing.expectEqualStrings("", alone.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, alone.term);
    const llvm = try temp.dir.readFileAlloc(testing.io, "alone.ll", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, llvm, "call i32 @mix(i32 1, i64 2, i8 zeroext 3, i32 4)") != null);
    try testing.expect(std.mem.indexOf(u8, llvm, "call i32 @square_plus(i32 7)") != null);
    const term = " + int(registers.read32(reg, 0x40004008))";
    const first = try externBuild(a, temp.dir, "first", try hostProgram(a, "reg: Registers, host: Host", term));
    try testing.expectEqualStrings("", first.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, first.term);
    const second = try externBuild(a, temp.dir, "second", try hostProgram(a, "host: Host, reg: Registers", term));
    try testing.expectEqualStrings("", second.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, second.term);
    const optional = try externBuild(a, temp.dir, "optional",
        \\extern func square_plus(host: Host, x: i32) -> i32
        \\
        \\func main(maybe: Host?) -> int:
        \\    match maybe:
        \\        case Some(host):
        \\            return int(square_plus(host, 3))
        \\        case None:
        \\            return 7
        \\
    );
    try testing.expectEqualStrings("", optional.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, optional.term);
    const ran = try onQemu(a, try std.fs.path.join(a, &.{ try temp.dir.realPathFileAlloc(testing.io, ".", a), "alone" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 234 }, ran.term);
    const given = try onQemu(a, try std.fs.path.join(a, &.{ try temp.dir.realPathFileAlloc(testing.io, ".", a), "optional" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 10 }, given.term);
}

/// A device program whose `debug` line the bare runtime writes through the platform's `myl_bare_write`.
const debug_program =
    \\func main() -> int:
    \\    debug(41 + 1)
    \\    return 3
    \\
;

test "debug links on the bare target without the platform's stand-in, and a platform that still defines it keeps linking with its own" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(a, temp.dir, "debugs", debug_program);
    try testing.expectEqualStrings("", built.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    const ran = try onQemu(a, built.output);
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, ran.term);
    try testing.expect(std.mem.startsWith(u8, ran.stderr, "42\nmyl-bare: status 3"));
    // The runtime's definition is weak: a platform's own one wins. A `debug` line is two writes (the text, then the
    // newline), so the stand-in's mark comes twice.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "stand_in.c", .data =
        \\#include <stddef.h>
        \\#include <stdint.h>
        \\void myl_bare_write(int stream, const unsigned char *bytes, size_t length);
        \\void myl_core_span_stream_write(int64_t fd, const unsigned char *data, uint64_t length) {
        \\    myl_bare_write((int)fd, (const unsigned char *)"platform: ", 10);
        \\    myl_bare_write((int)fd, data, (size_t)length);
        \\}
        \\
    });
    const stand_in = try std.fs.path.join(a, &.{ try temp.dir.realPathFileAlloc(testing.io, ".", a), "stand_in.c" });
    const own = try targetBuild(a, temp.dir, "own", debug_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--link", stand_in, "--linker-script", qemu_script });
    try testing.expectEqualStrings("", own.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, own.term);
    const own_ran = try onQemu(a, try std.fs.path.join(a, &.{ try temp.dir.realPathFileAlloc(testing.io, ".", a), "own" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 3 }, own_ran.term);
    try testing.expect(std.mem.startsWith(u8, own_ran.stderr, "platform: 42platform: \n"));
}

/// A device program: `main` receives the registers and reads one back.
const register_program =
    \\import registers
    \\
    \\func main(reg: Registers) -> int:
    \\    registers.write32(reg, 0x40004008, 1)
    \\    return int(registers.read32(reg, 0x40004008))
    \\
;

test "a host build refuses a main that asks for a Registers and says a test makes one; a bare build links it as volatile accesses" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const host = try hostBuild(a, temp.dir, "device", register_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, host.term);
    try testing.expect(std.mem.indexOf(u8, host.stderr, "device.selka:3:11: error[E_TARGET_CAPABILITY]: a `Registers` is provided only on a device target") != null);
    try testing.expect(std.mem.indexOf(u8, host.stderr, "a test makes one with `registers.simulated()`") != null);
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "device", .{}));
    const built = try bareBuild(a, temp.dir, "device", register_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "store volatile i32") != null and std.mem.indexOf(u8, built.llvm, "load volatile i32") != null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "myl_core_registers_") == null);
    try testing.expectEqual(built.image.reset, built.image.entry);
}

/// A program that makes a simulated bank, which only a host has.
const simulated_program =
    \\import registers
    \\
    \\func main(args: str[]) -> int:
    \\    const reg = registers.simulated()
    \\    registers.write32(reg, 0x10, 5)
    \\    return int(registers.read32(reg, 0x10)) + len(args)
    \\
;

test "a bare build refuses a program that makes a simulated register bank, naming the function; the host builds it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const refused = try targetBuild(arena.allocator(), temp.dir, "bank", simulated_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[E_TARGET_SIMULATED_REGISTERS]: the program calls `registers.simulated`, which only a simulated register bank has") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "undefined symbol") == null);
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "bank", .{}));
    const hosted = try hostBuild(arena.allocator(), temp.dir, "bank", simulated_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, hosted.term);
}

/// A device program that runs every `cpu` instruction (MCU-NOC1); it is linked, never run (`wfi` and `bkpt` would stop it).
const cpu_program =
    \\import cpu
    \\import registers
    \\
    \\func main(reg: Registers) -> int:
    \\    const held = cpu.interrupts_off(reg)
    \\    registers.write32(reg, 0x40004008, 1)
    \\    const before = held.primask
    \\    cpu.interrupts_restore(reg, own held)
    \\    cpu.send_event(reg)
    \\    cpu.wait_for_event(reg)
    \\    cpu.wait_for_interrupt(reg)
    \\    cpu.barrier(reg)
    \\    cpu.breakpoint(reg)
    \\    return int(before)
    \\
;

test "a bare build emits each cpu operation as its instruction, inline assembly with no runtime call, and links it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(a, temp.dir, "instructions", cpu_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    const lines = [_][]const u8{
        "call void asm sideeffect \"wfe\", \"~{memory}\"()",
        "call void asm sideeffect \"wfi\", \"~{memory}\"()",
        "call void asm sideeffect \"sev\", \"~{memory}\"()",
        "call void asm sideeffect \"dsb sy\\0Aisb sy\", \"~{memory}\"()",
        "call void asm sideeffect \"bkpt #0\", \"~{memory}\"()",
        "call i32 asm sideeffect \"mrs $0, primask\\0Acpsid i\", \"=r,~{memory}\"()",
        "call void asm sideeffect \"msr primask, $0\", \"r,~{memory}\"(i32 ",
    };
    for (lines) |line| try testing.expect(std.mem.indexOf(u8, built.llvm, line) != null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "myl_core_registers_") == null);
    // The image holds the instructions' Thumb encodings: `dsb sy`, `isb sy`, `cpsid i`, `sev` and `wfe`.
    const image = try temp.dir.readFileAlloc(testing.io, "instructions", a, .unlimited);
    for ([_][]const u8{ "\xbf\xf3\x4f\x8f", "\xbf\xf3\x6f\x8f", "\x72\xb6", "\x40\xbf", "\x20\xbf" }) |code| try testing.expect(std.mem.indexOf(u8, image, code) != null);
}

/// A device program that reads the `cpu` event log, which only a simulated bank keeps.
const cpu_log_program =
    \\import cpu
    \\
    \\func main(reg: Registers) -> int:
    \\    cpu.send_event(reg)
    \\    return cpu.event_count(reg)
    \\
;

test "a bare build refuses a program that reads the cpu event log, naming the function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const refused = try targetBuild(arena.allocator(), temp.dir, "log", cpu_log_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[E_TARGET_SIMULATED_REGISTERS]: the program calls `cpu.event_count`, which only a simulated register bank has") != null);
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "log", .{}));
}

/// A program that starts a second core, which only a device has (MCU-CORE1); on the host its bank is a simulated one.
const second_core_program =
    \\import registers
    \\
    \\func spin(reg: Registers) -> int:
    \\    registers.write32(reg, 0x10, 1)
    \\    return 0
    \\
    \\func main(args: str[]) -> int:
    \\    if registers.start_core1(registers.simulated(), spin):
    \\        return 1
    \\    return len(args)
    \\
;

test "a hosted build refuses a program that starts the second core, naming the function, and leaves no executable" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const refused = try hostBuild(arena.allocator(), temp.dir, "cores", second_core_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[E_TARGET_DEVICE_REGISTERS]: the program calls `registers.start_core1`, which only a device has") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "undefined symbol") == null);
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "cores", .{}));
}

test "a bare build of a main that takes only args links an image" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(arena.allocator(), temp.dir, "argv", "func main(args: str[]) -> int:\n    return len(args)\n");
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expect(std.mem.indexOf(u8, built.run.stderr, "E_TARGET_CAPABILITY") == null);
    try testing.expectEqual(built.image.reset, built.image.entry);
}

/// What a test reads of a linked bare image: its ELF type and machine, its entry, and the reset handler its vector table
/// (`.vectors`, the first words of the image) names. The image has no symbol table, so the entry is checked against the
/// reset vector, which is `myl_bare_reset` (`runtime/bare/core_bare.c`).
const Image = struct { kind: u16, machine: u16, entry: u32, reset: u32 };

/// Read `bytes` as a 32-bit little-endian ELF.
fn armImage(bytes: []const u8) !Image {
    if (bytes.len < 52 or !std.mem.eql(u8, bytes[0..4], "\x7fELF") or bytes[4] != 1 or bytes[5] != 1) return error.NotElf32;
    const word = struct {
        fn at(data: []const u8, offset: usize) u32 {
            return std.mem.readInt(u32, data[offset..][0..4], .little);
        }
    }.at;
    const half = struct {
        fn at(data: []const u8, offset: usize) u16 {
            return std.mem.readInt(u16, data[offset..][0..2], .little);
        }
    }.at;
    const sections: usize = word(bytes, 32);
    const size: usize = half(bytes, 46);
    const count: usize = half(bytes, 48);
    const names: usize = word(bytes, sections + @as(usize, half(bytes, 50)) * size + 16);
    for (0..count) |index| {
        const header = sections + index * size;
        const name = bytes[names + @as(usize, word(bytes, header)) ..];
        if (!std.mem.startsWith(u8, name, ".vectors\x00")) continue;
        return .{ .kind = half(bytes, 16), .machine = half(bytes, 18), .entry = word(bytes, 24), .reset = word(bytes, word(bytes, header + 16) + 4) };
    }
    return error.NoVectors;
}

/// Build `source` for the bare target with `--emit-llvm`, the QEMU platform file and its linker script, and return the build,
/// the LLVM text it wrote, the image's path and what the image says of itself.
fn bareBuild(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, source: []const u8) !struct { run: std.process.RunResult, llvm: []const u8, output: []const u8, image: Image } {
    const run = try targetBuild(a, dir, name, source, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    const llvm = try dir.readFileAlloc(testing.io, try std.fmt.allocPrint(a, "{s}.ll", .{name}), a, .unlimited);
    const image = try armImage(try dir.readFileAlloc(testing.io, name, a, .unlimited));
    return .{ .run = run, .llvm = llvm, .output = try std.fs.path.join(a, &.{ try dir.realPathFileAlloc(testing.io, ".", a), name }), .image = image };
}

/// Run the image at `path` on QEMU's mps2-an385 board with semihosting, which ends QEMU with the program's status. A machine
/// without `qemu-system-arm` on PATH skips the test that asks, never passes it.
fn onQemu(a: std.mem.Allocator, path: []const u8) !std.process.RunResult {
    const argv = [_][]const u8{ "qemu-system-arm", "-M", "mps2-an385", "-nographic", "-monitor", "none", "-serial", "none", "-semihosting-config", "enable=on,target=native", "-kernel", path };
    return privateRun(a, &argv) catch |err| switch (err) {
        error.FileNotFound => error.SkipZigTest,
        else => err,
    };
}

/// Which parts of the two-core runtime (MCU-CORE1) a bare image holds, by text only they carry (the image has no symbol
/// table): the locked log's prefix of core 1's lines (`myl_bare_log_write`) and the emulated TLS's line when its table is
/// full (`__emutls_get_address`, whose copies are made in each core's arena).
const TwoCoreRuntime = struct { log: bool, tls: bool };

fn twoCoreRuntime(image: []const u8) TwoCoreRuntime {
    return .{
        .log = std.mem.indexOf(u8, image, "core 1: ") != null,
        .tls = std.mem.indexOf(u8, image, "the runtime has room for 96 thread-local variables") != null,
    };
}

/// Build `source` for the QEMU device with `--release` as `name`, and return the build and the image's bytes.
fn bareRelease(a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, source: []const u8) !struct { run: std.process.RunResult, llvm: []const u8, image: []const u8, output: []const u8 } {
    const run = try targetBuild(a, dir, name, source, "thumbv6m-none", &.{ "--release", "--link", qemu_platform, "--linker-script", qemu_script });
    const llvm = try dir.readFileAlloc(testing.io, try std.fmt.allocPrint(a, "{s}.ll", .{name}), a, .unlimited);
    const output = try std.fs.path.join(a, &.{ try dir.realPathFileAlloc(testing.io, ".", a), name });
    return .{ .run = run, .llvm = llvm, .image = try dir.readFileAlloc(testing.io, name, a, .unlimited), .output = output };
}

test "a device image that never starts the second core has the one-core runtime: plain free lists, no emulated TLS, no locked log" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const source =
        \\func numbers(count: int) -> int[]:
        \\    mut values: int[] = []
        \\    for i in range(count):
        \\        append(mut values, i)
        \\    return values
        \\
        \\func main(args: str[]) -> int:
        \\    mut total = 0
        \\    for round in range(4):
        \\        for value in numbers(10 + round + len(args)):
        \\            total += value
        \\    return total % 256
        \\
    ;
    const built = try bareBuild(a, temp.dir, "lists", source);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "@myl_core_free_lists = external global [33 x ptr]") != null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "emutls") == null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "thread_local") == null);
    try testing.expectEqual(TwoCoreRuntime{ .log = false, .tls = false }, twoCoreRuntime(try temp.dir.readFileAlloc(testing.io, "lists", a, .unlimited)));
    const release = try bareRelease(a, temp.dir, "lists_release", source);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release.run.term);
    try testing.expect(std.mem.indexOf(u8, release.llvm, "emutls") == null);
    try testing.expectEqual(TwoCoreRuntime{ .log = false, .tls = false }, twoCoreRuntime(release.image));
    const ran = try onQemu(a, built.output);
    try testing.expectEqual(std.process.Child.Term{ .exited = 244 }, ran.term); // 45 + 55 + 66 + 78
    try testing.expect(std.mem.indexOf(u8, try std.mem.concat(a, u8, &.{ ran.stdout, ran.stderr }), "myl-bare: status 244, live blocks 0,") != null);
}

/// A device program that starts the second core around lists it builds and frees (a returned list is freed through the
/// free lists' inline path); on QEMU's one core the start answers False and `main` answers 42.
const starts_core1_program =
    \\import registers
    \\
    \\func spin(reg: Registers) -> int:
    \\    registers.write32(reg, 0x20000000, 1)
    \\    return 1
    \\
    \\func numbers(count: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(count):
    \\        append(mut values, i)
    \\    return values
    \\
    \\func sums(rounds: int) -> int:
    \\    mut total = 0
    \\    for round in range(rounds):
    \\        for value in numbers(round + 1):
    \\            total += value
    \\    return total
    \\
    \\func main(reg: Registers) -> int:
    \\    const before = sums(10)
    \\    if registers.start_core1(reg, spin):
    \\        return 2
    \\    if before != sums(10):
    \\        return 1
    \\    return 42
    \\
;

test "a device image that starts the second core has the two-core runtime and asks for the calling core's free lists, plain and --release" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(a, temp.dir, "cores", starts_core1_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    // Each core has its own free lists (MCU-CORE1): the emulated thread-local variable's copy, asked for, never native TLS.
    try testing.expect(std.mem.indexOf(u8, built.llvm, "call ptr @__emutls_get_address(ptr @__emutls_v.myl_core_free_lists)") != null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "@myl_core_free_lists") == null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "thread_local") == null);
    try testing.expectEqual(TwoCoreRuntime{ .log = true, .tls = true }, twoCoreRuntime(try temp.dir.readFileAlloc(testing.io, "cores", a, .unlimited)));
    const release = try bareRelease(a, temp.dir, "cores_release", starts_core1_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release.run.term);
    try testing.expect(std.mem.indexOf(u8, release.llvm, "call ptr @__emutls_get_address(ptr @__emutls_v.myl_core_free_lists)") != null);
    try testing.expectEqual(TwoCoreRuntime{ .log = true, .tls = true }, twoCoreRuntime(release.image));
    for ([_][]const u8{ built.output, release.output }) |image| {
        const ran = try onQemu(a, image);
        try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, ran.term);
        try testing.expect(std.mem.indexOf(u8, try std.mem.concat(a, u8, &.{ ran.stdout, ran.stderr }), "myl-bare: status 42, live blocks 0,") != null);
    }
}

/// A device program with `@freestanding(ram)` functions that also starts the second core (MCU-NOC2E): the second core's
/// entry is a ram function, started by value from `main` in flash; QEMU's one core refuses the start and `main` goes on.
const ram_core1_program =
    \\import registers
    \\
    \\
    \\@freestanding(ram)
    \\func spin(reg: Registers) -> int:
    \\    registers.write32(reg, 0x20000000, 1)
    \\    return 1
    \\
    \\
    \\@freestanding(ram)
    \\func mix(words: FixedArray[u32, 4]) -> u32:
    \\    mut total: u32 = 0
    \\    for i in range(4):
    \\        total = total + words[i]
    \\    return bit_and(bit_xor(total, 0x80), 0x3F)
    \\
    \\
    \\func main(reg: Registers) -> int:
    \\    mut values: int[] = []
    \\    for i in range(10):
    \\        append(mut values, i)
    \\    if registers.start_core1(reg, spin):
    \\        return 2
    \\    return int(mix(FixedArray[u32, 4]([0x11, 0x22, 0x33, 0x44])))
    \\
;

/// The `define` line of the function `name` in `llvm`, up to its opening brace.
fn defineLine(llvm: []const u8, name: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, llvm, name) orelse return "";
    const start = std.mem.lastIndexOfScalar(u8, llvm[0..at], '\n') orelse 0;
    return llvm[start .. std.mem.indexOfScalarPos(u8, llvm, at, '{') orelse llvm.len];
}

test "a device image with ram functions that starts the second core has both: the two-core runtime and a passing ram image check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(a, temp.dir, "ramcores", ram_core1_program);
    try testing.expectEqualStrings("", built.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expect(std.mem.indexOf(u8, defineLine(built.llvm, "\"my.ramcores::spin\"("), "section \".ramfunc\"") != null);
    try testing.expect(std.mem.indexOf(u8, defineLine(built.llvm, "\"my.ramcores::main\"("), ".ramfunc") == null);
    try testing.expectEqual(TwoCoreRuntime{ .log = true, .tls = true }, twoCoreRuntime(try temp.dir.readFileAlloc(testing.io, "ramcores", a, .unlimited)));
    const release = try bareRelease(a, temp.dir, "ramcores_release", ram_core1_program);
    try testing.expectEqualStrings("", release.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release.run.term);
    try testing.expectEqual(TwoCoreRuntime{ .log = true, .tls = true }, twoCoreRuntime(release.image));
    for ([_][]const u8{ built.output, release.output }) |image| {
        const ran = try onQemu(a, image);
        try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, ran.term);
        try testing.expect(std.mem.indexOf(u8, try std.mem.concat(a, u8, &.{ ran.stdout, ran.stderr }), "myl-bare: status 42, live blocks 0,") != null);
    }
}

/// The text only the bare runtime's fault decoder holds (`core_bare.c`, `myl_bare_fault_frame`): the names of an assertion's
/// clauses, which a program's own traps spell through their kinds. (Its table of code names comes with it.)
fn holdsFaultDecoder(image: []const u8) bool {
    return std.mem.indexOf(u8, image, "R_INVARIANT") != null and std.mem.indexOf(u8, image, "R_ENSURES") != null;
}

/// A device program with no freestanding function that traps (an index out of range) after its lists are built.
const plain_trapping_program =
    \\func numbers(count: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(count):
    \\        append(mut values, i)
    \\    return values
    \\
    \\func main(args: str[]) -> int:
    \\    const values = numbers(3 + len(args))
    \\    return values[len(args) + 5]
    \\
;

/// A device program whose `@freestanding` function indexes out of range on its fifth call: line 3 is the failed check.
const freestanding_fault_program =
    \\@freestanding
    \\func pick(words: FixedArray[u32, 4], index: int) -> u32:
    \\    return words[index]
    \\
    \\
    \\func main() -> int:
    \\    const words = FixedArray[u32, 4]([1, 2, 3, 4])
    \\    mut total: u32 = 0
    \\    for i in range(6):
    \\        total = total + pick(words, i)
    \\    return int(total)
    \\
;

test "a device image with no freestanding function carries no fault decoder, plain and --release; one with a freestanding fault carries it and reports the fault" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    // No freestanding function: no fault site in the text, and no decoder in the image (the plain handler is main's).
    const plain = try bareBuild(a, temp.dir, "plain", plain_trapping_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain.run.term);
    try testing.expect(std.mem.indexOf(u8, plain.llvm, "udf #83") == null);
    try testing.expect(!holdsFaultDecoder(try temp.dir.readFileAlloc(testing.io, "plain", a, .unlimited)));
    const plain_release = try bareRelease(a, temp.dir, "plain_release", plain_trapping_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain_release.run.term);
    try testing.expect(std.mem.indexOf(u8, plain_release.llvm, "udf #83") == null);
    try testing.expect(!holdsFaultDecoder(plain_release.image));
    // A freestanding fault site: the decoder is linked, in both modes.
    const faulting = try bareBuild(a, temp.dir, "fault", freestanding_fault_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, faulting.run.term);
    try testing.expect(std.mem.indexOf(u8, faulting.llvm, "asm sideeffect \"udf #83\"") != null);
    try testing.expect(holdsFaultDecoder(try temp.dir.readFileAlloc(testing.io, "fault", a, .unlimited)));
    const faulting_release = try bareRelease(a, temp.dir, "fault_release", freestanding_fault_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, faulting_release.run.term);
    try testing.expect(holdsFaultDecoder(faulting_release.image));
    // The plain program's trap is its own, and the freestanding one's fault is decoded: the code and the place.
    const trapped = try onQemu(a, plain.output);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, trapped.term);
    try testing.expect(std.mem.indexOf(u8, try std.mem.concat(a, u8, &.{ trapped.stdout, trapped.stderr }), "error[R_LIST_BOUNDS]") != null);
    for ([_][]const u8{ faulting.output, faulting_release.output }, [_][]const u8{ "fault.selka:3\n", "fault_release.selka:3\n" }) |image, place| {
        const ran = try onQemu(a, image);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
        const said = try std.mem.concat(a, u8, &.{ ran.stdout, ran.stderr });
        try testing.expect(std.mem.indexOf(u8, said, "error[R_LIST_BOUNDS] ") != null);
        try testing.expect(std.mem.indexOf(u8, said, place) != null);
    }
}

/// A device program that starts the second core and has a `@freestanding` function whose check fails (line 5): both flavours.
const starts_core1_and_faults_program =
    \\import registers
    \\
    \\@freestanding
    \\func pick(words: FixedArray[u32, 4], index: int) -> u32:
    \\    return words[index]
    \\
    \\
    \\func spin(reg: Registers) -> int:
    \\    registers.write32(reg, 0x20000000, 1)
    \\    return 1
    \\
    \\func main(reg: Registers) -> int:
    \\    const words = FixedArray[u32, 4]([1, 2, 3, 4])
    \\    if registers.start_core1(reg, spin):
    \\        return 2
    \\    mut total: u32 = 0
    \\    for i in range(6):
    \\        total = total + pick(words, i)
    \\    return int(total)
    \\
;

test "a device image that starts the second core and has a freestanding fault gets the two-core runtime and the fault decoder, and reports the fault" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(a, temp.dir, "both", starts_core1_and_faults_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expectEqual(TwoCoreRuntime{ .log = true, .tls = true }, twoCoreRuntime(try temp.dir.readFileAlloc(testing.io, "both", a, .unlimited)));
    try testing.expect(holdsFaultDecoder(try temp.dir.readFileAlloc(testing.io, "both", a, .unlimited)));
    const release = try bareRelease(a, temp.dir, "both_release", starts_core1_and_faults_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release.run.term);
    try testing.expectEqual(TwoCoreRuntime{ .log = true, .tls = true }, twoCoreRuntime(release.image));
    try testing.expect(holdsFaultDecoder(release.image));
    for ([_][]const u8{ built.output, release.output }, [_][]const u8{ "both.selka:5\n", "both_release.selka:5\n" }) |image, place| {
        const ran = try onQemu(a, image);
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, ran.term);
        const said = try std.mem.concat(a, u8, &.{ ran.stdout, ran.stderr });
        try testing.expect(std.mem.indexOf(u8, said, "error[R_LIST_BOUNDS] ") != null);
        try testing.expect(std.mem.indexOf(u8, said, place) != null);
    }
}

test "a bare build with the QEMU platform file and linker script writes an ARM image that starts at myl_bare_reset" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(arena.allocator(), temp.dir, "sum", summing_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expectEqual(@as(u16, 2), built.image.kind); // ET_EXEC
    try testing.expectEqual(@as(u16, 40), built.image.machine); // EM_ARM
    try testing.expectEqual(built.image.reset, built.image.entry);
    try testing.expectEqual(@as(u32, 1), built.image.entry & 1); // a Thumb function
    try testing.expect(std.mem.indexOf(u8, built.llvm, "llvm.x86") == null);
}

/// The code bytes of a 32-bit ELF image: its allocated, read-only, named sections (vectors, text, read-only data), as
/// `scripts/bare/bare_run.py` counts them.
fn codeBytes(bytes: []const u8) u32 {
    const word = struct {
        fn at(data: []const u8, offset: usize) u32 {
            return std.mem.readInt(u32, data[offset..][0..4], .little);
        }
    }.at;
    const sections: usize = word(bytes, 32);
    const size: usize = std.mem.readInt(u16, bytes[46..48], .little);
    const count: usize = std.mem.readInt(u16, bytes[48..50], .little);
    const names: usize = word(bytes, sections + @as(usize, std.mem.readInt(u16, bytes[50..52], .little)) * size + 16);
    var total: u32 = 0;
    for (0..count) |index| {
        const header = sections + index * size;
        const flags = word(bytes, header + 8);
        const named = bytes[names + @as(usize, word(bytes, header))] != 0;
        // SHF_ALLOC without SHF_WRITE, not SHT_NOBITS.
        if (flags & 2 != 0 and flags & 1 == 0 and word(bytes, header + 4) != 8 and named) total += word(bytes, header + 20);
    }
    return total;
}

/// A `--release` device program and the most code bytes its image may have: the one-core programs measured on 18 November
/// 2026 (lane MCU-SIZE) plus about 5%, the two-core one (it starts the second core, so it links the two-core runtime) on
/// 19 November (lane MCU-CORE1B) plus about 10%, and the freestanding one (its checks fault, so it links the fault decoder)
/// on 19 November (lane MCU-NOC2D) plus about 10%. The path is part of the image (each trap site's record holds it), so it is
/// given relative to the root. Raise one only for growth that is worth its bytes on a microcontroller, and say so in the commit.
const SizeCeiling = struct { program: []const u8, measured: u32, ceiling: u32, on: []const u8 = "18 November 2026" };
const size_ceilings = [_]SizeCeiling{
    .{ .program = "test/bare/return0.selka", .measured = 1328, .ceiling = 1400 },
    .{ .program = "test/bare/list_growth.selka", .measured = 4768, .ceiling = 5000 },
    .{ .program = "test/bare/sorting.selka", .measured = 7424, .ceiling = 7800 },
    .{ .program = "test/bare/core1_one_core.selka", .measured = 4732, .ceiling = 5200, .on = "19 November 2026" },
    .{ .program = "test/bare/freestanding_checksum.selka", .measured = 1912, .ceiling = 2100, .on = "19 November 2026" },
};

/// Build each program of `size_ceilings` for the device with `--release` in `dir` and return one line for each whose image
/// has more code bytes than its ceiling, with the bytes, the ceiling and the measured size (empty when all fit).
fn sizesOverCeiling(a: std.mem.Allocator, dir: std.Io.Dir) ![]const u8 {
    const root = try dir.realPathFileAlloc(testing.io, ".", a);
    var over: std.ArrayList(u8) = .empty;
    for (size_ceilings) |limit| {
        const output = try std.fs.path.join(a, &.{ root, std.fs.path.stem(limit.program) });
        const cache = try std.fs.path.join(a, &.{ root, "cache" });
        const built = try privateRun(a, &.{ compilerPath(), "build", "--target", "thumbv6m-none", "--release", limit.program, "-o", output, "--link", qemu_platform, "--linker-script", qemu_script, "--cache-dir", cache });
        if (!std.meta.eql(built.term, std.process.Child.Term{ .exited = 0 })) return std.fmt.allocPrint(a, "{s}: the build failed: {s}", .{ limit.program, built.stderr });
        const code = codeBytes(try dir.readFileAlloc(testing.io, std.fs.path.basename(output), a, .unlimited));
        if (code > limit.ceiling) try over.print(a, "{s}: {d} code bytes, ceiling {d} (measured {d} on {s})\n", .{ limit.program, code, limit.ceiling, limit.measured, limit.on });
    }
    return over.items;
}

test "the --release device images of return0, list_growth, sorting, the two-core core1_one_core and the freestanding_checksum stay under their code-size ceilings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try testing.expectEqualStrings("", try sizesOverCeiling(arena.allocator(), temp.dir));
}

test "the bare image runs on QEMU and ends with the program's status, when qemu-system-arm is on PATH" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(arena.allocator(), temp.dir, "sum", summing_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    const ran = try onQemu(arena.allocator(), built.output);
    try testing.expectEqual(std.process.Child.Term{ .exited = 120 }, ran.term);
    const said = try std.mem.concat(arena.allocator(), u8, &.{ ran.stdout, ran.stderr });
    try testing.expect(std.mem.indexOf(u8, said, "myl-bare: status 120, live blocks 0") != null);
}

test "a bare build without a linker script is refused with one line that says what to pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const refused = try targetBuild(arena.allocator(), temp.dir, "sum", summing_program, "thumbv6m-none", &.{ "--link", qemu_platform });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "a build for the target `thumbv6m-none` needs a linker script: add `--linker-script SCRIPT.ld`") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, refused.stderr, "\n"));
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "sum", .{}));
    const hosted = try targetBuild(arena.allocator(), temp.dir, "sum", summing_program, "x86_64-linux", &.{ "--linker-script", qemu_script });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, hosted.term);
    try testing.expect(std.mem.indexOf(u8, hosted.stderr, "`--linker-script` is for a bare target") != null);
}

/// Writes a float as text: the host's number-text runtime, which a bare target does not have.
const float_program =
    \\func half(n: int) -> float:
    \\    return float(n) / 2.0
    \\
    \\func main(args: str[]) -> int:
    \\    const t = f"{half(len(args) + 3)}"
    \\    return len(t)
    \\
;

test "a bare build of a program that writes a float as text is refused with a diagnostic that names it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const refused = try targetBuild(arena.allocator(), temp.dir, "half", float_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "error[E_TARGET_NUMBER_TEXT]: the program uses float text (`myl_core_") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "the target `thumbv6m-none` does not provide") != null);
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "half", .{}));
    const hosted = try hostBuild(arena.allocator(), temp.dir, "half", float_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, hosted.term);
}

test "--target with an unknown name is refused with the names of the known targets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const built = try privateRun(a, &.{ compilerPath(), "build", "--target", "thumbv7em-none", "main.selka", "-o", "out" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, built.term);
    try testing.expect(std.mem.indexOf(u8, built.stderr, "unknown target `thumbv7em-none`; the targets are x86_64-linux, thumbv6m-none") != null);
    const tested = try privateRun(a, &.{ compilerPath(), "test", "--target", "nowhere", "main.selka" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stderr, "unknown target `nowhere`") != null);
}

test "run, build --run, run-project and test refuse a target that only builds, with one line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ran = try privateRun(a, &.{ compilerPath(), "run", "--target", "thumbv6m-none", "main.selka" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, ran.term);
    try testing.expect(std.mem.indexOf(u8, ran.stderr, only_builds) != null);
    const built_run = try privateRun(a, &.{ compilerPath(), "build", "--target=thumbv6m-none", "main.selka", "--run" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, built_run.term);
    try testing.expect(std.mem.indexOf(u8, built_run.stderr, only_builds) != null);
    const project = try privateRun(a, &.{ compilerPath(), "run-project", "--target", "thumbv6m-none", "." });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, project.term);
    try testing.expect(std.mem.indexOf(u8, project.stderr, only_builds) != null);
    const tested = try privateRun(a, &.{ compilerPath(), "test", "--target", "thumbv6m-none", "main.selka" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, tested.term);
    try testing.expect(std.mem.indexOf(u8, tested.stderr, only_builds) != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, tested.stderr, "\n"));
}

test "a bare build of a list and an integer format string links an image with no thread-local storage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(arena.allocator(), temp.dir, "leds", list_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expect(std.mem.indexOf(u8, built.run.stderr, "error") == null);
    try testing.expectEqual(@as(u16, 40), built.image.machine);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "thread_local") == null);
}

test "a bare build of a dictionary program links an image with no unwind tables" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(arena.allocator(), temp.dir, "counts", dict_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expectEqual(built.image.reset, built.image.entry);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "uwtable") == null);
}

test "a bare build of a loop the host vectorizes keeps it scalar and links" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const built = try bareBuild(arena.allocator(), temp.dir, "sum", summing_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.run.term);
    try testing.expect(std.mem.indexOf(u8, built.run.stderr, "split the result") == null);
    try testing.expect(std.mem.indexOf(u8, built.llvm, "llvm.x86") == null);
}

/// A layout for the device-image tests: the whole image in RAM from 0x20000000, the vector table first, and a `.board`
/// section kept whole, so a constant of the device's C (`board.c`, from `inc/pins.h`) is in the image.
const flat_script =
    \\MEMORY { RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 264K }
    \\__stack_top = ORIGIN(RAM) + LENGTH(RAM);
    \\__stack_limit = __stack_top - 16K;
    \\ENTRY(myl_bare_reset)
    \\SECTIONS {
    \\  .vectors : { KEEP(*(.vectors)) } > RAM
    \\  .text : { *(.text*) *(.rodata*) KEEP(*(.board)) } > RAM
    \\  .data : { . = ALIGN(4); __data_start = .; *(.data*) . = ALIGN(4); __data_end = .; } > RAM
    \\  __data_load = __data_start;
    \\  .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss*) *(COMMON) . = ALIGN(4); __bss_end = .; } > RAM
    \\  __heap_start = .;
    \\  __heap_end = __stack_limit;
    \\  /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment) *(.note*) }
    \\}
    \\
;

/// A device project's configuration (MCU-C1): two devices of the same platform, `qemu` (QEMU's layout, chosen) and `flat`
/// (`flat_script`, a UF2 family), the board's C with its header folder.
const device_config =
    \\{"version": 1, "target": "thumbv6m-none", "device": "qemu",
    \\ "devices": {
    \\   "qemu": {"linker_script": "plat/link.ld", "links": ["plat/platform.c", "plat/board.c"], "include": ["plat/inc"]},
    \\   "flat": {"linker_script": "plat/flat.ld", "links": ["plat/platform.c", "plat/board.c"], "include": ["plat/inc"],
    \\            "image": "uf2", "uf2_family": "0xe48bff56"}}}
    \\
;

/// Lay out a device project in `dir`: `selka.json`, `prog.selka` (`summing_program`) and `plat/` with the QEMU platform's
/// file and script, `flat.ld`, `board.c` and `inc/pins.h` (whose `BOARD_ID` is `board_id`).
fn deviceProject(a: std.mem.Allocator, dir: std.Io.Dir, board_id: []const u8) ![]const u8 {
    try dir.createDirPath(testing.io, "plat/inc");
    const cwd = std.Io.Dir.cwd();
    try dir.writeFile(testing.io, .{ .sub_path = "plat/platform.c", .data = try cwd.readFileAlloc(testing.io, qemu_platform, a, .unlimited) });
    try dir.writeFile(testing.io, .{ .sub_path = "plat/link.ld", .data = try cwd.readFileAlloc(testing.io, qemu_script, a, .unlimited) });
    try dir.writeFile(testing.io, .{ .sub_path = "plat/flat.ld", .data = flat_script });
    try dir.writeFile(testing.io, .{ .sub_path = "plat/board.c", .data = "#include \"pins.h\"\n__attribute__((section(\".board\"), used)) const unsigned board_id = BOARD_ID;\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "plat/inc/pins.h", .data = try std.fmt.allocPrint(a, "#define BOARD_ID {s}u\n", .{board_id}) });
    try dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = device_config });
    try dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = summing_program });
    return dir.realPathFileAlloc(testing.io, ".", a);
}

/// `selka build ROOT/prog.selka -o ROOT/OUTPUT` with `extra` and nothing else: the project names the rest.
fn projectBuild(a: std.mem.Allocator, root: []const u8, output: []const u8, extra: []const []const u8) !std.process.RunResult {
    const head = [_][]const u8{ compilerPath(), "build", try std.fs.path.join(a, &.{ root, "prog.selka" }), "-o", try std.fs.path.join(a, &.{ root, output }), "--cache-dir", try std.fs.path.join(a, &.{ root, "cache" }) };
    return privateRun(a, try std.mem.concat(a, []const u8, &.{ &head, extra }));
}

test "a device project builds its image with a bare `selka build F.selka -o X.elf`, which runs on QEMU when it is on PATH" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try deviceProject(a, temp.dir, "0x5e1ca");
    const built = try projectBuild(a, root, "prog.elf", &.{});
    try testing.expectEqualStrings("", built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const image = try armImage(try temp.dir.readFileAlloc(testing.io, "prog.elf", a, .unlimited));
    try testing.expectEqual(@as(u16, 40), image.machine);
    try testing.expectEqual(image.reset, image.entry);
    const ran = try onQemu(a, try std.fs.path.join(a, &.{ root, "prog.elf" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 120 }, ran.term);
}

/// The `zig` the compiler under test runs, for `zig objcopy`.
fn zigPath() []const u8 {
    return @import("test_options").zig_path;
}

test "a device's .bin is the bytes zig objcopy makes of its ELF, its .uf2 holds them in 256-byte blocks, and a header edit rebuilds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try deviceProject(a, temp.dir, "0x5e1ca");
    for ([_][]const u8{ "prog.elf", "prog.bin", "prog" }) |output| {
        const built = try projectBuild(a, root, output, &.{ "--device", "flat" });
        try testing.expectEqualStrings("", built.stderr);
        try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    }
    const copied = try privateRun(a, &.{ zigPath(), "objcopy", "-O", "binary", try std.fs.path.join(a, &.{ root, "prog.elf" }), try std.fs.path.join(a, &.{ root, "objcopy.bin" }) });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, copied.term);
    const expected = try temp.dir.readFileAlloc(testing.io, "objcopy.bin", a, .unlimited);
    const raw = try temp.dir.readFileAlloc(testing.io, "prog.bin", a, .unlimited);
    try testing.expectEqualSlices(u8, expected, raw);
    try testing.expect(std.mem.indexOf(u8, raw, "\xca\xe1\x05\x00") != null);
    // `prog` has no extension, so the device's `image` (`uf2`) decides.
    const uf2 = try temp.dir.readFileAlloc(testing.io, "prog", a, .unlimited);
    const blocks = (raw.len + 255) / 256;
    try testing.expectEqual(blocks * 512, uf2.len);
    for (0..blocks) |index| {
        const block = uf2[index * 512 ..][0..512];
        const field = struct {
            fn at(bytes: []const u8, offset: usize) u32 {
                return std.mem.readInt(u32, bytes[offset..][0..4], .little);
            }
        }.at;
        try testing.expectEqual(@as(u32, 0x0A324655), field(block, 0));
        try testing.expectEqual(@as(u32, 0x9E5D5157), field(block, 4));
        try testing.expectEqual(@as(u32, 0x2000), field(block, 8));
        try testing.expectEqual(@as(u32, 0x20000000) + @as(u32, @intCast(index * 256)), field(block, 12));
        try testing.expectEqual(@as(u32, 256), field(block, 16));
        try testing.expectEqual(@as(u32, @intCast(index)), field(block, 20));
        try testing.expectEqual(@as(u32, @intCast(blocks)), field(block, 24));
        try testing.expectEqual(@as(u32, 0xe48bff56), field(block, 28));
        try testing.expectEqual(@as(u32, 0x0AB16F30), field(block, 508));
        const payload = raw[index * 256 .. @min(raw.len, index * 256 + 256)];
        try testing.expectEqualSlices(u8, payload, block[32..][0..payload.len]);
    }
    // The header is an input of the board's object: a new BOARD_ID is in the next image.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "plat/inc/pins.h", .data = "#define BOARD_ID 0x7a11u\n" });
    const again = try projectBuild(a, root, "prog.bin", &.{ "--device", "flat" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, again.term);
    const rebuilt = try temp.dir.readFileAlloc(testing.io, "prog.bin", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, rebuilt, "\x11\x7a\x00\x00") != null);
    try testing.expect(std.mem.indexOf(u8, rebuilt, "\xca\xe1\x05\x00") == null);
}

test "a device build refuses a device the file does not describe and a package's device, each with one line" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try deviceProject(a, temp.dir, "1");
    const unknown = try projectBuild(a, root, "prog.elf", &.{ "--device", "pico" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, unknown.term);
    try testing.expect(std.mem.indexOf(u8, unknown.stderr, "selka.json: error[E_PROJECT_CONFIG]: device \"pico\" names no entry of devices; the devices are qemu, flat") != null);
    const package = try projectBuild(a, root, "prog.elf", &.{ "--device", "rp2040/w55rp20-ram" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, package.term);
    try testing.expect(std.mem.indexOf(u8, package.stderr, "device \"rp2040/w55rp20-ram\" is a package's device") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, package.stderr, "\n"));
    try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, "prog.elf", .{}));
    // A command-line target wins over the project's; the device's linker script then does not fit the host.
    const hosted = try projectBuild(a, root, "prog.elf", &.{ "--target", "x86_64-linux" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, hosted.term);
    try testing.expect(std.mem.indexOf(u8, hosted.stderr, "`--linker-script` is for a bare target") != null);
}

/// The `selka.json` of a package that describes a device of QEMU's platform (MCU-C1B): its script, its platform file
/// and `board.c`, whose header `pins.h` is under the device's include folder.
const package_device_config =
    \\{"version": 1, "devices": {"virt": {"target": "thumbv6m-none", "linker_script": "qdev/link.ld",
    \\  "links": ["qdev/platform.c", "qdev/board.c"], "include": ["qdev/inc"]}}}
    \\
;

/// Lay out in `dir` a package `qemu` at `library/` with `package_device_config`, an application `app/` whose `main.selka`
/// imports it (status 120) and whose `selka.json` chooses `qemu/virt`, and `packages.json`. Returns `dir`'s path.
fn packageDeviceProject(a: std.mem.Allocator, dir: std.Io.Dir) ![]const u8 {
    const cwd = std.Io.Dir.cwd();
    try dir.createDirPath(testing.io, "library/qdev/inc");
    try dir.createDirPath(testing.io, "app");
    try dir.writeFile(testing.io, .{ .sub_path = "library/qdev/platform.c", .data = try cwd.readFileAlloc(testing.io, qemu_platform, a, .unlimited) });
    try dir.writeFile(testing.io, .{ .sub_path = "library/qdev/link.ld", .data = try cwd.readFileAlloc(testing.io, qemu_script, a, .unlimited) });
    try dir.writeFile(testing.io, .{ .sub_path = "library/qdev/board.c", .data = "#include \"pins.h\"\n__attribute__((section(\".board\"), used)) const unsigned board_id = BOARD_ID;\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "library/qdev/inc/pins.h", .data = "#define BOARD_ID 0x5e1cau\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "library/qemu.selka", .data = "public func factor() -> int:\n    return 7\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "library/selka.json", .data = package_device_config });
    try dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data = "import qemu\n\nfunc main() -> int:\n    return qemu.factor() * 17 + 1\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = "{\"version\": 1, \"device\": \"qemu/virt\"}\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "packages.json", .data = "{\"packages\":[{\"name\":\"qemu\",\"root\":\"library\"}]}\n" });
    return dir.realPathFileAlloc(testing.io, ".", a);
}

/// `selka packages lock ROOT/packages.json --output ROOT/lock.json`.
fn packageLock(a: std.mem.Allocator, root: []const u8) !std.process.RunResult {
    const manifest = try std.fs.path.join(a, &.{ root, "packages.json" });
    return privateRun(a, &.{ compilerPath(), "packages", "lock", manifest, "--output", try std.fs.path.join(a, &.{ root, "lock.json" }) });
}

/// `selka packages build ROOT/app/main.selka --lock ROOT/LOCK --command build -- -o ROOT/app.elf` and `extra`.
fn packageBuild(a: std.mem.Allocator, root: []const u8, lock: []const u8, extra: []const []const u8) !std.process.RunResult {
    const entry = try std.fs.path.join(a, &.{ root, "app/main.selka" });
    const locked = try std.fs.path.join(a, &.{ root, lock });
    const head = [_][]const u8{ compilerPath(), "packages", "build", entry, "--lock", locked, "--command", "build", "--", "-o", try std.fs.path.join(a, &.{ root, "app.elf" }) };
    return privateRun(a, try std.mem.concat(a, []const u8, &.{ &head, extra }));
}

/// Expect `result` to exit 2 with `part` in its error output.
fn expectRefused(result: std.process.RunResult, part: []const u8) !void {
    try testing.expectEqual(std.process.Child.Term{ .exited = 2 }, result.term);
    if (std.mem.indexOf(u8, result.stderr, part) == null) std.debug.print("stderr: {s}\n", .{result.stderr});
    try testing.expect(std.mem.indexOf(u8, result.stderr, part) != null);
}

test "a package's device builds through selka packages once the application allows its C, and the lock pins its files" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try packageDeviceProject(a, temp.dir);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, (try packageLock(a, root)).term);
    const lock = try temp.dir.readFileAlloc(testing.io, "lock.json", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, lock, "\"devices\"") != null and std.mem.indexOf(u8, lock, "\"path\": \"qdev/inc/pins.h\"") != null);
    // An old-style device records no description: its lock is what a lock written before descriptions was.
    try testing.expect(std.mem.indexOf(u8, lock, "device_descriptions") == null);
    // Without `allow_links` the refusal names the line to add.
    try expectRefused(try packageBuild(a, root, "lock.json", &.{}), "to build it, add \"allow_links\": [\"qemu\"] to");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = "{\"version\": 1, \"device\": \"qemu/virt\", \"allow_links\": [\"qemu\"]}\n" });
    const built = try packageBuild(a, root, "lock.json", &.{});
    try testing.expectEqualStrings("", built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const image = try armImage(try temp.dir.readFileAlloc(testing.io, "app.elf", a, .unlimited));
    try testing.expectEqual(image.reset, image.entry);
    // `--device` after `--` chooses it too; a device the package does not describe is named.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = "{\"version\": 1, \"allow_links\": [\"qemu\"]}\n" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, (try packageBuild(a, root, "lock.json", &.{ "--device", "qemu/virt" })).term);
    try expectRefused(try packageBuild(a, root, "lock.json", &.{ "--device", "qemu/pico" }), "package qemu has no device \"pico\"; its devices are virt");
    // A linker script, a C file or a header changed since the lock is refused by its name.
    const pinned = [_][]const u8{ "library/qdev/link.ld", "library/qdev/board.c", "library/qdev/inc/pins.h" };
    const named = [_][]const u8{ "(its device virt: qdev/link.ld)", "(its device virt: qdev/board.c)", "(its device virt: qdev/inc/pins.h)" };
    for (pinned, named) |path, refusal| {
        const before = try temp.dir.readFileAlloc(testing.io, path, a, .unlimited);
        try temp.dir.writeFile(testing.io, .{ .sub_path = path, .data = try std.mem.concat(a, u8, &.{ before, "\n" }) });
        try expectRefused(try packageBuild(a, root, "lock.json", &.{ "--device", "qemu/virt" }), refusal);
        try temp.dir.writeFile(testing.io, .{ .sub_path = path, .data = before });
    }
    // A lock without the device record checks what uses no device, and refuses the device with what to do.
    var parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, lock, .{});
    _ = parsed.object.getPtr("packages").?.array.items[0].object.orderedRemove("devices");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "old.json", .data = try std.json.Stringify.valueAlloc(a, parsed, .{}) });
    try expectRefused(try packageBuild(a, root, "old.json", &.{ "--device", "qemu/virt" }), "old.json records none of its devices (it was written before a lock recorded them); run `selka packages lock` again");
    const checked = try privateRun(a, &.{ compilerPath(), "packages", "build", try std.fs.path.join(a, &.{ root, "app/main.selka" }), "--lock", try std.fs.path.join(a, &.{ root, "old.json" }) });
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, checked.term);
    const ran = try onQemu(a, try std.fs.path.join(a, &.{ root, "app.elf" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 120 }, ran.term);
}

test "selka packages builds the application's own device from its snapshot, and a symbolic link may not take a device path out" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try packageDeviceProject(a, temp.dir);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, (try packageLock(a, root)).term);
    try temp.dir.createDirPath(testing.io, "app/plat/inc");
    for ([_][]const u8{ "platform.c", "link.ld", "board.c", "inc/pins.h" }) |name| {
        const bytes = try temp.dir.readFileAlloc(testing.io, try std.fs.path.join(a, &.{ "library/qdev", name }), a, .unlimited);
        try temp.dir.writeFile(testing.io, .{ .sub_path = try std.fs.path.join(a, &.{ "app/plat", name }), .data = bytes });
    }
    const own =
        \\{"version": 1, "target": "thumbv6m-none", "device": "own", "include": ["plat/inc"],
        \\ "devices": {"own": {"linker_script": "plat/link.ld", "links": ["plat/platform.c", "plat/board.c"]}}}
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = own });
    const built = try packageBuild(a, root, "lock.json", &.{});
    try testing.expectEqualStrings("", built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try testing.expectEqual(@as(u16, 40), (try armImage(try temp.dir.readFileAlloc(testing.io, "app.elf", a, .unlimited))).machine);
    // A link inside the folder whose real location is outside it is refused, by `build` and by `packages build`.
    try temp.dir.symLink(testing.io, "../../library/qdev/board.c", "app/plat/escape.c", .{});
    const escaping =
        \\{"version": 1, "target": "thumbv6m-none", "device": "own",
        \\ "devices": {"own": {"linker_script": "plat/link.ld", "links": ["plat/platform.c", "plat/escape.c"]}}}
    ;
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = escaping });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/solo.selka", .data = "func main() -> int:\n    return 3\n" });
    const solo = try privateRun(a, &.{ compilerPath(), "build", try std.fs.path.join(a, &.{ root, "app/solo.selka" }), "-o", try std.fs.path.join(a, &.{ root, "solo.elf" }) });
    try expectRefused(solo, "device \"own\": links entry \"plat/escape.c\" leaves the folder of this selka.json through a symbolic link");
    try expectRefused(try packageBuild(a, root, "lock.json", &.{}), "device \"own\": plat/escape.c leaves the folder of this selka.json through a symbolic link");
}

test "selka test puts the project's include folders on the include path of the C it links" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.createDirPath(testing.io, "c");
    try temp.dir.createDirPath(testing.io, "inc");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = "{\"version\": 1, \"links\": [\"c/answer.c\"], \"include\": [\"inc\"]}\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "c/answer.c", .data = "#include \"answer.h\"\nint linked_answer(void) { return ANSWER; }\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "inc/answer.h", .data = "#define ANSWER 42\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "answer_test.selka", .data = "extern func linked_answer(host: Host) -> i32\n\npublic func test_answer(host: Host) -> bool:\n    return int(linked_answer(host)) == 42\n" });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, ".cache" });
    const file = try privateRun(a, &.{ compilerPath(), "test", try std.fs.path.join(a, &.{ root, "answer_test.selka" }), "--allow-host", "--cache-dir", cache });
    try testing.expectEqualStrings("", file.stderr);
    try testing.expect(std.mem.indexOf(u8, file.stdout, "passed answer_test::test_answer") != null);
    const directory = try privateRun(a, &.{ compilerPath(), "test", root, "--allow-host", "--cache-dir", cache });
    try testing.expect(std.mem.indexOf(u8, directory.stdout, "answer_test::test_answer") != null);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, directory.term);
}

/// The device a project describes by its memory and binds to Selka hooks (MCU-NOC4A): QEMU's layout (the vector table at 0, the rest
/// in RAM) as `memory`, a `stack` the tests change, and the three hooks of `hooks_board`.
const hooks_config_head =
    \\{"version": 1, "device": "qemu-hooks",
    \\ "devices": {"qemu-hooks": {"target": "thumbv6m-none",
    \\   "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
    \\   "place": {"vectors": "boot", "code": "ram"},
;

/// The hooks of QEMU's mps2-an385 board in Selka: `start` enables UART0 and traps unaligned accesses, `write` sends each byte
/// through the data register (reading the buffer through `Registers`), `finish` asks the board to reset (QEMU runs with `-no-reboot`).
const hooks_board =
    \\import registers
    \\
    \\
    \\public func answer() -> int:
    \\    return 7
    \\
    \\
    \\@freestanding
    \\func send(reg: Registers, octet: u32):
    \\    mut waits = 0
    \\    while bit_and(registers.read32(reg, 0x40004004), 1) != 0:
    \\        waits += 1
    \\    registers.write32(reg, 0x40004000, octet)
    \\
    \\
    \\@freestanding
    \\func start(reg: Registers):
    \\    registers.write32(reg, 0xE000ED14, bit_or(registers.read32(reg, 0xE000ED14), 8))
    \\    registers.write32(reg, 0x40004010, 16)
    \\    registers.write32(reg, 0x40004008, 1)
    \\
    \\
    \\@freestanding
    \\func write(reg: Registers, stream: int, address: u32, length: u32):
    \\    _ = stream
    \\    for i in range(int(length)):
    \\        send(reg, u32(registers.read8(reg, address + u32(i))))
    \\
    \\
    \\@freestanding
    \\func finish(reg: Registers, status: int):
    \\    _ = status
    \\    registers.write32(reg, 0xE000ED0C, 0x05FA0004)
    \\
;

const hooks_program =
    \\import board
    \\
    \\
    \\func main() -> int:
    \\    debug("hello from the hooks")
    \\    return board.answer()
    \\
;

/// Lay out a described-device project in `dir`: `selka.json` made of `hooks_config_head`, `tail` (the keys after `place`) and the
/// closing braces, `board.selka` (`board_source`) and `prog.selka` (`program_source`). Returns the project's folder.
fn describedProject(a: std.mem.Allocator, dir: std.Io.Dir, tail: []const u8, sources: [2][]const u8) ![]const u8 {
    try dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = try std.mem.concat(a, u8, &.{ hooks_config_head, tail, "}}}\n" }) });
    try dir.writeFile(testing.io, .{ .sub_path = "board.selka", .data = sources[0] });
    try dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = sources[1] });
    return dir.realPathFileAlloc(testing.io, ".", a);
}

/// The keys of the hooks device after `place`: a stack of `stack`, then the three hooks.
fn hooksTail(a: std.mem.Allocator, stack: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, " \"stack\": \"{s}\", \"hooks\": {{\"start\": \"board.start\", \"write\": \"board.write\", \"exit\": \"board.finish\"}}", .{stack});
}

/// Run `path` on QEMU with UART0 written to `serial` and a reset ending the run (`-no-reboot`), as the hooks of `hooks_board` do.
fn onQemuSerial(a: std.mem.Allocator, path: []const u8, serial: []const u8) !std.process.RunResult {
    const argv = [_][]const u8{ "qemu-system-arm", "-M", "mps2-an385", "-nographic", "-monitor", "none", "-no-reboot", "-serial", try std.fmt.allocPrint(a, "file:{s}", .{serial}), "-kernel", path };
    return privateRun(a, &argv) catch |err| switch (err) {
        error.FileNotFound => error.SkipZigTest,
        else => err,
    };
}

/// Build the project at `root` as `output`, run it on QEMU, and return what the hooks wrote to UART0.
fn runHooksProject(a: std.mem.Allocator, root: []const u8, output: []const u8, extra: []const []const u8) ![]const u8 {
    const built = try projectBuild(a, root, output, extra);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const serial = try std.fs.path.join(a, &.{ root, "serial.txt" });
    const ran = try onQemuSerial(a, try std.fs.path.join(a, &.{ root, output }), serial);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    return std.Io.Dir.cwd().readFileAlloc(testing.io, serial, a, .unlimited);
}

test "a device described by memory and hooks in Selka prints and exits through them on QEMU, plain and --release, and a smaller stack is the next image's" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try describedProject(a, temp.dir, try hooksTail(a, "16K"), .{ hooks_board, hooks_program });
    const plain = try runHooksProject(a, root, "prog.elf", &.{});
    try testing.expect(std.mem.indexOf(u8, plain, "hello from the hooks\nmyl-bare: status 7, live blocks 0, heap high-water 0 of ") != null);
    try testing.expect(std.mem.indexOf(u8, plain, ", stack 264 of 16384") != null);
    const release = try runHooksProject(a, root, "release.elf", &.{"--release"});
    try testing.expect(std.mem.startsWith(u8, release, "myl-bare: status 7, live blocks 0, heap high-water 0 of "));
    // The same program with `stack` 8K is a different image, not the last one replayed: its stack limit is 8192 bytes below the top.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = try std.mem.concat(a, u8, &.{ hooks_config_head, try hooksTail(a, "8K"), "}}}\n" }) });
    const smaller = try runHooksProject(a, root, "prog.elf", &.{});
    try testing.expect(std.mem.indexOf(u8, smaller, ", stack 264 of 8192") != null);
}

/// One `selka.json` of two devices that differ only in the function their `start` hook binds (MCU-NOC4D): `board.start_first` and
/// `board.start_second`, which `two_starts_board` defines.
const two_starts_config =
    \\{"version": 1, "device": "first",
    \\ "devices": {
    \\  "first": {"target": "thumbv6m-none", "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
    \\            "place": {"vectors": "boot", "code": "ram"}, "stack": "16K",
    \\            "hooks": {"start": "board.start_first", "write": "board.write", "exit": "board.finish"}},
    \\  "second": {"target": "thumbv6m-none", "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
    \\             "place": {"vectors": "boot", "code": "ram"}, "stack": "16K",
    \\             "hooks": {"start": "board.start_second", "write": "board.write", "exit": "board.finish"}}}}
    \\
;

/// `hooks_board` with its `start` made the shared `setup`, and two start hooks that run it and then write one letter of their own to
/// UART0 before anything else does: `F` for `start_first`, `S` for `start_second`.
fn twoStartsBoard(a: std.mem.Allocator) ![]const u8 {
    var source: []const u8 = hooks_board;
    source = try std.mem.replaceOwned(u8, a, source, "@freestanding\nfunc start(reg: Registers):\n", "@freestanding\nfunc setup(reg: Registers):\n");
    return std.mem.replaceOwned(u8, a, source, "@freestanding\nfunc write(", "@freestanding\npublic func start_first(reg: Registers):\n    setup(reg)\n    send(reg, 70)\n\n\n@freestanding\npublic func start_second(reg: Registers):\n    setup(reg)\n    send(reg, 83)\n\n\n@freestanding\nfunc write(");
}

/// Build the two-device project at `root` for `device` as `output` and run it on QEMU: what the image wrote to UART0.
fn runDevice(a: std.mem.Allocator, root: []const u8, device: []const u8, extra: []const []const u8) ![]const u8 {
    const release = extra.len != 0;
    const output = try std.fmt.allocPrint(a, "{s}{s}.elf", .{ device, if (release) "-release" else "" });
    return runHooksProject(a, root, output, try std.mem.concat(a, []const u8, &.{ &.{ "--device", device }, extra }));
}

/// Both devices, built in turn through the one cache directory and the private stores, in `extra`'s mode: each image's first byte is
/// the letter its own `start` hook writes, so a unit or a record made for the other device's binding is the wrong letter.
fn expectEachRunsItsOwnStart(a: std.mem.Allocator, program: []const u8, prefixes: [2][]const u8, extra: []const []const u8) !void {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try describedProject(a, temp.dir, "", .{ try twoStartsBoard(a), program });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data = two_starts_config });
    const first = try runDevice(a, root, "first", extra);
    const second = try runDevice(a, root, "second", extra);
    const again = try runDevice(a, root, "first", extra);
    try testing.expect(std.mem.startsWith(u8, first, prefixes[0]));
    try testing.expect(std.mem.startsWith(u8, second, prefixes[1]));
    try testing.expect(std.mem.startsWith(u8, again, prefixes[0]));
}

test "two devices of one project that bind their start hook to different functions each run their own, built in turn through shared stores, plain and --release" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Both functions are called from `main` too, so the link cannot tell one binding from the other: only the letter the image writes first can.
    const called = "import board\n\n\nfunc main(reg: Registers) -> int:\n    board.start_first(reg)\n    board.start_second(reg)\n    return board.answer()\n";
    try expectEachRunsItsOwnStart(a, called, .{ "FFSmyl-bare: status 7", "SFSmyl-bare: status 7" }, &.{});
    try expectEachRunsItsOwnStart(a, called, .{ "FFSmyl-bare: status 7", "SFSmyl-bare: status 7" }, &.{"--release"});
}

test "two devices whose start hooks bind functions nothing else calls link and run their own after each other, plain and --release" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The second build's entry unit must not name the first device's function (`undefined hidden symbol` at its link).
    const unreached = "import board\n\n\nfunc main() -> int:\n    return board.answer()\n";
    try expectEachRunsItsOwnStart(a, unreached, .{ "Fmyl-bare: status 7", "Smyl-bare: status 7" }, &.{});
    try expectEachRunsItsOwnStart(a, unreached, .{ "Fmyl-bare: status 7", "Smyl-bare: status 7" }, &.{"--release"});
}

/// The C file of the host-hooks project (MCU-NOC4C): the board's reset as a function reached only through its address, as the RP2040's
/// boot ROM routine is. `reset_base` answers the address with its Thumb bit cleared, so the Selka hook computes the callable one
/// (`bit_or(base, 1)`); the function writes `[C 7]` to UART0 (a status digit no Selka code of the project writes) and asks for the reset.
const reset_c =
    \\#include <stdint.h>
    \\static void put(char c) {
    \\    while (*(volatile uint32_t *)0x40004004 & 1) {}
    \\    *(volatile uint32_t *)0x40004000 = (uint32_t)c;
    \\}
    \\__attribute__((noinline)) static void board_reset(int32_t status) {
    \\    put('['); put('C'); put(' '); put((char)('0' + status)); put(']'); put('\n');
    \\    *(volatile uint32_t *)0xE000ED0C = 0x05FA0004;
    \\}
    \\uint32_t reset_base(void) { return (uint32_t)(uintptr_t)&board_reset & ~1u; }
    \\
;

/// `hooks_board` with all three hooks taking `host` after `reg`, and `finish` ending in the C reset through an `@address extern func`
/// at an address it computes, instead of writing the reset register itself.
fn hostHooksBoard(a: std.mem.Allocator) ![]const u8 {
    var source: []const u8 = hooks_board;
    source = try std.mem.replaceOwned(u8, a, source, "func start(reg: Registers):\n", "func start(reg: Registers, host: Host):\n    _ = host\n");
    source = try std.mem.replaceOwned(u8, a, source, "func write(reg: Registers, stream: int,", "func write(reg: Registers, host: Host, stream: int,");
    source = try std.mem.replaceOwned(u8, a, source, "    _ = stream\n", "    _ = host\n    _ = stream\n");
    source = try std.mem.replaceOwned(u8, a, source, "func finish(reg: Registers, status: int):\n    _ = status\n    registers.write32(reg, 0xE000ED0C, 0x05FA0004)\n", "func finish(reg: Registers, host: Host, status: int):\n    _ = reg\n    reset_at(host, bit_or(reset_base(host), 1), i32(status))\n");
    return std.mem.concat(a, u8, &.{ source, "\n\nextern func reset_base(host: Host) -> u32\n\n\n@address\nextern func reset_at(host: Host, target: u32, status: i32) -> Unit\n" });
}

test "device hooks that take Host call C: the exit hook reaches the board's reset through an address, plain and --release" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try describedProject(a, temp.dir, try hooksTail(a, "16K"), .{ try hostHooksBoard(a), hooks_program });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "reset.c", .data = reset_c });
    const link = [_][]const u8{ "--link", try std.fs.path.join(a, &.{ root, "reset.c" }) };
    // Only the C function writes `[C 7]`, and only the reset it asks for ends the run: the hook reached C, with the live `Host`
    // token (a wrong one is the `R_CAPABILITY` trap before the call).
    const plain = try runHooksProject(a, root, "prog.elf", &link);
    try testing.expect(std.mem.startsWith(u8, plain, "hello from the hooks\nmyl-bare: status 7, live blocks 0, heap high-water 0 of "));
    try testing.expect(std.mem.endsWith(u8, plain, "[C 7]\n"));
    const release = try runHooksProject(a, root, "release.elf", &(link ++ [_][]const u8{"--release"}));
    try testing.expect(std.mem.startsWith(u8, release, "myl-bare: status 7, live blocks 0, heap high-water 0 of "));
    try testing.expect(std.mem.endsWith(u8, release, "[C 7]\n"));
}

/// The refusal a build of the hooks project meets when `from` in `source` (the board's, or the program's) becomes `to`: the exit
/// status and the compiler's stderr.
fn hookRefusal(a: std.mem.Allocator, change: struct { file: u1, from: []const u8, to: []const u8 }) !std.process.RunResult {
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    var sources = [2][]const u8{ hooks_board, hooks_program };
    sources[change.file] = try std.mem.replaceOwned(u8, a, sources[change.file], change.from, change.to);
    const root = try describedProject(a, temp.dir, try hooksTail(a, "16K"), sources);
    return projectBuild(a, root, "prog.elf", &.{});
}

test "a hook that is missing, not freestanding, of the wrong signature or unimported is refused by name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unimported = try hookRefusal(a, .{ .file = 1, .from = "import board\n\n\nfunc main() -> int:\n    debug(\"hello from the hooks\")\n    return board.answer()", .to = "func main() -> int:\n    return 7" });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, unimported.term);
    try testing.expect(std.mem.indexOf(u8, unimported.stderr, "selka.json: error[E_DEVICE_HOOK]: device \"qemu-hooks\": hook \"start\" binds board.start: the program does not import board: add `import board` to it") != null);
    const plain = try hookRefusal(a, .{ .file = 0, .from = "@freestanding\nfunc start(", .to = "func start(" });
    try testing.expect(std.mem.indexOf(u8, plain.stderr, "hook \"start\" binds board.start: it is not @freestanding (a hook runs where the runtime cannot): add `@freestanding` above it") != null);
    const wrong = try hookRefusal(a, .{ .file = 0, .from = "address: u32, length: u32)", .to = "address: u32, length: u32, extra: u32)" });
    // The message shows both accepted forms: without `host` and with it after `reg`.
    try testing.expect(std.mem.indexOf(u8, wrong.stderr, "hook \"write\" binds board.write: its signature is not the hook's: func(reg: Registers, stream: int, address: u32, length: u32) or func(reg: Registers, host: Host, stream: int, address: u32, length: u32)\n") != null);
    // A `Host` is accepted only second: not in any other place, and not twice.
    const late = try hookRefusal(a, .{ .file = 0, .from = "stream: int, address: u32", .to = "stream: int, _host: Host, address: u32" });
    try testing.expect(std.mem.indexOf(u8, late.stderr, "hook \"write\" binds board.write: its signature is not the hook's: func(reg: Registers, stream: int,") != null);
    const twice = try hookRefusal(a, .{ .file = 0, .from = "func start(reg: Registers):", .to = "func start(reg: Registers, _host: Host, _again: Host):" });
    try testing.expect(std.mem.indexOf(u8, twice.stderr, "hook \"start\" binds board.start: its signature is not the hook's: func(reg: Registers) or func(reg: Registers, host: Host)\n") != null);
    const first = try hookRefusal(a, .{ .file = 0, .from = "func finish(reg: Registers, status: int):", .to = "func finish(_host: Host, reg: Registers, status: int):" });
    try testing.expect(std.mem.indexOf(u8, first.stderr, "hook \"exit\" binds board.finish: its signature is not the hook's:") != null);
    const absent = try hookRefusal(a, .{ .file = 0, .from = "func finish(", .to = "func finished(" });
    try testing.expect(std.mem.indexOf(u8, absent.stderr, "hook \"exit\" binds board.finish: the module board has no function finish") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, absent.stderr, "E_DEVICE_HOOK"));
}

/// The `selka.json` of a package `qemu` whose device `virt` describes itself and names no file (MCU-NOC4E): QEMU's layout and the
/// three hooks of `hooks_board`, bound to the package's module `qemu.board` as a program imports it.
const described_package_config =
    \\{"version": 1, "devices": {"virt": {"target": "thumbv6m-none",
    \\  "memory": {"boot": ["0x0", "1K"], "ram": ["0x20000000", "264K"]},
    \\  "place": {"vectors": "boot", "code": "ram"}, "stack": "16K",
    \\  "hooks": {"start": "qemu.board.start", "write": "qemu.board.write", "exit": "qemu.board.finish"}}}}
    \\
;

/// Lay out in `dir` the package `qemu` at `library/` (its top module, `qemu/board.selka` = `hooks_board` and
/// `described_package_config`), an application `app/` whose `main.selka` imports `qemu.board` and whose `selka.json` chooses
/// `qemu/virt` without `allow_links` (the device has no C), and `packages.json`. Returns `dir`'s path.
fn describedPackageProject(a: std.mem.Allocator, dir: std.Io.Dir) ![]const u8 {
    try dir.createDirPath(testing.io, "library/qemu");
    try dir.createDirPath(testing.io, "app");
    try dir.writeFile(testing.io, .{ .sub_path = "library/qemu.selka", .data = "public func name() -> int:\n    return 1\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "library/qemu/board.selka", .data = hooks_board });
    try dir.writeFile(testing.io, .{ .sub_path = "library/selka.json", .data = described_package_config });
    try dir.writeFile(testing.io, .{ .sub_path = "app/main.selka", .data = "import qemu.board\n\n\nfunc main() -> int:\n    debug(\"hello from the hooks\")\n    return board.answer()\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = "{\"version\": 1, \"device\": \"qemu/virt\"}\n" });
    try dir.writeFile(testing.io, .{ .sub_path = "packages.json", .data = "{\"packages\":[{\"name\":\"qemu\",\"root\":\"library\"}]}\n" });
    return dir.realPathFileAlloc(testing.io, ".", a);
}

/// Build the application of `describedPackageProject` through `selka packages` with `extra` after `--`, run `app.elf` on QEMU and
/// return what its hooks wrote to UART0.
fn runPackageHooks(a: std.mem.Allocator, root: []const u8, extra: []const []const u8) ![]const u8 {
    const built = try packageBuild(a, root, "lock.json", extra);
    try testing.expectEqualStrings("", built.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const serial = try std.fs.path.join(a, &.{ root, "serial.txt" });
    const ran = try onQemuSerial(a, try std.fs.path.join(a, &.{ root, "app.elf" }), serial);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    return std.Io.Dir.cwd().readFileAlloc(testing.io, serial, a, .unlimited);
}

test "a package's described device prints and exits through hooks in the package's module on QEMU, plain and --release, and a changed description is refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try describedPackageProject(a, temp.dir);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, (try packageLock(a, root)).term);
    const lock = try temp.dir.readFileAlloc(testing.io, "lock.json", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, lock, "\"device_descriptions\"") != null and std.mem.indexOf(u8, lock, "\"qemu.board.start\"") != null);
    const plain = try runPackageHooks(a, root, &.{});
    try testing.expect(std.mem.indexOf(u8, plain, "hello from the hooks\nmyl-bare: status 7, live blocks 0, heap high-water 0 of ") != null);
    try testing.expect(std.mem.indexOf(u8, plain, ", stack 264 of 16384") != null);
    const release = try runPackageHooks(a, root, &.{"--release"});
    try testing.expect(std.mem.startsWith(u8, release, "myl-bare: status 7, live blocks 0, heap high-water 0 of "));
    // `--device` after `--` chooses it as the application's `device` does.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "app/selka.json", .data = "{\"version\": 1}\n" });
    const chosen = try runPackageHooks(a, root, &.{ "--device", "qemu/virt" });
    try testing.expect(std.mem.indexOf(u8, chosen, "hello from the hooks\n") != null);
    // A description edited since the lock is refused, naming the key; so is a lock written without the descriptions.
    const edits = [_][3][]const u8{
        .{ "\"16K\"", "\"8K\"", "stack" },
        .{ "qemu.board.write", "qemu.board.start", "hooks" },
        .{ "\"264K\"", "\"128K\"", "memory" },
    };
    for (edits) |edit| {
        try temp.dir.writeFile(testing.io, .{ .sub_path = "library/selka.json", .data = try std.mem.replaceOwned(u8, a, described_package_config, edit[0], edit[1]) });
        const refusal = try std.fmt.allocPrint(a, "locked dependency changed: qemu (its device virt: the {s} key)", .{edit[2]});
        try expectRefused(try packageBuild(a, root, "lock.json", &.{ "--device", "qemu/virt" }), refusal);
    }
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library/selka.json", .data = described_package_config });
    var parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, lock, .{});
    _ = parsed.object.getPtr("packages").?.array.items[0].object.orderedRemove("device_descriptions");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "old.json", .data = try std.json.Stringify.valueAlloc(a, parsed, .{}) });
    try expectRefused(try packageBuild(a, root, "old.json", &.{ "--device", "qemu/virt" }), "locked dependency changed: qemu (its device virt: the memory key)");
    // A description a project would refuse is refused when the package is locked.
    try temp.dir.writeFile(testing.io, .{ .sub_path = "library/selka.json", .data = try std.mem.replaceOwned(u8, a, described_package_config, "\"start\"", "\"begin\"") });
    try expectRefused(try packageLock(a, root), "library/selka.json: device \"virt\": unknown hook \"begin\"");
}

test "a flash description makes an image whose first 256 bytes are the sealed RP2040 boot stage, then the vector table with its stack top" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "selka.json", .data =
        \\{"version": 1, "device": "flash", "devices": {"flash": {"target": "thumbv6m-none",
        \\ "memory": {"flash": ["0x10000000", "2044K"], "ram": ["0x20000000", "252K"]},
        \\ "boot": "rp2040-read-03h", "stack": "16K", "image": "bin"}}}
    });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "prog.selka", .data = summing_program });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    const built = try projectBuild(a, root, "prog.bin", &.{});
    try testing.expectEqualStrings("", built.stderr);
    const image = try temp.dir.readFileAlloc(testing.io, "prog.bin", a, .unlimited);
    // The boot stage's code, its zero padding, and its CRC-32/MPEG-2 (0xe11ef9df, as tools/boot2.py seal writes it).
    try testing.expectEqualSlices(u8, "\x00\xb5\x0c\x4b\x00\x21\x99\x60", image[0..8]);
    try testing.expectEqualSlices(u8, &@as([8]u8, @splat(0)), image[76..84]);
    try testing.expectEqualSlices(u8, "\xdf\xf9\x1e\xe1", image[252..256]);
    // Word 0 of the vector table at 0x10000100 is the stack top, 0x2003F000 (the board's log area begins there).
    try testing.expectEqualSlices(u8, "\x00\xf0\x03\x20", image[256..260]);
    const elf = try projectBuild(a, root, "prog.elf", &.{});
    try testing.expectEqualStrings("", elf.stderr);
    const bytes = try temp.dir.readFileAlloc(testing.io, "prog.elf", a, .unlimited);
    const boot2 = std.mem.indexOf(u8, bytes, "\x00\xb5\x0c\x4b\x00\x21\x99\x60") orelse return error.TestUnexpectedResult;
    try testing.expectEqualSlices(u8, image[0..256], bytes[boot2..][0..256]);
}

/// A `@freestanding(ram)` function that writes a register and computes (MCU-NOC2B): its image keeps the promise.
const ram_clean_program =
    \\import registers
    \\
    \\
    \\@freestanding(ram)
    \\func step(reg: Registers, x: u32) -> u32:
    \\    registers.write32(reg, 0x40004008, 1)
    \\    return bit_and(x + 7, 0xFF)
    \\
    \\
    \\func main(reg: Registers) -> int:
    \\    return int(step(reg, 35))
    \\
;

/// The same function for the host, where the placement changes nothing.
const ram_host_program =
    \\@freestanding(ram)
    \\func step(x: u32) -> u32:
    \\    return bit_and(x + 7, 0xFF)
    \\
    \\
    \\func main() -> int:
    \\    return int(step(35))
    \\
;

/// Sixty-three elements of a 64-element array literal.
const sevens = "7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, ";

/// A `ram` function whose body needs `body` of the code generator, its arguments read from a register so nothing folds.
fn ramProgram(a: std.mem.Allocator, signature: []const u8, body: []const u8, call: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "import registers\n\n\n@freestanding(ram)\nfunc {s}:\n{s}\n\n\nfunc main(reg: Registers) -> int:\n    const given = registers.read32(reg, 0x40004004)\n{s}\n", .{ signature, body, call });
}

test "a ram function goes to .ramfunc on the device and keeps its promise on the image; the host build has no section" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const clean = try targetBuild(a, temp.dir, "clean", ram_clean_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    try testing.expectEqualStrings("", clean.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, clean.term);
    const llvm = try temp.dir.readFileAlloc(testing.io, "clean.ll", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, llvm, "@\"my.clean::step\"(i64 %p0, i32 %p1) nounwind noinline \"nooutline\" \"no-jump-tables\"=\"true\" section \".ramfunc\"") != null);
    const ran = try onQemu(a, try std.fs.path.join(a, &.{ try temp.dir.realPathFileAlloc(testing.io, ".", a), "clean" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, ran.term);
    const hosted = try hostBuild(a, temp.dir, "hosted", ram_host_program);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, hosted.term);
    const host_llvm = try temp.dir.readFileAlloc(testing.io, "hosted.ll", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, host_llvm, ".ramfunc") == null);
    try testing.expect(std.mem.indexOf(u8, host_llvm, "noinline") == null);
}

test "the image check refuses a ram function that reaches flash, naming the function, the symbol and the operation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const Case = struct { name: []const u8, signature: []const u8, body: []const u8, call: []const u8, expected: []const u8 };
    const cases = [_]Case{
        .{ .name = "divide", .signature = "ratio(a: u32, b: u32) -> u32", .body = "    return a // b", .call = "    return int(ratio(84, given + 2))", .expected = "error[E_FREESTANDING_RAM]: the @freestanding(ram) function `divide::ratio` calls `__aeabi_uidiv` at 0x" },
        .{ .name = "multiply", .signature = "scale(a: int, b: int) -> int", .body = "    return a * b", .call = "    return scale(21, int(given) + 2)", .expected = "function `multiply::scale` calls `__aeabi_lmul` at 0x" },
        .{ .name = "copy", .signature = "copied(words: FixedArray[u32, 64], first: u32) -> FixedArray[u32, 64]", .body = "    mut out = words\n    out[0] = first\n    return out", .call = "    const out = copied(FixedArray[u32, 64]([" ++ sevens ++ "7]), given)\n    return int(out[1])", .expected = "function `copy::copied` calls `__aeabi_memcpy` at 0x" },
    };
    for (cases) |case| {
        const refused = try targetBuild(a, temp.dir, case.name, try ramProgram(a, case.signature, case.body, case.call), "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
        try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
        try testing.expect(std.mem.indexOf(u8, refused.stderr, case.expected) != null);
        try testing.expectError(error.FileNotFound, temp.dir.access(testing.io, case.name, .{}));
    }
    // A `match` over twelve cases keeps no table: a tree of compares, all in RAM.
    var arms: std.ArrayList(u8) = .empty;
    for (0..12) |value| try arms.print(a, "        case {d}:\n            return {d}\n", .{ value, (value * 37 + 11) % 251 });
    const matched = try ramProgram(a, "code(x: u32) -> u32", try std.fmt.allocPrint(a, "    match x:\n{s}        case _:\n            return 0", .{arms.items}), "    return int(code(given + 2))");
    const kept = try targetBuild(a, temp.dir, "matched", matched, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", qemu_script });
    try testing.expectEqualStrings("", kept.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, kept.term);
}

/// A `ram` function that calls an `extern func`: the C is in flash or, with the attribute, in `.ramfunc`.
const ram_extern_program =
    \\extern func erase_page(host: Host, page: u32) -> u32
    \\
    \\
    \\@freestanding(ram)
    \\func erase(host: Host, page: u32) -> u32:
    \\    return erase_page(host, page)
    \\
    \\
    \\func main(host: Host) -> int:
    \\    return int(erase(host, 3))
    \\
;

test "the image check refuses a ram function calling C in flash and accepts C placed in .ramfunc" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    try temp.dir.writeFile(testing.io, .{ .sub_path = "flash.c", .data = "#include <stdint.h>\nuint32_t erase_page(uint32_t page) { return page + 1; }\n" });
    try temp.dir.writeFile(testing.io, .{ .sub_path = "ram.c", .data = "#include <stdint.h>\n__attribute__((section(\".ramfunc\"), noinline)) uint32_t erase_page(uint32_t page) { return page + 1; }\n" });
    const in_flash = try targetBuild(a, temp.dir, "in_flash", ram_extern_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--link", try std.fs.path.join(a, &.{ root, "flash.c" }), "--linker-script", qemu_script });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, in_flash.term);
    try testing.expect(std.mem.indexOf(u8, in_flash.stderr, "erase` calls `erase_page` at 0x") != null);
    try testing.expect(std.mem.indexOf(u8, in_flash.stderr, "must be C placed in `.ramfunc`") != null);
    const in_ram = try targetBuild(a, temp.dir, "in_ram", ram_extern_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--link", try std.fs.path.join(a, &.{ root, "ram.c" }), "--linker-script", qemu_script });
    try testing.expectEqualStrings("", in_ram.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, in_ram.term);
    // The `Host` token is compared inline in the ram function (MCU-NOC2C's form): no call of the runtime's check.
    const llvm = try temp.dir.readFileAlloc(testing.io, "in_ram.ll", a, .unlimited);
    try testing.expect(std.mem.indexOf(u8, llvm, "call void @myl_core_host_check") == null);
    try testing.expect(std.mem.indexOf(u8, llvm, "%host.wrong") != null);
    const ran = try onQemu(a, try std.fs.path.join(a, &.{ root, "in_ram" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 4 }, ran.term);
}

test "the image check refuses a ram function a linker script left in flash" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const script = try std.Io.Dir.cwd().readFileAlloc(testing.io, qemu_script, a, .unlimited);
    const unplaced = try std.mem.replaceOwned(u8, a, script, "*(.ramfunc*) ", "");
    try temp.dir.writeFile(testing.io, .{ .sub_path = "flash.ld", .data = unplaced });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    const refused = try targetBuild(a, temp.dir, "unplaced", ram_clean_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", try std.fs.path.join(a, &.{ root, "flash.ld" }) });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "step` is at 0x") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "which the image does not load into RAM: the device's linker script must put the section `.ramfunc` in RAM") != null);
}

/// A `@freestanding` function and a `@freestanding(ram)` one that each call every `cpu` function that acts on the machine
/// (MCU-NOC2F). Linked, never run: `wfi` and `bkpt` would stop the machine.
const cpu_freestanding_program =
    \\import cpu
    \\import registers
    \\
    \\
    \\@freestanding
    \\func in_flash(reg: Registers) -> u32:
    \\    const held = cpu.interrupts_off(reg)
    \\    registers.write32(reg, 0x40004008, 1)
    \\    const before = held.primask
    \\    cpu.interrupts_restore(reg, own held)
    \\    cpu.send_event(reg)
    \\    cpu.wait_for_event(reg)
    \\    cpu.wait_for_interrupt(reg)
    \\    cpu.barrier(reg)
    \\    cpu.breakpoint(reg)
    \\    return before
    \\
    \\
    \\@freestanding(ram)
    \\func in_ram(reg: Registers) -> u32:
    \\    const held = cpu.interrupts_off(reg)
    \\    registers.write32(reg, 0x40004008, 1)
    \\    const before = held.primask
    \\    cpu.interrupts_restore(reg, own held)
    \\    cpu.send_event(reg)
    \\    cpu.wait_for_event(reg)
    \\    cpu.wait_for_interrupt(reg)
    \\    cpu.barrier(reg)
    \\    cpu.breakpoint(reg)
    \\    return before
    \\
    \\
    \\func main(reg: Registers) -> int:
    \\    return int(in_flash(reg) + in_ram(reg))
    \\
;

/// The `define` of the function `name` in `llvm`, from its line to its closing brace.
fn defineBody(llvm: []const u8, name: []const u8) []const u8 {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, llvm, from, "define ")) |at| {
        const end = std.mem.indexOfScalarPos(u8, llvm, at, '\n') orelse llvm.len;
        if (std.mem.indexOf(u8, llvm[at..end], name) != null) return llvm[at .. std.mem.indexOfPos(u8, llvm, end, "\n}\n") orelse llvm.len];
        from = end;
    }
    return "";
}

/// The instructions of the `cpu` functions as inline assembly, the Thumb encodings an image holds for them (`mrs` and `msr` of
/// PRIMASK for any register: their second halfword and the first's high byte), and the registers' one volatile store.
const cpu_assembly = [_][]const u8{
    "call void asm sideeffect \"wfe\", \"~{memory}\"()",
    "call void asm sideeffect \"wfi\", \"~{memory}\"()",
    "call void asm sideeffect \"sev\", \"~{memory}\"()",
    "call void asm sideeffect \"dsb sy\\0Aisb sy\", \"~{memory}\"()",
    "call void asm sideeffect \"bkpt #0\", \"~{memory}\"()",
    "call i32 asm sideeffect \"mrs $0, primask\\0Acpsid i\", \"=r,~{memory}\"()",
    "call void asm sideeffect \"msr primask, $0\", \"r,~{memory}\"(i32 ",
};
const cpu_encodings = [_][]const u8{ "\x20\xbf", "\x30\xbf", "\x40\xbf", "\x00\xbe", "\x72\xb6", "\xbf\xf3\x4f\x8f", "\xbf\xf3\x6f\x8f", "\xef\xf3\x10", "\xf3\x10\x88" };

test "freestanding and ram functions call each cpu function as its instruction, plain and --release, and name no runtime function" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    // A plain build inlines nothing: each function calls the library's one-instruction helpers, and the build placed those in
    // RAM beside the ram function (the image check passes), so the ram function calls nothing in flash.
    const plain = try bareBuild(a, temp.dir, "cpufree", cpu_freestanding_program);
    try testing.expectEqualStrings("", plain.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, plain.run.term);
    try testing.expect(std.mem.indexOf(u8, plain.llvm, "myl_core_registers_") == null);
    for (cpu_assembly) |line| try testing.expect(std.mem.indexOf(u8, plain.llvm, line) != null);
    for ([_][]const u8{ "my.cpu::interrupts_off", "my.cpu::interrupts_restore", "my.cpu::send_event", "my.cpu::wait_for_event", "my.cpu::wait_for_interrupt", "my.cpu::barrier", "my.cpu::breakpoint" }) |name| {
        const body = defineBody(plain.llvm, try std.fmt.allocPrint(a, "@\"{s}\"(", .{name}));
        try testing.expect(std.mem.indexOf(u8, body[0 .. std.mem.indexOfScalar(u8, body, '\n') orelse body.len], "section \".ramfunc\"") != null);
    }
    const plain_image = try temp.dir.readFileAlloc(testing.io, "cpufree", a, .unlimited);
    for (cpu_encodings) |code| try testing.expect(std.mem.indexOf(u8, plain_image, code) != null);
    // `--release` is the same text (LLVM's own inlining, after this text, puts every instruction inline in the function that
    // calls it: the image of `test/bare/freestanding_ram_cpu.selka` shows `mrs`, `cpsid i`, `msr` in the ram function itself), and
    // it must still link, past the image check, with every helper in RAM and no runtime function named.
    const release = try bareRelease(a, temp.dir, "cpufree_release", cpu_freestanding_program);
    try testing.expectEqualStrings("", release.run.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, release.run.term);
    try testing.expect(std.mem.indexOf(u8, release.llvm, "myl_core_registers_") == null);
    for (cpu_assembly) |line| try testing.expect(std.mem.indexOf(u8, release.llvm, line) != null);
    try testing.expect(std.mem.indexOf(u8, release.llvm, "define internal fastcc i32 @\"my.cpufree_release::in_ram\"(i64 %p0) nounwind noinline \"nooutline\" \"no-jump-tables\"=\"true\" section \".ramfunc\"") != null);
    for (cpu_encodings) |code| try testing.expect(std.mem.indexOf(u8, release.image, code) != null);
}

test "an image that runs from RAM, whose .data holds only .ramfunc code, passes the image check, and a .ramfunc left in .text is still refused" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temp = testing.tmpDir(.{});
    defer temp.cleanup();
    const script = try std.Io.Dir.cwd().readFileAlloc(testing.io, qemu_script, a, .unlimited);
    // `.data` between `__data_start` and `__data_end` keeps the code of the ram functions and no initialised variable: the
    // variables go to a section of their own after it, which the program here does not have either.
    const ram_only = try std.mem.replaceOwned(u8, a, script, "*(.data*) . = ALIGN(4); __data_end = .; } > RAM", "__data_end = .; } > RAM\n  .data2 : { *(.data*) } > RAM");
    try testing.expect(!std.mem.eql(u8, ram_only, script));
    try temp.dir.writeFile(testing.io, .{ .sub_path = "ram_only.ld", .data = ram_only });
    // The same script with `.ramfunc` first in `.text`, where a device keeps its code in flash.
    const without = try std.mem.replaceOwned(u8, a, ram_only, "*(.ramfunc*) . = ALIGN(4); __data_end", "__data_end");
    const in_text = try std.mem.replaceOwned(u8, a, without, ".text : { *(.text*)", ".text : { *(.ramfunc*) *(.text*)");
    try testing.expect(!std.mem.eql(u8, in_text, ram_only));
    try temp.dir.writeFile(testing.io, .{ .sub_path = "in_text.ld", .data = in_text });
    const root = try temp.dir.realPathFileAlloc(testing.io, ".", a);
    const refused = try targetBuild(a, temp.dir, "in_text", ram_clean_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", try std.fs.path.join(a, &.{ root, "in_text.ld" }) });
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, refused.term);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "step` is at 0x") != null);
    try testing.expect(std.mem.indexOf(u8, refused.stderr, "in `.text`, which the image does not load into RAM") != null);
    const kept = try targetBuild(a, temp.dir, "ram_only", ram_clean_program, "thumbv6m-none", &.{ "--link", qemu_platform, "--linker-script", try std.fs.path.join(a, &.{ root, "ram_only.ld" }) });
    try testing.expectEqualStrings("", kept.stderr);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, kept.term);
    const ran = try onQemu(a, try std.fs.path.join(a, &.{ root, "ram_only" }));
    try testing.expectEqual(std.process.Child.Term{ .exited = 42 }, ran.term);
}
