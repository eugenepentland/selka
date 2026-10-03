from pathlib import Path
import collections,datetime,hashlib,io,json,math,statistics,subprocess,tarfile

ROOT=Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
WORK=ROOT/'.tmp-lox-parity'
OUT=Path(__file__).resolve().parent
METRICS=['instructions','cycles','branches','branch-misses']
SCOPE={'baseline-check':(26,4,1),'baseline-counters':(26,4,3),'baseline-timing':(26,4,3),'source-screen-check':(26,14,1),'source-screen-counters':(5,7,2),'tree-screen-timing':(13,6,2),'tree-direct-screen-timing':(13,4,2),'positive-screen-check':(26,8,1),'positive-screen-counters':(26,8,1),'carrier-baseline-screen-counters':(13,4,1),'sweep-screen-check':(26,4,1),'sweep-screen-counters':(26,4,2),'checkpoint-counters':(26,6,3)}
ANALYSES={'baseline-instruction-ratios':'baseline-counters','baseline-wall-ratios':'baseline-timing','source-screen-analysis':'source-screen-counters','tree-screen-timing-analysis':'tree-screen-timing','tree-direct-screen-analysis':'tree-direct-screen-timing','positive-screen-analysis':'positive-screen-counters','carrier-screen-analysis':'carrier-baseline-screen-counters','sweep-screen-analysis':'sweep-screen-counters','checkpoint-counter-analysis':'checkpoint-counters'}
files={}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):
    p=Path(p);raw=p.read_bytes();files[str(p)]=hashlib.sha256(raw).hexdigest();return json.loads(raw)
def close(a,b):assert math.isclose(a,b,rel_tol=1e-12,abs_tol=1e-12),(a,b)

manifest=read(WORK/'binaries.json')
ref=WORK/'reference';reference_commit='4e48a09220c2e018eba8c4b1eb3fe1137a3dae73'
assert manifest['reference_commit']==reference_commit
blob=subprocess.check_output(['git','-C',str(ROOT),'archive',reference_commit,'--','benchmarks/lox'])
archive=tarfile.open(fileobj=io.BytesIO(blob),mode='r:')
pinned={m.name:hashlib.sha256(archive.extractfile(m).read()).hexdigest() for m in archive.getmembers() if m.isfile()}
for name,digest in manifest['reference_source_hashes'].items():assert sha(ref/name)==digest==pinned[name],name
sizes=json.loads((ref/'benchmarks/lox/bench/sizes.json').read_text())
records={};loaded={};source_cache={};binary_cache={};command_records=0;all_percentages=[]

def source_hashes(desc):
    key=desc['path']
    if key not in source_cache:source_cache[key]={p.name:sha(p) for p in sorted(Path(key).glob('*.my'))}
    assert source_cache[key]==desc['hashes'],key
    return source_cache[key]

