//! Shared optimizer event counts for pass results and portable cache artifacts.

/// How often each release pass changed something.
pub const Counts = struct {
    inlined: u32 = 0,
    /// Loop copies added by unswitching and by trip-count guards.
    unswitched: u32 = 0,
    versioned: u32 = 0,
    proven: u32 = 0,
    vectorized: u32 = 0,
};
