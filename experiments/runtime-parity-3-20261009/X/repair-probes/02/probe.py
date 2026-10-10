#!/usr/bin/env python3
"""Development probe; never substitutes for X's complete qualification/timing."""
import argparse, gzip, hashlib, json, os, random, statistics, subprocess, sys
from pathlib import Path
ROOT = Path.cwd()
TOOLS = ROOT / 'experiments/runtime-parity-3-20261009/tools'
sys.path.insert(0, str(TOOLS))
from rows_mylang import harness
from confirm_rows_bound import measure
from quiet import quiet
import r5_cpu8
rows = harness()
OUT = ROOT / '.tmp/rp3/fix-02'
BIN = ROOT / '.mylang-cache/rp3/fix-probe-02'
COMPILER = ROOT / '.mylang-cache/rp3/compilers/fix-probe-02/release-fast/bin/mylang'
NAMES = ['sort_int', 'sort_records', 'mutate_nested', 'result_propagate', 'option_handle']
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p, v): p.write_text(json.dumps(v, indent=1)+'\n')
def build():
    assert '/build' in os.readlink('/proc/self/fd/9')
    BIN.mkdir(exist_ok=False)
    result = {'compiler': str(COMPILER), 'compiler_sha256': sha(COMPILER), 'builds': []}
    result['patch'] = subprocess.check_output(['git','diff','--','src/core/runtime/core_rt.c','src/core/runtime/core_sort.c'],text=True)
    for row in NAMES:
        source = ROOT / ('test/core/row_'+row+'.my')
        binary = BIN / row
        command = [str(COMPILER),'build',str(source),'-o',str(binary),'--release','--cache-dir',str(BIN/'cache'),'--link',str(ROOT/'benchmarks/runtime/ports/native_clock.c'),'--emit-llvm',str(BIN/(row+'.ll'))]
        proc = subprocess.run(command,capture_output=True,text=True)
        result['builds'].append({'row':row,'source_sha256':sha(source),'command':command,'status':proc.returncode,'stdout':proc.stdout,'stderr':proc.stderr})
        write(OUT/'builds.json',result)
        assert proc.returncode == 0, proc.stderr
        result['builds'][-1]['binary_sha256'] = sha(binary)
        print('built',row,flush=True)
    source=ROOT/'bench/parity/suite/sort_builtin.my'
    binary=BIN/'sort_builtin'
    command=[str(COMPILER),'build',str(source),'-o',str(binary),'--cache-dir',str(BIN/'parity-cache'),'--release']
    proc=subprocess.run(command,capture_output=True,text=True)
    result['builds'].append({'row':'parity/sort_builtin','source_sha256':sha(source),'command':command,'status':proc.returncode,'stdout':proc.stdout,'stderr':proc.stderr})
    write(OUT/'builds.json',result)
    assert proc.returncode==0,proc.stderr
    result['builds'][-1]['binary_sha256']=sha(binary)
    frozen=json.loads((ROOT/'.mylang-cache/rp3/timing-run-01-binaries/manifest.json').read_text())
    arms={'candidate':[str(binary)]}
    for label,name in [('base','sort_builtin.base-my'),('first','sort_builtin.my')]:
        f=next(f for f in frozen['files'] if Path(f['original']).name==name)
        assert sha(f['preserved'])==f['sha256'];arms[label]=[f['preserved']]
    expected=sha(ROOT/'bench/parity/suite/sort_builtin.expected')
    write(OUT/'sort-builtin-spec.json',{'name':'sort_builtin repair control','expected_stdout_sha256':expected,'reference':'base','arms':arms})
    write(OUT/'builds.json',result)
