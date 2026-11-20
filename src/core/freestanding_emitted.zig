//! The emitted side of `@freestanding` (`freestanding.zig`): how a failed check of a freestanding function faults, and the
//! check that the LLVM text of such a function names no runtime symbol.
//!
//! A failed check calls nothing. Its code and place are put in the first three argument registers and the target's trap
//! instruction runs: on `thumbv6m-none` `r0` holds the code, `r1` the address of the source path (a NUL-terminated
//! string, `@myl.path.N`) and `r2` the line, then `udf #83`; on x86-64 `rdi`, `rsi` and `rdx` hold them, then `ud2`. The
//! code is the trap kind the runtime numbers (`TRAP_*` in `runtime/core_rt.c`, `emit_llvm.TrapKind`) in its low byte; an
//! assertion's clause (`assert`, `@requires`, `@ensures`, `@invariant`) is in the next byte. The bare runtime's fault
//! handler decodes them (`runtime/bare/core_bare.c`, `myl_bare_fault_frame`): it reads the stacked registers, sees the
//! `udf #83` at the stacked program counter, and reports `error[R_LIST_BOUNDS] PATH:LINE` as a `--release` device build's
//! terse trap does. On x86-64 Linux the `ud2` is followed by the four bytes `MYLF`, which no instruction LLVM or the C
//! compiler emits after a `ud2` holds, and a unit that holds a fault carries its own `SIGILL` handler (`linuxHandler`),
//! installed by a constructor before `main`: it sees `ud2` and `MYLF` at the faulting address, flushes the program's
//! output, prints `error[R_LIST_BOUNDS] PATH:LINE` and the trap record a trap prints, and exits with status 1, as a trap
//! does. Any other illegal instruction is left to the default action. A program with no freestanding code has no fault,
//! so no handler: its executable is what it was.
//!
//! A foreign call in freestanding code (`emit_llvm.zig`, `freestandingHostCheck`) records no place and checks its `Host`
//! token inline against the constant both runtimes give it (`host_token`): a mismatch is the fault `R_CAPABILITY`.
const std = @import("std");
const ir = @import("ir.zig");
const Target = @import("target.zig").Target;

/// The immediate of the Thumb `udf` a freestanding fault uses: 83 is `S`. LLVM's own trap is `udf #254`, so a handler can
/// tell the two apart.
pub const thumb_immediate = 83;

/// The text of a Thumb fault in a unit's LLVM text, `asm sideeffect "udf #83"`: a unit that holds it is a failed check of a
/// `@freestanding` function, and a program with such a unit links the bare runtime's fault decoder (`driver.bareFlavour`).
/// A program with none has no fault to decode. `fault` writes it, and nothing else in the compiler's text does.
pub const fault_site = std.fmt.comptimePrint("asm sideeffect \"udf #{d}\"", .{thumb_immediate});

/// The bytes after an x86-64 fault's `ud2` (`MYLF`): LLVM's `llvm.trap` and the C compiler's checks are a `ud2` or `ud1`
/// followed by the next instruction, so the Linux handler tells a freestanding fault from them by these bytes.
pub const x86_signature = "MYLF";

/// The `Host` token both runtimes hand `main(host: Host)` (`core_io.c`, `bare/core_bare.c` `myl_core_host_grant`). On the
/// host the runtime's own check also reads its `--allow-host` flag, but the token exists only once the flag is set: the
/// grant fails without it and a `Host?` is then `None`, and nothing clears the flag. So the inline compare decides as the
/// runtime's check does.
pub const host_token: i64 = -6;

/// The trap kind of a freestanding foreign call whose `Host` token is not the live one: a fault only (`R_CAPABILITY`), the
/// runtime's own check failing as `core_io_fail` does.
pub const capability_kind = 24;

/// The trap kind numbered by the runtime for an assertion (`TRAP_ASSERTION`).
const assertion_kind = 8;

/// The fault code of a check of trap kind `kind`: the kind, and for an assertion the clause in the second byte.
pub fn faultCode(kind: u8, clause: u32) u32 {
    return @as(u32, kind) | (if (kind == assertion_kind) (clause & 0xff) << 8 else 0);
}

/// One fault: its code, the site whose `@myl.path.N` names its source file, its line and the instruction's debug location
/// suffix (`, !dbg !N` or empty).
pub const Fault = struct { code: u32, path: u32, line: u32, location: []const u8 };

