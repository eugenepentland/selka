#!/usr/bin/env python3
"""Run every runnable arena, byte-string and I/O documentation example natively.

Each fenced ``mylang`` block of the selected documents, and the bundled examples
that exercise the same surfaces, is built with QBE and compared against fresh VM
execution: same standard output, same exit status, same trap code.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from docs_examples import directives, fences, group, options, plan, project_shaped, write
from qbe_parity import ROOT, signature

DOCUMENTS = ('docs/arenas.md', 'docs/bytes.md', 'docs/io.md', 'docs/text.md')
EXAMPLES = ('examples/arena-managed/main.my', 'examples/python-bytes/main.my')


def units():
    """Every runnable documentation unit, plus the bundled example programs."""
    found = []
    for name in DOCUMENTS:
        blocks = [directives(fence) for fence in fences(name, (ROOT / name).read_text())]
        for unit in group([fence for fence in blocks if fence.tag in ('mylang', 'my')]):
            if plan(unit)['action'] == 'run':
                found.append(unit)
    return found


def invoke(command, cwd=None):
    return subprocess.run(list(map(str, command)), capture_output=True, timeout=300, cwd=cwd)


def build(args, source, output, cache, project):
    command = [sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output, '--compiler', args.compiler,
               '--qbe', args.qbe, '--zig', args.zig, '--cache-dir', cache]
    return invoke(command + (['--project'] if project else []))


def compare(args, label, entry, project, argv, cache):
    """Build one entry natively and match it against fresh VM execution.

    A native executable always reports the entry point's result, so the VM side
    always asks for it too; everything else is the example's own output.
    """
    output = cache.parent / 'program'
    built = build(args, entry, output, cache, project)
    assert built.returncode == 0, (label, built.stderr.decode(errors='replace'))
    command = 'run-project' if project else 'run'
    grants = [value for value in argv if value != '--print-result']
    vm = invoke([args.compiler, command, entry, '--print-result', *grants])
    native = invoke([output, *grants])
    assert signature(vm) == signature(native), (label, argv, vm.stdout, vm.stderr, native.stdout, native.stderr)


def schematic(args, temp):
    """Lower the schematic guest natively.

    Its host functions are registered by a VM host, so the application is checked
    rather than linked: every module and the guest's own `Result[None, int]` entry
    must reach native QBE units, including the byte-string and managed-text code
    the application leans on.
    """
    work = temp / 'schematic'
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    modules = []
    for path in sorted((ROOT / 'src/schematic/guest').glob('*.my')):
        if path.name == 'main.my':
            continue
        shutil.copy(path, work / path.name)
        modules.append(path.stem)
    for module in modules:
        (work / 'main.my').write_text(f'module main\nimport {module}\n\ndef main() -> int:\n    return 0\n')
        emitted = invoke([args.compiler, 'emit-project-qbe', work / 'main.my'])
        assert emitted.returncode == 0, (module, emitted.stderr.decode(errors='replace'))
    # The guest's own entry returns Result[None, int] and reaches native units too.
    entry = invoke([args.compiler, 'emit-project-qbe', ROOT / 'src/schematic/guest/main.my'])
    assert entry.returncode == 0, entry.stderr.decode(errors='replace')
    return len(modules) + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    count = 0
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-docs-') as directory:
        temp = Path(directory)
        cache = temp / 'cache'
        for index, unit in enumerate(units()):
            work = temp / f'unit{index}'
            shutil.rmtree(work, ignore_errors=True)
            entry = write(unit, work)
            project = project_shaped(unit, entry)
            compare(args, unit.label, entry, project, options(unit, 'run'), cache)
            count += 1
        for name in EXAMPLES:
            entry = ROOT / name
            project = entry.read_text().lstrip().startswith('module ')
            compare(args, name, entry, project, ['--print-result'], cache)
            count += 1
        modules = schematic(args, temp)
    print(f'QBE documentation parity: {count} runnable examples matched the VM, {modules} schematic guest modules lowered')


if __name__ == '__main__':
    main()
