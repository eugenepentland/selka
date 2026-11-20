//! The refused uses of an `extern type` handle (D-FFI-4, `docs/c-ffi.md#opaque-handles`).
//!
//! A handle is C's pointer carried unchanged: the front end keeps it a nominal type with no fields, Core a `u64`.
//! Its operations are `T()` (the null handle), `==` and `!=`, copying, storing and passing it to C. Every other use
//! is refused here with `E_EXTERN_TYPE` and a message that names the use.
const std = @import("std");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The diagnostic code of every refused use of a handle.
pub const code = "E_EXTERN_TYPE";

/// The kinds of refused use, each with its own message.
pub const Use = enum {
    operator,
    ordering,
    conversion,
    text,
    field,
    match,
    task,

    /// What the refusal says.
    pub fn message(self: Use) []const u8 {
        return switch (self) {
            .operator => "a handle has no arithmetic or bitwise operations; it is C's pointer, carried unchanged",
            .ordering => "handles are not ordered; only `==` and `!=` compare them",
            .conversion => "a handle does not convert to or from a number; it comes from C, and `T()` is the null handle",
            .text => "a handle cannot be printed, formatted or turned into text; print what C reports about it instead",
            .field => "a handle has no fields; C reads what it points to",
            .match => "a handle cannot be matched; compare it with `T()` to test for the null handle",
            .task => "a handle cannot cross to a parallel task: the C library decides which threads may use it",
        };
    }
};

/// Whether `ty` is an `extern type` handle.
pub fn is(ty: typed.Type, records: []const typed.Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].shape.builtin == .foreign_handle;
}

/// Whether `ty` is a handle or holds one in a field, case payload, element, key or value.
pub fn contains(ty: typed.Type, records: []const typed.Record) bool {
    var work: usize = 4096;
    return reaches(ty, records, 0, &work);
}

fn reaches(ty: typed.Type, records: []const typed.Record, depth: usize, work: *usize) bool {
    if (work.* == 0 or depth > 64) return false;
    work.* -= 1;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.shape.builtin == .foreign_handle) return true;
    if (record.contract.callback != null) return false;
    if (record.shape.buffer) |element| if (reaches(element, records, depth + 1, work)) return true;
    if (record.collection.key) |key| if (reaches(key, records, depth + 1, work)) return true;
    if (record.shape.array) |array| if (reaches(array.element, records, depth + 1, work)) return true;
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (reaches(payload, records, depth + 1, work)) return true;
    }
    for (record.fields) |field| if (reaches(field.ty, records, depth + 1, work)) return true;
    return false;
}

/// Refuse a use of a handle at `span`.
pub fn refuse(sink: *diagnostic.Sink, span: source.Span, use: Use) diagnostic.Error {
    return sink.fail(code, span, use.message());
}
