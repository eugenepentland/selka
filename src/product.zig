//! The product's names, in one place.
//!
//! Code that computes with a name (tests a suffix, strips it, joins a directory, builds a path or a symbol from parts)
//! takes it from here, so that renaming the product means changing these constants and nothing else: no line is left that
//! assumes the old spelling's shape (a three-character suffix, a fixed directory name). A whole name inside a message, a document or a test's
//! expected output stays literal text: a search for the full name finds it there.
//!
//! The helpers take the suffix as an argument (the `isSource` and `sourceStem` forms apply `source_suffix`), so a test can
//! check them with a suffix of another length.
const std = @import("std");

/// The command name, and the name of the installed executable.
pub const command = "selka";
/// The suffix of a source file, with its dot.
pub const source_suffix = ".selka";
/// The suffix that marks a source file as a test file.
pub const test_suffix = "_test" ++ source_suffix;
/// The suffix of a module interface artifact, with its dot.
pub const interface_suffix = ".selkai";
/// The project file's name: the nearest one at or above an entry configures it.
pub const project_file = "selka.json";
/// The name of the work directory a project keeps its caches in, and of the compiler's own beside the checkout.
pub const work_dir = ".selka-cache";
/// The work directory of the core's build, check and test caches (the default of `--cache-dir`).
pub const core_work_dir = work_dir ++ "/core";
/// The name of the per-user directories: the last part of `~/.cache/<it>`, `~/.config/<it>`, `~/.local/state/<it>` and
/// the directory under `libexec` that holds the installed components.
pub const user_dir = "selka";
/// Where the install step puts the compiled components, relative to the install prefix.
pub const components_subdir = "libexec/" ++ user_dir ++ "/components";
/// The file beside the executable that the install step writes the commit into.
pub const commit_file = "selka.commit";
/// The prefix of the environment variables the compiler reads. Only `selfhost/components.zig`, the component builder, tests a
/// variable for it; that builder is its own compilation root and keeps the prefix as literal text.
pub const env_prefix = "SELKA_";
/// The prefix of the environment variables the core and its runtime read (the C runtime spells it as text).
pub const core_env_prefix = "SELKA_CORE_";
/// The info-string tag of a fenced documentation block that is a program and runs.
pub const doc_fence_tag = "selka";
/// The tags of the fenced blocks the documentation runner executes.
pub const doc_executable_tags = [_][]const u8{doc_fence_tag};
/// The `# doc:` directive that marks a fenced block as not a program of the language.
pub const doc_not_marker = "not-selka";
/// The same directive as the compiler spelled it before the rename: a page written for the old name keeps its opt-outs, so both work.
pub const doc_old_not_marker = "not-mylang"; // rename: keep
/// The prefix of the symbol a guest function is emitted under (`<prefix>NAME`).
pub const guest_symbol_prefix = "my.";

/// Whether the `# doc:` directive `name` is the not-a-program marker, in either spelling.
pub fn isNotMarker(name: []const u8) bool {
    return std.mem.eql(u8, name, doc_not_marker) or std.mem.eql(u8, name, doc_old_not_marker);
}

/// Whether `path` ends with `suffix`.
pub fn hasSuffix(path: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, path, suffix);
}

/// `path` without its final `suffix`, or `path` itself when it does not end with it.
pub fn dropSuffix(path: []const u8, suffix: []const u8) []const u8 {
    return if (hasSuffix(path, suffix)) path[0 .. path.len - suffix.len] else path;
}

/// Whether `path` names a source file.
pub fn isSource(path: []const u8) bool {
    return hasSuffix(path, source_suffix);
}

/// `path` without the source suffix, or `path` itself when it has none.
pub fn sourceStem(path: []const u8) []const u8 {
    return dropSuffix(path, source_suffix);
}

/// `path` without its last `source_suffix.len` bytes: for a caller that knows `path` is a source path (a stricter
/// `sourceStem`, which leaves a path without the suffix whole).
pub fn chopSource(path: []const u8) []const u8 {
    return path[0 .. path.len - source_suffix.len];
}

/// Whether `path` names a test source file.
pub fn isTestSource(path: []const u8) bool {
    return hasSuffix(path, test_suffix);
}

/// The source file name of `stem`, allocated.
pub fn sourceName(allocator: std.mem.Allocator, stem: []const u8) std.mem.Allocator.Error![]u8 {
    return std.mem.concat(allocator, u8, &.{ stem, source_suffix });
}

/// `symbol` without the guest symbol prefix, or null when it has none.
pub fn guestName(symbol: []const u8) ?[]const u8 {
    return if (std.mem.startsWith(u8, symbol, guest_symbol_prefix)) symbol[guest_symbol_prefix.len..] else null;
}
