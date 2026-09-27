"""Production lifecycle controls for the isolated native-retain specialization."""
import importlib.util,subprocess
from pathlib import Path
root=Path.cwd();spec=importlib.util.spec_from_file_location('native_memory',root/'scripts/test_native_memory.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
work=root/'.tmp-mut-argument/flat-retain-lifecycle';work.mkdir(exist_ok=True)
for name,sources in module.SUITES:
 if name not in ('native_rc_contract','native_rc_collections','native_rc_arena','native_rc_hold','native_rc_execution','native_rc_stats','native_rc_codecs','native_rc_host'):continue
 module.run_suite(root,['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-ffunction-sections','-fdata-sections','-Wl,--gc-sections'],work,name,list(sources))
