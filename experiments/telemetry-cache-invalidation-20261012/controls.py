import json,os,pathlib,subprocess
root=pathlib.Path.cwd();out=root/'.tmp/telemetry-cache-probe';fixture=out/'controls.my'
source='public func test_constant() -> bool:\n    return 2 + 2 == 4\n\npublic func test_second() -> bool:\n    return 3 * 3 == 9\n'
fixture.write_text(source)
compiler=root/'.tmp/frozen-final-candidate/bin/mylang';base=dict(os.environ)
base['MYLANG_COMPONENT_CACHE']='/home/epentland/ai/canopy/mylang-dl-wave2-20261012-S09/.tmp/S09-native-component-cache'
for key in ['MYLANG_TEST_TELEMETRY_DIR','SELKA_VERIFICATION_TELEMETRY_DIR','MYL_CORE_LEAKCHECK']:base.pop(key,None)
rows=[]
def run(label,extra=None,flags=(),failed=0,cached=None):
 env=dict(base);env.update(extra or {})
 command=[str(compiler),'test',str(fixture),'--cache-dir',str(out/'control-cache'),'--json',*flags]
 p=subprocess.run(command,env=env,capture_output=True,text=True,timeout=90)
 report=json.loads(p.stdout);(out/(label+'-control.json')).write_text(p.stdout)
 row=dict(label=label,status=p.returncode,command=command,report=report);rows.append(row)
 assert p.returncode==(1 if failed else 0),(label,p.stderr)
 assert report['failed']==failed,(label,report)
 assert sum(report[k] for k in ['passed','cached','failed','skipped','unsupported'])==2,(label,report)
 if cached is not None:assert report['cached']==cached,(label,report)
 print(label,report['passed'],report['cached'],report['failed'],flush=True)
 return [t.get('cache',{}).get('key') for t in report['tests']]
a=run('new-a',{'SELKA_VERIFICATION_TELEMETRY_DIR':str(out/'new-a')},cached=0)
assert run('new-b',{'SELKA_VERIFICATION_TELEMETRY_DIR':str(out/'new-b')},cached=2)==a
assert run('new-absent',cached=2)==a
b=run('semantic-a',{'MYLANG_PROBE_RANDOM':'a'},cached=0)
c=run('semantic-b',{'MYLANG_PROBE_RANDOM':'b'},cached=0)
assert b!=a and c!=a and b!=c
assert run('semantic-restored',cached=2)==a
run('forced',flags=['--force'],cached=0)
run('facts',flags=['--release','--verify-facts'],cached=0)
run('leaks',{'MYL_CORE_LEAKCHECK':'1'},cached=0)
fixture.write_text(source.replace('2 + 2 == 4','2 + 2 == 5'))
run('source-failure',failed=1)
fixture.write_text(source)
run('source-restored',cached=2)
(out/'controls-summary.json').write_text(json.dumps(dict(schema=1,rows=rows,status='passed'),indent=2)+'\n')