/// Append the fault: one inline-assembly call that loads the registers and runs the trap instruction, then `unreachable`.
pub fn fault(a: std.mem.Allocator, out: *std.ArrayList(u8), target: Target, item: Fault) std.mem.Allocator.Error!void {
    if (thumb(target)) {
        try out.print(a, "  call void " ++ fault_site ++ ", \"{{r0}},{{r1}},{{r2}}\"(i32 {d}, ptr @myl.path.{d}, i32 {d}) #2{s}\n  unreachable\n", .{ item.code, item.path, item.line, item.location });
    } else try out.print(a, "  call void asm sideeffect \"ud2\\0A.ascii \\22{s}\\22\", \"{{rdi}},{{rsi}},{{rdx}}\"(i64 {d}, ptr @myl.path.{d}, i64 {d}) #2{s}\n  unreachable\n", .{ x86_signature, item.code, item.path, item.line, item.location });
}

/// The code each fault code names, by trap kind (`TRAP_*`, as `myl_core_trap` in `runtime/core_rt.c` names them), then
/// the four clauses of an assertion's second byte.
const code_names = [_][]const u8{
    "R_OVERFLOW",                "R_DIVISION_BY_ZERO",    "R_LIST_BOUNDS",     "R_FLOAT_CONVERSION", "R_OVERFLOW",
    "R_CORE_FACT",               "R_LIST_BOUNDS",         "R_OVERFLOW",        "R_ASSERT",           "R_MISSING_KEY",
    "R_LIST_ITERATION_MUTATION", "R_TEXT_BOUNDS",         "R_EMPTY_SEPARATOR", "R_SLICE_STEP",       "R_BYTE_RANGE",
    "R_TEXT_SCALAR",             "R_SUBSTRING_NOT_FOUND", "R_INVALID_SHIFT",   "R_LIST_VALUE",       "R_LIST_BOUNDS",
    "R_TEXT_BOUNDARY",           "R_TYPED_HOLE",          "R_FOREIGN_RESULT",  "R_FOREIGN_TARGET",   "R_CAPABILITY",
    "R_ASSERT",                  "R_REQUIRES",            "R_ENSURES",         "R_INVARIANT",
};

/// The number of trap kinds `code_names` names before the clauses.
const named_kinds = capability_kind + 1;

/// The bytes of LLVM string text whose only escapes are `\\XX` pairs.
fn llvmLength(text: []const u8) usize {
    return text.len - 2 * std.mem.count(u8, text, "\\");
}

/// Whether a unit for `target` that holds a fault carries the Linux handler: x86-64 Linux, whose fault is `ud2`.
pub fn linuxTarget(target: Target) bool {
    return std.mem.startsWith(u8, target.cc_target, "x86_64-linux");
}

/// A C function the Linux handler calls, and its declaration, for a unit that does not declare it already.
pub const Extern = struct { name: []const u8, declaration: []const u8 };

/// What `linuxHandler` calls: the C library's `sigaction`, `dprintf` and `_exit`, and the runtime's stream flush.
pub const handler_externs = [_]Extern{
    .{ .name = "sigaction", .declaration = "declare i32 @sigaction(i32, ptr, ptr) nounwind\n" },
    .{ .name = "dprintf", .declaration = "declare i32 @dprintf(i32, ptr, ...) nounwind\n" },
    .{ .name = "_exit", .declaration = "declare void @_exit(i32) noreturn nounwind\n" },
    .{ .name = "myl_core_stream_flush", .declaration = "declare void @myl_core_stream_flush(i64) nounwind\n" },
};

