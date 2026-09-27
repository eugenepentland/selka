from pathlib import Path
import subprocess,re,json,hashlib
r=Path.cwd();w=r/'.tmp-bytes';ssa=(w/'after-main.ssa').read_text();block=ssa.split(' # RC-READ-BYTES-VERSION-1 head 118\n')[1].split('\n %v503')[0];assert 'store' not in block
m=re.search(r'add %rcguards, (\d+)',block);offset=int(m[1]);guard=block.replace('@oi118','@fallback')
source='export function w $byte_guard(l %rcguards) {\n@start\n'+guard+'\n ret 1\n@fallback\n ret 0\n}\n';(w/'guard-probe.ssa').write_text(source)
(w/'guard-probe.c').write_text('''#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int byte_guard(void*);
int main(void) { uint64_t guards[16]={0}; uint32_t inputs[]={0,1,8,16,65536,0x80000000u,0xffffffffu};
 for(unsigned i=0;i<sizeof(inputs)/sizeof(inputs[0]);i++){guards[OFFSET/8]=inputs[i]; int result=byte_guard(guards); assert(result==(inputs[i]==0));assert(guards[OFFSET/8]==inputs[i]);printf("%u %d %llu\\n",inputs[i],result,(unsigned long long)guards[OFFSET/8]);}return 0;}
'''.replace('OFFSET',str(offset)))
cmds=[[str(w/'install-after/bin/qbe'),'-o',str(w/'guard-probe.s'),str(w/'guard-probe.ssa')],['cc','-O2','-o',str(w/'guard-probe'),str(w/'guard-probe.s'),str(w/'guard-probe.c')],[str(w/'guard-probe')]];rows=[]
for cmd in cmds:
 p=subprocess.run(cmd,capture_output=True,text=True);rows.append(dict(command=cmd,exit=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==0,rows
(w/'guard-probe.json').write_text(json.dumps(dict(extracted_from_sha256=hashlib.sha256(ssa.encode()).hexdigest(),offset=offset,runs=rows),indent=2)+'\n');print(rows[-1]['stdout'])
