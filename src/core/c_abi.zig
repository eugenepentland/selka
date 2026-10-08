//! The C ABI of `extern def` calls, in one place (target.zig: `CAbi`). Today it is
//! SysV x86-64 limited to scalars and pointers, which LLVM's own calling
//! convention for those types implements once a narrow integer or `bool` argument
//! carries its extension attribute; capability arguments are dropped.
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
