//! The target descriptions (docs/design/new-core-ir.md, Portability). Every
//! target-specific choice of the emitter, the fact pass and the driver is read
//! from a `Target`. A build picks one with `--target NAME` (`byName`); without the
//! flag it builds for `host`. Another target is a new `Target` value plus the pieces
//! this file names, not edits spread through the core.
const std = @import("std");

/// The C calling convention `extern def` calls are lowered for (see `c_abi.zig`): the
/// System V x86-64 one, or the ARM procedure call standard of a Cortex-M.
pub const CAbi = enum { sysv_x86_64, aapcs };

/// How traps are raised and reported (see `runtime/core_rt.c`, `myl_core_trap`): the
/// trap ends the process; its caller frames come from a walk of the stack through
/// `.eh_frame` and, per return address, from DWARF line tables and inline records
/// (`dwarf_lines`, docs/design/new-core-s1.md §13 R-1), or are not named (`posix_exit`,
/// `--trap-frames=posix_exit`, for measuring what the tables cost).
pub const Traps = enum { posix_exit, dwarf_lines };

/// What the vector lowering may use.
pub const Vector = struct {
    /// Bits of one vector register the lowering fills.
    bits: u16,
    /// x86 AVX2 intrinsics are available (`packusdw`, `pmulhuw`, `pmaddwd`); without
    /// them the vector lowering uses generic LLVM vector operations only.
    x86_avx2: bool,
    /// The emitter uses the fact pass's vector plans; without them every loop stays scalar.
    plans: bool,
};

/// The machine's word sizes and calling convention.
pub const Machine = struct {
    /// Bits of user address space: with elements of at least one byte, a list holds
    /// fewer than 2^bits elements (the list-length rule of the fact pass).
    user_address_bits: u6,
    /// Bits of the C `size_t`, the size argument of `memchr` and `memcmp`.
    size_bits: u8,
    c_abi: CAbi,
};

/// A capability family `main` may ask for, in the order of `Type.capabilityIndex` (`Clock` is 0).
pub const Capability = enum(u4) {
    clock,
    entropy,
    filesystem,
    network,
    environment,
    stream,
    host,
    process,
    input,
    stop,
    registers,

    /// The type a program writes for a parameter of this family (`Entropy` for `entropy`).
    pub fn typeName(self: Capability) []const u8 {
        return switch (self) {
            .clock => "Clock",
            .entropy => "Entropy",
            .filesystem => "Filesystem",
            .network => "Network",
            .environment => "Environment",
            .stream => "Stream",
            .host => "Host",
            .process => "Process",
            .input => "Input",
            .stop => "Stop",
            .registers => "Registers",
        };
    }
};

/// The capability families a system provides to `main`.
pub const Capabilities = std.EnumSet(Capability);

/// What a hosted system provides `main`: every family but `Registers`, which only a device has (a test on a host makes a
/// simulated bank with `registers.simulated()`).
const hosted_capabilities = blk: {
    var families = Capabilities.full;
    families.remove(.registers);
    break :blk families;
};

/// What a device provides `main` (MCU-EXT): its memory-mapped registers, and `Host`, through which an `extern func`
/// calls the platform's C (the boot ROM's flash routines, say) as a plain AAPCS call. The bare runtime grants the `Host`
/// unconditionally: a device has no command line to say `--allow-host`.
const device_capabilities: Capabilities = .initMany(&.{ .host, .registers });

/// What the system under the program provides.
pub const System = struct {
    traps: Traps,
    /// Functions carry DWARF line metadata (`!dbg`), for trap frames and for a debugger.
    lines: bool,
    /// Threads exist: the allocator's free lists are thread-local. (In a bare image that starts the second core, each core
    /// has its own free lists through the runtime's emulated TLS, `emit_llvm.perCoreFreeLists`, `driver.bareCores`.)
    threads: bool,
    /// Every function has an unwind table (`uwtable`), which a trap's stack walk reads.
    unwind_tables: bool,
    /// The runtime a program links with, and so whether this machine can run it.
    runtime: Runtime,
    /// The families `main` may ask for (`Stream`, `Filesystem` and the rest); read through `Target.provides`.
    capabilities: Capabilities,
};

