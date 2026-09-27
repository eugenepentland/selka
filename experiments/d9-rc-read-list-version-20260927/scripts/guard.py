from pathlib import Path
import ctypes,hashlib,json,re,subprocess
w=Path('.tmp-mut-argument/read-version');p=w/'rc_read_list_versions-after-emitted.json';f=next(f for f in json.loads(p.read_text())['functions'] if f['name']=='fold');il=f['il'];start=il.index(' # RC-READ-LIST-VERSION-1');end=il.index('\n@rcreadloop',start);guard=il[start:end];yes,no=re.search(r'jnz %v\d+, @(rcreadloop\d+), @(oi\d+)',guard).groups()
source='export function w $guard(l %rcguards, l %rcentries) {\n@start\n'+guard+'\n@'+yes+'\n ret 1\n@'+no+'\n ret 0\n}\n';(w/'guard.ssa').write_text(source)
cmd=[str(w/'install/bin/qbe'),'-o',str(w/'guard.s'),str(w/'guard.ssa')];subprocess.run(cmd,check=True)
link=['cc','-shared','-fPIC',str(w/'guard.s'),'-o',str(w/'guard.so')];subprocess.run(link,check=True)
lib=ctypes.CDLL(str(w.resolve()/'guard.so'));fn=lib.guard;fn.argtypes=[ctypes.c_void_p,ctypes.c_void_p];fn.restype=ctypes.c_int
live_offset=int(re.search(r'add %rcguards, (\d+)',guard).group(1));role_offset=int(re.search(r'add %rcentries, (\d+)',guard).group(1));rows=[]
for live in (0,1):
 for role in (0,1,2,3,4,8,10,16,18,31,0xffffffff):
  guards=ctypes.create_string_buffer(live_offset+4);entries=ctypes.create_string_buffer(role_offset+4)
  ctypes.c_uint32.from_buffer(guards,live_offset).value=live;ctypes.c_uint32.from_buffer(entries,role_offset).value=role
  got=fn(guards,entries);assert got==int(live==1 and role in (2,8)),(live,role,got);rows.append({'live':live,'role':role,'fast':got})
sha=lambda path:hashlib.sha256(Path(path).read_bytes()).hexdigest()
(w/'guard.json').write_text(json.dumps({'emission_sha256':sha(p),'source_sha256':sha(w/'guard.ssa'),'library_sha256':sha(w/'guard.so'),'qbe_command':cmd,'link_command':link,'rows':rows},indent=2)+'\n')
print('22 actual emitted guard executions; clear, LOAN16, mixed/unique/construction roles refuse')
