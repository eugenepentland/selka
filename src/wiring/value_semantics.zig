//! Process-wide value semantics mode (`VALUE-SEMANTICS-1`). Enabled by default;
//! `main` settles explicit flags, inherited environment and project opt-outs
//! before checking or lowering. Tests restore the previous mode after use.

/// Whether this process checks and lowers programs with value semantics.
pub var enabled: bool = true;

/// Internal measurement build: count COW sites only with value semantics.
pub var counting: bool = false;
