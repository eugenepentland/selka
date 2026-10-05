//! The one target description (docs/design/new-core-ir.md, Portability). Every
//! target-specific choice of the emitter, the fact pass and the driver is read
//! from here. L4: x86-64 Linux with AVX2 is the only target; another one is a new
//! `Target` value plus the pieces this file names, not edits spread through the core.
const std = @import("std");

/// The C calling convention `extern def` calls are lowered for (see `c_abi.zig`).
pub const CAbi = enum { sysv_x86_64 };

/// How traps are raised and reported (see `runtime/core_rt.c`, `myl_core_trap`): the
/// trap ends the process; its caller frames come from a walk of the stack through
/// `.eh_frame` and, per return address, from DWARF line tables and inline records
/// (`dwarf_lines`, docs/design/new-core-s1.md §13 R-1), from labels the emitter puts
/// after every call (`pc_labels`, the measured alternative), or not at all (`posix_exit`).
pub const Traps = enum { posix_exit, pc_labels, dwarf_lines };

/// Everything target-specific the core uses.
pub const Target = struct {
    /// The LLVM triple; empty lets clang use the host's (`zig cc` native target).
    triple: []const u8,
    /// Code generation flags for the CPU: features decide the vector instructions,
    /// and code layout follows the core's fetch and prediction windows.
    cpu_flags: []const []const u8,
    /// Bits of one vector register the lowering fills.
    vector_bits: u16,
    /// x86 AVX2 intrinsics are available (`packusdw`, `pmulhuw`, `pmaddwd`); without
    /// them the vector lowering uses generic LLVM vector operations only.
    x86_avx2: bool,
    /// Bits of user address space: with elements of at least one byte, a list holds
    /// fewer than 2^bits elements (the list-length rule of the fact pass).
    user_address_bits: u6,
    c_abi: CAbi,
    traps: Traps,

    /// The largest number of elements any list can hold on this target.
    pub fn maxListLength(self: Target) i128 {
        return @as(i128, 1) << self.user_address_bits;
    }
};

/// x86-64 Linux, AVX2 host (alderlake class), 47-bit user address space (no LA57
/// mappings: the runtime never asks for an address above 2^47).
pub const x86_64_linux_avx2: Target = .{
    .triple = "",
    // Innermost loops start on a 64-byte boundary (LLVM's x86 default is 16): Golden
    // Cove's uop cache and branch predictor work in 64-byte windows, so a small hot
    // loop that straddles two pays two lookups per iteration and its branches'
    // prediction depends on where the straddle falls (binary-search-fix README).
    .cpu_flags = &.{ "-march=native", "-mllvm", "-x86-experimental-pref-innermost-loop-alignment=6" },
    .vector_bits = 256,
    .x86_avx2 = true,
    .user_address_bits = 47,
    .c_abi = .sysv_x86_64,
    .traps = .dwarf_lines,
};

/// The target every build uses (L4).
pub const current = x86_64_linux_avx2;

/// A generic target description for tests of the portable fallbacks: same layout,
/// no x86 intrinsics.
pub const generic_256 = blk: {
    var t = x86_64_linux_avx2;
    t.x86_avx2 = false;
    break :blk t;
};

comptime {
    std.debug.assert(current.vector_bits % 16 == 0);
}