/// The Linux handler of a unit that holds a fault: the code names, a constructor that installs the handler for `SIGILL`
/// (`SA_SIGINFO | SA_RESETHAND`, so a second illegal instruction, or one that is not a fault, takes the default action),
/// and the handler. It reads the faulting address (`REG_RIP`) and the code, path and line (`rdi`, `rsi`, `rdx`) from the
/// kernel's `ucontext_t` (`uc_mcontext.gregs` at byte 40; the same layout under glibc and musl); flushes standard output
/// and standard error as a trap does (`flush_all`); prints the line and the trap record (`SELKA-TRAP`, which is how
/// `selka test` tells a trap from a crash); and exits 1, as `myl_core_trap` does.
pub fn linuxHandler(a: std.mem.Allocator, out: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    for (code_names, 0..) |name, index| try out.print(a, "@myl.fault.name.{d} = private unnamed_addr constant [{d} x i8] c\"{s}\\00\"\n", .{ index, name.len + 1, name });
    try out.print(a, "@myl.fault.names = private constant [{d} x ptr] [", .{code_names.len});
    for (0..code_names.len) |index| try out.print(a, "{s}ptr @myl.fault.name.{d}", .{ if (index == 0) "" else ", ", index });
    try out.appendSlice(a, "]\n");
    const format = "error[%s] %s:%lld\\0A";
    try out.print(a, "@myl.fault.format = private unnamed_addr constant [{d} x i8] c\"{s}\\00\"\n", .{ llvmLength(format) + 1, format });
    const record = "\\1ESELKA-TRAP {\\22version\\22:1,\\22operation\\22:\\22freestanding fault\\22}\\0A";
    try out.print(a, "@myl.fault.record = private unnamed_addr constant [{d} x i8] c\"{s}\\00\"\n", .{ llvmLength(record) + 1, record });
    try out.appendSlice(a, "@llvm.global_ctors = appending global [1 x { i32, ptr, ptr }] [{ i32, ptr, ptr } { i32 65535, ptr @myl.fault.install, ptr null }]\n");
    try out.appendSlice(a,
        \\define internal void @myl.fault.install() nounwind {
        \\  %action = alloca [19 x i64], align 8
        \\  store [19 x i64] zeroinitializer, ptr %action, align 8
        \\  store ptr @myl.fault.handler, ptr %action, align 8
        \\  %flags = getelementptr inbounds i8, ptr %action, i64 136
        \\  store i32 -2147483644, ptr %flags, align 8
        \\  %installed = call i32 @sigaction(i32 4, ptr %action, ptr null)
        \\  ret void
        \\}
        \\define internal void @myl.fault.handler(i32 %signal, ptr %info, ptr %context) nounwind {
        \\  %rip.at = getelementptr inbounds i8, ptr %context, i64 168
        \\  %rip = load i64, ptr %rip.at, align 8
        \\  %pc = inttoptr i64 %rip to ptr
        \\  %instruction = load volatile i16, ptr %pc, align 1
        \\  %ud2 = icmp eq i16 %instruction, 2831
        \\  br i1 %ud2, label %signed, label %other
        \\signed:
        \\  %mark.at = getelementptr inbounds i8, ptr %pc, i64 2
        \\  %mark = load volatile i32, ptr %mark.at, align 1
        \\  %ours = icmp eq i32 %mark, 1179408717
        \\  br i1 %ours, label %fault, label %other
        \\other:
        \\  ret void
        \\fault:
        \\  %code.at = getelementptr inbounds i8, ptr %context, i64 104
        \\  %code = load i64, ptr %code.at, align 8
        \\  %path.at = getelementptr inbounds i8, ptr %context, i64 112
        \\  %path = load ptr, ptr %path.at, align 8
        \\  %line.at = getelementptr inbounds i8, ptr %context, i64 136
        \\  %line = load i64, ptr %line.at, align 8
        \\  %kind = and i64 %code, 255
        \\  %clause.shifted = lshr i64 %code, 8
        \\  %clause = and i64 %clause.shifted, 255
        \\  %clause.known = icmp ult i64 %clause, 4
        \\  %clause.index = select i1 %clause.known, i64 %clause, i64 0
        \\
    );
    try out.print(a,
        \\  %clause.slot = add i64 %clause.index, {d}
        \\  %kind.known = icmp ult i64 %kind, {d}
        \\  %kind.slot = select i1 %kind.known, i64 %kind, i64 0
        \\  %assertion = icmp eq i64 %kind, {d}
        \\  %slot = select i1 %assertion, i64 %clause.slot, i64 %kind.slot
        \\  %name.at = getelementptr inbounds [{d} x ptr], ptr @myl.fault.names, i64 0, i64 %slot
        \\
    , .{ named_kinds, named_kinds, assertion_kind, code_names.len });
    try out.appendSlice(a,
        \\  %name = load ptr, ptr %name.at, align 8
        \\  call void @myl_core_stream_flush(i64 1)
        \\  call void @myl_core_stream_flush(i64 2)
        \\  %said = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @myl.fault.format, ptr %name, ptr %path, i64 %line)
        \\  %recorded = call i32 (i32, ptr, ...) @dprintf(i32 2, ptr @myl.fault.record)
        \\  call void @_exit(i32 1)
        \\  unreachable
        \\}
        \\
    );
}