/// The runtime a target's programs link with, and how its program is put together.
pub const Runtime = union(enum) {
    /// The hosted runtime (`driver.runtime_source`) with the C library and its start files: an executable this machine runs.
    hosted,
    /// A runtime for a CPU with no operating system: an image this machine cannot run, linked by a linker script the build names.
    bare: Bare,
};

/// How a bare target's image is made (`Runtime.bare`).
pub const Bare = struct {
    /// The runtime's C units, each the files under `src/core/runtime/` it names joined in order and compiled as one.
    units: []const RuntimeUnit,
    /// The headers under `src/core/runtime/` + `header_root` that stand in for the C library of a unit with `headers` set.
    headers: []const []const u8,
    /// Where `headers` are, under `src/core/runtime/`.
    header_root: []const u8,
    /// Arguments of every C compile of the runtime, after the target's own.
    c_flags: []const []const u8,
    /// The arguments that compile one LLVM unit of the program, in place of the build mode's (`build_mode.Mode.compileFlags`).
    compile: []const []const u8,
    /// What a `--release` build adds to every compile and to the link: whole-image optimisation.
    release: []const []const u8,
    /// The link's arguments after its objects: unused sections dropped, the entry symbol, no start files, no C library.
    link: []const []const u8,
};

/// One C unit of a bare runtime (`Bare.units`).
pub const RuntimeUnit = struct {
    /// The files under `src/core/runtime/`, joined in this order.
    files: []const []const u8,
    /// Its own arguments (defines), after `Bare.c_flags`.
    flags: []const []const u8,
    /// Whether `Bare.headers` come first on its include path.
    headers: bool,
    /// What a `--release` build adds after `flags` (the define that makes a trap terse: its code and its place only).
    release: []const []const u8 = &.{},
    /// What the two-core flavour of the runtime adds after `flags` and `release`: only a program that starts the second core
    /// (`registers.start_core1`, `driver.bareCores`) gets it; every other image's runtime is compiled without it.
    cores: Flavour = .{},
    /// What the fault decoder's flavour adds after `cores`: only a program with a freestanding fault site
    /// (`driver.bareFlavour`) gets the decoder of `udf #83` and its table of code names; every other image's fault
    /// handler is the plain one, and its code bytes are what they were without the decoder.
    freestanding: Flavour = .{},
};

/// The arguments a runtime unit's flavour adds (`RuntimeUnit.cores`, `RuntimeUnit.freestanding`): to every compile, and
/// to a `--release` one.
pub const Flavour = struct {
    /// After the unit's own arguments, in every build of the flavour.
    flags: []const []const u8 = &.{},
    /// After `flags`, in a `--release` build of the flavour.
    release: []const []const u8 = &.{},
};

