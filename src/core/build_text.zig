//! Text builder dispatch reserved for S2-T; existing S1 text paths stay in the builder.

/// The precise unsupported raw-octet type reason.
pub fn bytesRefusal() []const u8 {
    return "bytes type";
}

/// The precise unsupported code-point indexing reason.
pub fn indexRefusal() []const u8 {
    return "string index";
}
