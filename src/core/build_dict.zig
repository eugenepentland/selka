//! Dictionary builder dispatch reserved for S2-D; source paths refuse until implemented.

/// The precise unsupported dictionary or set type reason.
pub fn typeRefusal(set: bool) []const u8 {
    return if (set) "set type" else "dict type";
}
