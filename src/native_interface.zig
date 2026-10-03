//! Shared frontend export snapshot consumed by independent native backends.
const std = @import("std");
const fragments = @import("qbe_fragments.zig");
const typed = @import("typed.zig");
/// The safety and accounting code one emission is asked to generate. Every
/// field defaults to the fully checked, fully accounted program, so a caller
/// that names nothing gets the language's normal guarantees.
pub const Policy = struct {
    /// Original by default; native builds select the resolved QBE policy.
    native_variants: @import("runtime_contract").native_variants.Policy = .original,
    scalar_policy: @import("runtime_contract").scalars.Policy = .qbe,
    /// Drop `debug` statement lowering. Consumed before QBE emission, by the
    /// lowering step, so the backend never reads it.
    drop_debug: bool = false,
    /// Emit per-instruction step-budget accounting with its position markers. A
    /// build that can never be given a runtime step ceiling turns this off.
    step_checks: bool = true,
    /// Emit the per-call depth ceiling and its counter. A build that can never
    /// be given a runtime frame ceiling turns this off.
    frame_checks: bool = true,
    /// Emit copy-on-write value semantics (`COW-UNIQUE-1`): `checks` shares a
    /// payload at every transfer the ownership analysis calls a copy and makes
    /// it unique before every in-place write; `counting` also counts every
    /// inline check, mark and pin (`COW-STATS-1`).
    cow: Cow = .off,
};
/// Which copy-on-write code a build emits.
pub const Cow = @import("cow_plan.zig").Mode;
/// Public declaration roots and exact language-schema-v1 bytes from one check.
pub const Interface = struct {
    roots: []const typed.FunctionId = &.{},
    schema: ?[]const u8 = null,
    /// The safety and accounting code the backend generates for this program.
    policy: Policy = .{},
    /// Persistent per-function unit reuse, or null to emit every unit fresh.
    reuse: ?fragments.Reuse = null,
    /// MODULE-COMPILE-1: emit one module of the program, reading what its
    /// units need about every function it did not lower from that function's
    /// module interface. Null emits the whole program.
    module: ?*const Module = null,
    /// When set, the emission fills it with what it computed about every
    /// function: the facts a module interface carries and each unit's keys.
    report: ?*fragments.Report = null,
};

/// MODULE-COMPILE-1: one module's emission out of a program checked against
/// its imports' interfaces. Every function without imported facts is lowered
/// and analysed exactly as a whole-program emission analyses it; only the
/// functions `emit` marks become units.
pub const Module = struct {
    /// Per program function: whether this emission emits its unit.
    emit: []const bool,
    /// Per program function: the emission facts another module's interface
    /// states for a function this compilation stood in and did not lower.
    imported: []const ?Imported,
    /// Per merged-source input: the verbatim stretches of an interface text
    /// served in place of that module's source, so a position inside it is
    /// reported at its place in the real source; null for a real source.
    remap: []const ?[]const Stretch = &.{},
    /// The program-wide arena switch (whether any function of the program
    /// opens an arena scope), which every allocating unit's text reads and
    /// which no one module can derive.
    arenas: bool = false,
    /// Filled by the emission: the module's share of the program's runtime
    /// data, for a link to merge with the other modules' shares.
    parts: ?*Parts = null,
    /// MODULE-SCHEDULE-5: called once the allocation analysis is done and
    /// before any unit is emitted, with every function's facts: what a
    /// dependent's compile reads is final then.
    analyzed: ?Analyzed = null,
};

/// A hook the emission calls with every function's facts (no unit keys yet),
/// allocated with `arena`.
pub const Analyzed = struct {
    arena: std.mem.Allocator,
    context: *anyopaque,
    run: *const fn (context: *anyopaque, facts: fragments.Report) anyerror!void,
};

/// One module's share of the shared runtime C unit: the descriptors of every
/// type its compilation knows and the renderers its units call, each a
/// definition group named by its content-derived symbol.
pub const Parts = struct {
    descriptors: []const Block = &.{},
    renderers: []const Block = &.{},
    owners: []const @import("rc_descriptors.zig").Block = &.{},
    glue: []const @import("rc_glue.zig").Block = &.{},
};

/// One generated C definition group and the symbol it is ordered and merged by.
pub const Block = struct { name: []const u8, text: []const u8 };

/// What a caller's unit reads about a function it does not have the body of:
/// whether a call to it may allocate (transitively), and which of its
/// parameters its body writes.
pub const Imported = struct { allocates: bool, writes: []const bool };

/// One verbatim stretch of an interface text: where it starts in the text,
/// how many bytes map linearly onto the source (its copy and the blanked gap
/// after it), and the one-based line and column in the source it starts at.
pub const Stretch = struct { text: u32, extent: u32, line: u32, column: u32 };

/// The index of the stretch a position at `offset` in an interface text of
/// `length` bytes is reported through: the first whose extent holds it; null
/// for an offset no stretch covers (MODULE-COMPILE-1, MODULE-SYMBOL-CUTOFF-5).
pub fn stretchAt(stretches: []const Stretch, length: usize, offset: usize) ?usize {
    if (offset > length) return null;
    for (stretches, 0..) |stretch, index| {
        if (offset < stretch.text or offset > @as(usize, stretch.text) + stretch.extent) continue;
        return index;
    }
    return null;
}
