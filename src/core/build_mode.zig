//! Guest optimization policy, independent of how the compiler executable was built.
const std = @import("std");

/// The `zig cc` arguments that compile one LLVM unit of a lean debug build, in place of `-O0`: LLVM's IR passes are off
/// (`-Xclang -disable-llvm-passes`, so the unit keeps the shape Core's passes gave it) and code generation runs at -O2
/// (instruction selection, the optimizing register allocator, the machine passes), minus the six that cost compile time and
/// buy no run time on the measured programs (lane DBG-CG2, 5 November 2026): the instruction-reference variable-location
/// analysis, which every function with a line-table subprogram pays for although the IR has no variable debug info, and
/// the machine instruction scheduler, copy propagation, loop strength reduction, machine CSE and machine LICM. One switch is
/// added: interprocedural register allocation (`-mllvm -enable-ipra`), which lets a caller keep values in the registers a
/// callee it can see does not touch instead of saving them around the call. LLVM leaves it off by default; on the EDA
/// port's 547 units it ran 3.5% fewer instructions and about 2% fewer cycles with LLVM's compile work at 0.99 times
/// (lane DBG-IPRA, 18 November 2026).
const lean_flags = [_][]const u8{
    "-O2",                   "-Xclang",                                      "-disable-llvm-passes",
    "-mllvm",                "-experimental-debug-variable-locations=false", "-mllvm",
    "-enable-misched=false", "-mllvm",                                       "-disable-copyprop",
    "-mllvm",                "-disable-lsr",                                 "-mllvm",
    "-disable-machine-cse",  "-mllvm",                                       "-disable-machine-licm",
    "-mllvm",                "-enable-ipra",
};

/// The most bytes of LLVM text a unit of a lean debug build may have and still compile with LLVM's IR passes on
/// (`lean_passes_flags`); a larger unit compiles with `lean_flags`. The cap is inclusive: 50,000 bytes is small, 50,001 is not.
/// Why 50 KB (lane DBG-CAP measured the caps 50, 100, 200 and 400 KB, lane DBG-CAP50 built the one chosen, 18 and 19 November 2026):
/// the units up to it are 374 of the EDA port's 535 and 8.3% of its LLVM text, so the passes cost a cold build of the port 2.9% more
/// CPU time and an edit of one module 0 to 1.2% more instructions (an edit recompiles one unit), and with `-enable-ipra` buy 3.9% less
/// run time on the port and 17.6% less on 29 benchmark programs than the lean build before both (`-enable-ipra` alone: 1.8% and 1.2%);
/// a cap of 100 KB buys 0.4% more run time for 3% more cold build, and 200 KB costs 24% more cold build. That is three points of run
/// time for one of build time on edits and on programs of small units, and less than that on the port's cold build.
/// Lines kept in the debug line table fall from 97.3% to 96.6% of `-O0`'s on the port; trap text is unchanged.
pub const lean_passes_cap: usize = 50_000;

/// `lean_flags` with `-Xclang -disable-llvm-passes` removed: LLVM's own -O2 pipeline (inlining, SROA, GVN, the loop and vector passes)
/// runs on the unit first, then lean's code generation switches. The compile list of a lean unit of at most `lean_passes_cap` bytes.
const lean_passes_flags = blk: {
    if (!std.mem.eql(u8, lean_flags[1], "-Xclang") or !std.mem.eql(u8, lean_flags[2], "-disable-llvm-passes"))
        @compileError("lean_flags no longer starts -O2 -Xclang -disable-llvm-passes");
    break :blk [_][]const u8{lean_flags[0]} ++ lean_flags[3..].*;
};

/// What the key of a lean build adds to `lean_flags`: the cap and the list a unit within it compiles with, so that the two lists and the
/// cap are all in every lean key and no object compiled under another rule is served.
const lean_key_tail = std.fmt.comptimePrint("; units of at most {d} bytes: ", .{lean_passes_cap}) ++ joined(&lean_passes_flags);

const o0_flags = [_][]const u8{"-O0"};
const o2_flags = [_][]const u8{"-O2"};
const o3_flags = [_][]const u8{"-O3"};

