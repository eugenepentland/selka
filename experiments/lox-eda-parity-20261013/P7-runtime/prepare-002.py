#!/usr/bin/env python3
"""Prepare separately attributable runtime sources from pinned C1 and worker files."""
import pathlib,re,subprocess,json,hashlib,shutil
root=pathlib.Path.cwd();out=root/'experiments/lox-eda-parity-20261013/P7-runtime';work=root/'.tmp/lox-eda-parity/P7-runtime';baseline='be33ce79b5b58c3e254e73709c9dd7eb97e5a849'
def sha(data):return hashlib.sha256(data).hexdigest()
driver=subprocess.check_output(['git','show',baseline+':src/core/driver.zig']).decode();section=driver.split('pub const runtime_source = ',1)[1].split(';',1)[0];files=re.findall(r'@embedFile\("([^"]+)"\)',section)
assert len(files)==14
base={p:subprocess.check_output(['git','show',baseline+':src/core/'+p]) for p in files}
current={p:(root/'src/core'/p).read_bytes() for p in files};changed=[p for p in files if base[p]!=current[p]];assert set(changed)=={'runtime/core_rt.c','runtime/core_owned_copy.c'}
scalar=(out/'sources/scalar-core_owned_copy.c').read_bytes()
bulk_tail=current['runtime/core_owned_copy.c'].split(b'    copy->len = source->len;\n',1)[1].split(b'    for (int64_t i = 0; i < count; ++i)',1)[0]
bulk=base['runtime/core_owned_copy.c'].replace(b'    copy->len = source->len;\n',b'    copy->len = source->len;\n'+bulk_tail,1)
assert b'block_data_size(count, child->size, false)' in bulk
rows={}

for name,selected in {'baseline':[], 'scalar':['runtime/core_owned_copy.c'], 'pointer':['runtime/core_rt.c'], 'combined':['runtime/core_owned_copy.c','runtime/core_rt.c'], 'bulk':['runtime/core_owned_copy.c'], 'all':changed}.items():
 folder=work/'002'/name;folder.mkdir(parents=True,exist_ok=True);source=b'\n'.join((scalar if name in ['scalar','combined'] and p=='runtime/core_owned_copy.c' else bulk if name=='bulk' and p=='runtime/core_owned_copy.c' else current[p]) if p in selected else base[p] for p in files);(folder/'runtime.c').write_bytes(source)
 instrumented=b'static unsigned long long probe_copy_pushes, probe_reference_reads, probe_block_allocs;\n'+source
 for anchor,addition in [(b'static myl_block *block_alloc(uint32_t kind, size_t data, size_t *room) {',b'\n    ++probe_block_allocs;'),(b'stack->items[stack->count++] = (core_copy_work){shape, source, target};',b'++probe_copy_pushes;\n    '),(b'static myl_block *reference_at(myl_layout *layout, const unsigned char *element, int32_t r) {',b'\n    ++probe_reference_reads;')]:
  assert instrumented.count(anchor)==1
  instrumented=instrumented.replace(anchor,(addition+anchor if b'stack->items' in anchor else anchor+addition),1)
 (folder/'probe-runtime.c').write_bytes(instrumented);shutil.copyfile(out/'probe.c',folder/'probe.c')
 rows[name]={'runtime_sha256':sha(source),'probe_runtime_sha256':sha(instrumented),'selected':selected,'source_inputs':{p:sha((scalar if name in ['scalar','combined'] and p=='runtime/core_owned_copy.c' else bulk if name=='bulk' and p=='runtime/core_owned_copy.c' else current[p]) if p in selected else base[p]) for p in files}}
(out/'runtime-variants-002.json').write_text(json.dumps({'baseline_commit':baseline,'runtime_file_order':files,'variants':rows,'probe_sha256':sha((out/'probe.c').read_bytes())},indent=2)+'\n')
old=json.loads((out/'runtime-variants.json').read_text())
for name in ['baseline','scalar','pointer','combined']:assert rows[name]['runtime_sha256']==old['variants'][name]['runtime_sha256']
(out/'sources/bulk-core_owned_copy.c').write_bytes(bulk)
print('prepared six variants; first four runtime sources unchanged')