/// The section a `@freestanding(ram)` function's code goes to on a bare target (MCU-NOC2B). The device's linker script loads
/// it into RAM with the initialised data (`*(.ramfunc*)` first in `.data`, as `scripts/bare/qemu/link.ld` does), and its
/// start-up copies it there; `ram_image.zig` refuses an image whose script did not.
pub const ram_section = ".ramfunc";

/// Where a function's code goes on a bare target: where the target puts it, in RAM as a `@freestanding(ram)` function, or
/// in RAM as a `registers` read or write of a program with such functions (`registersAccess`), which a `ram` function
/// calls where it is not inlined (a plain build inlines nothing).
pub const Placement = enum { default, ram, ram_helper };

/// What the `define` line of a function adds after its attributes on a bare target: for a `ram` function `noinline` (its
/// code inlined into a caller in flash would run from flash), no outlining (an outlined piece goes to `.text`), no jump
/// table (a table would be read from flash) and the section `ram_section`; for a `ram_helper` the section alone, so a
/// caller in flash may still inline it. Nothing on the host, where all code runs from RAM, nor for any other function.
/// Core keeps a `ram` function out of a caller that is not `ram` too (`inline.zig`, `keepsPlace`).
pub fn placement(target: Target, place: Placement) []const u8 {
    if (target.system.runtime != .bare) return "";
    return switch (place) {
        .default => "",
        .ram => " noinline \"nooutline\" \"no-jump-tables\"=\"true\" section \"" ++ ram_section ++ "\"",
        .ram_helper => " section \"" ++ ram_section ++ "\"",
    };
}

fn thumb(target: Target) bool {
    return std.mem.startsWith(u8, target.cc_target, "thumb");
}

/// A broken promise: the freestanding function and the symbol its emitted text names.
pub const Violation = struct { function: []const u8, symbol: []const u8 };

/// The simulated bank's operations (`runtime/core_registers.c`, `myl_core_registers_NAME`) that a device emits as a volatile
/// load or store or as an instruction (`emit_registers.zig`): the `registers` reads and writes, and the `cpu` functions
/// that act on the machine. A freestanding function's text may name them on Linux, where they are the bank's calls; the
/// bank's readers (`cpu_event_count`, `cpu_interrupts_now`, ...) are not here. Every one is also a row of
/// `freestanding.inline_builtins`, directly or through `cpu.interrupts_off` and `cpu.interrupts_restore`.
const bank_operations = [_][]const u8{
    "read8",              "read16",                 "read32",
    "write8",             "write16",                "write32",
    "cpu_wait_for_event", "cpu_wait_for_interrupt", "cpu_send_event",
    "cpu_barrier",        "cpu_breakpoint",         "cpu_interrupts_disable",
    "cpu_interrupts_set",
};

/// Whether `name` (a runtime function's name, without the `@`) is one of `bank_operations`.
fn bankOperation(name: []const u8) bool {
    const prefix = "myl_core_registers_";
    if (!std.mem.startsWith(u8, name, prefix)) return false;
    for (bank_operations) |operation| if (std.mem.eql(u8, name[prefix.len..], operation)) return true;
    return false;
}

/// What the emitted text of a freestanding function may name besides the symbols `allowed` lists: LLVM's intrinsics,
/// the path strings its faults point at, the zero bytes constants are read from, and on Linux the simulated register
/// bank's reads, writes and `cpu` operations (on a device they are volatile loads and stores and instructions,
/// `emit_registers.zig`).
fn builtinAllowed(symbol: []const u8, target: Target) bool {
    if (std.mem.startsWith(u8, symbol, "@llvm.") or std.mem.startsWith(u8, symbol, "@myl.path.") or std.mem.eql(u8, symbol, "@myl.zeros")) return true;
    if (thumb(target)) return false;
    return symbol.len > 1 and bankOperation(symbol[1..]);
}

