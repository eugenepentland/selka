#!/usr/bin/env python3
"""Manual isolated exchange verification after complete compiler installation."""
import argparse, hashlib, json, os, pathlib, subprocess, time
P=pathlib.Path
p=argparse.ArgumentParser();p.add_argument('--compiler',type=P,required=True);p.add_argument('--root',type=P,required=True);p.add_argument('--output',type=P,required=True);a=p.parse_args()
assert os.environ.get('MYLANG_ADMISSION_KIND')=='build', 'invoke under one outer build-slot build lease'
a.output.mkdir(parents=True,exist_ok=False);work=a.root/'.tmp/lox-eda-parity/P7'/a.output.name;work.mkdir(parents=True,exist_ok=False)
rows=[]
(a.output/'outer-lease.json').write_text(json.dumps({'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR'],'pid':os.getpid()},indent=2)+'\n')
source_pins={str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted((a.root/'src').rglob('*')) if path.is_file()}
install=a.compiler.resolve().parents[1]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
installation={str(path):digest(path) for path in sorted(install.rglob('*')) if path.is_file()}
def run(name,argv,env=None,expected=0):
    assert all(digest(P(path))==identity for path,identity in installation.items()), 'installation changed during verification'
    if 'fixture_identity' in globals():assert digest(fixture)==fixture_identity, 'fixture changed during verification'
    clean_env={**os.environ,'MYLANG_JOBS':'4'};clean_env.pop('MYLANG_COUNTERS',None);clean_env.pop('MYL_CORE_LEAKCHECK',None)
    start=time.monotonic();r=subprocess.run(list(map(str,argv)),cwd=a.root,env=env if env is not None else clean_env,capture_output=True)
    (a.output/(name+'.stdout')).write_bytes(r.stdout);(a.output/(name+'.stderr')).write_bytes(r.stderr)
    rows.append({'name':name,'argv':list(map(str,argv)),'returncode':r.returncode,'elapsed_including_admission':time.monotonic()-start});(a.output/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
    assert r.returncode==expected,(name,r.stdout,r.stderr);return r
fixture=a.root/'src/core/list_exchange_fixture.my'
fixture_identity=digest(fixture)
(a.output/'inputs-before.json').write_text(json.dumps({'installation':installation,'fixture':str(fixture),'fixture_sha256':fixture_identity,'compiler_source_files':source_pins,'verifier_sha256':digest(P(__file__))},indent=2)+'\n')
for mode,flags in {'release':['--release'],'debug':['--unoptimized'],'verified':['--release','--verify-facts'],'optimized-debug':['--optimize-debug'],'no-facts':['--release','--no-facts']}.items():
    binary=work/mode;llvm=work/(mode+'.ll');counts=work/(mode+'.counts.json')
    run(mode+'-build',[a.compiler,'build',fixture,'--experimental-zero-rc','--counters',*flags,'--cache-dir',work/('cache-'+mode),'--emit-llvm',llvm,'-o',binary])
    env={**os.environ,'MYLANG_COUNTERS':str(counts),'MYL_CORE_LEAKCHECK':'1'};r=run(mode+'-run',[binary],env);assert r.stdout==b'exchange passed\n' and not r.stderr
    counted=json.loads(counts.read_text());totals=counted['totals'];assert all(totals[k]==0 for k in ['live_bytes_at_exit','runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks'])
    assert all(counted['kinds'][k]['count']==0 for k in ['retain','release','unique_test'])
    emitted=llvm.read_text();assert all(symbol not in emitted for symbol in ['@myl_core_retain(', '@myl_core_release(', '@myl_core_share('])
    for case in ['negative','positive','empty','unsigned-max']:
        r=run(mode+'-'+case,[binary,case],expected=1);assert b'error[R_LIST_BOUNDS]' in r.stderr
# Legacy RC exchange must detach snapshots before returning the old child.
rc_source=work/'rc-snapshot.my'
rc_source.write_text('func main(out: Stream) -> int:\n    mut rows = [[1], [2]]\n    mut saved = rows.snapshot()\n    mut old = rows.exchange(-1, [7])\n    old.append(9)\n    saved[0].append(8)\n    assert old == [2, 9]\n    assert rows == [[1], [7]]\n    assert saved == [[1, 8], [2]]\n    out.print("RC exchange passed")\n    return 0\n')
for mode,flags in {'release':['--release'],'debug':['--unoptimized'],'verified':['--release','--verify-facts'],'optimized-debug':['--optimize-debug'],'no-facts':['--release','--no-facts']}.items():
    label='rc-snapshot-'+mode;binary=work/label;counts=work/(label+'.counts.json')
    run(label+'-build',[a.compiler,'build',rc_source,'--counters',*flags,'--cache-dir',work/('cache-'+label),'-o',binary])
    r=run(label+'-run',[binary],{**os.environ,'MYLANG_COUNTERS':str(counts),'MYL_CORE_LEAKCHECK':'1'})
    assert r.stdout==b'RC exchange passed\n' and not r.stderr
    assert json.loads(counts.read_text())['totals']['live_bytes_at_exit']==0
# Sibling branch pairing and discarded large unions use runtime selectors.
for fixture_name in ['list_exchange_sibling_fixture','list_exchange_sibling_zero_fixture','list_exchange_wide_discard_fixture']:
    review_source=a.root/'src/core'/(fixture_name+'.my')
    for mode,flags in {'release':['--release'],'debug':['--unoptimized'],'verified':['--release','--verify-facts'],'optimized-debug':['--optimize-debug'],'no-facts':['--release','--no-facts']}.items():
        for ownership,owned_flags in [('zero-rc',['--experimental-zero-rc']),('rc',[])]:
            label=fixture_name+'-'+mode+'-'+ownership;binary=work/label
            run(label+'-build',[a.compiler,'build',review_source,*owned_flags,'--counters',*flags,'--cache-dir',work/('cache-'+label),'-o',binary])
            for arguments in [[],['take']]:
                case=label+('-take' if arguments else '-else');counts=work/(case+'.counts.json')
                r=run(case+'-run',[binary,*arguments],{**os.environ,'MYLANG_JOBS':'4','MYLANG_COUNTERS':str(counts),'MYL_CORE_LEAKCHECK':'1'})
                assert not r.stderr
                counted=json.loads(counts.read_text());assert counted['totals']['live_bytes_at_exit']==0
                if ownership=='zero-rc':
                    assert all(counted['totals'][k]==0 for k in ['runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks'])
                    assert all(counted['kinds'][k]['count']==0 for k in ['retain','release','unique_test'])
# No allocation or live-memory slope from exchanging the same two child owners.
slope=[]
source=work/'slope.my';source.write_text('func main(args: str[], out: Stream) -> int:\n    mut iterations = 0\n    match parse_int(args[0]):\n        case Some(value):\n            iterations = value\n        case None:\n            return 2\n    mut xs = [[1, 2]]\n    mut donor = [3, 4]\n    mut i = 0\n    while i < iterations:\n        donor = xs.exchange(0, donor)\n        i += 1\n    out.print(xs[0][0], donor[0])\n    return 0\n')
binary=work/'slope'
run('slope-build',[a.compiler,'build',source,'--experimental-zero-rc','--counters','--release','--cache-dir',work/'cache-slope','-o',binary])
for iterations in [10,10000]:
    counts=work/(str(iterations)+'.counts.json')
    r=run(str(iterations)+'-run',[binary,str(iterations).zfill(5)],{**os.environ,'MYLANG_COUNTERS':str(counts),'MYL_CORE_LEAKCHECK':'1'})
    assert r.stdout==b'1 3\n' and not r.stderr
    slope.append(json.loads(counts.read_text())['totals'])
for key in ['allocs','reallocs','alloc_bytes','realloc_added_bytes','peak_live_bytes','live_bytes_at_exit']:assert slope[0][key]==slope[1][key],(key,slope)
(a.output/'allocation-slope.json').write_text(json.dumps({'iterations':[10,10000],'totals':slope},indent=2)+'\n')
(a.output/'identity.json').write_text(json.dumps({'compiler':str(a.compiler),'sha256':hashlib.sha256(a.compiler.read_bytes()).hexdigest(),'fixture_sha256':hashlib.sha256(fixture.read_bytes()).hexdigest()},indent=2)+'\n')
# The compiler must refuse replacement borrows, use-after-move, active aliases and dropped Results.
refusals={
 'mut-pending-overwrite':('func bad(mut values: Result[int, int][]) -> int:\n    values = [Ok(8)]\n    return 0\nfunc main() -> int:\n    mut pending: Result[int, int][] = [Ok(1)]\n    const ignored = bad(mut pending)\n    _ = pending\n    return ignored\n',b'E_RESULT_OVERWRITE'),
 'generic-pending-overwrite':('func bad[T: storable](mut values: T[], value: T) -> T:\n    values = []\n    return value\nfunc main() -> int:\n    return 0\n',b'E_RESULT_OVERWRITE'),
 'index-relocation':('func grow(mut xs: int[]) -> int:\n    xs.append(3)\n    return -1\nfunc main() -> int:\n    mut xs = [1, 2]\n    _ = xs.exchange(grow(mut xs), 9)\n    return 0\n',b'E_MUTATION_OVERLAP'),
 'replacement-relocation':('func replacement(mut xs: int[]) -> int:\n    xs.append(3)\n    return 9\nfunc main() -> int:\n    mut xs = [1, 2]\n    _ = xs.exchange(0, replacement(mut xs))\n    return 0\n',b'E_MUTATION_OVERLAP'),
 'borrow':('func main() -> int:\n    mut xs = [[1], [2]]\n    _ = xs.exchange(0, xs[1])\n    return 0\n',b'E_SINGLE_OWNER_BORROW'),
 'moved':('func main() -> int:\n    mut xs = [[1]]\n    const donor = [2]\n    _ = xs.exchange(0, donor)\n    return len(donor)\n',b'E_SINGLE_OWNER_MOVED'),
 'pending':('func main() -> int:\n    mut pending: Result[int, str][] = [Ok(1)]\n    pending.exchange(0, Ok(2))\n    _ = pending\n    return 0\n',b'E_EXPLICIT_DISCARD_REQUIRED'),
 'arity':('func main() -> int:\n    mut xs = [1]\n    _ = xs.exchange(0)\n    return 0\n',b'E_ARITY'),
 'type':('func main() -> int:\n    mut xs = [1]\n    _ = xs.exchange(0, "wrong")\n    return 0\n',b'E_CALL_ARGUMENT'),
}
for name,(source,code) in refusals.items():
    path=work/('refusal-'+name+'.my');path.write_text(source)
    r=run('refusal-'+name,[a.compiler,'build',path,'--experimental-zero-rc','--release','--cache-dir',work/('cache-refusal-'+name),'-o',work/('refusal-'+name)],expected=1)
    assert code in r.stderr,(name,r.stderr)

for name in ['remaining-result-refusal','generic-remaining-result-refusal','local-old-result-refusal']:
    original=a.root/'experiments/lox-eda-parity-20261013/P7/fixtures'/(name+'.my')
    private=work/(name+'.my');private.write_bytes(original.read_bytes())
    r=run(name,[a.compiler,'build',private,'--experimental-zero-rc','--release','--cache-dir',work/('cache-'+name),'-o',work/name],expected=1)
    assert b'E_RESULT_UNHANDLED' in r.stderr,(name,r.stderr)

inputs={str(path):digest(path) for path in sorted(work.glob('*.my'))}
inputs[str(fixture)]=digest(fixture)
for path in sorted((a.root/'src/core').glob('list_exchange_*fixture.my')):inputs[str(path)]=digest(path)
(a.output/'input-identities.json').write_text(json.dumps({'installation':installation,'sources':inputs,'verifier_sha256':digest(P(__file__))},indent=2)+'\n')
assert all(digest(P(path))==identity for path,identity in installation.items())
assert all(digest(P(path))==identity for path,identity in source_pins.items()), 'compiler source tree changed during verification'
