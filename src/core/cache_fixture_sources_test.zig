//! Shared guest dependency revisions for native compiler and receipt cache tests.
//! Keep these source bytes identical across both independent cache test harnesses.

/// Original dependency revision, returning three.
pub const dependency = "public func value() -> int:\n    return 3\n";
/// Changed dependency revision, returning four.
pub const changed_dependency = "public func value() -> int:\n    return 4\n";
