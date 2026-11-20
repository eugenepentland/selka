//! The data types of the per-function check summaries (`semantic_summary.zig` re-exports them): what one function's summary holds,
//! and the table of them one successful check produces. The stored form and its readers are in `semantic_sections.zig`.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const semantic_key = @import("semantic_key.zig");
const owned = @import("semantic_entry.zig");

/// One edit of a stored repair, its span relative to the start of the function's declaration region.
pub const FixEdit = struct { start: u32, end: u32, text: []const u8 };

/// One stored diagnostic without related notes, its span relative to the start
/// of its function's declaration region.
pub const Note = struct {
    code: []const u8,
    severity: diagnostic.Severity,
    start: u32,
    end: u32,
    message: []const u8,
    rule: ?diagnostic.Rule = null,
    /// The edits of the diagnostic's repair, the first being its main edit; none for a diagnostic with no repair.
    fix: []const FixEdit = &.{},
};

/// What the `W_COPY_MOVE` filter of `check` learned about a caller when its body was checked (FR14b): whether it keeps what
/// the hint of `callee` (a stable key) would take, the result (`result`) or the argument at the parameter named `parameter`.
/// The answer reads the caller's body and the callee's declaration, both in the caller's dependency context, so it stands
/// while the caller's summary does. For a `W_COPY_FOR_STORE` answer that keeps nothing, `marks` are the starts of the
/// caller's arguments the repair writes `own ` before, relative to the start of the caller's declaration region (as pass
/// notes are): a caller that stands in is byte-identical, so they hold.
pub const Keep = struct { callee: []const u8, parameter: []const u8, result: bool, keeps: bool, marks: []const u32 = &.{} };

/// Diagnostics one function contributed: those appended while its body was
/// checked, and the warnings the whole-program passes reported inside it.
pub const Notes = struct {
    body: []const Note = &.{},
    pass: []const Note = &.{},
    /// Whether these notes and the facts beside them can stand in for the passes alone, the body being checked as usual: the function
    /// was checked, is not the entry point, nothing in it was silenced by a waiver and every diagnostic inside it is stored. Only
    /// module-local inputs decide it, never the types the program names (that part of `Summary.stubbable`), so it does not depend on
    /// the entry that made the summary. A summary stands in for its passes when this or `stubbable` is set.
    complete: bool = false,
    /// What decided whether the warnings of the function were reported (`syntax_hints.Guards`): present when it holds a stored warning
    /// or a site a waiver silenced, the digest of its file's waivers (`Guards.of`); for a function with a site whose warning read the
    /// rest of its file (a W13 warning, `Sink.file_reads`), the digest of the whole file as well (`Guards.wide`, FX13). The notes
    /// stand in only while the function's file and region still give the digest they were stored under.
    guard: ?[32]u8 = null,
    /// The filter's answers for this function as a caller of a function that held a judged `W_COPY_MOVE` hint (`Keep`).
    keeps: []const Keep = &.{},
};

/// Length and BLAKE3 digest of one declaration region's bytes, and the names
/// its syntax references (which those bytes determine).
pub const Region = struct { len: u32, digest: [32]u8, names: []const semantic_key.Name = &.{} };

/// Retained local validation facts. Callers read fresh declared signatures,
/// never these body facts, to determine mutation or return ownership.
pub const Fact = struct {
    mutates: []const u16 = &.{},
    mutates_unknown: bool = false,
    return_origin: origins.Origin = .{},
    inferred: struct { writes: bool = false, external: bool = false } = .{},
};

/// One generic template a body's specializations come from, as the body's check saw it: its stable key, dependency context and the
/// digest of its declaration region. A template whose context changed makes the body stale; one whose region changed makes it stale
/// for the artifacts that read callee bodies.
pub const Template = struct { key: []const u8, context: [32]u8, digest: [32]u8 };

/// What a body whose checked tree names a specialization or a type interned while checking needs from a fresh catalog to be stood in
/// for: the specializations to register, the records (declared ones with their shapes, interned ones with the recipe that interns
/// them) and the templates the specializations come from. Spans in the recipes are relative to the body's declaration region.
pub const Refs = struct {
    functions: []const owned.FunctionRef = &.{},
    records: []const owned.RecordRef = &.{},
    templates: []const Template = &.{},
};

/// What one checked body reached besides its own declaration: the functions
/// it calls and the catalog records its checked tree touched.
pub const Uses = struct {
    /// Positions in the same summary table of the functions the body names.
    callees: []const u32 = &.{},
    /// Positions in the same summary table of the functions the body names as values (`sort(key=by_key)`, a table's `parse=parse_one`), each
    /// of them also among `callees`. The optimizer may copy a function value into a unit of another module, so a function named this way is
    /// not private to its module (`typed.Program.private`); a body that stands in has no tree, and its function values are read from here.
    values: []const u32 = &.{},
    /// Positions in the table's record list of the records the tree touched. A record reached only through a field, element or return type
    /// is still touched, so a body is never stood in over a record whose shape (`Table.record_shapes`) changed.
    records: []const u32 = &.{},
    /// The references of a tree that names a specialization or an interned type, or null for a tree that names neither. Such a body can
    /// stand in only after the references resolve against the fresh catalog (G2m).
    refs: ?Refs = null,
};

/// One ordinary function's summary. `stubbable` is false for a function that
/// every check re-checks (the entry point, constants, conversions, host
/// declarations, and bodies whose checked tree names a specialization, a lambda
/// or a type interned while checking); its facts still bound the functions that
/// call it.
pub const Summary = struct {
    key: []const u8,
    context: [32]u8,
    region: Region,
    fact: Fact,
    notes: Notes = .{},
    uses: Uses = .{},
    stubbable: bool,
};

/// One entry's summaries and the names of the records they touched.
pub const Table = struct {
    records: []const []const u8 = &.{},
    /// The transitive shape digest of each record in `records` when the table was made (`Shapes.digest`): a body stands in only while every
    /// record it touched has the digest it had. Empty, or as long as `records`.
    record_shapes: []const [32]u8 = &.{},
    /// One summary per ordinary instance, indexed by instance. The row of a function in a section marked `reuse` is a light row: its key, context,
    /// region digest and length, facts and the `stubbable` and `complete` flags are those of the function, and its names, notes, uses and guard
    /// are empty, because the section is stored as it was (`encode` never reads them). A table with no `sections` has complete rows only.
    summaries: []const Summary = &.{},
    /// How the stored form cuts the table into sections, one per module, in the order they are stored. Empty: `encode` cuts the summaries by the
    /// module their keys name.
    sections: []const OutSection = &.{},
};

/// One module's functions in a produced table.
pub const OutSection = struct {
    /// The module's name, which the stored table is searched by.
    name: []const u8,
    /// The module's signature (`sema_module_groups.signatureOf`): equal when the module's functions, dependency contexts and region digests are.
    signature: [32]u8,
    /// The instances (indices of `Table.summaries`) of the module's functions, in the order the section stores them.
    members: []const u32,
    /// The section of the table the check started from that holds exactly these functions' summaries, or null when the section is written afresh.
    reuse: ?u32 = null,
};

/// One touched record: its catalog name and transitive shape digest.
pub const Shape = struct { name: []const u8, digest: [32]u8 };

/// What encoding the table again will take, as the table it was decoded from showed: the payload's bytes and the strings its pool held.
/// Both are hints for the buffers (a rebuilt table is nearly the same size), never limits.
pub const SizeHint = struct { bytes: usize = 0, strings: usize = 0 };