/// Everything target-specific the core uses.
pub const Target = struct {
    /// The name `--target` spells.
    name: []const u8,
    /// The LLVM triple; empty lets clang use the host's (`zig cc` native target).
    triple: []const u8,
    /// The `-target` argument of every `zig cc` that compiles or links for this target.
    cc_target: []const u8,
    /// Code generation flags for the CPU: features decide the vector instructions,
    /// and code layout follows the core's fetch and prediction windows.
    cpu_flags: []const []const u8,
    vector: Vector,
    machine: Machine,
    system: System,

    /// Whether `main` may ask for a capability of `family` on this target: a build refuses an entry parameter of a
    /// family the target does not provide (`E_TARGET_CAPABILITY`).
    pub fn provides(self: Target, family: Capability) bool {
        return self.system.capabilities.contains(family);
    }

    /// The families this target provides, as a sentence names them (`` `Host` and `Registers` ``), in
    /// `capabilityIndex` order: what the refusal of another family lists (`E_TARGET_CAPABILITY`).
    pub fn providedNames(self: Target, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        var text: std.ArrayList(u8) = .empty;
        const count = self.system.capabilities.count();
        var it = self.system.capabilities.iterator();
        var at: usize = 0;
        while (it.next()) |family| : (at += 1) {
            const separator: []const u8 = if (at == 0) "" else if (at + 1 == count) " and " else ", ";
            try text.print(allocator, "{s}`{s}`", .{ separator, family.typeName() });
        }
        return text.items;
    }

    /// The largest number of elements any list can hold on this target.
    pub fn maxListLength(self: Target) i128 {
        return @as(i128, 1) << self.machine.user_address_bits;
    }

    /// The LLVM integer type of the C `size_t`.
    pub fn sizeType(self: Target) []const u8 {
        return if (self.machine.size_bits == 32) "i32" else "i64";
    }

    /// Bytes of a data pointer: the width of `size_t` on every target here. Core IR lays out a pointer field, a list,
    /// box, dictionary or function value and a block reference in this many bytes (`ir.Module.pointer_bytes`).
    pub fn pointerBytes(self: Target) u32 {
        return self.machine.size_bits / 8;
    }

    /// The seven fields the single-target compiler's `Target` had, in its order: what every host key hashes.
    pub fn legacy(self: Target) Legacy {
        return .{
            .triple = self.triple,
            .cpu_flags = self.cpu_flags,
            .vector_bits = self.vector.bits,
            .x86_avx2 = self.vector.x86_avx2,
            .user_address_bits = self.machine.user_address_bits,
            .c_abi = self.machine.c_abi,
            .traps = self.system.traps,
        };
    }

    /// What sets a target other than the host apart, which its keys hash after `legacy`.
    pub fn distinct(self: Target) Distinct {
        return .{ .name = self.name, .cc_target = self.cc_target, .vector_plans = self.vector.plans, .size_bits = self.machine.size_bits, .system = self.system };
    }

    /// Whether this is the host target (or a variant of it that `--generic-vectors`, `--trap-frames` or `--cpu` made).
    pub fn isHost(self: Target) bool {
        return std.mem.eql(u8, self.name, host.name);
    }

    /// This target built for `cpu`: the same target for `native`; for another model the host target's variant with its flags
    /// (`x86_64_linux_v3`), or null for a bare target, which has no x86 CPU to choose.
    pub fn forCpu(self: *const Target, cpu: Cpu) ?*const Target {
        return switch (cpu) {
            .native => self,
            .x86_64_v3 => if (self.isHost()) &x86_64_linux_v3 else null,
        };
    }

    /// The model this target's flags name: `x86_64_v3` for `x86_64_linux_v3`, `native` for every other target.
    pub fn cpuModel(self: Target) Cpu {
        const v3 = x86_64_linux_v3.cpu_flags[0];
        return if (self.isHost() and std.mem.eql(u8, self.cpu_flags[0], v3)) .x86_64_v3 else .native;
    }

    /// Whether this machine runs the programs built for this target: `run`, `run-project`, `build --run` and `test` take only
    /// such a target, and a bare one only builds.
    pub fn runsHere(self: Target) bool {
        return self.system.runtime == .hosted;
    }

    /// The JSON a build hashes into its keys (`pipeline.prepareCallables`): for the host,
    /// exactly what the single-target compiler wrote, so every host key keeps its value;
    /// another target adds what sets it apart.
    pub fn jsonStringify(self: Target, writer: anytype) !void {
        if (self.isHost()) return writer.write(self.legacy());
        return writer.write(.{ .legacy = self.legacy(), .distinct = self.distinct() });
    }
};

/// `Target.legacy`: the single-target compiler's fields.
pub const Legacy = struct {
    triple: []const u8,
    cpu_flags: []const []const u8,
    vector_bits: u16,
    x86_avx2: bool,
    user_address_bits: u6,
    c_abi: CAbi,
    traps: Traps,
};

/// `Target.distinct`: the fields a target other than the host adds to its keys.
pub const Distinct = struct { name: []const u8, cc_target: []const u8, vector_plans: bool, size_bits: u8, system: System };

/// The `zig cc` arguments that start the innermost loops on a 64-byte boundary, after the CPU model's, in every hosted build
/// whichever model `--cpu` names.
const loop_alignment = [_][]const u8{ "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6" };

