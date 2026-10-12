#!/usr/bin/env python3
"""Fresh ownership cache qualification; never writes historical experiment paths.

Normal use admits each compiler process. A09 may run the whole script inside an
exclusive timing window with --admission held; never nest admission. --scaling
adds generated match/field/recursive/module/generic workloads. Reports retain
failed cases and separate compiler stage times from process elapsed/RSS.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

BASE = "fbfcaa7a923186a8e773c3760f81c10aa345a432"
ROOT = Path(__file__).resolve().parents[3]
VALID = '''import dep
func main(out: Stream) -> int:
    mut original = dep.values(7)
    const saved = original.copy()
    original.clear()
    out.print(len(saved), saved[1])
    return 0
'''
INVALID = VALID.replace('original.copy()', 'original')
DEP = '''public func values(n: int) -> int[]:
    return [n, n + 1, n + 2]
'''
MODES = {"rc": [], "single": ["--experimental-single-owner"], "zero": ["--experimental-zero-rc"]}
RC_TOKENS = ("@myl_core_retain", "@myl_core_release", "@myl_core_share(", "@myl_core_free_block(", "load atomic i32")


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def parse_report(stderr):
    for line in reversed(stderr.splitlines()):
        if line.startswith('{"version":"cache-report-v1"'):
            return json.loads(line)
    return None


class Run:
    def __init__(self, args):
        self.args = args
        self.work = args.work.resolve()
        self.out = args.output.resolve()
        if (self.out / 'results.json').exists():
            raise ValueError('Choose an unused evidence output directory')
        self.out.mkdir(parents=True, exist_ok=True)
        self.work.mkdir(parents=True, exist_ok=True)
        self.rows = []
        self.harness_sha256 = digest(__file__)
        self.env = dict(os.environ)
        for name in ("MYLANG_FRONTEND_CACHE", "MYLANG_TEST_SHARED_CACHE", "SOURCE_DATE_EPOCH", "ZERO_AR_DATE"):
            self.env.pop(name, None)
        self.env.update(MYLANG_COMPILER_SHARED_CACHE=str(self.work / 'shared'), MYLANG_CORE_RUNTIME_CACHE=str(self.work / 'objects'))

    def build(self, name, project, mode="zero", expected="3 8\n", refuse=False, extra=(), compiler=None, emit=True, retired_flag=None):
        target = self.work / 'bin' / name
        target.parent.mkdir(exist_ok=True)
        llvm = target.with_suffix('.ll')
        rss = target.with_suffix('.rss')
        mode_flags = [] if mode == 'zero' and (self.args.default_zero or (compiler is not None and self.args.candidate_default_zero)) else MODES[mode]
        arguments = [str(compiler or self.args.compiler), 'build', str(project / 'main.my'), '-o', str(target), '--cache-dir', str(project / 'cache'), '--release', '--zig', str(self.args.zig), '--report', *(['--emit-llvm', str(llvm)] if emit else []), *mode_flags, *extra]
        tree_rss = target.with_suffix('.tree-rss.json')
        measured = ['/usr/bin/time', '-f', '%M', '-o', str(rss), *arguments]
        if self.args.memory_wrapper:
            measured = ['python3', str(self.args.memory_wrapper.resolve()), '--output', str(tree_rss), '--', *measured]
        measured = ['/usr/bin/timeout', str(self.args.timeout), *measured]
        if self.args.admission == 'build':
            measured = [str(ROOT / 'scripts/build-slot.sh'), 'build', *measured]
        before = time.perf_counter_ns()
        try:
            result = subprocess.run(measured, cwd=project, env=self.env, capture_output=True, text=True)
            status, stdout, stderr = result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired as error:
            status, stdout, stderr = 124, error.stdout or '', error.stderr or ''
            if isinstance(stdout, bytes): stdout = stdout.decode(errors='replace')
            if isinstance(stderr, bytes): stderr = stderr.decode(errors='replace')
        elapsed = time.perf_counter_ns() - before
        report = parse_report(stderr)
        execution = None
        if status == 0:
            guest = subprocess.run([str(target)], cwd=project, env=self.env, capture_output=True, text=True, timeout=30)
            execution = dict(status=guest.returncode, stdout=guest.stdout, stderr=guest.stderr, expected=expected)
        clean = None
        if status == 0 and mode == 'zero' and emit:
            clean = not any(token in llvm.read_text() for token in RC_TOKENS)
        refusal_code = refuse if isinstance(refuse, str) else 'E_SINGLE_OWNER_MOVED' if refuse else None
        ok = status != 0 and refusal_code in stderr if refusal_code else status == 0 and execution['status'] == 0 and execution['stdout'] == expected and clean is not False
        if retired_flag:
            diagnostic = stderr.lower()
            ok = status == 2 and retired_flag in stderr and ('retired' in diagnostic or 'checked ownership is the default; drop the flag' in diagnostic)
        row = dict(name=name, mode=mode, arguments=arguments, status=status, expected_refusal=bool(refuse or retired_flag), passed=ok, report=report, execution=execution, llvm_rc_clean=clean, elapsed_ns=elapsed, elapsed_includes_admission_wait=self.args.admission != 'held', max_rss_kib=rss.read_text().strip().splitlines()[-1] if rss.exists() else None, compiler_sha256=digest(compiler or self.args.compiler), compiler_source_revision=self.args.candidate_revision if compiler else self.args.source_revision, sources={str(p.relative_to(project)):digest(p) for p in project.rglob('*.my')}, binary_sha256=digest(target) if status == 0 else None, llvm_sha256=digest(llvm) if status == 0 and emit else None)
        row['expected_refusal_code'] = refusal_code
        row['outcome'] = ('completed' if execution and execution['status'] == 0 else 'guest_failure') if status == 0 else 'compile_timeout' if status == 124 else 'source_refusal' if 'error[E_' in stderr else 'compiler_failure'
        if status == 0 and (name.endswith('-replay') or name == 'whole-build-replay'):
            row['passed'] &= report is not None and report['program'] == 'replayed'
        row['memory_instrumented'] = self.args.memory_wrapper is not None
        if tree_rss.exists():
            row['process_tree_rss'] = json.loads(tree_rss.read_text())
        self.rows.append(row)
        write(self.out / (name + '.stdout'), stdout)
        write(self.out / (name + '.stderr'), stderr)
        self.save()
        print(json.dumps({k:row[k] for k in ('name','status','passed','elapsed_ns','max_rss_kib')}), flush=True)
        return row

    def retired(self):
        project = self.work / 'retired-flags'
        write(project / 'main.my', VALID)
        write(project / 'dep.my', DEP)
        for selector in ('--experimental-single-owner', '--experimental-zero-rc'):
            self.build('retired-' + selector.removeprefix('--experimental-'), project, extra=(selector,), compiler=self.args.candidate, emit=False, retired_flag=selector)

    def save(self):
        write(self.out / 'results.json', json.dumps(dict(base=BASE, harness_sha256=self.harness_sha256, source_revision=self.args.source_revision, compiler=str(self.args.compiler), compiler_sha256=digest(self.args.compiler), admission=self.args.admission, rss_scope='GNU time maximum child process RSS, not summed process-tree peak', stage_times='report.stages.nanoseconds; frontend_phases may be inclusive', cases=self.rows, all_passed=all(r['passed'] for r in self.rows)), indent=2)+'\n')

    def caches(self):
        project = self.work / 'cache-project'
        write(project / 'main.my', VALID)
        write(project / 'dep.my', DEP)
        sequence = ('rc','zero','single','zero','rc','single') if not self.args.zero_only else ('zero','zero')
        for index, mode in enumerate(sequence):
            self.build(f'mode-{index}-{mode}', project, mode)
        self.build('zero-oracle', project, extra=('--no-cache',))
        self.build('whole-build-receipt', project, emit=False)
        self.build('whole-build-replay', project, emit=False)
        # Same private cache: an accepted RC program must not stand in for a
        # source ownership check, including after its syntax/body were cached.
        write(project / 'main.my', INVALID)
        if not self.args.zero_only:
            self.build('invalid-under-rc', project, mode='rc')
        self.build('invalid-owner-edit', project, refuse=True, emit=False)
        self.build('invalid-owner-edit-warm', project, refuse=True, emit=False)
        write(project / 'main.my', VALID)
        self.build('valid-owner-restored', project)
        write(project / 'dep.my', DEP.replace('n + 1', 'n + 9'))
        self.build('dependency-edit', project, expected='3 16\n')
        self.build('dependency-edit-warm', project, expected='3 16\n')
        write(project / 'dep.my', DEP)
        self.build('dependency-restored', project)
        relocated = self.work / 'relocated'
        write(relocated / 'main.my', VALID)
        write(relocated / 'dep.my', DEP)
        self.build('source-relocated', relocated)
        self.build('source-relocated-warm', relocated)
        if self.args.candidate:
            self.build('candidate-over-old-artifacts', project, compiler=self.args.candidate)
            self.build('candidate-over-old-artifacts-warm', project, compiler=self.args.candidate)
            if not self.args.default_zero:
                invalid = self.work / 'candidate-over-old-rc-receipt'
                write(invalid / 'main.my', INVALID)
                write(invalid / 'dep.my', DEP)
                self.build('old-rc-invalid-owner-receipt', invalid, mode='rc', emit=False)
                self.build('candidate-refuses-old-rc-receipt', invalid, compiler=self.args.candidate, refuse=True, emit=False)
                self.build('candidate-refuses-old-rc-receipt-warm', invalid, compiler=self.args.candidate, refuse=True, emit=False)
                write(invalid / 'main.my', VALID)
                self.build('candidate-old-rc-receipt-source-fixed', invalid, compiler=self.args.candidate, emit=False)

    def abi(self):
        project = self.work / 'map-abi'
        write(project / 'main.my', 'import parallel\nfunc make(n: int) -> str:\n    return str(n)\nfunc main(out: Stream) -> int:\n    const values = parallel.map([1, 2, 3], make)\n    out.print(values[0], values[2])\n    return 0\n')
        self.build('map-abi-baseline', project, expected='1 3\n')
        self.build('map-abi-receipt', project, expected='1 3\n', emit=False)
        self.build('map-abi-replay', project, expected='1 3\n', emit=False)
        if self.args.candidate:
            row = self.build('map-abi-candidate-old-artifacts', project, expected='1 3\n', compiler=self.args.candidate)
            if row['status'] == 0 and digest(self.args.compiler) != digest(self.args.candidate):
                row['passed'] &= row['report']['stages']['lowering']['reused'] == 0
                self.save()
            self.build('map-abi-candidate-receipt', project, expected='1 3\n', compiler=self.args.candidate, emit=False)
            self.build('map-abi-candidate-replay', project, expected='1 3\n', compiler=self.args.candidate, emit=False)

    def scaling(self):
        for family in self.args.families:
            for size in self.args.sizes:
                project = self.work / f'{family}-{size}'
                sources, expected = generate(family, size)
                for name, source in sources.items(): write(project / name, source)
                self.env['MYLANG_COMPILER_SHARED_CACHE'] = str(project / 'shared')
                self.env['MYLANG_CORE_RUNTIME_CACHE'] = str(project / 'objects')
                for phase in ('cold', 'warm', 'receipt', 'replay'):
                    self.build(f'{family}-{size}-{phase}', project, expected=expected, emit=phase in ('cold','warm'))
                source = (project / 'main.my').read_text()
                write(project / 'main.my', source.replace('out.print(', 'out.print(1 + ', 1))
                self.build(f'{family}-{size}-edit', project, expected=str(int(expected.strip())+1)+'\n', emit=False)

    def render_abi(self):
        project = self.work / 'render-abi'
        source = '''record RenderLabel:
    number: int
    word: str
func main(out: Stream) -> int:
    const value = RenderLabel(number=7, word="word-" + str(7))
    out.print(f"{value}")
    return 0
'''
        expected = "RenderLabel(number=7, word='word-7')\n"
        write(project / 'main.my', source)
        mode = 'zero' if self.args.default_zero else 'rc'
        self.build('render-abi-baseline', project, mode=mode, expected=expected)
        self.build('render-abi-receipt', project, mode=mode, expected=expected, emit=False)
        self.build('render-abi-replay', project, mode=mode, expected=expected, emit=False)
        if self.args.candidate:
            row = self.build('render-abi-candidate-old-artifacts', project, expected=expected, compiler=self.args.candidate)
            if row['status'] == 0 and digest(self.args.compiler) != digest(self.args.candidate):
                row['passed'] &= row['report']['stages']['lowering']['reused'] == 0
                self.save()
            self.build('render-abi-candidate-receipt', project, expected=expected, compiler=self.args.candidate, emit=False)
            self.build('render-abi-candidate-replay', project, expected=expected, compiler=self.args.candidate, emit=False)

    def result_cache(self):
        """Keep old source refusals and new Result obligations in the same cache."""
        project = self.work / 'result-cache'
        valid = self.args.result_source.read_text()
        invalid = self.args.result_negative.read_text()
        expected = self.args.result_output.read_text()
        write(project / 'main.my', valid)
        self.build('result-old-compiler-refusal', project, refuse=self.args.result_baseline_refusal, emit=False)
        row = self.build('result-candidate-old-refusal', project, compiler=self.args.candidate, expected=expected)
        if row['status'] == 0:
            row['passed'] &= row['report']['stages']['lowering']['reused'] == 0
            self.save()
        self.build('result-candidate-receipt', project, compiler=self.args.candidate, expected=expected, emit=False)
        self.build('result-candidate-replay', project, compiler=self.args.candidate, expected=expected, emit=False)
        write(project / 'main.my', invalid)
        self.build('result-candidate-unhandled-edit', project, compiler=self.args.candidate, refuse='E_RESULT_UNHANDLED', emit=False)
        self.build('result-candidate-unhandled-edit-warm', project, compiler=self.args.candidate, refuse='E_RESULT_UNHANDLED', emit=False)
        write(project / 'main.my', valid)
        self.build('result-candidate-handling-restored', project, compiler=self.args.candidate, expected=expected, emit=False)


def generate(family, size):
    """Deterministic, source-level scaling; ownership checks stay enabled."""
    if family == 'matches':
        lines = ['enum Bundle:', '    parts(value: int[], ignored: str[])', '', 'func make(n: int) -> Bundle:', '    return Bundle.parts(value=[n], ignored=[str(n)])', '', 'func nested(n: int) -> int:']
        indent = '    '
        for i in range(size):
            lines += [indent+f'match make(n + {i}):', indent+f'    case Bundle.parts(value=v{i}, ignored=_):']
            indent += '        '
        lines += [indent+f'return v{size-1}[0]', '', 'func main(out: Stream) -> int:', '    out.print(nested(1))', '    return 0', '']
        return {'main.my':'\n'.join(lines)}, f'{size}\n'
    if family == 'fields':
        fields = [f'f{i}' for i in range(size)]
        text = 'record Wide:\n'+''.join(f'    {f}: int[]\n' for f in fields)+'\nfunc main(out: Stream) -> int:\n    const value = Wide('+', '.join(f'{f}=[{i}]' for i,f in enumerate(fields))+')\n    out.print('+ ' + '.join(f'value.{f}[0]' for f in fields)+')\n    return 0\n'
        return {'main.my':text}, f'{size*(size-1)//2}\n'
    if family == 'recursive':
        text = 'enum Tree:\n    leaf(value: str)\n    next(child: Tree)\n\nfunc score(tree: Tree) -> int:\n    match tree:\n        case Tree.leaf(value=value):\n            return len(value)\n        case Tree.next(child=child):\n            return 1 + score(child)\n\nfunc main(out: Stream) -> int:\n    const tree = '+('Tree.next(child='*size)+'Tree.leaf(value="x")'+(')'*size)+'\n    out.print(score(tree))\n    return 0\n'
        return {'main.my':text}, f'{size+1}\n'
    if family == 'modules':
        sources = {}
        for i in range(size):
            prefix = f'import m{i-1}\n' if i else ''
            value = f'm{i-1}.value(n) + 1' if i else 'n + 1'
            sources[f'm{i}.my'] = prefix + f'public func value(n: int) -> int:\n    return {value}\n'
        sources['main.my'] = f'import m{size-1}\nfunc main(out: Stream) -> int:\n    out.print(m{size-1}.value(0))\n    return 0\n'
        return sources, f'{size}\n'
    text = 'func identify[T](value: T) -> T:\n    return value\n\n'
    for i in range(size): text += f'record R{i}:\n    value: int\n\n'
    text += 'func main(out: Stream) -> int:\n'
    for i in range(size): text += f'    const v{i} = identify[R{i}](R{i}(value={i}))\n'
    text += '    out.print('+' + '.join(f'v{i}.value' for i in range(size))+')\n    return 0\n'
    return {'main.my':text}, f'{size*(size-1)//2}\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--candidate', type=Path)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--admission', choices=('build','held'), default='build')
    parser.add_argument('--scaling', action='store_true')
    parser.add_argument('--scaling-only', action='store_true')
    parser.add_argument('--abi-only', action='store_true')
    parser.add_argument('--result-only', action='store_true')
    parser.add_argument('--render-only', action='store_true')
    parser.add_argument('--result-source', type=Path)
    parser.add_argument('--result-negative', type=Path)
    parser.add_argument('--result-output', type=Path)
    parser.add_argument('--result-baseline-refusal', default='E_COLLECTION_ELEMENT')
    parser.add_argument('--families', nargs='+', choices=('matches','fields','recursive','modules','generics'), default=['matches','fields','recursive','modules','generics'])
    parser.add_argument('--source-revision', default=BASE)
    parser.add_argument('--memory-wrapper', type=Path)
    parser.add_argument('--candidate-revision')
    parser.add_argument('--sizes', type=int, nargs='+', default=[8,16,32,64])
    parser.add_argument('--zero-only', action='store_true')
    parser.add_argument('--default-zero', action='store_true')
    parser.add_argument('--candidate-default-zero', action='store_true')
    parser.add_argument('--retired-flags', action='store_true')
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.zig = args.zig.resolve()
    if args.candidate:
        args.candidate = args.candidate.resolve()
        if not args.candidate_revision: parser.error('--candidate requires --candidate-revision')
    if args.retired_flags and not (args.default_zero or (args.candidate and args.candidate_default_zero)):
        parser.error('--retired-flags requires default checked ownership for the selected final compiler')
    if args.result_only and not args.result_source:
        parser.error('--result-only requires --result-source')
    if args.result_source and not (args.candidate and args.result_negative and args.result_output):
        parser.error('--result-source requires --candidate, --result-negative and --result-output')
    run = Run(args)
    if not args.scaling_only and not args.abi_only and not args.result_only and not args.render_only: run.caches()
    if not args.scaling_only and not args.result_only and not args.render_only: run.abi()
    if args.render_only: run.render_abi()
    if args.result_source: run.result_cache()
    if args.scaling or args.scaling_only: run.scaling()
    if args.retired_flags: run.retired()
    raise SystemExit(0 if all(row['passed'] for row in run.rows) else 1)

if __name__ == '__main__':
    main()
