//! S3-T2 owns mutable-byte and embedded-blob source lowering.
const ir = @import("ir.zig");

/// Keep mutable-byte types refused until runtime and ownership are qualified.
pub fn bufferType(context: anytype, span: u32) error{ OutOfMemory, Unsupported }!ir.Type {
    return context.refuse("byte_buffer type", span);
}

/// Preserve the embedded-asset refusal; S3-T2 resolves the source digest here.
pub fn blob(context: anytype, span: u32) error{ OutOfMemory, Unsupported }!ir.Ref {
    return context.mb.refuse("blob", span);
}
