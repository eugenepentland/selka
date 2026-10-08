#!/usr/bin/env python3
"""Write the working tree's CE-A files as of step K (1..4) from the final versions in .tmp/final."""
import re, sys, pathlib
k = int(sys.argv[1])
W = pathlib.Path("/home/epentland/ai/canopy/mylang-worktrees/claude-ce-records")
F = W / ".tmp/final"
def read(p): return (F / p).read_text()
def write(p, s): (W / p).write_text(s)

# Step switches.
s = read("src/core/emit_homes.zig")
on = lambda n: "true" if n <= k else "false"
s = re.sub(r"^pub const steps: .*$", f"pub const steps: struct {{ homes: bool, views: bool, write_backs: bool, in_out: bool }} = .{{ .homes = {on(1)}, .views = {on(2)}, .write_backs = {on(3)}, .in_out = {on(4)} }};", s, flags=re.M)
write("src/core/emit_homes.zig", s)

# Tests: drop the tests of later steps, and assertions that need a later step.
t = read("src/core/ce_records_test.zig")
def drop_test(text, name):
    start = text.index(f'test "{name}')
    start = text.rindex("\n// spec", 0, start) + 1
    end = text.index("\n}\n", start) + 3
    return text[:start] + text[end:].lstrip("\n")
def drop_between(text, first, last):
    i = text.index(first); j = text.index(last, i) + len(last)
    return text[:i] + text[j:]
if k < 2:
    t = drop_test(t, "a record field over four words is read where it lies")
if k < 3:
    t = drop_test(t, "a record whose old value has no later reader")
if k < 4:
    t = drop_test(t, "a mut record crosses a call in-out")
    t = drop_test(t, "a call's result record read whole")
    t = drop_between(t, "/// `bump(w: mut Wide, k) -> {i64, Wide}`", "    return m;\n}\n\n")
    t = drop_between(t, "    const walk = functionText(llvm, \"@\\\"my.walk\\\"\");", "copies(functionText(release, \"@\\\"my.walk\\\"\")));\n")
    t = t.replace("const Hand = support.Hand;\n", "").replace('const ir = @import("ir.zig");\n', "")
if k < 4:
    old = """    // The read-only parameter is copied once, into the caller's destination, and both stores go there.
    const bumped = functionText(llvm, "@\\"my.bumped\\"");
    try std.testing.expectEqual(@as(usize, 1), copies(bumped));
    try std.testing.expect(contains(bumped, "@llvm.memcpy.p0.p0.i64(ptr %v"));
    try std.testing.expect(contains(bumped, "getelementptr inbounds i8, ptr %ret, i64 0\\n"));"""
    new = """    // The read-only parameter is copied once and both stores write that copy where it is; the
    // return copies it into the caller's destination.
    const bumped = functionText(llvm, "@\\"my.bumped\\"");
    try std.testing.expectEqual(@as(usize, 2), copies(bumped));"""
    if k == 3:
        assert old in t, "bumped"
    t = t.replace(old, new)
write("src/core/ce_records_test.zig", t)

# Existing tests: the widen copy count drops to one when the result is built in `%ret` (step 4).
v = read("src/core/value_emit_test.zig")
if k < 4:
    v = v.replace('''    // The first write copies the parameter (its caller's memory is read-only) into the caller's
    // destination; the second writes that copy where it is, and the return copies nothing.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, widen, "@llvm.memcpy"));''', '''    // The first write copies the parameter (its caller's memory is read-only); the second writes
    // that copy where it is, and the return copies it into the caller's destination.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, widen, "@llvm.memcpy"));''')
write("src/core/value_emit_test.zig", v)
write("src/core/emit_llvm_test.zig", read("src/core/emit_llvm_test.zig"))
write("src/core/root_test.zig", read("src/core/root_test.zig"))
write("src/core/emit_llvm.zig", read("src/core/emit_llvm.zig"))
write("test/core/ce_records.my", read("test/core/ce_records.my"))

# SPEC: the bullets of the steps landed so far.
sp = read("SPEC.md")
keep = {1: [1, 5], 2: [1, 2, 5], 3: [1, 2, 3, 5], 4: [1, 2, 3, 4, 5]}[k]
for n in (2, 3, 4):
    if n not in keep:
        i = sp.index(f"- [NEW-CORE-CE-RECORDS-{n}] "); j = sp.index("\n", i) + 1
        sp = sp[:i] + sp[j:]
if k < 2:
    sp = sp.replace(", a field of such a construction or a field of a construction that lives in memory (NEW-CORE-CE-RECORDS-2) is never built", " or a field of such a construction is never built")
write("SPEC.md", sp)
