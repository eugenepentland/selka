import importlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);mode=sys.argv[2];sys.path.insert(0,str(root/'scripts'))
if mode=='retained':
 import cache_session
 sys.meta_path.insert(0,cache_session._GuardedFinder())
import verify_cache,verification_snapshot,fuzz_campaign_store,verification_process
modules=[verify_cache,verification_snapshot,fuzz_campaign_store,verification_process]
first=[m.LOADED_CODE_SHA256 for m in modules]
verify_cache.parse_options([])
again=importlib.import_module('verify_cache')
second=[m.LOADED_CODE_SHA256 for m in modules]
print(json.dumps({'mode':mode,'hashes':first,'same_process_repeat_stable':first==second,'same_module_object':again is verify_cache,'snapshot_filename':verification_snapshot._LOADED_CODE_OBJECT.co_filename},indent=2))
