//! The semantic cache's on-disk format version, apart from the store: `build.zig`
//! passes it to the CLI tests, and importing `semantic_store.zig` there would put
//! the whole front end in the build runner's compile closure, so every edit to it
//! would rebuild the runner and re-key every verification action.

/// On-disk format version. Bump for any layout, tag or validation change.
pub const version = "semantic-cache-v9";
