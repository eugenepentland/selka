#!/usr/bin/env python3
"""Check that the compiler's build-time identity follows the sources it covers.

``build_identity.zig`` embeds ``compiler_identity`` in the compiler: a digest of
every production source under ``src`` (a Zig file by its tokens, so a comment or a
change of layout leaves it as it was; any other file by its bytes), the Zig
toolchain and the optimize mode.
The front end keys its persistent caches by it, so a digest that describes other
bytes would let a rebuilt compiler replay an older compiler's answers.

This driver runs the real ``build_identity.zig`` on small throwaway trees with a
probe program in place of the compiler. It builds them with ``zig build`` exactly
the way the hazard was found: two trees that share one ``ZIG_LOCAL_CACHE_DIR``,
then edits in place. After every build it checks the identity the probe embeds
and the source list it covers, and that sharing one Zig cache between trees fails
loudly instead of reusing the other tree's configuration.

The compiler also embeds a build product (the number-text object) whose bytes
depend on settings in ``build.zig`` that no source file records. The throwaway
tree builds a small object the same way and hands it to the identity module, so
the driver can change only a build setting of the object and check that the
compiler identity follows the object's bytes: it moves when the object changes,
not when ``build.zig`` changes in a way that leaves the object as it was.
"""
import argparse
import hashlib
import json
import mmap
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TIMEOUT = 600

BUILD_ZIG = """\
const std = @import("std");
pub fn build(b: *std.Build) void {
    // The embedded product: an object whose machine code depends on the CPU it is built for.
    const object = b.addObject(.{ .name = "product", .root_module = b.createModule(.{
        .root_source_file = b.path("product.zig"),
        .target = b.resolveTargetQuery(std.Target.Query.parse(.{ .arch_os_abi = "x86_64-linux-gnu", .cpu_features = "CPU" }) catch @panic("target")),
        .optimize = .ReleaseFast,
        .strip = true,
    }) });
    const identity = @import("build_identity.zig").module(b, b.graph.host, .Debug, .{ .compile = 1 << 30, .run = 1 << 28 }, &.{.{ .name = "core_number_text_object", .file = object.getEmittedBin() }});
    const probe = b.addExecutable(.{ .name = "probe", .root_module = b.createModule(.{
        .root_source_file = b.path("probe.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }) });
    probe.root_module.addImport("build_identity", identity);
    b.installArtifact(probe);
    b.getInstallStep().dependOn(&b.addInstallFile(object.getEmittedBin(), "product.o").step);
}
"""

# One vector add: SSE2 pairs on the baseline CPU, one AVX2 instruction on skylake.
PRODUCT_ZIG = """\
export fn lanes(a: *[8]u32, b: *const [8]u32) void {
    var v: @Vector(8, u32) = a.*;
    v += b.*;
    a.* = v;
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
    for (built.embedded_products) |product| std.debug.print("product {s} {s}\\n", .{ product.name, product.digest });
    for (built.stage_identities, 0..) |stage, index| std.debug.print("stage {d} {s}\\n", .{ index, stage });
}
"""

# Explicit miniature policy: every production source affects the compiler identity; two test-only files affect nothing.
RULES = 'build_identity_rules.zig'
ELIGIBILITY = (
    'typed_walk.zig', 'typed.zig', 'type_identity.zig', 'sema.zig',
    'sema_contracts.zig', 'entry_adapter.zig', 'semantic_entry.zig',
    'semantic_cache.zig',
)
SOURCES = {
    'parser.zig': 'pub const parsed = true;\n',
    'core/emit.zig': 'pub const units = 1;\n',
    'core/test_runner_execute.zig': 'pub const trials = 1;\n',
    'core/runtime/rt.c': 'int myl_rt(void) { return 1; }\n',
    'sema_test.zig': 'test { }\n',
    'test_support.zig': 'pub const fixture = 1;\n',
}
SOURCES.update({name: 'pub const eligible = true;\n' for name in ELIGIBILITY})
# The stage roots of build_identity_rules.zig (`stage_roots`), mirrored here: the stage identities name every root,
# and a tree without one is refused (MissingSource), so the miniature tree must carry each as a leaf source.
STAGE_ROOTS = ('compiler.zig', 'core/frontend_reuse.zig', 'core/build.zig', 'core/lowering_cache.zig',
               'core/lowering_demand.zig', 'core/lowering_finish.zig', 'core/demand_ir.zig', 'core/passes.zig',
               'core/optimization_cache.zig', 'core/optimizer_shortcut.zig', 'core/fusion_checkpoint.zig',
               'core/emit_llvm.zig', 'core/emit_units.zig', 'core/emission_cache.zig', 'core/emission_key.zig',
               'core/native_receipt.zig', 'core/test_runner_facts.zig', 'core/test_runner_graph.zig',
               'core/test_runner_identity.zig')
