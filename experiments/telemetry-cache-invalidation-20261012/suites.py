import argparse,collections,hashlib,json,os,pathlib,subprocess,time
p=argparse.ArgumentParser();p.add_argument('phase',choices=['prepare','measure']);args=p.parse_args()
root=pathlib.Path.cwd();out=root/'.tmp/telemetry-cache-probe';compiler=root/'.tmp/frozen-final-candidate/bin/mylang'
base=dict(os.environ);base['MYLANG_COMPONENT_CACHE']='/home/epentland/ai/canopy/mylang-dl-wave2-20261012-S09/.tmp/S09-native-component-cache'
for name in ['MYLANG_TEST_TELEMETRY_DIR','SELKA_VERIFICATION_TELEMETRY_DIR','MYL_CORE_LEAKCHECK']:base.pop(name,None)
cases=[(suite,mode) for suite in ['guest','lang','value_semantics','ported'] for mode in (['debug'] if suite=='guest' else ['debug','unoptimized','release'])]
rows=[]
for cohort in (range(1) if args.phase=='prepare' else [-1,0,1,2]):
 for variant in (['new'] if cohort==-1 else ['old','new'] if cohort%2==0 else ['new','old']):
  for suite,mode in cases:
   env=dict(base);variable='MYLANG_TEST_TELEMETRY_DIR' if variant=='old' else 'SELKA_VERIFICATION_TELEMETRY_DIR'
   telemetry=out/f'{args.phase}-{variant}-{cohort}';telemetry.mkdir(exist_ok=True);env[variable]=str(telemetry)
   command=[str(compiler),'test',f'tests/{suite}','--cache-dir',str(out/'suite-caches'/f'{suite}-{mode}'),'--json','--jobs','4']
   if mode=='unoptimized':command.append('--unoptimized')
   if mode=='release':command+=['--release','--verify-facts'];env['MYL_CORE_LEAKCHECK']='1'
   label=f'{args.phase}-{cohort}-{variant}-{suite}-{mode}'
   started=time.monotonic();result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=120);elapsed=time.monotonic()-started
   (out/(label+'.json')).write_text(result.stdout);(out/(label+'.stderr')).write_text(result.stderr)
   report=json.loads(result.stdout) if result.stdout else {}
   counts={k:report.get(k) for k in ['passed','cached','failed','skipped','unsupported']}
   reasons=dict(collections.Counter(t.get('cache',{}).get('reason','unknown') for t in report.get('tests',[])))
   row=dict(label=label,suite=suite,mode=mode,variant=variant,cohort=cohort,command=command,status=result.returncode,elapsed_seconds=elapsed,counts=counts,reasons=reasons)
   rows.append(row);print(json.dumps({k:v for k,v in row.items() if k!='command'}),flush=True)
   if result.returncode:raise SystemExit(result.returncode)
(out/(args.phase+'-summary.json')).write_text(json.dumps(dict(schema=1,compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),rows=rows,scope='sequential suite invocations; not complete gate latency',affinity=sorted(os.sched_getaffinity(0))),indent=2)+'\n')
