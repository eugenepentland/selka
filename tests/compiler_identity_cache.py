#!/usr/bin/env python3
"""Check that the compiler's build-time identity follows the sources it covers.

``build_identity.zig`` embeds ``compiler_identity`` in the compiler: a digest of
every production source under ``src``, the Zig toolchain and the optimize mode.
The front end keys its persistent caches by it, so a digest that describes other
bytes would let a rebuilt compiler replay an older compiler's answers.

This driver runs the real ``build_identity.zig`` on small throwaway trees with a
probe program in place of the compiler. It builds them with ``zig build`` exactly
the way the hazard was found: two trees that share one ``ZIG_LOCAL_CACHE_DIR``,
then edits in place. After every build it checks the identity the probe embeds
and the source list it covers, and that sharing one Zig cache between trees fails
loudly instead of reusing the other tree's configuration.
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
    const identity = @import("build_identity.zig").module(b, b.graph.host, .Debug, .{ .compile = 1 << 30, .run = 1 << 28 });
    const probe = b.addExecutable(.{ .name = "probe", .root_module = b.createModule(.{
        .root_source_file = b.path("probe.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }) });
    probe.root_module.addImport("build_identity", identity);
    b.installArtifact(probe);
}
"""

# Prints the identity and every source it covers.
PROBE_ZIG = """\
const std = @import("std");
const built = @import("build_identity");
pub fn main(init: std.process.Init) !void {
    _ = init;
    std.debug.print("compiler_identity {s}\\n", .{built.compiler_identity});
    for (built.identity_inputs) |path| std.debug.print("input {s}\\n", .{path});
}
"""

# Production sources (a front-end file, a core file and a runtime C unit) and
# two test-only files.
SOURCES = {
    'sema.zig': 'pub const checked = true;\n',
    'core/emit.zig': 'pub const units = 1;\n',
    'core/runtime/rt.c': 'int myl_rt(void) { return 1; }\n',
    'sema_test.zig': 'test { }\n',
    'test_support.zig': 'pub const fixture = 1;\n',
}
PRODUCTION = sorted(['sema.zig', 'core/emit.zig', 'core/runtime/rt.c'])


def make_tree(path: Path) -> None:
    (path / 'src').mkdir(parents=True)
    shutil.copy(ROOT / 'build_identity.zig', path / 'build_identity.zig')
    (path / 'build.zig').write_text(BUILD_ZIG)
    (path / 'probe.zig').write_text(PROBE_ZIG)
    for name, text in SOURCES.items():
        (path / 'src' / name).parent.mkdir(parents=True, exist_ok=True)
        (path / 'src' / name).write_text(text)


def zig_build(zig: str, tree: Path, cache: Path) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.pop('ZIG_PROGRESS', None)
    env['ZIG_LOCAL_CACHE_DIR'] = str(cache)
    return subprocess.run([zig, 'build'], cwd=tree, env=env, capture_output=True,
                          text=True, timeout=TIMEOUT)


def build(zig: str, tree: Path, cache: Path) -> str:
    """Build `tree`, run its probe, check the sources it covers, return its identity."""
    result = zig_build(zig, tree, cache)
    if result.returncode != 0:
        raise AssertionError(f'zig build failed in {tree}:\n{result.stderr}')
    probe = subprocess.run([str(tree / 'zig-out' / 'bin' / 'probe')], capture_output=True,
                           text=True, timeout=TIMEOUT, check=True)
    identity, inputs = '', []
    for line in probe.stderr.splitlines():
        key, _, value = line.partition(' ')
        if key == 'input':
            inputs.append(value)
        elif key == 'compiler_identity':
            identity = value
    expect(len(identity) == 64, f'{tree}: compiler_identity is not a SHA-256: {identity!r}')
    expect(inputs == PRODUCTION, f'{tree}: the identity covers {inputs}, not the production '
           f'sources {PRODUCTION}')
    return identity


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def edit(tree: Path, name: str, text: str) -> None:
    (tree / 'src' / name).write_text((tree / 'src' / name).read_text() + text)


def run(zig: str, scratch: Path) -> None:
    base, work = scratch / 'base', scratch / 'work'
    make_tree(base)
    make_tree(work)
    edit(work, 'sema.zig', '// the work tree\n')
    shared = scratch / 'shared-cache'

    first = build(zig, base, shared)
    print(f'ok   base tree embeds its identity ({first[:12]})')

    # The hazard: a second tree with the same build.zig and the same Zig cache
    # reused the first tree's cached configure phase, so it embedded the base
    # tree's digest beside its own sources. It must now refuse.
    reused = zig_build(zig, work, shared)
    expect(reused.returncode != 0, 'a tree that shares another tree\'s Zig cache built '
           'with that tree\'s configuration instead of failing')
    expect(f'belongs to {base.resolve()}' in reused.stderr,
           f'the shared-cache failure does not name the other tree:\n{reused.stderr}')
    print('ok   a second tree sharing the Zig cache fails and names the first tree')

    private = build(zig, work, scratch / 'work-cache')
    expect(private != first, 'two trees with different sources embed one compiler_identity')
    print('ok   the second tree, with its own cache, embeds its own identity')

    # In-place edits in one tree, all through the same warm cache.
    edit(base, 'sema.zig', '// edited\n')
    frontend = build(zig, base, shared)
    expect(frontend != first, 'a front-end edit left compiler_identity unchanged')
    edit(base, 'core/emit.zig', '// edited\n')
    core = build(zig, base, shared)
    expect(core != frontend, 'a new-core edit left compiler_identity unchanged')
    edit(base, 'core/runtime/rt.c', '/* edited */\n')
    runtime = build(zig, base, shared)
    expect(runtime != core, 'a runtime C edit left compiler_identity unchanged')
    print('ok   front-end, core and runtime edits move compiler_identity')

    edit(base, 'sema_test.zig', '// edited\n')
    edit(base, 'test_support.zig', '// edited\n')
    test_only = build(zig, base, shared)
    expect(test_only == runtime, 'a test-only edit moved compiler_identity')
    print('ok   test-only edits leave compiler_identity unchanged')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--zig', default='zig', help='the pinned Zig executable')
    parser.add_argument('--keep', action='store_true', help='keep the scratch trees')
    args = parser.parse_args()
    scratch = Path(tempfile.mkdtemp(prefix='compiler-identity-'))
    try:
        run(args.zig, scratch)
    except AssertionError as failure:
        print(f'FAIL {failure}', file=sys.stderr)
        print(f'scratch trees kept at {scratch}', file=sys.stderr)
        return 1
    if not args.keep:
        shutil.rmtree(scratch, ignore_errors=True)
    print('compiler identity cache: all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
