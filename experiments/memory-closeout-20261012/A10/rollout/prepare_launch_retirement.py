#!/usr/bin/env python3
"""Prepare, without applying, the checked-default installed-component boundary."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--source-revision', required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[4]
scratch = root / '.tmp/memory-closeout/A10' / ('launch-retirement-' + args.source_revision[:9])
before = {}
after = {}


def load(path):
    before[path] = subprocess.check_output(['git', 'show', f'{args.source_revision}:{path}'], cwd=root, text=True)
    return before[path]


def replace(source, old, new, count=1):
    assert source.count(old) == count, (old, source.count(old), count)
    return source.replace(old, new)


p = 'src/component_launch.zig'
s = load(p)
s = replace(s, '    const parsed = std.json.parseFromSlice(Manifest, a, bytes,',
            '    try checkedOwnership(a, bytes);\n    const parsed = std.json.parseFromSlice(Manifest, a, bytes,')
s += r'''
/// Metadata is an admission requirement; the qualified recipe and binary digest
/// provide artifact provenance. A marker alone is not an ABI qualification.
fn checkedOwnership(a: std.mem.Allocator, bytes: []const u8) Error!void {
    const Selection = struct { memory_mode: []const u8, ownership_selection: []const u8, guest_abi: []const u8 };
    const parsed = std.json.parseFromSlice(Selection, a, bytes, .{ .ignore_unknown_fields = true }) catch |err| return mapFailure(err, error.ComponentManifest);
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.memory_mode, "zero-rc-v1") or
        !std.mem.eql(u8, parsed.value.ownership_selection, "checked-default-v1") or
        !std.mem.eql(u8, parsed.value.guest_abi, "mylang-checked-owned-v1")) return error.ComponentManifest;
}

// spec-case: SELFHOST-COMPONENT-1
test "component manifest refuses historical and opt-in ownership selections before artifact admission" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    const contents = "synthetic deployment boundary fixture\n";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
    for ([_][]const u8{ "test-index", "cache-plan" }) |component| {
        try temporary.dir.writeFile(io, .{ .sub_path = component, .data = contents });
        const filename = try std.fmt.allocPrint(a, "{s}.json", .{component});
        defer a.free(filename);
        const version: u32 = if (std.mem.eql(u8, component, "cache-plan")) 2 else 1;
        const cases = [_][]const u8{
            "",
            ",\"memory_mode\":\"zero-rc-v1\"",
            ",\"ownership_selection\":\"checked-default-v1\"",
            ",\"memory_mode\":\"legacy-rc\",\"ownership_selection\":\"checked-default-v1\"",
            ",\"memory_mode\":\"zero-rc-v1\",\"ownership_selection\":\"explicit-zero-rc-v1\"",
            ",\"memory_mode\":false,\"ownership_selection\":\"checked-default-v1\"",
            ",\"memory_mode\":\"zero-rc-v1\",\"ownership_selection\":null",
            ",\"memory_mode\":\"zero-rc-v1\",\"ownership_selection\":\"checked-default-v1\"",
        };
        const abis = [_][]const u8{ "", ",\"guest_abi\":\"legacy-rc\"", ",\"guest_abi\":\"mylang-checked-owned-v2\"", ",\"guest_abi\":false", ",\"guest_abi\":\"mylang-checked-owned-v1\"" };
        for (cases, 0..) |selection, index| for (abis, 0..) |abi, abi_index| {
            const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"{s}\",\"protocol\":{d},\"schema\":{d},\"artifact\":\"{s}\",\"sha256\":\"{s}\"{s}{s}}}", .{ component, version, version, component, std.fmt.bytesToHex(digest, .lower), selection, abi });
            defer a.free(manifest);
            try temporary.dir.writeFile(io, .{ .sub_path = filename, .data = manifest });
            if (index + 1 < cases.len or abi_index + 1 < abis.len) {
                try std.testing.expectError(error.ComponentManifest, artifact(a, io, directory, component));
                try std.testing.expectError(error.ComponentManifest, artifactSnapshot(a, io, directory, component));
            } else {
                const snapshot = try artifactSnapshot(a, io, directory, component);
                defer snapshot.deinit(a);
                try std.testing.expectEqualStrings(contents, snapshot.contents);
                try std.testing.expectEqualSlices(u8, &digest, &snapshot.verified.digest);
            }
        };
    }
}
'''
after[p] = s

for p in ['src/component_protocol_test.zig', 'src/cache_plan_protocol_test.zig']:
    s = load(p)
    s = replace(s, r'\"sha256\":\"{s}\"}}',
                r'\"sha256\":\"{s}\",\"memory_mode\":\"zero-rc-v1\",\"ownership_selection\":\"checked-default-v1\",\"guest_abi\":\"mylang-checked-owned-v1\"}}')
    after[p] = s

p = 'src/cache_plan_protocol_test.zig'
after[p] += r'''
// spec-case: SELFHOST-CACHE-PLAN-2
test "planner refuses a historical deployment selection even after binding the same binary" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    defer a.free(directory);
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("MYLANG_COMPONENT_DIR", directory);
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 0\n");
    var bound = try adapter.bind(a, io, &environ);
    defer bound.deinit(a);
    const valid = try temporary.dir.readFileAlloc(io, "cache-plan.json", a, .limited(65536));
    defer a.free(valid);
    const edits = [_][2][]const u8{
        .{ "zero-rc-v1", "legacy-rc" },
        .{ "checked-default-v1", "explicit-zero-rc-v1" },
        .{ "mylang-checked-owned-v1", "mylang-checked-owned-v2" },
    };
    for (edits) |edit| {
        const stale = try std.mem.replaceOwned(u8, a, valid, edit[0], edit[1]);
        defer a.free(stale);
        try temporary.dir.writeFile(io, .{ .sub_path = "cache-plan.json", .data = stale });
        try std.testing.expectError(error.ComponentManifest, bound.validate(a));
        try std.testing.expectError(error.ComponentManifest, adapter.bind(a, io, &environ));
        try temporary.dir.writeFile(io, .{ .sub_path = "cache-plan.json", .data = valid });
        try bound.validate(a);
    }
}
'''

patch = ''
for path, value in after.items():
    target = scratch / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value)
    patch += f'diff --git a/{path} b/{path}\n'
    patch += ''.join(difflib.unified_diff(before[path].splitlines(True), value.splitlines(True), fromfile='a/' + path, tofile='b/' + path))
args.output_dir.mkdir(parents=True, exist_ok=True)
(args.output_dir / 'C3-component-launch.patch').write_text(patch)
(args.output_dir / 'C3-component-launch.json').write_text(json.dumps({
    'status': 'UNAPPLIED; requires qualified checked-default owned package and fixture migrations',
    'source_revision': args.source_revision,
    'patch_sha256': hashlib.sha256(patch.encode()).hexdigest(),
    'files': {path: {'base_sha256': hashlib.sha256(before[path].encode()).hexdigest(),
                     'draft_sha256': hashlib.sha256(value.encode()).hexdigest()} for path, value in after.items()},
    'qualification': 'Synthetic deployment parser/admission tests do not establish guest binary ABI correctness.',
}, indent=2) + '\n')
print(scratch)
