import hashlib,json,pathlib,subprocess
import argparse
root=pathlib.Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument("--compiler",type=pathlib.Path,required=True);parser.add_argument("--output",type=pathlib.Path,required=True)
args=parser.parse_args();compiler=args.compiler.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
files=['rc_owned_values','rc_call_lifetimes','rc_collection_builtins','rc_aggregate_values','rc_borrowed_results','rc_readonly_values','rc_mut_uniqueness','rc_read_loans','rc_nested_read_loans','rc_receiver_loops','rc_live_views','rc_contract_results','pending_receivers','rc_semantic_history','rc_box_writeback','rc_dictionary_views','rc_view_receivers','rc_arena_values','rc_readonly_body','rc_inert_receivers','collection_read_callbacks','option_niche','option_narrowing','rc_semantic_publication','mut_argument_places','mut_dictionary_arguments','native_file_cleanup']
files=[f for f in files if (root/'tests/lang'/f'{f}.my').exists()]
record={'compiler_sha':hashlib.sha256(compiler.read_bytes()).hexdigest(),'runs':[]}
for backend in ['qbe','llvm']:
 for name in files:
  cmd=[str(compiler),'test',str(root/'tests/lang'/f'{name}.my'),'--rc-runtime=stats','--force','--json','--jobs','2','--cache-dir',str(out/'cache')]
  if backend=='llvm':cmd+=['--release']
  p=subprocess.run(cmd,text=True,capture_output=True)
  row={'backend':backend,'name':name,'command':cmd,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr};record['runs'].append(row)
  (out/'results.json').write_text(json.dumps(record,indent=2)+'\n')
  try:
   parsed=json.loads(p.stdout);print(backend,name,parsed.get('passed'),parsed.get('failed'),flush=True)
  except Exception: print(backend,name,'status',p.returncode,flush=True)

assert all(row["status"]==0 and json.loads(row["stdout"])["failed"]==0 for row in record["runs"]), record