/// The CPU model a hosted build compiles for (`--cpu=MODEL` of `build`, `run`, `run-project`, `build --run` and `test`).
pub const Cpu = enum {
    /// The machine the compiler runs on (`-march=native`), and the default: a program built to run here.
    native,
    /// The AVX2 floor (`-march=x86_64_v3`): the program runs on any machine with AVX2, as the Selka components of a release do.
    x86_64_v3,

    /// The word `--cpu` spells for this model.
    pub fn spelling(self: Cpu) []const u8 {
        return switch (self) {
            .native => "native",
            .x86_64_v3 => "x86-64-v3",
        };
    }

    /// The model `text` spells, or null for any other word.
    pub fn parse(text: []const u8) ?Cpu {
        for (std.enums.values(Cpu)) |model| if (std.mem.eql(u8, text, model.spelling())) return model;
        return null;
    }

    /// The refusal of a `--cpu` value that is not a model: one line, naming the two that are.
    pub fn unknown(allocator: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
        return std.fmt.allocPrint(allocator, "unknown --cpu value `{s}`; the values are `native` and `x86-64-v3`", .{text});
    }
};

/// x86-64 Linux, AVX2 host (alderlake class), 47-bit user address space (no LA57
/// mappings: the runtime never asks for an address above 2^47).
pub const x86_64_linux_avx2: Target = .{
    .name = "x86_64-linux",
    .triple = "",
    // Bundled libc headers and versioned link inputs; the C ABI remains x86-64 SysV.
    .cc_target = "x86_64-linux-gnu.2.31",
    // Innermost loops start on a 64-byte boundary (LLVM's x86 default is 16): Golden
    // Cove's uop cache and branch predictor work in 64-byte windows, so a small hot
    // loop that straddles two pays two lookups per iteration and its branches'
    // prediction depends on where the straddle falls (binary-search-fix README).
    .cpu_flags = &([_][]const u8{"-march=native"} ++ loop_alignment),
    .vector = .{ .bits = 256, .x86_avx2 = true, .plans = true },
    .machine = .{ .user_address_bits = 47, .size_bits = 64, .c_abi = .sysv_x86_64 },
    .system = .{ .traps = .dwarf_lines, .lines = true, .threads = true, .unwind_tables = true, .runtime = .hosted, .capabilities = hosted_capabilities },
};

/// The bare runtime of `src/core/runtime/bare/` (lane MCU-A2): the hosted runtime's files that need no operating system (in
/// the hosted order: `core_bytes.c` calls `core_sha256.c`), then
/// `bare/core_bare.c`, as one unit that sees the stand-in C library of `bare/include` first; `bare/core_bare_link.c` (the
/// allocator's and the C library's symbols) as a second. The platform's `--link` file supplies `myl_bare_write`,
/// `myl_bare_exit` and, if it wants, `myl_bare_platform_start`.
const bare_runtime: Bare = .{
    .units = &.{
        .{
            .files = &.{
                "core_rt.c",             "core_dict.c",      "core_unicode_data.h",    "core_text.c",   "core_sort.c",
                "core_number.c",         "core_sha256.c",    "core_bytes.c",           "core_values.c", "core_owned_copy.c",
                "bare/core_bare_heap.c", "bare/core_bare.c", "bare/core_bare_cores.c",
            },
            .flags = &.{ "-std=c11", "-DMYL_BARE", "-ffreestanding", "-w" },
            .headers = true,
            // A `--release` device image reports a trap as `error[CODE] PATH:LINE`, without the formatting code (core_bare.c).
            .release = &.{"-DMYL_BARE_TERSE"},
            // The two-core flavour (MCU-CORE1): each core's state and heap, the locked log (core_bare_cores.c,
            // core_bare_heap.c), with emulated TLS: each core's copy of a thread-local variable of the runtime comes from
            // `__emutls_get_address`, and the program's units ask it for the free lists themselves
            // (`emit_llvm.perCoreFreeLists`). In `--release` the unit stays machine code (`-fno-lto` after the whole
            // image's `-flto`): link-time code generation would lower its thread-local variables to native TLS, which a
            // bare image has no segment for.
            .cores = .{ .flags = &.{ "-DMYL_BARE_CORES", "-femulated-tls" }, .release = &.{"-fno-lto"} },
            // The fault decoder (MCU-NOC2D): the handler that reads a freestanding fault's code and place from the stacked
            // registers and names the code, with its table, for a program whose units hold a freestanding fault site.
            .freestanding = .{ .flags = &.{"-DMYL_BARE_FREESTANDING"} },
        },
        .{ .files = &.{"bare/core_bare_link.c"}, .flags = &.{"-DMYL_BARE"}, .headers = false },
    },
    .headers = &.{
        "elf.h",    "emmintrin.h", "errno.h",         "execinfo.h", "fcntl.h",       "inttypes.h", "linux/futex.h",
        "malloc.h", "math.h",      "myl_bare_libc.h", "pthread.h",  "sched.h",       "signal.h",   "stdio.h",
        "stdlib.h", "string.h",    "sys/mman.h",      "sys/stat.h", "sys/syscall.h", "time.h",     "unistd.h",
    },
    .header_root = "bare/include/",
    .c_flags = &.{ "-g0", "-fno-unwind-tables", "-fno-asynchronous-unwind-tables", "-fno-stack-protector" },
    .compile = &.{"-Os"},
    .release = &.{"-flto"},
    .link = &.{ "-static", "-nostartfiles", "-Wl,--gc-sections", "-Wl,--build-id=none", "-Wl,-e,myl_bare_reset" },
};

