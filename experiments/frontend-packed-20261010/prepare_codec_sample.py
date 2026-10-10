import pathlib, struct, json, shutil, time
root=pathlib.Path('/home/epentland/ai/canopy/mylang-build-cache-size-20261009/32/cache/stages-v1')
out=pathlib.Path('/home/epentland/ai/canopy/mylang-frontend-packed-20261010')
block=[]; block_len=0; count=0; chosen=0; raw=0; sizes=[]; records=0; total_bytes=0
start=time.monotonic()
with (out/'codec-sample.bin').open('wb') as target:
 def flush():
  global block,block_len,count,chosen,raw
  if not block:return
  if count%16==7:
   target.write(struct.pack('<Q',block_len))
   for p,n in block:
    target.write(struct.pack('<Q',n))
    with p.open('rb') as source:shutil.copyfileobj(source,target,1024*1024)
   chosen+=1;raw+=block_len;sizes.append(block_len)
  count+=1;block=[];block_len=0
 for p in sorted(root.glob('*.stage')):
  n=p.stat().st_size
  if block and block_len+8+n>256*1024:flush()
  block.append((p,n));block_len+=8+n;records+=1;total_bytes+=8+n
 flush()
meta={'source':str(root),'records':records,'whole_blocks':count,'whole_raw_bytes':total_bytes,'selected_blocks':chosen,'sample_raw_bytes':raw,'sample_block_sizes':sizes,'elapsed_seconds':time.monotonic()-start,'selection':'Every 16th key-sorted ~256KiB block (offset7), oversized record occupies independent block; original stage records including headers and u64 lengths preserved.'}
(out/'codec-sample.json').write_text(json.dumps(meta,indent=2)+'\n')
print({k:v for k,v in meta.items() if k!='sample_block_sizes'})
