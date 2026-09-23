//! Which slices the native lowering describes instead of building
//! (`DICT-RANGE-KEY-1`). `tests/lang/dictionary_range_keys.my` checks that the
//! answers are the built slices' answers; these tests pin which lowering
//! produced them, since a guest program cannot tell.
const std = @import("std");
const language = @import("compiler.zig");

const Unit = struct { name: []const u8, il: []const u8 };
const Manifest = struct { functions: []const Unit };

/// The IL of function `name` in `source`, owned by the caller.
fn lowered(a: std.mem.Allocator, source: []const u8, name: []const u8) ![]u8 {
    var program = try language.Compilation.init(a, "keys.my", source);
    defer program.deinit();
    const manifest = try program.emitQbe(a);
    defer a.free(manifest);
    var parsed = try std.json.parseFromSlice(Manifest, a, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer parsed.deinit();
    for (parsed.value.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return a.dupe(u8, unit.il);
    return error.TestUnexpectedResult;
}

fn count(il: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, il, needle);
}

const counting =
    \\def frequencies(seq: str, k: int) -> dict[str, int]:
    \\    counts: dict[str, int] = {}
    \\    for i in range(len(seq) - k + 1):
    \\        key = seq[i:i + k]
    \\        counts[key] = counts.get(key, 0) + 1
    \\    return counts
    \\
    \\
    \\def forms(s: str, d: mut dict[str, int]) -> int:
    \\    total = d[s[1:3]] + d.get(s[0:2], 5)
    \\    if s[2:4] in d:
    \\        total += 1
    \\    d[s[1:4]] += 2
    \\    d[s[2:5]] = 7
    \\    return total
    \\
    \\
    \\def kept(s: str, d: mut dict[str, int]) -> str:
    \\    key = s[0:2]
    \\    d[key] = 1
    \\    return key
    \\
    \\
    \\def main() -> int:
    \\    d = frequencies("ACGTACGT", 2)
    \\    return forms("abcdef", mut d) + len(kept("xyz", mut d))
;

// spec: DICT-RANGE-KEY-1
test "DICT-RANGE-KEY-1 a slice read only as a dictionary key is described, not built" {
    const a = std.testing.allocator;
    const frequencies = try lowered(a, counting, "frequencies");
    defer a.free(frequencies);
    try std.testing.expectEqual(@as(usize, 0), count(frequencies, "$myl_native_text_slice("));
    try std.testing.expectEqual(@as(usize, 1), count(frequencies, "$myl_native_text_range("));
    try std.testing.expectEqual(@as(usize, 1), count(frequencies, "$myl_native_dictionary_read_range("));
    try std.testing.expectEqual(@as(usize, 1), count(frequencies, "$myl_native_dictionary_write_range("));
    try std.testing.expectEqual(@as(usize, 0), count(frequencies, "$myl_native_dictionary_write("));
}

// spec-case: DICT-RANGE-KEY-1
test "every key spelling of a slice is described" {
    const a = std.testing.allocator;
    const forms = try lowered(a, counting, "forms");
    defer a.free(forms);
    try std.testing.expectEqual(@as(usize, 0), count(forms, "$myl_native_text_slice("));
    try std.testing.expectEqual(@as(usize, 5), count(forms, "$myl_native_text_range("));
    try std.testing.expectEqual(@as(usize, 3), count(forms, "$myl_native_dictionary_read_range("));
    try std.testing.expectEqual(@as(usize, 1), count(forms, "$myl_native_dictionary_contains_range("));
    try std.testing.expectEqual(@as(usize, 2), count(forms, "$myl_native_dictionary_write_range("));
}

// spec-case: DICT-RANGE-KEY-1
test "a slice with any other reader is still built" {
    const a = std.testing.allocator;
    const kept = try lowered(a, counting, "kept");
    defer a.free(kept);
    try std.testing.expectEqual(@as(usize, 1), count(kept, "$myl_native_text_slice("));
    try std.testing.expectEqual(@as(usize, 0), count(kept, "$myl_native_text_range("));
    try std.testing.expectEqual(@as(usize, 1), count(kept, "$myl_native_dictionary_write("));
}

// spec-case: DICT-RANGE-KEY-1
test "a slice key is described beside indices that count from the end" {
    // `get_index` carries an `Access` (PY-ARRAY-NEGATIVE-1); a dictionary read
    // through a slice key must still be recognized next to list and array
    // reads that normalize a negative index.
    const a = std.testing.allocator;
    const source =
        \\def mixed(s: str, names: list[str], marks: [3]int, d: mut dict[str, int]) -> int:
        \\    d[s[2:4]] += marks[-1]
        \\    return d[s[0:2]] + d[names[-2]] + marks[-3]
        \\
        \\
        \\def main() -> int:
        \\    d: dict[str, int] = {"ta": 1, "ga": 2, "ca": 3}
        \\    return mixed("gattaca", ["ta", "ca"], [4, 5, 6], mut d)
    ;
    const mixed = try lowered(a, source, "mixed");
    defer a.free(mixed);
    try std.testing.expectEqual(@as(usize, 0), count(mixed, "$myl_native_text_slice("));
    try std.testing.expectEqual(@as(usize, 2), count(mixed, "$myl_native_text_range("));
    try std.testing.expectEqual(@as(usize, 1), count(mixed, "$myl_native_dictionary_write_range("));
}

/// The text of `il` from `from` up to the first `until` after it.
fn between(il: []const u8, from: []const u8, until: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, il, from) orelse return "";
    const stop = std.mem.indexOfPos(u8, il, start, until) orelse il.len;
    return il[start..stop];
}

