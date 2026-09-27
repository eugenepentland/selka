"""Run the new protocol controls against unchanged pre-optimization retain."""
import ast,hashlib,importlib.util,inspect,json,subprocess
from pathlib import Path
root=Path.cwd();spec=importlib.util.spec_from_file_location('native_memory',root/'scripts/test_native_memory.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
work=root/'.tmp-mut-argument/retain-legacy';work.mkdir(exist_ok=True)
original=subprocess.run(['git','show','8c399ac010c8df7eaf5b2a9cd999e4e625706097:src/native_rc_values.c'],capture_output=True,check=True)
(work/'native_rc_values.c').write_bytes(original.stdout)
for name,sources in module.SUITES:
 if name=='native_rc_collections':
  # Resolve the helper's implicit runtime closure before substituting. Absolute
  # source paths then prevent its basename-triggered closure from adding the
  # current native_rc_values.c back into the legacy compilation.
  definition=ast.parse(inspect.getsource(module.run_suite))
  required=next(ast.literal_eval(node.value) for node in ast.walk(definition) if isinstance(node,ast.Assign) and any(isinstance(target,ast.Name) and target.id=='required' for target in node.targets))
  sources=list(sources)+[p for p in required if p not in sources]
  sources=[str(work/'native_rc_values.c') if p=='native_rc_values.c' else str(root/'src'/p) for p in sources]
  assert str(root/'src/native_rc_values.c') not in sources
  (work/'source-identity.json').write_text(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sources},indent=2)+'\n')
  module.run_suite(root,['cc','-std=c11','-Wall','-Wextra','-Werror','-fsanitize=address,undefined','-ffunction-sections','-fdata-sections','-Wl,--gc-sections'],work,name,sources)
