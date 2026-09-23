#!/usr/bin/env python3
"""Check that the bundled runtime's build-time identity follows the bytes it bundles.

``build_qbe_assets.zig`` embeds the native runtime sources in the compiler with
three digests, ``content_hash`` among them. ``mylang build`` publishes and reuses
the runtime tree and archive by that hash, so a hash that describes other bytes
makes it link a stale runtime without any error.

This driver runs the real ``build_qbe_assets.zig`` on small throwaway trees with
a probe program in place of the compiler. It builds them with ``zig build``
exactly the way the hazard was found: two trees that share one
``ZIG_LOCAL_CACHE_DIR``, then edits in place. After every build it checks that
the probe's embedded hash equals the digest of its embedded bytes, and that those
bytes are the tree's current sources. It also checks that sharing one Zig cache
between trees fails loudly instead of reusing the other tree's configuration.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIMEOUT = 600

BUILD_ZIG = """\
const std = @import("std");
pub fn build(b: *std.Build) void {
    const assets = @import("build_qbe_assets.zig").module(b, b.graph.host, .Debug, .{ .compile = 1 << 30, .run = 1 << 28 });
    const probe = b.addExecutable(.{ .name = "probe", .root_module = b.createModule(.{
        .root_source_file = b.path("probe.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }) });
    probe.root_module.addImport("qbe_build_assets", assets);
    b.installArtifact(probe);
}
"""

# Prints each digest, the digest recomputed from the embedded bytes with the
# encoding `content_hash` uses, and every bundled file.
PROBE_ZIG = """\
const std = @import("std");
const bundled = @import("qbe_build_assets");
pub fn main(init: std.process.Init) !void {
    var text: std.Io.Writer.Allocating = .init(init.gpa);
    defer text.deinit();
    for (bundled.files) |asset| try text.writer.print("{s}\\x00{d}\\x00{x}\\n", .{ asset.path, asset.bytes.len, std.hash.Wyhash.hash(0, asset.bytes) });
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(text.written(), &digest, .{});
    std.debug.print("content_hash {s}\\nrecomputed {s}\\n", .{ bundled.content_hash, &std.fmt.bytesToHex(digest, .lower) });
    std.debug.print("compiler_identity {s}\\ndriver_identity {s}\\n", .{ bundled.compiler_identity, bundled.driver_identity });
    for (bundled.files) |asset| std.debug.print("file {s} {x}\\n", .{ asset.path, asset.bytes });
}
"""

# A runtime closure (C unit, header, a Zig root and the unit it imports), a
# production source outside it, a native-driver source and a test-only file.
SOURCES = {
    'runtime.c': '#include "runtime.h"\nint myl_runtime(void) { return 1; }\n',
    'runtime.h': 'int myl_runtime(void);\n',
    'native_format.zig': 'pub const helper = @import("format_helper.zig");\n',
    'format_helper.zig': 'pub const width = 4;\n',
    'sema.zig': 'pub const checked = true;\n',
    'qbe_build.zig': 'pub const driver = 1;\n',
    'sema_test.zig': 'test { }\n',
}


def make_tree(path: Path) -> None:
    (path / 'src').mkdir(parents=True)
    shutil.copy(ROOT / 'build_qbe_assets.zig', path / 'build_qbe_assets.zig')
    (path / 'build.zig').write_text(BUILD_ZIG)
    (path / 'probe.zig').write_text(PROBE_ZIG)
    for name, text in SOURCES.items():
        (path / 'src' / name).write_text(text)


def zig_build(zig: str, tree: Path, cache: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.pop('ZIG_PROGRESS', None)
    env['ZIG_LOCAL_CACHE_DIR'] = str(cache)
    return subprocess.run([zig, 'build'], cwd=tree, env=env, capture_output=True,
                          text=True, timeout=TIMEOUT)


def build(zig: str, tree: Path, cache: Path) -> dict:
    """Build `tree`, run its probe, and check the identity it embeds."""
    result = zig_build(zig, tree, cache)
    if result.returncode != 0:
        raise AssertionError(f'zig build failed in {tree}:\n{result.stderr}')
    probe = subprocess.run([str(tree / 'zig-out' / 'bin' / 'probe')], capture_output=True,
                           text=True, timeout=TIMEOUT, check=True)
    fields, files = {}, {}
    for line in probe.stderr.splitlines():
        key, _, value = line.partition(' ')
        if key == 'file':
            name, _, data = value.partition(' ')
            files[name] = bytes.fromhex(data).decode()
        else:
            fields[key] = value
    expect(fields['content_hash'] == fields['recomputed'],
           f'{tree}: content_hash {fields["content_hash"]} is not the digest '
           f'{fields["recomputed"]} of the bytes it bundles')
    bundle = {name: (tree / 'src' / name).read_text() for name in
              ('runtime.c', 'runtime.h', 'native_format.zig', 'format_helper.zig')}
    expect(files == bundle, f'{tree}: bundled files are not the tree\'s runtime sources: '
           f'{sorted(files)} vs {sorted(bundle)}')
    return fields


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def edit(tree: Path, name: str, text: str) -> None:
    (tree / 'src' / name).write_text((tree / 'src' / name).read_text() + text)


def run(zig: str, scratch: Path) -> None:
    base, work = scratch / 'base', scratch / 'work'
    make_tree(base)
    make_tree(work)
    edit(work, 'runtime.c', '/* the work tree runtime */\n')
    shared = scratch / 'shared-cache'

    first = build(zig, base, shared)
    print(f'ok   base tree bundles its runtime ({first["content_hash"][:12]})')

    # The hazard: a second tree with the same build.zig and the same Zig cache
    # reused the first tree's cached configure phase, so it embedded the base
    # runtime's hash beside its own runtime bytes. It must now refuse.
    reused = zig_build(zig, work, shared)
    expect(reused.returncode != 0, 'a tree that shares another tree\'s Zig cache built '
           'with that tree\'s configuration instead of failing')
    expect(f'belongs to {base.resolve()}' in reused.stderr,
           f'the shared-cache failure does not name the other tree:\n{reused.stderr}')
    print('ok   a second tree sharing the Zig cache fails and names the first tree')

    private = build(zig, work, scratch / 'work-cache')
    expect(private['content_hash'] != first['content_hash'],
           'two trees with different runtime sources embed one content_hash')
    print('ok   the second tree, with its own cache, embeds its own runtime hash')

    # In-place edits in one tree, all through the same warm cache.
    edit(base, 'runtime.c', '/* edited */\n')
    edited = build(zig, base, shared)
    expect(edited['content_hash'] != first['content_hash'],
           'editing a runtime C unit left content_hash unchanged')
    edit(base, 'format_helper.zig', '// edited\n')
    imported = build(zig, base, shared)
    expect(imported['content_hash'] != edited['content_hash'],
           'editing a unit the Zig runtime root imports left content_hash unchanged')
    print('ok   in-place runtime edits move content_hash')

    edit(base, 'sema.zig', '// edited\n')
    frontend = build(zig, base, shared)
    expect(frontend['content_hash'] == imported['content_hash'],
           'a frontend edit moved the runtime content_hash')
    expect(frontend['compiler_identity'] != imported['compiler_identity'],
           'a frontend edit left compiler_identity unchanged')
    expect(frontend['driver_identity'] == imported['driver_identity'],
           'a frontend edit moved driver_identity')
    edit(base, 'qbe_build.zig', '// edited\n')
    driver = build(zig, base, shared)
    expect(driver['driver_identity'] != frontend['driver_identity'],
           'a native-driver edit left driver_identity unchanged')
    edit(base, 'sema_test.zig', '// edited\n')
    test_only = build(zig, base, shared)
    expect(test_only == driver, 'a test-only edit moved a build-time identity')
    print('ok   compiler and driver identities follow their inputs; test-only edits move none')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--zig', default='zig', help='the pinned Zig executable')
    parser.add_argument('--keep', action='store_true', help='keep the scratch trees')
    args = parser.parse_args()
    scratch = Path(tempfile.mkdtemp(prefix='runtime-identity-'))
    try:
        run(args.zig, scratch)
    except AssertionError as failure:
        print(f'FAIL {failure}', file=sys.stderr)
        print(f'scratch trees kept at {scratch}', file=sys.stderr)
        return 1
    if not args.keep:
        shutil.rmtree(scratch, ignore_errors=True)
    print('runtime identity cache: all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
