//! The C ABI of `extern def` calls, in one place (target.zig: `CAbi`). Today it is
//! SysV x86-64 limited to scalars and pointers, which LLVM's own calling
//! convention for those types implements once a narrow integer or `bool` argument
//! carries its extension attribute; capability arguments are dropped.
//! Windows x64 or AAPCS64 struct passing would be added here, not in the emitter.
const std = @import("std");
const ir = @import("ir.zig");

/// Whether a parameter of this type is passed to the C function at all.
pub fn passes(ty: ir.Type) bool {
    return ty != .cap;
}

/// The C symbol of an `extern def`: its unqualified name.
pub fn symbol(name: []const u8) []const u8 {
    var at: usize = name.len;
    while (at > 0 and name[at - 1] != ':') at -= 1;
    return name[at..];
}

/// Whether an `extern_c` function is a source `extern def` rather than a runtime helper:
/// the checker refuses source C symbols in the runtime's `myl_` and `mylang_` namespaces.
pub fn source(name: []const u8) bool {
    const c_name = symbol(name);
    return !std.mem.startsWith(u8, c_name, "myl_") and !std.mem.startsWith(u8, c_name, "mylang_");
}

/// The LLVM parameter attribute (empty for none) that a source `extern def` argument of this
/// type carries: SysV x86-64 C callers widen `int8_t`/`int16_t` by sign and `uint8_t`,
/// `uint16_t` and `bool` by zero to 32 bits, and Clang-compiled callees read the widened
/// register, so an argument passed without it reaches C with undefined upper bits.
pub fn argumentExtension(ty: ir.Type) []const u8 {
    return switch (ty) {
        .i8, .i16 => "signext",
        .u8, .u16, .bool => "zeroext",
        else => "",
    };
}