/// An ARM Cortex-M0+ (RP2040 class) with no operating system: 32-bit, no threads but up to two cores (each with its
/// own copy of the runtime's state, `registers.start_core1`), no
/// vector unit, no unwinder. It links with the bare runtime (`bare_runtime`) into an image
/// for a linker script the build names, everything compiled for size with each function and
/// datum in its own section, and it provides `main` its memory-mapped registers (`Registers`): a read or write of
/// one is a volatile load or store at the address (`emit_registers.zig`); and `Host`, for `extern func` calls of the
/// platform's C (`device_capabilities`).
pub const thumbv6m_none: Target = .{
    .name = "thumbv6m-none",
    .triple = "thumbv6m-none-eabi",
    .cc_target = "thumb-freestanding-eabi",
    // zig spells CPU names with underscores. These come after the build mode's level on every compile and link.
    .cpu_flags = &.{ "-mcpu=cortex_m0plus", "-Os", "-ffunction-sections", "-fdata-sections" },
    .vector = .{ .bits = 32, .x86_avx2 = false, .plans = false },
    .machine = .{ .user_address_bits = 32, .size_bits = 32, .c_abi = .aapcs },
    .system = .{ .traps = .posix_exit, .lines = true, .threads = false, .unwind_tables = false, .runtime = .{ .bare = bare_runtime }, .capabilities = device_capabilities },
};

/// The target a build uses without `--target`.
pub const host = x86_64_linux_avx2;

/// Every target `--target` names, the host first.
pub const all = [_]*const Target{ &x86_64_linux_avx2, &thumbv6m_none };

/// The target `--target` names `name`, or null for a name that is not known.
pub fn byName(name: []const u8) ?*const Target {
    for (all) |known| if (std.mem.eql(u8, known.name, name)) return known;
    return null;
}

/// The known names, for the refusal of an unknown one: "x86_64-linux, thumbv6m-none".
pub const names = blk: {
    var text: []const u8 = "";
    for (all, 0..) |known, index| text = text ++ (if (index == 0) "" else ", ") ++ known.name;
    break :blk text;
};

/// The host's C `-target`, for the tools that only ever build for the host (the toolchain's
/// approval).
pub const native_link_target = host.cc_target;

/// A generic target description for tests of the portable fallbacks: same layout,
/// no x86 intrinsics.
pub const generic_256 = blk: {
    var t = x86_64_linux_avx2;
    t.vector.x86_avx2 = false;
    break :blk t;
};

/// The host target compiled for the AVX2 floor (`--cpu=x86-64-v3`): the host's description with the model's `-march` in place
/// of `-march=native`. It keeps the host's name, so `isHost` holds, and it is not in `all`: `--cpu` chooses it, never `--target`.
pub const x86_64_linux_v3 = blk: {
    var t = x86_64_linux_avx2;
    t.cpu_flags = &([_][]const u8{"-march=x86_64_v3"} ++ loop_alignment);
    break :blk t;
};

comptime {
    for (all) |known| std.debug.assert(known.vector.bits % 16 == 0);
}
