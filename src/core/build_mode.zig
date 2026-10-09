//! Guest optimization policy, independent of how the compiler executable was built.

/// Optimized debug retains module units and debug lines; release uses one LLVM unit.
pub const Mode = enum {
    debug,
    optimized_debug,
    release,

    /// The optimization level for generated program code and foreign C sources.
    /// The shared C runtime has its own fixed -O2 policy.
    pub fn level(self: Mode) []const u8 {
        return switch (self) {
            .debug => "-O0",
            .optimized_debug => "-O2",
            .release => "-O3",
        };
    }

    /// Select a CLI mode, rejecting incompatible optimization switches.
    pub fn select(self: *Mode, requested: Mode) error{Usage}!void {
        if (self.* != .debug and requested != .debug and self.* != requested) return error.Usage;
        self.* = requested;
    }
};
