//! Source coordinates shared by Core diagnostics and native emission.

/// A source line and column for a span start.
pub const Location = struct { line: u32, column: u32, path: []const u8 = "" };

/// Resolve source offsets without depending on an emitter or the frontend.
pub const Locator = struct {
    context: *const anyopaque,
    locate: *const fn (*const anyopaque, u32) Location,
};
