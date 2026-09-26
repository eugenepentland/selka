import importlib.util,os
from pathlib import Path
r=Path.cwd();spec=importlib.util.spec_from_file_location('memory',r/'scripts/test_native_memory.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
flags=['cc','-std=c11','-Wall','-Wextra','-Werror','-g','-fsanitize=address,undefined','-DMYL_NATIVE_RC=1','-ffunction-sections','-fdata-sections','-Wl,--gc-sections']
m.run_suite(r,flags,r/'.tmp-box','qbe_runtime_rc',['native_heap.c','qbe_runtime_rc.c'])
