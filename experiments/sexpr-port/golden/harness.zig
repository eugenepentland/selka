//! Golden harness: run the REAL Zig S-expression printer from the sibling
//! `eda` repo over one input file and write its exact bytes to stdout.
//!
//! This file is the reference side of the byte-for-byte golden comparison in
//! `experiments/sexpr-port/golden_compare.py`. It is not built by mylang; it is
//! compiled with the pinned Zig against a *symlink* to `eda/src` set up by
//! `generate_zig_goldens.sh`, e.g.:
//!
//!   mkdir -p /tmp/sexpr-golden
//!   ln -s /home/epentland/ai/canopy/eda/src /tmp/sexpr-golden/src
//!   cp experiments/sexpr-port/golden/harness.zig /tmp/sexpr-golden/
//!   cd /tmp/sexpr-golden
//!   zig run harness.zig -- /abs/path/to/input.sexp > golden/<name>.txt
//!
//! The imports below are relative to the harness's working directory, which is
//! why it must run from a directory containing a `src` entry (the symlink).
//!
//! Two things are non-negotiable for this to link:
//!   * `pub var process_io` must exist in the ROOT source file, because
//!     `eda/src/infra/fs.zig` reads it via `@import("root").process_io`; the
//!     root file here is this harness, so the declaration lives here.
//!   * `main` takes `std.process.Init` (Zig 0.17), which installs the I/O
//!     capability used for both reading the input and writing stdout.
//!
//! Output contract: the printer's bytes are written verbatim, with NO trailing
//! newline appended. `printer.print` already separates top-level forms with
//! '\n'; a caller that wants a final newline adds it. `golden_compare.py`
//! compensates for the mylang side's own trailing newline, not this one.

const std = @import("std");
const sexpr_parser = @import("src/sexpr/parser.zig");
const printer = @import("src/sexpr/printer.zig");

/// Process I/O capability handed to the rest of the `eda` source graph.
/// `infra/fs.zig` reads this through `@import("root")`, so it must be `pub` and
/// must live in the root (main) file. `.failing` until `main` installs the real
/// capability from `std.process.Init`.
pub var process_io: std.Io = .failing;

/// Upper bound on an input file. Real EDA sources are ~185 kB; 256 MiB keeps a
/// stray binary or a pathological file from being read into a Debug-build list.
const max_input_bytes: u64 = 256 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    process_io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try std.Io.File.stderr().writeStreamingAll(init.io, "usage: harness <input.sexp>\n");
        std.process.exit(2);
    }

    const path = args[1];
    const source = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        path,
        arena,
        .limited64(max_input_bytes),
    ) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, "read failed: ");
        try std.Io.File.stderr().writeStreamingAll(init.io, @errorName(err));
        try std.Io.File.stderr().writeStreamingAll(init.io, "\n");
        std.process.exit(2);
    };

    const nodes = sexpr_parser.parse(arena, source) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, "parse failed: ");
        try std.Io.File.stderr().writeStreamingAll(init.io, @errorName(err));
        try std.Io.File.stderr().writeStreamingAll(init.io, "\n");
        std.process.exit(1);
    };

    const text = try printer.print(arena, nodes);
    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
