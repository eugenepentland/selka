//! The text and span forms of the runtime helpers a lowered body can call (F19).
//!
//! A function taking a plain `str`, `bytes` or list parameter is built over a borrowed view, and the runtime
//! helper it calls is then the helper's span form (`myl_core_span_starts` for `myl_core_str_starts`). The
//! allocation contract judges the body the build emits, so a span form must be classified exactly as its text
//! form is. This leaf file is the one table both sides read: the builder picks the symbol from it and
//! `cost.runtimeAllocationFree` derives the span form's classification from the text form's.

/// A helper whose span form the builder selects by the shape of the call's arguments: it names the span form
/// when each position in `texts` is text, and, for a `views_only` helper, only when one of them is a view.
pub const Redirect = struct { text: []const u8, span: []const u8, texts: u64, views_only: bool = false };

/// A helper and the span form a lowering or fusion pass names directly, without the call-shape test.
pub const Pair = struct { text: []const u8, span: []const u8 };

/// A runtime text helper whose span form takes each text argument as a borrowed `(data, length)`
/// (C9): an owned argument lends its octets for free (`emit_llvm`'s span argument), a view argument
/// needs no copy. `texts` is the mask of parameter positions that are text; every other position
/// keeps its type. A call names the span form only when each of its text positions is text.
pub const redirects = [_]Redirect{
    .{ .text = "myl_core_str_starts", .span = "myl_core_span_starts", .texts = 0b11 },
    .{ .text = "myl_core_str_ends", .span = "myl_core_span_ends", .texts = 0b11 },
    .{ .text = "myl_core_str_contains", .span = "myl_core_span_contains", .texts = 0b11 },
    // An owned text keeps the block form, which the encode fusion matches (`fuse_encode`); a view takes the span.
    .{ .text = "myl_core_text_encode", .span = "myl_core_span_encode", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_str_split_whitespace", .span = "myl_core_span_str_split_whitespace", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_str_find_byte", .span = "myl_core_span_find_byte", .texts = 0b11 },
    .{ .text = "myl_core_octets_compare", .span = "myl_core_span_octets_compare", .texts = 0b11 },
    .{ .text = "myl_core_from_hex_valid", .span = "myl_core_span_from_hex_valid", .texts = 0b1 },
    .{ .text = "myl_core_from_hex", .span = "myl_core_span_from_hex", .texts = 0b1 },
    .{ .text = "myl_core_text_repr", .span = "myl_core_span_text_repr", .texts = 0b1 },
    // The three predicates `is_digit`, `is_alpha` and `is_space` (F20): the property flag is the second parameter.
    .{ .text = "myl_core_text_every", .span = "myl_core_span_text_every", .texts = 0b1 },
    // `ord` reads the first scalar of its single-scalar text (F20).
    .{ .text = "myl_core_text_ord", .span = "myl_core_span_text_ord", .texts = 0b1 },
    .{ .text = "myl_core_text_search_bytes", .span = "myl_core_span_text_search_bytes", .texts = 0b11 },
    .{ .text = "myl_core_file_access", .span = "myl_core_span_file_access", .texts = 0b1100 },
    .{ .text = "myl_core_file_method", .span = "myl_core_span_file_method", .texts = 0b1000 },
    .{ .text = "myl_core_durable_access", .span = "myl_core_span_durable_access", .texts = 0b1100 },
    .{ .text = "myl_core_process_run", .span = "myl_core_span_process_run", .texts = 0b10 },
    .{ .text = "myl_core_process_control", .span = "myl_core_span_process_control", .texts = 0b10 },
    .{ .text = "myl_core_process_scripted", .span = "myl_core_span_process_scripted", .texts = 0b1 },
    // `env.get(name)` with a computed name reads the `str` in place; a literal name is bytes, which keep the block form.
    .{ .text = "myl_core_environment_text", .span = "myl_core_span_environment_text", .texts = 0b10 },
    .{ .text = "myl_core_input_memory", .span = "myl_core_span_input_memory", .texts = 0b1 },
    .{ .text = "myl_core_stream_write", .span = "myl_core_span_stream_write", .texts = 0b10 },
    .{ .text = "myl_core_stream_write_bytes", .span = "myl_core_span_stream_write", .texts = 0b10, .views_only = true },
    .{ .text = "myl_core_bytes_to_list", .span = "myl_core_span_bytes_to_list", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_parse_int_range", .span = "myl_core_span_parse_int_range", .texts = 0b1 },
    .{ .text = "myl_core_parse_float_range", .span = "myl_core_span_parse_float_range", .texts = 0b1 },
    .{ .text = "myl_core_parse_f32_range", .span = "myl_core_span_parse_f32_range", .texts = 0b1 },
    // Bytes helpers (C9 bytes): a bytes view takes the span form; an owned argument keeps the block helper
    // (`views_only`, and `spanRedirect` keeps every all-owned call on its block form).
    .{ .text = "myl_core_bytes_hex", .span = "myl_core_span_bytes_hex", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_bytes_blake3", .span = "myl_core_span_bytes_blake3", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_bytes_sha256", .span = "myl_core_span_bytes_sha256", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_bytes_search", .span = "myl_core_span_bytes_search", .texts = 0b11, .views_only = true },
    .{ .text = "myl_core_bytes_trim", .span = "myl_core_span_bytes_trim", .texts = 0b11, .views_only = true },
    .{ .text = "myl_core_bytes_find", .span = "myl_core_span_bytes_find", .texts = 0b11, .views_only = true },
    .{ .text = "myl_core_bytes_find_any", .span = "myl_core_span_bytes_find_any", .texts = 0b11, .views_only = true },
    .{ .text = "myl_core_bytes_contains_value", .span = "myl_core_span_bytes_contains_value", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_bytes_concat", .span = "myl_core_span_bytes_concat", .texts = 0b11, .views_only = true },
    .{ .text = "myl_core_bytes_utf8_count", .span = "myl_core_span_utf8_count", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_bytes_utf8_count_range", .span = "myl_core_span_bytes_utf8_count_range", .texts = 0b1, .views_only = true },
    .{ .text = "myl_core_bytes_decode_text", .span = "myl_core_span_decode_text", .texts = 0b1, .views_only = true },
};

/// Span forms that the builder and the fusion passes name in place of their text form, outside `redirects`.
pub const direct = [_]Pair{
    .{ .text = "myl_core_str_eq", .span = "myl_core_span_eq" },
    .{ .text = "myl_core_str_chars", .span = "myl_core_span_chars" },
    .{ .text = "myl_core_bytes_valid_list", .span = "myl_core_span_bytes_valid_list" },
    .{ .text = "myl_core_bytes_index_offset", .span = "myl_core_span_bytes_index_offset" },
    .{ .text = "myl_core_buffer_range_valid", .span = "myl_core_span_buffer_range_valid" },
    .{ .text = "myl_core_split_ws_start", .span = "myl_core_span_split_ws_start" },
    .{ .text = "myl_core_split_ws_end", .span = "myl_core_span_split_ws_end" },
    .{ .text = "myl_core_text_trim_view", .span = "myl_core_span_text_trim_view" },
};

/// Span helpers that have no text form to compare with: they allocate, write, serve emitted code or the split
/// fusions only, or (`myl_core_span_bytes_trim_view`, `myl_core_span_bytes_slice_view`) are audited by name in
/// `cost.runtimeAllocationFree`. A
/// test scans the runtime for every `myl_core_span_` name and requires it here or in a table above, so a new
/// span helper gets a classification before a promise over a body that calls it can be judged.
pub const other = [_][]const u8{
    "myl_core_span_buffer_from_list", "myl_core_span_bytes_from_list", "myl_core_span_bytes_trim_view",
    "myl_core_span_bytes_slice_view", "myl_core_span_hash",            "myl_core_span_parse_int",
    "myl_core_span_resource_write",   "myl_core_span_split_count",     "myl_core_span_split_end",
    "myl_core_span_split_fill",       "myl_core_span_split_next",      "myl_core_span_split_offsets",
    "myl_core_span_split_start",      "myl_core_span_str_append_char", "myl_core_span_str_code",
    "myl_core_span_str_width",
};

/// The text form of `symbol` when `symbol` is a span form named by `redirects` or `direct`, else null.
pub fn textForm(symbol: []const u8) ?[]const u8 {
    for (redirects) |form| if (eql(form.span, symbol)) return form.text;
    for (direct) |form| if (eql(form.span, symbol)) return form.text;
    return null;
}

fn eql(a: []const u8, b: []const u8) bool {
    return @import("std").mem.eql(u8, a, b);
}