def verify_doc(name,doc,required=None):
    assert doc.get('verified_after') and doc.get('finished_utc'),name
    cases={c['id']:c for c in doc['cases']};arms=set(doc['binary_sha256']);rounds=doc['rounds']
    assert len(cases)==len(doc['cases'])
    if required:assert (len(cases),len(arms),rounds)==required,(name,required)
    expected={(c,a,r) for c in cases for a in arms for r in range(rounds)}
    actual=[(s['case'],s['arm'],s['round']) for s in doc['samples']]
    assert len(actual)==len(set(actual)) and set(actual)==expected,name
    hashes={};source_descriptors=doc['manifest']['candidate_sources']
    assert doc['manifest']['reference_commit']==reference_commit
    assert doc['manifest']['reference_source_hashes']==manifest['reference_source_hashes']
    for arm,digest in doc['binary_sha256'].items():
        p=doc['manifest']['binaries'][arm]
        if p not in binary_cache:binary_cache[p]=sha(p)
        assert binary_cache[p]==digest==doc['manifest']['binary_sha256'][arm],arm
        assert manifest['binary_sha256'][arm]==digest,arm
        hashes[arm]=digest
    for desc in source_descriptors.values():source_hashes(desc)
    expected_out={}
    for case,c in cases.items():
        assert case==c['engine']+'/'+c['name']
        key=c['engine'] if doc['tier']=='timed' else doc['tier']
        assert c['size']==sizes[c['name']][key],(name,case)
        _,body=(ref/'benchmarks/lox/bench/scripts'/(c['name']+'.lox')).read_text().split('\n',1)
        wanted=(f"var N = {c['size']};\n"+body).encode()
        assert hashlib.sha256(wanted).hexdigest()==c['script_sha256']==sha(c['script']),case
        p=Path(c['expected']);assert p==ref/'benchmarks/lox/bench/expected'/(c['name']+'.'+key+'.out')
        expected_out[case]=sha(p)
    stats=collections.defaultdict(list)
    for sample in doc['samples']:
        assert sample['status']==0 and sample['stdout_sha256']==expected_out[sample['case']],(name,sample)
        assert sample['wall_s']>0
        if doc['phase']=='check':
            st=sample['collector_stats'];assert set(st)=={'allocations','collections','freed','live'}
            assert sample['stderr'].startswith('[stats] engine=') and sample['stderr'].count('\n')==1
            stats[sample['case'],sample['round']].append(st)
        else:assert sample['stderr']=='',(name,sample)
        if doc['phase']=='counters':
            for metric in METRICS:
                assert metric in sample and sample[metric]>=0
                pct=sample[metric+'_running_pct'];assert pct==100.0,(name,sample['case'],metric,pct)
                all_percentages.append(pct)
            assert sample['instructions']>0 and sample['cycles']>0
            assert sample['branch-misses']<=sample['branches']
    for observations in stats.values():assert all(s==observations[0] for s in observations)
    assert len(doc['quiet_waits'])==len(cases)*rounds
    assert all(max(float(x) for x in row['busy'].values())<.25 for row in doc['quiet_waits'])
    command_path=WORK/'measurements'/(name+'.command.json')
    command_ok=False
    if command_path.exists():
        record=read(command_path);assert record['status']==0 and record['sources_verified_after']
        assert record['source_hashes_before']==record['source_hashes_after']=={n:source_hashes(d) for n,d in source_descriptors.items()}
        serialized=json.dumps(doc['manifest'],indent=2)+'\n';assert hashlib.sha256(serialized.encode()).hexdigest()==record['manifest_sha256']
        assert sha(WORK/'measurements'/(name+'.log'))==record['log_sha256']
        command_ok=True
    records[name]={'phase':doc['phase'],'tier':doc['tier'],'cpu':doc['cpu'],'cases':len(cases),'arms':sorted(arms),'rounds':rounds,'samples':len(actual),'exact_coverage':True,'all_outputs_status_diagnostics_and_check_stats_pass':True,'binary_input_current_source_and_reference_hashes_pass':True,'run_py_before_after_source_log_record':command_ok,'receipt_sha256':files[str(WORK/'measurements'/(name+'.json'))]}
    return command_ok

for name,expected in SCOPE.items():
    d=read(WORK/'measurements'/(name+'.json'));loaded[name]=d
    command_records+=verify_doc(name,d,expected)

# Recompute ratios independently, using per-round pairs, per-case medians,
# and then a geometric mean over every case in an engine.
def independent(doc,baseline,candidate,metric):
    index={(s['case'],s['round'],s['arm']):s for s in doc['samples']};rows={};engines={}
    for case in sorted(c['id'] for c in doc['cases']):
        values=[index[case,r,candidate][metric]/index[case,r,baseline][metric] for r in range(doc['rounds'])]
        median=statistics.median(values);rows[case]={'ratio':median,'paired':values,'spread':100*(max(values)-min(values))/median}
    for e in ['vm','tree']:
        values=[r['ratio'] for c,r in rows.items() if c.startswith(e+'/')]
        if values:engines[e]=math.exp(sum(math.log(v) for v in values)/len(values))
    return rows,engines

