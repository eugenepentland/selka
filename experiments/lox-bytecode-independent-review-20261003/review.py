#!/usr/bin/env python3
"""Read-only source/receipt review; writes only this lane's review JSON."""
from collections import Counter
import difflib, gzip, hashlib, json, re, subprocess
from pathlib import Path

AUTHOR = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-bytecode-20261003')
AUTHOR_COMMIT = 'beaaf97c7397beafb0988f5ed73dde0bf4813ebb'
WORK = AUTHOR/'.tmp-lox-vm-bytecode-20261003'
ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
OUT = Path(__file__).resolve().parent
sha = lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
read = lambda p:json.loads(Path(p).read_text())
files = lambda p:{str(x.relative_to(p)):sha(x) for x in sorted(p.rglob('*')) if x.is_file()}
base = WORK/'control'
base37 = files(base)
assert len(base37) == 37 and base37 == files(ROOT/'.tmp-lox-next/combined')
expected_changed = ['chunk.my','compiler.my','compiler_test.my','driver_cases.json','driver_tests.my','vm.my']
sources = {}
for stage in ['octets-v2','octets-shape-v3']:
    path = WORK/stage
    descriptor = read(WORK/('source-'+stage+'.json'))
    current = files(path)
    assert len(current) == 37 and current == descriptor['source37']
    changed = sorted(k for k in current if current[k] != base37[k])
    assert changed == expected_changed
    patch = AUTHOR/'experiments/lox-vm-bytecode-20261003'/(stage+'.patch')
    actual = ''.join(''.join(difflib.unified_diff((base/k).read_text().splitlines(True),(path/k).read_text().splitlines(True),fromfile='a/'+k,tofile='b/'+k)) for k in changed)
    assert actual == patch.read_text()
    assert sha(patch) == descriptor['patch_sha256']
    sources[stage] = {'source':str(path),'source37':current,'changed_files':changed,'patch':str(patch),'patch_sha256':sha(patch),'descriptor_sha256':sha(WORK/('source-'+stage+'.json'))}

def text(stage,name): return (WORK/stage/name).read_text()
def replacement(value,old,new):
    assert value.count(old) == 1,old
    return value.replace(old,new)
chunk = replacement((base/'chunk.my').read_text(),'code: list[int]','code: list[u8]')
chunk = replacement(chunk,'target.code.append(byte)','target.code.append(u8(byte))')
assert chunk == text('octets-v2','chunk.my')
compiler = (base/'compiler.my').read_text()
for old,new in [('code.code[offset] = bit_and(shift_right(jump, 8), 255)','code.code[offset] = u8(bit_and(shift_right(jump, 8), 255))'),
                ('code.code[offset + 1] = bit_and(jump, 255)','code.code[offset + 1] = u8(bit_and(jump, 255))'),
                ('emit_bytes(mut p, chunk.OP_CALL, count)','emit_bytes(mut p, chunk.OP_CALL, bit_and(count, 255))')]:
    compiler = replacement(compiler,old,new)
assert compiler.count('emit_byte(mut p, count)') == 2
compiler = compiler.replace('emit_byte(mut p, count)','emit_byte(mut p, bit_and(count, 255))')
assert compiler == text('octets-v2','compiler.my')
vm = replacement((base/'vm.my').read_text(),'code: list[int]','code: list[u8]')
vm = replacement(vm,'byte = frame.code[frame.ip]','byte = int(frame.code[frame.ip])')
vm = replacement(vm,'return frame.code[frame.ip - 2] * 256 + frame.code[frame.ip - 1]','return int(frame.code[frame.ip - 2]) * 256 + int(frame.code[frame.ip - 1])')
vm = replacement(vm,'instruction = frame.code[frame.ip]','instruction = int(frame.code[frame.ip])')
assert vm == text('octets-v2','vm.my')
vm = replacement(vm,'        instruction = int(frame.code[frame.ip])','        opcode: u8 = frame.code[frame.ip]\n        instruction = int(opcode)')
assert vm == text('octets-shape-v3','vm.my')
assert [k for k in base37 if sources['octets-v2']['source37'][k] != sources['octets-shape-v3']['source37'][k]] == ['vm.my']
for stage in sources:
    drivers = text(stage,'driver_tests.my')
    assert drivers.startswith((base/'driver_tests.my').read_text())
    previous = read(base/'driver_cases.json')
    now = read(WORK/stage/'driver_cases.json')
    assert all(now[k] == v for k,v in previous.items())
    assert sorted(set(now)-set(previous)) == ['driver_tests::test_run_bytecode_argument_overflow','driver_tests::test_run_bytecode_big_endian_jumps','driver_tests::test_run_constant_operand_last_byte']
    provider = previous['driver_tests::test_run_callee_error_after_arguments']['providers'] if 'driver_tests::test_run_callee_error_after_arguments' in previous else next(iter(previous.values()))['providers']
    assert all(now[k]['providers'] == provider for k in set(now)-set(previous))
    old_names = {m.group(1) for k in base37 if k.endswith('.my') for m in re.finditer(r'^public def (test_\w+)\(', (base/k).read_text(),re.M)}
    names = {m.group(1) for k in base37 if k.endswith('.my') for m in re.finditer(r'^public def (test_\w+)\(', text(stage,k),re.M)}
    assert old_names <= names and len(old_names) == 84 and len(names) == 88

