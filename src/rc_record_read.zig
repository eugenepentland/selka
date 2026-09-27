//! Physical interval identity shared without importing concrete emission.
/// Entry load, inclusive scalar publication end, and the sole raw capture.
pub const Certificate = struct { start: usize, end: usize, root: usize, capture: usize, active: bool = false, home: enum { named, incoming } = .named };