def prepare():
    original = json.loads(gzip.decompress((ROOT/'experiments/runtime-parity-3-20261009/M0/rows-base-1.json.gz').read_bytes()))
    frozen = json.loads((ROOT/'.mylang-cache/rp3/timing-run-01-binaries/manifest.json').read_text())
    mapping = {Path(x['original']).name:x for x in frozen['files'] if '/all46/' in x['original']}
    cells = []
    selected = [(row,size) for row in NAMES for size in (4096,64)] + [('sort_int',n) for n in (32,33,48,63,65,128,255,256,257,512)]
    for row,size in selected:
        official = size in (64,4096)
        iterations = rows.UNITS[row][2 if size==4096 else 3] if official else 1600000//size
        arms = {}
        for label,kind in [('base','old'),('first','new'),('candidate',None)]:
            if kind:
                f = mapping['row_'+row+'_'+kind]
                binary = Path(f['preserved'])
                assert sha(binary)==f['sha256']
            else: binary=BIN/row
            arms[label]={'binary':str(binary),'sha256':sha(binary),'command':[str(binary),str(size),str(iterations),str(rows.SEED)],'startup_command':[str(binary),str(size),'1',str(rows.SEED)]}
        if official:
            base = original['rows'][row]['sizes'][str(size)]
            assert base['iterations']==iterations
            expected=base['checksum']
            starts={s['checksum'] for a in base['configurations'].values() for s in a['startup']}
            assert len(starts)==1
            start=starts.pop()
        else:
            expected=rows.parse_stdout(subprocess.check_output(arms['base']['command'],text=True))[0]
            start=rows.parse_stdout(subprocess.check_output(arms['base']['startup_command'],text=True))[0]
        unit=rows.UNITS[row][1]
        cells.append({'row':row,'size':size,'iterations':iterations,'unit':unit,'units':size*iterations if unit=='element' else iterations,'expected_checksum':expected,'expected_startup_checksum':start,'reference':'base','arms':arms,'official_cell':official})
    write(OUT/'cells.json',cells)
    return cells
def stable(cells):
    for cell in cells:
        for arm in cell['arms'].values(): assert sha(arm['binary'])==arm['sha256']
def cpu8(cells):
    assert '/build' in os.readlink('/proc/self/fd/9')
    r5_cpu8.EVENTS=('instructions','cycles','branch-misses','L1-dcache-loads','mem_inst_retired.all_stores')
    result={'complete':False,'cpu':8,'rounds':7,'cells':cells,'arms':[]}
    samples={(c['row'],c['size'],a):[] for c in cells for a in c['arms']}
    rng=random.Random(20261010)
    for n in range(7):
        order=[(c,a) for c in cells for a in c['arms']];rng.shuffle(order)
        for c,a in order: samples[c['row'],c['size'],a].append(r5_cpu8.sample(c,c['arms'][a],rows))
        result['arms']=[{'program':c['row']+'/'+str(c['size']),'arm':a,'median':{e:statistics.median(s[e] for s in samples[c['row'],c['size'],a]) for e in r5_cpu8.EVENTS},'samples':samples[c['row'],c['size'],a]} for c in cells for a in c['arms']]
        write(OUT/'cpu8.json',result)
        print('CPU8 round',n+1,flush=True)
    stable(cells);result['complete']=True;write(OUT/'cpu8.json',result)
    for c in cells:
        key=c['row']+'/'+str(c['size']);a={x['arm']:x['median'] for x in result['arms'] if x['program']==key}
        print(key,{label:{e:round(a[label][e]/a['base'][e],5) for e in r5_cpu8.EVENTS} for label in ('first','candidate')},flush=True)
def cpu10(cells):
    result={'complete':False,'cpu':10,'batches':3,'rounds':7,'cells':cells,'samples':[]}
    rng=random.Random(20261010)
    with quiet():
        result['load_start']=os.getloadavg()
        for n in range(3):
            order=list(cells);rng.shuffle(order)
            result['samples'].append({c['row']+'/'+str(c['size']):measure(c,rows,rng) for c in order})
            write(OUT/'cpu10.json',result);print('CPU10 batch',n+1,flush=True)
        result['load_end']=os.getloadavg()
    stable(cells)
    result['ratios']={key:{a:statistics.median(b[key]['ratios'][a] for b in result['samples']) for a in ('base','first','candidate')} for key in result['samples'][0]}
    result['complete']=True;write(OUT/'cpu10.json',result);print(json.dumps(result['ratios'],indent=1),flush=True)
if __name__=='__main__':
    mode=sys.argv[1]
    if mode=='build':build()
    elif mode=='cpu8':cpu8(prepare())
    elif mode=='cpu10':cpu10(json.loads((OUT/'cells.json').read_text()))
    else:raise ValueError(mode)
