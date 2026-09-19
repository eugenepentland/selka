//! Minimal benchmark project for the Zig S-expression reader.
//!
//! It builds exactly one executable from the sexpr closure vendored under
//! `src/`, with no other EDA sources, so `zig build` measures compiling this
//! reader rather than the whole application. The optimize mode is selected with
//! `-Doptimize=ReleaseFast|ReleaseSafe|Debug`, and `-p`/`--prefix` chooses where
//! the executable is installed.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "zig-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);
}
