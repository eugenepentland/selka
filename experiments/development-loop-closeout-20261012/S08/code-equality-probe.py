import argparse, hashlib, importlib, importlib.machinery, json, marshal, sys
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('root');parser.add_argument('--guarded',action='store_true');a=parser.parse_args()
def support(code,version):
 try:return {'supported':True,'sha256':hashlib.sha256(marshal.dumps(code,version)).hexdigest()}
 except ValueError as error:return {'supported':False,'error':str(error)}
root=Path(a.root);sys.path.insert(0,str(root/'scripts')); loaded={}
class Loader(importlib.machinery.SourceFileLoader):
    def get_code(self, fullname):
        code=(self.source_to_code(self.get_data(self.path),self.path) if a.guarded else super().get_code(fullname))
        loaded[fullname]=code
        return code
class Finder:
    def find_spec(self,fullname,path=None,target=None):
        spec=importlib.machinery.PathFinder.find_spec(fullname,path,target)
        if spec and isinstance(spec.loader,importlib.machinery.SourceFileLoader):spec.loader=Loader(fullname,spec.loader.path)
        return spec
sys.meta_path.insert(0,Finder());m=importlib.import_module('verify_cache');out={}
for name in ('verify_cache','verification_snapshot','fuzz_campaign_store','verification_process'):
    module=sys.modules[name];code=loaded[name];fresh=compile(Path(module.__file__).read_bytes(),code.co_filename,'exec',dont_inherit=True,optimize=sys.flags.optimize)
    out[name]={'loaded_hash':module.LOADED_CODE_SHA256,'filename':code.co_filename,'equal_fresh':code==fresh,'marshal_version_compatibility':{str(v):support(code,v) for v in range(marshal.version+1)},'post_hashes':{str(v):hashlib.sha256(marshal.dumps(code,v)).hexdigest() for v in [marshal.version]},'fresh_hashes':{str(v):hashlib.sha256(marshal.dumps(fresh,v)).hexdigest() for v in [marshal.version]}}
print(json.dumps(out,indent=2,sort_keys=True))