/// The guest's build. The development modes keep one LLVM unit per module and their
/// debug lines; release is one unit. Only the optimized development modes run Core's
/// facts passes.
pub const Mode = enum {
    /// Core's facts passes, LLVM `-O0` on every unit: the build of `selka test`, and what `--debug-o0` asks of
    /// `build`, `run`, `run-project` and `build --run` (the cheapest cold build; the slowest code).
    optimized_debug,
    /// The plain build of `build`, `run`, `run-project` and `build --run` (and `--debug-lean` of every command): Core's facts
    /// passes, then LLVM's IR passes off and code generation at -O2 minus the passes that cost compile time and no run
    /// time (`lean_flags`), except that a unit of at most `lean_passes_cap` bytes of LLVM text also gets LLVM's IR passes
    /// (`lean_passes_flags`; `unitFlags` chooses).
    lean_debug,
    /// `--optimize-debug`: Core's facts passes, LLVM -O2.
    optimized_o2,
    /// `--unoptimized`: no Core pass, LLVM -O0.
    debug,
    /// `--release`: Core's passes, one LLVM unit, LLVM -O3.
    release,

    /// The requested zig cc level for the link and for foreign C sources: the plain build links and compiles C at `-O0`.
    /// The pinned Zig currently maps both -O2 and -O3 to Clang -O2 (and -O1 to -O2),
    /// so -O3 here is the same level as -O2. The shared C runtime has its own fixed -O2 policy.
    pub fn level(self: Mode) []const u8 {
        return switch (self) {
            .optimized_debug, .lean_debug, .debug => "-O0",
            .optimized_o2 => "-O2",
            .release => "-O3",
        };
    }

    /// The `zig cc` arguments that compile one LLVM unit of this mode: `level()` alone, except for the lean build, whose answer is
    /// the list of its units above `lean_passes_cap` (`unitFlags` gives one unit's list).
    pub fn compileFlags(self: Mode) []const []const u8 {
        return switch (self) {
            .optimized_debug, .debug => &o0_flags,
            .lean_debug => &lean_flags,
            .optimized_o2 => &o2_flags,
            .release => &o3_flags,
        };
    }

    /// What every store key hashes for this mode: the whole argument list of a unit's compile, spelled out, so that no two
    /// modes share an object and an edit of the lean list moves every key made under it. The lean build's is both its lists
    /// and the cap between them (`lean_key_tail`): a unit's key also hashes its LLVM text, so the text and this string together
    /// fix which list the unit compiled with.
    pub fn keyed(self: Mode) []const u8 {
        return switch (self) {
            .optimized_debug, .debug => comptime joined(&o0_flags),
            .lean_debug => comptime joined(&lean_flags) ++ lean_key_tail,
            .optimized_o2 => comptime joined(&o2_flags),
            .release => comptime joined(&o3_flags),
        };
    }

    /// Whether this is a module-unit development build that runs Core's facts passes.
    pub fn developmentOptimized(self: Mode) bool {
        return self == .optimized_debug or self == .lean_debug or self == .optimized_o2;
    }

    /// Select a CLI mode, rejecting a different mode only after an explicit selection.
    pub fn select(self: *Mode, explicit: *bool, requested: Mode) error{Usage}!void {
        if (explicit.* and self.* != requested) return error.Usage;
        self.* = requested;
        explicit.* = true;
    }

    /// The mode `build`, `run`, `run-project` and `build --run` start from before any option: the lean debug build.
    pub const plain: Mode = .lean_debug;
};

/// Whether a unit of `mode` whose LLVM text is `text_len` bytes compiles with LLVM's IR passes on: a lean build's unit of at most
/// `lean_passes_cap` bytes. No other mode's compile depends on the size.
pub fn passesOn(mode: Mode, text_len: usize) bool {
    return mode == .lean_debug and text_len <= lean_passes_cap;
}

/// The `zig cc` arguments that compile one LLVM unit of `mode` whose LLVM text is `text_len` bytes: `mode.compileFlags()`, except
/// that a lean build's unit of at most `lean_passes_cap` bytes compiles with `lean_passes_flags` (`passesOn`).
pub fn unitFlags(mode: Mode, text_len: usize) []const []const u8 {
    return if (passesOn(mode, text_len)) &lean_passes_flags else mode.compileFlags();
}

/// The words of `flags` as one text, a space between them.
fn joined(comptime flags: []const []const u8) []const u8 {
    comptime {
        var text: []const u8 = "";
        for (flags, 0..) |flag, at| text = text ++ (if (at == 0) "" else " ") ++ flag;
        return text;
    }
}

/// Expect `mode.keyed()` to be `mode.compileFlags()` joined by spaces and nothing else.
fn expectKeyIsFlags(mode: Mode) !void {
    var words = std.mem.splitScalar(u8, mode.keyed(), ' ');
    for (mode.compileFlags()) |flag| try std.testing.expectEqualStrings(flag, words.next().?);
    try std.testing.expect(words.next() == null);
}

/// Expect `actual` to hold the words of `expected`, in order.
fn expectWords(expected: []const []const u8, actual: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try std.testing.expectEqualStrings(want, got);
}

/// Expect a unit of `mode` to compile with `mode.compileFlags()` at every size, the cap's two sides and both ends included.
fn expectSizeIgnored(mode: Mode) !void {
    try std.testing.expect(unitFlags(mode, 0).ptr == mode.compileFlags().ptr);
    try std.testing.expect(unitFlags(mode, lean_passes_cap).ptr == mode.compileFlags().ptr);
    try std.testing.expect(unitFlags(mode, lean_passes_cap + 1).ptr == mode.compileFlags().ptr);
    try std.testing.expect(unitFlags(mode, std.math.maxInt(usize)).ptr == mode.compileFlags().ptr);
    try std.testing.expect(!passesOn(mode, 0));
}

