import ast,hashlib,importlib.util,inspect,json,subprocess,sys
from pathlib import Path
root=Path.cwd();spec=importlib.util.spec_from_file_location('native_memory',root/'scripts/test_native_memory.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
legacy='--legacy' in sys.argv
work=root/'.tmp-mut-argument/descriptor-repeat'/('legacy' if legacy else 'suites');work.mkdir(exist_ok=True)
originals={}
if legacy:
 for name in ('native_rc_shapes.c',):
  path=work/name;path.write_bytes(subprocess.run(['git','show',f'd1d8b3c4:src/{name}'],capture_output=True,check=True).stdout);originals[name]=path
required=next(ast.literal_eval(node.value) for node in ast.walk(ast.parse(inspect.getsource(module.run_suite))) if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='required' for t in node.targets))
for name,sources in module.SUITES:
 if name not in (('native_rc_collections',) if '--collections-only' in sys.argv else ('native_rc_contract','native_rc_history','native_rc_loan','native_rc_collections','native_rc_arena','native_rc_hold')):continue
 sources=list(sources)+[p for p in required if p not in sources]
 sources=[str(originals.get(p,root/'src'/p)) for p in sources]
 (work/(name+'-source-identity.json')).write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources},indent=2)+'\n')
 module.run_suite(root,['cc','-std=c11','-Wall','-Wextra','-Werror','-DMYL_NATIVE_RC_COUNTING=1','-fsanitize=address,undefined','-ffunction-sections','-fdata-sections','-Wl,--gc-sections'],work,name,sources)
