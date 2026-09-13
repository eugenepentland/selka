#!/usr/bin/env python3
"""Exercise default module/edge limits through checking, execution, and reporting."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def invoke(compiler, command, entry, *options, status=0, code=None):
    result = subprocess.run([compiler, command, str(entry), *options],
                            capture_output=True, text=True, timeout=90)
    assert result.returncode == status, (command, result.returncode, result.stderr)
    if code:
        assert f'error[{code}]' in result.stderr, result.stderr
        assert result.stdout == '', result.stdout
    return result


def chain(directory, count):
    for i in range(count):
        name = 'main' if i == 0 else f'm{i}'
        imports = f'import m{i + 1} as next\n' if i + 1 < count else ''
        exports = '' if i == 0 else 'export value\n'
        function = 'main' if i == 0 else 'value'
        expression = 'next.value() + 1' if imports else '1'
        (directory / f'{name}.my').write_text(
            f'module {name}\n{imports}{exports}def {function}() -> i64:\n'
            f'    return {expression}\n', encoding='utf-8')
    return directory / 'main.my'


def dense(directory, edge_count):
    remaining = edge_count
    for i in range(92):
        name = 'main' if i == 0 else f'm{i}'
        targets = list(range(i + 1, 92))[:remaining]
        remaining -= len(targets)
        imports = ''.join(f'import m{j}\n' for j in targets)
        function = 'main' if i == 0 else 'value'
        (directory / f'{name}.my').write_text(
            f'module {name}\n{imports}def {function}() -> i64:\n    return 0\n',
            encoding='utf-8')
    assert remaining == 0
    return directory / 'main.my'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = parser.parse_args().compiler
    with tempfile.TemporaryDirectory(prefix='mylang-module-scaling-') as temporary:
        root = Path(temporary)
        deep = root / 'deep'
        deep.mkdir()
        entry = chain(deep, 256)
        graph = invoke(compiler, 'list-modules', entry).stdout
        assert graph == invoke(compiler, 'list-modules', entry).stdout
        names = [line.split()[1] for line in graph.splitlines() if ' path=' in line]
        assert names == [f'm{i}' for i in range(255, 0, -1)] + ['main'], names
        invoke(compiler, 'check-project', entry)
        invoke(compiler, 'fmt-project', entry, '--check')
        quality = invoke(compiler, 'report-project-quality', entry).stdout
        assert quality.count('reachable-from-main=true') == 256, quality
        assert quality.count('module-exported=true') == 255, quality
        assert quality.count('  calls ') == 255, quality
        duplicates = invoke(compiler, 'discover-project-duplicates', entry, '--approximate',
                            '--min-nodes=1', '--max-work=1').stdout
        assert '0 candidate groups; 256/256 functions indexed' in duplicates, duplicates
        assert 'truncated=true' in duplicates, duplicates
        assert invoke(compiler, 'run-project', entry, '--print-result', '--max-frames=256').stdout == '256\n'
        limited = invoke(compiler, 'run-project', entry, '--max-frames=255',
                         status=1, code='R_FRAME_LIMIT')
        assert 'm254.my:5:' in limited.stderr, limited.stderr
        leaf = deep / 'm255.my'
        saved = leaf.read_text(encoding='utf-8')
        leaf.write_text(saved.replace('return 1', 'return 2'), encoding='utf-8')
        changed = invoke(compiler, 'list-modules', entry).stdout
        before = [line for line in graph.splitlines() if ' path=' in line]
        after = [line for line in changed.splitlines() if ' path=' in line]
        assert sum(a != b for a, b in zip(before, after)) == 1
        assert invoke(compiler, 'run-project', entry, '--print-result').stdout == '257\n'
        leaf.write_text(saved.replace('return 1', 'return True'), encoding='utf-8')
        invalid = invoke(compiler, 'check-project', entry, status=1)
        assert invalid.stdout == '' and 'm255.my:4:' in invalid.stderr, invalid.stderr
        for command in ('report-project-quality', 'discover-project-duplicates'):
            rejected = invoke(compiler, command, entry, status=1)
            assert rejected.stdout == '' and 'm255.my:4:' in rejected.stderr, rejected.stderr
        leaf.write_text(saved.replace('module m255', 'module m255\nimport main'), encoding='utf-8')
        cycle = invoke(compiler, 'check-project', entry, status=1, code='E_IMPORT_CYCLE')
        assert 'm255.my:2:' in cycle.stderr and 'main.my:1:' in cycle.stderr, cycle.stderr
        chain(deep, 257)
        invoke(compiler, 'check-project', entry, status=1, code='E_MODULE_LIMIT')
        print('module scaling: 256-module checking/execution/formatting, stable order, '
              'quality/duplicate reports, leaf edits/diagnostics, cycle/frame boundaries, '
              'and 257-module rejection passed')

        wide = root / 'dense'
        wide.mkdir()
        entry = dense(wide, 4096)
        graph = invoke(compiler, 'list-modules', entry).stdout
        assert graph.count(' path=') == 92, graph
        assert graph.count('  import ') == 4096
        assert graph == invoke(compiler, 'list-modules', entry).stdout
        invoke(compiler, 'check-project', entry)
        assert invoke(compiler, 'run-project', entry, '--print-result').stdout == '0\n'
        dense(wide, 4097)
        invoke(compiler, 'check-project', entry, status=1, code='E_IMPORT_LIMIT')
        print('module scaling: shared 92-module DAG at 4096 imports, deterministic '
              'report/execution, and 4097-import rejection passed')


if __name__ == '__main__':
    main()
