import importlib.util
from pathlib import Path
root=Path.cwd();spec=importlib.util.spec_from_file_location('native_memory',root/'scripts/test_native_memory.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
work=root/'.tmp-mut-argument/retain-semantics';work.mkdir(exist_ok=True)
for name,sources in module.SUITES:
 if name in ('native_rc_loan','native_rc_history'):
  module.run_suite(root,['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-ffunction-sections','-fdata-sections','-Wl,--gc-sections'],work,name,list(sources))
