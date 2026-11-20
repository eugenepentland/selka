//! What a render of one unit reads of the whole module, read once for all the units of a program (`Survey.of`, made by
//! `emit_units` with the program's descriptor catalog) instead of once for each unit: the validation of the structural
//! equality declarations, whether the `testing` allocation counter is declared, and the parsed fast-path preludes. Done
//! per unit, the first two made emission's cost grow as units times functions.
const std = @import("std");
const ir = @import("ir.zig");
const equality = @import("build_equality.zig");
const testcount_runtime = @import("testcount_runtime.zig");
const fast_paths = @import("emit_fast_paths.zig");

/// Allocation, or a prelude `emit_fast_paths.Prelude.parse` refuses.
pub const Error = fast_paths.Error;

/// The whole-module facts of one program's renders. Read-only once made, so the emission jobs share it across threads.
pub const Survey = struct {
    /// Whether `build_equality.validateModule` accepts the module; a render of a module it refuses fails as it did.
    equality: bool,
    /// Whether the module declares the `testing` allocation counter (`testcount_runtime.needed`).
    test_counts: bool,
    /// The module's function and compound-type counts when it was surveyed. A render of a module whose counts differ
    /// reads the module itself (`fits`).
    functions: usize,
    compounds: usize,
    /// The fast-path preludes a render of this program may append, parsed (`prelude`).
    preludes: []const fast_paths.Prelude,

    /// Survey `module`, parsing each of `preludes`.
    pub fn of(a: std.mem.Allocator, module: *const ir.Module, preludes: []const []const u8) Error!Survey {
        const valid = if (equality.validateModule(a, module)) true else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnsupportedInstruction => false,
        };
        const parsed = try a.alloc(fast_paths.Prelude, preludes.len);
        for (preludes, parsed) |text, *slot| slot.* = try fast_paths.Prelude.parse(a, text);
        return .{
            .equality = valid,
            .test_counts = testcount_runtime.needed(module),
            .functions = module.functions.items.len,
            .compounds = module.compounds.items.len,
            .preludes = parsed,
        };
    }

    /// Whether this survey describes `module`: it has the functions and compound types it had when surveyed. Emission
    /// adds neither, so a mismatch means the survey belongs to another module.
    pub fn fits(self: *const Survey, module: *const ir.Module) bool {
        return module.functions.items.len == self.functions and module.compounds.items.len == self.compounds;
    }

    /// The parsed prelude whose text is `text`, or null when the survey holds none.
    pub fn prelude(self: *const Survey, text: []const u8) ?*const fast_paths.Prelude {
        for (self.preludes) |*known| if (std.mem.eql(u8, known.text, text)) return known;
        return null;
    }
};

/// `survey` when it describes `module`, else null.
pub fn fitting(survey: ?*const Survey, module: *const ir.Module) ?*const Survey {
    const known = survey orelse return null;
    return if (known.fits(module)) known else null;
}

/// Whether `module` declares the `testing` allocation counter: the survey's answer when it describes the module.
pub fn testCounts(survey: ?*const Survey, module: *const ir.Module) bool {
    if (fitting(survey, module)) |known| return known.test_counts;
    return testcount_runtime.needed(module);
}

/// Validate `module`'s structural equality declarations (`build_equality.validateModule`), or answer from the survey.
pub fn validateEquality(a: std.mem.Allocator, survey: ?*const Survey, module: *const ir.Module) (std.mem.Allocator.Error || equality.Error)!void {
    if (fitting(survey, module)) |known| {
        if (!known.equality) return error.UnsupportedInstruction;
        return;
    }
    return equality.validateModule(a, module);
}