/// The lowered instruction that contains `needle`, from its `@i` label through
/// its `@put_new` block: the path a write of a present key takes.
fn fastPath(il: []const u8, needle: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, il, needle) orelse return "";
    const start = std.mem.lastIndexOf(u8, il[0..at], "\n@i") orelse 0;
    const stop = std.mem.indexOfPos(u8, il, at, "\n@put_new") orelse il.len;
    return il[start..stop];
}

// spec: DICT-OVERWRITE-1
test "DICT-OVERWRITE-1 a dictionary write links its roots only on the new-key path" {
    const a = std.testing.allocator;
    const source =
        \\def tally(values: list[int]) -> dict[int, int]:
        \\    counts: dict[int, int] = {}
        \\    for value in values:
        \\        counts[value] = counts.get(value, 0) + 1
        \\    return counts
        \\
        \\
        \\def main() -> int:
        \\    return len(tally([1, 2, 1]))
    ;
    const tally = try lowered(a, source, "tally");
    defer a.free(tally);
    try std.testing.expectEqual(@as(usize, 1), count(tally, "$myl_native_dictionary_overwrite("));
    try std.testing.expectEqual(@as(usize, 1), count(tally, "$myl_native_dictionary_write("));
    const fast = fastPath(tally, "$myl_native_dictionary_overwrite(");
    try std.testing.expect(fast.len != 0);
    try std.testing.expectEqual(@as(usize, 0), count(fast, "%root"));
    const slow = between(tally, "\n@put_new", "\n@put_done");
    try std.testing.expect(count(slow, "=l add %root") != 0);
    try std.testing.expectEqual(@as(usize, 1), count(slow, "$myl_native_dictionary_write("));
    const frequencies = try lowered(a, counting, "frequencies");
    defer a.free(frequencies);
    const described = fastPath(frequencies, "$myl_native_dictionary_overwrite_range(");
    try std.testing.expect(described.len != 0);
    try std.testing.expectEqual(@as(usize, 0), count(described, "%root"));
}

// spec-case: DICT-RANGE-KEY-1
test "a program that opens an arena keeps building its slices" {
    const a = std.testing.allocator;
    const frequencies = try lowered(a, counting ++
        \\
        \\
        \\def scoped() -> int:
        \\    total = 0
        \\    with arena():
        \\        total = len(frequencies("ACGT", 1))
        \\    return total
    , "frequencies");
    defer a.free(frequencies);
    try std.testing.expectEqual(@as(usize, 1), count(frequencies, "$myl_native_text_slice("));
    try std.testing.expectEqual(@as(usize, 0), count(frequencies, "_range("));
}
