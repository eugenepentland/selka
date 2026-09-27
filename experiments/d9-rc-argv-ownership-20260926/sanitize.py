from pathlib import Path
import importlib.util
spec=importlib.util.spec_from_file_location('native','scripts/test_native_memory.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.run_suite(Path.cwd(),['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-fno-omit-frame-pointer','-ffunction-sections','-fdata-sections','-Wl,--gc-sections'],Path('.tmp-argv').resolve(),'native_argv',['native_heap.c','qbe_runtime.c','qbe_runtime_rc.c','qbe_stack.c'])
