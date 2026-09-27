import importlib.util, os, subprocess
from pathlib import Path
root=Path.cwd()
spec=importlib.util.spec_from_file_location('native_memory',root/'scripts/test_native_memory.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
directory=root/'.tmp-flat/suites'
directory.mkdir(exist_ok=True)
flags=['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-ffunction-sections','-fdata-sections','-Wl,--gc-sections']
for name,sources in module.SUITES:
    if name in ('native_rc_contract','native_rc_collections','native_rc_hold','native_rc_arena','native_rc_stats','native_rc_execution'):
        module.run_suite(root,flags,directory,name,list(sources))
