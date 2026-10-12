import hashlib,json,os,pathlib,subprocess,time
root=pathlib.Path.cwd()
out=root/'.tmp/telemetry-cache-probe'
fixture=out/'fixture.my'
fixture.write_text('public func test_constant() -> bool:\n    return 2 + 2 == 4\n\npublic func test_second() -> bool:\n    return 3 * 3 == 9\n')
compiler=root/'.tmp/frozen-final-candidate/bin/mylang'
base=dict(os.environ)
base['MYLANG_COMPONENT_CACHE']='/home/epentland/ai/canopy/mylang-dl-wave2-20261012-S09/.tmp/S09-native-component-cache'
base.pop('MYLANG_TEST_TELEMETRY_DIR',None)
results=[]
for name,telemetry in [('a1','telemetry-a'),('a2','telemetry-a'),('b1','telemetry-b'),('b2','telemetry-b'),('a3','telemetry-a'),('none1',None),('none2',None)]:
    env=dict(base)
    if telemetry:
        directory=out/telemetry
        directory.mkdir(exist_ok=True)
        env['MYLANG_TEST_TELEMETRY_DIR']=str(directory)
    command=[str(compiler),'test',str(fixture),'--cache-dir',str(out/'cache'),'--json']
    started=time.monotonic()
    result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=90)
    elapsed=time.monotonic()-started
    (out/(name+'.stdout.json')).write_text(result.stdout)
    (out/(name+'.stderr.txt')).write_text(result.stderr)
    row=dict(name=name,telemetry=telemetry,status=result.returncode,elapsed_seconds=elapsed,stdout=result.stdout)
    results.append(row)
    print(json.dumps(row),flush=True)
    if result.returncode: break
(out/'result.json').write_text(json.dumps(dict(compiler=str(compiler),compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),command=command,results=results),indent=2)+'\n')
