//! The C ABI of `extern def` calls, in one place (target.zig: `CAbi`). Today it is
//! SysV x86-64 limited to scalars and pointers, which LLVM's own calling
//! convention for those types implements once a narrow integer or `bool` argument
//! carries its extension attribute; capability arguments are dropped.
//! Windows x64 or AAPCS64 struct passing would be added here, not in the emitter.
const ir = @import("ir.zig");
const CAbi = @import("target.zig").CAbi;

/// Whether a parameter of this type is passed to the C function at all.
pub fn passes(ty: ir.Type) bool {
    return ty != .cap;
}

/// Whether a C function returns a structure of more than four bytes through memory its caller passes (`sret`, the
/// hidden first argument): so under the ARM procedure call standard. SysV x86-64 returns one of up to 16 bytes in two
/// registers, which is what LLVM does with a structure result, so the host's declarations name the structure.
pub fn structResultInMemory(abi: CAbi) bool {
    return abi == .aapcs;
}

/// Whether a C function whose result has the LLVM type `llvm_type` returns it through memory under `abi`. Every
/// structure or array result the emitter declares is wider than four bytes.
pub fn returnsInMemory(abi: CAbi, llvm_type: []const u8) bool {
    return structResultInMemory(abi) and llvm_type.len != 0 and (llvm_type[0] == '{' or llvm_type[0] == '[');
}

/// The C symbol of an `extern def`: its unqualified name.
pub fn symbol(name: []const u8) []const u8 {
    var at: usize = name.len;
    while (at > 0 and name[at - 1] != ':') at -= 1;
    return name[at..];
}

/// Whether an argument of this type crosses into C as the canonical quiet NaN when it is
/// any NaN (FLOAT-NAN-OBSERVED-3): foreign code can read a double's sign and payload
/// (`copysign`, `signbit`, a byte copy), which no guest operation observes.
pub fn canonicalizesNan(ty: ir.Type) bool {
    return ty == .f64;
}

/// The bits of a double with the sign cleared: a NaN's exceed `infinity_bits`.
pub const magnitude_mask = "9223372036854775807";
/// The bits of positive infinity.
pub const infinity_bits = "9218868437227405312";
/// The canonical quiet NaN, `0x7ff8000000000000`.
pub const canonical_nan_bits = "9221120237041090560";

/// The LLVM parameter attribute (empty for none) that an argument of this type carries in a
/// call to any C function, a source `extern def` or a runtime helper: SysV x86-64 C callers widen `int8_t`/`int16_t` by sign and `uint8_t`,
/// `uint16_t` and `bool` by zero to 32 bits, and Clang-compiled callees read the widened
/// register, so an argument passed without it reaches C with undefined upper bits.
pub fn argumentExtension(ty: ir.Type) []const u8 {
    return switch (ty) {
        .i8, .i16 => "signext",
        .u8, .u16, .bool => "zeroext",
        else => "",
    };
}

/// The runtime copy of a `-> bytes` source extern's result: `(site, data, length)` to a fresh owned `bytes`, trapping
/// `R_FOREIGN_RESULT` on a negative length or a null pointer with a positive one (`runtime/core_text.c`).
pub const bytes_copy = "myl_core_foreign_bytes";

/// Whether a source `extern def` call is more than a scalar call: a `bytes` result the runtime copies (D-FFI-3) or `mut`
/// out-parameters, each a pointer to a temporary (D-FFI-5). Runtime helpers, declared with span 0, never are.
pub fn foreign(function: *const ir.Function) bool {
    if (!function.signature.linkage.externC() or function.span == 0) return false;
    return function.signature.ret == .bytes or function.signature.passing.hasOwned();
}

/// How many `mut` out-parameters a source extern has.
pub fn outCount(sig: ir.Signature) usize {
    return @popCount(sig.passing.owned) + sig.passing.extra_owned.len;
}

/// The C function's own return type: the declared result, which leads the IR result record when the function has `mut`
/// out-parameters (`build.zig` `returnType`), or `void`.
pub fn foreignResult(m: *const ir.Module, sig: ir.Signature) ir.Type {
    const outs = outCount(sig);
    if (outs == 0) return sig.ret;
    if (m.kind(sig.ret) != .record) return .void;
    const fields = m.compound(sig.ret).record;
    return if (fields.len == outs + 1) fields[0] else .void;
}