SOURCES.update({name: 'pub const stage_root = true;\n' for name in STAGE_ROOTS})
# The product's source is a production file, and the emit stage embeds the product, as core/emit_units.zig does through
# core/number_runtime.zig: only stages whose closure reaches the embed carry the product's bytes.
PRODUCT_SOURCE = 'core/runtime/core_number_text.zig'
SOURCES[PRODUCT_SOURCE] = 'pub const number_text = true;\n'
SOURCES['core/emit_units.zig'] = 'pub const object = @embedFile("core_number_text_object");\n'
EMIT_STAGE = 3
# The roots of the engine kinds of build_identity_rules.zig (`engine_kinds`), mirrored here for the same reason: each kind's
# identity names its roots, and a tree without one is refused (MissingSource). The files a kind covers (`test_exec_covers`,
# `test_exec_boundary`, `test_report_covers` and the front end kinds' lists) are read from the rules file itself, so the list cannot drift; each is a leaf.
ENGINE_ROOTS = ('core/engine/kinds/probe.zig', 'core/engine/kinds/probe_size.zig', 'core/engine/kinds/probe_class.zig',
                'core/engine/kinds/test_exec.zig', 'core/engine/kinds/module_tokens.zig', 'core/engine/kinds/test_report.zig', 'core/engine/kinds/module_syntax.zig',
                'core/engine/kinds/project_graph.zig', 'core/engine/kinds/module_interface.zig', 'core/engine/kinds/module_check.zig', 'core/engine/kinds/noalloc_closure.zig', 'core/engine/kinds/module_passes.zig',
                'core/engine/kinds/program_diagnostics.zig', 'core/engine/kinds/unit_lower.zig', 'core/engine/kinds/program_facts.zig', 'core/engine/kinds/unit_optimize.zig', 'core/engine/kinds/unit_emit.zig', 'core/engine/kinds/ownership_proof.zig',
                'core/engine/kinds/test_facts.zig', 'core/engine/kinds/test_graph.zig')


def zig_list(name: str) -> list:
    """The strings of the `const NAME = [_][]const u8{ ... };` array of the rules file."""
    text = (ROOT / 'src' / RULES).read_text(encoding='utf-8')
    found = re.search(r'const %s = \[_\]\[\]const u8\{(.*?)\};' % name, text, re.S)
    assert found, f'{RULES} has no list called {name}'
    return re.findall(r'"([^"]+)"', found.group(1))


ENGINE_COVER_LISTS = ('test_exec_covers', 'test_exec_boundary', 'module_tokens_covers', 'test_report_covers', 'module_syntax_covers',
                      'project_graph_covers', 'module_interface_covers', 'module_check_covers', 'noalloc_closure_covers', 'module_passes_covers', 'program_diagnostics_covers', 'unit_lower_covers', 'program_facts_covers', 'unit_optimize_covers', 'unit_emit_covers', 'ownership_proof_covers',
                      'test_facts_covers', 'test_graph_covers')
ENGINE_COVERS = tuple(sorted(set(sum((zig_list(name) for name in ENGINE_COVER_LISTS), []))
                             - set(SOURCES) - set(ENGINE_ROOTS)))
SOURCES.update({name: 'pub const engine_root = true;\n' for name in ENGINE_ROOTS})
SOURCES.update({name: 'pub const engine_cover = true;\n' for name in ENGINE_COVERS})
PRODUCTION = sorted(['parser.zig', 'core/emit.zig', 'core/test_runner_execute.zig',
                     'core/runtime/rt.c', RULES, PRODUCT_SOURCE, *ELIGIBILITY, *STAGE_ROOTS, *ENGINE_ROOTS, *ENGINE_COVERS])

# Where the tool's own sources are copied from: this checkout, or (`--tool-root`) a mutated copy that must fail.
TOOL_ROOT = ROOT


def make_tree(path: Path) -> None:
    (path / 'src').mkdir(parents=True)
    shutil.copy(TOOL_ROOT / 'build_identity.zig', path / 'build_identity.zig')
    shutil.copy(TOOL_ROOT / 'src' / RULES, path / 'src' / RULES)
    (path / 'build.zig').write_text(BUILD_ZIG.replace('CPU', 'baseline'))
    (path / 'product.zig').write_text(PRODUCT_ZIG)
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
    return build_all(zig, tree, cache)['compiler']


