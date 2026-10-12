import argparse, hashlib, json, os, re, subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--case', required=True)
p.add_argument('--controls', action='store_true')
p.add_argument('--ordinary-only', action='store_true')
p.add_argument('--expected-output', type=Path)
args = p.parse_args()
here = Path(__file__).resolve().parent
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
compiler = args.compiler.resolve()
source = here / 'sources' / (args.case + '.my')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = {'compiler': str(compiler), 'compiler_sha256': sha(compiler),
          'source': str(source), 'source_sha256': sha(source), 'runs': []}
expected = args.expected_output.read_text() if args.expected_output else ''


def run(argv, env=None):
    argv = list(map(str, argv))
    p = subprocess.run(argv, capture_output=True, text=True, env=env, timeout=90)
    return {'argv': argv, 'status': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}


def save():
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')


if args.controls:
    result['zero_check'] = run([compiler, 'check', source, '--experimental-zero-rc'])
    modes = [('ordinary_release', [], ['--release'])]
else:
    modes = [(name, ['--experimental-zero-rc'], flags) for name, flags in [
        ('release', ['--release']), ('debug', ['--unoptimized']),
        ('verified_release', ['--release', '--verify-facts']),
        ('optimized_debug', ['--optimize-debug']), ('no_facts', ['--release', '--no-facts'])]]
    modes += [('ordinary_release', [], ['--release']), ('ordinary_debug', [], ['--unoptimized'])]
    if args.ordinary_only:
        modes = [mode for mode in modes if not mode[1]]
for name, ownership, flags in modes:
    directory = out / name
    directory.mkdir()
    binary = directory / 'program'
    llvm = directory / 'program.ll'
    counts = directory / 'counts.json'
    row = {'mode': name}
    result['runs'].append(row)
    row['build'] = run([compiler, 'build', source, *ownership, *flags, '--counters',
                        '--emit-llvm', llvm, '--cache-dir', directory / 'cache', '-o', binary])
    if row['build']['status'] == 0:
        row['binary_sha256'] = sha(binary)
        row['llvm_sha256'] = sha(llvm)
        row['run'] = run([binary], dict(os.environ, MYLANG_COUNTERS=str(counts), MYL_CORE_LEAKCHECK='1'))
        if counts.exists():
            counted = json.loads(counts.read_text())
            row['totals'] = counted['totals']
            row['rc_sites'] = [site for site in counted['sites']
                               if site['kind'] in ['retain', 'release', 'unique_test', 'uniqueness'] and site['count']]
        if ownership:
            row['legacy_llvm'] = re.findall(r'@myl_core_(?:retain|release|share)[A-Za-z_0-9]*', llvm.read_text())
        if not args.controls:
            row['pass'] = row['run']['status'] == 0 and row['run']['stdout'] == expected and row['run']['stderr'] == ''
            if ownership:
                row['pass'] &= not row['legacy_llvm'] and not row['rc_sites']
                row['pass'] &= all(row['totals'][k] == 0 for k in ['live_bytes_at_exit', 'runtime_retains',
                    'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks'])
    elif not args.controls:
        row['pass'] = False
    save()
    print(args.case, name, row.get('pass', row['build']['status']), flush=True)
if not args.controls:
    result['pass'] = all(row['pass'] for row in result['runs'])
save()
raise SystemExit(0 if args.controls or result['pass'] else 1)
