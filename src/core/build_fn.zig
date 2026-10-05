//! Function and array builder dispatch reserved for S2-F.

/// The precise unsupported function or fixed-array type reason.
pub fn typeRefusal(array: bool) []const u8 {
    return if (array) "fixed array type" else "function value type";
}

/// The precise unsupported function-reference expression reason.
pub fn valueRefusal() []const u8 {
    return "function_value";
}