def build_all(zig: str, tree: Path, cache: Path) -> dict:
    """Build `tree` and return its compiler identity, its stage identities and its embedded products.

    Checks the sources the identity covers, and that the digest recorded for the embedded product is the digest of
    the object file the build produced.
    """
    result = zig_build(zig, tree, cache)
    if result.returncode != 0:
        raise AssertionError(f'zig build failed in {tree}:\n{result.stderr}')
    probe = subprocess.run([str(tree / 'zig-out' / 'bin' / 'probe')], capture_output=True,
                           text=True, timeout=TIMEOUT, check=True)
    identity, inputs, products, stages = '', [], {}, {}
    for line in probe.stderr.splitlines():
        key, _, value = line.partition(' ')
        if key == 'input':
            inputs.append(value)
        elif key == 'compiler_identity':
            identity = value
        elif key == 'product':
            name, _, digest = value.partition(' ')
            products[name] = digest
        elif key == 'stage':
            index, _, digest = value.partition(' ')
            stages[int(index)] = digest
    expect(len(identity) == 64, f'{tree}: compiler_identity is not a SHA-256: {identity!r}')
    expect(inputs == PRODUCTION, f'{tree}: the identity covers {inputs}, not the production '
           f'sources {PRODUCTION}')
    expect(list(products) == ['core_number_text_object'], f'{tree}: the identity names the products {list(products)}')
    object_digest = hashlib.sha256((tree / 'zig-out' / 'product.o').read_bytes()).hexdigest()
    expect(products['core_number_text_object'] == object_digest,
           f'{tree}: the identity records {products["core_number_text_object"]} for an object whose bytes digest to {object_digest}')
    expect(len(stages) == 5, f'{tree}: the identity holds {len(stages)} stage identities, not 5')
    return {'compiler': identity, 'stages': stages, 'object': object_digest}


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def edit(tree: Path, name: str, text: str) -> None:
    (tree / 'src' / name).write_text((tree / 'src' / name).read_text() + text)


def run(zig: str, scratch: Path) -> None:
    base, work = scratch / 'base', scratch / 'work'
    make_tree(base)
    make_tree(work)
    edit(work, 'parser.zig', 'pub const work_tree = true;\n')
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
    first_identity = build(zig, base, shared)
    # A comment or a change of layout is not a different compiler (COMPILER-IDENTITY-TOKENS-1): the identity does not
    # move, so a rebuilt compiler replays the caches of the one it replaces.
    edit(base, 'parser.zig', '// a comment only\n\n\n    \n')
    expect(build(zig, base, shared) == first_identity, 'a comment-only edit of a Zig source moved the identity')
    print('ok   a comment-only edit of a Zig source moves no identity')
    prior = first_identity
    for name, label in (('parser.zig', 'a parser'), ('core/emit.zig', 'a new-core'), ('core/runtime/rt.c', 'a runtime C'),
                        ('core/test_runner_execute.zig', 'a runner')):
        edit(base, name, '/* edited */\n' if name.endswith('.c') else 'pub const edited = 1;\n')
        moved = build(zig, base, shared)
        expect(moved != prior, f'{label} edit left compiler_identity unchanged')
        prior = moved
    for name in ELIGIBILITY:
        edit(base, name, 'pub const edited = 1;\n')
        moved = build(zig, base, shared)
        expect(moved != prior, f'{name}: edit left compiler_identity unchanged')
        prior = moved
    print('ok   parser, core, runtime, runner and checker edits move compiler_identity')

    edit(base, 'sema_test.zig', '// edited\n')
    edit(base, 'test_support.zig', '// edited\n')
    expect(build(zig, base, shared) == prior, 'a test-only edit moved compiler_identity')
    print('ok   test-only edits leave the identity unchanged')

    # The finding of lane B (L1c): a change to how an embedded object is built, made in build.zig alone, left the
    # compiler identity as it was, so a stale replay record could serve a binary linked with the old object.
    before = build_all(zig, base, shared)
    # A build.zig edit that leaves the object's bytes as they were is not a different compiler.
    (base / 'build.zig').write_text((base / 'build.zig').read_text() + '// a comment about the build only\n')
    commented = build_all(zig, base, shared)
    expect(commented == before, 'a build.zig edit that left the embedded object unchanged moved an identity')
    print('ok   a build.zig edit that leaves the embedded object as it was moves no identity')
    # Only the CPU the object is built for changes: no source file differs.
    (base / 'build.zig').write_text((base / 'build.zig').read_text().replace('"baseline"', '"skylake"'))
    retargeted = build_all(zig, base, shared)
    expect(retargeted['object'] != before['object'], 'the CPU edit did not change the object, so the probe proves nothing')
    expect(retargeted['compiler'] != before['compiler'], 'a CPU change of the embedded object left compiler_identity unchanged')
    expect(retargeted['stages'][EMIT_STAGE] != before['stages'][EMIT_STAGE],
           'a CPU change of the embedded object left the identity of the stage that embeds it unchanged')
    unrelated = [index for index in before['stages'] if index != EMIT_STAGE and retargeted['stages'][index] != before['stages'][index]]
    expect(unrelated == [], f'a CPU change of the embedded object moved the stages {unrelated}, which do not embed it')
    print('ok   a build.zig-only change to the embedded object moves compiler_identity and the stage that embeds it')
    # And a comment-only edit of a Zig source still moves nothing, with the object in the graph.
    edit(base, 'parser.zig', '// a comment only, again\n')
    expect(build_all(zig, base, shared) == retargeted, 'a comment-only edit of a Zig source moved an identity')
    print('ok   a comment-only edit still moves no identity')


