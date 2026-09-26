//! Process-wide switch for opt-in value semantics (`VALUE-SEMANTICS-1`,
//! `docs/value-semantics.md`). `main` sets it once, before any checking or
//! lowering, from `--value-semantics`, from `"value_semantics": true` in the
//! entry's `mylang.json`, or from `MYLANG_VALUE_SEMANTICS=1`, which is how
//! every child compiler a command spawns inherits it. Tests that turn it on
//! restore the previous value before they return.

/// Whether this process checks and lowers programs with value semantics.
pub var enabled: bool = false;

/// Internal measurement build: count COW sites only with value semantics.
pub var counting: bool = false;
