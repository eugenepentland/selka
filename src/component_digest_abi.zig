//! Private fixed storage shared by the host and its LLVM SHA-256 object.
/// Storage is opaque; only the pinned helper initializes or interprets it.
pub const State = extern struct { storage: [128]u8 align(16) };
