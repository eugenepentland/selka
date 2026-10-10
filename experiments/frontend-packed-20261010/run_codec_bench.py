import subprocess,json,pathlib,statistics,sys
root=pathlib.Path('/home/epentland/ai/canopy/mylang-frontend-packed-20261010')
basename=sys.argv[1] if len(sys.argv)>1 else "sample"
prefix="codec" if basename=="sample" else "codec-"+basename
samples=[]
for run in range(3):
 r=subprocess.run(['taskset','-c','0',str(root/'codec_bench'),str(root/f"codec-{basename}.bin")],capture_output=True,text=True,check=True)
 sample=json.loads(r.stdout);samples.append(sample)
 (root/f"{prefix}-result-{run+1}.json").write_text(json.dumps(sample,indent=2)+'\n')
 print('run',run+1,sample,flush=True)
med={k:statistics.median(s[k] for s in samples) for k in samples[0]}
report={'method':'Pinned Zig std.compress.flate.Compress.Options.fastest (level_1), raw DEFLATE; system upstream libzstd 1.5.7 level1. ReleaseFast harness on CPU0. Deterministic every16th independent key-sorted ~256KiB real stage block, original framing retained; oversized records remain separate blocks. Three runs. All frames checked byte-for-byte on sequential decode. Random2000 block reads use identical PRNG stream, with reused max-sized output or allocator-owned fresh output; no file I/O in codec timing. Sequential time includes byte comparison. zstd compressor timing excludes output allocation; deflate compressor includes Writer allocation, so compressor comparison is approximate.', 'corpus':json.loads((root/f"codec-{basename}.json").read_text()),'samples':samples,'median':med}
for codec in ['deflate','zstd']:
 med[codec+'_ratio']=med[codec+'_bytes']/med['raw_bytes']
 med[codec+'_random_us_per_block']=med[codec+'_random_ns']/2000/1000
 med[codec+'_alloc_random_us_per_block']=med[codec+'_alloc_random_ns']/2000/1000
 med[codec+'_random_MiB_per_s']=med['random_raw_bytes']/(1024**2)/(med[codec+'_random_ns']/1e9)
(root/f"{prefix}-comparison.json").write_text(json.dumps(report,indent=2)+'\n')
print('median',med,flush=True)