/// The first symbol (`@name` or `@"name"`) in `text`, the emitted definition of freestanding `function`, that neither
/// `allowed` (the symbols of the functions it may call) nor `builtinAllowed` admits, or null when it keeps the promise.
pub fn check(function: []const u8, text: []const u8, allowed: []const []const u8, target: Target) ?Violation {
    var at: usize = 0;
    // The `define` line names the function itself.
    if (std.mem.indexOfScalar(u8, text, '\n')) |end| at = end;
    while (std.mem.indexOfScalarPos(u8, text, at, '@')) |start| {
        const end = symbolEnd(text, start);
        at = @max(end, start + 1);
        const name = text[start..end];
        if (name.len <= 1) continue;
        if (builtinAllowed(name, target)) continue;
        for (allowed) |known| {
            if (std.mem.eql(u8, known, name)) break;
        } else return .{ .function = function, .symbol = name };
    }
    return null;
}

fn symbolEnd(text: []const u8, start: usize) usize {
    var end = start + 1;
    if (end < text.len and text[end] == '"') {
        end += 1;
        while (end < text.len and text[end] != '"') end += 1;
        return @min(end + 1, text.len);
    }
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_' or text[end] == '.' or text[end] == '$')) end += 1;
    return end;
}

/// The internal error a broken promise is: the function and the symbol, as the other certificate validators name theirs.
pub fn report(violation: Violation) void {
    std.debug.print("internal error: the emitted code of @freestanding function `{s}` names `{s}`, which is not freestanding\n", .{ violation.function, violation.symbol });
}

/// Whether function `index` of `module` is a bank helper (MCU-B1, MCU-NOC2F): a `registers` read or write or a `cpu`
/// operation that acts on the machine, which a device emits as a volatile load or store or as its instruction, or a
/// function that does nothing but make or take apart the one scalar record such an operation answers or takes
/// (`cpu.interrupts_off` and `cpu.interrupts_restore` over the built-ins that read and set PRIMASK). Its body is one call
/// of the simulated bank's operation (`bank_operations`) or of another such helper, and nothing else but plain data
/// (`plumbing`). A test or budgeted run charges the wrapper its steps and frame (`test_runner_budget.zig`,
/// `run_budget.zig`): those calls are the runner's, not the body's.
pub fn registersAccess(module: *const ir.Module, index: usize) bool {
    return registersHelper(module, index, 0);
}

/// How many helpers deep a helper's call may go: `cpu.interrupts_off` calls the wrapper of the PRIMASK read.
const helper_depth = 2;

/// The operations a helper's body may hold beside its one call: parameters, constants, a width change and the making and
/// taking apart of a record, which a `cpu` state is.
fn plumbing(op: ir.Op) bool {
    return switch (op) {
        .param, .iconst, .undef, .copy, .convert, .record_make, .record_get, .call, .ret => true,
        else => false,
    };
}

fn registersHelper(module: *const ir.Module, index: usize, depth: usize) bool {
    const function = &module.functions.items[index];
    if (function.signature.linkage != .internal) return false;
    var calls: usize = 0;
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = function.inst(ref);
        if (!plumbing(inst.op)) return false;
        if (inst.op != .call) continue;
        const callee = inst.a.index();
        if (callee >= module.functions.items.len) return false;
        const name = module.functions.items[callee].name;
        if (budgetHelper(name)) continue;
        if (!bankOperation(name) and !(depth < helper_depth and registersHelper(module, callee, depth + 1))) return false;
        calls += 1;
    };
    return calls == 1;
}

/// The step and frame helpers a test or a budgeted run adds to each function it charges.
fn budgetHelper(name: []const u8) bool {
    for ([_][]const u8{ "myl_core_test_tick", "myl_core_test_enter", "myl_core_test_leave" }) |known| {
        if (std.mem.eql(u8, name, known)) return true;
    }
    return false;
}

test "a symbol the promise does not admit is named with its function" {
    const host = @import("target.zig").host;
    const text = "define internal fastcc i64 @\"my.f\"(i64 %p0) {\n  call void @myl_core_trap(ptr @myl.site.0, i64 0, i64 0)\n}\n";
    const found = check("f", text, &.{}, host).?;
    try std.testing.expectEqualStrings("f", found.function);
    try std.testing.expectEqualStrings("@myl_core_trap", found.symbol);
    const clean = "define internal fastcc i64 @\"my.f\"(i64 %p0) {\n  %v = call i64 @\"my.g\"(i64 %p0)\n  call void @llvm.assume(i1 true)\n}\n";
    try std.testing.expect(check("f", clean, &.{"@\"my.g\""}, host) == null);
    try std.testing.expectEqualStrings("@\"my.g\"", check("f", clean, &.{"@\"my.h\""}, host).?.symbol);
}
