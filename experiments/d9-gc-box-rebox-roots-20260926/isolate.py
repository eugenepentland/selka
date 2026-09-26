import hashlib,json,os,subprocess
from pathlib import Path
root=Path.cwd();w=root/'.tmp-repeat';compiler=Path('/home/epentland/ai/canopy/mylang-worktrees/d9-rc-integration/.tmp-rc/install-compact/bin/mylang')
source=(w/'rc_box_writeback.my').read_text();head=source[:source.index('def main(out: Stream)')];functions=['test_heap_option_mapping_write_updates_the_owner_after_a_snapshot','test_arena_option_mapping_write_updates_the_owner_after_a_snapshot','test_option_write_still_publishes_when_a_view_keeps_the_old_mapping_alive','test_repeated_option_writes_replace_the_latest_owner','test_reboxed_heap_owner_survives_an_inner_arena']
cases={'only':[functions[3]],'repeat':[functions[3]]*4}
for i in (0,1,2,4):cases['prior'+str(i)]=[functions[i],functions[3]]
result={'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':{}}
for name,calls in cases.items():
 folder=w/name;folder.mkdir(exist_ok=True);path=folder/'rc_box_writeback.my';text=head+'def main(out: Stream) -> int:\n'+''.join('    out.print('+f+'())\n' for f in calls)+'    return 0\n';path.write_text(text)
 command=[str(root/'scripts/build-slot.sh'),'build',str(compiler),'run',str(path),'--gc-runtime','--gc-stress','--cache-dir='+str(w/'before-cache')]
 p=subprocess.run(command,capture_output=True,text=True,env=dict(os.environ,TMPDIR=str(w)),timeout=600)
 result['runs'][name]={'command':command,'source':text,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr};(w/'isolate.json').write_text(json.dumps(result,indent=2)+'\n');print(name,p.returncode,repr(p.stdout),flush=True)
