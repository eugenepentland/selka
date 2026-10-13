#!/usr/bin/env python3
"""Validate the extracted exchange doc with one frozen compiler in one build lease."""
import argparse,hashlib,json,os,pathlib,subprocess
P=pathlib.Path
p=argparse.ArgumentParser();p.add_argument('--compiler',type=P,required=True);p.add_argument('--root',type=P,required=True);p.add_argument('--output',type=P,required=True);p.add_argument('--work',type=P,required=True);a=p.parse_args()
assert os.environ.get('MYLANG_ADMISSION_KIND')=='build', 'invoke under one outer build-slot build lease'
a.output.mkdir(parents=True,exist_ok=False);a.work.mkdir(parents=True,exist_ok=False)
def sha(path):return hashlib.sha256(P(path).read_bytes()).hexdigest()
old=json.loads((a.root/'experiments/lox-eda-parity-20261013/P7/docs/input.json').read_text());assert sha(old['document'])==old['document_sha256'];assert sha(old['source'])==old['source_sha256']
source=a.work/'exchange.my';source.write_bytes(P(old['source']).read_bytes());install=a.compiler.resolve().parents[1]
files={str(path):sha(path) for path in sorted(install.rglob('*')) if path.is_file()}
(a.output/'inputs.json').write_text(json.dumps({'document':old,'source':str(source),'source_sha256':sha(source),'installation':files,'compiler':str(a.compiler),'outer_lease':{'kind':os.environ['MYLANG_ADMISSION_KIND'],'directory':os.environ['MYLANG_ADMISSION_DIR']},'verifier_sha256':sha(__file__)},indent=2)+'\n')
rows=[]
for mode,flags in [('rc',[]),('zero-rc',['--experimental-zero-rc'])]:
    binary=a.work/mode
    for phase,argv,status in [('build',[str(a.compiler),'build',str(source),'--release',*flags,'--cache-dir',str(a.work/('cache-'+mode)),'-o',str(binary)],0),('run',[str(binary)],42)]:
        assert all(sha(path)==digest for path,digest in files.items())
        name=mode+'-'+phase;env={**os.environ,'MYLANG_JOBS':'4','MYL_CORE_LEAKCHECK':'1'};env.pop('MYLANG_COUNTERS',None)
        r=subprocess.run(argv,cwd=a.root,env=env,capture_output=True)
        (a.output/(name+'.stdout')).write_bytes(r.stdout);(a.output/(name+'.stderr')).write_bytes(r.stderr);rows.append({'command':argv,'returncode':r.returncode,'expected_exit':status});(a.output/'commands.json').write_text(json.dumps(rows,indent=2)+'\n');assert r.returncode==status,(name,r.stderr)
        if phase=='run':assert not r.stdout and not r.stderr
assert all(sha(path)==digest for path,digest in files.items())
