import importlib.util,subprocess,json
from pathlib import Path
r=Path.cwd();w=r/'.tmp-box';spec=importlib.util.spec_from_file_location('memory',r/'scripts/test_native_memory.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
s=(r/'src/qbe_runtime_rc.c').read_text();s=s.replace('myl_rc_value_retain_many(&ctx->heap, &destination, &source, 1)','myl_rc_value_copy(&ctx->heap, &destination, &source)');(w/'qbe_runtime_rc_before_retain.c').write_text(s)
flags=['cc','-std=c11','-Wall','-Wextra','-Werror','-g','-fsanitize=address,undefined','-DMYL_NATIVE_RC=1','-ffunction-sections','-fdata-sections','-Wl,--gc-sections']
try:m.run_suite(r,flags,w,'qbe_runtime_rc',['native_heap.c','../.tmp-box/qbe_runtime_rc_before_retain.c'])
except subprocess.CalledProcessError as e:
 assert e.returncode==-6, e
 (w/'negative-retain.json').write_text(json.dumps({'expected_abort':True,'exit':e.returncode,'source':s},indent=2)+'\n')
 print('Expected assertion failure with old pin-aware body copy',flush=True)
else:raise AssertionError('old helper unexpectedly preserved pinned child identity')