test "the lean build is -O2 code generation with LLVM's passes on small units, and every key spells its mode's whole compile" {
    const lean = Mode.lean_debug;
    const lean_list = "-O2 -Xclang -disable-llvm-passes -mllvm -experimental-debug-variable-locations=false -mllvm -enable-misched=false" ++
        " -mllvm -disable-copyprop -mllvm -disable-lsr -mllvm -disable-machine-cse -mllvm -disable-machine-licm" ++
        " -mllvm -enable-ipra";
    const passes_list = "-O2 -mllvm -experimental-debug-variable-locations=false -mllvm -enable-misched=false" ++
        " -mllvm -disable-copyprop -mllvm -disable-lsr -mllvm -disable-machine-cse -mllvm -disable-machine-licm" ++
        " -mllvm -enable-ipra";
    try std.testing.expectEqualStrings("-O0", lean.level());
    try std.testing.expectEqualStrings("-O2", lean.compileFlags()[0]);
    // The lean key is both lists and the cap, in one string.
    try std.testing.expectEqualStrings(lean_list ++ "; units of at most 50000 bytes: " ++ passes_list, lean.keyed());
    // Interprocedural register allocation is the lean build's alone: no other mode's compile names it.
    try std.testing.expect(std.mem.indexOf(u8, lean.keyed(), "-enable-ipra") != null);
    try std.testing.expect(std.mem.indexOf(u8, Mode.optimized_debug.keyed(), "-enable-ipra") == null);
    try std.testing.expect(std.mem.indexOf(u8, Mode.optimized_o2.keyed(), "-enable-ipra") == null);
    try std.testing.expect(std.mem.indexOf(u8, Mode.release.keyed(), "-enable-ipra") == null);
    // The key of every mode but the lean one is the compile list itself, not a second spelling of it.
    try expectKeyIsFlags(.optimized_debug);
    try expectKeyIsFlags(.optimized_o2);
    try expectKeyIsFlags(.debug);
    try expectKeyIsFlags(.release);
    // The two -O0 modes differ in their Core passes, not in what compiles a unit; every other pair differs in its key.
    try std.testing.expectEqualStrings(Mode.optimized_debug.keyed(), Mode.debug.keyed());
    try std.testing.expect(!std.mem.eql(u8, lean.keyed(), Mode.optimized_debug.keyed()));
    try std.testing.expect(!std.mem.eql(u8, lean.keyed(), Mode.optimized_o2.keyed()));
    try std.testing.expect(!std.mem.eql(u8, Mode.optimized_o2.keyed(), Mode.release.keyed()));
    try std.testing.expect(lean.developmentOptimized() and Mode.optimized_debug.developmentOptimized() and !Mode.debug.developmentOptimized());
    try std.testing.expectEqual(Mode.lean_debug, Mode.plain);
}

test "a lean unit of at most 50,000 bytes compiles with the lean list minus -Xclang -disable-llvm-passes, and the cap is inclusive" {
    const lean = Mode.lean_debug;
    const lean_list = lean.compileFlags();
    const small = unitFlags(lean, 1);
    // The small list is the lean list without its two words: the same switches in the same order, so LLVM's pipeline runs and nothing else moves.
    try std.testing.expectEqual(lean_list.len - 2, small.len);
    try std.testing.expectEqualStrings("-O2", small[0]);
    try expectWords(lean_list[3..], small[1..]);
    try std.testing.expect(std.mem.indexOf(u8, lean.keyed(), "-Xclang -disable-llvm-passes") != null);
    try std.testing.expect(std.mem.indexOf(u8, lean.keyed()[std.mem.indexOf(u8, lean.keyed(), "; units").?..], "-disable-llvm-passes") == null);
    // 50,000 bytes is small and 50,001 is not; an empty unit is small; a larger unit keeps the lean list itself.
    try std.testing.expectEqual(@as(usize, 50_000), lean_passes_cap);
    try std.testing.expect(passesOn(lean, 0));
    try std.testing.expect(passesOn(lean, 50_000));
    try std.testing.expect(!passesOn(lean, 50_001));
    try std.testing.expect(!passesOn(lean, std.math.maxInt(usize)));
    try std.testing.expect(unitFlags(lean, 50_000).ptr == unitFlags(lean, 0).ptr);
    try std.testing.expect(unitFlags(lean, 50_001).ptr == lean_list.ptr);
    try std.testing.expect(unitFlags(lean, 50_000).ptr != lean_list.ptr);
}

test "no other mode's compile depends on the size of the unit" {
    try expectSizeIgnored(.optimized_debug);
    try expectSizeIgnored(.optimized_o2);
    try expectSizeIgnored(.debug);
    try expectSizeIgnored(.release);
    try std.testing.expectEqualStrings("-O0", unitFlags(.optimized_debug, 10)[0]);
    try std.testing.expectEqual(@as(usize, 1), unitFlags(.optimized_debug, 10).len);
}
