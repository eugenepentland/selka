from pathlib import Path
import json,subprocess,hashlib
r=Path.cwd();w=r/'.tmp-rc/dict-loop';out=[]
cs={'before':r/'.tmp-rc/install-dict-key-prototype/bin/mylang','after':r/'.tmp-rc/install-dict-loop/bin/mylang'}
for side,c in cs.items():
 cmd=[str(c),'emit-qbe',str(r/'bench/parity/micro/dict_count.my'),'--rc-runtime','--drop-debug','--drop-step-checks','--drop-frame-checks']
 p=subprocess.run(cmd,capture_output=True,text=True);assert p.returncode==0,p.stderr
 s=next(x['il'] for x in json.loads(p.stdout)['functions'] if x['name']=='main');(w/f'{side}-main.ssa').write_text(s)
 body=s[s.index('\n@i34\n'):s.index('\n@i75\n')]
 row={'side':side,'command':cmd,'compiler_sha256':hashlib.sha256(c.read_bytes()).hexdigest(),'il_sha256':hashlib.sha256(s.encode()).hexdigest(),'bytes':len(s),'entry34':'\n@ce34\n' in s,'fast34':'@fi34' in s,'key_markers':s.count('# RC-DICTIONARY-KEY-1'),'tail_markers':s.count('# RC-DICTIONARY-TAIL-1'),'calls':{},'body_unique':body.count('call $myl_qbe_rc_unique_local(')}
 for name in ['myl_rc_native_loan','myl_rc_native_retain','myl_rc_hold_acquire','myl_qbe_rc_unique_local','myl_native_dictionary_write','myl_qbe_rc_frame_enter']:row['calls'][name]=s.count('call $'+name+'(')
 b=w/'full'/f'{side}-qbe-rc'
 m=json.loads(Path(str(b)+'.qbe-manifest.json').read_text());symbol=next(x['symbol'] for x in m['functions'] if x['name']=='main')
 native=['objdump','-d','--disassemble='+symbol,str(b)];p=subprocess.run(native,capture_output=True,text=True);assert p.returncode==0,p.stderr
 (w/f'{side}-main.asm').write_text(p.stdout);row['native_command']=native;row['native_binary_sha256']=hashlib.sha256(b.read_bytes()).hexdigest();row['native_calls']={name:p.stdout.count('<'+name+'>') for name in row['calls']}
 out.append(row)
(w/'emission.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
a,b=out;assert not a['entry34'] and b['entry34'];assert not a['fast34'] and not b['fast34'];assert a['body_unique']==1 and b['body_unique']==0;assert a['calls']==b['calls'];assert a['key_markers']==b['key_markers']==2;assert a['tail_markers']==b['tail_markers']==1

assert a["native_calls"] == b["native_calls"]