def verify(stage,version):
    path = WORK/stage
    hashes = sources[stage]['source37']
    build = read(WORK/(stage+'-build.json'))
    public = read(WORK/(stage+'-qualification.json'))
    gc = read(WORK/(version+'-gc/gc-builds.json'))
    for receipt,key in [(build,'source_sha256'),(public,'source_sha256'),(gc,'source37')]:
        assert receipt['verified_after'] and receipt[key] == hashes
        assert receipt['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
        assert receipt['qbe_sha256'] == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
    for row in build['runs']+gc['runs']:
        assert row['status'] == 0
        if 'binary' in row: assert sha(row['binary']) == row['binary_sha256']
        if 'runtime_object' in row: assert sha(row['runtime_object']) == row['runtime_object_sha256']
    assert len(public['runs']) == 4
    for row in public['runs']:
        assert row['status'] == 0 and '--cases' not in row['argv']
        assert row['summaries'] == ['88 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs']
        assert sha(row['log']) == row['log_sha256']
    work = WORK/(version+'-native')
    done = read(work/'completed.json')
    before,after = done['before'],done['after']
    assert done['verified_after'] and done['helper_status'] == 0
    assert before['candidate37'] == after['candidate37'] == hashes
    assert before['control37'] == after['control37'] == base37
    assert before['artifacts_sha256'] == after['artifacts_sha256']
    for p,h in after['artifacts_sha256'].items(): assert sha(p) == h,p
    for n,h in done['receipt_sha256'].items(): assert sha(work/n) == h,n
    assert not set(before['runner_affinity']) & {2,3,10,11}
    bins = read(work/'binaries.json')['binaries']
    observations = read(work/'observations.json')
    assert observations['verified_after'] and observations['manifest_sha256'] == sha(work/'binaries.json')
    assert observations['binary_sha256'] == {k:sha(v) for k,v in bins.items()}
    identity = lambda x:(x['name'],x['tier'],x['engine'],x['arm'],x['lox_gc_stress'])
    samples,omissions = observations['samples'],observations['unrun']
    actual,unrun = {identity(x) for x in samples},{identity(x) for x in omissions}
    cases = {(x['name'],x['tier'],x['engine']) for x in samples}
    expected = {(n,t,e,a,s) for n,t,e in cases for a in bins if not a.startswith('control-') for s in [False,True]}
    assert len(samples) == len(actual) == 1192 and len(omissions) == len(unrun) == 80
    assert len(cases) == 106 and actual.isdisjoint(unrun) and actual|unrun == expected
    assert Counter(t for n,t,e in cases) == {'smoke':26,'regression':34,'error':46}
    counts = Counter('native_gc_stress' if x['native_gc_stress'] else 'rc' if '-rc-' in x['arm'] else 'ordinary_gc' for x in samples)
    assert counts == done['mode_counts'] == {'rc':424,'ordinary_gc':424,'native_gc_stress':344}
    for x in samples:
        assert x['actual'] == x['expected'] and sha(x['command'][-1]) == x['source_sha256']
    for x in omissions:
        assert x['tier'] == 'smoke' and x['native_gc_stress']
        assert sha(work/'validation-inputs'/f"{x['name']}.{x['engine']}.{x['tier']}.lox") == x['source_sha256']
    for name,key,count in [('constant-255-boundary.json','samples',12),('argument-limits.json','pairs',192)]:
        rows = read(work/name)[key]
        assert len(rows) == len({(x.get('name','constant-255'),x.get('engine','vm'),x['arm'],x['lox_gc_stress']) for x in rows}) == count
        for x in rows: assert x['actual'] == x['expected'] and sha(x['argv'][-1]) == x['source_sha256']
        if count == 192:
            assert len({x['name'] for x in rows}) == 8
            assert all(x['actual']['status'] == (0 if x['name'] == 'argument255-last-slot' else 65) for x in rows)
    refused = read(work/'rc-native-stress-refusals.json')['pairs']
    assert len(refused) == len({(x['backend'],x['engine'],x['lox_gc_stress']) for x in refused}) == 8
    for x in refused:
        assert x['actual'] == x['expected'] and x['actual']['status'] == 2 and x['actual']['stdout'] == '' and '--gc-runtime' in x['actual']['stderr']
    return {'public_passes':352,'directory_provider':'No --cases; no provider-backed execution claim.',
            'bounded_pairs':1192,'bounded_mode_counts':dict(counts),'boundary_pairs':12,'argument_limit_pairs':192,
            'unaccounted_program_pairs':1396,'checked_refusal_pairs':8,'explicit_unrun_native_smoke_cells':80,
            'binary_sha256':observations['binary_sha256'],'source37_unchanged':True,'all_frozen_artifact_input_hashes_unchanged':True,
            'generated_inputs_rehashed_after':True,'receipts_sha256':{str(work/n):sha(work/n) for n in ['completed.json','observations.json','constant-255-boundary.json','argument-limits.json','rc-native-stress-refusals.json']},
            'build_receipts_sha256':{str(WORK/n):sha(WORK/n) for n in [stage+'-build.json',stage+'-qualification.json',version+'-gc/gc-builds.json']}}

verified = {stage:verify(stage,v) for stage,v in [('octets-v2','v2'),('octets-shape-v3','v3')]}
static = {}
for stage in verified:
    emission = read(WORK/(stage+'-emission.json'))
    run = next(x for x in emission['functions'] if x['name'] == 'vm::run')
    static[stage] = {'ssa_sha256':hashlib.sha256(run['il'].encode()).hexdigest(),'positive_index_sites':run['il'].count('# QBE-POSITIVE-INDEX-1'),'native':{}}
    for backend in ['llvm','qbe']:
        assembly = WORK/(stage+'-vm-run-'+backend+'.asm')
        lines = [x for x in assembly.read_text().splitlines() if re.match(r'^\s*[0-9a-f]+:\s+\S',x)]
        static[stage]['native'][backend] = {'decoded_instructions':len(lines),'call_sites':sum(bool(re.search(r':\s+call\s',x)) for x in lines),'asm_sha256':sha(assembly)}
spec = ROOT/'.tmp-lox-parity/inputs/pinned-SPEC.md'
assert sha(spec) == 'c818e2c812b6b7d9a3c3d4838c0526d54767369775298db23fb33f4055681f36'
author_evidence = AUTHOR/'experiments/lox-vm-bytecode-20261003'
published_sources = read(author_evidence/'sources.json')
assert published_sources['control37'] == base37
for stage in sources:
    assert published_sources[stage]['source37'] == sources[stage]['source37']
    assert published_sources[stage]['patch_sha256'] == sources[stage]['patch_sha256']
published = read(author_evidence/'qualification.json')
for stage in sources:
    v = published['variants'][stage]
    assert v['public_fresh'] == 352 and v['native_bounded'] == 1192 and v['operand255_pairs'] == 12
    assert v['argument_limit_pairs'] == 192 and v['rc_native_stress_refusal_pairs'] == 8 and v['native_smoke_unrun'] == 80
assert 'rejected' in published['rejected_variant'] or 'octets-v1' in published['rejected_variant']
archive = json.loads(gzip.decompress((author_evidence/'receipts.json.gz').read_bytes()))['raw_files']
assert len(archive) == 45
for name,value in archive.items():
    data = value['text'].encode()
    assert hashlib.sha256(data).hexdigest() == value['sha256']
    assert data == (WORK/name).read_bytes(),name
rejected = read(WORK/'argument-overflow-v1/observations.json')['rows']
assert all(x['status'] == (65 if x['arm'] == 'control' else 1) for x in rejected)
committed = subprocess.check_output(['git','-C',str(AUTHOR),'ls-tree','-r','--name-only',AUTHOR_COMMIT,'--','experiments/lox-vm-bytecode-20261003'],text=True).splitlines()
committed_hashes = {}
for name in committed:
    data = subprocess.check_output(['git','-C',str(AUTHOR),'show',AUTHOR_COMMIT+':'+name])
    assert data == (AUTHOR/name).read_bytes(),name
    committed_hashes[name] = hashlib.sha256(data).hexdigest()
report = {'finding':'No actionable defect in frozen corrected source v2 or scalar-shaped source v3 within the reviewed scope.',
          'author_commit':AUTHOR_COMMIT,'author_committed_files_sha256':committed_hashes,
          'source_review':sources,'control37':base37,'pinned_spec_sha256':sha(spec),'independent_receipt_verification':verified,'static_recount':static,
          'author_published_evidence_sha256':{n:sha(author_evidence/n) for n in ['sources.json','qualification.json','receipts.json.gz']},
          'author_archive_raw_files_independently_reconciled':45,
          'limitations':['Source-only d14/99ad candidates; proposed generic byte guard is not implemented or certified by this source review.',
                         'Rejected v1 is excluded from acceptance.',
                         '80 omitted native-stress smoke cells per stage are not passes; 8 refusal pairs per stage are not program passes.',
                         'Provider fixtures preserved structurally; directory runs do not pass --cases.',
                         'Public internal chunk.write_byte now checks octet range; callers outside its existing documented 0..255 byte contract are excluded.',
                         'No review of author constants optimization; these candidates retain original read_constant and contain no AST/constant runtime overlay.',
                         'No new guest execution, performance, canonical/source edits or parity claim.']}
(OUT/'review.json').write_text(json.dumps(report,indent=2)+'\n')
print('Verified v2/v3 source37, exact overlays, 352 public +1396 unaccounted program pairs +8 refusals each; 80 omissions each.')
