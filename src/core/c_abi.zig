//! The C ABI of `extern def` calls, in one place (target.zig: `CAbi`). Today it is
//! SysV x86-64 limited to scalars and pointers, which LLVM's own calling
//! convention for those types already implements; capability arguments are dropped.
//! Windows x64 or AAPCS64 struct passing would be added here, not in the emitter.
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