# The tool's per-file record (the record section of src/build_identity_rules.zig) must never change what the tool
# writes. Each case below edits a throwaway tree the way a developer or an editor does, then runs the tool with the
# record and without it, and the two outputs (identity.zig and the depfile) must be the same bytes. `--report` says how
# many sources the record served, so a case also shows that the record was used where it may be and refused where it
# may not. The record is keyed by each file's bytes (D-DL3-7), so it serves every file a case did not change.
# False (`--bytes-only`) checks only that the outputs match, so a mutated record shows the identity it would get wrong.
COUNTS = True

# Every kind of edge the closures follow, added to the miniature tree for the record cases and the fixtures: the front end
# module's members named directly and through an alias, a use of the whole module, an `@embedFile` of a `.selka` file and of
# the named product, a `.zon` import, a relative `../` import, a conditional import, an import in a function body, and
# an import inside a `test` declaration, which no closure follows.
EDGE_FILES = {
    'compiler.zig': 'pub const stage_root = true;\npub const typed = @import("typed.zig");\npub const sema = @import("sema.zig");\n',
    'core/engine/kinds/probe.zig': (
        '//! A probe that names every kind of edge.\n'
        'const typed = @import("selka").typed;\n'
        'const front = @import("selka");\n'
        'const checker = front.sema;\n'
        'const library = @embedFile("../../../stdlib/core.selka");\n'
        'const object = @embedFile("core_number_text_object");\n'
        'const settings = @import("probe.zon");\n'
        'const emitter = if (@import("builtin").os.tag == .linux) @import("../../emit.zig") else @import("../../parser_shim.zig");\n'
        'fn later() void {\n    _ = @import("probe_size.zig");\n}\n'
        'test {\n    _ = @import("never_followed.zig");\n}\n'),
    'core/engine/kinds/probe.zon': '.{ .probe = true }\n',
    'core/engine/kinds/probe_size.zig': 'const front = @import("selka");\nfn whole() void {\n    use(front);\n}\n',
    'core/parser_shim.zig': 'pub const shim = true;\n',
    'stdlib/core.selka': 'public func one() -> int:\n    return 1\n',
}


class Tool:
    """The identity tool compiled from a tree's build_identity.zig, run directly on a source tree."""

    def __init__(self, zig: str, tree: Path, work: Path, name: str):
        self.zig, self.tree, self.work = zig, tree, work
        self.exe = work / name / 'build-identity'
        self.exe.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([zig, 'build-exe', '-ODebug', str(tree / 'build_identity.zig'), f'-femit-bin={self.exe}',
                        '--cache-dir', str(work / 'zig-cache')], cwd=work, check=True, capture_output=True, timeout=TIMEOUT)
        self.version = subprocess.run([zig, 'version'], capture_output=True, text=True, check=True).stdout.strip()
        self.product = work / 'product.o'
        self.product.write_bytes(b'the embedded product\n')
        self.runs = 0

    def raw(self, tree: Path, *options: str, version: str = '', out: Path = None) -> tuple:
        """Run on `tree` into OUT (a fresh directory unless given); return (exit status, identity.zig or '', depfile
        or '', stderr)."""
        self.runs += 1
        out = out or self.work / f'out-{self.runs}'
        result = subprocess.run([str(self.exe), *options, str(tree.resolve()), str((tree / 'src').resolve()),
                                 version or self.version, 'debug', str(out), str(out / 'identity.d'),
                                 'core_number_text_object', str(self.product)],
                                capture_output=True, text=True, timeout=TIMEOUT)
        read = lambda path: path.read_text() if result.returncode == 0 and path.exists() else ''
        return result.returncode, read(out / 'identity.zig'), read(out / 'identity.d'), result.stderr

    def run(self, tree: Path, *options: str) -> tuple:
        """Run on `tree` with `options`; return (identity.zig, depfile, served count or None)."""
        status, identity, depfile, stderr = self.raw(tree, *options)
        if status != 0:
            raise AssertionError(f'the identity tool failed on {tree} with {options}:\n{stderr}')
        found = re.search(r'build-identity record: (\d+) served, (\d+) read', stderr)
        return identity, depfile, int(found.group(1)) if found else None