def comparisons(value,path=''):
    if isinstance(value,dict):
        if {'baseline','candidate','metric','rows','engines'}<=set(value):yield path,value
        else:
            for k,v in value.items():yield from comparisons(v,path+'/'+k)
analysis_rows=[]
for name,origin in ANALYSES.items():
    value=read(WORK/'measurements'/(name+'.json'))
    for key,comparison in comparisons(value):
        rows,engines=independent(loaded[origin],comparison['baseline'],comparison['candidate'],comparison['metric'])
        assert set(rows)==set(comparison['rows'])
        for case,row in rows.items():
            stored=comparison['rows'][case];close(row['ratio'],stored['candidate_over_baseline']);close(row['spread'],stored['spread_pct']);assert len(row['paired'])==len(stored['paired_ratios'])
            for a,b in zip(row['paired'],stored['paired_ratios']):close(a,b)
        for e,ratio in engines.items():close(ratio,comparison['engines'][e]['candidate_over_baseline']);assert comparison['engines'][e]['cases']==sum(c.startswith(e+'/') for c in rows)
        analysis_rows.append({'analysis':name,'comparison':key,'case_count':len(rows),'engine_ratios':engines})

final=read(WORK/'final-source.json');replay=read(WORK/'canonical-replay.json')
patch_sha='233332c7b4fd1325f3ec1251406b0b433e87520f5abc4db9cfcc70e79813445b'
assert final['patch_sha256']==replay['patch_sha256']==patch_sha==sha(final['patch'])
final_files={str(p.relative_to(final['path'])):sha(p) for p in sorted(Path(final['path']).rglob('*')) if p.is_file()}
assert final_files==final['files']==replay['hashes'] and replay['files']==len(final_files)==37 and replay['exact_match']
replayed=ROOT/'.tmp-lox-parity/replay-final-absolute/lox/benchmarks/lox/ports/mylang'
assert {str(p.relative_to(replayed)):sha(p) for p in sorted(replayed.rglob('*')) if p.is_file()}==final_files
for name in ['carrier-final-sweep','carrier-joined-flat']:
    build=read(WORK/(name+'-build.json'));assert sha(build['compiler'])==build['compiler_sha256'] and build['runtime']=='rc'
    for row in build['builds']:
        argv=row['argv'];binary=Path(argv[argv.index('-o')+1]);assert row['status']==0 and sha(binary)==row['binary_sha256']
        backend=argv[argv.index('--backend')+1];assert '--rc-runtime' in argv and '--keep-symbols' in argv
        if backend=='llvm':assert '--lto' in argv and argv[argv.index('--llvm-opt')+1]=='3'
        other='final-sweep' if name=='carrier-final-sweep' else 'positive-joined-flat'
        assert row['binary_sha256']==manifest['binary_sha256'][other+'-'+backend]

# Inspect the live checkpoint once at the end; never treat a live snapshot as
# completed or compute its ratios. Root owns all runs and root-file writes.
checkpoint_path=WORK/'measurements/checkpoint-timing.json'
cp=json.loads(checkpoint_path.read_bytes());checkpoint={'status':'pending','observed_samples':len(cp['samples']),'planned_samples':468,'verified_after':bool(cp.get('verified_after')),'aggregate_ratios_computed':False}
if cp.get('verified_after'):
    files[str(checkpoint_path)]=sha(checkpoint_path)
    command_records+=verify_doc('checkpoint-timing',cp,(26,6,3))
    checkpoint={'status':'complete_and_independently_verified','observed_samples':468,'planned_samples':468,'verified_after':True,'aggregate_ratios_computed':True,'comparisons':[]}
    for backend in ['llvm','qbe']:
        for base in ['baseline-'+backend,'rust','go']:
            rows,ratios=independent(cp,base,'final-sweep-'+backend,'wall_s');checkpoint['comparisons'].append({'baseline':base,'candidate':'final-sweep-'+backend,'engine_ratios':ratios})

