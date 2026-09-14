#!/usr/bin/env python3
"""Build native programs using a relocated compiler with no Python on PATH."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

import qbe_native_calls
import native_providers

ROOT = Path(__file__).resolve().parents[1]


def invoke(command, *, env, cwd):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=240,
                          env=env, cwd=cwd)


def checked(command, *, env, cwd):
    result = invoke(command, env=env, cwd=cwd)
    assert result.returncode == 0, (command, result.stdout.decode(errors='replace'),
                                    result.stderr.decode(errors='replace'))
    return result


class Builder:
    def __init__(self, directory, compiler, qbe, zig):
        self.directory = directory
        self.compiler = compiler
        self.qbe = qbe
        self.zig = zig
        self.source = directory / 'source with spaces.my'
        self.output = directory / 'native output'
        self.cache = directory / 'object cache'
        empty_path = directory / 'empty PATH'
        empty_path.mkdir()
        self.env = dict(os.environ, PATH=str(empty_path))
        assert shutil.which('python3', path=self.env['PATH']) is None
        assert shutil.which('python', path=self.env['PATH']) is None

    def build(self, *extra, failure=False):
        options = {'-o': self.output, '--qbe': self.qbe, '--zig': self.zig,
                   '--cache-dir': self.cache, '--target': 'amd64_sysv'}
        switches = ['--report']
        index = 0
        while index < len(extra):
            flag = extra[index]
            if flag in ('--project', '--library'):
                switches.append(flag)
                index += 1
            else:
                options[flag] = extra[index + 1]
                index += 2
        command = [self.compiler, 'build', self.source]
        for flag, value in options.items():
            command.extend([flag, value])
        command.extend(switches)
        result = invoke(command, env=self.env, cwd=self.directory)
        if failure:
            assert result.returncode != 0, (command, result.stdout)
            return result
        assert result.returncode == 0, (command, result.stderr.decode(errors='replace'))
        report = json.loads(result.stdout)
        assert report['version'] == 'qbe-build-v1', report
        assert all(report[key] >= 0 for key in ('frontend_seconds', 'codegen_seconds', 'link_seconds'))
        return report

    def execute(self, expected, *, options=(), env=None):
        result = checked([self.output, '--print-result', *options], env=env or self.env, cwd=self.directory)
        assert result.stdout == expected, result
        return result

    def snapshot(self):
        return (self.output.read_bytes(), self.manifest.read_bytes())

    @property
    def manifest(self):
        return self.output.with_name(self.output.name + '.qbe-manifest.json')


def keys(report):
    return {unit['name']: unit['key'] for unit in report['functions']}


def cache_acceptance(builder):
    builder.source.write_text('def square(x: i64) -> i64:\n    return x * x\n\n\n'
                              'def main() -> i64:\n    return square(4)\n')
    initial = builder.build()
    assert (initial['compiled_functions'], initial['reused_functions']) == (2, 0), initial
    builder.execute(b'16\n')
    previous_stat = builder.output.stat()
    repeat = builder.build()
    assert (repeat['compiled_functions'], repeat['reused_functions']) == (0, 2), repeat
    assert not repeat['output_changed'], repeat
    assert builder.output.stat().st_mtime_ns == previous_stat.st_mtime_ns
    assert keys(initial) == keys(repeat)

    builder.source.write_text('def square(x: i64) -> i64:\n    return x * x + 1\n\n\n'
                              'def main() -> i64:\n    return square(4)\n')
    edited = builder.build()
    assert (edited['compiled_functions'], edited['reused_functions']) == (1, 1), edited
    assert sum(keys(initial)[name] == key for name, key in keys(edited).items()) == 1
    builder.execute(b'17\n')
    cold = builder.build('--cache-dir', builder.directory / 'cold cache')
    assert cold['compiled_functions'] == 2, cold
    builder.execute(b'17\n')

    builder.source.write_text('# Formatting and declaration order are not native inputs.\n'
                              'def main() -> i64:\n'
                              '    return square(4)\n'
                              '\n'
                              'def square(x:i64)->i64:\n'
                              '    return x*x+1\n')
    reordered = builder.build()
    assert reordered['compiled_functions'] == 0 and keys(reordered) == keys(edited), reordered
    damaged = Path(reordered['functions'][0]['object'])
    damaged.write_bytes(b'invalid object bytes')
    repaired = builder.build()
    assert (repaired['compiled_functions'], repaired['reused_functions']) == (1, 1), repaired
    builder.execute(b'17\n')
    Path(repaired['functions'][0]['object']).with_suffix('.digest').write_bytes(b'\xff')
    repaired_checksum = builder.build()
    assert repaired_checksum['compiled_functions'] == 1, repaired_checksum
    builder.execute(b'17\n')
    runtime_archive_acceptance(builder)

    release = builder.build('--mode', 'ReleaseFast')
    assert release['compiled_functions'] == 2 and keys(release) != keys(repaired), release
    builder.execute(b'17\n')
    builder.source.write_text('def main() -> i64:\n    return 19\n')
    deleted = builder.build()
    assert len(deleted['functions']) == 1, deleted
    assert len(json.loads(builder.manifest.read_text())['functions']) == 1
    builder.execute(b'19\n')
    before = builder.snapshot()
    builder.source.write_text('def main() -> i64:\n    return True\n')
    assert builder.build(failure=True).returncode == 1
    assert builder.snapshot() == before
    builder.source.write_text('def main() -> i64:\n    return 20\n')
    failing = builder.directory / 'failing qbe'
    failing.write_text('#!/bin/sh\nexit 1\n')
    failing.chmod(0o700)
    assert builder.build('--qbe', failing, failure=True).returncode == 2
    assert builder.snapshot() == before
    bad_provider = builder.directory / 'invalid provider.c'
    bad_provider.write_text('This is not valid C.\n')
    assert builder.build('--provider', bad_provider, failure=True).returncode == 2
    assert builder.snapshot() == before
    assert builder.build('--target', 'not-a-target', failure=True).returncode == 2
    assert builder.snapshot() == before


def runtime_archive_acceptance(builder):
    """The runtime links as one verified archive that damage rebuilds, not as loose objects."""
    cache = builder.cache
    archives = sorted(cache.glob('*.a'))
    assert len(archives) == 1 and len(archives[0].stem) == 64, archives
    reused = builder.build()
    assert reused['runtime_reused'] and reused['compiled_functions'] == 0, reused
    archives[0].write_bytes(b'not an archive')
    rebuilt = builder.build()
    assert not rebuilt['runtime_reused'] and rebuilt['compiled_functions'] == 0, rebuilt
    assert sorted(cache.glob('*.a')) == archives, sorted(cache.glob('*.a'))
    builder.execute(b'17\n')
    archives[0].with_suffix('.digest').write_bytes(b'\xff')
    repaired = builder.build()
    assert not repaired['runtime_reused'], repaired
    builder.execute(b'17\n')
    assert builder.build()['runtime_reused'], 'a repaired archive must be reusable again'
    builder.execute(b'17\n')


def runtime_tree_acceptance(builder):
    """The bundled runtime materializes once per content hash and is shared safely."""
    cache = builder.directory / 'shared runtime cache'
    builder.source.write_text('def main() -> i64:\n    return 11\n')
    builder.build('--cache-dir', cache)
    builder.execute(b'11\n')
    trees = sorted((cache / 'runtime').iterdir())
    assert len(trees) == 1 and len(trees[0].name) == 64, trees
    tree = trees[0]
    bundled = {path.relative_to(tree).as_posix() for path in tree.rglob('*') if path.is_file()}
    assert 'qbe_runtime.c' in bundled and 'qbe_runtime.h' in bundled and 'native_format.zig' in bundled
    assert not any(name.endswith('_test.zig') for name in bundled), sorted(bundled)[:20]
    assert 'sema.zig' not in bundled and not any(name.endswith('.my') and '/' not in name for name in bundled)
    # A second build reuses the published tree instead of extracting it again.
    marker = tree / 'reuse marker'
    marker.write_text('kept')
    reused = builder.build('--cache-dir', cache)
    assert reused['runtime_reused'] and marker.read_text() == 'kept', reused
    assert sorted((cache / 'runtime').iterdir()) == trees
    assert not list(cache.glob('.pending-*')) and not list((cache / 'runtime').glob('.pending-*'))
    concurrent_runtime_tree(builder, tree.name)


def concurrent_runtime_tree(builder, expected):
    """Builds racing in separate directories over one cache publish the tree atomically."""
    cache = builder.directory / 'concurrent cache'
    running = []
    for index in range(4):
        work = builder.directory / ('concurrent work %d' % index)
        work.mkdir()
        (work / 'main.my').write_text('def main() -> i64:\n    return %d\n' % (index + 1))
        command = [builder.compiler, 'build', 'main.my', '-o', 'program', '--qbe', builder.qbe,
                   '--zig', builder.zig, '--cache-dir', cache]
        running.append((work, subprocess.Popen(list(map(str, command)), stdout=subprocess.PIPE,
                                               stderr=subprocess.PIPE, env=builder.env, cwd=work)))
    for index, (work, process) in enumerate(running):
        _, errors = process.communicate(timeout=600)
        assert process.returncode == 0, (index, errors.decode(errors='replace'))
        result = checked([work / 'program'], env=builder.env, cwd=work)
        assert result.stdout == ('%d\n' % (index + 1)).encode(), result
    published = sorted(path.name for path in (cache / 'runtime').iterdir())
    assert published == [expected], published
    assert (cache / 'runtime' / expected / 'qbe_runtime.c').is_file()


def project_and_locations(builder):
    (builder.directory / 'left.my').write_text('module left\nexport value\n\n'
                                               'def value() -> i64:\n    return 10\n')
    (builder.directory / 'right.my').write_text('module right\nexport value\n\n'
                                                'def value() -> i64:\n    return 20\n')
    builder.source = builder.directory / 'main.my'
    builder.source.write_text('module main\nimport left\nimport right\n\n'
                              'def main() -> i64:\n    return left.value() + right.value()\n')
    project = builder.build('--project')
    assert len(project['functions']) == 3
    assert len({unit['symbol'] for unit in project['functions']}) == 3
    builder.execute(b'30\n')
    builder.source.write_text('module main\nimport right\nimport left\n\n'
                              'def main() -> i64:\n    return left.value() + right.value()\n')
    reordered = builder.build('--project')
    assert reordered['compiled_functions'] == 0 and keys(project) == keys(reordered), reordered
    divide = ('def divide(x: i64) -> i64:\n    return 10 // x\n\n\n'
              'def main() -> i64:\n    return divide(0)\n')
    builder.source.write_text(divide)
    old = builder.build()
    trapped = invoke([builder.output], env=builder.env, cwd=builder.directory)
    assert trapped.returncode != 0 and b'R_DIVISION_BY_ZERO' in trapped.stderr, trapped
    assert (str(builder.source) + ':2:').encode() in trapped.stderr, trapped.stderr
    builder.source.write_text('\n\n' + divide)
    moved = builder.build()
    assert moved['compiled_functions'] == 0 and keys(old) == keys(moved), moved
    assert not moved['metadata_reused'], moved
    trapped = invoke([builder.output], env=builder.env, cwd=builder.directory)
    assert (str(builder.source) + ':4:').encode() in trapped.stderr, trapped.stderr


def boundary_acceptance(builder):
    builder.source.write_text((ROOT / 'src/native_fixtures/composite.my').read_text())
    builder.build('--provider', ROOT / 'tests/native_host_composite.c')
    builder.execute(b'42\n')
    builder.execute(b'42\n', options=['--gc-stress'])
    builder.source.write_text(native_providers.SOURCES[0])
    builder.build('--provider', ROOT / 'tests/native_provider.c')
    external = builder.execute(b'-9223372036854775808\n', env=dict(builder.env,
                               TEST_CLOCK_STATUS='0', TEST_RANDOM_STATUS='0', TEST_MISSING='0'))
    assert b'provider-calls: 1 1\n' in external.stderr, external
    builder.source.write_text((ROOT / 'src/native_fixtures/composite.my').read_text())
    provider = builder.directory / 'trusted provider with spaces.c'
    provider.write_bytes((ROOT / 'tests/native_host_composite.c').read_bytes())
    builder.build('--provider', provider)
    builder.execute(b'42\n')
    rejected = invoke([builder.output], env=dict(builder.env, MYLANG_HOST_BAD='1'), cwd=builder.directory)
    assert rejected.returncode != 0 and b'R_HOST_CONTRACT' in rejected.stderr, rejected
    # Formatting includes the optional Zig formatter runtime object.
    builder.source.write_text('module main\ndef main() -> int:\n    return len(str(42))\n')
    builder.build('--project')
    builder.execute(b'2\n')
    builder.source.write_text(qbe_native_calls.SOURCE)
    library = builder.directory / 'native library.so'
    builder.build('--project', '--library', '-o', library)
    harness = builder.directory / 'embedding host.c'
    harness.write_text(qbe_native_calls.HOST)
    executable = builder.directory / 'embedding host'
    checked([builder.zig, 'cc', '-std=c11', '-I', ROOT / 'src', harness, library,
             '-Wl,-rpath,' + str(builder.directory), '-o', executable], env=builder.env, cwd=builder.directory)
    checked([executable], env=builder.env, cwd=builder.directory)


def temporary_runs(builder):
    command = [builder.compiler, 'build', builder.source, '--run', '--report',
               '--qbe', builder.qbe, '--zig', builder.zig, '--cache-dir', builder.cache]
    def run(extra=(), data=b''):
        result = subprocess.run(list(map(str, [*command, *extra])), input=data,
                                capture_output=True, timeout=240, env=builder.env,
                                cwd=builder.directory)
        reports = [json.loads(line) for line in result.stderr.splitlines()
                   if line.startswith(b'{"version":"qbe-build-v1"')]
        if reports:
            output = Path(reports[0]['output'])
            assert not output.exists() and not output.parent.exists(), output
            assert not output.with_name(output.name + '.qbe-manifest.json').exists()
        assert not list(builder.cache.glob('.pending-*'))
        return result, reports
    previous = builder.snapshot()
    builder.source.write_text('def square(x: i64) -> i64:\n    return x * x\n\n\n'
                              'def main() -> i64:\n    return square(9)\n')
    result, reports = run()
    assert result.returncode == 0 and result.stdout == b'81\n', result
    assert len(reports) == 1
    result, reports = run()
    assert result.returncode == 0 and reports[0]['compiled_functions'] == 0
    result, _ = run(['--', '--max-steps=1'])
    assert result.returncode == 1 and b'R_STEP_LIMIT' in result.stderr, result
    builder.source.write_text('def main() -> i64:\n    return 1 // 0\n')
    result, _ = run()
    assert result.returncode == 1 and b'R_DIVISION_BY_ZERO' in result.stderr, result
    builder.source.write_text('def main() -> i64:\n    return True\n')
    result, reports = run()
    assert result.returncode == 1 and not reports, result
    assert builder.snapshot() == previous
    builder.source.write_text('result T:\n    ok: i64,\n    err: i64\n\n\n'
                              'def main(c: clock_cap) -> i64:\n'
                              '    match clock_now[T](c):\n'
                              '        case T.ok(n):\n'
                              '            return n\n'
                              '        case T.err(e):\n'
                              '            return e\n')
    provider = builder.directory / 'run stdio.c'
    provider.write_text('#include "native_providers.h"\n#include <stdio.h>\n#include <signal.h>\n'
                        'static MylangClockResult read_clock(void *ctx){(void)ctx;int ch=getchar();'
                        'if(ch==33)raise(SIGTERM);puts("guest output");fputs("guest error\\n",stderr);'
                        'return (MylangClockResult){MYLANG_PROVIDER_OK,ch};}'
                        'MylangNativeProviders mylang_native_providers(void){return (MylangNativeProviders){.clock_now=read_clock};}')
    result, _ = run(['--provider', provider], b'A')
    assert result.returncode == 0 and result.stdout == b'guest output\n65\n', result
    assert b'guest error\n' in result.stderr, result
    result, _ = run(['--provider', provider], b'!')
    assert result.returncode == 143, result
    assert builder.snapshot() == previous


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', required=True)
    parser.add_argument('--zig', required=True)
    args = parser.parse_args()
    qbe, zig = shutil.which(args.qbe), shutil.which(args.zig)
    assert qbe and zig, 'QBE and the pinned Zig toolchain must be installed'
    with tempfile.TemporaryDirectory(prefix='mylang standalone $native build ') as temp:
        directory = Path(temp)
        compiler = directory / 'relocated mylang'
        shutil.copy2(args.compiler.resolve(), compiler)
        builder = Builder(directory, compiler, Path(qbe).resolve(), Path(zig).resolve())
        help_result = checked([compiler, 'build', '--help'], env=builder.env, cwd=directory)
        assert b'mylang build' in help_result.stdout + help_result.stderr, help_result
        cache_acceptance(builder)
        runtime_tree_acceptance(builder)
        project_and_locations(builder)
        boundary_acceptance(builder)
        temporary_runs(builder)
    print('mylang build: relocated executable, no Python PATH, cache reuse/recovery, shared content-addressed runtime trees under concurrent builds, atomic failure preservation, project diagnostics, JSON, providers, library APIs and temporary runs with inherited I/O, status and cleanup passed')


if __name__ == '__main__':
    main()
