import hashlib,json,os,subprocess
from pathlib import Path
root=Path('/home/epentland/ai/canopy/mylang'); work=root/'.tmp/svg-fixes-20260921'; fixtures=root/'.tmp/full-svg-benchmark-20260921/projects/fixture'
arms={'before':root/'.tmp/full-svg-benchmark-20260921/mylang-o3','after':work/'mylang-o3'}
cases=['swapped_net_names','passive_declaration_order','passive_pin_order','display_raw_namespace','nc_raw_collision','nc_only_bridge_collision','empty_net_rejected']
def run(binary,case,stress=False):
 out=work/f'{case}-{binary.name}-{stress}.svg'; issue=work/f'{case}-{binary.name}-{stress}.issue'; issue.write_bytes(b'')
 out.write_bytes(b'')
 source = root/f'.tmp/schematic-implementation-20260921/implementation-{case}.sexp'
 if case == 'nc_only_bridge_collision':
  source = root/'experiments/svg-slowdown-20260921/production-row-index/nc-only-bridge-collision.sexp'
 env=dict(os.environ,MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',MYLANG_SCHEMATIC_OUTPUT=str(out),MYLANG_SCHEMATIC_ISSUE=str(issue),MYLANG_SCHEMATIC_INPUT_0=str(source),MYLANG_SCHEMATIC_INPUT_1=str(fixtures/'lib/pinouts/lmx2595rhar.sexp'),MYLANG_SCHEMATIC_INPUT_2=str(fixtures/'lib/interfaces/spi.sexp'))
 p=subprocess.run([str(binary),'--print-result']+(['--gc-stress'] if stress else []),cwd=root,env=env,capture_output=True,timeout=60)
 return p.returncode,p.stdout,p.stderr,out.read_bytes(),issue.read_bytes()
evidence={'passed':True,'cases':{}}
for case in cases:
 a=run(arms['before'],case); b=run(arms['after'],case); s=run(arms['after'],case,True)
 assert a==b,(case,a[0],b[0],hashlib.sha256(a[1]).hexdigest(),hashlib.sha256(b[1]).hexdigest(),a[2],b[2])
 assert b==s,(case,'stress')
 evidence['cases'][case]={'status':b[0],'stdout':b[1].decode(),'stderr':b[2].decode(),'svg_sha256':hashlib.sha256(b[3]).hexdigest() if b[3] else None,'issue':b[4].decode(),'equals_retained_before':True,'gc_stress_equals_normal':True}
(work/'variant-qualification.json').write_text(json.dumps(evidence,indent=2)+'\n'); print(json.dumps(evidence,indent=2))
