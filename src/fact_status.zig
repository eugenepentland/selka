//! How much of a declaration's contract a fact surface actually analyzed.
//!
//! `src/reference.zig` publishes this vocabulary as `analysis: checked |
//! template | declaration-only | declared` with `library.status: checked |
//! declaration-only | unavailable`, and `docs/reference.md` §Fact status defines
//! it. That engine belongs to the executable's root module, so it cannot import
//! this one and spells the names itself; this module is the single definition the
//! compiler's own surfaces share. `src/reference_test.zig` pins the reference's
//! spellings (`template`, `declaration-only`) and `FACT-STATUS-1` in
//! `interfaces_test.zig` pins these, so the two copies cannot drift silently.
//!
//! The rule the vocabulary enforces is the one F1 asks for: a conservative
//! internal mask is never published as an inferred fact. A surface that has no
//! checked instantiation publishes the status that says so and a `null` (JSON)
//! or `unavailable` (text) inferred set, while a declared ceiling stays visible
//! because the source wrote it.

/// The analysis behind one published declaration's facts.
pub const Status = enum {
    /// Bodies were checked and this declaration has a checked summary, so its
    /// inferred effects, mutation footprint and return origin are facts.
    checked,
    /// Bodies were checked, but this generic declaration has no checked
    /// instantiation here, so the checker's conservative mask is a bound only.
    template,
    /// Declarations and exported signatures were checked; bodies were not, so no
    /// inferred summary exists.
    declaration_only,
    /// A type, resource, constraint or field declaration: declared in source,
    /// with no body to analyze.
    declared,
    /// Only top-level lexical candidates were recovered because body syntax
    /// failed; no resolved relationship was published.
    lexical_only,
};

/// The wire spelling of one status, shared by the text and JSON surfaces.
pub fn name(status: Status) []const u8 {
    return switch (status) {
        .checked => "checked",
        .template => "template",
        .declaration_only => "declaration-only",
        .declared => "declared",
        .lexical_only => "lexical-only",
    };
}