raw_rows = 0
for doc in list(loaded.values()) + [cp]:
    grouped = collections.defaultdict(list)
    for sample in doc['samples']:
        grouped[sample['case'], sample['arm']].append(sample)
    for (case, arm), samples in grouped.items():
        saved = doc['summary'][case][arm]
        walls = [s['wall_s'] for s in samples]
        close(saved['wall_s'], statistics.median(walls))
        close(saved['wall_spread'], (max(walls)-min(walls))/statistics.median(walls))
        assert saved['samples'] == len(samples)
        for metric in METRICS + ['maxrss_kib']:
            values = [s[metric] for s in samples if metric in s]
            if values: close(saved[metric], statistics.median(values))
        if 'instructions' in saved: close(saved['ipc'], saved['instructions']/saved['cycles'])
        raw_rows += 1
for path,digest in files.items():assert sha(path)==digest,path
source_cpp={name:sha(ROOT/name) for name in ['experiments/lox-parity-20261003/run.py','experiments/lox-parity-20261003/analyze.py','experiments/lox-perf-improvements-20261002/analyze.py','experiments/lox-performance-audit-20261002/audit.py']}
summary={'reviewed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'mode':'independent read-only provenance and math review; no measurements or root writes','reference_commit':reference_commit,'reference_source_hashes_verified_against_git':len(manifest['reference_source_hashes']),'completed_receipts':records,'completed_observations':sum(x['samples'] for n,x in records.items() if n!='checkpoint-timing'),'PMU':{'counter_observations':len(all_percentages)//4,'percentage_fields':len(all_percentages),'all_recorded_percentages':sorted(set(all_percentages)),'all_four_metrics_present':True},'analyses_independently_recomputed':analysis_rows,'canonical_overlay_sha256':patch_sha,'canonical_replay_files':37,'positive_combined_guest_identity':'byte-identical for joined-flat and final-sweep, LLVM and QBE','checkpoint':checkpoint,'raw_summary_rows_independently_verified':raw_rows,'historical_initial_review_sha256':'14a59b774faea6cc230458b0593b9fe49c529b1622587e42bad3fb580110e24d','compiler_review_pending':'Root identified a try_result interior-edge omission in the positive-index certificate; the field-inout transfer proof has no finding. This read-only evidence review does not approve broad compiler integration or assume identity of a future rebuilt compiler.','implementation_review':{'pairing':'Generic compare pairs same case/round and takes median of paired ratios; independent full coverage checks passed. Checkpoint analyze.py separately rejects incomplete/duplicate coverage, unexpected diagnostics, missing3rounds and non100 instruction PMU.','run_py':'Refuses output overwrite, checks all .my source hashes before/after and immutable manifest/log hash; strips MYLANG_/LD_PRELOAD. audit.py checks executable/input hashes after the run, exact pinned stdout/status, and collector work for smoke.','limitations':['Initial baseline and source-screen receipts do not all have run.py source-before/after command records; their audit-runner binary/input verification and present source hashes pass.','run.py source checks cover .my modules, not every metadata file; final37 file identity is separately checked here.','Generic compare alone does not reject missing whole rounds or duplicate sample identities; strict checkpoint wrapper and this independent review do.','Checkpoint instruction validation code checks instructions percentage only; this review checks all four PMU percentages for every completed counter observation.','One/two-round or five-case screening is diagnostic and cannot substitute for the completed matched3round reference checkpoint.','No claim of Rust/Go parity follows from screening gains or a pending checkpoint.']},'reviewed_implementation_sha256':source_cpp,'reviewed_file_sha256':files}
(OUT/'review.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'completed_observations':summary['completed_observations'],'PMU_fields':len(all_percentages),'analysis_comparisons':len(analysis_rows),'checkpoint':checkpoint['status'],'checkpoint_samples':checkpoint['observed_samples'],'sources':len(source_cache),'reference_files':127},indent=2))