def compiler_identity(text: str) -> str:
    return re.search(r'compiler_identity = "([0-9a-f]{64})"', text).group(1)


def same_size_edit(path: Path) -> None:
    """Rewrite `path` in place with different bytes of the same length (its last digit or letter changed)."""
    data = bytearray(path.read_bytes())
    for index in range(len(data) - 1, -1, -1):
        if chr(data[index]).isalnum():
            data[index] = ord('7') if data[index] != ord('7') else ord('8')
            break
    with open(path, 'r+b') as handle:
        handle.write(bytes(data))


def write_files(src: Path, files: dict) -> None:
    for name, text in files.items():
        (src / name).parent.mkdir(parents=True, exist_ok=True)
        (src / name).write_text(text)


def record_cases(zig: str, scratch: Path) -> None:
    tree, work = scratch / 'record-tree', scratch / 'record-work'
    make_tree(tree)
    src = tree / 'src'
    write_files(src, EDGE_FILES)
    work.mkdir()
    tool = Tool(zig, tree, work, 'tool')
    record = ('--record', str(work / 'cache'), '--report')
    record_file = work / 'cache' / 'selka-identity-record' / 'record'

    def production() -> set:
        return {str(p.relative_to(src)) for p in src.rglob('*')
                if p.is_file() and not p.name.endswith('_test.zig') and p.name != 'test_support.zig'}

    sources = len(production())

    def compare(label: str, changed=(), served=None, runner: Tool = tool) -> str:
        identity, depfile, count = runner.run(tree, *record)
        plain_identity, plain_depfile, _ = runner.run(tree)
        expect(identity == plain_identity, f'{label}: the record gave another identity.zig than the uncached tool')
        expect(depfile == plain_depfile, f'{label}: the record gave another depfile than the uncached tool')
        expected = len(production() - set(changed)) if served is None else served
        expect(not COUNTS or count == expected, f'{label}: the record served {count} sources, expected {expected}')
        print(f'ok   record: {label} (served {count} of {len(production())})')
        return identity

    base = compare('a first run fills the record', served=0)
    expect('typed.zig' in base and 'core/engine/kinds/probe.zon' in base and 'stdlib/core.selka' in base,
           'the edge tree does not cover its member, .zon and .selka edges')
    expect(compare('nothing changed') == base, 'an unchanged tree moved the identity')
    (src / 'parser.zig').write_text((src / 'parser.zig').read_text() + '// a comment only\n')
    expect(compiler_identity(compare('a comment edit', ['parser.zig'])) == compiler_identity(base),
           'a comment edit moved the identity through the record')
    (src / 'parser.zig').write_text((src / 'parser.zig').read_text() + 'pub const edited = 1;\n')
    expect(compiler_identity(compare('a code edit', ['parser.zig'])) != compiler_identity(base),
           'a code edit left the identity unchanged')
    (src / 'typed.zig').write_text((src / 'typed.zig').read_text() + 'pub const member_edited = 1;\n')
    compare('a member file named through the front end module edited', ['typed.zig'])
    (src / 'compiler.zig').write_text((src / 'compiler.zig').read_text().replace('@import("typed.zig")', '@import("sema.zig")'))
    compare('the member table changed', ['compiler.zig'])
    (src / 'core' / 'added.zig').write_text('pub const added = 1;\n')
    (src / 'compiler.zig').write_text((src / 'compiler.zig').read_text() + 'const added = @import("core/added.zig");\n')
    expect('core/added.zig' in compare('a file added and imported', ['compiler.zig', 'core/added.zig']),
           'the added file is not covered')
    (src / 'core' / 'added.zig').unlink()
    (src / 'compiler.zig').write_text((src / 'compiler.zig').read_text().replace('const added = @import("core/added.zig");\n', ''))
    expect('core/added.zig' not in compare('a file deleted', ['compiler.zig']), 'the deleted file is still covered')
    (src / 'core' / 'parser_shim.zig').rename(src / 'core' / 'parser_shim2.zig')
    probe = src / 'core' / 'engine' / 'kinds' / 'probe.zig'
    probe.write_text(probe.read_text().replace('parser_shim.zig', 'parser_shim2.zig'))
    expect('core/parser_shim2.zig' in compare('a file renamed', ['core/parser_shim2.zig', 'core/engine/kinds/probe.zig']),
           'the renamed file is not covered')
    os.utime(src / 'core' / 'runtime' / 'rt.c')
    compare('a file touched without change')

    # A same-size edit, then another with its modification time put back, at once: the bytes decide.
    racy = src / 'core' / 'test_runner_execute.zig'
    same_size_edit(racy)
    first = racy.stat()
    compare('a same-size edit', [str(racy.relative_to(src))])
    same_size_edit(racy)
    os.utime(racy, ns=(first.st_atime_ns, first.st_mtime_ns))
    compare('a second same-size edit at once, its time restored', [str(racy.relative_to(src))])

    # The watch's live run writes into one directory every time. An unchanged identity must leave identity.zig (which
    # the compile steps watch) untouched, or the watch builds once more after every edit; a changed one is rewritten.
    fixed = work / 'fixed-out'

    def written(*options: str) -> tuple:
        status, identity, depfile, stderr = tool.raw(tree, *options, out=fixed)
        expect(status == 0, f'the identity tool failed into a fixed directory:\n{stderr}')
        status_of = (fixed / 'identity.zig').stat()
        return identity, depfile, (status_of.st_ino, status_of.st_mtime_ns, status_of.st_ctime_ns)

    for options in ((), record):
        label = 'with the record' if options else 'without the record'
        identity, depfile, before = written(*options)
        again, again_depfile, after = written(*options)
        expect((again, again_depfile) == (identity, depfile), f'{label}: an unchanged tree changed the outputs')
        expect(after == before, f'{label}: an unchanged identity rewrote identity.zig')
        print(f'ok   record: {label}, an unchanged identity leaves identity.zig untouched')
        (src / 'parser.zig').write_text((src / 'parser.zig').read_text() + 'pub const rewritten_%d = 1;\n' % len(options))
        changed, _, rewritten = written(*options)
        expect(compiler_identity(changed) != compiler_identity(identity) and rewritten != before,
               f'{label}: a changed identity was not written')
        expect((fixed / 'identity.zig').read_text() == changed, f'{label}: identity.zig does not hold the new identity')
        print(f'ok   record: {label}, a changed identity rewrites identity.zig')

    # A file replaced by other bytes of the same size with its old times restored (touch -r), in place and by a rename.
    target = src / 'parser.zig'
    old = target.stat()
    same_size_edit(target)
    os.utime(target, ns=(old.st_atime_ns, old.st_mtime_ns))
    compare('a same-size rewrite in place with its old times restored', ['parser.zig'])
    old = target.stat()
    replacement = src / 'parser.zig.new'
    replacement.write_bytes(target.read_bytes())
    same_size_edit(replacement)
    os.utime(replacement, ns=(old.st_atime_ns, old.st_mtime_ns))
    replacement.rename(target)
    compare('a same-size replacement by rename with its old times restored', ['parser.zig'])

    # A write through a shared memory mapping: the kernel moves the file's times only on the first write to a clean page,
    # so a second write to the dirty page leaves the status as it was. Three seconds apart, so a status rule with a
    # two-second racy window would have trusted the entry (the review of 13 November reproduced that).
    mapped = src / 'typed.zig'
    descriptor = os.open(mapped, os.O_RDWR)
    try:
        view = mmap.mmap(descriptor, 0, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
        index = view.rfind(b'1')
        view[index] = ord('5')
        time.sleep(3)
        compare('a write through a shared mapping', ['typed.zig'])
        before = os.stat(mapped)
        view[index] = ord('6')
        after = os.stat(mapped)
        compare('a second write to the same dirty page' + (' (the status did not move)' if
                (before.st_mtime_ns, before.st_ctime_ns) == (after.st_mtime_ns, after.st_ctime_ns) else ''), ['typed.zig'])
        view.close()
    finally:
        os.close(descriptor)

    # Named non-Zig files are digested by their bytes.
    same_size_edit(src / 'core' / 'runtime' / 'rt.c')
    before_my = compare('the C runtime edited (same size)', ['core/runtime/rt.c'])
    same_size_edit(src / 'stdlib' / 'core.selka')
    expect(compiler_identity(compare('an embedded .selka file edited (same size)', ['stdlib/core.selka'])) != compiler_identity(before_my),
           'a .selka edit left the identity unchanged')

    # Another root: tree two has the same paths and one file's other bytes; it gets tree one's record.
    other = scratch / 'record-other'
    shutil.copytree(tree, other)
    same_size_edit(other / 'src' / 'parser.zig')
    (work / 'cache-other' / 'selka-identity-record').mkdir(parents=True)
    shutil.copy(record_file, work / 'cache-other' / 'selka-identity-record' / 'record')
    identity, depfile, count = tool.run(other, '--record', str(work / 'cache-other'), '--report')
    expect((identity, depfile) == tool.run(other)[:2], 'a record of another root gave another identity')
    expect(not COUNTS or count == 0, f'a record of another root served {count} sources')
    print('ok   record: a record of another root is ignored')

    # A truncated record and a damaged one are ignored, and the next run writes a whole one.
    data = record_file.read_bytes()
    record_file.write_bytes(data[:len(data) // 2])
    compare('a truncated record', served=0)
    data = bytearray(record_file.read_bytes())
    data[len(data) // 3] ^= 0x40
    record_file.write_bytes(bytes(data))
    compare('a damaged record', served=0)
    compare('a whole record again')

    # Two runs at once: each reads a whole record (or none) and writes a whole one.
    plain = tool.run(tree)[:2]
    outs = [work / f'together-{index}' for index in range(4)]
    processes = [subprocess.Popen([str(tool.exe), *record, str(tree.resolve()), str(src.resolve()), tool.version, 'debug',
                                   str(out), str(out / 'identity.d'), 'core_number_text_object', str(tool.product)],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE) for out in outs]
    for process in processes:
        process.communicate(timeout=TIMEOUT)
        expect(process.returncode == 0, 'a concurrent run of the tool failed')
    for out in outs:
        expect(((out / 'identity.zig').read_text(), (out / 'identity.d').read_text()) == plain,
               'a concurrent run with the record gave another identity')
    compare('after four runs at once')

    # Another version of the tool (its source changed by a comment) ignores the record.
    changed = scratch / 'record-tool-two'
    (changed / 'src').mkdir(parents=True)
    shutil.copy(tree / 'build_identity.zig', changed / 'build_identity.zig')
    (changed / 'build_identity.zig').write_text((changed / 'build_identity.zig').read_text() + '// another version\n')
    shutil.copy(src / RULES, changed / 'src' / RULES)
    compare('another version of the tool', served=0, runner=Tool(zig, changed, work, 'tool-two'))

    # The field check computes both ways and agrees.
    tool.run(tree, '--record', str(work / 'cache'), '--record-check')
    print('ok   record: --record-check agrees')

    # A symbolic link under src would be invisible to the identity (it is no regular file), so the tool refuses it.
    (src / 'linked.zig').symlink_to('parser.zig')
    status, _, _, stderr = tool.raw(tree)
    expect(status != 0 and 'src/linked.zig is a symbolic link' in stderr,
           f'a symbolic link under src was not refused (exit {status}):\n{stderr}')
    status, _, _, stderr = tool.raw(tree, *record)
    expect(status != 0 and 'src/linked.zig is a symbolic link' in stderr, 'a symbolic link was not refused with the record')
    (src / 'linked.zig').unlink()
    print('ok   record: a symbolic link under src is refused')


# An oracle that shares no code with the tool under test: the outputs of main's tool at FIXTURE_COMMIT on fixed
# synthetic trees, committed in FIXTURES. The current tool must reproduce them byte for byte. When the rules change on
# purpose, regenerate them (see the failure message); until then they pin today's identities.
FIXTURE_COMMIT = '8d09296758'
FIXTURES = ROOT / 'test' / 'fixtures' / 'build-identity' / 'expected.json'
FIXTURE_VERSION = '0.0.0-fixture'
FIXTURE_TREES = {
    'miniature': {},
    'every-edge': EDGE_FILES,
    'refused-parse': {**EDGE_FILES, 'compiler.zig': 'pub const = ;\n'},
    'refused-unknown-module': {**EDGE_FILES, 'core/parser_shim.zig': 'const x = @import("no_such_module");\n'},
    'refused-non-literal': {'core/emit_llvm.zig': 'const name = "x.zig";\nconst x = @import(name);\n'},
    'refused-test-only': {'core/emit_llvm.zig': 'const x = @import("../sema_test.zig");\n'},
    'refused-missing': {'core/emit_llvm.zig': 'const x = @import("missing.zig");\n'},
    'refused-member-root': {**EDGE_FILES, 'compiler.zig': EDGE_FILES['compiler.zig'] + 'const x = @import("no_such_module");\n'},
}


def real_tree_case(zig: str, scratch: Path, depfile: str) -> None:
    """The real `src`: the tool's facts (fresh, then served from a record) give the identity its bytes give.

    `--record-check` forms the identity a second time from every source's bytes, parsing each file again in each of the
    stage and engine-kind closures (each parse freed after its file), and fails on any difference. The tool is built
    ReleaseFast: the bytes form takes about 4 s on all of `src` that way. The depfile (`--depfile`) names every source
    read, so the build reruns this check after any edit under `src`.
    """
    work = scratch / 'real-work'
    work.mkdir()
    exe = work / 'build-identity'
    subprocess.run([zig, 'build-exe', '-OReleaseFast', str(TOOL_ROOT / 'build_identity.zig'), f'-femit-bin={exe}',
                    '--cache-dir', str(work / 'zig-cache')], cwd=work, check=True, capture_output=True, timeout=TIMEOUT)
    product = work / 'product.o'
    product.write_bytes(b'the embedded product\n')
    for label in ('facts computed fresh', 'facts served from the record'):
        out = work / label.replace(' ', '-')
        result = subprocess.run([str(exe), '--record', str(work / 'cache'), '--record-check', '--report', str(ROOT),
                                 str(ROOT / 'src'), 'real-tree', 'debug', str(out), str(out / 'identity.d'),
                                 'core_number_text_object', str(product)], capture_output=True, text=True, timeout=TIMEOUT)
        expect(result.returncode == 0, f'the real src: {label} differ from the bytes form:\n{result.stderr[-3000:]}')
        print(f'ok   real tree: {label} give the identity the bytes give ({result.stderr.strip().splitlines()[-1]})')
    if depfile:
        shutil.copy(work / 'facts-served-from-the-record' / 'identity.d', depfile)


def fixture_outputs(zig: str, scratch: Path) -> dict:
    """What the tool built from TOOL_ROOT writes for each fixture tree: exit status, outputs, the first stderr line."""
    work = scratch / 'fixture-work'
    work.mkdir()
    tool = Tool(zig, TOOL_ROOT, work, 'fixture-tool')
    outputs = {}
    for name, files in FIXTURE_TREES.items():
        tree = scratch / f'fixture-{name}'
        write_files(tree / 'src', SOURCES)
        write_files(tree / 'src', files)
        status, identity, depfile, stderr = tool.raw(tree, version=FIXTURE_VERSION)
        source = str((tree / 'src').resolve())
        outputs[name] = {'exit': status, 'identity': identity, 'depfile': depfile.replace(source, '@SRC@'),
                         'error': stderr.strip().splitlines()[0] if status != 0 and stderr.strip() else ''}
    return outputs


def fixture_cases(zig: str, scratch: Path) -> None:
    expected = json.loads(FIXTURES.read_text())
    actual = fixture_outputs(zig, scratch)
    expect(sorted(expected['trees']) == sorted(actual), f'{FIXTURES} holds the trees {sorted(expected["trees"])}, the test '
           f'builds {sorted(actual)}; regenerate it')
    for name, want in expected['trees'].items():
        expect(actual[name] == want, f'fixture tree {name}: the tool no longer writes what {expected["generated_by"]} wrote. '
               'If the identity rules changed on purpose, regenerate the fixtures with the tool that has the intended rules: '
               'python3 tests/compiler_identity_cache.py --zig ZIG --write-fixtures --tool-root TREE (a tree holding '
               'build_identity.zig and src/build_identity_rules.zig), and say so in the commit')
        print(f'ok   fixture: {name} ({"exit 0" if want["exit"] == 0 else want["error"][:60]})')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--zig', default='zig', help='the pinned Zig executable')
    parser.add_argument('--keep', action='store_true', help='keep the scratch trees')
    parser.add_argument('--only', choices=('all', 'builds', 'record', 'fixtures', 'real'), default='all',
                        help='run only the zig build checks, the record comparison, the fixture oracle or the real tree')
    parser.add_argument('--depfile', default='', help='write a depfile naming every source of the real tree read')
    parser.add_argument('--generated-by', default=f"main's build_identity.zig at {FIXTURE_COMMIT}",
                        help='what --write-fixtures records as the tool that wrote the fixtures')
    parser.add_argument('--write-fixtures', action='store_true',
                        help=f'write {FIXTURES.relative_to(ROOT)} from the tool at --tool-root and stop')
    parser.add_argument('--bytes-only', action='store_true', help='skip the served-count checks of the record cases')
    parser.add_argument('--tool-root', type=Path, default=ROOT,
                        help='take build_identity.zig and the rules from this tree (a mutated copy must fail)')
    args = parser.parse_args()
    global TOOL_ROOT, COUNTS
    TOOL_ROOT = args.tool_root.resolve()
    COUNTS = not args.bytes_only
    scratch = Path(tempfile.mkdtemp(prefix='compiler-identity-'))
    try:
        if args.write_fixtures:
            FIXTURES.parent.mkdir(parents=True, exist_ok=True)
            FIXTURES.write_text(json.dumps({'generated_by': args.generated_by,
                                            'trees': fixture_outputs(args.zig, scratch)}, indent=1, sort_keys=True) + '\n')
            print(f'wrote {FIXTURES}')
            shutil.rmtree(scratch, ignore_errors=True)
            return 0
        if args.only in ('all', 'builds'):
            run(args.zig, scratch)
        if args.only in ('all', 'record'):
            record_cases(args.zig, scratch)
        if args.only in ('all', 'fixtures'):
            fixture_cases(args.zig, scratch)
        if args.only in ('all', 'real'):
            real_tree_case(args.zig, scratch, args.depfile)
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
