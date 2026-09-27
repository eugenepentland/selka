from pathlib import Path
import hashlib,json,os,stat,statistics,struct,subprocess,time
root=Path.cwd();work=root/'.tmp-mut-argument/scalar-readiness-audit';controls=root/'.tmp-mut-argument/type-facts/controls';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();results={'kind':'UNSOUND FOR GENERAL USE: constant-ready private QBE diagnostic, not a production candidate','base_commit':'c71d4046','cpu':3,'patches':[],'runs':[],'medians':{}}
env={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'};env['TMPDIR']=str(work)
def save():(work/'results.json').write_text(json.dumps(results,indent=2)+'\n')
def patch(source,target):
 data=bytearray(source.read_bytes());assert data[:6]==b'\x7fELF\x02\x01';address=int(next(line.split()[0] for line in subprocess.check_output(['nm','-n',str(source)],text=True).splitlines() if line.endswith(' T myl_rc_list_plain_ready')),16);phoff=struct.unpack_from('<Q',data,32)[0];entsize,count=struct.unpack_from('<HH',data,54);offset=None
 for i in range(count):
  kind,flags,fileoff,vaddr,paddr,filesz,memsz,alignment=struct.unpack_from('<IIQQQQQQ',data,phoff+i*entsize)
  if kind==1 and vaddr<=address< vaddr+filesz:offset=fileoff+address-vaddr;assert flags&1;break
 assert offset is not None
 original=bytes(data[offset:offset+6]);data[offset:offset+6]=b'\xb8\x01\x00\x00\x00\xc3';target.write_bytes(data);target.chmod(source.stat().st_mode)
 results['patches'].append({'source':str(source),'source_sha256':sha(source),'diagnostic':str(target),'diagnostic_sha256':sha(target),'symbol':'myl_rc_list_plain_ready','address':address,'file_offset':offset,'before_hex':original.hex(),'after_hex':'b801000000c3'});save()
for key,path in [('parity-micro-list_append_sum','bench/parity/micro/list_append_sum.expected'),('parity-suite-sieve','bench/parity/suite/sieve.expected')]:
 expected=(root/path).read_text()
 for mode in ['production','stats']:patch(controls/(key+'-after-qbe-'+mode),work/(key+'-constant-ready-'+mode))
 for repeat in range(3):
  for side in (['before','diagnostic'] if repeat%2==0 else ['diagnostic','before']):
   binary=controls/(key+'-after-qbe-production') if side=='before' else work/(key+'-constant-ready-production');cmd=['taskset','-c','3','perf','stat','-x,','-e','cpu_core/instructions/u','--',str(binary)];p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=120);assert p.returncode==0 and p.stdout==expected;fields=next(x.split(',') for x in p.stderr.splitlines() if ',cpu_core/instructions/u,' in x);assert float(fields[4])==100;results['runs'].append({'workload':key,'side':side,'repeat':repeat,'command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'instructions':int(fields[0]),'binary_sha256':sha(binary)});save()
 for side in ['before','diagnostic']:
  binary=controls/(key+'-after-qbe-stats') if side=='before' else work/(key+'-constant-ready-stats');cmd=['taskset','-c','3',str(binary)];p=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=120);assert p.returncode==0 and p.stdout==expected;counts=json.loads(next(x.split(' ',1)[1] for x in p.stderr.splitlines() if x.startswith('MYLANG_RC_COUNTS ')));results['runs'].append({'workload':key,'side':side,'counted':True,'command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'counts':counts,'binary_sha256':sha(binary)});save()
 med={side:statistics.median(x['instructions'] for x in results['runs'] if x['workload']==key and x['side']==side and 'instructions' in x) for side in ['before','diagnostic']};med['diagnostic_over_before']=med['diagnostic']/med['before'];results['medians'][key]=med;rows=[x['counts'] for x in results['runs'] if x['workload']==key and x.get('counted')];assert rows[0]==rows[1];save();print(key,med,flush=True)
