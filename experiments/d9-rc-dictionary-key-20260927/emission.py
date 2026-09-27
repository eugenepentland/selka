from pathlib import Path
import json,subprocess,hashlib
r=Path.cwd();w=r/'.tmp-rc/dict-key';data=json.loads((w/'measurements.json').read_text());out=[]
for side in ['before','after']:
 c=Path(data['compilers'][side]['path']);cmd=[str(c),'emit-qbe',str(r/'bench/parity/micro/dict_count.my'),'--rc-runtime','--drop-debug','--drop-step-checks','--drop-frame-checks'];p=subprocess.run(cmd,text=True,capture_output=True);assert p.returncode==0,p.stderr;f=next(x for x in json.loads(p.stdout)['functions'] if x['name']=='main');s=f['il'];(w/f'{side}-final-main.ssa').write_text(s)
 row={'side':side,'command':cmd,'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'bytes':len(s),'il_sha256':hashlib.sha256(s.encode()).hexdigest(),'key_markers':s.count('# RC-DICTIONARY-KEY-1'),'tail_markers':s.count('# RC-DICTIONARY-TAIL-1'),'calls':{}}
 for name in ['myl_rc_native_loan','myl_rc_native_retain','myl_rc_hold_acquire','myl_qbe_rc_unique_local','myl_native_dictionary_write','myl_qbe_rc_frame_enter']:row['calls'][name]=s.count('call $'+name+'(')
 b=w/'full'/f'{side}-qbe-rc';build=next(x for x in data['builds'] if x['side']==side and x['backend']=='qbe' and not x['stats']);symbol=next(x['symbol'] for x in build['manifest']['functions'] if x['name']=='main');cmd=['objdump','-d','--disassemble='+symbol,str(b)];p=subprocess.run(cmd,capture_output=True,text=True);assert p.returncode==0,p.stderr;(w/f'{side}-main.asm').write_text(p.stdout);row['native_command']=cmd;row['native_calls']={name:p.stdout.count('<'+name+'>') for name in row['calls']};out.append(row)
(w/'emission-final.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
a,b=out;assert a['key_markers']==0 and b['key_markers']==2
for field in ['calls','native_calls']:
 for name in ['myl_qbe_rc_unique_local','myl_native_dictionary_write','myl_qbe_rc_frame_enter']:assert a[field][name]==b[field][name],(field,name,a,b)
 assert a[field]['myl_rc_native_loan']-b[field]['myl_rc_native_loan']==2
