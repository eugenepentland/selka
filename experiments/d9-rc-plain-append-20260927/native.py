from pathlib import Path
import importlib.util,os
r=Path.cwd();s=importlib.util.spec_from_file_location('memory',r/'scripts/test_native_memory.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
w=r/'.tmp-rc/append-room/native';w.mkdir(exist_ok=True)
name,sources=next((a,b) for a,b in m.SUITES if a=='native_rc_collections')
m.run_suite(r,['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=undefined,address','-ffunction-sections','-fdata-sections','-Wl,--gc-sections'],w,name,list(sources))
